// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IPayoffQuoteEngineV2 } from "../src/interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { IPhase9LoanAccount } from "../src/interfaces/phase9/IPhase9LoanAccount.sol";
import { IPhase9LoanFactory } from "../src/interfaces/phase9/IPhase9LoanFactory.sol";
import { IPositionManagerV2 } from "../src/interfaces/phase9/IPositionManagerV2.sol";
import { IRefinanceCoordinator } from "../src/interfaces/phase9/IRefinanceCoordinator.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { CollateralCustodyV2 } from "../src/resolution/CollateralCustodyV2.sol";
import { LienRegistry } from "../src/resolution/LienRegistry.sol";
import { PayoffQuoteEngine } from "../src/resolution/PayoffQuoteEngine.sol";
import { Phase9LoanAccount } from "../src/resolution/Phase9LoanAccount.sol";
import { Phase9LoanFactory } from "../src/resolution/Phase9LoanFactory.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import { PositionManagerV2 } from "../src/resolution/PositionManagerV2.sol";
import { RefinanceCoordinator } from "../src/resolution/RefinanceCoordinator.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";

contract Phase9BootstrapDependencyStub { }

contract Phase9BootstrapGovernanceExecutor {
    error UnauthorizedHarnessCaller();

    address private immutable _harness;

    constructor(address harness_) {
        _harness = harness_;
    }

    function grantLoanFactoryRole(RoleManager roleManager, address factory) external {
        if (msg.sender != _harness) revert UnauthorizedHarnessCaller();
        roleManager.grantRole(ProtocolRoles.LOAN_FACTORY_ROLE, factory, type(uint64).max);
    }
}

contract Phase9BootstrapAssetSource {
    struct AssetRecord {
        address token;
        uint8 decimals;
        bytes32 runtimeCodeHash;
        bool exactBalanceDelta;
        bool active;
    }

    mapping(bytes32 assetId => AssetRecord record) private _assets;

    function setAsset(bytes32 assetId, AssetRecord calldata record) external {
        _assets[assetId] = record;
    }

    function resolveCustodyAsset(bytes32 assetId)
        external
        view
        returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        )
    {
        return _resolveAsset(assetId);
    }

    function resolveRefinanceAsset(bytes32 assetId)
        external
        view
        returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        )
    {
        return _resolveAsset(assetId);
    }

    function _resolveAsset(bytes32 assetId)
        private
        view
        returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        )
    {
        AssetRecord memory record = _assets[assetId];
        return (
            record.token,
            record.decimals,
            record.runtimeCodeHash,
            record.exactBalanceDelta,
            record.active
        );
    }
}

contract Phase9BootstrapPolicyResolver {
    error MissingCreationRecord();
    error MissingBootstrapRecord();
    error ForcedResolverFailure();

    struct CreationRecord {
        Phase9Types.LoanConfiguration configuration;
        uint8 creationMode;
        bytes32 bootstrapId;
        bool active;
    }

    struct BootstrapRecord {
        bytes32 policySetHash;
        bytes32 loanId;
        Phase9Types.DebtState initialDebt;
        Phase9Types.Tranche[] initialTranches;
        Phase9Types.Position[] initialPositions;
        Phase9Types.CustodyRecord[] custodyRecords;
        Phase9Types.Lien[] liens;
        bool active;
    }

    struct RefinancePolicyRecord {
        bytes32 boundOldPolicySetHash;
        bytes32 boundNewPolicySetHash;
        bytes32 proposedTermsHash;
        uint64 maximumValidity;
        uint32 maximumCommitments;
        bool active;
        bytes32[] collateralIds;
        Phase9Types.DebtState replacementDebt;
        Phase9Types.Tranche[] replacementTranches;
        Phase9Types.Position[] replacementPositions;
    }

    struct CompositePayoffQuotePolicyRecord {
        bytes32 policyHash;
        bytes32 boundPolicySetHash;
        address feePenaltyBeneficiary;
        bytes32 settlementAssetId;
        address settlementToken;
        uint64 maximumValidity;
        bool active;
    }

    mapping(bytes32 creationKey => CreationRecord record) private _creations;
    mapping(bytes32 bootstrapId => BootstrapRecord record) private _bootstraps;
    mapping(bytes32 refinancePolicyHash => RefinancePolicyRecord record) private _refinancePolicies;
    mapping(
        bytes32 loanId => mapping(address loanAccount => CompositePayoffQuotePolicyRecord record)
    ) private _payoffQuotePolicies;
    bool private _revertCreation;
    bool private _revertBootstrap;

    function setCreation(
        bytes32 policySetHash,
        bytes32 loanId,
        Phase9Types.LoanConfiguration calldata configuration,
        uint8 creationMode,
        bytes32 bootstrapId,
        bool active
    ) external {
        _creations[_creationKey(policySetHash, loanId)] = CreationRecord({
            configuration: configuration,
            creationMode: creationMode,
            bootstrapId: bootstrapId,
            active: active
        });
    }

    function setBootstrapAt(bytes32 bootstrapId, BootstrapRecord calldata supplied) external {
        _storeBootstrap(_bootstraps[bootstrapId], supplied);
    }

    function setRefinancePolicy(
        bytes32 refinancePolicyHash,
        RefinancePolicyRecord calldata supplied
    ) external {
        RefinancePolicyRecord storage record = _refinancePolicies[refinancePolicyHash];
        record.boundOldPolicySetHash = supplied.boundOldPolicySetHash;
        record.boundNewPolicySetHash = supplied.boundNewPolicySetHash;
        record.proposedTermsHash = supplied.proposedTermsHash;
        record.maximumValidity = supplied.maximumValidity;
        record.maximumCommitments = supplied.maximumCommitments;
        record.active = supplied.active;
        record.replacementDebt = supplied.replacementDebt;

        delete record.collateralIds;
        delete record.replacementTranches;
        delete record.replacementPositions;
        for (uint256 index = 0; index < supplied.collateralIds.length; ++index) {
            record.collateralIds.push(supplied.collateralIds[index]);
        }
        for (uint256 index = 0; index < supplied.replacementTranches.length; ++index) {
            record.replacementTranches.push(supplied.replacementTranches[index]);
        }
        for (uint256 index = 0; index < supplied.replacementPositions.length; ++index) {
            record.replacementPositions.push(supplied.replacementPositions[index]);
        }
    }

    function setPayoffQuotePolicy(
        bytes32 loanId,
        address loanAccount,
        CompositePayoffQuotePolicyRecord calldata supplied
    ) external {
        _payoffQuotePolicies[loanId][loanAccount] = supplied;
    }

    function setCreationFailure(bool value) external {
        _revertCreation = value;
    }

    function setBootstrapFailure(bool value) external {
        _revertBootstrap = value;
    }

    function resolveLoanCreation(bytes32 policySetHash, bytes32 loanId)
        external
        view
        returns (
            Phase9Types.LoanConfiguration memory configuration,
            uint8 creationMode,
            bytes32 bootstrapId,
            bool active
        )
    {
        if (_revertCreation) revert ForcedResolverFailure();
        CreationRecord memory record = _creations[_creationKey(policySetHash, loanId)];
        if (record.configuration.loanId == bytes32(0)) revert MissingCreationRecord();
        return (record.configuration, record.creationMode, record.bootstrapId, record.active);
    }

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
        )
    {
        if (_revertBootstrap) revert ForcedResolverFailure();
        BootstrapRecord storage record = _bootstraps[bootstrapId];
        if (record.loanId == bytes32(0)) revert MissingBootstrapRecord();
        return (
            record.policySetHash,
            record.loanId,
            record.initialDebt,
            record.initialTranches,
            record.initialPositions,
            record.custodyRecords,
            record.liens,
            record.active
        );
    }

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
        )
    {
        RefinancePolicyRecord storage record = _refinancePolicies[refinancePolicyHash];
        return (
            record.boundOldPolicySetHash,
            record.boundNewPolicySetHash,
            record.proposedTermsHash,
            record.maximumValidity,
            record.maximumCommitments,
            record.active,
            record.collateralIds,
            record.replacementDebt,
            record.replacementTranches,
            record.replacementPositions
        );
    }

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
        )
    {
        CompositePayoffQuotePolicyRecord memory record = _payoffQuotePolicies[loanId][loanAccount];
        return (
            record.policyHash,
            record.boundPolicySetHash,
            record.feePenaltyBeneficiary,
            record.settlementAssetId,
            record.settlementToken,
            record.maximumValidity,
            record.active
        );
    }

    function creation(bytes32 policySetHash, bytes32 loanId)
        external
        view
        returns (CreationRecord memory)
    {
        return _creations[_creationKey(policySetHash, loanId)];
    }

    function bootstrap(bytes32 bootstrapId) external view returns (BootstrapRecord memory) {
        return _bootstraps[bootstrapId];
    }

    function refinancePolicy(bytes32 refinancePolicyHash)
        external
        view
        returns (RefinancePolicyRecord memory)
    {
        return _refinancePolicies[refinancePolicyHash];
    }

    function _storeBootstrap(BootstrapRecord storage record, BootstrapRecord calldata supplied)
        private
    {
        record.policySetHash = supplied.policySetHash;
        record.loanId = supplied.loanId;
        record.initialDebt = supplied.initialDebt;
        record.active = supplied.active;

        delete record.initialTranches;
        delete record.initialPositions;
        delete record.custodyRecords;
        delete record.liens;
        for (uint256 index = 0; index < supplied.initialTranches.length; ++index) {
            record.initialTranches.push(supplied.initialTranches[index]);
        }
        for (uint256 index = 0; index < supplied.initialPositions.length; ++index) {
            record.initialPositions.push(supplied.initialPositions[index]);
        }
        for (uint256 index = 0; index < supplied.custodyRecords.length; ++index) {
            record.custodyRecords.push(supplied.custodyRecords[index]);
        }
        for (uint256 index = 0; index < supplied.liens.length; ++index) {
            record.liens.push(supplied.liens[index]);
        }
    }

    function _creationKey(bytes32 policySetHash, bytes32 loanId) private pure returns (bytes32) {
        return keccak256(abi.encode(policySetHash, loanId));
    }
}

