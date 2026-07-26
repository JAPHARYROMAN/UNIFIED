// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPayoffQuoteEngineV2 } from "../src/interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { PayoffQuoteEngine } from "../src/resolution/PayoffQuoteEngine.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";
import {
    Phase9PayoffCoordinatorProxy,
    Phase9PayoffMalformedPolicySource,
    Phase9PayoffMockAccount,
    Phase9PayoffMockFactory,
    Phase9PayoffMockPolicySource,
    Phase9PayoffMockPositionManager,
    Phase9PayoffMockRegistry,
    Phase9PayoffReference,
    Phase9PayoffUnauthorizedCaller,
    Phase9PayoffVm,
    Phase9PayoffWrongRuntimeToken
} from "./Phase9PayoffQuoteHarness.sol";

contract Phase9PayoffQuoteIdHarness is PayoffQuoteEngine {
    bool private _forced;
    bytes32 private _forcedQuoteId;

    constructor(
        Phase9PayoffMockRegistry registry_,
        address policy_,
        uint64 maximumValidity_,
        address factory_,
        address coordinator_
    ) PayoffQuoteEngine(registry_, policy_, maximumValidity_, factory_, coordinator_) { }

    function forceQuoteId(bytes32 quoteId_) external {
        _forced = true;
        _forcedQuoteId = quoteId_;
    }

    function _deriveQuoteId(PayoffQuoteV2 memory quote_) internal view override returns (bytes32) {
        if (_forced) return _forcedQuoteId;
        return super._deriveQuoteId(quote_);
    }
}

/// @dev Mandatory acceptance traceability:
/// P9Q-CFG-001, P9Q-CFG-002; P9Q-AUTH-001, P9Q-AUTH-002;
/// P9Q-SRC-001..P9Q-SRC-014; P9Q-POL-001..P9Q-POL-004;
/// P9Q-EQ-001..P9Q-EQ-007; P9Q-COMP-001..P9Q-COMP-004;
/// P9Q-ROUTE-001..P9Q-ROUTE-002; P9Q-TIME-001..P9Q-TIME-008;
/// P9Q-NONCE-001..P9Q-NONCE-006; P9Q-LIVE-001..P9Q-LIVE-002;
/// P9Q-ID-001..P9Q-ID-004; P9Q-EVT-001; P9Q-VIEW-001..P9Q-VIEW-002;
/// P9Q-CONS-001..P9Q-CONS-007; P9Q-TERM-001..P9Q-TERM-005;
/// P9Q-RPL-001..P9Q-RPL-006; P9Q-NOVAL-001..P9Q-NOVAL-004;
/// P9Q-LOCAL-001..P9Q-LOCAL-003.
/// Deployment-only P9Q-DEPLOY-001..005 are exercised by the dedicated local deployment
/// evidence suite because the quote engine test uses a coordinator caller proxy.
abstract contract Phase9PayoffQuoteFixture {
    struct IssuedEventData {
        bytes32 componentHash;
        uint256 gross;
        uint256 credits;
        uint256 net;
        bytes32 asset;
        address settlementToken;
        bytes32 route;
        uint64 issuedAt;
        uint64 validUntil;
        uint64 nonce;
    }

    Phase9PayoffVm internal constant vm =
        Phase9PayoffVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 internal constant NOW = 1_900_000_000;
    uint64 internal constant MAX_VALIDITY = 3_600;
    bytes32 internal constant LOAN_ID = keccak256("SYNTHETIC_PHASE9_LOAN");
    bytes32 internal constant ASSET_ID = keccak256("SYNTHETIC_PHASE9_ASSET");
    bytes32 internal constant POLICY_SET = keccak256("SYNTHETIC_PHASE9_POLICY_SET");
    bytes32 internal constant AGREEMENT = keccak256("SYNTHETIC_PHASE9_AGREEMENT");
    bytes32 internal constant POSITION_ID = keccak256("SYNTHETIC_PHASE9_POSITION");
    bytes32 internal constant TRANCHE_ID = keccak256("SYNTHETIC_PHASE9_TRANCHE");
    bytes32 internal constant REFINANCE_ID = keccak256("SYNTHETIC_PHASE9_REFINANCE");
    bytes32 internal constant SOURCE_EVENT_ID = keccak256("SYNTHETIC_PHASE9_SOURCE_EVENT");
    address internal constant BORROWER = address(0xB0110);
    address internal constant LENDER = address(0x1E0D3);
    address internal constant FEE_BENEFICIARY = address(0xFEE);
    bytes32 internal constant TOKEN_RUNTIME_HASH =
        0xb4cb1bc940c6783f3ecad43dc045c0fa93b02fae77d6e874a8adaf7216c907e5;

    Phase9PayoffMockRegistry internal registry;
    Phase9PayoffMockFactory internal factory;
    Phase9PayoffMockAccount internal account;
    Phase9PayoffMockPositionManager internal positions;
    Phase9PayoffMockPolicySource internal policy;
    Phase9PayoffCoordinatorProxy internal coordinator;
    Phase9LocalSyntheticToken internal token;
    PayoffQuoteEngine internal engine;

    function setUp() public virtual {
        vm.chainId(31_337);
        vm.warp(NOW);
        registry = new Phase9PayoffMockRegistry();
        factory = new Phase9PayoffMockFactory();
        account = new Phase9PayoffMockAccount();
        positions = new Phase9PayoffMockPositionManager();
        policy = new Phase9PayoffMockPolicySource();
        coordinator = new Phase9PayoffCoordinatorProxy();
        token = new Phase9LocalSyntheticToken(address(this));
        engine = new PayoffQuoteEngine(
            registry, address(policy), MAX_VALIDITY, address(factory), address(coordinator)
        );
        coordinator.bind(engine);
        _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
        _setCanonicalDebt(90, 5, 3, 3, 1, 7);
        _setPositions(address(positions), LENDER, 95, 1);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(token), true);
    }

    function _setCanonicalConfiguration(
        address positionManager,
        address settlementToken,
        bytes32 policySetHash
    ) internal {
        Phase9Types.LoanConfiguration memory configuration;
        configuration.factory = address(factory);
        configuration.loanRegistry = address(registry);
        configuration.settlementToken = settlementToken;
        configuration.settlementAssetId = ASSET_ID;
        configuration.borrower = BORROWER;
        configuration.positionManager = positionManager;
        configuration.payoffQuoteEngine = address(engine);
        configuration.refinanceCoordinator = address(coordinator);
        configuration.loanId = LOAN_ID;
        configuration.agreementHash = AGREEMENT;
        configuration.policySetHash = policySetHash;
        account.setConfiguration(configuration);
        registry.setRecord(
            LOAN_ID,
            Phase9PayoffMockRegistry.Record({
                account: address(account),
                borrower: BORROWER,
                agreementHash: AGREEMENT,
                version: 9,
                exists_: true,
                terminal: false
            })
        );
        factory.setLoan(LOAN_ID, address(account), positionManager);
    }

    function _setCanonicalDebt(
        uint256 principal,
        uint256 interest,
        uint256 fees,
        uint256 penalties,
        uint256 credits,
        uint64 version
    ) internal {
        Phase9Types.DebtState memory debt;
        debt.lifecycle = Phase9Types.LoanLifecycle.ACTIVE;
        debt.servicingState = Phase9Types.ServicingState.CURRENT;
        debt.termsVersion = 1;
        debt.debtStateVersion = version;
        debt.outstandingPrincipal = principal;
        debt.accruedInterest = interest;
        debt.accruedFees = fees;
        debt.accruedPenalties = penalties;
        debt.unappliedCredit = credits;
        account.setDebt(debt);
    }

    function _setPositions(address manager, address owner, uint256 claim, uint256 count) internal {
        Phase9Types.Position[] memory values = new Phase9Types.Position[](count);
        for (uint256 i; i < count; ++i) {
            values[i] = Phase9Types.Position({
                positionId: bytes32(uint256(POSITION_ID) + i),
                trancheId: TRANCHE_ID,
                owner: owner,
                votingPower: claim,
                claim: claim,
                state: Phase9Types.PositionState.ACTIVE
            });
        }
        Phase9PayoffMockPositionManager(manager).setPositions(values);
    }

    function _setCanonicalPolicy(
        bytes32 policySetHash,
        address beneficiary,
        bytes32 assetId,
        address settlementToken,
        bool active
    ) internal returns (bytes32 digest) {
        digest = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            LOAN_ID,
            address(account),
            policySetHash,
            beneficiary,
            assetId,
            settlementToken,
            MAX_VALIDITY
        );
        policy.setPolicy(
            LOAN_ID,
            address(account),
            Phase9PayoffMockPolicySource.Policy({
                policyHash: digest,
                boundPolicySetHash: policySetHash,
                feePenaltyBeneficiary: beneficiary,
                settlementAssetId: assetId,
                settlementToken: settlementToken,
                maximumValidity: MAX_VALIDITY,
                active: active
            })
        );
    }

    function _issue() internal returns (bytes32) {
        return coordinator.issue(LOAN_ID, NOW + MAX_VALIDITY);
    }

    function _issueCall(bytes32 loanId, uint64 validUntil)
        internal
        returns (bool success, bytes memory result)
    {
        return address(coordinator)
            .call(abi.encodeCall(Phase9PayoffCoordinatorProxy.issue, (loanId, validUntil)));
    }

    function _consumeCall(
        bytes32 quoteId,
        bytes32 refinanceId,
        uint64 version,
        bytes32 sourceEventId
    ) internal returns (bool success, bytes memory result) {
        return address(coordinator)
            .call(
                abi.encodeCall(
                    Phase9PayoffCoordinatorProxy.consume,
                    (quoteId, refinanceId, version, sourceEventId)
                )
            );
    }

    function _invalidateCall(bytes32 quoteId, bytes32 sourceEventId)
        internal
        returns (bool success, bytes memory result)
    {
        return address(coordinator)
            .call(abi.encodeCall(Phase9PayoffCoordinatorProxy.invalidate, (quoteId, sourceEventId)));
    }

    function _assertRevert(bool success, bytes memory result, bytes4 selector) internal pure {
        require(!success, "expected revert");
        require(result.length >= 4 && bytes4(result) == selector, "wrong revert selector");
    }

    function _assertQuoteUnchanged(
        bytes32 quoteId,
        bytes32 expectedHash,
        bytes32 expectedComponentsHash
    ) internal view {
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        require(keccak256(abi.encode(stored)) == expectedHash, "quote changed");
        require(keccak256(abi.encode(components_)) == expectedComponentsHash, "components changed");
    }

    function _externalEffectHash() internal view returns (bytes32) {
        bytes32 sourceHash = keccak256(
            abi.encode(
                account.configuration(),
                account.debtState(),
                positions.positionIds(),
                positions.position(POSITION_ID),
                registry.loanAccount(LOAN_ID),
                registry.protocolVersionOf(LOAN_ID),
                registry.isTerminal(LOAN_ID),
                factory.loanAccount(LOAN_ID),
                factory.positionManager(LOAN_ID)
            )
        );
        bytes32 valueHash = keccak256(
            abi.encode(
                token.totalSupply(),
                token.balanceOf(address(this)),
                token.balanceOf(address(account)),
                token.balanceOf(address(engine)),
                token.balanceOf(address(coordinator)),
                token.balanceOf(LENDER),
                token.balanceOf(FEE_BENEFICIARY),
                address(engine).balance,
                address(account).balance,
                address(positions).balance
            )
        );
        return keccak256(abi.encode(sourceHash, valueHash));
    }

    function _quoteStorageBase(bytes32 quoteId) internal pure returns (bytes32) {
        return keccak256(abi.encode(quoteId, uint256(5)));
    }

    function _nonceStorageSlot(bytes32 loanId) internal pure returns (bytes32) {
        return keccak256(abi.encode(loanId, uint256(4)));
    }

    function _latestStorageSlot(bytes32 loanId) internal pure returns (bytes32) {
        return keccak256(abi.encode(loanId, uint256(8)));
    }

    function _assertIssueEvent(
        Phase9PayoffVm.Log memory log_,
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_
    ) internal pure {
        require(log_.topics.length == 4, "issue indexed width");
        require(log_.topics[1] == quote_.quoteId, "event quote id");
        require(log_.topics[2] == quote_.loanId, "event loan id");
        require(uint64(uint256(log_.topics[3])) == quote_.debtStateVersion, "event debt version");
        IssuedEventData memory data = abi.decode(log_.data, (IssuedEventData));
        require(data.componentHash == quote_.componentBeneficiaryHash, "event components");
        require(
            data.gross == quote_.grossPayoff && data.credits == quote_.credits,
            "event gross/credits"
        );
        require(
            data.net == quote_.netPayoff && data.asset == quote_.settlementAssetId,
            "event net/asset"
        );
        require(
            data.settlementToken == quote_.settlementToken
                && data.route == quote_.settlementRouteHash,
            "event route"
        );
        require(
            data.issuedAt == quote_.issuedAt && data.validUntil == quote_.validUntil, "event times"
        );
        require(data.nonce == quote_.quoteNonce, "event nonce");
    }
}

