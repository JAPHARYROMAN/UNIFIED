package message

import (
	"bytes"
	"context"
	"encoding/hex"
	"errors"
	"testing"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func testEnvelope(t *testing.T, nonce uint64) *unifiedv1.CrossChainMessageEnvelope {
	t.Helper()
	hash := bytes.Repeat([]byte{0x11}, 32)
	zero := make([]byte, 32)
	createdAt := time.Unix(1_700_000_000, 0).UTC()
	envelope := &unifiedv1.CrossChainMessageEnvelope{
		SchemaVersion:          1,
		ProtocolId:             bytes.Repeat([]byte{0x01}, 32),
		SourceChainId:          "31337",
		SourceCoordinator:      bytes.Repeat([]byte{0x02}, 20),
		SourceComponent:        bytes.Repeat([]byte{0x03}, 20),
		DestinationChainId:     "31338",
		DestinationCoordinator: bytes.Repeat([]byte{0x04}, 20),
		DestinationComponent:   bytes.Repeat([]byte{0x05}, 20),
		LaneId:                 bytes.Repeat([]byte{0x06}, 32),
		SourceNonce:            nonce,
		AggregateId:            bytes.Repeat([]byte{0x07}, 32),
		ActionType:             unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_CanonicalUftLock{
			CanonicalUftLock: &unifiedv1.CanonicalUftLockPayload{
				LockId:               bytes.Repeat([]byte{0x11}, 32),
				LoanId:               bytes.Repeat([]byte{0x22}, 32),
				CanonicalToken:       bytes.Repeat([]byte{0x11}, 20),
				HomeBridgeHub:        bytes.Repeat([]byte{0x22}, 20),
				WrappedToken:         bytes.Repeat([]byte{0x33}, 20),
				DestinationRecipient: bytes.Repeat([]byte{0x44}, 20),
				Amount:               "1000000000000000000",
			},
		},
		CreatedAt:                     timestamppb.New(createdAt),
		ExpiresAt:                     timestamppb.New(createdAt.Add(time.Hour)),
		RoutePolicyHash:               append([]byte(nil), hash...),
		AdapterSetPolicyHash:          append([]byte(nil), hash...),
		SourceFinalityPolicyHash:      append([]byte(nil), hash...),
		DestinationFinalityPolicyHash: append([]byte(nil), hash...),
		CorrelationId:                 append([]byte(nil), hash...),
		CausationMessageId:            append([]byte(nil), zero...),
		SupersededMessageId:           append([]byte(nil), zero...),
	}
	if err := BindTypedActionABI(envelope); err != nil {
		t.Fatalf("bind ABI payload: %v", err)
	}
	sealed, err := Seal(envelope)
	if err != nil {
		t.Fatalf("seal: %v", err)
	}
	return sealed
}

func testRegistry() *Registry {
	return NewRegistryWithClock(func() time.Time {
		return time.Unix(1_700_000_100, 0).UTC()
	})
}

func testReportEnvelope(
	t *testing.T,
	action unifiedv1.CrossChainActionType,
) *unifiedv1.CrossChainMessageEnvelope {
	t.Helper()
	envelope := testEnvelope(t, 1)
	envelope.MessageId = nil
	envelope.ActionType = action
	hash32 := func(value byte) []byte { return bytes.Repeat([]byte{value}, 32) }
	address := func(value byte) []byte { return bytes.Repeat([]byte{value}, 20) }
	switch action {
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_WRAPPED_UFT_MINTED_V1:
		envelope.TypedAction = &unifiedv1.CrossChainMessageEnvelope_WrappedUftMinted{
			WrappedUftMinted: &unifiedv1.WrappedUftMintedPayload{
				LoanId: hash32(0x21), LockId: hash32(0x22),
				HomeLoanAccount: address(0x23), Borrower: address(0x24),
				Lender: address(0x25), WrappedToken: address(0x26),
				Amount: "1", PolicyHash: hash32(0x27),
			},
		}
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_LOCKED_V1:
		envelope.TypedAction = &unifiedv1.CrossChainMessageEnvelope_SatelliteCollateralLocked{
			SatelliteCollateralLocked: &unifiedv1.SatelliteCollateralLockedPayload{
				LoanId: hash32(0x31), CollateralId: hash32(0x32),
				HomeLoanAccount: address(0x33), Borrower: address(0x34),
				Lender: address(0x35), CollateralToken: address(0x36),
				Amount: "1", PolicyHash: hash32(0x37),
			},
		}
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_DISBURSEMENT_SETTLED_V1:
		envelope.TypedAction = &unifiedv1.CrossChainMessageEnvelope_SatelliteDisbursementSettled{
			SatelliteDisbursementSettled: &unifiedv1.SatelliteDisbursementSettledPayload{
				LoanId: hash32(0x41), FundingLockId: hash32(0x42),
				HomeLoanAccount: address(0x43), Borrower: address(0x44),
				Lender: address(0x45), WrappedToken: address(0x46),
				Amount: "1", PolicyHash: hash32(0x47),
			},
		}
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_RELEASED_V1:
		envelope.TypedAction = &unifiedv1.CrossChainMessageEnvelope_SatelliteCollateralReleased{
			SatelliteCollateralReleased: &unifiedv1.SatelliteCollateralReleasedPayload{
				LoanId: hash32(0x51), CollateralId: hash32(0x52),
				HomeLoanAccount: address(0x53), Borrower: address(0x54),
				Lender: address(0x55), CollateralToken: address(0x56),
				Amount: "1", PolicyHash: hash32(0x57),
			},
		}
	default:
		t.Fatalf("action %s is not a report fixture", action)
	}
	if err := BindTypedActionABI(envelope); err != nil {
		t.Fatal(err)
	}
	sealed, err := Seal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	return sealed
}

func TestGoldenMessageIDUsesNumericActionOrdinal(t *testing.T) {
	envelope := testEnvelope(t, 1)
	const expectedPayloadHash = "805585e890e898930c0ac7d38c1e157d0e4a5964eb8239552298bb2d3789877a"
	if actual := hex.EncodeToString(envelope.GetPayloadHash()); actual != expectedPayloadHash {
		t.Fatalf("golden payload hash changed: got %s want %s", actual, expectedPayloadHash)
	}
	const expected = "f8d9ef5672d829229110e480489155be0440e916833a1290a8955a8acf9c4801"
	actual := hex.EncodeToString(envelope.GetMessageId())
	if actual != expected {
		t.Fatalf("golden message id changed: got %s want %s", actual, expected)
	}
}

func TestDigestIsNonRecursiveAndDomainBound(t *testing.T) {
	envelope := testEnvelope(t, 1)
	first := append([]byte(nil), envelope.MessageId...)
	envelope.MessageId = bytes.Repeat([]byte{0xff}, 32)
	computed, err := ComputeMessageID(envelope)
	if err != nil {
		t.Fatalf("compute: %v", err)
	}
	if !bytes.Equal(first, computed[:]) {
		t.Fatal("message_id was recursively included in its preimage")
	}
	envelope.DestinationChainId = "31339"
	changed, err := ComputeMessageID(envelope)
	if err != nil {
		t.Fatalf("compute changed domain: %v", err)
	}
	if bytes.Equal(first, changed[:]) {
		t.Fatal("destination domain did not change message identity")
	}
}

func TestRejectsTypedActionMismatch(t *testing.T) {
	envelope := testEnvelope(t, 1)
	envelope.TypedAction = &unifiedv1.CrossChainMessageEnvelope_SatelliteCollateralLocked{
		SatelliteCollateralLocked: &unifiedv1.SatelliteCollateralLockedPayload{},
	}
	if err := ValidateEnvelope(envelope); !errors.Is(err, ErrInvalidEnvelope) {
		t.Fatalf("expected action/oneof mismatch, got %v", err)
	}
}

func TestRejectsCallerAuthoredABIBytesThatDisagreeWithTypedAction(t *testing.T) {
	envelope := testEnvelope(t, 1)
	envelope.TypedActionPayload[0] ^= 0xff
	hash := keccak(envelope.TypedActionPayload)
	envelope.PayloadHash = hash[:]
	envelope, err := Seal(envelope)
	if !errors.Is(err, ErrInvalidEnvelope) || envelope != nil {
		t.Fatalf("expected typed ABI mismatch, got envelope=%v err=%v", envelope, err)
	}
}

func TestRegistryExecutesOnceAndReturnsExactReplay(t *testing.T) {
	registry := testRegistry()
	envelope := testEnvelope(t, 1)
	calls := 0
	handler := func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
		calls++
		return []byte("result"), nil
	}
	first, err := registry.Execute(context.Background(), envelope, handler)
	if err != nil {
		t.Fatalf("execute: %v", err)
	}
	second, err := registry.Execute(context.Background(), envelope, handler)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if calls != 1 || first.Replay || !second.Replay || !bytes.Equal(second.Result, []byte("result")) {
		t.Fatal("exact replay repeated or changed the result")
	}
}

