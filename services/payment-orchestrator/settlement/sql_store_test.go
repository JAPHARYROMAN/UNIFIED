package settlement

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
)

var sqlStoreDriverSequence atomic.Uint64

type recordedSQLCall struct {
	query string
	args  []driver.NamedValue
}

type recordingSQLDriver struct {
	mu    sync.Mutex
	calls []recordedSQLCall
}

func (mock *recordingSQLDriver) Open(string) (driver.Conn, error) {
	return &recordingSQLConnection{mock: mock}, nil
}

func (mock *recordingSQLDriver) record(
	query string,
	args []driver.NamedValue,
) driver.Rows {
	mock.mu.Lock()
	defer mock.mu.Unlock()
	copied := append([]driver.NamedValue(nil), args...)
	mock.calls = append(mock.calls, recordedSQLCall{query: query, args: copied})
	value := driver.Value(true)
	if strings.Contains(query, "resolve_canonical_pending_reversal") {
		value = `["journal-final-reversal","journal-provisional-reversal"]`
	}
	return &singleValueRows{value: value}
}

type recordingSQLConnection struct {
	mock *recordingSQLDriver
}

func (*recordingSQLConnection) Prepare(string) (driver.Stmt, error) {
	return nil, errors.New("prepare is not supported")
}

func (*recordingSQLConnection) Close() error {
	return nil
}

func (*recordingSQLConnection) Begin() (driver.Tx, error) {
	return nil, errors.New("transactions are not supported")
}

func (connection *recordingSQLConnection) QueryContext(
	_ context.Context,
	query string,
	args []driver.NamedValue,
) (driver.Rows, error) {
	return connection.mock.record(query, args), nil
}

type singleValueRows struct {
	returned bool
	value    driver.Value
}

func (*singleValueRows) Columns() []string {
	return []string{"result"}
}

func (*singleValueRows) Close() error {
	return nil
}

func (rows *singleValueRows) Next(values []driver.Value) error {
	if rows.returned {
		return io.EOF
	}
	rows.returned = true
	values[0] = rows.value
	return nil
}

func newRecordingSQLStore(t *testing.T) (*SQLStore, *recordingSQLDriver) {
	t.Helper()
	mock := &recordingSQLDriver{}
	name := fmt.Sprintf(
		"unified-settlement-store-%d",
		sqlStoreDriverSequence.Add(1),
	)
	sql.Register(name, mock)
	database, err := sql.Open(name, "")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = database.Close() })
	store, err := NewSQLStore(database)
	if err != nil {
		t.Fatal(err)
	}
	return store, mock
}

func TestSQLStoreUsesAtomicQuarantineAndResolutionFunctions(t *testing.T) {
	now := time.Unix(1_772_000_000, 0).UTC()
	coordinator, err := NewInMemory(allocationmode.NewInMemory())
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, prepared)
	reversal := reversalFixture(
		submitted,
		"quarantine-sql",
		"provider-reversal-sql",
		submitted.Submission.SubmittedAt.Add(time.Minute),
	)
	pending := pendingSnapshot(reversal, submitted, StateSubmitted)
	quarantined := StoredCoordinator{
		PaymentID:                 submitted.PaymentID,
		AllocationID:              submitted.AllocationID,
		InstructionDigest:         submitted.InstructionDigest,
		AllocationExpectedVersion: submitted.PaymentVersion,
		State:                     StateQuarantined,
		Version:                   submitted.Version + 1,
		Snapshot:                  []byte(`{"state":"QUARANTINED"}`),
		PendingReversal:           true,
	}
	store, mock := newRecordingSQLStore(t)
	if err := store.QuarantinePendingReversal(
		StateSubmitted,
		submitted.Version,
		quarantined,
		pending,
	); err != nil {
		t.Fatalf("quarantine SQL call: %v", err)
	}

	proof := verifiedFailureFixture(t, submitted)
	resolvedAt := proof.Evidence().ObservedAt.Add(time.Minute)
	failed := quarantined
	failed.State = StateFailed
	failed.Version++
	failed.Snapshot = []byte(`{"state":"FAILED"}`)
	failed.Tombstoned = true
	failed.PendingReversal = false
	fallbackCalled := false
	resolution := PendingReversalResolution{
		Pending:             pending,
		ResolutionID:        "resolution-sql",
		ReversalEventID:     reversal.ReversalEventID,
		FailureEvidenceHash: proof.Evidence().EvidenceHash,
		FailureProof:        proof.Evidence(),
		ResolutionEvidence:  "resolution-sql-evidence",
		ResolvedBy:          "payment-operator",
		ResolvedAt:          resolvedAt,
	}
	resolution.RequestDigest = reversalResolutionRequestDigest(
		resolution.Pending,
		resolution.ResolutionID,
		resolution.FailureEvidenceHash,
		resolution.FailureProof,
		resolution.ResolutionEvidence,
		resolution.ResolvedBy,
		resolution.ResolvedAt,
	)
	journalIDs, err := store.ResolvePendingReversal(
		StateQuarantined,
		quarantined.Version,
		failed,
		resolution,
		func() ([]string, error) {
			fallbackCalled = true
			return []string{"must-not-run"}, nil
		},
	)
	if err != nil || fallbackCalled || len(journalIDs) != 2 {
		t.Fatalf(
			"atomic SQL resolution mismatch: journals=%v fallback=%v err=%v",
			journalIDs,
			fallbackCalled,
			err,
		)
	}

	mock.mu.Lock()
	defer mock.mu.Unlock()
	if len(mock.calls) != 2 ||
		!strings.Contains(
			mock.calls[0].query,
			"quarantine_canonical_pending_reversal",
		) ||
		len(mock.calls[0].args) != 15 ||
		!strings.Contains(
			mock.calls[1].query,
			"resolve_canonical_pending_reversal",
		) ||
		len(mock.calls[1].args) != 32 {
		t.Fatalf("unexpected SQL calls: %#v", mock.calls)
	}
	for index := 14; index < 32; index++ {
		if mock.calls[1].args[index].Value == nil {
			t.Fatalf("submitted proof argument %d was NULL", index+1)
		}
	}
}

