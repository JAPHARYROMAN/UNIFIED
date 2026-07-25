// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IReservePolicy } from "../interfaces/phase9/IReservePolicy.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9ProtectionTypes } from "./Phase9ProtectionTypes.sol";

/// @notice ABI/storage freeze stub for immutable reserve-policy versions.
contract ReservePolicy is IReservePolicy {
    address private _policyRegistrar;
    mapping(bytes32 policyVersionId => Phase9ProtectionTypes.ReservePolicyVersion policy_)
        private _policies;
    mapping(bytes32 poolId => bytes32 policyVersionId) private _activePolicyHashes;
    mapping(bytes32 operationId => bool processed) private _processedOperationIds;

    constructor(address policyRegistrar_) {
        _policyRegistrar = policyRegistrar_;
    }

    function registerPolicy(Phase9ProtectionTypes.ReservePolicyVersion calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function activatePolicy(bytes32, bytes32, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function restrictPolicy(bytes32, bytes32, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function policy(bytes32 policyVersionId)
        external
        view
        override
        returns (Phase9ProtectionTypes.ReservePolicyVersion memory)
    {
        return _policies[policyVersionId];
    }

    function activePolicy(bytes32 poolId) external view override returns (bytes32) {
        return _activePolicyHashes[poolId];
    }

    function operationProcessed(bytes32 operationId) external view override returns (bool) {
        return _processedOperationIds[operationId];
    }
}
