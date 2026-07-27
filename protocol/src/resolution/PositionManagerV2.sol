// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPhase9LoanAccount } from "../interfaces/phase9/IPhase9LoanAccount.sol";
import { IPositionManagerV2 } from "../interfaces/phase9/IPositionManagerV2.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9LocalSyntheticToken } from "../token/Phase9LocalSyntheticToken.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for version-9 lender positions and voting snapshots.
contract PositionManagerV2 is IPositionManagerV2 {
    bytes32 private _loanId;
    address private _loanAccount;
    IERC20 private _settlementToken;
    mapping(bytes32 trancheId => Phase9Types.Tranche tranche_) private _tranches;
    bytes32[] private _trancheIds;
    mapping(bytes32 positionId => Phase9Types.Position position_) private _positions;
    bytes32[] private _positionIds;
    mapping(bytes32 positionId => Phase9Types.Checkpoint[] checkpoints) private _ownerCheckpoints;
    mapping(bytes32 positionId => Phase9Types.Checkpoint[] checkpoints) private
        _votingPowerCheckpoints;
    mapping(bytes32 positionId => Phase9Types.Checkpoint[] checkpoints) private _claimCheckpoints;
    Phase9Types.Checkpoint[] private _totalVotingPowerCheckpoints;
    mapping(bytes32 snapshotId => Phase9Types.PositionRightSnapshot snapshot_) private _snapshots;
    mapping(bytes32 snapshotId => mapping(bytes32 positionId => bool consumed)) private
        _consumedVoteRights;
    bool private _initialized = true;

    function initialize(bytes32, address, address) external override {
        (bytes32 loanId_, address loanAccount_, address settlementToken_) =
            abi.decode(msg.data[4:], (bytes32, address, address));
        if (
            _initialized || block.chainid != 31337 || loanId_ == bytes32(0)
                || loanAccount_ == address(0) || loanAccount_.code.length == 0
                || settlementToken_ == address(0)
                || settlementToken_.codehash
                    != keccak256(type(Phase9LocalSyntheticToken).runtimeCode)
        ) {
            revert InvalidPositionOperation();
        }

        Phase9Types.LoanConfiguration memory configuration_ =
            _accountConfiguration(loanAccount_);
        if (
            configuration_.factory != msg.sender || configuration_.loanId != loanId_
                || configuration_.positionManager != address(this)
                || configuration_.settlementToken != settlementToken_
        ) {
            revert InvalidPositionOperation();
        }

        _initialized = true;
        _loanId = loanId_;
        _loanAccount = loanAccount_;
        _settlementToken = IERC20(settlementToken_);

        emit PositionManagerInitialized(loanId_, loanAccount_);
    }

    function registerTranche(Phase9Types.Tranche calldata) external override {
        Phase9Types.Tranche memory tranche_ =
            abi.decode(msg.data[4:], (Phase9Types.Tranche));
        _requireCoordinator();

        bytes32 trancheId = tranche_.trancheId;
        Phase9Types.Tranche storage existing = _tranches[trancheId];
        if (existing.trancheId != bytes32(0)) {
            if (keccak256(abi.encode(existing)) != keccak256(abi.encode(tranche_))) {
                revert InvalidPositionOperation();
            }
            return;
        }

        uint256 trancheCount = _trancheIds.length;
        if (
            trancheId == bytes32(0) || trancheCount >= 8 || tranche_.originalClaim == 0
                || tranche_.outstandingClaim == 0
                || tranche_.originalClaim != tranche_.outstandingClaim
                || tranche_.configurationHash == bytes32(0)
                || (trancheCount != 0
                    && uint256(trancheId) <= uint256(_trancheIds[trancheCount - 1]))
        ) {
            revert InvalidPositionOperation();
        }

        _tranches[trancheId] = tranche_;
        _trancheIds.push(trancheId);
        emit TrancheRegistered(trancheId, tranche_.priority, tranche_.originalClaim);
    }

    function issuePosition(Phase9Types.Position calldata) external override {
        Phase9Types.Position memory position_ =
            abi.decode(msg.data[4:], (Phase9Types.Position));
        _requireCoordinator();

        bytes32 positionId = position_.positionId;
        Phase9Types.Position storage existing = _positions[positionId];
        if (existing.positionId != bytes32(0)) {
            if (keccak256(abi.encode(existing)) != keccak256(abi.encode(position_))) {
                revert InvalidPositionOperation();
            }
            return;
        }

        uint256 positionCount = _positionIds.length;
        if (
            positionId == bytes32(0) || positionCount >= 32
                || position_.trancheId == bytes32(0)
                || _tranches[position_.trancheId].trancheId == bytes32(0)
                || position_.owner == address(0) || position_.claim == 0
                || position_.state != Phase9Types.PositionState.ACTIVE
                || (positionCount != 0
                    && uint256(positionId) <= uint256(_positionIds[positionCount - 1]))
                || !_claimFitsTranche(position_.trancheId, position_.claim)
        ) {
            revert InvalidPositionOperation();
        }
        if (block.number > type(uint64).max) revert InvalidPositionOperation();

        uint256 priorTotalVotingPower = _latestValue(_totalVotingPowerCheckpoints);
        if (position_.votingPower > type(uint256).max - priorTotalVotingPower) {
            revert InvalidPositionOperation();
        }

        _positions[positionId] = position_;
        _positionIds.push(positionId);
        _writeOwnerCheckpoint(_ownerCheckpoints[positionId], position_.owner);
        _writeValueCheckpoint(_votingPowerCheckpoints[positionId], position_.votingPower);
        _writeValueCheckpoint(_claimCheckpoints[positionId], position_.claim);
        _writeValueCheckpoint(
            _totalVotingPowerCheckpoints, priorTotalVotingPower + position_.votingPower
        );

        emit PositionIssued(positionId, position_.trancheId, position_.owner, position_.claim);
    }

    function transferPosition(bytes32, address) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function createSnapshot(Phase9Types.PositionRightSnapshot calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function consumeVotingRight(bytes32, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function tranche(bytes32 trancheId)
        external
        view
        override
        returns (Phase9Types.Tranche memory)
    {
        return _tranches[trancheId];
    }

    function trancheIds() external view override returns (bytes32[] memory) {
        return _trancheIds;
    }

    function position(bytes32 positionId)
        external
        view
        override
        returns (Phase9Types.Position memory)
    {
        return _positions[positionId];
    }

    function positionIds() external view override returns (bytes32[] memory) {
        return _positionIds;
    }

    function snapshot(bytes32 snapshotId)
        external
        view
        override
        returns (Phase9Types.PositionRightSnapshot memory)
    {
        return _snapshots[snapshotId];
    }

    function votingRightConsumed(bytes32 snapshotId, bytes32 positionId)
        external
        view
        override
        returns (bool)
    {
        return _consumedVoteRights[snapshotId][positionId];
    }

    function positionOwnerAt(bytes32 positionId, uint64 blockNumber)
        external
        view
        override
        returns (address)
    {
        return _ownerAt(_ownerCheckpoints[positionId], blockNumber);
    }

    function positionVotingPowerAt(bytes32 positionId, uint64 blockNumber)
        external
        view
        override
        returns (uint256)
    {
        return _valueAt(_votingPowerCheckpoints[positionId], blockNumber);
    }

    function positionClaimAt(bytes32 positionId, uint64 blockNumber)
        external
        view
        override
        returns (uint256)
    {
        return _valueAt(_claimCheckpoints[positionId], blockNumber);
    }

    function totalVotingPowerAt(uint64 blockNumber) external view override returns (uint256) {
        return _valueAt(_totalVotingPowerCheckpoints, blockNumber);
    }

    function _ownerAt(Phase9Types.Checkpoint[] storage checkpoints, uint64 blockNumber)
        private
        view
        returns (address)
    {
        for (uint256 index = checkpoints.length; index > 0; --index) {
            if (checkpoints[index - 1].blockNumber <= blockNumber) {
                return checkpoints[index - 1].owner;
            }
        }
        return address(0);
    }

    function _valueAt(Phase9Types.Checkpoint[] storage checkpoints, uint64 blockNumber)
        private
        view
        returns (uint256)
    {
        for (uint256 index = checkpoints.length; index > 0; --index) {
            if (checkpoints[index - 1].blockNumber <= blockNumber) {
                return checkpoints[index - 1].value;
            }
        }
        return 0;
    }

    function _requireCoordinator() private view {
        if (!_initialized || _loanAccount == address(0) || _loanAccount.code.length == 0) {
            revert InvalidPositionOperation();
        }

        Phase9Types.LoanConfiguration memory configuration_ =
            _accountConfiguration(_loanAccount);
        if (
            configuration_.refinanceCoordinator != msg.sender
                || configuration_.positionManager != address(this)
                || configuration_.loanId != _loanId
                || configuration_.settlementToken != address(_settlementToken)
                || address(_settlementToken).codehash
                    != keccak256(type(Phase9LocalSyntheticToken).runtimeCode)
        ) {
            revert InvalidPositionOperation();
        }
    }

    function _accountConfiguration(address loanAccount_)
        private
        view
        returns (Phase9Types.LoanConfiguration memory configuration_)
    {
        try IPhase9LoanAccount(loanAccount_).configuration() returns (
            Phase9Types.LoanConfiguration memory resolved
        ) {
            configuration_ = resolved;
        } catch {
            revert InvalidPositionOperation();
        }
    }

    function _claimFitsTranche(bytes32 trancheId, uint256 additionalClaim)
        private
        view
        returns (bool)
    {
        uint256 allocated;
        uint256 positionCount = _positionIds.length;
        for (uint256 index = 0; index < positionCount; ++index) {
            Phase9Types.Position storage existing = _positions[_positionIds[index]];
            if (existing.trancheId == trancheId) {
                if (existing.claim > type(uint256).max - allocated) return false;
                allocated += existing.claim;
            }
        }
        if (additionalClaim > type(uint256).max - allocated) return false;
        return allocated + additionalClaim <= _tranches[trancheId].outstandingClaim;
    }

    function _latestValue(Phase9Types.Checkpoint[] storage checkpoints)
        private
        view
        returns (uint256)
    {
        uint256 length = checkpoints.length;
        return length == 0 ? 0 : checkpoints[length - 1].value;
    }

    function _writeOwnerCheckpoint(
        Phase9Types.Checkpoint[] storage checkpoints,
        address owner
    ) private {
        uint64 currentBlock = uint64(block.number);
        Phase9Types.Checkpoint memory checkpoint = Phase9Types.Checkpoint({
            blockNumber: currentBlock, value: 0, owner: owner
        });
        uint256 length = checkpoints.length;
        if (length != 0 && checkpoints[length - 1].blockNumber == currentBlock) {
            checkpoints[length - 1] = checkpoint;
        } else {
            checkpoints.push(checkpoint);
        }
    }

    function _writeValueCheckpoint(
        Phase9Types.Checkpoint[] storage checkpoints,
        uint256 value
    ) private {
        uint64 currentBlock = uint64(block.number);
        Phase9Types.Checkpoint memory checkpoint = Phase9Types.Checkpoint({
            blockNumber: currentBlock, value: value, owner: address(0)
        });
        uint256 length = checkpoints.length;
        if (length != 0 && checkpoints[length - 1].blockNumber == currentBlock) {
            checkpoints[length - 1] = checkpoint;
        } else {
            checkpoints.push(checkpoint);
        }
    }
}
