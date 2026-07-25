package store

import (
	"errors"
	"testing"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
)

func TestRouteVersionsAreImmutable(t *testing.T) {
	repository := NewMemory()
	route := RouteVersion{
		RouteID: "route-local", Version: 1, PolicyHash: [32]byte{1},
		SourceChain: "31337", DestinationChain: "31338",
		ActivatedAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	if err := repository.PutRoute(route); err != nil {
		t.Fatalf("put route: %v", err)
	}
	route.PolicyHash = [32]byte{2}
	if err := repository.PutRoute(route); !errors.Is(err, ErrImmutableRoute) {
		t.Fatalf("expected immutable route rejection, got %v", err)
	}
}

func TestMessageCASAndReplay(t *testing.T) {
	repository := NewMemory()
	record := MessageRecord{
		MessageID: [32]byte{1},
		Envelope:  []byte("immutable"),
		State:     unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED,
		Version:   1,
		UpdatedAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	if _, err := repository.CreateMessage(record); err != nil {
		t.Fatalf("create: %v", err)
	}
	if _, err := repository.CreateMessage(record); err != nil {
		t.Fatalf("exact replay: %v", err)
	}
	if _, err := repository.CompareAndSet(
		record.MessageID,
		1,
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING,
		false,
		[32]byte{2},
		time.Unix(1_700_000_001, 0).UTC(),
	); err != nil {
		t.Fatalf("cas: %v", err)
	}
	if _, err := repository.CompareAndSet(
		record.MessageID,
		1,
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINAL,
		false,
		[32]byte{3},
		time.Unix(1_700_000_002, 0).UTC(),
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("expected stale version conflict, got %v", err)
	}
}

func TestCASRejectsJumpZeroEvidenceAndBackdatedTime(t *testing.T) {
	repository := NewMemory()
	updatedAt := time.Unix(1_700_000_000, 0).UTC()
	record := MessageRecord{
		MessageID: [32]byte{1}, Envelope: []byte("immutable"),
		State:   unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED,
		Version: 1, UpdatedAt: updatedAt,
	}
	if _, err := repository.CreateMessage(record); err != nil {
		t.Fatalf("create: %v", err)
	}
	for name, candidate := range map[string]struct {
		next     unifiedv1.CrossChainMessageState
		evidence [32]byte
		at       time.Time
	}{
		"jump": {
			next:     unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXECUTED,
			evidence: [32]byte{1}, at: updatedAt,
		},
		"zero evidence": {
			next: unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING,
			at:   updatedAt,
		},
		"backdated": {
			next:     unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING,
			evidence: [32]byte{1}, at: updatedAt.Add(-time.Second),
		},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := repository.CompareAndSet(
				record.MessageID, 1, candidate.next, false, candidate.evidence, candidate.at,
			); !errors.Is(err, ErrConflict) {
				t.Fatalf("expected conflict, got %v", err)
			}
		})
	}
}

func TestRouteRejectsZeroPolicySameDomainAndBadDeprecation(t *testing.T) {
	repository := NewMemory()
	activated := time.Unix(1_700_000_000, 0).UTC()
	badDeprecation := activated.Add(-time.Second)
	for name, route := range map[string]RouteVersion{
		"zero policy": {
			RouteID: "route", Version: 1, SourceChain: "31337",
			DestinationChain: "31338", ActivatedAt: activated,
		},
		"same domain": {
			RouteID: "route", Version: 1, PolicyHash: [32]byte{1},
			SourceChain: "31337", DestinationChain: "31337", ActivatedAt: activated,
		},
		"bad deprecation": {
			RouteID: "route", Version: 1, PolicyHash: [32]byte{1},
			SourceChain: "31337", DestinationChain: "31338",
			ActivatedAt: activated, DeprecatedAt: &badDeprecation,
		},
	} {
		t.Run(name, func(t *testing.T) {
			if err := repository.PutRoute(route); err == nil {
				t.Fatal("invalid route accepted")
			}
		})
	}
}
