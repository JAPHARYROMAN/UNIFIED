// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { LoanTypes } from "./LoanTypes.sol";

/// @notice Phase 3 principal-only same-chain loan account.
/// @dev Interest, collateral, default, and liquidation behavior are deliberately absent.
contract CoreLoanAccount is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error InvalidLoan();
    error InvalidState(LoanTypes.LoanLifecycle lifecycle);
    error UnauthorizedCaller(address caller);
    error DuplicatePayment(bytes32 paymentId);
    error AmountExceedsObligation(uint256 amount, uint256 remaining);
    error SettlementBalanceMismatch();

    LoanTypes.UniversalLoanTerms private _terms;
    LoanTypes.LoanStateVector private _state;
    address public lender;
    address public settlementToken;
    address public factory;
    ILoanRegistry public loanRegistry;
    uint256 public outstandingPrincipal;
    mapping(bytes32 paymentId => bool processed) public processedPayments;
    bool private _initialized;

    event LoanActivated(bytes32 indexed loanId, uint64 commencementTime, uint256 principalAmount);
    event LoanStateChanged(
        bytes32 indexed loanId, uint8 stateDomain, uint8 fromState, uint8 toState, uint64 stateNonce
    );
    event PaymentFinalized(bytes32 indexed paymentId, bytes32 indexed loanId, uint256 amount);
    event PaymentAllocated(
        bytes32 indexed paymentId,
        bytes32 indexed loanId,
        uint256 principal,
        uint256 interest,
        uint256 fees
    );
    event LoanClosed(bytes32 indexed loanId, bytes32 indexed journalRef);
    event JournalReferenceLinked(bytes32 indexed operationId, bytes32 indexed journalRef);

    modifier onlyFactory() {
        if (msg.sender != factory) revert UnauthorizedCaller(msg.sender);
        _;
    }

    function initialize(
        LoanTypes.UniversalLoanTerms calldata terms_,
        address lender_,
        address settlementToken_,
        ILoanRegistry loanRegistry_
    ) external {
        if (_initialized) revert AlreadyInitialized();
        if (
            terms_.loanId == bytes32(0) || terms_.agreementHash == bytes32(0)
                || terms_.parties.borrower == address(0) || lender_ == address(0)
                || lender_ == terms_.parties.borrower || settlementToken_.code.length == 0
                || address(loanRegistry_) == address(0) || terms_.principal.amount == 0
                || terms_.principal.assetId == bytes32(0) || terms_.commencementTime == 0
                || terms_.finalMaturityTime <= terms_.commencementTime
        ) {
            revert InvalidLoan();
        }
        _initialized = true;
        factory = msg.sender;
        _terms = terms_;
        lender = lender_;
        settlementToken = settlementToken_;
        loanRegistry = loanRegistry_;
        outstandingPrincipal = terms_.principal.amount;
        _state = LoanTypes.LoanStateVector({
            lifecycle: LoanTypes.LoanLifecycle.ACTIVATING,
            servicing: LoanTypes.ServicingState.NOT_STARTED,
            funding: LoanTypes.FundingState.FUNDED,
            latestPayment: LoanTypes.PaymentState.NONE,
            lastTransitionTime: uint64(block.timestamp),
            stateNonce: 1
        });
    }

    function activate(bytes32 journalRef) external onlyFactory {
        if (_state.lifecycle != LoanTypes.LoanLifecycle.ACTIVATING) {
            revert InvalidState(_state.lifecycle);
        }
        if (journalRef == bytes32(0)) revert InvalidLoan();
        LoanTypes.LoanLifecycle priorLifecycle = _state.lifecycle;
        LoanTypes.ServicingState priorServicing = _state.servicing;
        _state.lifecycle = LoanTypes.LoanLifecycle.ACTIVE;
        _state.servicing = LoanTypes.ServicingState.CURRENT;
        _advanceState();
        emit LoanStateChanged(
            _terms.loanId, 0, uint8(priorLifecycle), uint8(_state.lifecycle), _state.stateNonce
        );
        emit LoanStateChanged(
            _terms.loanId, 1, uint8(priorServicing), uint8(_state.servicing), _state.stateNonce
        );
        emit LoanActivated(_terms.loanId, _terms.commencementTime, _terms.principal.amount);
        emit JournalReferenceLinked(_terms.loanId, journalRef);
    }

    function repay(bytes32 paymentId, uint256 amount, bytes32 journalRef) external nonReentrant {
        if (_state.lifecycle != LoanTypes.LoanLifecycle.ACTIVE) {
            revert InvalidState(_state.lifecycle);
        }
        if (paymentId == bytes32(0) || journalRef == bytes32(0) || amount == 0) {
            revert InvalidLoan();
        }
        if (processedPayments[paymentId]) revert DuplicatePayment(paymentId);
        if (amount > outstandingPrincipal) {
            revert AmountExceedsObligation(amount, outstandingPrincipal);
        }

        LoanTypes.PaymentState priorPayment = _state.latestPayment;
        processedPayments[paymentId] = true;
        outstandingPrincipal -= amount;
        _state.latestPayment = LoanTypes.PaymentState.ALLOCATED;
        _advanceState();

        IERC20 token = IERC20(settlementToken);
        uint256 payerBefore = token.balanceOf(msg.sender);
        uint256 lenderBefore = token.balanceOf(lender);
        token.safeTransferFrom(msg.sender, lender, amount);
        if (
            payerBefore - token.balanceOf(msg.sender) != amount
                || token.balanceOf(lender) - lenderBefore != amount
        ) {
            revert SettlementBalanceMismatch();
        }

        emit PaymentFinalized(paymentId, _terms.loanId, amount);
        emit PaymentAllocated(paymentId, _terms.loanId, amount, 0, 0);
        emit LoanStateChanged(
            _terms.loanId,
            4,
            uint8(priorPayment),
            uint8(LoanTypes.PaymentState.ALLOCATED),
            _state.stateNonce
        );
        emit JournalReferenceLinked(paymentId, journalRef);

        if (outstandingPrincipal == 0) {
            _close(journalRef);
        }
    }

    function terms() external view returns (LoanTypes.UniversalLoanTerms memory) {
        return _terms;
    }

    function stateVector() external view returns (LoanTypes.LoanStateVector memory) {
        return _state;
    }

    function debtSnapshot(uint64 asOf) external view returns (LoanTypes.DebtSnapshot memory) {
        return LoanTypes.DebtSnapshot({
            outstandingPrincipal: outstandingPrincipal,
            accruedInterest: 0,
            capitalizedInterest: 0,
            accruedFees: 0,
            accruedPenalties: 0,
            recoverableCosts: 0,
            unappliedCredit: 0,
            asOf: asOf
        });
    }

    function borrower() external view returns (address) {
        return _terms.parties.borrower;
    }

    function loanId() external view returns (bytes32) {
        return _terms.loanId;
    }

    function isRepaymentAllowed() external view returns (bool) {
        return _state.lifecycle == LoanTypes.LoanLifecycle.ACTIVE;
    }

    function initialized() external view returns (bool) {
        return _initialized;
    }

    function _close(bytes32 journalRef) private {
        LoanTypes.LoanLifecycle priorLifecycle = _state.lifecycle;
        LoanTypes.ServicingState priorServicing = _state.servicing;
        LoanTypes.FundingState priorFunding = _state.funding;
        _state.lifecycle = LoanTypes.LoanLifecycle.CLOSED;
        _state.servicing = LoanTypes.ServicingState.REPAID;
        _state.funding = LoanTypes.FundingState.CLOSED;
        _advanceState();
        if (!loanRegistry.isTerminal(_terms.loanId)) {
            loanRegistry.markTerminal(_terms.loanId);
        }
        emit LoanStateChanged(
            _terms.loanId, 0, uint8(priorLifecycle), uint8(_state.lifecycle), _state.stateNonce
        );
        emit LoanStateChanged(
            _terms.loanId, 1, uint8(priorServicing), uint8(_state.servicing), _state.stateNonce
        );
        emit LoanStateChanged(
            _terms.loanId, 2, uint8(priorFunding), uint8(_state.funding), _state.stateNonce
        );
        emit LoanClosed(_terms.loanId, journalRef);
    }

    function _advanceState() private {
        _state.lastTransitionTime = uint64(block.timestamp);
        ++_state.stateNonce;
    }
}
