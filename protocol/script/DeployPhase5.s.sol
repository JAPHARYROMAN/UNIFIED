// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { PositionManager } from "../src/syndicate/PositionManager.sol";
import { SyndicateFactory } from "../src/syndicate/SyndicateFactory.sol";
import { SyndicateVault } from "../src/syndicate/SyndicateVault.sol";

interface Phase5DeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys Phase 5 implementations and a factory without creating a funding round.
contract DeployPhase5 {
    Phase5DeploymentVm private constant vm =
        Phase5DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        PositionManager positionImplementation;
        SyndicateVault vaultImplementation;
        SyndicateFactory factory;
    }

    function run(
        RoleManager roles,
        ILoanRegistry loans,
        AssetRegistry assets,
        PolicyRegistry policies,
        EmergencyController emergency
    ) external returns (Deployment memory deployment) {
        vm.startBroadcast();
        deployment.positionImplementation = new PositionManager();
        deployment.vaultImplementation = new SyndicateVault();
        deployment.factory = new SyndicateFactory(
            IRoleManager(address(roles)),
            loans,
            assets,
            policies,
            emergency,
            address(deployment.vaultImplementation),
            address(deployment.positionImplementation)
        );
        roles.grantRole(
            ProtocolRoles.LOAN_FACTORY_ROLE, address(deployment.factory), type(uint64).max
        );
        vm.stopBroadcast();
        require(
            roles.hasRole(ProtocolRoles.LOAN_FACTORY_ROLE, address(deployment.factory)),
            "factory authority missing"
        );
    }
}
