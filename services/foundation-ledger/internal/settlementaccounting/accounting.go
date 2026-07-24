// Package settlementaccounting posts finalized Phase 7C canonical settlement
// evidence to the foundation ledger. It does not execute payments or mutate loans.
package settlementaccounting

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
	"github.com/unified-finance/unified/services/payment-orchestrator/settlement"
)

const (
	AccountProviderBankAsset      = "1100"
	AccountProviderCardAsset      = "1120"
	AccountRestrictedToken        = "1260"
	AccountPrincipalReceivable    = "1310"
	AccountLenderRepaymentPayable = "2130"
	AccountRefundPayable          = "2150"
	AccountLenderPrincipalClaims  = "2310"
	AccountUnallocatedPayment     = "9120"
	AccountConversionClearing     = "9160"
)

var (
	ErrInvalidConfirmation   = errors.New("invalid canonical settlement confirmation")
	ErrConfirmationConflict  = errors.New("canonical settlement confirmation conflict")
	ErrPaymentAlreadyClaimed = errors.New("payment already has an economic allocation")
	ErrInvalidSourceEvidence = errors.New("invalid phase 7a source evidence")
	ErrInvalidReorg          = errors.New("invalid canonical settlement reorg")
	ErrReorgConflict         = errors.New("canonical settlement reorg conflict")
)

// Confirmation is readable durable evidence. It is deliberately not posting
// authority: Poster accepts only VerifiedConfirmation, whose private marker can
// be created only from the coordinator's opaque settlement.Confirmation.
type Confirmation struct {
	CanonicalizationID           string
	InstructionDigest            string
	PaymentID                    string
	AllocationID                 string
	LoanID                       string
	ChainID                      uint64
	Gateway                      string
	LoanAccount                  string
	Finalizer                    string
	Attester                     string
	BorrowerID                   string
	LenderID                     string
	SourceAssetID                string
	TargetAssetID                string
	TargetToken                  string
	SourceUnits                  string
	TargetUnits                  string
	PrincipalUnits               string
	RefundableExcessUnits        string
	DebtBeforeUnits              string
	DebtAfterUnits               string
	StateNonceBefore             uint64
	StateNonceAfter              uint64
	PolicySetHash                string
	ProviderIDHash               string
	ProviderReferenceHash        string
	ReconciliationCommitment     string
	OriginalJournalSetHash       string
	ConversionPolicyHash         string
	FinalityPolicyHash           string
	InstructionEvidenceHash      string
	JournalRef                   string
	ProviderFinalizedAt          uint64
	ReversalDeadline             uint64
	OriginalProvisionalJournalID string
	OriginalFinalJournalID       string
	ReconciliationID             string
	ConversionEvidenceHash       string
	GatewayTransactionHash       string
	GatewayEventID               string
	GatewayBlockHash             string
	GatewayBlockNumber           uint64
	GatewayLogIndex              uint32
	TransactionIndex             uint64
	ReceiptsRoot                 string
	InclusionProofHash           string
	ConfirmationDepth            uint64
	FinalityHeadBlock            uint64
	FinalityHeadHash             string
	HeaderAuthorityHash          string
	ReceiptHeaderSignatureHash   string
	HeadHeaderSignatureHash      string
	FinalityEvidenceHash         string
	EventEvidenceHash            string
	CorrelationID                string
	RawGatewayPayloadHash        string
	ConfirmedAt                  time.Time
}

type VerifiedConfirmation struct {
	evidence Confirmation
}

// DurableConfirmationAuthority is an opaque ledger-issued capability. Its
// private fields can only be populated by matching a coordinator confirmation
// against the canonical plan, conversion, gateway event, and finality records
// already committed to the foundation database.
type DurableConfirmationAuthority struct {
	canonicalizationID     string
	conversionEvidenceHash string
	paymentID              string
	allocationID           string
	instructionDigest      string
	transactionHash        string
	gatewayEventID         string
	eventEvidenceHash      string
	rawPayloadHash         string
	finalityEvidenceHash   string
	transactionIndex       uint64
	receiptsRoot           string
	inclusionProofHash     string
	finalityPolicyHash     string
	headerAuthorityHash    string
	receiptHeaderSigHash   string
	headHeaderSigHash      string
}

func (verified VerifiedConfirmation) Evidence() Confirmation {
	return cloneAccountingConfirmation(verified.evidence)
}

const loadDurableConfirmationAuthoritySQL = `
SELECT
    plan.canonicalization_id,
    conversion.evidence_hash
FROM canonicalization_plan AS plan
JOIN canonical_settlement_conversion AS conversion
  ON conversion.canonicalization_id = plan.canonicalization_id
JOIN canonical_settlement_confirmation AS confirmation
  ON confirmation.canonicalization_id = plan.canonicalization_id
JOIN canonical_gateway_event_projection AS event
  ON event.gateway_event_id = confirmation.gateway_event_id
JOIN canonical_coordinator_state_history AS confirmed_state
  ON confirmed_state.payment_id = plan.payment_id
 AND confirmed_state.instruction_digest = plan.instruction_digest
 AND confirmed_state.state = 'CONFIRMED'
WHERE plan.payment_id = $1
  AND plan.allocation_id = $2
  AND plan.instruction_digest = $3
  AND confirmation.transaction_hash = $4
  AND confirmation.gateway_event_id = $5
  AND confirmation.raw_payload_hash = $6
  AND confirmation.finality_evidence_hash = $7
  AND event.chain_id = $8
  AND event.gateway_address = $9
  AND event.block_hash = $10
  AND event.block_number = $11
  AND event.log_index = $12
  AND event.transaction_index = $13
  AND event.receipts_root = $14
  AND event.inclusion_proof_hash = $15
  AND event.finality_policy_hash = $16
  AND event.header_authority_hash = $17
  AND event.receipt_header_signature_hash = $18
  AND event.head_header_signature_hash = $19
  AND confirmation.transaction_index = event.transaction_index
  AND confirmation.receipts_root = event.receipts_root
  AND confirmation.inclusion_proof_hash = event.inclusion_proof_hash
  AND confirmation.finality_policy_hash = event.finality_policy_hash
  AND confirmation.header_authority_hash = event.header_authority_hash
  AND confirmation.receipt_header_signature_hash =
      event.receipt_header_signature_hash
  AND confirmation.head_header_signature_hash =
      event.head_header_signature_hash
  AND event.raw_payload_hash = $6
  AND confirmed_state.snapshot #>> '{Confirmation,EventID}' = $5
  AND confirmed_state.snapshot #>> '{Confirmation,EventEvidenceHash}' = $20
  AND confirmed_state.snapshot #>> '{Confirmation,GatewayPayloadHash}' = $6`

