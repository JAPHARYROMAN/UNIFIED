// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IMatureExternalSettlementPolicy } from "../interfaces/IMatureExternalSettlementPolicy.sol";

/// @notice Immutable synthetic policy for a fee-free, unit-for-unit mature settlement pair.
contract FixedMatureExternalSettlementPolicy is IERC165, IMatureExternalSettlementPolicy {
    error InvalidMatureSettlementPolicy();

    bytes32 public immutable sourceAssetId;
    bytes32 public immutable targetAssetId;
    bytes32 public immutable conversionPolicyHash;
    bytes32 public immutable finalityPolicyHash;
    uint64 public immutable minimumReversalDelay;

    constructor(
        bytes32 sourceAssetId_,
        bytes32 targetAssetId_,
        bytes32 conversionPolicyHash_,
        bytes32 finalityPolicyHash_,
        uint64 minimumReversalDelay_
    ) {
        if (
            sourceAssetId_ == bytes32(0) || targetAssetId_ == bytes32(0)
                || sourceAssetId_ == targetAssetId_ || conversionPolicyHash_ == bytes32(0)
                || finalityPolicyHash_ == bytes32(0) || minimumReversalDelay_ == 0
        ) {
            revert InvalidMatureSettlementPolicy();
        }
        sourceAssetId = sourceAssetId_;
        targetAssetId = targetAssetId_;
        conversionPolicyHash = conversionPolicyHash_;
        finalityPolicyHash = finalityPolicyHash_;
        minimumReversalDelay = minimumReversalDelay_;
    }

    function permitsMatureSettlement(
        bytes32 sourceAssetId_,
        bytes32 targetAssetId_,
        bytes32 conversionPolicyHash_,
        bytes32 finalityPolicyHash_,
        uint64 finalizedAt,
        uint64 reversalDeadline
    ) external view returns (bool) {
        return sourceAssetId_ == sourceAssetId && targetAssetId_ == targetAssetId
            && conversionPolicyHash_ == conversionPolicyHash
            && finalityPolicyHash_ == finalityPolicyHash && finalizedAt != 0
            && reversalDeadline > finalizedAt
            && uint256(reversalDeadline) >= uint256(finalizedAt) + minimumReversalDelay;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IMatureExternalSettlementPolicy).interfaceId;
    }
}