contract Phase9BootstrapEmergencyController {
    struct EmergencyRecord {
        bool active;
        uint64 expiry;
        bytes32 reasonCode;
    }

    mapping(bytes32 capability => EmergencyRecord record) private _emergencyStates;

    function setEmergencyState(bytes32 capability, bool active, uint64 expiry, bytes32 reasonCode)
        external
    {
        _emergencyStates[capability] =
            EmergencyRecord({ active: active, expiry: expiry, reasonCode: reasonCode });
    }

    function emergencyState(bytes32 capability)
        external
        view
        returns (bool active, uint64 expiry, bytes32 reasonCode)
    {
        EmergencyRecord memory record = _emergencyStates[capability];
        return (record.active, record.expiry, record.reasonCode);
    }
}

contract Phase9BootstrapPayoffQuotePolicySource {
    struct PayoffQuotePolicyRecord {
        bytes32 policyHash;
        bytes32 boundPolicySetHash;
        address feePenaltyBeneficiary;
        bytes32 settlementAssetId;
        address settlementToken;
        uint64 maximumValidity;
        bool active;
    }

    mapping(bytes32 loanId => mapping(address loanAccount => PayoffQuotePolicyRecord record))
        private _policies;

    function setPayoffQuotePolicy(
        bytes32 loanId,
        address loanAccount,
        PayoffQuotePolicyRecord calldata supplied
    ) external {
        _policies[loanId][loanAccount] = supplied;
    }

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
        )
    {
        PayoffQuotePolicyRecord memory record = _policies[loanId][loanAccount];
        return (
            record.policyHash,
            record.boundPolicySetHash,
            record.feePenaltyBeneficiary,
            record.settlementAssetId,
            record.settlementToken,
            record.maximumValidity,
            record.active
        );
    }

    function payoffQuotePolicy(bytes32 loanId, address loanAccount)
        external
        view
        returns (PayoffQuotePolicyRecord memory)
    {
        return _policies[loanId][loanAccount];
    }
}

contract Phase9RefinanceRequestDeployer {
    error RequestStackAlreadyDeployed();
    error CoordinatorPredictionMismatch();

    struct DeploymentInputs {
        address loanRegistry;
        address settlementToken;
        address quotePolicyRegistry;
        address refinancePolicyRegistry;
        address amendmentPolicyRegistry;
        address protectionPolicyRegistry;
        address recoveryPolicyRegistry;
        address assetRegistry;
        address emergencyController;
        address treasuryFeeRecipient;
        uint64 maximumQuoteValidity;
    }

    struct DeploymentComponents {
        address predictedCoordinator;
        LienRegistry lienRegistry;
        CollateralCustodyV2 collateralCustody;
        Phase9LoanAccount loanAccountImplementation;
        PositionManagerV2 positionManagerImplementation;
        Phase9LoanFactory loanFactory;
        PayoffQuoteEngine payoffQuoteEngine;
        RefinanceCoordinator refinanceCoordinator;
    }

    bool private _deployed;

    function deploy(DeploymentInputs calldata inputs)
        external
        returns (DeploymentComponents memory components)
    {
        if (_deployed) revert RequestStackAlreadyDeployed();
        _deployed = true;

        components.predictedCoordinator = predictCoordinator();
        components.lienRegistry = new LienRegistry(components.predictedCoordinator);
        components.collateralCustody = new CollateralCustodyV2(
            inputs.assetRegistry, address(components.lienRegistry), inputs.emergencyController
        );
        components.loanAccountImplementation = new Phase9LoanAccount();
        components.positionManagerImplementation = new PositionManagerV2();
        components.loanFactory = new Phase9LoanFactory(
            ILoanRegistry(inputs.loanRegistry),
            address(components.loanAccountImplementation),
            address(components.positionManagerImplementation),
            inputs.quotePolicyRegistry,
            inputs.refinancePolicyRegistry,
            inputs.amendmentPolicyRegistry,
            inputs.protectionPolicyRegistry,
            inputs.recoveryPolicyRegistry
        );
        components.payoffQuoteEngine = new PayoffQuoteEngine(
            ILoanRegistry(inputs.loanRegistry),
            inputs.quotePolicyRegistry,
            inputs.maximumQuoteValidity,
            address(components.loanFactory),
            components.predictedCoordinator
        );
        components.refinanceCoordinator = new RefinanceCoordinator(
            inputs.loanRegistry,
            address(components.loanFactory),
            address(components.payoffQuoteEngine),
            address(components.lienRegistry),
            inputs.assetRegistry,
            inputs.refinancePolicyRegistry,
            inputs.emergencyController,
            inputs.treasuryFeeRecipient,
            IERC20(inputs.settlementToken)
        );
        if (address(components.refinanceCoordinator) != components.predictedCoordinator) {
            revert CoordinatorPredictionMismatch();
        }
    }

    function predictCoordinator() public view returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), hex"07"))))
            );
    }
}

contract Phase9BootstrapUnauthorizedCaller {
    function createLoan(
        IPhase9LoanFactory factory,
        Phase9Types.LoanCreationRequest calldata request
    ) external returns (address loanAccount, address positionManager) {
        return factory.createLoan(request);
    }

    function requestRefinance(
        IRefinanceCoordinator coordinator,
        Phase9Types.RefinanceRecord calldata request
    ) external returns (bytes32 refinanceId) {
        return coordinator.requestRefinance(request);
    }
}

