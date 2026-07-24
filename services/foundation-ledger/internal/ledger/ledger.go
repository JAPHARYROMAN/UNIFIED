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
}

type Journal struct {
	ID             string    `json:"id"`
	LegalEntityID  string    `json:"legal_entity_id"`
	BookID         string    `json:"book_id"`
	SourceSystem   string    `json:"source_system"`
	IdempotencyKey string    `json:"idempotency_key"`
	EffectiveAt    time.Time `json:"effective_at"`
	Entries        []Entry   `json:"entries"`
	EvidenceHash   string    `json:"evidence_hash"`
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
}

func New() *Ledger {
	return &Ledger{
		byID:        make(map[string]PostedJournal),
		idempotency: make(map[string]string),
	}
}

func (l *Ledger) Post(journal Journal) (PostedJournal, error) {
	contentHash, err := validateAndHash(journal)
	if err != nil {
		return PostedJournal{}, err
	}
	scope := journal.LegalEntityID + "\x00" + journal.SourceSystem + "\x00" + journal.IdempotencyKey

	l.mu.Lock()
	defer l.mu.Unlock()
	if existingHash, ok := l.idempotency[scope]; ok {
		if existingHash != contentHash {
			return PostedJournal{}, ErrIdempotencyConflict
		}
		for _, existing := range l.byID {
			if existing.ContentHash == contentHash {
				return clone(existing), nil
			}
		}
	}
	if _, exists := l.byID[journal.ID]; exists {
		return PostedJournal{}, fmt.Errorf("%w: duplicate journal id", ErrInvalidJournal)
	}
	posted := PostedJournal{
		Journal:     copyJournal(journal),
		ContentHash: contentHash,
		PostedAt:    time.Now().UTC(),
	}
	l.byID[journal.ID] = posted
	l.idempotency[scope] = contentHash
	return clone(posted), nil
}

func (l *Ledger) Get(id string) (PostedJournal, bool) {
	l.mu.RLock()
	defer l.mu.RUnlock()
	journal, ok := l.byID[id]
	return clone(journal), ok
}

func validateAndHash(journal Journal) (string, error) {
	if journal.ID == "" || journal.LegalEntityID == "" || journal.BookID == "" ||
		journal.SourceSystem == "" || journal.IdempotencyKey == "" {
		return "", fmt.Errorf("%w: required identity field is empty", ErrInvalidJournal)
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