type authorityRow interface {
	Scan(dest ...any) error
}

type authorityQueryer interface {
	QueryRowContext(context.Context, string, ...any) authorityRow
}

type sqlAuthorityQueryer struct {
	db *sql.DB
}

func (queryer sqlAuthorityQueryer) QueryRowContext(
	ctx context.Context,
	query string,
	args ...any,
) authorityRow {
	return queryer.db.QueryRowContext(ctx, query, args...)
}

// LoadDurableConfirmationAuthority derives the ledger-owned identities from
// committed evidence. No caller-supplied canonicalization or conversion
// identity enters the resulting capability.
func LoadDurableConfirmationAuthority(
	ctx context.Context,
	db *sql.DB,
	input settlement.Confirmation,
) (DurableConfirmationAuthority, error) {
	if db == nil {
		return DurableConfirmationAuthority{}, ErrInvalidConfirmation
	}
	return loadDurableConfirmationAuthority(
		ctx,
		sqlAuthorityQueryer{db: db},
		input,
	)
}

func loadDurableConfirmationAuthority(
	ctx context.Context,
	queryer authorityQueryer,
	input settlement.Confirmation,
) (DurableConfirmationAuthority, error) {
	projection := input.AccountingProjection()
	if queryer == nil || projection.PaymentID == "" ||
		projection.AllocationID == "" || projection.InstructionDigest == "" ||
		projection.TransactionHash == "" || projection.EventID == "" ||
		!nonzeroCanonicalHash(projection.EventEvidenceHash) ||
		projection.GatewayPayloadHash == "" ||
		projection.FinalityEvidenceHash == "" ||
		!canonicalHash(projection.FinalityPolicyHash) ||
		!canonicalHash(projection.ReceiptsRoot) ||
		!canonicalHash(projection.InclusionProofHash) ||
		!canonicalHash(projection.HeaderAuthorityHash) ||
		!canonicalHash(projection.ReceiptHeaderSignatureHash) ||
		!canonicalHash(projection.HeadHeaderSignatureHash) {
		return DurableConfirmationAuthority{}, ErrInvalidConfirmation
	}
	authority := DurableConfirmationAuthority{
		paymentID:            projection.PaymentID,
		allocationID:         projection.AllocationID,
		instructionDigest:    projection.InstructionDigest,
		transactionHash:      projection.TransactionHash,
		gatewayEventID:       projection.EventID,
		eventEvidenceHash:    projection.EventEvidenceHash,
		rawPayloadHash:       projection.GatewayPayloadHash,
		finalityEvidenceHash: projection.FinalityEvidenceHash,
		transactionIndex:     projection.TransactionIndex,
		receiptsRoot:         projection.ReceiptsRoot,
		inclusionProofHash:   projection.InclusionProofHash,
		finalityPolicyHash:   projection.FinalityPolicyHash,
		headerAuthorityHash:  projection.HeaderAuthorityHash,
		receiptHeaderSigHash: projection.ReceiptHeaderSignatureHash,
		headHeaderSigHash:    projection.HeadHeaderSignatureHash,
	}
	err := queryer.QueryRowContext(
		ctx,
		loadDurableConfirmationAuthoritySQL,
		projection.PaymentID,
		projection.AllocationID,
		projection.InstructionDigest,
		projection.TransactionHash,
		projection.EventID,
		projection.GatewayPayloadHash,
		projection.FinalityEvidenceHash,
		projection.ChainID,
		projection.Gateway,
		projection.BlockHash,
		projection.BlockNumber,
		projection.LogIndex,
		strconv.FormatUint(projection.TransactionIndex, 10),
		projection.ReceiptsRoot,
		projection.InclusionProofHash,
		projection.FinalityPolicyHash,
		projection.HeaderAuthorityHash,
		projection.ReceiptHeaderSignatureHash,
		projection.HeadHeaderSignatureHash,
		projection.EventEvidenceHash,
	).Scan(
		&authority.canonicalizationID,
		&authority.conversionEvidenceHash,
	)
	if err != nil || authority.canonicalizationID == "" ||
		authority.conversionEvidenceHash == "" {
		return DurableConfirmationAuthority{}, ErrInvalidConfirmation
	}
	return authority, nil
}

