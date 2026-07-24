// Package paymentaccounting maps accepted Phase 7A provider transitions to the
// foundation ledger. It demonstrates balanced provisional, final, and linked reversal
// journals without allocating a payment to loan debt.
package paymentaccounting

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"slices"
	"sync"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

var (
	ErrInvalidTransition      = errors.New("invalid payment accounting transition")
	ErrTransitionConflict     = errors.New("payment accounting transition conflict")
	ErrInvalidReconciliation  = errors.New("invalid payment reconciliation")
	ErrReconciliationConflict = errors.New("payment reconciliation conflict")
	ErrInvalidResolution      = errors.New("invalid reconciliation resolution")
)

type Record struct {
	PaymentID            string
	ProvisionalJournalID string
	FinalJournalID       string
	ReversalJournalIDs   []string
}

type appliedTransition struct {
	contentHash string
	journalIDs  []string
}

type Poster struct {
	mu            sync.RWMutex
	book          *ledger.Ledger
	legalEntityID string
	bookID        string
	records       map[string]Record
	events        map[string]appliedTransition
}

func New(book *ledger.Ledger, legalEntityID string, bookID string) (*Poster, error) {
	if book == nil || legalEntityID == "" || bookID == "" {
		return nil, ErrInvalidTransition
	}
	return &Poster{
		book:          book,
		legalEntityID: legalEntityID,
		bookID:        bookID,
		records:       make(map[string]Record),
		events:        make(map[string]appliedTransition),
	}, nil
}

func (poster *Poster) Apply(transition payment.Transition) ([]string, error) {
	if poster == nil || transition.Payment.PaymentID == "" ||
		transition.Payment.ProviderID == "" || transition.ProviderEventID == "" ||
		transition.EvidenceHash == "" || transition.OccurredAt.IsZero() ||
		transition.ReceivedAt.IsZero() || transition.Payment.Status != transition.To {
		return nil, ErrInvalidTransition
	}
	contentHash := hashJSON(transition)
	eventKey := transition.Payment.ProviderID + "\x00" + transition.ProviderEventID

	poster.mu.Lock()
	defer poster.mu.Unlock()
	if existing, exists := poster.events[eventKey]; exists {
		if existing.contentHash != contentHash {
			return nil, ErrTransitionConflict
		}
		return slices.Clone(existing.journalIDs), nil
	}

	record := cloneRecord(poster.records[transition.Payment.PaymentID])
	var journals []ledger.Journal
	switch transition.To {
	case payment.StatusProvisional:
		if transition.From != payment.StatusProcessing ||
			record.ProvisionalJournalID != "" {
			return nil, ErrInvalidTransition
		}
		journal := poster.provisionalJournal(transition)
		journals = []ledger.Journal{journal}
		record.PaymentID = transition.Payment.PaymentID
		record.ProvisionalJournalID = journal.ID
	case payment.StatusFinal:
		if transition.From != payment.StatusProvisional ||
			record.ProvisionalJournalID == "" || record.FinalJournalID != "" {
			return nil, ErrInvalidTransition
		}
		journal := poster.finalJournal(transition)
		journals = []ledger.Journal{journal}
		record.FinalJournalID = journal.ID
	case payment.StatusReversed:
		if len(record.ReversalJournalIDs) != 0 ||
			(transition.From != payment.StatusProvisional &&
				transition.From != payment.StatusFinal) {
			return nil, ErrInvalidTransition
		}
		targets := []string{record.ProvisionalJournalID}
		if transition.From == payment.StatusFinal {
			targets = []string{record.FinalJournalID, record.ProvisionalJournalID}
		}
		for _, target := range targets {
			if target == "" {
				return nil, ErrInvalidTransition
			}
			original, exists := poster.book.Get(target)
			if !exists {
				return nil, ErrInvalidTransition
			}
			journals = append(journals, poster.reversalJournal(transition, original))
		}
	default:
		return nil, ErrInvalidTransition
	}

	posted, err := poster.book.PostBatch(journals)
	if err != nil {
		return nil, err
	}
	journalIDs := make([]string, len(posted))
	for index, journal := range posted {
		journalIDs[index] = journal.ID
	}
	if transition.To == payment.StatusReversed {
		record.ReversalJournalIDs = slices.Clone(journalIDs)
	}
	poster.records[transition.Payment.PaymentID] = record
	poster.events[eventKey] = appliedTransition{
		contentHash: contentHash,
		journalIDs:  slices.Clone(journalIDs),
	}
	return journalIDs, nil
}

