// Package settlement implements the synthetic Phase 7C canonicalization
// coordinator. It plans but does not post the principal/excess waterfall, and
// treats the finalized gateway event as the canonical economic commit.
package settlement

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"slices"
	"sync"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

var (
	ErrInvalidPlan       = errors.New("invalid canonical settlement plan")
	ErrPlanConflict      = errors.New("canonical settlement plan conflict")
	ErrInvalidTransition = errors.New("invalid canonical settlement transition")
	ErrInvalidEvent      = errors.New("invalid canonical gateway event")
	ErrInvalidReorg      = errors.New("invalid canonical settlement reorganization")
)

type State string

const (
	StatePrepared    State = "PREPARED"
	StateSubmitted   State = "SUBMITTED"
	StateConfirmed   State = "CONFIRMED"
	StateFailed      State = "FAILED"
	StateQuarantined State = "QUARANTINED"
	StateIncident    State = "INCIDENT"
)

// PrepareRequest contains only immutable provider, policy, reconciliation, loan,
// and conversion evidence. It contains no caller-selected payout recipient.
type PrepareRequest struct {
	PaymentID                string
	AllocationID             string
	LoanID                   string
	ProviderID               string
	ProviderReference        string
	PaymentStatus            payment.Status
	PaymentVersion           uint64
	SourceAssetID            string
	TargetAssetID            string
	TargetToken              string
	Denomination             string
	SourcePrecision          uint32
	TargetPrecision          uint32
	SourceUnits              string
	TargetUnits              string
	ReconciliationID         string
	DifferenceUnits          string
	UnmatchedItems           uint32
	FinalityPolicyHash       string
	ConversionPolicyHash     string
	PolicySetHash            string
	EligibilityEvidenceHash  string
	OriginalJournalIDs       []string
	ExpectedDebtUnits        string
	ExpectedStateNonce       uint64
	ChainID                  uint64
	GatewayAddress           string
	FinalizerAddress         string
	ProviderIDHash           string
	ProviderReferenceHash    string
	ReconciliationCommitment string
	OriginalJournalSetHash   string
	JournalRef               string
	AttesterAddress          string
	FinalizedAt              time.Time
	ReversalDeadline         time.Time
	PreparedAt               time.Time
	CorrelationID            string
}

type Plan struct {
	PaymentID                string
	AllocationID             string
	LoanID                   string
	ProviderID               string
	ProviderReference        string
	PaymentVersion           uint64
	SourceAssetID            string
	TargetAssetID            string
	TargetToken              string
	Denomination             string
	Precision                uint32
	SourceUnits              string
	TargetUnits              string
	PrincipalUnits           string
	RefundableExcessUnits    string
	DebtBeforeUnits          string
	DebtAfterUnits           string
	ReconciliationID         string
	ProviderIDHash           string
	ProviderReferenceHash    string
	ReconciliationCommitment string
	OriginalJournalSetHash   string
	FinalityPolicyHash       string
	ConversionPolicyHash     string
	PolicySetHash            string
	EligibilityEvidenceHash  string
	JournalRef               string
	ProviderFinalizedAt      uint64
	ReversalDeadlineUnix     uint64
	OriginalJournalIDs       []string
	ExpectedStateNonce       uint64
	ChainID                  uint64
	GatewayAddress           string
	FinalizerAddress         string
	AttesterAddress          string
	ReversalDeadline         time.Time
	CorrelationID            string
	InstructionDigest        string
	Instruction              SolidityInstruction
	State                    State
	Version                  uint64
	PreparedAt               time.Time
	Submission               Submission
	FailureReason            string
	FailureProof             chainprojection.TransactionFailureEvidence
	Replayed                 bool
}

type SubmissionRequest struct {
	PaymentID         string
	AllocationID      string
	InstructionDigest string
	ExpectedVersion   uint64
	ChainID           uint64
	Gateway           string
	Sender            string
	SenderNonce       uint64
	TransactionHash   string
	CalldataHash      string
	SubmittedAt       time.Time
}

type Submission struct {
	ChainID         uint64
	Gateway         string
	Sender          string
	SenderNonce     uint64
	TransactionHash string
	CalldataHash    string
	SubmittedAt     time.Time
}

type gatewayEvent struct {
	EventID                    string
	TransactionHash            string
	LogIndex                   uint32
	BlockNumber                uint64
	BlockHash                  string
	ChainID                    uint64
	Gateway                    string
	PaymentID                  string
	AllocationID               string
	LoanID                     string
	InstructionDigest          string
	PolicySetHash              string
	LoanAccount                string
	Finalizer                  string
	Attester                   string
	SourceAssetID              string
	TargetAssetID              string
	TargetToken                string
	SourceUnits                string
	GrossUnits                 string
	ProviderIDHash             string
	ProviderReferenceHash      string
	ReconciliationID           string
	ReconciliationCommitment   string
	OriginalJournalSetHash     string
	ConversionPolicyHash       string
	FinalityPolicyHash         string
	EvidenceHash               string
	JournalRef                 string
	ProviderFinalizedAt        uint64
	ReversalDeadline           uint64
	DebtBeforeUnits            string
	PrincipalUnits             string
	RefundableExcess           string
	DebtAfterUnits             string
	StateNonceBefore           uint64
	StateNonceAfter            uint64
	LenderID                   string
	BorrowerID                 string
	RawEvidenceHash            string
	TransactionIndex           uint64
	ReceiptsRoot               string
	InclusionProofHash         string
	ReceiptHeaderSignatureHash string
}

type ConfirmationRequest struct {
	PaymentID         string
	AllocationID      string
	InstructionDigest string
	ExpectedVersion   uint64
	Projection        chainprojection.VerifiedGatewayProjection
}

// AccountingProjection is a detached, read-only copy of a coordinator-issued
// confirmation. It preserves the complete instruction, gateway-log, recipient,
// and finality provenance required by accounting. Constructing this DTO does not
// construct a Confirmation; only Coordinator.Confirm can mint one.
type AccountingProjection struct {
	PaymentID                  string
	AllocationID               string
	LoanID                     string
	ProviderID                 string
	ProviderReference          string
	SourceAssetID              string
	TargetAssetID              string
	TargetToken                string
	Denomination               string
	Precision                  uint32
	SourceUnits                string
	TargetUnits                string
	PrincipalUnits             string
	RefundableExcessUnits      string
	DebtBeforeUnits            string
	DebtAfterUnits             string
	ReconciliationID           string
	ProviderIDHash             string
	ProviderReferenceHash      string
	ReconciliationCommitment   string
	OriginalJournalSetHash     string
	FinalityPolicyHash         string
	ConversionPolicyHash       string
	PolicySetHash              string
	EligibilityEvidenceHash    string
	JournalRef                 string
	ProviderFinalizedAt        uint64
	ReversalDeadlineUnix       uint64
	OriginalJournalIDs         []string
	CorrelationID              string
	InstructionDigest          string
	ChainID                    uint64
	Gateway                    string
	LoanAccount                string
	Finalizer                  string
	Attester                   string
	TransactionHash            string
	EventID                    string
	LogIndex                   uint32
	BlockNumber                uint64
	BlockHash                  string
	TransactionIndex           uint64
	ReceiptsRoot               string
	InclusionProofHash         string
	HeaderAuthorityHash        string
	ReceiptHeaderSignatureHash string
	HeadHeaderSignatureHash    string
	ConfirmationDepth          uint64
	FinalityHeadBlock          uint64
	FinalityHeadHash           string
	FinalityEvidenceHash       string
	StateNonceBefore           uint64
	StateNonceAfter            uint64
	LenderID                   string
	BorrowerID                 string
	EventEvidenceHash          string
	GatewayPayloadHash         string
	ConfirmedAt                time.Time
	Incident                   bool
}

type confirmationValue struct {
	Projection AccountingProjection
}

// Confirmation is an opaque coordinator-issued value. Its fields are private so
// another package cannot bypass indexer-owned finality by constructing a literal.
type Confirmation struct {
	value    confirmationValue
	replayed bool
}

