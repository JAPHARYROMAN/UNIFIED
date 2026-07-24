// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { CollateralManager } from "../src/collateral/CollateralManager.sol";
import { LiquidationEngine } from "../src/collateral/LiquidationEngine.sol";
import { OracleRouter } from "../src/risk/OracleRouter.sol";
import { ServicingEngine } from "../src/risk/ServicingEngine.sol";

interface Phase4B2DeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys liquidation logic without performing its one-time governance binding.
contract DeployPhase4B2 {
    Phase4B2DeploymentVm private constant vm =
        Phase4B2DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(
        IRoleManager roles,
        ILoanRegistry loans,
        CollateralManager collateral,
        ServicingEngine servicing,
        OracleRouter oracle,
        AssetRegistry assets,
        address treasury
    ) external returns (LiquidationEngine engine) {
        require(collateral.liquidationEngine() == address(0), "engine already bound");
        vm.startBroadcast();
        engine =
            new LiquidationEngine(roles, loans, collateral, servicing, oracle, assets, treasury);
        vm.stopBroadcast();
        require(collateral.liquidationEngine() == address(0), "binding requires governance");
    }
}
