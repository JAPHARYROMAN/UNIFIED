// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "./ProtocolRoles.sol";

/// @notice Central, auditable role directory with optional expiries.
contract RoleManager is IRoleManager {
    error InvalidAccount();
    error InvalidExpiry();
    error RoleConflict(bytes32 role, address account);
    error InvalidRoleAdministration();
    error Unauthorized(bytes32 role, address account);

    mapping(bytes32 role => mapping(address account => uint64 expiry)) private _roleExpiry;
    mapping(bytes32 role => bytes32 adminRole) private _roleAdmin;

    event RoleGranted(bytes32 indexed role, address indexed account, uint64 expiry, address sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 oldAdminRole, bytes32 newAdminRole);

    constructor(address administrator, address governanceExecutor) {
        if (
            administrator == address(0) || governanceExecutor == address(0)
                || administrator == governanceExecutor
        ) {
            revert InvalidAccount();
        }
        _roleExpiry[ProtocolRoles.DEFAULT_ADMIN_ROLE][administrator] = type(uint64).max;
        _roleExpiry[ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE][governanceExecutor] = type(uint64).max;
        _roleAdmin[ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE] = ProtocolRoles.DEFAULT_ADMIN_ROLE;
        emit RoleGranted(
            ProtocolRoles.DEFAULT_ADMIN_ROLE, administrator, type(uint64).max, msg.sender
        );
        emit RoleGranted(
            ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE, governanceExecutor, type(uint64).max, msg.sender
        );
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert Unauthorized(role, msg.sender);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        uint64 expiry = _roleExpiry[role][account];
        return expiry != 0 && (expiry == type(uint64).max || expiry >= block.timestamp);
    }

    function grantRole(bytes32 role, address account, uint64 expiry)
        external
        onlyRole(roleAdmin(role))
    {
        if (account == address(0)) revert InvalidAccount();
        if (expiry != type(uint64).max && expiry <= block.timestamp) revert InvalidExpiry();
        if (
            (role == ProtocolRoles.DEFAULT_ADMIN_ROLE
                    && hasRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE, account))
                || (role == ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE
                    && hasRole(ProtocolRoles.DEFAULT_ADMIN_ROLE, account))
        ) {
            revert RoleConflict(role, account);
        }
        _roleExpiry[role][account] = expiry;
        emit RoleGranted(role, account, expiry, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(roleAdmin(role)) {
        delete _roleExpiry[role][account];
        emit RoleRevoked(role, account, msg.sender);
    }

    function setRoleAdmin(bytes32 role, bytes32 newAdminRole)
        external
        onlyRole(ProtocolRoles.DEFAULT_ADMIN_ROLE)
    {
        if (
            (role == ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE
                    && newAdminRole != ProtocolRoles.DEFAULT_ADMIN_ROLE)
                || (role != ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE
                    && role != ProtocolRoles.DEFAULT_ADMIN_ROLE
                    && newAdminRole != ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
                || (role == ProtocolRoles.DEFAULT_ADMIN_ROLE
                    && newAdminRole != ProtocolRoles.DEFAULT_ADMIN_ROLE)
        ) {
            revert InvalidRoleAdministration();
        }
        bytes32 oldAdminRole = roleAdmin(role);
        _roleAdmin[role] = newAdminRole;
        emit RoleAdminChanged(role, oldAdminRole, newAdminRole);
    }

    function roleExpiry(bytes32 role, address account) external view returns (uint64) {
        return _roleExpiry[role][account];
    }

    function roleAdmin(bytes32 role) public view returns (bytes32) {
        bytes32 configured = _roleAdmin[role];
        if (configured != bytes32(0) || role == ProtocolRoles.DEFAULT_ADMIN_ROLE) {
            return configured;
        }
        return ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE;
    }
}
