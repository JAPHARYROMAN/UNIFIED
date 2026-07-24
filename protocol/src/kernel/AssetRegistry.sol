// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "./ProtocolRoles.sol";
import { RoleControlled } from "./RoleControlled.sol";

/// @notice Append-only asset identities with future-use activation status.
contract AssetRegistry is RoleControlled {
    error InvalidAsset();
    error AssetAlreadyRegistered(bytes32 assetId);
    error UnknownAsset(bytes32 assetId);

    struct AssetRecord {
        address token;
        uint8 decimals;
        bool active;
        bytes32 metadataHash;
    }

    mapping(bytes32 assetId => AssetRecord asset) private _assets;

    event AssetRegistered(
        bytes32 indexed assetId, address indexed token, uint8 decimals, bytes32 indexed metadataHash
    );
    event AssetActivationChanged(bytes32 indexed assetId, bool active);

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function registerAsset(bytes32 assetId, address token, uint8 decimals, bytes32 metadataHash)
        external
        onlyRole(ProtocolRoles.ASSET_REGISTRAR_ROLE)
    {
        if (
            assetId == bytes32(0) || token == address(0) || token.code.length == 0
                || metadataHash == bytes32(0)
        ) {
            revert InvalidAsset();
        }
        if (_assets[assetId].token != address(0)) revert AssetAlreadyRegistered(assetId);
        _assets[assetId] = AssetRecord({
            token: token, decimals: decimals, active: true, metadataHash: metadataHash
        });
        emit AssetRegistered(assetId, token, decimals, metadataHash);
    }

    function setActive(bytes32 assetId, bool active)
        external
        onlyRole(ProtocolRoles.ASSET_REGISTRAR_ROLE)
    {
        if (_assets[assetId].token == address(0)) revert UnknownAsset(assetId);
        _assets[assetId].active = active;
        emit AssetActivationChanged(assetId, active);
    }

    function resolve(bytes32 assetId) external view returns (AssetRecord memory) {
        AssetRecord memory asset = _assets[assetId];
        if (asset.token == address(0)) revert UnknownAsset(assetId);
        return asset;
    }

    function isActive(bytes32 assetId) external view returns (bool) {
        return _assets[assetId].active;
    }
}
