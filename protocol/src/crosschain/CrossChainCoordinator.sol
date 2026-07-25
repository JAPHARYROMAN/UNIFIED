// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import { ICrossChainReceiver } from "../interfaces/ICrossChainReceiver.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { RouteRegistry } from "./RouteRegistry.sol";
import { SyntheticFinalityVerifier } from "./SyntheticFinalityVerifier.sol";

/// @notice Typed, ordered, replay-safe local cross-chain message endpoint.
contract CrossChainCoordinator is ICrossChainCoordinator, RoleControlled, ReentrancyGuard {
    error InvalidCoordinatorConfiguration();
    error InvalidMessage();
    error InvalidRoute(bytes32 routePolicyHash);
    error InvalidMessageOrder(bytes32 laneId, uint64 expected, uint64 actual);
    error ConflictingMessage(bytes32 laneId, uint64 nonce);
    error MessageExpired(bytes32 messageId);
    error MessageAlreadyTombstoned(bytes32 messageId);
    error UnauthorizedRecoveryController(address caller);
    error InvalidExecutionResult();

    uint256 public constant MAX_PAYLOAD_BYTES = 16_384;

    bytes32 public immutable override protocolId;
    uint256 public immutable override localChainId;
    RouteRegistry public immutable routeRegistry;
    SyntheticFinalityVerifier public immutable finalityVerifier;
    address public recoveryController;

    mapping(bytes32 laneId => uint64 nonce) public override nextOutboundNonce;
    mapping(bytes32 laneId => uint64 nonce) public nextInboundNonce;
    mapping(bytes32 messageId => CrossChainTypes.MessageEnvelope envelope) private _envelopes;
    mapping(bytes32 messageId => CrossChainTypes.MessageState state) private _messageStates;
    mapping(bytes32 messageId => bytes32 resultHash) public executionResult;
    mapping(bytes32 messageId => bytes32 commitment) public acknowledgementCommitment;
    mapping(bytes32 messageId => bytes32 tombstoneHash) public tombstoneHash;
    mapping(bytes32 laneNonceKey => bytes32 messageId) public inboundMessageAt;

    event MessageSent(
        bytes32 indexed messageId,
        bytes32 indexed laneId,
        uint64 indexed sourceNonce,
        bytes32 aggregateId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes32 payloadHash,
        uint256 destinationChainId,
        address destinationComponent
    );
    event MessageExecuted(
        bytes32 indexed messageId,
        bytes32 indexed laneId,
        uint64 indexed sourceNonce,
        address destinationComponent,
        bytes32 resultHash
    );
    event MessageTombstoned(
        bytes32 indexed messageId,
        uint64 indexed recoveryNonce,
        bytes32 indexed reasonCode,
        bytes32 tombstoneEventHash
    );
    event RecoveryControllerConfigured(address indexed controller);
    event MessageAcknowledged(
        bytes32 indexed messageId,
        bytes32 indexed destinationResultHash,
        bytes32 indexed acknowledgementCommitment
    );

    constructor(
        IRoleManager roleManager_,
        bytes32 protocolId_,
        uint256 localChainId_,
        RouteRegistry routeRegistry_,
        SyntheticFinalityVerifier finalityVerifier_
    ) RoleControlled(roleManager_) {
        if (
            protocolId_ == bytes32(0) || localChainId_ == 0 || address(routeRegistry_) == address(0)
                || address(finalityVerifier_) == address(0)
        ) {
            revert InvalidCoordinatorConfiguration();
        }
        protocolId = protocolId_;
        localChainId = localChainId_;
        routeRegistry = routeRegistry_;
        finalityVerifier = finalityVerifier_;
    }

    function configureRecoveryController(address controller)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (controller.code.length == 0 || recoveryController != address(0)) {
            revert InvalidCoordinatorConfiguration();
        }
        recoveryController = controller;
        emit RecoveryControllerConfigured(controller);
    }

    function sendMessage(CrossChainTypes.MessageEnvelope calldata envelope, bytes calldata payload)
        external
        returns (bytes32 messageId_)
    {
        if (payload.length == 0 || payload.length > MAX_PAYLOAD_BYTES) revert InvalidMessage();
        _validateEnvelopeAndRoute(envelope, payload, true);
        if (block.timestamp >= envelope.expiresAt) revert MessageExpired(envelope.messageId);
        if (envelope.sourceComponent != msg.sender) revert InvalidMessage();

        uint64 expectedNonce = nextOutboundNonce[envelope.laneId] + 1;
        if (envelope.sourceNonce != expectedNonce) {
            revert InvalidMessageOrder(envelope.laneId, expectedNonce, envelope.sourceNonce);
        }
        messageId_ = CrossChainTypes.messageId(envelope);
        if (
            messageId_ != envelope.messageId
                || _messageStates[messageId_] != CrossChainTypes.MessageState.NONE
        ) {
            revert InvalidMessage();
        }
        nextOutboundNonce[envelope.laneId] = expectedNonce;
        _envelopes[messageId_] = envelope;
        _messageStates[messageId_] = CrossChainTypes.MessageState.SENT;
        emit MessageSent(
            messageId_,
            envelope.laneId,
            envelope.sourceNonce,
            envelope.aggregateId,
            envelope.actionType,
            envelope.payloadHash,
            envelope.destinationChainId,
            envelope.destinationComponent
        );
    }

    function executeMessage(
        CrossChainTypes.MessageEnvelope calldata envelope,
        bytes calldata payload,
        CrossChainTypes.SourceEventProof calldata proof,
        CrossChainTypes.FinalityCertificate calldata certificate
    ) external nonReentrant returns (bytes32 resultHash) {
        if (payload.length == 0 || payload.length > MAX_PAYLOAD_BYTES) revert InvalidMessage();
        bytes32 messageId_ = CrossChainTypes.messageId(envelope);
        if (messageId_ != envelope.messageId) revert InvalidMessage();
        RouteRegistry.RouteVersion memory route_ =
            _validateEnvelopeAndRouteIdentity(envelope, payload);
        if (executionResult[messageId_] != bytes32(0)) return executionResult[messageId_];
        _validateRouteAvailability(envelope, false);
        if (tombstoneHash[messageId_] != bytes32(0)) {
            revert MessageAlreadyTombstoned(messageId_);
        }
        if (
            block.timestamp >= envelope.expiresAt
                && !CrossChainTypes.isReportAction(envelope.actionType)
        ) revert MessageExpired(messageId_);

        bytes32 laneNonceKey = keccak256(abi.encode(envelope.laneId, envelope.sourceNonce));
        bytes32 existing = inboundMessageAt[laneNonceKey];
        if (existing != bytes32(0) && existing != messageId_) {
            revert ConflictingMessage(envelope.laneId, envelope.sourceNonce);
        }
        uint64 expectedNonce = nextInboundNonce[envelope.laneId] + 1;
        if (envelope.sourceNonce != expectedNonce) {
            revert InvalidMessageOrder(envelope.laneId, expectedNonce, envelope.sourceNonce);
        }

        _verifyFinality(envelope, proof, certificate, route_.config.sourceSignerSetHash);

        inboundMessageAt[laneNonceKey] = messageId_;
        _envelopes[messageId_] = envelope;
        _messageStates[messageId_] = CrossChainTypes.MessageState.VERIFIED;
        resultHash = ICrossChainReceiver(envelope.destinationComponent)
            .handleCrossChainMessage(messageId_, envelope.actionType, payload);
        if (resultHash == bytes32(0)) revert InvalidExecutionResult();
        executionResult[messageId_] = resultHash;
        _messageStates[messageId_] = CrossChainTypes.MessageState.EXECUTED;
        nextInboundNonce[envelope.laneId] = envelope.sourceNonce;
        emit MessageExecuted(
            messageId_,
            envelope.laneId,
            envelope.sourceNonce,
            envelope.destinationComponent,
            resultHash
        );
    }

    function recordTombstone(
        CrossChainTypes.MessageEnvelope calldata envelope,
        uint64 recoveryNonce,
        bytes32 reasonCode
    ) external returns (bytes32 tombstoneEventHash) {
        if (msg.sender != recoveryController) {
            revert UnauthorizedRecoveryController(msg.sender);
        }
        bytes32 messageId_ = CrossChainTypes.messageId(envelope);
        if (
            messageId_ != envelope.messageId || reasonCode == bytes32(0)
                || executionResult[messageId_] != bytes32(0)
                || tombstoneHash[messageId_] != bytes32(0)
                || envelope.destinationChainId != localChainId
                || envelope.destinationCoordinator != address(this)
        ) {
            revert InvalidMessage();
        }
        _validateTombstoneEnvelope(envelope);
        bytes32 laneNonceKey = keccak256(abi.encode(envelope.laneId, envelope.sourceNonce));
        uint64 expectedNonce = nextInboundNonce[envelope.laneId] + 1;
        if (envelope.sourceNonce != expectedNonce || inboundMessageAt[laneNonceKey] != bytes32(0)) {
            revert InvalidMessageOrder(envelope.laneId, expectedNonce, envelope.sourceNonce);
        }
        bytes32 envelopeHash = keccak256(abi.encode(envelope));
        tombstoneEventHash = CrossChainTypes.tombstoneEventHash(
            address(this), messageId_, envelopeHash, recoveryNonce, reasonCode
        );
        inboundMessageAt[laneNonceKey] = messageId_;
        _envelopes[messageId_] = envelope;
        tombstoneHash[messageId_] = tombstoneEventHash;
        _messageStates[messageId_] = CrossChainTypes.MessageState.DESTINATION_TOMBSTONED;
        nextInboundNonce[envelope.laneId] = envelope.sourceNonce;
        emit MessageTombstoned(messageId_, recoveryNonce, reasonCode, tombstoneEventHash);
    }

    function recordAcknowledgement(
        CrossChainTypes.MessageEnvelope calldata envelope,
        bytes32 destinationResultHash,
        CrossChainTypes.SourceEventProof calldata proof,
        CrossChainTypes.FinalityCertificate calldata certificate
    ) external returns (bytes32 commitment) {
        if (
            envelope.sourceChainId != localChainId || envelope.sourceCoordinator != address(this)
                || destinationResultHash == bytes32(0)
                || CrossChainTypes.messageId(envelope) != envelope.messageId
        ) revert InvalidMessage();
        CrossChainTypes.MessageEnvelope memory stored = _envelopes[envelope.messageId];
        if (
            stored.messageId != envelope.messageId
                || keccak256(abi.encode(stored)) != keccak256(abi.encode(envelope))
        ) revert InvalidMessage();
        commitment = acknowledgementEventHash(envelope, destinationResultHash);
        bytes32 existing = acknowledgementCommitment[envelope.messageId];
        if (existing != bytes32(0)) {
            if (existing != commitment) revert InvalidMessage();
            return existing;
        }
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(envelope.routePolicyHash);
        if (proof.eventHash != commitment) revert InvalidMessage();
        finalityVerifier.verify(
            envelope,
            proof,
            certificate,
            route_.config.destinationSignerSetHash,
            envelope.destinationFinalityPolicyHash,
            commitment
        );
        acknowledgementCommitment[envelope.messageId] = commitment;
        _messageStates[envelope.messageId] = CrossChainTypes.MessageState.ACKNOWLEDGED;
        emit MessageAcknowledged(envelope.messageId, destinationResultHash, commitment);
    }

    function acknowledgementEventHash(
        CrossChainTypes.MessageEnvelope calldata envelope,
        bytes32 destinationResultHash
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_XCHAIN_EXECUTION_ACKNOWLEDGEMENT_V1",
                envelope.destinationCoordinator,
                envelope.messageId,
                destinationResultHash
            )
        );
    }

    function messageEnvelope(bytes32 messageId_)
        external
        view
        returns (CrossChainTypes.MessageEnvelope memory)
    {
        return _envelopes[messageId_];
    }

    function messageState(bytes32 messageId_)
        external
        view
        override
        returns (CrossChainTypes.MessageState)
    {
        return _messageStates[messageId_];
    }

    function sourceMessageEventHash(CrossChainTypes.MessageEnvelope memory envelope)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_MESSAGE_SENT_V1",
                envelope.sourceCoordinator,
                envelope.messageId,
                envelope.laneId,
                envelope.sourceNonce,
                envelope.actionType,
                envelope.payloadHash
            )
        );
    }

    function _verifyFinality(
        CrossChainTypes.MessageEnvelope calldata envelope,
        CrossChainTypes.SourceEventProof calldata proof,
        CrossChainTypes.FinalityCertificate calldata certificate,
        bytes32 sourceSignerSetHash
    ) private view {
        finalityVerifier.verify(
            envelope,
            proof,
            certificate,
            sourceSignerSetHash,
            envelope.sourceFinalityPolicyHash,
            sourceMessageEventHash(envelope)
        );
    }

    function _validateEnvelopeAndRoute(
        CrossChainTypes.MessageEnvelope calldata envelope,
        bytes calldata payload,
        bool outbound
    ) private view returns (RouteRegistry.RouteVersion memory route_) {
        route_ = _validateEnvelopeAndRouteIdentity(envelope, payload);
        _validateRouteAvailability(envelope, outbound);
    }

    function _validateEnvelopeAndRouteIdentity(
        CrossChainTypes.MessageEnvelope calldata envelope,
        bytes calldata payload
    ) private view returns (RouteRegistry.RouteVersion memory route_) {
        if (
            envelope.schemaVersion != CrossChainTypes.SCHEMA_VERSION
                || envelope.protocolId != protocolId || envelope.payloadHash != keccak256(payload)
                || envelope.createdAt > block.timestamp || envelope.expiresAt <= envelope.createdAt
                || envelope.routePolicyHash == bytes32(0)
        ) {
            revert InvalidMessage();
        }
        route_ = routeRegistry.route(envelope.routePolicyHash);
        if (
            envelope.sourceChainId != route_.config.sourceChainId
                || envelope.sourceCoordinator != route_.config.sourceCoordinator
                || envelope.sourceComponent != route_.config.sourceComponent
                || envelope.destinationChainId != route_.config.destinationChainId
                || envelope.destinationCoordinator != route_.config.destinationCoordinator
                || envelope.destinationComponent != route_.config.destinationComponent
                || envelope.adapterSetPolicyHash != route_.config.adapterSetPolicyHash
                || envelope.sourceFinalityPolicyHash != route_.config.sourceFinalityPolicyHash
                || envelope.destinationFinalityPolicyHash
                    != route_.config.destinationFinalityPolicyHash
                || !routeRegistry.isActionAllowed(envelope.routePolicyHash, envelope.actionType)
                || envelope.laneId
                    != CrossChainTypes.laneId(
                        protocolId,
                        envelope.sourceChainId,
                        envelope.sourceComponent,
                        envelope.destinationChainId,
                        envelope.destinationComponent,
                        envelope.aggregateId,
                        route_.config.actionFamily
                    )
        ) {
            revert InvalidRoute(envelope.routePolicyHash);
        }
    }

    function _validateRouteAvailability(
        CrossChainTypes.MessageEnvelope calldata envelope,
        bool outbound
    ) private view {
        bool isExit = CrossChainTypes.isExitAction(envelope.actionType);
        bool isReport = CrossChainTypes.isReportAction(envelope.actionType);
        if (outbound) {
            if (
                envelope.sourceChainId != localChainId
                    || envelope.sourceCoordinator != address(this)
                    || (!isExit
                        && !routeRegistry.isAvailableForNewMessage(envelope.routePolicyHash))
                    || (isExit
                        && !routeRegistry.isExecutable(
                            envelope.routePolicyHash, envelope.createdAt, true
                        ))
            ) {
                revert InvalidRoute(envelope.routePolicyHash);
            }
        } else if (
            envelope.destinationChainId != localChainId
                || envelope.destinationCoordinator != address(this)
                || !routeRegistry.isExecutable(
                    envelope.routePolicyHash, envelope.createdAt, isExit || isReport
                )
        ) {
            revert InvalidRoute(envelope.routePolicyHash);
        }
    }

    function _validateTombstoneEnvelope(CrossChainTypes.MessageEnvelope calldata envelope)
        private
        view
    {
        if (
            envelope.schemaVersion != CrossChainTypes.SCHEMA_VERSION
                || envelope.protocolId != protocolId || envelope.routePolicyHash == bytes32(0)
                || envelope.expiresAt <= envelope.createdAt
        ) {
            revert InvalidMessage();
        }
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(envelope.routePolicyHash);
        if (
            envelope.sourceChainId != route_.config.sourceChainId
                || envelope.sourceCoordinator != route_.config.sourceCoordinator
                || envelope.sourceComponent != route_.config.sourceComponent
                || envelope.destinationChainId != route_.config.destinationChainId
                || envelope.destinationCoordinator != route_.config.destinationCoordinator
                || envelope.destinationComponent != route_.config.destinationComponent
                || envelope.adapterSetPolicyHash != route_.config.adapterSetPolicyHash
                || envelope.sourceFinalityPolicyHash != route_.config.sourceFinalityPolicyHash
                || envelope.destinationFinalityPolicyHash
                    != route_.config.destinationFinalityPolicyHash
                || !routeRegistry.isActionAllowed(envelope.routePolicyHash, envelope.actionType)
                || envelope.laneId
                    != CrossChainTypes.laneId(
                        protocolId,
                        envelope.sourceChainId,
                        envelope.sourceComponent,
                        envelope.destinationChainId,
                        envelope.destinationComponent,
                        envelope.aggregateId,
                        route_.config.actionFamily
                    )
                || !routeRegistry.isExecutable(envelope.routePolicyHash, envelope.createdAt, true)
        ) {
            revert InvalidRoute(envelope.routePolicyHash);
        }
    }
}
