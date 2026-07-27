// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILienRegistry } from "../interfaces/phase9/ILienRegistry.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for unique senior-lien identity and atomic handoff.
contract LienRegistry is ILienRegistry {
    /// @dev Retained as part of the historical frozen ABI after method activation.
    error Phase9ImplementationNotFrozen();

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
        _requireCoordinator();
        (
            bytes32 collateralId,
            bytes32 refinanceId,
            bytes32 targetLoanId,
            uint64 expectedLienVersion
        ) = abi.decode(msg.data[4:], (bytes32, bytes32, bytes32, uint64));

        Phase9Types.Lien storage lien_ = _liens[collateralId];
        if (
            block.chainid != 31337 || !_validStoredLienIdentity(lien_, collateralId)
                || refinanceId == bytes32(0) || targetLoanId == bytes32(0)
                || targetLoanId == lien_.seniorLoanId || lien_.lienVersion != expectedLienVersion
                || expectedLienVersion == type(uint64).max
        ) {
            revert InvalidLienHandoff(collateralId, expectedLienVersion);
        }

        uint64 nextLienVersion = expectedLienVersion + 1;
        bytes32 handoffId = _handoffId(
            refinanceId,
            collateralId,
            lien_.seniorLoanId,
            targetLoanId,
            expectedLienVersion,
            nextLienVersion
        );
        if (handoffId == bytes32(0)) {
            revert InvalidLienHandoff(collateralId, expectedLienVersion);
        }

        Phase9Types.LienHandoffResult memory expected = Phase9Types.LienHandoffResult({
            handoffId: handoffId,
            refinanceId: refinanceId,
            collateralId: collateralId,
            oldLoanId: lien_.seniorLoanId,
            newLoanId: targetLoanId,
            priorLienVersion: expectedLienVersion,
            nextLienVersion: nextLienVersion,
            state: Phase9Types.LienHandoffState.EXECUTING,
            evidenceHash: bytes32(0)
        });
        Phase9Types.LienHandoffResult memory existing = _handoffs[handoffId];

        if (lien_.status == Phase9Types.LienStatus.HANDOFF_PENDING) {
            if (
                lien_.pendingRefinanceId != refinanceId || lien_.pendingTargetLoanId != targetLoanId
                    || !_sameHandoff(existing, expected)
            ) {
                revert InvalidLienHandoff(collateralId, expectedLienVersion);
            }
            return handoffId;
        }

        if (
            lien_.status != Phase9Types.LienStatus.ACTIVE || lien_.pendingRefinanceId != bytes32(0)
                || lien_.pendingTargetLoanId != bytes32(0) || existing.handoffId != bytes32(0)
        ) {
            revert InvalidLienHandoff(collateralId, expectedLienVersion);
        }

        lien_.status = Phase9Types.LienStatus.HANDOFF_PENDING;
        lien_.pendingRefinanceId = refinanceId;
        lien_.pendingTargetLoanId = targetLoanId;
        _handoffs[handoffId] = expected;

        emit LienHandoffPending(collateralId, refinanceId, targetLoanId);
        return handoffId;
    }

    function completeHandoff(bytes32, bytes32)
        external
        override
        returns (Phase9Types.LienHandoffResult memory)
    {
        _requireCoordinator();
        (bytes32 handoffId, bytes32 evidenceHash) = abi.decode(msg.data[4:], (bytes32, bytes32));

        Phase9Types.LienHandoffResult memory result = _handoffs[handoffId];
        if (result.handoffId == bytes32(0)) revert UnknownLienHandoff(handoffId);
        if (!_validHandoffIdentity(result, handoffId)) {
            revert InvalidLienHandoff(result.collateralId, result.priorLienVersion);
        }

        bytes32 expectedEvidenceHash = _completionEvidenceHash(result);
        Phase9Types.Lien storage lien_ = _liens[result.collateralId];
        if (result.state == Phase9Types.LienHandoffState.ACTIVE_NEW) {
            if (
                evidenceHash != expectedEvidenceHash || result.evidenceHash != expectedEvidenceHash
                    || !_matchesActiveLien(lien_, result)
            ) {
                revert InvalidLienHandoff(result.collateralId, result.priorLienVersion);
            }
            return result;
        }

        if (
            result.state != Phase9Types.LienHandoffState.EXECUTING
                || result.evidenceHash != bytes32(0) || evidenceHash != expectedEvidenceHash
                || !_matchesPendingLien(lien_, result)
        ) {
            revert InvalidLienHandoff(result.collateralId, result.priorLienVersion);
        }

        lien_.seniorLoanId = result.newLoanId;
        lien_.lienVersion = result.nextLienVersion;
        lien_.status = Phase9Types.LienStatus.ACTIVE;
        lien_.pendingRefinanceId = bytes32(0);
        lien_.pendingTargetLoanId = bytes32(0);

        result.state = Phase9Types.LienHandoffState.ACTIVE_NEW;
        result.evidenceHash = expectedEvidenceHash;
        _handoffs[handoffId] = result;

        emit LienHandoffCompleted(
            result.collateralId, result.oldLoanId, result.newLoanId, result.nextLienVersion
        );
        return result;
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
        Phase9Types.LienHandoffResult memory result = _handoffs[handoffId];
        if (result.handoffId == bytes32(0)) revert UnknownLienHandoff(handoffId);
        return result;
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
            && lien_.assetId != bytes32(0) && lien_.quantity != 0 && lien_.borrower != address(0)
            && lien_.seniorLoanId != bytes32(0) && lien_.lienVersion != 0
            && lien_.status == Phase9Types.LienStatus.ACTIVE
            && lien_.pendingRefinanceId == bytes32(0) && lien_.pendingTargetLoanId == bytes32(0);
    }

    function _validStoredLienIdentity(Phase9Types.Lien storage lien_, bytes32 collateralId)
        private
        view
        returns (bool)
    {
        return collateralId != bytes32(0) && lien_.collateralId == collateralId
            && lien_.collateralManager != address(0) && lien_.vault != address(0)
            && lien_.assetId != bytes32(0) && lien_.quantity != 0 && lien_.borrower != address(0)
            && lien_.seniorLoanId != bytes32(0) && lien_.lienVersion != 0;
    }

    function _handoffId(
        bytes32 refinanceId,
        bytes32 collateralId,
        bytes32 oldLoanId,
        bytes32 newLoanId,
        uint64 priorLienVersion,
        uint64 nextLienVersion
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_LIEN_HANDOFF_V1",
                block.chainid,
                address(this),
                refinanceId,
                collateralId,
                oldLoanId,
                newLoanId,
                priorLienVersion,
                nextLienVersion
            )
        );
    }

    function _validHandoffIdentity(Phase9Types.LienHandoffResult memory result, bytes32 handoffId)
        private
        view
        returns (bool)
    {
        return result.handoffId == handoffId && handoffId != bytes32(0)
            && result.refinanceId != bytes32(0) && result.collateralId != bytes32(0)
            && result.oldLoanId != bytes32(0) && result.newLoanId != bytes32(0)
            && result.oldLoanId != result.newLoanId && result.priorLienVersion < type(uint64).max
            && result.nextLienVersion == result.priorLienVersion + 1
            && handoffId
                == _handoffId(
                result.refinanceId,
                result.collateralId,
                result.oldLoanId,
                result.newLoanId,
                result.priorLienVersion,
                result.nextLienVersion
            );
    }

    function _completionEvidenceHash(Phase9Types.LienHandoffResult memory result)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_LIEN_HANDOFF_RESULT_V1",
                block.chainid,
                address(this),
                result.handoffId,
                result.refinanceId,
                result.collateralId,
                result.oldLoanId,
                result.newLoanId,
                result.priorLienVersion,
                result.nextLienVersion,
                Phase9Types.LienHandoffState.ACTIVE_NEW
            )
        );
    }

    function _matchesPendingLien(
        Phase9Types.Lien storage lien_,
        Phase9Types.LienHandoffResult memory result
    ) private view returns (bool) {
        return _validStoredLienIdentity(lien_, result.collateralId)
            && lien_.seniorLoanId == result.oldLoanId
            && lien_.lienVersion == result.priorLienVersion
            && lien_.status == Phase9Types.LienStatus.HANDOFF_PENDING
            && lien_.pendingRefinanceId == result.refinanceId
            && lien_.pendingTargetLoanId == result.newLoanId;
    }

    function _matchesActiveLien(
        Phase9Types.Lien storage lien_,
        Phase9Types.LienHandoffResult memory result
    ) private view returns (bool) {
        return _validStoredLienIdentity(lien_, result.collateralId)
            && lien_.seniorLoanId == result.newLoanId && lien_.lienVersion == result.nextLienVersion
            && lien_.status == Phase9Types.LienStatus.ACTIVE
            && lien_.pendingRefinanceId == bytes32(0) && lien_.pendingTargetLoanId == bytes32(0);
    }

    function _sameHandoff(
        Phase9Types.LienHandoffResult memory left,
        Phase9Types.LienHandoffResult memory right
    ) private pure returns (bool) {
        return keccak256(abi.encode(left)) == keccak256(abi.encode(right));
    }

    function _sameLien(Phase9Types.Lien memory left, Phase9Types.Lien memory right)
        private
        pure
        returns (bool)
    {
        return keccak256(abi.encode(left)) == keccak256(abi.encode(right));
    }
}
