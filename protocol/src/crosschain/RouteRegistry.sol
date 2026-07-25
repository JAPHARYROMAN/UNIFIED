// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IEmergencyController } from "../interfaces/IEmergencyController.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { ChainRegistry } from "./ChainRegistry.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";

/// @notice Append-only route policies. Deprecation never rewrites an existing message policy.
contract RouteRegistry is RoleControlled {
    error InvalidRoute();
    error UnknownRoute(bytes32 routePolicyHash);
    error RouteAlreadyDeprecated(bytes32 routePolicyHash);
    error UnauthorizedRoutePause();

    uint32 public constant LOCK_ACTION_MASK = uint32(1) << 1;
    uint32 public constant REPORT_ACTION_MASK = (uint32(1) << 2) | (uint32(1) << 5)
        | (uint32(1) << 7) | (uint32(1) << 10) | (uint32(1) << 14);
    uint32 public constant BRIDGE_EXIT_ACTION_MASK = (uint32(1) << 3) | (uint32(1) << 15);
    uint32 public constant REPAYMENT_ACTION_MASK = uint32(1) << 8;
    uint32 public constant DISBURSEMENT_ACTION_MASK = (uint32(1) << 6) | (uint32(1) << 12);
    uint32 public constant COLLATERAL_RELEASE_ACTION_MASK = uint32(1) << 9;
    uint32 public constant SUPPORTED_ACTIONS_MASK = LOCK_ACTION_MASK | REPORT_ACTION_MASK
        | BRIDGE_EXIT_ACTION_MASK | REPAYMENT_ACTION_MASK | DISBURSEMENT_ACTION_MASK
        | COLLATERAL_RELEASE_ACTION_MASK;

    struct RouteConfig {
        uint32 sourceChainVersion;
        uint32 destinationChainVersion;
        uint256 sourceChainId;
        address sourceCoordinator;
        address sourceComponent;
        bytes32 sourceComponentCodeHash;
        uint256 destinationChainId;
        address destinationCoordinator;
        address destinationComponent;
        bytes32 destinationComponentCodeHash;
        bytes32 actionFamily;
        uint32 allowedActionsBitmap;
        bytes32 adapterId;
        bytes32 adapterCodeHash;
        bytes32 adapterSetPolicyHash;
        bytes32 sourceFinalityPolicyHash;
        bytes32 destinationFinalityPolicyHash;
        bytes32 sourceSignerSetHash;
        bytes32 destinationSignerSetHash;
        uint256 absoluteCap;
        uint256 chainCap;
        uint256 adapterCap;
        uint64 activatedAt;
    }

    struct RouteVersion {
        bytes32 routePolicyHash;
        RouteConfig config;
        uint64 deprecatedAt;
        bool paused;
        CrossChainTypes.RegistryStatus status;
    }

    ChainRegistry public immutable chainRegistry;
    IEmergencyController public immutable emergencyController;
    mapping(bytes32 routePolicyHash => RouteVersion route) private _routes;

    event RouteRegistered(
        bytes32 indexed routePolicyHash,
        uint256 indexed sourceChainId,
        uint256 indexed destinationChainId,
        address sourceComponent,
        address destinationComponent,
        bytes32 actionFamily,
        uint32 allowedActionsBitmap
    );
    event RouteDeprecated(bytes32 indexed routePolicyHash, uint64 deprecatedAt);
    event RoutePauseChanged(bytes32 indexed routePolicyHash, bool paused);

    constructor(
        IRoleManager roleManager_,
        ChainRegistry chainRegistry_,
        IEmergencyController emergencyController_
    ) RoleControlled(roleManager_) {
        if (address(chainRegistry_) == address(0) || address(emergencyController_) == address(0)) {
            revert InvalidRoute();
        }
        chainRegistry = chainRegistry_;
        emergencyController = emergencyController_;
    }

    function registerRoute(RouteConfig calldata config)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
        returns (bytes32 routePolicyHash)
    {
        _validateConfig(config);
        routePolicyHash = hashRoute(config);
        if (_routes[routePolicyHash].status != CrossChainTypes.RegistryStatus.NONE) {
            revert InvalidRoute();
        }
        _routes[routePolicyHash] = RouteVersion({
            routePolicyHash: routePolicyHash,
            config: config,
            deprecatedAt: 0,
            paused: false,
            status: CrossChainTypes.RegistryStatus.ACTIVE
        });
        emit RouteRegistered(
            routePolicyHash,
            config.sourceChainId,
            config.destinationChainId,
            config.sourceComponent,
            config.destinationComponent,
            config.actionFamily,
            config.allowedActionsBitmap
        );
    }

    function deprecateRoute(bytes32 routePolicyHash)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        RouteVersion storage route_ = _routes[routePolicyHash];
        if (route_.status == CrossChainTypes.RegistryStatus.NONE) {
            revert UnknownRoute(routePolicyHash);
        }
        if (route_.status == CrossChainTypes.RegistryStatus.DEPRECATED) {
            revert RouteAlreadyDeprecated(routePolicyHash);
        }
        route_.status = CrossChainTypes.RegistryStatus.DEPRECATED;
        route_.deprecatedAt = uint64(block.timestamp);
        emit RouteDeprecated(routePolicyHash, route_.deprecatedAt);
    }

    function setRoutePaused(bytes32 routePolicyHash, bool paused) external {
        bool governance = roleManager.hasRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE, msg.sender);
        bool authorized = governance
            || (paused
                && (roleManager.hasRole(ProtocolRoles.PAUSER_ROLE, msg.sender)
                    || roleManager.hasRole(ProtocolRoles.EMERGENCY_COUNCIL_ROLE, msg.sender)));
        if (!authorized) revert UnauthorizedRoutePause();
        RouteVersion storage route_ = _routes[routePolicyHash];
        if (route_.status == CrossChainTypes.RegistryStatus.NONE) {
            revert UnknownRoute(routePolicyHash);
        }
        route_.paused = paused;
        emit RoutePauseChanged(routePolicyHash, paused);
    }

    function route(bytes32 routePolicyHash) external view returns (RouteVersion memory) {
        RouteVersion memory route_ = _routes[routePolicyHash];
        if (route_.status == CrossChainTypes.RegistryStatus.NONE) {
            revert UnknownRoute(routePolicyHash);
        }
        return route_;
    }

    function isAvailableForNewMessage(bytes32 routePolicyHash) external view returns (bool) {
        RouteVersion storage route_ = _routes[routePolicyHash];
        if (
            route_.status != CrossChainTypes.RegistryStatus.ACTIVE || route_.paused
                || route_.config.activatedAt > block.timestamp
                || !chainRegistry.isActiveVersion(
                    route_.config.sourceChainId, route_.config.sourceChainVersion
                )
                || !chainRegistry.isActiveVersion(
                    route_.config.destinationChainId, route_.config.destinationChainVersion
                )
        ) {
            return false;
        }
        (bool adapterDisabled,,) = emergencyController.emergencyState(
            EmergencyActionIds.adapterActionId(route_.config.adapterId)
        );
        return !adapterDisabled;
    }

    function isActionAllowed(
        bytes32 routePolicyHash,
        CrossChainTypes.CrossChainActionType actionType
    ) external view returns (bool) {
        RouteVersion storage route_ = _routes[routePolicyHash];
        if (
            route_.status == CrossChainTypes.RegistryStatus.NONE
                || actionType == CrossChainTypes.CrossChainActionType.UNSPECIFIED
        ) {
            return false;
        }
        return route_.config.allowedActionsBitmap & CrossChainTypes.actionBit(actionType) != 0;
    }

    function isExecutable(bytes32 routePolicyHash, uint64 messageCreatedAt, bool allowPausedExit)
        external
        view
        returns (bool)
    {
        RouteVersion storage route_ = _routes[routePolicyHash];
        if (
            route_.status == CrossChainTypes.RegistryStatus.NONE
                || messageCreatedAt < route_.config.activatedAt
        ) {
            return false;
        }
        if (route_.deprecatedAt != 0 && messageCreatedAt >= route_.deprecatedAt) return false;
        if (
            !chainRegistry.wasActiveAt(
                    route_.config.sourceChainId, route_.config.sourceChainVersion, messageCreatedAt
                )
                || !chainRegistry.wasActiveAt(
                    route_.config.destinationChainId,
                    route_.config.destinationChainVersion,
                    messageCreatedAt
                )
        ) {
            return false;
        }
        if (allowPausedExit) return true;
        (bool adapterDisabled,,) = emergencyController.emergencyState(
            EmergencyActionIds.adapterActionId(route_.config.adapterId)
        );
        return !route_.paused && !adapterDisabled;
    }

    function hashRoute(RouteConfig memory config) public pure returns (bytes32) {
        return keccak256(abi.encode("UNIFIED_XCHAIN_ROUTE_V1", config));
    }

    function _validateConfig(RouteConfig calldata config) private view {
        if (
            config.sourceChainId == 0 || config.destinationChainId == 0
                || config.sourceChainId == config.destinationChainId
                || config.sourceCoordinator == address(0)
                || config.destinationCoordinator == address(0)
                || config.sourceComponent == address(0) || config.destinationComponent == address(0)
                || config.sourceComponentCodeHash == bytes32(0)
                || config.destinationComponentCodeHash == bytes32(0)
                || config.actionFamily == bytes32(0)
                || !_isSupportedLaneBitmap(config.allowedActionsBitmap)
                || config.adapterId == bytes32(0) || config.adapterCodeHash == bytes32(0)
                || config.adapterSetPolicyHash == bytes32(0)
                || config.sourceFinalityPolicyHash == bytes32(0)
                || config.destinationFinalityPolicyHash == bytes32(0)
                || config.sourceSignerSetHash == bytes32(0)
                || config.destinationSignerSetHash == bytes32(0) || config.absoluteCap == 0
                || config.chainCap == 0 || config.adapterCap == 0
                || config.activatedAt < block.timestamp
        ) {
            revert InvalidRoute();
        }
        ChainRegistry.ChainVersion memory source =
            chainRegistry.chainVersion(config.sourceChainId, config.sourceChainVersion);
        ChainRegistry.ChainVersion memory destination =
            chainRegistry.chainVersion(config.destinationChainId, config.destinationChainVersion);
        if (
            source.coordinator != config.sourceCoordinator
                || destination.coordinator != config.destinationCoordinator
                || source.status != CrossChainTypes.RegistryStatus.ACTIVE
                || destination.status != CrossChainTypes.RegistryStatus.ACTIVE
                || source.activatedAt > config.activatedAt
                || destination.activatedAt > config.activatedAt
        ) {
            revert InvalidRoute();
        }
        uint256 localChainId = chainRegistry.localChainId();
        if (
            (config.sourceChainId == localChainId
                    && config.sourceComponent.codehash != config.sourceComponentCodeHash)
                || (config.destinationChainId == localChainId
                    && config.destinationComponent.codehash != config.destinationComponentCodeHash)
        ) {
            revert InvalidRoute();
        }
    }

    function _isSupportedLaneBitmap(uint32 bitmap) private pure returns (bool) {
        if (bitmap == 0 || bitmap & ~SUPPORTED_ACTIONS_MASK != 0) return false;
        return _isSubset(bitmap, LOCK_ACTION_MASK) || _isSubset(bitmap, REPORT_ACTION_MASK)
            || _isSubset(bitmap, BRIDGE_EXIT_ACTION_MASK)
            || _isSubset(bitmap, REPAYMENT_ACTION_MASK)
            || _isSubset(bitmap, DISBURSEMENT_ACTION_MASK)
            || _isSubset(bitmap, COLLATERAL_RELEASE_ACTION_MASK);
    }

    function _isSubset(uint32 bitmap, uint32 laneMask) private pure returns (bool) {
        return bitmap & ~laneMask == 0;
    }
}

/// @dev Matches EmergencyController's stable adapter-action derivation without adding authority.
library EmergencyActionIds {
    bytes32 private constant ADAPTER_PREFIX = keccak256("ADAPTER");

    function adapterActionId(bytes32 adapterId) internal pure returns (bytes32) {
        return keccak256(abi.encode(ADAPTER_PREFIX, adapterId));
    }
}
