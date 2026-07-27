// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { CollateralCustodyV2 } from "../src/resolution/CollateralCustodyV2.sol";
import { LienRegistry } from "../src/resolution/LienRegistry.sol";
import { PayoffQuoteEngine } from "../src/resolution/PayoffQuoteEngine.sol";
import { Phase9LoanAccount } from "../src/resolution/Phase9LoanAccount.sol";
import { Phase9LoanFactory } from "../src/resolution/Phase9LoanFactory.sol";
import { PositionManagerV2 } from "../src/resolution/PositionManagerV2.sol";
import {
    Phase9RefinanceLifecycleModule,
    Phase9RefinanceRequestModule,
    Phase9RefinanceValidationModule,
    RefinanceCoordinator
} from "../src/resolution/RefinanceCoordinator.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";

enum ForgeContext {
    TestGroup,
    Test,
    Coverage,
    Snapshot,
    ScriptGroup,
    ScriptDryRun,
    ScriptBroadcast,
    ScriptResume,
    Unknown
}

interface Phase9RefinanceLocalDeploymentVm {
    function getNonce(address account) external view returns (uint64 nonce);
    function isContext(ForgeContext context) external view returns (bool result);
    function load(address target, bytes32 slot) external view returns (bytes32 value);
    function serializeAddress(string calldata objectKey, string calldata valueKey, address value)
        external
        returns (string memory json);
    function serializeBool(string calldata objectKey, string calldata valueKey, bool value)
        external
        returns (string memory json);
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
    function startBroadcast() external;
    function startBroadcast(address broadcaster) external;
    function stopBroadcast() external;
    function toString(uint256 value) external pure returns (string memory stringifiedValue);
    function writeJson(string calldata json, string calldata path) external;
}

