// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { RiskTypes } from "./RiskTypes.sol";

/// @notice Objective due, grace, cure, acceleration, default, and repayment state.
contract ServicingEngine is RoleControlled {
    error InvalidServicingRecord();
    error InvalidServicingTransition(RiskTypes.ServicingStatus status);

    struct Record {
        uint256 amountDue;
        uint256 amountPaid;
        uint64 dueTime;
        uint64 graceEndsAt;
        uint64 cureEndsAt;
        uint64 stateNonce;
        RiskTypes.ServicingStatus status;
    }

    mapping(bytes32 loanId => Record record) private _records;

    event ServicingConfigured(
        bytes32 indexed loanId,
        uint256 amountDue,
        uint64 dueTime,
        uint64 graceEndsAt,
        uint64 cureEndsAt
    );
    event ServicingPaymentApplied(
        bytes32 indexed loanId, bytes32 indexed paymentId, uint256 amount, uint256 remainingDue
    );
    event ServicingStateChanged(
        bytes32 indexed loanId,
        RiskTypes.ServicingStatus fromStatus,
        RiskTypes.ServicingStatus toStatus,
        uint64 stateNonce,
        bytes32 reasonCode
    );

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function configure(
        bytes32 loanId,
        uint256 amountDue,
        uint64 dueTime,
        uint64 graceEndsAt,
        uint64 cureEndsAt
    ) external onlyRole(ProtocolRoles.SERVICER_ROLE) {
        if (
            loanId == bytes32(0) || amountDue == 0 || dueTime <= block.timestamp
                || graceEndsAt < dueTime || cureEndsAt < graceEndsAt
                || _records[loanId].status != RiskTypes.ServicingStatus.NONE
        ) {
            revert InvalidServicingRecord();
        }
        _records[loanId] = Record({
            amountDue: amountDue,
            amountPaid: 0,
            dueTime: dueTime,
            graceEndsAt: graceEndsAt,
            cureEndsAt: cureEndsAt,
            stateNonce: 1,
            status: RiskTypes.ServicingStatus.CURRENT
        });
        emit ServicingConfigured(loanId, amountDue, dueTime, graceEndsAt, cureEndsAt);
        emit ServicingStateChanged(
            loanId,
            RiskTypes.ServicingStatus.NONE,
            RiskTypes.ServicingStatus.CURRENT,
            1,
            keccak256("SCHEDULE_CONFIGURED")
        );
    }

    function applyFinalPayment(bytes32 loanId, bytes32 paymentId, uint256 amount)
        external
        onlyRole(ProtocolRoles.PAYMENT_FINALIZER_ROLE)
    {
        Record storage record = _record(loanId);
        if (
            paymentId == bytes32(0) || amount == 0 || record.amountPaid + amount > record.amountDue
                || record.status == RiskTypes.ServicingStatus.DEFAULTED
                || record.status == RiskTypes.ServicingStatus.REPAID
        ) {
            revert InvalidServicingRecord();
        }
        record.amountPaid += amount;
        emit ServicingPaymentApplied(
            loanId, paymentId, amount, record.amountDue - record.amountPaid
        );
        if (record.amountPaid == record.amountDue) {
            _transition(
                loanId, record, RiskTypes.ServicingStatus.REPAID, keccak256("OBLIGATION_PAID")
            );
        }
    }

    function evaluate(bytes32 loanId) external returns (RiskTypes.ServicingStatus) {
        Record storage record = _record(loanId);
        if (
            record.status == RiskTypes.ServicingStatus.REPAID
                || record.status == RiskTypes.ServicingStatus.DEFAULTED
                || record.status == RiskTypes.ServicingStatus.ACCELERATED
        ) {
            return record.status;
        }
        RiskTypes.ServicingStatus target = RiskTypes.ServicingStatus.CURRENT;
        bytes32 reason = keccak256("NOT_DUE");
        if (record.amountPaid == record.amountDue) {
            target = RiskTypes.ServicingStatus.REPAID;
            reason = keccak256("OBLIGATION_PAID");
        } else if (record.status == RiskTypes.ServicingStatus.CURED) {
            target = RiskTypes.ServicingStatus.CURED;
            reason = keccak256("CURE_RECORDED");
        } else if (block.timestamp > record.graceEndsAt) {
            target = RiskTypes.ServicingStatus.DELINQUENT;
            reason = keccak256("GRACE_EXPIRED");
        } else if (block.timestamp > record.dueTime) {
            target = RiskTypes.ServicingStatus.GRACE;
            reason = keccak256("PAYMENT_OVERDUE");
        }
        if (target != record.status) _transition(loanId, record, target, reason);
        return record.status;
    }

    function accelerate(bytes32 loanId, bytes32 reasonCode)
        external
        onlyRole(ProtocolRoles.SERVICER_ROLE)
    {
        Record storage record = _record(loanId);
        if (record.status != RiskTypes.ServicingStatus.DELINQUENT || reasonCode == bytes32(0)) {
            revert InvalidServicingTransition(record.status);
        }
        _transition(loanId, record, RiskTypes.ServicingStatus.ACCELERATED, reasonCode);
    }

    function recordCure(bytes32 loanId, bytes32 evidenceHash)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
    {
        Record storage record = _record(loanId);
        if (
            (record.status != RiskTypes.ServicingStatus.GRACE
                    && record.status != RiskTypes.ServicingStatus.DELINQUENT)
                || block.timestamp > record.cureEndsAt || evidenceHash == bytes32(0)
        ) {
            revert InvalidServicingTransition(record.status);
        }
        _transition(loanId, record, RiskTypes.ServicingStatus.CURED, evidenceHash);
    }

    function confirmDefault(bytes32 loanId, bytes32 evidenceHash)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
    {
        Record storage record = _record(loanId);
        if (
            (record.status != RiskTypes.ServicingStatus.DELINQUENT
                    && record.status != RiskTypes.ServicingStatus.ACCELERATED)
                || block.timestamp <= record.cureEndsAt || evidenceHash == bytes32(0)
        ) {
            revert InvalidServicingTransition(record.status);
        }
        _transition(loanId, record, RiskTypes.ServicingStatus.DEFAULTED, evidenceHash);
    }

    function servicingRecord(bytes32 loanId) external view returns (Record memory) {
        return _record(loanId);
    }

    function liquidationEligible(bytes32 loanId) external view returns (bool) {
        return _records[loanId].status == RiskTypes.ServicingStatus.DEFAULTED;
    }

    function _record(bytes32 loanId) private view returns (Record storage record_) {
        record_ = _records[loanId];
        if (record_.status == RiskTypes.ServicingStatus.NONE) revert InvalidServicingRecord();
    }

    function _transition(
        bytes32 loanId,
        Record storage record_,
        RiskTypes.ServicingStatus target,
        bytes32 reasonCode
    ) private {
        RiskTypes.ServicingStatus prior = record_.status;
        record_.status = target;
        ++record_.stateNonce;
        emit ServicingStateChanged(loanId, prior, target, record_.stateNonce, reasonCode);
    }
}
