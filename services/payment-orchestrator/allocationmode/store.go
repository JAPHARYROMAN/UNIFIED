package allocationmode

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"sync"
)

var (
	ErrInvalidStore  = errors.New("invalid allocation mode store")
	ErrStoreConflict = errors.New("allocation mode store conflict")
)

// Store is the durable authority for the immutable payment/allocation mode
// claim. Coordinator state transitions remain owned by the Phase 7C saga store.
type Store interface {
	ClaimSynthetic(claim Claim) (bool, error)
	ClaimCanonical(claim Claim, commit func() error) error
	LoadClaims() ([]Claim, error)
}

type MemoryStore struct {
	mu     sync.Mutex
	claims map[string]Claim
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{claims: make(map[string]Claim)}
}

func (store *MemoryStore) ClaimSynthetic(claim Claim) (bool, error) {
	if store == nil || !validDurableClaim(claim) ||
		claim.Mode != ModeSyntheticProjection {
		return false, ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if existing, exists := store.claims[claim.PaymentID]; exists {
		if existing == claim {
			return true, nil
		}
		return false, ErrStoreConflict
	}
	for _, existing := range store.claims {
		if existing.AllocationID == claim.AllocationID {
			return false, ErrStoreConflict
		}
	}
	store.claims[claim.PaymentID] = claim
	return false, nil
}

func (store *MemoryStore) ClaimCanonical(
	claim Claim,
	commit func() error,
) error {
	if store == nil || !validDurableClaim(claim) ||
		claim.Mode != ModeCanonicalGateway ||
		claim.State != CanonicalPrepared || commit == nil {
		return ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if existing, exists := store.claims[claim.PaymentID]; exists {
		if sameDurableClaim(existing, claim) {
			return commit()
		}
		return ErrStoreConflict
	}
	for _, existing := range store.claims {
		if existing.AllocationID == claim.AllocationID {
			return ErrStoreConflict
		}
	}
	if err := commit(); err != nil {
		return err
	}
	store.claims[claim.PaymentID] = claim
	return nil
}

func (store *MemoryStore) LoadClaims() ([]Claim, error) {
	if store == nil {
		return nil, ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	result := make([]Claim, 0, len(store.claims))
	for _, claim := range store.claims {
		result = append(result, claim)
	}
	slices.SortFunc(result, func(left, right Claim) int {
		switch {
		case left.PaymentID < right.PaymentID:
			return -1
		case left.PaymentID > right.PaymentID:
			return 1
		default:
			return 0
		}
	})
	return result, nil
}

type SQLStore struct {
	db *sql.DB
}

func NewSQLStore(db *sql.DB) (*SQLStore, error) {
	if db == nil {
		return nil, ErrInvalidStore
	}
	return &SQLStore{db: db}, nil
}

const claimSyntheticSQL = `
SELECT claim_synthetic_payment_allocation($1, $2, $3, $4, $5, $6, $7)`

func (store *SQLStore) ClaimSynthetic(claim Claim) (bool, error) {
	if store == nil || store.db == nil || !validDurableClaim(claim) ||
		claim.Mode != ModeSyntheticProjection {
		return false, ErrInvalidStore
	}
	var status string
	err := store.db.QueryRowContext(
		context.Background(),
		claimSyntheticSQL,
		claim.ClaimID,
		claim.PaymentID,
		claim.AllocationID,
		claim.ExpectedVersion,
		claim.Digest,
		claim.EvidenceHash,
		claim.ClaimedAt.UTC(),
	).Scan(&status)
	if err != nil {
		return false, fmt.Errorf("claim synthetic payment allocation: %w", err)
	}
	switch status {
	case "CREATED":
		return false, nil
	case "REPLAYED":
		return true, nil
	default:
		return false, ErrStoreConflict
	}
}

const observeCanonicalSQL = `
SELECT EXISTS (
    SELECT 1
    FROM payment_allocation_mode_claim
    WHERE claim_id = $1
      AND payment_id = $2
      AND allocation_id = $3
      AND allocation_mode = 'CANONICAL_GATEWAY'
      AND expected_version = $4
      AND claimed_version = $4 + 1
      AND instruction_digest = $5
      AND claim_digest = $5
      AND evidence_hash = $6
      AND claimed_at = $7
)`

func (store *SQLStore) ClaimCanonical(
	claim Claim,
	commit func() error,
) error {
	if store == nil || store.db == nil || !validDurableClaim(claim) ||
		claim.Mode != ModeCanonicalGateway ||
		claim.State != CanonicalPrepared || commit == nil {
		return ErrInvalidStore
	}
	if err := commit(); err != nil {
		return err
	}
	var exists bool
	err := store.db.QueryRowContext(
		context.Background(),
		observeCanonicalSQL,
		claim.ClaimID,
		claim.PaymentID,
		claim.AllocationID,
		claim.ExpectedVersion,
		claim.Digest,
		claim.EvidenceHash,
		claim.ClaimedAt.UTC(),
	).Scan(&exists)
	if err != nil {
		return fmt.Errorf("observe canonical payment allocation claim: %w", err)
	}
	if !exists {
		return ErrStoreConflict
	}
	return nil
}

const loadClaimsSQL = `
SELECT
    claim_id,
    payment_id,
    allocation_id,
    allocation_mode,
    expected_version,
    instruction_digest,
    claim_digest,
    evidence_hash,
    claimed_at
FROM payment_allocation_mode_claim
ORDER BY payment_id`

func (store *SQLStore) LoadClaims() ([]Claim, error) {
	if store == nil || store.db == nil {
		return nil, ErrInvalidStore
	}
	rows, err := store.db.QueryContext(context.Background(), loadClaimsSQL)
	if err != nil {
		return nil, fmt.Errorf("load allocation mode claims: %w", err)
	}
	defer rows.Close()
	var result []Claim
	for rows.Next() {
		var claim Claim
		var mode string
		var instructionDigest sql.NullString
		var claimDigest string
		if err := rows.Scan(
			&claim.ClaimID,
			&claim.PaymentID,
			&claim.AllocationID,
			&mode,
			&claim.ExpectedVersion,
			&instructionDigest,
			&claimDigest,
			&claim.EvidenceHash,
			&claim.ClaimedAt,
		); err != nil {
			return nil, fmt.Errorf("scan allocation mode claim: %w", err)
		}
		claim.Mode = Mode(mode)
		claim.Digest = claimDigest
		if claim.Mode == ModeCanonicalGateway {
			if claim.Digest != instructionDigest.String {
				return nil, ErrInvalidStore
			}
			claim.State = CanonicalPrepared
		}
		claim.ClaimedAt = claim.ClaimedAt.UTC()
		if !validDurableClaim(claim) {
			return nil, ErrInvalidStore
		}
		result = append(result, claim)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate allocation mode claims: %w", err)
	}
	return result, nil
}

func validDurableClaim(claim Claim) bool {
	if claim.ClaimID == "" || claim.PaymentID == "" ||
		claim.AllocationID == "" || claim.Digest == "" ||
		claim.EvidenceHash == "" || claim.ClaimedAt.IsZero() {
		return false
	}
	switch claim.Mode {
	case ModeSyntheticProjection:
		return claim.ClaimID == "phase7b:"+claim.AllocationID &&
			claim.State == ""
	case ModeCanonicalGateway:
		return claim.ClaimID == "phase7c:"+claim.AllocationID &&
			claim.State == CanonicalPrepared
	default:
		return false
	}
}

func sameDurableClaim(left Claim, right Claim) bool {
	left.State = CanonicalPrepared
	right.State = CanonicalPrepared
	return left == right
}
