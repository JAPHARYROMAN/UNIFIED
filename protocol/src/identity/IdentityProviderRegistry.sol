// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { IdentityTypes } from "./IdentityTypes.sol";

/// @notice Public provider and credential-schema authority without raw identity data.
contract IdentityProviderRegistry is RoleControlled {
    error InvalidProvider();
    error UnknownProvider(bytes32 providerId);
    error InvalidSchema();
    error UnknownSchema(bytes32 schemaId);
    error InvalidStatusTransition();

    mapping(bytes32 providerId => IdentityTypes.ProviderRecord provider_) private _providers;
    bytes32[] private _providerIds;
    mapping(bytes32 schemaId => IdentityTypes.CredentialSchema schema_) private _schemas;
    bytes32[] private _schemaIds;

    event IdentityProviderRegistered(
        bytes32 indexed providerId,
        address indexed operator,
        bytes32 indexed metadataHash,
        uint16 maximumAssurance
    );
    event IdentityProviderStatusChanged(
        bytes32 indexed providerId,
        IdentityTypes.ProviderStatus status,
        bytes32 indexed evidenceHash
    );
    event CredentialSchemaRegistered(
        bytes32 indexed schemaId,
        bytes32 indexed providerId,
        bytes32 indexed definitionHash,
        uint16 maximumAssurance
    );
    event CredentialSchemaStatusChanged(
        bytes32 indexed schemaId, bool active, bytes32 indexed evidenceHash
    );

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function registerProvider(
        bytes32 providerId,
        address operator,
        bytes32 metadataHash,
        uint16 maximumAssurance
    ) external onlyRole(ProtocolRoles.IDENTITY_REGISTRAR_ROLE) {
        if (
            providerId == bytes32(0) || operator == address(0) || metadataHash == bytes32(0)
                || maximumAssurance == 0
                || _providers[providerId].status != IdentityTypes.ProviderStatus.NONE
        ) {
            revert InvalidProvider();
        }
        _providers[providerId] = IdentityTypes.ProviderRecord({
            providerId: providerId,
            operator: operator,
            metadataHash: metadataHash,
            maximumAssurance: maximumAssurance,
            registeredAt: uint64(block.timestamp),
            status: IdentityTypes.ProviderStatus.ACTIVE
        });
        _providerIds.push(providerId);
        emit IdentityProviderRegistered(providerId, operator, metadataHash, maximumAssurance);
    }

    function setProviderStatus(
        bytes32 providerId,
        IdentityTypes.ProviderStatus status,
        bytes32 evidenceHash
    ) external {
        IdentityTypes.ProviderRecord storage provider_ = _provider(providerId);
        if (
            status == IdentityTypes.ProviderStatus.NONE || status == provider_.status
                || evidenceHash == bytes32(0)
        ) {
            revert InvalidStatusTransition();
        }
        bool registrar = roleManager.hasRole(ProtocolRoles.IDENTITY_REGISTRAR_ROLE, msg.sender);
        bool revoker = roleManager.hasRole(ProtocolRoles.IDENTITY_REVOCATION_ROLE, msg.sender);
        if (!registrar && !revoker) {
            revert Unauthorized(ProtocolRoles.IDENTITY_REGISTRAR_ROLE, msg.sender);
        }
        if (
            provider_.status == IdentityTypes.ProviderStatus.RETIRED
                || (status == IdentityTypes.ProviderStatus.ACTIVE && !registrar)
        ) {
            revert InvalidStatusTransition();
        }
        provider_.status = status;
        emit IdentityProviderStatusChanged(providerId, status, evidenceHash);
    }

    function registerSchema(
        bytes32 schemaId,
        bytes32 providerId,
        bytes32 definitionHash,
        uint16 maximumAssurance
    ) external onlyRole(ProtocolRoles.IDENTITY_REGISTRAR_ROLE) {
        IdentityTypes.ProviderRecord storage provider_ = _provider(providerId);
        if (
            provider_.status != IdentityTypes.ProviderStatus.ACTIVE || schemaId == bytes32(0)
                || definitionHash == bytes32(0) || maximumAssurance == 0
                || maximumAssurance > provider_.maximumAssurance
                || _schemas[schemaId].schemaId != bytes32(0)
        ) {
            revert InvalidSchema();
        }
        _schemas[schemaId] = IdentityTypes.CredentialSchema({
            schemaId: schemaId,
            providerId: providerId,
            definitionHash: definitionHash,
            maximumAssurance: maximumAssurance,
            registeredAt: uint64(block.timestamp),
            active: true
        });
        _schemaIds.push(schemaId);
        emit CredentialSchemaRegistered(schemaId, providerId, definitionHash, maximumAssurance);
    }

    function setSchemaActive(bytes32 schemaId, bool active, bytes32 evidenceHash) external {
        IdentityTypes.CredentialSchema storage schema_ = _schema(schemaId);
        if (schema_.active == active || evidenceHash == bytes32(0)) {
            revert InvalidStatusTransition();
        }
        bool registrar = roleManager.hasRole(ProtocolRoles.IDENTITY_REGISTRAR_ROLE, msg.sender);
        bool revoker = roleManager.hasRole(ProtocolRoles.IDENTITY_REVOCATION_ROLE, msg.sender);
        if (!registrar && !revoker) {
            revert Unauthorized(ProtocolRoles.IDENTITY_REGISTRAR_ROLE, msg.sender);
        }
        if (
            active
                && (!registrar
                    || _providers[schema_.providerId].status != IdentityTypes.ProviderStatus.ACTIVE)
        ) {
            revert InvalidStatusTransition();
        }
        schema_.active = active;
        emit CredentialSchemaStatusChanged(schemaId, active, evidenceHash);
    }

    function isIssuerApproved(
        bytes32 providerId,
        bytes32 schemaId,
        address operator,
        uint16 assurance
    ) external view returns (bool) {
        IdentityTypes.ProviderRecord storage provider_ = _providers[providerId];
        IdentityTypes.CredentialSchema storage schema_ = _schemas[schemaId];
        return provider_.status == IdentityTypes.ProviderStatus.ACTIVE
            && provider_.operator == operator && schema_.active && schema_.providerId == providerId
            && assurance != 0 && assurance <= provider_.maximumAssurance
            && assurance <= schema_.maximumAssurance;
    }

    function provider(bytes32 providerId)
        external
        view
        returns (IdentityTypes.ProviderRecord memory)
    {
        return _provider(providerId);
    }

    function schema(bytes32 schemaId)
        external
        view
        returns (IdentityTypes.CredentialSchema memory)
    {
        return _schema(schemaId);
    }

    function providerIds() external view returns (bytes32[] memory) {
        return _providerIds;
    }

    function schemaIds() external view returns (bytes32[] memory) {
        return _schemaIds;
    }

    function _provider(bytes32 providerId)
        private
        view
        returns (IdentityTypes.ProviderRecord storage provider_)
    {
        provider_ = _providers[providerId];
        if (provider_.status == IdentityTypes.ProviderStatus.NONE) {
            revert UnknownProvider(providerId);
        }
    }

    function _schema(bytes32 schemaId)
        private
        view
        returns (IdentityTypes.CredentialSchema storage schema_)
    {
        schema_ = _schemas[schemaId];
        if (schema_.schemaId == bytes32(0)) revert UnknownSchema(schemaId);
    }
}
