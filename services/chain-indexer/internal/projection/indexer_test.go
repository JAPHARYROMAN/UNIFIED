package projection

import (
	"reflect"
	"testing"
)

func canonicalBlocks() []Block {
	return []Block{
		{
			Number: 1,
			Hash:   "block-1",
			Events: []Event{{
				ID: "event-tender", Type: TenderPublished, TxHash: "tx-1",
				TenderID: "tender-1", BorrowerID: "borrower-1",
			}},
		},
		{
			Number: 2, Hash: "block-2", ParentHash: "block-1",
			Events: []Event{
				{
					ID: "event-offer", Type: OfferSelected, TxHash: "tx-2",
					TenderID: "tender-1", OfferID: "offer-1",
				},
				{
					ID: "event-activation", Type: LoanActivated, TxHash: "tx-2",
					LoanID: "loan-1", BorrowerID: "borrower-1", LenderID: "lender-1",
					AssetID: "asset:local:usdc", AmountUnits: "1000",
				},
			},
		},
		{
			Number: 3, Hash: "block-3", ParentHash: "block-2",
			Events: []Event{{
				ID: "event-payment", Type: PrincipalRepaid, TxHash: "tx-3",
				LoanID: "loan-1", PaymentID: "payment-1", AmountUnits: "1000",
			}, {
				ID: "event-close", Type: LoanClosed, TxHash: "tx-3", LoanID: "loan-1",
			}},
		},
	}
}

func TestRebuildReproducesTheSameProjection(t *testing.T) {
	indexer := New(1)
	for _, block := range canonicalBlocks() {
		if err := indexer.Ingest(block); err != nil {
			t.Fatalf("ingest block %d: %v", block.Number, err)
		}
	}
	before := indexer.Snapshot()
	if err := indexer.Rebuild(); err != nil {
		t.Fatalf("rebuild: %v", err)
	}
	after := indexer.Snapshot()
	if !reflect.DeepEqual(before, after) {
		t.Fatalf("projection changed during rebuild\nbefore: %#v\nafter: %#v", before, after)
	}
	if after.Loans["loan-1"].Status != "CLOSED" ||
		after.Loans["loan-1"].OutstandingUnits != "0" {
		t.Fatal("canonical loan did not close")
	}
}

func TestReorgRollsBackOrphanedPayments(t *testing.T) {
	indexer := New(1)
	blocks := canonicalBlocks()
	for _, block := range blocks {
		if err := indexer.Ingest(block); err != nil {
			t.Fatalf("ingest block %d: %v", block.Number, err)
		}
	}
	replacement := Block{
		Number: 3, Hash: "block-3b", ParentHash: "block-2",
		Events: []Event{{
			ID: "event-payment-b", Type: PrincipalRepaid, TxHash: "tx-3b",
			LoanID: "loan-1", PaymentID: "payment-b", AmountUnits: "400",
		}},
	}
	if err := indexer.Ingest(replacement); err != nil {
		t.Fatalf("ingest replacement: %v", err)
	}
	loan := indexer.Snapshot().Loans["loan-1"]
	if loan.Status != "ACTIVE" || loan.OutstandingUnits != "600" ||
		loan.LastPaymentID != "payment-b" {
		t.Fatalf("orphaned state was not rolled back: %#v", loan)
	}
}

func TestUnknownParentIsRejectedWithoutChangingProjection(t *testing.T) {
	indexer := New(2)
	if err := indexer.Ingest(canonicalBlocks()[0]); err != nil {
		t.Fatalf("ingest genesis: %v", err)
	}
	before := indexer.Snapshot()
	err := indexer.Ingest(Block{Number: 2, Hash: "bad", ParentHash: "unknown"})
	if err != ErrUnknownParent {
		t.Fatalf("expected unknown parent, got %v", err)
	}
	if !reflect.DeepEqual(before, indexer.Snapshot()) {
		t.Fatal("invalid block changed the projection")
	}
}