// VerifyConfirmation combines two independently opaque authorities: the
// coordinator-issued finalized projection and the database-issued durable
// metadata capability.
func VerifyConfirmation(
	authority DurableConfirmationAuthority,
	input settlement.Confirmation,
) (VerifiedConfirmation, error) {
	projection := input.AccountingProjection()
	if authority.canonicalizationID == "" ||
		authority.conversionEvidenceHash == "" ||
		authority.paymentID != projection.PaymentID ||
		authority.allocationID != projection.AllocationID ||
		authority.instructionDigest != projection.InstructionDigest ||
		authority.transactionHash != projection.TransactionHash ||
		authority.gatewayEventID != projection.EventID ||
		authority.eventEvidenceHash != projection.EventEvidenceHash ||
		authority.rawPayloadHash != projection.GatewayPayloadHash ||
		authority.finalityEvidenceHash != projection.FinalityEvidenceHash ||
		authority.transactionIndex != projection.TransactionIndex ||
		authority.receiptsRoot != projection.ReceiptsRoot ||
		authority.inclusionProofHash != projection.InclusionProofHash ||
		authority.finalityPolicyHash != projection.FinalityPolicyHash ||
		authority.headerAuthorityHash != projection.HeaderAuthorityHash ||
		authority.receiptHeaderSigHash !=
			projection.ReceiptHeaderSignatureHash ||
		authority.headHeaderSigHash != projection.HeadHeaderSignatureHash ||
		projection.InstructionDigest == "" || len(projection.OriginalJournalIDs) != 2 {
		return VerifiedConfirmation{}, ErrInvalidConfirmation
	}
	var provisionalID string
	var finalID string
	for _, journalID := range projection.OriginalJournalIDs {
		switch {
		case strings.HasSuffix(journalID, ":provisional"):
			provisionalID = journalID
		case strings.HasSuffix(journalID, ":final"):
			finalID = journalID
		default:
			return VerifiedConfirmation{}, ErrInvalidConfirmation
		}
	}
	if provisionalID != "payment:"+projection.PaymentID+":provisional" ||
		finalID != "payment:"+projection.PaymentID+":final" {
		return VerifiedConfirmation{}, ErrInvalidConfirmation
	}
	confirmation := Confirmation{
		CanonicalizationID:           authority.canonicalizationID,
		InstructionDigest:            projection.InstructionDigest,
		PaymentID:                    projection.PaymentID,
		AllocationID:                 projection.AllocationID,
		LoanID:                       projection.LoanID,
		ChainID:                      projection.ChainID,
		Gateway:                      projection.Gateway,
		LoanAccount:                  projection.LoanAccount,
		Finalizer:                    projection.Finalizer,
		Attester:                     projection.Attester,
		BorrowerID:                   projection.BorrowerID,
		LenderID:                     projection.LenderID,
		SourceAssetID:                projection.SourceAssetID,
		TargetAssetID:                projection.TargetAssetID,
		TargetToken:                  projection.TargetToken,
		SourceUnits:                  projection.SourceUnits,
		TargetUnits:                  projection.TargetUnits,
		PrincipalUnits:               projection.PrincipalUnits,
		RefundableExcessUnits:        projection.RefundableExcessUnits,
		DebtBeforeUnits:              projection.DebtBeforeUnits,
		DebtAfterUnits:               projection.DebtAfterUnits,
		StateNonceBefore:             projection.StateNonceBefore,
		StateNonceAfter:              projection.StateNonceAfter,
		PolicySetHash:                projection.PolicySetHash,
		ProviderIDHash:               projection.ProviderIDHash,
		ProviderReferenceHash:        projection.ProviderReferenceHash,
		ReconciliationCommitment:     projection.ReconciliationCommitment,
		OriginalJournalSetHash:       projection.OriginalJournalSetHash,
		ConversionPolicyHash:         projection.ConversionPolicyHash,
		FinalityPolicyHash:           projection.FinalityPolicyHash,
		InstructionEvidenceHash:      projection.EligibilityEvidenceHash,
		JournalRef:                   projection.JournalRef,
		ProviderFinalizedAt:          projection.ProviderFinalizedAt,
		ReversalDeadline:             projection.ReversalDeadlineUnix,
		OriginalProvisionalJournalID: provisionalID,
		OriginalFinalJournalID:       finalID,
		ReconciliationID:             projection.ReconciliationID,
		ConversionEvidenceHash:       authority.conversionEvidenceHash,
		GatewayTransactionHash:       projection.TransactionHash,
		GatewayEventID:               projection.EventID,
		GatewayBlockHash:             projection.BlockHash,
		GatewayBlockNumber:           projection.BlockNumber,
		GatewayLogIndex:              projection.LogIndex,
		TransactionIndex:             projection.TransactionIndex,
		ReceiptsRoot:                 projection.ReceiptsRoot,
		InclusionProofHash:           projection.InclusionProofHash,
		ConfirmationDepth:            projection.ConfirmationDepth,
		FinalityHeadBlock:            projection.FinalityHeadBlock,
		FinalityHeadHash:             projection.FinalityHeadHash,
		HeaderAuthorityHash:          projection.HeaderAuthorityHash,
		ReceiptHeaderSignatureHash:   projection.ReceiptHeaderSignatureHash,
		HeadHeaderSignatureHash:      projection.HeadHeaderSignatureHash,
		FinalityEvidenceHash:         projection.FinalityEvidenceHash,
		EventEvidenceHash:            projection.EventEvidenceHash,
		CorrelationID:                projection.CorrelationID,
		RawGatewayPayloadHash:        projection.GatewayPayloadHash,
		ConfirmedAt:                  projection.ConfirmedAt,
	}
	if !validConfirmation(confirmation) {
		return VerifiedConfirmation{}, ErrInvalidConfirmation
	}
	return VerifiedConfirmation{evidence: confirmation}, nil
}

// ReorgEvidence is readable durable evidence, but it is not itself authority to
// compensate accounting. Only VerifiedReorg, constructed from the coordinator's
// durable opaque authority, is accepted by CompensateReorg.
type ReorgEvidence struct {
	ReorgID                             string
	CanonicalizationID                  string
	PaymentID                           string
	AllocationID                        string
	InstructionDigest                   string
	ChainID                             uint64
	Gateway                             string
	GatewayTransactionHash              string
	GatewayEventID                      string
	TransactionIndex                    uint64
	ReceiptsRoot                        string
	InclusionProofHash                  string
	FinalityPolicyHash                  string
	HeaderAuthorityHash                 string
	ReceiptHeaderSignatureHash          string
	ConfirmationHeadHeaderSignatureHash string
	ReplacementHeaderSignatureHash      string
	DetectedHeadHeaderSignatureHash     string
	OrphanedBlockHash                   string
	OrphanedBlockNumber                 uint64
	ReplacementBlockHash                string
	ReplacementBlockNumber              uint64
	ConfirmationDepth                   uint64
	DetectedHeadBlock                   uint64
	DetectedHeadHash                    string
	OrphanedEventEvidenceHash           string
	OrphanedRawPayloadHash              string
	Deep                                bool
	Owner                               string
	EvidenceHash                        string
	SubmissionSubmittedAt               time.Time
	OccurredAt                          time.Time
	ResolutionDeadline                  time.Time
}

type VerifiedReorg struct {
	evidence ReorgEvidence
}

type ReorgMetadata struct {
	ReorgID            string
	CanonicalizationID string
	Owner              string
	ResolutionDeadline time.Time
}

func (verified VerifiedReorg) Evidence() ReorgEvidence {
	return verified.evidence
}

