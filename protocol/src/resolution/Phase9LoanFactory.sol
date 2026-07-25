// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IPhase9LoanFactory } from "../interfaces/phase9/IPhase9LoanFactory.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for version-9 loan creation.
contract Phase9LoanFactory is IPhase9LoanFactory {
    ILoanRegistry private _loanRegistry;
    address private _loanAccountImplementation;
    address private _positionManagerImplementation;
    address private _quotePolicyRegistry;
    address private _refinancePolicyRegistry;
    address private _amendmentPolicyRegistry;
    address private _protectionPolicyRegistry;
    address private _recoveryPolicyRegistry;
    uint64 private _nextLoanNonce;
    mapping(bytes32 loanId => address account) private _loanAccounts;
    mapping(bytes32 loanId => address manager) private _positionManagers;
    mapping(bytes32 creationId => Phase9Types.LoanCreationRequest request)
        private _creationRequests;
    mapping(bytes32 creationId => bool processed) private _processedCreationIds;

    constructor(
        ILoanRegistry loanRegistry_,
        address loanAccountImplementation_,
        address positionManagerImplementation_,
        address quotePolicyRegistry_,
        address refinancePolicyRegistry_,
        address amendmentPolicyRegistry_,
        address protectionPolicyRegistry_,
        address recoveryPolicyRegistry_
    ) {
        _loanRegistry = loanRegistry_;
        _loanAccountImplementation = loanAccountImplementation_;
        _positionManagerImplementation = positionManagerImplementation_;
        _quotePolicyRegistry = quotePolicyRegistry_;
        _refinancePolicyRegistry = refinancePolicyRegistry_;
        _amendmentPolicyRegistry = amendmentPolicyRegistry_;
        _protectionPolicyRegistry = protectionPolicyRegistry_;
        _recoveryPolicyRegistry = recoveryPolicyRegistry_;
    }

    function createLoan(Phase9Types.LoanCreationRequest calldata)
        external
        override
        returns (address, address)
    {
        revert Phase9ImplementationNotFrozen();
    }

    function loanAccount(bytes32 loanId) external view override returns (address) {
        return _loanAccounts[loanId];
    }

    function positionManager(bytes32 loanId) external view override returns (address) {
        return _positionManagers[loanId];
    }

    function creationRequest(bytes32 creationId)
        external
        view
        override
        returns (Phase9Types.LoanCreationRequest memory)
    {
        return _creationRequests[creationId];
    }

    function nextLoanNonce() external view override returns (uint64) {
        return _nextLoanNonce;
    }
}