func (confirmation Confirmation) AccountingProjection() AccountingProjection {
	projection := confirmation.value.Projection
	projection.OriginalJournalIDs = slices.Clone(projection.OriginalJournalIDs)
	return projection
}

func (confirmation Confirmation) PaymentID() string {
	return confirmation.value.Projection.PaymentID
}

func (confirmation Confirmation) AllocationID() string {
	return confirmation.value.Projection.AllocationID
}

func (confirmation Confirmation) InstructionDigest() string {
	return confirmation.value.Projection.InstructionDigest
}

func (confirmation Confirmation) EventID() string {
	return confirmation.value.Projection.EventID
}

func (confirmation Confirmation) TransactionHash() string {
	return confirmation.value.Projection.TransactionHash
}

func (confirmation Confirmation) BlockHash() string {
	return confirmation.value.Projection.BlockHash
}

func (confirmation Confirmation) GatewayPayloadHash() string {
	return confirmation.value.Projection.GatewayPayloadHash
}

func (confirmation Confirmation) Incident() bool {
	return confirmation.value.Projection.Incident
}

func (confirmation Confirmation) Replayed() bool {
	return confirmation.replayed
}

type FailureRequest struct {
	PaymentID         string
	AllocationID      string
	InstructionDigest string
	ExpectedVersion   uint64
	Proof             chainprojection.VerifiedTransactionFailure
}

type RetryRequest struct {
	PaymentID         string
	AllocationID      string
	InstructionDigest string
	ExpectedVersion   uint64
	EvidenceHash      string
	RetriedAt         time.Time
}

type ReorgEvidence struct {
	ReorgID                            string
	PaymentID                          string
	AllocationID                       string
	InstructionDigest                  string
	ChainID                            uint64
	Gateway                            string
	OrphanedEventID                    string
	OrphanedTxHash                     string
	OrphanedEventEvidenceHash          string
	RawEvidenceHash                    string
	TransactionIndex                   uint64
	ReceiptsRoot                       string
	InclusionProofHash                 string
	OrphanedReceiptHeaderSignatureHash string
	OrphanedBlockHash                  string
	OrphanedBlock                      uint64
	ReplacementBlockHash               string
	ReplacementBlock                   uint64
	DepthClass                         chainprojection.ReorgDepthClass
	ConfirmationDepth                  uint64
	DetectedHead                       uint64
	DetectedHeadHash                   string
	FinalityPolicyHash                 string
	HeaderAuthorityHash                string
	ReplacementHeaderSignatureHash     string
	DetectedHeadHeaderSignatureHash    string
	Deep                               bool
	CompensationRequired               bool
	EvidenceHash                       string
	SubmissionSubmittedAt              time.Time
	DetectedAt                         time.Time
}

// DurableReorgAuthority is an opaque coordinator-issued capability proving that
// a lossless, policy-bound reorganization passed RecordReorg and its durable
// compare-and-swap. A zero value has no authority. The coordinator reconstructs
// this capability only from a validated durable snapshot after restart.
type DurableReorgAuthority struct {
	evidence ReorgEvidence
}

func (authority DurableReorgAuthority) Evidence() ReorgEvidence {
	return authority.evidence
}

type Coordinator struct {
	mu            sync.RWMutex
	modes         *allocationmode.Registry
	store         Store
	plans         map[string]Plan
	byAllocation  map[string]string
	confirmations map[string]Confirmation
	reorgs        []ReorgEvidence
	pending       map[string]PendingReversalSnapshot
	consumed      map[string]ConsumedPendingReversalSnapshot
	resolutions   map[string]StoredReversalResolution
}

func New(
	modes *allocationmode.Registry,
	store Store,
) (*Coordinator, error) {
	return NewWithStore(modes, store)
}

// NewInMemory is an explicit local-test helper. Runtime wiring must choose and
// supply a durable Store instead of silently receiving process-local state.
func NewInMemory(modes *allocationmode.Registry) (*Coordinator, error) {
	return NewWithStore(modes, NewMemoryStore())
}

// NewWithStore rehydrates every durable coordinator snapshot and its exact
// allocation claim before accepting work.
func NewWithStore(
	modes *allocationmode.Registry,
	store Store,
) (*Coordinator, error) {
	if modes == nil || store == nil {
		return nil, ErrInvalidPlan
	}
	coordinator := &Coordinator{
		modes:         modes,
		store:         store,
		plans:         make(map[string]Plan),
		byAllocation:  make(map[string]string),
		confirmations: make(map[string]Confirmation),
		pending:       make(map[string]PendingReversalSnapshot),
		consumed:      make(map[string]ConsumedPendingReversalSnapshot),
		resolutions:   make(map[string]StoredReversalResolution),
	}
	records, err := store.LoadAll()
	if err != nil {
		return nil, errors.Join(ErrInvalidPlan, err)
	}
	for _, record := range records {
		snapshot, err := decodeDurableSnapshot(record.Snapshot)
		if err != nil || !validRecoveredSnapshot(record, snapshot) {
			return nil, ErrInvalidPlan
		}
		if err := modes.Restore(snapshot.Claim, snapshot.Tombstoned); err != nil {
			return nil, errors.Join(ErrInvalidPlan, err)
		}
		plan := clonePlan(snapshot.Plan)
		coordinator.plans[plan.PaymentID] = plan
		coordinator.byAllocation[plan.AllocationID] = plan.PaymentID
		if snapshot.Confirmation != nil {
			projection := *snapshot.Confirmation
			projection.OriginalJournalIDs = slices.Clone(projection.OriginalJournalIDs)
			coordinator.confirmations[plan.PaymentID] = Confirmation{
				value: confirmationValue{Projection: projection},
			}
		}
		coordinator.reorgs = append(coordinator.reorgs, snapshot.Reorgs...)
		if snapshot.PendingReversal != nil {
			coordinator.pending[plan.PaymentID] = *snapshot.PendingReversal
		}
		if snapshot.ConsumedPendingReversal != nil {
			consumed := *snapshot.ConsumedPendingReversal
			coordinator.consumed[plan.PaymentID] = consumed
		}
	}
	tombstones, err := store.LoadTombstones()
	if err != nil {
		return nil, errors.Join(ErrInvalidPlan, err)
	}
	for _, tombstone := range tombstones {
		if err := modes.RestoreTombstone(tombstone.PaymentID); err != nil {
			return nil, errors.Join(ErrInvalidPlan, err)
		}
	}
	resolutions, err := store.LoadResolvedReversals()
	if err != nil {
		return nil, errors.Join(ErrInvalidPlan, err)
	}
	for _, resolution := range resolutions {
		if !validStoredReversalResolution(resolution) {
			return nil, ErrInvalidPlan
		}
		paymentID := resolution.Resolution.Pending.PaymentID
		plan, exists := coordinator.plans[paymentID]
		if !exists || plan.State != StateFailed ||
			!coordinator.modes.IsReversed(paymentID) {
			return nil, ErrInvalidPlan
		}
		quarantineID := resolution.Resolution.Pending.QuarantineID
		if _, exists := coordinator.resolutions[quarantineID]; exists {
			return nil, ErrInvalidPlan
		}
		resolution.JournalIDs = slices.Clone(resolution.JournalIDs)
		coordinator.resolutions[quarantineID] = resolution
	}
	return coordinator, nil
}

func CalculateAllocationID(request PrepareRequest) string {
	encoded, _ := json.Marshal(struct {
		PaymentID       string
		LoanID          string
		SourceAssetID   string
		TargetAssetID   string
		TargetUnits     string
		ExpectedDebt    string
		ExpectedNonce   uint64
		PaymentVersion  uint64
		PolicySetHash   string
		EligibilityHash string
	}{
		PaymentID:       request.PaymentID,
		LoanID:          request.LoanID,
		SourceAssetID:   request.SourceAssetID,
		TargetAssetID:   request.TargetAssetID,
		TargetUnits:     request.TargetUnits,
		ExpectedDebt:    request.ExpectedDebtUnits,
		ExpectedNonce:   request.ExpectedStateNonce,
		PaymentVersion:  request.PaymentVersion,
		PolicySetHash:   request.PolicySetHash,
		EligibilityHash: request.EligibilityEvidenceHash,
	})
	return "0x" + digest("UNIFIED_PHASE7C_ALLOCATION_V1", encoded)
}