// VerifyReorg is the sole constructor for accounting reorg authority. The
// durable capability can only be minted by the coordinator after its state
// transition commits, and can be reconstructed from that exact snapshot.
func VerifyReorg(
	metadata ReorgMetadata,
	coordinatorConfirmation settlement.Confirmation,
	authority settlement.DurableReorgAuthority,
) (VerifiedReorg, error) {
	projection := coordinatorConfirmation.AccountingProjection()
	reorg := authority.Evidence()
	if metadata.ReorgID == "" || metadata.CanonicalizationID == "" ||
		metadata.ReorgID != reorg.ReorgID ||
		metadata.Owner == "" || metadata.ResolutionDeadline.IsZero() ||
		reorg.PaymentID != projection.PaymentID ||
		reorg.AllocationID != projection.AllocationID ||
		reorg.InstructionDigest != projection.InstructionDigest ||
		reorg.ChainID != projection.ChainID ||
		reorg.Gateway != projection.Gateway ||
		reorg.OrphanedTxHash != projection.TransactionHash ||
		reorg.OrphanedEventID != projection.EventID ||
		reorg.TransactionIndex != projection.TransactionIndex ||
		reorg.ReceiptsRoot != projection.ReceiptsRoot ||
		reorg.InclusionProofHash != projection.InclusionProofHash ||
		reorg.OrphanedReceiptHeaderSignatureHash !=
			projection.ReceiptHeaderSignatureHash ||
		reorg.FinalityPolicyHash != projection.FinalityPolicyHash ||
		reorg.HeaderAuthorityHash != projection.HeaderAuthorityHash ||
		!canonicalHash(projection.FinalityPolicyHash) ||
		!canonicalHash(projection.HeaderAuthorityHash) ||
		!canonicalHash(projection.HeadHeaderSignatureHash) ||
		!canonicalHash(reorg.ReceiptsRoot) ||
		!canonicalHash(reorg.InclusionProofHash) ||
		!canonicalHash(reorg.OrphanedReceiptHeaderSignatureHash) ||
		!canonicalHash(reorg.ReplacementHeaderSignatureHash) ||
		!canonicalHash(reorg.DetectedHeadHeaderSignatureHash) ||
		reorg.OrphanedBlockHash != projection.BlockHash ||
		reorg.OrphanedBlock != projection.BlockNumber ||
		reorg.OrphanedEventEvidenceHash != projection.EventEvidenceHash ||
		reorg.RawEvidenceHash != projection.GatewayPayloadHash ||
		!nonzeroCanonicalHash(reorg.OrphanedEventEvidenceHash) ||
		reorg.ConfirmationDepth != projection.ConfirmationDepth ||
		reorg.ReplacementBlockHash == "" || reorg.ReplacementBlock == 0 ||
		reorg.DetectedHead < reorg.OrphanedBlock ||
		reorg.DetectedHeadHash == "" ||
		!reorg.Deep || !reorg.CompensationRequired ||
		reorg.EvidenceHash == "" || reorg.DetectedAt.IsZero() ||
		reorg.SubmissionSubmittedAt.IsZero() ||
		reorg.SubmissionSubmittedAt.After(reorg.DetectedAt) ||
		reorg.SubmissionSubmittedAt.After(projection.ConfirmedAt) ||
		!metadata.ResolutionDeadline.After(reorg.DetectedAt) {
		return VerifiedReorg{}, ErrInvalidReorg
	}
	return VerifiedReorg{evidence: ReorgEvidence{
		ReorgID:                             metadata.ReorgID,
		CanonicalizationID:                  metadata.CanonicalizationID,
		PaymentID:                           reorg.PaymentID,
		AllocationID:                        reorg.AllocationID,
		InstructionDigest:                   reorg.InstructionDigest,
		ChainID:                             reorg.ChainID,
		Gateway:                             reorg.Gateway,
		GatewayTransactionHash:              reorg.OrphanedTxHash,
		GatewayEventID:                      reorg.OrphanedEventID,
		TransactionIndex:                    reorg.TransactionIndex,
		ReceiptsRoot:                        reorg.ReceiptsRoot,
		InclusionProofHash:                  reorg.InclusionProofHash,
		FinalityPolicyHash:                  projection.FinalityPolicyHash,
		HeaderAuthorityHash:                 projection.HeaderAuthorityHash,
		ReceiptHeaderSignatureHash:          reorg.OrphanedReceiptHeaderSignatureHash,
		ConfirmationHeadHeaderSignatureHash: projection.HeadHeaderSignatureHash,
		ReplacementHeaderSignatureHash:      reorg.ReplacementHeaderSignatureHash,
		DetectedHeadHeaderSignatureHash:     reorg.DetectedHeadHeaderSignatureHash,
		OrphanedBlockHash:                   reorg.OrphanedBlockHash,
		OrphanedBlockNumber:                 reorg.OrphanedBlock,
		ReplacementBlockHash:                reorg.ReplacementBlockHash,
		ReplacementBlockNumber:              reorg.ReplacementBlock,
		ConfirmationDepth:                   reorg.ConfirmationDepth,
		DetectedHeadBlock:                   reorg.DetectedHead,
		DetectedHeadHash:                    reorg.DetectedHeadHash,
		OrphanedEventEvidenceHash:           reorg.OrphanedEventEvidenceHash,
		OrphanedRawPayloadHash:              reorg.RawEvidenceHash,
		Deep:                                reorg.Deep,
		Owner:                               metadata.Owner,
		EvidenceHash:                        reorg.EvidenceHash,
		SubmissionSubmittedAt:               reorg.SubmissionSubmittedAt.UTC(),
		OccurredAt:                          reorg.DetectedAt.UTC(),
		ResolutionDeadline:                  metadata.ResolutionDeadline.UTC(),
	}}, nil
}

// Incident is the owned, append-only operational consequence of compensating a
// settlement whose finalized chain event was later removed.
type Incident struct {
	IncidentID             string
	ReorgID                string
	CanonicalizationID     string
	InstructionDigest      string
	GatewayTransactionHash string
	GatewayEventID         string
	Owner                  string
	EvidenceHash           string
	ObservedAt             time.Time
}

type record struct {
	confirmationHash        string
	instructionDigest       string
	gatewayTransactionHash  string
	gatewayEventID          string
	gatewayBlockHash        string
	gatewayBlockNumber      uint64
	transactionIndex        uint64
	receiptsRoot            string
	inclusionProofHash      string
	finalityPolicyHash      string
	headerAuthorityHash     string
	receiptHeaderSigHash    string
	headHeaderSigHash       string
	instructionEvidenceHash string
	eventEvidenceHash       string
	rawGatewayPayloadHash   string
	journalIDs              []string
	reorgHash               string
	reversalJournalIDs      []string
}

