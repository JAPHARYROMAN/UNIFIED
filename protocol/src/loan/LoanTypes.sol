// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library LoanTypes {
    enum TenderState {
        NONE,
        OPEN,
        COMMITMENT_PENDING,
        FULFILLED,
        CANCELLED,
        EXPIRED
    }

    enum OfferState {
        NONE,
        ACTIVE,
        COUNTERED,
        CONSUMED,
        CANCELLED,
        EXPIRED
    }

    enum LoanLifecycle {
        NONE,
        PROPOSED,
        UNDERWRITING,
        FUNDING,
        ACTIVATING,
        ACTIVE,
        CLOSED,
        CANCELLED
    }

    enum ServicingState {
        NOT_STARTED,
        CURRENT,
        GRACE,
        DELINQUENT,
        ACCELERATED,
        RESTRUCTURING,
        REFINANCING,
        DEFAULTED,
        REPAID,
        SETTLED,
        WRITTEN_OFF
    }

    enum FundingState {
        NONE,
        OPEN,
        PARTIALLY_FUNDED,
        FUNDED,
        FAILED,
        REFUNDING,
        CLOSED
    }

    enum PaymentState {
        NONE,
        REQUESTED,
        AUTHORIZED,
        PROCESSING,
        PROVISIONAL,
        FINAL,
        ALLOCATED,
        REVERSED,
        DISPUTED,
        FAILED,
        REFUNDED
    }

    struct AgreementParties {
        address borrower;
        address arranger;
        address servicer;
        address collateralAgent;
        address paymentAgent;
    }

    struct MonetaryAmount {
        bytes32 assetId;
        uint256 amount;
    }

    struct UniversalLoanTerms {
        bytes32 loanId;
        bytes32 tenderId;
        bytes32 acceptedOfferId;
        bytes32 agreementHash;
        AgreementParties parties;
        MonetaryAmount principal;
        uint64 fundingDeadline;
        uint64 activationDeadline;
        uint64 commencementTime;
        uint64 finalMaturityTime;
        uint64 gracePeriod;
        uint32 protocolVersion;
        bytes32 policySetHash;
        bytes32 metadataHash;
    }

    struct LoanStateVector {
        LoanLifecycle lifecycle;
        ServicingState servicing;
        FundingState funding;
        PaymentState latestPayment;
        uint64 lastTransitionTime;
        uint64 stateNonce;
    }

    struct DebtSnapshot {
        uint256 outstandingPrincipal;
        uint256 accruedInterest;
        uint256 capitalizedInterest;
        uint256 accruedFees;
        uint256 accruedPenalties;
        uint256 recoverableCosts;
        uint256 unappliedCredit;
        uint64 asOf;
    }

    struct Offer {
        bytes32 offerId;
        bytes32 tenderId;
        bytes32 parentOfferId;
        address lender;
        address borrower;
        bytes32 assetId;
        uint256 principalAmount;
        uint256 originationFee;
        uint64 fundingDeadline;
        uint64 activationDeadline;
        uint64 finalMaturityTime;
        uint64 gracePeriod;
        uint32 protocolVersion;
        bytes32 policySetHash;
        bytes32 agreementHash;
        bytes32 metadataHash;
        uint256 nonce;
        uint64 expiry;
    }
}
