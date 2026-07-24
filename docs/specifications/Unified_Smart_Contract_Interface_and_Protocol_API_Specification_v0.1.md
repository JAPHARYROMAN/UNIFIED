# Unified Smart Contract Interface and Protocol API Specification

**Version:** 0.1  
**Status:** Architecture baseline  
**Scope:** Solidity interfaces, protocol boundaries, shared types, events, errors, roles, adapters, versioning, integration APIs, and implementation obligations.

---

## 1. Purpose

This specification converts Unified's Constitution, Domain Model, Universal Loan Model, Financial Accounting Specification, UFT Tokenomics, Threat Model, and Formal Verification Specification into concrete implementation contracts.

It defines:

- The trusted protocol kernel.
- Solidity interface boundaries.
- Canonical shared structs and enums.
- Contract responsibilities.
- Events and custom errors.
- Access-control roles and authority limits.
- Policy-module interfaces.
- External adapter interfaces.
- UFT, staking, governance, treasury, and bridge interfaces.
- Protocol-facing service APIs.
- Versioning, compatibility, upgrade, and deprecation rules.
- Formal properties each implementation must preserve.

This document defines interfaces and behavioral obligations. It does not prescribe every internal data structure or algorithm.

---

## 2. Governing hierarchy

Implementations must obey the following order of authority:

1. Unified Constitution.
2. Unified Protocol Invariants and Formal Verification Specification.
3. Universal Loan Model and State Machines.
4. Unified Financial Accounting Specification.
5. UFT Tokenomics and Economic Security Specification.
6. Unified Threat Model and Adversarial Security Specification.
7. Unified Domain Model.
8. This interface and API specification.
9. Contract implementation documentation.

When an interface interpretation conflicts with a higher-order document, the higher-order rule prevails.

---

# Part I — Interface Design Doctrine

## 3. Core principles

### 3.1 Small trusted kernel

The protocol kernel should contain only the minimum logic required to establish canonical identity, agreement integrity, policy binding, asset custody, debt state, authorization, and settlement.

### 3.2 Replaceable edges

Oracles, payment providers, bridges, identity attesters, underwriting models, exchange routes, auction mechanisms, and other external systems must be isolated behind adapters.

### 3.3 Immutable active agreements

Every activated loan binds to exact implementation and policy versions. Later registry changes must not silently alter an active loan.

### 3.4 Deny by default

No operation is permitted unless an interface, role, signature, or immutable agreement explicitly authorizes it.

### 3.5 One canonical authority

Every loan, payment, collateral position, lender claim, governance action, and UFT representation has one canonical authority.

### 3.6 Explicit finality

Initiation, authorization, provisional settlement, final settlement, accounting allocation, and economic completion are distinct.

### 3.7 Interface segregation

No module should receive authority broader than its function requires.

### 3.8 Event completeness

Every material state transition and asset movement must emit sufficient evidence for indexing, accounting, monitoring, reconciliation, and dispute resolution.

### 3.9 No hidden administrators

Every privileged operation must map to a named role, a governance execution, an emergency mandate, or an immutable system rule.

### 3.10 Pull over push

Where practical, distributable assets should be claimable through pull-based accounting rather than automatically pushed to arbitrary recipients.

---

## 4. Contract categories

Unified contracts are divided into these categories:

| Category | Purpose |
|---|---|
| Kernel | Canonical loan, registry, policy, and authority state |
| Account | Isolated loan, collateral, syndicate, staking, or treasury custody |
| Policy | Versioned economic and eligibility rules |
| Adapter | Bounded integration with external systems |
| Router | Safe selection and invocation of approved modules |
| Registry | Approved addresses, versions, assets, and capabilities |
| Governance | Proposals, voting, timelocks, councils, and execution |
| Utility | Signatures, math, accounting references, and shared validation |

---

# Part II — Canonical Solidity Types

## 5. Identifier types

Implementations should use deterministic `bytes32` identifiers unless a stronger domain requirement exists.

```solidity
library UnifiedIds {
    type LoanId is bytes32;
    type TenderId is bytes32;
    type OfferId is bytes32;
    type PolicyId is bytes32;
    type PositionId is bytes32;
    type PaymentId is bytes32;
    type SettlementId is bytes32;
    type CollateralId is bytes32;
    type CommitmentId is bytes32;
    type ProposalId is bytes32;
    type MessageId is bytes32;
    type CredentialId is bytes32;
    type DecisionId is bytes32;
    type JournalRef is bytes32;
}
```

Identifiers must be:

- Unique within their domain.
- Domain-separated.
- Bound to the relevant chain and contract where replay risk exists.
- Reproducible where deterministic derivation is required.
- Never reused after terminal closure.

---

## 6. Shared enums

```solidity
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

enum CollateralState {
    NONE,
    PENDING,
    LOCKED,
    MARGIN_CALL,
    PARTIALLY_LIQUIDATED,
    LIQUIDATING,
    RELEASE_PENDING,
    RELEASED,
    CLAIMED
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

enum PositionState {
    NONE,
    ISSUED,
    ACTIVE,
    LISTED,
    TRANSFER_LOCKED,
    PLEDGED,
    FROZEN,
    REDEEMED,
    EXTINGUISHED
}

enum FinalityClass {
    NONE,
    PROVISIONAL,
    CONDITIONAL,
    FINAL,
    REVERSED
}

enum AssetClass {
    NATIVE,
    ERC20,
    ERC721,
    ERC1155,
    TOKENIZED_RWA,
    OFFCHAIN_FIAT,
    OFFCHAIN_ASSET,
    SYNTHETIC_POSITION
}

enum PolicyFamily {
    IDENTITY,
    CREDIT,
    FUNDING,
    COLLATERAL,
    INTEREST,
    REPAYMENT,
    SETTLEMENT,
    LIQUIDATION,
    TRANSFER,
    REFINANCING,
    INSURANCE,
    FEE,
    CROSSCHAIN
}
```

Enums must not be reordered after deployment. New values must be appended.

---

## 7. Asset descriptor

```solidity
struct AssetDescriptor {
    bytes32 assetId;
    AssetClass assetClass;
    uint256 chainId;
    address token;
    uint256 tokenId;
    uint8 decimals;
    bytes32 externalAssetRef;
}
```

Rules:

- `assetId` must resolve through the approved asset registry.
- Off-chain assets require an approved custodian or attester reference.
- Token decimals must come from the registry, not untrusted runtime metadata.
- NFT identifiers must not be normalized as fungible quantities.

---

## 8. Monetary amount

```solidity
struct MonetaryAmount {
    bytes32 assetId;
    uint256 amount;
}
```

All amounts are unsigned integer minor units. Negative balances are represented through account classification, not signed token amounts.

---

## 9. Policy reference

```solidity
struct PolicyRef {
    bytes32 policyId;
    PolicyFamily family;
    uint32 major;
    uint32 minor;
    uint32 patch;
    address implementation;
    bytes32 configurationHash;
}
```

An activated loan must store the complete policy reference set or an immutable hash that resolves to it.

---

## 10. Agreement parties

```solidity
struct AgreementParties {
    address borrower;
    address arranger;
    address servicer;
    address collateralAgent;
    address paymentAgent;
}
```

An address may be zero only when the corresponding role is not applicable.

---

## 11. Universal loan terms

```solidity
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
```

The agreement hash must bind:

- Parties.
- Assets.
- Amounts.
- All policy versions.
- Schedule.
- Fees.
- Collateral and guarantee obligations.
- Transfer rights.
- Refinancing rights.
- Governing chain and verifying contract.

---

## 12. Loan state vector

```solidity
struct LoanStateVector {
    LoanLifecycle lifecycle;
    ServicingState servicing;
    FundingState funding;
    CollateralState collateral;
    PaymentState latestPayment;
    uint64 lastTransitionTime;
    uint64 stateNonce;
}
```

The state vector must be validated against the permitted compatibility matrix.

---

## 13. Debt snapshot

```solidity
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
```

The debt snapshot must be reproducible from canonical terms, accrual policy, finalized payments, and authorized adjustments.

---

## 14. Funding commitment

```solidity
struct FundingCommitment {
    bytes32 commitmentId;
    bytes32 loanId;
    address lender;
    bytes32 trancheId;
    uint256 committedAmount;
    uint256 fundedAmount;
    uint64 expiry;
    uint256 nonce;
    bytes32 termsHash;
}
```

---

## 15. Lender position

```solidity
struct LenderPositionData {
    bytes32 positionId;
    bytes32 loanId;
    bytes32 trancheId;
    address owner;
    uint256 principalUnits;
    uint256 incomeUnits;
    uint16 priority;
    PositionState state;
}
```