// Poster atomically records canonical settlement effects and their linked deep-reorg
// compensation.
type Poster struct {
	mu            sync.Mutex
	book          *ledger.Ledger
	legalEntityID string
	loanBookID    string
	records       map[string]record
	byPayment     map[string]string
	byAllocation  map[string]string
	incidents     map[string]Incident
}

func New(
	book *ledger.Ledger,
	legalEntityID string,
	loanBookID string,
) (*Poster, error) {
	if book == nil || legalEntityID == "" || loanBookID == "" {
		return nil, ErrInvalidConfirmation
	}
	return &Poster{
		book:          book,
		legalEntityID: legalEntityID,
		loanBookID:    loanBookID,
		records:       make(map[string]record),
		byPayment:     make(map[string]string),
		byAllocation:  make(map[string]string),
		incidents:     make(map[string]Incident),
	}, nil
}

// ApplyConfirmation validates the Phase 7A source journals and posts the complete
// canonical settlement accounting batch once.
func (poster *Poster) ApplyConfirmation(
	verified VerifiedConfirmation,
) ([]string, error) {
	confirmation := verified.evidence
	if poster == nil || !validConfirmation(confirmation) {
		return nil, ErrInvalidConfirmation
	}
	contentHash := hashJSON(confirmation)

	poster.mu.Lock()
	defer poster.mu.Unlock()

	if stored, exists := poster.records[confirmation.CanonicalizationID]; exists {
		if stored.confirmationHash != contentHash {
			return nil, ErrConfirmationConflict
		}
		return slices.Clone(stored.journalIDs), nil
	}
	if existing := poster.byPayment[confirmation.PaymentID]; existing != "" {
		return nil, ErrPaymentAlreadyClaimed
	}
	if existing := poster.byAllocation[confirmation.AllocationID]; existing != "" {
		return nil, ErrPaymentAlreadyClaimed
	}
	exactCanonicalPrefix := "payment:" + confirmation.PaymentID + ":canonical:" +
		confirmation.CanonicalizationID + ":"
	for _, item := range poster.book.List() {
		if item.SourceSystem != "canonical-settlement" ||
			!strings.HasPrefix(
				item.IdempotencyKey,
				"payment:"+confirmation.PaymentID+":canonical:",
			) {
			continue
		}
		if !strings.HasPrefix(item.IdempotencyKey, exactCanonicalPrefix) {
			return nil, ErrPaymentAlreadyClaimed
		}
	}

	provisional, _, sourceAccount, err := poster.validateSource(confirmation)
	if err != nil {
		return nil, err
	}
	journals := poster.buildJournals(confirmation, provisional, sourceAccount)
	posted, err := poster.book.PostBatch(journals)
	if err != nil {
		return nil, err
	}
	journalIDs := make([]string, len(posted))
	for index, item := range posted {
		journalIDs[index] = item.ID
	}
	poster.records[confirmation.CanonicalizationID] = record{
		confirmationHash:        contentHash,
		instructionDigest:       confirmation.InstructionDigest,
		gatewayTransactionHash:  confirmation.GatewayTransactionHash,
		gatewayEventID:          confirmation.GatewayEventID,
		gatewayBlockHash:        confirmation.GatewayBlockHash,
		gatewayBlockNumber:      confirmation.GatewayBlockNumber,
		transactionIndex:        confirmation.TransactionIndex,
		receiptsRoot:            confirmation.ReceiptsRoot,
		inclusionProofHash:      confirmation.InclusionProofHash,
		finalityPolicyHash:      confirmation.FinalityPolicyHash,
		headerAuthorityHash:     confirmation.HeaderAuthorityHash,
		receiptHeaderSigHash:    confirmation.ReceiptHeaderSignatureHash,
		headHeaderSigHash:       confirmation.HeadHeaderSignatureHash,
		instructionEvidenceHash: confirmation.InstructionEvidenceHash,
		eventEvidenceHash:       confirmation.EventEvidenceHash,
		rawGatewayPayloadHash:   confirmation.RawGatewayPayloadHash,
		journalIDs:              slices.Clone(journalIDs),
	}
	poster.byPayment[confirmation.PaymentID] = confirmation.CanonicalizationID
	poster.byAllocation[confirmation.AllocationID] = confirmation.CanonicalizationID
	return journalIDs, nil
}

