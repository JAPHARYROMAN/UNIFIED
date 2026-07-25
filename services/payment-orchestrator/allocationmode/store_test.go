package allocationmode

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestRegistryRestoresDurableSyntheticClaim(t *testing.T) {
	store := NewMemoryStore()
	first, err := New(store)
	if err != nil {
		t.Fatal(err)
	}
	claimedAt := time.Unix(1_771_000_000, 0).UTC()
	expected, replayed, err := first.ClaimMode(
		"payment-restart",
		"allocation-restart",
		ModeSyntheticProjection,
		"synthetic-evidence",
		4,
		"synthetic-evidence",
		claimedAt,
	)
	if err != nil || replayed {
		t.Fatalf("create synthetic claim: %#v %v", expected, err)
	}
	restarted, err := New(store)
	if err != nil {
		t.Fatal(err)
	}
	actual, exists := restarted.Lookup(expected.PaymentID)
	if !exists || actual != expected {
		t.Fatalf("restart lost durable claim: %#v", actual)
	}
}

func TestCrossRegistrySyntheticReplayRequiresExactDigest(t *testing.T) {
	store := NewMemoryStore()
	first, _ := New(store)
	second, _ := New(store)
	claimedAt := time.Unix(1_771_050_000, 0).UTC()
	if _, replayed, err := first.ClaimMode(
		"payment-content",
		"allocation-content",
		ModeSyntheticProjection,
		"digest-original",
		4,
		"shared-evidence",
		claimedAt,
	); err != nil || replayed {
		t.Fatalf("create original claim: replay=%v err=%v", replayed, err)
	}
	if _, _, err := second.ClaimMode(
		"payment-content",
		"allocation-content",
		ModeSyntheticProjection,
		"digest-altered",
		4,
		"shared-evidence",
		claimedAt,
	); !errors.Is(err, ErrClaimConflict) {
		t.Fatalf("cross-registry altered digest replay was accepted: %v", err)
	}
}

func TestTwoStaleRegistriesDistinguishCreateFromExactReplay(t *testing.T) {
	store := NewMemoryStore()
	first, _ := New(store)
	second, _ := New(store)
	claimedAt := time.Unix(1_771_100_000, 0).UTC()
	type result struct {
		replayed bool
		err      error
	}
	start := make(chan struct{})
	results := make(chan result, 2)
	claim := func(registry *Registry) {
		<-start
		_, replayed, err := registry.ClaimMode(
			"payment-concurrent-replay",
			"allocation-concurrent-replay",
			ModeSyntheticProjection,
			"concurrent-evidence",
			4,
			"concurrent-evidence",
			claimedAt,
		)
		results <- result{replayed: replayed, err: err}
	}
	go claim(first)
	go claim(second)
	close(start)
	left := <-results
	right := <-results
	if left.err != nil || right.err != nil ||
		left.replayed == right.replayed {
		t.Fatalf("create/replay distinction lost: %#v %#v", left, right)
	}
}

func TestConcurrentConflictingModesHaveOneDurableWinner(t *testing.T) {
	store := NewMemoryStore()
	syntheticRegistry, _ := New(store)
	canonicalRegistry, _ := New(store)
	claimedAt := time.Unix(1_771_200_000, 0).UTC()
	start := make(chan struct{})
	var canonicalCommitCalls atomic.Int32
	var wait sync.WaitGroup
	wait.Add(2)
	errorsByMode := make(chan error, 2)
	go func() {
		defer wait.Done()
		<-start
		_, _, err := syntheticRegistry.ClaimMode(
			"payment-mode-race",
			"allocation-synthetic",
			ModeSyntheticProjection,
			"synthetic-race-evidence",
			4,
			"synthetic-race-evidence",
			claimedAt,
		)
		errorsByMode <- err
	}()
	go func() {
		defer wait.Done()
		<-start
		_, err := canonicalRegistry.ClaimModeWithCommit(
			"payment-mode-race",
			"allocation-canonical",
			ModeCanonicalGateway,
			"canonical-instruction",
			4,
			"canonical-race-evidence",
			claimedAt,
			func(Claim) error {
				canonicalCommitCalls.Add(1)
				return nil
			},
		)
		errorsByMode <- err
	}()
	close(start)
	wait.Wait()
	close(errorsByMode)
	successes := 0
	conflicts := 0
	for err := range errorsByMode {
		switch {
		case err == nil:
			successes++
		case errors.Is(err, ErrClaimConflict),
			errors.Is(err, ErrStoreConflict):
			conflicts++
		default:
			t.Fatalf("unexpected race error: %v", err)
		}
	}
	if successes != 1 || conflicts != 1 {
		t.Fatalf("mode race did not select one winner: success=%d conflict=%d",
			successes, conflicts)
	}
	claims, err := store.LoadClaims()
	if err != nil || len(claims) != 1 {
		t.Fatalf("durable winner missing: %#v %v", claims, err)
	}
	if claims[0].Mode == ModeCanonicalGateway &&
		canonicalCommitCalls.Load() != 1 {
		t.Fatal("canonical winner did not commit its saga")
	}
	if claims[0].Mode == ModeSyntheticProjection &&
		canonicalCommitCalls.Load() != 0 {
		t.Fatal("losing canonical mode committed before durable arbitration")
	}
}

func TestConcurrentConflictingSyntheticClaimsHaveOneWinner(t *testing.T) {
	store := NewMemoryStore()
	first, _ := New(store)
	second, _ := New(store)
	claimedAt := time.Unix(1_771_300_000, 0).UTC()
	start := make(chan struct{})
	results := make(chan error, 2)
	for index, registry := range []*Registry{first, second} {
		index := index
		registry := registry
		go func() {
			<-start
			_, _, err := registry.ClaimMode(
				"payment-conflict",
				[]string{"allocation-left", "allocation-right"}[index],
				ModeSyntheticProjection,
				[]string{"evidence-left", "evidence-right"}[index],
				4,
				[]string{"evidence-left", "evidence-right"}[index],
				claimedAt,
			)
			results <- err
		}()
	}
	close(start)
	left := <-results
	right := <-results
	if (left == nil) == (right == nil) {
		t.Fatalf("conflicting claims did not select one winner: %v %v", left, right)
	}
}
