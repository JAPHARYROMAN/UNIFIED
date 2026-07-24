// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUnifiedToken } from "../interfaces/IUnifiedToken.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";

/// @notice Restricted custody primitive for one named genesis allocation mandate.
contract AllocationVault is RoleControlled {
    using SafeERC20 for IERC20;

    error InvalidBinding();
    error TokenAlreadyBound();
    error InvalidRelease();

    bytes32 public immutable allocationId;
    uint256 public immutable allocationCapacity;
    IERC20 public token;
    uint256 public released;

    event TokenBound(address indexed token, uint256 verifiedBalance);
    event AllocationReleased(
        bytes32 indexed allocationId,
        address indexed recipient,
        uint256 amount,
        bytes32 indexed authorizationReference
    );

    constructor(IRoleManager roleManager_, bytes32 allocationId_, uint256 allocationCapacity_)
        RoleControlled(roleManager_)
    {
        require(allocationId_ != bytes32(0), "allocation id is zero");
        require(allocationCapacity_ != 0, "allocation capacity is zero");
        allocationId = allocationId_;
        allocationCapacity = allocationCapacity_;
    }

    function bindToken(IUnifiedToken token_)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (address(token) != address(0)) revert TokenAlreadyBound();
        if (
            address(token_) == address(0) || token_.MAX_SUPPLY() != 1_000_000_000 ether
                || token_.balanceOf(address(this)) != allocationCapacity
        ) {
            revert InvalidBinding();
        }
        token = IERC20(address(token_));
        emit TokenBound(address(token_), allocationCapacity);
    }

    function release(address recipient, uint256 amount, bytes32 authorizationReference)
        external
        onlyRole(ProtocolRoles.TREASURY_OPERATOR_ROLE)
    {
        if (
            address(token) == address(0) || recipient == address(0) || amount == 0
                || authorizationReference == bytes32(0) || released + amount > allocationCapacity
        ) {
            revert InvalidRelease();
        }
        released += amount;
        token.safeTransfer(recipient, amount);
        emit AllocationReleased(allocationId, recipient, amount, authorizationReference);
    }
}
