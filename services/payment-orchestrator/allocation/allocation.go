// Package allocation implements the synthetic Phase 7B final-payment projector.
// It is deliberately non-canonical and cannot mutate an on-chain loan or collateral.
package allocation

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"slices"
	"sync"
	"time"

	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

var (
	ErrInvalidObligation  = errors.New("invalid synthetic obligation")
	ErrInvalidAllocation  = errors.New("invalid payment allocation")
	ErrAllocationConflict = errors.New("payment allocation conflict")
	ErrInvalidReversal    = errors.New("invalid allocation reversal")
	ErrAccounting         = errors.New("allocation accounting failed")
)

type Obligation struct {
	LoanID                    string
	BorrowerID                string
	LenderID                  string
	AssetID                   string
	OutstandingPrincipalUnits string
	Version                   uint64
	SourceAuthority           string
	SourceEvidenceHash        string
	AsOf                      time.Time
}

type FinalPayment struct {
	PaymentID          string
	ProviderID         string
	ProviderReference  string
	AssetID            string
	Units              string
	Status             payment.Status
	ReconciliationID   string
	DifferenceUnits    string
	UnmatchedItems     uint32
	FinalityPolicyHash string
	ReversalDeadline   time.Time
	EvidenceHash       string
	FinalizedAt        time.Time
}

type Request struct {
	AllocationID              string
	Payment                   FinalPayment
	LoanID                    string
	ExpectedObligationVersion uint64
	WaterfallPolicyHash       string
	CorrelationID             string
	EvidenceHash              string
	AllocatedAt               time.Time
}

type Allocation struct {
	AllocationID            string
	PaymentID               string
	LoanID                  string
	ProviderID              string
	ProviderReference       string
	AssetID                 string
	GrossUnits              string
	PrincipalUnits          string
	RefundableExcessUnits   string
	DebtBeforeUnits         string
	DebtAfterUnits          string
	ObligationVersionBefore uint64
	ObligationVersionAfter  uint64
	WaterfallPolicyHash     string
	FinalityPolicyHash      string
	ReconciliationID        string
	ReversalDeadline        time.Time
	CorrelationID           string
	EvidenceHash            string
	JournalIDs              []string
	AllocatedAt             time.Time
}

type ReversalRequest struct {
	ReversalID                string
	AllocationID              string
	PaymentID                 string
	ExpectedObligationVersion uint64
	ProviderID                string
	ProviderReference         string
	Status                    payment.Status
	ProviderEventID           string
	ReasonCode                string
	EvidenceHash              string
	ReversedAt                time.Time
}

type Reversal struct {
	ReversalID              string
	AllocationID            string
	PaymentID               string
	LoanID                  string
	RestoredPrincipalUnits  string
	RemovedExcessUnits      string
	DebtBeforeUnits         string
	DebtAfterUnits          string
	ObligationVersionBefore uint64
	ObligationVersionAfter  uint64
	ReasonCode              string
	EvidenceHash            string
	JournalIDs              []string
	ReversedAt              time.Time
}

type Accounting interface {
	ApplyAllocation(Allocation) ([]string, error)
	ReverseAllocation(Allocation, ReversalRequest) ([]string, error)
}

type Engine struct {
	mu          sync.RWMutex
	accounting  Accounting
	obligations map[string]Obligation
	allocations map[string]Allocation
	byPayment   map[string]string
	reversals   map[string]Reversal
}

func New(obligations []Obligation, accounting Accounting) (*Engine, error) {
	if len(obligations) == 0 || accounting == nil {
		return nil, ErrInvalidObligation
	}
	records := make(map[string]Obligation, len(obligations))
	for _, obligation := range obligations {
		if !validObligation(obligation) || records[obligation.LoanID].LoanID != "" {
			return nil, ErrInvalidObligation
		}
		records[obligation.LoanID] = obligation
	}
	return &Engine{
		accounting:  accounting,
		obligations: records,
		allocations: make(map[string]Allocation),
		byPayment:   make(map[string]string),
		reversals:   make(map[string]Reversal),
	}, nil
}

func CalculateAllocationID(request Request) string {
	encoded, _ := json.Marshal(struct {
		PaymentID           string
		LoanID              string
		ObligationVersion   uint64
		Units               string
		WaterfallPolicyHash string
		FinalityPolicyHash  string
		EvidenceHash        string
	}{
		PaymentID:           request.Payment.PaymentID,
		LoanID:              request.LoanID,
		ObligationVersion:   request.ExpectedObligationVersion,
		Units:               request.Payment.Units,
		WaterfallPolicyHash: request.WaterfallPolicyHash,
		FinalityPolicyHash:  request.Payment.FinalityPolicyHash,
		EvidenceHash:        request.EvidenceHash,
	})
	hash := sha256.Sum256(append([]byte("UNIFIED_PHASE7B_ALLOCATION_V1\x00"), encoded...))
	return hex.EncodeToString(hash[:])
}

