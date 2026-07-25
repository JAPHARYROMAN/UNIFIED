// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossChainLoanPolicy } from "../src/interfaces/ICrossChainLoanPolicy.sol";
import { IUnifiedToken } from "../src/interfaces/IUnifiedToken.sol";
import { BridgeExposurePolicy } from "../src/crosschain/BridgeExposurePolicy.sol";
import { ChainRegistry } from "../src/crosschain/ChainRegistry.sol";
import { CrossChainCoordinator } from "../src/crosschain/CrossChainCoordinator.sol";
import { CrossChainLoanAccount } from "../src/crosschain/CrossChainLoanAccount.sol";
import { CrossChainLoanAccountDeployer } from "../src/crosschain/CrossChainLoanAccountDeployer.sol";
import { CrossChainLoanFactory } from "../src/crosschain/CrossChainLoanFactory.sol";
import { CrossChainLoanPolicy } from "../src/crosschain/CrossChainLoanPolicy.sol";
import { CrossChainRecoveryController } from "../src/crosschain/CrossChainRecoveryController.sol";
import { CrossChainTypes } from "../src/crosschain/CrossChainTypes.sol";
import { Phase8LocalSyntheticToken } from "../src/crosschain/Phase8LocalSyntheticToken.sol";
import { RouteRegistry } from "../src/crosschain/RouteRegistry.sol";
import { SatelliteCollateralVault } from "../src/crosschain/SatelliteCollateralVault.sol";
import { SatelliteLoanComponent } from "../src/crosschain/SatelliteLoanComponent.sol";
import { SatelliteSettlementVault } from "../src/crosschain/SatelliteSettlementVault.sol";
import { SyntheticFinalityVerifier } from "../src/crosschain/SyntheticFinalityVerifier.sol";
import { UFTBridgeHub } from "../src/crosschain/UFTBridgeHub.sol";
import { WrappedUFT } from "../src/crosschain/WrappedUFT.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";

interface Phase8LocalDeploymentVm {
    function createSelectFork(string calldata rpcUrl) external returns (uint256 forkId);
    function selectFork(uint256 forkId) external;
    function startBroadcast() external;
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
    function addr(uint256 privateKey) external returns (address);
    function ffi(string[] calldata commandInput) external returns (bytes memory result);
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
    function toString(bytes32 value) external returns (string memory stringifiedValue);
    function serializeAddress(string calldata objectKey, string calldata valueKey, address value)
        external
        returns (string memory json);
    function serializeBool(string calldata objectKey, string calldata valueKey, bool value)
        external
        returns (string memory json);
    function serializeBytes(
        string calldata objectKey,
        string calldata valueKey,
        bytes calldata value
    ) external returns (string memory json);
    function serializeBytes32(string calldata objectKey, string calldata valueKey, bytes32 value)
        external
        returns (string memory json);
    function serializeString(
        string calldata objectKey,
        string calldata valueKey,
        string calldata value
    ) external returns (string memory json);
    function serializeUint(string calldata objectKey, string calldata valueKey, uint256 value)
        external
        returns (string memory json);
    function writeJson(string calldata json, string calldata path) external;
    function writeJson(string calldata json, string calldata path, string calldata valueKey)
        external;
}

