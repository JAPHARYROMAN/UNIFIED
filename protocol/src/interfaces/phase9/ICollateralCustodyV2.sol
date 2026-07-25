// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9Types } from "../../resolution/Phase9Types.sol";

interface ICollateralCustodyV2 {
    error InvalidCustodyOperation();
    error UnknownCollateral(bytes32 collateralId);
    error CustodyOperationReplay(bytes32 operationId);

    event CollateralCustodyRecorded(
        bytes32 indexed collateralId,
        bytes32 indexed assetId,
        address indexed borrower,
        uint256 quantity
    );
    event CollateralCustodyUpdated(
        bytes32 indexed collateralId,
        uint256 quantity,
        Phase9Types.CustodyStatus status,
        bytes32 operationId
    );

    function recordCustody(Phase9Types.CustodyRecord calldata record, bytes32 operationId) external;
    function updateCustody(
        bytes32 collateralId,
        uint256 quantity,
        Phase9Types.CustodyStatus status,
        bytes32 operationId
    ) external;
    function custody(bytes32 collateralId) external view returns (Phase9Types.CustodyRecord memory);
    function totalCustody(bytes32 assetId) external view returns (uint256);
    function operationProcessed(bytes32 operationId) external view returns (bool);
}