---

## 16. Collateral item

```solidity
struct CollateralItem {
    bytes32 collateralId;
    bytes32 loanId;
    AssetDescriptor asset;
    uint256 quantity;
    address depositor;
    address beneficiary;
    bytes32 valuationPolicyId;
    bytes32 liquidationPolicyId;
    bytes32 custodyRef;
}
```

---

## 17. Oracle observation

```solidity
struct OracleObservation {
    bytes32 assetId;
    bytes32 quoteAssetId;
    uint256 price;
    uint8 decimals;
    uint64 observedAt;
    uint64 validUntil;
    bytes32 sourceSetHash;
    uint32 confidenceBps;
}
```

---

## 18. Payment evidence

```solidity
struct PaymentEvidence {
    bytes32 paymentId;
    bytes32 loanId;
    bytes32 providerId;
    bytes32 externalReference;
    bytes32 assetId;
    uint256 grossAmount;
    uint256 providerFee;
    FinalityClass finality;
    uint64 observedAt;
    uint64 finalizedAt;
    bytes32 evidenceHash;
}
```

---

## 19. Allocation result

```solidity
struct PaymentAllocation {
    uint256 costs;
    uint256 penalties;
    uint256 fees;
    uint256 interest;
    uint256 principal;
    uint256 reserveContribution;
    uint256 refundableExcess;
}
```

The sum of allocation fields must equal the allocatable payment amount.

---

# Part III — Common Errors and Events

## 20. Custom errors

```solidity
error Unauthorized(address caller, bytes32 requiredRole);
error InvalidState(bytes32 entityId, uint8 currentState, uint8 requiredState);
error InvalidTransition(bytes32 entityId, uint8 fromState, uint8 toState);
error InvalidSignature(address expectedSigner);
error Expired(uint64 deadline, uint64 currentTime);
error NonceAlreadyUsed(address signer, uint256 nonce);
error DuplicateExecution(bytes32 operationId);
error UnsupportedAsset(bytes32 assetId);
error UnsupportedPolicy(bytes32 policyId, uint32 major);
error PolicyVersionMismatch(bytes32 policyId, bytes32 expectedHash, bytes32 actualHash);
error AgreementHashMismatch(bytes32 expected, bytes32 actual);
error InsufficientFunding(uint256 required, uint256 available);
error InsufficientCollateral(uint256 requiredValue, uint256 actualValue);
error InvalidOracleObservation(bytes32 assetId);
error StaleOracleObservation(bytes32 assetId, uint64 observedAt);
error PaymentNotFinal(bytes32 paymentId);
error AccountingReferenceRequired();
error AmountExceedsObligation(uint256 amount, uint256 remaining);
error PositionRightsExceeded(bytes32 loanId);
error CollateralStillEncumbered(bytes32 collateralId);
error ActiveLoanMutationForbidden(bytes32 loanId);
error TerminalState(bytes32 entityId);
error BridgeBackingInsufficient(uint256 required, uint256 available);
error GovernanceBoundaryViolation(bytes4 selector);
error EmergencyAuthorityExpired(uint64 expiry);
error ZeroAddress();
error ZeroAmount();
error ReentrancyDetected();
```

Implementations should prefer custom errors over revert strings.

---

## 21. Core events

```solidity
event TenderRegistered(bytes32 indexed tenderId, address indexed borrower, bytes32 metadataHash);
event OfferConsumed(bytes32 indexed offerId, bytes32 indexed loanId, address indexed lender);
event LoanCreated(bytes32 indexed loanId, address indexed borrower, bytes32 agreementHash);
event LoanActivated(bytes32 indexed loanId, uint64 commencementTime, uint256 principalAmount);
event LoanStateChanged(bytes32 indexed loanId, uint8 stateDomain, uint8 fromState, uint8 toState, uint64 stateNonce);
event FundingCommitted(bytes32 indexed commitmentId, bytes32 indexed loanId, address indexed lender, uint256 amount);
event LenderPositionIssued(bytes32 indexed positionId, bytes32 indexed loanId, address indexed owner, uint256 principalUnits);
event LenderPositionTransferred(bytes32 indexed positionId, address indexed from, address indexed to);
event CollateralLocked(bytes32 indexed collateralId, bytes32 indexed loanId, address indexed depositor, bytes32 assetId, uint256 quantity);
event CollateralReleased(bytes32 indexed collateralId, bytes32 indexed loanId, address indexed recipient);
event OracleObservationAccepted(bytes32 indexed assetId, uint256 price, uint64 observedAt, bytes32 sourceSetHash);
event PaymentObserved(bytes32 indexed paymentId, bytes32 indexed loanId, uint8 finality, uint256 amount);
event PaymentFinalized(bytes32 indexed paymentId, bytes32 indexed loanId, uint256 amount);
event PaymentAllocated(bytes32 indexed paymentId, bytes32 indexed loanId, uint256 principal, uint256 interest, uint256 fees);
event DefaultConfirmed(bytes32 indexed loanId, bytes32 defaultReason, uint64 confirmedAt);
event LiquidationStarted(bytes32 indexed liquidationId, bytes32 indexed loanId, bytes32 methodId);
event LiquidationCompleted(bytes32 indexed liquidationId, bytes32 indexed loanId, uint256 grossProceeds, uint256 borrowerSurplus);
event RefinanceCompleted(bytes32 indexed oldLoanId, bytes32 indexed newLoanId, uint256 payoffAmount);
event PolicyRegistered(bytes32 indexed policyId, uint8 indexed family, uint32 major, uint32 minor, uint32 patch, address implementation);
event PolicyDeprecated(bytes32 indexed policyId, uint32 major, uint32 minor, uint32 patch);
event AdapterStatusChanged(bytes32 indexed adapterId, address indexed adapter, bool enabled);
event EmergencyActionExecuted(bytes32 indexed actionId, bytes4 indexed selector, uint64 expiry);
event JournalReferenceLinked(bytes32 indexed operationId, bytes32 indexed journalRef);
```

Events must use indexed fields selectively to support practical querying without excessive gas cost.

---

# Part IV — Protocol Kernel Interfaces

## 22. IUnifiedProtocol

```solidity
interface IUnifiedProtocol {
    function protocolVersion() external view returns (uint32);
    function loanRegistry() external view returns (address);
    function policyRegistry() external view returns (address);
    function assetRegistry() external view returns (address);
    function roleManager() external view returns (address);
    function emergencyController() external view returns (address);
    function feeRouter() external view returns (address);
    function treasury() external view returns (address);
    function isPaused(bytes32 capability) external view returns (bool);
}
```

The root protocol contract should be a directory and capability authority, not a universal asset custodian.

---

## 23. ILoanFactory

```solidity
interface ILoanFactory {
    function createLoan(
        UniversalLoanTerms calldata terms,
        PolicyRef[] calldata policies,
        bytes calldata activationData
    ) external returns (bytes32 loanId, address loanAccount);

    function predictLoanAddress(
        bytes32 loanId,
        uint32 implementationVersion
    ) external view returns (address);

    function implementationForVersion(uint32 version) external view returns (address);
}
```

### Obligations

- Reject duplicate loan IDs.
- Verify agreement hash and policy set.
- Verify caller authority.
- Use deterministic deployment where appropriate.
- Register the loan atomically.
- Bind the loan to an immutable implementation version.
- Emit `LoanCreated`.

---

## 24. ILoanRegistry

```solidity
interface ILoanRegistry {
    function registerLoan(
        bytes32 loanId,
        address loanAccount,
        address borrower,
        bytes32 agreementHash,
        uint32 protocolVersion
    ) external;

    function loanAccount(bytes32 loanId) external view returns (address);
    function borrowerOf(bytes32 loanId) external view returns (address);
    function agreementHashOf(bytes32 loanId) external view returns (bytes32);
    function protocolVersionOf(bytes32 loanId) external view returns (uint32);
    function exists(bytes32 loanId) external view returns (bool);
    function isTerminal(bytes32 loanId) external view returns (bool);
}
```

Registration is append-only. A registered loan identity cannot be reassigned.

---

## 25. IUnifiedLoan

```solidity
interface IUnifiedLoan {
    function loanId() external view returns (bytes32);
    function terms() external view returns (UniversalLoanTerms memory);
    function policySet() external view returns (PolicyRef[] memory);
    function stateVector() external view returns (LoanStateVector memory);
    function debtSnapshot(uint64 asOf) external view returns (DebtSnapshot memory);
    function borrower() external view returns (address);
    function isRepaymentAllowed() external view returns (bool);

    function activate(bytes calldata activationEvidence) external;
    function repay(bytes32 paymentId, uint256 amount, bytes calldata settlementEvidence) external;
    function finalizeExternalPayment(PaymentEvidence calldata evidence) external;
    function applyPayment(bytes32 paymentId) external returns (PaymentAllocation memory);
    function declareDefault(bytes32 reasonCode, bytes calldata evidence) external;
    function cureDefault(bytes calldata cureEvidence) external;
    function close(bytes32 closureReason, bytes32 journalRef) external;
}
```