func (poster *Poster) Record(paymentID string) (Record, bool) {
	poster.mu.RLock()
	defer poster.mu.RUnlock()
	record, exists := poster.records[paymentID]
	return cloneRecord(record), exists
}

func (poster *Poster) provisionalJournal(transition payment.Transition) ledger.Journal {
	pendingAccount := "9140"
	if transition.Payment.Rail == payment.RailCard {
		pendingAccount = "9130"
	}
	return poster.journal(
		transition,
		"PAYMENT_PROVISIONAL",
		"provisional",
		[]ledger.Entry{
			poster.entry(transition, pendingAccount, ledger.Debit),
			poster.entry(transition, "9120", ledger.Credit),
		},
		"",
	)
}

func (poster *Poster) finalJournal(transition payment.Transition) ledger.Journal {
	settlementAccount := "1100"
	pendingAccount := "9140"
	if transition.Payment.Rail == payment.RailCard {
		settlementAccount = "1120"
		pendingAccount = "9130"
	}
	return poster.journal(
		transition,
		"PAYMENT_FINAL",
		"final",
		[]ledger.Entry{
			poster.entry(transition, settlementAccount, ledger.Debit),
			poster.entry(transition, pendingAccount, ledger.Credit),
		},
		"",
	)
}

func (poster *Poster) reversalJournal(
	transition payment.Transition,
	original ledger.PostedJournal,
) ledger.Journal {
	entries := make([]ledger.Entry, len(original.Entries))
	for index, entry := range original.Entries {
		if entry.Side == ledger.Debit {
			entry.Side = ledger.Credit
		} else {
			entry.Side = ledger.Debit
		}
		entries[index] = entry
	}
	stage := "provisional"
	if original.EntryType == "PAYMENT_FINAL" {
		stage = "final"
	}
	return poster.journal(
		transition,
		"PAYMENT_REVERSAL",
		stage+"-reversal",
		entries,
		original.ID,
	)
}

func (poster *Poster) journal(
	transition payment.Transition,
	entryType string,
	stage string,
	entries []ledger.Entry,
	reversalOf string,
) ledger.Journal {
	return ledger.Journal{
		ID:             "payment:" + transition.Payment.PaymentID + ":" + stage,
		LegalEntityID:  poster.legalEntityID,
		BookID:         poster.bookID,
		SourceSystem:   "payment-orchestrator",
		EntryType:      entryType,
		SourceEventID:  transition.Payment.ProviderID + ":" + transition.ProviderEventID,
		LoanID:         transition.Payment.LoanID,
		IdempotencyKey: "payment:" + transition.Payment.PaymentID + ":" + stage,
		CorrelationID:  transition.Payment.CorrelationID,
		EffectiveAt:    transition.OccurredAt.UTC(),
		Entries:        entries,
		EvidenceHash:   transition.EvidenceHash,
		ReversalOf:     reversalOf,
		Reason:         reversalReason(reversalOf),
	}
}

func (poster *Poster) entry(
	transition payment.Transition,
	account string,
	side ledger.Side,
) ledger.Entry {
	return ledger.Entry{
		AccountCode: account,
		Side:        side,
		AssetID:     transition.Payment.AssetID,
		Units:       transition.Payment.Units,
		PartyID:     transition.Payment.PayerReference,
		LoanID:      transition.Payment.LoanID,
	}
}

func reversalReason(reversalOf string) string {
	if reversalOf == "" {
		return ""
	}
	return "authenticated provider reversal"
}

type StatementKind string

const (
	StatementSettled  StatementKind = "SETTLED"
	StatementReversed StatementKind = "REVERSED"
)

