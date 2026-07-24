package allocationaccounting

import (
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocation"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

func TestAllocationAndReversalJournalsBalanceAndLink(t *testing.T) {
	book := ledger.New()
	poster, err := New(book)
	if err != nil {
		t.Fatalf("new poster: %v", err)
	}
	now := time.Unix(1_760_100_000, 0).UTC()
	item := allocation.Allocation{
		AllocationID:          "allocation-001",
		PaymentID:             "payment-001",
		LoanID:                "loan-001",
		AssetID:               "asset:local:usd",
		GrossUnits:            "1250",
		PrincipalUnits:        "1000",
		RefundableExcessUnits: "250",
		CorrelationID:         "correlation-001",
		EvidenceHash:          "allocation-evidence",
		AllocatedAt:           now,
	}
	ids, err := poster.ApplyAllocation(item)
	if err != nil {
		t.Fatalf("post allocation: %v", err)
	}
	item.JournalIDs = ids
	if len(ids) != 2 || len(book.List()) != 2 {
		t.Fatal("allocation did not atomically post two journals")
	}
	first, _ := book.Get(ids[0])
	if len(first.Entries) != 3 || first.Entries[0].AccountCode != "9120" ||
		first.Entries[1].AccountCode != "1310" ||
		first.Entries[2].AccountCode != "2150" {
		t.Fatal("principal and refundable excess mapping is incorrect")
	}
	reversed, err := poster.ReverseAllocation(item, allocation.ReversalRequest{
		ReversalID:        "reversal-001",
		AllocationID:      item.AllocationID,
		PaymentID:         item.PaymentID,
		ProviderID:        "provider-local",
		ProviderReference: "provider-reference-001",
		Status:            payment.StatusReversed,
		ProviderEventID:   "provider-reversal-001",
		ReasonCode:        "SYNTHETIC_CHARGEBACK",
		EvidenceHash:      "reversal-evidence",
		ReversedAt:        now.Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("reverse allocation: %v", err)
	}
	if len(reversed) != 2 || len(book.List()) != 4 {
		t.Fatal("reversal did not atomically offset both journals")
	}
	for _, id := range reversed {
		journal, _ := book.Get(id)
		if journal.ReversalOf == "" {
			t.Fatal("reversal lost original journal linkage")
		}
	}
}
