// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRecoveryManager } from "../interfaces/phase9/IRecoveryManager.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9RecoveryTypes } from "./Phase9RecoveryTypes.sol";

/// @notice ABI/storage freeze stub for unique loss sources, write-off, and later recovery.
contract RecoveryManager is IRecoveryManager {
    address private _assetRegistry;
    address private _settlementToken;
    address private _authorizedReceiptManager;
    mapping(bytes32 lossId => Phase9RecoveryTypes.LossRecord record) private _losses;
    mapping(bytes32 recoverySourceId => Phase9RecoveryTypes.RecoverySourceEvidence source) private
        _recoverySources;
    mapping(
        bytes32 lossId
            => mapping(
            bytes32 entitlementId => Phase9RecoveryTypes.RecoveryEntitlement entitlement_
        )
    ) private _entitlements;
    mapping(bytes32 allocationId => Phase9RecoveryTypes.RecoveryAllocation allocation_) private
        _allocations;
    mapping(bytes32 writeoffId => Phase9RecoveryTypes.WriteOffEvidence writeoff) private _writeOffs;
    mapping(bytes32 sourceId => bool processed) private _processedSourceIds;
    mapping(bytes32 operationId => bool processed) private _processedOperationIds;

    constructor(
        address assetRegistry_,
        address settlementToken_,
        address authorizedReceiptManager_
    ) {
        _assetRegistry = assetRegistry_;
        _settlementToken = settlementToken_;
        _authorizedReceiptManager = authorizedReceiptManager_;
    }

    function openLoss(bytes32, Phase9RecoveryTypes.LossRecord calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function recordRecoverySource(Phase9RecoveryTypes.RecoverySourceEvidence calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function setEntitlement(Phase9RecoveryTypes.RecoveryEntitlement calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function allocateRecovery(Phase9RecoveryTypes.RecoveryAllocation calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function recognizeWriteOff(Phase9RecoveryTypes.WriteOffEvidence calldata, bytes32)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function assetRegistry() external view override returns (address) {
        return _assetRegistry;
    }

    function settlementToken() external view override returns (address) {
        return _settlementToken;
    }

    function authorizedReceiptManager() external view override returns (address) {
        return _authorizedReceiptManager;
    }

    function loss(bytes32 lossId)
        external
        view
        override
        returns (Phase9RecoveryTypes.LossRecord memory)
    {
        return _losses[lossId];
    }

    function recoverySource(bytes32 recoverySourceId)
        external
        view
        override
        returns (Phase9RecoveryTypes.RecoverySourceEvidence memory)
    {
        return _recoverySources[recoverySourceId];
    }

    function entitlement(bytes32 lossId, bytes32 entitlementId)
        external
        view
        override
        returns (Phase9RecoveryTypes.RecoveryEntitlement memory)
    {
        return _entitlements[lossId][entitlementId];
    }

    function allocation(bytes32 allocationId)
        external
        view
        override
        returns (Phase9RecoveryTypes.RecoveryAllocation memory)
    {
        return _allocations[allocationId];
    }

    function writeOff(bytes32 writeoffId)
        external
        view
        override
        returns (Phase9RecoveryTypes.WriteOffEvidence memory)
    {
        return _writeOffs[writeoffId];
    }

    function operationProcessed(bytes32 operationId) external view override returns (bool) {
        return _processedOperationIds[operationId];
    }
}
