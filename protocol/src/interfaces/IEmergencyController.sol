// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

interface IEmergencyController {
    function pauseCapability(bytes32 capability, uint64 expiry, bytes32 reasonCode) external;
    function disableAdapter(bytes32 adapterId, uint64 expiry, bytes32 reasonCode) external;
    function setOracleCircuitBreaker(bytes32 assetId, bool active, uint64 expiry) external;
    function emergencyState(bytes32 capability)
        external
        view
        returns (bool active, uint64 expiry, bytes32 reasonCode);
    function clearExpiredAction(bytes32 actionId) external;
}
