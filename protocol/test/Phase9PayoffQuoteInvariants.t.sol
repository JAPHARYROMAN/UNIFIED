// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPayoffQuoteEngineV2 } from "../src/interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { PayoffQuoteEngine } from "../src/resolution/PayoffQuoteEngine.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";
import {
    Phase9PayoffCoordinatorProxy,
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
import { Phase9PayoffQuoteFixture } from "./Phase9PayoffQuote.t.sol";

contract Phase9PayoffInvariantIdHarness is PayoffQuoteEngine {
    bool private _forceQuoteId;
    bytes32 private _forcedQuoteId;

    constructor(
        Phase9PayoffMockRegistry registry_,
        address policy_,
        uint64 maximumValidity_,
        address factory_,
        address coordinator_
    ) PayoffQuoteEngine(registry_, policy_, maximumValidity_, factory_, coordinator_) { }

    function forceQuoteId(bytes32 quoteId_) external {
        _forceQuoteId = true;
        _forcedQuoteId = quoteId_;
    }

    function clearForcedQuoteId() external {
        _forceQuoteId = false;
        _forcedQuoteId = bytes32(0);
    }

    function _deriveQuoteId(PayoffQuoteV2 memory quote_) internal view override returns (bytes32) {
        if (_forceQuoteId) return _forcedQuoteId;
        return super._deriveQuoteId(quote_);
    }
}

contract Phase9PayoffQuoteInvariantHandler {
    Phase9PayoffVm private constant vm =
        Phase9PayoffVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant OTHER_POSITION_BENEFICIARY = address(0xBADBEEF);
    address private constant SUBSTITUTED_LENDER_BENEFICIARY = address(0xBAD1E0D);
    address private constant SUBSTITUTED_FEE_BENEFICIARY = address(0xBADFEE);

    struct Dependencies {
        Phase9PayoffInvariantIdHarness engine;
        Phase9PayoffCoordinatorProxy coordinator;
        Phase9PayoffMockRegistry registry;
        Phase9PayoffMockFactory factory;
        Phase9PayoffMockAccount account;
        Phase9PayoffMockPositionManager positions;
        Phase9PayoffMockPolicySource policy;
        Phase9LocalSyntheticToken token;
        bytes32 loanId;
        bytes32 assetId;
        bytes32 policySetHash;
        address lender;
        address feeBeneficiary;
        uint64 maximumValidity;
    }

    struct ModeledQuote {
        bytes32 tupleHash;
        bytes32 componentsHash;
        bytes32 policyHash;
        bytes32 boundPolicySetHash;
        bytes32 settlementAssetId;
        address settlementToken;
        address lenderBeneficiary;
        address feeBeneficiary;
        uint64 nonce;
        uint64 debtStateVersion;
        uint64 validUntil;
        IPayoffQuoteEngineV2.QuoteState dispositionState;
        bytes32 refinanceId;
        bytes32 sourceEventId;
        uint64 recordedAt;
    }

    struct QuoteIdentityFacts {
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
        uint256 netPayoff;
        bytes32 settlementAssetId;
        address settlementToken;
        bytes32 settlementRouteHash;
        uint64 issuedAt;
        uint64 validUntil;
        uint64 quoteNonce;
    }

    struct PolicyEvidence {
        bytes32 policyHash;
        bytes32 boundPolicySetHash;
        bytes32 settlementAssetId;
        address settlementToken;
        address feeBeneficiary;
    }

    Phase9PayoffInvariantIdHarness public immutable engine;
    Phase9PayoffCoordinatorProxy public immutable coordinator;
    Phase9PayoffMockRegistry public immutable registry;
    Phase9PayoffMockFactory public immutable factory;
    Phase9PayoffMockAccount public immutable account;
    Phase9PayoffMockAccount public immutable attackerAccount;
    Phase9PayoffMockPositionManager public immutable positions;
    Phase9PayoffMockPositionManager public immutable attackerPositions;
    Phase9PayoffMockPolicySource public immutable policy;
    Phase9LocalSyntheticToken public immutable token;
    Phase9LocalSyntheticToken public immutable replacementToken;
    Phase9PayoffWrongRuntimeToken public immutable wrongRuntimeToken;
    bytes32 public immutable loanId;
    bytes32 public immutable assetId;
    bytes32 public immutable policySetHash;
    address public immutable lender;
    address public immutable feeBeneficiary;
    uint64 public immutable maximumValidity;

    Phase9Types.LoanConfiguration private _canonicalConfiguration;
    Phase9Types.DebtState private _canonicalDebt;
    bytes32 private _positionId;
    bytes32 private _trancheId;
    bytes32 private _agreementHash;
    address private _borrower;

    bytes32[] private _issuedQuoteIds;
    mapping(bytes32 quoteId => ModeledQuote model) private _models;
    mapping(bytes32 quoteId => bool seen) private _seen;
    mapping(bytes32 quoteId => IPayoffQuoteEngineV2.QuoteState state) private _lastState;
    bytes32 private _firstPolicyHash;

    uint256 public successfulIssues;
    uint256 public successfulConsumes;
    uint256 public successfulInvalidations;
    uint256 public rejectedStaleConsumes;
    uint256 public rejectedSubstitutedConsumes;
    uint256 public exactRetryChecks;
    uint256 public unknownQuoteChecks;
    uint256 public economicSnapshotChecks;

    constructor(Dependencies memory dependencies) {
        engine = dependencies.engine;
        coordinator = dependencies.coordinator;
        registry = dependencies.registry;
        factory = dependencies.factory;
        account = dependencies.account;
        positions = dependencies.positions;
        policy = dependencies.policy;
        token = dependencies.token;
        loanId = dependencies.loanId;
        assetId = dependencies.assetId;
        policySetHash = dependencies.policySetHash;
        lender = dependencies.lender;
        feeBeneficiary = dependencies.feeBeneficiary;
        maximumValidity = dependencies.maximumValidity;

        _canonicalConfiguration = account.configuration();
        _canonicalDebt = account.debtState();
        _agreementHash = _canonicalConfiguration.agreementHash;
        _borrower = _canonicalConfiguration.borrower;
        bytes32[] memory ids = positions.positionIds();
        require(ids.length == 1, "canonical position cardinality");
        Phase9Types.Position memory position_ = positions.position(ids[0]);
        _positionId = position_.positionId;
        _trancheId = position_.trancheId;

        attackerAccount = new Phase9PayoffMockAccount();
        attackerAccount.setConfiguration(_canonicalConfiguration);
        attackerAccount.setDebt(_canonicalDebt);
        attackerPositions = new Phase9PayoffMockPositionManager();
        _setPosition(attackerPositions, lender, _lenderClaim(_canonicalDebt));
        replacementToken = new Phase9LocalSyntheticToken(address(this));
        wrongRuntimeToken = new Phase9PayoffWrongRuntimeToken(address(this));
    }

    // Acceptance action: arbitrary bounded issuance under the current dependency state.
    function issue(uint32 validitySeed) external {
        uint64 validity = uint64((uint256(validitySeed) % maximumValidity) + 1);
        _attemptIssue(validity);
    }

    // Acceptance action: forward-only time movement across live and expired boundaries.
    function warp(uint32 secondsSeed) external {
        vm.warp(block.timestamp + (uint256(secondsSeed) % (2 * maximumValidity + 1)));
        _observeAllStates();
    }

    function bumpDebtVersion() external {
        Phase9Types.DebtState memory debt = account.debtState();
        if (debt.debtStateVersion < type(uint64).max) ++debt.debtStateVersion;
        account.setDebt(debt);
    }

    function mutateDebtWithoutVersion(uint8 fieldSeed, uint64 amountSeed) external {
        Phase9Types.DebtState memory debt = account.debtState();
        uint256 changed = uint256(amountSeed) + 1;
        uint8 field = fieldSeed % 5;
        if (field == 0) debt.outstandingPrincipal = changed;
        else if (field == 1) debt.accruedInterest = changed;
        else if (field == 2) debt.accruedFees = changed;
        else if (field == 3) debt.accruedPenalties = changed;
        else debt.unappliedCredit = changed;
        account.setDebt(debt);
    }

    function substituteRegistryAccount(bool substitute) external {
        _setRegistryAccount(substitute ? address(attackerAccount) : address(account));
    }

    function substituteFactoryAccount(bool substitute) external {
        address manager = factory.positionManager(loanId);
        factory.setLoan(loanId, substitute ? address(attackerAccount) : address(account), manager);
    }

    function replaceFactoryPositionManagerWithIdenticalContents(bool replace) external {
        factory.setLoan(
            loanId,
            factory.loanAccount(loanId),
            replace ? address(attackerPositions) : address(positions)
        );
    }

    function mutateAccountCoordinatorOrPositionManager(uint8 fieldSeed, bool mutate) external {
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        if (fieldSeed % 2 == 0) {
            configuration.refinanceCoordinator = mutate ? address(0xBADCA11) : address(coordinator);
        } else {
            configuration.positionManager = mutate ? address(attackerPositions) : address(positions);
        }
        account.setConfiguration(configuration);
    }

    function mutatePositionOwnerOrClaim(uint8 mutationSeed) external {
        uint8 mutation = mutationSeed % 4;
        if (mutation == 0) {
            _setPosition(positions, lender, _lenderClaim(account.debtState()));
        } else if (mutation == 1) {
            _setPosition(positions, address(0), _lenderClaim(account.debtState()));
        } else if (mutation == 2) {
            _setPosition(positions, OTHER_POSITION_BENEFICIARY, _lenderClaim(account.debtState()));
        } else {
            _setPosition(positions, lender, _lenderClaim(account.debtState()) + 1);
        }
    }

    function mutatePolicySetAndResolver(uint8 mutationSeed) external {
        uint8 mutation = mutationSeed % 4;
        bytes32 changedPolicySet = keccak256("INVARIANT_CHANGED_POLICY_SET");
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        configuration.policySetHash =
            mutation == 1 || mutation == 3 ? changedPolicySet : policySetHash;
        account.setConfiguration(configuration);
        bytes32 resolverPolicySet =
            mutation == 2 || mutation == 3 ? changedPolicySet : policySetHash;
        _setPolicy(
            resolverPolicySet,
            feeBeneficiary,
            configuration.settlementAssetId,
            configuration.settlementToken,
            maximumValidity,
            true,
            false
        );
    }

    function mutatePolicyAssetTokenBeneficiaryOrRoute(uint8 mutationSeed) external {
        _restoreCanonicalAuthorities();
        uint8 mutation = mutationSeed % 8;
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        if (mutation == 0) {
            _setPolicy(
                policySetHash, feeBeneficiary, assetId, address(token), maximumValidity, true, true
            );
        } else if (mutation == 1) {
            configuration.settlementAssetId = keccak256("INVARIANT_CHANGED_ASSET");
            account.setConfiguration(configuration);
            _setPolicy(
                policySetHash,
                feeBeneficiary,
                configuration.settlementAssetId,
                address(token),
                maximumValidity,
                true,
                false
            );
        } else if (mutation == 2) {
            configuration.settlementToken = address(replacementToken);
            account.setConfiguration(configuration);
            _setPolicy(
                policySetHash,
                feeBeneficiary,
                assetId,
                address(replacementToken),
                maximumValidity,
                true,
                false
            );
        } else if (mutation == 3) {
            configuration.settlementToken = address(wrongRuntimeToken);
            account.setConfiguration(configuration);
            _setPolicy(
                policySetHash,
                feeBeneficiary,
                assetId,
                address(wrongRuntimeToken),
                maximumValidity,
                true,
                false
            );
        } else if (mutation == 4) {
            _setPolicy(
                policySetHash,
                SUBSTITUTED_FEE_BENEFICIARY,
                assetId,
                address(token),
                maximumValidity,
                true,
                false
            );
        } else if (mutation == 5) {
            _setPosition(
                positions, SUBSTITUTED_LENDER_BENEFICIARY, _lenderClaim(account.debtState())
            );
        } else if (mutation == 6) {
            _setPolicy(
                policySetHash,
                feeBeneficiary,
                assetId,
                address(token),
                maximumValidity,
                false,
                false
            );
        } else {
            Phase9Types.DebtState memory debt = account.debtState();
            debt.accruedFees += 1;
            account.setDebt(debt);
        }
    }

    function restoreCanonicalAuthorities() external {
        _restoreCanonicalAuthorities();
    }

    function switchChainAwayOrBack(bool local) external {
        vm.chainId(local ? 31_337 : 1);
    }

    function attemptSuccessorIssueUnderChangedPolicy(bytes32 mutationSeed) external {
        _ensureQuote();
        bytes32 latestQuoteId = _issuedQuoteIds[_issuedQuoteIds.length - 1];
        _terminalizeIfLive(latestQuoteId);
        vm.chainId(31_337);
        _restoreQuoteAuthorities(latestQuoteId);
        address changedBeneficiary = address(uint160(uint256(mutationSeed)));
        if (changedBeneficiary == address(0) || changedBeneficiary == feeBeneficiary) {
            changedBeneficiary = SUBSTITUTED_FEE_BENEFICIARY;
        }
        ModeledQuote storage model = _models[latestQuoteId];
        _setPolicy(
            model.boundPolicySetHash,
            changedBeneficiary,
            model.settlementAssetId,
            model.settlementToken,
            maximumValidity,
            true,
            false
        );
        bytes32 controlsBefore = _engineControlsHash();
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(
                Phase9PayoffCoordinatorProxy.issue, (loanId, uint64(block.timestamp) + uint64(1))
            )
        );
        require(!success, "changed successor policy accepted");
        require(
            engineLogs == 0 && _engineControlsHash() == controlsBefore, "successor failure state"
        );
        _restoreQuoteAuthorities(latestQuoteId);
    }

    function forceZeroQuoteId() external {
        _prepareCollisionAttempt();
        engine.forceQuoteId(bytes32(0));
        _assertCollisionRejected(bytes32(0));
        engine.clearForcedQuoteId();
    }

    function forceMaterializedQuoteId(uint256 quoteSeed) external {
        _prepareCollisionAttempt();
        bytes32 materialized = _issuedQuoteIds[quoteSeed % _issuedQuoteIds.length];
        engine.forceQuoteId(materialized);
        _assertCollisionRejected(materialized);
        engine.clearForcedQuoteId();
    }

    function consumeExact(uint256 quoteSeed) external {
        _ensureQuote();
        bytes32 quoteId = _issuedQuoteIds[quoteSeed % _issuedQuoteIds.length];
        ModeledQuote storage model = _models[quoteId];
        bytes32 refinanceId = model.dispositionState == IPayoffQuoteEngineV2.QuoteState.CONSUMED
            ? model.refinanceId
            : _consumeRefinanceId(quoteId);
        bytes32 sourceEventId = model.dispositionState == IPayoffQuoteEngineV2.QuoteState.CONSUMED
            ? model.sourceEventId
            : _consumeSourceId(quoteId);
        _attemptConsume(quoteId, refinanceId, model.debtStateVersion, sourceEventId);
    }

    function consumeStale(uint256 quoteSeed, bool callerUsesLiveVersion) external {
        _ensureQuote();
        bytes32 quoteId = _issuedQuoteIds[quoteSeed % _issuedQuoteIds.length];
        ModeledQuote storage model = _models[quoteId];
        if (
            model.dispositionState != IPayoffQuoteEngineV2.QuoteState.NONE
                || block.timestamp >= model.validUntil
        ) return;
        vm.chainId(31_337);
        _restoreQuoteAuthorities(quoteId);
        Phase9Types.DebtState memory debt = account.debtState();
        uint64 liveVersion = debt.debtStateVersion == type(uint64).max
            ? debt.debtStateVersion - 1
            : debt.debtStateVersion + 1;
        debt.debtStateVersion = liveVersion;
        account.setDebt(debt);
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(
                Phase9PayoffCoordinatorProxy.consume,
                (
                    quoteId,
                    _consumeRefinanceId(quoteId),
                    callerUsesLiveVersion ? liveVersion : model.debtStateVersion,
                    _consumeSourceId(quoteId)
                )
            )
        );
        require(!success, "stale consume accepted");
        require(
            engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
            "stale consume state"
        );
        ++rejectedStaleConsumes;
        _restoreQuoteAuthorities(quoteId);
    }

    function consumeSubstituted(uint256 quoteSeed, uint8 substitutionSeed) external {
        _ensureQuote();
        bytes32 quoteId = _issuedQuoteIds[quoteSeed % _issuedQuoteIds.length];
        ModeledQuote storage model = _models[quoteId];
        if (
            model.dispositionState != IPayoffQuoteEngineV2.QuoteState.NONE
                || block.timestamp >= model.validUntil
        ) return;
        vm.chainId(31_337);
        _restoreQuoteAuthorities(quoteId);
        _applyConsumptionSubstitution(quoteId, substitutionSeed % 9);
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(
                Phase9PayoffCoordinatorProxy.consume,
                (
                    quoteId,
                    _consumeRefinanceId(quoteId),
                    model.debtStateVersion,
                    _consumeSourceId(quoteId)
                )
            )
        );
        require(!success, "substituted consume accepted");
        require(
            engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
            "substituted consume state"
        );
        ++rejectedSubstitutedConsumes;
        vm.chainId(31_337);
        _restoreQuoteAuthorities(quoteId);
    }

    function invalidateExact(uint256 quoteSeed) external {
        _ensureQuote();
        bytes32 quoteId = _issuedQuoteIds[quoteSeed % _issuedQuoteIds.length];
        ModeledQuote storage model = _models[quoteId];
        bytes32 sourceEventId = model.dispositionState
                == IPayoffQuoteEngineV2.QuoteState.INVALIDATED
            || model.dispositionState == IPayoffQuoteEngineV2.QuoteState.EXPIRED
            ? model.sourceEventId
            : _invalidateSourceId(quoteId);
        _attemptInvalidate(quoteId, sourceEventId);
    }

    function invalidateChanged(uint256 quoteSeed, bytes32 mutationSeed) external {
        _ensureQuote();
        bytes32 quoteId = _issuedQuoteIds[quoteSeed % _issuedQuoteIds.length];
        ModeledQuote storage model = _models[quoteId];
        if (model.dispositionState == IPayoffQuoteEngineV2.QuoteState.NONE) {
            _attemptInvalidate(quoteId, _invalidateSourceId(quoteId));
        }
        if (
            model.dispositionState != IPayoffQuoteEngineV2.QuoteState.INVALIDATED
                && model.dispositionState != IPayoffQuoteEngineV2.QuoteState.EXPIRED
        ) return;
        bytes32 changedSource = keccak256(abi.encode("CHANGED_INVALIDATION", quoteId, mutationSeed));
        if (changedSource == model.sourceEventId) {
            changedSource = bytes32(uint256(changedSource) + 1);
        }
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(Phase9PayoffCoordinatorProxy.invalidate, (quoteId, changedSource))
        );
        require(!success, "changed invalidation accepted");
        require(
            engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
            "changed invalidation state"
        );
    }

    function invalidateZeroBeforeExpiry() external {
        bytes32 quoteId = _ensureLiveCanonicalQuote();
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(Phase9PayoffCoordinatorProxy.invalidate, (quoteId, bytes32(0)))
        );
        require(!success, "zero-source invalidation accepted");
        require(
            engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
            "zero-source pre-expiry state"
        );
    }

    function invalidateZeroAfterExpiry() external {
        bytes32 quoteId = _ensureLiveCanonicalQuote();
        vm.warp(_models[quoteId].validUntil);
        _observeState(quoteId);
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(Phase9PayoffCoordinatorProxy.invalidate, (quoteId, bytes32(0)))
        );
        require(!success, "zero-source expiry persistence accepted");
        require(
            engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
            "zero-source expiry state"
        );
    }

    function retryExact(uint256 quoteSeed) external {
        _ensureQuote();
        bytes32 quoteId = _issuedQuoteIds[quoteSeed % _issuedQuoteIds.length];
        ModeledQuote storage model = _models[quoteId];
        if (model.dispositionState == IPayoffQuoteEngineV2.QuoteState.NONE) {
            _attemptInvalidate(quoteId, _invalidateSourceId(quoteId));
        }
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        bool success;
        uint256 engineLogs;
        if (model.dispositionState == IPayoffQuoteEngineV2.QuoteState.CONSUMED) {
            Phase9Types.DebtState memory debt = account.debtState();
            debt.debtStateVersion = debt.debtStateVersion == type(uint64).max
                ? debt.debtStateVersion - 1
                : debt.debtStateVersion + 1;
            account.setDebt(debt);
            (success,, engineLogs) = _callCoordinator(
                abi.encodeCall(
                    Phase9PayoffCoordinatorProxy.consume,
                    (quoteId, model.refinanceId, model.debtStateVersion, model.sourceEventId)
                )
            );
        } else {
            (success,, engineLogs) = _callCoordinator(
                abi.encodeCall(
                    Phase9PayoffCoordinatorProxy.invalidate, (quoteId, model.sourceEventId)
                )
            );
        }
        require(success, "exact retry failed");
        require(
            engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
            "exact retry effect"
        );
        ++exactRetryChecks;
    }

    function attackUnauthorized(uint32 validitySeed) external {
        Phase9PayoffUnauthorizedCaller attacker = new Phase9PayoffUnauthorizedCaller();
        uint64 validity = uint64((uint256(validitySeed) % maximumValidity) + 1);
        bytes memory data = abi.encodeCall(
            IPayoffQuoteEngineV2.issueQuote, (loanId, uint64(block.timestamp) + validity)
        );
        bytes32 controlsBefore = _engineControlsHash();
        bytes32 economicsBefore = _economicHash();
        vm.recordLogs();
        (bool success,) = address(attacker)
            .call(abi.encodeCall(Phase9PayoffUnauthorizedCaller.invoke, (address(engine), data)));
        Phase9PayoffVm.Log[] memory logs = vm.getRecordedLogs();
        require(!success, "unauthorized issue");
        require(_engineLogCount(logs) == 0, "unauthorized event");
        require(_engineControlsHash() == controlsBefore, "unauthorized engine state");
        require(_economicHash() == economicsBefore, "unauthorized economic effect");
        ++economicSnapshotChecks;
    }

    function attackUnknownQuote(bytes32 quoteSeed) external {
        bytes32 unknown = keccak256(abi.encode("INVARIANT_UNKNOWN_QUOTE", quoteSeed));
        while (_seen[unknown] || unknown == bytes32(0)) unknown = keccak256(abi.encode(unknown));
        bytes32 quoteSlot = _quoteStorageBase(unknown);
        bytes32 quoteBefore = vm.load(address(engine), quoteSlot);
        bytes32 dispositionBefore = _rawDispositionHash(unknown);
        bytes32 controlsBefore = _engineControlsHash();
        bytes32 economicsBefore = _economicHash();
        (bool readSuccess,) =
            address(engine).call(abi.encodeCall(IPayoffQuoteEngineV2.quote, (unknown)));
        (bool consumeSuccess,) = address(coordinator)
            .call(
                abi.encodeCall(
                    Phase9PayoffCoordinatorProxy.consume,
                    (unknown, bytes32(uint256(1)), uint64(1), bytes32(uint256(2)))
                )
            );
        (bool invalidateSuccess,) = address(coordinator)
            .call(
                abi.encodeCall(
                    Phase9PayoffCoordinatorProxy.invalidate, (unknown, bytes32(uint256(3)))
                )
            );
        require(!readSuccess && !consumeSuccess && !invalidateSuccess, "unknown quote accepted");
        require(vm.load(address(engine), quoteSlot) == quoteBefore, "unknown quote materialized");
        require(
            _rawDispositionHash(unknown) == dispositionBefore, "unknown disposition materialized"
        );
        require(_engineControlsHash() == controlsBefore, "unknown quote control state");
        require(_economicHash() == economicsBefore, "unknown quote economic effect");
        ++unknownQuoteChecks;
        ++economicSnapshotChecks;
    }

    function assertModel() external view {
        uint256 liveCount;
        require(_issuedQuoteIds.length == successfulIssues, "modeled issue count");
        for (uint256 index; index < _issuedQuoteIds.length; ++index) {
            bytes32 quoteId = _issuedQuoteIds[index];
            ModeledQuote storage model = _models[quoteId];
            (
                IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
                IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
            ) = engine.quote(quoteId);
            require(quote_.quoteId == quoteId && _seen[quoteId], "quote key mutation");
            require(quote_.quoteNonce == index + 1 && quote_.quoteNonce == model.nonce, "nonce gap");
            require(_normalizedTupleHash(quote_) == model.tupleHash, "tuple mutation");
            require(
                keccak256(abi.encode(components_)) == model.componentsHash, "component mutation"
            );
            require(_quoteIdAtLocal(address(engine), quote_) == quoteId, "identity mutation");
            require(quote_.policyHash == model.policyHash, "policy mutation");
            require(quote_.settlementAssetId == model.settlementAssetId, "asset mutation");
            require(quote_.settlementToken == model.settlementToken, "token mutation");
            require(
                quote_.settlementToken.codehash
                    == keccak256(type(Phase9LocalSyntheticToken).runtimeCode),
                "accepted wrong token runtime"
            );

            IPayoffQuoteEngineV2.QuoteState storedDisposition = _storedDispositionState(quoteId);
            require(storedDisposition == model.dispositionState, "disposition model mismatch");
            IPayoffQuoteEngineV2.QuoteState expectedEffective = model.dispositionState;
            if (expectedEffective == IPayoffQuoteEngineV2.QuoteState.NONE) {
                expectedEffective = block.timestamp >= model.validUntil
                    ? IPayoffQuoteEngineV2.QuoteState.EXPIRED
                    : IPayoffQuoteEngineV2.QuoteState.ISSUED;
            } else {
                _assertStoredDisposition(quoteId, model);
            }
            require(quote_.state == expectedEffective, "effective state mismatch");
            if (quote_.state == IPayoffQuoteEngineV2.QuoteState.ISSUED) ++liveCount;
            require(_terminalMonotonic(_lastState[quoteId], quote_.state), "terminal regression");
        }
        require(liveCount <= 1, "multiple live quotes");
        require(
            successfulConsumes + successfulInvalidations <= successfulIssues, "terminal overflow"
        );
        require(token.balanceOf(address(engine)) == 0, "engine token balance");
        require(token.allowance(address(engine), address(coordinator)) == 0, "engine allowance");
        require(address(engine).balance == 0, "engine ETH balance");
        require(token.totalSupply() == token.FIXED_SUPPLY_UNITS(), "synthetic supply changed");
    }

    function issuedQuoteIds() external view returns (bytes32[] memory) {
        return _issuedQuoteIds;
    }

    function _attemptIssue(uint64 validity) private returns (bool success, bytes32 quoteId) {
        if (block.timestamp > type(uint64).max - validity) return (false, bytes32(0));
        bytes32 controlsBefore = _engineControlsHash();
        bytes memory result;
        uint256 engineLogs;
        (success, result, engineLogs) = _callCoordinator(
            abi.encodeCall(
                Phase9PayoffCoordinatorProxy.issue, (loanId, uint64(block.timestamp) + validity)
            )
        );
        if (!success) {
            require(
                engineLogs == 0 && _engineControlsHash() == controlsBefore, "failed issue state"
            );
            return (false, bytes32(0));
        }
        require(engineLogs == 1, "issue event count");
        quoteId = abi.decode(result, (bytes32));
        _recordIssue(quoteId);
    }

    function _recordIssue(bytes32 quoteId) private {
        require(quoteId != bytes32(0) && !_seen[quoteId], "issued id collision");
        require(block.chainid == 31_337, "accepted nonlocal issue");
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        require(
            quote_.loanId == loanId && quote_.loanAccount == address(account), "account authority"
        );
        (address lenderBeneficiary, address feeBeneficiary_) =
            _assertComponentEvidence(quote_, components_);
        PolicyEvidence memory policyEvidence =
            _assertPolicyEvidence(quote_, lenderBeneficiary, feeBeneficiary_);
        _assertQuoteIdentityAndRuntime(quoteId, quote_, policyEvidence.settlementToken);
        _recordModeledQuote(
            quoteId, quote_, components_, policyEvidence, lenderBeneficiary, feeBeneficiary_
        );
    }

    function _assertComponentEvidence(
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
    ) private pure returns (address lenderBeneficiary, address feeBeneficiary_) {
        require(components_.length == 5, "component cardinality");
        lenderBeneficiary = components_[0].beneficiary;
        feeBeneficiary_ = components_[2].beneficiary;
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory expectedComponents =
            Phase9PayoffReference.components(
                quote_.principal,
                quote_.accruedInterest,
                quote_.fees,
                quote_.penalties,
                quote_.credits,
                lenderBeneficiary,
                feeBeneficiary_
            );
        require(
            keccak256(abi.encode(components_)) == keccak256(abi.encode(expectedComponents)),
            "component authority"
        );
        require(
            quote_.componentBeneficiaryHash
                == Phase9PayoffReference.componentHash(expectedComponents),
            "component commitment"
        );
    }

    function _assertPolicyEvidence(
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
        address lenderBeneficiary,
        address feeBeneficiary_
    ) private view returns (PolicyEvidence memory evidence) {
        {
            Phase9Types.LoanConfiguration memory configuration = account.configuration();
            (
                bytes32 resolvedPolicyHash,
                bytes32 boundPolicySetHash,
                address resolvedFeeBeneficiary,
                bytes32 resolvedAssetId,
                address resolvedToken,
                uint64 resolvedMaximum,
                bool active
            ) = policy.resolvePayoffQuotePolicy(loanId, address(account));
            bytes32 expectedPolicyHash = Phase9PayoffReference.policyHash(
                address(engine),
                address(policy),
                loanId,
                address(account),
                boundPolicySetHash,
                resolvedFeeBeneficiary,
                resolvedAssetId,
                resolvedToken,
                resolvedMaximum
            );
            require(active && resolvedPolicyHash == expectedPolicyHash, "policy source authority");
            require(quote_.policyHash == expectedPolicyHash, "policy commitment");
            require(configuration.policySetHash == boundPolicySetHash, "policy-set authority");
            require(resolvedFeeBeneficiary == feeBeneficiary_, "fee beneficiary authority");
            require(
                quote_.settlementAssetId == resolvedAssetId
                    && quote_.settlementToken == resolvedToken,
                "settlement authority"
            );
            require(resolvedMaximum == maximumValidity, "maximum authority");
            evidence = PolicyEvidence({
                policyHash: expectedPolicyHash,
                boundPolicySetHash: boundPolicySetHash,
                settlementAssetId: resolvedAssetId,
                settlementToken: resolvedToken,
                feeBeneficiary: resolvedFeeBeneficiary
            });
        }
        require(
            quote_.settlementRouteHash
                == Phase9PayoffReference.routeHash(
                    address(engine),
                    address(coordinator),
                    loanId,
                    address(account),
                    evidence.settlementAssetId,
                    evidence.settlementToken,
                    lenderBeneficiary,
                    feeBeneficiary_,
                    quote_.policyHash
                ),
            "route commitment"
        );
    }

    function _assertQuoteIdentityAndRuntime(
        bytes32 quoteId,
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
        address resolvedToken
    ) private {
        require(
            quoteId == Phase9PayoffReference.quoteIdFor(address(engine), quote_), "quote identity"
        );
        require(
            resolvedToken.codehash == keccak256(type(Phase9LocalSyntheticToken).runtimeCode),
            "token runtime authority"
        );
        if (_firstPolicyHash == bytes32(0)) _firstPolicyHash = quote_.policyHash;
        else require(quote_.policyHash == _firstPolicyHash, "successor policy drift");
    }

    function _recordModeledQuote(
        bytes32 quoteId,
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_,
        PolicyEvidence memory evidence,
        address lenderBeneficiary,
        address feeBeneficiary_
    ) private {
        ++successfulIssues;
        require(quote_.quoteNonce == successfulIssues, "successful nonce gap");
        _seen[quoteId] = true;
        _issuedQuoteIds.push(quoteId);
        ModeledQuote storage model = _models[quoteId];
        model.tupleHash = _normalizedTupleHash(quote_);
        model.componentsHash = keccak256(abi.encode(components_));
        model.policyHash = evidence.policyHash;
        model.boundPolicySetHash = evidence.boundPolicySetHash;
        model.settlementAssetId = evidence.settlementAssetId;
        model.settlementToken = evidence.settlementToken;
        model.lenderBeneficiary = lenderBeneficiary;
        model.feeBeneficiary = feeBeneficiary_;
        model.nonce = quote_.quoteNonce;
        model.debtStateVersion = quote_.debtStateVersion;
        model.validUntil = quote_.validUntil;
        _lastState[quoteId] = IPayoffQuoteEngineV2.QuoteState.ISSUED;
    }

    function _attemptConsume(
        bytes32 quoteId,
        bytes32 refinanceId,
        uint64 version,
        bytes32 sourceEventId
    ) private {
        ModeledQuote storage model = _models[quoteId];
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(
                Phase9PayoffCoordinatorProxy.consume, (quoteId, refinanceId, version, sourceEventId)
            )
        );
        if (!success) {
            require(
                engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
                "failed consume state"
            );
            return;
        }
        if (model.dispositionState == IPayoffQuoteEngineV2.QuoteState.NONE) {
            require(block.timestamp < model.validUntil, "expired consume succeeded");
            require(refinanceId != bytes32(0) && sourceEventId != bytes32(0), "zero consume id");
            require(engineLogs == 1, "consume event count");
            model.dispositionState = IPayoffQuoteEngineV2.QuoteState.CONSUMED;
            model.refinanceId = refinanceId;
            model.sourceEventId = sourceEventId;
            model.recordedAt = uint64(block.timestamp);
            ++successfulConsumes;
        } else {
            require(
                model.dispositionState == IPayoffQuoteEngineV2.QuoteState.CONSUMED
                    && model.refinanceId == refinanceId && model.sourceEventId == sourceEventId
                    && model.debtStateVersion == version,
                "nonexact consume replay succeeded"
            );
            require(
                engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
                "consume replay effect"
            );
        }
        _observeState(quoteId);
    }

    function _attemptInvalidate(bytes32 quoteId, bytes32 sourceEventId) private {
        ModeledQuote storage model = _models[quoteId];
        bytes32 dispositionBefore = _rawDispositionHash(quoteId);
        (bool success,, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(Phase9PayoffCoordinatorProxy.invalidate, (quoteId, sourceEventId))
        );
        if (!success) {
            require(
                engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
                "failed invalidation state"
            );
            return;
        }
        if (model.dispositionState == IPayoffQuoteEngineV2.QuoteState.NONE) {
            require(sourceEventId != bytes32(0), "zero invalidation source");
            require(engineLogs == 1, "invalidation event count");
            model.dispositionState = block.timestamp >= model.validUntil
                ? IPayoffQuoteEngineV2.QuoteState.EXPIRED
                : IPayoffQuoteEngineV2.QuoteState.INVALIDATED;
            model.sourceEventId = sourceEventId;
            model.recordedAt = uint64(block.timestamp);
            ++successfulInvalidations;
        } else {
            require(
                (model.dispositionState == IPayoffQuoteEngineV2.QuoteState.INVALIDATED
                        || model.dispositionState == IPayoffQuoteEngineV2.QuoteState.EXPIRED)
                    && model.sourceEventId == sourceEventId,
                "nonexact invalidation replay succeeded"
            );
            require(
                engineLogs == 0 && _rawDispositionHash(quoteId) == dispositionBefore,
                "invalidation replay effect"
            );
        }
        _observeState(quoteId);
    }

    function _applyConsumptionSubstitution(bytes32 quoteId, uint8 substitution) private {
        ModeledQuote storage model = _models[quoteId];
        if (substitution == 0) {
            Phase9Types.DebtState memory debt = account.debtState();
            debt.accruedFees += 1;
            account.setDebt(debt);
        } else if (substitution == 1) {
            factory.setLoan(loanId, address(attackerAccount), address(positions));
        } else if (substitution == 2) {
            factory.setLoan(loanId, address(account), address(attackerPositions));
        } else if (substitution == 3) {
            Phase9Types.LoanConfiguration memory configuration = account.configuration();
            configuration.refinanceCoordinator = address(0xBADCA11);
            account.setConfiguration(configuration);
        } else if (substitution == 4) {
            _setPosition(
                positions, SUBSTITUTED_LENDER_BENEFICIARY, _lenderClaim(account.debtState())
            );
        } else if (substitution == 5) {
            _setPolicy(
                model.boundPolicySetHash,
                SUBSTITUTED_FEE_BENEFICIARY,
                model.settlementAssetId,
                model.settlementToken,
                maximumValidity,
                true,
                false
            );
        } else if (substitution == 6) {
            Phase9Types.LoanConfiguration memory configuration = account.configuration();
            configuration.settlementAssetId = keccak256("SUBSTITUTED_ASSET");
            account.setConfiguration(configuration);
            _setPolicy(
                model.boundPolicySetHash,
                model.feeBeneficiary,
                configuration.settlementAssetId,
                model.settlementToken,
                maximumValidity,
                true,
                false
            );
        } else if (substitution == 7) {
            Phase9Types.LoanConfiguration memory configuration = account.configuration();
            configuration.settlementToken = address(replacementToken);
            account.setConfiguration(configuration);
            _setPolicy(
                model.boundPolicySetHash,
                model.feeBeneficiary,
                model.settlementAssetId,
                address(replacementToken),
                maximumValidity,
                true,
                false
            );
        } else {
            vm.chainId(1);
        }
    }

    function _prepareCollisionAttempt() private {
        _ensureQuote();
        bytes32 latestQuoteId = _issuedQuoteIds[_issuedQuoteIds.length - 1];
        _terminalizeIfLive(latestQuoteId);
        vm.chainId(31_337);
        _restoreQuoteAuthorities(latestQuoteId);
    }

    function _assertCollisionRejected(bytes32 forcedQuoteId) private {
        bytes32 controlsBefore = _engineControlsHash();
        bytes32 forcedRecordBefore = vm.load(address(engine), _quoteStorageBase(forcedQuoteId));
        (bool success, bytes memory result, uint256 engineLogs) = _callCoordinator(
            abi.encodeCall(
                Phase9PayoffCoordinatorProxy.issue, (loanId, uint64(block.timestamp) + uint64(1))
            )
        );
        require(!success, "forced quote id accepted");
        require(
            result.length >= 4
                && bytes4(result) == IPayoffQuoteEngineV2.QuoteReplayConflict.selector,
            "wrong collision failure"
        );
        require(engineLogs == 0 && _engineControlsHash() == controlsBefore, "collision state");
        require(
            vm.load(address(engine), _quoteStorageBase(forcedQuoteId)) == forcedRecordBefore,
            "collision record changed"
        );
    }

    function _ensureQuote() private {
        if (_issuedQuoteIds.length != 0) return;
        vm.chainId(31_337);
        _restoreCanonicalAuthorities();
        (bool success,) = _attemptIssue(1);
        require(success, "could not materialize modeled quote");
    }

    function _ensureLiveCanonicalQuote() private returns (bytes32 quoteId) {
        vm.chainId(31_337);
        if (_issuedQuoteIds.length == 0) {
            _restoreCanonicalAuthorities();
        } else {
            bytes32 latest = _issuedQuoteIds[_issuedQuoteIds.length - 1];
            ModeledQuote storage latestModel = _models[latest];
            if (
                latestModel.dispositionState == IPayoffQuoteEngineV2.QuoteState.NONE
                    && block.timestamp < latestModel.validUntil
            ) {
                _attemptInvalidate(latest, _invalidateSourceId(latest));
            }
            _restoreQuoteAuthorities(latest);
        }
        (bool success, bytes32 issued) = _attemptIssue(maximumValidity);
        require(success, "could not create live quote");
        return issued;
    }

    function _terminalizeIfLive(bytes32 quoteId) private {
        ModeledQuote storage model = _models[quoteId];
        if (
            model.dispositionState == IPayoffQuoteEngineV2.QuoteState.NONE
                && block.timestamp < model.validUntil
        ) {
            _attemptInvalidate(quoteId, _invalidateSourceId(quoteId));
        }
    }

    function _restoreCanonicalAuthorities() private {
        account.setConfiguration(_canonicalConfiguration);
        account.setDebt(_canonicalDebt);
        _setRegistryAccount(address(account));
        factory.setLoan(loanId, address(account), address(positions));
        _setPosition(positions, lender, _lenderClaim(_canonicalDebt));
        _setPolicy(
            policySetHash, feeBeneficiary, assetId, address(token), maximumValidity, true, false
        );
    }

    function _restoreQuoteAuthorities(bytes32 quoteId) private {
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        ModeledQuote storage model = _models[quoteId];
        Phase9Types.LoanConfiguration memory configuration = _canonicalConfiguration;
        configuration.policySetHash = model.boundPolicySetHash;
        configuration.settlementAssetId = model.settlementAssetId;
        configuration.settlementToken = model.settlementToken;
        account.setConfiguration(configuration);
        Phase9Types.DebtState memory debt = _canonicalDebt;
        debt.debtStateVersion = quote_.debtStateVersion;
        debt.outstandingPrincipal = quote_.principal;
        debt.accruedInterest = quote_.accruedInterest;
        debt.accruedFees = quote_.fees;
        debt.accruedPenalties = quote_.penalties;
        debt.unappliedCredit = quote_.credits;
        account.setDebt(debt);
        _setRegistryAccount(address(account));
        factory.setLoan(loanId, address(account), address(positions));
        _setPosition(positions, model.lenderBeneficiary, quote_.principal + quote_.accruedInterest);
        _setPolicy(
            model.boundPolicySetHash,
            model.feeBeneficiary,
            model.settlementAssetId,
            model.settlementToken,
            maximumValidity,
            true,
            false
        );
        require(components_.length == 5, "modeled component loss");
    }

    function _setRegistryAccount(address loanAccount) private {
        registry.setRecord(
            loanId,
            Phase9PayoffMockRegistry.Record({
                account: loanAccount,
                borrower: _borrower,
                agreementHash: _agreementHash,
                version: 9,
                exists_: true,
                terminal: false
            })
        );
    }

    function _setPosition(Phase9PayoffMockPositionManager manager, address owner, uint256 claim)
        private
    {
        Phase9Types.Position[] memory values = new Phase9Types.Position[](1);
        values[0] = Phase9Types.Position({
            positionId: _positionId,
            trancheId: _trancheId,
            owner: owner,
            votingPower: claim,
            claim: claim,
            state: Phase9Types.PositionState.ACTIVE
        });
        manager.setPositions(values);
    }

    function _setPolicy(
        bytes32 boundPolicySetHash,
        address beneficiary,
        bytes32 settlementAssetId,
        address settlementToken,
        uint64 maximum,
        bool active,
        bool opaqueDigest
    ) private {
        bytes32 digest = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            loanId,
            address(account),
            boundPolicySetHash,
            beneficiary,
            settlementAssetId,
            settlementToken,
            maximum
        );
        if (opaqueDigest) digest = bytes32(uint256(digest) + 1);
        policy.setPolicy(
            loanId,
            address(account),
            Phase9PayoffMockPolicySource.Policy({
                policyHash: digest,
                boundPolicySetHash: boundPolicySetHash,
                feePenaltyBeneficiary: beneficiary,
                settlementAssetId: settlementAssetId,
                settlementToken: settlementToken,
                maximumValidity: maximum,
                active: active
            })
        );
    }

    function _callCoordinator(bytes memory data)
        private
        returns (bool success, bytes memory result, uint256 engineLogs)
    {
        bytes32 economicsBefore = _economicHash();
        vm.recordLogs();
        (success, result) = address(coordinator).call(data);
        Phase9PayoffVm.Log[] memory logs = vm.getRecordedLogs();
        require(_economicHash() == economicsBefore, "quote action economic effect");
        ++economicSnapshotChecks;
        return (success, result, _engineLogCount(logs));
    }

    function _economicHash() private view returns (bytes32) {
        bytes32 dependencyHash = keccak256(
            abi.encode(
                account.configuration(),
                account.debtState(),
                attackerAccount.configuration(),
                attackerAccount.debtState(),
                _positionManagerHash(positions),
                _positionManagerHash(attackerPositions),
                registry.loanAccount(loanId),
                registry.protocolVersionOf(loanId),
                registry.isTerminal(loanId),
                factory.loanAccount(loanId),
                factory.positionManager(loanId)
            )
        );
        (bool policySuccess, bytes memory policyData) = address(policy)
            .staticcall(
                abi.encodeWithSelector(
                    policy.resolvePayoffQuotePolicy.selector, loanId, address(account)
                )
            );
        bytes32 tokenHash = keccak256(
            abi.encode(
                token.totalSupply(),
                token.balanceOf(address(engine)),
                token.balanceOf(address(coordinator)),
                token.balanceOf(address(account)),
                token.balanceOf(lender),
                token.balanceOf(feeBeneficiary),
                token.balanceOf(_borrower),
                token.balanceOf(OTHER_POSITION_BENEFICIARY),
                token.balanceOf(SUBSTITUTED_LENDER_BENEFICIARY),
                token.balanceOf(SUBSTITUTED_FEE_BENEFICIARY),
                token.allowance(address(engine), address(coordinator))
            )
        );
        bytes32 substituteTokenHash = keccak256(
            abi.encode(
                replacementToken.totalSupply(),
                replacementToken.balanceOf(address(engine)),
                wrongRuntimeToken.totalSupply(),
                wrongRuntimeToken.balanceOf(address(engine)),
                wrongRuntimeToken.calls()
            )
        );
        bytes32 etherHash = keccak256(
            abi.encode(
                address(engine).balance,
                address(coordinator).balance,
                address(account).balance,
                address(attackerAccount).balance,
                address(positions).balance,
                address(attackerPositions).balance,
                lender.balance,
                feeBeneficiary.balance,
                _borrower.balance,
                OTHER_POSITION_BENEFICIARY.balance,
                SUBSTITUTED_LENDER_BENEFICIARY.balance,
                SUBSTITUTED_FEE_BENEFICIARY.balance
            )
        );
        return keccak256(
            abi.encode(
                dependencyHash, policySuccess, policyData, tokenHash, substituteTokenHash, etherHash
            )
        );
    }

    function _positionManagerHash(Phase9PayoffMockPositionManager manager)
        private
        view
        returns (bytes32)
    {
        bytes32[] memory ids = manager.positionIds();
        Phase9Types.Position[] memory positionTuples = new Phase9Types.Position[](ids.length);
        for (uint256 index; index < ids.length; ++index) {
            positionTuples[index] = manager.position(ids[index]);
        }
        return keccak256(abi.encode(address(manager), ids, positionTuples));
    }

    function _engineLogCount(Phase9PayoffVm.Log[] memory logs)
        private
        view
        returns (uint256 count)
    {
        for (uint256 index; index < logs.length; ++index) {
            if (logs[index].emitter == address(engine)) ++count;
        }
    }

    function _observeAllStates() private {
        for (uint256 index; index < _issuedQuoteIds.length; ++index) {
            _observeState(_issuedQuoteIds[index]);
        }
    }

    function _observeState(bytes32 quoteId) private {
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,) = engine.quote(quoteId);
        IPayoffQuoteEngineV2.QuoteState prior = _lastState[quoteId];
        require(_terminalMonotonic(prior, quote_.state), "terminal state changed");
        _lastState[quoteId] = quote_.state;
    }

    function _terminalMonotonic(
        IPayoffQuoteEngineV2.QuoteState prior,
        IPayoffQuoteEngineV2.QuoteState current
    ) private pure returns (bool) {
        if (
            prior == IPayoffQuoteEngineV2.QuoteState.CONSUMED
                || prior == IPayoffQuoteEngineV2.QuoteState.INVALIDATED
                || prior == IPayoffQuoteEngineV2.QuoteState.EXPIRED
        ) return current == prior;
        return current == IPayoffQuoteEngineV2.QuoteState.ISSUED
            || current == IPayoffQuoteEngineV2.QuoteState.CONSUMED
            || current == IPayoffQuoteEngineV2.QuoteState.INVALIDATED
            || current == IPayoffQuoteEngineV2.QuoteState.EXPIRED;
    }

    function _assertStoredDisposition(bytes32 quoteId, ModeledQuote storage model) private view {
        bytes32 base = _dispositionStorageBase(quoteId);
        require(
            vm.load(address(engine), bytes32(uint256(base) + 1)) == model.sourceEventId, "source"
        );
        require(
            vm.load(address(engine), bytes32(uint256(base) + 2)) == model.refinanceId, "refinance"
        );
        uint256 packed = uint256(vm.load(address(engine), bytes32(uint256(base) + 3)));
        require(uint64(packed) == model.debtStateVersion, "disposition debt version");
        require(uint64(packed >> 64) == model.recordedAt, "disposition recorded time");
        require(model.sourceEventId != bytes32(0), "zero terminal source");
        if (model.dispositionState == IPayoffQuoteEngineV2.QuoteState.CONSUMED) {
            require(model.refinanceId != bytes32(0), "zero consuming refinance");
        } else {
            require(model.refinanceId == bytes32(0), "invalidation refinance");
        }
    }

    function _storedDispositionState(bytes32 quoteId)
        private
        view
        returns (IPayoffQuoteEngineV2.QuoteState)
    {
        return IPayoffQuoteEngineV2.QuoteState(
            uint8(uint256(vm.load(address(engine), _dispositionStorageBase(quoteId))))
        );
    }

    function _rawDispositionHash(bytes32 quoteId) private view returns (bytes32) {
        bytes32 base = _dispositionStorageBase(quoteId);
        return keccak256(
            abi.encode(
                vm.load(address(engine), base),
                vm.load(address(engine), bytes32(uint256(base) + 1)),
                vm.load(address(engine), bytes32(uint256(base) + 2)),
                vm.load(address(engine), bytes32(uint256(base) + 3))
            )
        );
    }

    function _engineControlsHash() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                vm.load(address(engine), keccak256(abi.encode(loanId, uint256(4)))),
                vm.load(address(engine), keccak256(abi.encode(loanId, uint256(8))))
            )
        );
    }

    function _quoteStorageBase(bytes32 quoteId) private pure returns (bytes32) {
        return keccak256(abi.encode(quoteId, uint256(5)));
    }

    function _dispositionStorageBase(bytes32 quoteId) private pure returns (bytes32) {
        return keccak256(abi.encode(quoteId, uint256(7)));
    }

    function _normalizedTupleHash(IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_)
        private
        pure
        returns (bytes32)
    {
        IPayoffQuoteEngineV2.QuoteState observedState = quote_.state;
        quote_.state = IPayoffQuoteEngineV2.QuoteState.ISSUED;
        bytes32 normalizedHash = keccak256(abi.encode(quote_));
        quote_.state = observedState;
        return normalizedHash;
    }

    function _quoteIdAtLocal(address engine_, IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_)
        private
        pure
        returns (bytes32)
    {
        QuoteIdentityFacts memory identity = QuoteIdentityFacts({
            loanId: quote_.loanId,
            loanAccount: quote_.loanAccount,
            policyHash: quote_.policyHash,
            debtStateVersion: quote_.debtStateVersion,
            principal: quote_.principal,
            accruedInterest: quote_.accruedInterest,
            fees: quote_.fees,
            penalties: quote_.penalties,
            credits: quote_.credits,
            componentBeneficiaryHash: quote_.componentBeneficiaryHash,
            netPayoff: quote_.netPayoff,
            settlementAssetId: quote_.settlementAssetId,
            settlementToken: quote_.settlementToken,
            settlementRouteHash: quote_.settlementRouteHash,
            issuedAt: quote_.issuedAt,
            validUntil: quote_.validUntil,
            quoteNonce: quote_.quoteNonce
        });
        return keccak256(abi.encode("UNIFIED_PAYOFF_QUOTE_V1", engine_, uint256(31_337), identity));
    }

    function _consumeRefinanceId(bytes32 quoteId) private pure returns (bytes32) {
        return keccak256(abi.encode("INVARIANT_REFINANCE", quoteId));
    }

    function _consumeSourceId(bytes32 quoteId) private pure returns (bytes32) {
        return keccak256(abi.encode("INVARIANT_CONSUME_SOURCE", quoteId));
    }

    function _invalidateSourceId(bytes32 quoteId) private pure returns (bytes32) {
        return keccak256(abi.encode("INVARIANT_INVALIDATE_SOURCE", quoteId));
    }

    function _lenderClaim(Phase9Types.DebtState memory debt) private pure returns (uint256) {
        return debt.outstandingPrincipal + debt.accruedInterest;
    }
}

