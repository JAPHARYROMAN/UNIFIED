// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IUnifiedToken } from "../interfaces/IUnifiedToken.sol";
import { IUFTBurner } from "../interfaces/IUFTBurner.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";

/// @notice Burns only canonical UFT already held by this contract.
contract UFTBurner is IUFTBurner, RoleControlled {
    error InvalidBurn();

    IUnifiedToken public immutable uft;
    bytes32 public immutable uftAssetId;
    uint256 public cumulativeBurned;

    event UFTBurned(
        uint256 amount,
        bytes32 indexed sourceRevenuePeriod,
        bytes32 indexed sourceAsset,
        bytes32 indexed executionReference,
        uint256 cumulativeBurnedSupply,
        uint256 resultingTotalSupply
    );

    constructor(IRoleManager roleManager_, IUnifiedToken uft_, bytes32 uftAssetId_)
        RoleControlled(roleManager_)
    {
        require(address(uft_) != address(0) && uftAssetId_ != bytes32(0), "invalid burner");
        uft = uft_;
        uftAssetId = uftAssetId_;
    }

    function burnFromRevenue(uint256 amount, bytes32 revenueEpoch, bytes32 journalRef)
        external
        onlyRole(ProtocolRoles.TREASURY_OPERATOR_ROLE)
    {
        if (
            amount == 0 || revenueEpoch == bytes32(0) || journalRef == bytes32(0)
                || uft.balanceOf(address(this)) < amount
        ) {
            revert InvalidBurn();
        }
        uft.burn(amount);
        cumulativeBurned += amount;
        emit UFTBurned(
            amount, revenueEpoch, uftAssetId, journalRef, cumulativeBurned, uft.totalSupply()
        );
    }
}
