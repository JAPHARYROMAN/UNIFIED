// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEmergencyController } from "../interfaces/IEmergencyController.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { ICollateralCustodyV2 } from "../interfaces/phase9/ICollateralCustodyV2.sol";
import { ILienRegistry } from "../interfaces/phase9/ILienRegistry.sol";
import { IPayoffQuoteEngineV2 } from "../interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { IPhase9LoanAccount } from "../interfaces/phase9/IPhase9LoanAccount.sol";
import { IPhase9LoanFactory } from "../interfaces/phase9/IPhase9LoanFactory.sol";
import { IPositionManagerV2 } from "../interfaces/phase9/IPositionManagerV2.sol";
import { IRefinanceCoordinator } from "../interfaces/phase9/IRefinanceCoordinator.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

interface IPhase9RefinanceAssetSource {
    function resolveRefinanceAsset(bytes32 settlementAssetId)
        external
        view
        returns (
            address settlementToken,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        );

    function resolveCustodyAsset(bytes32 assetId)
        external
        view
        returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        );
}

interface IPhase9RefinancePolicySource {
    function resolveLoanCreation(bytes32 policySetHash, bytes32 loanId)
        external
        view
        returns (
            Phase9Types.LoanConfiguration memory configuration,
            uint8 creationMode,
            bytes32 bootstrapId,
            bool active
        );

    function resolveBootstrap(bytes32 bootstrapId)
        external
        view
        returns (
            bytes32 policySetHash,
            bytes32 loanId,
            Phase9Types.DebtState memory initialDebt,
            Phase9Types.Tranche[] memory initialTranches,
            Phase9Types.Position[] memory initialPositions,
            Phase9Types.CustodyRecord[] memory custodyRecords,
            Phase9Types.Lien[] memory liens,
            bool active
        );

