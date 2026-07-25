// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9RecoveryTypes } from "../../recovery/Phase9RecoveryTypes.sol";

interface IGuaranteeVault {
    error InvalidGuarantee();
    error UnknownGuarantee(bytes32 guaranteeId);
    error GuaranteeReceiptReplay(bytes32 receiptId);

    event GuaranteeRegistered(
        bytes32 indexed guaranteeId,
        bytes32 indexed loanId,
        address indexed guarantor,
        uint256 maximumAmount
    );
    event GuaranteeReceiptRecorded(
        bytes32 indexed guaranteeId, bytes32 indexed receiptId, uint256 amount, uint256 paidAmount
    );

    function registerGuarantee(Phase9RecoveryTypes.Guarantee calldata guarantee_) external;
    function recordGuaranteeReceipt(
        bytes32 guaranteeId,
        bytes32 receiptId,
        uint256 amount,
        bytes32 balanceDeltaHash
    ) external;
    function assetRegistry() external view returns (address);
    function settlementToken() external view returns (address);
    function authorizedRecoveryManager() external view returns (address);
    function guarantee(bytes32 guaranteeId)
        external
        view
        returns (Phase9RecoveryTypes.Guarantee memory);
    function receiptProcessed(bytes32 receiptId) external view returns (bool);
}