func (engine *Engine) Allocate(request Request) (Allocation, error) {
	if engine == nil || request.AllocationID == "" ||
		request.AllocationID != CalculateAllocationID(request) ||
		request.LoanID == "" || request.WaterfallPolicyHash == "" ||
		request.CorrelationID == "" || request.EvidenceHash == "" ||
		request.AllocatedAt.IsZero() ||
		request.AllocatedAt.Before(request.Payment.FinalizedAt) ||
		!validFinalPayment(request.Payment) {
		return Allocation{}, ErrInvalidAllocation
	}
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if allocationID, exists := engine.byPayment[request.Payment.PaymentID]; exists {
		existing := engine.allocations[allocationID]
		if existing.AllocationID == request.AllocationID &&
			existing.EvidenceHash == request.EvidenceHash {
			return cloneAllocation(existing), nil
		}
		return Allocation{}, ErrAllocationConflict
	}
	obligation, exists := engine.obligations[request.LoanID]
	if !exists || obligation.Version != request.ExpectedObligationVersion ||
		obligation.AssetID != request.Payment.AssetID ||
		request.AllocatedAt.Before(obligation.AsOf) {
		return Allocation{}, ErrInvalidAllocation
	}
	debt, _ := canonicalPositive(obligation.OutstandingPrincipalUnits)
	gross, _ := canonicalPositive(request.Payment.Units)
	principal := new(big.Int).Set(gross)
	if principal.Cmp(debt) > 0 {
		principal.Set(debt)
	}
	if principal.Sign() == 0 {
		return Allocation{}, ErrInvalidAllocation
	}
	excess := new(big.Int).Sub(new(big.Int).Set(gross), principal)
	after := new(big.Int).Sub(new(big.Int).Set(debt), principal)
	allocation := Allocation{
		AllocationID:            request.AllocationID,
		PaymentID:               request.Payment.PaymentID,
		LoanID:                  request.LoanID,
		ProviderID:              request.Payment.ProviderID,
		ProviderReference:       request.Payment.ProviderReference,
		AssetID:                 obligation.AssetID,
		GrossUnits:              gross.String(),
		PrincipalUnits:          principal.String(),
		RefundableExcessUnits:   excess.String(),
		DebtBeforeUnits:         debt.String(),
		DebtAfterUnits:          after.String(),
		ObligationVersionBefore: obligation.Version,
		ObligationVersionAfter:  obligation.Version + 1,
		WaterfallPolicyHash:     request.WaterfallPolicyHash,
		FinalityPolicyHash:      request.Payment.FinalityPolicyHash,
		ReconciliationID:        request.Payment.ReconciliationID,
		ReversalDeadline:        request.Payment.ReversalDeadline.UTC(),
		CorrelationID:           request.CorrelationID,
		EvidenceHash:            request.EvidenceHash,
		AllocatedAt:             request.AllocatedAt.UTC(),
	}
	journalIDs, err := engine.accounting.ApplyAllocation(allocation)
	if err != nil {
		return Allocation{}, errors.Join(ErrAccounting, err)
	}
	allocation.JournalIDs = slices.Clone(journalIDs)
	obligation.OutstandingPrincipalUnits = after.String()
	obligation.Version++
	obligation.AsOf = request.AllocatedAt.UTC()
	obligation.SourceAuthority = "SYNTHETIC_PAYMENT_ALLOCATION"
	obligation.SourceEvidenceHash = request.EvidenceHash
	engine.obligations[obligation.LoanID] = obligation
	engine.allocations[allocation.AllocationID] = allocation
	engine.byPayment[allocation.PaymentID] = allocation.AllocationID
	return cloneAllocation(allocation), nil
}

