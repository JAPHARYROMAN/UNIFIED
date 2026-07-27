// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { PayoffQuoteEngine } from "../src/resolution/PayoffQuoteEngine.sol";
import { RefinanceCoordinator } from "../src/resolution/RefinanceCoordinator.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";

interface Phase9LocalDeploymentVm {
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
    function stopBroadcast() external;
    function toString(uint256 value) external pure returns (string memory stringifiedValue);
    function writeJson(string calldata json, string calldata path) external;
}

library Phase9PayoffDeploymentTypes {
    struct Configuration {
        ILoanRegistry loanRegistry;
        address phase9LoanFactory;
        address quotePolicyRegistry;
        address lienRegistry;
        address assetRegistry;
        address refinancePolicyRegistry;
        address emergencyController;
        address treasuryFeeRecipient;
        address fixtureAllocator;
        uint64 maximumQuoteValidity;
    }

    struct PairEvidence {
        address deployer;
        uint64 engineCreateNonce;
        uint256 chainId;
        address settlementToken;
        address predictedEngine;
        address engine;
        address predictedCoordinator;
        address coordinator;
        bytes32 configurationHash;
        bytes32 engineConstructorArgsHash;
        bytes32 coordinatorConstructorArgsHash;
        bytes32 expectedTokenRuntimeCodeHash;
        bytes32 expectedEngineRuntimeCodeHash;
        bytes32 expectedCoordinatorRuntimeCodeHash;
        bytes32 deploymentCallHash;
    }

    struct PostDeploymentObservation {
        bytes32 tokenRuntimeCodeHash;
        bytes32 engineRuntimeCodeHash;
        bytes32 coordinatorRuntimeCodeHash;
        bytes32[4] engineSlots;
        bytes32[9] coordinatorSlots;
    }
}

