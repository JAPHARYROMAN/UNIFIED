// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

interface ILoanRegistry {
    function registerLoan(
        bytes32 loanId,
        address loanAccount,
        address borrower,
        bytes32 agreementHash,
        uint32 protocolVersion
    ) external;

    function loanAccount(bytes32 loanId) external view returns (address);
    function borrowerOf(bytes32 loanId) external view returns (address);
    function agreementHashOf(bytes32 loanId) external view returns (bytes32);
    function protocolVersionOf(bytes32 loanId) external view returns (uint32);
    function exists(bytes32 loanId) external view returns (bool);
    function isTerminal(bytes32 loanId) external view returns (bool);
    function markTerminal(bytes32 loanId) external;
}