### Constitutional restrictions

`IUnifiedLoan` must not expose generic setters for:

- Borrower.
- Lender rights.
- Principal.
- Interest policy.
- Maturity.
- Collateral policy.
- Payment waterfall.
- Agreement hash.
- Bound policy versions.

Changes must occur only through an authorized amendment or restructuring interface already permitted by the agreement.

---

## 26. ILoanAmendmentController

```solidity
interface ILoanAmendmentController {
    function proposeAmendment(
        bytes32 loanId,
        bytes32 amendmentHash,
        uint64 expiry
    ) external returns (bytes32 amendmentId);

    function consent(
        bytes32 amendmentId,
        address consentingParty,
        bytes calldata signature
    ) external;

    function executeAmendment(
        bytes32 amendmentId,
        bytes calldata executionData
    ) external;

    function requiredConsents(bytes32 amendmentId) external view returns (address[] memory);
    function isExecutable(bytes32 amendmentId) external view returns (bool);
}
```

Amendment execution must preserve constitutional and seniority constraints.

---

# Part V — Marketplace and Offer Interfaces

## 27. ITenderRegistry

```solidity
interface ITenderRegistry {
    function registerTender(
        bytes32 tenderId,
        address borrower,
        bytes32 metadataHash,
        uint64 expiry
    ) external;

    function cancelTender(bytes32 tenderId) external;
    function markFulfilled(bytes32 tenderId, bytes32 loanId) external;
    function tenderOwner(bytes32 tenderId) external view returns (address);
    function tenderStatus(bytes32 tenderId) external view returns (uint8);
}
```

Full tender search metadata may remain off-chain, but on-chain status and integrity anchors must be authoritative where registered.

---

## 28. IOfferManager

```solidity
interface IOfferManager {
    function hashOffer(bytes calldata encodedOffer) external view returns (bytes32);
    function verifyOffer(bytes calldata encodedOffer, bytes calldata signature) external view returns (address signer);
    function consumeOffer(
        bytes32 offerId,
        bytes32 loanId,
        bytes calldata encodedOffer,
        bytes calldata signature
    ) external;
    function cancelNonce(uint256 nonce) external;
    function cancelNonceRange(uint256 minimumNonce) external;
    function isNonceUsed(address signer, uint256 nonce) external view returns (bool);
}
```

Offers must use typed, domain-separated signatures and include chain ID, verifying contract, expiry, nonce, tender or borrower binding, asset IDs, and policy hashes.

---

# Part VI — Policy Registry and Base Policy Interfaces

## 29. IPolicyRegistry

```solidity
interface IPolicyRegistry {
    function registerPolicy(PolicyRef calldata policy, bytes32 codeHash) external;
    function deprecatePolicy(bytes32 policyId, uint32 major, uint32 minor, uint32 patch) external;
    function resolvePolicy(
        bytes32 policyId,
        uint32 major,
        uint32 minor,
        uint32 patch
    ) external view returns (PolicyRef memory);
    function isApproved(PolicyRef calldata policy) external view returns (bool);
    function codeHashOf(address implementation) external view returns (bytes32);
}
```

Deprecation prevents new bindings but does not invalidate active loans.

---

## 30. IBasePolicy

```solidity
interface IBasePolicy {
    function policyId() external pure returns (bytes32);
    function policyFamily() external pure returns (PolicyFamily);
    function semanticVersion() external pure returns (uint32 major, uint32 minor, uint32 patch);
    function interfaceId() external pure returns (bytes4);
    function configurationSchemaHash() external pure returns (bytes32);
    function validateConfiguration(bytes calldata config) external view returns (bool);
}
```

Policy implementations should be stateless when practical. Loan-specific settings should be immutable configuration data bound by hash.

---

## 31. IIdentityPolicy

```solidity
interface IIdentityPolicy is IBasePolicy {
    function validateEligibility(
        address participant,
        bytes32 productId,
        bytes calldata credentialProof
    ) external view returns (bool eligible, bytes32 reasonCode);
}
```

The policy must not require public disclosure of raw identity data.

---

## 32. ICreditPolicy

```solidity
interface ICreditPolicy is IBasePolicy {
    function validateDecision(
        address borrower,
        bytes32 decisionId,
        bytes calldata attestation
    ) external view returns (bool valid, uint256 exposureLimit, uint64 validUntil);

    function exposureAfterOrigination(
        address borrower,
        uint256 proposedAmount
    ) external view returns (uint256 totalExposure);
}
```

---

## 33. IFundingPolicy

```solidity
interface IFundingPolicy is IBasePolicy {
    function minimumFunding(bytes calldata config) external view returns (uint256);
    function maximumFunding(bytes calldata config) external view returns (uint256);
    function canCommit(
        bytes32 loanId,
        address lender,
        uint256 amount,
        bytes calldata config
    ) external view returns (bool, bytes32 reasonCode);
    function derivePositionRights(
        FundingCommitment calldata commitment,
        bytes calldata config
    ) external view returns (LenderPositionData memory);
}
```

---

## 34. IInterestModel

```solidity
interface IInterestModel is IBasePolicy {
    function currentRate(
        bytes32 loanId,
        uint64 timestamp,
        bytes calldata config
    ) external view returns (uint256 annualRateRay);

    function accrue(
        bytes32 loanId,
        uint256 principal,
        uint64 from,
        uint64 to,
        bytes calldata config
    ) external view returns (uint256 interestAmount);
}
```

Requirements:

- Deterministic rounding.
- Explicit day-count convention.
- Explicit compounding convention.
- Rate floors and caps.
- Stale benchmark behavior.
- No retroactive benchmark substitution.

---

## 35. IRepaymentSchedule

```solidity
interface IRepaymentSchedule is IBasePolicy {
    function obligationAt(
        bytes32 loanId,
        uint64 timestamp,
        bytes calldata config
    ) external view returns (DebtSnapshot memory);

    function allocatePayment(
        DebtSnapshot calldata debt,
        uint256 amount,
        bytes calldata config
    ) external view returns (PaymentAllocation memory);

    function nextDueDate(
        bytes32 loanId,
        uint64 timestamp,
        bytes calldata config
    ) external view returns (uint64);
}
```

---

## 36. ICollateralPolicy

```solidity
interface ICollateralPolicy is IBasePolicy {
    function requiredInitialValue(
        bytes32 loanId,
        uint256 principalValue,
        address borrower,
        bytes calldata config
    ) external view returns (uint256);

    function healthFactor(
        bytes32 loanId,
        DebtSnapshot calldata debt,
        OracleObservation[] calldata prices,
        bytes calldata config
    ) external view returns (uint256 healthFactorRay);

    function canRelease(
        bytes32 loanId,
        bytes32 collateralId,
        DebtSnapshot calldata debt,
        bytes calldata config
    ) external view returns (bool);
}
```

---

## 37. ILiquidationPolicy

```solidity
interface ILiquidationPolicy is IBasePolicy {
    function liquidationEligible(
        bytes32 loanId,
        DebtSnapshot calldata debt,
        OracleObservation[] calldata prices,
        uint64 timestamp,
        bytes calldata config
    ) external view returns (bool eligible, bytes32 reasonCode);

    function maximumLiquidationAmount(
        bytes32 loanId,
        DebtSnapshot calldata debt,
        bytes calldata config
    ) external view returns (uint256);

    function distributeProceeds(
        bytes32 loanId,
        uint256 grossProceeds,
        uint256 executionCosts,
        bytes calldata config
    ) external view returns (bytes memory distributionPlan);
}
```

---

## 38. ISettlementPolicy

```solidity
interface ISettlementPolicy is IBasePolicy {
    function requiredFinality(
        bytes32 assetId,
        bytes32 paymentRail,
        bytes calldata config
    ) external view returns (FinalityClass);

    function validateEvidence(
        PaymentEvidence calldata evidence,
        bytes calldata config
    ) external view returns (bool valid);

    function reversalWindow(
        bytes32 paymentRail,
        bytes calldata config
    ) external view returns (uint64);
}
```

---

## 39. ITransferPolicy