func CalculateInstructionDigest(request PrepareRequest) (string, error) {
	if request.FinalizedAt.Unix() < 0 || request.ReversalDeadline.Unix() < 0 {
		return "", ErrInvalidDigestInput
	}
	return SolidityInstructionDigest(SolidityDigestInput{
		ChainID:       request.ChainID,
		Gateway:       request.GatewayAddress,
		Finalizer:     request.FinalizerAddress,
		PolicySetHash: request.PolicySetHash,
		Instruction: SolidityInstruction{
			PaymentID:                request.PaymentID,
			AllocationID:             request.AllocationID,
			LoanID:                   request.LoanID,
			SourceAssetID:            request.SourceAssetID,
			TargetAssetID:            request.TargetAssetID,
			SourceUnits:              request.SourceUnits,
			TargetUnits:              request.TargetUnits,
			ProviderIDHash:           request.ProviderIDHash,
			ProviderReferenceHash:    request.ProviderReferenceHash,
			ReconciliationID:         request.ReconciliationID,
			ReconciliationCommitment: request.ReconciliationCommitment,
			OriginalJournalSetHash:   request.OriginalJournalSetHash,
			ConversionPolicyHash:     request.ConversionPolicyHash,
			FinalityPolicyHash:       request.FinalityPolicyHash,
			EvidenceHash:             request.EligibilityEvidenceHash,
			JournalRef:               request.JournalRef,
			FinalizedAt:              uint64(request.FinalizedAt.Unix()),
			ReversalDeadline:         uint64(request.ReversalDeadline.Unix()),
			ExpectedDebt:             request.ExpectedDebtUnits,
			ExpectedStateNonce:       request.ExpectedStateNonce,
			Attester:                 request.AttesterAddress,
		},
	})
}

func (coordinator *Coordinator) Prepare(request PrepareRequest) (Plan, error) {
	if coordinator == nil || !validPrepare(request) ||
		request.AllocationID != CalculateAllocationID(request) {
		return Plan{}, ErrInvalidPlan
	}
	instructionDigest, digestErr := CalculateInstructionDigest(request)
	if digestErr != nil {
		return Plan{}, ErrInvalidPlan
	}
	gross, _ := positive(request.TargetUnits)
	debt, _ := positive(request.ExpectedDebtUnits)
	principal := new(big.Int).Set(gross)
	if principal.Cmp(debt) > 0 {
		principal.Set(debt)
	}
	excess := new(big.Int).Sub(new(big.Int).Set(gross), principal)
	after := new(big.Int).Sub(new(big.Int).Set(debt), principal)

	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	if existing, ok := coordinator.plans[request.PaymentID]; ok {
		if existing.InstructionDigest != instructionDigest ||
			existing.AllocationID != request.AllocationID {
			return Plan{}, ErrPlanConflict
		}
		if existing.State == StatePrepared {
			claim, claimed := coordinator.modes.Lookup(existing.PaymentID)
			if !claimed || !claimMatchesPlan(claim, existing) ||
				claim.State != allocationmode.CanonicalPrepared {
				return Plan{}, ErrInvalidTransition
			}
		}
		if existing.State == StateFailed {
			return Plan{}, ErrInvalidTransition
		}
		replayed := clonePlan(existing)
		replayed.Replayed = true
		return replayed, nil
	}
	if owner, ok := coordinator.byAllocation[request.AllocationID]; ok &&
		owner != request.PaymentID {
		return Plan{}, ErrPlanConflict
	}
	plan := Plan{
		PaymentID:                request.PaymentID,
		AllocationID:             request.AllocationID,
		LoanID:                   request.LoanID,
		ProviderID:               request.ProviderID,
		ProviderReference:        request.ProviderReference,
		PaymentVersion:           request.PaymentVersion,
		SourceAssetID:            request.SourceAssetID,
		TargetAssetID:            request.TargetAssetID,
		TargetToken:              request.TargetToken,
		Denomination:             request.Denomination,
		Precision:                request.TargetPrecision,
		SourceUnits:              request.SourceUnits,
		TargetUnits:              request.TargetUnits,
		PrincipalUnits:           principal.String(),
		RefundableExcessUnits:    excess.String(),
		DebtBeforeUnits:          debt.String(),
		DebtAfterUnits:           after.String(),
		ReconciliationID:         request.ReconciliationID,
		ProviderIDHash:           request.ProviderIDHash,
		ProviderReferenceHash:    request.ProviderReferenceHash,
		ReconciliationCommitment: request.ReconciliationCommitment,
		OriginalJournalSetHash:   request.OriginalJournalSetHash,
		FinalityPolicyHash:       request.FinalityPolicyHash,
		ConversionPolicyHash:     request.ConversionPolicyHash,
		PolicySetHash:            request.PolicySetHash,
		EligibilityEvidenceHash:  request.EligibilityEvidenceHash,
		JournalRef:               request.JournalRef,
		ProviderFinalizedAt:      uint64(request.FinalizedAt.Unix()),
		ReversalDeadlineUnix:     uint64(request.ReversalDeadline.Unix()),
		OriginalJournalIDs:       slices.Clone(request.OriginalJournalIDs),
		ExpectedStateNonce:       request.ExpectedStateNonce,
		ChainID:                  request.ChainID,
		GatewayAddress:           request.GatewayAddress,
		FinalizerAddress:         request.FinalizerAddress,
		AttesterAddress:          request.AttesterAddress,
		ReversalDeadline:         request.ReversalDeadline.UTC(),
		CorrelationID:            request.CorrelationID,
		InstructionDigest:        instructionDigest,
		Instruction: SolidityInstruction{
			PaymentID:                request.PaymentID,
			AllocationID:             request.AllocationID,
			LoanID:                   request.LoanID,
			SourceAssetID:            request.SourceAssetID,
			TargetAssetID:            request.TargetAssetID,
			SourceUnits:              request.SourceUnits,
			TargetUnits:              request.TargetUnits,
			ProviderIDHash:           request.ProviderIDHash,
			ProviderReferenceHash:    request.ProviderReferenceHash,
			ReconciliationID:         request.ReconciliationID,
			ReconciliationCommitment: request.ReconciliationCommitment,
			OriginalJournalSetHash:   request.OriginalJournalSetHash,
			ConversionPolicyHash:     request.ConversionPolicyHash,
			FinalityPolicyHash:       request.FinalityPolicyHash,
			EvidenceHash:             request.EligibilityEvidenceHash,
			JournalRef:               request.JournalRef,
			FinalizedAt:              uint64(request.FinalizedAt.Unix()),
			ReversalDeadline:         uint64(request.ReversalDeadline.Unix()),
			ExpectedDebt:             request.ExpectedDebtUnits,
			ExpectedStateNonce:       request.ExpectedStateNonce,
			Attester:                 request.AttesterAddress,
		},
		State:      StatePrepared,
		Version:    1,
		PreparedAt: request.PreparedAt.UTC(),
	}
	claim, err := coordinator.modes.ClaimModeWithCommit(
		request.PaymentID,
		request.AllocationID,
		allocationmode.ModeCanonicalGateway,
		instructionDigest,
		request.PaymentVersion,
		request.EligibilityEvidenceHash,
		request.PreparedAt,
		func(claim allocationmode.Claim) error {
			return coordinator.createDurable(
				plan,
				claim,
				request.EligibilityEvidenceHash,
				request.PreparedAt,
			)
		},
	)
	if err != nil || claim.State != allocationmode.CanonicalPrepared {
		return Plan{}, errors.Join(ErrPlanConflict, err)
	}
	coordinator.plans[plan.PaymentID] = plan
	coordinator.byAllocation[plan.AllocationID] = plan.PaymentID
	return clonePlan(plan), nil
}

