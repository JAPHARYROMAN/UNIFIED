// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9ProtectionTypes } from "../../protection/Phase9ProtectionTypes.sol";

interface IInsuranceReserveVault {
    error InvalidReserveOperation();
    error ReserveFundingReplay(bytes32 fundingEventId);
    error ClaimPaymentReplay(bytes32 claimPaymentId);

    event ReserveFunded(bytes32 indexed fundingEventId, bytes32 indexed poolId, bytes32 indexed assetId, uint256 amount);
    event PremiumFunded(bytes32 indexed premiumEventId, bytes32 indexed coverageId, uint256 amount);
    event ClaimPaid(bytes32 indexed claimPaymentId, bytes32 indexed claimId, address indexed beneficiary, uint256 amount);

    function fundReserve(Phase9ProtectionTypes.ReserveFundingResult calldata funding) external;
    function fundPremium(Phase9ProtectionTypes.PremiumEvidence calldata premium) external;
    function payClaim(Phase9ProtectionTypes.ClaimPayment calldata payment) external;
    function custody(bytes32 poolId, bytes32 assetId) external view returns (uint256);
    function fundingResult(bytes32 fundingEventId) external view returns (Phase9ProtectionTypes.ReserveFundingResult memory);
    function claimPayment(bytes32 claimPaymentId) external view returns (Phase9ProtectionTypes.ClaimPayment memory);
}
