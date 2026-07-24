// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "./ProtocolRoles.sol";
import { ProtocolTypes } from "./ProtocolTypes.sol";
import { RoleControlled } from "./RoleControlled.sol";

/// @notice Immutable semantic policy versions; deprecation applies only to future bindings.
contract PolicyRegistry is RoleControlled {
    error InvalidPolicy();
    error PolicyAlreadyRegistered(bytes32 key);
    error PolicyNotFound(bytes32 key);

    struct PolicyRecord {
        ProtocolTypes.PolicyRef policy;
        bytes32 codeHash;
        bool deprecated;
    }

    mapping(bytes32 key => PolicyRecord record) private _policies;
    mapping(address implementation => bytes32 codeHash) private _codeHashes;
    mapping(bytes32 key => uint64 timestamp) public activeFrom;

    event PolicyRegistered(
        bytes32 indexed key,
        bytes32 indexed policyId,
        address indexed implementation,
        uint32 major,
        uint32 minor,
        uint32 patch,
        bytes32 codeHash,
        uint64 activeFrom
    );
    event PolicyDeprecated(bytes32 indexed key);

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function registerPolicy(ProtocolTypes.PolicyRef calldata policy, bytes32 codeHash)
        external
        onlyRole(ProtocolRoles.POLICY_REGISTRAR_ROLE)
    {
        _registerPolicy(policy, codeHash, uint64(block.timestamp));
    }

    function registerPolicyWithActivation(
        ProtocolTypes.PolicyRef calldata policy,
        bytes32 codeHash,
        uint64 activationTime
    ) external onlyRole(ProtocolRoles.POLICY_REGISTRAR_ROLE) {
        if (activationTime < block.timestamp) revert InvalidPolicy();
        _registerPolicy(policy, codeHash, activationTime);
    }

    function _registerPolicy(
        ProtocolTypes.PolicyRef calldata policy,
        bytes32 codeHash,
        uint64 activationTime
    ) private {
        if (
            policy.policyId == bytes32(0) || policy.implementation.code.length == 0
                || policy.interfaceId == bytes4(0) || policy.configurationSchemaHash == bytes32(0)
                || codeHash == bytes32(0)
        ) {
            revert InvalidPolicy();
        }
        bytes32 actualCodeHash;
        address implementation = policy.implementation;
        assembly ("memory-safe") {
            actualCodeHash := extcodehash(implementation)
        }
        if (actualCodeHash != codeHash) revert InvalidPolicy();
        try IERC165(implementation).supportsInterface(policy.interfaceId) returns (bool supported) {
            if (!supported) revert InvalidPolicy();
        } catch {
            revert InvalidPolicy();
        }

        bytes32 key = policyKey(policy.policyId, policy.major, policy.minor, policy.patch);
        if (_policies[key].policy.implementation != address(0)) {
            revert PolicyAlreadyRegistered(key);
        }
        _policies[key] = PolicyRecord({ policy: policy, codeHash: codeHash, deprecated: false });
        _codeHashes[implementation] = codeHash;
        activeFrom[key] = activationTime;
        emit PolicyRegistered(
            key,
            policy.policyId,
            implementation,
            policy.major,
            policy.minor,
            policy.patch,
            codeHash,
            activationTime
        );
    }

    function deprecatePolicy(bytes32 policyId, uint32 major, uint32 minor, uint32 patch)
        external
        onlyRole(ProtocolRoles.POLICY_REGISTRAR_ROLE)
    {
        bytes32 key = policyKey(policyId, major, minor, patch);
        if (_policies[key].policy.implementation == address(0)) revert PolicyNotFound(key);
        _policies[key].deprecated = true;
        emit PolicyDeprecated(key);
    }

    function resolvePolicy(bytes32 policyId, uint32 major, uint32 minor, uint32 patch)
        external
        view
        returns (ProtocolTypes.PolicyRef memory)
    {
        bytes32 key = policyKey(policyId, major, minor, patch);
        PolicyRecord storage record = _policies[key];
        if (record.policy.implementation == address(0)) revert PolicyNotFound(key);
        return record.policy;
    }

    function isApproved(ProtocolTypes.PolicyRef calldata policy) external view returns (bool) {
        bytes32 key = policyKey(policy.policyId, policy.major, policy.minor, policy.patch);
        PolicyRecord storage record = _policies[key];
        return !record.deprecated && activeFrom[key] <= block.timestamp
            && record.policy.implementation == policy.implementation
            && record.policy.interfaceId == policy.interfaceId
            && record.policy.configurationSchemaHash == policy.configurationSchemaHash;
    }

    function isDeprecated(bytes32 policyId, uint32 major, uint32 minor, uint32 patch)
        external
        view
        returns (bool)
    {
        return _policies[policyKey(policyId, major, minor, patch)].deprecated;
    }

    function codeHashOf(address implementation) external view returns (bytes32) {
        return _codeHashes[implementation];
    }

    function policyKey(bytes32 policyId, uint32 major, uint32 minor, uint32 patch)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(policyId, major, minor, patch));
    }
}
