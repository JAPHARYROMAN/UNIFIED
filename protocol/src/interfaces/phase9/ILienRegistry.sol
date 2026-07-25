// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9Types } from "../../resolution/Phase9Types.sol";

interface ILienRegistry {
    error InvalidLien();
    error UnknownLien(bytes32 collateralId);
    error InvalidLienHandoff(bytes32 collateralId, uint64 lienVersion);

    event LienRegistered(bytes32 indexed collateralId, bytes32 indexed seniorLoanId, uint64 lienVersion);
    event LienHandoffPending(bytes32 indexed collateralId, bytes32 indexed refinanceId, bytes32 indexed targetLoanId);
    event LienHandoffCompleted(bytes32 indexed collateralId, bytes32 indexed oldLoanId, bytes32 indexed newLoanId, uint64 lienVersion);

    function registerLien(Phase9Types.Lien calldata lien_) external;
    function beginHandoff(bytes32 collateralId, bytes32 refinanceId, bytes32 targetLoanId, uint64 expectedLienVersion) external returns (bytes32 handoffId);
    function completeHandoff(bytes32 handoffId, bytes32 evidenceHash) external returns (Phase9Types.LienHandoffResult memory result);
    function registeredRefinanceCoordinator() external view returns (address);
    function lien(bytes32 collateralId) external view returns (Phase9Types.Lien memory);
    function handoff(bytes32 handoffId) external view returns (Phase9Types.LienHandoffResult memory);
}
