package recovery

import (
	"crypto/sha256"
	"encoding/hex"
	"testing"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestRecoveryV2ProtobufRoundTripMatchesSolidityGolden(t *testing.T) {
	authorization := &unifiedv1.CrossChainRecoveryAuthorizationV2{
		ProtocolId:             repeatedByte(0x01, 32),
		SourceChainId:          "31337",
		SourceCoordinator:      repeatedByte(0x02, 20),
		DestinationChainId:     "31338",
		DestinationCoordinator: repeatedByte(0x04, 20),
		Request: &unifiedv1.CrossChainRecoveryRequestV2{
			MessageId:                  repeatedByte(0xaa, 32),
			EnvelopeHash:               repeatedByte(0xbb, 32),
			RoutePolicyHash:            repeatedByte(0xcc, 32),
			AssetAmountCommitment:      repeatedByte(0xdd, 32),
			SourceStateCommitment:      repeatedByte(0xee, 32),
			DestinationStateCommitment: repeatedByte(0xff, 32),
			CompensationPayloadHash:    repeatedByte(0x12, 32),
			MessageExpiresAt:           1_700_003_600,
			RecoveryNonce:              7,
			ReasonCode:                 repeatedByte(0x13, 32),
			Action:                     unifiedv1.RecoveryAction_RECOVERY_ACTION_TOMBSTONE_THEN_COMPENSATE,
			AuthorizerSetHash:          repeatedByte(0x14, 32),
			AuthorizerSetVersion:       1,
		},
		AuthorizerSignatures: [][]byte{
			repeatedByte(0x21, 65),
			repeatedByte(0x22, 65),
		},
		SignerBitmap: 3,
	}
	wire, err := proto.MarshalOptions{Deterministic: true}.Marshal(authorization)
	if err != nil {
		t.Fatal(err)
	}
	const expectedWireSHA256 = "73012516be56b9e049e86c2ceb3aadca52ccc6badd6d32aece816deb6cc4ed1e"
	wireHash := sha256.Sum256(wire)
	if actual := hex.EncodeToString(wireHash[:]); actual != expectedWireSHA256 {
		t.Fatalf("recovery protobuf wire changed: got %s want %s", actual, expectedWireSHA256)
	}

	var recovered unifiedv1.CrossChainRecoveryAuthorizationV2
	if err := proto.Unmarshal(wire, &recovered); err != nil {
		t.Fatal(err)
	}
	if !proto.Equal(authorization, &recovered) {
		t.Fatal("recovery protobuf roundtrip changed the authorization")
	}
	request := recovered.GetRequest()
	canonical := Authorization{
		ProtocolID:             fixed32(t, recovered.GetProtocolId()),
		SourceChainID:          recovered.GetSourceChainId(),
		SourceCoordinator:      fixed20(t, recovered.GetSourceCoordinator()),
		DestinationChainID:     recovered.GetDestinationChainId(),
		DestinationCoordinator: fixed20(t, recovered.GetDestinationCoordinator()),
		Request: AuthorizationRequest{
			MessageID:                  fixed32(t, request.GetMessageId()),
			EnvelopeHash:               fixed32(t, request.GetEnvelopeHash()),
			RoutePolicyHash:            fixed32(t, request.GetRoutePolicyHash()),
			AssetAmountCommitment:      fixed32(t, request.GetAssetAmountCommitment()),
			SourceStateCommitment:      fixed32(t, request.GetSourceStateCommitment()),
			DestinationStateCommitment: fixed32(t, request.GetDestinationStateCommitment()),
			CompensationPayloadHash:    fixed32(t, request.GetCompensationPayloadHash()),
			MessageExpiresAt:           request.GetMessageExpiresAt(),
			RecoveryNonce:              request.GetRecoveryNonce(),
			ReasonCode:                 fixed32(t, request.GetReasonCode()),
			Action:                     uint8(request.GetAction()),
			AuthorizerSetHash:          fixed32(t, request.GetAuthorizerSetHash()),
			AuthorizerSetVersion:       request.GetAuthorizerSetVersion(),
		},
	}
	digest, err := DigestAuthorization(canonical)
	if err != nil {
		t.Fatal(err)
	}
	const expectedDigest = "2ca5318f1079c2d3c45a5cefb7c5cf784728956bd328df3ee36feeb9b16af0ad"
	if actual := hex.EncodeToString(digest[:]); actual != expectedDigest {
		t.Fatalf("recovery authorization digest changed: got %s want %s", actual, expectedDigest)
	}
	recoveryID, err := RecoveryID(canonical.Request)
	if err != nil {
		t.Fatal(err)
	}
	const expectedRecoveryID = "049c45f9e5e106b33a2932b696fc45bdf394b35bb7b94e2b79e837cdfc4b0763"
	if actual := hex.EncodeToString(recoveryID[:]); actual != expectedRecoveryID {
		t.Fatalf("recovery id changed: got %s want %s", actual, expectedRecoveryID)
	}
}

func TestRouteAuthorityBindingsHaveDeterministicProtobufWire(t *testing.T) {
	signerSet := &unifiedv1.CrossChainSignerSet{
		SignerSetHash: repeatedByte(0x60, 32),
		Version:       7,
		Threshold:     2,
		SignerAddresses: [][]byte{
			repeatedByte(0x11, 20),
			repeatedByte(0x22, 20),
			repeatedByte(0x33, 20),
		},
		ObserverAuthorityHash: repeatedByte(0x70, 32),
		ValidFrom:             timestamppb.New(time.Unix(1_700_000_000, 0)),
		ValidUntil:            timestamppb.New(time.Unix(1_800_000_000, 0)),
		Status:                unifiedv1.CrossChainSignerSetStatus_CROSS_CHAIN_SIGNER_SET_STATUS_ACTIVE,
	}
	signerWire, err := proto.MarshalOptions{Deterministic: true}.Marshal(signerSet)
	if err != nil {
		t.Fatal(err)
	}
	const expectedSignerWireSHA256 = "2237eefd7c6e62a3ae9dfc1c8698ef896cb8b363ed47237f22abc3e78bbfd832"
	signerWireHash := sha256.Sum256(signerWire)
	if actual := hex.EncodeToString(signerWireHash[:]); actual != expectedSignerWireSHA256 {
		t.Fatalf(
			"signer-set protobuf wire changed: got %s want %s",
			actual,
			expectedSignerWireSHA256,
		)
	}
	var recoveredSignerSet unifiedv1.CrossChainSignerSet
	if err := proto.Unmarshal(signerWire, &recoveredSignerSet); err != nil {
		t.Fatal(err)
	}
	if !proto.Equal(signerSet, &recoveredSignerSet) {
		t.Fatal("signer-set protobuf roundtrip changed the authority binding")
	}

	route := &unifiedv1.CrossChainRoutePolicy{
		RouteId:      &unifiedv1.Identifier{Value: "route-home-satellite-v7"},
		RouteVersion: 7,
		SourceDomain: &unifiedv1.CrossChainDomain{
			ChainId:           "31337",
			Coordinator:       repeatedByte(0x41, 20),
			ConfigurationHash: repeatedByte(0x42, 32),
			FinalityVerifier:  repeatedByte(0x43, 20),
			Version:           3,
		},
		DestinationDomain: &unifiedv1.CrossChainDomain{
			ChainId:           "31338",
			Coordinator:       repeatedByte(0x51, 20),
			ConfigurationHash: repeatedByte(0x52, 32),
			FinalityVerifier:  repeatedByte(0x53, 20),
			Version:           4,
		},
		AllowedActions: []unifiedv1.CrossChainActionType{
			unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1,
			unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_WRAPPED_UFT_MINTED_V1,
		},
		AdapterSetPolicyHash:          repeatedByte(0x61, 32),
		SourceFinalityPolicyHash:      repeatedByte(0x62, 32),
		DestinationFinalityPolicyHash: repeatedByte(0x63, 32),
		SignerThreshold:               2,
		TimeoutSeconds:                3_600,
		RouteAbsoluteCapUnits:         "1000000",
		ChainAbsoluteCapUnits:         "5000000",
		AdapterAbsoluteCapUnits:       "250000",
		PolicyHash:                    repeatedByte(0x64, 32),
		SourceSignerSetHash:           repeatedByte(0x65, 32),
		SourceSignerSetVersion:        11,
		DestinationSignerSetHash:      repeatedByte(0x66, 32),
		DestinationSignerSetVersion:   12,
	}
	routeWire, err := proto.MarshalOptions{Deterministic: true}.Marshal(route)
	if err != nil {
		t.Fatal(err)
	}
	const expectedRouteWireSHA256 = "fa54a0008ff00b48ec121c7d10ee19c9fec720a21bc9927119713e5f26506954"
	routeWireHash := sha256.Sum256(routeWire)
	if actual := hex.EncodeToString(routeWireHash[:]); actual != expectedRouteWireSHA256 {
		t.Fatalf(
			"route protobuf wire changed: got %s want %s",
			actual,
			expectedRouteWireSHA256,
		)
	}
	var recoveredRoute unifiedv1.CrossChainRoutePolicy
	if err := proto.Unmarshal(routeWire, &recoveredRoute); err != nil {
		t.Fatal(err)
	}
	if !proto.Equal(route, &recoveredRoute) {
		t.Fatal("route protobuf roundtrip changed directional signer bindings")
	}
	if recoveredRoute.GetSourceSignerSetVersion() != 11 ||
		recoveredRoute.GetDestinationSignerSetVersion() != 12 {
		t.Fatal("route protobuf roundtrip dropped signer-set versions")
	}
}

func repeatedByte(value byte, length int) []byte {
	result := make([]byte, length)
	for index := range result {
		result[index] = value
	}
	return result
}

func fixed32(t *testing.T, value []byte) [32]byte {
	t.Helper()
	if len(value) != 32 {
		t.Fatalf("expected 32 bytes, got %d", len(value))
	}
	var result [32]byte
	copy(result[:], value)
	return result
}

func fixed20(t *testing.T, value []byte) [20]byte {
	t.Helper()
	if len(value) != 20 {
		t.Fatalf("expected 20 bytes, got %d", len(value))
	}
	var result [20]byte
	copy(result[:], value)
	return result
}
