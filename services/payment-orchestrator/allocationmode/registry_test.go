package allocationmode

import (
	"errors"
	"testing"
	"time"
)

func claimForTest(
	registry *Registry,
	paymentID string,
	allocationID string,
	mode Mode,
	digest string,
) (Claim, bool, error) {
	claimedAt := time.Unix(1_770_000_000, 0).UTC()
	if mode == ModeCanonicalGateway {
		claim, err := registry.ClaimModeWithCommit(
			paymentID,
			allocationID,
			mode,
			digest,
			4,
			"canonical-evidence:"+digest,
			claimedAt,
			func(Claim) error { return nil },
		)
		return claim, false, err
	}
	return registry.ClaimMode(
		paymentID,
		allocationID,
		mode,
		digest,
		4,
		digest,
		claimedAt,
	)
}

func transitionForTest(
	registry *Registry,
	claim Claim,
	expected CanonicalState,
	next CanonicalState,
) (Claim, error) {
	return registry.TransitionWithCommit(
		claim.PaymentID,
		claim.AllocationID,
		claim.Digest,
		expected,
		next,
		func(Claim) error { return nil },
	)
}

func handleReversalForTest(
	registry *Registry,
	paymentID string,
) (Claim, ReversalDisposition, error) {
	return registry.HandleReversalWithCommit(
		paymentID,
		func(Claim, ReversalDisposition, bool) error { return nil },
	)
}

func TestClaimReplayConflictAndPermanentRetention(t *testing.T) {
	registry := NewInMemory()
	first, replayed, err := claimForTest(registry,
		"payment-1",
		"allocation-1",
		ModeSyntheticProjection,
		"digest-1",
	)
	if err != nil || replayed {
		t.Fatalf("claim synthetic mode: replay=%v err=%v", replayed, err)
	}
	second, replayed, err := claimForTest(registry,
		"payment-1",
		"allocation-1",
		ModeSyntheticProjection,
		"digest-1",
	)
	if err != nil || !replayed || second != first {
		t.Fatalf("exact replay changed claim: %#v %#v %v", first, second, err)
	}
	if _, _, err := claimForTest(registry,
		"payment-1",
		"allocation-2",
		ModeCanonicalGateway,
		"digest-2",
	); !errors.Is(err, ErrClaimConflict) {
		t.Fatalf("expected cross-mode conflict, got %v", err)
	}
	if err := registry.Release(first); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("durable claim release was not rejected: %v", err)
	}
	if retained, exists := registry.Lookup("payment-1"); !exists || retained != first {
		t.Fatalf("durable claim was not retained: %#v", retained)
	}
}

func TestCanonicalReversalDispositionsAreAtomic(t *testing.T) {
	registry := NewInMemory()
	prepared, _, err := claimForTest(registry,
		"payment-prepared",
		"allocation-prepared",
		ModeCanonicalGateway,
		"digest-prepared",
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, disposition, err := handleReversalForTest(
		registry,
		prepared.PaymentID,
	); err != nil || disposition != ReversalQuarantined {
		t.Fatalf("prepared reversal disposition: %s", disposition)
	}
	retained, exists := registry.Lookup(prepared.PaymentID)
	if !exists || retained.State != CanonicalQuarantined {
		t.Fatalf("prepared reversal did not retain a blocking claim: %#v", retained)
	}
	if _, _, err := claimForTest(registry,
		prepared.PaymentID,
		prepared.AllocationID,
		ModeSyntheticProjection,
		"stale-final-evidence",
	); !errors.Is(err, ErrClaimConflict) {
		t.Fatalf("reversed payment accepted a stale allocation claim: %v", err)
	}

	submitted, _, err := claimForTest(registry,
		"payment-submitted",
		"allocation-submitted",
		ModeCanonicalGateway,
		"digest-submitted",
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := transitionForTest(
		registry,
		submitted,
		CanonicalPrepared,
		CanonicalSubmitted,
	); err != nil {
		t.Fatal(err)
	}
	if claim, disposition, err := handleReversalForTest(
		registry,
		submitted.PaymentID,
	); err != nil || disposition != ReversalQuarantined ||
		claim.State != CanonicalQuarantined {
		t.Fatalf("submitted reversal was not quarantined: %#v %s", claim, disposition)
	}

	confirmed, _, err := claimForTest(registry,
		"payment-confirmed",
		"allocation-confirmed",
		ModeCanonicalGateway,
		"digest-confirmed",
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := transitionForTest(
		registry,
		confirmed,
		CanonicalPrepared,
		CanonicalSubmitted,
	); err != nil {
		t.Fatal(err)
	}
	confirmed, err = transitionForTest(
		registry,
		confirmed,
		CanonicalSubmitted,
		CanonicalConfirmed,
	)
	if err != nil {
		t.Fatal(err)
	}
	if claim, disposition, err := handleReversalForTest(
		registry,
		confirmed.PaymentID,
	); err != nil || disposition != ReversalIncident ||
		claim.State != CanonicalIncident {
		t.Fatalf("confirmed reversal was not an incident: %#v %s", claim, disposition)
	}
}

func TestResolveQuarantinedReversalRetainsClaimUntilCommit(t *testing.T) {
	registry := NewInMemory()
	claim, _, err := claimForTest(registry,
		"payment-submitted",
		"allocation-submitted",
		ModeCanonicalGateway,
		"digest-submitted",
	)
	if err != nil {
		t.Fatal(err)
	}
	claim, err = transitionForTest(
		registry,
		claim,
		CanonicalPrepared,
		CanonicalSubmitted,
	)
	if err != nil {
		t.Fatal(err)
	}
	quarantined, disposition, err := handleReversalForTest(
		registry,
		claim.PaymentID,
	)
	if err != nil || disposition != ReversalQuarantined {
		t.Fatalf("submitted reversal disposition: %s", disposition)
	}
	commitFailure := errors.New("accounting unavailable")
	if err := registry.ResolveQuarantinedReversal(
		quarantined,
		func() error { return commitFailure },
	); !errors.Is(err, ErrResolutionFailed) || !errors.Is(err, commitFailure) {
		t.Fatalf("expected retained commit failure, got %v", err)
	}
	retained, exists := registry.Lookup(claim.PaymentID)
	if !exists || retained.State != CanonicalQuarantined ||
		registry.IsReversed(claim.PaymentID) {
		t.Fatalf("failed commit released the canonical claim: %#v", retained)
	}
	committed := false
	if err := registry.ResolveQuarantinedReversal(
		quarantined,
		func() error {
			committed = true
			return nil
		},
	); err != nil {
		t.Fatalf("resolve quarantined reversal: %v", err)
	}
	if !committed || !registry.IsReversed(claim.PaymentID) {
		t.Fatal("successful reversal did not create a permanent tombstone")
	}
	retained, exists = registry.Lookup(claim.PaymentID)
	if !exists || retained.State != CanonicalFailed {
		t.Fatalf("successful reversal did not retain the permanent failed claim: %#v", retained)
	}
}
