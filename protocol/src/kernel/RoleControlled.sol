// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";

abstract contract RoleControlled {
    error Unauthorized(bytes32 role, address account);

    IRoleManager public immutable roleManager;

    constructor(IRoleManager roleManager_) {
        require(address(roleManager_) != address(0), "role manager is zero");
        roleManager = roleManager_;
    }

    modifier onlyRole(bytes32 role) {
        if (!roleManager.hasRole(role, msg.sender)) {
            revert Unauthorized(role, msg.sender);
        }
        _;
    }
}
