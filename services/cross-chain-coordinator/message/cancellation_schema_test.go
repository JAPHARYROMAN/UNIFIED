package message

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"testing"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"google.golang.org/protobuf/proto"
)

const cancellationGoldenAmount = "1000000000000000000"

func repeatedCancellationByte(value byte, length int) []byte {
	return bytes.Repeat([]byte{value}, length)
}

func cancellationAuthorizationGolden() *unifiedv1.LoanCancellationAuthorization {
	return &unifiedv1.LoanCancellationAuthorization{
		LoanRouter:                repeatedCancellationByte(0x11, 20),
		LoanId:                    repeatedCancellationByte(0x22, 32),
		FundingLockId:             repeatedCancellationByte(0x33, 32),
		DisbursementMessageId:     repeatedCancellationByte(0x44, 32),
		DisbursementTombstoneHash: repeatedCancellationByte(0x55, 32),
		Amount:                    cancellationGoldenAmount,
		PolicyHash:                repeatedCancellationByte(0x66, 32),
		AuthorizationNonce:        7,
		ValidUntil:                1_700_003_600,
		ReasonCode:                repeatedCancellationByte(0x77, 32),
		AuthorizerSetHash:         repeatedCancellationByte(0x88, 32),
		AuthorizerSetVersion:      1,
	}
}

func cancellationRequestedGolden() *unifiedv1.LoanCancellationRequestedPayload {
	return &unifiedv1.LoanCancellationRequestedPayload{
		CancellationId:            repeatedCancellationByte(0x99, 32),
		LoanId:                    repeatedCancellationByte(0x22, 32),
		FundingLockId:             repeatedCancellationByte(0x33, 32),
		DisbursementMessageId:     repeatedCancellationByte(0x44, 32),
		DisbursementTombstoneHash: repeatedCancellationByte(0x55, 32),
		HomeLoanAccount:           repeatedCancellationByte(0xaa, 20),
		Lender:                    repeatedCancellationByte(0xbb, 20),
		WrappedToken:              repeatedCancellationByte(0xcc, 20),
		Amount:                    cancellationGoldenAmount,
		PolicyHash:                repeatedCancellationByte(0x66, 32),
		ReasonCode:                repeatedCancellationByte(0x77, 32),
	}
}

func fundingCancelledGolden() *unifiedv1.SatelliteFundingCancelledPayload {
	return &unifiedv1.SatelliteFundingCancelledPayload{
		CancellationId:            repeatedCancellationByte(0x99, 32),
		LoanId:                    repeatedCancellationByte(0x22, 32),
		FundingLockId:             repeatedCancellationByte(0x33, 32),
		DisbursementMessageId:     repeatedCancellationByte(0x44, 32),
		DisbursementTombstoneHash: repeatedCancellationByte(0x55, 32),
		EscrowBurnResultHash:      repeatedCancellationByte(0xdd, 32),
		HomeLoanAccount:           repeatedCancellationByte(0xaa, 20),
		Lender:                    repeatedCancellationByte(0xbb, 20),
		WrappedToken:              repeatedCancellationByte(0xcc, 20),
		Amount:                    cancellationGoldenAmount,
		PolicyHash:                repeatedCancellationByte(0x66, 32),
	}
}

