// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Marker and immutable product identity required by Phase 6B activation.
interface IUnderwrittenCreditPolicy {
    function requiresUnderwriting() external view returns (bool);

    function productHash() external view returns (bytes32);
}
