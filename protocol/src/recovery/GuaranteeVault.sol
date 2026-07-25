// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IGuaranteeVault } from "../interfaces/phase9/IGuaranteeVault.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9RecoveryTypes } from "./Phase9RecoveryTypes.sol";

/// @notice ABI/storage freeze stub for capped synthetic guarantee commitments.
contract GuaranteeVault is IGuaranteeVault {
    address private _assetRegistry;
    address private _settlementToken;
    address private _authorizedRecoveryManager;
    mapping(bytes32 guaranteeId => Phase9RecoveryTypes.Guarantee guarantee_) private _guarantees;
    mapping(bytes32 receiptId => bool processed) private _processedReceiptIds;

    constructor(
        address assetRegistry_,
        address settlementToken_,
        address authorizedRecoveryManager_
    ) {
        _assetRegistry = assetRegistry_;
        _settlementToken = settlementToken_;
        _authorizedRecoveryManager = authorizedRecoveryManager_;
    }

    function registerGuarantee(Phase9RecoveryTypes.Guarantee calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function recordGuaranteeReceipt(bytes32, bytes32, uint256, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function assetRegistry() external view override returns (address) {
        return _assetRegistry;
    }

    function settlementToken() external view override returns (address) {
        return _settlementToken;
    }

    function authorizedRecoveryManager() external view override returns (address) {
        return _authorizedRecoveryManager;
    }

    function guarantee(bytes32 guaranteeId)
        external
        view
        override
        returns (Phase9RecoveryTypes.Guarantee memory)
    {
        return _guarantees[guaranteeId];
    }

    function receiptProcessed(bytes32 receiptId) external view override returns (bool) {
        return _processedReceiptIds[receiptId];
    }
}
