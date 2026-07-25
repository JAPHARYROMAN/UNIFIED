// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9Types } from "../../resolution/Phase9Types.sol";

interface IPositionManagerV2 {
    error InvalidPositionOperation();
    error UnknownPosition(bytes32 positionId);
    error VotingRightAlreadyConsumed(bytes32 snapshotId, bytes32 positionId);

    event PositionManagerInitialized(bytes32 indexed loanId, address indexed loanAccount);
    event TrancheRegistered(bytes32 indexed trancheId, uint32 priority, uint256 originalClaim);
    event PositionIssued(
        bytes32 indexed positionId, bytes32 indexed trancheId, address indexed owner, uint256 claim
    );
    event PositionTransferred(
        bytes32 indexed positionId, address indexed oldOwner, address indexed newOwner
    );
    event PositionSnapshotCreated(
        bytes32 indexed snapshotId,
        bytes32 indexed loanId,
        uint64 snapshotBlock,
        bytes32 positionRoot
    );

    function initialize(bytes32 loanId, address loanAccount, address settlementToken) external;
    function registerTranche(Phase9Types.Tranche calldata tranche_) external;
    function issuePosition(Phase9Types.Position calldata position_) external;
    function transferPosition(bytes32 positionId, address newOwner) external;
    function createSnapshot(Phase9Types.PositionRightSnapshot calldata snapshot) external;
    function consumeVotingRight(bytes32 snapshotId, bytes32 positionId) external;
    function tranche(bytes32 trancheId) external view returns (Phase9Types.Tranche memory);
    function trancheIds() external view returns (bytes32[] memory);
    function position(bytes32 positionId) external view returns (Phase9Types.Position memory);
    function positionIds() external view returns (bytes32[] memory);
    function snapshot(bytes32 snapshotId)
        external
        view
        returns (Phase9Types.PositionRightSnapshot memory);
    function votingRightConsumed(bytes32 snapshotId, bytes32 positionId)
        external
        view
        returns (bool);
    function positionOwnerAt(bytes32 positionId, uint64 blockNumber) external view returns (address);
    function positionVotingPowerAt(bytes32 positionId, uint64 blockNumber)
        external
        view
        returns (uint256);
    function positionClaimAt(bytes32 positionId, uint64 blockNumber) external view returns (uint256);
    function totalVotingPowerAt(uint64 blockNumber) external view returns (uint256);
}