type StatementEntry struct {
	EntryID           string
	ProviderID        string
	ProviderReference string
	PaymentID         string
	AssetID           string
	Units             string
	Kind              StatementKind
	OccurredAt        time.Time
}

type ReconciliationStatus string

const (
	ReconciliationMatched   ReconciliationStatus = "MATCHED"
	ReconciliationException ReconciliationStatus = "EXCEPTION"
)

type ReconciliationRun struct {
	RunID                string
	ProviderID           string
	AssetID              string
	AsOf                 time.Time
	ProviderSnapshotHash string
	LedgerSnapshotHash   string
	ExpectedUnits        string
	ObservedUnits        string
	DifferenceUnits      string
	UnmatchedItems       uint32
	Status               ReconciliationStatus
	Owner                string
	ResolutionDeadline   time.Time
	CreatedAt            time.Time
}

type Exception struct {
	ExceptionID        string
	RunID              string
	ProviderID         string
	AssetID            string
	DifferenceUnits    string
	UnmatchedItems     uint32
	ReasonCode         string
	Owner              string
	DetectedAt         time.Time
	ResolutionDeadline time.Time
}

type Resolution struct {
	ResolutionID        string
	ExceptionID         string
	EvidenceHash        string
	ResolutionJournalID string
	ResolvedBy          string
	ResolvedAt          time.Time
}

type Reconciler struct {
	mu          sync.RWMutex
	poster      *Poster
	runs        map[string]ReconciliationRun
	runHashes   map[string]string
	exceptions  map[string]Exception
	resolutions map[string]Resolution
}

func NewReconciler(poster *Poster) (*Reconciler, error) {
	if poster == nil {
		return nil, ErrInvalidReconciliation
	}
	return &Reconciler{
		poster:      poster,
		runs:        make(map[string]ReconciliationRun),
		runHashes:   make(map[string]string),
		exceptions:  make(map[string]Exception),
		resolutions: make(map[string]Resolution),
	}, nil
}

