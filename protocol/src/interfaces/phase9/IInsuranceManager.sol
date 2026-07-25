// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9ProtectionTypes } from "../../protection/Phase9ProtectionTypes.sol";

interface IInsuranceManager {
    error InvalidCoverage();
    error InvalidInsuranceClaim();
    error InvalidClaimDecision();
    error InsuranceOperationReplay(bytes32 operationId);

    event CoverageCreated(bytes32 indexed coverageId, bytes32 indexed loanId, bytes32 indexed poolId, address beneficiary);
    event ClaimSubmitted(bytes32 indexed claimId, bytes32 indexed coverageId, bytes32 indexed lossId, uint256 requestedAmount);
    event ClaimDecisionRecorded(bytes32 indexed decisionId, bytes32 indexed claimId, uint256 approvedAmount);
    event ClaimPaymentRecorded(bytes32 indexed claimPaymentId, bytes32 indexed claimId, address indexed beneficiary, uint256 amount);

    function registerPolicyVersion(Phase9ProtectionTypes.ReservePolicyVersion calldata policy_) external;
    function setActivePolicy(bytes32 poolId, bytes32 policyVersionId, bytes32 operationId) external;
    function createCoverage(Phase9ProtectionTypes.LoanCoverage calldata coverage) external;
    function submitClaim(Phase9ProtectionTypes.InsuranceClaim calldata claim_) external;
    function recordDecision(Phase9ProtectionTypes.ClaimDecision calldata decision, bytes[] calldata signatures) external;
    function recordClaimPayment(Phase9ProtectionTypes.ClaimPayment calldata payment) external;
    function registerAdjudicatorSet(Phase9ProtectionTypes.AdjudicatorSet calldata adjudicatorSet) external;
    function coverage(bytes32 coverageId) external view returns (Phase9ProtectionTypes.LoanCoverage memory);
    function claim(bytes32 claimId) external view returns (Phase9ProtectionTypes.InsuranceClaim memory);
    function decision(bytes32 decisionId) external view returns (Phase9ProtectionTypes.ClaimDecision memory);
    function claimPayment(bytes32 claimPaymentId) external view returns (Phase9ProtectionTypes.ClaimPayment memory);
    function activePolicy(bytes32 poolId) external view returns (bytes32);
    function operationProcessed(bytes32 operationId) external view returns (bool);
}
