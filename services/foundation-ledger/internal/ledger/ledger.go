// Package ledger provides a foundation-only, in-memory double-entry posting
// kernel. It demonstrates invariants without implementing production accounting.
package ledger

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"sync"
	"time"
)

var (
	ErrInvalidJournal      = errors.New("invalid journal")
	ErrUnbalancedJournal   = errors.New("journal is not balanced by asset")
	ErrIdempotencyConflict = errors.New("idempotency key was reused with different content")
	ErrAlreadyReversed     = errors.New("journal already has a posted reversal")
	ErrUnknownJournal      = errors.New("journal does not exist")
)

type Side string

const (
	Debit  Side = "DEBIT"
	Credit Side = "CREDIT"
)

type Entry struct {
	AccountCode string `json:"account_code"`
	Side        Side   `json:"side"`
	AssetID     string `json:"asset_id"`
	Units       string `json:"units"`
	PartyID     string `json:"party_id,omitempty"`
	LoanID      string `json:"loan_id,omitempty"`
}

type Journal struct {
	ID             string    `json:"id"`
	LegalEntityID  string    `json:"legal_entity_id"`
	BookID         string    `json:"book_id"`
	SourceSystem   string    `json:"source_system"`
	EntryType      string    `json:"entry_type"`
	SourceEventID  string    `json:"source_event_id"`
	LoanID         string    `json:"loan_id,omitempty"`
	IdempotencyKey string    `json:"idempotency_key"`
	CorrelationID  string    `json:"correlation_id"`
	EffectiveAt    time.Time `json:"effective_at"`
	Entries        []Entry   `json:"entries"`
	EvidenceHash   string    `json:"evidence_hash"`
	ReversalOf     string    `json:"reversal_of,omitempty"`
	Reason         string    `json:"reason,omitempty"`
}

type PostedJournal struct {
	Journal
	ContentHash string
	PostedAt    time.Time
}

type Ledger struct {
	mu          sync.RWMutex
	byID        map[string]PostedJournal
	idempotency map[string]string
	reversals   map[string]string
}

func New() *Ledger {
	return &Ledger{
		byID:        make(map[string]PostedJournal),
		idempotency: make(map[string]string),
		reversals:   make(map[string]string),
	}
}

func (l *Ledger) Post(journal Journal) (PostedJournal, error) {
	contentHash, err := validateAndHash(journal)
	if err != nil {
		return PostedJournal{}, err
	}

	l.mu.Lock()
	defer l.mu.Unlock()
	return postValidated(journal, contentHash, time.Now().UTC(), l.byID, l.idempotency, l.reversals)
}

// PostBatch validates and commits related journals as one in-memory transaction.
func (l *Ledger) PostBatch(journals []Journal) ([]PostedJournal, error) {
	if len(journals) == 0 {
		return nil, fmt.Errorf("%w: empty batch", ErrInvalidJournal)
	}
	contentHashes := make([]string, len(journals))
	for index, journal := range journals {
		contentHash, err := validateAndHash(journal)
		if err != nil {
			return nil, err
		}
		contentHashes[index] = contentHash
	}

	l.mu.Lock()
	defer l.mu.Unlock()
	byID := cloneJournalMap(l.byID)
	idempotency := cloneStringMap(l.idempotency)
	reversals := cloneStringMap(l.reversals)
	postedAt := time.Now().UTC()
	result := make([]PostedJournal, 0, len(journals))
	for index, journal := range journals {
		posted, err := postValidated(
			journal,
			contentHashes[index],
			postedAt,
			byID,
			idempotency,
			reversals,
		)
		if err != nil {
			return nil, err
		}
		result = append(result, posted)
	}
	l.byID = byID
	l.idempotency = idempotency
	l.reversals = reversals
	return result, nil
}

func postValidated(
	journal Journal,
	contentHash string,
	postedAt time.Time,
	byID map[string]PostedJournal,
	idempotency map[string]string,
	reversals map[string]string,
) (PostedJournal, error) {
	scope := journal.LegalEntityID + "\x00" + journal.SourceSystem + "\x00" + journal.IdempotencyKey
	if existingID, ok := idempotency[scope]; ok {
		existing := byID[existingID]
		if existing.ContentHash != contentHash {
			return PostedJournal{}, ErrIdempotencyConflict
		}
		return clone(existing), nil
	}
	if _, exists := byID[journal.ID]; exists {
		return PostedJournal{}, fmt.Errorf("%w: duplicate journal id", ErrInvalidJournal)
	}
	if journal.ReversalOf != "" {
		if _, exists := byID[journal.ReversalOf]; !exists {
			return PostedJournal{}, fmt.Errorf("%w: reversal target %s", ErrUnknownJournal, journal.ReversalOf)
		}
		if existingID, exists := reversals[journal.ReversalOf]; exists {
			return PostedJournal{}, fmt.Errorf("%w: %s", ErrAlreadyReversed, existingID)
		}
	}
	posted := PostedJournal{
		Journal:     copyJournal(journal),
		ContentHash: contentHash,
		PostedAt:    postedAt,
	}
	byID[journal.ID] = posted
	idempotency[scope] = journal.ID
	if journal.ReversalOf != "" {
		reversals[journal.ReversalOf] = journal.ID
	}
	return clone(posted), nil
}

