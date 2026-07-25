// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import { ICrossChainReceiver, IWrappedMintReceiver } from "../interfaces/ICrossChainReceiver.sol";
import {
    ISatelliteLoanComponent,
    ISatelliteLoanProvisioner
} from "../interfaces/ISatelliteLoanComponent.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { ISatelliteRepaymentAuthorizer } from "./WrappedUFT.sol";

interface IWrappedLoanCancellationBurner {
    function burnEscrowedLoanCancellation(bytes32 cancellationId, bytes32 loanId, uint256 amount)
        external
        returns (bytes32 resultHash);
}

/// @notice Satellite wUFT escrow, exact borrower disbursement, and repayment burn authorizer.
contract SatelliteSettlementVault is
    ICrossChainReceiver,
    IWrappedMintReceiver,
    ISatelliteLoanProvisioner,
    ISatelliteRepaymentAuthorizer,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    error InvalidSatelliteSettlement();
    error UnauthorizedSatelliteSettlementCaller(address caller);
    error SatelliteSettlementBalanceMismatch();

    struct SettlementRecord {
        bytes32 loanId;
        bytes32 fundingLockId;
        address homeLoanAccount;
        address homeLoanRouter;
        address borrower;
        address lender;
        uint256 principalAmount;
        uint256 escrowedAmount;
        uint256 disbursedAmount;
        uint256 authorizedRepaymentAmount;
        bytes32 cancellationId;
        uint256 cancelledAmount;
        bytes32 repaymentRoutePolicyHash;
        bytes32 policyHash;
    }

    address public immutable component;
    ICrossChainCoordinator public immutable coordinator;
    IERC20 public immutable wrappedUFT;
    mapping(bytes32 loanId => SettlementRecord record) private _records;
    mapping(bytes32 paymentId => bool consumed) public consumedPayment;

    event SatelliteSettlementProvisioned(
        bytes32 indexed loanId,
        bytes32 indexed fundingLockId,
        address indexed borrower,
        uint256 principalAmount
    );
    event SatelliteFundingEscrowed(
        bytes32 indexed loanId, bytes32 indexed fundingLockId, uint256 amount
    );
    event SatelliteFundingDisbursed(
        bytes32 indexed loanId, bytes32 indexed fundingLockId, uint256 amount
    );
    event SatelliteFundingCancelled(
        bytes32 indexed cancellationId,
        bytes32 indexed loanId,
        bytes32 indexed disbursementMessageId,
        uint256 amount,
        bytes32 escrowBurnResultHash,
        bytes32 reportMessageId
    );
    event SatelliteRepaymentAuthorized(
        bytes32 indexed loanId, bytes32 indexed paymentId, address indexed borrower, uint256 amount
    );
    event SatelliteRepaymentAuthorizationReversed(
        bytes32 indexed loanId, bytes32 indexed paymentId, address indexed borrower, uint256 amount
    );

    constructor(address component_, ICrossChainCoordinator coordinator_, IERC20 wrappedUFT_) {
        if (
            component_.code.length == 0 || address(coordinator_) == address(0)
                || address(wrappedUFT_).code.length == 0
        ) {
            revert InvalidSatelliteSettlement();
        }
        component = component_;
        coordinator = coordinator_;
        wrappedUFT = wrappedUFT_;
    }

    function provisionLoan(CrossChainTypes.SatelliteLoanProvisioning calldata provisioning)
        external
        override
    {
        if (msg.sender != component) {
            revert UnauthorizedSatelliteSettlementCaller(msg.sender);
        }
        if (
            provisioning.loanId == bytes32(0) || provisioning.fundingLockId == bytes32(0)
                || provisioning.homeLoanAccount == address(0)
                || provisioning.homeLoanRouter == address(0) || provisioning.borrower == address(0)
                || provisioning.lender == address(0)
                || provisioning.wrappedToken != address(wrappedUFT)
                || provisioning.principalAmount == 0
                || provisioning.repaymentRoutePolicyHash == bytes32(0)
                || provisioning.policyHash == bytes32(0)
                || _records[provisioning.loanId].loanId != bytes32(0)
        ) {
            revert InvalidSatelliteSettlement();
        }
        _records[provisioning.loanId] = SettlementRecord({
            loanId: provisioning.loanId,
            fundingLockId: provisioning.fundingLockId,
            homeLoanAccount: provisioning.homeLoanAccount,
            homeLoanRouter: provisioning.homeLoanRouter,
            borrower: provisioning.borrower,
            lender: provisioning.lender,
            principalAmount: provisioning.principalAmount,
            escrowedAmount: 0,
            disbursedAmount: 0,
            authorizedRepaymentAmount: 0,
            cancellationId: bytes32(0),
            cancelledAmount: 0,
            repaymentRoutePolicyHash: provisioning.repaymentRoutePolicyHash,
            policyHash: provisioning.policyHash
        });
        emit SatelliteSettlementProvisioned(
            provisioning.loanId,
            provisioning.fundingLockId,
            provisioning.borrower,
            provisioning.principalAmount
        );
    }

    function onWrappedMint(bytes32 lockId, bytes32 loanId, uint256 amount)
        external
        override
        nonReentrant
    {
        if (msg.sender != address(wrappedUFT)) {
            revert UnauthorizedSatelliteSettlementCaller(msg.sender);
        }
        SettlementRecord storage record = _records[loanId];
        if (
            record.loanId == bytes32(0) || lockId != record.fundingLockId
                || amount != record.principalAmount || record.escrowedAmount != 0
                || wrappedUFT.balanceOf(address(this)) < amount
        ) {
            revert InvalidSatelliteSettlement();
        }
        record.escrowedAmount = amount;
        ISatelliteLoanComponent(component).reportMintConfirmed(loanId, lockId, amount);
        emit SatelliteFundingEscrowed(loanId, lockId, amount);
    }

    function handleCrossChainMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external override nonReentrant returns (bytes32 resultHash) {
        if (msg.sender != address(coordinator)) {
            revert UnauthorizedSatelliteSettlementCaller(msg.sender);
        }
        if (actionType == CrossChainTypes.ACTION_HOME_LOAN_CANCELLATION_REQUESTED) {
            return _cancelEscrow(messageId, payload);
        }
        if (actionType != CrossChainTypes.ACTION_HOME_DISBURSEMENT_AUTHORIZED) {
            revert InvalidSatelliteSettlement();
        }
        CrossChainTypes.HomeDisbursementAuthorizedPayload memory action =
            abi.decode(payload, (CrossChainTypes.HomeDisbursementAuthorizedPayload));
        SettlementRecord storage record = _records[action.loanId];
        if (
            record.loanId == bytes32(0) || record.escrowedAmount != record.principalAmount
                || record.disbursedAmount != 0 || action.fundingLockId != record.fundingLockId
                || action.homeLoanAccount != record.homeLoanAccount
                || action.borrower != record.borrower || action.lender != record.lender
                || action.wrappedToken != address(wrappedUFT)
                || action.amount != record.principalAmount || action.policyHash != record.policyHash
        ) {
            revert InvalidSatelliteSettlement();
        }
        record.disbursedAmount = record.principalAmount;
        uint256 vaultBefore = wrappedUFT.balanceOf(address(this));
        uint256 borrowerBefore = wrappedUFT.balanceOf(record.borrower);
        wrappedUFT.safeTransfer(record.borrower, record.principalAmount);
        if (
            vaultBefore - wrappedUFT.balanceOf(address(this)) != record.principalAmount
                || wrappedUFT.balanceOf(record.borrower) - borrowerBefore != record.principalAmount
        ) {
            revert SatelliteSettlementBalanceMismatch();
        }
        bytes32 reportMessageId = ISatelliteLoanComponent(component)
            .reportDisbursementSettled(action.loanId, record.fundingLockId, record.principalAmount);
        resultHash = keccak256(
            abi.encode(
                "UNIFIED_SATELLITE_DISBURSEMENT_RESULT_V1",
                messageId,
                reportMessageId,
                action.loanId,
                record.fundingLockId,
                record.principalAmount
            )
        );
        emit SatelliteFundingDisbursed(action.loanId, record.fundingLockId, record.principalAmount);
    }

    function _cancelEscrow(bytes32 messageId, bytes calldata payload)
        private
        returns (bytes32 resultHash)
    {
        CrossChainTypes.LoanCancellationRequestedPayload memory action =
            abi.decode(payload, (CrossChainTypes.LoanCancellationRequestedPayload));
        SettlementRecord storage record = _records[action.loanId];
        if (
            action.cancellationId == bytes32(0) || record.loanId == bytes32(0)
                || record.escrowedAmount != record.principalAmount || record.disbursedAmount != 0
                || record.cancellationId != bytes32(0) || record.cancelledAmount != 0
                || action.fundingLockId != record.fundingLockId
                || action.homeLoanAccount != record.homeLoanAccount
                || action.lender != record.lender || action.wrappedToken != address(wrappedUFT)
                || action.amount != record.principalAmount || action.policyHash != record.policyHash
                || action.reasonCode == bytes32(0)
        ) {
            revert InvalidSatelliteSettlement();
        }
        if (action.disbursementMessageId == bytes32(0)) {
            if (action.disbursementTombstoneHash != bytes32(0)) {
                revert InvalidSatelliteSettlement();
            }
        } else if (
            action.disbursementTombstoneHash == bytes32(0)
                || coordinator.messageState(action.disbursementMessageId)
                    != CrossChainTypes.MessageState.DESTINATION_TOMBSTONED
                || coordinator.tombstoneHash(action.disbursementMessageId)
                    != action.disbursementTombstoneHash
                || coordinator.executionResult(action.disbursementMessageId) != bytes32(0)
        ) {
            revert InvalidSatelliteSettlement();
        }

        record.cancellationId = action.cancellationId;
        record.cancelledAmount = record.principalAmount;
        record.escrowedAmount = 0;
        bytes32 burnResultHash = IWrappedLoanCancellationBurner(address(wrappedUFT))
            .burnEscrowedLoanCancellation(action.cancellationId, action.loanId, action.amount);
        CrossChainTypes.SatelliteFundingCancelledPayload memory report =
            CrossChainTypes.SatelliteFundingCancelledPayload({
                cancellationId: action.cancellationId,
                loanId: action.loanId,
                fundingLockId: action.fundingLockId,
                disbursementMessageId: action.disbursementMessageId,
                disbursementTombstoneHash: action.disbursementTombstoneHash,
                escrowBurnResultHash: burnResultHash,
                homeLoanAccount: action.homeLoanAccount,
                lender: action.lender,
                wrappedToken: action.wrappedToken,
                amount: action.amount,
                policyHash: action.policyHash
            });
        bytes32 reportMessageId =
            ISatelliteLoanComponent(component).reportFundingCancellation(report);
        resultHash = keccak256(
            abi.encode(
                "UNIFIED_SATELLITE_FUNDING_CANCELLATION_RESULT_V1",
                messageId,
                reportMessageId,
                action.cancellationId,
                action.loanId,
                action.amount,
                burnResultHash
            )
        );
        emit SatelliteFundingCancelled(
            action.cancellationId,
            action.loanId,
            action.disbursementMessageId,
            action.amount,
            burnResultHash,
            reportMessageId
        );
    }

    function authorizeRepaymentBurn(
        bytes32 loanId,
        bytes32 paymentId,
        address borrower,
        uint256 amount
    ) external override returns (RepaymentAuthorization memory authorization) {
        if (msg.sender != address(wrappedUFT)) {
            revert UnauthorizedSatelliteSettlementCaller(msg.sender);
        }
        SettlementRecord storage record = _records[loanId];
        if (
            record.loanId == bytes32(0) || paymentId == bytes32(0) || borrower != record.borrower
                || amount == 0 || consumedPayment[paymentId]
                || record.disbursedAmount != record.principalAmount
                || record.authorizedRepaymentAmount + amount > record.principalAmount
        ) {
            revert InvalidSatelliteSettlement();
        }
        consumedPayment[paymentId] = true;
        record.authorizedRepaymentAmount += amount;
        authorization = RepaymentAuthorization({
            lender: record.lender,
            homeLoanRouter: record.homeLoanRouter,
            policyHash: record.policyHash,
            backingRoutePolicyHash: ISatelliteLoanComponent(component).backingRoutePolicyHash(),
            repaymentRoutePolicyHash: record.repaymentRoutePolicyHash
        });
        emit SatelliteRepaymentAuthorized(loanId, paymentId, borrower, amount);
    }

    function reverseRepaymentBurn(
        bytes32 loanId,
        bytes32 paymentId,
        address borrower,
        uint256 amount
    ) external {
        if (msg.sender != address(wrappedUFT)) {
            revert UnauthorizedSatelliteSettlementCaller(msg.sender);
        }
        SettlementRecord storage record = _records[loanId];
        if (
            record.loanId == bytes32(0) || paymentId == bytes32(0) || borrower != record.borrower
                || amount == 0 || !consumedPayment[paymentId]
                || amount > record.authorizedRepaymentAmount
        ) {
            revert InvalidSatelliteSettlement();
        }
        consumedPayment[paymentId] = false;
        record.authorizedRepaymentAmount -= amount;
        emit SatelliteRepaymentAuthorizationReversed(loanId, paymentId, borrower, amount);
    }

    function settlementRecord(bytes32 loanId) external view returns (SettlementRecord memory) {
        return _records[loanId];
    }
}
