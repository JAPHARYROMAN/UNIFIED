// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IInsuranceManager } from "../interfaces/phase9/IInsuranceManager.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9ProtectionTypes } from "./Phase9ProtectionTypes.sol";

/// @notice ABI/storage freeze stub for coverage, adjudication, and exact claim payment.
contract InsuranceManager is IInsuranceManager {
    address private _reserveVault;
    address private _reservePolicy;
    address private _recoveryManager;
    address private _settlementToken;
    mapping(bytes32 policyHash => Phase9ProtectionTypes.ReservePolicyVersion policy_)
        private _policyVersions;
    mapping(bytes32 poolId => bytes32 policyHash) private _activePolicyHashes;
    mapping(bytes32 coverageId => Phase9ProtectionTypes.LoanCoverage coverage_)
        private _coverages;
    mapping(bytes32 claimId => Phase9ProtectionTypes.InsuranceClaim claim_) private _claims;
    mapping(bytes32 decisionId => Phase9ProtectionTypes.ClaimDecision decision_)
        private _decisions;
    mapping(bytes32 claimPaymentId => Phase9ProtectionTypes.ClaimPayment payment)
        private _claimPayments;
    mapping(bytes32 adjudicatorSetHash => Phase9ProtectionTypes.AdjudicatorSet adjudicatorSet)
        private _adjudicatorSets;
    mapping(bytes32 signatureId => bool processed) private _processedSignatureIds;
    mapping(bytes32 operationId => bool processed) private _processedOperationIds;

    constructor(
        address reserveVault_,
        address reservePolicy_,
        address recoveryManager_,
        address settlementToken_
    ) {
        _reserveVault = reserveVault_;
        _reservePolicy = reservePolicy_;
        _recoveryManager = recoveryManager_;
        _settlementToken = settlementToken_;
    }

    function registerPolicyVersion(Phase9ProtectionTypes.ReservePolicyVersion calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function setActivePolicy(bytes32, bytes32, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function createCoverage(Phase9ProtectionTypes.LoanCoverage calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function submitClaim(Phase9ProtectionTypes.InsuranceClaim calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function recordDecision(Phase9ProtectionTypes.ClaimDecision calldata, bytes[] calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function recordClaimPayment(Phase9ProtectionTypes.ClaimPayment calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function registerAdjudicatorSet(Phase9ProtectionTypes.AdjudicatorSet calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function coverage(bytes32 coverageId)
        external
        view
        override
        returns (Phase9ProtectionTypes.LoanCoverage memory)
    {
        return _coverages[coverageId];
    }

    function claim(bytes32 claimId)
        external
        view
        override
        returns (Phase9ProtectionTypes.InsuranceClaim memory)
    {
        return _claims[claimId];
    }

    function decision(bytes32 decisionId)
        external
        view
        override
        returns (Phase9ProtectionTypes.ClaimDecision memory)
    {
        return _decisions[decisionId];
    }

    function claimPayment(bytes32 claimPaymentId)
        external
        view
        override
        returns (Phase9ProtectionTypes.ClaimPayment memory)
    {
        return _claimPayments[claimPaymentId];
    }

    function activePolicy(bytes32 poolId) external view override returns (bytes32) {
        return _activePolicyHashes[poolId];
    }

    function operationProcessed(bytes32 operationId) external view override returns (bool) {
        return _processedOperationIds[operationId];
    }
}
