// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9Types } from "../../resolution/Phase9Types.sol";

interface IRefinanceCoordinator {
    error InvalidRefinance();
    error UnknownRefinance(bytes32 refinanceId);
    error RefinanceReplayConflict(bytes32 refinanceId);
    error UnknownFundingCommitment(bytes32 commitmentId);

    event RefinanceRequested(
        bytes32 indexed refinanceId,
        bytes32 indexed oldLoanId,
        bytes32 indexed newLoanId,
        bytes32 quoteId
    );
    event RefinanceCommitmentRecorded(
        bytes32 indexed refinanceId,
        bytes32 indexed commitmentId,
        address indexed funder,
        uint256 amount
    );
    event RefinanceExecuted(
        bytes32 indexed refinanceId, bytes32 indexed executionEventId, bytes32 resultHash
    );
    event RefinanceRefunded(
        bytes32 indexed refinanceId, bytes32 indexed commitmentId, uint256 amount
    );
    event RefinanceStateTransitioned(
        bytes32 indexed refinanceId,
        Phase9Types.RefinanceState indexed previousState,
        Phase9Types.RefinanceState indexed nextState,
        uint64 stateVersion,
        bytes32 operationId,
        bytes32 evidenceHash
    );

    function requestRefinance(Phase9Types.RefinanceRecord calldata request)
        external
        returns (bytes32 refinanceId);
    function recordFundingCommitment(Phase9Types.FundingCommitment calldata commitment) external;
    function executeRefinance(bytes32 refinanceId, bytes32 operationId)
        external
        returns (Phase9Types.RefinanceTerminalResult memory result);
    function cancelRefinance(bytes32 refinanceId, bytes32 operationId) external;
    function refundCommitment(bytes32 commitmentId, bytes32 operationId) external;
    function refinance(bytes32 refinanceId)
        external
        view
        returns (Phase9Types.RefinanceRecord memory);
    function fundingCommitment(bytes32 commitmentId)
        external
        view
        returns (Phase9Types.FundingCommitment memory);
    function commitmentIds(bytes32 refinanceId) external view returns (bytes32[] memory);
    function escrowedUnits(bytes32 refinanceId) external view returns (uint256);
    function terminalResult(bytes32 refinanceId)
        external
        view
        returns (Phase9Types.RefinanceTerminalResult memory);
    function operationProcessed(bytes32 operationId) external view returns (bool);
}
