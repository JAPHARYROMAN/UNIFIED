// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IUnifiedToken } from "../interfaces/IUnifiedToken.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";

/// @notice Versioned synthetic bridge-cap policies with a frozen circulating-supply reference.
contract BridgeExposurePolicy is RoleControlled {
    error InvalidExposurePolicy();
    error UnknownExposurePolicy(bytes32 policyHash);
    error ExposureLimitExceeded(bytes32 dimension, uint256 exposure, uint256 limit);

    uint64 public constant MINIMUM_RISK_INCREASE_DELAY = 1 days;

    struct ExposureConfig {
        uint256 circulatingSupplyReference;
        bytes32 circulatingSupplyEvidenceHash;
        uint256 routeAbsoluteCap;
        uint256 chainAbsoluteCap;
        uint256 adapterAbsoluteCap;
        uint256 aggregateAbsoluteCap;
        uint16 routePercentageCeilingBps;
        uint16 aggregatePercentageCeilingBps;
        uint64 activationDelay;
        uint64 activeFrom;
    }

    IUnifiedToken public immutable canonicalUFT;
    mapping(bytes32 policyHash => ExposureConfig config) private _policies;
    mapping(bytes32 routePolicyHash => bytes32 exposurePolicyHash) public activePolicyForRoute;
    mapping(bytes32 policyHash => uint64 registeredAt) public policyRegisteredAt;
    mapping(bytes32 routePolicyHash => uint64 version) public routePolicyVersion;
    mapping(bytes32 routePolicyHash => mapping(bytes32 policyHash => bool used)) public
        policyPreviouslyActivated;

    event ExposurePolicyRegistered(
        bytes32 indexed policyHash,
        uint256 circulatingSupplyReference,
        bytes32 indexed evidenceHash,
        uint64 activeFrom
    );
    event RouteExposurePolicyActivated(bytes32 indexed routePolicyHash, bytes32 indexed policyHash);

    constructor(IRoleManager roleManager_, IUnifiedToken canonicalUFT_)
        RoleControlled(roleManager_)
    {
        if (address(canonicalUFT_).code.length == 0) {
            revert InvalidExposurePolicy();
        }
        canonicalUFT = canonicalUFT_;
    }

    function registerPolicy(ExposureConfig calldata config)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
        returns (bytes32 policyHash)
    {
        if (
            config.circulatingSupplyReference == 0
                || config.circulatingSupplyReference > canonicalUFT.totalSupply()
                || config.circulatingSupplyEvidenceHash == bytes32(0)
                || config.routeAbsoluteCap == 0 || config.chainAbsoluteCap == 0
                || config.adapterAbsoluteCap == 0 || config.aggregateAbsoluteCap == 0
                || config.routePercentageCeilingBps == 0
                || config.routePercentageCeilingBps > CrossChainTypes.MAX_ROUTE_EXPOSURE_BPS
                || config.aggregatePercentageCeilingBps == 0
                || config.aggregatePercentageCeilingBps > CrossChainTypes.MAX_AGGREGATE_EXPOSURE_BPS
                || config.activeFrom < block.timestamp
                || uint256(config.activeFrom) < block.timestamp + uint256(config.activationDelay)
        ) {
            revert InvalidExposurePolicy();
        }
        policyHash = keccak256(abi.encode("UNIFIED_BRIDGE_EXPOSURE_POLICY_V1", config));
        if (_policies[policyHash].circulatingSupplyReference != 0) {
            revert InvalidExposurePolicy();
        }
        _policies[policyHash] = config;
        policyRegisteredAt[policyHash] = uint64(block.timestamp);
        emit ExposurePolicyRegistered(
            policyHash,
            config.circulatingSupplyReference,
            config.circulatingSupplyEvidenceHash,
            config.activeFrom
        );
    }

    function activateForRoute(bytes32 routePolicyHash, bytes32 policyHash)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
    {
        ExposureConfig storage config = _policies[policyHash];
        if (
            routePolicyHash == bytes32(0) || config.circulatingSupplyReference == 0
                || config.activeFrom > block.timestamp
                || policyPreviouslyActivated[routePolicyHash][policyHash]
        ) {
            revert InvalidExposurePolicy();
        }
        bytes32 priorPolicyHash = activePolicyForRoute[routePolicyHash];
        if (
            priorPolicyHash != bytes32(0)
                && _requiresDelayedActivation(_policies[priorPolicyHash], config)
                && uint256(config.activeFrom)
                    < uint256(policyRegisteredAt[policyHash]) + uint256(MINIMUM_RISK_INCREASE_DELAY)
        ) {
            revert InvalidExposurePolicy();
        }
        activePolicyForRoute[routePolicyHash] = policyHash;
        policyPreviouslyActivated[routePolicyHash][policyHash] = true;
        ++routePolicyVersion[routePolicyHash];
        emit RouteExposurePolicyActivated(routePolicyHash, policyHash);
    }

    function validateLock(
        bytes32 routePolicyHash,
        uint256 routeExposure,
        uint256 chainExposure,
        uint256 adapterExposure,
        uint256 aggregateExposure
    ) external view {
        bytes32 policyHash = activePolicyForRoute[routePolicyHash];
        ExposureConfig storage config = _policies[policyHash];
        if (config.circulatingSupplyReference == 0 || config.activeFrom > block.timestamp) {
            revert UnknownExposurePolicy(policyHash);
        }
        uint256 routePercentageCap = Math.mulDiv(
            config.circulatingSupplyReference, config.routePercentageCeilingBps, CrossChainTypes.BPS
        );
        uint256 aggregatePercentageCap = Math.mulDiv(
            config.circulatingSupplyReference,
            config.aggregatePercentageCeilingBps,
            CrossChainTypes.BPS
        );
        _requireWithin(keccak256("ROUTE_ABSOLUTE"), routeExposure, config.routeAbsoluteCap);
        _requireWithin(keccak256("ROUTE_PERCENTAGE"), routeExposure, routePercentageCap);
        _requireWithin(keccak256("CHAIN_ABSOLUTE"), chainExposure, config.chainAbsoluteCap);
        _requireWithin(keccak256("ADAPTER_ABSOLUTE"), adapterExposure, config.adapterAbsoluteCap);
        _requireWithin(
            keccak256("AGGREGATE_ABSOLUTE"), aggregateExposure, config.aggregateAbsoluteCap
        );
        _requireWithin(keccak256("AGGREGATE_PERCENTAGE"), aggregateExposure, aggregatePercentageCap);
    }

    function policy(bytes32 policyHash) external view returns (ExposureConfig memory) {
        ExposureConfig memory config = _policies[policyHash];
        if (config.circulatingSupplyReference == 0) {
            revert UnknownExposurePolicy(policyHash);
        }
        return config;
    }

    function _requireWithin(bytes32 dimension, uint256 exposure, uint256 limit) private pure {
        if (exposure > limit) revert ExposureLimitExceeded(dimension, exposure, limit);
    }

    function _isEffectiveIncrease(ExposureConfig storage prior, ExposureConfig storage next)
        private
        view
        returns (bool)
    {
        return next.routeAbsoluteCap > prior.routeAbsoluteCap
            || next.chainAbsoluteCap > prior.chainAbsoluteCap
            || next.adapterAbsoluteCap > prior.adapterAbsoluteCap
            || next.aggregateAbsoluteCap > prior.aggregateAbsoluteCap
            || _routePercentageCap(next) > _routePercentageCap(prior)
            || _aggregatePercentageCap(next) > _aggregatePercentageCap(prior);
    }

    function _requiresDelayedActivation(ExposureConfig storage prior, ExposureConfig storage next)
        private
        view
        returns (bool)
    {
        return next.circulatingSupplyReference != prior.circulatingSupplyReference
            || next.circulatingSupplyEvidenceHash != prior.circulatingSupplyEvidenceHash
            || _isEffectiveIncrease(prior, next);
    }

    function _routePercentageCap(ExposureConfig storage config) private view returns (uint256) {
        return Math.mulDiv(
            config.circulatingSupplyReference, config.routePercentageCeilingBps, CrossChainTypes.BPS
        );
    }

    function _aggregatePercentageCap(ExposureConfig storage config) private view returns (uint256) {
        return Math.mulDiv(
            config.circulatingSupplyReference,
            config.aggregatePercentageCeilingBps,
            CrossChainTypes.BPS
        );
    }
}