/// @notice Deploys the synthetic Phase 8 bridge foundation across two local Anvil domains.
contract DeployPhase8Local {
    Phase8LocalDeploymentVm private constant vm =
        Phase8LocalDeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant HOME_CHAIN_ID = 31_337;
    uint256 private constant SATELLITE_CHAIN_ID = 31_338;
    bytes32 private constant PROTOCOL_ID = keccak256("UNIFIED_PHASE8_LOCAL_V1");
    bytes32 private constant HOME_OBSERVER_PUBLIC_KEY =
        0xe84d4f1b0cf0e0217292b079bb4db43ad1416f4609b111675e720d2b1dbc0eac;
    bytes32 private constant SATELLITE_OBSERVER_PUBLIC_KEY =
        0xb442c9cb0eb1bce60df619505451f95701b64e32b269bda231d95a7475f5a6ac;
    address private constant LOCAL_ADMIN = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address private constant LOCAL_GOVERNANCE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 private constant SIGNER_ONE_KEY = 1;
    uint256 private constant SIGNER_TWO_KEY = 2;
    uint256 private constant SIGNER_THREE_KEY = 3;
    bytes32 private constant LOAN_ID = keccak256("LOCAL_FULL_FLOW_LOAN");
    bytes32 private constant LOCK_ID = keccak256("LOCAL_FULL_FLOW_LOCK");
    bytes32 private constant COLLATERAL_ID = keccak256("LOCAL_FULL_FLOW_COLLATERAL");
    bytes32 private constant POLICY_HASH = keccak256("LOCAL_FULL_FLOW_POLICY");
    uint256 private constant PRINCIPAL = 100 ether;
    uint256 private constant COLLATERAL_AMOUNT = 150 ether;

    struct Domain {
        uint256 chainId;
        RoleManager roles;
        ChainRegistry chains;
        EmergencyController emergency;
        RouteRegistry routes;
        SyntheticFinalityVerifier verifier;
        CrossChainCoordinator coordinator;
        CrossChainRecoveryController recovery;
        bytes32 signerSetHash;
        bytes32 coordinatorCodeHash;
        bytes32 verifierCodeHash;
        uint64 activationBlock;
    }

    struct MessageEvidence {
        CrossChainTypes.MessageEnvelope envelope;
        bytes payload;
        CrossChainTypes.SourceEventProof sourceProof;
        CrossChainTypes.FinalityCertificate sourceCertificate;
        bytes32 destinationResultHash;
        CrossChainTypes.SourceEventProof acknowledgementProof;
        CrossChainTypes.FinalityCertificate acknowledgementCertificate;
    }

    struct RunState {
        uint256 homeFork;
        uint256 satelliteFork;
        uint64 activatedAt;
        Domain home;
        Domain satellite;
        Phase8LocalSyntheticToken canonical;
        Phase8LocalSyntheticToken collateral;
        BridgeExposurePolicy exposure;
        UFTBridgeHub hub;
        WrappedUFT wrapped;
        LoanRegistry loanRegistry;
        CrossChainLoanAccountDeployer accountDeployer;
        CrossChainLoanFactory loanFactory;
        CrossChainLoanPolicy loanPolicy;
        SatelliteLoanComponent satelliteComponent;
        SatelliteCollateralVault collateralVault;
        SatelliteSettlementVault settlementVault;
        CrossChainLoanAccount loanAccount;
        bytes32 hubCodeHash;
        bytes32 wrappedCodeHash;
        bytes32 loanFactoryCodeHash;
        bytes32 satelliteComponentCodeHash;
        bytes32 collateralVaultCodeHash;
        bytes32 settlementVaultCodeHash;
        bytes32 mintRouteHash;
        bytes32 reportRouteHash;
        bytes32 repaymentRouteHash;
        bytes32 alternateRepaymentRouteHash;
        bytes32 bridgeExitRouteHash;
        bytes32 disbursementRouteHash;
        bytes32 collateralReleaseRouteHash;
        bytes32 exposureHash;
        bytes32 sampleMessageId;
        uint8 flowMessageCount;
        MessageEvidence[8] flowMessages;
        bytes32 mintReplayResultHash;
        bytes32 repaymentReplayResultHash;
        bytes32 collateralReleaseReplayResultHash;
        uint256 borrowerReceivedPrincipalUnits;
        uint256 lenderReceivedRepaymentUnits;
    }

    function run(string calldata homeRpc, string calldata satelliteRpc, string calldata outputRoot)
        external
    {
        _run(homeRpc, satelliteRpc, outputRoot, true);
    }

    /// @notice Deploy and configure the two local domains without creating any
    /// loan or cross-chain message. The live evidence runner uses the emitted
    /// blueprint to stage source receipt finality before destination execution.
    function runDeployOnly(
        string calldata homeRpc,
        string calldata satelliteRpc,
        string calldata outputRoot
    ) external {
        _run(homeRpc, satelliteRpc, outputRoot, false);
    }

    function _run(
        string calldata homeRpc,
        string calldata satelliteRpc,
        string calldata outputRoot,
        bool executeDiagnosticFlow
    ) private {
        RunState memory state;
        state.homeFork = vm.createSelectFork(homeRpc);
        // The smoke runners pin both Anvil domains to this timestamp while broadcasting.
        state.activatedAt = uint64(block.timestamp);
        state.home = _deployDomain(HOME_CHAIN_ID, state.activatedAt);

        state.satelliteFork = vm.createSelectFork(satelliteRpc);
        require(block.timestamp == state.activatedAt, "domain timestamps differ");
        state.satellite = _deployDomain(SATELLITE_CHAIN_ID, state.activatedAt);
        _registerRemoteSignerSets(state);

        vm.selectFork(state.homeFork);
        _registerChains(state.home, state.satellite, state.activatedAt);
        vm.selectFork(state.satelliteFork);
        _registerChains(state.satellite, state.home, state.activatedAt);

        vm.selectFork(state.homeFork);
        vm.startBroadcast();
        state.home.recovery = new CrossChainRecoveryController(
            state.home.coordinator, state.home.routes, state.home.verifier, _recoverySigners()
        );
        state.home.coordinator.configureRecoveryController(address(state.home.recovery));
        state.canonical = new Phase8LocalSyntheticToken("Synthetic Local UFT", "sUFT");
        state.exposure =
            new BridgeExposurePolicy(state.home.roles, IUnifiedToken(address(state.canonical)));
        state.hub = new UFTBridgeHub(
            state.home.roles,
            IUnifiedToken(address(state.canonical)),
            state.home.coordinator,
            state.home.routes,
            state.exposure,
            address(state.home.recovery)
        );
        state.loanRegistry = new LoanRegistry(state.home.roles);
        state.accountDeployer = new CrossChainLoanAccountDeployer(state.home.roles);
        state.loanFactory = new CrossChainLoanFactory(
            state.home.roles,
            state.loanRegistry,
            state.hub,
            state.home.coordinator,
            state.home.routes,
            state.accountDeployer
        );
        state.accountDeployer.bindFactory(address(state.loanFactory));
        state.home.roles
            .grantRole(
                ProtocolRoles.LOAN_FACTORY_ROLE, address(state.loanFactory), type(uint64).max
            );
        state.hubCodeHash = address(state.hub).codehash;
        state.loanFactoryCodeHash = address(state.loanFactory).codehash;
        vm.stopBroadcast();

        vm.selectFork(state.satelliteFork);
        vm.startBroadcast();
        state.satellite.recovery = new CrossChainRecoveryController(
            state.satellite.coordinator,
            state.satellite.routes,
            state.satellite.verifier,
            _recoverySigners()
        );
        state.satellite.coordinator.configureRecoveryController(address(state.satellite.recovery));
        state.collateral = new Phase8LocalSyntheticToken("Synthetic Local Collateral", "sCOL");
        state.wrapped = new WrappedUFT(
            state.satellite.roles,
            HOME_CHAIN_ID,
            address(state.canonical),
            address(state.hub),
            state.satellite.coordinator,
            state.satellite.routes,
            address(state.satellite.recovery)
        );
        state.satelliteComponent = new SatelliteLoanComponent(
            state.satellite.roles, state.satellite.coordinator, state.satellite.routes
        );
        state.collateralVault = new SatelliteCollateralVault(
            address(state.satelliteComponent),
            state.satellite.coordinator,
            IERC20(address(state.collateral))
        );
        state.settlementVault = new SatelliteSettlementVault(
            address(state.satelliteComponent),
            state.satellite.coordinator,
            IERC20(address(state.wrapped))
        );
        state.wrappedCodeHash = address(state.wrapped).codehash;
        state.satelliteComponentCodeHash = address(state.satelliteComponent).codehash;
        state.collateralVaultCodeHash = address(state.collateralVault).codehash;
        state.settlementVaultCodeHash = address(state.settlementVault).codehash;
        vm.stopBroadcast();

        RouteRegistry.RouteConfig memory mintRoute = _mintRoute(
            state.home,
            state.satellite,
            address(state.hub),
            address(state.wrapped),
            state.hubCodeHash,
            state.wrappedCodeHash,
            state.activatedAt
        );
        mintRoute = _registerFinalityPolicies(state, mintRoute);

        vm.selectFork(state.homeFork);
        vm.startBroadcast();
        state.mintRouteHash = state.home.routes.registerRoute(mintRoute);
        state.exposureHash = _registerExposure(state.exposure, state.canonical, state.activatedAt);
        state.exposure.activateForRoute(state.mintRouteHash, state.exposureHash);
        vm.stopBroadcast();

        vm.selectFork(state.satelliteFork);
        vm.startBroadcast();
        require(
            state.satellite.routes.registerRoute(mintRoute) == state.mintRouteHash, "route drift"
        );
        state.wrapped.configureCanonicalBackingRoute(state.mintRouteHash);
        vm.stopBroadcast();

        _configureFullFlow(state);
        if (executeDiagnosticFlow) {
            _runFullFlow(state);
            _runRequiredReplays(state);
            _writeEvmEvidence(outputRoot, state);
        } else {
            _writeLiveBlueprint(outputRoot, state);
        }

        vm.selectFork(state.homeFork);
        _writeHomeManifest(
            outputRoot,
            state.home,
            state.canonical,
            state.exposure,
            state.hub,
            state.mintRouteHash,
            state.exposureHash,
            state.sampleMessageId,
            state.hubCodeHash
        );
        vm.selectFork(state.satelliteFork);
        _writeSatelliteManifest(
            outputRoot,
            state.satellite,
            state.collateral,
            state.wrapped,
            state.mintRouteHash,
            state.wrappedCodeHash
        );
    }

    function _writeLiveBlueprint(string calldata outputRoot, RunState memory state) private {
        vm.selectFork(state.homeFork);
        BridgeExposurePolicy.ExposureConfig memory exposureConfig =
            state.exposure.policy(state.exposureHash);
        string memory key = "phase8_live_blueprint";
        vm.serializeUint(key, "schema_version", 1);
        vm.serializeString(key, "artifact_type", "PHASE8_LIVE_DEPLOYMENT_BLUEPRINT");
        vm.serializeString(key, "environment", "local");
        vm.serializeBool(key, "contains_real_value", false);
        vm.serializeBytes32(key, "protocol_id", PROTOCOL_ID);
        vm.serializeUint(key, "activated_at", state.activatedAt);
        vm.serializeAddress(key, "local_admin", LOCAL_ADMIN);
        vm.serializeAddress(key, "local_governance", LOCAL_GOVERNANCE);
        vm.serializeBytes32(key, "loan_id", LOAN_ID);
        vm.serializeBytes32(key, "funding_lock_id", LOCK_ID);
        vm.serializeBytes32(key, "collateral_id", COLLATERAL_ID);
        vm.serializeBytes32(key, "loan_policy_hash", POLICY_HASH);
        vm.serializeUint(key, "principal_units", PRINCIPAL);
        vm.serializeUint(key, "collateral_units", COLLATERAL_AMOUNT);
        vm.serializeBytes32(key, "exposure_policy_hash", state.exposureHash);
        vm.serializeUint(
            key, "circulating_supply_reference_units", exposureConfig.circulatingSupplyReference
        );
        vm.serializeBytes32(
            key, "circulating_supply_evidence_hash", exposureConfig.circulatingSupplyEvidenceHash
        );
        vm.serializeUint(key, "route_absolute_cap_units", exposureConfig.routeAbsoluteCap);
        vm.serializeUint(key, "chain_absolute_cap_units", exposureConfig.chainAbsoluteCap);
        vm.serializeUint(key, "adapter_absolute_cap_units", exposureConfig.adapterAbsoluteCap);
        vm.serializeUint(key, "aggregate_absolute_cap_units", exposureConfig.aggregateAbsoluteCap);
        vm.serializeUint(
            key, "route_percentage_ceiling_bps", exposureConfig.routePercentageCeilingBps
        );
        vm.serializeUint(
            key, "aggregate_percentage_ceiling_bps", exposureConfig.aggregatePercentageCeilingBps
        );
        vm.serializeUint(key, "activation_delay", exposureConfig.activationDelay);
        vm.serializeUint(key, "active_from", exposureConfig.activeFrom);
        vm.serializeUint(key, "exposure_policy_version", 1);

        vm.serializeAddress(key, "home_role_manager", address(state.home.roles));
        vm.serializeAddress(key, "home_chain_registry", address(state.home.chains));
        vm.serializeAddress(key, "home_emergency_controller", address(state.home.emergency));
        vm.serializeAddress(key, "home_route_registry", address(state.home.routes));
        vm.serializeAddress(key, "home_finality_verifier", address(state.home.verifier));
        vm.serializeAddress(key, "home_coordinator", address(state.home.coordinator));
        vm.serializeAddress(key, "home_recovery_controller", address(state.home.recovery));
        vm.serializeAddress(key, "canonical_token", address(state.canonical));
        vm.serializeAddress(key, "bridge_exposure_policy", address(state.exposure));
        vm.serializeAddress(key, "bridge_hub", address(state.hub));
        vm.serializeAddress(key, "loan_registry", address(state.loanRegistry));
        vm.serializeAddress(key, "loan_account_deployer", address(state.accountDeployer));
        vm.serializeAddress(key, "loan_factory", address(state.loanFactory));
        vm.serializeAddress(key, "loan_policy", address(state.loanPolicy));
        vm.serializeBytes32(key, "home_signer_set_hash", state.home.signerSetHash);

        vm.serializeAddress(key, "satellite_role_manager", address(state.satellite.roles));
        vm.serializeAddress(key, "satellite_chain_registry", address(state.satellite.chains));
        vm.serializeAddress(
            key, "satellite_emergency_controller", address(state.satellite.emergency)
        );
        vm.serializeAddress(key, "satellite_route_registry", address(state.satellite.routes));
        vm.serializeAddress(key, "satellite_finality_verifier", address(state.satellite.verifier));
        vm.serializeAddress(key, "satellite_coordinator", address(state.satellite.coordinator));
        vm.serializeAddress(key, "satellite_recovery_controller", address(state.satellite.recovery));
        vm.serializeAddress(key, "collateral_token", address(state.collateral));
        vm.serializeAddress(key, "wrapped_uft", address(state.wrapped));
        vm.serializeAddress(key, "satellite_loan_component", address(state.satelliteComponent));
        vm.serializeAddress(key, "satellite_collateral_vault", address(state.collateralVault));
        vm.serializeAddress(key, "satellite_settlement_vault", address(state.settlementVault));
        vm.serializeBytes32(key, "satellite_signer_set_hash", state.satellite.signerSetHash);

        vm.serializeBytes32(key, "mint_route_hash", state.mintRouteHash);
        vm.serializeBytes32(key, "report_route_hash", state.reportRouteHash);
        vm.serializeBytes32(key, "repayment_route_hash", state.repaymentRouteHash);
        vm.serializeBytes32(
            key, "alternate_repayment_route_hash", state.alternateRepaymentRouteHash
        );
        vm.serializeBytes32(key, "bridge_exit_route_hash", state.bridgeExitRouteHash);
        vm.serializeBytes32(key, "disbursement_route_hash", state.disbursementRouteHash);
        string memory json = vm.serializeBytes32(
            key, "collateral_release_route_hash", state.collateralReleaseRouteHash
        );
        vm.writeJson(json, string.concat(outputRoot, "/phase8-live-blueprint.json"));
    }

    function _deployDomain(uint256 chainId, uint64 activatedAt)
        private
        returns (Domain memory domain)
    {
        require(block.chainid == chainId, "wrong fork");
        domain.chainId = chainId;
        domain.activationBlock = uint64(block.number);
        vm.startBroadcast();
        domain.roles = new RoleManager(LOCAL_ADMIN, LOCAL_GOVERNANCE);
        domain.chains = new ChainRegistry(domain.roles, chainId);
        domain.emergency = new EmergencyController(domain.roles);
        domain.routes = new RouteRegistry(domain.roles, domain.chains, domain.emergency);
        domain.verifier = new SyntheticFinalityVerifier(domain.roles, domain.chains);
        domain.coordinator = new CrossChainCoordinator(
            domain.roles, PROTOCOL_ID, chainId, domain.routes, domain.verifier
        );
        domain.coordinatorCodeHash = address(domain.coordinator).codehash;
        domain.verifierCodeHash = address(domain.verifier).codehash;
        domain.signerSetHash = domain.verifier
            .registerSignerSet(
                _observerAuthorityHash(chainId),
                1,
                _recoverySigners(),
                activatedAt,
                activatedAt + 30 days
            );
        domain.roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, LOCAL_GOVERNANCE, type(uint64).max);
        vm.stopBroadcast();
    }

    function _mintRoute(
        Domain memory home,
        Domain memory satellite,
        address hub,
        address wrapped,
        bytes32 hubCodeHash,
        bytes32 wrappedCodeHash,
        uint64 activatedAt
    ) private pure returns (RouteRegistry.RouteConfig memory) {
        return RouteRegistry.RouteConfig({
            sourceChainVersion: 1,
            destinationChainVersion: 1,
            sourceChainId: HOME_CHAIN_ID,
            sourceCoordinator: address(home.coordinator),
            sourceComponent: hub,
            sourceComponentCodeHash: hubCodeHash,
            destinationChainId: SATELLITE_CHAIN_ID,
            destinationCoordinator: address(satellite.coordinator),
            destinationComponent: wrapped,
            destinationComponentCodeHash: wrappedCodeHash,
            actionFamily: keccak256("LOCAL_CANONICAL_LOCK_MINT"),
            allowedActionsBitmap: uint32(1) << 1,
            adapterId: keccak256("LOCAL_ADAPTER"),
            adapterCodeHash: keccak256("LOCAL_ADAPTER_CODE"),
            adapterSetPolicyHash: _adapterSetPolicyHash(),
            sourceFinalityPolicyHash: bytes32(0),
            destinationFinalityPolicyHash: bytes32(0),
            sourceSignerSetHash: home.signerSetHash,
            destinationSignerSetHash: satellite.signerSetHash,
            absoluteCap: 1_000 ether,
            chainCap: 1_000 ether,
            adapterCap: 1_000 ether,
            activatedAt: activatedAt
        });
    }

    function _configureFullFlow(RunState memory state) private {
        state.reportRouteHash = _registerRouteBoth(
            state,
            _route(
                state,
                false,
                address(state.satelliteComponent),
                address(state.loanFactory),
                state.satelliteComponentCodeHash,
                state.loanFactoryCodeHash,
                (uint32(1) << 2) | (uint32(1) << 5) | (uint32(1) << 7) | (uint32(1) << 10)
                    | (uint32(1) << 14),
                keccak256("LOAN_REPORT")
            )
        );
        state.repaymentRouteHash = _registerRouteBoth(
            state,
            _route(
                state,
                false,
                address(state.wrapped),
                address(state.loanFactory),
                state.wrappedCodeHash,
                state.loanFactoryCodeHash,
                uint32(1) << 8,
                keccak256("LOAN_REPAYMENT")
            )
        );
        state.alternateRepaymentRouteHash = _registerRouteBoth(
            state,
            _route(
                state,
                false,
                address(state.wrapped),
                address(state.loanFactory),
                state.wrappedCodeHash,
                state.loanFactoryCodeHash,
                uint32(1) << 8,
                keccak256("ALTERNATE_LOAN_REPAYMENT")
            )
        );
        state.bridgeExitRouteHash = _registerRouteBoth(
            state,
            _route(
                state,
                false,
                address(state.wrapped),
                address(state.hub),
                state.wrappedCodeHash,
                state.hubCodeHash,
                (uint32(1) << 3) | (uint32(1) << 15),
                keccak256("BRIDGE_EXIT")
            )
        );
        state.disbursementRouteHash = _registerRouteBoth(
            state,
            _route(
                state,
                true,
                address(state.loanFactory),
                address(state.settlementVault),
                state.loanFactoryCodeHash,
                state.settlementVaultCodeHash,
                (uint32(1) << 6) | (uint32(1) << 12),
                keccak256("LOAN_DISBURSEMENT")
            )
        );
        state.collateralReleaseRouteHash = _registerRouteBoth(
            state,
            _route(
                state,
                true,
                address(state.loanFactory),
                address(state.collateralVault),
                state.loanFactoryCodeHash,
                state.collateralVaultCodeHash,
                uint32(1) << 9,
                keccak256("COLLATERAL_RELEASE")
            )
        );

        vm.selectFork(state.satelliteFork);
        vm.startBroadcast();
        state.satelliteComponent
            .configureInfrastructure(
                address(state.loanFactory),
                address(state.wrapped),
                address(state.collateral),
                address(state.collateralVault),
                address(state.settlementVault),
                state.reportRouteHash,
                state.mintRouteHash,
                state.repaymentRouteHash
            );
        state.wrapped.configureLoanSettlementVault(address(state.settlementVault));
        vm.stopBroadcast();

        vm.selectFork(state.homeFork);
        vm.startBroadcast();
        state.loanPolicy = new CrossChainLoanPolicy(
            ICrossChainLoanPolicy.Configuration({
                protocolId: PROTOCOL_ID,
                homeChainId: HOME_CHAIN_ID,
                satelliteChainId: SATELLITE_CHAIN_ID,
                homeCoordinator: address(state.home.coordinator),
                satelliteCoordinator: address(state.satellite.coordinator),
                homeLoanRouter: address(state.loanFactory),
                homeBridgeHub: address(state.hub),
                wrappedUFT: address(state.wrapped),
                satelliteComponent: address(state.satelliteComponent),
                satelliteCollateralVault: address(state.collateralVault),
                satelliteSettlementVault: address(state.settlementVault),
                canonicalUFT: address(state.canonical),
                collateralToken: address(state.collateral),
                mintRouteHash: state.mintRouteHash,
                reportRouteHash: state.reportRouteHash,
                repaymentRouteHash: state.repaymentRouteHash,
                disbursementRouteHash: state.disbursementRouteHash,
                collateralReleaseRouteHash: state.collateralReleaseRouteHash,
                policyHash: POLICY_HASH
            })
        );
        state.loanFactory.bindPolicy(state.loanPolicy);
        vm.stopBroadcast();
    }

    function _route(
        RunState memory state,
        bool sourceIsHome,
        address sourceComponent,
        address destinationComponent,
        bytes32 sourceComponentCodeHash,
        bytes32 destinationComponentCodeHash,
        uint32 allowedActions,
        bytes32 actionFamily
    ) private pure returns (RouteRegistry.RouteConfig memory) {
        Domain memory source = sourceIsHome ? state.home : state.satellite;
        Domain memory destination = sourceIsHome ? state.satellite : state.home;
        bytes32 adapterId = keccak256(abi.encode("LOCAL_ADAPTER", actionFamily));
        return RouteRegistry.RouteConfig({
            sourceChainVersion: 1,
            destinationChainVersion: 1,
            sourceChainId: source.chainId,
            sourceCoordinator: address(source.coordinator),
            sourceComponent: sourceComponent,
            sourceComponentCodeHash: sourceComponentCodeHash,
            destinationChainId: destination.chainId,
            destinationCoordinator: address(destination.coordinator),
            destinationComponent: destinationComponent,
            destinationComponentCodeHash: destinationComponentCodeHash,
            actionFamily: actionFamily,
            allowedActionsBitmap: allowedActions,
            adapterId: adapterId,
            adapterCodeHash: keccak256(abi.encode("LOCAL_ADAPTER_CODE", adapterId)),
            adapterSetPolicyHash: _adapterSetPolicyHash(),
            sourceFinalityPolicyHash: bytes32(0),
            destinationFinalityPolicyHash: bytes32(0),
            sourceSignerSetHash: source.signerSetHash,
            destinationSignerSetHash: destination.signerSetHash,
            absoluteCap: 1_000 ether,
            chainCap: 1_000 ether,
            adapterCap: 1_000 ether,
            activatedAt: state.activatedAt
        });
    }

    function _registerRouteBoth(RunState memory state, RouteRegistry.RouteConfig memory route)
        private
        returns (bytes32 routeHash)
    {
        route = _registerFinalityPolicies(state, route);
        vm.selectFork(state.homeFork);
        vm.startBroadcast();
        routeHash = state.home.routes.registerRoute(route);
        vm.stopBroadcast();
        vm.selectFork(state.satelliteFork);
        vm.startBroadcast();
        require(state.satellite.routes.registerRoute(route) == routeHash, "route drift");
        vm.stopBroadcast();
    }

    function _registerFinalityPolicies(
        RunState memory state,
        RouteRegistry.RouteConfig memory route
    ) private returns (RouteRegistry.RouteConfig memory) {
        SyntheticFinalityVerifier.FinalityPolicyConfig memory
            sourcePolicy = _finalityPolicy(state, route, false);
        SyntheticFinalityVerifier.FinalityPolicyConfig memory destinationPolicy =
            _finalityPolicy(state, route, true);

        vm.selectFork(state.homeFork);
        vm.startBroadcast();
        route.sourceFinalityPolicyHash = state.home.verifier.registerFinalityPolicy(sourcePolicy);
        route.destinationFinalityPolicyHash =
            state.home.verifier.registerFinalityPolicy(destinationPolicy);
        vm.stopBroadcast();

        vm.selectFork(state.satelliteFork);
        vm.startBroadcast();
        require(
            state.satellite.verifier.registerFinalityPolicy(sourcePolicy)
                == route.sourceFinalityPolicyHash,
            "source finality policy drift"
        );
        require(
            state.satellite.verifier.registerFinalityPolicy(destinationPolicy)
                == route.destinationFinalityPolicyHash,
            "destination finality policy drift"
        );
        vm.stopBroadcast();
        return route;
    }

    function _finalityPolicy(
        RunState memory state,
        RouteRegistry.RouteConfig memory route,
        bool destinationEvidence
    ) private pure returns (SyntheticFinalityVerifier.FinalityPolicyConfig memory) {
        uint256 evidenceChainId =
            destinationEvidence ? route.destinationChainId : route.sourceChainId;
        return SyntheticFinalityVerifier.FinalityPolicyConfig({
            destinationEvidence: destinationEvidence,
            sourceChainId: route.sourceChainId,
            sourceCoordinator: route.sourceCoordinator,
            sourceComponent: route.sourceComponent,
            destinationChainId: route.destinationChainId,
            destinationCoordinator: route.destinationCoordinator,
            destinationComponent: route.destinationComponent,
            evidenceChainVersion: destinationEvidence
                ? route.destinationChainVersion
                : route.sourceChainVersion,
            evidenceChainConfigurationHash: _chainConfigurationHash(
                evidenceChainId == HOME_CHAIN_ID ? state.home : state.satellite
            ),
            actionFamily: route.actionFamily,
            allowedActionsBitmap: route.allowedActionsBitmap,
            requiredDepth: 12,
            observerAuthorityHash: _observerAuthorityHash(evidenceChainId),
            signerSetHash: destinationEvidence
                ? route.destinationSignerSetHash
                : route.sourceSignerSetHash,
            signerSetVersion: 1
        });
    }

    function _registerExposure(
        BridgeExposurePolicy exposure,
        Phase8LocalSyntheticToken canonical,
        uint64 activatedAt
    ) private returns (bytes32) {
        return exposure.registerPolicy(
            BridgeExposurePolicy.ExposureConfig({
                circulatingSupplyReference: canonical.MAX_SUPPLY(),
                circulatingSupplyEvidenceHash: keccak256("LOCAL_SYNTHETIC_SUPPLY"),
                routeAbsoluteCap: 1_000 ether,
                chainAbsoluteCap: 1_000 ether,
                adapterAbsoluteCap: 1_000 ether,
                aggregateAbsoluteCap: 1_000 ether,
                routePercentageCeilingBps: 500,
                aggregatePercentageCeilingBps: 1_500,
                activationDelay: 0,
                activeFrom: activatedAt
            })
        );
    }

    function _runFullFlow(RunState memory state) private {
        (address accountAddress, bytes32 mintMessageId, bytes32 collateralReportMessageId) =
            _originateAndLock(state);
        state.loanAccount = CrossChainLoanAccount(accountAddress);
        state.sampleMessageId = mintMessageId;

        _executeAndAcknowledge(
            state,
            true,
            mintMessageId,
            abi.encode(
                CrossChainTypes.CanonicalUftLockPayload({
                    lockId: LOCK_ID,
                    loanId: LOAN_ID,
                    canonicalToken: address(state.canonical),
                    homeBridgeHub: address(state.hub),
                    wrappedToken: address(state.wrapped),
                    destinationRecipient: address(state.settlementVault),
                    amount: PRINCIPAL
                })
            )
        );
        vm.selectFork(state.satelliteFork);
        bytes32 mintReportMessageId = state.satelliteComponent
            .reportMessage(LOAN_ID, CrossChainTypes.ACTION_SATELLITE_MINT_CONFIRMED);

        _executeAndAcknowledge(
            state,
            false,
            collateralReportMessageId,
            abi.encode(
                CrossChainTypes.SatelliteCollateralLockedPayload({
                    loanId: LOAN_ID,
                    collateralId: COLLATERAL_ID,
                    homeLoanAccount: accountAddress,
                    borrower: LOCAL_ADMIN,
                    lender: LOCAL_GOVERNANCE,
                    collateralToken: address(state.collateral),
                    amount: COLLATERAL_AMOUNT,
                    policyHash: POLICY_HASH
                })
            )
        );
        _executeAndAcknowledge(
            state,
            false,
            mintReportMessageId,
            abi.encode(
                CrossChainTypes.WrappedUftMintedPayload({
                    loanId: LOAN_ID,
                    lockId: LOCK_ID,
                    homeLoanAccount: accountAddress,
                    borrower: LOCAL_ADMIN,
                    lender: LOCAL_GOVERNANCE,
                    wrappedToken: address(state.wrapped),
                    amount: PRINCIPAL,
                    policyHash: POLICY_HASH
                })
            )
        );

        _settleDisbursement(state, accountAddress);
        _repayReleaseAndClose(state, accountAddress);
    }

    function _originateAndLock(RunState memory state)
        private
        returns (address accountAddress, bytes32 mintMessageId, bytes32 collateralReportMessageId)
    {
        vm.selectFork(state.homeFork);
        vm.startBroadcast(LOCAL_GOVERNANCE);
        state.canonical.approve(address(state.hub), PRINCIPAL);
        (accountAddress, mintMessageId) = state.loanFactory
            .createLoan(
                CrossChainTypes.CrossChainLoanTerms({
                    loanId: LOAN_ID,
                    agreementHash: keccak256("LOCAL_FULL_FLOW_AGREEMENT"),
                    fundingLockId: LOCK_ID,
                    collateralId: COLLATERAL_ID,
                    borrower: LOCAL_ADMIN,
                    lender: LOCAL_GOVERNANCE,
                    principalAmount: PRINCIPAL,
                    collateralAmount: COLLATERAL_AMOUNT,
                    policyHash: POLICY_HASH
                }),
                uint64(block.timestamp + 2 days)
            );
        vm.stopBroadcast();
        CrossChainTypes.SatelliteLoanProvisioning memory provisioning =
            state.loanFactory.satelliteProvisioning(LOAN_ID);

        vm.selectFork(state.satelliteFork);
        vm.startBroadcast(LOCAL_GOVERNANCE);
        state.satelliteComponent.provisionLoan(provisioning);
        state.collateral.transfer(LOCAL_ADMIN, COLLATERAL_AMOUNT);
        vm.stopBroadcast();
        vm.startBroadcast(LOCAL_ADMIN);
        state.collateral.approve(address(state.collateralVault), COLLATERAL_AMOUNT);
        collateralReportMessageId = state.collateralVault.lockCollateral(LOAN_ID);
        vm.stopBroadcast();
    }

    function _settleDisbursement(RunState memory state, address accountAddress) private {
        vm.selectFork(state.homeFork);
        bytes32 disbursementMessageId =
            CrossChainLoanAccount(accountAddress).disbursementMessageId();
        require(disbursementMessageId != bytes32(0), "missing disbursement");
        _executeAndAcknowledge(
            state,
            true,
            disbursementMessageId,
            abi.encode(
                CrossChainTypes.HomeDisbursementAuthorizedPayload({
                    loanId: LOAN_ID,
                    fundingLockId: LOCK_ID,
                    homeLoanAccount: accountAddress,
                    borrower: LOCAL_ADMIN,
                    lender: LOCAL_GOVERNANCE,
                    wrappedToken: address(state.wrapped),
                    amount: PRINCIPAL,
                    policyHash: POLICY_HASH
                })
            )
        );
        vm.selectFork(state.satelliteFork);
        state.borrowerReceivedPrincipalUnits = state.wrapped.balanceOf(LOCAL_ADMIN);
        bytes32 settledReportMessageId = state.satelliteComponent
            .reportMessage(LOAN_ID, CrossChainTypes.ACTION_SATELLITE_DISBURSEMENT_SETTLED);
        _executeAndAcknowledge(
            state,
            false,
            settledReportMessageId,
            abi.encode(
                CrossChainTypes.SatelliteDisbursementSettledPayload({
                    loanId: LOAN_ID,
                    fundingLockId: LOCK_ID,
                    homeLoanAccount: accountAddress,
                    borrower: LOCAL_ADMIN,
                    lender: LOCAL_GOVERNANCE,
                    wrappedToken: address(state.wrapped),
                    amount: PRINCIPAL,
                    policyHash: POLICY_HASH
                })
            )
        );
        vm.selectFork(state.homeFork);
        require(
            CrossChainLoanAccount(accountAddress).state()
                == CrossChainTypes.CrossChainLoanState.ACTIVE,
            "loan not active"
        );
    }

    function _repayReleaseAndClose(RunState memory state, address accountAddress) private {
        bytes32 burnId = keccak256("LOCAL_FULL_FLOW_REPAYMENT_BURN");
        bytes32 paymentId = keccak256("LOCAL_FULL_FLOW_PAYMENT");
        vm.selectFork(state.satelliteFork);
        vm.startBroadcast(LOCAL_ADMIN);
        bytes32 repaymentMessageId = state.wrapped
            .burnForLoanRepayment(
                burnId,
                LOAN_ID,
                paymentId,
                state.repaymentRouteHash,
                PRINCIPAL,
                uint64(block.timestamp + 2 days)
            );
        vm.stopBroadcast();
        _executeAndAcknowledge(
            state,
            false,
            repaymentMessageId,
            abi.encode(
                CrossChainTypes.SatelliteRepaymentBurnedPayload({
                    burnId: burnId,
                    loanId: LOAN_ID,
                    paymentId: paymentId,
                    backingRoutePolicyHash: state.mintRouteHash,
                    canonicalToken: address(state.canonical),
                    homeBridgeHub: address(state.hub),
                    wrappedToken: address(state.wrapped),
                    lender: LOCAL_GOVERNANCE,
                    amount: PRINCIPAL
                })
            )
        );

        vm.selectFork(state.homeFork);
        state.lenderReceivedRepaymentUnits = state.canonical.balanceOf(LOCAL_GOVERNANCE)
            - (state.canonical.MAX_SUPPLY() - PRINCIPAL);
        bytes32 releaseMessageId =
            CrossChainLoanAccount(accountAddress).collateralReleaseMessageId();
        require(releaseMessageId != bytes32(0), "missing collateral release");
        _executeAndAcknowledge(
            state,
            true,
            releaseMessageId,
            abi.encode(
                CrossChainTypes.HomeCollateralReleaseAuthorizedPayload({
                    loanId: LOAN_ID,
                    collateralId: COLLATERAL_ID,
                    homeLoanAccount: accountAddress,
                    borrower: LOCAL_ADMIN,
                    lender: LOCAL_GOVERNANCE,
                    collateralToken: address(state.collateral),
                    amount: COLLATERAL_AMOUNT,
                    policyHash: POLICY_HASH
                })
            )
        );
        vm.selectFork(state.satelliteFork);
        bytes32 releaseReportMessageId = state.satelliteComponent
            .reportMessage(LOAN_ID, CrossChainTypes.ACTION_SATELLITE_COLLATERAL_RELEASED);
        _executeAndAcknowledge(
            state,
            false,
            releaseReportMessageId,
            abi.encode(
                CrossChainTypes.SatelliteCollateralReleasedPayload({
                    loanId: LOAN_ID,
                    collateralId: COLLATERAL_ID,
                    homeLoanAccount: accountAddress,
                    borrower: LOCAL_ADMIN,
                    lender: LOCAL_GOVERNANCE,
                    collateralToken: address(state.collateral),
                    amount: COLLATERAL_AMOUNT,
                    policyHash: POLICY_HASH
                })
            )
        );

        vm.selectFork(state.homeFork);
        require(
            CrossChainLoanAccount(accountAddress).state()
                == CrossChainTypes.CrossChainLoanState.CLOSED,
            "loan not closed"
        );
        require(
            CrossChainLoanAccount(accountAddress).outstandingPrincipal() == 0, "principal remains"
        );
        require(state.hub.loanBacking(LOAN_ID) == 0, "loan backing remains");
        require(state.hub.totalBridgeBacking() == 0, "bridge backing remains");
        require(state.loanRegistry.isTerminal(LOAN_ID), "registry not terminal");
        require(
            state.borrowerReceivedPrincipalUnits == PRINCIPAL, "borrower principal receipt mismatch"
        );
        require(
            state.lenderReceivedRepaymentUnits == PRINCIPAL, "lender repayment receipt mismatch"
        );
        vm.selectFork(state.satelliteFork);
        require(state.wrapped.totalSupply() == 0, "wrapped supply remains");
        require(
            state.collateral.balanceOf(LOCAL_ADMIN) == COLLATERAL_AMOUNT, "collateral not released"
        );
    }

    function _executeAndAcknowledge(
        RunState memory state,
        bool sourceIsHome,
        bytes32 messageId,
        bytes memory payload
    ) private returns (bytes32 resultHash) {
        Domain memory source = sourceIsHome ? state.home : state.satellite;
        Domain memory destination = sourceIsHome ? state.satellite : state.home;
        uint256 sourceFork = sourceIsHome ? state.homeFork : state.satelliteFork;
        uint256 destinationFork = sourceIsHome ? state.satelliteFork : state.homeFork;

        vm.selectFork(sourceFork);
        CrossChainTypes.MessageEnvelope memory envelope =
            source.coordinator.messageEnvelope(messageId);
        CrossChainTypes.SourceEventProof memory sourceProof = _proof(
            envelope,
            source.coordinator.sourceMessageEventHash(envelope),
            envelope.sourceFinalityPolicyHash,
            source.chainId
        );
        CrossChainTypes.FinalityCertificate memory sourceCertificate = _certificate(
            destination.verifier, destination.chainId, envelope, sourceProof, source.signerSetHash
        );
        vm.selectFork(destinationFork);
        vm.startBroadcast(LOCAL_GOVERNANCE);
        resultHash = destination.coordinator
            .executeMessage(envelope, payload, sourceProof, sourceCertificate);
        vm.stopBroadcast();

        CrossChainTypes.SourceEventProof memory acknowledgementProof = _proof(
            envelope,
            destination.coordinator.acknowledgementEventHash(envelope, resultHash),
            envelope.destinationFinalityPolicyHash,
            destination.chainId
        );
        CrossChainTypes.FinalityCertificate memory acknowledgementCertificate = _certificate(
            source.verifier,
            source.chainId,
            envelope,
            acknowledgementProof,
            destination.signerSetHash
        );
        vm.selectFork(sourceFork);
        vm.startBroadcast(LOCAL_GOVERNANCE);
        source.coordinator
            .recordAcknowledgement(
                envelope, resultHash, acknowledgementProof, acknowledgementCertificate
            );
        vm.stopBroadcast();
        require(
            source.coordinator.messageState(messageId) == CrossChainTypes.MessageState.ACKNOWLEDGED,
            "message not acknowledged"
        );
        require(state.flowMessageCount < state.flowMessages.length, "too many flow messages");
        state.flowMessages[state.flowMessageCount] = MessageEvidence({
            envelope: envelope,
            payload: payload,
            sourceProof: sourceProof,
            sourceCertificate: sourceCertificate,
            destinationResultHash: resultHash,
            acknowledgementProof: acknowledgementProof,
            acknowledgementCertificate: acknowledgementCertificate
        });
        ++state.flowMessageCount;
    }

    function _runRequiredReplays(RunState memory state) private {
        require(state.flowMessageCount == 8, "incomplete flow");
        state.mintReplayResultHash = _replayMessage(state, 0, true);
        state.repaymentReplayResultHash = _replayMessage(state, 5, false);
        state.collateralReleaseReplayResultHash = _replayMessage(state, 6, true);
    }

    function _replayMessage(RunState memory state, uint8 index, bool sourceIsHome)
        private
        returns (bytes32 replayResultHash)
    {
        MessageEvidence memory evidence = state.flowMessages[index];
        Domain memory destination = sourceIsHome ? state.satellite : state.home;
        vm.selectFork(sourceIsHome ? state.satelliteFork : state.homeFork);
        vm.startBroadcast(LOCAL_GOVERNANCE);
        replayResultHash = destination.coordinator
            .executeMessage(
                evidence.envelope,
                evidence.payload,
                evidence.sourceProof,
                evidence.sourceCertificate
            );
        vm.stopBroadcast();
        require(replayResultHash == evidence.destinationResultHash, "replay result drift");
    }

    function _proof(
        CrossChainTypes.MessageEnvelope memory envelope,
        bytes32 eventHash,
        bytes32 finalityPolicyHash,
        uint256 evidenceChainId
    ) private returns (CrossChainTypes.SourceEventProof memory proof) {
        proof = CrossChainTypes.SourceEventProof({
                sourceBlockHash: keccak256(
                    abi.encode("LOCAL_BLOCK", evidenceChainId, envelope.messageId)
                ),
                sourceBlockNumber: 100,
                sourceBlockTimestamp: envelope.createdAt,
                transactionHash: keccak256(
                    abi.encode("LOCAL_TX", evidenceChainId, envelope.messageId)
                ),
                transactionIndex: 1,
                receiptRoot: keccak256(
                    abi.encode("LOCAL_ROOT", evidenceChainId, envelope.messageId)
                ),
                receiptProofHash: keccak256(
                    abi.encode("LOCAL_PROOF", evidenceChainId, envelope.messageId)
                ),
                logIndex: 1,
                eventHash: eventHash,
                finalityHeadHash: keccak256(
                    abi.encode("LOCAL_FINALITY_HEAD", evidenceChainId, envelope.messageId)
                ),
                finalityHeadNumber: 112,
                requiredDepth: 12,
                headerAuthorityHash: _observerAuthorityHash(evidenceChainId),
                observerSignedHeaderCommitment: bytes32(0),
                observerSignature: bytes(""),
                finalityPolicyHash: finalityPolicyHash
            });
        proof.observerSignedHeaderCommitment = CrossChainTypes.observerHeaderCommitment(proof);
        proof.observerSignature =
            _signObserverCommitment(evidenceChainId, proof.observerSignedHeaderCommitment);
    }

    function _signObserverCommitment(uint256 evidenceChainId, bytes32 commitment)
        private
        returns (bytes memory signature)
    {
        string[] memory command = new string[](7);
        command[0] = "uv";
        command[1] = "run";
        command[2] = "python";
        command[3] = "../tools/sign_phase8_observer.py";
        command[4] = "sign";
        command[5] = evidenceChainId == HOME_CHAIN_ID ? "home" : "satellite";
        command[6] = vm.toString(commitment);
        signature = vm.ffi(command);
        require(signature.length == 64, "invalid observer signature");
    }

    function _certificate(
        SyntheticFinalityVerifier verifier,
        uint256 verifierChainId,
        CrossChainTypes.MessageEnvelope memory envelope,
        CrossChainTypes.SourceEventProof memory proof,
        bytes32 signerSetHash
    ) private returns (CrossChainTypes.FinalityCertificate memory certificate) {
        bytes32 proofHash = CrossChainTypes.sourceProofHash(proof);
        bytes32 digest = CrossChainTypes.finalityCertificateDigest(
            address(verifier), verifierChainId, envelope.messageId, proofHash, signerSetHash, 1
        );
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signature(SIGNER_ONE_KEY, digest);
        signatures[1] = _signature(SIGNER_TWO_KEY, digest);
        certificate = CrossChainTypes.FinalityCertificate({
            messageId: envelope.messageId,
            sourceProofHash: proofHash,
            signerSetHash: signerSetHash,
            signerSetVersion: 1,
            signatures: signatures
        });
    }

    function _signature(uint256 key, bytes32 digest) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _registerChains(Domain memory local, Domain memory remote, uint64 activatedAt)
        private
    {
        vm.startBroadcast();
        local.chains
            .registerChain(
                local.chainId,
                address(local.coordinator),
                address(local.verifier),
                local.coordinatorCodeHash,
                local.verifierCodeHash,
                _chainConfigurationHash(local),
                activatedAt
            );
        local.chains
            .registerChain(
                remote.chainId,
                address(remote.coordinator),
                address(remote.verifier),
                remote.coordinatorCodeHash,
                remote.verifierCodeHash,
                _chainConfigurationHash(remote),
                activatedAt
            );
        vm.stopBroadcast();
    }

    function _chainConfigurationHash(Domain memory domain) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_LOCAL_CHAIN_CONFIGURATION_V1",
                domain.chainId,
                uint32(1),
                address(domain.coordinator),
                address(domain.verifier),
                _observerAuthorityHash(domain.chainId),
                domain.activationBlock
            )
        );
    }

    function _observerPublicKey(uint256 chainId) private pure returns (bytes32) {
        require(
            chainId == HOME_CHAIN_ID || chainId == SATELLITE_CHAIN_ID, "unknown observer domain"
        );
        return chainId == HOME_CHAIN_ID ? HOME_OBSERVER_PUBLIC_KEY : SATELLITE_OBSERVER_PUBLIC_KEY;
    }

    function _observerAuthorityHash(uint256 chainId) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_observerPublicKey(chainId)));
    }

    function _adapterSetPolicyHash() private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_LOCAL_ADAPTER_SET_POLICY_V1",
                uint64(2),
                keccak256(bytes("mock-bridge-provider-a")),
                keccak256(bytes("TRANSPORT_ONLY")),
                keccak256(bytes("mock-bridge-provider-b")),
                keccak256(bytes("TRANSPORT_ONLY"))
            )
        );
    }

    function _registerRemoteSignerSets(RunState memory state) private {
        vm.selectFork(state.homeFork);
        vm.startBroadcast();
        require(
            state.home.verifier
                .registerSignerSet(
                    _observerAuthorityHash(SATELLITE_CHAIN_ID),
                    1,
                    _recoverySigners(),
                    state.activatedAt,
                    state.activatedAt + 30 days
                ) == state.satellite.signerSetHash,
            "satellite signer set drift"
        );
        vm.stopBroadcast();

        vm.selectFork(state.satelliteFork);
        vm.startBroadcast();
        require(
            state.satellite.verifier
                .registerSignerSet(
                    _observerAuthorityHash(HOME_CHAIN_ID),
                    1,
                    _recoverySigners(),
                    state.activatedAt,
                    state.activatedAt + 30 days
                ) == state.home.signerSetHash,
            "home signer set drift"
        );
        vm.stopBroadcast();
    }

    function _recoverySigners() private returns (address[3] memory signers) {
        signers = [vm.addr(SIGNER_TWO_KEY), vm.addr(SIGNER_THREE_KEY), vm.addr(SIGNER_ONE_KEY)];
    }

    function _writeEvmEvidence(string calldata outputRoot, RunState memory state) private {
        require(state.flowMessageCount == 8, "flow evidence incomplete");
        string memory path = string.concat(outputRoot, "/phase8-evm-evidence.pending.json");
        _writeEvmHeader(path, state);
        _writeHomeEvmEvidence(path, state);
        _serializeRoute(path, "mint", state.home, state.mintRouteHash);
        _serializeRoute(path, "report", state.home, state.reportRouteHash);
        _serializeRoute(path, "repayment", state.home, state.repaymentRouteHash);
        _serializeRoute(path, "alternate_repayment", state.home, state.alternateRepaymentRouteHash);
        _serializeRoute(path, "bridge_exit", state.home, state.bridgeExitRouteHash);
        _serializeRoute(path, "disbursement", state.home, state.disbursementRouteHash);
        _serializeRoute(path, "collateral_release", state.home, state.collateralReleaseRouteHash);
        _serializeMessage(path, "flow_message_01", state.flowMessages[0]);
        _serializeMessage(path, "flow_message_02", state.flowMessages[1]);
        _serializeMessage(path, "flow_message_03", state.flowMessages[2]);
        _serializeMessage(path, "flow_message_04", state.flowMessages[3]);
        _serializeMessage(path, "flow_message_05", state.flowMessages[4]);
        _serializeMessage(path, "flow_message_06", state.flowMessages[5]);
        _serializeMessage(path, "flow_message_07", state.flowMessages[6]);
        _serializeMessage(path, "flow_message_08", state.flowMessages[7]);
        _writeFlowEvmSummary(path, state);
        _writeSatelliteEvmEvidence(path, state);
    }

    function _writeEvmHeader(string memory path, RunState memory state) private {
        string memory key = "phase8_evm_header";
        vm.serializeUint(key, "schema_version", 1);
        vm.serializeString(key, "artifact_type", "PHASE8_EVM_EVIDENCE");
        vm.serializeString(key, "environment", "local");
        vm.serializeBool(key, "contains_real_value", false);
        vm.serializeBytes32(key, "protocol_id", PROTOCOL_ID);
        vm.serializeUint(key, "activated_at", state.activatedAt);
        vm.serializeBytes32(key, "loan_id", LOAN_ID);
        vm.serializeBytes32(key, "funding_lock_id", LOCK_ID);
        vm.serializeBytes32(key, "collateral_id", COLLATERAL_ID);
        vm.serializeUint(key, "principal_units", PRINCIPAL);
        vm.serializeUint(key, "collateral_units", COLLATERAL_AMOUNT);
        vm.serializeBytes(key, "canonical_sorted_signers_abi", abi.encode(_recoverySigners()));
        vm.serializeBytes32(key, "home_observer_public_key", HOME_OBSERVER_PUBLIC_KEY);
        vm.serializeBytes32(
            key, "home_observer_authority_hash", _observerAuthorityHash(HOME_CHAIN_ID)
        );
        vm.serializeBytes32(key, "satellite_observer_public_key", SATELLITE_OBSERVER_PUBLIC_KEY);
        vm.serializeBytes32(
            key, "satellite_observer_authority_hash", _observerAuthorityHash(SATELLITE_CHAIN_ID)
        );
        vm.serializeString(key, "provider_a_id", "mock-bridge-provider-a");
        vm.serializeString(key, "provider_a_authority", "TRANSPORT_ONLY");
        vm.serializeString(key, "provider_b_id", "mock-bridge-provider-b");
        vm.serializeString(key, "provider_b_authority", "TRANSPORT_ONLY");
        string memory json =
            vm.serializeBytes32(key, "adapter_set_policy_hash", _adapterSetPolicyHash());
        vm.writeJson(json, path);
    }

    function _writeHomeEvmEvidence(string memory path, RunState memory state) private {
        string memory key = "phase8_evm_home";
        vm.selectFork(state.homeFork);
        vm.serializeUint(key, "home_chain_id", state.home.chainId);
        vm.serializeUint(key, "home_chain_version", 1);
        vm.serializeUint(key, "home_activation_block", state.home.activationBlock);
        vm.serializeBytes32(
            key, "home_chain_configuration_hash", _chainConfigurationHash(state.home)
        );
        vm.serializeBytes32(key, "home_signer_set_hash", state.home.signerSetHash);
        vm.serializeBytes(
            key,
            "home_signer_set_abi",
            abi.encode(state.home.verifier.signerSetRecord(state.home.signerSetHash))
        );
        _serializeContract(key, "home_role_manager", address(state.home.roles));
        _serializeContract(key, "home_chain_registry", address(state.home.chains));
        _serializeContract(key, "home_emergency_controller", address(state.home.emergency));
        _serializeContract(key, "home_route_registry", address(state.home.routes));
        _serializeContract(key, "home_finality_verifier", address(state.home.verifier));
        _serializeContract(key, "home_coordinator", address(state.home.coordinator));
        _serializeContract(key, "home_recovery_controller", address(state.home.recovery));
        _serializeContract(key, "home_canonical_uft", address(state.canonical));
        _serializeContract(key, "home_loan_registry", address(state.loanRegistry));
        _serializeContract(key, "home_bridge_exposure_policy", address(state.exposure));
        _serializeContract(key, "home_bridge_hub", address(state.hub));
        _serializeContract(
            key, "home_cross_chain_loan_account_deployer", address(state.accountDeployer)
        );
        _serializeContract(key, "home_cross_chain_loan_factory", address(state.loanFactory));
        _serializeContract(key, "home_cross_chain_loan_policy", address(state.loanPolicy));
        _serializeContract(key, "home_cross_chain_loan_account", address(state.loanAccount));
        string memory json = vm.serializeBytes32(
            key, "home_recovery_authorizer_set_hash", state.home.recovery.authorizerSetHash()
        );
        vm.writeJson(json, path, ".home");
    }

    function _writeFlowEvmSummary(string memory path, RunState memory state) private {
        string memory key = "phase8_evm_flow_summary";
        vm.selectFork(state.homeFork);
        vm.serializeBytes32(
            key, "mint_original_result_hash", state.flowMessages[0].destinationResultHash
        );
        vm.serializeBytes32(key, "mint_replay_result_hash", state.mintReplayResultHash);
        vm.serializeBytes32(
            key, "repayment_original_result_hash", state.flowMessages[5].destinationResultHash
        );
        vm.serializeBytes32(key, "repayment_replay_result_hash", state.repaymentReplayResultHash);
        vm.serializeBytes32(
            key,
            "collateral_release_original_result_hash",
            state.flowMessages[6].destinationResultHash
        );
        vm.serializeBytes32(
            key, "collateral_release_replay_result_hash", state.collateralReleaseReplayResultHash
        );
        vm.serializeUint(
            key, "final_outstanding_principal", state.loanAccount.outstandingPrincipal()
        );
        vm.serializeUint(key, "final_bridge_backing", state.hub.totalBridgeBacking());
        vm.serializeUint(key, "final_loan_backing", state.hub.loanBacking(LOAN_ID));
        vm.serializeUint(key, "final_route_exposure", state.hub.routeBacking(state.mintRouteHash));
        vm.serializeUint(key, "final_aggregate_exposure", state.hub.totalBridgeBacking());
        vm.serializeUint(
            key, "borrower_received_principal_units", state.borrowerReceivedPrincipalUnits
        );
        vm.serializeUint(key, "lender_received_repayment_units", state.lenderReceivedRepaymentUnits);
        string memory json = vm.serializeUint(key, "duplicate_economic_effects", 0);
        vm.writeJson(json, path, ".flow_summary");
    }

    function _writeSatelliteEvmEvidence(string memory path, RunState memory state) private {
        string memory key = "phase8_evm_satellite";
        vm.selectFork(state.satelliteFork);
        vm.serializeUint(key, "satellite_chain_id", state.satellite.chainId);
        vm.serializeUint(key, "satellite_chain_version", 1);
        vm.serializeUint(key, "satellite_activation_block", state.satellite.activationBlock);
        vm.serializeBytes32(
            key, "satellite_chain_configuration_hash", _chainConfigurationHash(state.satellite)
        );
        vm.serializeBytes32(key, "satellite_signer_set_hash", state.satellite.signerSetHash);
        vm.serializeBytes(
            key,
            "satellite_signer_set_abi",
            abi.encode(state.satellite.verifier.signerSetRecord(state.satellite.signerSetHash))
        );
        _serializeContract(key, "satellite_role_manager", address(state.satellite.roles));
        _serializeContract(key, "satellite_chain_registry", address(state.satellite.chains));
        _serializeContract(
            key, "satellite_emergency_controller", address(state.satellite.emergency)
        );
        _serializeContract(key, "satellite_route_registry", address(state.satellite.routes));
        _serializeContract(key, "satellite_finality_verifier", address(state.satellite.verifier));
        _serializeContract(key, "satellite_coordinator", address(state.satellite.coordinator));
        _serializeContract(key, "satellite_recovery_controller", address(state.satellite.recovery));
        _serializeContract(key, "satellite_collateral_token", address(state.collateral));
        _serializeContract(key, "satellite_wrapped_uft", address(state.wrapped));
        _serializeContract(key, "satellite_loan_component", address(state.satelliteComponent));
        _serializeContract(key, "satellite_collateral_vault", address(state.collateralVault));
        _serializeContract(key, "satellite_settlement_vault", address(state.settlementVault));
        vm.serializeBytes32(
            key,
            "satellite_recovery_authorizer_set_hash",
            state.satellite.recovery.authorizerSetHash()
        );
        vm.serializeUint(key, "final_wrapped_supply", state.wrapped.totalSupply());
        vm.serializeUint(
            key,
            "final_settlement_vault_balance",
            state.wrapped.balanceOf(address(state.settlementVault))
        );
        vm.serializeUint(
            key,
            "final_collateral_vault_balance",
            state.collateral.balanceOf(address(state.collateralVault))
        );
        vm.serializeUint(
            key, "final_borrower_wrapped_balance", state.wrapped.balanceOf(LOCAL_ADMIN)
        );
        vm.serializeUint(
            key, "final_borrower_collateral_balance", state.collateral.balanceOf(LOCAL_ADMIN)
        );
        string memory json = vm.serializeBool(key, "flow_complete", true);
        vm.writeJson(json, path, ".satellite");
    }

    function _serializeContract(string memory key, string memory label, address target) private {
        vm.serializeAddress(key, string.concat(label, "_address"), target);
        vm.serializeBytes32(key, string.concat(label, "_runtime_code_hash"), target.codehash);
    }

    function _serializeRoute(
        string memory path,
        string memory purpose,
        Domain memory home,
        bytes32 routePolicyHash
    ) private {
        string memory key = string.concat("phase8_evm_route_", purpose);
        RouteRegistry.RouteVersion memory route = home.routes.route(routePolicyHash);
        vm.serializeBytes32(key, string.concat("route_", purpose, "_hash"), routePolicyHash);
        vm.serializeBytes(
            key, string.concat("route_", purpose, "_config_abi"), abi.encode(route.config)
        );
        vm.serializeBytes(
            key,
            string.concat("route_", purpose, "_source_finality_policy_abi"),
            abi.encode(home.verifier.finalityPolicy(route.config.sourceFinalityPolicyHash))
        );
        string memory json = vm.serializeBytes(
            key,
            string.concat("route_", purpose, "_destination_finality_policy_abi"),
            abi.encode(home.verifier.finalityPolicy(route.config.destinationFinalityPolicyHash))
        );
        vm.writeJson(json, path, string.concat(".routes_", purpose));
    }

    function _serializeMessage(
        string memory path,
        string memory label,
        MessageEvidence memory evidence
    ) private {
        string memory key = string.concat("phase8_evm_", label);
        vm.serializeBytes(key, string.concat(label, "_envelope_abi"), abi.encode(evidence.envelope));
        vm.serializeBytes(key, string.concat(label, "_payload"), evidence.payload);
        vm.serializeBytes(
            key, string.concat(label, "_source_proof_abi"), abi.encode(evidence.sourceProof)
        );
        vm.serializeBytes(
            key,
            string.concat(label, "_source_certificate_abi"),
            abi.encode(evidence.sourceCertificate)
        );
        vm.serializeBytes(
            key,
            string.concat(label, "_acknowledgement_proof_abi"),
            abi.encode(evidence.acknowledgementProof)
        );
        vm.serializeBytes(
            key,
            string.concat(label, "_acknowledgement_certificate_abi"),
            abi.encode(evidence.acknowledgementCertificate)
        );
        vm.serializeBytes(
            key,
            string.concat(label, "_execute_calldata"),
            abi.encodeCall(
                CrossChainCoordinator.executeMessage,
                (
                    evidence.envelope,
                    evidence.payload,
                    evidence.sourceProof,
                    evidence.sourceCertificate
                )
            )
        );
        vm.serializeBytes(
            key,
            string.concat(label, "_acknowledgement_calldata"),
            abi.encodeCall(
                CrossChainCoordinator.recordAcknowledgement,
                (
                    evidence.envelope,
                    evidence.destinationResultHash,
                    evidence.acknowledgementProof,
                    evidence.acknowledgementCertificate
                )
            )
        );
        vm.serializeBytes32(key, string.concat(label, "_message_id"), evidence.envelope.messageId);
        vm.serializeUint(
            key, string.concat(label, "_action_ordinal"), uint8(evidence.envelope.actionType)
        );
        vm.serializeBytes32(
            key, string.concat(label, "_payload_hash"), evidence.envelope.payloadHash
        );
        vm.serializeBytes32(
            key, string.concat(label, "_destination_result_hash"), evidence.destinationResultHash
        );
        vm.serializeBytes32(
            key,
            string.concat(label, "_source_proof_hash"),
            CrossChainTypes.sourceProofHash(evidence.sourceProof)
        );
        vm.serializeUint(
            key, string.concat(label, "_source_chain_id"), evidence.envelope.sourceChainId
        );
        vm.serializeBytes32(
            key,
            string.concat(label, "_source_observer_commitment"),
            evidence.sourceProof.observerSignedHeaderCommitment
        );
        vm.serializeBytes(
            key,
            string.concat(label, "_source_observer_signature"),
            evidence.sourceProof.observerSignature
        );
        vm.serializeBytes32(
            key,
            string.concat(label, "_acknowledgement_proof_hash"),
            CrossChainTypes.sourceProofHash(evidence.acknowledgementProof)
        );
        vm.serializeUint(
            key,
            string.concat(label, "_acknowledgement_chain_id"),
            evidence.envelope.destinationChainId
        );
        vm.serializeBytes32(
            key,
            string.concat(label, "_acknowledgement_observer_commitment"),
            evidence.acknowledgementProof.observerSignedHeaderCommitment
        );
        string memory json = vm.serializeBytes(
            key,
            string.concat(label, "_acknowledgement_observer_signature"),
            evidence.acknowledgementProof.observerSignature
        );
        vm.writeJson(json, path, string.concat(".", label));
    }

    function _writeHomeManifest(
        string calldata outputRoot,
        Domain memory home,
        Phase8LocalSyntheticToken canonical,
        BridgeExposurePolicy exposure,
        UFTBridgeHub hub,
        bytes32 mintRouteHash,
        bytes32 exposureHash,
        bytes32 sampleMessageId,
        bytes32 hubCodeHash
    ) private {
        string memory key = "phase8_home";
        vm.serializeString(key, "environment", "local");
        vm.serializeBool(key, "contains_real_value", false);
        vm.serializeUint(key, "chain_id", HOME_CHAIN_ID);
        vm.serializeAddress(key, "role_manager", address(home.roles));
        vm.serializeAddress(key, "chain_registry", address(home.chains));
        vm.serializeAddress(key, "route_registry", address(home.routes));
        vm.serializeAddress(key, "finality_verifier", address(home.verifier));
        vm.serializeAddress(key, "coordinator", address(home.coordinator));
        vm.serializeAddress(key, "recovery_controller", address(home.recovery));
        vm.serializeAddress(key, "canonical_synthetic_token", address(canonical));
        vm.serializeAddress(key, "exposure_policy", address(exposure));
        vm.serializeAddress(key, "bridge_hub", address(hub));
        vm.serializeBytes32(key, "coordinator_code_hash", home.coordinatorCodeHash);
        vm.serializeBytes32(key, "bridge_hub_code_hash", hubCodeHash);
        vm.serializeBytes32(key, "signer_set_hash", home.signerSetHash);
        vm.serializeBytes32(key, "mint_route_hash", mintRouteHash);
        vm.serializeBytes32(key, "exposure_policy_hash", exposureHash);
        string memory json = vm.serializeBytes32(key, "sample_outbound_message_id", sampleMessageId);
        vm.writeJson(json, string.concat(outputRoot, "/phase8-home-31337.json"));
    }

    function _writeSatelliteManifest(
        string calldata outputRoot,
        Domain memory satellite,
        Phase8LocalSyntheticToken collateral,
        WrappedUFT wrapped,
        bytes32 mintRouteHash,
        bytes32 wrappedCodeHash
    ) private {
        string memory key = "phase8_satellite";
        vm.serializeString(key, "environment", "local");
        vm.serializeBool(key, "contains_real_value", false);
        vm.serializeUint(key, "chain_id", SATELLITE_CHAIN_ID);
        vm.serializeAddress(key, "role_manager", address(satellite.roles));
        vm.serializeAddress(key, "chain_registry", address(satellite.chains));
        vm.serializeAddress(key, "route_registry", address(satellite.routes));
        vm.serializeAddress(key, "finality_verifier", address(satellite.verifier));
        vm.serializeAddress(key, "coordinator", address(satellite.coordinator));
        vm.serializeAddress(key, "recovery_controller", address(satellite.recovery));
        vm.serializeAddress(key, "collateral_synthetic_token", address(collateral));
        vm.serializeAddress(key, "wrapped_uft", address(wrapped));
        vm.serializeBytes32(key, "coordinator_code_hash", satellite.coordinatorCodeHash);
        vm.serializeBytes32(key, "wrapped_uft_code_hash", wrappedCodeHash);
        vm.serializeBytes32(key, "signer_set_hash", satellite.signerSetHash);
        string memory json = vm.serializeBytes32(key, "mint_route_hash", mintRouteHash);
        vm.writeJson(json, string.concat(outputRoot, "/phase8-satellite-31338.json"));
    }
}