func (reconciler *Reconciler) Run(
	runID string,
	providerID string,
	assetID string,
	asOf time.Time,
	owner string,
	resolutionDeadline time.Time,
	payments []payment.Intent,
	statement []StatementEntry,
) (ReconciliationRun, error) {
	if reconciler == nil || runID == "" || providerID == "" || assetID == "" ||
		asOf.IsZero() || owner == "" || !resolutionDeadline.After(asOf) {
		return ReconciliationRun{}, ErrInvalidReconciliation
	}
	expected := new(big.Int)
	expectedByPayment := make(map[string]*big.Int)
	seenPayments := make(map[string]bool)
	ledgerEvidence := make([]string, 0)
	for _, intent := range payments {
		if intent.ProviderID != providerID || intent.AssetID != assetID ||
			intent.CreatedAt.After(asOf) {
			continue
		}
		if intent.PaymentID == "" || seenPayments[intent.PaymentID] {
			return ReconciliationRun{}, ErrInvalidReconciliation
		}
		seenPayments[intent.PaymentID] = true
		units, ok := canonicalInteger(intent.Units)
		if !ok || units.Sign() <= 0 {
			return ReconciliationRun{}, ErrInvalidReconciliation
		}
		if !intent.FinalizedAt.IsZero() && !intent.FinalizedAt.After(asOf) &&
			(intent.ReversedAt.IsZero() || intent.ReversedAt.After(asOf)) {
			if intent.ProviderReference == "" {
				return ReconciliationRun{}, ErrInvalidReconciliation
			}
			expected.Add(expected, units)
			expectedByPayment[reconciliationKey(
				intent.PaymentID,
				intent.ProviderReference,
			)] = new(big.Int).Set(units)
		}
		record, exists := reconciler.poster.Record(intent.PaymentID)
		if !exists {
			if !intent.ProvisionalAt.IsZero() && !intent.ProvisionalAt.After(asOf) {
				return ReconciliationRun{}, ErrInvalidReconciliation
			}
			continue
		}
		ids := []string{record.ProvisionalJournalID, record.FinalJournalID}
		ids = append(ids, record.ReversalJournalIDs...)
		for _, journalID := range ids {
			if journalID == "" {
				continue
			}
			journal, exists := reconciler.poster.book.Get(journalID)
			if !exists {
				return ReconciliationRun{}, ErrInvalidReconciliation
			}
			ledgerEvidence = append(ledgerEvidence, journal.ID+":"+journal.ContentHash)
		}
	}

	observed := new(big.Int)
	observedByPayment := make(map[string]*big.Int)
	statementEvidence := make([]StatementEntry, 0, len(statement))
	seenEntries := make(map[string]bool)
	for _, entry := range statement {
		if entry.EntryID == "" || entry.ProviderID != providerID ||
			entry.AssetID != assetID || entry.ProviderReference == "" ||
			entry.PaymentID == "" || entry.OccurredAt.IsZero() ||
			entry.OccurredAt.After(asOf) || seenEntries[entry.EntryID] {
			return ReconciliationRun{}, ErrInvalidReconciliation
		}
		seenEntries[entry.EntryID] = true
		units, ok := canonicalInteger(entry.Units)
		if !ok || units.Sign() <= 0 {
			return ReconciliationRun{}, ErrInvalidReconciliation
		}
		switch entry.Kind {
		case StatementSettled:
			observed.Add(observed, units)
			addUnits(
				observedByPayment,
				reconciliationKey(entry.PaymentID, entry.ProviderReference),
				units,
			)
		case StatementReversed:
			observed.Sub(observed, units)
			addUnits(
				observedByPayment,
				reconciliationKey(entry.PaymentID, entry.ProviderReference),
				new(big.Int).Neg(new(big.Int).Set(units)),
			)
		default:
			return ReconciliationRun{}, ErrInvalidReconciliation
		}
		statementEvidence = append(statementEvidence, entry)
	}
	if observed.Sign() < 0 {
		return ReconciliationRun{}, ErrInvalidReconciliation
	}
	slices.SortFunc(statementEvidence, func(left, right StatementEntry) int {
		if left.EntryID < right.EntryID {
			return -1
		}
		if left.EntryID > right.EntryID {
			return 1
		}
		return 0
	})
	slices.Sort(ledgerEvidence)
	difference := new(big.Int).Sub(new(big.Int).Set(observed), expected)
	unmatchedItems := mismatchCount(expectedByPayment, observedByPayment)
	status := ReconciliationMatched
	if difference.Sign() != 0 || unmatchedItems != 0 {
		status = ReconciliationException
	}
	run := ReconciliationRun{
		RunID:                runID,
		ProviderID:           providerID,
		AssetID:              assetID,
		AsOf:                 asOf.UTC(),
		ProviderSnapshotHash: hashJSON(statementEvidence),
		LedgerSnapshotHash:   hashJSON(ledgerEvidence),
		ExpectedUnits:        expected.String(),
		ObservedUnits:        observed.String(),
		DifferenceUnits:      difference.String(),
		UnmatchedItems:       unmatchedItems,
		Status:               status,
		Owner:                owner,
		ResolutionDeadline:   resolutionDeadline.UTC(),
		CreatedAt:            asOf.UTC(),
	}
	contentHash := hashJSON(run)

	reconciler.mu.Lock()
	defer reconciler.mu.Unlock()
	if existing, exists := reconciler.runs[runID]; exists {
		if reconciler.runHashes[runID] != contentHash {
			return ReconciliationRun{}, ErrReconciliationConflict
		}
		return existing, nil
	}
	reconciler.runs[runID] = run
	reconciler.runHashes[runID] = contentHash
	if status == ReconciliationException {
		exceptionID := runID + ":difference"
		reconciler.exceptions[exceptionID] = Exception{
			ExceptionID:        exceptionID,
			RunID:              runID,
			ProviderID:         providerID,
			AssetID:            assetID,
			DifferenceUnits:    difference.String(),
			UnmatchedItems:     unmatchedItems,
			ReasonCode:         "PROVIDER_LEDGER_MISMATCH",
			Owner:              owner,
			DetectedAt:         asOf.UTC(),
			ResolutionDeadline: resolutionDeadline.UTC(),
		}
	}
	return run, nil
}

