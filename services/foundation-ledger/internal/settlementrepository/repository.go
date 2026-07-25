// Package settlementrepository restores durable Phase 7C evidence after a process
// restart. The caller replays the returned immutable evidence through the idempotent
// accounting poster.
package settlementrepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementaccounting"
	"github.com/unified-finance/unified/services/payment-orchestrator/settlement"
)

var ErrInvalidRepository = errors.New("invalid canonical settlement repository")

type rowScanner interface {
	Scan(dest ...any) error
}

type DeepCompensationRequest struct {
	CompensationID           string
	CompensationEvidenceHash string
	ConfirmationID           string
	Reorg                    settlementaccounting.VerifiedReorg
}

// CanonicalSuccessCommitRequest carries the opaque coordinator confirmation
// plus the only two deployment-local values that are not economic authority:
// the conversion evidence hash and the configured target ledger book.
type CanonicalSuccessCommitRequest struct {
	Confirmation           settlement.Confirmation
	ConversionEvidenceHash string
	ConvertedAt            time.Time
	TargetBookID           string
}

type CanonicalSuccessCommitResult struct {
	ConfirmationID string   `json:"confirmation_id"`
	ConversionID   string   `json:"conversion_id"`
	GatewayEventID string   `json:"gateway_event_id"`
	JournalIDs     []string `json:"journal_ids"`
}

const commitCanonicalSuccessSQL = `
SELECT commit_canonical_external_settlement(
    $1::jsonb, $2, $3, $4
)::text`

// CommitCanonicalSuccess invokes the database-owned one-statement commit. The
// function derives plan, submission, event, recipients, amounts, journals,
// payout and refund from the exact coordinator snapshot and returns the same
// result for an exact retry after response loss or restart.
func (repository *Repository) CommitCanonicalSuccess(
	ctx context.Context,
	request CanonicalSuccessCommitRequest,
) (CanonicalSuccessCommitResult, error) {
	projection := request.Confirmation.AccountingProjection()
	if repository == nil || repository.queryer == nil ||
		projection.PaymentID == "" || projection.AllocationID == "" ||
		projection.InstructionDigest == "" || projection.EventID == "" ||
		projection.TransactionHash == "" ||
		projection.GatewayPayloadHash == "" ||
		projection.FinalityEvidenceHash == "" ||
		request.ConversionEvidenceHash == "" ||
		request.ConvertedAt.IsZero() || request.TargetBookID == "" {
		return CanonicalSuccessCommitResult{}, ErrInvalidRepository
	}
	encodedProjection, err := json.Marshal(projection)
	if err != nil {
		return CanonicalSuccessCommitResult{}, ErrInvalidRepository
	}
	var encodedResult string
	err = repository.queryer.QueryRowContext(
		ctx,
		commitCanonicalSuccessSQL,
		string(encodedProjection),
		request.ConversionEvidenceHash,
		request.ConvertedAt.UTC(),
		request.TargetBookID,
	).Scan(&encodedResult)
	if err != nil {
		return CanonicalSuccessCommitResult{}, fmt.Errorf(
			"commit canonical external settlement: %w",
			err,
		)
	}
	var result CanonicalSuccessCommitResult
	if json.Unmarshal([]byte(encodedResult), &result) != nil ||
		result.ConfirmationID == "" || result.ConversionID == "" ||
		result.GatewayEventID != projection.EventID ||
		len(result.JournalIDs) < 7 || len(result.JournalIDs) > 8 ||
		!uniqueNonempty(result.JournalIDs) {
		return CanonicalSuccessCommitResult{}, ErrInvalidRepository
	}
	result.JournalIDs = slices.Clone(result.JournalIDs)
	return result, nil
}

const recordDeepCompensationSQL = `
SELECT record_deep_canonical_settlement_compensation(
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
    $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22,
    $23, $24, $25, $26, $27, $28, $29, $30, $31, $32, $33
)`