func TestSQLStorePassesNoFailureReceiptForPreparedOrigin(t *testing.T) {
	now := time.Unix(1_772_100_000, 0).UTC()
	pending := PendingReversalSnapshot{
		QuarantineID:         "quarantine-prepared-sql",
		IngressID:            1,
		ProviderID:           "provider-local",
		ProviderEventID:      "reversal-prepared-sql",
		ProviderReference:    "provider-reference",
		AssetID:              "asset:local:usd",
		Units:                "400",
		RawHash:              "raw-prepared",
		SignatureHash:        "signature-prepared",
		PaymentID:            "payment-prepared-sql",
		AllocationID:         "allocation-prepared-sql",
		InstructionDigest:    "instruction-prepared-sql",
		CallbackEvidenceHash: "callback-prepared",
		CallbackExpiresAt:    now.Add(time.Hour),
		OccurredAt:           now,
		ReceivedAt:           now.Add(time.Minute),
		OriginState:          StatePrepared,
	}
	next := StoredCoordinator{
		PaymentID:                 pending.PaymentID,
		AllocationID:              pending.AllocationID,
		InstructionDigest:         pending.InstructionDigest,
		AllocationExpectedVersion: 4,
		State:                     StateFailed,
		Version:                   3,
		Snapshot:                  []byte(`{"state":"FAILED"}`),
		Tombstoned:                true,
	}
	store, mock := newRecordingSQLStore(t)
	resolution := PendingReversalResolution{
		Pending:             pending,
		ResolutionID:        "resolution-prepared-sql",
		ReversalEventID:     "provider-local:reversal-prepared-sql",
		FailureEvidenceHash: "derived-pre-submission-failure",
		ResolutionEvidence:  "resolution-prepared-evidence",
		ResolvedBy:          "payment-operator",
		ResolvedAt:          now.Add(2 * time.Minute),
	}
	resolution.RequestDigest = reversalResolutionRequestDigest(
		resolution.Pending,
		resolution.ResolutionID,
		resolution.FailureEvidenceHash,
		resolution.FailureProof,
		resolution.ResolutionEvidence,
		resolution.ResolvedBy,
		resolution.ResolvedAt,
	)
	_, err := store.ResolvePendingReversal(
		StateQuarantined,
		2,
		next,
		resolution,
		func() ([]string, error) {
			return []string{"must-not-run"}, nil
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	mock.mu.Lock()
	defer mock.mu.Unlock()
	if len(mock.calls) != 1 || len(mock.calls[0].args) != 32 {
		t.Fatalf("unexpected prepared SQL call: %#v", mock.calls)
	}
	for index := 14; index < 32; index++ {
		if mock.calls[0].args[index].Value != nil {
			t.Fatalf("prepared proof argument %d was not NULL", index+1)
		}
	}
}

func TestPendingFailureSQLArgumentsPreserveFullUint64TransactionIndex(t *testing.T) {
	resolution := PendingReversalResolution{
		Pending: PendingReversalSnapshot{OriginState: StateSubmitted},
		FailureProof: chainprojection.TransactionFailureEvidence{
			TransactionIndex: ^uint64(0),
		},
	}
	arguments := pendingFailureSQLArguments(resolution)
	if arguments[15] != "18446744073709551615" {
		t.Fatalf("full uint64 transaction index was narrowed: %#v", arguments[15])
	}
}
