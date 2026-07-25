// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface ICrossChainLoanPolicy is IERC165 {
    struct Configuration {
        bytes32 protocolId;
        uint256 homeChainId;
        uint256 satelliteChainId;
        address homeCoordinator;
        address satelliteCoordinator;
        address homeLoanRouter;
        address homeBridgeHub;
        address wrappedUFT;
        address satelliteComponent;
        address satelliteCollateralVault;
        address satelliteSettlementVault;
        address canonicalUFT;
        address collateralToken;
        bytes32 mintRouteHash;
        bytes32 reportRouteHash;
        bytes32 repaymentRouteHash;
        bytes32 disbursementRouteHash;
        bytes32 collateralReleaseRouteHash;
        bytes32 policyHash;
    }

    function configuration() external view returns (Configuration memory);
    function configurationHash() external view returns (bytes32);
}
