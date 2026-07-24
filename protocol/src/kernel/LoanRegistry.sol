// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "./ProtocolRoles.sol";
import { RoleControlled } from "./RoleControlled.sol";

/// @notice Canonical append-only loan identity directory.
contract LoanRegistry is ILoanRegistry, RoleControlled {
    error InvalidLoan();
    error LoanAlreadyRegistered(bytes32 loanId);
    error UnknownLoan(bytes32 loanId);
    error TerminalStateAlreadySet(bytes32 loanId);

    struct LoanRecord {
        address loanAccount;
        address borrower;
        bytes32 agreementHash;
        uint32 protocolVersion;
        bool terminal;
    }

    mapping(bytes32 loanId => LoanRecord loan) private _loans;

    event LoanRegistered(
        bytes32 indexed loanId,
        address indexed loanAccount,
        address indexed borrower,
        bytes32 agreementHash,
        uint32 protocolVersion
    );
    event LoanMarkedTerminal(bytes32 indexed loanId, address indexed sender);

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function registerLoan(
        bytes32 loanId,
        address account,
        address borrower,
        bytes32 agreementHash,
        uint32 protocolVersion
    ) external onlyRole(ProtocolRoles.LOAN_FACTORY_ROLE) {
        if (
            loanId == bytes32(0) || account == address(0) || account.code.length == 0
                || borrower == address(0) || agreementHash == bytes32(0) || protocolVersion == 0
        ) {
            revert InvalidLoan();
        }
        if (_loans[loanId].loanAccount != address(0)) revert LoanAlreadyRegistered(loanId);
        _loans[loanId] = LoanRecord({
            loanAccount: account,
            borrower: borrower,
            agreementHash: agreementHash,
            protocolVersion: protocolVersion,
            terminal: false
        });
        emit LoanRegistered(loanId, account, borrower, agreementHash, protocolVersion);
    }

    function markTerminal(bytes32 loanId) external onlyRole(ProtocolRoles.SERVICER_ROLE) {
        LoanRecord storage loan = _loans[loanId];
        if (loan.loanAccount == address(0)) revert UnknownLoan(loanId);
        if (loan.terminal) revert TerminalStateAlreadySet(loanId);
        loan.terminal = true;
        emit LoanMarkedTerminal(loanId, msg.sender);
    }

    function loanAccount(bytes32 loanId) external view returns (address) {
        return _loans[loanId].loanAccount;
    }

    function borrowerOf(bytes32 loanId) external view returns (address) {
        return _loans[loanId].borrower;
    }

    function agreementHashOf(bytes32 loanId) external view returns (bytes32) {
        return _loans[loanId].agreementHash;
    }

    function protocolVersionOf(bytes32 loanId) external view returns (uint32) {
        return _loans[loanId].protocolVersion;
    }

    function exists(bytes32 loanId) external view returns (bool) {
        return _loans[loanId].loanAccount != address(0);
    }

    function isTerminal(bytes32 loanId) external view returns (bool) {
        return _loans[loanId].terminal;
    }
}