func (repository *Repository) RecordDeepCompensation(
	ctx context.Context,
	request DeepCompensationRequest,
) (string, error) {
	reorg := request.Reorg.Evidence()
	if repository == nil || repository.queryer == nil ||
		request.CompensationID == "" || request.CompensationEvidenceHash == "" ||
		request.ConfirmationID == "" ||
		reorg.ReorgID == "" || reorg.CanonicalizationID == "" ||
		reorg.PaymentID == "" || reorg.AllocationID == "" ||
		reorg.InstructionDigest == "" || reorg.ChainID == 0 ||
		reorg.Gateway == "" || reorg.GatewayTransactionHash == "" ||
		reorg.GatewayEventID == "" || reorg.ReceiptsRoot == "" ||
		reorg.InclusionProofHash == "" || reorg.FinalityPolicyHash == "" ||
		reorg.HeaderAuthorityHash == "" ||
		reorg.ReceiptHeaderSignatureHash == "" ||
		reorg.ConfirmationHeadHeaderSignatureHash == "" ||
		reorg.ReplacementHeaderSignatureHash == "" ||
		reorg.DetectedHeadHeaderSignatureHash == "" ||
		reorg.OrphanedBlockHash == "" ||
		reorg.OrphanedBlockNumber == 0 || reorg.ReplacementBlockHash == "" ||
		reorg.ReplacementBlockNumber == 0 || reorg.ConfirmationDepth == 0 ||
		reorg.DetectedHeadBlock < reorg.OrphanedBlockNumber ||
		reorg.DetectedHeadHash == "" ||
		reorg.OrphanedEventEvidenceHash == "" ||
		reorg.OrphanedRawPayloadHash == "" ||
		!reorg.Deep || reorg.Owner == "" || reorg.EvidenceHash == "" ||
		reorg.SubmissionSubmittedAt.IsZero() ||
		reorg.OccurredAt.IsZero() ||
		reorg.SubmissionSubmittedAt.After(reorg.OccurredAt) ||
		!reorg.ResolutionDeadline.After(reorg.OccurredAt) {
		return "", ErrInvalidRepository
	}
	var compensationID string
	err := repository.queryer.QueryRowContext(
		ctx,
		recordDeepCompensationSQL,
		reorg.ReorgID,
		request.CompensationID,
		request.ConfirmationID,
		reorg.CanonicalizationID,
		reorg.InstructionDigest,
		reorg.ChainID,
		reorg.Gateway,
		reorg.GatewayTransactionHash,
		reorg.GatewayEventID,
		strconv.FormatUint(reorg.TransactionIndex, 10),
		reorg.ReceiptsRoot,
		reorg.InclusionProofHash,
		reorg.FinalityPolicyHash,
		reorg.HeaderAuthorityHash,
		reorg.ReceiptHeaderSignatureHash,
		reorg.ConfirmationHeadHeaderSignatureHash,
		reorg.ReplacementHeaderSignatureHash,
		reorg.DetectedHeadHeaderSignatureHash,
		reorg.OrphanedBlockHash,
		reorg.OrphanedBlockNumber,
		reorg.ReplacementBlockHash,
		reorg.ReplacementBlockNumber,
		reorg.ConfirmationDepth,
		reorg.DetectedHeadBlock,
		reorg.DetectedHeadHash,
		reorg.OrphanedEventEvidenceHash,
		reorg.OrphanedRawPayloadHash,
		reorg.EvidenceHash,
		reorg.SubmissionSubmittedAt,
		request.CompensationEvidenceHash,
		reorg.Owner,
		reorg.OccurredAt,
		reorg.ResolutionDeadline,
	).Scan(&compensationID)
	if err != nil {
		return "", fmt.Errorf("record canonical settlement deep compensation: %w", err)
	}
	if compensationID != request.CompensationID {
		return "", ErrInvalidRepository
	}
	return compensationID, nil
}

type rowQueryer interface {
	QueryRowContext(ctx context.Context, query string, args ...any) rowScanner
}

