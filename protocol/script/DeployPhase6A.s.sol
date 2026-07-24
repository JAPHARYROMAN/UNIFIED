// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { CredentialRegistry } from "../src/identity/CredentialRegistry.sol";
import { CreditDecisionRegistry } from "../src/identity/CreditDecisionRegistry.sol";
import { ExposureManager } from "../src/identity/ExposureManager.sol";
import { IdentityProviderRegistry } from "../src/identity/IdentityProviderRegistry.sol";

interface Phase6ADeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys Phase 6A registries without providers, credentials, or decisions.
contract DeployPhase6A {
    Phase6ADeploymentVm private constant vm =
        Phase6ADeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        IdentityProviderRegistry providers;
        CredentialRegistry credentials;
        CreditDecisionRegistry decisions;
        ExposureManager exposure;
    }

    function run(RoleManager roles, ILoanRegistry loans)
        external
        returns (Deployment memory deployment)
    {
        vm.startBroadcast();
        deployment.providers = new IdentityProviderRegistry(IRoleManager(address(roles)));
        deployment.credentials =
            new CredentialRegistry(IRoleManager(address(roles)), deployment.providers);
        deployment.decisions =
            new CreditDecisionRegistry(IRoleManager(address(roles)), deployment.credentials);
        deployment.exposure =
            new ExposureManager(IRoleManager(address(roles)), deployment.decisions, loans);
        vm.stopBroadcast();
        require(
            address(deployment.exposure.decisionRegistry()) == address(deployment.decisions),
            "decision boundary mismatch"
        );
        require(
            address(deployment.decisions.credentialRegistry()) == address(deployment.credentials),
            "credential boundary mismatch"
        );
    }
}
