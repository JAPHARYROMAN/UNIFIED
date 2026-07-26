// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PayoffQuoteEngine } from "../src/resolution/PayoffQuoteEngine.sol";
import { RefinanceCoordinator } from "../src/resolution/RefinanceCoordinator.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";
import {
    Phase9PayoffMockFactory,
    Phase9PayoffMockPolicySource,
    Phase9PayoffMockRegistry,
    Phase9PayoffVm
} from "./Phase9PayoffQuoteHarness.sol";

contract Phase9DeploymentFiller { }

/// @dev Disposable local-only consecutive-CREATE harness for P9Q-DEPLOY-001..004.
contract Phase9SequentialCreateDeployer {
    struct DeploymentEvidence {
        address engine;
        address coordinator;
        address predictedCoordinator;
        bool reciprocal;
    }

    struct CoordinatorDependencies {
        address registry;
        address factory;
        address engine;
        address policy;
        IERC20 token;
    }

    function deploy(
        Phase9PayoffMockRegistry registry,
        Phase9PayoffMockPolicySource policy,
        Phase9PayoffMockFactory factory,
        Phase9LocalSyntheticToken token,
        uint64 maximumValidity,
        bool insertInterveningCreate,
        bool perturbEngineCoordinator
    ) external returns (DeploymentEvidence memory evidence) {
        require(
            address(registry) != address(0) && address(policy) != address(0)
                && address(factory) != address(0) && address(token) != address(0)
                && maximumValidity != 0,
            "invalid local dependency"
        );
        address predicted = _createAddressAtNonceTwo();
        if (insertInterveningCreate) new Phase9DeploymentFiller();
        address engineCoordinator =
            perturbEngineCoordinator ? address(uint160(predicted) + 1) : predicted;
        PayoffQuoteEngine engine = new PayoffQuoteEngine(
            registry, address(policy), maximumValidity, address(factory), engineCoordinator
        );
        RefinanceCoordinator coordinator = _deployCoordinator(
            CoordinatorDependencies({
                registry: address(registry),
                factory: address(factory),
                engine: address(engine),
                policy: address(policy),
                token: IERC20(address(token))
            })
        );
        require(address(coordinator) == predicted, "coordinator prediction mismatch");
        require(engineCoordinator == address(coordinator), "engine binding mismatch");
        require(address(engine).code.length != 0 && address(coordinator).code.length != 0, "code");
        evidence = DeploymentEvidence({
            engine: address(engine),
            coordinator: address(coordinator),
            predictedCoordinator: predicted,
            reciprocal: true
        });
    }

    function predictedCoordinator() external view returns (address) {
        return _createAddressAtNonceTwo();
    }

    function _createAddressAtNonceTwo() private view returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(hex"d694", address(this), hex"02"))))
            );
    }

    function _deployCoordinator(CoordinatorDependencies memory dependencies)
        private
        returns (RefinanceCoordinator)
    {
        return new RefinanceCoordinator(
            dependencies.registry,
            dependencies.factory,
            dependencies.engine,
            address(0x111),
            address(0x222),
            dependencies.policy,
            address(0x333),
            address(0x444),
            dependencies.token
        );
    }
}