func (reconciler *Reconciler) Resolve(
	exceptionID string,
	resolutionID string,
	evidenceHash string,
	resolutionJournalID string,
	resolvedBy string,
	resolvedAt time.Time,
) (Resolution, error) {
	if reconciler == nil || exceptionID == "" || resolutionID == "" ||
		evidenceHash == "" || resolvedBy == "" || resolvedAt.IsZero() {
		return Resolution{}, ErrInvalidResolution
	}
	reconciler.mu.Lock()
	defer reconciler.mu.Unlock()
	exception, exists := reconciler.exceptions[exceptionID]
	if !exists || resolvedAt.Before(exception.DetectedAt) {
		return Resolution{}, ErrInvalidResolution
	}
	if existing, exists := reconciler.resolutions[exceptionID]; exists {
		if existing.ResolutionID == resolutionID &&
			existing.EvidenceHash == evidenceHash &&
			existing.ResolutionJournalID == resolutionJournalID &&
			existing.ResolvedBy == resolvedBy &&
			existing.ResolvedAt.Equal(resolvedAt.UTC()) {
			return existing, nil
		}
		return Resolution{}, ErrInvalidResolution
	}
	if resolutionJournalID != "" {
		if _, exists := reconciler.poster.book.Get(resolutionJournalID); !exists {
			return Resolution{}, ErrInvalidResolution
		}
	}
	resolution := Resolution{
		ResolutionID:        resolutionID,
		ExceptionID:         exceptionID,
		EvidenceHash:        evidenceHash,
		ResolutionJournalID: resolutionJournalID,
		ResolvedBy:          resolvedBy,
		ResolvedAt:          resolvedAt.UTC(),
	}
	reconciler.resolutions[exceptionID] = resolution
	return resolution, nil
}

func (reconciler *Reconciler) Exception(exceptionID string) (Exception, bool) {
	reconciler.mu.RLock()
	defer reconciler.mu.RUnlock()
	exception, exists := reconciler.exceptions[exceptionID]
	return exception, exists
}

func (reconciler *Reconciler) Resolution(exceptionID string) (Resolution, bool) {
	reconciler.mu.RLock()
	defer reconciler.mu.RUnlock()
	resolution, exists := reconciler.resolutions[exceptionID]
	return resolution, exists
}

func AgingClass(detectedAt time.Time, asOf time.Time) (string, error) {
	if detectedAt.IsZero() || asOf.Before(detectedAt) {
		return "", ErrInvalidReconciliation
	}
	days := int(asOf.Sub(detectedAt) / (24 * time.Hour))
	switch {
	case days <= 1:
		return "0-1_DAY", nil
	case days <= 3:
		return "2-3_DAYS", nil
	case days <= 7:
		return "4-7_DAYS", nil
	case days <= 30:
		return "8-30_DAYS", nil
	default:
		return "OVER_30_DAYS", nil
	}
}

func cloneRecord(record Record) Record {
	record.ReversalJournalIDs = slices.Clone(record.ReversalJournalIDs)
	return record
}

func canonicalInteger(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.String() == value
}

func reconciliationKey(paymentID string, providerReference string) string {
	return paymentID + "\x00" + providerReference
}

func addUnits(target map[string]*big.Int, key string, units *big.Int) {
	if target[key] == nil {
		target[key] = new(big.Int)
	}
	target[key].Add(target[key], units)
}

func mismatchCount(expected map[string]*big.Int, observed map[string]*big.Int) uint32 {
	keys := make(map[string]bool, len(expected)+len(observed))
	for key := range expected {
		keys[key] = true
	}
	for key := range observed {
		keys[key] = true
	}
	var count uint32
	for key := range keys {
		expectedUnits := expected[key]
		if expectedUnits == nil {
			expectedUnits = new(big.Int)
		}
		observedUnits := observed[key]
		if observedUnits == nil {
			observedUnits = new(big.Int)
		}
		if expectedUnits.Cmp(observedUnits) != 0 {
			count++
		}
	}
	return count
}

func hashJSON(value any) string {
	encoded, _ := json.Marshal(value)
	hash := sha256.Sum256(encoded)
	return hex.EncodeToString(hash[:])
}
