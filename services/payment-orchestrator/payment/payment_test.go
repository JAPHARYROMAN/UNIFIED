package payment

import (
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"slices"
	"testing"
	"time"
)

type recordingAccounting struct {
	transitions []Transition
	failures    int
}

func (accounting *recordingAccounting) Apply(transition Transition) ([]string, error) {
	if accounting.failures > 0 {
		accounting.failures--
		return nil, errors.New("synthetic accounting outage")
	}
	accounting.transitions = append(accounting.transitions, transition)
	return []string{"journal:" + transition.Payment.PaymentID + ":" + string(transition.To)}, nil
}

type fixture struct {
	orchestrator *Orchestrator
	accounting   *recordingAccounting
	privateKey   ed25519.PrivateKey
	now          time.Time
}

func newFixture(t *testing.T, supportsReversal bool) fixture {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate provider key: %v", err)
	}
	accounting := &recordingAccounting{}
	orchestrator, err := New([]Provider{{
		ID:               "provider-local",
		Rail:             RailBank,
		PublicKey:        publicKey,
		Active:           true,
		AssetID:          "asset:local:usd",
		SupportsReversal: supportsReversal,
		Version:          1,
	}}, accounting)
	if err != nil {
		t.Fatalf("new orchestrator: %v", err)
	}
	now := time.Unix(1_750_000_000, 0).UTC()
	return fixture{
		orchestrator: orchestrator,
		accounting:   accounting,
		privateKey:   privateKey,
		now:          now,
	}
}

func (fixture fixture) intent() Intent {
	return Intent{
		PaymentID:      "payment-001",
		LegalEntityID:  "entity-local",
		IdempotencyKey: "intent-key-001",
		CorrelationID:  "correlation-001",
		PayerReference: "payer-opaque-001",
		LoanID:         "loan-local-001",
		ProviderID:     "provider-local",
		Rail:           RailBank,
		Purpose:        "LOAN_REPAYMENT_UNALLOCATED",
		AssetID:        "asset:local:usd",
		Units:          "1000",
		ExpiresAt:      fixture.now.Add(time.Hour),
		SchemaVersion:  1,
	}
}

func (fixture fixture) callback(eventID string, status Status, offset time.Duration) Callback {
	return Callback{
		ProviderID:        "provider-local",
		ProviderEventID:   eventID,
		PaymentID:         "payment-001",
		ProviderReference: "provider-reference-001",
		Status:            status,
		AssetID:           "asset:local:usd",
		Units:             "1000",
		OccurredAt:        fixture.now.Add(offset),
		ExpiresAt:         fixture.now.Add(offset + 10*time.Minute),
		EvidenceHash:      "evidence-" + eventID,
	}
}

func (fixture fixture) ingest(
	t *testing.T,
	callback Callback,
	receivedAt time.Time,
) (CallbackResult, error) {
	t.Helper()
	raw, err := EncodeCallback(callback)
	if err != nil {
		t.Fatalf("encode callback: %v", err)
	}
	signature := ed25519.Sign(fixture.privateKey, SigningMessage(raw))
	return fixture.orchestrator.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		receivedAt,
	)
}

func TestIntentIdempotencyAndConflict(t *testing.T) {
	fixture := newFixture(t, true)
	first, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now)
	if err != nil {
		t.Fatalf("create intent: %v", err)
	}
	replayed, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now)
	if err != nil {
		t.Fatalf("replay intent: %v", err)
	}
	if first != replayed || first.Status != StatusCreated || first.Version != 1 {
		t.Fatal("idempotent intent replay did not return the original")
	}
	conflict := fixture.intent()
	conflict.Units = "1001"
	if _, err := fixture.orchestrator.CreateIntent(conflict, fixture.now); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("expected idempotency conflict, got %v", err)
	}
	if len(fixture.orchestrator.Payments()) != 1 {
		t.Fatal("intent conflict created another payment")
	}
}

