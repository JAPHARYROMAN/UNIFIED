package settlement

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"sync"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
)

var (
	ErrStoreConflict = errors.New("canonical coordinator store compare-and-swap conflict")
	ErrInvalidStore  = errors.New("invalid canonical coordinator store")
)

// PendingReversalSnapshot is the durable, non-sensitive metadata needed to keep
// a prepared, failed, or submitted canonical operation quarantined across
// process restarts.
type PendingReversalSnapshot struct {
	QuarantineID          string
	IngressID             uint64
	ProviderID            string
	ProviderEventID       string
	ProviderReference     string
	AssetID               string
	Units                 string
	RawHash               string
	SignatureHash         string
	PaymentID             string
	AllocationID          string
	InstructionDigest     string
	CallbackEvidenceHash  string
	CallbackExpiresAt     time.Time
	OccurredAt            time.Time
	ReceivedAt            time.Time
	OriginState           State
	SubmissionChainID     uint64
	SubmissionGateway     string
	SubmissionTxHash      string
	SubmissionSubmittedAt time.Time
}

// StoredTombstone is the durable allocation prohibition created only after the
// ordinary payment reversal has committed.
type StoredTombstone struct {
	PaymentID         string
	AllocationID      string
	InstructionDigest string
	QuarantineID      string
	ReversalEventID   string
	EvidenceHash      string
	OccurredAt        time.Time
}

type PendingReversalResolution struct {
	Pending             PendingReversalSnapshot
	RequestDigest       string
	ResolutionID        string
	ReversalEventID     string
	FailureEvidenceHash string
	FailureProof        chainprojection.TransactionFailureEvidence
	ResolutionEvidence  string
	ResolvedBy          string
	ResolvedAt          time.Time
}

// StoredReversalResolution retains the complete committed result so an exact
// resolution command can be answered after response loss or process restart.
type StoredReversalResolution struct {
	Resolution PendingReversalResolution
	JournalIDs []string
}

// ConsumedPendingReversalSnapshot is the durable incident produced when the
// exact submitted transaction finalizes after its provider reversal was
// quarantined. Confirmation stores the full verified economic projection;
// this record binds that projection to the consumed callback.
type ConsumedPendingReversalSnapshot struct {
	Pending                PendingReversalSnapshot
	ResolutionID           string
	ResolutionEvidenceHash string
	ResolvedBy             string
	ResolvedAt             time.Time
	GatewayEventID         string
	GatewayTransactionHash string
	GatewayRawPayloadHash  string
	FinalityEvidenceHash   string
}

// StoredCoordinator is the storage-neutral CAS envelope. Snapshot is canonical
// JSON produced and validated by the coordinator; stores treat it as opaque.
type StoredCoordinator struct {
	PaymentID                 string
	AllocationID              string
	InstructionDigest         string
	AllocationExpectedVersion uint64
	State                     State
	Version                   uint64
	Snapshot                  []byte
	Tombstoned                bool
	PendingReversal           bool
}

// Store persists one current coordinator snapshot and append-only transition
// history. CompareAndSwap must reject stale state/version writers atomically.
type Store interface {
	Create(
		record StoredCoordinator,
		evidenceHash string,
		occurredAt time.Time,
	) error
	CompareAndSwap(
		expectedState State,
		expectedVersion uint64,
		next StoredCoordinator,
		evidenceHash string,
		occurredAt time.Time,
	) error
	QuarantinePendingReversal(
		expectedState State,
		expectedVersion uint64,
		next StoredCoordinator,
		pending PendingReversalSnapshot,
	) error
	CreateTombstone(record StoredTombstone) error
	ResolvePendingReversal(
		expectedState State,
		expectedVersion uint64,
		next StoredCoordinator,
		resolution PendingReversalResolution,
		localFallback func() ([]string, error),
	) ([]string, error)
	LoadAll() ([]StoredCoordinator, error)
	LoadTombstones() ([]StoredTombstone, error)
	LoadResolvedReversals() ([]StoredReversalResolution, error)
}

type durableSnapshot struct {
	Plan                    Plan
	Confirmation            *AccountingProjection
	Reorgs                  []ReorgEvidence
	Claim                   allocationmode.Claim
	Tombstoned              bool
	PendingReversal         *PendingReversalSnapshot
	ConsumedPendingReversal *ConsumedPendingReversalSnapshot
}

type MemoryStore struct {
	mu          sync.Mutex
	records     map[string]StoredCoordinator
	tombstones  map[string]StoredTombstone
	quarantines map[string]PendingReversalSnapshot
	resolutions map[string]StoredReversalResolution
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		records:     make(map[string]StoredCoordinator),
		tombstones:  make(map[string]StoredTombstone),
		quarantines: make(map[string]PendingReversalSnapshot),
		resolutions: make(map[string]StoredReversalResolution),
	}
}