// CompensateReorg posts linked opposites for the complete original Phase 7C batch.
func (poster *Poster) CompensateReorg(verified VerifiedReorg) ([]string, error) {
	reorg := verified.evidence
	if poster == nil || reorg.ReorgID == "" || reorg.CanonicalizationID == "" ||
		reorg.PaymentID == "" || reorg.AllocationID == "" ||
		reorg.InstructionDigest == "" ||
		reorg.ChainID == 0 || reorg.Gateway == "" ||
		reorg.GatewayTransactionHash == "" || reorg.GatewayEventID == "" ||
		!canonicalHash(reorg.ReceiptsRoot) ||
		!canonicalHash(reorg.InclusionProofHash) ||
		!canonicalHash(reorg.FinalityPolicyHash) ||
		!canonicalHash(reorg.HeaderAuthorityHash) ||
		!canonicalHash(reorg.ReceiptHeaderSignatureHash) ||
		!canonicalHash(reorg.ConfirmationHeadHeaderSignatureHash) ||
		reorg.OrphanedBlockHash == "" || reorg.OrphanedBlockNumber == 0 ||
		reorg.ReplacementBlockHash == "" || reorg.ReplacementBlockNumber == 0 ||
		reorg.ConfirmationDepth == 0 ||
		reorg.DetectedHeadBlock < reorg.OrphanedBlockNumber ||
		reorg.DetectedHeadHash == "" ||
		!nonzeroCanonicalHash(reorg.OrphanedEventEvidenceHash) ||
		reorg.OrphanedRawPayloadHash == "" || !reorg.Deep ||
		reorg.Owner == "" || reorg.EvidenceHash == "" || reorg.OccurredAt.IsZero() ||
		!reorg.ResolutionDeadline.After(reorg.OccurredAt) {
		return nil, ErrInvalidReorg
	}
	contentHash := hashJSON(reorg)

	poster.mu.Lock()
	defer poster.mu.Unlock()
	stored, exists := poster.records[reorg.CanonicalizationID]
	if !exists ||
		reorg.InstructionDigest != stored.instructionDigest ||
		reorg.GatewayTransactionHash != stored.gatewayTransactionHash ||
		reorg.GatewayEventID != stored.gatewayEventID ||
		reorg.OrphanedBlockHash != stored.gatewayBlockHash ||
		reorg.OrphanedBlockNumber != stored.gatewayBlockNumber ||
		reorg.TransactionIndex != stored.transactionIndex ||
		reorg.ReceiptsRoot != stored.receiptsRoot ||
		reorg.InclusionProofHash != stored.inclusionProofHash ||
		reorg.FinalityPolicyHash != stored.finalityPolicyHash ||
		reorg.HeaderAuthorityHash != stored.headerAuthorityHash ||
		reorg.ReceiptHeaderSignatureHash != stored.receiptHeaderSigHash ||
		reorg.ConfirmationHeadHeaderSignatureHash != stored.headHeaderSigHash ||
		reorg.OrphanedEventEvidenceHash != stored.eventEvidenceHash ||
		reorg.OrphanedRawPayloadHash != stored.rawGatewayPayloadHash {
		return nil, ErrInvalidReorg
	}
	if stored.reorgHash != "" {
		if stored.reorgHash != contentHash {
			return nil, ErrReorgConflict
		}
		return slices.Clone(stored.reversalJournalIDs), nil
	}

	journals := make([]ledger.Journal, 0, len(stored.journalIDs))
	for _, journalID := range stored.journalIDs {
		original, exists := poster.book.Get(journalID)
		if !exists {
			return nil, ErrInvalidReorg
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
			ID:             original.ID + ":reorg:" + reorg.ReorgID,
			LegalEntityID:  original.LegalEntityID,
			BookID:         original.BookID,
			SourceSystem:   "canonical-settlement",
			EntryType:      "CANONICAL_SETTLEMENT_REORG",
			SourceEventID:  reorg.GatewayEventID,
			LoanID:         original.LoanID,
			IdempotencyKey: reorg.ReorgID + ":" + original.ID,
			CorrelationID:  original.CorrelationID,
			EffectiveAt:    reorg.OccurredAt.UTC(),
			Entries:        entries,
			EvidenceHash:   reorg.EvidenceHash,
			ReversalOf:     original.ID,
			Reason:         "deep reorganization removed finalized gateway event",
		})
	}
	posted, err := poster.book.PostBatch(journals)
	if err != nil {
		return nil, err
	}
	reversalIDs := make([]string, len(posted))
	for index, item := range posted {
		reversalIDs[index] = item.ID
	}
	stored.reorgHash = contentHash
	stored.reversalJournalIDs = slices.Clone(reversalIDs)
	poster.records[reorg.CanonicalizationID] = stored
	poster.incidents[reorg.ReorgID] = Incident{
		IncidentID:             "reorg:" + reorg.ReorgID,
		ReorgID:                reorg.ReorgID,
		CanonicalizationID:     reorg.CanonicalizationID,
		InstructionDigest:      reorg.InstructionDigest,
		GatewayTransactionHash: reorg.GatewayTransactionHash,
		GatewayEventID:         reorg.GatewayEventID,
		Owner:                  reorg.Owner,
		EvidenceHash:           reorg.EvidenceHash,
		ObservedAt:             reorg.OccurredAt.UTC(),
	}
	return reversalIDs, nil
}

// Incidents returns a detached snapshot of deep-reorganization incidents.
func (poster *Poster) Incidents() []Incident {
	if poster == nil {
		return nil
	}
	poster.mu.Lock()
	defer poster.mu.Unlock()
	result := make([]Incident, 0, len(poster.incidents))
	for _, incident := range poster.incidents {
		result = append(result, incident)
	}
	return result
}

func (poster *Poster) validateSource(
	confirmation Confirmation,
) (ledger.PostedJournal, ledger.PostedJournal, string, error) {
	provisional, provisionalExists := poster.book.Get(
		confirmation.OriginalProvisionalJournalID,
	)
	final, finalExists := poster.book.Get(confirmation.OriginalFinalJournalID)
	if !provisionalExists || !finalExists ||
		provisional.ID != "payment:"+confirmation.PaymentID+":provisional" ||
		final.ID != "payment:"+confirmation.PaymentID+":final" ||
		provisional.LegalEntityID != poster.legalEntityID ||
		final.LegalEntityID != poster.legalEntityID ||
		provisional.BookID != final.BookID ||
		provisional.SourceSystem != "payment-orchestrator" ||
		final.SourceSystem != "payment-orchestrator" ||
		provisional.EntryType != "PAYMENT_PROVISIONAL" ||
		final.EntryType != "PAYMENT_FINAL" ||
		provisional.LoanID != confirmation.LoanID ||
		final.LoanID != confirmation.LoanID ||
		len(provisional.Entries) != 2 || len(final.Entries) != 2 {
		return ledger.PostedJournal{}, ledger.PostedJournal{}, "", ErrInvalidSourceEvidence
	}
	pendingAccount := provisional.Entries[0].AccountCode
	sourceAccount := final.Entries[0].AccountCode
	if (pendingAccount != "9130" && pendingAccount != "9140") ||
		(sourceAccount != AccountProviderBankAsset &&
			sourceAccount != AccountProviderCardAsset) ||
		provisional.Entries[0].Side != ledger.Debit ||
		provisional.Entries[1].AccountCode != AccountUnallocatedPayment ||
		provisional.Entries[1].Side != ledger.Credit ||
		final.Entries[0].Side != ledger.Debit ||
		final.Entries[1].AccountCode != pendingAccount ||
		final.Entries[1].Side != ledger.Credit {
		return ledger.PostedJournal{}, ledger.PostedJournal{}, "", ErrInvalidSourceEvidence
	}
	for _, item := range []ledger.PostedJournal{provisional, final} {
		for _, line := range item.Entries {
			if line.AssetID != confirmation.SourceAssetID ||
				line.Units != confirmation.SourceUnits ||
				line.LoanID != confirmation.LoanID ||
				line.PartyID != confirmation.BorrowerID {
				return ledger.PostedJournal{}, ledger.PostedJournal{}, "", ErrInvalidSourceEvidence
			}
		}
	}

	sourceBalance := new(big.Int)
	for _, item := range poster.book.List() {
		if item.ReversalOf == provisional.ID || item.ReversalOf == final.ID {
			return ledger.PostedJournal{}, ledger.PostedJournal{}, "", ErrInvalidSourceEvidence
		}
		if item.SourceSystem == "payment-allocation" &&
			item.SourceEventID == confirmation.PaymentID {
			return ledger.PostedJournal{}, ledger.PostedJournal{}, "", ErrPaymentAlreadyClaimed
		}
		if item.SourceSystem == "canonical-settlement" &&
			strings.HasPrefix(
				item.IdempotencyKey,
				"payment:"+confirmation.PaymentID+":canonical:"+
					confirmation.CanonicalizationID+":",
			) {
			continue
		}
		if !journalBelongsToPayment(item, confirmation.PaymentID) {
			continue
		}
		for _, line := range item.Entries {
			if line.AccountCode != AccountUnallocatedPayment ||
				line.AssetID != confirmation.SourceAssetID {
				continue
			}
			units, ok := canonicalNonNegative(line.Units)
			if !ok {
				return ledger.PostedJournal{}, ledger.PostedJournal{}, "", ErrInvalidSourceEvidence
			}
			if line.Side == ledger.Credit {
				sourceBalance.Add(sourceBalance, units)
			} else {
				sourceBalance.Sub(sourceBalance, units)
			}
		}
	}
	expected, _ := canonicalNonNegative(confirmation.SourceUnits)
	if sourceBalance.Cmp(expected) != 0 {
		return ledger.PostedJournal{}, ledger.PostedJournal{}, "", ErrInvalidSourceEvidence
	}
	return provisional, final, sourceAccount, nil
}

