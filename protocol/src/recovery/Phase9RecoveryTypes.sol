// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Shared guarantee, loss, write-off, recovery, and entitlement ABI types.
library Phase9RecoveryTypes {
    enum GuaranteeState {
        NONE,
        PROPOSED,
        ACCEPTED,
        ACTIVE,
        CLAIM_PENDING,
        PARTIALLY_PAID,
        PAID,
        EXPIRED,
        RELEASED,
        EXHAUSTED
    }
    enum RecoveryCaseState {
        NONE,
        OPEN,
        RECOVERY_PENDING,
        LOSS_FINALIZED,
        WRITE_OFF_PENDING,
        WRITTEN_OFF,
        RECOVERY_OPEN,
        RECOVERED,
        CLOSED_WITH_UNRECOVERED_LOSS,
        DISPUTED
    }
    enum RecoverySourceType {
        NONE,
        COLLATERAL,
        GUARANTOR,
        INSURANCE,
        MOCKED_LEGAL_RECEIPT,
        OTHER_AUTHORIZED_RECEIPT
    }
    enum RecoverySourceState {
        NONE,
        OBSERVED,
        FINAL,
        ALLOCATED,
        REJECTED,
        DISPUTED
    }
    enum RecoveryEntitlementKind {
        NONE,
        LENDER_UNCOVERED,
        PRODUCT_POOL_SUBROGATION,
        GUARANTOR_SUBROGATION,
        BORROWER_SURPLUS
    }

    struct Guarantee {
        bytes32 guaranteeId;
        bytes32 loanId;
        bytes32 lossId;
        address guarantor;
        bytes32 assetId;
        uint256 maximumAmount;
        uint64 coveredEventMask;
        uint32 priority;
        bytes32 subrogationPolicyHash;
        uint64 validFrom;
        uint64 expiresAt;
        uint256 committedAmount;
        uint256 paidAmount;
        GuaranteeState state;
        bytes32 guaranteeDigest;
    }

    struct LossRecord {
        bytes32 loanId;
        uint64 debtStateVersion;
        bytes32 defaultEventId;
        bytes32 settlementAssetId;
        uint256 grossCoveredLossExposure;
        uint256 collateralCredited;
        uint256 guarantorCredited;
        uint256 insuranceCredited;
        uint256 otherRecoveryCredited;
        uint256 forgivenessRecognized;
        uint256 residualLossExposure;
        uint256 realizedLossRecognized;
        uint256 writeoffRecognized;
        uint256 lenderUncoveredRight;
        uint256 productPoolSubrogationRight;
        uint256 guarantorSubrogationRight;
        uint256 laterRecoveryAllocated;
        uint256 borrowerSurplus;
        bytes32 waterfallPolicyHash;
        RecoveryCaseState state;
        uint64 stateVersion;
    }

    struct RecoverySourceEvidence {
        bytes32 recoverySourceId;
        bytes32 lossId;
        RecoverySourceType sourceType;
        address sourceParty;
        bytes32 sourceReferenceHash;
        uint256 amount;
        bytes32 transactionHash;
        uint32 logIndex;
        bytes32 balanceDeltaHash;
        bytes32 descriptiveEvidenceHash;
        RecoverySourceState state;
        uint64 finalizedAt;
    }

    struct RecoveryEntitlement {
        bytes32 entitlementId;
        bytes32 lossId;
        RecoveryEntitlementKind kind;
        address beneficiary;
        uint256 originalAmount;
        uint256 remainingAmount;
        uint32 priority;
        bytes32 policyHash;
    }

    struct RecoveryAllocation {
        bytes32 allocationId;
        bytes32 lossId;
        bytes32 recoverySourceId;
        bytes32 entitlementId;
        address beneficiary;
        uint256 amount;
        uint32 allocationSequence;
        uint256 receiptResidual;
        bytes32 waterfallPolicyHash;
        bytes32 allocationDigest;
    }

    struct WriteOffEvidence {
        bytes32 writeoffId;
        bytes32 lossId;
        bytes32 loanId;
        uint64 debtStateVersion;
        uint256 residualLossExposure;
        uint256 writeoffAmount;
        bytes32 positionAllocationHash;
        bytes32 recoveryAssessmentHash;
        bytes32 reasonCode;
        bytes32 approvalPolicyHash;
        uint64 writeoffNonce;
        bytes32 approvalEvidenceHash;
        uint64 recognizedAt;
    }
}