func (store *MemoryStore) Create(
	record StoredCoordinator,
	evidenceHash string,
	occurredAt time.Time,
) error {
	if store == nil || !validStoredCoordinator(record) ||
		evidenceHash == "" || occurredAt.IsZero() {
		return ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if existing, exists := store.records[record.PaymentID]; exists {
		if storedCoordinatorsEqual(existing, record) {
			return nil
		}
		return ErrStoreConflict
	}
	store.records[record.PaymentID] = cloneStoredCoordinator(record)
	return nil
}

func (store *MemoryStore) CompareAndSwap(
	expectedState State,
	expectedVersion uint64,
	next StoredCoordinator,
	evidenceHash string,
	occurredAt time.Time,
) error {
	if store == nil || !validStoredCoordinator(next) ||
		!validState(expectedState) || expectedVersion == 0 ||
		next.Version != expectedVersion+1 ||
		evidenceHash == "" || occurredAt.IsZero() {
		return ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	current, exists := store.records[next.PaymentID]
	if !exists || current.State != expectedState ||
		current.Version != expectedVersion ||
		current.AllocationID != next.AllocationID ||
		current.InstructionDigest != next.InstructionDigest ||
		current.AllocationExpectedVersion != next.AllocationExpectedVersion {
		return ErrStoreConflict
	}
	store.records[next.PaymentID] = cloneStoredCoordinator(next)
	return nil
}

func (store *MemoryStore) LoadAll() ([]StoredCoordinator, error) {
	if store == nil {
		return nil, ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	result := make([]StoredCoordinator, 0, len(store.records))
	for _, record := range store.records {
		result = append(result, cloneStoredCoordinator(record))
	}
	slices.SortFunc(result, func(left, right StoredCoordinator) int {
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

func (store *MemoryStore) CreateTombstone(record StoredTombstone) error {
	if store == nil || !validStoredTombstone(record) {
		return ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if existing, exists := store.tombstones[record.PaymentID]; exists {
		if existing == record {
			return nil
		}
		return ErrStoreConflict
	}
	store.tombstones[record.PaymentID] = record
	return nil
}

func (store *MemoryStore) QuarantinePendingReversal(
	expectedState State,
	expectedVersion uint64,
	next StoredCoordinator,
	pending PendingReversalSnapshot,
) error {
	if store == nil || !validStoredCoordinator(next) ||
		!validPendingSnapshot(pending) ||
		pending.PaymentID != next.PaymentID ||
		pending.AllocationID != next.AllocationID ||
		pending.InstructionDigest != next.InstructionDigest ||
		pending.OriginState != expectedState ||
		next.State != StateQuarantined || next.Tombstoned ||
		!next.PendingReversal || next.Version != expectedVersion+1 {
		return ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	current, exists := store.records[next.PaymentID]
	if !exists || current.State != expectedState ||
		current.Version != expectedVersion ||
		current.AllocationID != next.AllocationID ||
		current.InstructionDigest != next.InstructionDigest ||
		current.AllocationExpectedVersion != next.AllocationExpectedVersion ||
		current.Tombstoned || current.PendingReversal {
		return ErrStoreConflict
	}
	if existing, exists := store.quarantines[pending.QuarantineID]; exists &&
		existing != pending {
		return ErrStoreConflict
	}
	store.records[next.PaymentID] = cloneStoredCoordinator(next)
	store.quarantines[pending.QuarantineID] = pending
	return nil
}

func (store *MemoryStore) ResolvePendingReversal(
	expectedState State,
	expectedVersion uint64,
	next StoredCoordinator,
	resolution PendingReversalResolution,
	localFallback func() ([]string, error),
) ([]string, error) {
	if store == nil || expectedState != StateQuarantined ||
		!validStoredCoordinator(next) || next.State != StateFailed ||
		next.Version != expectedVersion+1 || !next.Tombstoned ||
		next.PendingReversal || !validPendingResolution(resolution) ||
		localFallback == nil {
		return nil, ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if stored, exists := store.resolutions[resolution.Pending.QuarantineID]; exists {
		current, currentExists := store.records[next.PaymentID]
		if !currentExists || !storedCoordinatorsEqual(current, next) ||
			stored.Resolution != resolution {
			return nil, ErrStoreConflict
		}
		return slices.Clone(stored.JournalIDs), nil
	}
	current, exists := store.records[next.PaymentID]
	if !exists || current.State != expectedState ||
		current.Version != expectedVersion || !current.PendingReversal ||
		current.Tombstoned ||
		current.AllocationID != next.AllocationID ||
		current.InstructionDigest != next.InstructionDigest ||
		current.AllocationExpectedVersion != next.AllocationExpectedVersion {
		return nil, ErrStoreConflict
	}
	pending, exists := store.quarantines[resolution.Pending.QuarantineID]
	if !exists || pending != resolution.Pending {
		return nil, ErrStoreConflict
	}
	tombstone := StoredTombstone{
		PaymentID:         next.PaymentID,
		AllocationID:      next.AllocationID,
		InstructionDigest: next.InstructionDigest,
		QuarantineID:      resolution.Pending.QuarantineID,
		ReversalEventID:   resolution.ReversalEventID,
		EvidenceHash:      resolution.ResolutionEvidence,
		OccurredAt:        resolution.ResolvedAt.UTC(),
	}
	if existing, exists := store.tombstones[next.PaymentID]; exists &&
		existing != tombstone {
		return nil, ErrStoreConflict
	}
	journalIDs, err := localFallback()
	if err != nil {
		return nil, err
	}
	if len(journalIDs) == 0 || len(journalIDs) > 2 ||
		!uniqueNonempty(journalIDs) {
		return nil, ErrInvalidStore
	}
	store.records[next.PaymentID] = cloneStoredCoordinator(next)
	store.tombstones[next.PaymentID] = tombstone
	store.resolutions[resolution.Pending.QuarantineID] = StoredReversalResolution{
		Resolution: resolution,
		JournalIDs: slices.Clone(journalIDs),
	}
	delete(store.quarantines, resolution.Pending.QuarantineID)
	return slices.Clone(journalIDs), nil
}

func (store *MemoryStore) LoadTombstones() ([]StoredTombstone, error) {
	if store == nil {
		return nil, ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	result := make([]StoredTombstone, 0, len(store.tombstones))
	for _, tombstone := range store.tombstones {
		result = append(result, tombstone)
	}
	slices.SortFunc(result, func(left, right StoredTombstone) int {
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

func (store *MemoryStore) LoadResolvedReversals() ([]StoredReversalResolution, error) {
	if store == nil {
		return nil, ErrInvalidStore
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	result := make([]StoredReversalResolution, 0, len(store.resolutions))
	for _, resolution := range store.resolutions {
		copy := resolution
		copy.JournalIDs = slices.Clone(resolution.JournalIDs)
		result = append(result, copy)
	}
	slices.SortFunc(result, func(left, right StoredReversalResolution) int {
		switch {
		case left.Resolution.Pending.QuarantineID <
			right.Resolution.Pending.QuarantineID:
			return -1
		case left.Resolution.Pending.QuarantineID >
			right.Resolution.Pending.QuarantineID:
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

const createCoordinatorSQL = `
SELECT create_canonical_coordinator_state(
    $1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10
)`

func (store *SQLStore) Create(
	record StoredCoordinator,
	evidenceHash string,
	occurredAt time.Time,
) error {
	if store == nil || store.db == nil || !validStoredCoordinator(record) ||
		evidenceHash == "" || occurredAt.IsZero() {
		return ErrInvalidStore
	}
	var created bool
	err := store.db.QueryRowContext(
		context.Background(),
		createCoordinatorSQL,
		record.PaymentID,
		record.AllocationID,
		record.InstructionDigest,
		record.AllocationExpectedVersion,
		string(record.State),
		record.Version,
		string(record.Snapshot),
		evidenceHash,
		occurredAt.UTC(),
		occurredAt.UTC(),
	).Scan(&created)
	if err != nil {
		return fmt.Errorf("create canonical coordinator state: %w", err)
	}
	if !created {
		return ErrStoreConflict
	}
	return nil
}

const compareAndSwapCoordinatorSQL = `
SELECT compare_and_swap_canonical_coordinator_state(
    $1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $10, $11, $12
)`

func (store *SQLStore) CompareAndSwap(
	expectedState State,
	expectedVersion uint64,
	next StoredCoordinator,
	evidenceHash string,
	occurredAt time.Time,
) error {
	if store == nil || store.db == nil || !validStoredCoordinator(next) ||
		!validState(expectedState) || expectedVersion == 0 ||
		next.Version != expectedVersion+1 ||
		evidenceHash == "" || occurredAt.IsZero() {
		return ErrInvalidStore
	}
	var changed bool
	err := store.db.QueryRowContext(
		context.Background(),
		compareAndSwapCoordinatorSQL,
		next.PaymentID,
		next.AllocationID,
		next.InstructionDigest,
		string(expectedState),
		expectedVersion,
		string(next.State),
		next.Version,
		string(next.Snapshot),
		next.Tombstoned,
		next.PendingReversal,
		evidenceHash,
		occurredAt.UTC(),
	).Scan(&changed)
	if err != nil {
		return fmt.Errorf("compare and swap canonical coordinator state: %w", err)
	}
	if !changed {
		return ErrStoreConflict
	}
	return nil
}

const createTombstoneSQL = `
SELECT create_canonical_allocation_tombstone(
    $1, $2, $3, $4, $5, $6, $7
)`

func (store *SQLStore) CreateTombstone(record StoredTombstone) error {
	if store == nil || store.db == nil || !validStoredTombstone(record) {
		return ErrInvalidStore
	}
	var allocationID any
	var instructionDigest any
	var quarantineID any
	if record.AllocationID != "" {
		allocationID = record.AllocationID
		instructionDigest = record.InstructionDigest
	}
	if record.QuarantineID != "" {
		quarantineID = record.QuarantineID
	}
	var created bool
	err := store.db.QueryRowContext(
		context.Background(),
		createTombstoneSQL,
		record.PaymentID,
		allocationID,
		instructionDigest,
		quarantineID,
		record.ReversalEventID,
		record.EvidenceHash,
		record.OccurredAt.UTC(),
	).Scan(&created)
	if err != nil {
		return fmt.Errorf("create canonical allocation tombstone: %w", err)
	}
	if !created {
		return ErrStoreConflict
	}
	return nil
}

const quarantinePendingReversalSQL = `
SELECT quarantine_canonical_pending_reversal(
    $1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12, $13, $14, $15
)`

func (store *SQLStore) QuarantinePendingReversal(
	expectedState State,
	expectedVersion uint64,
	next StoredCoordinator,
	pending PendingReversalSnapshot,
) error {
	if store == nil || store.db == nil || !validStoredCoordinator(next) ||
		!validPendingSnapshot(pending) ||
		pending.PaymentID != next.PaymentID ||
		pending.AllocationID != next.AllocationID ||
		pending.InstructionDigest != next.InstructionDigest ||
		pending.OriginState != expectedState ||
		next.State != StateQuarantined || next.Tombstoned ||
		!next.PendingReversal || !validState(expectedState) ||
		next.Version != expectedVersion+1 {
		return ErrInvalidStore
	}
	var changed bool
	err := store.db.QueryRowContext(
		context.Background(),
		quarantinePendingReversalSQL,
		next.PaymentID,
		next.AllocationID,
		next.InstructionDigest,
		string(expectedState),
		expectedVersion,
		next.Version,
		string(next.Snapshot),
		pending.QuarantineID,
		pending.ProviderID,
		pending.ProviderEventID,
		pending.RawHash,
		pending.CallbackEvidenceHash,
		pending.OccurredAt.UTC(),
		pending.ReceivedAt.UTC(),
		pending.ReceivedAt.UTC().Add(24*time.Hour),
	).Scan(&changed)
	if err != nil {
		return fmt.Errorf("quarantine canonical pending reversal: %w", err)
	}
	if !changed {
		return ErrStoreConflict
	}
	return nil
}

const resolvePendingReversalSQL = `
SELECT to_json(resolve_canonical_pending_reversal(
    $1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, $10, $11, $12, $13,
    $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25,
    $26, $27, $28, $29, $30, $31, $32
))::text`

func (store *SQLStore) ResolvePendingReversal(
	expectedState State,
	expectedVersion uint64,
	next StoredCoordinator,
	resolution PendingReversalResolution,
	localFallback func() ([]string, error),
) ([]string, error) {
	if store == nil || store.db == nil ||
		expectedState != StateQuarantined ||
		!validStoredCoordinator(next) || next.State != StateFailed ||
		next.Version != expectedVersion+1 || !next.Tombstoned ||
		next.PendingReversal || !validPendingResolution(resolution) ||
		localFallback == nil {
		return nil, ErrInvalidStore
	}
	failureArguments := pendingFailureSQLArguments(resolution)
	var encodedJournalIDs sql.NullString
	err := store.db.QueryRowContext(
		context.Background(),
		resolvePendingReversalSQL,
		next.PaymentID,
		next.AllocationID,
		next.InstructionDigest,
		expectedVersion,
		next.Version,
		string(next.Snapshot),
		resolution.Pending.QuarantineID,
		resolution.ResolutionID,
		resolution.ReversalEventID,
		resolution.FailureEvidenceHash,
		resolution.ResolutionEvidence,
		resolution.ResolvedBy,
		resolution.ResolvedAt.UTC(),
		string(resolution.Pending.OriginState),
		failureArguments[0],
		failureArguments[1],
		failureArguments[2],
		failureArguments[3],
		failureArguments[4],
		failureArguments[5],
		failureArguments[6],
		failureArguments[7],
		failureArguments[8],
		failureArguments[9],
		failureArguments[10],
		failureArguments[11],
		failureArguments[12],
		failureArguments[13],
		failureArguments[14],
		failureArguments[15],
		failureArguments[16],
		failureArguments[17],
	).Scan(&encodedJournalIDs)
	if err != nil {
		return nil, fmt.Errorf("resolve canonical pending reversal: %w", err)
	}
	if !encodedJournalIDs.Valid {
		return nil, ErrStoreConflict
	}
	var journalIDs []string
	if json.Unmarshal([]byte(encodedJournalIDs.String), &journalIDs) != nil ||
		len(journalIDs) == 0 || len(journalIDs) > 2 ||
		!uniqueNonempty(journalIDs) {
		return nil, ErrInvalidStore
	}
	return journalIDs, nil
}

const loadCoordinatorSQL = `
SELECT
    coordinator.payment_id,
    coordinator.allocation_id,
    coordinator.instruction_digest,
    claim.expected_version,
    coordinator.state,
    coordinator.version,
    coordinator.snapshot::text,
    coordinator.tombstoned,
    coordinator.pending_reversal
FROM canonical_coordinator_state AS coordinator
JOIN payment_allocation_mode_claim AS claim
  USING (payment_id, allocation_id)
ORDER BY coordinator.payment_id`

func (store *SQLStore) LoadAll() ([]StoredCoordinator, error) {
	if store == nil || store.db == nil {
		return nil, ErrInvalidStore
	}
	rows, err := store.db.QueryContext(context.Background(), loadCoordinatorSQL)
	if err != nil {
		return nil, fmt.Errorf("load canonical coordinator state: %w", err)
	}
	defer rows.Close()
	var result []StoredCoordinator
	for rows.Next() {
		var record StoredCoordinator
		var state string
		var snapshot string
		if err := rows.Scan(
			&record.PaymentID,
			&record.AllocationID,
			&record.InstructionDigest,
			&record.AllocationExpectedVersion,
			&state,
			&record.Version,
			&snapshot,
			&record.Tombstoned,
			&record.PendingReversal,
		); err != nil {
			return nil, fmt.Errorf("scan canonical coordinator state: %w", err)
		}
		record.State = State(state)
		record.Snapshot = []byte(snapshot)
		if !validStoredCoordinator(record) {
			return nil, ErrInvalidStore
		}
		result = append(result, record)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate canonical coordinator state: %w", err)
	}
	return result, nil
}

const loadTombstonesSQL = `
SELECT
    payment_id,
    allocation_id,
    instruction_digest,
    quarantine_id,
    reversal_event_id,
    evidence_hash,
    occurred_at
FROM canonical_allocation_tombstone
ORDER BY payment_id`

func (store *SQLStore) LoadTombstones() ([]StoredTombstone, error) {
	if store == nil || store.db == nil {
		return nil, ErrInvalidStore
	}
	rows, err := store.db.QueryContext(context.Background(), loadTombstonesSQL)
	if err != nil {
		return nil, fmt.Errorf("load canonical allocation tombstones: %w", err)
	}
	defer rows.Close()
	var result []StoredTombstone
	for rows.Next() {
		var record StoredTombstone
		var allocationID sql.NullString
		var instructionDigest sql.NullString
		var quarantineID sql.NullString
		if err := rows.Scan(
			&record.PaymentID,
			&allocationID,
			&instructionDigest,
			&quarantineID,
			&record.ReversalEventID,
			&record.EvidenceHash,
			&record.OccurredAt,
		); err != nil {
			return nil, fmt.Errorf("scan canonical allocation tombstone: %w", err)
		}
		record.AllocationID = allocationID.String
		record.InstructionDigest = instructionDigest.String
		record.QuarantineID = quarantineID.String
		record.OccurredAt = record.OccurredAt.UTC()
		if !validStoredTombstone(record) {
			return nil, ErrInvalidStore
		}
		result = append(result, record)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate canonical allocation tombstones: %w", err)
	}
	return result, nil
}

const loadResolvedReversalsSQL = `
SELECT
    history.snapshot,
    resolution.resolution_id,
    reversal.event_id,
    resolution.evidence_hash,
    resolution.resolved_by,
    resolution.resolved_at,
    to_json(reversal.journal_ids)::text,
    failure.chain_id,
    failure.gateway_address,
    failure.transaction_hash,
    failure.receipt_payload_hash,
    failure.receipt_status,
    failure.block_number,
    failure.block_hash,
    failure.confirmation_depth,
    failure.head_block_number,
    failure.head_block_hash,
    failure.evidence_hash,
    failure.observed_at,
    failure.finality_policy_hash,
    failure.header_authority_hash,
    failure.receipt_header_signature_hash,
    failure.head_header_signature_hash,
    failure.transaction_index::text,
    failure.receipts_root,
    failure.inclusion_proof_hash
FROM canonical_pending_reversal_quarantine AS canonical
JOIN payment_callback_quarantine AS quarantine
  ON quarantine.quarantine_id = canonical.quarantine_id
JOIN payment_callback_quarantine_resolution AS resolution
  ON resolution.quarantine_id = canonical.quarantine_id
JOIN payment_state_event AS reversal
  ON reversal.event_id =
     quarantine.provider_id || ':' || quarantine.provider_event_id
 AND reversal.payment_id = canonical.payment_id
 AND reversal.from_status = 'FINAL'
 AND reversal.to_status = 'REVERSED'
JOIN canonical_allocation_tombstone AS tombstone
  ON tombstone.payment_id = canonical.payment_id
 AND tombstone.quarantine_id = canonical.quarantine_id
 AND tombstone.reversal_event_id = reversal.event_id
JOIN LATERAL (
    SELECT stored.snapshot
    FROM canonical_coordinator_state_history AS stored
    WHERE stored.payment_id = canonical.payment_id
      AND stored.state = 'QUARANTINED'
      AND stored.pending_reversal
      AND stored.snapshot #>> '{PendingReversal,QuarantineID}' =
          canonical.quarantine_id
    ORDER BY stored.version DESC
    LIMIT 1
) AS history ON true
LEFT JOIN canonical_reverted_transaction_evidence AS failure
  ON failure.quarantine_id = canonical.quarantine_id
ORDER BY canonical.quarantine_id`

func (store *SQLStore) LoadResolvedReversals() ([]StoredReversalResolution, error) {
	if store == nil || store.db == nil {
		return nil, ErrInvalidStore
	}
	rows, err := store.db.QueryContext(context.Background(), loadResolvedReversalsSQL)
	if err != nil {
		return nil, fmt.Errorf("load canonical reversal resolutions: %w", err)
	}
	defer rows.Close()
	var result []StoredReversalResolution
	for rows.Next() {
		var snapshotJSON []byte
		var resolutionID string
		var reversalEventID string
		var resolutionEvidence string
		var resolvedBy string
		var resolvedAt time.Time
		var journalJSON string
		var failureChainID sql.NullInt64
		var failureGateway sql.NullString
		var failureTransactionHash sql.NullString
		var failureReceiptHash sql.NullString
		var failureStatus sql.NullString
		var failureBlockNumber sql.NullInt64
		var failureBlockHash sql.NullString
		var failureDepth sql.NullInt64
		var failureHeadNumber sql.NullInt64
		var failureHeadHash sql.NullString
		var failureEvidenceHash sql.NullString
		var failureObservedAt sql.NullTime
		var failureFinalityPolicyHash sql.NullString
		var failureHeaderAuthorityHash sql.NullString
		var failureReceiptHeaderSignatureHash sql.NullString
		var failureHeadHeaderSignatureHash sql.NullString
		var failureTransactionIndex sql.NullString
		var failureReceiptsRoot sql.NullString
		var failureInclusionProofHash sql.NullString
		if err := rows.Scan(
			&snapshotJSON,
			&resolutionID,
			&reversalEventID,
			&resolutionEvidence,
			&resolvedBy,
			&resolvedAt,
			&journalJSON,
			&failureChainID,
			&failureGateway,
			&failureTransactionHash,
			&failureReceiptHash,
			&failureStatus,
			&failureBlockNumber,
			&failureBlockHash,
			&failureDepth,
			&failureHeadNumber,
			&failureHeadHash,
			&failureEvidenceHash,
			&failureObservedAt,
			&failureFinalityPolicyHash,
			&failureHeaderAuthorityHash,
			&failureReceiptHeaderSignatureHash,
			&failureHeadHeaderSignatureHash,
			&failureTransactionIndex,
			&failureReceiptsRoot,
			&failureInclusionProofHash,
		); err != nil {
			return nil, fmt.Errorf("scan canonical reversal resolution: %w", err)
		}
		snapshot, err := decodeDurableSnapshot(snapshotJSON)
		if err != nil || snapshot.PendingReversal == nil {
			return nil, ErrInvalidStore
		}
		pending := *snapshot.PendingReversal
		var journalIDs []string
		if err := json.Unmarshal([]byte(journalJSON), &journalIDs); err != nil {
			return nil, ErrInvalidStore
		}
		var failure chainprojection.TransactionFailureEvidence
		var canonicalFailureEvidenceHash string
		if pending.OriginState == StateSubmitted {
			if !failureChainID.Valid || failureChainID.Int64 <= 0 ||
				!failureGateway.Valid || !failureTransactionHash.Valid ||
				!failureReceiptHash.Valid || !failureStatus.Valid ||
				!failureBlockNumber.Valid || failureBlockNumber.Int64 <= 0 ||
				!failureBlockHash.Valid || !failureDepth.Valid ||
				failureDepth.Int64 <= 0 || !failureHeadNumber.Valid ||
				failureHeadNumber.Int64 <= 0 || !failureHeadHash.Valid ||
				!failureEvidenceHash.Valid || !failureObservedAt.Valid {
				return nil, ErrInvalidStore
			}
			if !failureFinalityPolicyHash.Valid ||
				!failureHeaderAuthorityHash.Valid ||
				!failureReceiptHeaderSignatureHash.Valid ||
				!failureHeadHeaderSignatureHash.Valid ||
				!failureTransactionIndex.Valid ||
				!failureReceiptsRoot.Valid ||
				!failureInclusionProofHash.Valid {
				return nil, ErrInvalidStore
			}
			transactionIndex, err := strconv.ParseUint(
				failureTransactionIndex.String,
				10,
				64,
			)
			if err != nil {
				return nil, ErrInvalidStore
			}
			failure = chainprojection.TransactionFailureEvidence{
				ChainID:            uint64(failureChainID.Int64),
				Gateway:            failureGateway.String,
				TransactionHash:    failureTransactionHash.String,
				ReceiptPayloadHash: failureReceiptHash.String,
				Status: chainprojection.TransactionReceiptStatus(
					failureStatus.String,
				),
				TransactionIndex:           transactionIndex,
				BlockNumber:                uint64(failureBlockNumber.Int64),
				BlockHash:                  failureBlockHash.String,
				ReceiptsRoot:               failureReceiptsRoot.String,
				InclusionProofHash:         failureInclusionProofHash.String,
				FinalityPolicyHash:         failureFinalityPolicyHash.String,
				HeaderAuthorityHash:        failureHeaderAuthorityHash.String,
				ReceiptHeaderSignatureHash: failureReceiptHeaderSignatureHash.String,
				HeadHeaderSignatureHash:    failureHeadHeaderSignatureHash.String,
				ConfirmationDepth:          uint64(failureDepth.Int64),
				HeadBlockNumber:            uint64(failureHeadNumber.Int64),
				HeadBlockHash:              failureHeadHash.String,
				EvidenceHash:               failureEvidenceHash.String,
				ObservedAt:                 failureObservedAt.Time.UTC(),
			}
			canonicalFailureEvidenceHash = failure.EvidenceHash
		} else {
			if failureChainID.Valid || failureGateway.Valid ||
				failureTransactionHash.Valid || failureReceiptHash.Valid ||
				failureStatus.Valid || failureBlockNumber.Valid ||
				failureBlockHash.Valid || failureDepth.Valid ||
				failureHeadNumber.Valid || failureHeadHash.Valid ||
				failureEvidenceHash.Valid || failureObservedAt.Valid ||
				failureFinalityPolicyHash.Valid ||
				failureHeaderAuthorityHash.Valid ||
				failureReceiptHeaderSignatureHash.Valid ||
				failureHeadHeaderSignatureHash.Valid ||
				failureTransactionIndex.Valid ||
				failureReceiptsRoot.Valid ||
				failureInclusionProofHash.Valid {
				return nil, ErrInvalidStore
			}
			canonicalFailureEvidenceHash =
				preSubmissionFailureEvidenceHash(snapshot.Plan, pending)
		}
		resolution := PendingReversalResolution{
			Pending:             pending,
			ResolutionID:        resolutionID,
			ReversalEventID:     reversalEventID,
			FailureEvidenceHash: canonicalFailureEvidenceHash,
			FailureProof:        failure,
			ResolutionEvidence:  resolutionEvidence,
			ResolvedBy:          resolvedBy,
			ResolvedAt:          resolvedAt.UTC(),
		}
		resolution.RequestDigest = reversalResolutionRequestDigest(
			pending,
			resolution.ResolutionID,
			resolution.FailureEvidenceHash,
			resolution.FailureProof,
			resolution.ResolutionEvidence,
			resolution.ResolvedBy,
			resolution.ResolvedAt,
		)
		stored := StoredReversalResolution{
			Resolution: resolution,
			JournalIDs: journalIDs,
		}
		if !validStoredReversalResolution(stored) {
			return nil, ErrInvalidStore
		}
		result = append(result, stored)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate canonical reversal resolutions: %w", err)
	}
	return result, nil
}

func encodeDurableSnapshot(snapshot durableSnapshot) ([]byte, error) {
	return json.Marshal(snapshot)
}

func decodeDurableSnapshot(encoded []byte) (durableSnapshot, error) {
	var snapshot durableSnapshot
	if len(encoded) == 0 || json.Unmarshal(encoded, &snapshot) != nil {
		return durableSnapshot{}, ErrInvalidStore
	}
	return snapshot, nil
}

func validStoredCoordinator(record StoredCoordinator) bool {
	return record.PaymentID != "" &&
		record.AllocationID != "" &&
		record.InstructionDigest != "" &&
		record.AllocationExpectedVersion > 0 &&
		validState(record.State) &&
		record.Version > 0 &&
		len(record.Snapshot) > 0
}

func validState(state State) bool {
	switch state {
	case StatePrepared, StateSubmitted, StateConfirmed, StateFailed,
		StateQuarantined, StateIncident:
		return true
	default:
		return false
	}
}

func cloneStoredCoordinator(record StoredCoordinator) StoredCoordinator {
	record.Snapshot = slices.Clone(record.Snapshot)
	return record
}

func storedCoordinatorsEqual(left StoredCoordinator, right StoredCoordinator) bool {
	return left.PaymentID == right.PaymentID &&
		left.AllocationID == right.AllocationID &&
		left.InstructionDigest == right.InstructionDigest &&
		left.AllocationExpectedVersion == right.AllocationExpectedVersion &&
		left.State == right.State &&
		left.Version == right.Version &&
		slices.Equal(left.Snapshot, right.Snapshot) &&
		left.Tombstoned == right.Tombstoned &&
		left.PendingReversal == right.PendingReversal
}

func validStoredTombstone(record StoredTombstone) bool {
	return record.PaymentID != "" &&
		((record.AllocationID == "") == (record.InstructionDigest == "")) &&
		record.ReversalEventID != "" &&
		record.EvidenceHash != "" &&
		!record.OccurredAt.IsZero()
}

func validPendingResolution(resolution PendingReversalResolution) bool {
	if !validPendingSnapshot(resolution.Pending) ||
		resolution.RequestDigest == "" ||
		resolution.ResolutionID == "" ||
		resolution.ReversalEventID == "" ||
		resolution.ReversalEventID != resolution.Pending.ProviderID+":"+
			resolution.Pending.ProviderEventID ||
		resolution.FailureEvidenceHash == "" ||
		resolution.ResolutionEvidence == "" ||
		resolution.ResolvedBy == "" ||
		resolution.ResolvedAt.IsZero() {
		return false
	}
	if resolution.RequestDigest != reversalResolutionRequestDigest(
		resolution.Pending,
		resolution.ResolutionID,
		resolution.FailureEvidenceHash,
		resolution.FailureProof,
		resolution.ResolutionEvidence,
		resolution.ResolvedBy,
		resolution.ResolvedAt,
	) {
		return false
	}
	failure := resolution.FailureProof
	switch resolution.Pending.OriginState {
	case StateSubmitted:
		return failure.Status == chainprojection.TransactionReverted &&
			failure.EvidenceHash == resolution.FailureEvidenceHash &&
			failure.ChainID == resolution.Pending.SubmissionChainID &&
			failure.Gateway == resolution.Pending.SubmissionGateway &&
			failure.TransactionHash == resolution.Pending.SubmissionTxHash &&
			failure.ReceiptPayloadHash != "" &&
			failure.FinalityPolicyHash != "" &&
			failure.HeaderAuthorityHash != "" &&
			failure.ReceiptHeaderSignatureHash != "" &&
			failure.HeadHeaderSignatureHash != "" &&
			failure.BlockNumber > 0 && failure.BlockHash != "" &&
			failure.ReceiptsRoot != "" && failure.InclusionProofHash != "" &&
			failure.ConfirmationDepth > 0 &&
			failure.HeadBlockNumber >= failure.BlockNumber &&
			failure.HeadBlockNumber-failure.BlockNumber >=
				failure.ConfirmationDepth &&
			failure.HeadBlockHash != "" && !failure.ObservedAt.IsZero() &&
			!failure.ObservedAt.Before(
				resolution.Pending.SubmissionSubmittedAt,
			) &&
			!failure.ObservedAt.After(resolution.ResolvedAt)
	case StatePrepared, StateFailed:
		return failure == (chainprojection.TransactionFailureEvidence{})
	default:
		return false
	}
}

func validStoredReversalResolution(record StoredReversalResolution) bool {
	return validPendingResolution(record.Resolution) &&
		len(record.JournalIDs) > 0 && len(record.JournalIDs) <= 2 &&
		uniqueNonempty(record.JournalIDs)
}

func validConsumedPendingReversal(
	consumed ConsumedPendingReversalSnapshot,
	plan Plan,
	confirmation AccountingProjection,
) bool {
	return validPendingSnapshot(consumed.Pending) &&
		submittedPendingMatchesPlan(consumed.Pending, plan) &&
		consumed.ResolutionID == "canonical-success:"+consumed.GatewayEventID &&
		consumed.ResolutionEvidenceHash != "" &&
		consumed.ResolvedBy == "canonical-chain-indexer" &&
		!consumed.ResolvedAt.IsZero() &&
		consumed.GatewayEventID == confirmation.EventID &&
		consumed.GatewayTransactionHash == confirmation.TransactionHash &&
		consumed.GatewayRawPayloadHash == confirmation.GatewayPayloadHash &&
		consumed.FinalityEvidenceHash == confirmation.FinalityEvidenceHash &&
		consumed.ResolutionEvidenceHash == confirmation.FinalityEvidenceHash &&
		consumed.ResolvedAt.Equal(confirmation.ConfirmedAt.UTC()) &&
		confirmation.Incident
}

func validPendingSnapshot(pending PendingReversalSnapshot) bool {
	switch pending.OriginState {
	case StateSubmitted:
		if pending.SubmissionChainID == 0 ||
			pending.SubmissionGateway == "" ||
			pending.SubmissionTxHash == "" ||
			pending.SubmissionSubmittedAt.IsZero() {
			return false
		}
	case StatePrepared, StateFailed:
		if pending.SubmissionChainID != 0 ||
			pending.SubmissionGateway != "" ||
			pending.SubmissionTxHash != "" ||
			!pending.SubmissionSubmittedAt.IsZero() {
			return false
		}
	default:
		return false
	}
	return pending.QuarantineID != "" && pending.IngressID > 0 &&
		pending.ProviderID != "" && pending.ProviderEventID != "" &&
		pending.ProviderReference != "" && pending.AssetID != "" &&
		pending.Units != "" && pending.RawHash != "" &&
		pending.SignatureHash != "" && pending.PaymentID != "" &&
		pending.AllocationID != "" && pending.InstructionDigest != "" &&
		pending.CallbackEvidenceHash != "" &&
		!pending.CallbackExpiresAt.IsZero() &&
		!pending.OccurredAt.IsZero() && !pending.ReceivedAt.IsZero() &&
		!pending.ReceivedAt.Before(pending.OccurredAt) &&
		!pending.ReceivedAt.After(pending.CallbackExpiresAt)
}

func pendingFailureSQLArguments(
	resolution PendingReversalResolution,
) [18]any {
	var result [18]any
	if resolution.Pending.OriginState != StateSubmitted {
		return result
	}
	failure := resolution.FailureProof
	result[0] = failure.ChainID
	result[1] = failure.Gateway
	result[2] = failure.TransactionHash
	result[3] = failure.ReceiptPayloadHash
	result[4] = string(failure.Status)
	result[5] = failure.BlockNumber
	result[6] = failure.BlockHash
	result[7] = failure.ConfirmationDepth
	result[8] = failure.HeadBlockNumber
	result[9] = failure.HeadBlockHash
	result[10] = failure.ObservedAt.UTC()
	result[11] = failure.FinalityPolicyHash
	result[12] = failure.HeaderAuthorityHash
	result[13] = failure.ReceiptHeaderSignatureHash
	result[14] = failure.HeadHeaderSignatureHash
	result[15] = strconv.FormatUint(failure.TransactionIndex, 10)
	result[16] = failure.ReceiptsRoot
	result[17] = failure.InclusionProofHash
	return result
}

func (coordinator *Coordinator) durableRecord(
	plan Plan,
	claim allocationmode.Claim,
) (StoredCoordinator, error) {
	var pending *PendingReversalSnapshot
	if existing, exists := coordinator.pending[plan.PaymentID]; exists {
		copy := existing
		pending = &copy
	}
	return coordinator.durableRecordWith(
		plan,
		claim,
		false,
		pending,
	)
}

func (coordinator *Coordinator) durableRecordWith(
	plan Plan,
	claim allocationmode.Claim,
	tombstoned bool,
	pending *PendingReversalSnapshot,
) (StoredCoordinator, error) {
	if !claimMatchesPlan(claim, plan) ||
		stateFromCanonical(claim.State) != plan.State {
		return StoredCoordinator{}, ErrInvalidTransition
	}
	snapshot := durableSnapshot{
		Plan:       clonePlan(plan),
		Claim:      claim,
		Tombstoned: tombstoned,
	}
	if confirmation, exists := coordinator.confirmations[plan.PaymentID]; exists {
		projection := confirmation.AccountingProjection()
		snapshot.Confirmation = &projection
	}
	for _, reorg := range coordinator.reorgs {
		if reorg.PaymentID == plan.PaymentID {
			snapshot.Reorgs = append(snapshot.Reorgs, reorg)
		}
	}
	if pending != nil {
		copy := *pending
		snapshot.PendingReversal = &copy
	}
	if consumed, exists := coordinator.consumed[plan.PaymentID]; exists {
		copy := consumed
		snapshot.ConsumedPendingReversal = &copy
	}
	encoded, err := encodeDurableSnapshot(snapshot)
	if err != nil {
		return StoredCoordinator{}, errors.Join(ErrInvalidStore, err)
	}
	return StoredCoordinator{
		PaymentID:                 plan.PaymentID,
		AllocationID:              plan.AllocationID,
		InstructionDigest:         plan.InstructionDigest,
		AllocationExpectedVersion: plan.PaymentVersion,
		State:                     plan.State,
		Version:                   plan.Version,
		Snapshot:                  encoded,
		Tombstoned:                snapshot.Tombstoned,
		PendingReversal:           snapshot.PendingReversal != nil,
	}, nil
}

func (coordinator *Coordinator) createDurable(
	plan Plan,
	claim allocationmode.Claim,
	evidenceHash string,
	occurredAt time.Time,
) error {
	record, err := coordinator.durableRecord(plan, claim)
	if err != nil {
		return err
	}
	return coordinator.store.Create(record, evidenceHash, occurredAt)
}

func (coordinator *Coordinator) compareAndSwapDurable(
	expectedState State,
	expectedVersion uint64,
	plan Plan,
	claim allocationmode.Claim,
	evidenceHash string,
	occurredAt time.Time,
) error {
	record, err := coordinator.durableRecord(plan, claim)
	if err != nil {
		return err
	}
	return coordinator.store.CompareAndSwap(
		expectedState,
		expectedVersion,
		record,
		evidenceHash,
		occurredAt,
	)
}

func validRecoveredSnapshot(
	record StoredCoordinator,
	snapshot durableSnapshot,
) bool {
	plan := snapshot.Plan
	if plan.PaymentID != record.PaymentID ||
		plan.AllocationID != record.AllocationID ||
		plan.InstructionDigest != record.InstructionDigest ||
		plan.PaymentVersion != record.AllocationExpectedVersion ||
		plan.State != record.State ||
		plan.Version != record.Version ||
		snapshot.Claim.PaymentID != plan.PaymentID ||
		snapshot.Claim.AllocationID != plan.AllocationID ||
		snapshot.Claim.Digest != plan.InstructionDigest ||
		snapshot.Claim.Mode != allocationmode.ModeCanonicalGateway ||
		stateFromCanonical(snapshot.Claim.State) != plan.State ||
		snapshot.Tombstoned != record.Tombstoned ||
		(snapshot.PendingReversal != nil) != record.PendingReversal {
		return false
	}
	if snapshot.Confirmation != nil {
		confirmation := snapshot.Confirmation
		if confirmation.PaymentID != plan.PaymentID ||
			confirmation.AllocationID != plan.AllocationID ||
			confirmation.InstructionDigest != plan.InstructionDigest ||
			confirmation.FinalityPolicyHash != plan.FinalityPolicyHash ||
			confirmation.TransactionHash == "" ||
			confirmation.BlockHash == "" ||
			confirmation.ReceiptsRoot == "" ||
			confirmation.InclusionProofHash == "" ||
			confirmation.HeaderAuthorityHash == "" ||
			confirmation.ReceiptHeaderSignatureHash == "" ||
			confirmation.HeadHeaderSignatureHash == "" ||
			confirmation.ConfirmationDepth == 0 ||
			confirmation.FinalityHeadHash == "" ||
			confirmation.FinalityEvidenceHash == "" ||
			plan.Submission.SubmittedAt.IsZero() ||
			confirmation.ConfirmedAt.Before(plan.Submission.SubmittedAt) ||
			(plan.State != StateConfirmed && plan.State != StateIncident) {
			return false
		}
	}
	if snapshot.PendingReversal != nil {
		pending := snapshot.PendingReversal
		if !validPendingSnapshot(*pending) ||
			pending.PaymentID != plan.PaymentID ||
			pending.AllocationID != plan.AllocationID ||
			pending.InstructionDigest != plan.InstructionDigest ||
			plan.State != StateQuarantined {
			return false
		}
		if pending.OriginState == StateSubmitted &&
			(pending.SubmissionChainID != plan.Submission.ChainID ||
				pending.SubmissionGateway != plan.Submission.Gateway ||
				pending.SubmissionTxHash != plan.Submission.TransactionHash ||
				!pending.SubmissionSubmittedAt.Equal(
					plan.Submission.SubmittedAt.UTC(),
				)) {
			return false
		}
	}
	if snapshot.ConsumedPendingReversal != nil {
		if snapshot.PendingReversal != nil || snapshot.Confirmation == nil ||
			plan.State != StateIncident || snapshot.Tombstoned ||
			!validConsumedPendingReversal(
				*snapshot.ConsumedPendingReversal,
				plan,
				*snapshot.Confirmation,
			) {
			return false
		}
	}
	for _, reorg := range snapshot.Reorgs {
		if !validRecoveredReorg(plan, snapshot.Confirmation, reorg) {
			return false
		}
	}
	return true
}

func validRecoveredReorg(
	plan Plan,
	confirmation *AccountingProjection,
	reorg ReorgEvidence,
) bool {
	if reorg.ReorgID != "reorg:"+reorg.EvidenceHash ||
		reorg.PaymentID != plan.PaymentID ||
		reorg.AllocationID != plan.AllocationID ||
		reorg.InstructionDigest != plan.InstructionDigest ||
		reorg.ChainID != plan.ChainID ||
		reorg.Gateway != plan.GatewayAddress ||
		reorg.FinalityPolicyHash != plan.FinalityPolicyHash ||
		reorg.OrphanedEventID == "" ||
		!validCanonicalHash(reorg.OrphanedTxHash) ||
		!validNonzeroHash(reorg.OrphanedEventEvidenceHash) ||
		!validCanonicalHash(reorg.RawEvidenceHash) ||
		!validCanonicalHash(reorg.ReceiptsRoot) ||
		!validCanonicalHash(reorg.InclusionProofHash) ||
		!validCanonicalHash(reorg.OrphanedReceiptHeaderSignatureHash) ||
		!validCanonicalHash(reorg.OrphanedBlockHash) ||
		reorg.OrphanedBlock == 0 ||
		!validCanonicalHash(reorg.ReplacementBlockHash) ||
		reorg.ReplacementBlock == 0 ||
		reorg.ConfirmationDepth == 0 ||
		reorg.DetectedHead < reorg.OrphanedBlock ||
		!validCanonicalHash(reorg.DetectedHeadHash) ||
		!validCanonicalHash(reorg.FinalityPolicyHash) ||
		!validCanonicalHash(reorg.HeaderAuthorityHash) ||
		!validCanonicalHash(reorg.ReplacementHeaderSignatureHash) ||
		!validCanonicalHash(reorg.DetectedHeadHeaderSignatureHash) ||
		!validCanonicalHash(reorg.EvidenceHash) ||
		reorg.SubmissionSubmittedAt.IsZero() ||
		reorg.DetectedAt.IsZero() ||
		reorg.DetectedAt.Before(reorg.SubmissionSubmittedAt) ||
		reorg.Deep != (reorg.DepthClass == chainprojection.ReorgDeepFinality) ||
		reorg.CompensationRequired != reorg.Deep {
		return false
	}
	if !reorg.Deep {
		return reorg.DepthClass == chainprojection.ReorgPreFinality &&
			reorg.OrphanedEventEvidenceHash == plan.EligibilityEvidenceHash &&
			reorg.OrphanedTxHash == plan.Submission.TransactionHash
	}
	return confirmation != nil &&
		reorg.OrphanedEventID == confirmation.EventID &&
		reorg.OrphanedTxHash == confirmation.TransactionHash &&
		reorg.OrphanedEventEvidenceHash == confirmation.EventEvidenceHash &&
		reorg.TransactionIndex == confirmation.TransactionIndex &&
		reorg.ReceiptsRoot == confirmation.ReceiptsRoot &&
		reorg.InclusionProofHash == confirmation.InclusionProofHash &&
		reorg.OrphanedReceiptHeaderSignatureHash ==
			confirmation.ReceiptHeaderSignatureHash &&
		reorg.OrphanedBlockHash == confirmation.BlockHash &&
		reorg.OrphanedBlock == confirmation.BlockNumber &&
		reorg.RawEvidenceHash == confirmation.GatewayPayloadHash &&
		reorg.FinalityPolicyHash == confirmation.FinalityPolicyHash &&
		reorg.HeaderAuthorityHash == confirmation.HeaderAuthorityHash &&
		reorg.ConfirmationDepth == confirmation.ConfirmationDepth &&
		reorg.DetectedHead >= confirmation.FinalityHeadBlock &&
		!reorg.DetectedAt.Before(confirmation.ConfirmedAt)
}

func validCanonicalHash(value string) bool {
	_, err := decodeFixedHex(value, 32)
	return err == nil
}
