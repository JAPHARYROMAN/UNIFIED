package allocation

import (
	"errors"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

type accountingStub struct {
	fail        bool
	allocations int
	reversals   int
}

func (stub *accountingStub) ApplyAllocation(Allocation) ([]string, error) {
	if stub.fail {
		stub.fail = false
		return nil, errors.New("synthetic outage")
	}
	stub.allocations++
	return []string{"journal-allocation", "journal-lender"}, nil
}

func (stub *accountingStub) ReverseAllocation(
	Allocation,
	ReversalRequest,
) ([]string, error) {
	if stub.fail {
		stub.fail = false
		return nil, errors.New("synthetic outage")
	}
	stub.reversals++
	return []string{"journal-allocation-reversal", "journal-lender-reversal"}, nil
}

func fixture(t *testing.T, debt string) (*Engine, *accountingStub, time.Time) {
	t.Helper()
	now := time.Unix(1_760_000_000, 0).UTC()
	stub := &accountingStub{}
	engine, err := New([]Obligation{{
		LoanID:                    "loan-001",
		BorrowerID:                "borrower-001",
		LenderID:                  "lender-001",
		AssetID:                   "asset:local:usd",
		OutstandingPrincipalUnits: debt,
		Version:                   1,
		SourceAuthority:           "SYNTHETIC_LOAN_SNAPSHOT",
		SourceEvidenceHash:        "snapshot-evidence",
		AsOf:                      now,
	}}, stub)
	if err != nil {
		t.Fatalf("new allocation engine: %v", err)
	}
	return engine, stub, now
}

func request(now time.Time, units string) Request {
	result := Request{
		Payment: FinalPayment{
			PaymentID:          "payment-001",
			ProviderID:         "provider-local",
			ProviderReference:  "provider-reference-001",
			AssetID:            "asset:local:usd",
			Units:              units,
			Status:             payment.StatusFinal,
			ReconciliationID:   "reconciliation-001",
			DifferenceUnits:    "0",
			FinalityPolicyHash: "finality-policy-v1",
			ReversalDeadline:   now.Add(24 * time.Hour),
			EvidenceHash:       "payment-evidence",
			FinalizedAt:        now.Add(time.Hour),
		},
		LoanID:                    "loan-001",
		ExpectedObligationVersion: 1,
		WaterfallPolicyHash:       "principal-then-excess-v1",
		CorrelationID:             "correlation-001",
		EvidenceHash:              "allocation-evidence",
		AllocatedAt:               now.Add(2 * time.Hour),
	}
	result.AllocationID = CalculateAllocationID(result)
	return result
}

func TestPartialAllocationAndReplay(t *testing.T) {
	engine, stub, now := fixture(t, "1000")
	input := request(now, "400")
	first, err := engine.Allocate(input)
	if err != nil {
		t.Fatalf("allocate: %v", err)
	}
	second, err := engine.Allocate(input)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	obligation, _ := engine.Obligation("loan-001")
	if first.PrincipalUnits != "400" || first.RefundableExcessUnits != "0" ||
		first.DebtAfterUnits != "600" || second.AllocationID != first.AllocationID ||
		obligation.OutstandingPrincipalUnits != "600" || stub.allocations != 1 {
		t.Fatal("partial allocation or replay violated conservation")
	}
}

func TestOverpaymentBecomesRefundableCredit(t *testing.T) {
	engine, _, now := fixture(t, "1000")
	item, err := engine.Allocate(request(now, "1250"))
	if err != nil {
		t.Fatalf("allocate overpayment: %v", err)
	}
	if item.PrincipalUnits != "1000" || item.RefundableExcessUnits != "250" ||
		item.DebtAfterUnits != "0" {
		t.Fatal("overpayment was not split into principal and refundable credit")
	}
	if engine.ReleaseEligible(item.AllocationID, now.Add(23*time.Hour)) ||
		!engine.ReleaseEligible(item.AllocationID, now.Add(25*time.Hour)) {
		t.Fatal("release evidence ignored the reversal-risk deadline")
	}
}

func TestFinalityReconciliationVersionAndAssetFailClosed(t *testing.T) {
	cases := []func(*Request){
		func(value *Request) { value.Payment.Status = payment.StatusProvisional },
		func(value *Request) { value.Payment.DifferenceUnits = "1" },
		func(value *Request) { value.Payment.UnmatchedItems = 1 },
		func(value *Request) { value.ExpectedObligationVersion = 2 },
		func(value *Request) { value.Payment.AssetID = "asset:local:other" },
	}
	for index, mutate := range cases {
		engine, stub, now := fixture(t, "1000")
		input := request(now, "400")
		mutate(&input)
		input.AllocationID = CalculateAllocationID(input)
		if _, err := engine.Allocate(input); !errors.Is(err, ErrInvalidAllocation) {
			t.Fatalf("case %d expected rejection, got %v", index, err)
		}
		obligation, _ := engine.Obligation("loan-001")
		if obligation.OutstandingPrincipalUnits != "1000" || stub.allocations != 0 {
			t.Fatalf("case %d left a partial effect", index)
		}
	}
}

func TestAccountingOutageLeavesStateRetryable(t *testing.T) {
	engine, stub, now := fixture(t, "1000")
	input := request(now, "400")
	stub.fail = true
	if _, err := engine.Allocate(input); !errors.Is(err, ErrAccounting) {
		t.Fatalf("expected accounting failure, got %v", err)
	}
	obligation, _ := engine.Obligation("loan-001")
	if obligation.Version != 1 || obligation.OutstandingPrincipalUnits != "1000" {
		t.Fatal("accounting outage changed the obligation")
	}
	if _, err := engine.Allocate(input); err != nil {
		t.Fatalf("retry allocation: %v", err)
	}
}

func TestReversalRestoresExactPrincipalOnce(t *testing.T) {
	engine, stub, now := fixture(t, "1000")
	item, err := engine.Allocate(request(now, "1250"))
	if err != nil {
		t.Fatalf("allocate: %v", err)
	}
	reversalRequest := ReversalRequest{
		ReversalID:                "reversal-001",
		AllocationID:              item.AllocationID,
		PaymentID:                 item.PaymentID,
		ExpectedObligationVersion: 2,
		ProviderID:                item.ProviderID,
		ProviderReference:         item.ProviderReference,
		Status:                    payment.StatusReversed,
		ProviderEventID:           "provider-reversal-001",
		ReasonCode:                "SYNTHETIC_CHARGEBACK",
		EvidenceHash:              "reversal-evidence",
		ReversedAt:                now.Add(3 * time.Hour),
	}
	first, err := engine.Reverse(reversalRequest)
	if err != nil {
		t.Fatalf("reverse: %v", err)
	}
	second, err := engine.Reverse(reversalRequest)
	if err != nil {
		t.Fatalf("replay reversal: %v", err)
	}
	obligation, _ := engine.Obligation("loan-001")
	if first.DebtAfterUnits != "1000" || first.RemovedExcessUnits != "250" ||
		second.ReversalID != first.ReversalID ||
		obligation.OutstandingPrincipalUnits != "1000" || stub.reversals != 1 ||
		engine.ReleaseEligible(item.AllocationID, now.Add(30*time.Hour)) {
		t.Fatal("reversal did not restore exact state once")
	}
}
