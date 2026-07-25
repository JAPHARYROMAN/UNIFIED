// Package allocationmode owns the shared, in-memory payment allocation latch.
// A payment can be claimed by either the synthetic Phase 7B allocator or the
// canonical Phase 7C gateway coordinator, never both.
package allocationmode

import (
	"errors"
	"sync"
	"time"
)

var (
	ErrInvalidClaim      = errors.New("invalid allocation mode claim")
	ErrClaimConflict     = errors.New("allocation mode claim conflict")
	ErrInvalidTransition = errors.New("invalid canonical allocation transition")
	ErrResolutionFailed  = errors.New("canonical reversal resolution failed")
)

type Mode string

const (
	ModeSyntheticProjection Mode = "SYNTHETIC_PROJECTION"
	ModeCanonicalGateway    Mode = "CANONICAL_GATEWAY"
)

type CanonicalState string

const (
	CanonicalPrepared    CanonicalState = "PREPARED"
	CanonicalSubmitted   CanonicalState = "SUBMITTED"
	CanonicalConfirmed   CanonicalState = "CONFIRMED"
	CanonicalFailed      CanonicalState = "FAILED"
	CanonicalQuarantined CanonicalState = "QUARANTINED"
	CanonicalIncident    CanonicalState = "INCIDENT"
)

type Claim struct {
	ClaimID         string
	PaymentID       string
	AllocationID    string
	Mode            Mode
	Digest          string
	State           CanonicalState
	ExpectedVersion uint64
	EvidenceHash    string
	ClaimedAt       time.Time
}

type ReversalDisposition string

const (
	ReversalUnclaimed   ReversalDisposition = "UNCLAIMED"
	ReversalSynthetic   ReversalDisposition = "SYNTHETIC"
	ReversalReleased    ReversalDisposition = "RELEASED"
	ReversalQuarantined ReversalDisposition = "QUARANTINED"
	ReversalIncident    ReversalDisposition = "INCIDENT"
)

type Registry struct {
	mu           sync.RWMutex
	byPayment    map[string]Claim
	byAllocation map[string]string
	reversed     map[string]bool
	store        Store
}

func New(store Store) (*Registry, error) {
	if store == nil {
		return nil, ErrInvalidStore
	}
	registry := &Registry{
		byPayment:    make(map[string]Claim),
		byAllocation: make(map[string]string),
		reversed:     make(map[string]bool),
		store:        store,
	}
	claims, err := store.LoadClaims()
	if err != nil {
		return nil, err
	}
	for _, claim := range claims {
		if !validDurableClaim(claim) {
			return nil, ErrInvalidStore
		}
		if _, exists := registry.byPayment[claim.PaymentID]; exists {
			return nil, ErrStoreConflict
		}
		if _, exists := registry.byAllocation[claim.AllocationID]; exists {
			return nil, ErrStoreConflict
		}
		registry.byPayment[claim.PaymentID] = claim
		registry.byAllocation[claim.AllocationID] = claim.PaymentID
	}
	return registry, nil
}

// NewInMemory is an explicit test/local-development constructor.
func NewInMemory() *Registry {
	registry, err := New(NewMemoryStore())
	if err != nil {
		panic(err)
	}
	return registry
}

