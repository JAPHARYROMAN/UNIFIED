// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

interface IRoleManager {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account, uint64 expiry) external;
    function revokeRole(bytes32 role, address account) external;
    function roleExpiry(bytes32 role, address account) external view returns (uint64);
    function roleAdmin(bytes32 role) external view returns (bytes32);
}
