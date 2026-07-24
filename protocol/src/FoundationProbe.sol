// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { FoundationTypes } from "./generated/FoundationTypes.sol";

/// @notice Compile-tested boundary probe for generated foundation types.
/// @dev This contract carries no funds, authority, loan behavior, or UFT mint path.
contract FoundationProbe {
    function moneyHash(FoundationTypes.Money calldata amount) external pure returns (bytes32) {
        return keccak256(abi.encode(amount.assetId.value, amount.units));
    }

    function policyHash(FoundationTypes.PolicyReference calldata policy)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(policy.policyId, policy.version, policy.contentHash));
    }
}