contract Phase9PayoffQuoteDeploymentTest {
    Phase9PayoffVm private constant vm =
        Phase9PayoffVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Phase9PayoffMockRegistry private registry;
    Phase9PayoffMockFactory private factory;
    Phase9PayoffMockPolicySource private policy;
    Phase9LocalSyntheticToken private token;

    function setUp() public {
        vm.chainId(31_337);
        registry = new Phase9PayoffMockRegistry();
        factory = new Phase9PayoffMockFactory();
        policy = new Phase9PayoffMockPolicySource();
        token = new Phase9LocalSyntheticToken(address(this));
    }

    function test_P9Q_DEPLOY001_ConsecutiveCreatePredictionAndReciprocalBindings() public {
        Phase9SequentialCreateDeployer deployer = new Phase9SequentialCreateDeployer();
        Phase9SequentialCreateDeployer.DeploymentEvidence memory evidence =
            deployer.deploy(registry, policy, factory, token, 3_600, false, false);
        require(evidence.coordinator == evidence.predictedCoordinator, "prediction");
        require(evidence.reciprocal, "reciprocal evidence");
        require(evidence.engine.code.length != 0 && evidence.coordinator.code.length != 0, "code");
        require(
            address(uint160(uint256(vm.load(evidence.engine, bytes32(uint256(3))))))
                == evidence.coordinator,
            "engine raw binding"
        );
        require(
            address(uint160(uint256(vm.load(evidence.coordinator, bytes32(uint256(2))))))
                == evidence.engine,
            "coordinator raw binding"
        );
    }

    function test_P9Q_DEPLOY002_InterveningCreateRevertsCompleteDeployment() public {
        Phase9SequentialCreateDeployer deployer = new Phase9SequentialCreateDeployer();
        (bool success,) = address(deployer)
            .call(
                abi.encodeCall(
                    Phase9SequentialCreateDeployer.deploy,
                    (registry, policy, factory, token, 3_600, true, false)
                )
            );
        require(!success, "intervening create accepted");
        require(deployer.predictedCoordinator().code.length == 0, "partial predicted code");
    }

    function test_P9Q_DEPLOY003_PerturbedConstructorBindingRevertsCompleteDeployment() public {
        Phase9SequentialCreateDeployer deployer = new Phase9SequentialCreateDeployer();
        address predicted = deployer.predictedCoordinator();
        (bool success,) = address(deployer)
            .call(
                abi.encodeCall(
                    Phase9SequentialCreateDeployer.deploy,
                    (registry, policy, factory, token, 3_600, false, true)
                )
            );
        require(!success, "perturbed binding accepted");
        require(predicted.code.length == 0, "partial coordinator code");
    }

    function test_P9Q_DEPLOY004_NoRebindingInitializationOrRepairSelectorExists() public {
        Phase9SequentialCreateDeployer deployer = new Phase9SequentialCreateDeployer();
        Phase9SequentialCreateDeployer.DeploymentEvidence memory evidence =
            deployer.deploy(registry, policy, factory, token, 3_600, false, false);
        (bool success,) = evidence.engine
            .call(abi.encodeWithSignature("setRefinanceCoordinator(address)", address(0xBAD)));
        require(!success, "engine rebinding selector");
        (success,) =
            evidence.engine.call(abi.encodeWithSignature("initialize(address)", address(0xBAD)));
        require(!success, "engine initializer selector");
        (success,) = evidence.coordinator
            .call(abi.encodeWithSignature("setPayoffQuoteEngine(address)", address(0xBAD)));
        require(!success, "coordinator repair selector");
        _assertExecutableOpcodeAbsent(evidence.engine.code, 0xf4, "engine DELEGATECALL opcode");
        _assertExecutableOpcodeAbsent(evidence.engine.code, 0xf5, "engine CREATE2 opcode");
    }

    function _assertExecutableOpcodeAbsent(
        bytes memory runtime,
        uint8 forbidden,
        string memory reason
    ) private pure {
        require(runtime.length >= 2, "runtime metadata trailer");
        uint256 metadataLength =
            (uint256(uint8(runtime[runtime.length - 2])) << 8) | uint8(runtime[runtime.length - 1]);
        require(metadataLength + 2 <= runtime.length, "runtime metadata length");
        uint256 executableLength = runtime.length - metadataLength - 2;
        uint256 cursor;
        while (cursor < executableLength) {
            uint8 opcode = uint8(runtime[cursor]);
            require(opcode != forbidden, reason);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                cursor += uint256(opcode) - 0x5f + 1;
            } else {
                ++cursor;
            }
        }
    }
}
