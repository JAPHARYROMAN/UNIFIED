// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9RecoveryTypes } from "../../recovery/Phase9RecoveryTypes.sol";

interface IRecoveryManager {
    error InvalidRecoveryOperation();
    error UnknownLoss(bytes32 lossId);
    error RecoveryOperationReplay(bytes32 operationId);

    event LossOpened(
        bytes32 indexed lossId, bytes32 indexed loanId, uint256 grossCoveredLossExposure
    );
    event RecoverySourceRecorded(
        bytes32 indexed recoverySourceId,
        bytes32 indexed lossId,
        Phase9RecoveryTypes.RecoverySourceType sourceType,
        uint256 amount
    );
    event RecoveryEntitlementSet(
        bytes32 indexed entitlementId,
        bytes32 indexed lossId,
        address indexed beneficiary,
        uint256 amount
    );
    event RecoveryAllocated(
        bytes32 indexed allocationId,
        bytes32 indexed lossId,
        bytes32 indexed entitlementId,
        uint256 amount
    );
    event WriteOffRecognized(bytes32 indexed writeoffId, bytes32 indexed lossId, uint256 amount);

    function openLoss(bytes32 lossId, Phase9RecoveryTypes.LossRecord calldata loss) external;
    function recordRecoverySource(Phase9RecoveryTypes.RecoverySourceEvidence calldata source)
        external;
    function setEntitlement(Phase9RecoveryTypes.RecoveryEntitlement calldata entitlement) external;
    function allocateRecovery(Phase9RecoveryTypes.RecoveryAllocation calldata allocation) external;
    function recognizeWriteOff(
        Phase9RecoveryTypes.WriteOffEvidence calldata writeoff,
        bytes32 operationId
    ) external;
    function assetRegistry() external view returns (address);
    function settlementToken() external view returns (address);
    function authorizedReceiptManager() external view returns (address);
    function loss(bytes32 lossId) external view returns (Phase9RecoveryTypes.LossRecord memory);
    function recoverySource(bytes32 recoverySourceId)
        external
        view
        returns (Phase9RecoveryTypes.RecoverySourceEvidence memory);
    function entitlement(bytes32 lossId, bytes32 entitlementId)
        external
        view
        returns (Phase9RecoveryTypes.RecoveryEntitlement memory);
    function allocation(bytes32 allocationId)
        external
        view
        returns (Phase9RecoveryTypes.RecoveryAllocation memory);
    function writeOff(bytes32 writeoffId)
        external
        view
        returns (Phase9RecoveryTypes.WriteOffEvidence memory);
    function operationProcessed(bytes32 operationId) external view returns (bool);
}
