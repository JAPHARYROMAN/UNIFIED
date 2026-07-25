// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Immutable policy boundary for mature, same-denomination external settlement.
interface IMatureExternalSettlementPolicy {
    function permitsMatureSettlement(
        bytes32 sourceAssetId,
        bytes32 targetAssetId,
        bytes32 conversionPolicyHash,
        bytes32 finalityPolicyHash,
        uint64 finalizedAt,
        uint64 reversalDeadline
    ) external view returns (bool);
}