func TestAuthenticatedLifecycleAndExactReplay(t *testing.T) {
	fixture := newFixture(t, true)
	if _, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	processing := fixture.callback("event-processing", StatusProcessing, time.Minute)
	if _, err := fixture.ingest(t, processing, fixture.now.Add(2*time.Minute)); err != nil {
		t.Fatalf("processing callback: %v", err)
	}
	provisional := fixture.callback("event-provisional", StatusProvisional, 3*time.Minute)
	first, err := fixture.ingest(t, provisional, fixture.now.Add(4*time.Minute))
	if err != nil {
		t.Fatalf("provisional callback: %v", err)
	}
	replayed, err := fixture.ingest(t, provisional, fixture.now.Add(5*time.Minute))
	if err != nil {
		t.Fatalf("provisional replay: %v", err)
	}
	if !replayed.Replayed || first.RawHash != replayed.RawHash ||
		!slices.Equal(first.JournalIDs, replayed.JournalIDs) {
		t.Fatal("exact callback replay did not return the original effect")
	}
	final := fixture.callback("event-final", StatusFinal, 6*time.Minute)
	result, err := fixture.ingest(t, final, fixture.now.Add(7*time.Minute))
	if err != nil {
		t.Fatalf("final callback: %v", err)
	}
	if result.Payment.Status != StatusFinal || result.Payment.Version != 4 ||
		len(fixture.accounting.transitions) != 2 {
		t.Fatal("authenticated lifecycle produced an unexpected state or effect count")
	}
	if len(fixture.orchestrator.RawCallbacks()) != 4 {
		t.Fatal("every ingress, including replay, must be retained")
	}
}

func TestInvalidCallbacksAreQuarantinedWithoutEconomicEffect(t *testing.T) {
	fixture := newFixture(t, true)
	if _, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	callback := fixture.callback("event-invalid-signature", StatusProcessing, time.Minute)
	raw, _ := EncodeCallback(callback)
	invalidSignature := make([]byte, ed25519.SignatureSize)
	if _, err := fixture.orchestrator.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		invalidSignature,
		fixture.now.Add(2*time.Minute),
	); !errors.Is(err, ErrUnauthorizedCallback) {
		t.Fatalf("expected authentication failure, got %v", err)
	}

	stale := fixture.callback("event-stale", StatusProcessing, 3*time.Minute)
	stale.ExpiresAt = fixture.now.Add(4 * time.Minute)
	if _, err := fixture.ingest(t, stale, fixture.now.Add(5*time.Minute)); !errors.Is(err, ErrInvalidCallback) {
		t.Fatalf("expected stale callback rejection, got %v", err)
	}

	mismatch := fixture.callback("event-mismatch", StatusProcessing, 6*time.Minute)
	mismatch.Units = "999"
	if _, err := fixture.ingest(t, mismatch, fixture.now.Add(7*time.Minute)); !errors.Is(err, ErrInvalidCallback) {
		t.Fatalf("expected exact-amount rejection, got %v", err)
	}

	unknown := fixture.callback("event-unknown", StatusProcessing, 8*time.Minute)
	unknown.PaymentID = "payment-unknown"
	if _, err := fixture.ingest(t, unknown, fixture.now.Add(9*time.Minute)); !errors.Is(err, ErrUnknownPayment) {
		t.Fatalf("expected unknown payment rejection, got %v", err)
	}

	payment, _ := fixture.orchestrator.Payment("payment-001")
	if payment.Status != StatusCreated || len(fixture.accounting.transitions) != 0 ||
		len(fixture.orchestrator.Quarantines()) != 4 {
		t.Fatal("invalid callbacks changed economics or escaped quarantine")
	}
	rawRecords := fixture.orchestrator.RawCallbacks()
	rawRecords[0].RawPayload[0] ^= 0xff
	if fixture.orchestrator.RawCallbacks()[0].RawPayload[0] == rawRecords[0].RawPayload[0] {
		t.Fatal("raw callback evidence was mutable through a returned slice")
	}
}

func TestConflictingReplayAndOutOfOrderDeliveryFailClosed(t *testing.T) {
	fixture := newFixture(t, true)
	if _, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	processing := fixture.callback("event-shared", StatusProcessing, time.Minute)
	if _, err := fixture.ingest(t, processing, fixture.now.Add(2*time.Minute)); err != nil {
		t.Fatalf("processing callback: %v", err)
	}
	conflict := fixture.callback("event-shared", StatusProvisional, 3*time.Minute)
	if _, err := fixture.ingest(t, conflict, fixture.now.Add(4*time.Minute)); !errors.Is(err, ErrCallbackConflict) {
		t.Fatalf("expected provider event conflict, got %v", err)
	}
	final := fixture.callback("event-final-too-early", StatusFinal, 5*time.Minute)
	if _, err := fixture.ingest(t, final, fixture.now.Add(6*time.Minute)); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("expected out-of-order rejection, got %v", err)
	}
	current, _ := fixture.orchestrator.Payment("payment-001")
	if current.Status != StatusProcessing || len(fixture.accounting.transitions) != 0 ||
		len(fixture.orchestrator.Quarantines()) != 2 {
		t.Fatal("conflict or reordered delivery changed payment economics")
	}
}