func (poster *Poster) buildJournals(
	confirmation Confirmation,
	provisional ledger.PostedJournal,
	sourceAccount string,
) []ledger.Journal {
	principalEntries := []ledger.Entry{
		entry(confirmation, AccountUnallocatedPayment, ledger.Debit,
			confirmation.TargetAssetID, confirmation.TargetUnits, ""),
		entry(confirmation, AccountPrincipalReceivable, ledger.Credit,
			confirmation.TargetAssetID, confirmation.PrincipalUnits, confirmation.BorrowerID),
	}
	excess, _ := canonicalNonNegative(confirmation.RefundableExcessUnits)
	if excess.Sign() > 0 {
		principalEntries = append(principalEntries, entry(
			confirmation,
			AccountRefundPayable,
			ledger.Credit,
			confirmation.TargetAssetID,
			confirmation.RefundableExcessUnits,
			confirmation.BorrowerID,
		))
	}

	sourceBookID := provisional.BookID
	journals := []ledger.Journal{
		poster.journal(confirmation, sourceBookID, "source-unallocated",
			"CANONICAL_SOURCE_CLEARED", []ledger.Entry{
				entry(confirmation, AccountUnallocatedPayment, ledger.Debit,
					confirmation.SourceAssetID, confirmation.SourceUnits, confirmation.BorrowerID),
				entry(confirmation, AccountConversionClearing, ledger.Credit,
					confirmation.SourceAssetID, confirmation.SourceUnits, ""),
			}),
		poster.journal(confirmation, sourceBookID, "source-converted",
			"CANONICAL_SOURCE_CONVERTED", []ledger.Entry{
				entry(confirmation, AccountConversionClearing, ledger.Debit,
					confirmation.SourceAssetID, confirmation.SourceUnits, ""),
				entry(confirmation, sourceAccount, ledger.Credit,
					confirmation.SourceAssetID, confirmation.SourceUnits, ""),
			}),
		poster.journal(confirmation, poster.loanBookID, "target-custody",
			"CANONICAL_TARGET_CUSTODY", []ledger.Entry{
				entry(confirmation, AccountRestrictedToken, ledger.Debit,
					confirmation.TargetAssetID, confirmation.TargetUnits, ""),
				entry(confirmation, AccountConversionClearing, ledger.Credit,
					confirmation.TargetAssetID, confirmation.TargetUnits, ""),
			}),
		poster.journal(confirmation, poster.loanBookID, "target-unallocated",
			"CANONICAL_TARGET_UNALLOCATED", []ledger.Entry{
				entry(confirmation, AccountConversionClearing, ledger.Debit,
					confirmation.TargetAssetID, confirmation.TargetUnits, ""),
				entry(confirmation, AccountUnallocatedPayment, ledger.Credit,
					confirmation.TargetAssetID, confirmation.TargetUnits, confirmation.BorrowerID),
			}),
		poster.journal(confirmation, poster.loanBookID, "allocation",
			"CANONICAL_PAYMENT_ALLOCATED", principalEntries),
		poster.journal(confirmation, poster.loanBookID, "lender-claim",
			"CANONICAL_LENDER_CLAIM_ALLOCATED", []ledger.Entry{
				entry(confirmation, AccountLenderPrincipalClaims, ledger.Debit,
					confirmation.TargetAssetID, confirmation.PrincipalUnits, confirmation.LenderID),
				entry(confirmation, AccountLenderRepaymentPayable, ledger.Credit,
					confirmation.TargetAssetID, confirmation.PrincipalUnits, confirmation.LenderID),
			}),
		poster.journal(confirmation, poster.loanBookID, "lender-payout",
			"CANONICAL_LENDER_PAID", []ledger.Entry{
				entry(confirmation, AccountLenderRepaymentPayable, ledger.Debit,
					confirmation.TargetAssetID, confirmation.PrincipalUnits, confirmation.LenderID),
				entry(confirmation, AccountRestrictedToken, ledger.Credit,
					confirmation.TargetAssetID, confirmation.PrincipalUnits, confirmation.LenderID),
			}),
	}
	if excess.Sign() > 0 {
		journals = append(journals, poster.journal(
			confirmation,
			poster.loanBookID,
			"borrower-refund",
			"CANONICAL_BORROWER_REFUNDED",
			[]ledger.Entry{
				entry(confirmation, AccountRefundPayable, ledger.Debit,
					confirmation.TargetAssetID, confirmation.RefundableExcessUnits,
					confirmation.BorrowerID),
				entry(confirmation, AccountRestrictedToken, ledger.Credit,
					confirmation.TargetAssetID, confirmation.RefundableExcessUnits,
					confirmation.BorrowerID),
			},
		))
	}
	return journals
}