/// @notice Deterministic validation of the post-transaction payoff deployment evidence.
/// @dev Raw storage is evidence only. A rejection cannot and does not revert deployment history.
library Phase9PayoffDeploymentEvidence {
    bytes32 internal constant ACCEPTED = bytes32(0);
    bytes32 internal constant WRONG_CHAIN = keccak256("WRONG_CHAIN");
    bytes32 internal constant WRONG_CREATE_SEQUENCE = keccak256("WRONG_CREATE_SEQUENCE");
    bytes32 internal constant WRONG_ADDRESS = keccak256("WRONG_ADDRESS");
    bytes32 internal constant WRONG_CONFIGURATION = keccak256("WRONG_CONFIGURATION");
    bytes32 internal constant WRONG_CONSTRUCTOR_ARGS = keccak256("WRONG_CONSTRUCTOR_ARGS");
    bytes32 internal constant WRONG_CODE_HASH = keccak256("WRONG_CODE_HASH");
    bytes32 internal constant WRONG_ENGINE_STORAGE = keccak256("WRONG_ENGINE_STORAGE");
    bytes32 internal constant WRONG_COORDINATOR_STORAGE = keccak256("WRONG_COORD_STORAGE");

    bytes32 private constant CONFIGURATION_DOMAIN =
        keccak256("UNIFIED_PHASE9_PAYOFF_DEPLOYMENT_CONFIGURATION_V1");
    bytes32 private constant ENGINE_ARGS_DOMAIN =
        keccak256("UNIFIED_PHASE9_PAYOFF_ENGINE_CONSTRUCTOR_ARGS_V1");
    bytes32 private constant COORDINATOR_ARGS_DOMAIN =
        keccak256("UNIFIED_PHASE9_REFINANCE_COORDINATOR_CONSTRUCTOR_ARGS_V1");
    bytes32 private constant DEPLOYMENT_CALL_DOMAIN =
        keccak256("UNIFIED_PHASE9_PAYOFF_DEPLOYMENT_CALL_V1");

    function validate(
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        Phase9PayoffDeploymentTypes.PairEvidence memory evidence,
        Phase9PayoffDeploymentTypes.PostDeploymentObservation memory observation
    ) internal pure returns (bytes32 rejectionCode) {
        if (evidence.chainId != 31_337) return WRONG_CHAIN;
        if (evidence.deployer == address(0) || evidence.engineCreateNonce != 1) {
            return WRONG_CREATE_SEQUENCE;
        }
        if (
            evidence.predictedEngine != createAddress(evidence.deployer, 1)
                || evidence.predictedCoordinator != createAddress(evidence.deployer, 2)
                || evidence.engine != evidence.predictedEngine
                || evidence.coordinator != evidence.predictedCoordinator
        ) return WRONG_ADDRESS;

        bytes32 expectedConfigurationHash =
            configurationHash(configuration, evidence.settlementToken);
        if (evidence.configurationHash != expectedConfigurationHash) return WRONG_CONFIGURATION;
        if (
            evidence.engineConstructorArgsHash
                    != engineConstructorArgsHash(configuration, evidence.coordinator)
                || evidence.coordinatorConstructorArgsHash
                    != coordinatorConstructorArgsHash(
                        configuration, evidence.engine, evidence.settlementToken
                    )
        ) return WRONG_CONSTRUCTOR_ARGS;
        if (
            evidence.deploymentCallHash
                != deploymentCallHash(
                    evidence.deployer,
                    evidence.engineCreateNonce,
                    expectedConfigurationHash,
                    evidence.engine,
                    evidence.coordinator,
                    evidence.engineConstructorArgsHash,
                    evidence.coordinatorConstructorArgsHash
                )
        ) return WRONG_CONSTRUCTOR_ARGS;

        if (
            observation.tokenRuntimeCodeHash == bytes32(0)
                || observation.engineRuntimeCodeHash == bytes32(0)
                || observation.coordinatorRuntimeCodeHash == bytes32(0)
                || observation.tokenRuntimeCodeHash != evidence.expectedTokenRuntimeCodeHash
                || observation.engineRuntimeCodeHash != evidence.expectedEngineRuntimeCodeHash
                || observation.coordinatorRuntimeCodeHash
                    != evidence.expectedCoordinatorRuntimeCodeHash
        ) return WRONG_CODE_HASH;

        if (
            observation.engineSlots[0] != _addressWord(address(configuration.loanRegistry))
                || observation.engineSlots[1]
                    != _packedPolicyAndValidity(
                        configuration.quotePolicyRegistry, configuration.maximumQuoteValidity
                    ) || observation.engineSlots[2] != _addressWord(configuration.phase9LoanFactory)
                || observation.engineSlots[3] != _addressWord(evidence.coordinator)
        ) return WRONG_ENGINE_STORAGE;

        if (
            observation.coordinatorSlots[0] != _addressWord(address(configuration.loanRegistry))
                || observation.coordinatorSlots[1] != _addressWord(configuration.phase9LoanFactory)
                || observation.coordinatorSlots[2] != _addressWord(evidence.engine)
                || observation.coordinatorSlots[3] != _addressWord(configuration.lienRegistry)
                || observation.coordinatorSlots[4] != _addressWord(configuration.assetRegistry)
                || observation.coordinatorSlots[5]
                    != _addressWord(configuration.refinancePolicyRegistry)
                || observation.coordinatorSlots[6]
                    != _addressWord(configuration.emergencyController)
                || observation.coordinatorSlots[7]
                    != _addressWord(configuration.treasuryFeeRecipient)
                || observation.coordinatorSlots[8] != _addressWord(evidence.settlementToken)
        ) return WRONG_COORDINATOR_STORAGE;

        return ACCEPTED;
    }

    function createAddress(address deployer, uint8 nonce) internal pure returns (address) {
        require(nonce != 0 && nonce <= 0x7f, "unsupported CREATE nonce");
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(nonce)))
                )
            )
        );
    }

    function configurationHash(
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        address settlementToken
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CONFIGURATION_DOMAIN,
                uint256(31_337),
                address(configuration.loanRegistry),
                configuration.phase9LoanFactory,
                configuration.quotePolicyRegistry,
                configuration.lienRegistry,
                configuration.assetRegistry,
                configuration.refinancePolicyRegistry,
                configuration.emergencyController,
                configuration.treasuryFeeRecipient,
                configuration.fixtureAllocator,
                configuration.maximumQuoteValidity,
                settlementToken
            )
        );
    }

    function engineConstructorArgsHash(
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        address coordinator
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ENGINE_ARGS_DOMAIN,
                address(configuration.loanRegistry),
                configuration.quotePolicyRegistry,
                configuration.maximumQuoteValidity,
                configuration.phase9LoanFactory,
                coordinator
            )
        );
    }

    function coordinatorConstructorArgsHash(
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        address engine,
        address settlementToken
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                COORDINATOR_ARGS_DOMAIN,
                address(configuration.loanRegistry),
                configuration.phase9LoanFactory,
                engine,
                configuration.lienRegistry,
                configuration.assetRegistry,
                configuration.refinancePolicyRegistry,
                configuration.emergencyController,
                configuration.treasuryFeeRecipient,
                settlementToken
            )
        );
    }

    function deploymentCallHash(
        address deployer,
        uint64 engineCreateNonce,
        bytes32 configurationHash_,
        address engine,
        address coordinator,
        bytes32 engineArgsHash,
        bytes32 coordinatorArgsHash
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DEPLOYMENT_CALL_DOMAIN,
                uint256(31_337),
                deployer,
                engineCreateNonce,
                engine,
                coordinator,
                configurationHash_,
                engineArgsHash,
                coordinatorArgsHash
            )
        );
    }

    function _addressWord(address value) private pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    function _packedPolicyAndValidity(address policy, uint64 maximumValidity)
        private
        pure
        returns (bytes32)
    {
        return bytes32(uint256(uint160(policy)) | (uint256(maximumValidity) << 160));
    }
}