type sqlQueryer struct {
	db *sql.DB
}

func (queryer sqlQueryer) QueryRowContext(
	ctx context.Context,
	query string,
	args ...any,
) rowScanner {
	return queryer.db.QueryRowContext(ctx, query, args...)
}

type Repository struct {
	queryer rowQueryer
}

func New(db *sql.DB) (*Repository, error) {
	if db == nil {
		return nil, ErrInvalidRepository
	}
	return &Repository{queryer: sqlQueryer{db: db}}, nil
}

const loadConfirmationSQL = `
SELECT
    plan.canonicalization_id,
    plan.instruction_digest,
    plan.payment_id,
    plan.allocation_id,
    plan.loan_id,
    event.chain_id,
    event.gateway_address,
    event.loan_account,
    event.finalizer_id,
    event.accounting_attester_id,
    event.borrower_id,
    event.lender_id,
    plan.source_asset_id,
    plan.target_asset_id,
    event.target_token,
    plan.source_units::text,
    plan.target_units::text,
    plan.principal_units::text,
    plan.refundable_excess_units::text,
    plan.debt_before_units::text,
    plan.debt_after_units::text,
    event.state_nonce_before,
    event.state_nonce_after,
    event.policy_set_hash,
    event.provider_id_hash,
    event.provider_reference_hash,
    event.reconciliation_commitment,
    event.original_journal_set_hash,
    event.conversion_policy_hash,
    event.finality_policy_hash,
    event.instruction_evidence_hash,
    event.journal_ref,
    event.provider_finalized_at,
    event.reversal_deadline,
    eligibility.original_provisional_journal_id,
    eligibility.original_final_journal_id,
    eligibility.reconciliation_id,
    conversion.evidence_hash,
    confirmation.transaction_hash,
    confirmation.gateway_event_id,
    confirmation.block_hash,
    confirmation.block_number,
    confirmation.log_index,
    confirmation.transaction_index,
    confirmation.receipts_root,
    confirmation.inclusion_proof_hash,
    confirmation.chain_finality_depth,
    confirmation.finality_head_block,
    confirmation.finality_head_hash,
    confirmation.header_authority_hash,
    confirmation.receipt_header_signature_hash,
    confirmation.head_header_signature_hash,
    confirmation.finality_evidence_hash,
    confirmed_state.snapshot #>> '{Confirmation,EventEvidenceHash}',
    intent.correlation_id,
    confirmation.raw_payload_hash,
    confirmation.confirmed_at
FROM canonicalization_plan AS plan
JOIN canonicalization_eligibility AS eligibility
  ON eligibility.eligibility_id = plan.eligibility_id
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
 AND confirmed_state.snapshot #>> '{Confirmation,EventID}' =
     confirmation.gateway_event_id
 AND confirmed_state.snapshot #>> '{Confirmation,GatewayPayloadHash}' =
     confirmation.raw_payload_hash
JOIN payment_intent AS intent
  ON intent.payment_id = plan.payment_id
WHERE plan.canonicalization_id = $1`