// ClaimMode atomically claims both payment and allocation identities. An exact
// replay returns the existing claim; any change of mode or digest conflicts.
func (registry *Registry) ClaimMode(
	paymentID string,
	allocationID string,
	mode Mode,
	digest string,
	expectedVersion uint64,
	evidenceHash string,
	claimedAt time.Time,
) (Claim, bool, error) {
	if registry == nil || paymentID == "" || allocationID == "" || digest == "" ||
		evidenceHash == "" || claimedAt.IsZero() ||
		mode != ModeSyntheticProjection {
		return Claim{}, false, ErrInvalidClaim
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	if registry.reversed[paymentID] {
		return Claim{}, false, ErrClaimConflict
	}
	if existing, ok := registry.byPayment[paymentID]; ok {
		if sameClaim(existing, paymentID, allocationID, mode, digest) &&
			existing.ExpectedVersion == expectedVersion &&
			existing.EvidenceHash == evidenceHash &&
			existing.ClaimedAt.Equal(claimedAt.UTC()) {
			return existing, true, nil
		}
		return Claim{}, false, ErrClaimConflict
	}
	if owner, ok := registry.byAllocation[allocationID]; ok && owner != paymentID {
		return Claim{}, false, ErrClaimConflict
	}
	record := Claim{
		ClaimID:         "phase7b:" + allocationID,
		PaymentID:       paymentID,
		AllocationID:    allocationID,
		Mode:            mode,
		Digest:          digest,
		ExpectedVersion: expectedVersion,
		EvidenceHash:    evidenceHash,
		ClaimedAt:       claimedAt.UTC(),
	}
	replayed, err := registry.store.ClaimSynthetic(record)
	if err != nil {
		return Claim{}, false, errors.Join(ErrClaimConflict, err)
	}
	registry.byPayment[paymentID] = record
	registry.byAllocation[allocationID] = paymentID
	return record, replayed, nil
}

// ClaimModeWithCommit publishes a new claim only after commit succeeds while
// holding the allocation latch. This lets a durable coordinator persist
// PREPARED before any concurrent path can observe the claim.
func (registry *Registry) ClaimModeWithCommit(
	paymentID string,
	allocationID string,
	mode Mode,
	digest string,
	expectedVersion uint64,
	evidenceHash string,
	claimedAt time.Time,
	commit func(Claim) error,
) (Claim, error) {
	if registry == nil || commit == nil || paymentID == "" ||
		allocationID == "" || digest == "" || evidenceHash == "" ||
		claimedAt.IsZero() || mode != ModeCanonicalGateway {
		return Claim{}, ErrInvalidClaim
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	if registry.reversed[paymentID] {
		return Claim{}, ErrClaimConflict
	}
	if _, exists := registry.byPayment[paymentID]; exists {
		return Claim{}, ErrClaimConflict
	}
	if _, exists := registry.byAllocation[allocationID]; exists {
		return Claim{}, ErrClaimConflict
	}
	record := Claim{
		ClaimID:         "phase7c:" + allocationID,
		PaymentID:       paymentID,
		AllocationID:    allocationID,
		Mode:            mode,
		Digest:          digest,
		State:           CanonicalPrepared,
		ExpectedVersion: expectedVersion,
		EvidenceHash:    evidenceHash,
		ClaimedAt:       claimedAt.UTC(),
	}
	if err := registry.store.ClaimCanonical(
		record,
		func() error { return commit(record) },
	); err != nil {
		return Claim{}, err
	}
	registry.byPayment[paymentID] = record
	registry.byAllocation[allocationID] = paymentID
	return record, nil
}

// Release is retained only to reject legacy callers. Allocation claims are
// immutable once durable; failed downstream work must resume the exact claim.
func (registry *Registry) Release(claim Claim) error {
	return ErrInvalidTransition
}

func (registry *Registry) Lookup(paymentID string) (Claim, bool) {
	if registry == nil {
		return Claim{}, false
	}
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	record, ok := registry.byPayment[paymentID]
	return record, ok
}

// TransitionWithCommit performs the durable compare-and-swap before publishing
// the next in-memory state, under the same allocation-latch critical section.
func (registry *Registry) TransitionWithCommit(
	paymentID string,
	allocationID string,
	digest string,
	expected CanonicalState,
	next CanonicalState,
	commit func(Claim) error,
) (Claim, error) {
	if registry == nil || commit == nil ||
		!validCanonicalState(expected) || !validCanonicalState(next) {
		return Claim{}, ErrInvalidTransition
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	record, ok := registry.byPayment[paymentID]
	if !ok || record.Mode != ModeCanonicalGateway ||
		record.AllocationID != allocationID || record.Digest != digest ||
		record.State != expected || !allowedCanonicalTransition(expected, next) {
		return Claim{}, ErrInvalidTransition
	}
	record.State = next
	if err := commit(record); err != nil {
		return Claim{}, err
	}
	registry.byPayment[paymentID] = record
	return record, nil
}

// HandleReversalWithCommit persists the exact disposition before publishing the
// latch transition. The callback receives whether a permanent tombstone will be
// created by the transition.
func (registry *Registry) HandleReversalWithCommit(
	paymentID string,
	commit func(Claim, ReversalDisposition, bool) error,
) (Claim, ReversalDisposition, error) {
	if registry == nil || paymentID == "" {
		return Claim{}, ReversalUnclaimed, ErrInvalidClaim
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	record, ok := registry.byPayment[paymentID]
	if !ok {
		if commit == nil {
			return Claim{}, ReversalUnclaimed, ErrResolutionFailed
		}
		if err := commit(
			Claim{PaymentID: paymentID},
			ReversalUnclaimed,
			true,
		); err != nil {
			return Claim{}, ReversalUnclaimed,
				errors.Join(ErrResolutionFailed, err)
		}
		registry.reversed[paymentID] = true
		return Claim{}, ReversalUnclaimed, nil
	}
	if record.Mode == ModeSyntheticProjection {
		if commit == nil {
			return Claim{}, ReversalSynthetic, ErrResolutionFailed
		}
		if err := commit(record, ReversalSynthetic, true); err != nil {
			return Claim{}, ReversalSynthetic,
				errors.Join(ErrResolutionFailed, err)
		}
		registry.reversed[paymentID] = true
		return record, ReversalSynthetic, nil
	}
	switch record.State {
	case CanonicalPrepared, CanonicalFailed:
		if commit == nil {
			return Claim{}, ReversalQuarantined, ErrResolutionFailed
		}
		if err := commit(record, ReversalQuarantined, false); err != nil {
			return Claim{}, ReversalQuarantined,
				errors.Join(ErrResolutionFailed, err)
		}
		record.State = CanonicalQuarantined
		registry.byPayment[paymentID] = record
		return record, ReversalQuarantined, nil
	case CanonicalSubmitted:
		if commit == nil {
			return Claim{}, ReversalQuarantined, ErrResolutionFailed
		}
		if err := commit(record, ReversalQuarantined, false); err != nil {
			return Claim{}, ReversalQuarantined,
				errors.Join(ErrResolutionFailed, err)
		}
		record.State = CanonicalQuarantined
		registry.byPayment[paymentID] = record
		return record, ReversalQuarantined, nil
	case CanonicalQuarantined:
		return record, ReversalQuarantined, nil
	case CanonicalConfirmed:
		if commit == nil {
			return Claim{}, ReversalIncident, ErrResolutionFailed
		}
		if err := commit(record, ReversalIncident, false); err != nil {
			return Claim{}, ReversalIncident,
				errors.Join(ErrResolutionFailed, err)
		}
		record.State = CanonicalIncident
		registry.byPayment[paymentID] = record
		return record, ReversalIncident, nil
	case CanonicalIncident:
		return record, ReversalIncident, nil
	default:
		return record, ReversalQuarantined, nil
	}
}

func (registry *Registry) IsReversed(paymentID string) bool {
	if registry == nil {
		return false
	}
	registry.mu.RLock()
	defer registry.mu.RUnlock()
	return registry.reversed[paymentID]
}

// ResolveQuarantinedReversal serializes the Phase 7A reversal commit with the
// permanent failure of the submitted canonical claim and creation of the
// reversal tombstone. If commit fails, the claim remains quarantined.
func (registry *Registry) ResolveQuarantinedReversal(
	claim Claim,
	commit func() error,
) error {
	if registry == nil || commit == nil {
		return ErrInvalidClaim
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	existing, ok := registry.byPayment[claim.PaymentID]
	if !ok || !sameClaim(
		existing,
		claim.PaymentID,
		claim.AllocationID,
		claim.Mode,
		claim.Digest,
	) || existing.Mode != ModeCanonicalGateway ||
		existing.State != CanonicalQuarantined {
		return ErrInvalidTransition
	}
	if err := commit(); err != nil {
		return errors.Join(ErrResolutionFailed, err)
	}
	existing.State = CanonicalFailed
	registry.byPayment[existing.PaymentID] = existing
	registry.reversed[existing.PaymentID] = true
	return nil
}

// Restore rehydrates one authoritative durable claim. It is idempotent for an
// exact record and rejects every conflicting payment or allocation owner.
func (registry *Registry) Restore(claim Claim, tombstoned bool) error {
	if registry == nil || claim.PaymentID == "" || claim.AllocationID == "" ||
		claim.Digest == "" ||
		(claim.Mode != ModeSyntheticProjection &&
			claim.Mode != ModeCanonicalGateway) ||
		(claim.Mode == ModeCanonicalGateway && !validCanonicalState(claim.State)) {
		return ErrInvalidClaim
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	if existing, exists := registry.byPayment[claim.PaymentID]; exists {
		if !sameDurableClaim(existing, claim) ||
			(registry.reversed[claim.PaymentID] && !tombstoned) {
			return ErrClaimConflict
		}
		existing.State = claim.State
		registry.byPayment[claim.PaymentID] = existing
		if tombstoned {
			registry.reversed[claim.PaymentID] = true
		}
		return nil
	}
	if owner, exists := registry.byAllocation[claim.AllocationID]; exists &&
		owner != claim.PaymentID {
		return ErrClaimConflict
	}
	registry.byPayment[claim.PaymentID] = claim
	registry.byAllocation[claim.AllocationID] = claim.PaymentID
	if tombstoned {
		registry.reversed[claim.PaymentID] = true
	}
	return nil
}

// RestoreTombstone rehydrates a durable reversal prohibition that may not have
// a coordinator-owned claim (for example, a reversal observed before prepare).
func (registry *Registry) RestoreTombstone(paymentID string) error {
	if registry == nil || paymentID == "" {
		return ErrInvalidClaim
	}
	registry.mu.Lock()
	defer registry.mu.Unlock()
	registry.reversed[paymentID] = true
	return nil
}

func sameClaim(
	record Claim,
	paymentID string,
	allocationID string,
	mode Mode,
	digest string,
) bool {
	return record.PaymentID == paymentID &&
		record.AllocationID == allocationID &&
		record.Mode == mode &&
		record.Digest == digest
}

func validCanonicalState(state CanonicalState) bool {
	switch state {
	case CanonicalPrepared, CanonicalSubmitted, CanonicalConfirmed, CanonicalFailed,
		CanonicalQuarantined, CanonicalIncident:
		return true
	default:
		return false
	}
}

func allowedCanonicalTransition(from CanonicalState, to CanonicalState) bool {
	switch from {
	case CanonicalPrepared:
		return to == CanonicalSubmitted || to == CanonicalFailed ||
			to == CanonicalQuarantined
	case CanonicalSubmitted:
		return to == CanonicalConfirmed || to == CanonicalFailed ||
			to == CanonicalQuarantined
	case CanonicalQuarantined:
		return to == CanonicalIncident || to == CanonicalFailed
	case CanonicalConfirmed:
		return to == CanonicalIncident
	case CanonicalFailed:
		return to == CanonicalPrepared || to == CanonicalQuarantined
	default:
		return false
	}
}
