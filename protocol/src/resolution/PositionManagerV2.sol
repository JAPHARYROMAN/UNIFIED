// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPositionManagerV2 } from "../interfaces/phase9/IPositionManagerV2.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
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
    bool private _initialized;

    function initialize(bytes32, address, address) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function registerTranche(Phase9Types.Tranche calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function issuePosition(Phase9Types.Position calldata) external override {
        revert Phase9ImplementationNotFrozen();
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
}
