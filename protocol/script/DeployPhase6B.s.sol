// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { ExposureManager } from "../src/identity/ExposureManager.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { CoreLoanAccount } from "../src/loan/CoreLoanAccount.sol";
import { FundingManager } from "../src/loan/FundingManager.sol";
import { OfferManager } from "../src/loan/OfferManager.sol";
import { TenderRegistry } from "../src/loan/TenderRegistry.sol";
import { UnderwrittenLoanFactory } from "../src/loan/UnderwrittenLoanFactory.sol";

interface Phase6BDeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Attaches a synthetic version-3 activation factory to Phase 3 and Phase 6A.
contract DeployPhase6B {
    Phase6BDeploymentVm private constant vm =
        Phase6BDeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        CoreLoanAccount loanImplementation;
        UnderwrittenLoanFactory loanFactory;
    }

    function run(
        RoleManager roles,
        ILoanRegistry loans,
        TenderRegistry tenders,
        OfferManager offers,
        FundingManager funding,
        AssetRegistry assets,
        PolicyRegistry policies,
        EmergencyController emergency,
        ExposureManager exposure
    ) external returns (Deployment memory deployment) {
        require(
            address(roles).code.length != 0 && address(loans).code.length != 0
                && address(tenders).code.length != 0 && address(offers).code.length != 0
                && address(funding).code.length != 0 && address(assets).code.length != 0
                && address(policies).code.length != 0 && address(emergency).code.length != 0
                && address(exposure).code.length != 0
                && address(exposure.loanRegistry()) == address(loans),
            "invalid phase 6b attachment"
        );
        vm.startBroadcast();
        deployment.loanImplementation = new CoreLoanAccount();
        deployment.loanFactory = new UnderwrittenLoanFactory(
            IRoleManager(address(roles)),
            loans,
            tenders,
            offers,
            funding,
            assets,
            policies,
            emergency,
            exposure,
            address(deployment.loanImplementation)
        );
        roles.grantRole(
            ProtocolRoles.LOAN_FACTORY_ROLE, address(deployment.loanFactory), type(uint64).max
        );
        roles.grantRole(
            ProtocolRoles.EXPOSURE_FACTORY_ROLE, address(deployment.loanFactory), type(uint64).max
        );
        vm.stopBroadcast();
        require(
            roles.hasRole(ProtocolRoles.LOAN_FACTORY_ROLE, address(deployment.loanFactory))
                && roles.hasRole(
                    ProtocolRoles.EXPOSURE_FACTORY_ROLE, address(deployment.loanFactory)
                ),
            "phase 6b authority missing"
        );
    }
}
