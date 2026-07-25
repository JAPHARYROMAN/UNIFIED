// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { ChainRegistry } from "./ChainRegistry.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";

/// @notice Local-only finality verifier for observer evidence plus 2-of-3 attestations.
/// @dev This contract does not verify the observer's Ed25519 signature. Each threshold signer
/// attests that it independently verified that signature against the pinned observer authority.
/// The exact signature and canonical signed-header commitment are included in sourceProofHash,
/// so neither an observer artifact nor threshold signatures can be substituted after signing.
/// This synthetic verifier is not a consensus client and must not be used for production finality.
contract SyntheticFinalityVerifier is RoleControlled {
    using ECDSA for bytes32;

    error InvalidSignerSet();
    error UnknownSignerSet(bytes32 signerSetHash);
    error InvalidFinalityPolicy();
    error UnknownFinalityPolicy(bytes32 policyHash);
    error InvalidFinalityProof();
    error InsufficientFinalityAttestations(uint256 valid, uint256 required);

    uint8 public constant SIGNER_COUNT = 3;
    uint8 public constant THRESHOLD = 2;
    ChainRegistry public immutable chainRegistry;

    struct SignerSet {
        bytes32 signerSetHash;
        bytes32 observerAuthorityHash;
        uint32 version;
        address[3] signers;
        uint64 validFrom;
        uint64 validUntil;
        bool active;
    }

    struct FinalityPolicyConfig {
        bool destinationEvidence;
        uint256 sourceChainId;
        address sourceCoordinator;
        address sourceComponent;
        uint256 destinationChainId;
        address destinationCoordinator;
        address destinationComponent;
        uint32 evidenceChainVersion;
        bytes32 evidenceChainConfigurationHash;
        bytes32 actionFamily;
        uint32 allowedActionsBitmap;
        uint64 requiredDepth;
        bytes32 observerAuthorityHash;
        bytes32 signerSetHash;
        uint32 signerSetVersion;
    }

    mapping(bytes32 signerSetHash => SignerSet signerSet) private _signerSets;
    mapping(bytes32 policyHash => FinalityPolicyConfig config) private _finalityPolicies;

    event SignerSetRegistered(
        bytes32 indexed signerSetHash,
        bytes32 indexed observerAuthorityHash,
        uint32 indexed version,
        address[3] signers,
        uint64 validFrom,
        uint64 validUntil
    );
    event SignerSetDisabled(bytes32 indexed signerSetHash);
    event FinalityPolicyRegistered(
        bytes32 indexed policyHash,
        bytes32 indexed signerSetHash,
        bool indexed destinationEvidence,
        uint256 evidenceChainId,
        uint32 evidenceChainVersion,
        uint64 requiredDepth,
        bytes32 actionFamily,
        uint32 allowedActionsBitmap,
        bytes32 evidenceChainConfigurationHash
    );

    constructor(IRoleManager roleManager_, ChainRegistry chainRegistry_)
        RoleControlled(roleManager_)
    {
        if (address(chainRegistry_) == address(0)) revert InvalidFinalityPolicy();
        chainRegistry = chainRegistry_;
    }

    function registerSignerSet(
        bytes32 observerAuthorityHash,
        uint32 version,
        address[3] calldata signers,
        uint64 validFrom,
        uint64 validUntil
    ) external onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE) returns (bytes32 signerSetHash) {
        if (
            observerAuthorityHash == bytes32(0) || version == 0 || validFrom < block.timestamp
                || validUntil <= validFrom || signers[0] == address(0) || signers[1] == address(0)
                || signers[2] == address(0) || signers[0] == signers[1] || signers[0] == signers[2]
                || signers[1] == signers[2]
        ) {
            revert InvalidSignerSet();
        }
        signerSetHash = keccak256(
            abi.encode(
                "UNIFIED_SYNTHETIC_SIGNER_SET_V1",
                observerAuthorityHash,
                version,
                signers,
                THRESHOLD,
                validFrom,
                validUntil
            )
        );
        if (_signerSets[signerSetHash].signerSetHash != bytes32(0)) {
            revert InvalidSignerSet();
        }
        _signerSets[signerSetHash] = SignerSet({
            signerSetHash: signerSetHash,
            observerAuthorityHash: observerAuthorityHash,
            version: version,
            signers: signers,
            validFrom: validFrom,
            validUntil: validUntil,
            active: true
        });
        emit SignerSetRegistered(
            signerSetHash, observerAuthorityHash, version, signers, validFrom, validUntil
        );
    }

    function disableSignerSet(bytes32 signerSetHash)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        SignerSet storage record = _signerSets[signerSetHash];
        if (record.signerSetHash == bytes32(0)) revert UnknownSignerSet(signerSetHash);
        record.active = false;
        emit SignerSetDisabled(signerSetHash);
    }

    function registerFinalityPolicy(FinalityPolicyConfig calldata config)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
        returns (bytes32 policyHash)
    {
        SignerSet storage signerSet = _signerSets[config.signerSetHash];
        uint256 evidenceChainId =
            config.destinationEvidence ? config.destinationChainId : config.sourceChainId;
        address evidenceCoordinator =
            config.destinationEvidence ? config.destinationCoordinator : config.sourceCoordinator;
        ChainRegistry.ChainVersion memory chain =
            chainRegistry.chainVersion(evidenceChainId, config.evidenceChainVersion);
        if (
            config.sourceChainId == 0 || config.sourceCoordinator == address(0)
                || config.sourceComponent == address(0) || config.destinationChainId == 0
                || config.sourceChainId == config.destinationChainId
                || config.destinationCoordinator == address(0)
                || config.destinationComponent == address(0) || config.evidenceChainVersion == 0
                || config.evidenceChainConfigurationHash == bytes32(0)
                || config.actionFamily == bytes32(0) || config.allowedActionsBitmap == 0
                || config.requiredDepth == 0 || config.observerAuthorityHash == bytes32(0)
                || signerSet.signerSetHash == bytes32(0) || !signerSet.active
                || config.signerSetVersion != signerSet.version
                || config.observerAuthorityHash != signerSet.observerAuthorityHash
                || chain.coordinator != evidenceCoordinator
                || chain.configurationHash != config.evidenceChainConfigurationHash
                || !chainRegistry.isActiveVersion(evidenceChainId, config.evidenceChainVersion)
        ) {
            revert InvalidFinalityPolicy();
        }
        policyHash = keccak256(abi.encode("UNIFIED_SYNTHETIC_FINALITY_POLICY_V1", config));
        if (_finalityPolicies[policyHash].sourceChainId != 0) {
            revert InvalidFinalityPolicy();
        }
        _finalityPolicies[policyHash] = config;
        emit FinalityPolicyRegistered(
            policyHash,
            config.signerSetHash,
            config.destinationEvidence,
            evidenceChainId,
            config.evidenceChainVersion,
            config.requiredDepth,
            config.actionFamily,
            config.allowedActionsBitmap,
            config.evidenceChainConfigurationHash
        );
    }

    function verify(
        CrossChainTypes.MessageEnvelope calldata envelope,
        CrossChainTypes.SourceEventProof calldata proof,
        CrossChainTypes.FinalityCertificate calldata certificate,
        bytes32 expectedSignerSetHash,
        bytes32 expectedFinalityPolicyHash,
        bytes32 expectedEventHash
    ) external view returns (bool) {
        SignerSet storage record = _signerSets[expectedSignerSetHash];
        if (record.signerSetHash == bytes32(0) || !record.active) {
            revert UnknownSignerSet(expectedSignerSetHash);
        }
        FinalityPolicyConfig storage policy = _finalityPolicies[expectedFinalityPolicyHash];
        if (policy.sourceChainId == 0) {
            revert UnknownFinalityPolicy(expectedFinalityPolicyHash);
        }
        _validatePolicyBinding(envelope, proof, policy, record, expectedSignerSetHash);
        bytes32 recomputedMessageId = CrossChainTypes.messageId(envelope);
        bytes32 proofHash = CrossChainTypes.sourceProofHash(proof);
        if (
            envelope.messageId != recomputedMessageId
                || certificate.messageId != recomputedMessageId
                || certificate.sourceProofHash != proofHash
                || certificate.signerSetHash != expectedSignerSetHash
                || certificate.signerSetVersion != record.version
                || certificate.signatures.length < THRESHOLD
                || certificate.signatures.length > SIGNER_COUNT
                || envelope.createdAt < record.validFrom || envelope.expiresAt > record.validUntil
                || proof.headerAuthorityHash != record.observerAuthorityHash
                || proof.observerSignedHeaderCommitment
                    != CrossChainTypes.observerHeaderCommitment(proof)
                || proof.observerSignature.length == 0 || proof.observerSignature.length > 256
                || proof.finalityPolicyHash != expectedFinalityPolicyHash
                || proof.eventHash != expectedEventHash || proof.sourceBlockHash == bytes32(0)
                || proof.transactionHash == bytes32(0) || proof.receiptRoot == bytes32(0)
                || proof.receiptProofHash == bytes32(0) || proof.finalityHeadHash == bytes32(0)
                || proof.sourceBlockNumber == 0 || proof.sourceBlockTimestamp < envelope.createdAt
                || uint256(proof.finalityHeadNumber)
                    < uint256(proof.sourceBlockNumber) + proof.requiredDepth
        ) {
            revert InvalidFinalityProof();
        }

        bytes32 digest = CrossChainTypes.finalityCertificateDigest(
            address(this),
            block.chainid,
            recomputedMessageId,
            proofHash,
            expectedSignerSetHash,
            record.version
        );
        bool[3] memory seen;
        uint256 valid;
        for (uint256 index = 0; index < certificate.signatures.length; ++index) {
            address recovered = digest.recover(certificate.signatures[index]);
            for (uint256 signerIndex = 0; signerIndex < SIGNER_COUNT; ++signerIndex) {
                if (recovered == record.signers[signerIndex] && !seen[signerIndex]) {
                    seen[signerIndex] = true;
                    ++valid;
                    break;
                }
            }
        }
        if (valid < THRESHOLD) {
            revert InsufficientFinalityAttestations(valid, THRESHOLD);
        }
        return true;
    }

    function _validatePolicyBinding(
        CrossChainTypes.MessageEnvelope calldata envelope,
        CrossChainTypes.SourceEventProof calldata proof,
        FinalityPolicyConfig storage policy,
        SignerSet storage signerSet,
        bytes32 expectedSignerSetHash
    ) private view {
        if (
            policy.signerSetHash != expectedSignerSetHash
                || policy.signerSetVersion != signerSet.version
                || policy.observerAuthorityHash != signerSet.observerAuthorityHash
                || envelope.sourceChainId != policy.sourceChainId
                || envelope.sourceCoordinator != policy.sourceCoordinator
                || envelope.sourceComponent != policy.sourceComponent
                || envelope.destinationChainId != policy.destinationChainId
                || envelope.destinationCoordinator != policy.destinationCoordinator
                || envelope.destinationComponent != policy.destinationComponent
                || envelope.laneId
                    != CrossChainTypes.laneId(
                        envelope.protocolId,
                        envelope.sourceChainId,
                        envelope.sourceComponent,
                        envelope.destinationChainId,
                        envelope.destinationComponent,
                        envelope.aggregateId,
                        policy.actionFamily
                    )
                || policy.allowedActionsBitmap & CrossChainTypes.actionBit(envelope.actionType) == 0
                || proof.requiredDepth != policy.requiredDepth
        ) {
            revert InvalidFinalityProof();
        }
    }

    function signerSetRecord(bytes32 signerSetHash) external view returns (SignerSet memory) {
        SignerSet memory record = _signerSets[signerSetHash];
        if (record.signerSetHash == bytes32(0)) revert UnknownSignerSet(signerSetHash);
        return record;
    }

    function finalityPolicy(bytes32 policyHash)
        external
        view
        returns (FinalityPolicyConfig memory)
    {
        FinalityPolicyConfig memory config = _finalityPolicies[policyHash];
        if (config.sourceChainId == 0) revert UnknownFinalityPolicy(policyHash);
        return config;
    }
}
