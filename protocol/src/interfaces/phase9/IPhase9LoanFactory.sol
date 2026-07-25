// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9Types } from "../../resolution/Phase9Types.sol";

interface IPhase9LoanFactory {
    error InvalidPhase9LoanConfiguration();
    error Phase9LoanAlreadyExists(bytes32 loanId);

    event Phase9LoanCreated(
        bytes32 indexed loanId,
        bytes32 indexed refinanceId,
        address indexed loanAccount,
        address positionManager,
        address borrower,
        bytes32 oldLoanId,
        uint64 newLoanNonce,
        uint64 loanNonce
    );

    function createLoan(Phase9Types.LoanCreationRequest calldata request)
        external
        returns (address loanAccount, address positionManager);
    function loanAccount(bytes32 loanId) external view returns (address);
    function positionManager(bytes32 loanId) external view returns (address);
    function creationRequest(bytes32 creationId)
        external
        view
        returns (Phase9Types.LoanCreationRequest memory);
    function nextLoanNonce() external view returns (uint64);
}
