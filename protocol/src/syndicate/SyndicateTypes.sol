// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library SyndicateTypes {
    enum RoundStatus {
        NONE,
        SCHEDULED,
        OPEN,
        ACTIVE,
        FAILED,
        CANCELLED,
        CLOSED
    }

    enum CommitmentStatus {
        NONE,
        FUNDED,
        POSITION_ACTIVE,
        REFUNDED
    }

    enum PositionStatus {
        NONE,
        PENDING,
        ACTIVE,
        PLEDGED,
        FROZEN,
        MERGED,
        REDEEMED,
        CANCELLED
    }

    enum TransferPolicy {
        NONE,
        NON_TRANSFERABLE,
        FREELY_TRANSFERABLE
    }

    struct FundingRoundTerms {
        bytes32 loanId;
        bytes32 roundId;
        bytes32 agreementHash;
        bytes32 policySetHash;
        bytes32 metadataHash;
        address borrower;
        bytes32 settlementAssetId;
        uint256 minimumFunding;
        uint256 targetFunding;
        uint256 maximumFunding;
        uint64 opensAt;
        uint64 closesAt;
        uint64 finalMaturityTime;
        uint64 gracePeriod;
        uint32 protocolVersion;
    }

    struct TrancheConfiguration {
        bytes32 trancheId;
        bytes32 nameHash;
        uint8 seniorityRank;
        uint256 targetSize;
        uint16 couponBps;
        uint16 votingBps;
        TransferPolicy transferPolicy;
    }

    struct Commitment {
        bytes32 commitmentId;
        bytes32 trancheId;
        bytes32 positionId;
        address lender;
        uint256 amount;
        CommitmentStatus status;
    }

    struct Position {
        bytes32 positionId;
        bytes32 loanId;
        bytes32 trancheId;
        address owner;
        address pledgee;
        uint256 shares;
        uint256 votingPower;
        uint64 acquiredAt;
        PositionStatus status;
    }
}