contract Phase9PayoffQuoteCanonicalTest is Phase9PayoffQuoteFixture {
    function test_P9Q_EQ001_COMP001_COMP003_ROUTE001_ID001_EVT001_LOCAL002_CanonicalQuote() public {
        vm.recordLogs();
        bytes32 quoteId = _issue();
        Phase9PayoffVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1, "issue event count");
        require(logs[0].emitter == address(engine), "issue event emitter");
        require(
            logs[0].topics[0]
                == keccak256(
                    "PayoffQuoteIssued(bytes32,bytes32,uint64,bytes32,uint256,uint256,uint256,bytes32,address,bytes32,uint64,uint64,uint64)"
                ),
            "issue event topic"
        );

        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        require(stored.quoteId == quoteId, "quote id key");
        _assertIssueEvent(logs[0], stored);
        require(stored.grossPayoff == 101 && stored.netPayoff == 100, "payoff equation");
        require(stored.quoteNonce == 1 && stored.issuedAt == NOW, "nonce/time");
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "issued state");
        require(components_.length == 5, "component count");

        IPayoffQuoteEngineV2.PayoffComponentV2[] memory expected =
            Phase9PayoffReference.components(90, 5, 3, 3, 1, LENDER, FEE_BENEFICIARY);
        require(keccak256(abi.encode(components_)) == keccak256(abi.encode(expected)), "components");
        require(
            stored.componentBeneficiaryHash == Phase9PayoffReference.componentHash(expected),
            "component hash"
        );
        require(
            stored.settlementRouteHash
                == Phase9PayoffReference.routeHash(
                    address(engine),
                    address(coordinator),
                    LOAN_ID,
                    address(account),
                    ASSET_ID,
                    address(token),
                    LENDER,
                    FEE_BENEFICIARY,
                    stored.policyHash
                ),
            "route hash"
        );
        require(
            quoteId == Phase9PayoffReference.quoteIdFor(address(engine), stored), "quote preimage"
        );
        require(address(token).codehash == TOKEN_RUNTIME_HASH, "pinned token runtime");
    }

    function test_P9Q_COMP002_ZeroComponentsRemain() public {
        _setCanonicalDebt(90, 5, 0, 0, 0, 7);
        _setPositions(address(positions), LENDER, 95, 1);
        bytes32 quoteId = _issue();
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        require(components_.length == 5, "zero components omitted");
        require(components_[2].amount == 0 && components_[3].amount == 0, "zero values");
        require(stored.netPayoff == 95, "zero route payoff");
    }

    function test_P9Q_EQ003_FullNonzeroFeeAndPenaltyCreditLeavesLenderClaim() public {
        _setCanonicalDebt(90, 5, 3, 4, 7, 7);
        _setPositions(address(positions), LENDER, 95, 1);
        bytes32 quoteId = _issue();
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        require(stored.fees == 3 && stored.penalties == 4 && stored.credits == 7, "nonzero facts");
        require(stored.grossPayoff == 102, "gross payoff");
        require(stored.netPayoff == stored.principal + stored.accruedInterest, "lender claim");
        require(
            components_[2].amount == 3 && components_[3].amount == 4 && components_[4].amount == 7,
            "component amounts"
        );
    }

    function test_P9Q_POL001_PolicyEncoderMatchesStoredQuote() public {
        bytes32 expected = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            LOAN_ID,
            address(account),
            POLICY_SET,
            FEE_BENEFICIARY,
            ASSET_ID,
            address(token),
            MAX_VALIDITY
        );
        bytes32 quoteId = _issue();
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.policyHash == expected, "policy hash");
    }

    function test_P9Q_COMP004_ROUTE002_ID002_ID003_CommitmentsBindEveryField() public view {
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory first =
            Phase9PayoffReference.components(90, 5, 3, 3, 1, LENDER, FEE_BENEFICIARY);
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory changed =
            Phase9PayoffReference.components(91, 5, 3, 3, 1, LENDER, FEE_BENEFICIARY);
        require(
            Phase9PayoffReference.componentHash(first)
                != Phase9PayoffReference.componentHash(changed),
            "component amount unbound"
        );
        bytes32 policyHash_ = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            LOAN_ID,
            address(account),
            POLICY_SET,
            FEE_BENEFICIARY,
            ASSET_ID,
            address(token),
            MAX_VALIDITY
        );
        bytes32 route = Phase9PayoffReference.routeHash(
            address(engine),
            address(coordinator),
            LOAN_ID,
            address(account),
            ASSET_ID,
            address(token),
            LENDER,
            FEE_BENEFICIARY,
            policyHash_
        );
        bytes32 changedRoute = Phase9PayoffReference.routeHash(
            address(engine),
            address(coordinator),
            LOAN_ID,
            address(account),
            ASSET_ID,
            address(token),
            address(0xBAD),
            FEE_BENEFICIARY,
            policyHash_
        );
        require(route != changedRoute, "route beneficiary unbound");
        require(
            keccak256(abi.encode("UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1", first))
                != keccak256(abi.encodePacked("UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1")),
            "packed commitment accepted"
        );
    }

    function test_P9Q_ID002_NonCanonicalPackedExtendedAndReorderedPreimagesDiffer() public {
        bytes32 quoteId = _issue();
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        Phase9PayoffReference.QuoteIdentityFacts memory identity =
            Phase9PayoffReference.QuoteIdentityFacts({
                loanId: stored.loanId,
                loanAccount: stored.loanAccount,
                policyHash: stored.policyHash,
                debtStateVersion: stored.debtStateVersion,
                principal: stored.principal,
                accruedInterest: stored.accruedInterest,
                fees: stored.fees,
                penalties: stored.penalties,
                credits: stored.credits,
                componentBeneficiaryHash: stored.componentBeneficiaryHash,
                netPayoff: stored.netPayoff,
                settlementAssetId: stored.settlementAssetId,
                settlementToken: stored.settlementToken,
                settlementRouteHash: stored.settlementRouteHash,
                issuedAt: stored.issuedAt,
                validUntil: stored.validUntil,
                quoteNonce: stored.quoteNonce
            });
        bytes32 canonical = Phase9PayoffReference.quoteIdFor(address(engine), stored);
        bytes32 packed = keccak256(
            abi.encodePacked(
                "UNIFIED_PAYOFF_QUOTE_V1", address(engine), block.chainid, abi.encode(identity)
            )
        );
        bytes32 withGross = keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_QUOTE_V1",
                address(engine),
                block.chainid,
                identity,
                stored.grossPayoff
            )
        );
        bytes32 withQuoteId = keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_QUOTE_V1", address(engine), block.chainid, identity, stored.quoteId
            )
        );
        bytes32 reordered = keccak256(
            abi.encode("UNIFIED_PAYOFF_QUOTE_V1", block.chainid, address(engine), identity)
        );
        require(canonical == quoteId, "canonical identity");
        require(packed != canonical, "packed accepted");
        require(withGross != canonical, "gross included");
        require(withQuoteId != canonical, "quote id included");
        require(reordered != canonical, "reordered accepted");
    }
}

