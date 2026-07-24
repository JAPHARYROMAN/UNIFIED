package payment

import (
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
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

func claimModeForPaymentTest(
	modes *allocationmode.Registry,
	paymentID string,
	allocationID string,
	mode allocationmode.Mode,
	digest string,
) (allocationmode.Claim, bool, error) {
	claimedAt := time.Unix(1_750_000_000, 0).UTC()
	if mode == allocationmode.ModeCanonicalGateway {
		claim, err := modes.ClaimModeWithCommit(
			paymentID,
			allocationID,
			mode,
			digest,
			4,
			"canonical-evidence:"+digest,
			claimedAt,
			func(allocationmode.Claim) error { return nil },
		)
		return claim, false, err
	}
	return modes.ClaimMode(
		paymentID,
		allocationID,
		mode,
		digest,
		4,
		digest,
		claimedAt,
	)
}

func newFixture(t *testing.T, supportsReversal bool) fixture {
	return newFixtureWithModes(t, supportsReversal, allocationmode.NewInMemory())
}

func newFixtureWithModes(
	t *testing.T,
	supportsReversal bool,
	modes *allocationmode.Registry,
) fixture {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate provider key: %v", err)
	}
	accounting := &recordingAccounting{}
	canonical, err := NewLocalCanonicalReversalCoordinator(modes)
	if err != nil {
		t.Fatalf("new canonical reversal coordinator: %v", err)
	}
	orchestrator, err := New([]Provider{{
		ID:               "provider-local",
		Rail:             RailBank,
		PublicKey:        publicKey,
		Active:           true,
		AssetID:          "asset:local:usd",
		SupportsReversal: supportsReversal,
		Version:          1,
	}}, accounting, modes, canonical)
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

func finalizeFixturePayment(t *testing.T, fixture fixture) {
	t.Helper()
	if _, err := fixture.orchestrator.CreateIntent(fixture.intent(), fixture.now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	steps := []struct {
		id     string
		status Status
		offset time.Duration
	}{
		{"event-processing", StatusProcessing, time.Minute},
		{"event-provisional", StatusProvisional, 3 * time.Minute},
		{"event-final", StatusFinal, 5 * time.Minute},
	}
	for _, step := range steps {
		if _, err := fixture.ingest(
			t,
			fixture.callback(step.id, step.status, step.offset),
			fixture.now.Add(step.offset+time.Minute),
		); err != nil {
			t.Fatalf("ingest %s: %v", step.status, err)
		}
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

func TestCanonicalReversalGuardPreparedSubmittedAndConfirmed(t *testing.T) {
	t.Run("prepared reversal is quarantined before accounting", func(t *testing.T) {
		modes := allocationmode.NewInMemory()
		fixture := newFixtureWithModes(t, true, modes)
		finalizeFixturePayment(t, fixture)
		if _, _, err := claimModeForPaymentTest(modes,
			"payment-001",
			"allocation-canonical",
			allocationmode.ModeCanonicalGateway,
			"digest-canonical",
		); err != nil {
			t.Fatal(err)
		}
		result, err := fixture.ingest(
			t,
			fixture.callback("event-reversal-prepared", StatusReversed, 7*time.Minute),
			fixture.now.Add(8*time.Minute),
		)
		if !errors.Is(err, ErrCanonicalPending) ||
			result.Payment.Status != StatusFinal ||
			result.Disposition != "QUARANTINED" {
			t.Fatalf("prepared reversal was not blocked durably: %#v %v", result, err)
		}
		retained, exists := modes.Lookup("payment-001")
		if !exists || retained.State != allocationmode.CanonicalQuarantined {
			t.Fatalf("prepared canonical claim was not quarantined: %#v", retained)
		}
		if len(fixture.accounting.transitions) != 2 {
			t.Fatal("prepared reversal posted accounting before resolution")
		}
	})

	t.Run("submitted reversal is quarantined without mutation", func(t *testing.T) {
		modes := allocationmode.NewInMemory()
		fixture := newFixtureWithModes(t, true, modes)
		finalizeFixturePayment(t, fixture)
		claim, _, err := claimModeForPaymentTest(modes,
			"payment-001",
			"allocation-canonical",
			allocationmode.ModeCanonicalGateway,
			"digest-canonical",
		)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := modes.TransitionWithCommit(
			claim.PaymentID,
			claim.AllocationID,
			claim.Digest,
			allocationmode.CanonicalPrepared,
			allocationmode.CanonicalSubmitted,
			func(allocationmode.Claim) error { return nil },
		); err != nil {
			t.Fatal(err)
		}
		callback := fixture.callback(
			"event-reversal-submitted",
			StatusReversed,
			7*time.Minute,
		)
		first, err := fixture.ingest(t, callback, fixture.now.Add(8*time.Minute))
		if !errors.Is(err, ErrCanonicalPending) ||
			first.Payment.Status != StatusFinal ||
			first.Disposition != "QUARANTINED" ||
			len(fixture.accounting.transitions) != 2 ||
			len(fixture.orchestrator.Quarantines()) != 1 {
			t.Fatalf("submitted guard failed: %#v %v", first, err)
		}
		replay, err := fixture.ingest(t, callback, fixture.now.Add(9*time.Minute))
		if !errors.Is(err, ErrCanonicalPending) || !replay.Replayed ||
			len(fixture.orchestrator.Quarantines()) != 1 {
			t.Fatalf("guarded replay duplicated evidence: %#v %v", replay, err)
		}
		quarantine := fixture.orchestrator.Quarantines()[0]
		if _, err := fixture.orchestrator.ResolveQuarantine(
			quarantine.QuarantineID,
			"generic-resolution",
			"generic-evidence",
			"payment-operator",
			fixture.now.Add(10*time.Minute),
		); !errors.Is(err, ErrInvalidResolution) {
			t.Fatalf("generic resolution bypassed canonical proof: %v", err)
		}
		request := CanonicalReversalResolutionRequest{
			QuarantineID:           quarantine.QuarantineID,
			ResolutionID:           "canonical-resolution-001",
			PaymentID:              claim.PaymentID,
			AllocationID:           claim.AllocationID,
			InstructionDigest:      claim.Digest,
			ResolutionEvidenceHash: "resolution-evidence-hash",
			ResolvedBy:             "payment-operator",
			ResolvedAt:             fixture.now.Add(10 * time.Minute),
		}
		fixture.accounting.failures = 1
		if _, _, err := fixture.orchestrator.ResolveCanonicalReversal(request); !errors.Is(err, ErrAccounting) {
			t.Fatalf("expected accounting failure, got %v", err)
		}
		retained, exists := modes.Lookup(claim.PaymentID)
		current, _ := fixture.orchestrator.Payment(claim.PaymentID)
		if !exists || retained.State != allocationmode.CanonicalQuarantined ||
			current.Status != StatusFinal || modes.IsReversed(claim.PaymentID) ||
			len(fixture.accounting.transitions) != 2 {
			t.Fatalf(
				"failed resolution released claim or changed economics: %#v %#v",
				retained,
				current,
			)
		}
		result, resolution, err := fixture.orchestrator.ResolveCanonicalReversal(request)
		if err != nil {
			t.Fatalf("resolve canonical reversal: %v", err)
		}
		if result.Payment.Status != StatusReversed ||
			result.Disposition != "REVERSED" ||
			len(result.JournalIDs) != 1 ||
			resolution.CanonicalFailureEvidenceHash != callback.EvidenceHash ||
			len(fixture.accounting.transitions) != 3 ||
			!modes.IsReversed(claim.PaymentID) {
			t.Fatalf("canonical reversal resolution lost effects: %#v %#v", result, resolution)
		}
		retained, exists = modes.Lookup(claim.PaymentID)
		if !exists || retained.State != allocationmode.CanonicalFailed {
			t.Fatalf("resolved canonical claim was not retained as failed: %#v", retained)
		}
		if _, _, err := claimModeForPaymentTest(modes,
			claim.PaymentID,
			claim.AllocationID,
			allocationmode.ModeSyntheticProjection,
			"stale-provider-evidence",
		); !errors.Is(err, allocationmode.ErrClaimConflict) {
			t.Fatalf("reversed payment accepted a new allocation: %v", err)
		}
		replayed, err := fixture.ingest(t, callback, fixture.now.Add(11*time.Minute))
		if err != nil || !replayed.Replayed ||
			replayed.Payment.Status != StatusReversed ||
			replayed.Disposition != "REVERSED" ||
			len(fixture.orchestrator.Quarantines()) != 1 {
			t.Fatalf("resolved callback replay was not stable: %#v %v", replayed, err)
		}
	})

	t.Run("confirmed contradiction becomes incident only", func(t *testing.T) {
		modes := allocationmode.NewInMemory()
		fixture := newFixtureWithModes(t, true, modes)
		finalizeFixturePayment(t, fixture)
		claim, _, err := claimModeForPaymentTest(modes,
			"payment-001",
			"allocation-canonical",
			allocationmode.ModeCanonicalGateway,
			"digest-canonical",
		)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := modes.TransitionWithCommit(
			claim.PaymentID,
			claim.AllocationID,
			claim.Digest,
			allocationmode.CanonicalPrepared,
			allocationmode.CanonicalSubmitted,
			func(allocationmode.Claim) error { return nil },
		); err != nil {
			t.Fatal(err)
		}
		if _, err := modes.TransitionWithCommit(
			claim.PaymentID,
			claim.AllocationID,
			claim.Digest,
			allocationmode.CanonicalSubmitted,
			allocationmode.CanonicalConfirmed,
			func(allocationmode.Claim) error { return nil },
		); err != nil {
			t.Fatal(err)
		}
		result, err := fixture.ingest(
			t,
			fixture.callback("event-reversal-confirmed", StatusReversed, 7*time.Minute),
			fixture.now.Add(8*time.Minute),
		)
		if !errors.Is(err, ErrCanonicalConfirmed) ||
			result.Payment.Status != StatusFinal ||
			result.Disposition != "INCIDENT" ||
			len(fixture.accounting.transitions) != 2 ||
			len(fixture.orchestrator.CanonicalIncidents()) != 1 {
			t.Fatalf("confirmed contradiction changed economics: %#v %v", result, err)
		}
	})
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
