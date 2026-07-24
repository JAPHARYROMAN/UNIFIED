package loanaccounting

import (
	"errors"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

func TestActivationRepaymentAndReplayReconcile(t *testing.T) {
	book := ledger.New()
	accounting := New(book)
	activatedAt := time.Unix(1_800_000_000, 0).UTC()
	activation := Activation{
		EventID:             "event-activation-001",
		LoanID:              "loan-001",
		BorrowerID:          "borrower-001",
		LenderID:            "lender-001",
		AssetID:             "asset:local:usdc",
		PrincipalUnits:      "1000000000",
		OriginationFeeUnits: "10000000",
		CorrelationID:       "loan-001",
		EvidenceHash:        "block:100:tx:1",
		Finality:            "FINAL",
		EffectiveAt:         activatedAt,
	}
	journals, err := accounting.PostActivation(activation)
	if err != nil {
		t.Fatalf("post activation: %v", err)
	}
	if len(journals) != 2 {
		t.Fatalf("expected obligation and fee journals, got %d", len(journals))
	}
	replayed, err := accounting.PostActivation(activation)
	if err != nil {
		t.Fatalf("replay activation: %v", err)
	}
	if replayed[0].ContentHash != journals[0].ContentHash ||
		!replayed[0].PostedAt.Equal(journals[0].PostedAt) {
		t.Fatal("activation replay did not return the original posting")
	}

	repayment := PrincipalRepayment{
		EventID:       "event-payment-001",
		PaymentID:     "payment-001",
		LoanID:        "loan-001",
		BorrowerID:    "borrower-001",
		LenderID:      "lender-001",
		AssetID:       "asset:local:usdc",
		Units:         "1000000000",
		CorrelationID: "loan-001",
		EvidenceHash:  "block:101:tx:1",
		Finality:      "FINAL",
		EffectiveAt:   activatedAt.Add(time.Hour),
	}
	first, err := accounting.PostPrincipalRepayment(repayment)
	if err != nil {
		t.Fatalf("post repayment: %v", err)
	}
	second, err := accounting.PostPrincipalRepayment(repayment)
	if err != nil {
		t.Fatalf("replay repayment: %v", err)
	}
	if first.ContentHash != second.ContentHash || !first.PostedAt.Equal(second.PostedAt) {
		t.Fatal("repayment was not idempotent")
	}
	if len(book.List()) != 3 {
		t.Fatalf("expected three authoritative journals, got %d", len(book.List()))
	}
}

func TestPaymentIdentifierCannotBeReusedForDifferentAmount(t *testing.T) {
	book := ledger.New()
	accounting := New(book)
	event := PrincipalRepayment{
		EventID:       "event-payment-001",
		PaymentID:     "payment-001",
		LoanID:        "loan-001",
		BorrowerID:    "borrower-001",
		LenderID:      "lender-001",
		AssetID:       "asset:local:usdc",
		Units:         "100",
		CorrelationID: "loan-001",
		EvidenceHash:  "block:101:tx:1",
		Finality:      "FINAL",
		EffectiveAt:   time.Unix(1_800_000_000, 0).UTC(),
	}
	if _, err := accounting.PostPrincipalRepayment(event); err != nil {
		t.Fatalf("first payment: %v", err)
	}
	event.Units = "101"
	if _, err := accounting.PostPrincipalRepayment(event); !errors.Is(err, ledger.ErrIdempotencyConflict) {
		t.Fatalf("expected idempotency conflict, got %v", err)
	}
}

func TestProvisionalChainEventCannotPostAuthoritativeAccounting(t *testing.T) {
	book := ledger.New()
	accounting := New(book)
	_, err := accounting.PostPrincipalRepayment(PrincipalRepayment{
		EventID: "event-payment-001", PaymentID: "payment-001", LoanID: "loan-001",
		BorrowerID: "borrower-001", LenderID: "lender-001", AssetID: "asset:local:usdc",
		Units: "100", CorrelationID: "loan-001", EvidenceHash: "provisional",
		Finality: "PROVISIONAL", EffectiveAt: time.Unix(1_800_000_000, 0).UTC(),
	})
	if !errors.Is(err, ErrInvalidEvent) {
		t.Fatalf("expected provisional event rejection, got %v", err)
	}
	if len(book.List()) != 0 {
		t.Fatal("provisional event changed the authoritative ledger")
	}
}