library Phase9RefinanceLocalDeploymentTypes {
    struct Configuration {
        address broadcaster;
        IRoleManager roleManager;
        ILoanRegistry loanRegistry;
        IERC20 settlementToken;
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

    struct Deployment {
        address[10] predicted;
        address[10] actual;
        bytes32 configurationHash;
    }

    struct CandidateBinding {
        string planSha256;
        bytes32 resetIdentity;
        string sourceCommit;
        string evidencePath;
    }
}

/// @notice Candidate-only local deployment for the fixed Phase 9 refinance module graph.
/// @dev The coordinator must be linked by Forge CLI to the predicted nonce-6/7/8 modules.
contract DeployPhase9RefinanceLocal {
    error InvalidLocalChain(uint256 chainId);
    error InvalidEvidencePath();
    error InvalidDeploymentConfiguration();
    error InvalidBroadcasterNonce(uint64 expected, uint64 actual);
    error CreateAddressMismatch(uint256 ordinal, address predicted, address actual);
    error MissingRuntimeCode(address target);
    error StorageBindingMismatch(address target, uint256 slot, bytes32 expected, bytes32 actual);
    error RuntimeLinkMismatch(uint256 offset, address expected, address actual);

    uint64 private constant STARTING_NONCE = 1;
    uint64 private constant FINAL_EXPECTED_NONCE = 11;
    bytes32 private constant CANDIDATE_EVIDENCE_PATH_HASH =
        keccak256("deployments/local/phase9-refinance-deployment-candidate.json");
    bytes32 private constant CONFIGURATION_DOMAIN =
        keccak256("UNIFIED_PHASE9_REFINANCE_DEPLOYMENT_CONFIGURATION_V1");
    bytes32 private constant LOAN_FACTORY_ROLE = keccak256("LOAN_FACTORY_ROLE");

    uint256 private constant LIFECYCLE_LINK_0 = 1178;
    uint256 private constant LIFECYCLE_LINK_1 = 1269;
    uint256 private constant LIFECYCLE_LINK_2 = 1398;
    uint256 private constant LIFECYCLE_LINK_3 = 1540;
    uint256 private constant REQUEST_LINK_0 = 1589;
    uint256 private constant VALIDATION_LINK_0 = 1860;
    uint256 private constant REQUEST_LINK_1 = 2067;

    Phase9RefinanceLocalDeploymentVm private constant vm =
        Phase9RefinanceLocalDeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(
        Phase9RefinanceLocalDeploymentTypes.Configuration calldata configuration,
        string calldata planSha256,
        bytes32 resetIdentity,
        string calldata sourceCommit,
        string calldata evidencePath
    ) external returns (Phase9RefinanceLocalDeploymentTypes.Deployment memory deployment) {
        if (block.chainid != 31_337) revert InvalidLocalChain(block.chainid);
        if (keccak256(bytes(evidencePath)) != CANDIDATE_EVIDENCE_PATH_HASH) {
            revert InvalidEvidencePath();
        }
        if (
            !_isCanonicalSha256(planSha256) || resetIdentity == bytes32(0)
                || !_isCanonicalSourceCommit(sourceCommit)
        ) revert InvalidDeploymentConfiguration();
        Phase9RefinanceLocalDeploymentTypes.CandidateBinding memory binding =
            Phase9RefinanceLocalDeploymentTypes.CandidateBinding({
                planSha256: planSha256,
                resetIdentity: resetIdentity,
                sourceCommit: sourceCommit,
                evidencePath: evidencePath
            });
        _requireConfiguration(configuration);

        uint64 actualNonce = vm.getNonce(configuration.broadcaster);
        if (actualNonce != STARTING_NONCE) {
            revert InvalidBroadcasterNonce(STARTING_NONCE, actualNonce);
        }

        for (uint8 nonce = 1; nonce <= 10; ++nonce) {
            deployment.predicted[nonce - 1] = _createAddress(configuration.broadcaster, nonce);
        }
        _requireFactoryRoleAbsent(configuration.roleManager, deployment.predicted[4]);
        deployment.configurationHash = _configurationHash(configuration);
        _broadcast(configuration, deployment);
        _assertDeployment(configuration, deployment);
        if (!vm.isContext(ForgeContext.ScriptBroadcast)) {
            revert InvalidDeploymentConfiguration();
        }
        _writeCandidate(binding, configuration, deployment);
    }

    function _broadcast(
        Phase9RefinanceLocalDeploymentTypes.Configuration calldata configuration,
        Phase9RefinanceLocalDeploymentTypes.Deployment memory deployment
    ) private {
        vm.startBroadcast(configuration.broadcaster);

        deployment.actual[0] = address(new LienRegistry(deployment.predicted[9]));
        deployment.actual[1] = address(
            new CollateralCustodyV2(
                configuration.assetRegistry,
                deployment.predicted[0],
                configuration.emergencyController
            )
        );
        deployment.actual[2] = address(new Phase9LoanAccount());
        deployment.actual[3] = address(new PositionManagerV2());
        deployment.actual[4] = address(
            new Phase9LoanFactory(
                configuration.loanRegistry,
                deployment.predicted[2],
                deployment.predicted[3],
                configuration.quotePolicyRegistry,
                configuration.refinancePolicyRegistry,
                configuration.amendmentPolicyRegistry,
                configuration.protectionPolicyRegistry,
                configuration.recoveryPolicyRegistry
            )
        );
        deployment.actual[5] = _deployModule(type(Phase9RefinanceValidationModule).creationCode);
        deployment.actual[6] = _deployModule(type(Phase9RefinanceRequestModule).creationCode);
        deployment.actual[7] = _deployModule(type(Phase9RefinanceLifecycleModule).creationCode);
        deployment.actual[8] = address(
            new PayoffQuoteEngine(
                configuration.loanRegistry,
                configuration.quotePolicyRegistry,
                configuration.maximumQuoteValidity,
                deployment.predicted[4],
                deployment.predicted[9]
            )
        );
        deployment.actual[9] = address(
            new RefinanceCoordinator(
                address(configuration.loanRegistry),
                deployment.predicted[4],
                deployment.predicted[8],
                deployment.predicted[0],
                configuration.assetRegistry,
                configuration.refinancePolicyRegistry,
                configuration.emergencyController,
                configuration.treasuryFeeRecipient,
                configuration.settlementToken
            )
        );

        vm.stopBroadcast();

        uint64 finalNonce = vm.getNonce(configuration.broadcaster);
        if (finalNonce != FINAL_EXPECTED_NONCE) {
            revert InvalidBroadcasterNonce(FINAL_EXPECTED_NONCE, finalNonce);
        }
    }

    function _assertDeployment(
        Phase9RefinanceLocalDeploymentTypes.Configuration calldata configuration,
        Phase9RefinanceLocalDeploymentTypes.Deployment memory deployment
    ) private view {
        for (uint256 index; index < 10; ++index) {
            if (deployment.actual[index] != deployment.predicted[index]) {
                revert CreateAddressMismatch(
                    index + 1, deployment.predicted[index], deployment.actual[index]
                );
            }
            _requireCode(deployment.actual[index]);
        }

        address coordinator = deployment.actual[9];
        _requireFactoryRoleAbsent(configuration.roleManager, deployment.actual[4]);
        if (LienRegistry(deployment.actual[0]).registeredRefinanceCoordinator() != coordinator) {
            revert InvalidDeploymentConfiguration();
        }
        if (
            Phase9LoanFactory(deployment.actual[4]).nextLoanNonce() != 1
                || Phase9LoanFactory(deployment.actual[4]).loanAccount(bytes32(0)) != address(0)
                || Phase9LoanFactory(deployment.actual[4]).positionManager(bytes32(0)) != address(0)
                || CollateralCustodyV2(deployment.actual[1]).totalCustody(bytes32(0)) != 0
                || CollateralCustodyV2(deployment.actual[1]).operationProcessed(bytes32(0))
                || RefinanceCoordinator(coordinator).escrowedUnits(bytes32(0)) != 0
                || RefinanceCoordinator(coordinator).operationProcessed(bytes32(0))
                || RefinanceCoordinator(coordinator).commitmentIds(bytes32(0)).length != 0
        ) revert InvalidDeploymentConfiguration();

        _assertConstructorStorage(configuration, deployment);
        _assertCoordinatorLinks(deployment);
    }

    function _assertConstructorStorage(
        Phase9RefinanceLocalDeploymentTypes.Configuration calldata configuration,
        Phase9RefinanceLocalDeploymentTypes.Deployment memory deployment
    ) private view {
        _assertSlot(deployment.actual[0], 0, _addressWord(deployment.actual[9]));

        _assertSlot(deployment.actual[1], 0, _addressWord(configuration.assetRegistry));
        _assertSlot(deployment.actual[1], 1, _addressWord(deployment.actual[0]));
        _assertSlot(deployment.actual[1], 2, _addressWord(configuration.emergencyController));

        _assertSlot(deployment.actual[4], 0, _addressWord(address(configuration.loanRegistry)));
        _assertSlot(deployment.actual[4], 1, _addressWord(deployment.actual[2]));
        _assertSlot(deployment.actual[4], 2, _addressWord(deployment.actual[3]));
        _assertSlot(deployment.actual[4], 3, _addressWord(configuration.quotePolicyRegistry));
        _assertSlot(deployment.actual[4], 4, _addressWord(configuration.refinancePolicyRegistry));
        _assertSlot(deployment.actual[4], 5, _addressWord(configuration.amendmentPolicyRegistry));
        _assertSlot(deployment.actual[4], 6, _addressWord(configuration.protectionPolicyRegistry));
        _assertSlot(
            deployment.actual[4],
            7,
            bytes32(uint256(uint160(configuration.recoveryPolicyRegistry)) | (uint256(1) << 160))
        );

        _assertSlot(deployment.actual[8], 0, _addressWord(address(configuration.loanRegistry)));
        _assertSlot(
            deployment.actual[8],
            1,
            bytes32(
                uint256(uint160(configuration.quotePolicyRegistry))
                    | (uint256(configuration.maximumQuoteValidity) << 160)
            )
        );
        _assertSlot(deployment.actual[8], 2, _addressWord(deployment.actual[4]));
        _assertSlot(deployment.actual[8], 3, _addressWord(deployment.actual[9]));

        address coordinator = deployment.actual[9];
        _assertSlot(coordinator, 0, _addressWord(address(configuration.loanRegistry)));
        _assertSlot(coordinator, 1, _addressWord(deployment.actual[4]));
        _assertSlot(coordinator, 2, _addressWord(deployment.actual[8]));
        _assertSlot(coordinator, 3, _addressWord(deployment.actual[0]));
        _assertSlot(coordinator, 4, _addressWord(configuration.assetRegistry));
        _assertSlot(coordinator, 5, _addressWord(configuration.refinancePolicyRegistry));
        _assertSlot(coordinator, 6, _addressWord(configuration.emergencyController));
        _assertSlot(coordinator, 7, _addressWord(configuration.treasuryFeeRecipient));
        _assertSlot(coordinator, 8, _addressWord(address(configuration.settlementToken)));
        for (uint256 slot = 9; slot < 16; ++slot) {
            _assertSlot(coordinator, slot, bytes32(0));
        }
    }

    function _assertCoordinatorLinks(
        Phase9RefinanceLocalDeploymentTypes.Deployment memory deployment
    ) private view {
        address coordinator = deployment.actual[9];
        _assertRuntimeLink(coordinator, LIFECYCLE_LINK_0, deployment.actual[7]);
        _assertRuntimeLink(coordinator, LIFECYCLE_LINK_1, deployment.actual[7]);
        _assertRuntimeLink(coordinator, LIFECYCLE_LINK_2, deployment.actual[7]);
        _assertRuntimeLink(coordinator, LIFECYCLE_LINK_3, deployment.actual[7]);
        _assertRuntimeLink(coordinator, REQUEST_LINK_0, deployment.actual[6]);
        _assertRuntimeLink(coordinator, VALIDATION_LINK_0, deployment.actual[5]);
        _assertRuntimeLink(coordinator, REQUEST_LINK_1, deployment.actual[6]);
    }

    function _requireConfiguration(
        Phase9RefinanceLocalDeploymentTypes.Configuration calldata configuration
    ) private view {
        if (
            configuration.broadcaster == address(0) || configuration.broadcaster.code.length != 0
                || configuration.treasuryFeeRecipient == address(0)
                || configuration.quotePolicyRegistry != configuration.refinancePolicyRegistry
                || configuration.maximumQuoteValidity == 0
        ) revert InvalidDeploymentConfiguration();

        _requireCode(address(configuration.roleManager));
        _requireCode(address(configuration.loanRegistry));
        _requireCode(address(configuration.settlementToken));
        _requireCode(configuration.quotePolicyRegistry);
        _requireCode(configuration.refinancePolicyRegistry);
        _requireCode(configuration.amendmentPolicyRegistry);
        _requireCode(configuration.protectionPolicyRegistry);
        _requireCode(configuration.recoveryPolicyRegistry);
        _requireCode(configuration.assetRegistry);
        _requireCode(configuration.emergencyController);
        if (
            address(configuration.settlementToken).codehash
                != keccak256(type(Phase9LocalSyntheticToken).runtimeCode)
        ) revert InvalidDeploymentConfiguration();
    }

    function _configurationHash(
        Phase9RefinanceLocalDeploymentTypes.Configuration calldata configuration
    ) private view returns (bytes32) {
        bytes32 registryHash = keccak256(
            abi.encode(
                address(configuration.roleManager),
                address(configuration.loanRegistry),
                address(configuration.settlementToken),
                configuration.quotePolicyRegistry,
                configuration.refinancePolicyRegistry,
                configuration.amendmentPolicyRegistry,
                configuration.protectionPolicyRegistry,
                configuration.recoveryPolicyRegistry
            )
        );
        bytes32 localAuthorityHash = keccak256(
            abi.encode(
                configuration.broadcaster,
                configuration.assetRegistry,
                configuration.emergencyController,
                configuration.treasuryFeeRecipient,
                configuration.maximumQuoteValidity
            )
        );
        return keccak256(
            abi.encode(CONFIGURATION_DOMAIN, block.chainid, registryHash, localAuthorityHash)
        );
    }

    function _writeCandidate(
        Phase9RefinanceLocalDeploymentTypes.CandidateBinding memory binding,
        Phase9RefinanceLocalDeploymentTypes.Configuration calldata configuration,
        Phase9RefinanceLocalDeploymentTypes.Deployment memory deployment
    ) private {
        string memory key = "phase9_refinance_deployment_candidate";
        vm.serializeUint(key, "schema_version", 1);
        vm.serializeString(key, "artifact_type", "PHASE9_REFINANCE_DEPLOYMENT_CANDIDATE");
        vm.serializeString(key, "environment", "local");
        vm.serializeBool(key, "contains_real_value", false);
        vm.serializeUint(key, "chain_id", block.chainid);
        vm.serializeBool(key, "topology_only", true);
        vm.serializeBool(key, "topology_verified", false);
        vm.serializeBool(key, "role_grant_performed", false);
        vm.serializeString(key, "plan_sha256", binding.planSha256);
        vm.serializeBytes32(key, "reset_identity", binding.resetIdentity);
        vm.serializeString(key, "source_commit", binding.sourceCommit);
        vm.serializeAddress(key, "broadcaster", configuration.broadcaster);
        vm.serializeString(key, "latest_nonce_before", "0x0");
        vm.serializeString(key, "pending_nonce_before", "0x0");
        vm.serializeString(key, "latest_nonce_prepared", "0x1");
        vm.serializeString(key, "pending_nonce_prepared", "0x1");
        vm.serializeUint(key, "starting_nonce", STARTING_NONCE);
        vm.serializeUint(key, "final_nonce", FINAL_EXPECTED_NONCE);
        vm.serializeAddress(key, "role_manager", address(configuration.roleManager));
        vm.serializeAddress(key, "loan_registry", address(configuration.loanRegistry));
        vm.serializeAddress(key, "settlement_token", address(configuration.settlementToken));
        vm.serializeAddress(key, "quote_policy_registry", configuration.quotePolicyRegistry);
        vm.serializeAddress(key, "refinance_policy_registry", configuration.refinancePolicyRegistry);
        vm.serializeAddress(key, "amendment_policy_registry", configuration.amendmentPolicyRegistry);
        vm.serializeAddress(
            key, "protection_policy_registry", configuration.protectionPolicyRegistry
        );
        vm.serializeAddress(key, "recovery_policy_registry", configuration.recoveryPolicyRegistry);
        vm.serializeAddress(key, "asset_registry", configuration.assetRegistry);
        vm.serializeAddress(key, "emergency_controller", configuration.emergencyController);
        vm.serializeAddress(key, "treasury_fee_recipient", configuration.treasuryFeeRecipient);
        vm.serializeString(
            key, "maximum_quote_validity", vm.toString(configuration.maximumQuoteValidity)
        );
        vm.serializeBytes32(key, "configuration_hash", deployment.configurationHash);
        vm.serializeBool(key, "role_before_absent", true);
        vm.serializeBool(key, "role_after_absent", true);

        _serializeDeploymentAddresses(key, deployment);

        vm.serializeBool(key, "activation_accepted", false);
        vm.serializeBool(key, "post_broadcast_verification_required", true);
        string memory json = vm.serializeBool(key, "deployment_history_reverted", false);
        vm.writeJson(json, binding.evidencePath);
    }

    function _serializeDeploymentAddresses(
        string memory key,
        Phase9RefinanceLocalDeploymentTypes.Deployment memory deployment
    ) private {
        _serializePair(key, "lien_registry", deployment.predicted[0], deployment.actual[0]);
        _serializePair(key, "collateral_custody", deployment.predicted[1], deployment.actual[1]);
        _serializePair(
            key, "loan_account_implementation", deployment.predicted[2], deployment.actual[2]
        );
        _serializePair(
            key, "position_manager_implementation", deployment.predicted[3], deployment.actual[3]
        );
        _serializePair(key, "phase9_loan_factory", deployment.predicted[4], deployment.actual[4]);
        _serializePair(key, "validation_module", deployment.predicted[5], deployment.actual[5]);
        _serializePair(key, "request_module", deployment.predicted[6], deployment.actual[6]);
        _serializePair(key, "lifecycle_module", deployment.predicted[7], deployment.actual[7]);
        _serializePair(key, "payoff_quote_engine", deployment.predicted[8], deployment.actual[8]);
        _serializePair(key, "refinance_coordinator", deployment.predicted[9], deployment.actual[9]);
    }

    function _serializePair(
        string memory key,
        string memory label,
        address predicted,
        address actual
    ) private {
        vm.serializeAddress(key, string.concat("predicted_", label), predicted);
        vm.serializeAddress(key, string.concat("actual_", label), actual);
        vm.serializeBytes32(key, string.concat(label, "_runtime_code_hash"), actual.codehash);
    }

    function _deployModule(bytes memory creationCode) private returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (deployed == address(0)) revert InvalidDeploymentConfiguration();
    }

    function _assertSlot(address target, uint256 slot, bytes32 expected) private view {
        bytes32 actual = vm.load(target, bytes32(slot));
        if (actual != expected) {
            revert StorageBindingMismatch(target, slot, expected, actual);
        }
    }

    function _assertRuntimeLink(address target, uint256 offset, address expected) private view {
        address actual;
        assembly ("memory-safe") {
            let pointer := mload(0x40)
            extcodecopy(target, pointer, offset, 20)
            actual := shr(96, mload(pointer))
        }
        if (actual != expected) revert RuntimeLinkMismatch(offset, expected, actual);
    }

    function _requireCode(address target) private view {
        if (target.code.length == 0) revert MissingRuntimeCode(target);
    }

    function _requireFactoryRoleAbsent(IRoleManager roleManager, address factory) private view {
        if (
            roleManager.roleExpiry(LOAN_FACTORY_ROLE, factory) != 0
                || roleManager.hasRole(LOAN_FACTORY_ROLE, factory)
        ) revert InvalidDeploymentConfiguration();
    }

    function _isCanonicalSha256(string calldata supplied) private pure returns (bool) {
        bytes calldata value = bytes(supplied);
        if (
            value.length != 71 || value[0] != "s" || value[1] != "h" || value[2] != "a"
                || value[3] != "2" || value[4] != "5" || value[5] != "6" || value[6] != ":"
        ) return false;
        for (uint256 index = 7; index < value.length; ++index) {
            if (!_isLowerHex(value[index])) return false;
        }
        return true;
    }

    function _isCanonicalSourceCommit(string calldata supplied) private pure returns (bool) {
        bytes calldata value = bytes(supplied);
        if (value.length != 40) return false;
        for (uint256 index; index < value.length; ++index) {
            if (!_isLowerHex(value[index])) return false;
        }
        return true;
    }

    function _isLowerHex(bytes1 character) private pure returns (bool) {
        return (character >= "0" && character <= "9") || (character >= "a" && character <= "f");
    }

    function _addressWord(address value) private pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    function _createAddress(address deployer, uint8 nonce) private pure returns (address) {
        if (nonce == 0 || nonce > 0x7f) revert InvalidDeploymentConfiguration();
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(nonce)))
                )
            )
        );
    }
}
