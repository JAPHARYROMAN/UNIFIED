// Package allocationaccounting posts synthetic Phase 7B allocation and reversal journals.
package allocationaccounting

import (
	"errors"
	"math/big"
	"slices"
	"sync"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocation"
)

var ErrInvalidAllocation = errors.New("invalid allocation accounting")

type record struct {
	journalIDs []string
	reversed   bool
}

type Poster struct {
	mu      sync.Mutex
	book    *ledger.Ledger
	records map[string]record
}

func New(book *ledger.Ledger) (*Poster, error) {
	if book == nil {
		return nil, ErrInvalidAllocation
	}
	return &Poster{book: book, records: make(map[string]record)}, nil
}

func (poster *Poster) ApplyAllocation(item allocation.Allocation) ([]string, error) {
	if poster == nil || item.AllocationID == "" || item.PaymentID == "" ||
		item.LoanID == "" || item.AssetID == "" || item.CorrelationID == "" ||
		item.EvidenceHash == "" || item.AllocatedAt.IsZero() {
		return nil, ErrInvalidAllocation
	}
	gross, grossOK := nonNegative(item.GrossUnits)
	principal, principalOK := nonNegative(item.PrincipalUnits)
	excess, excessOK := nonNegative(item.RefundableExcessUnits)
	if !grossOK || !principalOK || !excessOK || principal.Sign() <= 0 ||
		new(big.Int).Add(new(big.Int).Set(principal), excess).Cmp(gross) != 0 {
		return nil, ErrInvalidAllocation
	}
	poster.mu.Lock()
	defer poster.mu.Unlock()
	if existing, exists := poster.records[item.AllocationID]; exists {
		return slices.Clone(existing.journalIDs), nil
	}
	allocationEntries := []ledger.Entry{entry(item, "9120", ledger.Debit, item.GrossUnits)}
	allocationEntries = append(
		allocationEntries,
		entry(item, "1310", ledger.Credit, item.PrincipalUnits),
	)
	if excess.Sign() > 0 {
		allocationEntries = append(
			allocationEntries,
			entry(item, "2150", ledger.Credit, item.RefundableExcessUnits),
		)
	}
	journals := []ledger.Journal{
		journal(item, "allocation", "PAYMENT_ALLOCATED", allocationEntries, ""),
		journal(item, "lender-claim", "LENDER_CLAIM_ALLOCATED", []ledger.Entry{
			entry(item, "2310", ledger.Debit, item.PrincipalUnits),
			entry(item, "2130", ledger.Credit, item.PrincipalUnits),
		}, ""),
	}
	posted, err := poster.book.PostBatch(journals)
	if err != nil {
		return nil, err
	}
	ids := []string{posted[0].ID, posted[1].ID}
	poster.records[item.AllocationID] = record{journalIDs: slices.Clone(ids)}
	return ids, nil
}

func (poster *Poster) ReverseAllocation(
	item allocation.Allocation,
	request allocation.ReversalRequest,
) ([]string, error) {
	if poster == nil || request.ReversalID == "" || request.ProviderEventID == "" ||
		request.EvidenceHash == "" || request.ReversedAt.IsZero() {
		return nil, ErrInvalidAllocation
	}
	poster.mu.Lock()
	defer poster.mu.Unlock()
	stored, exists := poster.records[item.AllocationID]
	if !exists || stored.reversed || !slices.Equal(stored.journalIDs, item.JournalIDs) {
		return nil, ErrInvalidAllocation
	}
	journals := make([]ledger.Journal, 0, len(stored.journalIDs))
	for _, journalID := range stored.journalIDs {
		original, exists := poster.book.Get(journalID)
		if !exists {
			return nil, ErrInvalidAllocation
		}
		entries := make([]ledger.Entry, len(original.Entries))
		for index, line := range original.Entries {
			if line.Side == ledger.Debit {
				line.Side = ledger.Credit
			} else {
				line.Side = ledger.Debit
			}
			entries[index] = line
		}
		journals = append(journals, ledger.Journal{
			ID:             original.ID + ":reversal",
			LegalEntityID:  original.LegalEntityID,
			BookID:         original.BookID,
			SourceSystem:   "payment-allocation",
			EntryType:      "PAYMENT_ALLOCATION_REVERSAL",
			SourceEventID:  request.ProviderEventID,
			LoanID:         item.LoanID,
			IdempotencyKey: request.ReversalID + ":" + original.ID,
			CorrelationID:  item.CorrelationID,
			EffectiveAt:    request.ReversedAt.UTC(),
			Entries:        entries,
			EvidenceHash:   request.EvidenceHash,
			ReversalOf:     original.ID,
			Reason:         request.ReasonCode,
		})
	}
	posted, err := poster.book.PostBatch(journals)
	if err != nil {
		return nil, err
	}
	ids := make([]string, len(posted))
	for index, result := range posted {
		ids[index] = result.ID
	}
	stored.reversed = true
	poster.records[item.AllocationID] = stored
	return ids, nil
}

func journal(
	item allocation.Allocation,
	suffix string,
	entryType string,
	entries []ledger.Entry,
	reversalOf string,
) ledger.Journal {
	return ledger.Journal{
		ID:             "allocation:" + item.AllocationID + ":" + suffix,
		LegalEntityID:  "unified-protocol",
		BookID:         "loan-subledger",
		SourceSystem:   "payment-allocation",
		EntryType:      entryType,
		SourceEventID:  item.PaymentID,
		LoanID:         item.LoanID,
		IdempotencyKey: item.AllocationID + ":" + suffix,
		CorrelationID:  item.CorrelationID,
		EffectiveAt:    item.AllocatedAt.UTC(),
		Entries:        entries,
		EvidenceHash:   item.EvidenceHash,
		ReversalOf:     reversalOf,
	}
}

func entry(
	item allocation.Allocation,
	account string,
	side ledger.Side,
	units string,
) ledger.Entry {
	return ledger.Entry{
		AccountCode: account,
		Side:        side,
		AssetID:     item.AssetID,
		Units:       units,
		LoanID:      item.LoanID,
	}
}

func nonNegative(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.Sign() >= 0 && parsed.String() == value
}
