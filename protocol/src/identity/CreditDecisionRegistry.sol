// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CredentialRegistry } from "./CredentialRegistry.sol";
import { IdentityTypes } from "./IdentityTypes.sol";

/// @notice Immutable approved decision attestations with public provenance only.
contract CreditDecisionRegistry is RoleControlled {
    error InvalidDecision();
    error UnknownDecision(bytes32 decisionId);
    error DecisionAlreadyRevoked(bytes32 decisionId);

    uint64 public constant MAX_FEATURE_AGE = 30 days;
    uint64 public constant MAX_DECISION_VALIDITY = 90 days;

    CredentialRegistry public immutable credentialRegistry;
    mapping(bytes32 decisionId => IdentityTypes.CreditDecision decision_) private _decisions;
    bytes32[] private _decisionIds;
    mapping(
        bytes32 subjectCommitment
            => mapping(bytes32 assetId => mapping(bytes32 productHash => bytes32 decisionId))
    ) private _currentDecisionIds;

    event CreditDecisionIssued(
        bytes32 indexed decisionId,
        bytes32 indexed subjectCommitment,
        address indexed borrower,
        bytes32 previousDecisionId,
        uint64 sequence,
        bytes32 credentialId,
        bytes32 policyId,
        bytes32 settlementAssetId,
        bytes32 productHash,
        uint256 maximumExposure,
        uint64 maximumDuration,
        uint64 expiresAt
    );
    event CreditDecisionRevoked(
        bytes32 indexed decisionId, address indexed sender, bytes32 indexed evidenceHash
    );

    constructor(IRoleManager roleManager_, CredentialRegistry credentialRegistry_)
        RoleControlled(roleManager_)
    {
        if (address(credentialRegistry_).code.length == 0) revert InvalidDecision();
        credentialRegistry = credentialRegistry_;
    }

    function issueDecision(IdentityTypes.CreditDecisionInput calldata input)
        external
        onlyRole(ProtocolRoles.UNDERWRITER_ROLE)
    {
        bytes32 currentId = _currentDecisionIds[
            input.subjectCommitment
        ][input.settlementAssetId][input.productHash];
        if (
            input.decisionId == bytes32(0) || input.credentialId == bytes32(0)
                || input.subjectCommitment == bytes32(0) || input.borrower == address(0)
                || input.credentialScopeHash == bytes32(0) || input.credentialEpoch == 0
                || input.minimumAssurance == 0 || input.policyId == bytes32(0)
                || input.policyMajor == 0 || input.ruleSetHash == bytes32(0)
                || input.modelSetHash == bytes32(0) || input.featureEvidenceRoot == bytes32(0)
                || input.featureSchemaHash == bytes32(0) || input.featuresAsOf > block.timestamp
                || block.timestamp - input.featuresAsOf > MAX_FEATURE_AGE
                || input.settlementAssetId == bytes32(0) || input.productHash == bytes32(0)
                || input.maximumExposure == 0 || input.maximumDuration == 0
                || input.expiresAt <= block.timestamp
                || input.expiresAt - block.timestamp > MAX_DECISION_VALIDITY
                || input.reasonCodesHash == bytes32(0)
                || _decisions[input.decisionId].status != IdentityTypes.DecisionStatus.NONE
                || !_validLineage(input, currentId)
                || !credentialRegistry.isUsable(
                    input.credentialId,
                    input.borrower,
                    input.subjectCommitment,
                    input.credentialScopeHash,
                    input.credentialEpoch,
                    input.minimumAssurance
                )
        ) {
            revert InvalidDecision();
        }
        _decisions[input.decisionId] = IdentityTypes.CreditDecision({
            decisionId: input.decisionId,
            previousDecisionId: input.previousDecisionId,
            credentialId: input.credentialId,
            subjectCommitment: input.subjectCommitment,
            borrower: input.borrower,
            credentialScopeHash: input.credentialScopeHash,
            credentialEpoch: input.credentialEpoch,
            minimumAssurance: input.minimumAssurance,
            policyId: input.policyId,
            policyMajor: input.policyMajor,
            policyMinor: input.policyMinor,
            policyPatch: input.policyPatch,
            ruleSetHash: input.ruleSetHash,
            modelSetHash: input.modelSetHash,
            featureEvidenceRoot: input.featureEvidenceRoot,
            featureSchemaHash: input.featureSchemaHash,
            featuresAsOf: input.featuresAsOf,
            settlementAssetId: input.settlementAssetId,
            productHash: input.productHash,
            maximumExposure: input.maximumExposure,
            maximumDuration: input.maximumDuration,
            issuedAt: uint64(block.timestamp),
            expiresAt: input.expiresAt,
            sequence: input.sequence,
            reasonCodesHash: input.reasonCodesHash,
            underwriter: msg.sender,
            revokedAt: 0,
            status: IdentityTypes.DecisionStatus.ACTIVE
        });
        _decisionIds.push(input.decisionId);
        _currentDecisionIds[input.subjectCommitment][input.settlementAssetId][input.productHash] =
        input.decisionId;
        emit CreditDecisionIssued(
            input.decisionId,
            input.subjectCommitment,
            input.borrower,
            input.previousDecisionId,
            input.sequence,
            input.credentialId,
            input.policyId,
            input.settlementAssetId,
            input.productHash,
            input.maximumExposure,
            input.maximumDuration,
            input.expiresAt
        );
    }

    function revokeDecision(bytes32 decisionId, bytes32 evidenceHash) external {
        IdentityTypes.CreditDecision storage decision_ = _decision(decisionId);
        bool authorized = msg.sender == decision_.underwriter
            || roleManager.hasRole(ProtocolRoles.IDENTITY_REVOCATION_ROLE, msg.sender);
        if (!authorized) {
            revert Unauthorized(ProtocolRoles.IDENTITY_REVOCATION_ROLE, msg.sender);
        }
        if (decision_.status == IdentityTypes.DecisionStatus.REVOKED) {
            revert DecisionAlreadyRevoked(decisionId);
        }
        if (evidenceHash == bytes32(0)) revert InvalidDecision();
        decision_.status = IdentityTypes.DecisionStatus.REVOKED;
        decision_.revokedAt = uint64(block.timestamp);
        emit CreditDecisionRevoked(decisionId, msg.sender, evidenceHash);
    }

    function isUsable(
        bytes32 decisionId,
        address borrower,
        bytes32 subjectCommitment,
        bytes32 settlementAssetId,
        bytes32 productHash,
        uint256 amount,
        uint64 duration
    ) public view returns (bool) {
        IdentityTypes.CreditDecision storage decision_ = _decisions[decisionId];
        if (
            decision_.status != IdentityTypes.DecisionStatus.ACTIVE
                || _currentDecisionIds[subjectCommitment][settlementAssetId][productHash]
                    != decisionId || decision_.borrower != borrower
                || decision_.subjectCommitment != subjectCommitment
                || decision_.settlementAssetId != settlementAssetId
                || decision_.productHash != productHash || amount == 0
                || amount > decision_.maximumExposure || duration == 0
                || duration > decision_.maximumDuration || block.timestamp >= decision_.expiresAt
        ) {
            return false;
        }
        return credentialRegistry.isUsable(
            decision_.credentialId,
            borrower,
            subjectCommitment,
            decision_.credentialScopeHash,
            decision_.credentialEpoch,
            decision_.minimumAssurance
        );
    }

    function decision(bytes32 decisionId)
        external
        view
        returns (IdentityTypes.CreditDecision memory)
    {
        return _decision(decisionId);
    }

    function decisionIds() external view returns (bytes32[] memory) {
        return _decisionIds;
    }

    function currentDecisionId(
        bytes32 subjectCommitment,
        bytes32 settlementAssetId,
        bytes32 productHash
    ) external view returns (bytes32) {
        return _currentDecisionIds[subjectCommitment][settlementAssetId][productHash];
    }

    function _validLineage(IdentityTypes.CreditDecisionInput calldata input, bytes32 currentId)
        private
        view
        returns (bool)
    {
        if (currentId == bytes32(0)) {
            return input.previousDecisionId == bytes32(0) && input.sequence == 1;
        }
        IdentityTypes.CreditDecision storage current = _decisions[currentId];
        return input.previousDecisionId == currentId && input.sequence == current.sequence + 1;
    }

    function _decision(bytes32 decisionId)
        private
        view
        returns (IdentityTypes.CreditDecision storage decision_)
    {
        decision_ = _decisions[decisionId];
        if (decision_.status == IdentityTypes.DecisionStatus.NONE) {
            revert UnknownDecision(decisionId);
        }
    }
}
