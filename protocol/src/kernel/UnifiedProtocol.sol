// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IEmergencyController } from "../interfaces/IEmergencyController.sol";

/// @notice Immutable protocol directory. It intentionally holds no user or protocol assets.
contract UnifiedProtocol {
    error InvalidConfiguration();

    bytes32 public constant PROTOCOL_ID = keccak256("UNIFIED_PROTOCOL");
    uint32 public immutable protocolVersion;
    uint256 public immutable homeChainId;
    bytes32 public immutable chainConfigHash;
    address public immutable loanRegistry;
    address public immutable policyRegistry;
    address public immutable assetRegistry;
    address public immutable roleManager;
    address public immutable emergencyController;
    address public immutable feeRouter;
    address public immutable treasury;

    constructor(
        uint32 protocolVersion_,
        address loanRegistry_,
        address policyRegistry_,
        address assetRegistry_,
        address roleManager_,
        address emergencyController_,
        address feeRouter_,
        address treasury_,
        bytes32 chainConfigHash_
    ) {
        if (
            protocolVersion_ == 0 || loanRegistry_ == address(0) || policyRegistry_ == address(0)
                || assetRegistry_ == address(0) || roleManager_ == address(0)
                || emergencyController_ == address(0) || feeRouter_ == address(0)
                || treasury_ == address(0) || chainConfigHash_ == bytes32(0)
        ) {
            revert InvalidConfiguration();
        }
        protocolVersion = protocolVersion_;
        homeChainId = block.chainid;
        chainConfigHash = chainConfigHash_;
        loanRegistry = loanRegistry_;
        policyRegistry = policyRegistry_;
        assetRegistry = assetRegistry_;
        roleManager = roleManager_;
        emergencyController = emergencyController_;
        feeRouter = feeRouter_;
        treasury = treasury_;
    }

    function isPaused(bytes32 capability) external view returns (bool) {
        (bool active,,) = IEmergencyController(emergencyController).emergencyState(capability);
        return active;
    }
}
