// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ICollateralCustodyV2 } from "../interfaces/phase9/ICollateralCustodyV2.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for collateral custody independent of loan accounts.
contract CollateralCustodyV2 is ICollateralCustodyV2 {
    address private _assetRegistry;
    address private _lienRegistry;
    address private _emergencyController;
    mapping(bytes32 collateralId => Phase9Types.CustodyRecord record) private _custody;
    mapping(bytes32 assetId => uint256 quantity) private _totalExactCustody;
    mapping(bytes32 operationId => bool processed) private _processedCustodyOperationIds;

    constructor(address assetRegistry_, address lienRegistry_, address emergencyController_) {
        _assetRegistry = assetRegistry_;
        _lienRegistry = lienRegistry_;
        _emergencyController = emergencyController_;
    }

    function recordCustody(Phase9Types.CustodyRecord calldata, bytes32)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function updateCustody(bytes32, uint256, Phase9Types.CustodyStatus, bytes32)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function custody(bytes32 collateralId)
        external
        view
        override
        returns (Phase9Types.CustodyRecord memory)
    {
        return _custody[collateralId];
    }

    function totalCustody(bytes32 assetId) external view override returns (uint256) {
        return _totalExactCustody[assetId];
    }

    function operationProcessed(bytes32 operationId) external view override returns (bool) {
        return _processedCustodyOperationIds[operationId];
    }
}
