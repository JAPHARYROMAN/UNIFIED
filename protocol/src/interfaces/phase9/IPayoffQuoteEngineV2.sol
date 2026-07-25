// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

interface IPayoffQuoteEngineV2 {
    enum QuoteState { NONE, ISSUED, CONSUMED, EXPIRED, INVALIDATED }
    enum ComponentKind {
        NONE,
        PRINCIPAL,
        ACCRUED_INTEREST,
        CAPITALIZED_INTEREST,
        FEE,
        PENALTY,
        RECOVERABLE_COST,
        CREDIT
    }

    struct PayoffComponentV2 {
        ComponentKind kind;
        uint256 amount;
        address beneficiary;
        string obligationCode;
    }

    struct PayoffQuoteV2 {
        bytes32 quoteId;
        bytes32 loanId;
        address loanAccount;
        bytes32 policyHash;
        uint64 debtStateVersion;
        uint256 principal;
        uint256 accruedInterest;
        uint256 fees;
        uint256 penalties;
        uint256 credits;
        bytes32 componentBeneficiaryHash;
        uint256 grossPayoff;
        uint256 netPayoff;
        bytes32 settlementAssetId;
        address settlementToken;
        bytes32 settlementRouteHash;
        uint64 issuedAt;
        uint64 validUntil;
        uint64 quoteNonce;
        QuoteState state;
    }

    error InvalidQuoteInput();
    error UnknownQuote(bytes32 quoteId);
    error UnauthorizedQuoteCaller(address caller);
    error StaleDebtVersion(uint64 expectedVersion, uint64 actualVersion);
    error QuoteExpired(bytes32 quoteId, uint64 validUntil);
    error QuoteTerminal(bytes32 quoteId, QuoteState state);
    error QuoteReplayConflict(bytes32 quoteId);

    event PayoffQuoteIssued(
        bytes32 indexed quoteId,
        bytes32 indexed loanId,
        uint64 indexed debtStateVersion,
        bytes32 componentBeneficiaryHash,
        uint256 grossPayoff,
        uint256 credits,
        uint256 netPayoff,
        bytes32 settlementAssetId,
        address settlementToken,
        bytes32 settlementRouteHash,
        uint64 issuedAt,
        uint64 validUntil,
        uint64 quoteNonce
    );
    event PayoffQuoteDispositionRecorded(
        bytes32 indexed quoteId,
        bytes32 indexed refinanceId,
        QuoteState state,
        bytes32 sourceEventId,
        uint64 recordedAt
    );

    function issueQuote(bytes32 loanId, uint64 validUntil)
        external
        returns (bytes32 quoteId);
    function consumeQuote(
        bytes32 quoteId,
        bytes32 refinanceId,
        uint64 expectedDebtStateVersion,
        bytes32 sourceEventId
    ) external returns (PayoffQuoteV2 memory storedQuote);
    function invalidateQuote(bytes32 quoteId, bytes32 sourceEventId) external;
    function quote(bytes32 quoteId)
        external
        view
        returns (PayoffQuoteV2 memory storedQuote, PayoffComponentV2[] memory components);
}