func (coordinator *Coordinator) Submit(request SubmissionRequest) (Plan, error) {
	if coordinator == nil || !validSubmission(request) {
		return Plan{}, ErrInvalidTransition
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	plan, ok := coordinator.plans[request.PaymentID]
	if !ok || plan.AllocationID != request.AllocationID ||
		plan.InstructionDigest != request.InstructionDigest {
		return Plan{}, ErrPlanConflict
	}
	submission := Submission{
		ChainID:         request.ChainID,
		Gateway:         request.Gateway,
		Sender:          request.Sender,
		SenderNonce:     request.SenderNonce,
		TransactionHash: request.TransactionHash,
		CalldataHash:    request.CalldataHash,
		SubmittedAt:     request.SubmittedAt.UTC(),
	}
	if plan.State == StateSubmitted && plan.Submission == submission {
		replayed := clonePlan(plan)
		replayed.Replayed = true
		return replayed, nil
	}
	if plan.State != StatePrepared || plan.Version != request.ExpectedVersion ||
		request.SubmittedAt.Before(plan.PreparedAt) ||
		request.ChainID != plan.ChainID ||
		request.Gateway != plan.GatewayAddress ||
		request.Sender != plan.FinalizerAddress {
		return Plan{}, ErrInvalidTransition
	}
	nextPlan := clonePlan(plan)
	nextPlan.State = StateSubmitted
	nextPlan.Version++
	nextPlan.Submission = submission
	if _, err := coordinator.modes.TransitionWithCommit(
		plan.PaymentID,
		plan.AllocationID,
		plan.InstructionDigest,
		allocationmode.CanonicalPrepared,
		allocationmode.CanonicalSubmitted,
		func(claim allocationmode.Claim) error {
			return coordinator.compareAndSwapDurable(
				StatePrepared,
				plan.Version,
				nextPlan,
				claim,
				request.CalldataHash,
				request.SubmittedAt,
			)
		},
	); err != nil {
		return Plan{}, errors.Join(ErrInvalidTransition, err)
	}
	plan = nextPlan
	coordinator.plans[plan.PaymentID] = plan
	return clonePlan(plan), nil
}

func (coordinator *Coordinator) Confirm(
	request ConfirmationRequest,
) (Confirmation, error) {
	if coordinator == nil || request.PaymentID == "" || request.AllocationID == "" ||
		request.InstructionDigest == "" || request.ExpectedVersion == 0 {
		return Confirmation{}, ErrInvalidEvent
	}
	event, proof := gatewayProjection(request.Projection)
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	plan, ok := coordinator.plans[request.PaymentID]
	if !ok || plan.AllocationID != request.AllocationID ||
		plan.InstructionDigest != request.InstructionDigest {
		return Confirmation{}, ErrPlanConflict
	}
	if existing, ok := coordinator.confirmations[request.PaymentID]; ok {
		if sameGatewayEvent(existing, event) {
			existing.replayed = true
			return cloneConfirmation(existing), nil
		}
		return Confirmation{}, ErrPlanConflict
	}
	pending, hadPending := coordinator.pending[plan.PaymentID]
	versionMatches := plan.Version == request.ExpectedVersion
	if plan.State == StateQuarantined && hadPending &&
		pending.OriginState == StateSubmitted &&
		request.ExpectedVersion < ^uint64(0) &&
		plan.Version == request.ExpectedVersion+1 {
		versionMatches = true
	}
	if !versionMatches || !validEvent(plan, event, proof) ||
		(plan.State == StateQuarantined &&
			(!hadPending || !submittedPendingMatchesPlan(pending, plan))) {
		return Confirmation{}, ErrInvalidEvent
	}
	claim, exists := coordinator.modes.Lookup(plan.PaymentID)
	if !exists || claim.AllocationID != plan.AllocationID ||
		claim.Digest != plan.InstructionDigest ||
		stateFromCanonical(claim.State) != plan.State {
		return Confirmation{}, ErrInvalidTransition
	}
	var expected allocationmode.CanonicalState
	var next allocationmode.CanonicalState
	var finalState State
	var incident bool
	switch claim.State {
	case allocationmode.CanonicalSubmitted:
		expected = allocationmode.CanonicalSubmitted
		next = allocationmode.CanonicalConfirmed
		finalState = StateConfirmed
	case allocationmode.CanonicalQuarantined:
		expected = allocationmode.CanonicalQuarantined
		next = allocationmode.CanonicalIncident
		finalState = StateIncident
		incident = true
	default:
		return Confirmation{}, ErrInvalidTransition
	}
	confirmation := Confirmation{value: confirmationValue{Projection: AccountingProjection{
		PaymentID:                  plan.PaymentID,
		AllocationID:               plan.AllocationID,
		LoanID:                     plan.LoanID,
		ProviderID:                 plan.ProviderID,
		ProviderReference:          plan.ProviderReference,
		SourceAssetID:              plan.SourceAssetID,
		TargetAssetID:              plan.TargetAssetID,
		TargetToken:                plan.TargetToken,
		Denomination:               plan.Denomination,
		Precision:                  plan.Precision,
		SourceUnits:                plan.SourceUnits,
		TargetUnits:                plan.TargetUnits,
		PrincipalUnits:             plan.PrincipalUnits,
		RefundableExcessUnits:      plan.RefundableExcessUnits,
		DebtBeforeUnits:            plan.DebtBeforeUnits,
		DebtAfterUnits:             plan.DebtAfterUnits,
		ReconciliationID:           plan.ReconciliationID,
		ProviderIDHash:             event.ProviderIDHash,
		ProviderReferenceHash:      event.ProviderReferenceHash,
		ReconciliationCommitment:   event.ReconciliationCommitment,
		OriginalJournalSetHash:     event.OriginalJournalSetHash,
		FinalityPolicyHash:         plan.FinalityPolicyHash,
		ConversionPolicyHash:       plan.ConversionPolicyHash,
		PolicySetHash:              plan.PolicySetHash,
		EligibilityEvidenceHash:    plan.EligibilityEvidenceHash,
		JournalRef:                 event.JournalRef,
		ProviderFinalizedAt:        event.ProviderFinalizedAt,
		ReversalDeadlineUnix:       event.ReversalDeadline,
		OriginalJournalIDs:         slices.Clone(plan.OriginalJournalIDs),
		CorrelationID:              plan.CorrelationID,
		InstructionDigest:          plan.InstructionDigest,
		ChainID:                    event.ChainID,
		Gateway:                    event.Gateway,
		LoanAccount:                event.LoanAccount,
		Finalizer:                  event.Finalizer,
		Attester:                   event.Attester,
		TransactionHash:            event.TransactionHash,
		EventID:                    event.EventID,
		LogIndex:                   event.LogIndex,
		BlockNumber:                event.BlockNumber,
		BlockHash:                  event.BlockHash,
		TransactionIndex:           event.TransactionIndex,
		ReceiptsRoot:               event.ReceiptsRoot,
		InclusionProofHash:         event.InclusionProofHash,
		HeaderAuthorityHash:        proof.HeaderAuthorityHash,
		ReceiptHeaderSignatureHash: event.ReceiptHeaderSignatureHash,
		HeadHeaderSignatureHash:    proof.HeadHeaderSignatureHash,
		ConfirmationDepth:          proof.ConfirmationDepth,
		FinalityHeadBlock:          proof.HeadBlockNumber,
		FinalityHeadHash:           proof.HeadBlockHash,
		FinalityEvidenceHash:       proof.EvidenceHash,
		StateNonceBefore:           event.StateNonceBefore,
		StateNonceAfter:            event.StateNonceAfter,
		LenderID:                   event.LenderID,
		BorrowerID:                 event.BorrowerID,
		EventEvidenceHash:          event.EvidenceHash,
		GatewayPayloadHash:         event.RawEvidenceHash,
		ConfirmedAt:                proof.ObservedAt.UTC(),
		Incident:                   incident,
	}}}
	nextPlan := clonePlan(plan)
	nextPlan.State = finalState
	nextPlan.Version++
	var consumed ConsumedPendingReversalSnapshot
	if incident {
		consumed = ConsumedPendingReversalSnapshot{
			Pending:                pending,
			ResolutionID:           "canonical-success:" + event.EventID,
			ResolutionEvidenceHash: proof.EvidenceHash,
			ResolvedBy:             "canonical-chain-indexer",
			ResolvedAt:             proof.ObservedAt.UTC(),
			GatewayEventID:         event.EventID,
			GatewayTransactionHash: event.TransactionHash,
			GatewayRawPayloadHash:  event.RawEvidenceHash,
			FinalityEvidenceHash:   proof.EvidenceHash,
		}
		delete(coordinator.pending, plan.PaymentID)
		coordinator.consumed[plan.PaymentID] = consumed
	}
	coordinator.confirmations[plan.PaymentID] = confirmation
	if _, err := coordinator.modes.TransitionWithCommit(
		plan.PaymentID,
		plan.AllocationID,
		plan.InstructionDigest,
		expected,
		next,
		func(nextClaim allocationmode.Claim) error {
			return coordinator.compareAndSwapDurable(
				plan.State,
				plan.Version,
				nextPlan,
				nextClaim,
				proof.EvidenceHash,
				proof.ObservedAt,
			)
		},
	); err != nil {
		delete(coordinator.confirmations, plan.PaymentID)
		if hadPending {
			coordinator.pending[plan.PaymentID] = pending
		}
		if incident {
			delete(coordinator.consumed, plan.PaymentID)
		}
		return Confirmation{}, errors.Join(ErrInvalidTransition, err)
	}
	plan = nextPlan
	coordinator.plans[plan.PaymentID] = plan
	return cloneConfirmation(confirmation), nil
}

func (coordinator *Coordinator) Fail(request FailureRequest) (Plan, error) {
	failure := request.Proof.Evidence()
	if coordinator == nil || request.PaymentID == "" || request.AllocationID == "" ||
		request.InstructionDigest == "" || request.ExpectedVersion == 0 ||
		failure.Status != chainprojection.TransactionReverted ||
		failure.EvidenceHash == "" || failure.ReceiptPayloadHash == "" ||
		failure.FinalityPolicyHash == "" ||
		failure.HeaderAuthorityHash == "" ||
		failure.ReceiptHeaderSignatureHash == "" ||
		failure.HeadHeaderSignatureHash == "" ||
		failure.ReceiptsRoot == "" || failure.InclusionProofHash == "" ||
		failure.ObservedAt.IsZero() {
		return Plan{}, ErrInvalidTransition
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	plan, ok := coordinator.plans[request.PaymentID]
	if !ok || plan.AllocationID != request.AllocationID ||
		plan.InstructionDigest != request.InstructionDigest {
		return Plan{}, ErrPlanConflict
	}
	if plan.State == StateFailed && plan.FailureProof == failure {
		replayed := clonePlan(plan)
		replayed.Replayed = true
		return replayed, nil
	}
	if plan.Version != request.ExpectedVersion ||
		plan.State != StateSubmitted ||
		failure.TransactionHash != plan.Submission.TransactionHash ||
		failure.ChainID != plan.Submission.ChainID ||
		failure.Gateway != plan.Submission.Gateway ||
		failure.FinalityPolicyHash != plan.FinalityPolicyHash ||
		failure.ObservedAt.Before(plan.Submission.SubmittedAt) ||
		failure.ConfirmationDepth == 0 ||
		failure.HeadBlockNumber < failure.BlockNumber ||
		failure.HeadBlockNumber-failure.BlockNumber < failure.ConfirmationDepth {
		return Plan{}, ErrInvalidTransition
	}
	claim, exists := coordinator.modes.Lookup(plan.PaymentID)
	if !exists || claim.State != allocationmode.CanonicalSubmitted ||
		!claimMatchesPlan(claim, plan) {
		return Plan{}, ErrInvalidTransition
	}
	nextPlan := clonePlan(plan)
	nextPlan.State = StateFailed
	nextPlan.Version++
	nextPlan.FailureReason = "VERIFIED_TRANSACTION_REVERTED"
	nextPlan.FailureProof = failure
	if _, err := coordinator.modes.TransitionWithCommit(
		plan.PaymentID,
		plan.AllocationID,
		plan.InstructionDigest,
		allocationmode.CanonicalSubmitted,
		allocationmode.CanonicalFailed,
		func(nextClaim allocationmode.Claim) error {
			return coordinator.compareAndSwapDurable(
				StateSubmitted,
				plan.Version,
				nextPlan,
				nextClaim,
				failure.EvidenceHash,
				failure.ObservedAt,
			)
		},
	); err != nil {
		return Plan{}, errors.Join(ErrInvalidTransition, err)
	}
	plan = nextPlan
	coordinator.plans[plan.PaymentID] = plan
	return clonePlan(plan), nil
}

// Retry is the only route that can reacquire an exact failed/cancelled plan.
// It advances the plan version so a stale submitter cannot reuse old calldata.
func (coordinator *Coordinator) Retry(request RetryRequest) (Plan, error) {
	if coordinator == nil || request.PaymentID == "" || request.AllocationID == "" ||
		request.InstructionDigest == "" || request.ExpectedVersion == 0 ||
		request.EvidenceHash == "" || request.RetriedAt.IsZero() {
		return Plan{}, ErrInvalidTransition
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	plan, ok := coordinator.plans[request.PaymentID]
	if !ok || plan.AllocationID != request.AllocationID ||
		plan.InstructionDigest != request.InstructionDigest ||
		plan.State != StateFailed || plan.Version != request.ExpectedVersion ||
		coordinator.modes.IsReversed(plan.PaymentID) {
		return Plan{}, ErrInvalidTransition
	}
	nextPlan := clonePlan(plan)
	nextPlan.State = StatePrepared
	nextPlan.Version++
	nextPlan.PreparedAt = request.RetriedAt.UTC()
	nextPlan.Submission = Submission{}
	nextPlan.FailureReason = ""
	nextPlan.FailureProof = chainprojection.TransactionFailureEvidence{}
	if _, err := coordinator.modes.TransitionWithCommit(
		plan.PaymentID,
		plan.AllocationID,
		plan.InstructionDigest,
		allocationmode.CanonicalFailed,
		allocationmode.CanonicalPrepared,
		func(nextClaim allocationmode.Claim) error {
			return coordinator.compareAndSwapDurable(
				StateFailed,
				plan.Version,
				nextPlan,
				nextClaim,
				request.EvidenceHash,
				request.RetriedAt,
			)
		},
	); err != nil {
		return Plan{}, errors.Join(ErrPlanConflict, err)
	}
	plan = nextPlan
	coordinator.plans[plan.PaymentID] = plan
	return clonePlan(plan), nil
}

func (coordinator *Coordinator) RecordReorg(
	expectedVersion uint64,
	envelope chainprojection.VerifiedReorgEnvelope,
) (DurableReorgAuthority, error) {
	request := envelope.Evidence()
	deep := request.DepthClass == chainprojection.ReorgDeepFinality
	if coordinator == nil || expectedVersion == 0 ||
		request.PaymentID == "" || request.AllocationID == "" ||
		request.InstructionDigest == "" || request.ChainID == 0 ||
		request.Gateway == "" || request.EventID == "" ||
		request.TransactionHash == "" || request.OrphanedBlockHash == "" ||
		!validNonzeroHash(request.OrphanedEventEvidenceHash) ||
		request.RawEvidenceHash == "" || request.ReceiptsRoot == "" ||
		request.InclusionProofHash == "" ||
		request.OrphanedReceiptHeaderSignatureHash == "" ||
		request.OrphanedBlock == 0 || request.ReplacementBlock == 0 ||
		request.ReplacementBlockHash == "" ||
		request.ConfirmationDepth == 0 ||
		request.DetectedHead < request.OrphanedBlock ||
		request.DetectedHeadHash == "" || request.FinalityPolicyHash == "" ||
		request.HeaderAuthorityHash == "" ||
		request.ReplacementHeaderSignatureHash == "" ||
		request.DetectedHeadHeaderSignatureHash == "" ||
		(request.DepthClass != chainprojection.ReorgPreFinality && !deep) ||
		request.CompensationRequired != deep ||
		request.EvidenceHash == "" || request.DetectedAt.IsZero() {
		return DurableReorgAuthority{}, ErrInvalidReorg
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	plan, ok := coordinator.plans[request.PaymentID]
	if !ok || plan.AllocationID != request.AllocationID ||
		plan.InstructionDigest != request.InstructionDigest ||
		request.ChainID != plan.ChainID ||
		request.Gateway != plan.GatewayAddress ||
		request.FinalityPolicyHash != plan.FinalityPolicyHash {
		return DurableReorgAuthority{}, ErrInvalidReorg
	}
	for _, existing := range coordinator.reorgs {
		if existing.OrphanedEventID == request.EventID {
			if existing.EvidenceHash == request.EvidenceHash {
				return DurableReorgAuthority{evidence: existing}, nil
			}
			return DurableReorgAuthority{}, ErrInvalidReorg
		}
	}
	if plan.Version != expectedVersion {
		return DurableReorgAuthority{}, ErrInvalidReorg
	}
	evidence := ReorgEvidence{
		ReorgID:                            "reorg:" + request.EvidenceHash,
		PaymentID:                          plan.PaymentID,
		AllocationID:                       plan.AllocationID,
		InstructionDigest:                  plan.InstructionDigest,
		ChainID:                            request.ChainID,
		Gateway:                            request.Gateway,
		OrphanedEventID:                    request.EventID,
		OrphanedTxHash:                     request.TransactionHash,
		OrphanedEventEvidenceHash:          request.OrphanedEventEvidenceHash,
		RawEvidenceHash:                    request.RawEvidenceHash,
		TransactionIndex:                   request.TransactionIndex,
		ReceiptsRoot:                       request.ReceiptsRoot,
		InclusionProofHash:                 request.InclusionProofHash,
		OrphanedReceiptHeaderSignatureHash: request.OrphanedReceiptHeaderSignatureHash,
		OrphanedBlockHash:                  request.OrphanedBlockHash,
		OrphanedBlock:                      request.OrphanedBlock,
		ReplacementBlockHash:               request.ReplacementBlockHash,
		ReplacementBlock:                   request.ReplacementBlock,
		DepthClass:                         request.DepthClass,
		ConfirmationDepth:                  request.ConfirmationDepth,
		DetectedHead:                       request.DetectedHead,
		DetectedHeadHash:                   request.DetectedHeadHash,
		FinalityPolicyHash:                 request.FinalityPolicyHash,
		HeaderAuthorityHash:                request.HeaderAuthorityHash,
		ReplacementHeaderSignatureHash:     request.ReplacementHeaderSignatureHash,
		DetectedHeadHeaderSignatureHash:    request.DetectedHeadHeaderSignatureHash,
		Deep:                               deep,
		CompensationRequired:               request.CompensationRequired,
		EvidenceHash:                       request.EvidenceHash,
		SubmissionSubmittedAt:              plan.Submission.SubmittedAt.UTC(),
		DetectedAt:                         request.DetectedAt.UTC(),
	}
	claim, exists := coordinator.modes.Lookup(plan.PaymentID)
	if !exists {
		return DurableReorgAuthority{}, ErrInvalidReorg
	}
	nextPlan := clonePlan(plan)
	coordinator.reorgs = append(coordinator.reorgs, evidence)
	rollbackReorg := func() {
		coordinator.reorgs = coordinator.reorgs[:len(coordinator.reorgs)-1]
	}
	if plan.State == StateSubmitted || plan.State == StateQuarantined {
		if deep || request.TransactionHash != plan.Submission.TransactionHash ||
			request.OrphanedEventEvidenceHash != plan.EligibilityEvidenceHash ||
			request.ChainID != plan.Submission.ChainID ||
			request.Gateway != plan.Submission.Gateway ||
			plan.Submission.SubmittedAt.IsZero() ||
			request.DetectedAt.Before(plan.Submission.SubmittedAt) {
			rollbackReorg()
			return DurableReorgAuthority{}, ErrInvalidReorg
		}
		if claim.State == allocationmode.CanonicalQuarantined {
			nextPlan.State = StateQuarantined
			nextPlan.Version++
			nextPlan.FailureReason = "REORG_BEFORE_FINALITY_REVERSAL_PENDING"
			if err := coordinator.compareAndSwapDurable(
				StateQuarantined,
				plan.Version,
				nextPlan,
				claim,
				evidence.EvidenceHash,
				evidence.DetectedAt,
			); err != nil {
				rollbackReorg()
				return DurableReorgAuthority{}, errors.Join(ErrInvalidReorg, err)
			}
		} else {
			nextPlan.State = StateFailed
			nextPlan.Version++
			nextPlan.FailureReason = "REORG_BEFORE_FINALITY"
			if _, err := coordinator.modes.TransitionWithCommit(
				plan.PaymentID,
				plan.AllocationID,
				plan.InstructionDigest,
				allocationmode.CanonicalSubmitted,
				allocationmode.CanonicalFailed,
				func(nextClaim allocationmode.Claim) error {
					return coordinator.compareAndSwapDurable(
						StateSubmitted,
						plan.Version,
						nextPlan,
						nextClaim,
						evidence.EvidenceHash,
						evidence.DetectedAt,
					)
				},
			); err != nil {
				rollbackReorg()
				return DurableReorgAuthority{}, errors.Join(ErrInvalidReorg, err)
			}
		}
	} else if plan.State == StateConfirmed || plan.State == StateIncident {
		confirmation, confirmed := coordinator.confirmations[plan.PaymentID]
		projection := confirmation.AccountingProjection()
		if !deep || !confirmed ||
			request.EventID != projection.EventID ||
			request.TransactionHash != projection.TransactionHash ||
			request.OrphanedEventEvidenceHash != projection.EventEvidenceHash ||
			request.TransactionIndex != projection.TransactionIndex ||
			request.ReceiptsRoot != projection.ReceiptsRoot ||
			request.InclusionProofHash != projection.InclusionProofHash ||
			request.OrphanedReceiptHeaderSignatureHash !=
				projection.ReceiptHeaderSignatureHash ||
			request.OrphanedBlockHash != projection.BlockHash ||
			request.RawEvidenceHash != projection.GatewayPayloadHash ||
			request.ChainID != projection.ChainID ||
			request.Gateway != projection.Gateway ||
			request.FinalityPolicyHash != projection.FinalityPolicyHash ||
			request.HeaderAuthorityHash != projection.HeaderAuthorityHash ||
			request.ConfirmationDepth != projection.ConfirmationDepth ||
			request.DetectedHead < projection.FinalityHeadBlock ||
			request.DetectedAt.Before(projection.ConfirmedAt) {
			rollbackReorg()
			return DurableReorgAuthority{}, ErrInvalidReorg
		}
		nextPlan.State = StateIncident
		nextPlan.Version++
		if claim.State == allocationmode.CanonicalConfirmed {
			if _, err := coordinator.modes.TransitionWithCommit(
				plan.PaymentID,
				plan.AllocationID,
				plan.InstructionDigest,
				allocationmode.CanonicalConfirmed,
				allocationmode.CanonicalIncident,
				func(nextClaim allocationmode.Claim) error {
					return coordinator.compareAndSwapDurable(
						StateConfirmed,
						plan.Version,
						nextPlan,
						nextClaim,
						evidence.EvidenceHash,
						evidence.DetectedAt,
					)
				},
			); err != nil {
				rollbackReorg()
				return DurableReorgAuthority{}, errors.Join(ErrInvalidReorg, err)
			}
		} else if claim.State != allocationmode.CanonicalIncident {
			rollbackReorg()
			return DurableReorgAuthority{}, ErrInvalidReorg
		} else if err := coordinator.compareAndSwapDurable(
			StateIncident,
			plan.Version,
			nextPlan,
			claim,
			evidence.EvidenceHash,
			evidence.DetectedAt,
		); err != nil {
			rollbackReorg()
			return DurableReorgAuthority{}, errors.Join(ErrInvalidReorg, err)
		}
	} else {
		rollbackReorg()
		return DurableReorgAuthority{}, ErrInvalidReorg
	}
	plan = nextPlan
	coordinator.plans[plan.PaymentID] = plan
	return DurableReorgAuthority{evidence: evidence}, nil
}

func (coordinator *Coordinator) Plan(paymentID string) (Plan, bool) {
	if coordinator == nil {
		return Plan{}, false
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	plan, ok := coordinator.plans[paymentID]
	if !ok {
		return Plan{}, false
	}
	if claim, exists := coordinator.modes.Lookup(paymentID); exists &&
		claimMatchesPlan(claim, plan) {
		plan.State = stateFromCanonical(claim.State)
	} else if plan.State == StatePrepared || plan.State == StateQuarantined {
		plan.FailureReason = missingClaimReason(
			coordinator.modes,
			paymentID,
			exists,
			plan.State,
		)
		plan.State = StateFailed
		plan.Version++
		coordinator.plans[paymentID] = plan
	}
	return clonePlan(plan), true
}

func (coordinator *Coordinator) Confirmation(paymentID string) (Confirmation, bool) {
	if coordinator == nil {
		return Confirmation{}, false
	}
	coordinator.mu.RLock()
	defer coordinator.mu.RUnlock()
	record, ok := coordinator.confirmations[paymentID]
	return cloneConfirmation(record), ok
}

func (coordinator *Coordinator) Reorgs() []ReorgEvidence {
	if coordinator == nil {
		return nil
	}
	coordinator.mu.RLock()
	defer coordinator.mu.RUnlock()
	return slices.Clone(coordinator.reorgs)
}

// ReorgAuthority returns an opaque capability for a reorganization that has
// already won the coordinator's durable state transition. It remains available
// after restart because the complete authenticated evidence is in the snapshot.
func (coordinator *Coordinator) ReorgAuthority(
	reorgID string,
) (DurableReorgAuthority, bool) {
	if coordinator == nil || reorgID == "" {
		return DurableReorgAuthority{}, false
	}
	coordinator.mu.RLock()
	defer coordinator.mu.RUnlock()
	for _, evidence := range coordinator.reorgs {
		if evidence.ReorgID == reorgID {
			return DurableReorgAuthority{evidence: evidence}, true
		}
	}
	return DurableReorgAuthority{}, false
}

func validPrepare(request PrepareRequest) bool {
	source, sourceOK := positive(request.SourceUnits)
	target, targetOK := positive(request.TargetUnits)
	debt, debtOK := positive(request.ExpectedDebtUnits)
	difference, differenceOK := nonNegative(request.DifferenceUnits)
	return request.PaymentID != "" && request.AllocationID != "" &&
		request.LoanID != "" && request.ProviderID != "" &&
		request.ProviderReference != "" && request.PaymentStatus == payment.StatusFinal &&
		request.PaymentVersion > 0 &&
		request.SourceAssetID != "" && request.TargetAssetID != "" &&
		request.SourceAssetID != request.TargetAssetID && validAddress(request.TargetToken) &&
		request.Denomination != "" && request.SourcePrecision > 0 &&
		request.SourcePrecision == request.TargetPrecision &&
		sourceOK && targetOK && source.Cmp(target) == 0 &&
		debtOK && debt.Sign() > 0 &&
		request.ReconciliationID != "" && differenceOK && difference.Sign() == 0 &&
		request.UnmatchedItems == 0 && request.FinalityPolicyHash != "" &&
		request.ConversionPolicyHash != "" && request.PolicySetHash != "" &&
		request.EligibilityEvidenceHash != "" && len(request.OriginalJournalIDs) == 2 &&
		uniqueNonempty(request.OriginalJournalIDs) && request.ExpectedStateNonce > 0 &&
		request.ChainID > 0 && validAddress(request.GatewayAddress) &&
		validAddress(request.FinalizerAddress) &&
		validAddress(request.AttesterAddress) &&
		request.FinalizedAt.Nanosecond() == 0 &&
		request.ReversalDeadline.Nanosecond() == 0 &&
		!request.FinalizedAt.IsZero() &&
		request.ReversalDeadline.After(request.FinalizedAt) &&
		!request.PreparedAt.Before(request.ReversalDeadline) &&
		request.CorrelationID != ""
}

func validSubmission(request SubmissionRequest) bool {
	return request.PaymentID != "" && request.AllocationID != "" &&
		request.InstructionDigest != "" && request.ExpectedVersion > 0 &&
		request.ChainID > 0 && request.Gateway != "" && request.Sender != "" &&
		request.TransactionHash != "" && request.CalldataHash != "" &&
		!request.SubmittedAt.IsZero()
}

func gatewayProjection(
	verified chainprojection.VerifiedGatewayProjection,
) (gatewayEvent, chainprojection.FinalityProof) {
	event := verified.Settlement()
	return gatewayEvent{
		EventID:                    event.EventID,
		TransactionHash:            event.TransactionHash,
		LogIndex:                   event.LogIndex,
		BlockNumber:                event.UpdatedInBlock,
		BlockHash:                  event.BlockHash,
		ChainID:                    event.ChainID,
		Gateway:                    event.Gateway,
		PaymentID:                  event.PaymentID,
		AllocationID:               event.AllocationID,
		LoanID:                     event.LoanID,
		InstructionDigest:          event.InstructionDigest,
		PolicySetHash:              event.PolicySetHash,
		LoanAccount:                event.LoanAccount,
		Finalizer:                  event.Finalizer,
		Attester:                   event.Attester,
		SourceAssetID:              event.SourceAssetID,
		TargetAssetID:              event.TargetAssetID,
		TargetToken:                event.TargetToken,
		SourceUnits:                event.SourceUnits,
		GrossUnits:                 event.GrossUnits,
		ProviderIDHash:             event.ProviderIDHash,
		ProviderReferenceHash:      event.ProviderReferenceHash,
		ReconciliationID:           event.ReconciliationID,
		ReconciliationCommitment:   event.ReconciliationCommitment,
		OriginalJournalSetHash:     event.OriginalJournalSetHash,
		ConversionPolicyHash:       event.ConversionPolicyHash,
		FinalityPolicyHash:         event.FinalityPolicyHash,
		EvidenceHash:               event.EvidenceHash,
		JournalRef:                 event.JournalRef,
		ProviderFinalizedAt:        event.ProviderFinalizedAt,
		ReversalDeadline:           event.ReversalDeadline,
		DebtBeforeUnits:            event.DebtBeforeUnits,
		PrincipalUnits:             event.PrincipalUnits,
		RefundableExcess:           event.RefundableExcessUnits,
		DebtAfterUnits:             event.DebtAfterUnits,
		StateNonceBefore:           event.StateNonceBefore,
		StateNonceAfter:            event.StateNonceAfter,
		LenderID:                   event.LenderID,
		BorrowerID:                 event.BorrowerID,
		RawEvidenceHash:            event.RawEvidenceHash,
		TransactionIndex:           event.TransactionIndex,
		ReceiptsRoot:               event.ReceiptsRoot,
		InclusionProofHash:         event.InclusionProofHash,
		ReceiptHeaderSignatureHash: event.ReceiptHeaderSignatureHash,
	}, verified.Proof()
}

func validEvent(
	plan Plan,
	event gatewayEvent,
	proof chainprojection.FinalityProof,
) bool {
	gross, grossOK := positive(event.GrossUnits)
	source, sourceOK := positive(event.SourceUnits)
	principal, principalOK := positive(event.PrincipalUnits)
	excess, excessOK := nonNegative(event.RefundableExcess)
	before, beforeOK := positive(event.DebtBeforeUnits)
	after, afterOK := nonNegative(event.DebtAfterUnits)
	instruction := plan.Instruction
	return proof.Finality == chainprojection.Final &&
		proof.ConfirmationDepth > 0 &&
		proof.HeadBlockNumber >= event.BlockNumber &&
		proof.HeadBlockNumber-event.BlockNumber >= proof.ConfirmationDepth &&
		proof.HeadBlockHash != "" &&
		proof.EvidenceHash != "" &&
		proof.FinalityPolicyHash == plan.FinalityPolicyHash &&
		proof.HeaderAuthorityHash != "" &&
		proof.HeadHeaderSignatureHash != "" &&
		!proof.ObservedAt.IsZero() &&
		!plan.Submission.SubmittedAt.IsZero() &&
		!proof.ObservedAt.Before(plan.Submission.SubmittedAt) &&
		(plan.State == StateSubmitted || plan.State == StateQuarantined) &&
		event.EventID != "" &&
		event.ReceiptsRoot != "" &&
		event.InclusionProofHash != "" &&
		event.ReceiptHeaderSignatureHash != "" &&
		event.TransactionHash == plan.Submission.TransactionHash &&
		event.ChainID == plan.Submission.ChainID &&
		event.Gateway == plan.Submission.Gateway && event.BlockNumber > 0 &&
		event.BlockHash != "" && event.LoanID == plan.LoanID &&
		event.PaymentID == plan.PaymentID && event.AllocationID == plan.AllocationID &&
		event.InstructionDigest == plan.InstructionDigest &&
		event.PolicySetHash == plan.PolicySetHash &&
		event.Finalizer == plan.FinalizerAddress &&
		event.Attester == plan.AttesterAddress &&
		event.SourceAssetID == plan.SourceAssetID &&
		event.TargetAssetID == plan.TargetAssetID &&
		event.TargetToken == plan.TargetToken &&
		event.SourceUnits == plan.SourceUnits &&
		event.GrossUnits == plan.TargetUnits &&
		event.ProviderIDHash == instruction.ProviderIDHash &&
		event.ProviderReferenceHash == instruction.ProviderReferenceHash &&
		event.ReconciliationID == instruction.ReconciliationID &&
		event.ReconciliationCommitment == instruction.ReconciliationCommitment &&
		event.OriginalJournalSetHash == instruction.OriginalJournalSetHash &&
		event.ConversionPolicyHash == instruction.ConversionPolicyHash &&
		event.FinalityPolicyHash == instruction.FinalityPolicyHash &&
		event.EvidenceHash == instruction.EvidenceHash &&
		event.JournalRef == instruction.JournalRef &&
		event.ProviderFinalizedAt == instruction.FinalizedAt &&
		event.ReversalDeadline == instruction.ReversalDeadline &&
		event.PrincipalUnits == plan.PrincipalUnits &&
		event.RefundableExcess == plan.RefundableExcessUnits &&
		event.DebtBeforeUnits == plan.DebtBeforeUnits &&
		event.DebtAfterUnits == plan.DebtAfterUnits &&
		event.StateNonceBefore == plan.ExpectedStateNonce &&
		event.StateNonceAfter > event.StateNonceBefore &&
		event.LenderID != "" && event.BorrowerID != "" &&
		event.EvidenceHash != "" && event.RawEvidenceHash != "" &&
		sourceOK && grossOK && source.Cmp(gross) == 0 &&
		principalOK && excessOK && beforeOK && afterOK &&
		new(big.Int).Add(new(big.Int).Set(principal), excess).Cmp(gross) == 0 &&
		new(big.Int).Add(new(big.Int).Set(principal), after).Cmp(before) == 0
}

func sameGatewayEvent(
	record Confirmation,
	event gatewayEvent,
) bool {
	projection := record.value.Projection
	return projection.EventID == event.EventID &&
		projection.TransactionHash == event.TransactionHash &&
		projection.BlockHash == event.BlockHash &&
		projection.TransactionIndex == event.TransactionIndex &&
		projection.ReceiptsRoot == event.ReceiptsRoot &&
		projection.InclusionProofHash == event.InclusionProofHash &&
		projection.ReceiptHeaderSignatureHash ==
			event.ReceiptHeaderSignatureHash &&
		projection.LogIndex == event.LogIndex &&
		projection.EventEvidenceHash == event.EvidenceHash &&
		projection.GatewayPayloadHash == event.RawEvidenceHash &&
		projection.InstructionDigest == event.InstructionDigest &&
		projection.ChainID == event.ChainID &&
		projection.Gateway == event.Gateway &&
		projection.LoanID == event.LoanID &&
		projection.LoanAccount == event.LoanAccount &&
		projection.PaymentID == event.PaymentID &&
		projection.AllocationID == event.AllocationID &&
		projection.TargetAssetID == event.TargetAssetID &&
		projection.TargetToken == event.TargetToken &&
		projection.TargetUnits == event.GrossUnits &&
		projection.PrincipalUnits == event.PrincipalUnits &&
		projection.RefundableExcessUnits == event.RefundableExcess &&
		projection.DebtBeforeUnits == event.DebtBeforeUnits &&
		projection.DebtAfterUnits == event.DebtAfterUnits &&
		projection.StateNonceBefore == event.StateNonceBefore &&
		projection.StateNonceAfter == event.StateNonceAfter &&
		projection.Finalizer == event.Finalizer &&
		projection.Attester == event.Attester &&
		projection.LenderID == event.LenderID &&
		projection.BorrowerID == event.BorrowerID
}

func claimMatchesPlan(claim allocationmode.Claim, plan Plan) bool {
	return claim.Mode == allocationmode.ModeCanonicalGateway &&
		claim.PaymentID == plan.PaymentID &&
		claim.AllocationID == plan.AllocationID &&
		claim.Digest == plan.InstructionDigest
}

func submittedPendingMatchesPlan(
	pending PendingReversalSnapshot,
	plan Plan,
) bool {
	return pending.OriginState == StateSubmitted &&
		pending.PaymentID == plan.PaymentID &&
		pending.AllocationID == plan.AllocationID &&
		pending.InstructionDigest == plan.InstructionDigest &&
		pending.SubmissionChainID == plan.Submission.ChainID &&
		pending.SubmissionGateway == plan.Submission.Gateway &&
		pending.SubmissionTxHash == plan.Submission.TransactionHash &&
		pending.SubmissionSubmittedAt.Equal(plan.Submission.SubmittedAt.UTC())
}

func missingClaimReason(
	modes *allocationmode.Registry,
	paymentID string,
	claimExists bool,
	planState State,
) string {
	if modes.IsReversed(paymentID) {
		if planState == StateQuarantined {
			return "PAYMENT_REVERSED"
		}
		return "REVERSED_BEFORE_SUBMISSION"
	}
	if claimExists {
		return "ALLOCATION_MODE_CONFLICT"
	}
	return "MODE_CLAIM_RELEASED"
}

func positive(value string) (*big.Int, bool) {
	number, ok := new(big.Int).SetString(value, 10)
	return number, ok && number.Sign() > 0 && number.String() == value
}

func nonNegative(value string) (*big.Int, bool) {
	number, ok := new(big.Int).SetString(value, 10)
	return number, ok && number.Sign() >= 0 && number.String() == value
}

func uniqueNonempty(values []string) bool {
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		if value == "" {
			return false
		}
		if _, exists := seen[value]; exists {
			return false
		}
		seen[value] = struct{}{}
	}
	return true
}

func validAddress(value string) bool {
	decoded, err := decodeFixedHex(value, 20)
	if err != nil {
		return false
	}
	for _, item := range decoded {
		if item != 0 {
			return true
		}
	}
	return false
}

func validNonzeroHash(value string) bool {
	decoded, err := decodeFixedHex(value, 32)
	if err != nil {
		return false
	}
	for _, item := range decoded {
		if item != 0 {
			return true
		}
	}
	return false
}

func digest(domain string, encoded []byte) string {
	hash := sha256.Sum256(append(append([]byte(domain), 0), encoded...))
	return hex.EncodeToString(hash[:])
}

func stateFromCanonical(state allocationmode.CanonicalState) State {
	switch state {
	case allocationmode.CanonicalPrepared:
		return StatePrepared
	case allocationmode.CanonicalSubmitted:
		return StateSubmitted
	case allocationmode.CanonicalConfirmed:
		return StateConfirmed
	case allocationmode.CanonicalFailed:
		return StateFailed
	case allocationmode.CanonicalQuarantined:
		return StateQuarantined
	case allocationmode.CanonicalIncident:
		return StateIncident
	default:
		return ""
	}
}

func clonePlan(plan Plan) Plan {
	plan.OriginalJournalIDs = slices.Clone(plan.OriginalJournalIDs)
	return plan
}

func cloneConfirmation(record Confirmation) Confirmation {
	record.value.Projection.OriginalJournalIDs =
		slices.Clone(record.value.Projection.OriginalJournalIDs)
	return record
}
