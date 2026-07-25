// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRestructuringController } from "../interfaces/phase9/IRestructuringController.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for bounded borrower-and-lender restructuring consent.
contract RestructuringController is IRestructuringController {
    address private _loanRegistry;
    address private _amendmentPolicyRegistry;
    address private _emergencyController;
    mapping(bytes32 loanId => uint64 nonce) private _nextProposalNonce;
    mapping(bytes32 restructureId => Phase9Types.RestructuringProposal proposal_)
        private _proposals;
    mapping(bytes32 restructureId => Phase9Types.BorrowerConsentRecord consent)
        private _borrowerConsents;
    mapping(bytes32 restructureId => mapping(bytes32 positionId => Phase9Types.VoteRecord vote_))
        private _votes;
    mapping(bytes32 restructureId => uint256 weight) private _supportWeight;
    mapping(bytes32 restructureId => uint256 weight) private _opposeWeight;
    mapping(bytes32 restructureId => uint256 weight) private _castWeight;
    mapping(bytes32 restructureId => Phase9Types.RestructuringExecutionResult result)
        private _executionResults;

    constructor(
        address loanRegistry_,
        address amendmentPolicyRegistry_,
        address emergencyController_
    ) {
        _loanRegistry = loanRegistry_;
        _amendmentPolicyRegistry = amendmentPolicyRegistry_;
        _emergencyController = emergencyController_;
    }

    function propose(Phase9Types.RestructuringProposal calldata)
        external
        override
        returns (bytes32)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function recordBorrowerConsent(Phase9Types.BorrowerConsentRecord calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function castVote(Phase9Types.VoteRecord calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function execute(bytes32, bytes32)
        external
        override
        returns (Phase9Types.RestructuringExecutionResult memory)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function proposal(bytes32 restructureId)
        external
        view
        override
        returns (Phase9Types.RestructuringProposal memory)
    {
        return _proposals[restructureId];
    }

    function borrowerConsent(bytes32 restructureId)
        external
        view
        override
        returns (Phase9Types.BorrowerConsentRecord memory)
    {
        return _borrowerConsents[restructureId];
    }

    function vote(bytes32 restructureId, bytes32 positionId)
        external
        view
        override
        returns (Phase9Types.VoteRecord memory)
    {
        return _votes[restructureId][positionId];
    }

    function voteWeights(bytes32 restructureId)
        external
        view
        override
        returns (uint256 support, uint256 oppose, uint256 cast)
    {
        return (
            _supportWeight[restructureId],
            _opposeWeight[restructureId],
            _castWeight[restructureId]
        );
    }

    function executionResult(bytes32 restructureId)
        external
        view
        override
        returns (Phase9Types.RestructuringExecutionResult memory)
    {
        return _executionResults[restructureId];
    }
}
