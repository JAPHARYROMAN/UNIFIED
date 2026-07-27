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
        _requireCoordinator();
        Phase9Types.Lien memory lien_ = abi.decode(msg.data[4:], (Phase9Types.Lien));

        Phase9Types.Lien memory existing = _liens[lien_.collateralId];
        if (existing.collateralId != bytes32(0)) {
            if (_sameLien(existing, lien_)) return;
            revert InvalidLien();
        }
        if (!_validInitialLien(lien_)) revert InvalidLien();

        _liens[lien_.collateralId] = lien_;
        emit LienRegistered(lien_.collateralId, lien_.seniorLoanId, lien_.lienVersion);
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
        Phase9Types.Lien memory result = _liens[collateralId];
        if (result.collateralId == bytes32(0)) revert UnknownLien(collateralId);
        return result;
    }

    function handoff(bytes32 handoffId)
        external
        view
        override
        returns (Phase9Types.LienHandoffResult memory)
    {
        return _handoffs[handoffId];
    }

    function _requireCoordinator() private view {
        if (
            _registeredRefinanceCoordinator == address(0)
                || _registeredRefinanceCoordinator.code.length == 0
                || msg.sender != _registeredRefinanceCoordinator
        ) {
            revert InvalidLien();
        }
    }

    function _validInitialLien(Phase9Types.Lien memory lien_) private view returns (bool) {
        return block.chainid == 31337 && lien_.collateralId != bytes32(0)
            && lien_.collateralManager != address(0) && lien_.vault != address(0)
            && lien_.assetId != bytes32(0) && lien_.quantity != 0
            && lien_.borrower != address(0) && lien_.seniorLoanId != bytes32(0)
            && lien_.lienVersion != 0 && lien_.status == Phase9Types.LienStatus.ACTIVE
            && lien_.pendingRefinanceId == bytes32(0)
            && lien_.pendingTargetLoanId == bytes32(0);
    }

    function _sameLien(Phase9Types.Lien memory left, Phase9Types.Lien memory right)
        private
        pure
        returns (bool)
    {
        return keccak256(abi.encode(left)) == keccak256(abi.encode(right));
    }
}