func TestAccountingOutageCanRetryWithoutPartialState(t *testing.T) {
	fixture := newFixture(t, true)
	if _, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	if _, err := fixture.ingest(
		t,
		fixture.callback("event-processing", StatusProcessing, time.Minute),
		fixture.now.Add(2*time.Minute),
	); err != nil {
		t.Fatalf("processing callback: %v", err)
	}
	fixture.accounting.failures = 1
	provisional := fixture.callback("event-provisional", StatusProvisional, 3*time.Minute)
	if _, err := fixture.ingest(t, provisional, fixture.now.Add(4*time.Minute)); !errors.Is(err, ErrAccounting) {
		t.Fatalf("expected accounting outage, got %v", err)
	}
	current, _ := fixture.orchestrator.Payment("payment-001")
	if current.Status != StatusProcessing || len(fixture.accounting.transitions) != 0 {
		t.Fatal("accounting outage left partial payment state")
	}
	if _, err := fixture.ingest(t, provisional, fixture.now.Add(5*time.Minute)); err != nil {
		t.Fatalf("retry after accounting outage: %v", err)
	}
	current, _ = fixture.orchestrator.Payment("payment-001")
	if current.Status != StatusProvisional || len(fixture.accounting.transitions) != 1 {
		t.Fatal("retry did not create exactly one effect")
	}
}

func TestReversalCapabilityAndQuarantineResolution(t *testing.T) {
	fixture := newFixture(t, false)
	if _, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	if _, err := fixture.ingest(
		t,
		fixture.callback("event-processing", StatusProcessing, time.Minute),
		fixture.now.Add(2*time.Minute),
	); err != nil {
		t.Fatalf("processing callback: %v", err)
	}
	if _, err := fixture.ingest(
		t,
		fixture.callback("event-provisional", StatusProvisional, 3*time.Minute),
		fixture.now.Add(4*time.Minute),
	); err != nil {
		t.Fatalf("provisional callback: %v", err)
	}
	reversal := fixture.callback("event-reversal", StatusReversed, 5*time.Minute)
	if _, err := fixture.ingest(t, reversal, fixture.now.Add(6*time.Minute)); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("expected unsupported reversal rejection, got %v", err)
	}
	quarantine := fixture.orchestrator.Quarantines()[0]
	resolution, err := fixture.orchestrator.ResolveQuarantine(
		quarantine.QuarantineID,
		"resolution-001",
		"resolution-evidence",
		"payment-operator",
		fixture.now.Add(7*time.Minute),
	)
	if err != nil {
		t.Fatalf("resolve quarantine: %v", err)
	}
	if resolution.QuarantineID != quarantine.QuarantineID {
		t.Fatal("resolution lost quarantine linkage")
	}
	if _, err := fixture.orchestrator.ResolveQuarantine(
		quarantine.QuarantineID,
		"resolution-002",
		"different",
		"payment-operator",
		fixture.now.Add(8*time.Minute),
	); !errors.Is(err, ErrInvalidResolution) {
		t.Fatalf("expected immutable resolution rejection, got %v", err)
	}
}

func TestOversizeAndNoncanonicalPayloadsRetainOnlySafeEvidence(t *testing.T) {
	fixture := newFixture(t, true)
	if _, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	oversize := make([]byte, MaxCallbackBytes+1)
	oversizeSignature := ed25519.Sign(fixture.privateKey, SigningMessage(oversize))
	if _, err := fixture.orchestrator.IngestCallback(
		"provider-local",
		"event-oversize",
		oversize,
		oversizeSignature,
		fixture.now.Add(time.Minute),
	); !errors.Is(err, ErrInvalidCallback) {
		t.Fatalf("expected oversize rejection, got %v", err)
	}
	records := fixture.orchestrator.RawCallbacks()
	if len(records) != 1 || len(records[0].RawPayload) != 0 || records[0].RawHash == "" {
		t.Fatal("oversize ingress did not retain hash-only evidence")
	}

	callback := fixture.callback("event-noncanonical", StatusProcessing, 2*time.Minute)
	raw, _ := EncodeCallback(callback)
	raw = append(raw, '\n')
	signature := ed25519.Sign(fixture.privateKey, SigningMessage(raw))
	if _, err := fixture.orchestrator.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		fixture.now.Add(3*time.Minute),
	); !errors.Is(err, ErrInvalidCallback) {
		t.Fatalf("expected noncanonical rejection, got %v", err)
	}
	current, _ := fixture.orchestrator.Payment("payment-001")
	if current.Status != StatusCreated || len(fixture.orchestrator.Quarantines()) != 2 {
		t.Fatal("unsafe payload changed payment state or escaped quarantine")
	}
}