abstract contract Phase9RefinanceBootstrapHarness {
    error BootstrapHarnessAlreadyInitialized();
    error InvalidBootstrapHarnessState();

    bytes32 internal constant SETTLEMENT_ASSET_ID =
        0x61737365743a7068617365393a7039756e697400000000000000000000000000;

    struct BootstrapSpec {
        bytes32 seed;
        bytes32 loanId;
        address borrower;
        address lender;
        bytes32 agreementHash;
        bytes32 policySetHash;
        bytes32 amendmentPolicyHash;
        bytes32 protectionPolicyHash;
        bytes32 recoveryPolicyHash;
        bytes32 collateralId;
        bytes32 collateralAssetId;
        uint256 collateralQuantity;
        uint256 outstandingPrincipal;
        uint256 accruedInterest;
    }

    struct ReplacementSpec {
        bytes32 oldLoanId;
        address borrower;
        bytes32 refinanceId;
        uint64 newLoanNonce;
        bytes32 agreementHash;
        bytes32 policySetHash;
        bytes32 amendmentPolicyHash;
        bytes32 protectionPolicyHash;
        bytes32 recoveryPolicyHash;
    }

    struct CreationIdentity {
        uint256 chainId;
        address factory;
        bytes32 loanId;
        bytes32 oldLoanId;
        address borrower;
        bytes32 refinanceId;
        uint64 newLoanNonce;
        uint64 loanNonce;
        bytes32 agreementHash;
        bytes32 policySetHash;
        uint8 creationMode;
        bytes32 bootstrapId;
        address predictedAccount;
        address predictedManager;
    }

    RoleManager internal roleManager;
    LoanRegistry internal loanRegistry;
    Phase9LocalSyntheticToken internal settlementToken;
    Phase9LoanAccount internal loanAccountImplementation;
    PositionManagerV2 internal positionManagerImplementation;
    Phase9LoanFactory internal phase9LoanFactory;
    Phase9BootstrapPolicyResolver internal policyResolver;
    Phase9BootstrapAssetSource internal custodyAssetSource;
    LienRegistry internal lienRegistry;
    CollateralCustodyV2 internal collateralCustody;

    Phase9BootstrapPayoffQuotePolicySource internal quotePolicyRegistry;
    Phase9BootstrapDependencyStub internal amendmentPolicyRegistry;
    Phase9BootstrapDependencyStub internal protectionPolicyRegistry;
    Phase9BootstrapDependencyStub internal recoveryPolicyRegistry;
    Phase9BootstrapDependencyStub internal payoffQuoteEngine;
    Phase9BootstrapDependencyStub internal restructuringController;
    Phase9BootstrapDependencyStub internal insuranceManager;
    Phase9BootstrapDependencyStub internal recoveryManager;
    Phase9BootstrapEmergencyController internal emergencyController;

    mapping(bytes32 loanId => bytes32 creationId) internal canonicalCreationIds;
    mapping(bytes32 loanId => bytes32 bootstrapId) internal canonicalBootstrapIds;

    function _deployBootstrapHarness() internal {
        if (address(phase9LoanFactory) != address(0)) revert BootstrapHarnessAlreadyInitialized();
        if (block.chainid != 31337) revert InvalidBootstrapHarnessState();

        Phase9BootstrapGovernanceExecutor governance =
            new Phase9BootstrapGovernanceExecutor(address(this));
        roleManager = new RoleManager(address(this), address(governance));
        loanRegistry = new LoanRegistry(roleManager);
        settlementToken = new Phase9LocalSyntheticToken(address(this));
        loanAccountImplementation = new Phase9LoanAccount();
        positionManagerImplementation = new PositionManagerV2();
        policyResolver = new Phase9BootstrapPolicyResolver();
        custodyAssetSource = new Phase9BootstrapAssetSource();
        lienRegistry = new LienRegistry(address(this));

        quotePolicyRegistry = new Phase9BootstrapPayoffQuotePolicySource();
        amendmentPolicyRegistry = new Phase9BootstrapDependencyStub();
        protectionPolicyRegistry = new Phase9BootstrapDependencyStub();
        recoveryPolicyRegistry = new Phase9BootstrapDependencyStub();
        payoffQuoteEngine = new Phase9BootstrapDependencyStub();
        restructuringController = new Phase9BootstrapDependencyStub();
        insuranceManager = new Phase9BootstrapDependencyStub();
        recoveryManager = new Phase9BootstrapDependencyStub();
        emergencyController = new Phase9BootstrapEmergencyController();
        collateralCustody = new CollateralCustodyV2(
            address(custodyAssetSource), address(lienRegistry), address(emergencyController)
        );

        phase9LoanFactory = new Phase9LoanFactory(
            ILoanRegistry(address(loanRegistry)),
            address(loanAccountImplementation),
            address(positionManagerImplementation),
            address(quotePolicyRegistry),
            address(policyResolver),
            address(amendmentPolicyRegistry),
            address(protectionPolicyRegistry),
            address(recoveryPolicyRegistry)
        );
        governance.grantLoanFactoryRole(roleManager, address(phase9LoanFactory));
    }

    function _defaultBootstrapSpec(bytes32 seed, address borrower, address lender)
        internal
        pure
        returns (BootstrapSpec memory spec)
    {
        spec.seed = seed;
        spec.loanId = keccak256(abi.encode("PHASE9_BOOTSTRAP_LOAN", seed));
        spec.borrower = borrower;
        spec.lender = lender;
        spec.agreementHash = keccak256(abi.encode("PHASE9_BOOTSTRAP_AGREEMENT", seed));
        spec.policySetHash = keccak256(abi.encode("PHASE9_BOOTSTRAP_POLICY", seed));
        spec.amendmentPolicyHash = keccak256(abi.encode("PHASE9_AMENDMENT_POLICY", seed));
        spec.protectionPolicyHash = keccak256(abi.encode("PHASE9_PROTECTION_POLICY", seed));
        spec.recoveryPolicyHash = keccak256(abi.encode("PHASE9_RECOVERY_POLICY", seed));
        spec.collateralId = keccak256(abi.encode("PHASE9_BOOTSTRAP_COLLATERAL", seed));
        spec.collateralAssetId = keccak256(abi.encode("PHASE9_BOOTSTRAP_COLLATERAL_ASSET", seed));
        spec.collateralQuantity = 25;
        spec.outstandingPrincipal = 90;
        spec.accruedInterest = 5;
    }

    function _defaultReplacementSpec(
        bytes32 seed,
        bytes32 oldLoanId,
        address borrower,
        bytes32 refinanceId,
        uint64 newLoanNonce
    ) internal pure returns (ReplacementSpec memory spec) {
        spec.oldLoanId = oldLoanId;
        spec.borrower = borrower;
        spec.refinanceId = refinanceId;
        spec.newLoanNonce = newLoanNonce;
        spec.agreementHash = keccak256(abi.encode("PHASE9_REPLACEMENT_AGREEMENT", seed));
        spec.policySetHash = keccak256(abi.encode("PHASE9_REPLACEMENT_POLICY", seed));
        spec.amendmentPolicyHash = keccak256(abi.encode("PHASE9_AMENDMENT_POLICY", seed));
        spec.protectionPolicyHash = keccak256(abi.encode("PHASE9_PROTECTION_POLICY", seed));
        spec.recoveryPolicyHash = keccak256(abi.encode("PHASE9_RECOVERY_POLICY", seed));
    }

    function _prepareBootstrap(BootstrapSpec memory spec)
        internal
        returns (Phase9Types.LoanCreationRequest memory request, bytes32 bootstrapId)
    {
        _requireHarnessReady();
        address predictedManager = _predictPositionManager(spec.loanId);
        Phase9Types.LoanConfiguration memory configuration =
            _configuration(spec.loanId, spec.borrower, predictedManager);
        configuration.agreementHash = spec.agreementHash;
        configuration.policySetHash = spec.policySetHash;
        configuration.amendmentPolicyHash = spec.amendmentPolicyHash;
        configuration.protectionPolicyHash = spec.protectionPolicyHash;
        configuration.recoveryPolicyHash = spec.recoveryPolicyHash;

        bootstrapId = _deriveBootstrapId(spec.loanId, spec.borrower, spec.policySetHash);
        policyResolver.setCreation(
            spec.policySetHash, spec.loanId, configuration, 1, bootstrapId, true
        );
        policyResolver.setBootstrapAt(
            bootstrapId, _bootstrapRecord(spec, configuration, bootstrapId)
        );
        canonicalBootstrapIds[spec.loanId] = bootstrapId;

        request.configuration = configuration;
        request.creationId = bytes32(0);
    }

    function _prepareReplacement(ReplacementSpec memory spec)
        internal
        returns (Phase9Types.LoanCreationRequest memory request)
    {
        _requireHarnessReady();
        bytes32 loanId = _deriveReplacementLoanId(spec);
        Phase9Types.LoanConfiguration memory configuration =
            _configuration(loanId, spec.borrower, _predictPositionManager(loanId));
        configuration.agreementHash = spec.agreementHash;
        configuration.policySetHash = spec.policySetHash;
        configuration.amendmentPolicyHash = spec.amendmentPolicyHash;
        configuration.protectionPolicyHash = spec.protectionPolicyHash;
        configuration.recoveryPolicyHash = spec.recoveryPolicyHash;

        policyResolver.setCreation(spec.policySetHash, loanId, configuration, 2, bytes32(0), true);
        request = Phase9Types.LoanCreationRequest({
            oldLoanId: spec.oldLoanId,
            newLoanNonce: spec.newLoanNonce,
            refinanceId: spec.refinanceId,
            configuration: configuration,
            creationId: bytes32(0)
        });
    }

    function _createBootstrap(BootstrapSpec memory spec)
        internal
        returns (address loanAccount, address positionManager, bytes32 creationId)
    {
        (Phase9Types.LoanCreationRequest memory request, bytes32 bootstrapId) =
            _prepareBootstrap(spec);
        return _submitFresh(request, 1, bootstrapId);
    }

    function _createReplacement(ReplacementSpec memory spec)
        internal
        returns (bytes32 loanId, address loanAccount, address positionManager, bytes32 creationId)
    {
        Phase9Types.LoanCreationRequest memory request = _prepareReplacement(spec);
        loanId = request.configuration.loanId;
        (loanAccount, positionManager, creationId) = _submitFresh(request, 2, bytes32(0));
    }

    function _submitFresh(
        Phase9Types.LoanCreationRequest memory request,
        uint8 creationMode,
        bytes32 bootstrapId
    ) internal returns (address loanAccount, address positionManager, bytes32 creationId) {
        if (request.creationId != bytes32(0)) revert InvalidBootstrapHarnessState();
        uint64 loanNonce = phase9LoanFactory.nextLoanNonce();
        creationId = _deriveCreationId(request, creationMode, bootstrapId, loanNonce);
        (loanAccount, positionManager) = phase9LoanFactory.createLoan(request);

        Phase9Types.LoanCreationRequest memory stored =
            phase9LoanFactory.creationRequest(creationId);
        request.creationId = creationId;
        if (
            stored.creationId != creationId
                || keccak256(abi.encode(stored)) != keccak256(abi.encode(request))
                || loanAccount != phase9LoanFactory.loanAccount(request.configuration.loanId)
                || positionManager
                    != phase9LoanFactory.positionManager(request.configuration.loanId)
        ) {
            revert InvalidBootstrapHarnessState();
        }
        canonicalCreationIds[request.configuration.loanId] = creationId;
    }

    function _replayCanonical(bytes32 loanId)
        internal
        returns (address loanAccount, address positionManager)
    {
        bytes32 creationId = canonicalCreationIds[loanId];
        if (creationId == bytes32(0)) revert InvalidBootstrapHarnessState();
        Phase9Types.LoanCreationRequest memory stored =
            phase9LoanFactory.creationRequest(creationId);
        return phase9LoanFactory.createLoan(stored);
    }

    function _installBootstrapPositions(bytes32 loanId) internal {
        bytes32 bootstrapId = canonicalBootstrapIds[loanId];
        Phase9BootstrapPolicyResolver.BootstrapRecord memory record =
            policyResolver.bootstrap(bootstrapId);
        IPositionManagerV2 manager = IPositionManagerV2(phase9LoanFactory.positionManager(loanId));
        for (uint256 index = 0; index < record.initialTranches.length; ++index) {
            manager.registerTranche(record.initialTranches[index]);
        }
        for (uint256 index = 0; index < record.initialPositions.length; ++index) {
            manager.issuePosition(record.initialPositions[index]);
        }
    }

    function _recordBootstrapSecurity(bytes32 loanId) internal {
        bytes32 bootstrapId = canonicalBootstrapIds[loanId];
        Phase9BootstrapPolicyResolver.BootstrapRecord memory record =
            policyResolver.bootstrap(bootstrapId);
        for (uint256 index = 0; index < record.custodyRecords.length; ++index) {
            bytes32 operationId = _deriveCustodyOperationId(
                bootstrapId, loanId, record.custodyRecords[index].collateralId
            );
            collateralCustody.recordCustody(record.custodyRecords[index], operationId);
            lienRegistry.registerLien(record.liens[index]);
        }
    }

    function _canonicalRequest(bytes32 loanId)
        internal
        view
        returns (Phase9Types.LoanCreationRequest memory)
    {
        return phase9LoanFactory.creationRequest(canonicalCreationIds[loanId]);
    }

    function _configuration(bytes32 loanId, address borrower, address predictedManager)
        private
        view
        returns (Phase9Types.LoanConfiguration memory configuration)
    {
        configuration.factory = address(phase9LoanFactory);
        configuration.loanRegistry = address(loanRegistry);
        configuration.settlementToken = address(settlementToken);
        configuration.settlementAssetId = SETTLEMENT_ASSET_ID;
        configuration.borrower = borrower;
        configuration.positionManager = predictedManager;
        configuration.collateralCustody = address(collateralCustody);
        configuration.lienRegistry = address(lienRegistry);
        configuration.payoffQuoteEngine = address(payoffQuoteEngine);
        configuration.refinanceCoordinator = address(this);
        configuration.restructuringController = address(restructuringController);
        configuration.insuranceManager = address(insuranceManager);
        configuration.recoveryManager = address(recoveryManager);
        configuration.loanId = loanId;
    }

    function _bootstrapRecord(
        BootstrapSpec memory spec,
        Phase9Types.LoanConfiguration memory configuration,
        bytes32 bootstrapId
    ) private returns (Phase9BootstrapPolicyResolver.BootstrapRecord memory record) {
        uint256 claim = spec.outstandingPrincipal + spec.accruedInterest;
        bytes32 trancheId = keccak256(abi.encode("PHASE9_BOOTSTRAP_TRANCHE", spec.seed));
        bytes32 positionId = keccak256(abi.encode("PHASE9_BOOTSTRAP_POSITION", spec.seed));

        record.policySetHash = spec.policySetHash;
        record.loanId = spec.loanId;
        record.initialDebt = Phase9Types.DebtState({
            lifecycle: Phase9Types.LoanLifecycle.ACTIVE,
            servicingState: Phase9Types.ServicingState.CURRENT,
            termsVersion: 1,
            debtStateVersion: 1,
            stateNonce: 1,
            commencementTime: 1,
            maturityTime: 2,
            scheduleHash: keccak256(abi.encode("PHASE9_BOOTSTRAP_SCHEDULE", spec.seed)),
            outstandingPrincipal: spec.outstandingPrincipal,
            accruedInterest: spec.accruedInterest,
            capitalizedInterest: 0,
            accruedFees: 0,
            accruedPenalties: 0,
            recoverableCosts: 0,
            unappliedCredit: 0,
            coveredLossExposure: 0,
            realizedLoss: 0,
            writtenOffAmount: 0,
            recoveredAfterWriteoff: 0,
            activeRefinanceId: bytes32(0),
            activeRestructureId: bytes32(0)
        });
        record.initialTranches = new Phase9Types.Tranche[](1);
        record.initialTranches[0] = Phase9Types.Tranche({
            trancheId: trancheId,
            priority: 1,
            originalClaim: claim,
            outstandingClaim: claim,
            configurationHash: keccak256(abi.encode("PHASE9_BOOTSTRAP_TRANCHE_CONFIG", spec.seed))
        });
        record.initialPositions = new Phase9Types.Position[](1);
        record.initialPositions[0] = Phase9Types.Position({
            positionId: positionId,
            trancheId: trancheId,
            owner: spec.lender,
            votingPower: claim,
            claim: claim,
            state: Phase9Types.PositionState.ACTIVE
        });

        (record.custodyRecords, record.liens) =
            _bootstrapSecurityRecords(spec, configuration, bootstrapId);
        record.active = true;
    }

    function _bootstrapSecurityRecords(
        BootstrapSpec memory spec,
        Phase9Types.LoanConfiguration memory configuration,
        bytes32 bootstrapId
    )
        private
        returns (Phase9Types.CustodyRecord[] memory custodyRecords, Phase9Types.Lien[] memory liens)
    {
        bytes32 tokenRuntimeHash = address(settlementToken).codehash;
        custodyAssetSource.setAsset(
            spec.collateralAssetId,
            Phase9BootstrapAssetSource.AssetRecord({
                token: address(settlementToken),
                decimals: 6,
                runtimeCodeHash: tokenRuntimeHash,
                exactBalanceDelta: true,
                active: true
            })
        );

        custodyRecords = new Phase9Types.CustodyRecord[](1);
        custodyRecords[0] = Phase9Types.CustodyRecord({
            collateralId: spec.collateralId,
            assetId: spec.collateralAssetId,
            token: address(settlementToken),
            borrower: spec.borrower,
            quantity: spec.collateralQuantity,
            status: Phase9Types.CustodyStatus.HELD,
            identityHash: _deriveCustodyIdentity(spec, bootstrapId, tokenRuntimeHash)
        });
        liens = new Phase9Types.Lien[](1);
        liens[0] = Phase9Types.Lien({
            collateralId: spec.collateralId,
            collateralManager: configuration.collateralCustody,
            vault: configuration.collateralCustody,
            assetId: spec.collateralAssetId,
            quantity: spec.collateralQuantity,
            borrower: spec.borrower,
            seniorLoanId: spec.loanId,
            lienVersion: 1,
            status: Phase9Types.LienStatus.ACTIVE,
            pendingRefinanceId: bytes32(0),
            pendingTargetLoanId: bytes32(0)
        });
    }

    function _deriveCustodyIdentity(
        BootstrapSpec memory spec,
        bytes32 bootstrapId,
        bytes32 tokenRuntimeHash
    ) private view returns (bytes32) {
        bytes32 operationId = _deriveCustodyOperationId(bootstrapId, spec.loanId, spec.collateralId);
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1",
                block.chainid,
                address(collateralCustody),
                address(custodyAssetSource),
                operationId,
                spec.collateralId,
                spec.collateralAssetId,
                address(settlementToken),
                tokenRuntimeHash,
                uint8(6),
                true,
                spec.borrower,
                spec.collateralQuantity
            )
        );
    }

    function _deriveBootstrapId(bytes32 loanId, address borrower, bytes32 policySetHash)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_LOCAL_BOOTSTRAP_V1",
                block.chainid,
                address(phase9LoanFactory),
                address(policyResolver),
                loanId,
                borrower,
                policySetHash
            )
        );
    }

    function _deriveReplacementLoanId(ReplacementSpec memory spec) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_REFINANCED_LOAN_V1",
                block.chainid,
                address(phase9LoanFactory),
                spec.oldLoanId,
                spec.borrower,
                spec.agreementHash,
                spec.policySetHash,
                spec.newLoanNonce
            )
        );
    }

    function _deriveCreationId(
        Phase9Types.LoanCreationRequest memory request,
        uint8 creationMode,
        bytes32 bootstrapId,
        uint64 loanNonce
    ) internal view returns (bytes32) {
        CreationIdentity memory identity = CreationIdentity({
            chainId: block.chainid,
            factory: address(phase9LoanFactory),
            loanId: request.configuration.loanId,
            oldLoanId: request.oldLoanId,
            borrower: request.configuration.borrower,
            refinanceId: request.refinanceId,
            newLoanNonce: request.newLoanNonce,
            loanNonce: loanNonce,
            agreementHash: request.configuration.agreementHash,
            policySetHash: request.configuration.policySetHash,
            creationMode: creationMode,
            bootstrapId: bootstrapId,
            predictedAccount: _predictLoanAccount(request.configuration.loanId),
            predictedManager: _predictPositionManager(request.configuration.loanId)
        });
        return keccak256(abi.encode("UNIFIED_PHASE9_LOAN_CREATION_V1", identity));
    }

    function _deriveCustodyOperationId(bytes32 bootstrapId, bytes32 loanId, bytes32 collateralId)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_V1",
                block.chainid,
                address(this),
                bootstrapId,
                loanId,
                address(collateralCustody),
                collateralId
            )
        );
    }

    function _predictLoanAccount(bytes32 loanId) internal view returns (address) {
        bytes32 salt = keccak256(abi.encode("UNIFIED_PHASE9_LOAN_ACCOUNT_CLONE_V1", loanId));
        return _predictClone(address(loanAccountImplementation), salt);
    }

    function _predictPositionManager(bytes32 loanId) internal view returns (address) {
        bytes32 salt = keccak256(abi.encode("UNIFIED_PHASE9_POSITION_MANAGER_CLONE_V1", loanId));
        return _predictClone(address(positionManagerImplementation), salt);
    }

    function _predictClone(address implementation, bytes32 salt) private view returns (address) {
        bytes32 creationCodeHash = keccak256(
            abi.encodePacked(
                hex"3d602d80600a3d3981f3",
                hex"363d3d373d3d3d363d73",
                bytes20(implementation),
                hex"5af43d82803e903d91602b57fd5bf3"
            )
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(phase9LoanFactory), salt, creationCodeHash
                        )
                    )
                )
            )
        );
    }

    function _requireHarnessReady() private view {
        if (address(phase9LoanFactory) == address(0)) revert InvalidBootstrapHarnessState();
    }
}

