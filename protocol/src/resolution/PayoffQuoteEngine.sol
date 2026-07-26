// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IPayoffQuoteEngineV2 } from "../interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { IPhase9LoanAccount } from "../interfaces/phase9/IPhase9LoanAccount.sol";
import { IPhase9LoanFactory } from "../interfaces/phase9/IPhase9LoanFactory.sol";
import { IPositionManagerV2 } from "../interfaces/phase9/IPositionManagerV2.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9LocalSyntheticToken } from "../token/Phase9LocalSyntheticToken.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice Immutable, non-value-moving payoff facts for the synthetic local Phase 9 domain.
contract PayoffQuoteEngine is IPayoffQuoteEngineV2 {
    struct QuoteDispositionV2 {
        IPayoffQuoteEngineV2.QuoteState state;
        bytes32 sourceEventId;
        bytes32 refinanceId;
        uint64 debtStateVersion;
        uint64 recordedAt;
    }

    struct PolicyFacts {
        bytes32 policyHash;
        bytes32 boundPolicySetHash;
        address feePenaltyBeneficiary;
        bytes32 settlementAssetId;
        address settlementToken;
        uint64 maximumValidity;
    }

    struct CanonicalQuoteFacts {
        bytes32 loanId;
        address loanAccount;
        bytes32 policyHash;
        uint64 debtStateVersion;
        uint256 principal;
        uint256 accruedInterest;
        uint256 fees;
        uint256 penalties;
        uint256 credits;
        uint256 grossPayoff;
        uint256 netPayoff;
        bytes32 settlementAssetId;
        address settlementToken;
        address lenderBeneficiary;
        address feePenaltyBeneficiary;
        bytes32 componentBeneficiaryHash;
        bytes32 settlementRouteHash;
        IPayoffQuoteEngineV2.PayoffComponentV2[] components;
    }

    struct LoanAuthorityFacts {
        address loanAccount;
        address positionManager;
        Phase9Types.LoanConfiguration configuration;
        Phase9Types.DebtState debt;
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

    ILoanRegistry private _loanRegistry;
    address private _quotePolicyRegistry;
    uint64 private _maximumQuoteValidity;
    address private _approvedPhase9Factory;
    address private _refinanceCoordinator;
    mapping(bytes32 loanId => uint64 nonce) private _nextQuoteNonce;
    mapping(bytes32 quoteId => IPayoffQuoteEngineV2.PayoffQuoteV2 quote_) private _quotes;
    mapping(bytes32 quoteId => IPayoffQuoteEngineV2.PayoffComponentV2[] components) private
        _quoteComponents;
    mapping(bytes32 quoteId => QuoteDispositionV2 disposition) private _quoteDispositions;
    mapping(bytes32 loanId => bytes32 quoteId) private _latestQuoteId;

    constructor(
        ILoanRegistry loanRegistry_,
        address quotePolicyRegistry_,
        uint64 maximumQuoteValidity_,
        address approvedPhase9Factory_,
        address refinanceCoordinator_
    ) {
        if (
            block.chainid != 31337 || address(loanRegistry_) == address(0)
                || quotePolicyRegistry_ == address(0) || maximumQuoteValidity_ == 0
                || approvedPhase9Factory_ == address(0) || refinanceCoordinator_ == address(0)
                || address(loanRegistry_).code.length == 0 || quotePolicyRegistry_.code.length == 0
                || approvedPhase9Factory_.code.length == 0
        ) {
            revert InvalidQuoteInput();
        }

        _loanRegistry = loanRegistry_;
        _quotePolicyRegistry = quotePolicyRegistry_;
        _maximumQuoteValidity = maximumQuoteValidity_;
        _approvedPhase9Factory = approvedPhase9Factory_;
        _refinanceCoordinator = refinanceCoordinator_;
    }

    function issueQuote(bytes32, uint64) external override returns (bytes32) {
        if (msg.data.length == 0) _phase9FrozenErrorCompatibilityMarker();
        (bytes32 loanId, uint64 validUntil) = abi.decode(msg.data[4:], (bytes32, uint64));
        return _issueQuote(loanId, validUntil);
    }

    function _issueQuote(bytes32 loanId, uint64 validUntil) private returns (bytes32 quoteId) {
        _requireCoordinator();

        uint64 issuedAt = _currentTime();
        if (
            validUntil <= issuedAt
                || uint256(validUntil) - uint256(issuedAt) > _maximumQuoteValidity
        ) {
            revert InvalidQuoteInput();
        }

        bytes32 latestQuoteId = _latestQuoteId[loanId];
        _requireNoEffectiveLiveQuote(loanId, latestQuoteId);

        CanonicalQuoteFacts memory facts = _resolveCanonicalFacts(loanId, false, 0);
        _requirePriorPolicyBinding(facts, latestQuoteId);

        uint64 quoteNonce = _nextQuoteNonce[loanId];
        if (quoteNonce == 0) {
            if (latestQuoteId != bytes32(0)) revert InvalidQuoteInput();
            quoteNonce = 1;
        }
        if (quoteNonce == type(uint64).max) revert QuoteReplayConflict(bytes32(0));

        PayoffQuoteV2 memory storedQuote = _buildQuote(facts, issuedAt, validUntil, quoteNonce);
        quoteId = storedQuote.quoteId;
        if (quoteId == bytes32(0) || _quotes[quoteId].quoteId != bytes32(0)) {
            revert QuoteReplayConflict(quoteId);
        }

        _quotes[quoteId] = storedQuote;
        for (uint256 index = 0; index < facts.components.length; ++index) {
            _quoteComponents[quoteId].push(facts.components[index]);
        }
        _latestQuoteId[loanId] = quoteId;
        _nextQuoteNonce[loanId] = quoteNonce + 1;

        _emitQuoteIssued(quoteId);
    }

    function consumeQuote(bytes32, bytes32, uint64, bytes32)
        external
        override
        returns (PayoffQuoteV2 memory)
    {
        (
            bytes32 quoteId,
            bytes32 refinanceId,
            uint64 expectedDebtStateVersion,
            bytes32 sourceEventId
        ) = abi.decode(msg.data[4:], (bytes32, bytes32, uint64, bytes32));
        return _consumeQuote(quoteId, refinanceId, expectedDebtStateVersion, sourceEventId);
    }

    function _consumeQuote(
        bytes32 quoteId,
        bytes32 refinanceId,
        uint64 expectedDebtStateVersion,
        bytes32 sourceEventId
    ) private returns (PayoffQuoteV2 memory storedQuote) {
        _requireCoordinator();
        storedQuote = _loadQuote(quoteId);
        QuoteDispositionV2 memory disposition = _quoteDispositions[quoteId];
        if (disposition.state != QuoteState.NONE) {
            if (disposition.state != QuoteState.CONSUMED) {
                revert QuoteTerminal(quoteId, disposition.state);
            }
            if (
                disposition.refinanceId != refinanceId
                    || disposition.debtStateVersion != expectedDebtStateVersion
                    || disposition.sourceEventId != sourceEventId
            ) {
                revert QuoteReplayConflict(quoteId);
            }
            storedQuote.state = QuoteState.CONSUMED;
            return storedQuote;
        }
        if (refinanceId == bytes32(0) || sourceEventId == bytes32(0)) {
            revert InvalidQuoteInput();
        }

        if (block.timestamp >= storedQuote.validUntil) {
            revert QuoteExpired(quoteId, storedQuote.validUntil);
        }
        if (expectedDebtStateVersion != storedQuote.debtStateVersion) {
            revert StaleDebtVersion(expectedDebtStateVersion, storedQuote.debtStateVersion);
        }
        if (
            storedQuote.state != QuoteState.ISSUED || storedQuote.issuedAt >= storedQuote.validUntil
                || block.timestamp < storedQuote.issuedAt
                || uint256(storedQuote.validUntil) - uint256(storedQuote.issuedAt)
                    > _maximumQuoteValidity || storedQuote.quoteNonce == 0
                || _latestQuoteId[storedQuote.loanId] != quoteId
        ) {
            revert InvalidQuoteInput();
        }

        CanonicalQuoteFacts memory facts =
            _resolveCanonicalFacts(storedQuote.loanId, true, expectedDebtStateVersion);
        PayoffQuoteV2 memory expectedQuote = _buildQuote(
            facts, storedQuote.issuedAt, storedQuote.validUntil, storedQuote.quoteNonce
        );
        if (
            keccak256(abi.encode(storedQuote)) != keccak256(abi.encode(expectedQuote))
                || !_componentsEqual(quoteId, facts.components)
        ) {
            revert InvalidQuoteInput();
        }

        uint64 recordedAt = _currentTime();
        _quoteDispositions[quoteId] = QuoteDispositionV2({
            state: QuoteState.CONSUMED,
            sourceEventId: sourceEventId,
            refinanceId: refinanceId,
            debtStateVersion: expectedDebtStateVersion,
            recordedAt: recordedAt
        });
        storedQuote.state = QuoteState.CONSUMED;

        emit PayoffQuoteDispositionRecorded(
            quoteId, refinanceId, QuoteState.CONSUMED, sourceEventId, recordedAt
        );
    }

    function invalidateQuote(bytes32, bytes32) external override {
        (bytes32 quoteId, bytes32 sourceEventId) = abi.decode(msg.data[4:], (bytes32, bytes32));
        _invalidateQuote(quoteId, sourceEventId);
    }

    function _invalidateQuote(bytes32 quoteId, bytes32 sourceEventId) private {
        _requireCoordinator();
        PayoffQuoteV2 memory storedQuote = _loadQuote(quoteId);
        if (sourceEventId == bytes32(0)) revert InvalidQuoteInput();

        QuoteDispositionV2 memory disposition = _quoteDispositions[quoteId];
        if (disposition.state != QuoteState.NONE) {
            if (
                disposition.state != QuoteState.INVALIDATED
                    && disposition.state != QuoteState.EXPIRED
            ) {
                revert QuoteTerminal(quoteId, disposition.state);
            }
            if (
                disposition.refinanceId != bytes32(0)
                    || disposition.debtStateVersion != storedQuote.debtStateVersion
                    || disposition.sourceEventId != sourceEventId
            ) {
                revert QuoteReplayConflict(quoteId);
            }
            return;
        }

        if (storedQuote.state != QuoteState.ISSUED) {
            revert QuoteTerminal(quoteId, storedQuote.state);
        }
        QuoteState terminalState =
            block.timestamp >= storedQuote.validUntil ? QuoteState.EXPIRED : QuoteState.INVALIDATED;
        uint64 recordedAt = _currentTime();
        _quoteDispositions[quoteId] = QuoteDispositionV2({
            state: terminalState,
            sourceEventId: sourceEventId,
            refinanceId: bytes32(0),
            debtStateVersion: storedQuote.debtStateVersion,
            recordedAt: recordedAt
        });

        emit PayoffQuoteDispositionRecorded(
            quoteId, bytes32(0), terminalState, sourceEventId, recordedAt
        );
    }

    function quote(bytes32 quoteId)
        external
        view
        override
        returns (PayoffQuoteV2 memory storedQuote, PayoffComponentV2[] memory components)
    {
        storedQuote = _loadQuote(quoteId);
        QuoteDispositionV2 memory disposition = _quoteDispositions[quoteId];
        if (disposition.state != QuoteState.NONE) {
            storedQuote.state = disposition.state;
        } else if (
            storedQuote.state == QuoteState.ISSUED && block.timestamp >= storedQuote.validUntil
        ) {
            storedQuote.state = QuoteState.EXPIRED;
        }
        components = _quoteComponents[quoteId];
    }

    function _resolveCanonicalFacts(
        bytes32 loanId,
        bool enforceDebtStateVersion,
        uint64 expectedDebtStateVersion
    ) private view returns (CanonicalQuoteFacts memory facts) {
        LoanAuthorityFacts memory loan = _resolveLoanAuthority(
            loanId, enforceDebtStateVersion, expectedDebtStateVersion
        );
        Phase9Types.DebtState memory debt = loan.debt;

        uint256 lenderClaim = _checkedAdd(debt.outstandingPrincipal, debt.accruedInterest);
        uint256 feePenaltyTotal = _checkedAdd(debt.accruedFees, debt.accruedPenalties);
        uint256 grossPayoff = _checkedAdd(lenderClaim, feePenaltyTotal);
        if (debt.unappliedCredit > feePenaltyTotal) revert InvalidQuoteInput();
        uint256 netPayoff = grossPayoff - debt.unappliedCredit;
        if (netPayoff == 0) revert InvalidQuoteInput();

        address lenderBeneficiary = _resolveLenderBeneficiary(loan.positionManager, lenderClaim);
        PolicyFacts memory policy = _resolvePolicy(loanId, loan.loanAccount, loan.configuration);
        PayoffComponentV2[] memory components =
            _buildComponents(debt, lenderBeneficiary, policy.feePenaltyBeneficiary);

        facts.loanId = loanId;
        facts.loanAccount = loan.loanAccount;
        facts.policyHash = policy.policyHash;
        facts.debtStateVersion = debt.debtStateVersion;
        facts.principal = debt.outstandingPrincipal;
        facts.accruedInterest = debt.accruedInterest;
        facts.fees = debt.accruedFees;
        facts.penalties = debt.accruedPenalties;
        facts.credits = debt.unappliedCredit;
        facts.grossPayoff = grossPayoff;
        facts.netPayoff = netPayoff;
        facts.settlementAssetId = policy.settlementAssetId;
        facts.settlementToken = policy.settlementToken;
        facts.lenderBeneficiary = lenderBeneficiary;
        facts.feePenaltyBeneficiary = policy.feePenaltyBeneficiary;
        facts.components = components;
        facts.componentBeneficiaryHash = _deriveComponentBeneficiaryHash(components);
        facts.settlementRouteHash = _deriveSettlementRouteHash(facts);
    }

    function _resolveLoanAuthority(
        bytes32 loanId,
        bool enforceDebtStateVersion,
        uint64 expectedDebtStateVersion
    ) private view returns (LoanAuthorityFacts memory loan) {
        if (
            block.chainid != 31337 || loanId == bytes32(0)
                || address(_loanRegistry).code.length == 0
                || _approvedPhase9Factory.code.length == 0
        ) {
            revert InvalidQuoteInput();
        }

        bool exists;
        bool terminal;
        uint32 protocolVersion;
        try _loanRegistry.exists(loanId) returns (bool exists_) {
            exists = exists_;
        } catch {
            revert InvalidQuoteInput();
        }
        try _loanRegistry.isTerminal(loanId) returns (bool terminal_) {
            terminal = terminal_;
        } catch {
            revert InvalidQuoteInput();
        }
        try _loanRegistry.protocolVersionOf(loanId) returns (uint32 protocolVersion_) {
            protocolVersion = protocolVersion_;
        } catch {
            revert InvalidQuoteInput();
        }
        try _loanRegistry.loanAccount(loanId) returns (address loanAccount_) {
            loan.loanAccount = loanAccount_;
        } catch {
            revert InvalidQuoteInput();
        }
        if (
            !exists || terminal || protocolVersion != 9 || loan.loanAccount == address(0)
                || loan.loanAccount.code.length == 0
        ) {
            revert InvalidQuoteInput();
        }

        address factoryLoanAccount;
        try IPhase9LoanFactory(_approvedPhase9Factory).loanAccount(loanId) returns (
            address factoryLoanAccount_
        ) {
            factoryLoanAccount = factoryLoanAccount_;
        } catch {
            revert InvalidQuoteInput();
        }
        try IPhase9LoanFactory(_approvedPhase9Factory).positionManager(loanId) returns (
            address positionManager_
        ) {
            loan.positionManager = positionManager_;
        } catch {
            revert InvalidQuoteInput();
        }
        if (
            factoryLoanAccount != loan.loanAccount || loan.positionManager == address(0)
                || loan.positionManager.code.length == 0
        ) {
            revert InvalidQuoteInput();
        }

        try IPhase9LoanAccount(loan.loanAccount).configuration() returns (
            Phase9Types.LoanConfiguration memory configuration_
        ) {
            loan.configuration = configuration_;
        } catch {
            revert InvalidQuoteInput();
        }
        Phase9Types.LoanConfiguration memory configuration = loan.configuration;
        if (
            configuration.loanId != loanId || configuration.loanRegistry != address(_loanRegistry)
                || configuration.factory != _approvedPhase9Factory
                || configuration.payoffQuoteEngine != address(this)
                || configuration.refinanceCoordinator != _refinanceCoordinator
                || configuration.positionManager != loan.positionManager
                || configuration.policySetHash == bytes32(0)
                || configuration.settlementAssetId == bytes32(0)
                || configuration.settlementToken == address(0)
                || configuration.settlementToken.codehash
                    != keccak256(type(Phase9LocalSyntheticToken).runtimeCode)
        ) {
            revert InvalidQuoteInput();
        }

        try IPhase9LoanAccount(loan.loanAccount).debtState() returns (
            Phase9Types.DebtState memory debt_
        ) {
            loan.debt = debt_;
        } catch {
            revert InvalidQuoteInput();
        }
        if (enforceDebtStateVersion && loan.debt.debtStateVersion != expectedDebtStateVersion) {
            revert StaleDebtVersion(expectedDebtStateVersion, loan.debt.debtStateVersion);
        }
        if (
            loan.debt.lifecycle != Phase9Types.LoanLifecycle.ACTIVE
                || !_isSupportedServicingState(loan.debt.servicingState)
                || loan.debt.capitalizedInterest != 0 || loan.debt.recoverableCosts != 0
        ) {
            revert InvalidQuoteInput();
        }
    }

    function _resolvePolicy(
        bytes32 loanId,
        address loanAccount,
        Phase9Types.LoanConfiguration memory configuration
    ) private view returns (PolicyFacts memory policy) {
        (bool success, bytes memory returnData) = _quotePolicyRegistry.staticcall(
            abi.encodeCall(
                IPhase9PayoffQuotePolicySource.resolvePayoffQuotePolicy, (loanId, loanAccount)
            )
        );
        if (!success || returnData.length != 7 * 32) {
            revert InvalidQuoteInput();
        }
        (
            bytes32 policyHashWord,
            bytes32 boundPolicySetHashWord,
            bytes32 feePenaltyBeneficiaryWord,
            bytes32 settlementAssetIdWord,
            bytes32 settlementTokenWord,
            bytes32 maximumValidityWord,
            bytes32 activeWord
        ) = abi.decode(returnData, (bytes32, bytes32, bytes32, bytes32, bytes32, bytes32, bytes32));
        if (
            uint256(feePenaltyBeneficiaryWord) > type(uint160).max
                || uint256(settlementTokenWord) > type(uint160).max
                || uint256(maximumValidityWord) > type(uint64).max || uint256(activeWord) > 1
        ) {
            revert InvalidQuoteInput();
        }
        policy = PolicyFacts({
            policyHash: policyHashWord,
            boundPolicySetHash: boundPolicySetHashWord,
            feePenaltyBeneficiary: address(uint160(uint256(feePenaltyBeneficiaryWord))),
            settlementAssetId: settlementAssetIdWord,
            settlementToken: address(uint160(uint256(settlementTokenWord))),
            maximumValidity: uint64(uint256(maximumValidityWord))
        });
        bool active = activeWord == bytes32(uint256(1));

        if (
            !active || policy.policyHash == bytes32(0)
                || policy.boundPolicySetHash != configuration.policySetHash
                || policy.feePenaltyBeneficiary == address(0)
                || policy.settlementAssetId != configuration.settlementAssetId
                || policy.settlementToken != configuration.settlementToken
                || policy.maximumValidity == 0 || policy.maximumValidity != _maximumQuoteValidity
                || _quotePolicyRegistry.code.length == 0 || policy.settlementToken.code.length == 0
                || policy.policyHash != _derivePolicyHash(loanId, loanAccount, policy)
        ) {
            revert InvalidQuoteInput();
        }
    }

    function _resolveLenderBeneficiary(address positionManager, uint256 lenderClaim)
        private
        view
        returns (address lenderBeneficiary)
    {
        bytes32[] memory positionIds;
        try IPositionManagerV2(positionManager).positionIds() returns (
            bytes32[] memory positionIds_
        ) {
            positionIds = positionIds_;
        } catch {
            revert InvalidQuoteInput();
        }
        uint256 activeCount;
        for (uint256 index = 0; index < positionIds.length; ++index) {
            Phase9Types.Position memory position_;
            try IPositionManagerV2(positionManager).position(positionIds[index]) returns (
                Phase9Types.Position memory resolvedPosition
            ) {
                position_ = resolvedPosition;
            } catch {
                revert InvalidQuoteInput();
            }
            if (position_.state == Phase9Types.PositionState.ACTIVE) {
                ++activeCount;
                if (
                    positionIds[index] == bytes32(0) || position_.owner == address(0)
                        || position_.claim != lenderClaim
                ) {
                    revert InvalidQuoteInput();
                }
                lenderBeneficiary = position_.owner;
            }
        }
        if (activeCount != 1) revert InvalidQuoteInput();
    }

    function _buildComponents(
        Phase9Types.DebtState memory debt,
        address lenderBeneficiary,
        address feePenaltyBeneficiary
    ) private pure returns (PayoffComponentV2[] memory components) {
        components = new PayoffComponentV2[](5);
        components[0] = PayoffComponentV2({
            kind: ComponentKind.PRINCIPAL,
            amount: debt.outstandingPrincipal,
            beneficiary: lenderBeneficiary,
            obligationCode: "PRINCIPAL"
        });
        components[1] = PayoffComponentV2({
            kind: ComponentKind.ACCRUED_INTEREST,
            amount: debt.accruedInterest,
            beneficiary: lenderBeneficiary,
            obligationCode: "ACCRUED_INTEREST"
        });
        components[2] = PayoffComponentV2({
            kind: ComponentKind.FEE,
            amount: debt.accruedFees,
            beneficiary: feePenaltyBeneficiary,
            obligationCode: "FEE"
        });
        components[3] = PayoffComponentV2({
            kind: ComponentKind.PENALTY,
            amount: debt.accruedPenalties,
            beneficiary: feePenaltyBeneficiary,
            obligationCode: "PENALTY"
        });
        components[4] = PayoffComponentV2({
            kind: ComponentKind.CREDIT,
            amount: debt.unappliedCredit,
            beneficiary: feePenaltyBeneficiary,
            obligationCode: "FEE_PENALTY_CREDIT"
        });
    }

    function _buildQuote(
        CanonicalQuoteFacts memory facts,
        uint64 issuedAt,
        uint64 validUntil,
        uint64 quoteNonce
    ) private view returns (PayoffQuoteV2 memory storedQuote) {
        storedQuote.loanId = facts.loanId;
        storedQuote.loanAccount = facts.loanAccount;
        storedQuote.policyHash = facts.policyHash;
        storedQuote.debtStateVersion = facts.debtStateVersion;
        storedQuote.principal = facts.principal;
        storedQuote.accruedInterest = facts.accruedInterest;
        storedQuote.fees = facts.fees;
        storedQuote.penalties = facts.penalties;
        storedQuote.credits = facts.credits;
        storedQuote.componentBeneficiaryHash = facts.componentBeneficiaryHash;
        storedQuote.grossPayoff = facts.grossPayoff;
        storedQuote.netPayoff = facts.netPayoff;
        storedQuote.settlementAssetId = facts.settlementAssetId;
        storedQuote.settlementToken = facts.settlementToken;
        storedQuote.settlementRouteHash = facts.settlementRouteHash;
        storedQuote.issuedAt = issuedAt;
        storedQuote.validUntil = validUntil;
        storedQuote.quoteNonce = quoteNonce;
        storedQuote.state = QuoteState.ISSUED;
        storedQuote.quoteId = _deriveQuoteId(storedQuote);
    }

    function _requirePriorPolicyBinding(CanonicalQuoteFacts memory facts, bytes32 latestQuoteId)
        private
        view
    {
        if (latestQuoteId == bytes32(0)) return;
        PayoffQuoteV2 storage priorQuote = _quotes[latestQuoteId];
        PayoffComponentV2[] storage priorComponents = _quoteComponents[latestQuoteId];
        if (
            priorQuote.quoteId != latestQuoteId || priorQuote.loanId != facts.loanId
                || priorQuote.loanAccount != facts.loanAccount
                || priorQuote.policyHash != facts.policyHash
                || priorQuote.settlementAssetId != facts.settlementAssetId
                || priorQuote.settlementToken != facts.settlementToken
                || priorComponents.length != 5 || priorComponents[2].kind != ComponentKind.FEE
                || priorComponents[3].kind != ComponentKind.PENALTY
                || priorComponents[4].kind != ComponentKind.CREDIT
                || priorComponents[2].beneficiary != facts.feePenaltyBeneficiary
                || priorComponents[3].beneficiary != facts.feePenaltyBeneficiary
                || priorComponents[4].beneficiary != facts.feePenaltyBeneficiary
                || keccak256(bytes(priorComponents[2].obligationCode)) != keccak256(bytes("FEE"))
                || keccak256(bytes(priorComponents[3].obligationCode))
                    != keccak256(bytes("PENALTY"))
                || keccak256(bytes(priorComponents[4].obligationCode))
                    != keccak256(bytes("FEE_PENALTY_CREDIT"))
        ) {
            revert InvalidQuoteInput();
        }
    }

    function _requireNoEffectiveLiveQuote(bytes32 loanId, bytes32 latestQuoteId) private view {
        if (latestQuoteId == bytes32(0)) return;
        PayoffQuoteV2 storage latestQuote = _quotes[latestQuoteId];
        QuoteState dispositionState = _quoteDispositions[latestQuoteId].state;
        if (
            latestQuote.quoteId != latestQuoteId || latestQuote.loanId != loanId
                || latestQuote.state != QuoteState.ISSUED
        ) {
            revert InvalidQuoteInput();
        }
        if (dispositionState == QuoteState.NONE) {
            if (block.timestamp < latestQuote.validUntil) revert InvalidQuoteInput();
            return;
        }
        if (
            dispositionState != QuoteState.CONSUMED && dispositionState != QuoteState.EXPIRED
                && dispositionState != QuoteState.INVALIDATED
        ) {
            revert InvalidQuoteInput();
        }
    }

    function _componentsEqual(bytes32 quoteId, PayoffComponentV2[] memory expectedComponents)
        private
        view
        returns (bool)
    {
        PayoffComponentV2[] storage storedComponents = _quoteComponents[quoteId];
        if (storedComponents.length != expectedComponents.length) return false;
        for (uint256 index = 0; index < expectedComponents.length; ++index) {
            if (
                keccak256(abi.encode(storedComponents[index]))
                    != keccak256(abi.encode(expectedComponents[index]))
            ) {
                return false;
            }
        }
        return true;
    }

    function _derivePolicyHash(bytes32 loanId, address loanAccount, PolicyFacts memory policy)
        internal
        view
        virtual
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_POLICY_V1",
                block.chainid,
                address(this),
                _quotePolicyRegistry,
                loanId,
                loanAccount,
                policy.boundPolicySetHash,
                policy.feePenaltyBeneficiary,
                policy.settlementAssetId,
                policy.settlementToken,
                policy.maximumValidity
            )
        );
    }

    function _deriveComponentBeneficiaryHash(PayoffComponentV2[] memory components)
        internal
        pure
        virtual
        returns (bytes32)
    {
        return keccak256(abi.encode("UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1", components));
    }

    function _deriveSettlementRouteHash(CanonicalQuoteFacts memory facts)
        internal
        view
        virtual
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1",
                block.chainid,
                address(this),
                _refinanceCoordinator,
                facts.loanId,
                facts.loanAccount,
                facts.settlementAssetId,
                facts.settlementToken,
                facts.lenderBeneficiary,
                facts.feePenaltyBeneficiary,
                facts.policyHash
            )
        );
    }

    function _deriveQuoteId(PayoffQuoteV2 memory storedQuote)
        internal
        view
        virtual
        returns (bytes32)
    {
        QuoteIdentityFacts memory identity = QuoteIdentityFacts({
            loanId: storedQuote.loanId,
            loanAccount: storedQuote.loanAccount,
            policyHash: storedQuote.policyHash,
            debtStateVersion: storedQuote.debtStateVersion,
            principal: storedQuote.principal,
            accruedInterest: storedQuote.accruedInterest,
            fees: storedQuote.fees,
            penalties: storedQuote.penalties,
            credits: storedQuote.credits,
            componentBeneficiaryHash: storedQuote.componentBeneficiaryHash,
            netPayoff: storedQuote.netPayoff,
            settlementAssetId: storedQuote.settlementAssetId,
            settlementToken: storedQuote.settlementToken,
            settlementRouteHash: storedQuote.settlementRouteHash,
            issuedAt: storedQuote.issuedAt,
            validUntil: storedQuote.validUntil,
            quoteNonce: storedQuote.quoteNonce
        });
        return
            keccak256(abi.encode("UNIFIED_PAYOFF_QUOTE_V1", address(this), block.chainid, identity));
    }

    function _loadQuote(bytes32 quoteId) private view returns (PayoffQuoteV2 memory storedQuote) {
        storedQuote = _quotes[quoteId];
        if (quoteId == bytes32(0) || storedQuote.quoteId == bytes32(0)) {
            revert UnknownQuote(quoteId);
        }
    }

    function _emitQuoteIssued(bytes32 quoteId) private {
        emit PayoffQuoteIssued(
            quoteId,
            _quotes[quoteId].loanId,
            _quotes[quoteId].debtStateVersion,
            _quotes[quoteId].componentBeneficiaryHash,
            _quotes[quoteId].grossPayoff,
            _quotes[quoteId].credits,
            _quotes[quoteId].netPayoff,
            _quotes[quoteId].settlementAssetId,
            _quotes[quoteId].settlementToken,
            _quotes[quoteId].settlementRouteHash,
            _quotes[quoteId].issuedAt,
            _quotes[quoteId].validUntil,
            _quotes[quoteId].quoteNonce
        );
    }

    function _requireCoordinator() private view {
        if (msg.sender != _refinanceCoordinator) revert UnauthorizedQuoteCaller(msg.sender);
    }

    function _currentTime() private view returns (uint64 currentTime) {
        if (block.timestamp > type(uint64).max) revert InvalidQuoteInput();
        currentTime = uint64(block.timestamp);
    }

    function _checkedAdd(uint256 left, uint256 right) private pure returns (uint256 result) {
        if (right > type(uint256).max - left) revert InvalidQuoteInput();
        result = left + right;
    }

    function _isSupportedServicingState(Phase9Types.ServicingState servicingState)
        private
        pure
        returns (bool)
    {
        return servicingState == Phase9Types.ServicingState.CURRENT
            || servicingState == Phase9Types.ServicingState.DELINQUENT
            || servicingState == Phase9Types.ServicingState.DEFAULTED;
    }

    /// @dev Retains the frozen error in compiler ABI metadata; this path is intentionally unreachable.
    function _phase9FrozenErrorCompatibilityMarker() private pure {
        revert Phase9ImplementationNotFrozen();
    }
}

interface IPhase9PayoffQuotePolicySource {
    function resolvePayoffQuotePolicy(bytes32 loanId, address loanAccount)
        external
        view
        returns (
            bytes32 policyHash,
            bytes32 boundPolicySetHash,
            address feePenaltyBeneficiary,
            bytes32 settlementAssetId,
            address settlementToken,
            uint64 maximumValidity,
            bool active
        );
}
