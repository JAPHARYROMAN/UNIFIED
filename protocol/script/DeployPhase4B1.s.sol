// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { CollateralManager } from "../src/collateral/CollateralManager.sol";

interface Phase4B1DeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys custody with no assets, debt ceiling, or liquidation engine configured.
contract DeployPhase4B1 {
    Phase4B1DeploymentVm private constant vm =
        Phase4B1DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(
        IRoleManager roles,
        ILoanRegistry loans,
        AssetRegistry assets,
        bytes32 uftAssetId,
        IERC20 uft
    ) external returns (CollateralManager manager) {
        vm.startBroadcast();
        manager = new CollateralManager(roles, loans, assets, uftAssetId, uft);
        vm.stopBroadcast();
        require(manager.liquidationEngine() == address(0), "liquidation must remain unbound");
    }
}