func (l *Ledger) Get(id string) (PostedJournal, bool) {
	l.mu.RLock()
	defer l.mu.RUnlock()
	journal, ok := l.byID[id]
	return clone(journal), ok
}

func (l *Ledger) List() []PostedJournal {
	l.mu.RLock()
	defer l.mu.RUnlock()
	result := make([]PostedJournal, 0, len(l.byID))
	for _, journal := range l.byID {
		result = append(result, clone(journal))
	}
	return result
}

func (l *Ledger) Reverse(
	originalID string,
	reversalID string,
	idempotencyKey string,
	sourceEventID string,
	reason string,
	effectiveAt time.Time,
) (PostedJournal, error) {
	original, ok := l.Get(originalID)
	if !ok {
		return PostedJournal{}, fmt.Errorf("%w: %s", ErrUnknownJournal, originalID)
	}
	entries := make([]Entry, len(original.Entries))
	for index, entry := range original.Entries {
		if entry.Side == Debit {
			entry.Side = Credit
		} else {
			entry.Side = Debit
		}
		entries[index] = entry
	}
	return l.Post(Journal{
		ID:             reversalID,
		LegalEntityID:  original.LegalEntityID,
		BookID:         original.BookID,
		SourceSystem:   original.SourceSystem,
		EntryType:      "REVERSAL",
		SourceEventID:  sourceEventID,
		LoanID:         original.LoanID,
		IdempotencyKey: idempotencyKey,
		CorrelationID:  original.CorrelationID,
		EffectiveAt:    effectiveAt,
		Entries:        entries,
		EvidenceHash:   original.EvidenceHash,
		ReversalOf:     original.ID,
		Reason:         reason,
	})
}

func validateAndHash(journal Journal) (string, error) {
	if journal.ID == "" || journal.LegalEntityID == "" || journal.BookID == "" ||
		journal.SourceSystem == "" || journal.EntryType == "" ||
		journal.SourceEventID == "" || journal.IdempotencyKey == "" ||
		journal.CorrelationID == "" || journal.EvidenceHash == "" ||
		journal.EffectiveAt.IsZero() {
		return "", fmt.Errorf("%w: required identity field is empty", ErrInvalidJournal)
	}
	if journal.ReversalOf == journal.ID {
		return "", fmt.Errorf("%w: journal cannot reverse itself", ErrInvalidJournal)
	}
	if len(journal.Entries) < 2 {
		return "", fmt.Errorf("%w: at least two entries are required", ErrInvalidJournal)
	}
	debits := make(map[string]*big.Int)
	credits := make(map[string]*big.Int)
	for index, entry := range journal.Entries {
		if entry.AccountCode == "" || entry.AssetID == "" {
			return "", fmt.Errorf("%w: entry %d has an empty account or asset", ErrInvalidJournal, index)
		}
		units, ok := new(big.Int).SetString(entry.Units, 10)
		if !ok || units.Sign() <= 0 {
			return "", fmt.Errorf("%w: entry %d units must be a positive integer", ErrInvalidJournal, index)
		}
		switch entry.Side {
		case Debit:
			add(debits, entry.AssetID, units)
		case Credit:
			add(credits, entry.AssetID, units)
		default:
			return "", fmt.Errorf("%w: entry %d has an invalid side", ErrInvalidJournal, index)
		}
	}
	for assetID, debit := range debits {
		credit := credits[assetID]
		if credit == nil || debit.Cmp(credit) != 0 {
			return "", fmt.Errorf("%w: asset %s", ErrUnbalancedJournal, assetID)
		}
	}
	for assetID := range credits {
		if debits[assetID] == nil {
			return "", fmt.Errorf("%w: asset %s", ErrUnbalancedJournal, assetID)
		}
	}
	encoded, err := json.Marshal(journal)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrInvalidJournal, err)
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}

func add(totals map[string]*big.Int, assetID string, units *big.Int) {
	if totals[assetID] == nil {
		totals[assetID] = new(big.Int)
	}
	totals[assetID].Add(totals[assetID], units)
}

func copyJournal(journal Journal) Journal {
	copied := journal
	copied.Entries = append([]Entry(nil), journal.Entries...)
	return copied
}

func clone(posted PostedJournal) PostedJournal {
	posted.Journal = copyJournal(posted.Journal)
	return posted
}

func cloneJournalMap(source map[string]PostedJournal) map[string]PostedJournal {
	result := make(map[string]PostedJournal, len(source))
	for key, value := range source {
		result[key] = clone(value)
	}
	return result
}

func cloneStringMap(source map[string]string) map[string]string {
	result := make(map[string]string, len(source))
	for key, value := range source {
		result[key] = value
	}
	return result
}
