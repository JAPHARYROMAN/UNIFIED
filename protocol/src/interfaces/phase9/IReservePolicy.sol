// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9ProtectionTypes } from "../../protection/Phase9ProtectionTypes.sol";

interface IReservePolicy {
    error InvalidReservePolicy();
    error ReservePolicyAlreadyRegistered(bytes32 policyVersionId);
    error UnknownReservePolicy(bytes32 policyVersionId);

    event ReservePolicyRegistered(
        bytes32 indexed policyVersionId,
        bytes32 indexed poolId,
        bytes32 indexed contentHash,
        uint64 effectiveAt
    );
    event ReservePolicyActivated(bytes32 indexed poolId, bytes32 indexed policyVersionId);
    event ReservePolicyRestricted(bytes32 indexed policyVersionId, bytes32 indexed reasonCode);

    function registerPolicy(Phase9ProtectionTypes.ReservePolicyVersion calldata policy_) external;
    function activatePolicy(bytes32 poolId, bytes32 policyVersionId, bytes32 operationId) external;
    function restrictPolicy(bytes32 policyVersionId, bytes32 reasonCode, bytes32 operationId)
        external;
    function policy(bytes32 policyVersionId)
        external
        view
        returns (Phase9ProtectionTypes.ReservePolicyVersion memory);
    function activePolicy(bytes32 poolId) external view returns (bytes32);
    function operationProcessed(bytes32 operationId) external view returns (bool);
}