    function resolveRefinancePolicy(bytes32 refinancePolicyHash)
        external
        view
        returns (
            bytes32 boundOldPolicySetHash,
            bytes32 boundNewPolicySetHash,
            bytes32 proposedTermsHash,
            uint64 maximumValidity,
            uint32 maximumCommitments,
            bool active,
            bytes32[] memory collateralIds,
            Phase9Types.DebtState memory replacementDebt,
            Phase9Types.Tranche[] memory replacementTranches,
            Phase9Types.Position[] memory replacementPositions
        );
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

struct Phase9RefinanceValidationContext {
    uint256 chainId;
    address coordinator;
    address loanRegistry;
    address phase9LoanFactory;
    address payoffQuoteEngine;
    address lienRegistry;
    address assetRegistry;
    address policyRegistry;
    address emergencyController;
    address treasuryFeeRecipient;
    address settlementToken;
    uint64 activeLock;
}

/// @dev Slot-zero access mirror. Padding names and positions are part of ADR 0023.
struct Phase9RefinanceStorageLayout {
    address loanRegistry;
    uint96 loanRegistryPadding;
    address phase9LoanFactory;
    uint96 phase9LoanFactoryPadding;
    address payoffQuoteEngine;
    uint96 payoffQuoteEnginePadding;
    address lienRegistry;
    uint96 lienRegistryPadding;
    address assetRegistry;
    uint96 assetRegistryPadding;
    address policyRegistry;
    uint96 policyRegistryPadding;
    address emergencyController;
    uint96 emergencyControllerPadding;
    address treasuryFeeRecipient;
    uint96 treasuryFeeRecipientPadding;
    IERC20 settlementToken;
    uint96 settlementTokenPadding;
    mapping(bytes32 oldLoanId => uint64 nonce) nextRefinanceNonce;
    mapping(bytes32 refinanceId => Phase9Types.RefinanceRecord record) refinances;
    mapping(bytes32 refinanceId => bytes32[] commitmentIds_) commitmentIds;
    mapping(bytes32 commitmentId => Phase9Types.FundingCommitment commitment) commitments;
    mapping(bytes32 refinanceId => uint256 units) escrowedUnits;
    mapping(bytes32 refinanceId => Phase9Types.RefinanceTerminalResult result) terminalResults;
    mapping(bytes32 operationId => bool processed) processedOperationIds;
}

uint64 constant PHASE9_REFINANCE_ACTIVE_MASK = uint64(1) << 63;
uint64 constant PHASE9_REFINANCE_NONCE_MASK = PHASE9_REFINANCE_ACTIVE_MASK - 1;
uint8 constant PHASE9_LOCAL_BOOTSTRAP = 1;
uint8 constant PHASE9_REFINANCE_REPLACEMENT = 2;
uint32 constant PHASE9_PROTOCOL_VERSION = 9;
bytes32 constant PHASE9_SETTLEMENT_ASSET_ID =
    0x61737365743a7068617365393a7039756e697400000000000000000000000000;
bytes32 constant PHASE9_REFINANCE_REQUEST_CAPABILITY =
    keccak256("CAPABILITY_PHASE9_REFINANCE_REQUEST");
bytes32 constant PHASE9_REFINANCE_FUNDING_CAPABILITY =
    keccak256("CAPABILITY_PHASE9_REFINANCE_FUNDING");
bytes32 constant PHASE9_LOCAL_TOKEN_RUNTIME_CODE_HASH =
    0xb4cb1bc940c6783f3ecad43dc045c0fa93b02fae77d6e874a8adaf7216c907e5;

uint256 constant PHASE9_REFINANCE_MAX_PLAN_BYTES = 22_272;

library Phase9RefinanceRequestModule {
    struct RefinancePolicyFacts {
        bytes32 oldPolicySetHash;
        bytes32 newPolicySetHash;
        bytes32 proposedTermsHash;
        uint64 maximumValidity;
        uint32 maximumCommitments;
        bool active;
        bytes32[] collateralIds;
        Phase9Types.DebtState replacementDebt;
        Phase9Types.Tranche[] replacementTranches;
        Phase9Types.Position[] replacementPositions;
    }

    struct BootstrapFacts {
        bytes32 policySetHash;
        bytes32 loanId;
        Phase9Types.DebtState debt;
        Phase9Types.Tranche[] tranches;
        Phase9Types.Position[] positions;
        Phase9Types.CustodyRecord[] custodyRecords;
        Phase9Types.Lien[] liens;
        bool active;
    }

    struct ValidationPlan {
        bytes32 domain;
        bytes32 contextHash;
        bytes32 requestHash;
        bytes32 planDigest;
        RefinancePolicyFacts policy;
        Phase9Types.LoanConfiguration replacementConfiguration;
        Phase9Types.LoanConfiguration oldConfiguration;
        address oldLoanAccount;
        address oldPositionManager;
        bytes32 bootstrapId;
        bool freshOldLoan;
        BootstrapFacts bootstrap;
    }

    struct CreationFacts {
        Phase9Types.LoanConfiguration configuration;
        uint8 mode;
        bytes32 bootstrapId;
        bool active;
    }

    struct OldLoanFacts {
        Phase9Types.LoanConfiguration configuration;
        Phase9Types.DebtState debt;
        address loanAccount;
        address positionManager;
        bytes32 bootstrapId;
        bool fresh;
    }

    struct PayoffPolicyFacts {
        bytes32 policyHash;
        bytes32 boundPolicySetHash;
        address feePenaltyBeneficiary;
        bytes32 settlementAssetId;
        address settlementToken;
        uint64 maximumValidity;
        bool active;
    }

    struct CustodyAssetFacts {
        address token;
        uint8 decimals;
        bytes32 runtimeCodeHash;
    }

    struct CustodyIdentityFields {
        uint256 chainId;
        address custody;
        address assetRegistry;
        bytes32 operationId;
        bytes32 collateralId;
        bytes32 assetId;
        address token;
        bytes32 runtimeCodeHash;
        uint8 decimals;
        bool exactBalanceDelta;
        address borrower;
        uint256 quantity;
    }

    struct RefinancePolicyIdentityFields {
        uint256 chainId;
        address coordinator;
        address policyRegistry;
        bytes32 oldLoanId;
        bytes32 newLoanId;
        address borrower;
        address oldLender;
        address newPositionManager;
        bytes32 oldPolicySetHash;
        bytes32 newPolicySetHash;
        bytes32 proposedTermsHash;
        bytes32 settlementAssetId;
        bytes32 collateralSetHash;
        uint256 fundingAmount;
        uint256 refinanceFee;
        uint256 borrowerProceeds;
        uint64 expiresAt;
        uint64 maximumValidity;
        uint32 maximumCommitments;
        bytes32 collateralIdsHash;
        bytes32 replacementDebtHash;
        bytes32 replacementTranchesHash;
        bytes32 replacementPositionsHash;
    }

    struct RefinanceIdentityFields {
        uint256 chainId;
        address coordinator;
        bytes32 oldLoanId;
        bytes32 newLoanId;
        address borrower;
        address oldLender;
        address newPositionManager;
        bytes32 quoteId;
        bytes32 componentBeneficiaryHash;
        uint256 oldNetPayoff;
        uint256 newPrincipal;
        bytes32 settlementAssetId;
        bytes32 collateralSetHash;
        uint64 lienVersion;
        bytes32 proposedTermsHash;
        bytes32 newPolicySetHash;
        uint256 fundingAmount;
        uint256 refinanceFee;
        uint256 borrowerProceeds;
        uint64 expiresAt;
        uint64 refinanceNonce;
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

    event RefinanceRequested(
        bytes32 indexed refinanceId,
        bytes32 indexed oldLoanId,
        bytes32 indexed newLoanId,
        bytes32 quoteId
    );
    event RefinanceStateTransitioned(
        bytes32 indexed refinanceId,
        Phase9Types.RefinanceState indexed previousState,
        Phase9Types.RefinanceState indexed nextState,
        uint64 stateVersion,
        bytes32 operationId,
        bytes32 evidenceHash
    );

    function begin(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request
    ) public {
        _validateRequestWire(request);
        _acquireRefinanceLock(state, request.oldLoanId, request.refinanceNonce);
    }

    function complete(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        bytes memory encodedPlan
    ) public returns (bytes32 refinanceId) {
        ValidationPlan memory plan = abi.decode(encodedPlan, (ValidationPlan));
        _validatePlan(state, request, plan);

        OldLoanFacts memory oldLoan;
        oldLoan.configuration = plan.oldConfiguration;
        oldLoan.loanAccount = plan.oldLoanAccount;
        oldLoan.positionManager = plan.oldPositionManager;
        oldLoan.bootstrapId = plan.bootstrapId;
        oldLoan.fresh = plan.freshOldLoan;
        if (oldLoan.fresh) {
            Phase9Types.LoanCreationRequest memory oldCreation = Phase9Types.LoanCreationRequest({
                oldLoanId: bytes32(0),
                newLoanNonce: 0,
                refinanceId: bytes32(0),
                configuration: plan.oldConfiguration,
                creationId: bytes32(0)
            });
            (oldLoan.loanAccount, oldLoan.positionManager) =
                IPhase9LoanFactory(state.phase9LoanFactory).createLoan(oldCreation);
            _validateLoanGraph(
                state,
                request.oldLoanId,
                request.borrower,
                plan.oldConfiguration,
                oldLoan.loanAccount,
                oldLoan.positionManager
            );
            oldLoan.debt = _accountDebt(oldLoan.loanAccount);
            if (keccak256(abi.encode(oldLoan.debt)) != keccak256(abi.encode(plan.bootstrap.debt))) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
            _installBootstrap(state, request, plan.policy, oldLoan, plan.bootstrap);
        }
        _validateLoanGraph(
            state,
            request.oldLoanId,
            request.borrower,
            plan.oldConfiguration,
            oldLoan.loanAccount,
            oldLoan.positionManager
        );
        oldLoan.debt = _accountDebt(oldLoan.loanAccount);
        _validateOldDebt(request, oldLoan.debt);
        _validateExistingLenderPosition(request, oldLoan.positionManager, oldLoan.debt);
        _preflightExistingCollateral(state, request, plan.policy, plan.oldConfiguration);

        PayoffPolicyFacts memory payoffPolicy =
            _resolvePayoffPolicy(state, request, plan.policy, oldLoan);
        bytes32 quoteId = _issueAndValidateQuote(state, request, oldLoan, payoffPolicy);
        refinanceId = _deriveRefinanceId(request, quoteId);

        (address newLoanAccount, address newPositionManager) =
            _createReplacementLoan(state, request, refinanceId, plan.replacementConfiguration);
        _validateReplacementGraph(
            state,
            request,
            refinanceId,
            plan.replacementConfiguration,
            newLoanAccount,
            newPositionManager
        );

        Phase9Types.RefinanceRecord memory accepted = request;
        accepted.refinanceId = refinanceId;
        accepted.quoteId = quoteId;
        accepted.state = Phase9Types.RefinanceState.ACCEPTED;
        accepted.stateVersion = 1;
        state.refinances[refinanceId] = accepted;

        bytes32 operationId = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_REQUEST_OPERATION_V1", block.chainid, address(this), refinanceId
            )
        );
        state.processedOperationIds[operationId] = true;
        bytes32 transitionEvidenceHash = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_STATE_TRANSITION_V1",
                block.chainid,
                address(this),
                refinanceId,
                Phase9Types.RefinanceState.NONE,
                Phase9Types.RefinanceState.ACCEPTED,
                uint64(1),
                operationId,
                operationId
            )
        );
        emit RefinanceRequested(refinanceId, request.oldLoanId, request.newLoanId, quoteId);
        emit RefinanceStateTransitioned(
            refinanceId,
            Phase9Types.RefinanceState.NONE,
            Phase9Types.RefinanceState.ACCEPTED,
            1,
            operationId,
            transitionEvidenceHash
        );
    }

    function _validatePlan(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        ValidationPlan memory plan
    ) private view {
        bytes32 contextHash = _validationContextHash(state, request.oldLoanId);
        bytes32 requestHash = keccak256(abi.encode(request));
        bytes32 bodyHash = _validationPlanBodyHash(plan);
        if (
            state.nextRefinanceNonce[request.oldLoanId]
                    != (PHASE9_REFINANCE_ACTIVE_MASK | request.refinanceNonce)
                || plan.domain != keccak256("UNIFIED_REFINANCE_VALIDATION_PLAN_V1")
                || plan.contextHash != contextHash || plan.requestHash != requestHash
                || plan.planDigest
                    != keccak256(
                        abi.encode(
                            "UNIFIED_REFINANCE_VALIDATION_PLAN_DIGEST_V1",
                            contextHash,
                            requestHash,
                            bodyHash
                        )
                    )
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validationContextHash(Phase9RefinanceStorageLayout storage state, bytes32 oldLoanId)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_VALIDATION_CONTEXT_V1",
                block.chainid,
                address(this),
                state.loanRegistry,
                state.phase9LoanFactory,
                state.payoffQuoteEngine,
                state.lienRegistry,
                state.assetRegistry,
                state.policyRegistry,
                state.emergencyController,
                state.treasuryFeeRecipient,
                address(state.settlementToken),
                state.nextRefinanceNonce[oldLoanId]
            )
        );
    }

    function _validationPlanBodyHash(ValidationPlan memory plan) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                plan.policy,
                plan.replacementConfiguration,
                plan.oldConfiguration,
                plan.oldLoanAccount,
                plan.oldPositionManager,
                plan.bootstrapId,
                plan.freshOldLoan,
                plan.bootstrap
            )
        );
    }

    function _validateRequestWire(Phase9Types.RefinanceRecord calldata request) private view {
        uint256 payoffAndFee = _checkedAdd(request.oldNetPayoff, request.refinanceFee);
        if (
            block.chainid != 31337 || block.timestamp > type(uint64).max
                || request.refinanceId != bytes32(0) || request.quoteId != bytes32(0)
                || request.state != Phase9Types.RefinanceState.NONE || request.stateVersion != 0
                || request.acceptedFunding != 0 || request.executionAttempts != 0
                || request.terminalEvidenceHash != bytes32(0) || request.oldLoanId == bytes32(0)
                || request.newLoanId == bytes32(0) || request.oldLoanId == request.newLoanId
                || request.borrower == address(0) || request.oldLender == address(0)
                || request.newPositionManager == address(0)
                || request.componentBeneficiaryHash == bytes32(0)
                || request.settlementAssetId != PHASE9_SETTLEMENT_ASSET_ID
                || request.collateralSetHash == bytes32(0) || request.lienVersion == 0
                || request.proposedTermsHash == bytes32(0) || request.newPolicySetHash == bytes32(0)
                || request.refinancePolicyHash == bytes32(0) || request.refinanceNonce == 0
                || request.refinanceNonce >= PHASE9_REFINANCE_NONCE_MASK
                || request.newLoanNonce != request.refinanceNonce
                || request.expiresAt <= block.timestamp || msg.sender != request.borrower
                || request.oldNetPayoff == 0 || request.newPrincipal == 0
                || request.fundingAmount == 0 || request.newPrincipal != request.fundingAmount
                || request.fundingAmount != _checkedAdd(payoffAndFee, request.borrowerProceeds)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _acquireRefinanceLock(
        Phase9RefinanceStorageLayout storage state,
        bytes32 oldLoanId,
        uint64 refinanceNonce
    ) private {
        uint64 raw = state.nextRefinanceNonce[oldLoanId];
        if (
            (raw & PHASE9_REFINANCE_ACTIVE_MASK) != 0 || raw == PHASE9_REFINANCE_NONCE_MASK
                || refinanceNonce != (raw == 0 ? 1 : raw)
        ) revert IRefinanceCoordinator.InvalidRefinance();
        state.nextRefinanceNonce[oldLoanId] = PHASE9_REFINANCE_ACTIVE_MASK | refinanceNonce;
    }

    function _validateCoreDependencies(Phase9RefinanceStorageLayout storage state) private view {
        if (
            state.loanRegistry.code.length == 0 || state.phase9LoanFactory.code.length == 0
                || state.payoffQuoteEngine.code.length == 0 || state.lienRegistry.code.length == 0
                || state.assetRegistry.code.length == 0 || state.policyRegistry.code.length == 0
                || state.emergencyController.code.length == 0
                || state.treasuryFeeRecipient == address(0)
                || address(state.settlementToken).code.length == 0
        ) revert IRefinanceCoordinator.InvalidRefinance();
        if (
            _addressCall(
                    state.lienRegistry,
                    abi.encodeCall(ILienRegistry.registeredRefinanceCoordinator, ())
                ) != address(this)
        ) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _requireRequestOpen(Phase9RefinanceStorageLayout storage state) private view {
        try IEmergencyController(state.emergencyController)
            .emergencyState(PHASE9_REFINANCE_REQUEST_CAPABILITY) returns (
            bool active, uint64, bytes32
        ) {
            if (active) revert IRefinanceCoordinator.InvalidRefinance();
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateSettlementAsset(
        Phase9RefinanceStorageLayout storage state,
        bytes32 settlementAssetId
    ) private view {
        if (PHASE9_LOCAL_TOKEN_RUNTIME_CODE_HASH != address(state.settlementToken).codehash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        try IPhase9RefinanceAssetSource(state.assetRegistry)
            .resolveRefinanceAsset(settlementAssetId) returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        ) {
            if (
                !active || !exactBalanceDelta || decimals != 6
                    || token != address(state.settlementToken) || runtimeCodeHash != token.codehash
                    || runtimeCodeHash != PHASE9_LOCAL_TOKEN_RUNTIME_CODE_HASH
            ) revert IRefinanceCoordinator.InvalidRefinance();
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _resolveRefinancePolicy(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request
    ) private view returns (RefinancePolicyFacts memory policy) {
        try IPhase9RefinancePolicySource(state.policyRegistry)
            .resolveRefinancePolicy(request.refinancePolicyHash) returns (
            bytes32 oldPolicySetHash,
            bytes32 newPolicySetHash,
            bytes32 proposedTermsHash,
            uint64 maximumValidity,
            uint32 maximumCommitments,
            bool active,
            bytes32[] memory collateralIds,
            Phase9Types.DebtState memory replacementDebt,
            Phase9Types.Tranche[] memory replacementTranches,
            Phase9Types.Position[] memory replacementPositions
        ) {
            policy.oldPolicySetHash = oldPolicySetHash;
            policy.newPolicySetHash = newPolicySetHash;
            policy.proposedTermsHash = proposedTermsHash;
            policy.maximumValidity = maximumValidity;
            policy.maximumCommitments = maximumCommitments;
            policy.active = active;
            policy.collateralIds = collateralIds;
            policy.replacementDebt = replacementDebt;
            policy.replacementTranches = replacementTranches;
            policy.replacementPositions = replacementPositions;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        _requireCanonicalRefinancePolicy(state, request.refinancePolicyHash, policy);
        if (
            !policy.active || policy.oldPolicySetHash == bytes32(0)
                || policy.newPolicySetHash != request.newPolicySetHash
                || policy.proposedTermsHash != request.proposedTermsHash
                || policy.maximumValidity == 0 || policy.maximumCommitments == 0
                || policy.maximumCommitments > 32 || policy.collateralIds.length == 0
                || policy.collateralIds.length > 16 || policy.replacementTranches.length == 0
                || policy.replacementTranches.length > 8 || policy.replacementPositions.length == 0
                || policy.replacementPositions.length > 32
                || uint256(request.expiresAt) - block.timestamp > policy.maximumValidity
        ) revert IRefinanceCoordinator.InvalidRefinance();
        _validateStrictIds(policy.collateralIds);
        _validateReplacementTemplate(request, policy);
        if (_deriveRefinancePolicyHash(state, request, policy) != request.refinancePolicyHash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _requireCanonicalRefinancePolicy(
        Phase9RefinanceStorageLayout storage state,
        bytes32 policyHash,
        RefinancePolicyFacts memory policy
    ) private view {
        (bool ok, bytes memory raw) = state.policyRegistry
            .staticcall(
                abi.encodeCall(IPhase9RefinancePolicySource.resolveRefinancePolicy, (policyHash))
            );
        bytes memory canonical = abi.encode(
            policy.oldPolicySetHash,
            policy.newPolicySetHash,
            policy.proposedTermsHash,
            policy.maximumValidity,
            policy.maximumCommitments,
            policy.active,
            policy.collateralIds,
            policy.replacementDebt,
            policy.replacementTranches,
            policy.replacementPositions
        );
        if (!ok || raw.length != canonical.length || keccak256(raw) != keccak256(canonical)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _resolveCreation(
        Phase9RefinanceStorageLayout storage state,
        bytes32 policySetHash,
        bytes32 loanId
    ) private view returns (CreationFacts memory creation) {
        try IPhase9RefinancePolicySource(state.policyRegistry)
            .resolveLoanCreation(policySetHash, loanId) returns (
            Phase9Types.LoanConfiguration memory configuration,
            uint8 mode,
            bytes32 bootstrapId,
            bool active
        ) {
            creation = CreationFacts(configuration, mode, bootstrapId, active);
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (bool ok, bytes memory raw) = state.policyRegistry
            .staticcall(
                abi.encodeCall(
                    IPhase9RefinancePolicySource.resolveLoanCreation, (policySetHash, loanId)
                )
            );
        bytes memory canonical = abi.encode(
            creation.configuration, creation.mode, creation.bootstrapId, creation.active
        );
        if (!ok || raw.length != canonical.length || keccak256(raw) != keccak256(canonical)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateReplacementConfiguration(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy,
        CreationFacts memory creation
    ) private view {
        bytes32 expectedNewLoanId = keccak256(
            abi.encode(
                "UNIFIED_PHASE9_REFINANCED_LOAN_V1",
                block.chainid,
                state.phase9LoanFactory,
                request.oldLoanId,
                request.borrower,
                creation.configuration.agreementHash,
                policy.newPolicySetHash,
                request.newLoanNonce
            )
        );
        if (
            !creation.active || creation.mode != PHASE9_REFINANCE_REPLACEMENT
                || creation.bootstrapId != bytes32(0)
                || creation.configuration.policySetHash != policy.newPolicySetHash
                || expectedNewLoanId != request.newLoanId
                || creation.configuration.positionManager != request.newPositionManager
        ) revert IRefinanceCoordinator.InvalidRefinance();
        _validateConfiguration(
            state,
            creation.configuration,
            request.newLoanId,
            request.borrower,
            policy.newPolicySetHash,
            true
        );
    }

    function _requireReplacementAbsent(
        Phase9RefinanceStorageLayout storage state,
        bytes32 newLoanId
    ) private view {
        if (
            _factoryLoanAccount(state, newLoanId) != address(0)
                || _factoryPositionManager(state, newLoanId) != address(0)
                || _registryLoanAccount(state, newLoanId) != address(0)
                || _registryExists(state, newLoanId)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _prepareOldLoan(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy,
        CreationFacts memory replacement
    ) private returns (OldLoanFacts memory oldLoan) {
        CreationFacts memory creation = _resolveCreation(
            state, policy.oldPolicySetHash, request.oldLoanId
        );
        if (!creation.active || creation.configuration.policySetHash != policy.oldPolicySetHash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        oldLoan.configuration = creation.configuration;
        oldLoan.loanAccount = _factoryLoanAccount(state, request.oldLoanId);
        oldLoan.positionManager = _factoryPositionManager(state, request.oldLoanId);
        address registeredAccount = _registryLoanAccount(state, request.oldLoanId);
        bool registered = _registryExists(state, request.oldLoanId);
        oldLoan.fresh = oldLoan.loanAccount == address(0);
        if (replacement.configuration.collateralCustody != creation.configuration.collateralCustody)
        {
            revert IRefinanceCoordinator.InvalidRefinance();
        }

        if (oldLoan.fresh) {
            if (
                oldLoan.positionManager != address(0) || registered
                    || registeredAccount != address(0) || creation.mode != PHASE9_LOCAL_BOOTSTRAP
                    || creation.bootstrapId
                        != _deriveBootstrapId(state, request, policy.oldPolicySetHash)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            oldLoan.bootstrapId = creation.bootstrapId;
            _validateConfiguration(
                state,
                creation.configuration,
                request.oldLoanId,
                request.borrower,
                policy.oldPolicySetHash,
                true
            );
            BootstrapFacts memory bootstrap =
                _resolveBootstrap(state, request, policy, creation.bootstrapId);
            _preflightFreshCollateral(state, request, policy, creation.configuration, bootstrap);
            Phase9Types.LoanCreationRequest memory creationRequest = Phase9Types.LoanCreationRequest({
                oldLoanId: bytes32(0),
                newLoanNonce: 0,
                refinanceId: bytes32(0),
                configuration: creation.configuration,
                creationId: bytes32(0)
            });
            (oldLoan.loanAccount, oldLoan.positionManager) =
                IPhase9LoanFactory(state.phase9LoanFactory).createLoan(creationRequest);
            _validateLoanGraph(
                state,
                request.oldLoanId,
                request.borrower,
                creation.configuration,
                oldLoan.loanAccount,
                oldLoan.positionManager
            );
            oldLoan.debt = _accountDebt(oldLoan.loanAccount);
            if (keccak256(abi.encode(oldLoan.debt)) != keccak256(abi.encode(bootstrap.debt))) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
            _installBootstrap(state, request, policy, oldLoan, bootstrap);
        } else {
            if (
                oldLoan.positionManager == address(0) || !registered
                    || registeredAccount != oldLoan.loanAccount
                    || _registryTerminal(state, request.oldLoanId)
                    || !(creation.mode == PHASE9_REFINANCE_REPLACEMENT
                        && creation.bootstrapId == bytes32(0)
                        || creation.mode == PHASE9_LOCAL_BOOTSTRAP
                        && creation.bootstrapId
                            == _deriveBootstrapId(state, request, policy.oldPolicySetHash))
            ) revert IRefinanceCoordinator.InvalidRefinance();
            _validateConfiguration(
                state,
                creation.configuration,
                request.oldLoanId,
                request.borrower,
                policy.oldPolicySetHash,
                false
            );
            _validateLoanGraph(
                state,
                request.oldLoanId,
                request.borrower,
                creation.configuration,
                oldLoan.loanAccount,
                oldLoan.positionManager
            );
            oldLoan.debt = _accountDebt(oldLoan.loanAccount);
            _validateOldDebt(request, oldLoan.debt);
            _validateExistingLenderPosition(request, oldLoan.positionManager, oldLoan.debt);
            _preflightExistingCollateral(state, request, policy, creation.configuration);
        }
    }

    function _resolveBootstrap(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy,
        bytes32 bootstrapId
    ) private view returns (BootstrapFacts memory bootstrap) {
        try IPhase9RefinancePolicySource(state.policyRegistry)
            .resolveBootstrap(bootstrapId) returns (
            bytes32 policySetHash,
            bytes32 loanId,
            Phase9Types.DebtState memory debt,
            Phase9Types.Tranche[] memory tranches,
            Phase9Types.Position[] memory positions,
            Phase9Types.CustodyRecord[] memory custodyRecords,
            Phase9Types.Lien[] memory liens,
            bool active
        ) {
            bootstrap.policySetHash = policySetHash;
            bootstrap.loanId = loanId;
            bootstrap.debt = debt;
            bootstrap.tranches = tranches;
            bootstrap.positions = positions;
            bootstrap.custodyRecords = custodyRecords;
            bootstrap.liens = liens;
            bootstrap.active = active;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        _requireCanonicalBootstrap(state, bootstrapId, bootstrap);
        if (
            !bootstrap.active || bootstrap.policySetHash != policy.oldPolicySetHash
                || bootstrap.loanId != request.oldLoanId || bootstrap.tranches.length == 0
                || bootstrap.tranches.length > 8 || bootstrap.positions.length != 1
                || bootstrap.custodyRecords.length == 0 || bootstrap.custodyRecords.length > 16
                || bootstrap.custodyRecords.length != bootstrap.liens.length
                || bootstrap.liens.length != policy.collateralIds.length
        ) revert IRefinanceCoordinator.InvalidRefinance();
        _validateOldDebt(request, bootstrap.debt);
        _validateBootstrapIssuance(request, bootstrap);
    }

    function _requireCanonicalBootstrap(
        Phase9RefinanceStorageLayout storage state,
        bytes32 bootstrapId,
        BootstrapFacts memory bootstrap
    ) private view {
        (bool ok, bytes memory raw) = state.policyRegistry
            .staticcall(
                abi.encodeCall(IPhase9RefinancePolicySource.resolveBootstrap, (bootstrapId))
            );
        bytes memory canonical = abi.encode(
            bootstrap.policySetHash,
            bootstrap.loanId,
            bootstrap.debt,
            bootstrap.tranches,
            bootstrap.positions,
            bootstrap.custodyRecords,
            bootstrap.liens,
            bootstrap.active
        );
        if (!ok || raw.length != canonical.length || keccak256(raw) != keccak256(canonical)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateBootstrapIssuance(
        Phase9Types.RefinanceRecord calldata request,
        BootstrapFacts memory bootstrap
    ) private pure {
        uint256 trancheClaims;
        bytes32 prior;
        for (uint256 i = 0; i < bootstrap.tranches.length; ++i) {
            Phase9Types.Tranche memory tranche_ = bootstrap.tranches[i];
            if (
                tranche_.trancheId == bytes32(0)
                    || (i != 0 && uint256(tranche_.trancheId) <= uint256(prior))
                    || tranche_.originalClaim == 0
                    || tranche_.outstandingClaim != tranche_.originalClaim
                    || tranche_.configurationHash == bytes32(0)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            prior = tranche_.trancheId;
            trancheClaims = _checkedAdd(trancheClaims, tranche_.outstandingClaim);
        }
        Phase9Types.Position memory position_ = bootstrap.positions[0];
        uint256 lenderClaim =
            _checkedAdd(bootstrap.debt.outstandingPrincipal, bootstrap.debt.accruedInterest);
        if (
            position_.positionId == bytes32(0) || position_.trancheId == bytes32(0)
                || position_.owner != request.oldLender || position_.votingPower == 0
                || position_.claim != lenderClaim
                || position_.state != Phase9Types.PositionState.ACTIVE
                || !_containsTranche(bootstrap.tranches, position_.trancheId)
                || trancheClaims != lenderClaim
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateOldDebt(
        Phase9Types.RefinanceRecord calldata request,
        Phase9Types.DebtState memory debt
    ) private pure {
        uint256 lenderClaim = _checkedAdd(debt.outstandingPrincipal, debt.accruedInterest);
        uint256 feePenalty = _checkedAdd(debt.accruedFees, debt.accruedPenalties);
        uint256 grossPayoff = _checkedAdd(lenderClaim, feePenalty);
        if (
            debt.lifecycle != Phase9Types.LoanLifecycle.ACTIVE
                || !(debt.servicingState == Phase9Types.ServicingState.CURRENT
                    || debt.servicingState == Phase9Types.ServicingState.DELINQUENT
                    || debt.servicingState == Phase9Types.ServicingState.DEFAULTED)
                || debt.termsVersion == 0 || debt.debtStateVersion == 0 || debt.stateNonce == 0
                || debt.scheduleHash == bytes32(0) || debt.commencementTime == 0
                || debt.maturityTime <= debt.commencementTime || lenderClaim == 0
                || debt.capitalizedInterest != 0 || debt.recoverableCosts != 0
                || debt.unappliedCredit > feePenalty || debt.coveredLossExposure != 0
                || debt.realizedLoss != 0 || debt.writtenOffAmount != 0
                || debt.recoveredAfterWriteoff != 0 || debt.activeRefinanceId != bytes32(0)
                || debt.activeRestructureId != bytes32(0)
                || grossPayoff - debt.unappliedCredit != request.oldNetPayoff
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateExistingLenderPosition(
        Phase9Types.RefinanceRecord calldata request,
        address positionManager,
        Phase9Types.DebtState memory debt
    ) private view {
        bytes32[] memory ids;
        try IPositionManagerV2(positionManager).positionIds() returns (bytes32[] memory ids_) {
            ids = ids_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        if (ids.length == 0 || ids.length > 32) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        uint256 activeCount;
        uint256 lenderClaim = _checkedAdd(debt.outstandingPrincipal, debt.accruedInterest);
        for (uint256 i = 0; i < ids.length; ++i) {
            Phase9Types.Position memory position_ = _position(positionManager, ids[i]);
            if (ids[i] == bytes32(0) || position_.positionId != ids[i]) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
            if (position_.state == Phase9Types.PositionState.ACTIVE) {
                ++activeCount;
                if (
                    position_.owner != request.oldLender || position_.claim != lenderClaim
                        || position_.trancheId == bytes32(0)
                ) revert IRefinanceCoordinator.InvalidRefinance();
            }
        }
        if (activeCount != 1) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _preflightFreshCollateral(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy,
        Phase9Types.LoanConfiguration memory configuration,
        BootstrapFacts memory bootstrap
    ) private view {
        bytes32[] memory entryHashes = new bytes32[](policy.collateralIds.length);
        for (uint256 i = 0; i < policy.collateralIds.length; ++i) {
            Phase9Types.CustodyRecord memory custodyRecord = bootstrap.custodyRecords[i];
            Phase9Types.Lien memory lienRecord = bootstrap.liens[i];
            bytes32 operationId = _bootstrapCustodyOperationId(
                state,
                request,
                policy.oldPolicySetHash,
                configuration.collateralCustody,
                policy.collateralIds[i]
            );
            _validateCollateralFields(
                request,
                policy.collateralIds[i],
                configuration.collateralCustody,
                custodyRecord,
                lienRecord
            );
            _validateFreshCustodyIdentity(
                state, configuration.collateralCustody, custodyRecord, operationId
            );
            _requireCollateralAbsent(
                state, configuration.collateralCustody, policy.collateralIds[i]
            );
            entryHashes[i] = _collateralEntryHash(lienRecord);
        }
        if (keccak256(abi.encode(entryHashes)) != request.collateralSetHash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _preflightExistingCollateral(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy,
        Phase9Types.LoanConfiguration memory configuration
    ) private view {
        bytes32[] memory entryHashes = new bytes32[](policy.collateralIds.length);
        for (uint256 i = 0; i < policy.collateralIds.length; ++i) {
            Phase9Types.CustodyRecord memory custodyRecord =
                _custody(configuration.collateralCustody, policy.collateralIds[i]);
            Phase9Types.Lien memory lienRecord = _lien(state, policy.collateralIds[i]);
            _validateCollateralFields(
                request,
                policy.collateralIds[i],
                configuration.collateralCustody,
                custodyRecord,
                lienRecord
            );
            entryHashes[i] = _collateralEntryHash(lienRecord);
        }
        if (keccak256(abi.encode(entryHashes)) != request.collateralSetHash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateCollateralFields(
        Phase9Types.RefinanceRecord calldata request,
        bytes32 collateralId,
        address custody,
        Phase9Types.CustodyRecord memory custodyRecord,
        Phase9Types.Lien memory lienRecord
    ) private pure {
        if (
            collateralId == bytes32(0) || custodyRecord.collateralId != collateralId
                || lienRecord.collateralId != collateralId || custodyRecord.assetId == bytes32(0)
                || custodyRecord.assetId != lienRecord.assetId || custodyRecord.token == address(0)
                || custodyRecord.identityHash == bytes32(0)
                || custodyRecord.borrower != request.borrower
                || lienRecord.borrower != request.borrower || custodyRecord.quantity == 0
                || custodyRecord.quantity != lienRecord.quantity
                || custodyRecord.status != Phase9Types.CustodyStatus.HELD
                || lienRecord.collateralManager != custody || lienRecord.vault != custody
                || lienRecord.seniorLoanId != request.oldLoanId
                || lienRecord.lienVersion != request.lienVersion
                || lienRecord.status != Phase9Types.LienStatus.ACTIVE
                || lienRecord.pendingRefinanceId != bytes32(0)
                || lienRecord.pendingTargetLoanId != bytes32(0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateFreshCustodyIdentity(
        Phase9RefinanceStorageLayout storage state,
        address custodyAddress,
        Phase9Types.CustodyRecord memory record_,
        bytes32 operationId
    ) private view {
        CustodyAssetFacts memory asset;
        try IPhase9RefinanceAssetSource(state.assetRegistry)
            .resolveCustodyAsset(record_.assetId) returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        ) {
            if (
                !active || !exactBalanceDelta || token != record_.token
                    || runtimeCodeHash == bytes32(0) || token.codehash != runtimeCodeHash
            ) revert IRefinanceCoordinator.InvalidRefinance();
            asset = CustodyAssetFacts(token, decimals, runtimeCodeHash);
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        CustodyIdentityFields memory fields;
        fields.chainId = block.chainid;
        fields.custody = custodyAddress;
        fields.assetRegistry = state.assetRegistry;
        fields.operationId = operationId;
        fields.collateralId = record_.collateralId;
        fields.assetId = record_.assetId;
        fields.token = asset.token;
        fields.runtimeCodeHash = asset.runtimeCodeHash;
        fields.decimals = asset.decimals;
        fields.exactBalanceDelta = true;
        fields.borrower = record_.borrower;
        fields.quantity = record_.quantity;
        if (
            record_.identityHash
                != keccak256(abi.encode("UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1", fields))
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _requireCollateralAbsent(
        Phase9RefinanceStorageLayout storage state,
        address custodyAddress,
        bytes32 collateralId
    ) private view {
        Phase9Types.CustodyRecord memory existing = _custody(custodyAddress, collateralId);
        if (existing.collateralId != bytes32(0)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        try ILienRegistry(state.lienRegistry).lien(collateralId) returns (Phase9Types.Lien memory) {
            revert IRefinanceCoordinator.InvalidRefinance();
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(ILienRegistry.UnknownLien.selector, collateralId)
                    )
            ) revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _installBootstrap(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy,
        OldLoanFacts memory oldLoan,
        BootstrapFacts memory bootstrap
    ) private {
        for (uint256 i = 0; i < bootstrap.tranches.length; ++i) {
            IPositionManagerV2(oldLoan.positionManager).registerTranche(bootstrap.tranches[i]);
        }
        for (uint256 i = 0; i < bootstrap.positions.length; ++i) {
            IPositionManagerV2(oldLoan.positionManager).issuePosition(bootstrap.positions[i]);
        }
        for (uint256 i = 0; i < bootstrap.liens.length; ++i) {
            bytes32 operationId = _bootstrapCustodyOperationId(
                state,
                request,
                policy.oldPolicySetHash,
                oldLoan.configuration.collateralCustody,
                policy.collateralIds[i]
            );
            try ICollateralCustodyV2(oldLoan.configuration.collateralCustody)
                .recordCustody(bootstrap.custodyRecords[i], operationId) { }
            catch {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
            try ILienRegistry(state.lienRegistry).registerLien(bootstrap.liens[i]) { }
            catch {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
            if (
                keccak256(
                            abi.encode(
                                _custody(
                                    oldLoan.configuration.collateralCustody, policy.collateralIds[i]
                                )
                            )
                        ) != keccak256(abi.encode(bootstrap.custodyRecords[i]))
                    || keccak256(abi.encode(_lien(state, policy.collateralIds[i])))
                        != keccak256(abi.encode(bootstrap.liens[i]))
            ) revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _resolvePayoffPolicy(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy,
        OldLoanFacts memory oldLoan
    ) private view returns (PayoffPolicyFacts memory payoff) {
        (bool ok, bytes memory raw) = state.policyRegistry
            .staticcall(
                abi.encodeCall(
                    IPhase9PayoffQuotePolicySource.resolvePayoffQuotePolicy,
                    (request.oldLoanId, oldLoan.loanAccount)
                )
            );
        if (!ok || raw.length != 7 * 32) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (
            bytes32 policyHashWord,
            bytes32 boundPolicySetHashWord,
            bytes32 beneficiaryWord,
            bytes32 settlementAssetIdWord,
            bytes32 settlementTokenWord,
            bytes32 maximumValidityWord,
            bytes32 activeWord
        ) = abi.decode(raw, (bytes32, bytes32, bytes32, bytes32, bytes32, bytes32, bytes32));
        if (
            uint256(beneficiaryWord) > type(uint160).max
                || uint256(settlementTokenWord) > type(uint160).max
                || uint256(maximumValidityWord) > type(uint64).max || uint256(activeWord) > 1
        ) revert IRefinanceCoordinator.InvalidRefinance();
        payoff = PayoffPolicyFacts({
            policyHash: policyHashWord,
            boundPolicySetHash: boundPolicySetHashWord,
            feePenaltyBeneficiary: address(uint160(uint256(beneficiaryWord))),
            settlementAssetId: settlementAssetIdWord,
            settlementToken: address(uint160(uint256(settlementTokenWord))),
            maximumValidity: uint64(uint256(maximumValidityWord)),
            active: activeWord == bytes32(uint256(1))
        });
        if (
            !payoff.active || payoff.policyHash == bytes32(0)
                || payoff.boundPolicySetHash != policy.oldPolicySetHash
                || payoff.boundPolicySetHash != oldLoan.configuration.policySetHash
                || payoff.feePenaltyBeneficiary == address(0)
                || payoff.settlementAssetId != request.settlementAssetId
                || payoff.settlementToken != address(state.settlementToken)
                || payoff.maximumValidity != policy.maximumValidity
                || payoff.policyHash
                    != _derivePayoffPolicyHash(
                        state, request.oldLoanId, oldLoan.loanAccount, payoff
                    )
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _derivePayoffPolicyHash(
        Phase9RefinanceStorageLayout storage state,
        bytes32 loanId,
        address loanAccount,
        PayoffPolicyFacts memory payoff
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_POLICY_V1",
                block.chainid,
                state.payoffQuoteEngine,
                state.policyRegistry,
                loanId,
                loanAccount,
                payoff.boundPolicySetHash,
                payoff.feePenaltyBeneficiary,
                payoff.settlementAssetId,
                payoff.settlementToken,
                payoff.maximumValidity
            )
        );
    }

    function _issueAndValidateQuote(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        OldLoanFacts memory oldLoan,
        PayoffPolicyFacts memory payoff
    ) private returns (bytes32 quoteId) {
        try IPayoffQuoteEngineV2(state.payoffQuoteEngine)
            .issueQuote(request.oldLoanId, request.expiresAt) returns (
            bytes32 quoteId_
        ) {
            quoteId = quoteId_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote;
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components;
        try IPayoffQuoteEngineV2(state.payoffQuoteEngine).quote(quoteId) returns (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) {
            quote = quote_;
            components = components_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        _validateQuote(state, request, oldLoan, payoff, quoteId, quote, components);
    }

    function _validateQuote(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        OldLoanFacts memory oldLoan,
        PayoffPolicyFacts memory payoff,
        bytes32 quoteId,
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote,
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components
    ) private view {
        uint256 lenderClaim =
            _checkedAdd(oldLoan.debt.outstandingPrincipal, oldLoan.debt.accruedInterest);
        uint256 feePenalty = _checkedAdd(oldLoan.debt.accruedFees, oldLoan.debt.accruedPenalties);
        uint256 gross = _checkedAdd(lenderClaim, feePenalty);
        if (components.length != 5) revert IRefinanceCoordinator.InvalidRefinance();
        _validateComponents(request, oldLoan.debt, payoff, components);
        bytes32 componentHash =
            keccak256(abi.encode("UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1", components));
        bytes32 routeHash = _deriveSettlementRouteHash(state, request, oldLoan, payoff);
        if (
            quote.quoteId != quoteId || quoteId == bytes32(0) || quote.loanId != request.oldLoanId
                || quote.loanAccount != oldLoan.loanAccount || quote.policyHash != payoff.policyHash
                || quote.debtStateVersion != oldLoan.debt.debtStateVersion
                || quote.principal != oldLoan.debt.outstandingPrincipal
                || quote.accruedInterest != oldLoan.debt.accruedInterest
                || quote.fees != oldLoan.debt.accruedFees
                || quote.penalties != oldLoan.debt.accruedPenalties
                || quote.credits != oldLoan.debt.unappliedCredit || quote.grossPayoff != gross
                || quote.netPayoff != gross - oldLoan.debt.unappliedCredit
                || quote.netPayoff != request.oldNetPayoff
                || quote.componentBeneficiaryHash != componentHash
                || componentHash != request.componentBeneficiaryHash
                || quote.settlementAssetId != request.settlementAssetId
                || quote.settlementToken != address(state.settlementToken)
                || quote.settlementRouteHash != routeHash
                || quote.issuedAt != uint64(block.timestamp)
                || quote.validUntil != request.expiresAt || quote.quoteNonce == 0
                || quote.state != IPayoffQuoteEngineV2.QuoteState.ISSUED
        ) revert IRefinanceCoordinator.InvalidRefinance();
        QuoteIdentityFacts memory identity = QuoteIdentityFacts({
            loanId: quote.loanId,
            loanAccount: quote.loanAccount,
            policyHash: quote.policyHash,
            debtStateVersion: quote.debtStateVersion,
            principal: quote.principal,
            accruedInterest: quote.accruedInterest,
            fees: quote.fees,
            penalties: quote.penalties,
            credits: quote.credits,
            componentBeneficiaryHash: quote.componentBeneficiaryHash,
            netPayoff: quote.netPayoff,
            settlementAssetId: quote.settlementAssetId,
            settlementToken: quote.settlementToken,
            settlementRouteHash: quote.settlementRouteHash,
            issuedAt: quote.issuedAt,
            validUntil: quote.validUntil,
            quoteNonce: quote.quoteNonce
        });
        if (
            quoteId
                != keccak256(
                    abi.encode(
                        "UNIFIED_PAYOFF_QUOTE_V1", state.payoffQuoteEngine, block.chainid, identity
                    )
                )
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _deriveSettlementRouteHash(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        OldLoanFacts memory oldLoan,
        PayoffPolicyFacts memory payoff
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1",
                block.chainid,
                state.payoffQuoteEngine,
                address(this),
                request.oldLoanId,
                oldLoan.loanAccount,
                request.settlementAssetId,
                address(state.settlementToken),
                request.oldLender,
                payoff.feePenaltyBeneficiary,
                payoff.policyHash
            )
        );
    }

    function _validateComponents(
        Phase9Types.RefinanceRecord calldata request,
        Phase9Types.DebtState memory debt,
        PayoffPolicyFacts memory payoff,
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components
    ) private pure {
        if (
            components[0].kind != IPayoffQuoteEngineV2.ComponentKind.PRINCIPAL
                || components[0].amount != debt.outstandingPrincipal
                || components[0].beneficiary != request.oldLender
                || keccak256(bytes(components[0].obligationCode)) != keccak256(bytes("PRINCIPAL"))
                || components[1].kind != IPayoffQuoteEngineV2.ComponentKind.ACCRUED_INTEREST
                || components[1].amount != debt.accruedInterest
                || components[1].beneficiary != request.oldLender
                || keccak256(bytes(components[1].obligationCode))
                    != keccak256(bytes("ACCRUED_INTEREST"))
                || components[2].kind != IPayoffQuoteEngineV2.ComponentKind.FEE
                || components[2].amount != debt.accruedFees
                || components[2].beneficiary != payoff.feePenaltyBeneficiary
                || keccak256(bytes(components[2].obligationCode)) != keccak256(bytes("FEE"))
                || components[3].kind != IPayoffQuoteEngineV2.ComponentKind.PENALTY
                || components[3].amount != debt.accruedPenalties
                || components[3].beneficiary != payoff.feePenaltyBeneficiary
                || keccak256(bytes(components[3].obligationCode)) != keccak256(bytes("PENALTY"))
                || components[4].kind != IPayoffQuoteEngineV2.ComponentKind.CREDIT
                || components[4].amount != debt.unappliedCredit
                || components[4].beneficiary != payoff.feePenaltyBeneficiary
                || keccak256(bytes(components[4].obligationCode))
                    != keccak256(bytes("FEE_PENALTY_CREDIT"))
        ) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _createReplacementLoan(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        bytes32 refinanceId,
        Phase9Types.LoanConfiguration memory configuration
    ) private returns (address loanAccount, address positionManager) {
        Phase9Types.LoanCreationRequest memory creation = Phase9Types.LoanCreationRequest({
            oldLoanId: request.oldLoanId,
            newLoanNonce: request.newLoanNonce,
            refinanceId: refinanceId,
            configuration: configuration,
            creationId: bytes32(0)
        });
        (loanAccount, positionManager) =
            IPhase9LoanFactory(state.phase9LoanFactory).createLoan(creation);
    }

    function _validateReplacementGraph(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        bytes32 refinanceId,
        Phase9Types.LoanConfiguration memory configuration,
        address loanAccount,
        address positionManager
    ) private view {
        if (refinanceId == bytes32(0) || positionManager != request.newPositionManager) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        _validateLoanGraph(
            state, request.newLoanId, request.borrower, configuration, loanAccount, positionManager
        );
        if (
            keccak256(abi.encode(_accountDebt(loanAccount)))
                    != keccak256(abi.encode(_emptyReplacementDebt()))
                || _agreementVersionHash(loanAccount, 0) != bytes32(0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateReplacementTemplate(
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy
    ) private pure {
        Phase9Types.DebtState memory debt = policy.replacementDebt;
        if (
            debt.lifecycle != Phase9Types.LoanLifecycle.ACTIVE
                || debt.servicingState != Phase9Types.ServicingState.CURRENT
                || debt.termsVersion == 0 || debt.debtStateVersion == 0 || debt.stateNonce == 0
                || debt.scheduleHash == bytes32(0) || debt.commencementTime == 0
                || debt.maturityTime <= debt.commencementTime
                || debt.outstandingPrincipal != request.newPrincipal || debt.accruedInterest != 0
                || debt.capitalizedInterest != 0 || debt.accruedFees != 0
                || debt.accruedPenalties != 0 || debt.recoverableCosts != 0
                || debt.unappliedCredit != 0 || debt.coveredLossExposure != 0
                || debt.realizedLoss != 0 || debt.writtenOffAmount != 0
                || debt.recoveredAfterWriteoff != 0 || debt.activeRefinanceId != bytes32(0)
                || debt.activeRestructureId != bytes32(0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
        uint256 trancheClaims;
        bytes32 prior;
        for (uint256 i = 0; i < policy.replacementTranches.length; ++i) {
            Phase9Types.Tranche memory tranche_ = policy.replacementTranches[i];
            if (
                tranche_.trancheId == bytes32(0)
                    || (i != 0 && uint256(tranche_.trancheId) <= uint256(prior))
                    || tranche_.originalClaim == 0
                    || tranche_.outstandingClaim != tranche_.originalClaim
                    || tranche_.configurationHash == bytes32(0)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            prior = tranche_.trancheId;
            trancheClaims = _checkedAdd(trancheClaims, tranche_.outstandingClaim);
        }
        uint256 positionClaims;
        prior = bytes32(0);
        for (uint256 i = 0; i < policy.replacementPositions.length; ++i) {
            Phase9Types.Position memory position_ = policy.replacementPositions[i];
            if (
                position_.positionId == bytes32(0)
                    || (i != 0 && uint256(position_.positionId) <= uint256(prior))
                    || position_.trancheId == bytes32(0) || position_.owner == address(0)
                    || position_.votingPower == 0 || position_.claim == 0
                    || position_.state != Phase9Types.PositionState.ACTIVE
                    || !_containsTranche(policy.replacementTranches, position_.trancheId)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            prior = position_.positionId;
            positionClaims = _checkedAdd(positionClaims, position_.claim);
        }
        if (trancheClaims != request.newPrincipal || positionClaims != request.newPrincipal) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateConfiguration(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.LoanConfiguration memory configuration,
        bytes32 loanId,
        address borrower,
        bytes32 policySetHash,
        bool managerMustBeAbsent
    ) private view {
        if (
            configuration.factory != state.phase9LoanFactory
                || configuration.loanRegistry != state.loanRegistry
                || configuration.settlementToken != address(state.settlementToken)
                || configuration.settlementAssetId != PHASE9_SETTLEMENT_ASSET_ID
                || configuration.borrower != borrower || configuration.positionManager == address(0)
                || configuration.collateralCustody.code.length == 0
                || configuration.lienRegistry != state.lienRegistry
                || configuration.payoffQuoteEngine != state.payoffQuoteEngine
                || configuration.refinanceCoordinator != address(this)
                || configuration.restructuringController.code.length == 0
                || configuration.insuranceManager.code.length == 0
                || configuration.recoveryManager.code.length == 0 || configuration.loanId != loanId
                || configuration.agreementHash == bytes32(0)
                || configuration.policySetHash != policySetHash
                || configuration.amendmentPolicyHash == bytes32(0)
                || configuration.protectionPolicyHash == bytes32(0)
                || configuration.recoveryPolicyHash == bytes32(0)
                || (managerMustBeAbsent && configuration.positionManager.code.length != 0)
                || (!managerMustBeAbsent && configuration.positionManager.code.length == 0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateLoanGraph(
        Phase9RefinanceStorageLayout storage state,
        bytes32 loanId,
        address borrower,
        Phase9Types.LoanConfiguration memory expectedConfiguration,
        address loanAccount,
        address positionManager
    ) private view {
        if (
            positionManager.code.length == 0 || _factoryLoanAccount(state, loanId) != loanAccount
                || _factoryPositionManager(state, loanId) != positionManager
                || !_registryExists(state, loanId) || _registryTerminal(state, loanId)
                || _registryLoanAccount(state, loanId) != loanAccount
                || _registryBorrower(state, loanId) != borrower
                || _registryAgreementHash(state, loanId) != expectedConfiguration.agreementHash
                || _registryProtocolVersion(state, loanId) != PHASE9_PROTOCOL_VERSION
                || keccak256(abi.encode(_accountConfiguration(loanAccount)))
                    != keccak256(abi.encode(expectedConfiguration))
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _factoryLoanAccount(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (address account)
    {
        account = _addressCall(
            state.phase9LoanFactory, abi.encodeCall(IPhase9LoanFactory.loanAccount, (loanId))
        );
    }

    function _factoryPositionManager(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (address manager)
    {
        manager = _addressCall(
            state.phase9LoanFactory, abi.encodeCall(IPhase9LoanFactory.positionManager, (loanId))
        );
    }

    function _registryLoanAccount(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (address account)
    {
        account =
            _addressCall(state.loanRegistry, abi.encodeCall(ILoanRegistry.loanAccount, (loanId)));
    }

    function _registryExists(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (bool exists)
    {
        exists = _boolCall(state.loanRegistry, abi.encodeCall(ILoanRegistry.exists, (loanId)));
    }

    function _registryTerminal(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (bool terminal)
    {
        terminal = _boolCall(state.loanRegistry, abi.encodeCall(ILoanRegistry.isTerminal, (loanId)));
    }

    function _registryBorrower(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (address borrower)
    {
        borrower = _addressCall(
            state.loanRegistry, abi.encodeCall(ILoanRegistry.borrowerOf, (loanId))
        );
    }

    function _registryAgreementHash(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (bytes32 agreementHash)
    {
        agreementHash = _wordCall(
            state.loanRegistry, abi.encodeCall(ILoanRegistry.agreementHashOf, (loanId))
        );
    }

    function _registryProtocolVersion(Phase9RefinanceStorageLayout storage state, bytes32 loanId)
        private
        view
        returns (uint32 version)
    {
        uint256 value = uint256(
            _wordCall(state.loanRegistry, abi.encodeCall(ILoanRegistry.protocolVersionOf, (loanId)))
        );
        if (value > type(uint32).max) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        version = uint32(value);
    }

    function _accountConfiguration(address account)
        private
        view
        returns (Phase9Types.LoanConfiguration memory configuration)
    {
        try IPhase9LoanAccount(account).configuration() returns (
            Phase9Types.LoanConfiguration memory configuration_
        ) {
            configuration = configuration_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _accountDebt(address account)
        private
        view
        returns (Phase9Types.DebtState memory debt)
    {
        try IPhase9LoanAccount(account).debtState() returns (Phase9Types.DebtState memory debt_) {
            debt = debt_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _agreementVersionHash(address account, uint64 version)
        private
        view
        returns (bytes32 result)
    {
        result = _wordCall(
            account, abi.encodeCall(IPhase9LoanAccount.agreementVersionHash, (version))
        );
    }

    function _wordCall(address target, bytes memory input) private view returns (bytes32 result) {
        (bool ok, bytes memory raw) = target.staticcall(input);
        if (!ok || raw.length != 32) revert IRefinanceCoordinator.InvalidRefinance();
        result = abi.decode(raw, (bytes32));
    }

    function _addressCall(address target, bytes memory input)
        private
        view
        returns (address result)
    {
        uint256 value = uint256(_wordCall(target, input));
        if (value > type(uint160).max) revert IRefinanceCoordinator.InvalidRefinance();
        result = address(uint160(value));
    }

    function _boolCall(address target, bytes memory input) private view returns (bool result) {
        uint256 value = uint256(_wordCall(target, input));
        if (value > 1) revert IRefinanceCoordinator.InvalidRefinance();
        result = value == 1;
    }

    function _position(address manager, bytes32 positionId)
        private
        view
        returns (Phase9Types.Position memory result)
    {
        try IPositionManagerV2(manager).position(positionId) returns (
            Phase9Types.Position memory result_
        ) {
            result = result_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _custody(address custodyAddress, bytes32 collateralId)
        private
        view
        returns (Phase9Types.CustodyRecord memory result)
    {
        try ICollateralCustodyV2(custodyAddress).custody(collateralId) returns (
            Phase9Types.CustodyRecord memory result_
        ) {
            result = result_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _lien(Phase9RefinanceStorageLayout storage state, bytes32 collateralId)
        private
        view
        returns (Phase9Types.Lien memory result)
    {
        try ILienRegistry(state.lienRegistry).lien(collateralId) returns (
            Phase9Types.Lien memory result_
        ) {
            result = result_;
        } catch {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _deriveRefinanceId(Phase9Types.RefinanceRecord calldata request, bytes32 quoteId)
        private
        view
        returns (bytes32)
    {
        RefinanceIdentityFields memory fields = RefinanceIdentityFields({
            chainId: block.chainid,
            coordinator: address(this),
            oldLoanId: request.oldLoanId,
            newLoanId: request.newLoanId,
            borrower: request.borrower,
            oldLender: request.oldLender,
            newPositionManager: request.newPositionManager,
            quoteId: quoteId,
            componentBeneficiaryHash: request.componentBeneficiaryHash,
            oldNetPayoff: request.oldNetPayoff,
            newPrincipal: request.newPrincipal,
            settlementAssetId: request.settlementAssetId,
            collateralSetHash: request.collateralSetHash,
            lienVersion: request.lienVersion,
            proposedTermsHash: request.proposedTermsHash,
            newPolicySetHash: request.newPolicySetHash,
            fundingAmount: request.fundingAmount,
            refinanceFee: request.refinanceFee,
            borrowerProceeds: request.borrowerProceeds,
            expiresAt: request.expiresAt,
            refinanceNonce: request.refinanceNonce
        });
        return keccak256(abi.encode("UNIFIED_REFINANCE_V1", fields));
    }

    function _deriveRefinancePolicyHash(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        RefinancePolicyFacts memory policy
    ) private view returns (bytes32) {
        RefinancePolicyIdentityFields memory fields =
            RefinancePolicyIdentityFields({
                chainId: block.chainid,
                coordinator: address(this),
                policyRegistry: state.policyRegistry,
                oldLoanId: request.oldLoanId,
                newLoanId: request.newLoanId,
                borrower: request.borrower,
                oldLender: request.oldLender,
                newPositionManager: request.newPositionManager,
                oldPolicySetHash: policy.oldPolicySetHash,
                newPolicySetHash: policy.newPolicySetHash,
                proposedTermsHash: policy.proposedTermsHash,
                settlementAssetId: request.settlementAssetId,
                collateralSetHash: request.collateralSetHash,
                fundingAmount: request.fundingAmount,
                refinanceFee: request.refinanceFee,
                borrowerProceeds: request.borrowerProceeds,
                expiresAt: request.expiresAt,
                maximumValidity: policy.maximumValidity,
                maximumCommitments: policy.maximumCommitments,
                collateralIdsHash: keccak256(abi.encode(policy.collateralIds)),
                replacementDebtHash: keccak256(abi.encode(policy.replacementDebt)),
                replacementTranchesHash: keccak256(abi.encode(policy.replacementTranches)),
                replacementPositionsHash: keccak256(abi.encode(policy.replacementPositions))
            });
        return keccak256(abi.encode("UNIFIED_REFINANCE_POLICY_V1", fields));
    }

    function _deriveBootstrapId(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        bytes32 oldPolicySetHash
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_LOCAL_BOOTSTRAP_V1",
                block.chainid,
                state.phase9LoanFactory,
                state.policyRegistry,
                request.oldLoanId,
                request.borrower,
                oldPolicySetHash
            )
        );
    }

    function _bootstrapCustodyOperationId(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord calldata request,
        bytes32 oldPolicySetHash,
        address custody,
        bytes32 collateralId
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_V1",
                block.chainid,
                address(this),
                _deriveBootstrapId(state, request, oldPolicySetHash),
                request.oldLoanId,
                custody,
                collateralId
            )
        );
    }

    function _collateralEntryHash(Phase9Types.Lien memory lienRecord)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                lienRecord.collateralId,
                lienRecord.assetId,
                lienRecord.quantity,
                lienRecord.vault,
                lienRecord.borrower,
                lienRecord.lienVersion
            )
        );
    }

    function _validateStrictIds(bytes32[] memory ids) private pure {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (ids[i] == bytes32(0) || (i != 0 && uint256(ids[i]) <= uint256(ids[i - 1]))) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
        }
    }

    function _containsTranche(Phase9Types.Tranche[] memory tranches, bytes32 trancheId)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < tranches.length; ++i) {
            if (tranches[i].trancheId == trancheId) return true;
        }
        return false;
    }

    function _emptyReplacementDebt() private pure returns (Phase9Types.DebtState memory debt) {
        debt.lifecycle = Phase9Types.LoanLifecycle.CREATED;
        debt.servicingState = Phase9Types.ServicingState.NONE;
    }

    function _checkedAdd(uint256 left, uint256 right) private pure returns (uint256 result) {
        if (left > type(uint256).max - right) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        unchecked {
            result = left + right;
        }
    }
}

library Phase9RefinanceValidationModule {
    function preflight(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request
    ) public view returns (bytes memory encodedPlan) {
        _validateContext(context, request);
        _validateRequestEnvironment(context, request);

        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy =
            _resolveRefinancePolicy(context, request);
        Phase9RefinanceRequestModule.CreationFacts memory replacement =
            _resolveCreation(context, policy.newPolicySetHash, request.newLoanId);
        _validateReplacementConfiguration(context, request, policy, replacement);
        _requireReplacementAbsent(context, request.newLoanId);

        Phase9RefinanceRequestModule.CreationFacts memory oldCreation =
            _resolveCreation(context, policy.oldPolicySetHash, request.oldLoanId);
        if (
            !oldCreation.active
                || oldCreation.configuration.policySetHash != policy.oldPolicySetHash
                || oldCreation.configuration.collateralCustody
                    != replacement.configuration.collateralCustody
        ) revert IRefinanceCoordinator.InvalidRefinance();

        address oldLoanAccount = _factoryLoanAccount(context, request.oldLoanId);
        address oldPositionManager = _factoryPositionManager(context, request.oldLoanId);
        address registeredAccount = _registryLoanAccount(context, request.oldLoanId);
        bool registered = _registryExists(context, request.oldLoanId);
        bool fresh = oldLoanAccount == address(0);
        Phase9RefinanceRequestModule.BootstrapFacts memory bootstrap;

        if (fresh) {
            bytes32 expectedBootstrapId =
                _deriveBootstrapId(context, request, policy.oldPolicySetHash);
            if (
                oldPositionManager != address(0) || registered || registeredAccount != address(0)
                    || oldCreation.mode != PHASE9_LOCAL_BOOTSTRAP
                    || oldCreation.bootstrapId != expectedBootstrapId
            ) revert IRefinanceCoordinator.InvalidRefinance();
            _validateConfiguration(
                context,
                oldCreation.configuration,
                request.oldLoanId,
                request.borrower,
                policy.oldPolicySetHash,
                true
            );
            bootstrap = _resolveBootstrap(context, request, policy, oldCreation.bootstrapId);
            _preflightFreshCollateral(
                context, request, policy, oldCreation.configuration, bootstrap
            );
        } else {
            if (
                oldPositionManager == address(0) || !registered
                    || registeredAccount != oldLoanAccount
                    || _registryTerminal(context, request.oldLoanId)
                    || !(oldCreation.mode == PHASE9_REFINANCE_REPLACEMENT
                        && oldCreation.bootstrapId == bytes32(0)
                        || oldCreation.mode == PHASE9_LOCAL_BOOTSTRAP
                        && oldCreation.bootstrapId
                            == _deriveBootstrapId(context, request, policy.oldPolicySetHash))
            ) revert IRefinanceCoordinator.InvalidRefinance();
            _validateConfiguration(
                context,
                oldCreation.configuration,
                request.oldLoanId,
                request.borrower,
                policy.oldPolicySetHash,
                false
            );
            _validateLoanGraph(
                context,
                request.oldLoanId,
                request.borrower,
                oldCreation.configuration,
                oldLoanAccount,
                oldPositionManager
            );
            Phase9Types.DebtState memory debt = _accountDebt(oldLoanAccount);
            _validateOldDebt(request, debt);
            _validateExistingLenderPosition(request, oldPositionManager, debt);
            _preflightExistingCollateral(context, request, policy, oldCreation.configuration);
        }

        Phase9RefinanceRequestModule.ValidationPlan memory plan;
        plan.domain = keccak256("UNIFIED_REFINANCE_VALIDATION_PLAN_V1");
        plan.contextHash = keccak256(abi.encode("UNIFIED_REFINANCE_VALIDATION_CONTEXT_V1", context));
        plan.requestHash = keccak256(abi.encode(request));
        plan.policy = policy;
        plan.replacementConfiguration = replacement.configuration;
        plan.oldConfiguration = oldCreation.configuration;
        plan.oldLoanAccount = oldLoanAccount;
        plan.oldPositionManager = oldPositionManager;
        plan.bootstrapId = oldCreation.bootstrapId;
        plan.freshOldLoan = fresh;
        plan.bootstrap = bootstrap;
        plan.planDigest = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_VALIDATION_PLAN_DIGEST_V1",
                plan.contextHash,
                plan.requestHash,
                _planBodyHash(plan)
            )
        );
        encodedPlan = abi.encode(plan);
        if (encodedPlan.length == 0 || encodedPlan.length > PHASE9_REFINANCE_MAX_PLAN_BYTES) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateContext(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request
    ) private view {
        if (
            context.chainId != block.chainid || block.chainid != 31337
                || context.coordinator != address(this)
                || context.activeLock != (PHASE9_REFINANCE_ACTIVE_MASK | request.refinanceNonce)
                || context.coordinator.code.length == 0 || context.loanRegistry.code.length == 0
                || context.phase9LoanFactory.code.length == 0
                || context.payoffQuoteEngine.code.length == 0
                || context.lienRegistry.code.length == 0 || context.assetRegistry.code.length == 0
                || context.policyRegistry.code.length == 0
                || context.emergencyController.code.length == 0
                || context.treasuryFeeRecipient == address(0)
                || context.settlementToken.code.length == 0
                || _addressCall(
                        context.lienRegistry,
                        abi.encodeCall(ILienRegistry.registeredRefinanceCoordinator, ())
                    ) != context.coordinator
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateRequestEnvironment(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request
    ) private view {
        (bool emergencyOk, bytes memory emergencyRaw) = _boundedStaticcall(
            context.emergencyController,
            abi.encodeCall(
                IEmergencyController.emergencyState, (PHASE9_REFINANCE_REQUEST_CAPABILITY)
            ),
            96
        );
        if (!emergencyOk || emergencyRaw.length != 96) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (bool emergencyActive,,) = abi.decode(emergencyRaw, (bool, uint64, bytes32));
        if (
            emergencyActive
                || context.settlementToken.codehash != PHASE9_LOCAL_TOKEN_RUNTIME_CODE_HASH
        ) revert IRefinanceCoordinator.InvalidRefinance();

        (bool assetOk, bytes memory assetRaw) = _boundedStaticcall(
            context.assetRegistry,
            abi.encodeCall(
                IPhase9RefinanceAssetSource.resolveRefinanceAsset, (request.settlementAssetId)
            ),
            160
        );
        if (!assetOk || assetRaw.length != 160) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        ) = abi.decode(assetRaw, (address, uint8, bytes32, bool, bool));
        if (
            !active || !exactBalanceDelta || decimals != 6 || token != context.settlementToken
                || runtimeCodeHash != token.codehash
                || runtimeCodeHash != PHASE9_LOCAL_TOKEN_RUNTIME_CODE_HASH
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _resolveRefinancePolicy(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request
    ) private view returns (Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy) {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            context.policyRegistry,
            abi.encodeCall(
                IPhase9RefinancePolicySource.resolveRefinancePolicy, (request.refinancePolicyHash)
            ),
            8_992
        );
        if (!ok || raw.length == 0) revert IRefinanceCoordinator.InvalidRefinance();
        policy = _decodeRefinancePolicy(raw);
        _requireCanonicalRefinancePolicy(raw, policy);
        if (
            !policy.active || policy.oldPolicySetHash == bytes32(0)
                || policy.newPolicySetHash != request.newPolicySetHash
                || policy.proposedTermsHash != request.proposedTermsHash
                || policy.maximumValidity == 0 || policy.maximumCommitments == 0
                || policy.maximumCommitments > 32 || policy.collateralIds.length == 0
                || policy.collateralIds.length > 16 || policy.replacementTranches.length == 0
                || policy.replacementTranches.length > 8 || policy.replacementPositions.length == 0
                || policy.replacementPositions.length > 32
                || uint256(request.expiresAt) - block.timestamp > policy.maximumValidity
        ) revert IRefinanceCoordinator.InvalidRefinance();
        _validateStrictIds(policy.collateralIds);
        _validateReplacementTemplate(request, policy);
        if (_deriveRefinancePolicyHash(context, request, policy) != request.refinancePolicyHash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _decodeRefinancePolicy(bytes memory raw)
        private
        pure
        returns (Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy)
    {
        (
            bytes32 oldPolicySetHash,
            bytes32 newPolicySetHash,
            bytes32 proposedTermsHash,
            uint64 maximumValidity,
            uint32 maximumCommitments,
            bool active,
            bytes32[] memory collateralIds,
            Phase9Types.DebtState memory replacementDebt,
            Phase9Types.Tranche[] memory replacementTranches,
            Phase9Types.Position[] memory replacementPositions
        ) = abi.decode(
            raw,
            (
                bytes32,
                bytes32,
                bytes32,
                uint64,
                uint32,
                bool,
                bytes32[],
                Phase9Types.DebtState,
                Phase9Types.Tranche[],
                Phase9Types.Position[]
            )
        );
        policy.oldPolicySetHash = oldPolicySetHash;
        policy.newPolicySetHash = newPolicySetHash;
        policy.proposedTermsHash = proposedTermsHash;
        policy.maximumValidity = maximumValidity;
        policy.maximumCommitments = maximumCommitments;
        policy.active = active;
        policy.collateralIds = collateralIds;
        policy.replacementDebt = replacementDebt;
        policy.replacementTranches = replacementTranches;
        policy.replacementPositions = replacementPositions;
    }

    function _requireCanonicalRefinancePolicy(
        bytes memory raw,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy
    ) private pure {
        bytes memory canonical =
            abi.encode(
                policy.oldPolicySetHash,
                policy.newPolicySetHash,
                policy.proposedTermsHash,
                policy.maximumValidity,
                policy.maximumCommitments,
                policy.active,
                policy.collateralIds,
                policy.replacementDebt,
                policy.replacementTranches,
                policy.replacementPositions
            );
        if (raw.length != canonical.length || keccak256(raw) != keccak256(canonical)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _resolveCreation(
        Phase9RefinanceValidationContext memory context,
        bytes32 policySetHash,
        bytes32 loanId
    ) private view returns (Phase9RefinanceRequestModule.CreationFacts memory creation) {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            context.policyRegistry,
            abi.encodeCall(
                IPhase9RefinancePolicySource.resolveLoanCreation, (policySetHash, loanId)
            ),
            704
        );
        if (!ok || raw.length == 0) revert IRefinanceCoordinator.InvalidRefinance();
        (
            Phase9Types.LoanConfiguration memory configuration,
            uint8 mode,
            bytes32 bootstrapId,
            bool active
        ) = abi.decode(raw, (Phase9Types.LoanConfiguration, uint8, bytes32, bool));
        bytes memory canonical = abi.encode(configuration, mode, bootstrapId, active);
        if (raw.length != canonical.length || keccak256(raw) != keccak256(canonical)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        creation = Phase9RefinanceRequestModule.CreationFacts({
            configuration: configuration, mode: mode, bootstrapId: bootstrapId, active: active
        });
    }

    function _resolveBootstrap(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy,
        bytes32 bootstrapId
    ) private view returns (Phase9RefinanceRequestModule.BootstrapFacts memory bootstrap) {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            context.policyRegistry,
            abi.encodeCall(IPhase9RefinancePolicySource.resolveBootstrap, (bootstrapId)),
            11_712
        );
        if (!ok || raw.length == 0) revert IRefinanceCoordinator.InvalidRefinance();
        (
            bytes32 policySetHash,
            bytes32 loanId,
            Phase9Types.DebtState memory debt,
            Phase9Types.Tranche[] memory tranches,
            Phase9Types.Position[] memory positions,
            Phase9Types.CustodyRecord[] memory custodyRecords,
            Phase9Types.Lien[] memory liens,
            bool active
        ) = abi.decode(
            raw,
            (
                bytes32,
                bytes32,
                Phase9Types.DebtState,
                Phase9Types.Tranche[],
                Phase9Types.Position[],
                Phase9Types.CustodyRecord[],
                Phase9Types.Lien[],
                bool
            )
        );
        bytes memory canonical = abi.encode(
            policySetHash, loanId, debt, tranches, positions, custodyRecords, liens, active
        );
        if (raw.length != canonical.length || keccak256(raw) != keccak256(canonical)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        bootstrap.policySetHash = policySetHash;
        bootstrap.loanId = loanId;
        bootstrap.debt = debt;
        bootstrap.tranches = tranches;
        bootstrap.positions = positions;
        bootstrap.custodyRecords = custodyRecords;
        bootstrap.liens = liens;
        bootstrap.active = active;
        if (
            !active || policySetHash != policy.oldPolicySetHash || loanId != request.oldLoanId
                || tranches.length == 0 || tranches.length > 8 || positions.length != 1
                || custodyRecords.length == 0 || custodyRecords.length > 16
                || custodyRecords.length != liens.length
                || liens.length != policy.collateralIds.length
        ) revert IRefinanceCoordinator.InvalidRefinance();
        _validateOldDebt(request, debt);
        _validateBootstrapIssuance(request, bootstrap);
    }

    function _validateReplacementConfiguration(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy,
        Phase9RefinanceRequestModule.CreationFacts memory creation
    ) private view {
        bytes32 expectedNewLoanId = keccak256(
            abi.encode(
                "UNIFIED_PHASE9_REFINANCED_LOAN_V1",
                block.chainid,
                context.phase9LoanFactory,
                request.oldLoanId,
                request.borrower,
                creation.configuration.agreementHash,
                policy.newPolicySetHash,
                request.newLoanNonce
            )
        );
        if (
            !creation.active || creation.mode != PHASE9_REFINANCE_REPLACEMENT
                || creation.bootstrapId != bytes32(0)
                || creation.configuration.policySetHash != policy.newPolicySetHash
                || expectedNewLoanId != request.newLoanId
                || creation.configuration.positionManager != request.newPositionManager
        ) revert IRefinanceCoordinator.InvalidRefinance();
        _validateConfiguration(
            context,
            creation.configuration,
            request.newLoanId,
            request.borrower,
            policy.newPolicySetHash,
            true
        );
    }

    function _validateReplacementTemplate(
        Phase9Types.RefinanceRecord calldata request,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy
    ) private pure {
        Phase9Types.DebtState memory debt = policy.replacementDebt;
        if (
            debt.lifecycle != Phase9Types.LoanLifecycle.ACTIVE
                || debt.servicingState != Phase9Types.ServicingState.CURRENT
                || debt.termsVersion == 0 || debt.debtStateVersion == 0 || debt.stateNonce == 0
                || debt.scheduleHash == bytes32(0) || debt.commencementTime == 0
                || debt.maturityTime <= debt.commencementTime
                || debt.outstandingPrincipal != request.newPrincipal || debt.accruedInterest != 0
                || debt.capitalizedInterest != 0 || debt.accruedFees != 0
                || debt.accruedPenalties != 0 || debt.recoverableCosts != 0
                || debt.unappliedCredit != 0 || debt.coveredLossExposure != 0
                || debt.realizedLoss != 0 || debt.writtenOffAmount != 0
                || debt.recoveredAfterWriteoff != 0 || debt.activeRefinanceId != bytes32(0)
                || debt.activeRestructureId != bytes32(0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
        uint256 trancheClaims;
        bytes32 prior;
        for (uint256 i = 0; i < policy.replacementTranches.length; ++i) {
            Phase9Types.Tranche memory tranche_ = policy.replacementTranches[i];
            if (
                tranche_.trancheId == bytes32(0)
                    || (i != 0 && uint256(tranche_.trancheId) <= uint256(prior))
                    || tranche_.originalClaim == 0
                    || tranche_.outstandingClaim != tranche_.originalClaim
                    || tranche_.configurationHash == bytes32(0)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            prior = tranche_.trancheId;
            trancheClaims = _checkedAdd(trancheClaims, tranche_.outstandingClaim);
        }
        uint256 positionClaims;
        prior = bytes32(0);
        for (uint256 i = 0; i < policy.replacementPositions.length; ++i) {
            Phase9Types.Position memory position_ = policy.replacementPositions[i];
            if (
                position_.positionId == bytes32(0)
                    || (i != 0 && uint256(position_.positionId) <= uint256(prior))
                    || position_.trancheId == bytes32(0) || position_.owner == address(0)
                    || position_.votingPower == 0 || position_.claim == 0
                    || position_.state != Phase9Types.PositionState.ACTIVE
                    || !_containsTranche(policy.replacementTranches, position_.trancheId)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            prior = position_.positionId;
            positionClaims = _checkedAdd(positionClaims, position_.claim);
        }
        if (trancheClaims != request.newPrincipal || positionClaims != request.newPrincipal) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateBootstrapIssuance(
        Phase9Types.RefinanceRecord calldata request,
        Phase9RefinanceRequestModule.BootstrapFacts memory bootstrap
    ) private pure {
        uint256 trancheClaims;
        bytes32 prior;
        for (uint256 i = 0; i < bootstrap.tranches.length; ++i) {
            Phase9Types.Tranche memory tranche_ = bootstrap.tranches[i];
            if (
                tranche_.trancheId == bytes32(0)
                    || (i != 0 && uint256(tranche_.trancheId) <= uint256(prior))
                    || tranche_.originalClaim == 0
                    || tranche_.outstandingClaim != tranche_.originalClaim
                    || tranche_.configurationHash == bytes32(0)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            prior = tranche_.trancheId;
            trancheClaims = _checkedAdd(trancheClaims, tranche_.outstandingClaim);
        }
        Phase9Types.Position memory position_ = bootstrap.positions[0];
        uint256 lenderClaim =
            _checkedAdd(bootstrap.debt.outstandingPrincipal, bootstrap.debt.accruedInterest);
        if (
            position_.positionId == bytes32(0) || position_.trancheId == bytes32(0)
                || position_.owner != request.oldLender || position_.votingPower == 0
                || position_.claim != lenderClaim
                || position_.state != Phase9Types.PositionState.ACTIVE
                || !_containsTranche(bootstrap.tranches, position_.trancheId)
                || trancheClaims != lenderClaim
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateOldDebt(
        Phase9Types.RefinanceRecord calldata request,
        Phase9Types.DebtState memory debt
    ) private pure {
        uint256 lenderClaim = _checkedAdd(debt.outstandingPrincipal, debt.accruedInterest);
        uint256 feePenalty = _checkedAdd(debt.accruedFees, debt.accruedPenalties);
        uint256 grossPayoff = _checkedAdd(lenderClaim, feePenalty);
        if (
            debt.lifecycle != Phase9Types.LoanLifecycle.ACTIVE
                || !(debt.servicingState == Phase9Types.ServicingState.CURRENT
                    || debt.servicingState == Phase9Types.ServicingState.DELINQUENT
                    || debt.servicingState == Phase9Types.ServicingState.DEFAULTED)
                || debt.termsVersion == 0 || debt.debtStateVersion == 0 || debt.stateNonce == 0
                || debt.scheduleHash == bytes32(0) || debt.commencementTime == 0
                || debt.maturityTime <= debt.commencementTime || lenderClaim == 0
                || debt.capitalizedInterest != 0 || debt.recoverableCosts != 0
                || debt.unappliedCredit > feePenalty || debt.coveredLossExposure != 0
                || debt.realizedLoss != 0 || debt.writtenOffAmount != 0
                || debt.recoveredAfterWriteoff != 0 || debt.activeRefinanceId != bytes32(0)
                || debt.activeRestructureId != bytes32(0)
                || grossPayoff - debt.unappliedCredit != request.oldNetPayoff
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateExistingLenderPosition(
        Phase9Types.RefinanceRecord calldata request,
        address manager,
        Phase9Types.DebtState memory debt
    ) private view {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            manager, abi.encodeCall(IPositionManagerV2.positionIds, ()), 1_088
        );
        if (!ok || raw.length == 0) revert IRefinanceCoordinator.InvalidRefinance();
        bytes32[] memory ids = abi.decode(raw, (bytes32[]));
        if (
            raw.length != abi.encode(ids).length || keccak256(raw) != keccak256(abi.encode(ids))
                || ids.length == 0 || ids.length > 32
        ) revert IRefinanceCoordinator.InvalidRefinance();
        uint256 activeCount;
        uint256 lenderClaim = _checkedAdd(debt.outstandingPrincipal, debt.accruedInterest);
        for (uint256 i = 0; i < ids.length; ++i) {
            Phase9Types.Position memory position_ = _position(manager, ids[i]);
            if (ids[i] == bytes32(0) || position_.positionId != ids[i]) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
            if (position_.state == Phase9Types.PositionState.ACTIVE) {
                ++activeCount;
                if (
                    position_.owner != request.oldLender || position_.claim != lenderClaim
                        || position_.trancheId == bytes32(0)
                ) revert IRefinanceCoordinator.InvalidRefinance();
            }
        }
        if (activeCount != 1) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _preflightFreshCollateral(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy,
        Phase9Types.LoanConfiguration memory configuration,
        Phase9RefinanceRequestModule.BootstrapFacts memory bootstrap
    ) private view {
        bytes32[] memory entryHashes = new bytes32[](policy.collateralIds.length);
        for (uint256 i = 0; i < policy.collateralIds.length; ++i) {
            Phase9Types.CustodyRecord memory custodyRecord = bootstrap.custodyRecords[i];
            Phase9Types.Lien memory lienRecord = bootstrap.liens[i];
            bytes32 operationId = _bootstrapCustodyOperationId(
                context,
                request,
                policy.oldPolicySetHash,
                configuration.collateralCustody,
                policy.collateralIds[i]
            );
            _validateCollateralFields(
                request,
                policy.collateralIds[i],
                configuration.collateralCustody,
                custodyRecord,
                lienRecord
            );
            _validateFreshCustodyIdentity(
                context, configuration.collateralCustody, custodyRecord, operationId
            );
            _requireCollateralAbsent(
                context, configuration.collateralCustody, policy.collateralIds[i]
            );
            entryHashes[i] = _collateralEntryHash(lienRecord);
        }
        if (keccak256(abi.encode(entryHashes)) != request.collateralSetHash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _preflightExistingCollateral(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy,
        Phase9Types.LoanConfiguration memory configuration
    ) private view {
        bytes32[] memory entryHashes = new bytes32[](policy.collateralIds.length);
        for (uint256 i = 0; i < policy.collateralIds.length; ++i) {
            Phase9Types.CustodyRecord memory custodyRecord =
                _custody(configuration.collateralCustody, policy.collateralIds[i]);
            Phase9Types.Lien memory lienRecord = _lien(context, policy.collateralIds[i]);
            _validateCollateralFields(
                request,
                policy.collateralIds[i],
                configuration.collateralCustody,
                custodyRecord,
                lienRecord
            );
            entryHashes[i] = _collateralEntryHash(lienRecord);
        }
        if (keccak256(abi.encode(entryHashes)) != request.collateralSetHash) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _validateCollateralFields(
        Phase9Types.RefinanceRecord calldata request,
        bytes32 collateralId,
        address custodyAddress,
        Phase9Types.CustodyRecord memory custodyRecord,
        Phase9Types.Lien memory lienRecord
    ) private pure {
        if (
            collateralId == bytes32(0) || custodyRecord.collateralId != collateralId
                || lienRecord.collateralId != collateralId || custodyRecord.assetId == bytes32(0)
                || custodyRecord.assetId != lienRecord.assetId || custodyRecord.token == address(0)
                || custodyRecord.identityHash == bytes32(0)
                || custodyRecord.borrower != request.borrower
                || lienRecord.borrower != request.borrower || custodyRecord.quantity == 0
                || custodyRecord.quantity != lienRecord.quantity
                || custodyRecord.status != Phase9Types.CustodyStatus.HELD
                || lienRecord.collateralManager != custodyAddress
                || lienRecord.vault != custodyAddress
                || lienRecord.seniorLoanId != request.oldLoanId
                || lienRecord.lienVersion != request.lienVersion
                || lienRecord.status != Phase9Types.LienStatus.ACTIVE
                || lienRecord.pendingRefinanceId != bytes32(0)
                || lienRecord.pendingTargetLoanId != bytes32(0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateFreshCustodyIdentity(
        Phase9RefinanceValidationContext memory context,
        address custodyAddress,
        Phase9Types.CustodyRecord memory record_,
        bytes32 operationId
    ) private view {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            context.assetRegistry,
            abi.encodeCall(IPhase9RefinanceAssetSource.resolveCustodyAsset, (record_.assetId)),
            160
        );
        if (!ok || raw.length != 160) revert IRefinanceCoordinator.InvalidRefinance();
        (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        ) = abi.decode(raw, (address, uint8, bytes32, bool, bool));
        Phase9RefinanceRequestModule.CustodyIdentityFields memory fields;
        fields.chainId = block.chainid;
        fields.custody = custodyAddress;
        fields.assetRegistry = context.assetRegistry;
        fields.operationId = operationId;
        fields.collateralId = record_.collateralId;
        fields.assetId = record_.assetId;
        fields.token = token;
        fields.runtimeCodeHash = runtimeCodeHash;
        fields.decimals = decimals;
        fields.exactBalanceDelta = true;
        fields.borrower = record_.borrower;
        fields.quantity = record_.quantity;
        if (
            !active || !exactBalanceDelta || token != record_.token || runtimeCodeHash == bytes32(0)
                || token.codehash != runtimeCodeHash
                || record_.identityHash
                    != keccak256(abi.encode("UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1", fields))
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _requireCollateralAbsent(
        Phase9RefinanceValidationContext memory context,
        address custodyAddress,
        bytes32 collateralId
    ) private view {
        if (_custody(custodyAddress, collateralId).collateralId != bytes32(0)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (bool ok, bytes memory raw) = _boundedStaticcall(
            context.lienRegistry, abi.encodeCall(ILienRegistry.lien, (collateralId)), 36
        );
        if (
            ok || raw.length != 36
                || keccak256(raw)
                    != keccak256(
                        abi.encodeWithSelector(ILienRegistry.UnknownLien.selector, collateralId)
                    )
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateConfiguration(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.LoanConfiguration memory configuration,
        bytes32 loanId,
        address borrower,
        bytes32 policySetHash,
        bool managerMustBeAbsent
    ) private view {
        if (
            configuration.factory != context.phase9LoanFactory
                || configuration.loanRegistry != context.loanRegistry
                || configuration.settlementToken != context.settlementToken
                || configuration.settlementAssetId != PHASE9_SETTLEMENT_ASSET_ID
                || configuration.borrower != borrower || configuration.positionManager == address(0)
                || configuration.collateralCustody.code.length == 0
                || configuration.lienRegistry != context.lienRegistry
                || configuration.payoffQuoteEngine != context.payoffQuoteEngine
                || configuration.refinanceCoordinator != context.coordinator
                || configuration.restructuringController.code.length == 0
                || configuration.insuranceManager.code.length == 0
                || configuration.recoveryManager.code.length == 0 || configuration.loanId != loanId
                || configuration.agreementHash == bytes32(0)
                || configuration.policySetHash != policySetHash
                || configuration.amendmentPolicyHash == bytes32(0)
                || configuration.protectionPolicyHash == bytes32(0)
                || configuration.recoveryPolicyHash == bytes32(0)
                || (managerMustBeAbsent && configuration.positionManager.code.length != 0)
                || (!managerMustBeAbsent && configuration.positionManager.code.length == 0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateLoanGraph(
        Phase9RefinanceValidationContext memory context,
        bytes32 loanId,
        address borrower,
        Phase9Types.LoanConfiguration memory expectedConfiguration,
        address loanAccount,
        address positionManager
    ) private view {
        if (
            loanAccount.code.length == 0 || positionManager.code.length == 0
                || _factoryLoanAccount(context, loanId) != loanAccount
                || _factoryPositionManager(context, loanId) != positionManager
                || !_registryExists(context, loanId) || _registryTerminal(context, loanId)
                || _registryLoanAccount(context, loanId) != loanAccount
                || _addressCall(
                        context.loanRegistry, abi.encodeCall(ILoanRegistry.borrowerOf, (loanId))
                    ) != borrower
                || _wordCall(
                        context.loanRegistry,
                        abi.encodeCall(ILoanRegistry.agreementHashOf, (loanId))
                    ) != expectedConfiguration.agreementHash
                || uint256(
                        _wordCall(
                            context.loanRegistry,
                            abi.encodeCall(ILoanRegistry.protocolVersionOf, (loanId))
                        )
                    ) != PHASE9_PROTOCOL_VERSION
                || keccak256(abi.encode(_accountConfiguration(loanAccount)))
                    != keccak256(abi.encode(expectedConfiguration))
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _requireReplacementAbsent(
        Phase9RefinanceValidationContext memory context,
        bytes32 loanId
    ) private view {
        if (
            _factoryLoanAccount(context, loanId) != address(0)
                || _factoryPositionManager(context, loanId) != address(0)
                || _registryLoanAccount(context, loanId) != address(0)
                || _registryExists(context, loanId)
        ) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _factoryLoanAccount(Phase9RefinanceValidationContext memory context, bytes32 loanId)
        private
        view
        returns (address)
    {
        return _addressCall(
            context.phase9LoanFactory, abi.encodeCall(IPhase9LoanFactory.loanAccount, (loanId))
        );
    }

    function _factoryPositionManager(
        Phase9RefinanceValidationContext memory context,
        bytes32 loanId
    ) private view returns (address) {
        return _addressCall(
            context.phase9LoanFactory, abi.encodeCall(IPhase9LoanFactory.positionManager, (loanId))
        );
    }

    function _registryLoanAccount(Phase9RefinanceValidationContext memory context, bytes32 loanId)
        private
        view
        returns (address)
    {
        return
            _addressCall(context.loanRegistry, abi.encodeCall(ILoanRegistry.loanAccount, (loanId)));
    }

    function _registryExists(Phase9RefinanceValidationContext memory context, bytes32 loanId)
        private
        view
        returns (bool)
    {
        return _boolCall(context.loanRegistry, abi.encodeCall(ILoanRegistry.exists, (loanId)));
    }

    function _registryTerminal(Phase9RefinanceValidationContext memory context, bytes32 loanId)
        private
        view
        returns (bool)
    {
        return _boolCall(context.loanRegistry, abi.encodeCall(ILoanRegistry.isTerminal, (loanId)));
    }

    function _accountConfiguration(address account)
        private
        view
        returns (Phase9Types.LoanConfiguration memory configuration)
    {
        (bool ok, bytes memory raw) =
            _boundedStaticcall(account, abi.encodeCall(IPhase9LoanAccount.configuration, ()), 608);
        if (!ok || raw.length != 608) revert IRefinanceCoordinator.InvalidRefinance();
        configuration = abi.decode(raw, (Phase9Types.LoanConfiguration));
        if (keccak256(raw) != keccak256(abi.encode(configuration))) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _accountDebt(address account)
        private
        view
        returns (Phase9Types.DebtState memory debt)
    {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            account, abi.encodeCall(IPhase9LoanAccount.debtState, ()), 672
        );
        if (!ok || raw.length != 672) revert IRefinanceCoordinator.InvalidRefinance();
        debt = abi.decode(raw, (Phase9Types.DebtState));
        if (keccak256(raw) != keccak256(abi.encode(debt))) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _position(address manager, bytes32 positionId)
        private
        view
        returns (Phase9Types.Position memory result)
    {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            manager, abi.encodeCall(IPositionManagerV2.position, (positionId)), 192
        );
        if (!ok || raw.length != 192) revert IRefinanceCoordinator.InvalidRefinance();
        result = abi.decode(raw, (Phase9Types.Position));
        if (keccak256(raw) != keccak256(abi.encode(result))) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _custody(address custodyAddress, bytes32 collateralId)
        private
        view
        returns (Phase9Types.CustodyRecord memory result)
    {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            custodyAddress, abi.encodeCall(ICollateralCustodyV2.custody, (collateralId)), 224
        );
        if (!ok || raw.length != 224) revert IRefinanceCoordinator.InvalidRefinance();
        result = abi.decode(raw, (Phase9Types.CustodyRecord));
        if (keccak256(raw) != keccak256(abi.encode(result))) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _lien(Phase9RefinanceValidationContext memory context, bytes32 collateralId)
        private
        view
        returns (Phase9Types.Lien memory result)
    {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            context.lienRegistry, abi.encodeCall(ILienRegistry.lien, (collateralId)), 352
        );
        if (!ok || raw.length != 352) revert IRefinanceCoordinator.InvalidRefinance();
        result = abi.decode(raw, (Phase9Types.Lien));
        if (keccak256(raw) != keccak256(abi.encode(result))) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _wordCall(address target, bytes memory input) private view returns (bytes32 result) {
        (bool ok, bytes memory raw) = _boundedStaticcall(target, input, 32);
        if (!ok || raw.length != 32) revert IRefinanceCoordinator.InvalidRefinance();
        result = abi.decode(raw, (bytes32));
    }

    function _addressCall(address target, bytes memory input)
        private
        view
        returns (address result)
    {
        uint256 value = uint256(_wordCall(target, input));
        if (value > type(uint160).max) revert IRefinanceCoordinator.InvalidRefinance();
        result = address(uint160(value));
    }

    function _boolCall(address target, bytes memory input) private view returns (bool result) {
        uint256 value = uint256(_wordCall(target, input));
        if (value > 1) revert IRefinanceCoordinator.InvalidRefinance();
        result = value == 1;
    }

    function _deriveRefinancePolicyHash(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy
    ) private view returns (bytes32) {
        Phase9RefinanceRequestModule.RefinancePolicyIdentityFields memory fields;
        fields.chainId = block.chainid;
        fields.coordinator = context.coordinator;
        fields.policyRegistry = context.policyRegistry;
        fields.oldLoanId = request.oldLoanId;
        fields.newLoanId = request.newLoanId;
        fields.borrower = request.borrower;
        fields.oldLender = request.oldLender;
        fields.newPositionManager = request.newPositionManager;
        fields.oldPolicySetHash = policy.oldPolicySetHash;
        fields.newPolicySetHash = policy.newPolicySetHash;
        fields.proposedTermsHash = policy.proposedTermsHash;
        fields.settlementAssetId = request.settlementAssetId;
        fields.collateralSetHash = request.collateralSetHash;
        fields.fundingAmount = request.fundingAmount;
        fields.refinanceFee = request.refinanceFee;
        fields.borrowerProceeds = request.borrowerProceeds;
        fields.expiresAt = request.expiresAt;
        fields.maximumValidity = policy.maximumValidity;
        fields.maximumCommitments = policy.maximumCommitments;
        fields.collateralIdsHash = keccak256(abi.encode(policy.collateralIds));
        fields.replacementDebtHash = keccak256(abi.encode(policy.replacementDebt));
        fields.replacementTranchesHash = keccak256(abi.encode(policy.replacementTranches));
        fields.replacementPositionsHash = keccak256(abi.encode(policy.replacementPositions));
        return keccak256(abi.encode("UNIFIED_REFINANCE_POLICY_V1", fields));
    }

    function _deriveBootstrapId(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request,
        bytes32 oldPolicySetHash
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_LOCAL_BOOTSTRAP_V1",
                block.chainid,
                context.phase9LoanFactory,
                context.policyRegistry,
                request.oldLoanId,
                request.borrower,
                oldPolicySetHash
            )
        );
    }

    function _bootstrapCustodyOperationId(
        Phase9RefinanceValidationContext memory context,
        Phase9Types.RefinanceRecord calldata request,
        bytes32 oldPolicySetHash,
        address custodyAddress,
        bytes32 collateralId
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_V1",
                block.chainid,
                context.coordinator,
                _deriveBootstrapId(context, request, oldPolicySetHash),
                request.oldLoanId,
                custodyAddress,
                collateralId
            )
        );
    }

    function _collateralEntryHash(Phase9Types.Lien memory lienRecord)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                lienRecord.collateralId,
                lienRecord.assetId,
                lienRecord.quantity,
                lienRecord.vault,
                lienRecord.borrower,
                lienRecord.lienVersion
            )
        );
    }

    function _planBodyHash(Phase9RefinanceRequestModule.ValidationPlan memory plan)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                plan.policy,
                plan.replacementConfiguration,
                plan.oldConfiguration,
                plan.oldLoanAccount,
                plan.oldPositionManager,
                plan.bootstrapId,
                plan.freshOldLoan,
                plan.bootstrap
            )
        );
    }

    function _validateStrictIds(bytes32[] memory ids) private pure {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (ids[i] == bytes32(0) || (i != 0 && uint256(ids[i]) <= uint256(ids[i - 1]))) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
        }
    }

    function _containsTranche(Phase9Types.Tranche[] memory tranches, bytes32 trancheId)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < tranches.length; ++i) {
            if (tranches[i].trancheId == trancheId) return true;
        }
        return false;
    }

    function _checkedAdd(uint256 left, uint256 right) private pure returns (uint256 result) {
        if (left > type(uint256).max - right) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        unchecked {
            result = left + right;
        }
    }

    function _boundedStaticcall(address target, bytes memory input, uint256 maximumReturndata)
        private
        view
        returns (bool ok, bytes memory output)
    {
        assembly ("memory-safe") {
            ok := staticcall(gas(), target, add(input, 0x20), mload(input), 0, 0)
            let size := returndatasize()
            if gt(size, maximumReturndata) {
                ok := 0
                size := 0
            }
            output := mload(0x40)
            mstore(output, size)
            returndatacopy(add(output, 0x20), 0, size)
            mstore(0x40, and(add(add(output, 0x20), add(size, 0x1f)), not(0x1f)))
        }
    }
}

library Phase9RefinanceLifecycleModule {
    struct FundingTransition {
        Phase9Types.RefinanceState previousState;
        uint64 stateVersionAfter;
        uint256 acceptedFundingAfter;
        uint256 escrowedUnitsAfter;
        uint256 commitmentCountAfter;
        bytes32 fundingResultHash;
        bytes32 transitionEvidenceHash;
    }

    event RefinanceCommitmentRecorded(
        bytes32 indexed refinanceId,
        bytes32 indexed commitmentId,
        address indexed funder,
        uint256 amount
    );
    event RefinanceStateTransitioned(
        bytes32 indexed refinanceId,
        Phase9Types.RefinanceState indexed previousState,
        Phase9Types.RefinanceState indexed nextState,
        uint64 stateVersion,
        bytes32 operationId,
        bytes32 evidenceHash
    );

    function recordFundingCommitment(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.FundingCommitment calldata commitment
    ) public {
        if (commitment.commitmentId == bytes32(0)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        Phase9Types.FundingCommitment storage existing = state.commitments[commitment.commitmentId];
        if (existing.commitmentId != bytes32(0)) {
            if (
                commitment.state != Phase9Types.FundingCommitmentState.NONE
                    || commitment.fundingResultHash != bytes32(0)
                    || !_sameCommitment(existing, commitment)
            ) {
                revert IRefinanceCoordinator.RefinanceReplayConflict(existing.refinanceId);
            }
            return;
        }
        _validateNewCommitmentFields(commitment);

        Phase9Types.RefinanceRecord memory refinance_ = state.refinances[commitment.refinanceId];
        _validateRefinanceForFunding(state, refinance_, commitment);
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy =
            _resolveRefinancePolicy(state, refinance_);
        _validatePolicyCommitment(state, refinance_, commitment, policy);
        FundingTransition memory transition = _fundingTransition(state, refinance_, commitment);

        _requireFundingOpen(state);
        _validateSettlementAsset(state, refinance_.settlementAssetId);
        uint256 coordinatorBalanceBefore = _tokenWord(
            address(state.settlementToken), abi.encodeCall(IERC20.balanceOf, (address(this)))
        );
        uint256 funderBalanceBefore = _tokenWord(
            address(state.settlementToken), abi.encodeCall(IERC20.balanceOf, (commitment.funder))
        );
        if (
            _tokenWord(
                    address(state.settlementToken),
                    abi.encodeCall(IERC20.allowance, (commitment.funder, address(this)))
                ) < commitment.amount
        ) revert IRefinanceCoordinator.InvalidRefinance();

        _persistFunding(state, refinance_, commitment, transition);
        _transferFunding(state, commitment, coordinatorBalanceBefore, funderBalanceBefore);

        emit RefinanceCommitmentRecorded(
            commitment.refinanceId, commitment.commitmentId, commitment.funder, commitment.amount
        );
        emit RefinanceStateTransitioned(
            commitment.refinanceId,
            transition.previousState,
            Phase9Types.RefinanceState.FUNDING_ESCROWED,
            transition.stateVersionAfter,
            commitment.commitmentId,
            transition.transitionEvidenceHash
        );
    }

    function executeRefinance(Phase9RefinanceStorageLayout storage, bytes32, bytes32)
        public
        pure
        returns (Phase9Types.RefinanceTerminalResult memory)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function cancelRefinance(Phase9RefinanceStorageLayout storage, bytes32, bytes32) public pure {
        revert Phase9ImplementationNotFrozen();
    }

    function refundCommitment(Phase9RefinanceStorageLayout storage, bytes32, bytes32) public pure {
        revert Phase9ImplementationNotFrozen();
    }

    function _validateNewCommitmentFields(Phase9Types.FundingCommitment calldata commitment)
        private
        pure
    {
        if (
            commitment.state != Phase9Types.FundingCommitmentState.NONE
                || commitment.fundingResultHash != bytes32(0)
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _sameCommitment(
        Phase9Types.FundingCommitment storage existing,
        Phase9Types.FundingCommitment calldata supplied
    ) private view returns (bool) {
        return existing.commitmentId == supplied.commitmentId
            && existing.refinanceId == supplied.refinanceId
            && existing.positionId == supplied.positionId
            && existing.trancheId == supplied.trancheId && existing.funder == supplied.funder
            && existing.amount == supplied.amount
            && existing.commitmentNonce == supplied.commitmentNonce
            && existing.commitmentDigest == supplied.commitmentDigest
            && existing.state == Phase9Types.FundingCommitmentState.FUNDED
            && existing.fundingResultHash != bytes32(0);
    }

    function _validateRefinanceForFunding(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord memory refinance_,
        Phase9Types.FundingCommitment calldata commitment
    ) private view {
        if (refinance_.refinanceId == bytes32(0)) {
            revert IRefinanceCoordinator.UnknownRefinance(commitment.refinanceId);
        }
        uint64 activeLock = state.nextRefinanceNonce[refinance_.oldLoanId];
        if (
            block.chainid != 31337 || block.timestamp > type(uint64).max
                || commitment.refinanceId != refinance_.refinanceId
                || commitment.positionId == bytes32(0) || commitment.trancheId == bytes32(0)
                || commitment.funder == address(0) || commitment.amount == 0
                || commitment.commitmentNonce == 0 || commitment.commitmentDigest == bytes32(0)
                || msg.sender != commitment.funder
                || (refinance_.state != Phase9Types.RefinanceState.ACCEPTED
                    && refinance_.state != Phase9Types.RefinanceState.FUNDING_ESCROWED)
                || refinance_.stateVersion == type(uint64).max || refinance_.executionAttempts != 0
                || refinance_.terminalEvidenceHash != bytes32(0)
                || refinance_.expiresAt <= block.timestamp
                || refinance_.settlementAssetId != PHASE9_SETTLEMENT_ASSET_ID
                || refinance_.refinancePolicyHash == bytes32(0) || refinance_.fundingAmount == 0
                || refinance_.newPrincipal != refinance_.fundingAmount
                || refinance_.acceptedFunding >= refinance_.fundingAmount
                || state.escrowedUnits[refinance_.refinanceId] != refinance_.acceptedFunding
                || activeLock != (PHASE9_REFINANCE_ACTIVE_MASK | refinance_.refinanceNonce)
                || state.processedOperationIds[commitment.commitmentId]
        ) revert IRefinanceCoordinator.InvalidRefinance();

        bytes32 expectedCommitmentId = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_FUNDING_COMMITMENT_V1",
                commitment.refinanceId,
                commitment.positionId,
                commitment.trancheId,
                commitment.funder,
                commitment.amount,
                commitment.commitmentNonce
            )
        );
        bytes32 expectedCommitmentDigest = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_FUNDING_COMMITMENT_DIGEST_V1",
                block.chainid,
                address(this),
                commitment.commitmentId,
                commitment.refinanceId,
                commitment.positionId,
                commitment.trancheId,
                commitment.funder,
                commitment.amount,
                commitment.commitmentNonce,
                refinance_.refinancePolicyHash,
                refinance_.expiresAt
            )
        );
        if (
            commitment.commitmentId != expectedCommitmentId
                || commitment.commitmentDigest != expectedCommitmentDigest
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _resolveRefinancePolicy(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord memory refinance_
    ) private view returns (Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy) {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            state.policyRegistry,
            abi.encodeCall(
                IPhase9RefinancePolicySource.resolveRefinancePolicy,
                (refinance_.refinancePolicyHash)
            ),
            8_992
        );
        if (!ok || raw.length == 0) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        _validateRefinancePolicyEncoding(raw);
        (
            bytes32 oldPolicySetHash,
            bytes32 newPolicySetHash,
            bytes32 proposedTermsHash,
            uint64 maximumValidity,
            uint32 maximumCommitments,
            bool active,
            bytes32[] memory collateralIds,
            Phase9Types.DebtState memory replacementDebt,
            Phase9Types.Tranche[] memory replacementTranches,
            Phase9Types.Position[] memory replacementPositions
        ) = abi.decode(
            raw,
            (
                bytes32,
                bytes32,
                bytes32,
                uint64,
                uint32,
                bool,
                bytes32[],
                Phase9Types.DebtState,
                Phase9Types.Tranche[],
                Phase9Types.Position[]
            )
        );
        bytes memory canonical = abi.encode(
            oldPolicySetHash,
            newPolicySetHash,
            proposedTermsHash,
            maximumValidity,
            maximumCommitments,
            active,
            collateralIds,
            replacementDebt,
            replacementTranches,
            replacementPositions
        );
        if (raw.length != canonical.length || keccak256(raw) != keccak256(canonical)) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        policy.oldPolicySetHash = oldPolicySetHash;
        policy.newPolicySetHash = newPolicySetHash;
        policy.proposedTermsHash = proposedTermsHash;
        policy.maximumValidity = maximumValidity;
        policy.maximumCommitments = maximumCommitments;
        policy.active = active;
        policy.collateralIds = collateralIds;
        policy.replacementDebt = replacementDebt;
        policy.replacementTranches = replacementTranches;
        policy.replacementPositions = replacementPositions;
    }

    function _validateRefinancePolicyEncoding(bytes memory raw) private pure {
        if (
            raw.length < 1_056 || raw.length > 8_992 || raw.length % 32 != 0
                || _wordAt(raw, 96) > type(uint64).max || _wordAt(raw, 128) > type(uint32).max
                || _wordAt(raw, 160) > 1 || _wordAt(raw, 224) >= 5 || _wordAt(raw, 256) >= 5
                || _wordAt(raw, 288) > type(uint64).max || _wordAt(raw, 320) > type(uint64).max
                || _wordAt(raw, 352) > type(uint64).max || _wordAt(raw, 384) > type(uint64).max
                || _wordAt(raw, 416) > type(uint64).max
        ) revert IRefinanceCoordinator.InvalidRefinance();

        uint256 collateralOffset = _wordAt(raw, 192);
        uint256 trancheOffset = _wordAt(raw, 896);
        uint256 positionOffset = _wordAt(raw, 928);
        if (collateralOffset != 960) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        uint256 collateralCount = _wordAt(raw, collateralOffset);
        if (collateralCount > 16 || trancheOffset != collateralOffset + 32 + collateralCount * 32) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        uint256 trancheCount = _wordAt(raw, trancheOffset);
        if (trancheCount > 8 || positionOffset != trancheOffset + 32 + trancheCount * 160) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        uint256 positionCount = _wordAt(raw, positionOffset);
        if (positionCount > 32 || raw.length != positionOffset + 32 + positionCount * 192) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }

        for (uint256 i = 0; i < trancheCount; ++i) {
            if (_wordAt(raw, trancheOffset + 64 + i * 160) > type(uint32).max) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
        }
        for (uint256 i = 0; i < positionCount; ++i) {
            uint256 positionStart = positionOffset + 32 + i * 192;
            if (
                _wordAt(raw, positionStart + 64) > type(uint160).max
                    || _wordAt(raw, positionStart + 160) >= 4
            ) revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _wordAt(bytes memory encoded, uint256 offset) private pure returns (uint256 value) {
        assembly ("memory-safe") {
            value := mload(add(add(encoded, 0x20), offset))
        }
    }

    function _validatePolicyCommitment(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord memory refinance_,
        Phase9Types.FundingCommitment calldata commitment,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy
    ) private view {
        if (
            !policy.active || policy.oldPolicySetHash == bytes32(0)
                || policy.newPolicySetHash != refinance_.newPolicySetHash
                || policy.proposedTermsHash != refinance_.proposedTermsHash
                || policy.maximumValidity == 0 || policy.maximumCommitments == 0
                || policy.maximumCommitments > 32 || policy.collateralIds.length == 0
                || policy.collateralIds.length > 16 || policy.replacementTranches.length == 0
                || policy.replacementTranches.length > 8 || policy.replacementPositions.length == 0
                || policy.replacementPositions.length > 32
                || policy.replacementPositions.length > policy.maximumCommitments
                || state.commitmentIds[refinance_.refinanceId].length >= policy.maximumCommitments
                || state.commitmentIds[refinance_.refinanceId].length >= 32
                || _deriveRefinancePolicyHash(state, refinance_, policy)
                    != refinance_.refinancePolicyHash
        ) revert IRefinanceCoordinator.InvalidRefinance();

        _validateStrictIds(policy.collateralIds);
        _validatePolicyPositions(refinance_, commitment, policy);
        _validatePriorCommitments(state, refinance_, commitment.positionId);
    }

    function _validatePolicyPositions(
        Phase9Types.RefinanceRecord memory refinance_,
        Phase9Types.FundingCommitment calldata commitment,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy
    ) private pure {
        uint256 trancheClaims;
        bytes32 priorId;
        for (uint256 i = 0; i < policy.replacementTranches.length; ++i) {
            Phase9Types.Tranche memory tranche_ = policy.replacementTranches[i];
            if (
                tranche_.trancheId == bytes32(0)
                    || (i != 0 && uint256(tranche_.trancheId) <= uint256(priorId))
                    || tranche_.originalClaim == 0
                    || tranche_.outstandingClaim != tranche_.originalClaim
                    || tranche_.configurationHash == bytes32(0)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            priorId = tranche_.trancheId;
            trancheClaims = _checkedAdd(trancheClaims, tranche_.outstandingClaim);
        }

        bool matched;
        uint256 positionClaims;
        priorId = bytes32(0);
        for (uint256 i = 0; i < policy.replacementPositions.length; ++i) {
            Phase9Types.Position memory position_ = policy.replacementPositions[i];
            if (
                position_.positionId == bytes32(0)
                    || (i != 0 && uint256(position_.positionId) <= uint256(priorId))
                    || position_.trancheId == bytes32(0) || position_.owner == address(0)
                    || position_.votingPower == 0 || position_.claim == 0
                    || position_.state != Phase9Types.PositionState.ACTIVE
                    || !_containsTranche(policy.replacementTranches, position_.trancheId)
            ) revert IRefinanceCoordinator.InvalidRefinance();
            priorId = position_.positionId;
            positionClaims = _checkedAdd(positionClaims, position_.claim);
            if (position_.positionId == commitment.positionId) {
                if (
                    position_.trancheId != commitment.trancheId
                        || position_.owner != commitment.funder
                        || position_.claim != commitment.amount
                ) revert IRefinanceCoordinator.InvalidRefinance();
                matched = true;
            }
        }
        if (
            !matched || trancheClaims != refinance_.newPrincipal
                || positionClaims != refinance_.newPrincipal
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validatePriorCommitments(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord memory refinance_,
        bytes32 nextPositionId
    ) private view {
        bytes32[] storage ids = state.commitmentIds[refinance_.refinanceId];
        uint256 attributedFunding;
        for (uint256 i = 0; i < ids.length; ++i) {
            Phase9Types.FundingCommitment storage prior = state.commitments[ids[i]];
            if (
                prior.commitmentId != ids[i] || prior.refinanceId != refinance_.refinanceId
                    || prior.positionId == nextPositionId
                    || prior.state != Phase9Types.FundingCommitmentState.FUNDED
                    || prior.fundingResultHash == bytes32(0) || !state.processedOperationIds[ids[i]]
            ) revert IRefinanceCoordinator.InvalidRefinance();
            for (uint256 j = 0; j < i; ++j) {
                if (state.commitments[ids[j]].positionId == prior.positionId) {
                    revert IRefinanceCoordinator.InvalidRefinance();
                }
            }
            attributedFunding = _checkedAdd(attributedFunding, prior.amount);
        }
        if (attributedFunding != refinance_.acceptedFunding) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
    }

    function _fundingTransition(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord memory refinance_,
        Phase9Types.FundingCommitment calldata commitment
    ) private view returns (FundingTransition memory transition) {
        transition.previousState = refinance_.state;
        transition.stateVersionAfter = refinance_.stateVersion + 1;
        transition.acceptedFundingAfter = _checkedAdd(refinance_.acceptedFunding, commitment.amount);
        transition.escrowedUnitsAfter =
            _checkedAdd(state.escrowedUnits[refinance_.refinanceId], commitment.amount);
        transition.commitmentCountAfter = state.commitmentIds[refinance_.refinanceId].length + 1;
        if (
            transition.acceptedFundingAfter > refinance_.fundingAmount
                || transition.escrowedUnitsAfter != transition.acceptedFundingAfter
        ) revert IRefinanceCoordinator.InvalidRefinance();
        transition.fundingResultHash = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_FUNDING_RESULT_V1",
                block.chainid,
                address(this),
                refinance_.refinanceId,
                commitment.commitmentId,
                commitment.funder,
                commitment.amount,
                commitment.commitmentNonce,
                transition.acceptedFundingAfter,
                transition.escrowedUnitsAfter,
                transition.commitmentCountAfter,
                Phase9Types.RefinanceState.FUNDING_ESCROWED,
                transition.stateVersionAfter
            )
        );
        transition.transitionEvidenceHash = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_STATE_TRANSITION_V1",
                block.chainid,
                address(this),
                refinance_.refinanceId,
                transition.previousState,
                Phase9Types.RefinanceState.FUNDING_ESCROWED,
                transition.stateVersionAfter,
                commitment.commitmentId,
                transition.fundingResultHash
            )
        );
    }

    function _requireFundingOpen(Phase9RefinanceStorageLayout storage state) private view {
        (bool ok, bytes memory raw) = _boundedStaticcall(
            state.emergencyController,
            abi.encodeCall(
                IEmergencyController.emergencyState, (PHASE9_REFINANCE_FUNDING_CAPABILITY)
            ),
            96
        );
        if (!ok || raw.length != 96 || _wordAt(raw, 0) > 1 || _wordAt(raw, 32) > type(uint64).max) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (bool active,,) = abi.decode(raw, (bool, uint64, bytes32));
        if (active) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _validateSettlementAsset(
        Phase9RefinanceStorageLayout storage state,
        bytes32 settlementAssetId
    ) private view {
        if (address(state.settlementToken).codehash != PHASE9_LOCAL_TOKEN_RUNTIME_CODE_HASH) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (bool ok, bytes memory raw) = _boundedStaticcall(
            state.assetRegistry,
            abi.encodeCall(IPhase9RefinanceAssetSource.resolveRefinanceAsset, (settlementAssetId)),
            160
        );
        if (
            !ok || raw.length != 160 || _wordAt(raw, 0) > type(uint160).max
                || _wordAt(raw, 32) > type(uint8).max || _wordAt(raw, 96) > 1
                || _wordAt(raw, 128) > 1
        ) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        ) = abi.decode(raw, (address, uint8, bytes32, bool, bool));
        if (
            !active || !exactBalanceDelta || decimals != 6
                || token != address(state.settlementToken) || runtimeCodeHash != token.codehash
                || runtimeCodeHash != PHASE9_LOCAL_TOKEN_RUNTIME_CODE_HASH
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _persistFunding(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord memory refinance_,
        Phase9Types.FundingCommitment calldata commitment,
        FundingTransition memory transition
    ) private {
        Phase9Types.RefinanceRecord storage storedRefinance =
            state.refinances[refinance_.refinanceId];
        storedRefinance.state = Phase9Types.RefinanceState.FUNDING_ESCROWED;
        storedRefinance.stateVersion = transition.stateVersionAfter;
        storedRefinance.acceptedFunding = transition.acceptedFundingAfter;
        state.escrowedUnits[refinance_.refinanceId] = transition.escrowedUnitsAfter;
        state.commitmentIds[refinance_.refinanceId].push(commitment.commitmentId);
        state.commitments[commitment.commitmentId] = Phase9Types.FundingCommitment({
            commitmentId: commitment.commitmentId,
            refinanceId: commitment.refinanceId,
            positionId: commitment.positionId,
            trancheId: commitment.trancheId,
            funder: commitment.funder,
            amount: commitment.amount,
            commitmentNonce: commitment.commitmentNonce,
            commitmentDigest: commitment.commitmentDigest,
            state: Phase9Types.FundingCommitmentState.FUNDED,
            fundingResultHash: transition.fundingResultHash
        });
        state.processedOperationIds[commitment.commitmentId] = true;
    }

    function _transferFunding(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.FundingCommitment calldata commitment,
        uint256 coordinatorBalanceBefore,
        uint256 funderBalanceBefore
    ) private {
        (bool success, bytes memory returned) = address(state.settlementToken)
            .call(
                abi.encodeCall(
                    IERC20.transferFrom, (commitment.funder, address(this), commitment.amount)
                )
            );
        if (!success || returned.length != 32 || _decodedBoolean(returned) != true) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }

        uint256 coordinatorBalanceAfter = _tokenWord(
            address(state.settlementToken), abi.encodeCall(IERC20.balanceOf, (address(this)))
        );
        uint256 funderBalanceAfter = _tokenWord(
            address(state.settlementToken), abi.encodeCall(IERC20.balanceOf, (commitment.funder))
        );
        if (
            coordinatorBalanceBefore > type(uint256).max - commitment.amount
                || coordinatorBalanceAfter != coordinatorBalanceBefore + commitment.amount
                || funderBalanceAfter > funderBalanceBefore
                || funderBalanceBefore - funderBalanceAfter != commitment.amount
        ) revert IRefinanceCoordinator.InvalidRefinance();
    }

    function _tokenWord(address token, bytes memory input) private view returns (uint256 value) {
        (bool success, bytes memory returned) = token.staticcall(input);
        if (!success || returned.length != 32) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        value = abi.decode(returned, (uint256));
    }

    function _decodedBoolean(bytes memory encoded) private pure returns (bool value) {
        uint256 word = abi.decode(encoded, (uint256));
        if (word > 1) revert IRefinanceCoordinator.InvalidRefinance();
        value = word == 1;
    }

    function _boundedStaticcall(address target, bytes memory input, uint256 maximumReturndata)
        private
        view
        returns (bool ok, bytes memory output)
    {
        assembly ("memory-safe") {
            ok := staticcall(gas(), target, add(input, 0x20), mload(input), 0, 0)
            let size := returndatasize()
            if gt(size, maximumReturndata) {
                ok := 0
                size := 0
            }
            output := mload(0x40)
            mstore(output, size)
            returndatacopy(add(output, 0x20), 0, size)
            mstore(0x40, and(add(add(output, 0x20), add(size, 0x1f)), not(0x1f)))
        }
    }

    function _deriveRefinancePolicyHash(
        Phase9RefinanceStorageLayout storage state,
        Phase9Types.RefinanceRecord memory refinance_,
        Phase9RefinanceRequestModule.RefinancePolicyFacts memory policy
    ) private view returns (bytes32) {
        Phase9RefinanceRequestModule.RefinancePolicyIdentityFields memory fields;
        fields.chainId = block.chainid;
        fields.coordinator = address(this);
        fields.policyRegistry = state.policyRegistry;
        fields.oldLoanId = refinance_.oldLoanId;
        fields.newLoanId = refinance_.newLoanId;
        fields.borrower = refinance_.borrower;
        fields.oldLender = refinance_.oldLender;
        fields.newPositionManager = refinance_.newPositionManager;
        fields.oldPolicySetHash = policy.oldPolicySetHash;
        fields.newPolicySetHash = policy.newPolicySetHash;
        fields.proposedTermsHash = policy.proposedTermsHash;
        fields.settlementAssetId = refinance_.settlementAssetId;
        fields.collateralSetHash = refinance_.collateralSetHash;
        fields.fundingAmount = refinance_.fundingAmount;
        fields.refinanceFee = refinance_.refinanceFee;
        fields.borrowerProceeds = refinance_.borrowerProceeds;
        fields.expiresAt = refinance_.expiresAt;
        fields.maximumValidity = policy.maximumValidity;
        fields.maximumCommitments = policy.maximumCommitments;
        fields.collateralIdsHash = keccak256(abi.encode(policy.collateralIds));
        fields.replacementDebtHash = keccak256(abi.encode(policy.replacementDebt));
        fields.replacementTranchesHash = keccak256(abi.encode(policy.replacementTranches));
        fields.replacementPositionsHash = keccak256(abi.encode(policy.replacementPositions));
        return keccak256(abi.encode("UNIFIED_REFINANCE_POLICY_V1", fields));
    }

    function _validateStrictIds(bytes32[] memory ids) private pure {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (ids[i] == bytes32(0) || (i != 0 && uint256(ids[i]) <= uint256(ids[i - 1]))) {
                revert IRefinanceCoordinator.InvalidRefinance();
            }
        }
    }

    function _containsTranche(Phase9Types.Tranche[] memory tranches, bytes32 trancheId)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < tranches.length; ++i) {
            if (tranches[i].trancheId == trancheId) return true;
        }
        return false;
    }

    function _checkedAdd(uint256 left, uint256 right) private pure returns (uint256 result) {
        if (left > type(uint256).max - right) {
            revert IRefinanceCoordinator.InvalidRefinance();
        }
        unchecked {
            result = left + right;
        }
    }
}

/// @notice Fixed-ABI coordinator whose mutators execute through ADR-0023 linked modules.
contract RefinanceCoordinator is IRefinanceCoordinator {
    address private _loanRegistry;
    address private _phase9LoanFactory;
    address private _payoffQuoteEngine;
    address private _lienRegistry;
    address private _assetRegistry;
    address private _policyRegistry;
    address private _emergencyController;
    address private _treasuryFeeRecipient;
    IERC20 private _settlementToken;
    mapping(bytes32 oldLoanId => uint64 nonce) private _nextRefinanceNonce;
    mapping(bytes32 refinanceId => Phase9Types.RefinanceRecord record) private _refinances;
    mapping(bytes32 refinanceId => bytes32[] commitmentIds_) private _commitmentIds;
    mapping(bytes32 commitmentId => Phase9Types.FundingCommitment commitment) private _commitments;
    mapping(bytes32 refinanceId => uint256 units) private _escrowedUnits;
    mapping(bytes32 refinanceId => Phase9Types.RefinanceTerminalResult result) private
        _terminalResults;
    mapping(bytes32 operationId => bool processed) private _processedOperationIds;

    constructor(
        address loanRegistry_,
        address phase9LoanFactory_,
        address payoffQuoteEngine_,
        address lienRegistry_,
        address assetRegistry_,
        address policyRegistry_,
        address emergencyController_,
        address treasuryFeeRecipient_,
        IERC20 settlementToken_
    ) {
        _loanRegistry = loanRegistry_;
        _phase9LoanFactory = phase9LoanFactory_;
        _payoffQuoteEngine = payoffQuoteEngine_;
        _lienRegistry = lienRegistry_;
        _assetRegistry = assetRegistry_;
        _policyRegistry = policyRegistry_;
        _emergencyController = emergencyController_;
        _treasuryFeeRecipient = treasuryFeeRecipient_;
        _settlementToken = settlementToken_;
    }

    function requestRefinance(Phase9Types.RefinanceRecord calldata request)
        external
        override
        returns (bytes32 refinanceId)
    {
        Phase9RefinanceStorageLayout storage state = _layout();
        Phase9RefinanceRequestModule.begin(state, request);
        Phase9RefinanceValidationContext memory context =
            _validationContext(state, request.oldLoanId);
        bytes memory encodedPlan;
        try Phase9RefinanceValidationModule.preflight(context, request) returns (
            bytes memory plan
        ) {
            if (plan.length == 0 || plan.length > PHASE9_REFINANCE_MAX_PLAN_BYTES) {
                revert InvalidRefinance();
            }
            encodedPlan = plan;
        } catch {
            revert InvalidRefinance();
        }
        return Phase9RefinanceRequestModule.complete(state, request, encodedPlan);
    }

    function recordFundingCommitment(Phase9Types.FundingCommitment calldata commitment)
        external
        override
    {
        Phase9RefinanceLifecycleModule.recordFundingCommitment(_layout(), commitment);
    }

    function executeRefinance(bytes32 refinanceId, bytes32 operationId)
        external
        override
        returns (Phase9Types.RefinanceTerminalResult memory)
    {
        return Phase9RefinanceLifecycleModule.executeRefinance(_layout(), refinanceId, operationId);
    }

    function cancelRefinance(bytes32 refinanceId, bytes32 operationId) external override {
        Phase9RefinanceLifecycleModule.cancelRefinance(_layout(), refinanceId, operationId);
    }

    function refundCommitment(bytes32 commitmentId, bytes32 operationId) external override {
        Phase9RefinanceLifecycleModule.refundCommitment(_layout(), commitmentId, operationId);
    }

    function refinance(bytes32 refinanceId)
        external
        view
        override
        returns (Phase9Types.RefinanceRecord memory)
    {
        Phase9Types.RefinanceRecord memory result = _refinances[refinanceId];
        if (result.refinanceId == bytes32(0)) revert UnknownRefinance(refinanceId);
        return result;
    }

    function fundingCommitment(bytes32 commitmentId)
        external
        view
        override
        returns (Phase9Types.FundingCommitment memory)
    {
        Phase9Types.FundingCommitment memory result = _commitments[commitmentId];
        if (result.commitmentId == bytes32(0)) {
            revert UnknownFundingCommitment(commitmentId);
        }
        return result;
    }

    function commitmentIds(bytes32 refinanceId) external view override returns (bytes32[] memory) {
        if (_refinances[refinanceId].refinanceId == bytes32(0)) {
            revert UnknownRefinance(refinanceId);
        }
        return _commitmentIds[refinanceId];
    }

    function escrowedUnits(bytes32 refinanceId) external view override returns (uint256) {
        if (_refinances[refinanceId].refinanceId == bytes32(0)) {
            revert UnknownRefinance(refinanceId);
        }
        return _escrowedUnits[refinanceId];
    }

    function terminalResult(bytes32 refinanceId)
        external
        view
        override
        returns (Phase9Types.RefinanceTerminalResult memory)
    {
        if (_refinances[refinanceId].refinanceId == bytes32(0)) {
            revert UnknownRefinance(refinanceId);
        }
        return _terminalResults[refinanceId];
    }

    function operationProcessed(bytes32 operationId) external view override returns (bool) {
        return _processedOperationIds[operationId];
    }

    function _validationContext(Phase9RefinanceStorageLayout storage state, bytes32 oldLoanId)
        private
        view
        returns (Phase9RefinanceValidationContext memory context)
    {
        context.chainId = block.chainid;
        context.coordinator = address(this);
        context.loanRegistry = state.loanRegistry;
        context.phase9LoanFactory = state.phase9LoanFactory;
        context.payoffQuoteEngine = state.payoffQuoteEngine;
        context.lienRegistry = state.lienRegistry;
        context.assetRegistry = state.assetRegistry;
        context.policyRegistry = state.policyRegistry;
        context.emergencyController = state.emergencyController;
        context.treasuryFeeRecipient = state.treasuryFeeRecipient;
        context.settlementToken = address(state.settlementToken);
        context.activeLock = state.nextRefinanceNonce[oldLoanId];
    }

    function _layout() private pure returns (Phase9RefinanceStorageLayout storage state) {
        assembly ("memory-safe") {
            state.slot := 0
        }
    }
}
