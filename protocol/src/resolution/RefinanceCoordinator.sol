// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRefinanceCoordinator } from "../interfaces/phase9/IRefinanceCoordinator.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for exact-funded atomic refinancing.
contract RefinanceCoordinator is IRefinanceCoordinator {
    address private _loanRegistry;
    address private _phase9LoanFactory;
    address private _payoffQuoteEngine;
    address private _lienRegistry;
    address private _assetRegistry;
    address private _policyRegistry;
    address private _emergencyController;
    address private _treasuryFeeRecipient;
    IERC20 private _settlementToken;
    mapping(bytes32 oldLoanId => uint64 nonce) private _nextRefinanceNonce;
    mapping(bytes32 refinanceId => Phase9Types.RefinanceRecord record) private _refinances;
    mapping(bytes32 refinanceId => bytes32[] commitmentIds_) private _commitmentIds;
    mapping(bytes32 commitmentId => Phase9Types.FundingCommitment commitment)
        private _commitments;
    mapping(bytes32 refinanceId => uint256 units) private _escrowedUnits;
    mapping(bytes32 refinanceId => Phase9Types.RefinanceTerminalResult result)
        private _terminalResults;
    mapping(bytes32 operationId => bool processed) private _processedOperationIds;

    constructor(
        address loanRegistry_,
        address phase9LoanFactory_,
        address payoffQuoteEngine_,
        address lienRegistry_,
        address assetRegistry_,
        address policyRegistry_,
        address emergencyController_,
        address treasuryFeeRecipient_,
        IERC20 settlementToken_
    ) {
        _loanRegistry = loanRegistry_;
        _phase9LoanFactory = phase9LoanFactory_;
        _payoffQuoteEngine = payoffQuoteEngine_;
        _lienRegistry = lienRegistry_;
        _assetRegistry = assetRegistry_;
        _policyRegistry = policyRegistry_;
        _emergencyController = emergencyController_;
        _treasuryFeeRecipient = treasuryFeeRecipient_;
        _settlementToken = settlementToken_;
    }

    function requestRefinance(Phase9Types.RefinanceRecord calldata)
        external
        override
        returns (bytes32)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function recordFundingCommitment(Phase9Types.FundingCommitment calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function executeRefinance(bytes32, bytes32)
        external
        override
        returns (Phase9Types.RefinanceTerminalResult memory)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function cancelRefinance(bytes32, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function refundCommitment(bytes32, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function refinance(bytes32 refinanceId)
        external
        view
        override
        returns (Phase9Types.RefinanceRecord memory)
    {
        return _refinances[refinanceId];
    }

    function fundingCommitment(bytes32 commitmentId)
        external
        view
        override
        returns (Phase9Types.FundingCommitment memory)
    {
        return _commitments[commitmentId];
    }

    function commitmentIds(bytes32 refinanceId)
        external
        view
        override
        returns (bytes32[] memory)
    {
        return _commitmentIds[refinanceId];
    }

    function escrowedUnits(bytes32 refinanceId) external view override returns (uint256) {
        return _escrowedUnits[refinanceId];
    }

    function terminalResult(bytes32 refinanceId)
        external
        view
        override
        returns (Phase9Types.RefinanceTerminalResult memory)
    {
        return _terminalResults[refinanceId];
    }

    function operationProcessed(bytes32 operationId) external view override returns (bool) {
        return _processedOperationIds[operationId];
    }
}