func (poster *Poster) journal(
	confirmation Confirmation,
	bookID string,
	suffix string,
	entryType string,
	entries []ledger.Entry,
) ledger.Journal {
	return ledger.Journal{
		ID:            "canonical:" + confirmation.CanonicalizationID + ":" + suffix,
		LegalEntityID: poster.legalEntityID,
		BookID:        bookID,
		SourceSystem:  "canonical-settlement",
		EntryType:     entryType,
		SourceEventID: confirmation.GatewayEventID,
		LoanID:        confirmation.LoanID,
		IdempotencyKey: "payment:" + confirmation.PaymentID + ":canonical:" +
			confirmation.CanonicalizationID + ":" + suffix,
		CorrelationID: confirmation.CorrelationID,
		EffectiveAt:   confirmation.ConfirmedAt.UTC(),
		Entries:       entries,
		EvidenceHash:  confirmation.RawGatewayPayloadHash,
	}
}

func entry(
	confirmation Confirmation,
	accountCode string,
	side ledger.Side,
	assetID string,
	units string,
	partyID string,
) ledger.Entry {
	return ledger.Entry{
		AccountCode: accountCode,
		Side:        side,
		AssetID:     assetID,
		Units:       units,
		PartyID:     partyID,
		LoanID:      confirmation.LoanID,
	}
}

func validConfirmation(confirmation Confirmation) bool {
	source, sourceOK := canonicalPositive(confirmation.SourceUnits)
	target, targetOK := canonicalPositive(confirmation.TargetUnits)
	principal, principalOK := canonicalPositive(confirmation.PrincipalUnits)
	excess, excessOK := canonicalNonNegative(confirmation.RefundableExcessUnits)
	debtBefore, debtBeforeOK := canonicalPositive(confirmation.DebtBeforeUnits)
	debtAfter, debtAfterOK := canonicalNonNegative(confirmation.DebtAfterUnits)
	if !sourceOK || !targetOK || !principalOK || !excessOK ||
		!debtBeforeOK || !debtAfterOK ||
		source.Cmp(target) != 0 ||
		new(big.Int).Add(new(big.Int).Set(principal), excess).Cmp(target) != 0 ||
		new(big.Int).Add(new(big.Int).Set(principal), debtAfter).Cmp(debtBefore) != 0 {
		return false
	}
	return confirmation.CanonicalizationID != "" &&
		confirmation.InstructionDigest != "" &&
		confirmation.PaymentID != "" &&
		confirmation.AllocationID != "" &&
		confirmation.LoanID != "" &&
		confirmation.ChainID > 0 &&
		confirmation.Gateway != "" &&
		confirmation.LoanAccount != "" &&
		confirmation.Finalizer != "" &&
		confirmation.Attester != "" &&
		confirmation.BorrowerID != "" &&
		confirmation.LenderID != "" &&
		confirmation.BorrowerID != confirmation.LenderID &&
		confirmation.SourceAssetID != "" &&
		confirmation.TargetAssetID != "" &&
		confirmation.SourceAssetID != confirmation.TargetAssetID &&
		confirmation.TargetToken != "" &&
		confirmation.StateNonceBefore > 0 &&
		confirmation.StateNonceAfter > confirmation.StateNonceBefore &&
		confirmation.PolicySetHash != "" &&
		confirmation.ProviderIDHash != "" &&
		confirmation.ProviderReferenceHash != "" &&
		confirmation.ReconciliationCommitment != "" &&
		confirmation.OriginalJournalSetHash != "" &&
		confirmation.ConversionPolicyHash != "" &&
		canonicalHash(confirmation.FinalityPolicyHash) &&
		confirmation.InstructionEvidenceHash != "" &&
		confirmation.JournalRef != "" &&
		confirmation.ProviderFinalizedAt > 0 &&
		confirmation.ReversalDeadline > confirmation.ProviderFinalizedAt &&
		confirmation.OriginalProvisionalJournalID != "" &&
		confirmation.OriginalFinalJournalID != "" &&
		confirmation.ReconciliationID != "" &&
		confirmation.ConversionEvidenceHash != "" &&
		confirmation.GatewayTransactionHash != "" &&
		confirmation.GatewayEventID != "" &&
		confirmation.GatewayBlockHash != "" &&
		confirmation.GatewayBlockNumber > 0 &&
		canonicalHash(confirmation.ReceiptsRoot) &&
		canonicalHash(confirmation.InclusionProofHash) &&
		confirmation.ConfirmationDepth > 0 &&
		confirmation.FinalityHeadBlock >= confirmation.GatewayBlockNumber &&
		confirmation.FinalityHeadBlock-confirmation.GatewayBlockNumber >=
			confirmation.ConfirmationDepth &&
		confirmation.FinalityHeadHash != "" &&
		canonicalHash(confirmation.HeaderAuthorityHash) &&
		canonicalHash(confirmation.ReceiptHeaderSignatureHash) &&
		canonicalHash(confirmation.HeadHeaderSignatureHash) &&
		confirmation.FinalityEvidenceHash != "" &&
		nonzeroCanonicalHash(confirmation.EventEvidenceHash) &&
		confirmation.CorrelationID != "" &&
		confirmation.RawGatewayPayloadHash != "" &&
		!confirmation.ConfirmedAt.IsZero()
}

func journalBelongsToPayment(journal ledger.PostedJournal, paymentID string) bool {
	return journal.ID == "payment:"+paymentID+":provisional" ||
		journal.ID == "payment:"+paymentID+":final" ||
		journal.SourceEventID == paymentID ||
		strings.HasPrefix(journal.IdempotencyKey, "payment:"+paymentID+":")
}

func canonicalPositive(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.Sign() > 0 && parsed.String() == value
}

func canonicalNonNegative(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.Sign() >= 0 && parsed.String() == value
}

func canonicalHash(value string) bool {
	if len(value) != 66 || !strings.HasPrefix(value, "0x") ||
		value != strings.ToLower(value) {
		return false
	}
	_, err := hex.DecodeString(value[2:])
	return err == nil
}

func nonzeroCanonicalHash(value string) bool {
	if !canonicalHash(value) {
		return false
	}
	decoded, _ := hex.DecodeString(value[2:])
	for _, item := range decoded {
		if item != 0 {
			return true
		}
	}
	return false
}

func hashJSON(value any) string {
	encoded, _ := json.Marshal(value)
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:])
}

func cloneAccountingConfirmation(confirmation Confirmation) Confirmation {
	// The current durable DTO has no slice/map fields. Keep the helper so adding
	// one cannot accidentally expose mutable authority through Evidence().
	return confirmation
}