```solidity
interface ITransferPolicy is IBasePolicy {
    function canTransfer(
        bytes32 positionId,
        address from,
        address to,
        uint256 units,
        bytes calldata eligibilityProof,
        bytes calldata config
    ) external view returns (bool, bytes32 reasonCode);
}
```

---

## 40. IRefinancingPolicy

```solidity
interface IRefinancingPolicy is IBasePolicy {
    function payoffQuote(
        bytes32 loanId,
        uint64 settlementTime,
        bytes calldata config
    ) external view returns (uint256 payoffAmount, uint64 quoteExpiry);

    function validateReplacementLoan(
        bytes32 oldLoanId,
        UniversalLoanTerms calldata newTerms,
        bytes calldata config
    ) external view returns (bool, bytes32 reasonCode);
}
```

---

## 41. IInsurancePolicy

```solidity
interface IInsurancePolicy is IBasePolicy {
    function coverageAmount(
        bytes32 loanId,
        bytes32 lossEvent,
        uint256 realizedLoss,
        bytes calldata config
    ) external view returns (uint256);

    function validateClaim(
        bytes32 loanId,
        bytes32 claimId,
        bytes calldata evidence,
        bytes calldata config
    ) external view returns (bool);
}
```

---

# Part VII — Funding, Syndication, and Position Interfaces

## 42. IFundingManager

```solidity
interface IFundingManager {
    function commit(
        bytes32 loanId,
        uint256 amount,
        bytes32 trancheId,
        bytes calldata authorization
    ) external returns (bytes32 commitmentId);

    function withdrawCommitment(bytes32 commitmentId) external;
    function finalizeFunding(bytes32 loanId) external;
    function refund(bytes32 commitmentId) external;
    function fundedAmount(bytes32 loanId) external view returns (uint256);
    function availableToDisburse(bytes32 loanId) external view returns (uint256);
}
```

---

## 43. ISyndicateVault

```solidity
interface ISyndicateVault {
    function loanId() external view returns (bytes32);
    function depositCommitment(bytes32 commitmentId, uint256 amount) external;
    function disburse(address recipient, uint256 amount, bytes32 journalRef) external;
    function receiveRepayment(bytes32 paymentId, uint256 amount) external;
    function claimable(address lender, bytes32 assetId) external view returns (uint256);
    function claim(bytes32 assetId, address recipient) external returns (uint256);
    function totalPositionUnits() external view returns (uint256);
}
```

---

## 44. IPositionManager

```solidity
interface IPositionManager {
    function issuePosition(LenderPositionData calldata position) external;
    function splitPosition(bytes32 positionId, uint256[] calldata units) external returns (bytes32[] memory childIds);
    function mergePositions(bytes32[] calldata positionIds) external returns (bytes32 mergedId);
    function transferPosition(bytes32 positionId, address to, bytes calldata proof) external;
    function pledgePosition(bytes32 positionId, bytes32 encumbranceRef) external;
    function releasePledge(bytes32 positionId, bytes32 encumbranceRef) external;
    function redeemPosition(bytes32 positionId) external;
    function position(bytes32 positionId) external view returns (LenderPositionData memory);
}
```

Position tokenization may use ERC-1155 or another approved representation, but economic-right conservation must remain canonical in `IPositionManager`.

---

# Part VIII — Collateral, Oracle, and Liquidation Interfaces

## 45. ICollateralManager

```solidity
interface ICollateralManager {
    function lockCollateral(
        bytes32 loanId,
        CollateralItem calldata item,
        bytes calldata transferData
    ) external;

    function addCollateral(
        bytes32 loanId,
        CollateralItem calldata item,
        bytes calldata transferData
    ) external;

    function substituteCollateral(
        bytes32 loanId,
        bytes32 existingCollateralId,
        CollateralItem calldata replacement,
        bytes calldata authorization
    ) external;

    function releaseCollateral(
        bytes32 loanId,
        bytes32 collateralId,
        address recipient,
        bytes32 journalRef
    ) external;

    function collateralOf(bytes32 loanId) external view returns (CollateralItem[] memory);
    function controlledValue(bytes32 loanId) external view returns (uint256);
}
```

The manager must verify actual custody before recording collateral as locked.

---

## 46. ICollateralVault

```solidity
interface ICollateralVault {
    function loanId() external view returns (bytes32);
    function depositERC20(address token, address from, uint256 amount) external;
    function depositERC721(address token, address from, uint256 tokenId) external;
    function depositERC1155(address token, address from, uint256 tokenId, uint256 amount, bytes calldata data) external;
    function release(bytes32 collateralId, address recipient) external;
    function transferToLiquidator(bytes32 collateralId, address recipient, uint256 quantity) external;
    function balanceOfAsset(bytes32 assetId) external view returns (uint256);
}
```

The vault must reject unsolicited token callbacks unless explicitly supported.

---

## 47. IOracleRouter

```solidity
interface IOracleRouter {
    function price(
        bytes32 assetId,
        bytes32 quoteAssetId
    ) external view returns (OracleObservation memory);

    function validateObservation(
        OracleObservation calldata observation,
        bytes32 riskContext
    ) external view returns (bool);

    function adapterFor(bytes32 assetId, bytes32 quoteAssetId) external view returns (address);
    function isCircuitBroken(bytes32 assetId) external view returns (bool);
}
```

No user-selected arbitrary oracle may authorize collateral release, borrowing, or liquidation.

---

## 48. ILiquidationEngine

```solidity
interface ILiquidationEngine {
    function startLiquidation(
        bytes32 loanId,
        bytes32 methodId,
        bytes calldata evidence
    ) external returns (bytes32 liquidationId);

    function executePartial(
        bytes32 liquidationId,
        bytes32 collateralId,
        uint256 quantity,
        bytes calldata executionData
    ) external;

    function finalizeLiquidation(
        bytes32 liquidationId,
        uint256 grossProceeds,
        uint256 executionCosts,
        bytes32 journalRef
    ) external;

    function liquidationStatus(bytes32 liquidationId) external view returns (uint8);
}
```

---

## 49. IAuctionAdapter

```solidity
interface IAuctionAdapter {
    function createAuction(
        bytes32 liquidationId,
        CollateralItem calldata item,
        bytes calldata auctionConfig
    ) external returns (bytes32 auctionId);

    function settleAuction(bytes32 auctionId) external returns (
        bytes32 settlementAssetId,
        uint256 grossProceeds,
        address buyer
    );

    function cancelAuction(bytes32 auctionId, bytes calldata authorityProof) external;
    function auctionState(bytes32 auctionId) external view returns (uint8);
}
```

---

# Part IX — Payment, Fiat, Card, and Accounting Interfaces

## 50. IPaymentRouter

```solidity
interface IPaymentRouter {
    function initiatePayment(
        bytes32 loanId,
        bytes32 railId,
        bytes32 assetId,
        uint256 amount,
        address payer,
        bytes calldata railData
    ) external returns (bytes32 paymentId);

    function submitEvidence(PaymentEvidence calldata evidence, bytes calldata providerSignature) external;
    function finalizePayment(bytes32 paymentId) external;
    function reversePayment(bytes32 paymentId, bytes32 reasonCode, bytes calldata evidence) external;
    function paymentEvidence(bytes32 paymentId) external view returns (PaymentEvidence memory);
}
```

---

## 51. IPaymentAdapter

```solidity
interface IPaymentAdapter {
    function adapterId() external pure returns (bytes32);
    function supportedRail() external pure returns (bytes32);
    function initiate(bytes calldata instruction) external returns (bytes32 externalReference);
    function verifyCallback(bytes calldata callbackData, bytes calldata signature) external view returns (PaymentEvidence memory);
    function queryStatus(bytes32 externalReference) external view returns (PaymentEvidence memory);
    function supportsReversal() external pure returns (bool);
}
```

Adapters must not directly mutate loan balances.

---

## 52. IFiatSettlementAdapter

```solidity
interface IFiatSettlementAdapter is IPaymentAdapter {
    function supportedCurrency(bytes32 currencyId) external view returns (bool);
    function settlementAccountHash(bytes32 currencyId) external view returns (bytes32);
    function reconciliationCutoff(bytes32 currencyId) external view returns (uint64);
}
```

Raw bank-account details must not be emitted publicly.

---

## 53. ICardSettlementAdapter

```solidity
interface ICardSettlementAdapter is IPaymentAdapter {
    function chargebackWindow(bytes32 merchantProgramId) external view returns (uint64);
    function reserveRequirement(bytes32 merchantProgramId) external view returns (uint16 basisPoints);
    function processorSettlementStatus(bytes32 externalReference) external view returns (uint8);
}
```

Collateral release must not rely on card authorization alone.

---

## 54. IAccountingBridge