/// @dev Shared real-stack fixture for the D1 refinance-request evidence suites.
abstract contract Phase9RefinanceRequestHarness {
    error RequestHarnessAlreadyInitialized();
    error InvalidRequestHarnessState();

    bytes32 internal constant REQUEST_SETTLEMENT_ASSET_ID =
        0x61737365743a7068617365393a7039756e697400000000000000000000000000;
    uint64 internal constant REQUEST_MAXIMUM_VALIDITY = 3_600;
    uint32 internal constant REQUEST_MAXIMUM_COMMITMENTS = 4;
    uint256 internal constant REQUEST_OLD_PRINCIPAL = 90;
    uint256 internal constant REQUEST_OLD_INTEREST = 5;
    uint256 internal constant REQUEST_NEW_PRINCIPAL = 120;
    uint256 internal constant REQUEST_REFINANCE_FEE = 2;
    uint256 internal constant REQUEST_BORROWER_PROCEEDS = 23;
    uint256 internal constant REQUEST_COLLATERAL_QUANTITY = 25;

    address internal constant REQUEST_OLD_LENDER = address(0x1E0D3);
    address internal constant REQUEST_NEW_LENDER = address(0xB0B);
    address internal constant REQUEST_TREASURY = address(0xFEE);

    struct RequestPolicyIdentity {
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

    RoleManager internal requestRoleManager;
    LoanRegistry internal requestLoanRegistry;
    Phase9LocalSyntheticToken internal requestSettlementToken;
    Phase9BootstrapPolicyResolver internal requestPolicyResolver;
    Phase9BootstrapAssetSource internal requestAssetSource;
    Phase9BootstrapEmergencyController internal requestEmergencyController;
    Phase9BootstrapDependencyStub internal requestAmendmentPolicyRegistry;
    Phase9BootstrapDependencyStub internal requestProtectionPolicyRegistry;
    Phase9BootstrapDependencyStub internal requestRecoveryPolicyRegistry;
    Phase9BootstrapDependencyStub internal requestRestructuringController;
    Phase9BootstrapDependencyStub internal requestInsuranceManager;
    Phase9BootstrapDependencyStub internal requestRecoveryManager;
    Phase9RefinanceRequestDeployer internal requestDeployer;
    Phase9RefinanceRequestDeployer.DeploymentComponents internal requestComponents;
    Phase9Types.RefinanceRecord internal requestRecord;
    bytes32 internal requestOldPolicySetHash;
    bytes32 internal requestOldBootstrapId;
    bytes32 internal requestCollateralId;
    bytes32 internal requestCollateralAssetId;
    bytes32 internal requestReplacementTrancheId;
    bytes32 internal requestReplacementPositionId;

    function _deployRequestHarness(bytes32 seed) internal {
        if (address(requestComponents.refinanceCoordinator) != address(0)) {
            revert RequestHarnessAlreadyInitialized();
        }
        if (block.chainid != 31337) revert InvalidRequestHarnessState();

        Phase9BootstrapGovernanceExecutor governance =
            new Phase9BootstrapGovernanceExecutor(address(this));
        requestRoleManager = new RoleManager(address(this), address(governance));
        requestLoanRegistry = new LoanRegistry(requestRoleManager);
        requestSettlementToken = new Phase9LocalSyntheticToken(address(this));
        requestPolicyResolver = new Phase9BootstrapPolicyResolver();
        requestAssetSource = new Phase9BootstrapAssetSource();
        requestEmergencyController = new Phase9BootstrapEmergencyController();
        requestAmendmentPolicyRegistry = new Phase9BootstrapDependencyStub();
        requestProtectionPolicyRegistry = new Phase9BootstrapDependencyStub();
        requestRecoveryPolicyRegistry = new Phase9BootstrapDependencyStub();
        requestRestructuringController = new Phase9BootstrapDependencyStub();
        requestInsuranceManager = new Phase9BootstrapDependencyStub();
        requestRecoveryManager = new Phase9BootstrapDependencyStub();
        requestDeployer = new Phase9RefinanceRequestDeployer();

        Phase9RefinanceRequestDeployer.DeploymentInputs memory inputs =
            Phase9RefinanceRequestDeployer.DeploymentInputs({
                loanRegistry: address(requestLoanRegistry),
                settlementToken: address(requestSettlementToken),
                quotePolicyRegistry: address(requestPolicyResolver),
                refinancePolicyRegistry: address(requestPolicyResolver),
                amendmentPolicyRegistry: address(requestAmendmentPolicyRegistry),
                protectionPolicyRegistry: address(requestProtectionPolicyRegistry),
                recoveryPolicyRegistry: address(requestRecoveryPolicyRegistry),
                assetRegistry: address(requestAssetSource),
                emergencyController: address(requestEmergencyController),
                treasuryFeeRecipient: REQUEST_TREASURY,
                maximumQuoteValidity: REQUEST_MAXIMUM_VALIDITY
            });
        requestComponents = requestDeployer.deploy(inputs);
        governance.grantLoanFactoryRole(requestRoleManager, address(requestComponents.loanFactory));

        _configureRequestFixture(seed);
    }

    function _configureRequestFixture(bytes32 seed) private {
        requestOldPolicySetHash = keccak256(abi.encode("P9R_OLD_POLICY", seed));
        requestCollateralId = keccak256(abi.encode("P9R_COLLATERAL", seed));
        requestCollateralAssetId = keccak256(abi.encode("P9R_COLLATERAL_ASSET", seed));

        bytes32 oldLoanId = keccak256(abi.encode("P9R_OLD_LOAN", seed));
        bytes32 oldAgreementHash = keccak256(abi.encode("P9R_OLD_AGREEMENT", seed));
        Phase9Types.LoanConfiguration memory oldConfiguration = _requestConfiguration(
            oldLoanId,
            address(this),
            _requestPredictManager(oldLoanId),
            oldAgreementHash,
            requestOldPolicySetHash,
            seed
        );
        requestOldBootstrapId = keccak256(
            abi.encode(
                "UNIFIED_PHASE9_LOCAL_BOOTSTRAP_V1",
                block.chainid,
                address(requestComponents.loanFactory),
                address(requestPolicyResolver),
                oldLoanId,
                address(this),
                requestOldPolicySetHash
            )
        );
        requestPolicyResolver.setCreation(
            requestOldPolicySetHash, oldLoanId, oldConfiguration, 1, requestOldBootstrapId, true
        );
        requestPolicyResolver.setBootstrapAt(
            requestOldBootstrapId, _requestBootstrapRecord(seed, oldLoanId, oldConfiguration)
        );

        _configureRequestReplacement(seed, oldLoanId);
        _configureRequestAssets();
        _configureRequestQuotePolicy(oldLoanId, oldConfiguration);
        requestSettlementToken.approve(
            address(requestComponents.collateralCustody), REQUEST_COLLATERAL_QUANTITY
        );
    }

    function _configureRequestReplacement(bytes32 seed, bytes32 oldLoanId) private {
        bytes32 newPolicySetHash = keccak256(abi.encode("P9R_NEW_POLICY", seed));
        bytes32 proposedTermsHash = keccak256(abi.encode("P9R_PROPOSED_TERMS", seed));
        bytes32 newAgreementHash = keccak256(abi.encode("P9R_NEW_AGREEMENT", seed));
        bytes32 newLoanId = keccak256(
            abi.encode(
                "UNIFIED_PHASE9_REFINANCED_LOAN_V1",
                block.chainid,
                address(requestComponents.loanFactory),
                oldLoanId,
                address(this),
                newAgreementHash,
                newPolicySetHash,
                uint64(1)
            )
        );
        address newManager = _requestPredictManager(newLoanId);
        Phase9Types.LoanConfiguration memory newConfiguration = _requestConfiguration(
            newLoanId,
            address(this),
            newManager,
            newAgreementHash,
            newPolicySetHash,
            keccak256(abi.encode("P9R_REPLACEMENT_CONFIGURATION", seed))
        );
        requestPolicyResolver.setCreation(
            newPolicySetHash, newLoanId, newConfiguration, 2, bytes32(0), true
        );

        Phase9Types.DebtState memory replacementDebt = _requestReplacementDebt(seed);
        Phase9Types.Tranche[] memory replacementTranches = _requestReplacementTranches(seed);
        Phase9Types.Position[] memory replacementPositions =
            _requestReplacementPositions(seed, replacementTranches[0].trancheId);
        bytes32[] memory collateralIds = new bytes32[](1);
        collateralIds[0] = requestCollateralId;

        bytes32 collateralEntryHash = keccak256(
            abi.encode(
                requestCollateralId,
                requestCollateralAssetId,
                REQUEST_COLLATERAL_QUANTITY,
                address(requestComponents.collateralCustody),
                address(this),
                uint64(1)
            )
        );
        bytes32[] memory collateralEntryHashes = new bytes32[](1);
        collateralEntryHashes[0] = collateralEntryHash;

        requestRecord.oldLoanId = oldLoanId;
        requestRecord.newLoanId = newLoanId;
        requestRecord.borrower = address(this);
        requestRecord.oldLender = REQUEST_OLD_LENDER;
        requestRecord.newPositionManager = newManager;
        requestRecord.componentBeneficiaryHash = _requestComponentBeneficiaryHash();
        requestRecord.oldNetPayoff = REQUEST_OLD_PRINCIPAL + REQUEST_OLD_INTEREST;
        requestRecord.newPrincipal = REQUEST_NEW_PRINCIPAL;
        requestRecord.settlementAssetId = REQUEST_SETTLEMENT_ASSET_ID;
        requestRecord.collateralSetHash = keccak256(abi.encode(collateralEntryHashes));
        requestRecord.lienVersion = 1;
        requestRecord.proposedTermsHash = proposedTermsHash;
        requestRecord.newPolicySetHash = newPolicySetHash;
        requestRecord.fundingAmount = REQUEST_NEW_PRINCIPAL;
        requestRecord.refinanceFee = REQUEST_REFINANCE_FEE;
        requestRecord.borrowerProceeds = REQUEST_BORROWER_PROCEEDS;
        requestRecord.expiresAt = uint64(block.timestamp + 600);
        requestRecord.refinanceNonce = 1;
        requestRecord.newLoanNonce = 1;
        requestRecord.refinancePolicyHash = _requestPolicyHash(
            requestOldPolicySetHash,
            collateralIds,
            replacementDebt,
            replacementTranches,
            replacementPositions
        );

        Phase9BootstrapPolicyResolver.RefinancePolicyRecord memory policy;
        policy.boundOldPolicySetHash = requestOldPolicySetHash;
        policy.boundNewPolicySetHash = newPolicySetHash;
        policy.proposedTermsHash = proposedTermsHash;
        policy.maximumValidity = REQUEST_MAXIMUM_VALIDITY;
        policy.maximumCommitments = REQUEST_MAXIMUM_COMMITMENTS;
        policy.active = true;
        policy.collateralIds = collateralIds;
        policy.replacementDebt = replacementDebt;
        policy.replacementTranches = replacementTranches;
        policy.replacementPositions = replacementPositions;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, policy);
    }

    function _configureRequestAssets() private {
        Phase9BootstrapAssetSource.AssetRecord memory asset = Phase9BootstrapAssetSource.AssetRecord({
            token: address(requestSettlementToken),
            decimals: 6,
            runtimeCodeHash: address(requestSettlementToken).codehash,
            exactBalanceDelta: true,
            active: true
        });
        requestAssetSource.setAsset(REQUEST_SETTLEMENT_ASSET_ID, asset);
        requestAssetSource.setAsset(requestCollateralAssetId, asset);
    }

    function _configureRequestQuotePolicy(
        bytes32 oldLoanId,
        Phase9Types.LoanConfiguration memory oldConfiguration
    ) private {
        address oldAccount = _requestPredictAccount(oldLoanId);
        bytes32 quotePolicyHash = keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_POLICY_V1",
                block.chainid,
                address(requestComponents.payoffQuoteEngine),
                address(requestPolicyResolver),
                oldLoanId,
                oldAccount,
                oldConfiguration.policySetHash,
                REQUEST_TREASURY,
                REQUEST_SETTLEMENT_ASSET_ID,
                address(requestSettlementToken),
                REQUEST_MAXIMUM_VALIDITY
            )
        );
        requestPolicyResolver.setPayoffQuotePolicy(
            oldLoanId,
            oldAccount,
            Phase9BootstrapPolicyResolver.CompositePayoffQuotePolicyRecord({
                policyHash: quotePolicyHash,
                boundPolicySetHash: oldConfiguration.policySetHash,
                feePenaltyBeneficiary: REQUEST_TREASURY,
                settlementAssetId: REQUEST_SETTLEMENT_ASSET_ID,
                settlementToken: address(requestSettlementToken),
                maximumValidity: REQUEST_MAXIMUM_VALIDITY,
                active: true
            })
        );
    }

    function _requestConfiguration(
        bytes32 loanId,
        address borrower,
        address manager,
        bytes32 agreementHash,
        bytes32 policySetHash,
        bytes32 seed
    ) private view returns (Phase9Types.LoanConfiguration memory configuration) {
        configuration = Phase9Types.LoanConfiguration({
                factory: address(requestComponents.loanFactory),
                loanRegistry: address(requestLoanRegistry),
                settlementToken: address(requestSettlementToken),
                settlementAssetId: REQUEST_SETTLEMENT_ASSET_ID,
                borrower: borrower,
                positionManager: manager,
                collateralCustody: address(requestComponents.collateralCustody),
                lienRegistry: address(requestComponents.lienRegistry),
                payoffQuoteEngine: address(requestComponents.payoffQuoteEngine),
                refinanceCoordinator: address(requestComponents.refinanceCoordinator),
                restructuringController: address(requestRestructuringController),
                insuranceManager: address(requestInsuranceManager),
                recoveryManager: address(requestRecoveryManager),
                loanId: loanId,
                agreementHash: agreementHash,
                policySetHash: policySetHash,
                amendmentPolicyHash: keccak256(abi.encode("P9R_AMENDMENT", seed)),
                protectionPolicyHash: keccak256(abi.encode("P9R_PROTECTION", seed)),
                recoveryPolicyHash: keccak256(abi.encode("P9R_RECOVERY", seed))
            });
    }

    function _requestBootstrapRecord(
        bytes32 seed,
        bytes32 oldLoanId,
        Phase9Types.LoanConfiguration memory configuration
    ) private view returns (Phase9BootstrapPolicyResolver.BootstrapRecord memory record) {
        bytes32 trancheId = keccak256(abi.encode("P9R_OLD_TRANCHE", seed));
        bytes32 positionId = keccak256(abi.encode("P9R_OLD_POSITION", seed));
        record.policySetHash = configuration.policySetHash;
        record.loanId = oldLoanId;
        record.initialDebt = Phase9Types.DebtState({
            lifecycle: Phase9Types.LoanLifecycle.ACTIVE,
            servicingState: Phase9Types.ServicingState.CURRENT,
            termsVersion: 1,
            debtStateVersion: 1,
            stateNonce: 1,
            commencementTime: 1,
            maturityTime: 2,
            scheduleHash: keccak256(abi.encode("P9R_OLD_SCHEDULE", seed)),
            outstandingPrincipal: REQUEST_OLD_PRINCIPAL,
            accruedInterest: REQUEST_OLD_INTEREST,
            capitalizedInterest: 0,
            accruedFees: 0,
            accruedPenalties: 0,
            recoverableCosts: 0,
            unappliedCredit: 0,
            coveredLossExposure: 0,
            realizedLoss: 0,
            writtenOffAmount: 0,
            recoveredAfterWriteoff: 0,
            activeRefinanceId: bytes32(0),
            activeRestructureId: bytes32(0)
        });
        record.initialTranches = new Phase9Types.Tranche[](1);
        record.initialTranches[0] = Phase9Types.Tranche({
            trancheId: trancheId,
            priority: 1,
            originalClaim: REQUEST_OLD_PRINCIPAL + REQUEST_OLD_INTEREST,
            outstandingClaim: REQUEST_OLD_PRINCIPAL + REQUEST_OLD_INTEREST,
            configurationHash: keccak256(abi.encode("P9R_OLD_TRANCHE_CONFIG", seed))
        });
        record.initialPositions = new Phase9Types.Position[](1);
        record.initialPositions[0] = Phase9Types.Position({
            positionId: positionId,
            trancheId: trancheId,
            owner: REQUEST_OLD_LENDER,
            votingPower: REQUEST_OLD_PRINCIPAL + REQUEST_OLD_INTEREST,
            claim: REQUEST_OLD_PRINCIPAL + REQUEST_OLD_INTEREST,
            state: Phase9Types.PositionState.ACTIVE
        });
        record.custodyRecords = new Phase9Types.CustodyRecord[](1);
        record.liens = new Phase9Types.Lien[](1);
        bytes32 operationId = keccak256(
            abi.encode(
                "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_V1",
                block.chainid,
                address(requestComponents.refinanceCoordinator),
                requestOldBootstrapId,
                oldLoanId,
                address(requestComponents.collateralCustody),
                requestCollateralId
            )
        );
        bytes32 identityHash = keccak256(
            abi.encode(
                "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1",
                block.chainid,
                address(requestComponents.collateralCustody),
                address(requestAssetSource),
                operationId,
                requestCollateralId,
                requestCollateralAssetId,
                address(requestSettlementToken),
                address(requestSettlementToken).codehash,
                uint8(6),
                true,
                address(this),
                REQUEST_COLLATERAL_QUANTITY
            )
        );
        record.custodyRecords[0] = Phase9Types.CustodyRecord({
            collateralId: requestCollateralId,
            assetId: requestCollateralAssetId,
            token: address(requestSettlementToken),
            borrower: address(this),
            quantity: REQUEST_COLLATERAL_QUANTITY,
            status: Phase9Types.CustodyStatus.HELD,
            identityHash: identityHash
        });
        record.liens[0] = Phase9Types.Lien({
            collateralId: requestCollateralId,
            collateralManager: address(requestComponents.collateralCustody),
            vault: address(requestComponents.collateralCustody),
            assetId: requestCollateralAssetId,
            quantity: REQUEST_COLLATERAL_QUANTITY,
            borrower: address(this),
            seniorLoanId: oldLoanId,
            lienVersion: 1,
            status: Phase9Types.LienStatus.ACTIVE,
            pendingRefinanceId: bytes32(0),
            pendingTargetLoanId: bytes32(0)
        });
        record.active = true;
    }

    function _requestReplacementDebt(bytes32 seed)
        private
        pure
        returns (Phase9Types.DebtState memory debt)
    {
        debt = Phase9Types.DebtState({
            lifecycle: Phase9Types.LoanLifecycle.ACTIVE,
            servicingState: Phase9Types.ServicingState.CURRENT,
            termsVersion: 1,
            debtStateVersion: 1,
            stateNonce: 1,
            commencementTime: 1,
            maturityTime: 2,
            scheduleHash: keccak256(abi.encode("P9R_NEW_SCHEDULE", seed)),
            outstandingPrincipal: REQUEST_NEW_PRINCIPAL,
            accruedInterest: 0,
            capitalizedInterest: 0,
            accruedFees: 0,
            accruedPenalties: 0,
            recoverableCosts: 0,
            unappliedCredit: 0,
            coveredLossExposure: 0,
            realizedLoss: 0,
            writtenOffAmount: 0,
            recoveredAfterWriteoff: 0,
            activeRefinanceId: bytes32(0),
            activeRestructureId: bytes32(0)
        });
    }

    function _requestReplacementTranches(bytes32 seed)
        private
        returns (Phase9Types.Tranche[] memory tranches)
    {
        requestReplacementTrancheId = keccak256(abi.encode("P9R_NEW_TRANCHE", seed));
        tranches = new Phase9Types.Tranche[](1);
        tranches[0] = Phase9Types.Tranche({
            trancheId: requestReplacementTrancheId,
            priority: 1,
            originalClaim: REQUEST_NEW_PRINCIPAL,
            outstandingClaim: REQUEST_NEW_PRINCIPAL,
            configurationHash: keccak256(abi.encode("P9R_NEW_TRANCHE_CONFIG", seed))
        });
    }

    function _requestReplacementPositions(bytes32 seed, bytes32 trancheId)
        private
        returns (Phase9Types.Position[] memory positions)
    {
        requestReplacementPositionId = keccak256(abi.encode("P9R_NEW_POSITION", seed));
        positions = new Phase9Types.Position[](1);
        positions[0] = Phase9Types.Position({
            positionId: requestReplacementPositionId,
            trancheId: trancheId,
            owner: REQUEST_NEW_LENDER,
            votingPower: REQUEST_NEW_PRINCIPAL,
            claim: REQUEST_NEW_PRINCIPAL,
            state: Phase9Types.PositionState.ACTIVE
        });
    }

    function _requestComponentBeneficiaryHash() private pure returns (bytes32) {
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components =
            new IPayoffQuoteEngineV2.PayoffComponentV2[](5);
        components[0] = IPayoffQuoteEngineV2.PayoffComponentV2({
            kind: IPayoffQuoteEngineV2.ComponentKind.PRINCIPAL,
            amount: REQUEST_OLD_PRINCIPAL,
            beneficiary: REQUEST_OLD_LENDER,
            obligationCode: "PRINCIPAL"
        });
        components[1] = IPayoffQuoteEngineV2.PayoffComponentV2({
            kind: IPayoffQuoteEngineV2.ComponentKind.ACCRUED_INTEREST,
            amount: REQUEST_OLD_INTEREST,
            beneficiary: REQUEST_OLD_LENDER,
            obligationCode: "ACCRUED_INTEREST"
        });
        components[2] = IPayoffQuoteEngineV2.PayoffComponentV2({
            kind: IPayoffQuoteEngineV2.ComponentKind.FEE,
            amount: 0,
            beneficiary: REQUEST_TREASURY,
            obligationCode: "FEE"
        });
        components[3] = IPayoffQuoteEngineV2.PayoffComponentV2({
            kind: IPayoffQuoteEngineV2.ComponentKind.PENALTY,
            amount: 0,
            beneficiary: REQUEST_TREASURY,
            obligationCode: "PENALTY"
        });
        components[4] = IPayoffQuoteEngineV2.PayoffComponentV2({
            kind: IPayoffQuoteEngineV2.ComponentKind.CREDIT,
            amount: 0,
            beneficiary: REQUEST_TREASURY,
            obligationCode: "FEE_PENALTY_CREDIT"
        });
        return keccak256(abi.encode("UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1", components));
    }

    function _requestPolicyHash(
        bytes32 oldPolicySetHash,
        bytes32[] memory collateralIds,
        Phase9Types.DebtState memory replacementDebt,
        Phase9Types.Tranche[] memory replacementTranches,
        Phase9Types.Position[] memory replacementPositions
    ) private view returns (bytes32) {
        RequestPolicyIdentity memory identity = RequestPolicyIdentity({
            chainId: block.chainid,
            coordinator: address(requestComponents.refinanceCoordinator),
            policyRegistry: address(requestPolicyResolver),
            oldLoanId: requestRecord.oldLoanId,
            newLoanId: requestRecord.newLoanId,
            borrower: requestRecord.borrower,
            oldLender: requestRecord.oldLender,
            newPositionManager: requestRecord.newPositionManager,
            oldPolicySetHash: oldPolicySetHash,
            newPolicySetHash: requestRecord.newPolicySetHash,
            proposedTermsHash: requestRecord.proposedTermsHash,
            settlementAssetId: requestRecord.settlementAssetId,
            collateralSetHash: requestRecord.collateralSetHash,
            fundingAmount: requestRecord.fundingAmount,
            refinanceFee: requestRecord.refinanceFee,
            borrowerProceeds: requestRecord.borrowerProceeds,
            expiresAt: requestRecord.expiresAt,
            maximumValidity: REQUEST_MAXIMUM_VALIDITY,
            maximumCommitments: REQUEST_MAXIMUM_COMMITMENTS,
            collateralIdsHash: keccak256(abi.encode(collateralIds)),
            replacementDebtHash: keccak256(abi.encode(replacementDebt)),
            replacementTranchesHash: keccak256(abi.encode(replacementTranches)),
            replacementPositionsHash: keccak256(abi.encode(replacementPositions))
        });
        return keccak256(abi.encode("UNIFIED_REFINANCE_POLICY_V1", identity));
    }

    function _requestPredictAccount(bytes32 loanId) internal view returns (address) {
        return _requestPredictClone(
            address(requestComponents.loanAccountImplementation),
            keccak256(abi.encode("UNIFIED_PHASE9_LOAN_ACCOUNT_CLONE_V1", loanId))
        );
    }

    function _requestPredictManager(bytes32 loanId) internal view returns (address) {
        return _requestPredictClone(
            address(requestComponents.positionManagerImplementation),
            keccak256(abi.encode("UNIFIED_PHASE9_POSITION_MANAGER_CLONE_V1", loanId))
        );
    }

    function _requestPredictClone(address implementation, bytes32 salt)
        private
        view
        returns (address)
    {
        bytes32 creationCodeHash = keccak256(
            abi.encodePacked(
                hex"3d602d80600a3d3981f3",
                hex"363d3d373d3d3d363d73",
                bytes20(implementation),
                hex"5af43d82803e903d91602b57fd5bf3"
            )
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(requestComponents.loanFactory),
                            salt,
                            creationCodeHash
                        )
                    )
                )
            )
        );
    }

    function _requestRefinance() internal returns (bytes32) {
        return requestComponents.refinanceCoordinator.requestRefinance(requestRecord);
    }

    function _requestSelector(bytes memory returned) internal pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
