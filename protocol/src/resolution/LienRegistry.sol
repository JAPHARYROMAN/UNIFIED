// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILienRegistry } from "../interfaces/phase9/ILienRegistry.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for unique senior-lien identity and atomic handoff.
contract LienRegistry is ILienRegistry {
    address private _registeredRefinanceCoordinator;
    mapping(bytes32 collateralId => Phase9Types.Lien lien_) private _liens;
    mapping(bytes32 handoffId => Phase9Types.LienHandoffResult result) private _handoffs;

    constructor(address registeredRefinanceCoordinator_) {
        _registeredRefinanceCoordinator = registeredRefinanceCoordinator_;
    }

    function registerLien(Phase9Types.Lien calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function beginHandoff(bytes32, bytes32, bytes32, uint64) external override returns (bytes32) {
        revert Phase9ImplementationNotFrozen();
    }

    function completeHandoff(bytes32, bytes32)
        external
        override
        returns (Phase9Types.LienHandoffResult memory)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function registeredRefinanceCoordinator() external view override returns (address) {
        return _registeredRefinanceCoordinator;
    }

    function lien(bytes32 collateralId) external view override returns (Phase9Types.Lien memory) {
        return _liens[collateralId];
    }

    function handoff(bytes32 handoffId)
        external
        view
        override
        returns (Phase9Types.LienHandoffResult memory)
    {
        return _handoffs[handoffId];
    }
}