contract Phase9PayoffQuoteInvariantTest is Phase9PayoffQuoteFixture {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    struct FuzzArtifactSelector {
        string artifact;
        bytes4[] selectors;
    }

    struct FuzzInterface {
        address addr;
        string[] artifacts;
    }

    Phase9PayoffQuoteInvariantHandler private handler;
    address[] private _targets;

    function setUp() public override {
        super.setUp();
        coordinator = new Phase9PayoffCoordinatorProxy();
        Phase9PayoffInvariantIdHarness invariantEngine = new Phase9PayoffInvariantIdHarness(
            registry, address(policy), MAX_VALIDITY, address(factory), address(coordinator)
        );
        engine = invariantEngine;
        coordinator.bind(engine);
        _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
        _setCanonicalDebt(90, 5, 3, 3, 1, 7);
        _setPositions(address(positions), LENDER, 95, 1);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(token), true);

        handler = new Phase9PayoffQuoteInvariantHandler(
            Phase9PayoffQuoteInvariantHandler.Dependencies({
                engine: invariantEngine,
                coordinator: coordinator,
                registry: registry,
                factory: factory,
                account: account,
                positions: positions,
                policy: policy,
                token: token,
                loanId: LOAN_ID,
                assetId: ASSET_ID,
                policySetHash: POLICY_SET,
                lender: LENDER,
                feeBeneficiary: FEE_BENEFICIARY,
                maximumValidity: MAX_VALIDITY
            })
        );
        _targets.push(address(handler));
    }

    function invariant_P9Q_StatefulAuthorityIdentityNonceAndDispositionModel() public view {
        handler.assertModel();
    }

    function invariant_P9Q_StatefulQuoteEngineNeverMovesTokenOrEther() public view {
        require(token.balanceOf(address(engine)) == 0, "engine token balance");
        require(token.allowance(address(engine), address(coordinator)) == 0, "engine allowance");
        require(address(engine).balance == 0, "engine ETH balance");
        require(token.totalSupply() == token.FIXED_SUPPLY_UNITS(), "synthetic supply changed");
    }

    function testInvariantHarnessCoversPositiveAndNegativeStatefulActions() public {
        FuzzSelector[] memory configuredTargets = this.targetSelectors();
        require(configuredTargets.length == 1, "target group count");
        require(configuredTargets[0].addr == address(handler), "target handler");
        require(configuredTargets[0].selectors.length == 26, "target selector count");
        require(
            configuredTargets[0].selectors[25] == handler.attackUnknownQuote.selector,
            "unknown quote action not targeted"
        );
        for (uint256 index; index < configuredTargets[0].selectors.length; ++index) {
            for (uint256 other = index + 1; other < configuredTargets[0].selectors.length; ++other) {
                require(
                    configuredTargets[0].selectors[index] != configuredTargets[0].selectors[other],
                    "duplicate target selector"
                );
            }
        }
        handler.restoreCanonicalAuthorities();
        handler.issue(1);
        handler.consumeStale(0, false);
        handler.consumeSubstituted(0, 5);
        handler.consumeExact(0);
        handler.retryExact(0);
        handler.forceZeroQuoteId();
        handler.forceMaterializedQuoteId(0);
        handler.attackUnknownQuote(bytes32(uint256(1)));
        require(handler.successfulIssues() >= 1, "handler issue evidence");
        require(handler.rejectedStaleConsumes() == 1, "handler stale evidence");
        require(handler.rejectedSubstitutedConsumes() == 1, "handler substitution evidence");
        require(handler.exactRetryChecks() == 1, "handler replay evidence");
        require(handler.unknownQuoteChecks() == 1, "handler unknown evidence");
        require(handler.economicSnapshotChecks() == 8, "handler economic action evidence");
        handler.assertModel();
    }

    function targetSelectors() external view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](26);
        selectors[0] = handler.issue.selector;
        selectors[1] = handler.warp.selector;
        selectors[2] = handler.bumpDebtVersion.selector;
        selectors[3] = handler.mutateDebtWithoutVersion.selector;
        selectors[4] = handler.substituteRegistryAccount.selector;
        selectors[5] = handler.substituteFactoryAccount.selector;
        selectors[6] = handler.replaceFactoryPositionManagerWithIdenticalContents.selector;
        selectors[7] = handler.mutateAccountCoordinatorOrPositionManager.selector;
        selectors[8] = handler.mutatePositionOwnerOrClaim.selector;
        selectors[9] = handler.mutatePolicySetAndResolver.selector;
        selectors[10] = handler.mutatePolicyAssetTokenBeneficiaryOrRoute.selector;
        selectors[11] = handler.restoreCanonicalAuthorities.selector;
        selectors[12] = handler.switchChainAwayOrBack.selector;
        selectors[13] = handler.attemptSuccessorIssueUnderChangedPolicy.selector;
        selectors[14] = handler.forceZeroQuoteId.selector;
        selectors[15] = handler.forceMaterializedQuoteId.selector;
        selectors[16] = handler.consumeExact.selector;
        selectors[17] = handler.consumeStale.selector;
        selectors[18] = handler.consumeSubstituted.selector;
        selectors[19] = handler.invalidateExact.selector;
        selectors[20] = handler.invalidateChanged.selector;
        selectors[21] = handler.invalidateZeroBeforeExpiry.selector;
        selectors[22] = handler.invalidateZeroAfterExpiry.selector;
        selectors[23] = handler.retryExact.selector;
        selectors[24] = handler.attackUnauthorized.selector;
        selectors[25] = handler.attackUnknownQuote.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector({ addr: address(handler), selectors: selectors });
    }

    function targetContracts() external view returns (address[] memory) {
        return _targets;
    }

    // Explicit empty optional-target surfaces prevent Foundry from probing missing selectors.
    function targetArtifactSelectors()
        external
        pure
        returns (FuzzArtifactSelector[] memory values)
    {
        return values;
    }

    function targetArtifacts() external pure returns (string[] memory values) {
        return values;
    }

    function excludeArtifacts() external pure returns (string[] memory values) {
        return values;
    }

    function targetSenders() external pure returns (address[] memory values) {
        return values;
    }

    function excludeSenders() external pure returns (address[] memory values) {
        return values;
    }

    function excludeContracts() external pure returns (address[] memory values) {
        return values;
    }

    function targetInterfaces() external pure returns (FuzzInterface[] memory values) {
        return values;
    }

    function excludeSelectors() external pure returns (FuzzSelector[] memory values) {
        return values;
    }
}
