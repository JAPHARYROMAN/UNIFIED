// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import {
    DeployPhase9Local,
    Phase9PayoffDeploymentTypes,
    Phase9PayoffPairDeployer
} from "../script/DeployPhase9Local.s.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";
import {
    Phase9PayoffMockFactory,
    Phase9PayoffMockPolicySource,
    Phase9PayoffMockRegistry
} from "./Phase9PayoffQuoteHarness.sol";

interface Phase9PayoffLocalDeploymentVm {
    function chainId(uint256 chainId) external;
    function load(address target, bytes32 slot) external view returns (bytes32 value);
    function revertToState(uint256 snapshotId) external returns (bool success);
    function snapshotState() external returns (uint256 snapshotId);
}

contract Phase9PayoffLocalDependency { }

contract Phase9PayoffLocalDeploymentEvidenceTest {
    struct ResetReceipt {
        bool activationAccepted;
        bool completedDeploymentObserved;
        bool boundedLocalStateReset;
        bool deploymentHistoryReverted;
    }

    Phase9PayoffLocalDeploymentVm private constant vm =
        Phase9PayoffLocalDeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Phase9PayoffMockRegistry private registry;
    Phase9PayoffMockFactory private factory;
    Phase9PayoffMockPolicySource private quotePolicy;
    Phase9PayoffLocalDependency private lienRegistry;
    Phase9PayoffLocalDependency private assetRegistry;
    Phase9PayoffLocalDependency private refinancePolicy;
    Phase9PayoffLocalDependency private emergencyController;
    Phase9LocalSyntheticToken private token;
    DeployPhase9Local private evidenceValidator;

    Phase9PayoffDeploymentTypes.Configuration private configuration;

    function setUp() public {
        vm.chainId(31_337);
        registry = new Phase9PayoffMockRegistry();
        factory = new Phase9PayoffMockFactory();
        quotePolicy = new Phase9PayoffMockPolicySource();
        lienRegistry = new Phase9PayoffLocalDependency();
        assetRegistry = new Phase9PayoffLocalDependency();
        refinancePolicy = new Phase9PayoffLocalDependency();
        emergencyController = new Phase9PayoffLocalDependency();
        token = new Phase9LocalSyntheticToken(address(this));
        evidenceValidator = new DeployPhase9Local();
        configuration = Phase9PayoffDeploymentTypes.Configuration({
            loanRegistry: registry,
            phase9LoanFactory: address(factory),
            quotePolicyRegistry: address(quotePolicy),
            lienRegistry: address(lienRegistry),
            assetRegistry: address(assetRegistry),
            refinancePolicyRegistry: address(refinancePolicy),
            emergencyController: address(emergencyController),
            treasuryFeeRecipient: address(this),
            fixtureAllocator: address(this),
            maximumQuoteValidity: 3_600
        });
    }

    function test_P9Q_DEPLOY005_MismatchedPostEvidenceRejectsActivationThenBoundedReset() public {
        uint256 cleanPairSnapshot = vm.snapshotState();

        Phase9PayoffPairDeployer pairDeployer = new Phase9PayoffPairDeployer(configuration, token);
        Phase9PayoffDeploymentTypes.PairEvidence memory evidence = evidenceValidator.assembleEvidence(
            address(pairDeployer), configuration, address(token)
        );
        address predictedEngine = evidence.predictedEngine;
        address predictedCoordinator = evidence.predictedCoordinator;
        Phase9PayoffDeploymentTypes.PostDeploymentObservation memory observation =
            _observe(evidence);
        require(
            evidenceValidator.validateReleaseEvidence(configuration, evidence, observation)
                == bytes32(0),
            "valid evidence rejected"
        );

        bool completedDeploymentObserved =
            evidence.engine.code.length != 0 && evidence.coordinator.code.length != 0;
        require(completedDeploymentObserved, "deployment did not complete before evidence");

        observation.engineSlots[3] = bytes32(uint256(uint160(address(0xBAD))));
        bytes32 rejection =
            evidenceValidator.validateReleaseEvidence(configuration, evidence, observation);
        require(rejection != bytes32(0), "mismatched raw evidence accepted");

        bool activationAccepted;
        require(!activationAccepted, "activation accepted before evidence");
        bytes32 prohibitedLoanId = keccak256("P9Q-DEPLOY-005-NO-LOAN");
        require(!registry.exists(prohibitedLoanId), "loan created before activation evidence");
        (bool quoteExists,) =
            evidence.engine.staticcall(abi.encodeWithSignature("quote(bytes32)", prohibitedLoanId));
        require(!quoteExists, "quote created before activation evidence");
        require(vm.revertToState(cleanPairSnapshot), "bounded local reset failed");
        require(predictedEngine.code.length == 0, "engine survived bounded reset");
        require(predictedCoordinator.code.length == 0, "coordinator survived bounded reset");
        require(address(token).code.length != 0, "reset escaped pair boundary");
        require(address(pairDeployer).code.length == 0, "constructor deployer survived reset");

        ResetReceipt memory receipt = ResetReceipt({
            activationAccepted: false,
            completedDeploymentObserved: completedDeploymentObserved,
            boundedLocalStateReset: true,
            deploymentHistoryReverted: false
        });
        require(!receipt.activationAccepted, "reset receipt accepted activation");
        require(receipt.completedDeploymentObserved, "receipt rewrote completed deployment");
        require(receipt.boundedLocalStateReset, "reset not recorded");
        require(!receipt.deploymentHistoryReverted, "receipt claimed historical transaction revert");
    }

    function testEvidenceValidatorRejectsConstructorArgumentAndCodeHashSubstitution() public {
        Phase9PayoffPairDeployer pairDeployer = new Phase9PayoffPairDeployer(configuration, token);
        Phase9PayoffDeploymentTypes.PairEvidence memory evidence = evidenceValidator.assembleEvidence(
            address(pairDeployer), configuration, address(token)
        );
        Phase9PayoffDeploymentTypes.PostDeploymentObservation memory observation =
            _observe(evidence);

        bytes32 originalArgsHash = evidence.coordinatorConstructorArgsHash;
        evidence.coordinatorConstructorArgsHash = keccak256("substituted coordinator arguments");
        require(
            evidenceValidator.validateReleaseEvidence(configuration, evidence, observation)
                != bytes32(0),
            "constructor substitution accepted"
        );
        evidence.coordinatorConstructorArgsHash = originalArgsHash;

        observation.coordinatorRuntimeCodeHash = keccak256("substituted runtime");
        require(
            evidenceValidator.validateReleaseEvidence(configuration, evidence, observation)
                != bytes32(0),
            "runtime substitution accepted"
        );
    }

    function testConstructorOnlyPairDeployerFitsEvmRuntimeAndInitcodeLimits() public view {
        uint256 runtimeLength = type(Phase9PayoffPairDeployer).runtimeCode.length;
        uint256 initcodeLength = type(Phase9PayoffPairDeployer).creationCode.length
            + abi.encode(configuration, token).length;
        require(runtimeLength <= 24_576, "pair deployer exceeds EIP-170 runtime limit");
        require(initcodeLength <= 49_152, "pair deployer exceeds EIP-3860 initcode limit");
    }

    function testDeploymentEntrypointRejectsAlternateEvidencePathBeforeBroadcast() public {
        (bool success, bytes memory revertData) = address(evidenceValidator)
            .call(
                abi.encodeWithSelector(
                    DeployPhase9Local.run.selector,
                    configuration,
                    "deployments/local/phase9-payoff-deployment-evidence.json"
                )
            );
        require(!success, "alternate evidence path accepted");
        require(revertData.length == 4, "unexpected evidence-path rejection");
        bytes4 selector;
        assembly ("memory-safe") {
            selector := mload(add(revertData, 0x20))
        }
        require(selector == DeployPhase9Local.InvalidEvidencePath.selector, "wrong rejection");
    }

    function _observe(Phase9PayoffDeploymentTypes.PairEvidence memory evidence)
        private
        view
        returns (Phase9PayoffDeploymentTypes.PostDeploymentObservation memory observation)
    {
        observation.tokenRuntimeCodeHash = evidence.settlementToken.codehash;
        observation.engineRuntimeCodeHash = evidence.engine.codehash;
        observation.coordinatorRuntimeCodeHash = evidence.coordinator.codehash;
        for (uint256 slot; slot < 4; ++slot) {
            observation.engineSlots[slot] = vm.load(evidence.engine, bytes32(slot));
        }
        for (uint256 slot; slot < 9; ++slot) {
            observation.coordinatorSlots[slot] = vm.load(evidence.coordinator, bytes32(slot));
        }
    }
}
