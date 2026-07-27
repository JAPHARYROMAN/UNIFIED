// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ICollateralCustodyV2 } from "../interfaces/phase9/ICollateralCustodyV2.sol";
import { ILienRegistry } from "../interfaces/phase9/ILienRegistry.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for collateral custody independent of loan accounts.
contract CollateralCustodyV2 is ICollateralCustodyV2 {
    struct CustodyAssetFacts {
        address token;
        uint8 decimals;
        bytes32 runtimeCodeHash;
    }

    bytes32 private constant _CUSTODY_REENTRANCY_GUARD =
        keccak256("UNIFIED_PHASE9_CUSTODY_REENTRANCY_GUARD_V1");

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

    function recordCustody(Phase9Types.CustodyRecord calldata, bytes32) external override {
        _requireCoordinator();
        (Phase9Types.CustodyRecord memory record, bytes32 operationId) =
            abi.decode(msg.data[4:], (Phase9Types.CustodyRecord, bytes32));
        if (
            _processedCustodyOperationIds[_CUSTODY_REENTRANCY_GUARD]
                || operationId == bytes32(0) || operationId == _CUSTODY_REENTRANCY_GUARD
        ) {
            revert InvalidCustodyOperation();
        }

        Phase9Types.CustodyRecord memory stored = _custody[record.collateralId];
        if (_processedCustodyOperationIds[operationId]) {
            if (stored.collateralId == bytes32(0) || !_sameCustodyRecord(stored, record)) {
                revert CustodyOperationReplay(operationId);
            }

            _validateCustodyIdentity(record, operationId);
            _validateExactReplay(record);
            return;
        }
        if (stored.collateralId != bytes32(0)) {
            revert CustodyOperationReplay(operationId);
        }

        _processedCustodyOperationIds[_CUSTODY_REENTRANCY_GUARD] = true;
        _validateCustodyIdentity(record, operationId);
        _requireLienAbsent(record.collateralId);

        uint256 aggregateBefore = _totalExactCustody[record.assetId];
        if (record.quantity > type(uint256).max - aggregateBefore) {
            revert InvalidCustodyOperation();
        }
        uint256 aggregateAfter = aggregateBefore + record.quantity;
        uint256 borrowerBefore = _balanceOf(record.token, record.borrower);
        uint256 custodyBefore = _balanceOf(record.token, address(this));
        if (borrowerBefore < record.quantity) {
            revert InvalidCustodyOperation();
        }

        _processedCustodyOperationIds[operationId] = true;
        _custody[record.collateralId] = record;
        _totalExactCustody[record.assetId] = aggregateAfter;

        _transferFrom(record.token, record.borrower, address(this), record.quantity);

        uint256 borrowerAfter = _balanceOf(record.token, record.borrower);
        uint256 custodyAfter = _balanceOf(record.token, address(this));
        if (
            borrowerAfter > borrowerBefore || custodyAfter < custodyBefore
                || borrowerBefore - borrowerAfter != record.quantity
                || custodyAfter - custodyBefore != record.quantity || custodyAfter < aggregateAfter
        ) {
            revert InvalidCustodyOperation();
        }

        _processedCustodyOperationIds[_CUSTODY_REENTRANCY_GUARD] = false;
        emit CollateralCustodyRecorded(
            record.collateralId, record.assetId, record.borrower, record.quantity
        );
    }

    function updateCustody(bytes32, uint256, Phase9Types.CustodyStatus, bytes32) external override {
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

    function _requireCoordinator() private view {
        if (_lienRegistry.code.length == 0) revert InvalidCustodyOperation();
        try ILienRegistry(_lienRegistry).registeredRefinanceCoordinator() returns (
            address coordinator
        ) {
            if (coordinator == address(0) || msg.sender != coordinator) {
                revert InvalidCustodyOperation();
            }
        } catch {
            revert InvalidCustodyOperation();
        }
    }

    function _validateCustodyIdentity(
        Phase9Types.CustodyRecord memory record_,
        bytes32 operationId
    ) private view {
        if (
            block.chainid != 31337 || _assetRegistry.code.length == 0
                || record_.collateralId == bytes32(0) || record_.assetId == bytes32(0)
                || record_.token.code.length == 0 || record_.borrower == address(0)
                || record_.quantity == 0 || record_.status != Phase9Types.CustodyStatus.HELD
                || record_.identityHash == bytes32(0)
        ) {
            revert InvalidCustodyOperation();
        }

        CustodyAssetFacts memory asset = _resolveCustodyAsset(record_);
        if (
            record_.identityHash
                != keccak256(
                    abi.encode(
                        "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1",
                        block.chainid,
                        address(this),
                        _assetRegistry,
                        operationId,
                        record_.collateralId,
                        record_.assetId,
                        asset.token,
                        asset.runtimeCodeHash,
                        asset.decimals,
                        true,
                        record_.borrower,
                        record_.quantity
                    )
                )
        ) {
            revert InvalidCustodyOperation();
        }
    }

    function _resolveCustodyAsset(Phase9Types.CustodyRecord memory record_)
        private
        view
        returns (CustodyAssetFacts memory asset)
    {
        try IPhase9CustodyAssetSource(_assetRegistry).resolveCustodyAsset(record_.assetId) returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        ) {
            if (
                !active || !exactBalanceDelta || token != record_.token
                    || runtimeCodeHash == bytes32(0) || token.codehash != runtimeCodeHash
            ) {
                revert InvalidCustodyOperation();
            }
            asset = CustodyAssetFacts({
                token: token, decimals: decimals, runtimeCodeHash: runtimeCodeHash
            });
        } catch {
            revert InvalidCustodyOperation();
        }
    }

    function _requireLienAbsent(bytes32 collateralId) private view {
        try ILienRegistry(_lienRegistry).lien(collateralId) returns (
            Phase9Types.Lien memory existing
        ) {
            if (existing.collateralId != bytes32(0)) revert InvalidCustodyOperation();
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(ILienRegistry.UnknownLien.selector, collateralId)
                    )
            ) {
                revert InvalidCustodyOperation();
            }
        }
    }

    function _validateExactReplay(Phase9Types.CustodyRecord memory record_) private view {
        uint256 aggregate = _totalExactCustody[record_.assetId];
        if (aggregate < record_.quantity || _balanceOf(record_.token, address(this)) < aggregate) {
            revert InvalidCustodyOperation();
        }

        try ILienRegistry(_lienRegistry).lien(record_.collateralId) returns (
            Phase9Types.Lien memory existingLien
        ) {
            if (
                existingLien.collateralId != record_.collateralId
                    || existingLien.collateralManager != address(this)
                    || existingLien.vault == address(0) || existingLien.assetId != record_.assetId
                    || existingLien.quantity != record_.quantity
                    || existingLien.borrower != record_.borrower
                    || existingLien.seniorLoanId == bytes32(0) || existingLien.lienVersion == 0
                    || existingLien.status != Phase9Types.LienStatus.ACTIVE
                    || existingLien.pendingRefinanceId != bytes32(0)
                    || existingLien.pendingTargetLoanId != bytes32(0)
            ) {
                revert InvalidCustodyOperation();
            }
        } catch {
            revert InvalidCustodyOperation();
        }
    }

    function _balanceOf(address token, address account) private view returns (uint256 balance) {
        (bool success, bytes memory returned) =
            token.staticcall(abi.encodeCall(IPhase9CustodyToken.balanceOf, (account)));
        if (!success || returned.length != 32) revert InvalidCustodyOperation();
        balance = abi.decode(returned, (uint256));
    }

    function _transferFrom(address token, address from, address to, uint256 quantity) private {
        (bool success, bytes memory returned) =
            token.call(abi.encodeCall(IPhase9CustodyToken.transferFrom, (from, to, quantity)));
        if (!success || returned.length != 32 || !abi.decode(returned, (bool))) {
            revert InvalidCustodyOperation();
        }
    }

    function _sameCustodyRecord(
        Phase9Types.CustodyRecord memory left,
        Phase9Types.CustodyRecord memory right
    ) private pure returns (bool) {
        return keccak256(abi.encode(left)) == keccak256(abi.encode(right));
    }
}

interface IPhase9CustodyAssetSource {
    function resolveCustodyAsset(bytes32 assetId)
        external
        view
        returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        );
}

interface IPhase9CustodyToken {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 quantity) external returns (bool);
}