func TestRegistryRejectsExpiryAtBoundaryBeforeHandler(t *testing.T) {
	now := time.Unix(1_700_003_600, 0).UTC()
	registry := NewRegistryWithClock(func() time.Time { return now })
	envelope := testEnvelope(t, 1)
	calls := 0
	result, err := registry.Execute(
		context.Background(),
		envelope,
		func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
			calls++
			return []byte("must-not-run"), nil
		},
	)
	if !errors.Is(err, ErrMessageExpired) ||
		result.State != unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXPIRED ||
		calls != 0 {
		t.Fatalf("expired message executed or was not retained: state=%v calls=%d err=%v", result.State, calls, err)
	}
	replay, err := registry.Execute(
		context.Background(),
		envelope,
		func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
			calls++
			return nil, nil
		},
	)
	if !errors.Is(err, ErrMessageExpired) || !replay.Replay || calls != 0 {
		t.Fatalf("expired replay changed state: %#v calls=%d err=%v", replay, calls, err)
	}
}

func TestRegistryAcceptsFinalizedReportsAfterTransportExpiry(t *testing.T) {
	reportActions := []unifiedv1.CrossChainActionType{
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_WRAPPED_UFT_MINTED_V1,
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_LOCKED_V1,
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_DISBURSEMENT_SETTLED_V1,
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_RELEASED_V1,
	}
	for _, action := range reportActions {
		t.Run(action.String(), func(t *testing.T) {
			now := time.Unix(1_700_003_600, 0).UTC()
			registry := NewRegistryWithClock(func() time.Time { return now })
			envelope := testReportEnvelope(t, action)
			calls := 0
			result, err := registry.Execute(
				context.Background(),
				envelope,
				func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
					calls++
					return []byte("finalized-report"), nil
				},
			)
			if err != nil || calls != 1 ||
				result.State != unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXECUTED {
				t.Fatalf(
					"finalized report was discarded: state=%s calls=%d err=%v",
					result.State,
					calls,
					err,
				)
			}
			if !IsReportAction(action) {
				t.Fatal("report action helper drifted")
			}
		})
	}
	if IsReportAction(
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1,
	) {
		t.Fatal("economic command was classified as a report")
	}
}