```solidity
interface IAccountingBridge {
    function requestJournal(
        bytes32 operationId,
        bytes32 journalType,
        bytes calldata accountingPayload
    ) external returns (bytes32 journalRef);

    function confirmJournal(
        bytes32 operationId,
        bytes32 journalRef,
        bytes32 entryHash,
        bytes calldata attestation
    ) external;

    function journalStatus(bytes32 operationId) external view returns (uint8);
}
```

The accounting bridge records references and attestations. It must not attempt to reproduce the complete off-chain ledger on-chain.

---

# Part X — Refinancing, Restructuring, Insurance, and Recovery

## 55. IRefinanceCoordinator

```solidity
interface IRefinanceCoordinator {
    function requestRefinance(
        bytes32 oldLoanId,
        UniversalLoanTerms calldata proposedTerms,
        bytes32 proposedPolicySetHash
    ) external returns (bytes32 refinanceId);

    function lockNewFunding(bytes32 refinanceId, uint256 amount) external;
    function executeRefinance(bytes32 refinanceId, bytes calldata settlementBundle) external;
    function cancelRefinance(bytes32 refinanceId) external;
    function refinanceState(bytes32 refinanceId) external view returns (uint8);
}
```

Execution must be atomic where possible and compensating where external settlement prevents atomicity.

---

## 56. IRestructuringController

```solidity
interface IRestructuringController {
    function proposeRestructure(
        bytes32 loanId,
        bytes32 amendedTermsHash,
        bytes32 disclosureHash,
        uint64 expiry
    ) external returns (bytes32 restructureId);

    function voteLenderPosition(
        bytes32 restructureId,
        bytes32 positionId,
        bool support,
        bytes calldata authorization
    ) external;

    function acceptBorrower(bytes32 restructureId, bytes calldata signature) external;
    function executeRestructure(bytes32 restructureId) external;
}
```

Required consent thresholds are defined by the original loan agreement.

---

## 57. IInsuranceManager

```solidity
interface IInsuranceManager {
    function bindCoverage(
        bytes32 loanId,
        bytes32 policyId,
        uint256 coverageLimit,
        uint64 expiry
    ) external returns (bytes32 coverageId);

    function submitClaim(
        bytes32 coverageId,
        bytes32 lossEvent,
        uint256 requestedAmount,
        bytes calldata evidence
    ) external returns (bytes32 claimId);

    function approveClaim(bytes32 claimId, uint256 approvedAmount) external;
    function payClaim(bytes32 claimId, address recipient, bytes32 journalRef) external;
    function recordRecovery(bytes32 claimId, uint256 amount, bytes32 journalRef) external;
}
```

Claims cannot exceed funded reserves and contractual coverage.

---

## 58. IRecoveryManager

```solidity
interface IRecoveryManager {
    function openRecovery(bytes32 loanId, bytes32 recoveryType, bytes32 evidenceHash) external returns (bytes32 recoveryId);
    function recordRecoveryProceeds(bytes32 recoveryId, bytes32 assetId, uint256 amount, bytes32 journalRef) external;
    function distributeRecovery(bytes32 recoveryId) external;
    function closeRecovery(bytes32 recoveryId) external;
}
```

---

# Part XI — Identity, Credentials, and Underwriting Interfaces

## 59. IIdentityAttestationRegistry

```solidity
interface IIdentityAttestationRegistry {
    function registerAttester(bytes32 attesterId, address attester, bytes32 capabilityHash, uint64 expiry) external;
    function revokeAttester(bytes32 attesterId, bytes32 reasonCode) external;
    function validateCredential(
        address subject,
        bytes32 credentialType,
        bytes calldata proof
    ) external view returns (bool valid, uint64 validUntil, bytes32 attesterId);
}
```

No raw identity document should be stored in this registry.

---

## 60. ICreditDecisionRegistry

```solidity
interface ICreditDecisionRegistry {
    function registerDecision(
        bytes32 decisionId,
        address borrower,
        bytes32 policyId,
        bytes32 modelVersionHash,
        uint256 exposureLimit,
        uint64 validUntil,
        bytes calldata attestation
    ) external;

    function consumeExposure(bytes32 decisionId, bytes32 loanId, uint256 amount) external;
    function releaseExposure(bytes32 decisionId, bytes32 loanId, uint256 amount) external;
    function remainingExposure(bytes32 decisionId) external view returns (uint256);
    function isValid(bytes32 decisionId) external view returns (bool);
}
```

---

## 61. IUnderwritingAdapter

```solidity
interface IUnderwritingAdapter {
    function adapterId() external pure returns (bytes32);
    function requestDecision(bytes calldata applicationPayload) external returns (bytes32 requestId);
    function verifyDecision(bytes calldata decisionPayload, bytes calldata signature) external view returns (
        bytes32 decisionId,
        address borrower,
        uint256 exposureLimit,
        uint64 validUntil,
        bytes32 modelVersionHash
    );
}
```

Automated decisions must remain attributable to a policy and model version.

---

# Part XII — UFT Interfaces

## 62. IUnifiedToken

```solidity
interface IUnifiedToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function MAX_SUPPLY() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function burn(uint256 amount) external;
}
```

There must be no callable post-genesis mint interface.

---

## 63. IUFTBurner

```solidity
interface IUFTBurner {
    function burnFromRevenue(uint256 amount, bytes32 revenueEpoch, bytes32 journalRef) external;
    function cumulativeBurned() external view returns (uint256);
}
```

The burner may burn only UFT already controlled by the burner or explicitly approved for burning.

---

## 64. IUFTStakingVault

```solidity
interface IUFTStakingVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function requestWithdraw(uint256 shares, address receiver) external returns (bytes32 requestId);
    function claimWithdraw(bytes32 requestId) external returns (uint256 assets);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function slash(uint256 amount, bytes32 incidentId, bytes32 authorityProof) external;
    function pendingWithdrawals() external view returns (uint256);
}
```

Staking shares must remain backed by accounted vault assets after rewards and losses.

---

## 65. IVoteEscrowUFT

```solidity
interface IVoteEscrowUFT {
    function createLock(uint256 amount, uint64 unlockTime, address delegatee) external returns (bytes32 lockId);
    function increaseAmount(bytes32 lockId, uint256 amount) external;
    function extendLock(bytes32 lockId, uint64 newUnlockTime) external;
    function delegate(bytes32 lockId, address delegatee) external;
    function withdraw(bytes32 lockId) external;
    function votingPowerAt(address account, uint256 timepoint) external view returns (uint256);
    function totalVotingPowerAt(uint256 timepoint) external view returns (uint256);
}
```

Locked collateral and bridge backing cannot simultaneously create voting power.

---

## 66. IProtocolFeeRouter

```solidity
interface IProtocolFeeRouter {
    struct RevenueSplit {
        uint16 insuranceBps;
        uint16 stakerBps;
        uint16 treasuryBps;
        uint16 burnBps;
        uint16 liquidityBps;
        uint16 publicGoodsBps;
    }

    function collectFee(bytes32 sourceId, bytes32 assetId, uint256 amount, bytes32 journalRef) external;
    function distribute(bytes32 assetId, uint256 amount) external;
    function revenueSplit() external view returns (RevenueSplit memory);
    function setRevenueSplit(RevenueSplit calldata split) external;
    function burnSuspended() external view returns (bool);
}
```

The split must equal 10,000 basis points. Burn allocation must suspend under defined reserve-deficiency conditions.

---

## 67. IUFTBridgeHub

```solidity
interface IUFTBridgeHub {
    function lockForBridge(uint256 destinationChainId, uint256 amount, address recipient) external returns (bytes32 messageId);
    function releaseFromBridge(bytes32 messageId, address recipient, uint256 amount, bytes calldata proof) external;
    function reconcileSatelliteBurn(uint256 sourceChainId, uint256 amount, bytes32 messageId, bytes calldata proof) external;
    function backingForChain(uint256 chainId) external view returns (uint256);
    function totalBridgeBacking() external view returns (uint256);
}
```

---

# Part XIII — Governance, Roles, Treasury, and Emergency Interfaces

## 68. Canonical roles

