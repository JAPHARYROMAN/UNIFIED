// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { RouteRegistry } from "./RouteRegistry.sol";

/// @notice Shared exact-envelope builder for fixed, registered source components.
library CrossChainMessageBuilder {
    struct BuildRequest {
        bytes32 routePolicyHash;
        address sourceComponent;
        bytes32 aggregateId;
        CrossChainTypes.CrossChainActionType actionType;
        bytes32 payloadHash;
        uint64 expiresAt;
        bytes32 correlationId;
        bytes32 causationMessageId;
        bytes32 supersededMessageId;
    }

    function build(
        ICrossChainCoordinator coordinator,
        RouteRegistry routeRegistry,
        BuildRequest memory request
    ) internal view returns (CrossChainTypes.MessageEnvelope memory envelope) {
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(request.routePolicyHash);
        bytes32 laneId = CrossChainTypes.laneId(
            coordinator.protocolId(),
            route_.config.sourceChainId,
            request.sourceComponent,
            route_.config.destinationChainId,
            route_.config.destinationComponent,
            request.aggregateId,
            route_.config.actionFamily
        );
        envelope.schemaVersion = CrossChainTypes.SCHEMA_VERSION;
        envelope.protocolId = coordinator.protocolId();
        envelope.sourceChainId = route_.config.sourceChainId;
        envelope.sourceCoordinator = route_.config.sourceCoordinator;
        envelope.sourceComponent = request.sourceComponent;
        envelope.destinationChainId = route_.config.destinationChainId;
        envelope.destinationCoordinator = route_.config.destinationCoordinator;
        envelope.destinationComponent = route_.config.destinationComponent;
        envelope.laneId = laneId;
        envelope.sourceNonce = coordinator.nextOutboundNonce(laneId) + 1;
        envelope.aggregateId = request.aggregateId;
        envelope.actionType = request.actionType;
        envelope.payloadHash = request.payloadHash;
        envelope.createdAt = uint64(block.timestamp);
        envelope.expiresAt = request.expiresAt;
        envelope.routePolicyHash = request.routePolicyHash;
        envelope.adapterSetPolicyHash = route_.config.adapterSetPolicyHash;
        envelope.sourceFinalityPolicyHash = route_.config.sourceFinalityPolicyHash;
        envelope.destinationFinalityPolicyHash = route_.config.destinationFinalityPolicyHash;
        envelope.correlationId = request.correlationId;
        envelope.causationMessageId = request.causationMessageId;
        envelope.supersededMessageId = request.supersededMessageId;
        envelope.messageId = CrossChainTypes.messageId(envelope);
    }
}
