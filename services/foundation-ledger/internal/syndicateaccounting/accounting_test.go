package syndicateaccounting

import (
	"errors"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

func TestCommitmentActivationDistributionAndTransferReconcile(t *testing.T) {
	book := ledger.New()
	accounting := New(book)
	effectiveAt := time.Unix(1_800_000_000, 0).UTC()
	base := BaseEvent{
		LoanID: "loan-001", AssetID: "asset:local:usdc", CorrelationID: "loan-001",
		EvidenceHash: "block:300:tx:1", Finality: "FINAL", EffectiveAt: effectiveAt,
	}
	commitment := Commitment{
		BaseEvent: base, CommitmentID: "commitment-001", LenderID: "lender-001", Units: "100",
	}
	commitment.EventID = "event-commitment-001"
	if _, err := accounting.PostCommitment(commitment); err != nil {
		t.Fatalf("post commitment: %v", err)
	}
	activation := Activation{
		BaseEvent: base, BorrowerID: "borrower-001", Units: "100",
		Positions: []PositionRight{
			{PositionID: "position-001", TrancheID: "senior", OwnerID: "lender-001", Units: "60"},
			{PositionID: "position-002", TrancheID: "junior", OwnerID: "lender-002", Units: "40"},
		},
	}
	activation.EventID = "event-activation-001"
	journals, err := accounting.PostActivation(activation)
	if err != nil || len(journals) != 2 {
		t.Fatalf("post activation: journals=%d err=%v", len(journals), err)
	}
	transfer := PositionTransfer{
		BaseEvent: base, TransferID: "transfer-001", PositionID: "position-003",
		SellerID: "lender-001", BuyerID: "buyer-001", TrancheID: "senior",
		ShareUnits: "40", ClaimUnits: "40", CutoffBlock: 500,
	}
	transfer.EventID = "event-transfer-001"
	if _, err := accounting.PostPositionTransfer(transfer); err != nil {
		t.Fatalf("post position transfer: %v", err)
	}
	distribution := Distribution{
		BaseEvent: base, PaymentID: "payment-001", BorrowerID: "borrower-001", Units: "70",
		Allocations: []Allocation{
			{
				PositionID: "position-001", TrancheID: "senior",
				OwnerID: "lender-001", Units: "20",
			},
			{
				PositionID: "position-003", TrancheID: "senior",
				OwnerID: "buyer-001", Units: "40",
			},
			{
				PositionID: "position-002", TrancheID: "junior",
				OwnerID: "lender-002", Units: "10",
			},
		},
	}
	distribution.EventID = "event-distribution-001"
	first, err := accounting.PostDistribution(distribution)
	if err != nil {
		t.Fatalf("post distribution: %v", err)
	}
	replayed, err := accounting.PostDistribution(distribution)
	if err != nil || replayed.ContentHash != first.ContentHash ||
		!replayed.PostedAt.Equal(first.PostedAt) {
		t.Fatalf("distribution replay was not idempotent: %v", err)
	}
	if len(book.List()) != 5 {
		t.Fatalf("expected five balanced journals, got %d", len(book.List()))
	}
}

func TestFailedRoundRefundAndInvalidDistribution(t *testing.T) {
	book := ledger.New()
	accounting := New(book)
	base := BaseEvent{
		EventID: "event-refund-001", LoanID: "loan-001", AssetID: "asset:local:usdc",
		CorrelationID: "loan-001", EvidenceHash: "block:301:tx:1", Finality: "FINAL",
		EffectiveAt: time.Unix(1_800_000_000, 0).UTC(),
	}
	if _, err := accounting.PostRefund(Refund{
		BaseEvent: base, CommitmentID: "commitment-001", LenderID: "lender-001", Units: "50",
	}); err != nil {
		t.Fatalf("post refund: %v", err)
	}
	base.EventID = "event-activation-invalid"
	if _, err := accounting.PostActivation(Activation{
		BaseEvent: base, BorrowerID: "borrower-001", Units: "100",
		Positions: []PositionRight{{
			PositionID: "position-001", TrancheID: "senior",
			OwnerID: "lender-001", Units: "99",
		}},
	}); !errors.Is(err, ErrInvalidEvent) {
		t.Fatalf("expected activated-right conservation rejection, got %v", err)
	}
	base.EventID = "event-distribution-001"
	_, err := accounting.PostDistribution(Distribution{
		BaseEvent: base, PaymentID: "payment-001", BorrowerID: "borrower-001", Units: "70",
		Allocations: []Allocation{
			{
				PositionID: "position-001", TrancheID: "senior",
				OwnerID: "lender-001", Units: "69",
			},
		},
	})
	if !errors.Is(err, ErrInvalidEvent) {
		t.Fatalf("expected distribution conservation rejection, got %v", err)
	}
	base.Finality = "PROVISIONAL"
	if _, err := accounting.PostRefund(Refund{
		BaseEvent: base, CommitmentID: "commitment-002", LenderID: "lender-002", Units: "50",
	}); !errors.Is(err, ErrInvalidEvent) {
		t.Fatalf("expected provisional refund rejection, got %v", err)
	}
}
