// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { InterestEngine } from "../src/risk/InterestEngine.sol";
import { OracleRouter } from "../src/risk/OracleRouter.sol";
import { ScheduleEngine } from "../src/risk/ScheduleEngine.sol";
import { ServicingEngine } from "../src/risk/ServicingEngine.sol";

interface Phase4ADeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys stateless calculations and role-bound risk state without live feeds.
contract DeployPhase4A {
    Phase4ADeploymentVm private constant vm =
        Phase4ADeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        OracleRouter oracle;
        InterestEngine interest;
        ScheduleEngine schedule;
        ServicingEngine servicing;
    }

    function run(IRoleManager roles) external returns (Deployment memory deployment) {
        require(address(roles).code.length != 0, "invalid role manager");
        vm.startBroadcast();
        deployment.oracle = new OracleRouter(roles);
        deployment.interest = new InterestEngine();
        deployment.schedule = new ScheduleEngine();
        deployment.servicing = new ServicingEngine(roles);
        vm.stopBroadcast();
    }
}
