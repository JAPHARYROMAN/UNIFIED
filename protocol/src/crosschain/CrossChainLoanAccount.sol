// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IUFTBridgeHub } from "../interfaces/IUFTBridgeHub.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";

interface ICrossChainLoanRouter {
    function authorizeDisbursement(bytes32 loanId) external returns (bytes32 messageId);

    function authorizeCollateralRelease(bytes32 loanId) external returns (bytes32 messageId);
}

/// @notice Home-authoritative principal-only cross-chain loan.
contract CrossChainLoanAccount is ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant REPAYMENT_OPERATION_DOMAIN =
        keccak256("UNIFIED_REPAYMENT_OPERATION_V1");

    error InvalidLoan();
    error InvalidLoanState(CrossChainTypes.CrossChainLoanState state);
    error UnauthorizedLoanCaller(address caller);
    error DuplicateLoanOperation(bytes32 operationId);
    error AmountExceedsPrincipal(uint256 amount, uint256 outstanding);
    error LoanBalanceMismatch();

    CrossChainTypes.CrossChainLoanTerms private _terms;
    CrossChainTypes.CrossChainLoanState public state;
    address public immutable factory;
    ILoanRegistry public immutable loanRegistry;
    IUFTBridgeHub public immutable bridgeHub;
    IERC20 public immutable canonicalUFT;
    address public immutable wrappedUFT;
    bytes32 public immutable policyConfigurationHash;
    uint256 public outstandingPrincipal;
    uint64 public stateNonce;
    bytes32 public mintMessageId;
    bytes32 public disbursementMessageId;
    bytes32 public collateralReleaseMessageId;
    bytes32 public cancellationId;
    bytes32 public cancellationMessageId;
    bytes32 public cancellationDisbursementTombstoneHash;
    bool public mintConfirmed;
    bool public collateralConfirmed;
    bool public collateralReleased;
    bool public fundingRefunded;
    mapping(bytes32 operationId => bool processed) public processedOperations;

    event CrossChainLoanInitialized(
        bytes32 indexed loanId,
        address indexed borrower,
        address indexed lender,
        uint256 principalAmount,
        bytes32 policyHash
    );
    event CrossChainLoanActivated(bytes32 indexed loanId, bytes32 indexed operationId);
    event CrossChainRepaymentFinalized(
        bytes32 indexed loanId, bytes32 indexed paymentId, uint256 amount, bool remote
    );
    event CrossChainLoanStateChanged(
        bytes32 indexed loanId,
        CrossChainTypes.CrossChainLoanState priorState,
        CrossChainTypes.CrossChainLoanState newState,
        uint64 stateNonce
    );
    event CrossChainLoanClosed(bytes32 indexed loanId, bytes32 indexed releaseOperationId);
    event CrossChainLoanCancellationRequested(
        bytes32 indexed loanId,
        bytes32 indexed cancellationId,
        bytes32 indexed cancellationMessageId
    );
    event CrossChainLoanCancellationCompleted(
        bytes32 indexed loanId, bytes32 indexed cancellationId, bytes32 escrowBurnResultHash
    );

    modifier onlyFactory() {
        if (msg.sender != factory) revert UnauthorizedLoanCaller(msg.sender);
        _;
    }

    constructor(
        CrossChainTypes.CrossChainLoanTerms memory terms_,
        address factory_,
        ILoanRegistry loanRegistry_,
        IUFTBridgeHub bridgeHub_,
        IERC20 canonicalUFT_,
        address wrappedUFT_,
        bytes32 policyConfigurationHash_
    ) {
        if (
            terms_.loanId == bytes32(0) || terms_.agreementHash == bytes32(0)
                || terms_.fundingLockId == bytes32(0) || terms_.collateralId == bytes32(0)
                || terms_.borrower == address(0) || terms_.lender == address(0)
                || terms_.borrower == terms_.lender || terms_.principalAmount == 0
                || terms_.collateralAmount == 0 || terms_.policyHash == bytes32(0)
                || factory_.code.length == 0 || address(loanRegistry_) == address(0)
                || address(bridgeHub_) == address(0) || address(canonicalUFT_).code.length == 0
                || wrappedUFT_ == address(0) || policyConfigurationHash_ == bytes32(0)
        ) {
            revert InvalidLoan();
        }
        _terms = terms_;
        factory = factory_;
        loanRegistry = loanRegistry_;
        bridgeHub = bridgeHub_;
        canonicalUFT = canonicalUFT_;
        wrappedUFT = wrappedUFT_;
        policyConfigurationHash = policyConfigurationHash_;
        state = CrossChainTypes.CrossChainLoanState.ACTIVATING;
        stateNonce = 1;
        emit CrossChainLoanInitialized(
            terms_.loanId, terms_.borrower, terms_.lender, terms_.principalAmount, terms_.policyHash
        );
    }

    function bindOrigination(bytes32 mintMessageId_) external onlyFactory {
        if (mintMessageId != bytes32(0) || mintMessageId_ == bytes32(0)) {
            revert InvalidLoan();
        }
        mintMessageId = mintMessageId_;
    }

    function recordMintConfirmed(bytes32 operationId, uint256 amount, bytes32 policyHash)
        external
        onlyFactory
    {
        _requireActivatingOperation(operationId, amount, policyHash);
        mintConfirmed = true;
        _maybeAuthorizeDisbursement();
    }

    function recordCollateralLocked(bytes32 operationId, uint256 amount, bytes32 policyHash)
        external
        onlyFactory
    {
        if (
            (state != CrossChainTypes.CrossChainLoanState.ACTIVATING
                    && state != CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING)
                || operationId != _terms.collateralId || amount != _terms.collateralAmount
                || policyHash != _terms.policyHash || collateralConfirmed
        ) {
            revert InvalidLoan();
        }
        collateralConfirmed = true;
        processedOperations[
            _operationKey(CrossChainTypes.ACTION_SATELLITE_COLLATERAL_LOCKED, operationId)
        ] = true;
        if (state == CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING) {
            if (fundingRefunded) {
                _enterCancellationClosing();
            } else {
                _advanceState();
            }
            return;
        }
        _advanceState();
        _maybeAuthorizeDisbursement();
    }

    function recordDisbursement(bytes32 operationId, uint256 amount, bytes32 policyHash)
        external
        onlyFactory
    {
        bool resolvesCancellationRace =
            state == CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING
                && cancellationId != bytes32(0) && cancellationMessageId != bytes32(0)
                && disbursementMessageId != bytes32(0) && !fundingRefunded;
        if (
            (state != CrossChainTypes.CrossChainLoanState.ACTIVATING && !resolvesCancellationRace)
                || !mintConfirmed || !collateralConfirmed || operationId != _terms.fundingLockId
                || processedOperations[
                    _operationKey(
                        CrossChainTypes.ACTION_SATELLITE_DISBURSEMENT_SETTLED, operationId
                    )
                ] || amount != _terms.principalAmount || policyHash != _terms.policyHash
        ) {
            revert InvalidLoan();
        }
        processedOperations[
            _operationKey(CrossChainTypes.ACTION_SATELLITE_DISBURSEMENT_SETTLED, operationId)
        ] = true;
        outstandingPrincipal = _terms.principalAmount;
        CrossChainTypes.CrossChainLoanState prior = state;
        state = CrossChainTypes.CrossChainLoanState.ACTIVE;
        _advanceState();
        emit CrossChainLoanActivated(_terms.loanId, operationId);
        emit CrossChainLoanStateChanged(_terms.loanId, prior, state, stateNonce);
    }

    function requestCancellation(
        bytes32 cancellationId_,
        bytes32 cancellationMessageId_,
        bytes32 disbursementTombstoneHash_
    ) external onlyFactory {
        if (
            state != CrossChainTypes.CrossChainLoanState.ACTIVATING || !mintConfirmed
                || outstandingPrincipal != 0 || cancellationId_ == bytes32(0)
                || cancellationMessageId_ == bytes32(0) || cancellationId != bytes32(0)
        ) {
            revert InvalidLoan();
        }
        cancellationId = cancellationId_;
        cancellationMessageId = cancellationMessageId_;
        cancellationDisbursementTombstoneHash = disbursementTombstoneHash_;
        CrossChainTypes.CrossChainLoanState prior = state;
        state = CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING;
        _advanceState();
        emit CrossChainLoanCancellationRequested(
            _terms.loanId, cancellationId_, cancellationMessageId_
        );
        emit CrossChainLoanStateChanged(_terms.loanId, prior, state, stateNonce);
    }

    function recordCancellationCompensated(
        CrossChainTypes.SatelliteFundingCancelledPayload calldata cancellation
    ) external onlyFactory nonReentrant {
        bytes32 operationKey = _operationKey(
            CrossChainTypes.ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED,
            cancellation.cancellationId
        );
        if (
            state != CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING
                || cancellation.cancellationId != cancellationId
                || cancellation.fundingLockId != _terms.fundingLockId
                || cancellation.disbursementMessageId != disbursementMessageId
                || cancellation.disbursementTombstoneHash != cancellationDisbursementTombstoneHash
                || cancellation.homeLoanAccount != address(this)
                || cancellation.lender != _terms.lender || cancellation.wrappedToken != wrappedUFT
                || cancellation.amount != _terms.principalAmount
                || cancellation.policyHash != _terms.policyHash
                || cancellation.escrowBurnResultHash == bytes32(0) || fundingRefunded
                || outstandingPrincipal != 0 || processedOperations[operationKey]
        ) {
            revert InvalidLoan();
        }
        processedOperations[operationKey] = true;
        bridgeHub.refundCancelledLoan(
            _terms.loanId, cancellation.cancellationId, _terms.lender, cancellation.amount
        );
        fundingRefunded = true;
        emit CrossChainLoanCancellationCompleted(
            _terms.loanId, cancellation.cancellationId, cancellation.escrowBurnResultHash
        );
        if (collateralConfirmed) {
            _enterCancellationClosing();
        } else {
            _advanceState();
        }
    }

    function recordRemoteRepayment(CrossChainTypes.SatelliteRepaymentBurnedPayload calldata burn)
        external
        onlyFactory
        nonReentrant
    {
        if (
            state != CrossChainTypes.CrossChainLoanState.ACTIVE || burn.loanId != _terms.loanId
                || burn.paymentId == bytes32(0) || burn.burnId == bytes32(0)
                || burn.lender != _terms.lender || burn.wrappedToken != wrappedUFT
                || burn.amount == 0 || processedOperations[_repaymentOperationKey(burn.paymentId)]
        ) {
            revert InvalidLoan();
        }
        if (burn.amount > outstandingPrincipal) {
            revert AmountExceedsPrincipal(burn.amount, outstandingPrincipal);
        }
        processedOperations[_repaymentOperationKey(burn.paymentId)] = true;
        bridgeHub.releaseLoanBacking(_terms.loanId, burn.burnId, _terms.lender, burn.amount);
        outstandingPrincipal -= burn.amount;
        _advanceState();
        emit CrossChainRepaymentFinalized(_terms.loanId, burn.paymentId, burn.amount, true);
        if (outstandingPrincipal == 0) _enterClosing();
    }

    function directHomeRepayment(bytes32 paymentId, uint256 amount) external nonReentrant {
        if (
            state != CrossChainTypes.CrossChainLoanState.ACTIVE || paymentId == bytes32(0)
                || amount == 0 || processedOperations[_repaymentOperationKey(paymentId)]
        ) {
            revert InvalidLoan();
        }
        if (amount > outstandingPrincipal) {
            revert AmountExceedsPrincipal(amount, outstandingPrincipal);
        }
        processedOperations[_repaymentOperationKey(paymentId)] = true;
        uint256 payerBefore = canonicalUFT.balanceOf(msg.sender);
        uint256 lenderBefore = canonicalUFT.balanceOf(_terms.lender);
        canonicalUFT.safeTransferFrom(msg.sender, _terms.lender, amount);
        if (
            payerBefore - canonicalUFT.balanceOf(msg.sender) != amount
                || canonicalUFT.balanceOf(_terms.lender) - lenderBefore != amount
        ) {
            revert LoanBalanceMismatch();
        }
        bridgeHub.reclassifyLoanBacking(_terms.loanId, amount);
        outstandingPrincipal -= amount;
        _advanceState();
        emit CrossChainRepaymentFinalized(_terms.loanId, paymentId, amount, false);
        if (outstandingPrincipal == 0) _enterClosing();
    }

    function recordCollateralReleased(bytes32 operationId, uint256 amount, bytes32 policyHash)
        external
        onlyFactory
    {
        if (
            state != CrossChainTypes.CrossChainLoanState.CLOSING
                || operationId != _terms.collateralId || collateralReleased
                || amount != _terms.collateralAmount || policyHash != _terms.policyHash
        ) {
            revert InvalidLoan();
        }
        collateralReleased = true;
        CrossChainTypes.CrossChainLoanState prior = state;
        state = CrossChainTypes.CrossChainLoanState.CLOSED;
        _advanceState();
        if (!loanRegistry.isTerminal(_terms.loanId)) {
            loanRegistry.markTerminal(_terms.loanId);
        }
        emit CrossChainLoanClosed(_terms.loanId, operationId);
        emit CrossChainLoanStateChanged(_terms.loanId, prior, state, stateNonce);
    }

    function onFundingCompensated(bytes32 lockId) external {
        if (
            msg.sender != address(bridgeHub) || lockId != _terms.fundingLockId
                || state != CrossChainTypes.CrossChainLoanState.ACTIVATING
        ) {
            revert UnauthorizedLoanCaller(msg.sender);
        }
        CrossChainTypes.CrossChainLoanState prior = state;
        fundingRefunded = true;
        if (collateralConfirmed) {
            state = CrossChainTypes.CrossChainLoanState.CLOSING;
            collateralReleaseMessageId =
                ICrossChainLoanRouter(factory).authorizeCollateralRelease(_terms.loanId);
        } else {
            state = CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING;
        }
        _advanceState();
        emit CrossChainLoanStateChanged(_terms.loanId, prior, state, stateNonce);
    }

    function terms() external view returns (CrossChainTypes.CrossChainLoanTerms memory) {
        return _terms;
    }

    function borrower() external view returns (address) {
        return _terms.borrower;
    }

    function lender() external view returns (address) {
        return _terms.lender;
    }

    function loanId() external view returns (bytes32) {
        return _terms.loanId;
    }

    function isRepaymentAllowed() external view returns (bool) {
        return state == CrossChainTypes.CrossChainLoanState.ACTIVE;
    }

    function repaymentOperationKey(bytes32 paymentId) external pure returns (bytes32) {
        return _repaymentOperationKey(paymentId);
    }

    function _requireActivatingOperation(bytes32 operationId, uint256 amount, bytes32 policyHash)
        private
    {
        if (
            state != CrossChainTypes.CrossChainLoanState.ACTIVATING
                || operationId != _terms.fundingLockId || amount != _terms.principalAmount
                || policyHash != _terms.policyHash || mintConfirmed
        ) {
            revert InvalidLoan();
        }
        processedOperations[
            _operationKey(CrossChainTypes.ACTION_SATELLITE_MINT_CONFIRMED, operationId)
        ] = true;
        _advanceState();
    }

    function _maybeAuthorizeDisbursement() private {
        if (
            state == CrossChainTypes.CrossChainLoanState.ACTIVATING && cancellationId == bytes32(0)
                && mintConfirmed && collateralConfirmed && disbursementMessageId == bytes32(0)
        ) {
            disbursementMessageId = ICrossChainLoanRouter(factory)
                .authorizeDisbursement(_terms.loanId);
        }
    }

    function _enterCancellationClosing() private {
        CrossChainTypes.CrossChainLoanState prior = state;
        state = CrossChainTypes.CrossChainLoanState.CLOSING;
        collateralReleaseMessageId =
            ICrossChainLoanRouter(factory).authorizeCollateralRelease(_terms.loanId);
        _advanceState();
        emit CrossChainLoanStateChanged(_terms.loanId, prior, state, stateNonce);
    }

    function _enterClosing() private {
        CrossChainTypes.CrossChainLoanState prior = state;
        state = CrossChainTypes.CrossChainLoanState.CLOSING;
        collateralReleaseMessageId =
            ICrossChainLoanRouter(factory).authorizeCollateralRelease(_terms.loanId);
        _advanceState();
        emit CrossChainLoanStateChanged(_terms.loanId, prior, state, stateNonce);
    }

    function _advanceState() private {
        ++stateNonce;
    }

    function _operationKey(CrossChainTypes.CrossChainActionType actionType, bytes32 operationId)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(actionType, operationId));
    }

    function _repaymentOperationKey(bytes32 paymentId) private pure returns (bytes32) {
        return keccak256(abi.encode(REPAYMENT_OPERATION_DOMAIN, paymentId));
    }
}