func (repository *Repository) LoadConfirmation(
	ctx context.Context,
	canonicalizationID string,
) (settlementaccounting.Confirmation, error) {
	if repository == nil || repository.queryer == nil || canonicalizationID == "" {
		return settlementaccounting.Confirmation{}, ErrInvalidRepository
	}
	var confirmation settlementaccounting.Confirmation
	err := repository.queryer.QueryRowContext(
		ctx,
		loadConfirmationSQL,
		canonicalizationID,
	).Scan(
		&confirmation.CanonicalizationID,
		&confirmation.InstructionDigest,
		&confirmation.PaymentID,
		&confirmation.AllocationID,
		&confirmation.LoanID,
		&confirmation.ChainID,
		&confirmation.Gateway,
		&confirmation.LoanAccount,
		&confirmation.Finalizer,
		&confirmation.Attester,
		&confirmation.BorrowerID,
		&confirmation.LenderID,
		&confirmation.SourceAssetID,
		&confirmation.TargetAssetID,
		&confirmation.TargetToken,
		&confirmation.SourceUnits,
		&confirmation.TargetUnits,
		&confirmation.PrincipalUnits,
		&confirmation.RefundableExcessUnits,
		&confirmation.DebtBeforeUnits,
		&confirmation.DebtAfterUnits,
		&confirmation.StateNonceBefore,
		&confirmation.StateNonceAfter,
		&confirmation.PolicySetHash,
		&confirmation.ProviderIDHash,
		&confirmation.ProviderReferenceHash,
		&confirmation.ReconciliationCommitment,
		&confirmation.OriginalJournalSetHash,
		&confirmation.ConversionPolicyHash,
		&confirmation.FinalityPolicyHash,
		&confirmation.InstructionEvidenceHash,
		&confirmation.JournalRef,
		&confirmation.ProviderFinalizedAt,
		&confirmation.ReversalDeadline,
		&confirmation.OriginalProvisionalJournalID,
		&confirmation.OriginalFinalJournalID,
		&confirmation.ReconciliationID,
		&confirmation.ConversionEvidenceHash,
		&confirmation.GatewayTransactionHash,
		&confirmation.GatewayEventID,
		&confirmation.GatewayBlockHash,
		&confirmation.GatewayBlockNumber,
		&confirmation.GatewayLogIndex,
		&confirmation.TransactionIndex,
		&confirmation.ReceiptsRoot,
		&confirmation.InclusionProofHash,
		&confirmation.ConfirmationDepth,
		&confirmation.FinalityHeadBlock,
		&confirmation.FinalityHeadHash,
		&confirmation.HeaderAuthorityHash,
		&confirmation.ReceiptHeaderSignatureHash,
		&confirmation.HeadHeaderSignatureHash,
		&confirmation.FinalityEvidenceHash,
		&confirmation.EventEvidenceHash,
		&confirmation.CorrelationID,
		&confirmation.RawGatewayPayloadHash,
		&confirmation.ConfirmedAt,
	)
	if err != nil {
		return settlementaccounting.Confirmation{}, fmt.Errorf(
			"load canonical settlement confirmation: %w",
			err,
		)
	}
	return confirmation, nil
}