/// @notice Fresh, disposable deployer for the engine/coordinator reciprocal constructor cycle.
/// @dev Its first CREATE is nonce 1 and its immediately following CREATE is nonce 2.
contract Phase9PayoffPairDeployer {
    error InvalidLocalChain(uint256 chainId);
    error InvalidDeploymentInput();
    error CreateAddressMismatch(address predicted, address actual);
    error RuntimeCodeMismatch(address target, bytes32 expected, bytes32 actual);

    event PayoffPairDeployed(
        address indexed deployer,
        address indexed engine,
        address indexed coordinator,
        uint64 engineCreateNonce
    );

    constructor(
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        Phase9LocalSyntheticToken settlementToken
    ) {
        if (block.chainid != 31_337) revert InvalidLocalChain(block.chainid);
        _requireValidConfiguration(configuration, settlementToken);

        address predictedEngine = Phase9PayoffDeploymentEvidence.createAddress(address(this), 1);
        address predictedCoordinator =
            Phase9PayoffDeploymentEvidence.createAddress(address(this), 2);

        bytes32 expectedTokenCodeHash = keccak256(type(Phase9LocalSyntheticToken).runtimeCode);
        _requireCodeHash(address(settlementToken), expectedTokenCodeHash);

        // These two CREATEs are deliberately consecutive. Do not insert a creation or callback.
        PayoffQuoteEngine engine = new PayoffQuoteEngine(
            configuration.loanRegistry,
            configuration.quotePolicyRegistry,
            configuration.maximumQuoteValidity,
            configuration.phase9LoanFactory,
            predictedCoordinator
        );
        if (address(engine) != predictedEngine) {
            revert CreateAddressMismatch(predictedEngine, address(engine));
        }
        RefinanceCoordinator coordinator = new RefinanceCoordinator(
            address(configuration.loanRegistry),
            configuration.phase9LoanFactory,
            address(engine),
            configuration.lienRegistry,
            configuration.assetRegistry,
            configuration.refinancePolicyRegistry,
            configuration.emergencyController,
            configuration.treasuryFeeRecipient,
            IERC20(address(settlementToken))
        );
        if (address(coordinator) != predictedCoordinator) {
            revert CreateAddressMismatch(predictedCoordinator, address(coordinator));
        }

        bytes32 expectedEngineCodeHash = keccak256(type(PayoffQuoteEngine).runtimeCode);
        _requireCodeHash(address(engine), expectedEngineCodeHash);
        // The coordinator is created from the compiler-fixed, fully linked child initcode above.
        // Its live runtime hash and constructor slots are independently pinned by release evidence;
        // embedding the same runtime bytes here again would exceed the EIP-3860 initcode limit.

        emit PayoffPairDeployed(address(this), address(engine), address(coordinator), 1);
    }

    function _requireValidConfiguration(
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        Phase9LocalSyntheticToken settlementToken
    ) private view {
        if (
            address(configuration.loanRegistry) == address(0)
                || configuration.phase9LoanFactory == address(0)
                || configuration.quotePolicyRegistry == address(0)
                || configuration.lienRegistry == address(0)
                || configuration.assetRegistry == address(0)
                || configuration.refinancePolicyRegistry == address(0)
                || configuration.emergencyController == address(0)
                || configuration.treasuryFeeRecipient == address(0)
                || configuration.fixtureAllocator == address(0)
                || configuration.maximumQuoteValidity == 0 || address(settlementToken) == address(0)
                || address(configuration.loanRegistry).code.length == 0
                || configuration.phase9LoanFactory.code.length == 0
                || configuration.quotePolicyRegistry.code.length == 0
                || configuration.lienRegistry.code.length == 0
                || configuration.assetRegistry.code.length == 0
                || configuration.refinancePolicyRegistry.code.length == 0
                || configuration.emergencyController.code.length == 0
        ) revert InvalidDeploymentInput();
    }

    function _requireCodeHash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (target.code.length == 0 || actual != expected) {
            revert RuntimeCodeMismatch(target, expected, actual);
        }
    }
}

