// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";

/// @notice Append-only chain and coordinator identities for cross-chain routes.
contract ChainRegistry is RoleControlled {
    error InvalidChain();
    error UnknownChainVersion(uint256 chainId, uint32 version);
    error ChainVersionAlreadyDeprecated(uint256 chainId, uint32 version);

    struct ChainVersion {
        uint256 chainId;
        uint32 version;
        address coordinator;
        address finalityVerifier;
        bytes32 coordinatorCodeHash;
        bytes32 finalityVerifierCodeHash;
        bytes32 configurationHash;
        uint64 activatedAt;
        uint64 deprecatedAt;
        CrossChainTypes.RegistryStatus status;
    }

    mapping(uint256 chainId => uint32 version) public latestVersion;
    mapping(uint256 chainId => mapping(uint32 version => ChainVersion record)) private _chains;
    uint256 public immutable localChainId;

    event ChainVersionRegistered(
        uint256 indexed chainId,
        uint32 indexed version,
        address indexed coordinator,
        address finalityVerifier,
        bytes32 coordinatorCodeHash,
        bytes32 finalityVerifierCodeHash,
        bytes32 configurationHash,
        uint64 activatedAt
    );
    event ChainVersionDeprecated(
        uint256 indexed chainId, uint32 indexed version, uint64 deprecatedAt
    );

    constructor(IRoleManager roleManager_, uint256 localChainId_) RoleControlled(roleManager_) {
        if (localChainId_ == 0) revert InvalidChain();
        localChainId = localChainId_;
    }

    function registerChain(
        uint256 chainId,
        address coordinator,
        address finalityVerifier,
        bytes32 coordinatorCodeHash,
        bytes32 finalityVerifierCodeHash,
        bytes32 configurationHash,
        uint64 activatedAt
    ) external onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE) returns (uint32 version) {
        if (
            chainId == 0 || coordinator == address(0) || finalityVerifier == address(0)
                || coordinatorCodeHash == bytes32(0) || finalityVerifierCodeHash == bytes32(0)
                || configurationHash == bytes32(0) || activatedAt < block.timestamp
        ) {
            revert InvalidChain();
        }
        if (
            chainId == localChainId
                && (coordinator.codehash != coordinatorCodeHash
                    || finalityVerifier.codehash != finalityVerifierCodeHash)
        ) {
            revert InvalidChain();
        }
        version = latestVersion[chainId] + 1;
        latestVersion[chainId] = version;
        _chains[chainId][version] = ChainVersion({
            chainId: chainId,
            version: version,
            coordinator: coordinator,
            finalityVerifier: finalityVerifier,
            coordinatorCodeHash: coordinatorCodeHash,
            finalityVerifierCodeHash: finalityVerifierCodeHash,
            configurationHash: configurationHash,
            activatedAt: activatedAt,
            deprecatedAt: 0,
            status: CrossChainTypes.RegistryStatus.ACTIVE
        });
        emit ChainVersionRegistered(
            chainId,
            version,
            coordinator,
            finalityVerifier,
            coordinatorCodeHash,
            finalityVerifierCodeHash,
            configurationHash,
            activatedAt
        );
    }

    function deprecateChain(uint256 chainId, uint32 version)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        ChainVersion storage record = _chains[chainId][version];
        if (record.status == CrossChainTypes.RegistryStatus.NONE) {
            revert UnknownChainVersion(chainId, version);
        }
        if (record.status == CrossChainTypes.RegistryStatus.DEPRECATED) {
            revert ChainVersionAlreadyDeprecated(chainId, version);
        }
        record.status = CrossChainTypes.RegistryStatus.DEPRECATED;
        record.deprecatedAt = uint64(block.timestamp);
        emit ChainVersionDeprecated(chainId, version, record.deprecatedAt);
    }

    function chainVersion(uint256 chainId, uint32 version)
        external
        view
        returns (ChainVersion memory)
    {
        ChainVersion memory record = _chains[chainId][version];
        if (record.status == CrossChainTypes.RegistryStatus.NONE) {
            revert UnknownChainVersion(chainId, version);
        }
        return record;
    }

    function isKnown(uint256 chainId, uint32 version, address coordinator, address verifier)
        external
        view
        returns (bool)
    {
        ChainVersion storage record = _chains[chainId][version];
        return record.status != CrossChainTypes.RegistryStatus.NONE
            && record.coordinator == coordinator && record.finalityVerifier == verifier;
    }

    function isActiveVersion(uint256 chainId, uint32 version) external view returns (bool) {
        ChainVersion storage record = _chains[chainId][version];
        return record.status == CrossChainTypes.RegistryStatus.ACTIVE
            && record.activatedAt <= block.timestamp;
    }

    function wasActiveAt(uint256 chainId, uint32 version, uint64 timestamp)
        external
        view
        returns (bool)
    {
        ChainVersion storage record = _chains[chainId][version];
        return record.status != CrossChainTypes.RegistryStatus.NONE
            && record.activatedAt <= timestamp
            && (record.deprecatedAt == 0 || timestamp < record.deprecatedAt);
    }
}
