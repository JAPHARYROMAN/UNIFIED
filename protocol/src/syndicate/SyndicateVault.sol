// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { LoanTypes } from "../loan/LoanTypes.sol";
import { PositionManager } from "./PositionManager.sol";
import { SyndicateTypes } from "./SyndicateTypes.sol";

/// @notice Exact-asset funding round and canonical principal account for one syndicate.
contract SyndicateVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error InvalidFundingRound();
    error InvalidFundingState(SyndicateTypes.RoundStatus status);
    error InvalidCommitment();
    error DuplicatePayment(bytes32 paymentId);
    error SettlementBalanceMismatch();

    uint8 public constant MAX_TRANCHES = 8;
    uint8 public constant MAX_COMMITMENTS = 64;

    address public factory;
    ILoanRegistry public loanRegistry;
    PositionManager public positionManager;
    IERC20 public settlementToken;
    SyndicateTypes.FundingRoundTerms private _fundingTerms;
    LoanTypes.UniversalLoanTerms private _loanTerms;
    SyndicateTypes.RoundStatus public roundStatus;
    uint256 public totalCommitted;
    uint256 public outstandingPrincipal;
    mapping(bytes32 commitmentId => SyndicateTypes.Commitment commitment_) private _commitments;
    bytes32[] private _commitmentIds;
    mapping(bytes32 paymentId => bool processed) public processedPayments;
    bool private _initialized;

    event FundingRoundOpened(bytes32 indexed loanId, bytes32 indexed roundId, uint64 closesAt);
    event CommitmentFunded(
        bytes32 indexed commitmentId,
        bytes32 indexed trancheId,
        address indexed lender,
        uint256 amount,
        bytes32 positionId
    );
    event CommitmentRefunded(bytes32 indexed commitmentId, address indexed lender, uint256 amount);
    event FundingRoundActivated(
        bytes32 indexed loanId,
        uint256 fundedPrincipal,
        address indexed borrower,
        bytes32 journalRef
    );
    event FundingRoundEnded(
        bytes32 indexed loanId, SyndicateTypes.RoundStatus status, bytes32 reasonCode
    );
    event SyndicatePaymentAllocated(
        bytes32 indexed paymentId,
        bytes32 indexed loanId,
        uint256 amount,
        uint256 remainingPrincipal,
        bytes32 journalRef
    );

    constructor() {
        _initialized = true;
    }

    function initialize(
        address factory_,
        ILoanRegistry loanRegistry_,
        PositionManager positionManager_,
        IERC20 settlementToken_,
        SyndicateTypes.FundingRoundTerms calldata fundingTerms_,
        SyndicateTypes.TrancheConfiguration[] calldata tranches
    ) external {
        if (_initialized) revert AlreadyInitialized();
        if (
            factory_ != msg.sender || factory_.code.length == 0
                || address(loanRegistry_).code.length == 0
                || address(positionManager_).code.length == 0
                || address(settlementToken_).code.length == 0
        ) {
            revert InvalidFundingRound();
        }
        _validateTerms(fundingTerms_, tranches);
        _initialized = true;
        factory = factory_;
        loanRegistry = loanRegistry_;
        positionManager = positionManager_;
        settlementToken = settlementToken_;
        _fundingTerms = fundingTerms_;
        _loanTerms = LoanTypes.UniversalLoanTerms({
            loanId: fundingTerms_.loanId,
            tenderId: fundingTerms_.roundId,
            acceptedOfferId: bytes32(0),
            agreementHash: fundingTerms_.agreementHash,
            parties: LoanTypes.AgreementParties({
                borrower: fundingTerms_.borrower,
                arranger: factory_,
                servicer: address(this),
                collateralAgent: address(0),
                paymentAgent: address(this)
            }),
            principal: LoanTypes.MonetaryAmount({
                assetId: fundingTerms_.settlementAssetId, amount: fundingTerms_.targetFunding
            }),
            fundingDeadline: fundingTerms_.closesAt,
            activationDeadline: fundingTerms_.closesAt,
            commencementTime: 0,
            finalMaturityTime: fundingTerms_.finalMaturityTime,
            gracePeriod: fundingTerms_.gracePeriod,
            protocolVersion: fundingTerms_.protocolVersion,
            policySetHash: fundingTerms_.policySetHash,
            metadataHash: fundingTerms_.metadataHash
        });
        for (uint256 index = 0; index < tranches.length; ++index) {
            positionManager_.configureTranche(tranches[index]);
        }
        if (fundingTerms_.opensAt <= block.timestamp) {
            roundStatus = SyndicateTypes.RoundStatus.OPEN;
            emit FundingRoundOpened(
                fundingTerms_.loanId, fundingTerms_.roundId, fundingTerms_.closesAt
            );
        } else {
            roundStatus = SyndicateTypes.RoundStatus.SCHEDULED;
        }
    }

    function openRound() external {
        if (
            roundStatus != SyndicateTypes.RoundStatus.SCHEDULED
                || block.timestamp < _fundingTerms.opensAt
                || block.timestamp >= _fundingTerms.closesAt
        ) {
            revert InvalidFundingState(roundStatus);
        }
        roundStatus = SyndicateTypes.RoundStatus.OPEN;
        emit FundingRoundOpened(_fundingTerms.loanId, _fundingTerms.roundId, _fundingTerms.closesAt);
    }

    function commit(bytes32 commitmentId, bytes32 trancheId, uint256 amount)
        external
        nonReentrant
        returns (bytes32 positionId)
    {
        if (
            roundStatus != SyndicateTypes.RoundStatus.OPEN
                || block.timestamp >= _fundingTerms.closesAt || commitmentId == bytes32(0)
                || amount == 0
                || _commitments[commitmentId].status != SyndicateTypes.CommitmentStatus.NONE
                || _commitmentIds.length >= MAX_COMMITMENTS
                || totalCommitted + amount > _fundingTerms.maximumFunding
        ) {
            revert InvalidCommitment();
        }
        positionId = keccak256(abi.encode("SYNDICATE_POSITION", _fundingTerms.loanId, commitmentId));
        _commitments[commitmentId] = SyndicateTypes.Commitment({
            commitmentId: commitmentId,
            trancheId: trancheId,
            positionId: positionId,
            lender: msg.sender,
            amount: amount,
            status: SyndicateTypes.CommitmentStatus.FUNDED
        });
        _commitmentIds.push(commitmentId);
        totalCommitted += amount;
        positionManager.issuePending(positionId, trancheId, msg.sender, amount);
        _pullExact(msg.sender, amount);
        emit CommitmentFunded(commitmentId, trancheId, msg.sender, amount, positionId);
    }

    function finalize(bytes32 journalRef) external nonReentrant {
        if (
            roundStatus != SyndicateTypes.RoundStatus.OPEN || journalRef == bytes32(0)
                || (block.timestamp < _fundingTerms.closesAt
                    && totalCommitted < _fundingTerms.targetFunding)
        ) {
            revert InvalidFundingState(roundStatus);
        }
        if (totalCommitted < _fundingTerms.minimumFunding) {
            roundStatus = SyndicateTypes.RoundStatus.FAILED;
            loanRegistry.markTerminal(_fundingTerms.loanId);
            emit FundingRoundEnded(
                _fundingTerms.loanId,
                SyndicateTypes.RoundStatus.FAILED,
                keccak256("MINIMUM_NOT_MET")
            );
            return;
        }

        positionManager.activateFunding(totalCommitted);
        outstandingPrincipal = totalCommitted;
        _loanTerms.principal.amount = totalCommitted;
        _loanTerms.commencementTime = uint64(block.timestamp);
        roundStatus = SyndicateTypes.RoundStatus.ACTIVE;
        _transferExact(_fundingTerms.borrower, totalCommitted);
        for (uint256 index = 0; index < _commitmentIds.length; ++index) {
            _commitments[_commitmentIds[index]].status =
            SyndicateTypes.CommitmentStatus.POSITION_ACTIVE;
        }
        emit FundingRoundActivated(
            _fundingTerms.loanId, totalCommitted, _fundingTerms.borrower, journalRef
        );
    }

    function cancelRound(bytes32 reasonCode) external {
        if (
            msg.sender != _fundingTerms.borrower || reasonCode == bytes32(0)
                || (roundStatus != SyndicateTypes.RoundStatus.SCHEDULED
                    && roundStatus != SyndicateTypes.RoundStatus.OPEN)
        ) {
            revert InvalidFundingState(roundStatus);
        }
        roundStatus = SyndicateTypes.RoundStatus.CANCELLED;
        loanRegistry.markTerminal(_fundingTerms.loanId);
        emit FundingRoundEnded(
            _fundingTerms.loanId, SyndicateTypes.RoundStatus.CANCELLED, reasonCode
        );
    }

    function refund(bytes32 commitmentId) external nonReentrant {
        if (
            roundStatus != SyndicateTypes.RoundStatus.FAILED
                && roundStatus != SyndicateTypes.RoundStatus.CANCELLED
        ) {
            revert InvalidFundingState(roundStatus);
        }
        SyndicateTypes.Commitment storage commitment_ = _commitment(commitmentId);
        if (commitment_.status != SyndicateTypes.CommitmentStatus.FUNDED) {
            revert InvalidCommitment();
        }
        _refund(commitment_);
    }

    function repay(bytes32 paymentId, uint256 amount, bytes32 journalRef) external nonReentrant {
        if (
            roundStatus != SyndicateTypes.RoundStatus.ACTIVE || paymentId == bytes32(0)
                || journalRef == bytes32(0) || amount == 0 || amount > outstandingPrincipal
        ) {
            revert InvalidFundingState(roundStatus);
        }
        if (processedPayments[paymentId]) revert DuplicatePayment(paymentId);
        processedPayments[paymentId] = true;
        _pullExact(msg.sender, amount);
        settlementToken.forceApprove(address(positionManager), amount);
        _distribute(amount);
        settlementToken.forceApprove(address(positionManager), 0);
        outstandingPrincipal -= amount;
        emit SyndicatePaymentAllocated(
            paymentId, _fundingTerms.loanId, amount, outstandingPrincipal, journalRef
        );
        if (outstandingPrincipal == 0) {
            roundStatus = SyndicateTypes.RoundStatus.CLOSED;
            loanRegistry.markTerminal(_fundingTerms.loanId);
            emit FundingRoundEnded(
                _fundingTerms.loanId,
                SyndicateTypes.RoundStatus.CLOSED,
                keccak256("PRINCIPAL_REPAID")
            );
        }
    }

    function commitment(bytes32 commitmentId)
        external
        view
        returns (SyndicateTypes.Commitment memory)
    {
        return _commitment(commitmentId);
    }

    function commitmentIds() external view returns (bytes32[] memory) {
        return _commitmentIds;
    }

    function fundingTerms() external view returns (SyndicateTypes.FundingRoundTerms memory) {
        return _fundingTerms;
    }

    function terms() external view returns (LoanTypes.UniversalLoanTerms memory) {
        return _loanTerms;
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
        return _fundingTerms.borrower;
    }

    function lender() external view returns (address) {
        return address(positionManager);
    }

    function loanId() external view returns (bytes32) {
        return _fundingTerms.loanId;
    }

    function isRepaymentAllowed() external view returns (bool) {
        return roundStatus == SyndicateTypes.RoundStatus.ACTIVE;
    }

    function initialized() external view returns (bool) {
        return _initialized;
    }

    function _distribute(uint256 amount) private {
        bytes32[] memory ids = positionManager.trancheIds();
        uint256 remaining = amount;
        for (uint256 index = 0; index < ids.length; ++index) {
            uint256 trancheOutstanding = positionManager.tranche(ids[index]).outstandingPrincipal;
            uint256 allocation = Math.min(remaining, trancheOutstanding);
            if (allocation != 0) {
                positionManager.recordDistribution(ids[index], allocation);
                remaining -= allocation;
            }
        }
        if (remaining != 0) revert SettlementBalanceMismatch();
    }

    function _refund(SyndicateTypes.Commitment storage commitment_) private {
        commitment_.status = SyndicateTypes.CommitmentStatus.REFUNDED;
        positionManager.cancelPending(commitment_.positionId);
        _transferExact(commitment_.lender, commitment_.amount);
        emit CommitmentRefunded(commitment_.commitmentId, commitment_.lender, commitment_.amount);
    }

    function _commitment(bytes32 commitmentId)
        private
        view
        returns (SyndicateTypes.Commitment storage commitment_)
    {
        commitment_ = _commitments[commitmentId];
        if (commitment_.status == SyndicateTypes.CommitmentStatus.NONE) {
            revert InvalidCommitment();
        }
    }

    function _validateTerms(
        SyndicateTypes.FundingRoundTerms calldata terms_,
        SyndicateTypes.TrancheConfiguration[] calldata tranches
    ) private view {
        if (
            terms_.loanId == bytes32(0) || terms_.roundId == bytes32(0)
                || terms_.agreementHash == bytes32(0) || terms_.policySetHash == bytes32(0)
                || terms_.metadataHash == bytes32(0) || terms_.borrower == address(0)
                || terms_.settlementAssetId == bytes32(0) || terms_.minimumFunding == 0
                || terms_.minimumFunding > terms_.targetFunding
                || terms_.targetFunding > terms_.maximumFunding || terms_.opensAt < block.timestamp
                || terms_.closesAt <= terms_.opensAt || terms_.finalMaturityTime <= terms_.closesAt
                || terms_.protocolVersion == 0 || tranches.length == 0
                || tranches.length > MAX_TRANCHES
        ) {
            revert InvalidFundingRound();
        }
        uint256 totalCapacity;
        for (uint256 index = 0; index < tranches.length; ++index) {
            if (tranches[index].seniorityRank != index + 1) revert InvalidFundingRound();
            totalCapacity += tranches[index].targetSize;
        }
        if (totalCapacity != terms_.maximumFunding) revert InvalidFundingRound();
    }

    function _pullExact(address sender, uint256 amount) private {
        uint256 beforeBalance = settlementToken.balanceOf(address(this));
        settlementToken.safeTransferFrom(sender, address(this), amount);
        if (settlementToken.balanceOf(address(this)) - beforeBalance != amount) {
            revert SettlementBalanceMismatch();
        }
    }

    function _transferExact(address recipient, uint256 amount) private {
        uint256 senderBefore = settlementToken.balanceOf(address(this));
        uint256 recipientBefore = settlementToken.balanceOf(recipient);
        settlementToken.safeTransfer(recipient, amount);
        if (
            senderBefore - settlementToken.balanceOf(address(this)) != amount
                || settlementToken.balanceOf(recipient) - recipientBefore != amount
        ) {
            revert SettlementBalanceMismatch();
        }
    }
}