/// @notice Local-only deployment entry point and post-transaction release-evidence assembler.
contract DeployPhase9Local {
    error InvalidEvidencePath();
    error PostDeploymentEvidenceRejected(bytes32 reason);

    bytes32 private constant CANDIDATE_EVIDENCE_PATH_HASH =
        keccak256("deployments/local/phase9-payoff-deployment-candidate.json");

    Phase9LocalDeploymentVm private constant vm =
        Phase9LocalDeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(
        Phase9PayoffDeploymentTypes.Configuration calldata configuration,
        string calldata evidencePath
    )
        external
        returns (address settlementToken, Phase9PayoffDeploymentTypes.PairEvidence memory evidence)
    {
        if (keccak256(bytes(evidencePath)) != CANDIDATE_EVIDENCE_PATH_HASH) {
            revert InvalidEvidencePath();
        }

        vm.startBroadcast();
        Phase9LocalSyntheticToken token =
            new Phase9LocalSyntheticToken(configuration.fixtureAllocator);
        Phase9PayoffPairDeployer pairDeployer = new Phase9PayoffPairDeployer(configuration, token);
        vm.stopBroadcast();

        evidence = assembleEvidence(address(pairDeployer), configuration, address(token));
        _writeCandidate(evidencePath, configuration, evidence);
        settlementToken = address(token);
    }

    function assembleEvidence(
        address pairDeployer,
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        address settlementToken
    ) public view returns (Phase9PayoffDeploymentTypes.PairEvidence memory evidence) {
        if (pairDeployer.code.length == 0 || settlementToken.code.length == 0) {
            revert PostDeploymentEvidenceRejected(keccak256("WRONG_CODE_HASH"));
        }
        address engine = Phase9PayoffDeploymentEvidence.createAddress(pairDeployer, 1);
        address coordinator = Phase9PayoffDeploymentEvidence.createAddress(pairDeployer, 2);
        evidence.deployer = pairDeployer;
        evidence.engineCreateNonce = 1;
        evidence.chainId = block.chainid;
        evidence.settlementToken = settlementToken;
        evidence.predictedEngine = engine;
        evidence.engine = engine;
        evidence.predictedCoordinator = coordinator;
        evidence.coordinator = coordinator;
        evidence.configurationHash =
            Phase9PayoffDeploymentEvidence.configurationHash(configuration, settlementToken);
        evidence.engineConstructorArgsHash =
            Phase9PayoffDeploymentEvidence.engineConstructorArgsHash(configuration, coordinator);
        evidence.coordinatorConstructorArgsHash =
            Phase9PayoffDeploymentEvidence.coordinatorConstructorArgsHash(
                configuration, engine, settlementToken
            );
        evidence.expectedTokenRuntimeCodeHash =
            keccak256(type(Phase9LocalSyntheticToken).runtimeCode);
        evidence.expectedEngineRuntimeCodeHash = keccak256(type(PayoffQuoteEngine).runtimeCode);
        evidence.expectedCoordinatorRuntimeCodeHash =
            keccak256(type(RefinanceCoordinator).runtimeCode);
        evidence.deploymentCallHash = Phase9PayoffDeploymentEvidence.deploymentCallHash(
            pairDeployer,
            1,
            evidence.configurationHash,
            engine,
            coordinator,
            evidence.engineConstructorArgsHash,
            evidence.coordinatorConstructorArgsHash
        );
    }

    function validateReleaseEvidence(
        Phase9PayoffDeploymentTypes.Configuration memory configuration,
        Phase9PayoffDeploymentTypes.PairEvidence memory evidence,
        Phase9PayoffDeploymentTypes.PostDeploymentObservation memory observation
    ) external pure returns (bytes32 rejectionCode) {
        return Phase9PayoffDeploymentEvidence.validate(configuration, evidence, observation);
    }

    function _writeCandidate(
        string calldata evidencePath,
        Phase9PayoffDeploymentTypes.Configuration calldata configuration,
        Phase9PayoffDeploymentTypes.PairEvidence memory evidence
    ) private {
        string memory key = "phase9_payoff_deployment_candidate";
        vm.serializeUint(key, "schema_version", 1);
        vm.serializeString(key, "artifact_type", "PHASE9_PAYOFF_DEPLOYMENT_CANDIDATE");
        vm.serializeString(key, "environment", "local");
        vm.serializeBool(key, "contains_real_value", false);
        vm.serializeUint(key, "chain_id", evidence.chainId);
        vm.serializeAddress(key, "pair_deployer", evidence.deployer);
        vm.serializeUint(key, "engine_create_nonce", evidence.engineCreateNonce);
        vm.serializeAddress(key, "loan_registry", address(configuration.loanRegistry));
        vm.serializeAddress(key, "phase9_loan_factory", configuration.phase9LoanFactory);
        vm.serializeAddress(key, "quote_policy_registry", configuration.quotePolicyRegistry);
        vm.serializeAddress(key, "lien_registry", configuration.lienRegistry);
        vm.serializeAddress(key, "asset_registry", configuration.assetRegistry);
        vm.serializeAddress(key, "refinance_policy_registry", configuration.refinancePolicyRegistry);
        vm.serializeAddress(key, "emergency_controller", configuration.emergencyController);
        vm.serializeAddress(key, "treasury_fee_recipient", configuration.treasuryFeeRecipient);
        vm.serializeAddress(key, "fixture_allocator", configuration.fixtureAllocator);
        vm.serializeString(
            key, "maximum_quote_validity", vm.toString(uint256(configuration.maximumQuoteValidity))
        );
        vm.serializeAddress(key, "settlement_token", evidence.settlementToken);
        vm.serializeAddress(key, "predicted_engine", evidence.predictedEngine);
        vm.serializeAddress(key, "predicted_coordinator", evidence.predictedCoordinator);
        vm.serializeBytes32(key, "configuration_hash", evidence.configurationHash);
        vm.serializeBytes32(key, "engine_constructor_args_hash", evidence.engineConstructorArgsHash);
        vm.serializeBytes32(
            key, "coordinator_constructor_args_hash", evidence.coordinatorConstructorArgsHash
        );
        vm.serializeBytes32(key, "deployment_call_hash", evidence.deploymentCallHash);
        vm.serializeBytes32(
            key, "expected_token_runtime_code_hash", evidence.expectedTokenRuntimeCodeHash
        );
        vm.serializeBytes32(
            key, "expected_engine_runtime_code_hash", evidence.expectedEngineRuntimeCodeHash
        );
        vm.serializeBytes32(
            key,
            "expected_coordinator_runtime_code_hash",
            evidence.expectedCoordinatorRuntimeCodeHash
        );
        vm.serializeBytes32(
            key,
            "expected_pair_runtime_code_hash",
            keccak256(type(Phase9PayoffPairDeployer).runtimeCode)
        );
        vm.serializeBool(key, "activation_accepted", false);
        vm.serializeBool(key, "post_broadcast_verification_required", true);
        string memory json = vm.serializeBool(key, "deployment_history_reverted", false);
        vm.writeJson(json, evidencePath);
    }
}
