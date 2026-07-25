// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { CrossChainTypes } from "../crosschain/CrossChainTypes.sol";

interface ISatelliteLoanComponent {
    function provisionedLoan(bytes32 loanId)
        external
        view
        returns (CrossChainTypes.SatelliteLoanProvisioning memory);

    function backingRoutePolicyHash() external view returns (bytes32);

    function reportMintConfirmed(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        returns (bytes32 messageId);

    function reportCollateralLocked(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        returns (bytes32 messageId);

    function reportDisbursementSettled(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        returns (bytes32 messageId);

    function reportFundingCancellation(
        CrossChainTypes.SatelliteFundingCancelledPayload calldata cancellation
    ) external returns (bytes32 messageId);

    function reportCollateralReleased(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        returns (bytes32 messageId);
}

interface ISatelliteLoanProvisioner {
    function provisionLoan(CrossChainTypes.SatelliteLoanProvisioning calldata provisioning) external;
}