```solidity
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
bytes32 constant GOVERNANCE_EXECUTOR_ROLE = keccak256("GOVERNANCE_EXECUTOR_ROLE");
bytes32 constant POLICY_REGISTRAR_ROLE = keccak256("POLICY_REGISTRAR_ROLE");
bytes32 constant ASSET_REGISTRAR_ROLE = keccak256("ASSET_REGISTRAR_ROLE");
bytes32 constant LOAN_FACTORY_ROLE = keccak256("LOAN_FACTORY_ROLE");
bytes32 constant SERVICER_ROLE = keccak256("SERVICER_ROLE");
bytes32 constant PAYMENT_FINALIZER_ROLE = keccak256("PAYMENT_FINALIZER_ROLE");
bytes32 constant ACCOUNTING_ATTESTER_ROLE = keccak256("ACCOUNTING_ATTESTER_ROLE");
bytes32 constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
bytes32 constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");
bytes32 constant TREASURY_OPERATOR_ROLE = keccak256("TREASURY_OPERATOR_ROLE");
bytes32 constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE");
bytes32 constant EMERGENCY_COUNCIL_ROLE = keccak256("EMERGENCY_COUNCIL_ROLE");
bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
```

No single operational key should hold all roles.

---

## 69. IRoleManager

```solidity
interface IRoleManager {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account, uint64 expiry) external;
    function revokeRole(bytes32 role, address account) external;
    function roleExpiry(bytes32 role, address account) external view returns (uint64);
    function roleAdmin(bytes32 role) external view returns (bytes32);
}
```

Time-bounded roles should be preferred for operational and emergency authority.

---

## 70. IUnifiedGovernor

```solidity
interface IUnifiedGovernor {
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash,
        uint8 proposalClass
    ) external returns (uint256 proposalId);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256 weight);
    function queue(uint256 proposalId) external;
    function execute(uint256 proposalId) external payable;
    function cancel(uint256 proposalId) external;
    function state(uint256 proposalId) external view returns (uint8);
}
```

The governor must enforce proposal-class thresholds, snapshot voting, quorum, approval ratio, and timelock rules.

---

## 71. ITimelockExecutor

```solidity
interface ITimelockExecutor {
    function schedule(bytes32 operationId, address target, uint256 value, bytes calldata data, uint64 delay) external;
    function execute(bytes32 operationId, address target, uint256 value, bytes calldata data) external payable;
    function cancel(bytes32 operationId) external;
    function readyAt(bytes32 operationId) external view returns (uint64);
}
```

Execution payload hashes must match the queued proposal exactly.

---

## 72. IEmergencyController

```solidity
interface IEmergencyController {
    function pauseCapability(bytes32 capability, uint64 expiry, bytes32 reasonCode) external;
    function disableAdapter(bytes32 adapterId, uint64 expiry, bytes32 reasonCode) external;
    function setOracleCircuitBreaker(bytes32 assetId, bool active, uint64 expiry) external;
    function emergencyState(bytes32 capability) external view returns (bool active, uint64 expiry, bytes32 reasonCode);
    function clearExpiredAction(bytes32 actionId) external;
}
```

Emergency powers cannot:

- Mint UFT.
- Transfer arbitrary user assets.
- Change active-loan economics.
- Edit posted accounting records.
- Create unbacked bridge representations.
- Block valid repayment longer than technically necessary.

---

## 73. IUnifiedTreasury

```solidity
interface IUnifiedTreasury {
    function mandateBalance(bytes32 mandateId, bytes32 assetId) external view returns (uint256);
    function transferUnderMandate(
        bytes32 mandateId,
        bytes32 assetId,
        address recipient,
        uint256 amount,
        bytes32 journalRef
    ) external;
    function reserveCoverage(bytes32 reserveId) external view returns (uint256 assets, uint256 liabilities);
}
```

Restricted reserves cannot be spent through general treasury mandates.

---

# Part XIV — Cross-Chain Interfaces

## 74. ICrossChainCoordinator

```solidity
interface ICrossChainCoordinator {
    function sendMessage(
        uint256 destinationChainId,
        bytes32 loanId,
        bytes32 actionType,
        bytes calldata payload
    ) external returns (bytes32 messageId);

    function receiveMessage(
        uint256 sourceChainId,
        bytes32 messageId,
        bytes32 loanId,
        bytes32 actionType,
        bytes calldata payload,
        bytes calldata proof
    ) external;

    function retryMessage(bytes32 messageId) external;
    function markTimedOut(bytes32 messageId) external;
    function messageState(bytes32 messageId) external view returns (uint8);
}
```

---

## 75. ICrossChainAdapter

```solidity
interface ICrossChainAdapter {
    function adapterId() external pure returns (bytes32);
    function send(uint256 destinationChainId, bytes calldata payload) external payable returns (bytes32 providerMessageId);
    function verify(
        uint256 sourceChainId,
        bytes32 providerMessageId,
        bytes calldata payload,
        bytes calldata proof
    ) external view returns (bool);
    function finalityDelay(uint256 chainId) external view returns (uint64);
}
```

---

## 76. ISatelliteLoanComponent

```solidity
interface ISatelliteLoanComponent {
    function canonicalChainId() external view returns (uint256);
    function canonicalLoanId() external view returns (bytes32);
    function executeCanonicalInstruction(bytes32 messageId, bytes32 actionType, bytes calldata payload) external;
    function reportState() external returns (bytes32 messageId);
}
```

Satellite contracts cannot independently change canonical economics.

---

# Part XV — Asset and Adapter Registries

## 77. IAssetRegistry

```solidity
interface IAssetRegistry {
    function registerAsset(AssetDescriptor calldata asset, bytes32 riskClass, bool borrowable, bool collateralEligible) external;
    function updateAssetStatus(bytes32 assetId, bool borrowable, bool collateralEligible) external;
    function asset(bytes32 assetId) external view returns (AssetDescriptor memory);
    function isBorrowable(bytes32 assetId) external view returns (bool);
    function isCollateralEligible(bytes32 assetId) external view returns (bool);
    function riskClass(bytes32 assetId) external view returns (bytes32);
}
```

Delisting affects new originations unless the active agreement already defines emergency behavior.

---

## 78. IAdapterRegistry

```solidity
interface IAdapterRegistry {
    function registerAdapter(bytes32 adapterId, address adapter, bytes32 capabilityHash, uint32 version) external;
    function disableAdapter(bytes32 adapterId) external;
    function adapter(bytes32 adapterId) external view returns (address);
    function isEnabled(bytes32 adapterId) external view returns (bool);
    function capabilityHash(bytes32 adapterId) external view returns (bytes32);
}
```

---

# Part XVI — Protocol API for Off-Chain Services

## 79. API design rules

Off-chain APIs must:

- Treat on-chain state as canonical where designated.
- Expose explicit finality and authority fields.
- Use idempotency keys for every write.
- Support deterministic pagination.
- Preserve event ordering.
- Return machine-readable reason codes.
- Never expose secret credentials or raw restricted identity data.
- Maintain versioned schemas.
- Include correlation IDs.
- Distinguish command acceptance from completion.

---

## 80. Command envelope

```json
{
  "command_id": "cmd_...",
  "idempotency_key": "...",
  "command_type": "FINALIZE_PAYMENT",
  "aggregate_type": "LOAN",
  "aggregate_id": "loan_...",
  "expected_version": 42,
  "actor": {
    "type": "WALLET",
    "id": "0x..."
  },
  "payload": {},
  "submitted_at": "RFC3339 timestamp",
  "signature": "optional detached signature"
}
```

---

## 81. Command response

```json
{
  "command_id": "cmd_...",
  "status": "ACCEPTED",
  "aggregate_id": "loan_...",
  "aggregate_version": 43,
  "operation_id": "op_...",
  "finality": "PENDING",
  "reason_code": null,
  "links": {
    "operation": "/v1/operations/op_..."
  }
}
```

`ACCEPTED` does not mean economically final.

---

## 82. Event envelope

```json
{
  "event_id": "evt_...",
  "event_type": "PaymentFinalized",
  "aggregate_type": "LOAN",
  "aggregate_id": "loan_...",
  "aggregate_version": 44,
  "authority_class": "ONCHAIN_HOME",
  "source_chain_id": 1,
  "source_contract": "0x...",
  "source_transaction": "0x...",
  "block_number": 123,
  "block_hash": "0x...",
  "finality": "FINAL",
  "payload": {},
  "observed_at": "RFC3339 timestamp"
}
```

---

## 83. Required service APIs

### Marketplace API

```text
POST   /v1/tenders
GET    /v1/tenders/{tender_id}
POST   /v1/tenders/{tender_id}/cancel
GET    /v1/tenders
POST   /v1/offers
GET    /v1/offers/{offer_id}
POST   /v1/offers/{offer_id}/cancel
POST   /v1/offers/{offer_id}/accept
```

### Loan API

