// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library RiskTypes {
    uint256 internal constant RAY = 1e27;
    uint256 internal constant BPS = 10_000;

    enum ScheduleKind {
        NONE,
        BULLET,
        EQUAL_PRINCIPAL,
        ANNUITY,
        INTEREST_ONLY,
        BALLOON,
        CUSTOM
    }

    enum InstallmentState {
        NONE,
        SCHEDULED,
        DUE,
        PARTIALLY_PAID,
        PAID,
        OVERDUE,
        WAIVED,
        DEFERRED,
        REPLACED
    }

    enum ServicingStatus {
        NONE,
        CURRENT,
        GRACE,
        DELINQUENT,
        CURED,
        ACCELERATED,
        DEFAULTED,
        REPAID
    }

    enum CollateralKind {
        NONE,
        NATIVE,
        ERC20,
        ERC721,
        ERC1155
    }

    enum CollateralStatus {
        NONE,
        LOCKED,
        RELEASED,
        LIQUIDATED,
        CLAIMED
    }

    struct OracleObservation {
        bytes32 assetId;
        bytes32 quoteAssetId;
        uint256 value;
        uint8 decimals;
        uint64 observedAt;
        uint64 retrievedAt;
        uint64 roundId;
        uint16 confidenceBps;
        bytes32 sourceEvidenceHash;
    }

    struct InterestTerms {
        uint256 annualRateRay;
        uint256 spreadRay;
        uint256 floorRateRay;
        uint256 capRateRay;
        uint64 maximumBenchmarkAge;
    }

    struct SchedulePlan {
        ScheduleKind kind;
        uint256 principal;
        uint256 totalInterest;
        uint256 periodicRateRay;
        uint256 balloonPrincipal;
        uint64 startTime;
        uint64 periodSeconds;
        uint32 installmentCount;
        uint32 paymentHolidayCount;
    }

    struct Installment {
        uint32 index;
        uint64 dueTime;
        uint256 principalDue;
        uint256 interestDue;
        InstallmentState state;
    }

    struct CollateralItem {
        bytes32 collateralId;
        bytes32 assetId;
        CollateralKind kind;
        address token;
        uint256 tokenId;
        uint256 quantity;
        address owner;
        uint64 lockedAt;
        CollateralStatus status;
    }
}
