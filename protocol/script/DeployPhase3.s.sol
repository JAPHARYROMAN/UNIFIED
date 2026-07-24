// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { CoreLoanAccount } from "../src/loan/CoreLoanAccount.sol";
import { CoreLoanFactory } from "../src/loan/CoreLoanFactory.sol";
import { FundingManager } from "../src/loan/FundingManager.sol";
import { OfferManager } from "../src/loan/OfferManager.sol";
import { TenderRegistry } from "../src/loan/TenderRegistry.sol";

interface Phase3DeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Reproducibly attaches the Phase 3 loan spine to an existing Phase 2 kernel.
contract DeployPhase3 {
    Phase3DeploymentVm private constant vm =
        Phase3DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        TenderRegistry tenders;
        OfferManager offers;
        FundingManager funding;
        CoreLoanAccount loanImplementation;
        CoreLoanFactory loanFactory;
    }

    function run(
        RoleManager roles,
        ILoanRegistry loanRegistry,
        AssetRegistry assets,
        PolicyRegistry policies,
        EmergencyController emergency,
        address feeReceiver
    ) external returns (Deployment memory deployment) {
        require(
            address(roles).code.length != 0 && address(loanRegistry).code.length != 0
                && address(assets).code.length != 0 && address(policies).code.length != 0
                && address(emergency).code.length != 0 && feeReceiver != address(0),
            "invalid phase 2 attachment"
        );

        vm.startBroadcast();
        deployment.tenders = new TenderRegistry(IRoleManager(address(roles)));
        deployment.offers = new OfferManager(IRoleManager(address(roles)));
        deployment.funding = new FundingManager(IRoleManager(address(roles)), assets, feeReceiver);
        deployment.loanImplementation = new CoreLoanAccount();
        deployment.loanFactory = new CoreLoanFactory(
            IRoleManager(address(roles)),
            loanRegistry,
            deployment.tenders,
            deployment.offers,
            deployment.funding,
            assets,
            policies,
            emergency,
            address(deployment.loanImplementation)
        );
        roles.grantRole(
            ProtocolRoles.LOAN_FACTORY_ROLE, address(deployment.loanFactory), type(uint64).max
        );
        require(
            roles.hasRole(ProtocolRoles.LOAN_FACTORY_ROLE, address(deployment.loanFactory)),
            "factory authority missing"
        );
        vm.stopBroadcast();
    }
}