func TestRegistryRetainsRetryableFailureWithoutPartialConsume(t *testing.T) {
	registry := testRegistry()
	envelope := testEnvelope(t, 1)
	calls := 0
	handler := func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
		calls++
		if calls == 1 {
			return nil, errors.New("target reverted")
		}
		return []byte("success"), nil
	}
	if result, err := registry.Execute(context.Background(), envelope, handler); err == nil ||
		result.State != unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_FAILED {
		t.Fatalf("expected retained failed state, got state %v err %v", result.State, err)
	}
	result, err := registry.Execute(context.Background(), envelope, handler)
	if err != nil || result.State != unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXECUTED {
		t.Fatalf("retry failed: state %v err %v", result.State, err)
	}
}

func TestRegistryRejectsFutureNonceAndChangedContent(t *testing.T) {
	registry := testRegistry()
	future := testEnvelope(t, 2)
	if _, err := registry.Execute(context.Background(), future, func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
		return nil, nil
	}); !errors.Is(err, ErrOutOfOrder) {
		t.Fatalf("expected out of order, got %v", err)
	}

	first := testEnvelope(t, 1)
	if _, err := registry.Execute(context.Background(), first, func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
		return []byte("done"), nil
	}); err != nil {
		t.Fatalf("execute: %v", err)
	}
	changed := testEnvelope(t, 1)
	changed.AggregateId = bytes.Repeat([]byte{0xaa}, 32)
	changed, err := Seal(changed)
	if err != nil {
		t.Fatalf("seal changed: %v", err)
	}
	if _, err := registry.Execute(context.Background(), changed, func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
		return nil, nil
	}); !errors.Is(err, ErrNonceConflict) {
		t.Fatalf("expected nonce conflict, got %v", err)
	}
}