func TestCancellationSchemasMatchSolidityABIGoldens(t *testing.T) {
	authorization, err := EncodeLoanCancellationAuthorizationABI(
		cancellationAuthorizationGolden(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(authorization) != 12*32 {
		t.Fatalf("authorization ABI is %d bytes, want 12 words", len(authorization))
	}
	authorizationHash := keccak(authorization)
	if actual := hex.EncodeToString(authorizationHash[:]); actual !=
		"6559f566fae044a0b47fad5ad54de9a09b55e0cba3bd34290293e4e3e36b0bc0" {
		t.Fatalf("authorization ABI golden changed: %s", actual)
	}

	requestEnvelope := &unifiedv1.CrossChainMessageEnvelope{
		ActionType: unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANCELLATION_REQUESTED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_LoanCancellationRequested{
			LoanCancellationRequested: cancellationRequestedGolden(),
		},
	}
	request, err := EncodeTypedActionABI(requestEnvelope)
	if err != nil {
		t.Fatal(err)
	}
	if len(request) != 11*32 {
		t.Fatalf("action-12 ABI is %d bytes, want 11 words", len(request))
	}
	requestHash := keccak(request)
	if actual := hex.EncodeToString(requestHash[:]); actual !=
		"d8b5a830c89f14d7eaebe14c1c819a2526194c05491fb357bf972464612fb992" {
		t.Fatalf("action-12 ABI golden changed: %s", actual)
	}

	completionEnvelope := &unifiedv1.CrossChainMessageEnvelope{
		ActionType: unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SOURCE_COMPENSATED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_SatelliteFundingCancelled{
			SatelliteFundingCancelled: fundingCancelledGolden(),
		},
	}
	completion, err := EncodeTypedActionABI(completionEnvelope)
	if err != nil {
		t.Fatal(err)
	}
	if len(completion) != 11*32 {
		t.Fatalf("action-14 ABI is %d bytes, want 11 words", len(completion))
	}
	completionHash := keccak(completion)
	if actual := hex.EncodeToString(completionHash[:]); actual !=
		"e272800252a7b96d69aba58e658c1151e5211a1c7137700ff341cbe2d9c23dba" {
		t.Fatalf("action-14 ABI golden changed: %s", actual)
	}
}

func TestCancellationProtobufWireAndOneofTagsAreFrozen(t *testing.T) {
	assertWireGolden := func(message proto.Message, expectedLength int, expectedHash string) {
		t.Helper()
		wire, err := proto.MarshalOptions{Deterministic: true}.Marshal(message)
		if err != nil {
			t.Fatal(err)
		}
		if len(wire) != expectedLength {
			t.Fatalf("wire length is %d, want %d", len(wire), expectedLength)
		}
		actual := sha256.Sum256(wire)
		if hex.EncodeToString(actual[:]) != expectedHash {
			t.Fatalf("wire SHA-256 changed: %x", actual)
		}
	}

	assertWireGolden(
		cancellationAuthorizationGolden(),
		291,
		"d49fc566ee4db808a2baa92b2ce06d3bf7c22f57909e8fe6325118033d11622a",
	)
	assertWireGolden(
		cancellationRequestedGolden(),
		325,
		"15e698482aa0b475255ea058fca3ed816a7cae9921658c1c85dfe958b4155285",
	)
	assertWireGolden(
		fundingCancelledGolden(),
		325,
		"1c7fe124da7a90146e157f9afea1b265ccda3394b1312b5044045766519a1909",
	)

	requestEnvelope := &unifiedv1.CrossChainMessageEnvelope{
		ActionType: unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANCELLATION_REQUESTED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_LoanCancellationRequested{
			LoanCancellationRequested: cancellationRequestedGolden(),
		},
	}
	completionEnvelope := &unifiedv1.CrossChainMessageEnvelope{
		ActionType: unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SOURCE_COMPENSATED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_SatelliteFundingCancelled{
			SatelliteFundingCancelled: fundingCancelledGolden(),
		},
	}
	assertWireGolden(
		requestEnvelope,
		331,
		"f44dda8552740502b82c98dc488e20d2da4084f37cd924a557c44df79c429d52",
	)
	assertWireGolden(
		completionEnvelope,
		331,
		"4a61e679ca6b749434663f331d6da94fffd5cff01edb3104138145242a6a56d7",
	)

	typedAction := requestEnvelope.ProtoReflect().Descriptor().Oneofs().ByName("typed_action")
	if typedAction.Fields().ByName("loan_cancellation_requested").Number() != 40 {
		t.Fatal("action-12 typed oneof tag is not 40")
	}
	if typedAction.Fields().ByName("satellite_funding_cancelled").Number() != 42 {
		t.Fatal("action-14 typed oneof tag is not 42")
	}
}

func TestAction14CancellationCompletionCannotUseGenericTypedPayload(t *testing.T) {
	envelope := &unifiedv1.CrossChainMessageEnvelope{
		ActionType: unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SOURCE_COMPENSATED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_LoanCancellationRequested{
			LoanCancellationRequested: cancellationRequestedGolden(),
		},
	}
	if _, err := EncodeTypedActionABI(envelope); !errors.Is(err, ErrInvalidEnvelope) {
		t.Fatalf("expected action-14 typed-payload mismatch, got %v", err)
	}
}
