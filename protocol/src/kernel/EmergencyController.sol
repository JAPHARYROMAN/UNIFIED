// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IEmergencyController } from "../interfaces/IEmergencyController.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "./ProtocolRoles.sol";
import { RoleControlled } from "./RoleControlled.sol";

/// @notice Time-bounded, capability-scoped emergency controls.
contract EmergencyController is IEmergencyController, RoleControlled {
    error InvalidAction();
    error InvalidExpiry();
    error ProtectedCapability(bytes32 capability);

    uint64 public constant MAX_EMERGENCY_DURATION = 7 days;
    bytes32 public constant CAPABILITY_REPAYMENT = keccak256("CAPABILITY_REPAYMENT");
    bytes32 public constant CAPABILITY_COLLATERAL_TOP_UP =
        keccak256("CAPABILITY_COLLATERAL_TOP_UP");

    bytes32 private constant ADAPTER_PREFIX = keccak256("ADAPTER");
    bytes32 private constant ORACLE_PREFIX = keccak256("ORACLE");

    struct EmergencyAction {
        uint64 expiry;
        bytes32 reasonCode;
    }

    mapping(bytes32 actionId => EmergencyAction action) private _actions;

    event EmergencyActionActivated(
        bytes32 indexed actionId, uint64 expiry, bytes32 indexed reasonCode, address indexed sender
    );
    event EmergencyActionCleared(bytes32 indexed actionId, address indexed sender);

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    modifier onlyEmergencyAuthority() {
        bool authorized = roleManager.hasRole(ProtocolRoles.PAUSER_ROLE, msg.sender)
            || roleManager.hasRole(ProtocolRoles.EMERGENCY_COUNCIL_ROLE, msg.sender);
        if (!authorized) revert Unauthorized(ProtocolRoles.PAUSER_ROLE, msg.sender);
        _;
    }

    function pauseCapability(bytes32 capability, uint64 expiry, bytes32 reasonCode)
        external
        onlyEmergencyAuthority
    {
        if (capability == CAPABILITY_REPAYMENT || capability == CAPABILITY_COLLATERAL_TOP_UP) {
            revert ProtectedCapability(capability);
        }
        _activate(capability, expiry, reasonCode);
    }

    function disableAdapter(bytes32 adapterId, uint64 expiry, bytes32 reasonCode)
        external
        onlyEmergencyAuthority
    {
        if (adapterId == bytes32(0)) revert InvalidAction();
        _activate(adapterActionId(adapterId), expiry, reasonCode);
    }

    function setOracleCircuitBreaker(bytes32 assetId, bool active, uint64 expiry)
        external
        onlyEmergencyAuthority
    {
        if (assetId == bytes32(0)) revert InvalidAction();
        bytes32 actionId = oracleActionId(assetId);
        if (!active) {
            delete _actions[actionId];
            emit EmergencyActionCleared(actionId, msg.sender);
            return;
        }
        _activate(actionId, expiry, keccak256("ORACLE_CIRCUIT_BREAKER"));
    }

    function emergencyState(bytes32 actionId)
        external
        view
        returns (bool active, uint64 expiry, bytes32 reasonCode)
    {
        EmergencyAction memory action = _actions[actionId];
        return (
            action.expiry >= block.timestamp && action.expiry != 0, action.expiry, action.reasonCode
        );
    }

    function clearExpiredAction(bytes32 actionId) external {
        EmergencyAction memory action = _actions[actionId];
        if (action.expiry == 0 || action.expiry >= block.timestamp) revert InvalidAction();
        delete _actions[actionId];
        emit EmergencyActionCleared(actionId, msg.sender);
    }

    function adapterActionId(bytes32 adapterId) public pure returns (bytes32) {
        return keccak256(abi.encode(ADAPTER_PREFIX, adapterId));
    }

    function oracleActionId(bytes32 assetId) public pure returns (bytes32) {
        return keccak256(abi.encode(ORACLE_PREFIX, assetId));
    }

    function _activate(bytes32 actionId, uint64 expiry, bytes32 reasonCode) private {
        if (actionId == bytes32(0) || reasonCode == bytes32(0)) revert InvalidAction();
        if (expiry <= block.timestamp || uint256(expiry) > block.timestamp + MAX_EMERGENCY_DURATION)
        {
            revert InvalidExpiry();
        }
        _actions[actionId] = EmergencyAction({ expiry: expiry, reasonCode: reasonCode });
        emit EmergencyActionActivated(actionId, expiry, reasonCode, msg.sender);
    }
}
