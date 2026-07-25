// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICrossChainReceiver } from "../src/interfaces/ICrossChainReceiver.sol";
import { IUnifiedToken } from "../src/interfaces/IUnifiedToken.sol";
import { BridgeExposurePolicy } from "../src/crosschain/BridgeExposurePolicy.sol";
import { ChainRegistry } from "../src/crosschain/ChainRegistry.sol";
import { CrossChainTypes } from "../src/crosschain/CrossChainTypes.sol";
import { CrossChainRecoveryController } from "../src/crosschain/CrossChainRecoveryController.sol";
import { RouteRegistry } from "../src/crosschain/RouteRegistry.sol";
import { SyntheticFinalityVerifier } from "../src/crosschain/SyntheticFinalityVerifier.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";

interface Phase8CoreVm {
    function addr(uint256 privateKey) external returns (address);
    function prank(address sender) external;
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 timestamp) external;
}

contract Phase8CoreReceiver is ICrossChainReceiver {
    function handleCrossChainMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(messageId, actionType, payload));
    }
}

contract Phase8CoreUFT is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000 ether;

    constructor() ERC20("Phase 8 UFT", "P8UFT") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract Phase8CrossChainCoreTest {
    Phase8CoreVm private constant vm =
        Phase8CoreVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 private constant NOW = 1_900_000_000;
    uint256 private constant SIGNER_ONE_KEY = 1;
    uint256 private constant SIGNER_TWO_KEY = 2;
    uint256 private constant SIGNER_THREE_KEY = 3;
    bytes32 private constant OBSERVER_AUTHORITY = bytes32(uint256(0x9999));
    bytes32 private constant FINALITY_POLICY = bytes32(uint256(0x1111));
    bytes32 private constant RUNTIME_ACTION_FAMILY = keccak256("RUNTIME_FINALITY_ACTION");
    bytes32 private constant GOLDEN_PAYLOAD_HASH =
        0x805585e890e898930c0ac7d38c1e157d0e4a5964eb8239552298bb2d3789877a;
    bytes32 private constant GOLDEN_MESSAGE_ID =
        0xf8d9ef5672d829229110e480489155be0440e916833a1290a8955a8acf9c4801;
    bytes32 private constant GOLDEN_OBSERVER_COMMITMENT =
        0xd3cd7ce881b2b2ef436bbe402071adf723ebcd7ff7d379b4f2d10d7d84c039c8;
    bytes32 private constant GOLDEN_PROOF_HASH =
        0x48d3a5bd4a6edfa6da4ceb1fb19fb7d7d975e24ac53af96bc4bc39947a566caf;
    bytes32 private constant GOLDEN_FINALITY_DIGEST =
        0x6ebe5277d0c32b531c792319523fd367e073607937dea0c3949c5f8d43ca8820;

    RoleManager private roles;
    ChainRegistry private verifierChains;
    SyntheticFinalityVerifier private verifier;
    bytes32 private signerSetHash;
    bytes32 private runtimePolicyHash;
    address[3] private signers;

    function setUp() public {
        vm.warp(NOW);
        roles = new RoleManager(address(0xA11), address(this));
        verifierChains = new ChainRegistry(roles, 999_999);
        verifier = new SyntheticFinalityVerifier(roles, verifierChains);
        verifierChains.registerChain(
            31_337,
            0x0202020202020202020202020202020202020202,
            address(verifier),
            keccak256("RUNTIME_SOURCE_COORDINATOR_CODE"),
            address(verifier).codehash,
            keccak256("RUNTIME_SOURCE_CONFIGURATION"),
            NOW
        );
        verifierChains.registerChain(
            31_338,
            0x0404040404040404040404040404040404040404,
            address(verifier),
            keccak256("RUNTIME_DESTINATION_COORDINATOR_CODE"),
            address(verifier).codehash,
            keccak256("RUNTIME_DESTINATION_CONFIGURATION"),
            NOW
        );
        signers = [vm.addr(SIGNER_TWO_KEY), vm.addr(SIGNER_THREE_KEY), vm.addr(SIGNER_ONE_KEY)];
        signerSetHash =
            verifier.registerSignerSet(OBSERVER_AUTHORITY, 1, signers, NOW, NOW + 30 days);
        runtimePolicyHash = verifier.registerFinalityPolicy(
            SyntheticFinalityVerifier.FinalityPolicyConfig({
                destinationEvidence: false,
                sourceChainId: 31_337,
                sourceCoordinator: 0x0202020202020202020202020202020202020202,
                sourceComponent: 0x0303030303030303030303030303030303030303,
                destinationChainId: 31_338,
                destinationCoordinator: 0x0404040404040404040404040404040404040404,
                destinationComponent: 0x0505050505050505050505050505050505050505,
                evidenceChainVersion: 1,
                evidenceChainConfigurationHash: keccak256("RUNTIME_SOURCE_CONFIGURATION"),
                actionFamily: RUNTIME_ACTION_FAMILY,
                allowedActionsBitmap: uint32(1) << 1,
                requiredDepth: 12,
                observerAuthorityHash: OBSERVER_AUTHORITY,
                signerSetHash: signerSetHash,
                signerSetVersion: 1
            })
        );
    }

    function testCanonicalPayloadMessageAndFinalityGoldens() public pure {
        CrossChainTypes.CanonicalUftLockPayload memory payload =
            CrossChainTypes.CanonicalUftLockPayload({
                lockId: hex"1111111111111111111111111111111111111111111111111111111111111111",
                loanId: hex"2222222222222222222222222222222222222222222222222222222222222222",
                canonicalToken: 0x1111111111111111111111111111111111111111,
                homeBridgeHub: 0x2222222222222222222222222222222222222222,
                wrappedToken: 0x3333333333333333333333333333333333333333,
                destinationRecipient: 0x4444444444444444444444444444444444444444,
                amount: 1 ether
            });
        bytes memory encoded = abi.encode(payload);
        require(encoded.length == 224, "payload length");
        require(keccak256(encoded) == GOLDEN_PAYLOAD_HASH, "payload hash");

        CrossChainTypes.MessageEnvelope memory envelope = _goldenEnvelope();
        require(CrossChainTypes.messageId(envelope) == GOLDEN_MESSAGE_ID, "message id");

        CrossChainTypes.SourceEventProof memory proof = _goldenProof();
        require(
            CrossChainTypes.observerHeaderCommitment(proof) == GOLDEN_OBSERVER_COMMITMENT,
            "observer commitment"
        );
        require(CrossChainTypes.sourceProofHash(proof) == GOLDEN_PROOF_HASH, "proof hash");
        require(
            CrossChainTypes.finalityCertificateDigest(
                0x5555555555555555555555555555555555555555,
                31_338,
                GOLDEN_MESSAGE_ID,
                GOLDEN_PROOF_HASH,
                hex"7777777777777777777777777777777777777777777777777777777777777777",
                1
            ) == GOLDEN_FINALITY_DIGEST,
            "finality digest"
        );
    }

    function testFinalityNeedsCommittedObserverEvidenceAndTwoDistinctSigners() public {
        CrossChainTypes.MessageEnvelope memory envelope = _runtimeEnvelope();
        CrossChainTypes.SourceEventProof memory proof = _runtimeProof(envelope);
        CrossChainTypes.FinalityCertificate memory certificate = _certificate(envelope, proof, 2);
        require(
            verifier.verify(
                envelope, proof, certificate, signerSetHash, runtimePolicyHash, proof.eventHash
            ),
            "valid proof"
        );

        CrossChainTypes.SourceEventProof memory missingObserver = proof;
        missingObserver.observerSignature = hex"";
        _requireVerifyFailure(envelope, missingObserver, certificate);

        CrossChainTypes.SourceEventProof memory changedObserver = proof;
        changedObserver.observerSignature = hex"deadbeef";
        _requireVerifyFailure(envelope, changedObserver, certificate);

        CrossChainTypes.FinalityCertificate memory oneSignature = _certificate(envelope, proof, 1);
        _requireVerifyFailure(envelope, proof, oneSignature);
        CrossChainTypes.FinalityCertificate memory oversized = _certificate(envelope, proof, 4);
        _requireVerifyFailure(envelope, proof, oversized);
        CrossChainTypes.MessageEnvelope memory beyondSignerHorizon = _runtimeEnvelope();
        beyondSignerHorizon.expiresAt = NOW + 31 days;
        beyondSignerHorizon.messageId = CrossChainTypes.messageId(beyondSignerHorizon);
        CrossChainTypes.SourceEventProof memory horizonProof = _runtimeProof(beyondSignerHorizon);
        CrossChainTypes.FinalityCertificate memory horizonCertificate =
            _certificate(beyondSignerHorizon, horizonProof, 2);
        _requireVerifyFailure(beyondSignerHorizon, horizonProof, horizonCertificate);

        CrossChainTypes.SourceEventProof memory historicalProof = _runtimeProof(envelope);
        CrossChainTypes.FinalityCertificate memory historicalCertificate =
            _certificate(envelope, historicalProof, 2);
        vm.warp(NOW + 31 days);
        require(
            verifier.verify(
                envelope,
                historicalProof,
                historicalCertificate,
                signerSetHash,
                runtimePolicyHash,
                historicalProof.eventHash
            ),
            "historical signer set unavailable"
        );
        verifier.disableSignerSet(signerSetHash);
        _requireVerifyFailure(envelope, historicalProof, historicalCertificate);
    }

    function testFinalityPolicyRejectsShallowDepthAndWrongAction() public {
        CrossChainTypes.MessageEnvelope memory envelope = _runtimeEnvelope();
        CrossChainTypes.SourceEventProof memory shallow = _runtimeProof(envelope);
        shallow.requiredDepth = 1;
        shallow.observerSignedHeaderCommitment = CrossChainTypes.observerHeaderCommitment(shallow);
        _requireVerifyFailure(envelope, shallow, _certificate(envelope, shallow, 2));

        CrossChainTypes.MessageEnvelope memory wrongAction = envelope;
        wrongAction.actionType = CrossChainTypes.ACTION_SATELLITE_COLLATERAL_LOCKED;
        wrongAction.messageId = CrossChainTypes.messageId(wrongAction);
        CrossChainTypes.SourceEventProof memory wrongActionProof = _runtimeProof(wrongAction);
        _requireVerifyFailure(
            wrongAction, wrongActionProof, _certificate(wrongAction, wrongActionProof, 2)
        );
    }

    function testFinalityPolicyRegistrationRequiresPinnedChainConfiguration() public {
        SyntheticFinalityVerifier.FinalityPolicyConfig memory policy =
            verifier.finalityPolicy(runtimePolicyHash);
        policy.evidenceChainConfigurationHash = keccak256("UNREGISTERED_CHAIN_CONFIGURATION");
        (bool accepted,) = address(verifier)
            .call(abi.encodeCall(SyntheticFinalityVerifier.registerFinalityPolicy, (policy)));
        require(!accepted, "unregistered chain configuration accepted");
    }

    function testRecoveryV2Goldens() public pure {
        CrossChainRecoveryController.RecoveryRequest memory request =
            CrossChainRecoveryController.RecoveryRequest({
                messageId: hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                envelopeHash: hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                routePolicyHash: hex"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                assetAmountCommitment: hex"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
                sourceStateCommitment: hex"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                destinationStateCommitment: hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                compensationPayloadHash: hex"1212121212121212121212121212121212121212121212121212121212121212",
                messageExpiresAt: 1_700_003_600,
                recoveryNonce: 7,
                reasonCode: hex"1313131313131313131313131313131313131313131313131313131313131313",
                action: CrossChainRecoveryController.RecoveryAction.TOMBSTONE_THEN_COMPENSATE,
                authorizerSetHash: hex"1414141414141414141414141414141414141414141414141414141414141414",
                authorizerSetVersion: 1
            });
        require(
            keccak256(abi.encode("UNIFIED_XCHAIN_RECOVERY_ID_V1", request))
                == 0x049c45f9e5e106b33a2932b696fc45bdf394b35bb7b94e2b79e837cdfc4b0763,
            "recovery id golden"
        );
        require(
            keccak256(
                abi.encode(
                    "UNIFIED_XCHAIN_RECOVERY_AUTHORIZATION_V2",
                    bytes32(hex"0101010101010101010101010101010101010101010101010101010101010101"),
                    uint256(31_337),
                    0x0202020202020202020202020202020202020202,
                    uint256(31_338),
                    0x0404040404040404040404040404040404040404,
                    request
                )
            ) == 0x2ca5318f1079c2d3c45a5cefb7c5cf784728956bd328df3ee36feeb9b16af0ad,
            "recovery digest golden"
        );
    }

    function testRemoteIdentitiesMasksPauseAndExposurePolicyArePinned() public {
        ChainRegistry chains = new ChainRegistry(roles, 31_337);
        EmergencyController emergency = new EmergencyController(roles);
        RouteRegistry routes = new RouteRegistry(roles, chains, emergency);
        Phase8CoreReceiver sourceComponent = new Phase8CoreReceiver();

        chains.registerChain(
            31_337,
            address(this),
            address(verifier),
            address(this).codehash,
            address(verifier).codehash,
            keccak256("HOME_CONFIG"),
            NOW
        );
        address remoteCoordinator = address(0xC001);
        chains.registerChain(
            31_338,
            remoteCoordinator,
            address(0xF1A1),
            keccak256("REMOTE_COORDINATOR_CODE"),
            keccak256("REMOTE_VERIFIER_CODE"),
            keccak256("REMOTE_CONFIG"),
            NOW
        );

        RouteRegistry.RouteConfig memory config = _routeConfig(
            address(this),
            address(sourceComponent),
            remoteCoordinator,
            address(0xD357),
            uint32(1) << 1,
            keccak256("REMOTE_LOCK")
        );
        bytes32 routeHash = routes.registerRoute(config);
        require(routeHash != bytes32(0), "remote route");
        require(routes.isAvailableForNewMessage(routeHash), "active chain route unavailable");
        require(routes.isExecutable(routeHash, NOW, false), "active ordinary route unavailable");

        RouteRegistry.RouteConfig memory invalid = config;
        invalid.actionFamily = keccak256("UNSPECIFIED_BIT");
        invalid.allowedActionsBitmap = 1;
        _requireRouteFailure(routes, invalid);
        invalid.actionFamily = keccak256("RESERVED_BIT");
        invalid.allowedActionsBitmap = uint32(1) << 11;
        _requireRouteFailure(routes, invalid);
        invalid.actionFamily = keccak256("MIXED_LANES");
        invalid.allowedActionsBitmap = (uint32(1) << 1) | (uint32(1) << 5);
        _requireRouteFailure(routes, invalid);
        invalid.actionFamily = keccak256("OUT_OF_RANGE");
        invalid.allowedActionsBitmap = uint32(1) << 31;
        _requireRouteFailure(routes, invalid);

        address pauser = address(0xFA05E);
        roles.grantRole(ProtocolRoles.PAUSER_ROLE, pauser, type(uint64).max);
        vm.prank(pauser);
        routes.setRoutePaused(routeHash, true);
        require(
            !routes.isAvailableForNewMessage(routeHash), "paused route accepted ordinary message"
        );
        require(!routes.isExecutable(routeHash, NOW, false), "paused ordinary message executable");
        require(routes.isExecutable(routeHash, NOW, true), "paused safety report/exit blocked");
        vm.prank(pauser);
        (bool resumed,) =
            address(routes).call(abi.encodeCall(RouteRegistry.setRoutePaused, (routeHash, false)));
        require(!resumed, "pauser resumed route");
        routes.setRoutePaused(routeHash, false);

        vm.warp(NOW + 1);
        chains.deprecateChain(31_338, 1);
        require(
            !routes.isAvailableForNewMessage(routeHash), "deprecated chain accepted new message"
        );
        require(routes.isExecutable(routeHash, NOW, false), "pre-deprecation ordinary message lost");
        require(
            !routes.isExecutable(routeHash, NOW + 2, false),
            "post-deprecation ordinary message executable"
        );
        require(routes.isExecutable(routeHash, NOW, true), "existing exit route lost");
        require(
            !routes.isExecutable(routeHash, NOW + 1, true),
            "exact-boundary safety report/exit accepted"
        );
        require(
            !routes.isExecutable(routeHash, NOW + 2, true),
            "post-deprecation safety report/exit accepted"
        );
        invalid = config;
        invalid.actionFamily = keccak256("AFTER_CHAIN_DEPRECATION");
        _requireRouteFailure(routes, invalid);

        vm.warp(NOW);
        _assertExposureRotation(routeHash);
    }

    function testRouteAndSourceChainDeprecationBoundSafetyMessages() public {
        (, RouteRegistry deprecatedRoutes, bytes32 deprecatedRoute) =
            _configuredRoute(keccak256("ROUTE_DEPRECATION_BOUNDARY"));
        vm.warp(NOW + 1);
        deprecatedRoutes.deprecateRoute(deprecatedRoute);
        require(
            deprecatedRoutes.isExecutable(deprecatedRoute, NOW, true),
            "pre-route-deprecation safety message lost"
        );
        require(
            !deprecatedRoutes.isExecutable(deprecatedRoute, NOW + 1, true),
            "route-deprecation boundary safety message accepted"
        );
        require(
            !deprecatedRoutes.isExecutable(deprecatedRoute, NOW + 2, true),
            "post-route-deprecation safety message accepted"
        );

        (ChainRegistry sourceChains, RouteRegistry sourceRoutes, bytes32 sourceRoute) =
            _configuredRoute(keccak256("SOURCE_CHAIN_DEPRECATION_BOUNDARY"));
        vm.warp(NOW + 2);
        sourceChains.deprecateChain(31_337, 1);
        require(
            sourceRoutes.isExecutable(sourceRoute, NOW + 1, true),
            "pre-source-deprecation safety message lost"
        );
        require(
            !sourceRoutes.isExecutable(sourceRoute, NOW + 2, true),
            "source-deprecation boundary safety message accepted"
        );
        require(
            !sourceRoutes.isExecutable(sourceRoute, NOW + 3, true),
            "post-source-deprecation safety message accepted"
        );
    }

    function _assertExposureRotation(bytes32 routeHash) private {
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
        Phase8CoreUFT token = new Phase8CoreUFT();
        BridgeExposurePolicy exposure =
            new BridgeExposurePolicy(roles, IUnifiedToken(address(token)));
        bytes32 first = exposure.registerPolicy(_exposureConfig(50_000 ether, 0, NOW));
        bytes32 second = exposure.registerPolicy(_exposureConfig(40_000 ether, 0, NOW));
        exposure.activateForRoute(routeHash, first);
        exposure.activateForRoute(routeHash, second);
        require(exposure.activePolicyForRoute(routeHash) == second, "reduction");
        (bool rollback,) = address(exposure)
            .call(abi.encodeCall(BridgeExposurePolicy.activateForRoute, (routeHash, first)));
        require(!rollback, "historic looser policy reactivated");
        (bool oversized,) = address(exposure)
            .staticcall(
                abi.encodeCall(
                    BridgeExposurePolicy.validateLock,
                    (routeHash, 45_000 ether, 45_000 ether, 45_000 ether, 45_000 ether)
                )
            );
        require(!oversized, "reduction did not bind new lock");
        require(exposure.policy(first).routeAbsoluteCap == 50_000 ether, "old policy mutated");
        _assertZeroDelayIncreaseRejected(exposure, routeHash);
        _assertZeroDelayReferenceChangeRejected(exposure, routeHash);
        _assertZeroDelayEvidenceHashChangeRejected(exposure, routeHash);
        bytes32 delayed =
            exposure.registerPolicy(_exposureConfig(60_000 ether, 1 days, NOW + 1 days));
        (bool early,) = address(exposure)
            .call(abi.encodeCall(BridgeExposurePolicy.activateForRoute, (routeHash, delayed)));
        require(!early, "increase activated early");
        vm.warp(NOW + 1 days);
        exposure.activateForRoute(routeHash, delayed);
        require(exposure.activePolicyForRoute(routeHash) == delayed, "delayed increase");
        _assertDelayedEvidenceHashChange(exposure, routeHash);
    }

    function _assertZeroDelayIncreaseRejected(BridgeExposurePolicy exposure, bytes32 routeHash)
        private
    {
        bytes32 immediateIncrease = exposure.registerPolicy(_exposureConfig(60_000 ether, 0, NOW));
        (bool accepted,) = address(exposure)
            .call(
                abi.encodeCall(
                    BridgeExposurePolicy.activateForRoute, (routeHash, immediateIncrease)
                )
            );
        require(!accepted, "zero-delay increase activated");
    }

    function _assertZeroDelayReferenceChangeRejected(
        BridgeExposurePolicy exposure,
        bytes32 routeHash
    ) private {
        BridgeExposurePolicy.ExposureConfig memory changedReference =
            _exposureConfig(40_000 ether, 0, NOW);
        changedReference.circulatingSupplyReference = 900_000 ether;
        bytes32 immediateReferenceChange = exposure.registerPolicy(changedReference);
        (bool accepted,) = address(exposure)
            .call(
                abi.encodeCall(
                    BridgeExposurePolicy.activateForRoute, (routeHash, immediateReferenceChange)
                )
            );
        require(!accepted, "zero-delay reference change activated");
    }

    function _assertZeroDelayEvidenceHashChangeRejected(
        BridgeExposurePolicy exposure,
        bytes32 routeHash
    ) private {
        BridgeExposurePolicy.ExposureConfig memory changedEvidence =
            _exposureConfig(40_000 ether, 0, NOW);
        changedEvidence.circulatingSupplyEvidenceHash =
            keccak256("REPLACEMENT_CIRCULATING_SUPPLY_EVIDENCE");
        bytes32 immediateEvidenceChange = exposure.registerPolicy(changedEvidence);
        (bool accepted,) = address(exposure)
            .call(
                abi.encodeCall(
                    BridgeExposurePolicy.activateForRoute, (routeHash, immediateEvidenceChange)
                )
            );
        require(!accepted, "zero-delay evidence change activated");
    }

    function _assertDelayedEvidenceHashChange(BridgeExposurePolicy exposure, bytes32 routeHash)
        private
    {
        uint64 activationTime = uint64(block.timestamp + 1 days);
        BridgeExposurePolicy.ExposureConfig memory changedEvidence =
            _exposureConfig(60_000 ether, 1 days, activationTime);
        changedEvidence.circulatingSupplyEvidenceHash =
            keccak256("DELAYED_CIRCULATING_SUPPLY_EVIDENCE");
        bytes32 delayedEvidenceChange = exposure.registerPolicy(changedEvidence);
        (bool early,) = address(exposure)
            .call(
                abi.encodeCall(
                    BridgeExposurePolicy.activateForRoute, (routeHash, delayedEvidenceChange)
                )
            );
        require(!early, "evidence change activated early");
        vm.warp(activationTime);
        exposure.activateForRoute(routeHash, delayedEvidenceChange);
        require(
            exposure.activePolicyForRoute(routeHash) == delayedEvidenceChange,
            "delayed evidence change"
        );
    }

    function _goldenEnvelope()
        private
        pure
        returns (CrossChainTypes.MessageEnvelope memory envelope)
    {
        bytes32 ones = hex"1111111111111111111111111111111111111111111111111111111111111111";
        envelope = CrossChainTypes.MessageEnvelope({
            schemaVersion: 1,
            messageId: GOLDEN_MESSAGE_ID,
            protocolId: hex"0101010101010101010101010101010101010101010101010101010101010101",
            sourceChainId: 31_337,
            sourceCoordinator: 0x0202020202020202020202020202020202020202,
            sourceComponent: 0x0303030303030303030303030303030303030303,
            destinationChainId: 31_338,
            destinationCoordinator: 0x0404040404040404040404040404040404040404,
            destinationComponent: 0x0505050505050505050505050505050505050505,
            laneId: hex"0606060606060606060606060606060606060606060606060606060606060606",
            sourceNonce: 1,
            aggregateId: hex"0707070707070707070707070707070707070707070707070707070707070707",
            actionType: CrossChainTypes.CrossChainActionType.CANONICAL_UFT_LOCKED_V1,
            payloadHash: GOLDEN_PAYLOAD_HASH,
            createdAt: 1_700_000_000,
            expiresAt: 1_700_003_600,
            routePolicyHash: ones,
            adapterSetPolicyHash: ones,
            sourceFinalityPolicyHash: ones,
            destinationFinalityPolicyHash: ones,
            correlationId: ones,
            causationMessageId: bytes32(0),
            supersededMessageId: bytes32(0)
        });
    }

    function _runtimeEnvelope()
        private
        view
        returns (CrossChainTypes.MessageEnvelope memory envelope)
    {
        envelope = _goldenEnvelope();
        envelope.createdAt = NOW;
        envelope.expiresAt = NOW + 1 days;
        envelope.sourceFinalityPolicyHash = runtimePolicyHash;
        envelope.destinationFinalityPolicyHash = runtimePolicyHash;
        envelope.laneId = CrossChainTypes.laneId(
            envelope.protocolId,
            envelope.sourceChainId,
            envelope.sourceComponent,
            envelope.destinationChainId,
            envelope.destinationComponent,
            envelope.aggregateId,
            RUNTIME_ACTION_FAMILY
        );
        envelope.messageId = CrossChainTypes.messageId(envelope);
    }

    function _goldenProof() private pure returns (CrossChainTypes.SourceEventProof memory proof) {
        proof = CrossChainTypes.SourceEventProof({
            sourceBlockHash: hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            sourceBlockNumber: 100,
            sourceBlockTimestamp: 1_700_000_000,
            transactionHash: hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            transactionIndex: 2,
            receiptRoot: hex"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            receiptProofHash: hex"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
            logIndex: 3,
            eventHash: hex"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            finalityHeadHash: hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            finalityHeadNumber: 112,
            requiredDepth: 12,
            headerAuthorityHash: hex"9999999999999999999999999999999999999999999999999999999999999999",
            observerSignedHeaderCommitment: GOLDEN_OBSERVER_COMMITMENT,
            observerSignature: hex"01020304",
            finalityPolicyHash: hex"1111111111111111111111111111111111111111111111111111111111111111"
        });
    }

    function _runtimeProof(CrossChainTypes.MessageEnvelope memory envelope)
        private
        view
        returns (CrossChainTypes.SourceEventProof memory proof)
    {
        proof = CrossChainTypes.SourceEventProof({
            sourceBlockHash: keccak256("SOURCE_BLOCK"),
            sourceBlockNumber: 100,
            sourceBlockTimestamp: envelope.createdAt,
            transactionHash: keccak256("SOURCE_TX"),
            transactionIndex: 2,
            receiptRoot: keccak256("RECEIPT_ROOT"),
            receiptProofHash: keccak256("RECEIPT_PROOF"),
            logIndex: 3,
            eventHash: keccak256("EXPECTED_EVENT"),
            finalityHeadHash: keccak256("FINALITY_HEAD"),
            finalityHeadNumber: 112,
            requiredDepth: 12,
            headerAuthorityHash: OBSERVER_AUTHORITY,
            observerSignedHeaderCommitment: bytes32(0),
            observerSignature: hex"01020304",
            finalityPolicyHash: runtimePolicyHash
        });
        proof.observerSignedHeaderCommitment = CrossChainTypes.observerHeaderCommitment(proof);
    }

    function _certificate(
        CrossChainTypes.MessageEnvelope memory envelope,
        CrossChainTypes.SourceEventProof memory proof,
        uint256 signatureCount
    ) private returns (CrossChainTypes.FinalityCertificate memory certificate) {
        bytes32 proofHash = CrossChainTypes.sourceProofHash(proof);
        bytes32 digest = CrossChainTypes.finalityCertificateDigest(
            address(verifier), block.chainid, envelope.messageId, proofHash, signerSetHash, 1
        );
        bytes[] memory signatures = new bytes[](signatureCount);
        if (signatureCount > 0) signatures[0] = _signature(SIGNER_ONE_KEY, digest);
        if (signatureCount > 1) signatures[1] = _signature(SIGNER_TWO_KEY, digest);
        if (signatureCount > 2) signatures[2] = _signature(SIGNER_THREE_KEY, digest);
        if (signatureCount > 3) signatures[3] = _signature(SIGNER_ONE_KEY, digest);
        certificate = CrossChainTypes.FinalityCertificate({
            messageId: envelope.messageId,
            sourceProofHash: proofHash,
            signerSetHash: signerSetHash,
            signerSetVersion: 1,
            signatures: signatures
        });
    }

    function _signature(uint256 key, bytes32 digest) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _requireVerifyFailure(
        CrossChainTypes.MessageEnvelope memory envelope,
        CrossChainTypes.SourceEventProof memory proof,
        CrossChainTypes.FinalityCertificate memory certificate
    ) private view {
        (bool success,) = address(verifier)
            .staticcall(
                abi.encodeCall(
                    SyntheticFinalityVerifier.verify,
                    (
                        envelope,
                        proof,
                        certificate,
                        signerSetHash,
                        runtimePolicyHash,
                        proof.eventHash
                    )
                )
            );
        require(!success, "invalid finality accepted");
    }

    function _routeConfig(
        address sourceCoordinator,
        address sourceComponent,
        address destinationCoordinator,
        address destinationComponent,
        uint32 allowedActions,
        bytes32 actionFamily
    ) private view returns (RouteRegistry.RouteConfig memory config) {
        config = RouteRegistry.RouteConfig({
            sourceChainVersion: 1,
            destinationChainVersion: 1,
            sourceChainId: 31_337,
            sourceCoordinator: sourceCoordinator,
            sourceComponent: sourceComponent,
            sourceComponentCodeHash: sourceComponent.codehash,
            destinationChainId: 31_338,
            destinationCoordinator: destinationCoordinator,
            destinationComponent: destinationComponent,
            destinationComponentCodeHash: keccak256("REMOTE_COMPONENT_CODE"),
            actionFamily: actionFamily,
            allowedActionsBitmap: allowedActions,
            adapterId: keccak256("ADAPTER"),
            adapterCodeHash: keccak256("ADAPTER_CODE"),
            adapterSetPolicyHash: keccak256("ADAPTER_SET"),
            sourceFinalityPolicyHash: FINALITY_POLICY,
            destinationFinalityPolicyHash: keccak256("DESTINATION_FINALITY"),
            sourceSignerSetHash: signerSetHash,
            destinationSignerSetHash: signerSetHash,
            absoluteCap: 1_000 ether,
            chainCap: 2_000 ether,
            adapterCap: 2_000 ether,
            activatedAt: NOW
        });
    }

    function _configuredRoute(bytes32 actionFamily)
        private
        returns (ChainRegistry chains, RouteRegistry routes, bytes32 routeHash)
    {
        chains = new ChainRegistry(roles, 31_337);
        EmergencyController emergency = new EmergencyController(roles);
        routes = new RouteRegistry(roles, chains, emergency);
        Phase8CoreReceiver sourceComponent = new Phase8CoreReceiver();
        uint64 activatedAt = uint64(block.timestamp);
        chains.registerChain(
            31_337,
            address(this),
            address(verifier),
            address(this).codehash,
            address(verifier).codehash,
            keccak256(abi.encode("HOME_CONFIG", actionFamily)),
            activatedAt
        );
        address remoteCoordinator = address(uint160(uint256(actionFamily)));
        chains.registerChain(
            31_338,
            remoteCoordinator,
            address(0xF1A1),
            keccak256(abi.encode("REMOTE_COORDINATOR_CODE", actionFamily)),
            keccak256(abi.encode("REMOTE_VERIFIER_CODE", actionFamily)),
            keccak256(abi.encode("REMOTE_CONFIG", actionFamily)),
            activatedAt
        );
        RouteRegistry.RouteConfig memory config = _routeConfig(
            address(this),
            address(sourceComponent),
            remoteCoordinator,
            address(0xD357),
            uint32(1) << 10,
            actionFamily
        );
        config.activatedAt = activatedAt;
        routeHash = routes.registerRoute(config);
    }

    function _requireRouteFailure(RouteRegistry routes, RouteRegistry.RouteConfig memory config)
        private
    {
        (bool success,) =
            address(routes).call(abi.encodeCall(RouteRegistry.registerRoute, (config)));
        require(!success, "invalid route accepted");
    }

    function _exposureConfig(uint256 routeCap, uint64 activationDelay, uint64 activeFrom)
        private
        pure
        returns (BridgeExposurePolicy.ExposureConfig memory)
    {
        return BridgeExposurePolicy.ExposureConfig({
            circulatingSupplyReference: 1_000_000 ether,
            circulatingSupplyEvidenceHash: keccak256("FIXED_CIRCULATING_SUPPLY_EVIDENCE"),
            routeAbsoluteCap: routeCap,
            chainAbsoluteCap: 100_000 ether,
            adapterAbsoluteCap: 100_000 ether,
            aggregateAbsoluteCap: 150_000 ether,
            routePercentageCeilingBps: 500,
            aggregatePercentageCeilingBps: 1_500,
            activationDelay: activationDelay,
            activeFrom: activeFrom
        });
    }
}