func (engine *Engine) Reverse(request ReversalRequest) (Reversal, error) {
	if engine == nil || request.ReversalID == "" || request.AllocationID == "" ||
		request.PaymentID == "" || request.ProviderID == "" ||
		request.ProviderReference == "" || request.Status != payment.StatusReversed ||
		request.ProviderEventID == "" ||
		request.ReasonCode == "" || request.EvidenceHash == "" ||
		request.ReversedAt.IsZero() {
		return Reversal{}, ErrInvalidReversal
	}
	engine.mu.Lock()
	defer engine.mu.Unlock()
	if existing, exists := engine.reversals[request.AllocationID]; exists {
		if existing.ReversalID == request.ReversalID &&
			existing.EvidenceHash == request.EvidenceHash {
			return cloneReversal(existing), nil
		}
		return Reversal{}, ErrInvalidReversal
	}
	allocation, exists := engine.allocations[request.AllocationID]
	obligation := engine.obligations[allocation.LoanID]
	if !exists || allocation.PaymentID != request.PaymentID ||
		allocation.ProviderID != request.ProviderID ||
		allocation.ProviderReference != request.ProviderReference ||
		obligation.Version != request.ExpectedObligationVersion ||
		request.ReversedAt.Before(allocation.AllocatedAt) {
		return Reversal{}, ErrInvalidReversal
	}
	current, ok := canonicalNonNegative(obligation.OutstandingPrincipalUnits)
	if !ok {
		return Reversal{}, ErrInvalidReversal
	}
	principal, _ := canonicalPositive(allocation.PrincipalUnits)
	restored := new(big.Int).Add(new(big.Int).Set(current), principal)
	reversal := Reversal{
		ReversalID:              request.ReversalID,
		AllocationID:            allocation.AllocationID,
		PaymentID:               allocation.PaymentID,
		LoanID:                  allocation.LoanID,
		RestoredPrincipalUnits:  principal.String(),
		RemovedExcessUnits:      allocation.RefundableExcessUnits,
		DebtBeforeUnits:         current.String(),
		DebtAfterUnits:          restored.String(),
		ObligationVersionBefore: obligation.Version,
		ObligationVersionAfter:  obligation.Version + 1,
		ReasonCode:              request.ReasonCode,
		EvidenceHash:            request.EvidenceHash,
		ReversedAt:              request.ReversedAt.UTC(),
	}
	journalIDs, err := engine.accounting.ReverseAllocation(allocation, request)
	if err != nil {
		return Reversal{}, errors.Join(ErrAccounting, err)
	}
	reversal.JournalIDs = slices.Clone(journalIDs)
	obligation.OutstandingPrincipalUnits = restored.String()
	obligation.Version++
	obligation.AsOf = request.ReversedAt.UTC()
	obligation.SourceAuthority = "SYNTHETIC_PAYMENT_REVERSAL"
	obligation.SourceEvidenceHash = request.EvidenceHash
	engine.obligations[obligation.LoanID] = obligation
	engine.reversals[allocation.AllocationID] = reversal
	return cloneReversal(reversal), nil
}

func (engine *Engine) ReleaseEligible(allocationID string, asOf time.Time) bool {
	engine.mu.RLock()
	defer engine.mu.RUnlock()
	allocation, exists := engine.allocations[allocationID]
	if !exists || asOf.IsZero() || asOf.Before(allocation.ReversalDeadline) {
		return false
	}
	if _, reversed := engine.reversals[allocationID]; reversed {
		return false
	}
	obligation := engine.obligations[allocation.LoanID]
	if obligation.OutstandingPrincipalUnits != "0" {
		return false
	}
	for otherID, other := range engine.allocations {
		if other.LoanID != allocation.LoanID {
			continue
		}
		if _, reversed := engine.reversals[otherID]; !reversed &&
			asOf.Before(other.ReversalDeadline) {
			return false
		}
	}
	return true
}

func (engine *Engine) Obligation(loanID string) (Obligation, bool) {
	engine.mu.RLock()
	defer engine.mu.RUnlock()
	obligation, exists := engine.obligations[loanID]
	return obligation, exists
}

func validObligation(obligation Obligation) bool {
	units, ok := canonicalPositive(obligation.OutstandingPrincipalUnits)
	return obligation.LoanID != "" && obligation.BorrowerID != "" &&
		obligation.LenderID != "" && obligation.AssetID != "" &&
		obligation.Version > 0 && obligation.SourceAuthority != "" &&
		obligation.SourceEvidenceHash != "" && !obligation.AsOf.IsZero() &&
		ok && units.Sign() > 0
}

func validFinalPayment(final FinalPayment) bool {
	units, ok := canonicalPositive(final.Units)
	difference, differenceOK := canonicalNonNegative(final.DifferenceUnits)
	return final.PaymentID != "" && final.ProviderID != "" &&
		final.ProviderReference != "" && final.AssetID != "" &&
		final.Status == payment.StatusFinal && final.ReconciliationID != "" &&
		differenceOK && difference.Sign() == 0 && final.UnmatchedItems == 0 &&
		final.FinalityPolicyHash != "" && final.EvidenceHash != "" &&
		!final.FinalizedAt.IsZero() && final.ReversalDeadline.After(final.FinalizedAt) &&
		ok && units.Sign() > 0
}

func canonicalPositive(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.Sign() > 0 && parsed.String() == value
}

func canonicalNonNegative(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.Sign() >= 0 && parsed.String() == value
}

func cloneAllocation(record Allocation) Allocation {
	record.JournalIDs = slices.Clone(record.JournalIDs)
	return record
}

func cloneReversal(record Reversal) Reversal {
	record.JournalIDs = slices.Clone(record.JournalIDs)
	return record
}