const loadDeepReorgSQL = `
SELECT
    reorg.reorg_id,
    reorg.canonicalization_id,
    plan.payment_id,
    plan.allocation_id,
    reorg.instruction_digest,
    reorg.chain_id,
    reorg.gateway_address,
    reorg.orphaned_transaction_hash,
    reorg.orphaned_gateway_event_id,
    reorg.transaction_index,
    reorg.receipts_root,
    reorg.inclusion_proof_hash,
    reorg.finality_policy_hash,
    reorg.header_authority_hash,
    reorg.orphaned_receipt_header_signature_hash,
    reorg.confirmation_head_header_signature_hash,
    reorg.replacement_header_signature_hash,
    reorg.detected_head_header_signature_hash,
    reorg.orphaned_block_hash,
    reorg.orphaned_block_number,
    reorg.replacement_block_hash,
    reorg.replacement_block_number,
    reorg.confirmation_depth,
    reorg.detected_head_block,
    reorg.detected_head_hash,
    reorg.orphaned_event_evidence_hash,
    reorg.orphaned_raw_payload_hash,
    incident.owner,
    reorg.evidence_hash,
    reorg.submission_submitted_at,
    reorg.detected_at,
    incident.resolution_deadline
FROM canonical_settlement_reorg AS reorg
JOIN canonical_settlement_reorg_compensation AS compensation
  ON compensation.reorg_id = reorg.reorg_id
JOIN canonical_settlement_incident AS incident
  ON incident.incident_id = compensation.incident_id
JOIN canonical_settlement_confirmation AS confirmation
  ON confirmation.confirmation_id = compensation.confirmation_id
JOIN canonical_gateway_event_projection AS event
  ON event.gateway_event_id = confirmation.gateway_event_id
JOIN canonicalization_plan AS plan
  ON plan.canonicalization_id = reorg.canonicalization_id
WHERE reorg.canonicalization_id = $1
  AND reorg.reorg_kind = 'DEEP'
  AND reorg.compensation_required
  AND reorg.confirmation_id = confirmation.confirmation_id
  AND reorg.orphaned_gateway_event_id = event.gateway_event_id
  AND confirmation.transaction_index = event.transaction_index
  AND confirmation.receipts_root = event.receipts_root
  AND confirmation.inclusion_proof_hash = event.inclusion_proof_hash
  AND confirmation.finality_policy_hash = event.finality_policy_hash
  AND confirmation.header_authority_hash = event.header_authority_hash
  AND confirmation.receipt_header_signature_hash =
      event.receipt_header_signature_hash
  AND confirmation.head_header_signature_hash =
      event.head_header_signature_hash
  AND EXISTS (
      SELECT 1
      FROM canonical_coordinator_state_history AS confirmed_state
      WHERE confirmed_state.payment_id = plan.payment_id
        AND confirmed_state.instruction_digest = reorg.instruction_digest
        AND confirmed_state.state = 'CONFIRMED'
        AND confirmed_state.snapshot #>> '{Confirmation,EventID}' =
            reorg.orphaned_gateway_event_id
        AND confirmed_state.snapshot
                #>> '{Confirmation,EventEvidenceHash}' =
            reorg.orphaned_event_evidence_hash
        AND confirmed_state.snapshot
                #>> '{Confirmation,GatewayPayloadHash}' =
            reorg.orphaned_raw_payload_hash
  )`

func (repository *Repository) LoadDeepReorg(
	ctx context.Context,
	canonicalizationID string,
) (settlementaccounting.ReorgEvidence, error) {
	if repository == nil || repository.queryer == nil || canonicalizationID == "" {
		return settlementaccounting.ReorgEvidence{}, ErrInvalidRepository
	}
	reorg := settlementaccounting.ReorgEvidence{Deep: true}
	err := repository.queryer.QueryRowContext(
		ctx,
		loadDeepReorgSQL,
		canonicalizationID,
	).Scan(
		&reorg.ReorgID,
		&reorg.CanonicalizationID,
		&reorg.PaymentID,
		&reorg.AllocationID,
		&reorg.InstructionDigest,
		&reorg.ChainID,
		&reorg.Gateway,
		&reorg.GatewayTransactionHash,
		&reorg.GatewayEventID,
		&reorg.TransactionIndex,
		&reorg.ReceiptsRoot,
		&reorg.InclusionProofHash,
		&reorg.FinalityPolicyHash,
		&reorg.HeaderAuthorityHash,
		&reorg.ReceiptHeaderSignatureHash,
		&reorg.ConfirmationHeadHeaderSignatureHash,
		&reorg.ReplacementHeaderSignatureHash,
		&reorg.DetectedHeadHeaderSignatureHash,
		&reorg.OrphanedBlockHash,
		&reorg.OrphanedBlockNumber,
		&reorg.ReplacementBlockHash,
		&reorg.ReplacementBlockNumber,
		&reorg.ConfirmationDepth,
		&reorg.DetectedHeadBlock,
		&reorg.DetectedHeadHash,
		&reorg.OrphanedEventEvidenceHash,
		&reorg.OrphanedRawPayloadHash,
		&reorg.Owner,
		&reorg.EvidenceHash,
		&reorg.SubmissionSubmittedAt,
		&reorg.OccurredAt,
		&reorg.ResolutionDeadline,
	)
	if err != nil {
		return settlementaccounting.ReorgEvidence{}, fmt.Errorf(
			"load canonical settlement deep reorg: %w",
			err,
		)
	}
	return reorg, nil
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