```text
GET    /v1/loans/{loan_id}
GET    /v1/loans/{loan_id}/state
GET    /v1/loans/{loan_id}/debt
GET    /v1/loans/{loan_id}/schedule
GET    /v1/loans/{loan_id}/positions
POST   /v1/loans/{loan_id}/repayment-intents
POST   /v1/loans/{loan_id}/amendments
POST   /v1/loans/{loan_id}/refinance-requests
POST   /v1/loans/{loan_id}/restructure-requests
```

### Payment API

```text
POST   /v1/payments
GET    /v1/payments/{payment_id}
POST   /v1/payments/{payment_id}/evidence
POST   /v1/payments/{payment_id}/finalize
POST   /v1/payments/{payment_id}/reverse
GET    /v1/payments/{payment_id}/allocations
```

### Collateral API

```text
GET    /v1/loans/{loan_id}/collateral
POST   /v1/loans/{loan_id}/collateral-intents
POST   /v1/loans/{loan_id}/collateral-substitutions
GET    /v1/loans/{loan_id}/health
GET    /v1/liquidations/{liquidation_id}
```

### Identity and underwriting API

```text
POST   /v1/identity/verification-sessions
GET    /v1/credentials/{credential_id}
POST   /v1/credit/applications
GET    /v1/credit/decisions/{decision_id}
GET    /v1/credit/exposure/{party_id}
```

### UFT API

```text
GET    /v1/uft/supply
GET    /v1/uft/allocations
GET    /v1/uft/burns
GET    /v1/uft/staking
POST   /v1/uft/staking/deposit-intents
POST   /v1/uft/staking/withdrawal-requests
GET    /v1/uft/bridge-backing
GET    /v1/governance/proposals
```

### Accounting and reconciliation API

```text
POST   /v1/accounting/journal-requests
GET    /v1/accounting/journals/{journal_ref}
GET    /v1/reconciliation/runs/{run_id}
GET    /v1/reconciliation/exceptions
POST   /v1/reconciliation/exceptions/{exception_id}/resolve
```

---

# Part XVII — Versioning and Compatibility

## 84. Semantic versioning

Every policy, adapter, implementation, and API schema must carry:

```text
MAJOR.MINOR.PATCH
```

- `MAJOR`: Breaking behavioral or storage change.
- `MINOR`: Backward-compatible capability addition.
- `PATCH`: Backward-compatible correction that does not alter active agreement economics.

---

## 85. Active-loan version binding

At activation, every loan binds to:

- Protocol version.
- Loan implementation version.
- Policy implementation addresses.
- Policy semantic versions.
- Configuration hashes.
- Adapter requirements where contractual.
- Agreement hash.

A registry update cannot change these references.

---

## 86. Upgradeable and immutable components

### Recommended immutable components

- Canonical UFT token.
- Genesis allocation roots.
- Permanent burner constraints.
- Offer hashing domain constants.
- Constitutional authority boundaries.

### Versioned deploy-new components

- Loan-account implementations.
- Policy modules.
- Payment adapters.
- Oracle adapters.
- Bridge adapters.
- Auction adapters.
- Underwriting adapters.

### Carefully upgradeable components

- Registries.
- Routers.
- Index-compatible governance components.
- Non-economic operational coordinators.

Upgradeability must not create an indirect path to alter active loan terms.

---

## 87. Storage layout rules

Upgradeable contracts must:

- Use namespaced storage or an equivalent collision-resistant pattern.
- Reserve explicit storage gaps where relevant.
- Never reorder or change existing storage types.
- Append new fields only.
- Run automated storage-layout diffing.
- Bind implementation code hashes.
- Require governance and timelock approval.
- Pass migration and rollback simulation.

---

## 88. Interface compatibility

Contracts should expose ERC-165 interface detection where appropriate.

A new implementation is compatible only when:

- Required selectors remain available.
- Return semantics remain equivalent.
- Events required by indexers remain emitted.
- Custom error meanings remain stable.
- State invariants remain preserved.
- Gas changes do not create denial-of-service risk.

---

## 89. Deprecation

Deprecation lifecycle:

```text
ACTIVE
→ DISCOURAGED
→ DEPRECATED_FOR_NEW_BINDINGS
→ DISABLED_FOR_NEW_BINDINGS
→ ARCHIVED
```

Deprecation must not strand active loans. Required adapters must remain available or receive a contractually permitted migration path.

---

# Part XVIII — Security and Implementation Requirements

## 90. Reentrancy

Asset-moving entry points must use checks-effects-interactions, reentrancy guards where appropriate, and pull-based claims.

## 91. Token compatibility

Asset adapters must handle or reject:

- Fee-on-transfer tokens.
- Rebasing tokens.
- Tokens returning no boolean.
- Tokens with callbacks.
- Blacklistable tokens.
- Pausable tokens.
- Upgradeable tokens.
- ERC-777-style hooks.
- Nonstandard decimals.

No asset is supported merely because it implements an ERC interface.

## 92. Signature safety

Every signature must bind:

- Chain ID.
- Verifying contract.
- Action type.
- Signer.
- Nonce.
- Expiry.
- Relevant entity ID.
- Asset and amount.
- Policy or terms hash.

## 93. External-call isolation

Untrusted adapters must not receive unrestricted delegatecall access to kernel storage.

## 94. Gas-bounded iteration

Core state changes must not require iterating over an unbounded number of lenders, installments, collateral items, votes, or messages.

## 95. Denial-of-service resistance

One recipient’s failed transfer must not block unrelated claimants. Claimable balances should be isolated.

## 96. Emergency repayment

Pause controls should block new risk creation while preserving safe repayment, debt reduction, and collateral release after valid final settlement.

## 97. Event and storage consistency

Events must be emitted after successful state mutation and must match stored values.

## 98. Idempotency

Every payment callback, bridge message, accounting confirmation, liquidation finalization, and recovery operation requires a unique operation ID and consumed marker.

---

# Part XIX — Formal Verification Mapping

## 99. Interface-to-invariant matrix

| Interface | Primary invariant families |
|---|---|
| `IUnifiedToken` | INV-SUP, INV-AUTH |
| `IUFTBridgeHub` | INV-SUP, INV-BRG |
| `ILoanFactory` | INV-LOAN, INV-AUTH |
| `IUnifiedLoan` | INV-LOAN, INV-INT, INV-PAY |
| `IFundingManager` | INV-FUND |
| `IPositionManager` | INV-FUND, INV-AUTH |
| `ICollateralManager` | INV-COL |
| `IOracleRouter` | INV-ORC |
| `ILiquidationEngine` | INV-LIQ, INV-COL |
| `IPaymentRouter` | INV-PAY, INV-ACC |
| `IAccountingBridge` | INV-ACC |
| `IRefinanceCoordinator` | INV-REFI, INV-COL |
| `IInsuranceManager` | INV-INS, INV-ACC |
| `IUnifiedGovernor` | INV-GOV, INV-AUTH |
| `IEmergencyController` | INV-GOV, REC-* |
| `IUFTStakingVault` | INV-STK, INV-SUP |
| `ICrossChainCoordinator` | INV-BRG, REC-* |

---

## 100. Mandatory executable properties

Each implementation package must include assertions for:

1. No duplicate loan ID.
2. No duplicate offer consumption.
3. No duplicate payment allocation.
4. No duplicate bridge execution.
5. No lender-right overissuance.
6. No collateral release with unpaid secured debt.
7. No terminal-state reactivation.
8. No active agreement mutation.
9. No post-genesis UFT minting.
10. No wrapped-UFT overissuance.
11. No unfunded reward distribution.
12. No governance timelock bypass.
13. No unauthorized treasury movement.
14. No unbalanced accounting reference confirmation.
15. No invalid oracle-authorized liquidation.
16. No refinancing double lien.
17. No provisional-payment final release.
18. No role use after expiry.
19. No policy substitution after activation.
20. No hidden generic asset-transfer authority.

---

# Part XX — Deployment and Registration Gates

## 101. Contract registration gate

A contract cannot enter an approved registry until it has:

- Source-code review.
- Compiler reproducibility.
- Verified bytecode and code hash.
- Unit tests.
- Stateful fuzz tests.
- Invariant tests.
- Static analysis.
- Storage-layout review where applicable.
- Threat-model mapping.
- Independent audit for critical contracts.
- Governance approval.
- Timelock completion.

---

## 102. Adapter registration gate

An adapter must additionally document:

- External trust assumptions.
- Authentication mechanism.
- Finality model.
- Reversal behavior.
- Rate limits.
- Failure modes.
- Recovery procedure.
- Maximum exposure.
- Monitoring signals.
- Disable procedure.

---

## 103. Loan implementation gate

A loan implementation must prove:

