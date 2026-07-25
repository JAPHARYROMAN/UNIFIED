// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ICrossChainLoanPolicy } from "../interfaces/ICrossChainLoanPolicy.sol";

/// @notice Immutable first-slice policy binding every home/satellite authority and route.
contract CrossChainLoanPolicy is ICrossChainLoanPolicy {
    error InvalidCrossChainLoanPolicy();

    Configuration private _configuration;
    bytes32 private immutable _configurationHash;

    constructor(Configuration memory config) {
        if (
            config.protocolId == bytes32(0) || config.homeChainId == 0
                || config.satelliteChainId == 0 || config.homeChainId == config.satelliteChainId
                || config.homeCoordinator == address(0) || config.satelliteCoordinator == address(0)
                || config.homeLoanRouter == address(0) || config.homeBridgeHub == address(0)
                || config.wrappedUFT == address(0) || config.satelliteComponent == address(0)
                || config.satelliteCollateralVault == address(0)
                || config.satelliteSettlementVault == address(0)
                || config.canonicalUFT == address(0) || config.collateralToken == address(0)
                || config.mintRouteHash == bytes32(0) || config.reportRouteHash == bytes32(0)
                || config.repaymentRouteHash == bytes32(0)
                || config.disbursementRouteHash == bytes32(0)
                || config.collateralReleaseRouteHash == bytes32(0)
                || config.policyHash == bytes32(0)
        ) {
            revert InvalidCrossChainLoanPolicy();
        }
        if (
            (block.chainid == config.homeChainId
                    && (config.homeCoordinator.code.length == 0
                        || config.homeLoanRouter.code.length == 0
                        || config.homeBridgeHub.code.length == 0
                        || config.canonicalUFT.code.length == 0))
                || (block.chainid == config.satelliteChainId
                    && (config.satelliteCoordinator.code.length == 0
                        || config.wrappedUFT.code.length == 0
                        || config.satelliteComponent.code.length == 0
                        || config.satelliteCollateralVault.code.length == 0
                        || config.satelliteSettlementVault.code.length == 0
                        || config.collateralToken.code.length == 0))
                || (block.chainid != config.homeChainId && block.chainid != config.satelliteChainId)
        ) {
            revert InvalidCrossChainLoanPolicy();
        }
        _configuration = config;
        _configurationHash = keccak256(abi.encode("UNIFIED_CROSS_CHAIN_LOAN_POLICY_V1", config));
    }

    function configuration() external view override returns (Configuration memory) {
        return _configuration;
    }

    function configurationHash() external view override returns (bytes32) {
        return _configurationHash;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(ICrossChainLoanPolicy).interfaceId;
    }
}
