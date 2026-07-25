// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IInsuranceReserveVault } from "../interfaces/phase9/IInsuranceReserveVault.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9ProtectionTypes } from "./Phase9ProtectionTypes.sol";

/// @notice ABI/storage freeze stub for segregated product-pool reserve custody.
contract InsuranceReserveVault is IInsuranceReserveVault {
    address private _assetRegistry;
    address private _insuranceManager;
    mapping(bytes32 poolId => mapping(bytes32 assetId => uint256 units)) private _custodyUnits;
    mapping(bytes32 fundingEventId => Phase9ProtectionTypes.ReserveFundingResult result) private
        _fundingResults;
    mapping(bytes32 claimPaymentId => Phase9ProtectionTypes.ClaimPayment result) private
        _claimPayments;

    constructor(address assetRegistry_, address insuranceManager_) {
        _assetRegistry = assetRegistry_;
        _insuranceManager = insuranceManager_;
    }

    function fundReserve(Phase9ProtectionTypes.ReserveFundingResult calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function fundPremium(Phase9ProtectionTypes.PremiumEvidence calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function payClaim(Phase9ProtectionTypes.ClaimPayment calldata) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function custody(bytes32 poolId, bytes32 assetId) external view override returns (uint256) {
        return _custodyUnits[poolId][assetId];
    }

    function fundingResult(bytes32 fundingEventId)
        external
        view
        override
        returns (Phase9ProtectionTypes.ReserveFundingResult memory)
    {
        return _fundingResults[fundingEventId];
    }

    function claimPayment(bytes32 claimPaymentId)
        external
        view
        override
        returns (Phase9ProtectionTypes.ClaimPayment memory)
    {
        return _claimPayments[claimPaymentId];
    }
}