- Immutable agreement binding.
- Valid state-transition graph.
- Debt reproducibility.
- Repayment liveness.
- Correct terminal closure.
- Collateral safety.
- Payment-finality correctness.
- Position-right conservation.
- Upgrade isolation.
- Event completeness.

---

# Part XXI — Recommended Package Layout

## 104. Solidity repository structure

```text
protocol/
├── src/
│   ├── kernel/
│   │   ├── UnifiedProtocol.sol
│   │   ├── LoanFactory.sol
│   │   ├── LoanRegistry.sol
│   │   └── PolicyRegistry.sol
│   ├── loan/
│   │   ├── UnifiedLoan.sol
│   │   ├── LoanAmendmentController.sol
│   │   └── LoanStorage.sol
│   ├── marketplace/
│   │   ├── TenderRegistry.sol
│   │   └── OfferManager.sol
│   ├── funding/
│   │   ├── FundingManager.sol
│   │   ├── SyndicateVault.sol
│   │   └── PositionManager.sol
│   ├── collateral/
│   │   ├── CollateralManager.sol
│   │   ├── CollateralVault.sol
│   │   └── LiquidationEngine.sol
│   ├── payment/
│   │   ├── PaymentRouter.sol
│   │   └── AccountingBridge.sol
│   ├── refinancing/
│   │   ├── RefinanceCoordinator.sol
│   │   └── RestructuringController.sol
│   ├── insurance/
│   │   ├── InsuranceManager.sol
│   │   └── RecoveryManager.sol
│   ├── identity/
│   │   ├── IdentityAttestationRegistry.sol
│   │   └── CreditDecisionRegistry.sol
│   ├── uft/
│   │   ├── UnifiedToken.sol
│   │   ├── UFTBurner.sol
│   │   ├── UFTStakingVault.sol
│   │   ├── VoteEscrowUFT.sol
│   │   └── UFTBridgeHub.sol
│   ├── governance/
│   │   ├── UnifiedGovernor.sol
│   │   ├── TimelockExecutor.sol
│   │   ├── EmergencyController.sol
│   │   └── UnifiedTreasury.sol
│   ├── crosschain/
│   │   ├── CrossChainCoordinator.sol
│   │   └── SatelliteLoanComponent.sol
│   ├── policies/
│   │   ├── identity/
│   │   ├── credit/
│   │   ├── funding/
│   │   ├── interest/
│   │   ├── repayment/
│   │   ├── collateral/
│   │   ├── liquidation/
│   │   ├── settlement/
│   │   ├── transfer/
│   │   ├── refinancing/
│   │   └── insurance/
│   ├── adapters/
│   │   ├── oracle/
│   │   ├── bridge/
│   │   ├── payment/
│   │   ├── auction/
│   │   ├── identity/
│   │   └── underwriting/
│   ├── interfaces/
│   ├── libraries/
│   ├── types/
│   └── errors/
├── test/
│   ├── unit/
│   ├── integration/
│   ├── invariant/
│   ├── fuzz/
│   ├── fork/
│   └── adversarial/
├── script/
└── formal/
```

---

# Part XXII — Architecture Decisions Locked by This Specification

## 105. Locked decisions

1. Unified uses a small kernel and replaceable modules.
2. Active loans bind to immutable versions.
3. Generic setters are prohibited on active loan economics.
4. Policy modules are versioned and registry-approved.
5. Adapters cannot directly mutate loan balances.
6. Payment finality precedes final debt reduction.
7. Accounting references are linked to material operations.
8. Position rights are centrally conserved.
9. Collateral custody must be proven before recognition.
10. UFT has no post-genesis mint interface.
11. Wrapped UFT remains fully backed.
12. Governance execution is timelocked.
13. Emergency roles are bounded and expiring.
14. Cross-chain satellites cannot alter canonical economics.
15. External callbacks are authenticated and idempotent.
16. Every implementation maps to formal invariant families.
17. Registries preserve active-loan continuity during deprecation.
18. Restricted treasury reserves remain mandate-separated.
19. APIs expose explicit authority and finality.
20. Command acceptance is not represented as completion.

---

# Part XXIII — Remaining Implementation Decisions

## 106. Decisions deferred to implementation ADRs

The following require dedicated architecture decision records:

- EVM target chains and canonical home chain.
- Proxy pattern, if any, for registries and routers.
- Loan-account deployment strategy: clone, beacon, or immutable instance.
- Position representation: ERC-1155, ERC-721, or internal ledger.
- Staking-vault standard and asynchronous withdrawal implementation.
- Governance framework implementation.
- Oracle aggregation algorithm.
- Cross-chain messaging providers.
- Fiat and card providers.
- Identity credential and zero-knowledge proof standards.
- Off-chain accounting attestation mechanism.
- Event-indexing and reorganization policy.
- Smart-account and gas-sponsorship architecture.
- Supported token behavior matrix.
- Auction implementation strategies.
- Formal verification tools and proof languages.

Each ADR must preserve this specification’s interface and invariant obligations.

---

# Part XXIV — Completion Criteria

## 107. Specification completion checklist

This interface specification is implementation-ready when:

- Every canonical entity maps to an interface or explicit off-chain authority.
- Every state transition has one authorized entry point.
- Every asset movement has an event and accounting reference.
- Every external integration has an adapter boundary.
- Every privileged operation maps to a bounded role.
- Every active-loan field is classified as immutable or amendable.
- Every contract maps to formal invariants.
- Every interface has semantic-version rules.
- Every module has a failure and recovery path.
- Every launch-critical contract has a test and audit gate.

---

# Appendix A — Minimal End-to-End Origination Call Flow

```text
1. Borrower registers tender metadata hash.
2. Lender signs a typed offer.
3. Borrower accepts the offer.
4. OfferManager verifies and consumes the nonce.
5. CreditDecisionRegistry validates available exposure.
6. FundingManager locks single or syndicated funding.
7. CollateralManager verifies and locks required collateral.
8. LoanFactory resolves approved implementation and policies.
9. LoanFactory deploys and registers the loan account.
10. AccountingBridge requests origination journal references.
11. Loan account verifies activation readiness.
12. Principal is disbursed or external settlement begins.
13. Finality policy confirms completion.
14. Loan activates and emits canonical events.
15. Indexers, accounting, notifications, and monitoring consume events.
```

---

# Appendix B — Minimal Repayment Call Flow

```text
1. Borrower initiates payment through PaymentRouter.
2. Payment adapter returns an external or on-chain reference.
3. Payment evidence is observed.
4. Settlement policy determines finality requirements.
5. Payment becomes final.
6. Loan computes debt snapshot.
7. Repayment schedule allocates payment.
8. Lender and reserve claims are credited.
9. Accounting journal is posted and linked.
10. Loan balances update once.
11. If fully repaid, collateral release becomes eligible.
12. CollateralManager releases collateral.
13. Loan closes after all rights and balances reconcile.
```

---

# Appendix C — Minimal Cross-Chain Collateral Flow

```text
1. Home-chain loan requests remote collateral lock.
2. CrossChainCoordinator creates domain-bound message.
3. Approved adapter transmits message.
4. Satellite component verifies canonical source.
5. Satellite vault locks collateral.
6. Satellite emits and transmits custody confirmation.
7. Home coordinator verifies confirmation and finality.
8. Home loan records remote collateral readiness.
9. Duplicate confirmations are rejected.
10. Release or liquidation uses the same canonical instruction path.
```

---

# Appendix D — Prohibited Interface Patterns

The following patterns are prohibited:

```solidity
function setLoanTerms(bytes32 loanId, bytes calldata arbitraryTerms) external;
function adminWithdrawAnyToken(address token, address from, address to, uint256 amount) external;
function mintUFT(address to, uint256 amount) external;
function setBorrower(bytes32 loanId, address borrower) external;
function setOutstandingDebt(bytes32 loanId, uint256 amount) external;
function markPaymentFinal(bytes32 paymentId) external; // without evidence and bounded authority
function executeBridgePayload(bytes calldata payload) external; // without source/message binding
function upgradeActiveLoan(bytes32 loanId, address implementation) external;
function editPostedJournal(bytes32 journalRef, bytes calldata replacement) external;
```

---

# Appendix E — Next Required Specification

The next foundation should be the **Unified On-Chain/Off-Chain Data Architecture and Event Contract Specification v0.1**.

It should define:

- Canonical storage location for every field.
- Database schemas and ownership boundaries.
- Event schemas and indexing projections.
- Chain-reorganization behavior.
- Command and event buses.
- Idempotency and deduplication.
- Privacy and encryption boundaries.
- Data-retention rules.
- Audit and reconciliation pipelines.
- API projections and read models.
- Cross-chain and provider-event normalization.
- Disaster recovery and data restoration.