contract Phase9PayoffQuoteAuthorizationAndInputTest is Phase9PayoffQuoteFixture {
    function test_P9Q_CFG001_ConstructorRejectsEveryZeroOrInvalidAuthority() public {
        _expectConstructorFailure(
            address(0), address(policy), MAX_VALIDITY, address(factory), address(coordinator)
        );
        _expectConstructorFailure(
            address(registry), address(0), MAX_VALIDITY, address(factory), address(coordinator)
        );
        _expectConstructorFailure(
            address(registry), address(policy), 0, address(factory), address(coordinator)
        );
        _expectConstructorFailure(
            address(registry), address(policy), MAX_VALIDITY, address(0), address(coordinator)
        );
        _expectConstructorFailure(
            address(registry), address(policy), MAX_VALIDITY, address(factory), address(0)
        );
        _expectConstructorFailure(
            address(0x1001), address(policy), MAX_VALIDITY, address(factory), address(coordinator)
        );
        _expectConstructorFailure(
            address(registry), address(0x1002), MAX_VALIDITY, address(factory), address(coordinator)
        );
        _expectConstructorFailure(
            address(registry), address(policy), MAX_VALIDITY, address(0x1003), address(coordinator)
        );
    }

    function test_P9Q_AUTH001_AUTH002_OnlyCoordinatorMayMutate() public {
        Phase9PayoffUnauthorizedCaller attacker = new Phase9PayoffUnauthorizedCaller();
        bytes memory callData = abi.encodeCall(IPayoffQuoteEngineV2.issueQuote, (LOAN_ID, NOW + 1));
        (bool success, bytes memory result) = address(attacker)
            .call(
                abi.encodeCall(Phase9PayoffUnauthorizedCaller.invoke, (address(engine), callData))
            );
        _assertRevert(success, result, IPayoffQuoteEngineV2.UnauthorizedQuoteCaller.selector);
        bytes32 quoteId = _issue();
        require(quoteId != bytes32(0), "coordinator issue");
    }

    function test_P9Q_AUTH002_AllNamedUnauthorizedIdentitiesFailAllMutators() public {
        address[] memory callers = new address[](6);
        callers[0] = BORROWER;
        callers[1] = LENDER;
        callers[2] = address(account);
        callers[3] = address(factory);
        callers[4] = address(policy);
        callers[5] = address(0xA11CE);
        for (uint256 i; i < callers.length; ++i) {
            _assertUnauthorizedFrom(
                callers[i], abi.encodeCall(IPayoffQuoteEngineV2.issueQuote, (LOAN_ID, NOW + 1))
            );
            _assertUnauthorizedFrom(
                callers[i],
                abi.encodeCall(
                    IPayoffQuoteEngineV2.consumeQuote,
                    (bytes32(uint256(1)), REFINANCE_ID, 7, SOURCE_EVENT_ID)
                )
            );
            _assertUnauthorizedFrom(
                callers[i],
                abi.encodeCall(
                    IPayoffQuoteEngineV2.invalidateQuote, (bytes32(uint256(1)), SOURCE_EVENT_ID)
                )
            );
        }
    }

    function test_P9Q_SRC001_SRC002_UnknownZeroAndWrongVersionFailWithoutNonce() public {
        (bool success, bytes memory result) = _issueCall(bytes32(0), NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        (success, result) = _issueCall(keccak256("UNKNOWN_LOAN"), NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        Phase9PayoffMockRegistry.Record memory record = Phase9PayoffMockRegistry.Record({
            account: address(account),
            borrower: BORROWER,
            agreementHash: AGREEMENT,
            version: 8,
            exists_: true,
            terminal: false
        });
        registry.setRecord(LOAN_ID, record);
        (success, result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        require(
            vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "nonce advanced"
        );
    }

    function test_P9Q_SRC003_SRC004_SRC005_FactoryAndEveryAccountBindingAreCanonical() public {
        factory.setLoan(LOAN_ID, address(0xBAD), address(positions));
        _expectInvalidIssue();
        factory.setLoan(LOAN_ID, address(account), address(positions));
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        configuration.refinanceCoordinator = address(0xBAD);
        account.setConfiguration(configuration);
        _expectInvalidIssue();
        _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
        Phase9Types.DebtState memory debt = account.debtState();
        debt.lifecycle = Phase9Types.LoanLifecycle.CLOSED;
        account.setDebt(debt);
        _expectInvalidIssue();
        debt.lifecycle = Phase9Types.LoanLifecycle.ACTIVE;
        debt.servicingState = Phase9Types.ServicingState.TERMINAL;
        account.setDebt(debt);
        _expectInvalidIssue();
    }

    function test_P9Q_SRC004_EveryQuoteRelevantAccountConfigurationFieldIsChecked() public {
        for (uint256 field; field < 9; ++field) {
            _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
            Phase9Types.LoanConfiguration memory configuration = account.configuration();
            if (field == 0) configuration.loanId = keccak256("WRONG_LOAN");
            else if (field == 1) configuration.factory = address(0x101);
            else if (field == 2) configuration.loanRegistry = address(0x102);
            else if (field == 3) configuration.payoffQuoteEngine = address(0x103);
            else if (field == 4) configuration.refinanceCoordinator = address(0x104);
            else if (field == 5) configuration.positionManager = address(0x105);
            else if (field == 6) configuration.policySetHash = keccak256("WRONG_POLICY_SET");
            else if (field == 7) configuration.settlementAssetId = keccak256("WRONG_ASSET");
            else configuration.settlementToken = address(0x106);
            account.setConfiguration(configuration);
            _expectInvalidIssue();
        }
    }

    function test_P9Q_SRC005_UninitializedTerminalAndCodeLessAccountsAreRejected() public {
        Phase9PayoffMockRegistry.Record memory record = Phase9PayoffMockRegistry.Record({
            account: address(account),
            borrower: BORROWER,
            agreementHash: AGREEMENT,
            version: 9,
            exists_: true,
            terminal: true
        });
        registry.setRecord(LOAN_ID, record);
        _expectInvalidIssue();

        record.terminal = false;
        record.account = address(0xC0DE);
        registry.setRecord(LOAN_ID, record);
        factory.setLoan(LOAN_ID, address(0xC0DE), address(positions));
        _expectInvalidIssue();

        Phase9PayoffMockAccount uninitialized = new Phase9PayoffMockAccount();
        record.account = address(uninitialized);
        registry.setRecord(LOAN_ID, record);
        factory.setLoan(LOAN_ID, address(uninitialized), address(positions));
        _expectInvalidIssue();
    }

    function test_P9Q_SRC006_SRC007_PositionCardinalityOwnerAndClaimFailClosed() public {
        _setPositions(address(positions), LENDER, 95, 0);
        _expectInvalidIssue();
        _setPositions(address(positions), LENDER, 95, 2);
        _expectInvalidIssue();
        _setPositions(address(positions), address(0), 95, 1);
        _expectInvalidIssue();
        _setPositions(address(positions), LENDER, 94, 1);
        _expectInvalidIssue();
    }

    function test_P9Q_SRC008_SRC009_SRC010_DependencyFailuresLeaveNoPartialState() public {
        policy.setShouldRevert(true);
        _expectInvalidIssue();
        policy.setShouldRevert(false);
        account.setReadReverts(false, true);
        _expectIssueFailure();
        account.setReadReverts(false, false);
        positions.setShouldRevert(true);
        _expectIssueFailure();
        require(vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "partial nonce");
    }

    function test_P9Q_SRC008_MalformedPolicyReturnIsNormalizedAndLeavesNoState() public {
        Phase9PayoffMalformedPolicySource malformed = new Phase9PayoffMalformedPolicySource();
        for (uint8 mode; mode <= 4; ++mode) {
            malformed.setMode(mode);
            _installMalformedPolicyEngine(malformed);
            vm.recordLogs();
            (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
            _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
            require(
                vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "partial nonce"
            );
            require(
                vm.load(address(engine), _latestStorageSlot(LOAN_ID)) == bytes32(0),
                "partial latest"
            );
            require(vm.getRecordedLogs().length == 0, "malformed event");
        }
    }

    function test_P9Q_SRC011_SRC012_IdenticalAttackerManagerAndNoCodeManagerRejected() public {
        Phase9PayoffMockPositionManager attacker = new Phase9PayoffMockPositionManager();
        _setPositions(address(attacker), LENDER, 95, 1);
        factory.setLoan(LOAN_ID, address(account), address(attacker));
        _expectInvalidIssue();
        factory.setLoan(LOAN_ID, address(account), address(0x1234));
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        configuration.positionManager = address(0x1234);
        account.setConfiguration(configuration);
        _expectInvalidIssue();
        factory.setLoan(LOAN_ID, address(account), address(0));
        configuration.positionManager = address(0);
        account.setConfiguration(configuration);
        _expectInvalidIssue();
    }

    function test_P9Q_SRC013_WrongRuntimeTokenWithExactMetadataRejected() public {
        Phase9PayoffWrongRuntimeToken wrong = new Phase9PayoffWrongRuntimeToken(address(this));
        _setCanonicalConfiguration(address(positions), address(wrong), POLICY_SET);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(wrong), true);
        _expectInvalidIssue();
        require(wrong.calls() == 0, "wrong token called");
    }

    function test_P9Q_CFG002_POL002_ZeroMismatchInactiveOrOpaquePolicyRejected() public {
        Phase9PayoffMockPolicySource.Policy memory invalid = Phase9PayoffMockPolicySource.Policy({
            policyHash: bytes32(uint256(1)),
            boundPolicySetHash: POLICY_SET,
            feePenaltyBeneficiary: FEE_BENEFICIARY,
            settlementAssetId: ASSET_ID,
            settlementToken: address(token),
            maximumValidity: MAX_VALIDITY - 1,
            active: true
        });
        policy.setPolicy(LOAN_ID, address(account), invalid);
        _expectInvalidIssue();
        invalid.maximumValidity = MAX_VALIDITY;
        invalid.active = false;
        policy.setPolicy(LOAN_ID, address(account), invalid);
        _expectInvalidIssue();
        invalid.active = true;
        invalid.feePenaltyBeneficiary = address(0);
        policy.setPolicy(LOAN_ID, address(account), invalid);
        _expectInvalidIssue();

        invalid = Phase9PayoffMockPolicySource.Policy({
            policyHash: bytes32(0),
            boundPolicySetHash: POLICY_SET,
            feePenaltyBeneficiary: FEE_BENEFICIARY,
            settlementAssetId: ASSET_ID,
            settlementToken: address(token),
            maximumValidity: MAX_VALIDITY,
            active: true
        });
        _setPolicyAndExpectInvalid(invalid);
        invalid.policyHash = bytes32(uint256(1));
        invalid.boundPolicySetHash = bytes32(0);
        _setPolicyAndExpectInvalid(invalid);
        invalid.boundPolicySetHash = POLICY_SET;
        invalid.settlementAssetId = bytes32(0);
        _setPolicyAndExpectInvalid(invalid);
        invalid.settlementAssetId = ASSET_ID;
        invalid.settlementToken = address(0);
        _setPolicyAndExpectInvalid(invalid);
        invalid.settlementToken = address(token);
        invalid.maximumValidity = 0;
        _setPolicyAndExpectInvalid(invalid);

        _setCanonicalPolicy(
            POLICY_SET, FEE_BENEFICIARY, keccak256("OTHER_ASSET"), address(token), true
        );
        _expectInvalidIssue();
        Phase9LocalSyntheticToken replacement = new Phase9LocalSyntheticToken(address(this));
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(replacement), true);
        _expectInvalidIssue();
    }

    function test_P9Q_EQ004_EQ005_EQ006_EQ007_InvalidEquationComponentsReject() public {
        _setCanonicalDebt(90, 5, 3, 3, 7, 7);
        _expectInvalidIssue();
        _setCanonicalDebt(0, 0, 1, 0, 1, 7);
        _setPositions(address(positions), LENDER, 0, 1);
        _expectInvalidIssue();
        _setCanonicalDebt(type(uint256).max, 1, 0, 0, 0, 7);
        _setPositions(address(positions), LENDER, type(uint256).max, 1);
        _expectInvalidIssue();
        _setCanonicalDebt(90, 5, 3, 3, 1, 7);
        Phase9Types.DebtState memory debt = account.debtState();
        debt.capitalizedInterest = 1;
        account.setDebt(debt);
        _expectInvalidIssue();
        debt.capitalizedInterest = 0;
        debt.recoverableCosts = 1;
        account.setDebt(debt);
        _expectInvalidIssue();
    }

    function test_P9Q_TIME001_TIME002_TIME003_TIME008_HalfOpenBoundedIssuance() public {
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW - 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        (success, result) = _issueCall(LOAN_ID, NOW);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        (success, result) = _issueCall(LOAN_ID, NOW + MAX_VALIDITY + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        bytes32 quoteId = _issue();
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.issuedAt == NOW && stored.validUntil == NOW + MAX_VALIDITY, "time authority");
    }

    function test_P9Q_VIEW001_UnknownAndZeroQuoteNeverReturnZeroTuple() public {
        (bool success, bytes memory result) = address(engine)
            .call(abi.encodeCall(IPayoffQuoteEngineV2.quote, (bytes32(uint256(123)))));
        _assertRevert(success, result, IPayoffQuoteEngineV2.UnknownQuote.selector);
        (success, result) =
            address(engine).call(abi.encodeCall(IPayoffQuoteEngineV2.quote, (bytes32(0))));
        _assertRevert(success, result, IPayoffQuoteEngineV2.UnknownQuote.selector);
    }

    function test_P9Q_LOCAL003_WrongChainIssueFailsWithoutState() public {
        vm.chainId(1);
        _expectInvalidIssue();
        require(
            vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "nonce advanced"
        );
    }

    function _expectConstructorFailure(
        address registry_,
        address policy_,
        uint64 maximum_,
        address factory_,
        address coordinator_
    ) private {
        try new PayoffQuoteEngine(
            Phase9PayoffMockRegistry(registry_), policy_, maximum_, factory_, coordinator_
        ) {
            revert("constructor accepted invalid input");
        } catch (bytes memory reason) {
            require(
                bytes4(reason) == IPayoffQuoteEngineV2.InvalidQuoteInput.selector,
                "constructor error"
            );
        }
    }

    function _expectInvalidIssue() private {
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function _expectIssueFailure() private {
        (bool success,) = _issueCall(LOAN_ID, NOW + 1);
        require(!success, "dependency failure accepted");
    }

    function _assertUnauthorizedFrom(address caller, bytes memory data) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(engine).call(data);
        _assertRevert(success, result, IPayoffQuoteEngineV2.UnauthorizedQuoteCaller.selector);
        require(
            keccak256(result)
                == keccak256(
                    abi.encodeWithSelector(
                        IPayoffQuoteEngineV2.UnauthorizedQuoteCaller.selector, caller
                    )
                ),
            "wrong unauthorized caller"
        );
    }

    function _installMalformedPolicyEngine(Phase9PayoffMalformedPolicySource malformed) private {
        coordinator = new Phase9PayoffCoordinatorProxy();
        engine = new PayoffQuoteEngine(
            registry, address(malformed), MAX_VALIDITY, address(factory), address(coordinator)
        );
        coordinator.bind(engine);
        _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
    }

    function _setPolicyAndExpectInvalid(Phase9PayoffMockPolicySource.Policy memory invalid)
        private
    {
        policy.setPolicy(LOAN_ID, address(account), invalid);
        _expectInvalidIssue();
    }
}

contract Phase9PayoffQuoteLifecycleTest is Phase9PayoffQuoteFixture {
    function test_P9Q_TIME004_TIME005_TIME006_TIME007_ExpiryBoundaryAndPersistence() public {
        bytes32 quoteId = _issue();
        vm.warp(NOW + MAX_VALIDITY - 1);
        (bool success,) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        require(success, "pre-expiry consume");

        setUp();
        quoteId = _issue();
        vm.warp(NOW + MAX_VALIDITY);
        bytes memory result;
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteExpired.selector);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory effective,) = engine.quote(quoteId);
        require(effective.state == IPayoffQuoteEngineV2.QuoteState.EXPIRED, "effective expiry");
        vm.recordLogs();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        require(vm.getRecordedLogs().length == 1, "expiry event count");
        (effective,) = engine.quote(quoteId);
        require(effective.state == IPayoffQuoteEngineV2.QuoteState.EXPIRED, "persisted expiry");
    }

    function test_P9Q_NONCE001_NONCE002_NONCE003_LIVE001_LIVE002_GaplessPerLoanNonces() public {
        bytes32 first = _issue();
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 10);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        coordinator.invalidate(first, SOURCE_EVENT_ID);
        bytes32 second = coordinator.issue(LOAN_ID, NOW + 20);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory firstQuote,) = engine.quote(first);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory secondQuote,) = engine.quote(second);
        require(firstQuote.quoteNonce == 1 && secondQuote.quoteNonce == 2, "nonce gap");
        require(firstQuote.state == IPayoffQuoteEngineV2.QuoteState.INVALIDATED, "prior mutation");
        require(secondQuote.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "successor state");
    }

    function test_P9Q_NONCE003_DifferentLoansHaveIndependentNonceOne() public {
        bytes32 secondLoanId = keccak256("SECOND_SYNTHETIC_LOAN");
        Phase9PayoffMockAccount secondAccount = new Phase9PayoffMockAccount();
        Phase9PayoffMockPositionManager secondPositions = new Phase9PayoffMockPositionManager();
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        configuration.loanId = secondLoanId;
        configuration.positionManager = address(secondPositions);
        secondAccount.setConfiguration(configuration);
        secondAccount.setDebt(account.debtState());
        _setPositions(address(secondPositions), LENDER, 95, 1);
        registry.setRecord(
            secondLoanId,
            Phase9PayoffMockRegistry.Record({
                account: address(secondAccount),
                borrower: BORROWER,
                agreementHash: AGREEMENT,
                version: 9,
                exists_: true,
                terminal: false
            })
        );
        factory.setLoan(secondLoanId, address(secondAccount), address(secondPositions));
        bytes32 secondPolicyHash = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            secondLoanId,
            address(secondAccount),
            POLICY_SET,
            FEE_BENEFICIARY,
            ASSET_ID,
            address(token),
            MAX_VALIDITY
        );
        policy.setPolicy(
            secondLoanId,
            address(secondAccount),
            Phase9PayoffMockPolicySource.Policy({
                policyHash: secondPolicyHash,
                boundPolicySetHash: POLICY_SET,
                feePenaltyBeneficiary: FEE_BENEFICIARY,
                settlementAssetId: ASSET_ID,
                settlementToken: address(token),
                maximumValidity: MAX_VALIDITY,
                active: true
            })
        );

        bytes32 first = _issue();
        bytes32 second = coordinator.issue(secondLoanId, NOW + MAX_VALIDITY);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory firstQuote,) = engine.quote(first);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory secondQuote,) = engine.quote(second);
        require(firstQuote.quoteNonce == 1 && secondQuote.quoteNonce == 1, "cross-loan nonce");
    }

    function test_P9Q_LIVE002_EffectiveExpiryAllowsSuccessorWithoutPriorWrite() public {
        bytes32 first = coordinator.issue(LOAN_ID, NOW + 1);
        vm.warp(NOW + 1);
        bytes32 second = coordinator.issue(LOAN_ID, NOW + 2);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory firstQuote,) = engine.quote(first);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory secondQuote,) = engine.quote(second);
        require(
            firstQuote.state == IPayoffQuoteEngineV2.QuoteState.EXPIRED, "prior effective state"
        );
        require(secondQuote.quoteNonce == 2, "expiry successor nonce");
    }

    function test_P9Q_NONCE004_NonceExhaustionCannotWrap() public {
        vm.store(address(engine), _nonceStorageSlot(LOAN_ID), bytes32(uint256(type(uint64).max)));
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
        require(
            keccak256(result)
                == keccak256(
                    abi.encodeWithSelector(
                        IPayoffQuoteEngineV2.QuoteReplayConflict.selector, bytes32(0)
                    )
                ),
            "exhaustion payload"
        );
        require(
            vm.load(address(engine), _nonceStorageSlot(LOAN_ID))
                == bytes32(uint256(type(uint64).max)),
            "nonce wrapped"
        );
    }

    function test_P9Q_NONCE005_ForcedZeroQuoteIdPreservesEveryPreWriteField() public {
        Phase9PayoffQuoteIdHarness harness = _replaceWithIdHarness();
        harness.forceQuoteId(bytes32(0));
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
        require(
            keccak256(result)
                == keccak256(
                    abi.encodeWithSelector(
                        IPayoffQuoteEngineV2.QuoteReplayConflict.selector, bytes32(0)
                    )
                ),
            "zero id payload"
        );
        require(
            vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "nonce advanced"
        );
        require(
            vm.load(address(engine), _latestStorageSlot(LOAN_ID)) == bytes32(0), "latest changed"
        );
    }

    function test_P9Q_NONCE006_PreMaterializedDerivedIdPreservesAllPreState() public {
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_ =
            Phase9PayoffReference.components(90, 5, 3, 3, 1, LENDER, FEE_BENEFICIARY);
        bytes32 policyHash_ = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            LOAN_ID,
            address(account),
            POLICY_SET,
            FEE_BENEFICIARY,
            ASSET_ID,
            address(token),
            MAX_VALIDITY
        );
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory candidate;
        candidate.loanId = LOAN_ID;
        candidate.loanAccount = address(account);
        candidate.policyHash = policyHash_;
        candidate.debtStateVersion = 7;
        candidate.principal = 90;
        candidate.accruedInterest = 5;
        candidate.fees = 3;
        candidate.penalties = 3;
        candidate.credits = 1;
        candidate.componentBeneficiaryHash = Phase9PayoffReference.componentHash(components_);
        candidate.grossPayoff = 101;
        candidate.netPayoff = 100;
        candidate.settlementAssetId = ASSET_ID;
        candidate.settlementToken = address(token);
        candidate.settlementRouteHash = Phase9PayoffReference.routeHash(
            address(engine),
            address(coordinator),
            LOAN_ID,
            address(account),
            ASSET_ID,
            address(token),
            LENDER,
            FEE_BENEFICIARY,
            policyHash_
        );
        candidate.issuedAt = NOW;
        candidate.validUntil = NOW + MAX_VALIDITY;
        candidate.quoteNonce = 1;
        bytes32 collision = Phase9PayoffReference.quoteIdFor(address(engine), candidate);
        vm.store(address(engine), _quoteStorageBase(collision), collision);
        bytes32 oldLatest = vm.load(address(engine), _latestStorageSlot(LOAN_ID));
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + MAX_VALIDITY);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
        require(
            keccak256(result)
                == keccak256(
                    abi.encodeWithSelector(
                        IPayoffQuoteEngineV2.QuoteReplayConflict.selector, collision
                    )
                ),
            "collision payload"
        );
        require(
            vm.load(address(engine), _quoteStorageBase(collision)) == collision,
            "collision overwritten"
        );
        require(
            vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "nonce advanced"
        );
        require(
            vm.load(address(engine), _latestStorageSlot(LOAN_ID)) == oldLatest, "latest changed"
        );
    }

    function test_P9Q_CONS001_CONS002_CONS003_CONS006_ConsumeAndVersionValidation() public {
        bytes32 quoteId = _issue();
        (, IPayoffQuoteEngineV2.PayoffComponentV2[] memory beforeComponents) = engine.quote(quoteId);
        bytes32 componentHash = keccak256(abi.encode(beforeComponents));
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, 6, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.StaleDebtVersion.selector);
        (success, result) = _consumeCall(quoteId, bytes32(0), 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        vm.recordLogs();
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory consumed =
            coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        Phase9PayoffVm.Log[] memory logs = vm.getRecordedLogs();
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory afterComponents
        ) = engine.quote(quoteId);
        require(consumed.state == IPayoffQuoteEngineV2.QuoteState.CONSUMED, "consume state");
        require(keccak256(abi.encode(consumed)) == keccak256(abi.encode(stored)), "return/storage");
        require(keccak256(abi.encode(afterComponents)) == componentHash, "consume components");
        require(logs.length == 1 && logs[0].emitter == address(engine), "consume event count");
        require(logs[0].topics.length == 3, "consume indexed width");
        require(
            logs[0].topics[0]
                == keccak256(
                    "PayoffQuoteDispositionRecorded(bytes32,bytes32,uint8,bytes32,uint64)"
                ),
            "consume event topic"
        );
        require(logs[0].topics[1] == quoteId, "consume event quote");
        require(logs[0].topics[2] == REFINANCE_ID, "consume event refinance");
        (IPayoffQuoteEngineV2.QuoteState state, bytes32 sourceEventId, uint64 recordedAt) =
            abi.decode(logs[0].data, (IPayoffQuoteEngineV2.QuoteState, bytes32, uint64));
        require(state == IPayoffQuoteEngineV2.QuoteState.CONSUMED, "consume event state");
        require(sourceEventId == SOURCE_EVENT_ID && recordedAt == NOW, "consume event data");
    }

    function test_P9Q_CONS004_CONS005_CONS007_FullCanonicalRevalidation() public {
        bytes32 quoteId = _issue();
        Phase9Types.DebtState memory debt = account.debtState();
        debt.debtStateVersion = 8;
        account.setDebt(debt);
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.StaleDebtVersion.selector);
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 8, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.StaleDebtVersion.selector);

        debt.debtStateVersion = 7;
        debt.accruedFees = 4;
        account.setDebt(debt);
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function test_P9Q_CONS005_EveryRouteAndRecipientSubstitutionWithoutVersionFails() public {
        bytes32 quoteId = _issue();
        _setPositions(address(positions), address(0xBEEF), 95, 1);
        _expectInvalidConsume(quoteId);

        setUp();
        quoteId = _issue();
        _setPositions(address(positions), LENDER, 96, 1);
        _expectInvalidConsume(quoteId);

        setUp();
        quoteId = _issue();
        _setCanonicalPolicy(POLICY_SET, address(0xBEEF), ASSET_ID, address(token), true);
        _expectInvalidConsume(quoteId);

        setUp();
        quoteId = _issue();
        bytes32 changedAsset = keccak256("CHANGED_ASSET");
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        configuration.settlementAssetId = changedAsset;
        account.setConfiguration(configuration);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, changedAsset, address(token), true);
        _expectInvalidConsume(quoteId);

        setUp();
        quoteId = _issue();
        Phase9LocalSyntheticToken replacement = new Phase9LocalSyntheticToken(address(this));
        configuration = account.configuration();
        configuration.settlementToken = address(replacement);
        account.setConfiguration(configuration);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(replacement), true);
        _expectInvalidConsume(quoteId);

        setUp();
        quoteId = _issue();
        bytes32 changedPolicySet = keccak256("CHANGED_POLICY_SET_ROUTE");
        configuration = account.configuration();
        configuration.policySetHash = changedPolicySet;
        account.setConfiguration(configuration);
        _setCanonicalPolicy(changedPolicySet, FEE_BENEFICIARY, ASSET_ID, address(token), true);
        _expectInvalidConsume(quoteId);
    }

    function test_P9Q_CONS006_ZeroSourceEventCannotConsume() public {
        bytes32 quoteId = _issue();
        (bool success, bytes memory result) = _consumeCall(quoteId, REFINANCE_ID, 7, bytes32(0));
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "zero source terminalized");
    }

    function test_P9Q_CONS007_StoredContentCorruptionCannotConsume() public {
        bytes32 quoteId = _issue();
        bytes32 grossSlot = bytes32(uint256(_quoteStorageBase(quoteId)) + 11);
        vm.store(address(engine), grossSlot, bytes32(uint256(102)));
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);

        setUp();
        quoteId = _issue();
        vm.store(address(engine), _quoteStorageBase(quoteId), keccak256("CORRUPTED_QUOTE_ID"));
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function test_P9Q_SRC013_LOCAL003_ConsumeRejectsWrongRuntimeAndWrongChain() public {
        bytes32 quoteId = _issue();
        Phase9PayoffWrongRuntimeToken wrong = new Phase9PayoffWrongRuntimeToken(address(this));
        _setCanonicalConfiguration(address(positions), address(wrong), POLICY_SET);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(wrong), true);
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        require(wrong.calls() == 0, "wrong token called on consume");

        _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(token), true);
        vm.chainId(1);
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "wrong chain disposition");
    }

    function test_P9Q_SRC011_ConsumeRejectsIdenticalContentFactoryManagerSubstitution() public {
        bytes32 quoteId = _issue();
        Phase9PayoffMockPositionManager attacker = new Phase9PayoffMockPositionManager();
        _setPositions(address(attacker), LENDER, 95, 1);
        factory.setLoan(LOAN_ID, address(account), address(attacker));
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function test_P9Q_POL003_POL004_SuccessorAndConsumeRejectPolicyMutation() public {
        bytes32 quoteId = _issue();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        _setCanonicalPolicy(POLICY_SET, address(0xBEEF), ASSET_ID, address(token), true);
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);

        setUp();
        quoteId = _issue();
        bytes32 changedSet = keccak256("CHANGED_POLICY_SET");
        _setCanonicalConfiguration(address(positions), address(token), changedSet);
        _setCanonicalPolicy(changedSet, FEE_BENEFICIARY, ASSET_ID, address(token), true);
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function test_P9Q_TERM001_TERM002_TERM003_TERM004_TERM005_TerminalPrecedence() public {
        bytes32 quoteId = _issue();
        (bool success, bytes memory result) = _invalidateCall(quoteId, bytes32(0));
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        vm.recordLogs();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        require(vm.getRecordedLogs().length == 1, "invalidation event count");
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteTerminal.selector);

        setUp();
        quoteId = _issue();
        vm.warp(NOW + MAX_VALIDITY);
        (success, result) = _invalidateCall(quoteId, bytes32(0));
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);

        setUp();
        quoteId = _issue();
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        (success, result) = _invalidateCall(quoteId, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteTerminal.selector);

        setUp();
        quoteId = _issue();
        vm.warp(NOW + MAX_VALIDITY);
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        (success, result) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteTerminal.selector);
    }

    function test_P9Q_TERM005_AuthorizationUnknownZeroSourceAndTerminalPrecedence() public {
        bytes32 unknown = keccak256("UNKNOWN_QUOTE");
        vm.prank(BORROWER);
        (bool success, bytes memory result) = address(engine)
            .call(abi.encodeCall(IPayoffQuoteEngineV2.invalidateQuote, (unknown, bytes32(0))));
        _assertRevert(success, result, IPayoffQuoteEngineV2.UnauthorizedQuoteCaller.selector);
        (success, result) = _invalidateCall(unknown, bytes32(0));
        _assertRevert(success, result, IPayoffQuoteEngineV2.UnknownQuote.selector);

        bytes32 quoteId = _issue();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        (success, result) = _invalidateCall(quoteId, bytes32(0));
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function test_P9Q_RPL003_RPL004_ExpiryPersistenceReplayIsIdempotentOrConflict() public {
        bytes32 quoteId = _issue();
        vm.warp(NOW + MAX_VALIDITY);
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        vm.recordLogs();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        require(vm.getRecordedLogs().length == 0, "expiry replay event");
        (bool success, bytes memory result) = _invalidateCall(quoteId, keccak256("CHANGED"));
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
    }

    function test_P9Q_RPL001_RPL002_RPL003_RPL004_RPL005_RPL006_ReplayMatrix() public {
        bytes32 quoteId = _issue();
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        Phase9Types.DebtState memory debt = account.debtState();
        debt.outstandingPrincipal = 0;
        debt.debtStateVersion = 8;
        account.setDebt(debt);
        vm.recordLogs();
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory replay =
            coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        require(replay.state == IPayoffQuoteEngineV2.QuoteState.CONSUMED, "consume replay");
        require(vm.getRecordedLogs().length == 0, "consume replay event");
        (bool success, bytes memory result) =
            _consumeCall(quoteId, keccak256("CHANGED"), 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);

        setUp();
        quoteId = _issue();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        debt = account.debtState();
        debt.outstandingPrincipal = 1;
        account.setDebt(debt);
        vm.recordLogs();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        require(vm.getRecordedLogs().length == 0, "invalidate replay event");
        (success, result) = _invalidateCall(quoteId, keccak256("CHANGED"));
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
    }

    function test_P9Q_NOVAL001_NOVAL002_NOVAL003_NOVAL004_NoValueMovementOrRescue() public {
        vm.deal(address(engine), 10 ether);
        bytes32 externalHash = _externalEffectHash();
        bytes32 quoteId = _issue();
        require(_externalEffectHash() == externalHash, "issue external effect");

        (bool success,) = _issueCall(LOAN_ID, NOW + 1);
        require(!success && _externalEffectHash() == externalHash, "concurrent issue effect");
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        require(_externalEffectHash() == externalHash, "consume external effect");
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        require(_externalEffectHash() == externalHash, "consume replay external effect");
        (success,) = _invalidateCall(quoteId, SOURCE_EVENT_ID);
        require(!success && _externalEffectHash() == externalHash, "terminal reject effect");

        (success,) = address(coordinator).call{ value: 1 }(
            abi.encodeCall(Phase9PayoffCoordinatorProxy.issue, (LOAN_ID, NOW + 1))
        );
        require(!success, "payable issue reached engine");
        require(_externalEffectHash() == externalHash, "value reject external effect");

        setUp();
        vm.deal(address(engine), 10 ether);
        externalHash = _externalEffectHash();
        quoteId = _issue();
        require(_externalEffectHash() == externalHash, "invalidate issue effect");
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        require(_externalEffectHash() == externalHash, "invalidate external effect");
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        require(_externalEffectHash() == externalHash, "invalidate replay external effect");
        (success,) = _invalidateCall(quoteId, keccak256("CHANGED_SOURCE"));
        require(!success && _externalEffectHash() == externalHash, "replay conflict effect");
    }

    function test_P9Q_NOVAL003_ExactTokenHasNoExecutionCallsAcrossAllQuotePaths() public {
        vm.startStateDiffRecording();
        bytes32 quoteId = _issue();
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), true);

        vm.startStateDiffRecording();
        (bool success,) = _issueCall(LOAN_ID, NOW + 1);
        require(!success, "concurrent issue accepted");
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);

        vm.startStateDiffRecording();
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), true);

        vm.startStateDiffRecording();
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);

        vm.startStateDiffRecording();
        (success,) = _consumeCall(quoteId, keccak256("CHANGED_REFINANCE"), 7, SOURCE_EVENT_ID);
        require(!success, "changed consume replay accepted");
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);

        vm.startStateDiffRecording();
        (success,) = _invalidateCall(quoteId, SOURCE_EVENT_ID);
        require(!success, "consumed quote invalidated");
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);

        setUp();
        vm.startStateDiffRecording();
        quoteId = _issue();
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), true);

        vm.startStateDiffRecording();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);

        vm.startStateDiffRecording();
        coordinator.invalidate(quoteId, SOURCE_EVENT_ID);
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);

        vm.startStateDiffRecording();
        (success,) = _invalidateCall(quoteId, keccak256("CHANGED_SOURCE"));
        require(!success, "changed invalidation replay accepted");
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);

        vm.startStateDiffRecording();
        (success,) = _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        require(!success, "invalidated quote consumed");
        _assertNoTokenExecutionAccess(vm.stopAndReturnStateDiff(), false);
    }

    function test_P9Q_NOVAL002_ValueRejectedForConsumeAndInvalidateWithoutMutation() public {
        bytes32 quoteId = _issue();
        (bool success,) = address(coordinator).call{ value: 1 }(
            abi.encodeCall(
                Phase9PayoffCoordinatorProxy.consume, (quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID)
            )
        );
        require(!success, "value consume accepted");
        (success,) = address(coordinator).call{ value: 1 }(
            abi.encodeCall(Phase9PayoffCoordinatorProxy.invalidate, (quoteId, SOURCE_EVENT_ID))
        );
        require(!success, "value invalidate accepted");
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "value changed state");
    }

    function test_P9Q_VIEW002_ReadsAreImmutableExceptExpiryOverlay() public {
        bytes32 quoteId = _issue();
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory before_,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory beforeComponents
        ) = engine.quote(quoteId);
        bytes32 tupleHash = keccak256(abi.encode(before_));
        bytes32 componentsHash = keccak256(abi.encode(beforeComponents));
        _assertQuoteUnchanged(quoteId, tupleHash, componentsHash);
        vm.warp(NOW + MAX_VALIDITY);
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory after_,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory afterComponents
        ) = engine.quote(quoteId);
        before_.state = IPayoffQuoteEngineV2.QuoteState.EXPIRED;
        require(
            keccak256(abi.encode(after_)) == keccak256(abi.encode(before_)), "expiry changed tuple"
        );
        require(
            keccak256(abi.encode(afterComponents)) == componentsHash, "expiry changed components"
        );
    }

    function _replaceWithIdHarness() private returns (Phase9PayoffQuoteIdHarness harness) {
        coordinator = new Phase9PayoffCoordinatorProxy();
        harness = new Phase9PayoffQuoteIdHarness(
            registry, address(policy), MAX_VALIDITY, address(factory), address(coordinator)
        );
        engine = harness;
        coordinator.bind(engine);
        _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(token), true);
    }

    function _expectInvalidConsume(bytes32 quoteId) private {
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "substitution terminalized");
    }

    function _assertNoTokenExecutionAccess(
        Phase9PayoffVm.AccountAccess[] memory accesses,
        bool expectIdentityRead
    ) private view {
        uint256 identityReads;
        for (uint256 index; index < accesses.length; ++index) {
            Phase9PayoffVm.AccountAccess memory access_ = accesses[index];
            if (access_.account != address(token)) continue;
            require(
                access_.kind != Phase9PayoffVm.AccountAccessKind.Call
                    && access_.kind != Phase9PayoffVm.AccountAccessKind.DelegateCall
                    && access_.kind != Phase9PayoffVm.AccountAccessKind.CallCode
                    && access_.kind != Phase9PayoffVm.AccountAccessKind.StaticCall,
                "token execution call"
            );
            require(
                access_.kind == Phase9PayoffVm.AccountAccessKind.Extcodesize
                    || access_.kind == Phase9PayoffVm.AccountAccessKind.Extcodehash,
                "unexpected token account access"
            );
            require(access_.accessor == address(engine), "non-engine token observer");
            ++identityReads;
        }
        require((identityReads != 0) == expectIdentityRead, "token identity-read expectation");
    }
}
