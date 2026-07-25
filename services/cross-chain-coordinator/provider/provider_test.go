package provider

import (
	"bytes"
	"context"
	"errors"
	"testing"
	"time"
)

type fakeTransport struct {
	id       string
	err      error
	received [][]byte
}

func (transport *fakeTransport) ID() string { return transport.id }

func (transport *fakeTransport) Submit(_ context.Context, delivery Delivery) (Receipt, error) {
	transport.received = append(transport.received, append([]byte(nil), delivery.Envelope...))
	if transport.err != nil {
		return Receipt{}, transport.err
	}
	return Receipt{ProviderID: transport.id, Receipt: []byte("accepted")}, nil
}

func TestFailoverUsesExactImmutableBytes(t *testing.T) {
	first := &fakeTransport{id: "provider-a", err: Retryable(errors.New("outage"))}
	second := &fakeTransport{id: "provider-b"}
	router := NewRouter()
	var route [32]byte
	route[0] = 1
	if err := router.RegisterRoute(route, first, second); err != nil {
		t.Fatalf("register: %v", err)
	}
	delivery := Delivery{
		MessageID:   [32]byte{2},
		RoutePolicy: route,
		Envelope:    []byte("same-envelope"),
		SourceProof: []byte("same-proof"),
		AttemptedAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	delivery.EnvelopeHash = contentHash(delivery.Envelope)
	delivery.ProofHash = contentHash(delivery.SourceProof)
	receipt, err := router.Deliver(context.Background(), delivery)
	if err != nil {
		t.Fatalf("deliver: %v", err)
	}
	if receipt.ProviderID != "provider-b" ||
		len(first.received) != 1 || len(second.received) != 1 ||
		!bytes.Equal(first.received[0], second.received[0]) {
		t.Fatal("failover changed bytes or did not use the approved provider")
	}
	attempts := router.Attempts(delivery.MessageID)
	if len(attempts) != 2 || attempts[0].Success || !attempts[1].Success {
		t.Fatal("attempt evidence did not retain failure and success")
	}
}

func TestChangedRetryIsRejected(t *testing.T) {
	transport := &fakeTransport{id: "provider-a"}
	router := NewRouter()
	var route [32]byte
	route[0] = 1
	if err := router.RegisterRoute(route, transport); err != nil {
		t.Fatalf("register: %v", err)
	}
	delivery := Delivery{
		MessageID:   [32]byte{1},
		RoutePolicy: route,
		Envelope:    []byte("envelope"),
		SourceProof: []byte("proof"),
		AttemptedAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	delivery.EnvelopeHash = contentHash(delivery.Envelope)
	delivery.ProofHash = contentHash(delivery.SourceProof)
	if _, err := router.Deliver(context.Background(), delivery); err != nil {
		t.Fatalf("first delivery: %v", err)
	}
	delivery.Envelope = []byte("changed")
	if _, err := router.Deliver(context.Background(), delivery); !errors.Is(err, ErrIdentityConflict) {
		t.Fatalf("expected immutable identity conflict, got %v", err)
	}
}

func TestRejectsCallerSuppliedFalseContentHashes(t *testing.T) {
	transport := &fakeTransport{id: "provider-a"}
	router := NewRouter()
	var route [32]byte
	route[0] = 1
	if err := router.RegisterRoute(route, transport); err != nil {
		t.Fatalf("register: %v", err)
	}
	delivery := Delivery{
		MessageID: [32]byte{1}, RoutePolicy: route,
		Envelope: []byte("envelope"), EnvelopeHash: [32]byte{0xff},
		SourceProof: []byte("proof"), ProofHash: [32]byte{0xee},
		AttemptedAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	if _, err := router.Deliver(context.Background(), delivery); !errors.Is(err, ErrIdentityConflict) {
		t.Fatalf("expected content hash rejection, got %v", err)
	}
	if len(transport.received) != 0 {
		t.Fatal("false content hashes reached a provider")
	}
}

func TestNonRetryableFailureDoesNotReachFallbackProvider(t *testing.T) {
	first := &fakeTransport{id: "provider-a", err: errors.New("provider rejected authority")}
	second := &fakeTransport{id: "provider-b"}
	router := NewRouter()
	route := [32]byte{1}
	if err := router.RegisterRoute(route, first, second); err != nil {
		t.Fatal(err)
	}
	delivery := Delivery{
		MessageID: [32]byte{2}, RoutePolicy: route,
		Envelope: []byte("envelope"), SourceProof: []byte("proof"),
		AttemptedAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	delivery.EnvelopeHash = contentHash(delivery.Envelope)
	delivery.ProofHash = contentHash(delivery.SourceProof)
	if _, err := router.Deliver(t.Context(), delivery); err == nil ||
		errors.Is(err, ErrNoProvider) {
		t.Fatalf("expected closed nonretryable failure, got %v", err)
	}
	if len(first.received) != 1 || len(second.received) != 0 {
		t.Fatal("nonretryable failure reached fallback provider")
	}
}

func TestEmptyReceiptFailsClosed(t *testing.T) {
	empty := &receiptTransport{id: "provider-a"}
	fallback := &fakeTransport{id: "provider-b"}
	router := NewRouter()
	route := [32]byte{1}
	if err := router.RegisterRoute(route, empty, fallback); err != nil {
		t.Fatal(err)
	}
	delivery := Delivery{
		MessageID: [32]byte{2}, RoutePolicy: route,
		Envelope: []byte("envelope"), SourceProof: []byte("proof"),
		AttemptedAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	delivery.EnvelopeHash = contentHash(delivery.Envelope)
	delivery.ProofHash = contentHash(delivery.SourceProof)
	if _, err := router.Deliver(t.Context(), delivery); !errors.Is(err, ErrIdentityConflict) {
		t.Fatalf("expected receipt identity rejection, got %v", err)
	}
	if len(fallback.received) != 0 {
		t.Fatal("empty receipt reached fallback provider")
	}
}

type receiptTransport struct {
	id string
}

func (transport *receiptTransport) ID() string { return transport.id }

func (transport *receiptTransport) Submit(
	context.Context,
	Delivery,
) (Receipt, error) {
	return Receipt{ProviderID: transport.id}, nil
}

func TestRejectsZeroDeliveryCommitments(t *testing.T) {
	router := NewRouter()
	if err := router.RegisterRoute([32]byte{}, &fakeTransport{id: "provider-a"}); err == nil {
		t.Fatal("zero route policy was accepted")
	}
}
