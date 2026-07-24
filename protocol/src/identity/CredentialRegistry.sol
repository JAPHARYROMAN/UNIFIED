// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { IdentityProviderRegistry } from "./IdentityProviderRegistry.sol";
import { IdentityTypes } from "./IdentityTypes.sol";

/// @notice Commitment-only credential envelopes with prospective revocation.
contract CredentialRegistry is RoleControlled {
    error InvalidCredential();
    error UnknownCredential(bytes32 credentialId);
    error CredentialAlreadyRevoked(bytes32 credentialId);

    uint64 public constant MAX_CREDENTIAL_VALIDITY = 730 days;

    IdentityProviderRegistry public immutable providerRegistry;
    mapping(bytes32 credentialId => IdentityTypes.Credential credential_) private _credentials;
    bytes32[] private _credentialIds;

    event CredentialIssued(
        bytes32 indexed credentialId,
        bytes32 indexed subjectCommitment,
        address indexed boundAccount,
        bytes32 providerId,
        bytes32 schemaId,
        bytes32 claimsCommitment,
        bytes32 scopeHash,
        uint64 epoch,
        uint16 assurance,
        uint64 validFrom,
        uint64 validUntil
    );
    event CredentialRevoked(
        bytes32 indexed credentialId, address indexed sender, bytes32 indexed evidenceHash
    );

    constructor(IRoleManager roleManager_, IdentityProviderRegistry providerRegistry_)
        RoleControlled(roleManager_)
    {
        if (address(providerRegistry_).code.length == 0) revert InvalidCredential();
        providerRegistry = providerRegistry_;
    }

    function issueCredential(IdentityTypes.CredentialInput calldata input)
        external
        onlyRole(ProtocolRoles.CREDENTIAL_ISSUER_ROLE)
    {
        if (
            input.credentialId == bytes32(0) || input.subjectCommitment == bytes32(0)
                || input.boundAccount == address(0) || input.providerId == bytes32(0)
                || input.schemaId == bytes32(0) || input.claimsCommitment == bytes32(0)
                || input.scopeHash == bytes32(0) || input.epoch == 0 || input.assurance == 0
                || input.validFrom < block.timestamp || input.validUntil <= input.validFrom
                || input.validUntil - input.validFrom > MAX_CREDENTIAL_VALIDITY
                || _credentials[input.credentialId].status != IdentityTypes.CredentialStatus.NONE
                || !providerRegistry.isIssuerApproved(
                    input.providerId, input.schemaId, msg.sender, input.assurance
                )
        ) {
            revert InvalidCredential();
        }
        _credentials[input.credentialId] = IdentityTypes.Credential({
            credentialId: input.credentialId,
            subjectCommitment: input.subjectCommitment,
            boundAccount: input.boundAccount,
            providerId: input.providerId,
            schemaId: input.schemaId,
            claimsCommitment: input.claimsCommitment,
            scopeHash: input.scopeHash,
            epoch: input.epoch,
            assurance: input.assurance,
            validFrom: input.validFrom,
            validUntil: input.validUntil,
            issuedAt: uint64(block.timestamp),
            revokedAt: 0,
            issuer: msg.sender,
            status: IdentityTypes.CredentialStatus.ACTIVE
        });
        _credentialIds.push(input.credentialId);
        emit CredentialIssued(
            input.credentialId,
            input.subjectCommitment,
            input.boundAccount,
            input.providerId,
            input.schemaId,
            input.claimsCommitment,
            input.scopeHash,
            input.epoch,
            input.assurance,
            input.validFrom,
            input.validUntil
        );
    }

    function revokeCredential(bytes32 credentialId, bytes32 evidenceHash) external {
        IdentityTypes.Credential storage credential_ = _credential(credentialId);
        bool authorized = msg.sender == credential_.issuer
            || roleManager.hasRole(ProtocolRoles.IDENTITY_REVOCATION_ROLE, msg.sender);
        if (!authorized) {
            revert Unauthorized(ProtocolRoles.IDENTITY_REVOCATION_ROLE, msg.sender);
        }
        if (credential_.status == IdentityTypes.CredentialStatus.REVOKED) {
            revert CredentialAlreadyRevoked(credentialId);
        }
        if (evidenceHash == bytes32(0)) revert InvalidCredential();
        credential_.status = IdentityTypes.CredentialStatus.REVOKED;
        credential_.revokedAt = uint64(block.timestamp);
        emit CredentialRevoked(credentialId, msg.sender, evidenceHash);
    }

    function isUsable(
        bytes32 credentialId,
        address account,
        bytes32 subjectCommitment,
        bytes32 scopeHash,
        uint64 epoch,
        uint16 minimumAssurance
    ) public view returns (bool) {
        IdentityTypes.Credential storage credential_ = _credentials[credentialId];
        if (
            credential_.status != IdentityTypes.CredentialStatus.ACTIVE
                || credential_.boundAccount != account
                || credential_.subjectCommitment != subjectCommitment
                || credential_.scopeHash != scopeHash || credential_.epoch != epoch
                || credential_.assurance < minimumAssurance
                || block.timestamp < credential_.validFrom
                || block.timestamp >= credential_.validUntil
        ) {
            return false;
        }
        return providerRegistry.isIssuerApproved(
            credential_.providerId, credential_.schemaId, credential_.issuer, credential_.assurance
        );
    }

    function credential(bytes32 credentialId)
        external
        view
        returns (IdentityTypes.Credential memory)
    {
        return _credential(credentialId);
    }

    function credentialIds() external view returns (bytes32[] memory) {
        return _credentialIds;
    }

    function _credential(bytes32 credentialId)
        private
        view
        returns (IdentityTypes.Credential storage credential_)
    {
        credential_ = _credentials[credentialId];
        if (credential_.status == IdentityTypes.CredentialStatus.NONE) {
            revert UnknownCredential(credentialId);
        }
    }
}
