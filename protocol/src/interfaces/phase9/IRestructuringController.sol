// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9Types } from "../../resolution/Phase9Types.sol";

interface IRestructuringController {
    error InvalidRestructuring();
    error UnknownRestructuring(bytes32 restructureId);
    error RestructuringVoteReplay(bytes32 restructureId, bytes32 positionId);

    event RestructuringProposed(bytes32 indexed restructureId, bytes32 indexed loanId, bytes32 indexed snapshotId);
    event BorrowerConsentRecorded(bytes32 indexed restructureId, address indexed borrower, bytes32 consentDigest);
    event RestructuringVoteRecorded(bytes32 indexed restructureId, bytes32 indexed positionId, Phase9Types.VoteChoice choice, uint256 weight);
    event RestructuringExecuted(bytes32 indexed restructureId, bytes32 indexed executionEventId, bytes32 amendmentDigest);

    function propose(Phase9Types.RestructuringProposal calldata proposal) external returns (bytes32 restructureId);
    function recordBorrowerConsent(Phase9Types.BorrowerConsentRecord calldata consent) external;
    function castVote(Phase9Types.VoteRecord calldata vote) external;
    function execute(bytes32 restructureId, bytes32 operationId) external returns (Phase9Types.RestructuringExecutionResult memory result);
    function proposal(bytes32 restructureId) external view returns (Phase9Types.RestructuringProposal memory);
    function borrowerConsent(bytes32 restructureId) external view returns (Phase9Types.BorrowerConsentRecord memory);
    function vote(bytes32 restructureId, bytes32 positionId) external view returns (Phase9Types.VoteRecord memory);
    function voteWeights(bytes32 restructureId) external view returns (uint256 support, uint256 oppose, uint256 cast);
    function executionResult(bytes32 restructureId) external view returns (Phase9Types.RestructuringExecutionResult memory);
}
