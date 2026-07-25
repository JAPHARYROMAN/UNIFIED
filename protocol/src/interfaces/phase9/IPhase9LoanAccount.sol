// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9Types } from "../../resolution/Phase9Types.sol";

interface IPhase9LoanAccount {
    error InvalidPhase9LoanOperation();
    error UnauthorizedPhase9LoanCaller(address caller);
    error Phase9LoanOperationReplay(bytes32 operationId);

    event RefinancePayoffRecorded(
        bytes32 indexed refinanceId, uint256 amount, uint64 debtStateVersion
    );
    event ReplacementLoanActivated(bytes32 indexed refinanceId, uint64 debtStateVersion);
    event RestructuringApplied(
        bytes32 indexed restructureId, uint64 termsVersion, uint64 debtStateVersion
    );
    event LossRecorded(
        bytes32 indexed lossId, uint256 coveredLossExposure, uint64 debtStateVersion
    );
    event WriteOffRecorded(bytes32 indexed writeoffId, uint256 amount, uint64 debtStateVersion);
    event PostWriteOffRecoveryRecorded(
        bytes32 indexed recoverySourceId, uint256 amount, uint64 debtStateVersion
    );
    event Phase9LoanClosed(bytes32 indexed loanId, uint64 debtStateVersion);

    function initialize(
        Phase9Types.LoanConfiguration calldata configuration,
        Phase9Types.DebtState calldata initialDebt
    ) external;
    function configuration() external view returns (Phase9Types.LoanConfiguration memory);
    function debtState() external view returns (Phase9Types.DebtState memory);
    function agreementVersionHash(uint64 version) external view returns (bytes32);
    function operationProcessed(bytes32 operationId) external view returns (bool);
    function recordRefinancePayoff(bytes32 refinanceId, uint256 amount, bytes32 operationId)
        external;
    function activateReplacementLoan(
        bytes32 refinanceId,
        Phase9Types.DebtState calldata initialDebt,
        bytes32 operationId
    ) external;
    function applyRestructuring(Phase9Types.LoanAmendment calldata amendment, bytes32 operationId)
        external;
    function recordCoveredLoss(bytes32 lossId, uint256 amount, bytes32 operationId) external;
    function recordRealizedLoss(bytes32 lossId, uint256 amount, bytes32 operationId) external;
    function recordWriteOff(bytes32 writeoffId, uint256 amount, bytes32 operationId) external;
    function recordPostWriteOffRecovery(
        bytes32 recoverySourceId,
        uint256 amount,
        bytes32 operationId
    ) external;
    function closeLoan(bytes32 operationId) external;
}
