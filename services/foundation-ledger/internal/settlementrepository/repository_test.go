package settlementrepository

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementaccounting"
	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementintegration"
	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementtest"
)

type fakeQueryer struct {
	row *fakeRow
}

func (queryer fakeQueryer) QueryRowContext(
	_ context.Context,
	query string,
	args ...any,
) rowScanner {
	queryer.row.query = query
	queryer.row.args = args
	return queryer.row
}

type fakeRow struct {
	query  string
	args   []any
	values []any
	err    error
}

func (row *fakeRow) Scan(dest ...any) error {
	if row.err != nil {
		return row.err
	}
	if len(dest) != len(row.values) {
		return errors.New("unexpected scan width")
	}
	for index, value := range row.values {
		switch target := dest[index].(type) {
		case *string:
			*target = value.(string)
		case *uint64:
			*target = value.(uint64)
		case *uint32:
			*target = value.(uint32)
		case *time.Time:
			*target = value.(time.Time)
		default:
			return errors.New("unexpected scan type")
		}
	}
	return nil
}

func TestLoadConfirmationRestoresCompleteAuthorityProvenance(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	row := &fakeRow{values: []any{
		"canonical-001", "instruction-001", "payment-001", "allocation-001",
		"loan-001", uint64(31337), "0xgateway", "0xloan-account",
		"0xfinalizer", "0xattester", "borrower-001", "lender-001",
		"fiat-usd", "usdc-mainnet", "0xtarget-token",
		"1250", "1250", "1000", "250", "1000", "0",
		uint64(7), uint64(9), "policy-set", "provider-id-hash",
		"provider-reference-hash", "reconciliation-commitment",
		"original-journal-set-hash", "conversion-policy", "finality-policy",
		"instruction-evidence", "journal-ref", uint64(1_900_000_000),
		uint64(1_900_086_400), "payment:payment-001:provisional",
		"payment:payment-001:final", "reconciliation-001",
		"conversion-evidence", "0xtransaction", "gateway-event-001",
		"0xblock-100", uint64(100), uint32(4), uint64(0),
		"0xreceipts-root", "0xinclusion-proof", uint64(12),
		uint64(112), "0xblock-112", "0xheader-authority",
		"0xreceipt-header-signature", "0xhead-header-signature",
		"finality-evidence",
		"0x9999999999999999999999999999999999999999999999999999999999999999",
		"correlation-001", "raw-gateway-payload", now,
	}}
	repository := &Repository{queryer: fakeQueryer{row: row}}
	confirmation, err := repository.LoadConfirmation(context.Background(), "canonical-001")
	if err != nil {
		t.Fatal(err)
	}
	if confirmation.InstructionDigest != "instruction-001" ||
		confirmation.ChainID != 31337 ||
		confirmation.Gateway != "0xgateway" ||
		confirmation.LoanAccount != "0xloan-account" ||
		confirmation.Finalizer != "0xfinalizer" ||
		confirmation.Attester != "0xattester" ||
		confirmation.BorrowerID != "borrower-001" ||
		confirmation.LenderID != "lender-001" ||
		confirmation.TargetToken != "0xtarget-token" ||
		confirmation.StateNonceBefore != 7 ||
		confirmation.StateNonceAfter != 9 ||
		confirmation.OriginalFinalJournalID != "payment:payment-001:final" ||
		confirmation.InstructionEvidenceHash != "instruction-evidence" ||
		confirmation.RawGatewayPayloadHash != "raw-gateway-payload" ||
		confirmation.TransactionIndex != 0 ||
		confirmation.ReceiptsRoot != "0xreceipts-root" ||
		confirmation.InclusionProofHash != "0xinclusion-proof" ||
		confirmation.HeaderAuthorityHash != "0xheader-authority" ||
		confirmation.ReceiptHeaderSignatureHash !=
			"0xreceipt-header-signature" ||
		confirmation.HeadHeaderSignatureHash != "0xhead-header-signature" ||
		confirmation.EventEvidenceHash !=
			"0x9999999999999999999999999999999999999999999999999999999999999999" ||
		confirmation.FinalityHeadBlock != 112 ||
		!strings.Contains(row.query, "EventEvidenceHash") ||
		!strings.Contains(row.query, "canonical_gateway_event_projection") {
		t.Fatalf("durable confirmation lost provenance: %#v", confirmation)
	}
}

func TestLoadDeepReorgRestoresCompensationEnvelope(t *testing.T) {
	now := time.Date(2026, 7, 24, 13, 0, 0, 0, time.UTC)
	deadline := now.Add(24 * time.Hour)
	row := &fakeRow{values: []any{
		"reorg-001", "canonical-001", "payment-001", "allocation-001",
		"instruction-001", uint64(31337), "0xgateway", "0xtransaction",
		"gateway-event-001", uint64(0), "0xreceipts-root",
		"0xinclusion-proof", "0xfinality-policy", "0xheader-authority",
		"0xreceipt-header-signature", "0xhead-header-signature",
		"0xreplacement-header-signature", "0xdetected-head-header-signature",
		"0xorphaned-block", uint64(100),
		"0xreplacement-block", uint64(100), uint64(12), uint64(112),
		"0xdetected-head",
		"0x9999999999999999999999999999999999999999999999999999999999999999",
		"raw-gateway-payload",
		"chain-operations",
		"reorg-evidence", now.Add(-2 * time.Hour), now, deadline,
	}}
	repository := &Repository{queryer: fakeQueryer{row: row}}
	reorg, err := repository.LoadDeepReorg(context.Background(), "canonical-001")
	if err != nil {
		t.Fatal(err)
	}
	if !reorg.Deep ||
		reorg.PaymentID != "payment-001" ||
		reorg.AllocationID != "allocation-001" ||
		reorg.InstructionDigest != "instruction-001" ||
		reorg.ChainID != 31337 ||
		reorg.Gateway != "0xgateway" ||
		reorg.TransactionIndex != 0 ||
		reorg.ReceiptsRoot != "0xreceipts-root" ||
		reorg.InclusionProofHash != "0xinclusion-proof" ||
		reorg.FinalityPolicyHash != "0xfinality-policy" ||
		reorg.HeaderAuthorityHash != "0xheader-authority" ||
		reorg.ReceiptHeaderSignatureHash != "0xreceipt-header-signature" ||
		reorg.ConfirmationHeadHeaderSignatureHash !=
			"0xhead-header-signature" ||
		reorg.ReplacementHeaderSignatureHash !=
			"0xreplacement-header-signature" ||
		reorg.DetectedHeadHeaderSignatureHash !=
			"0xdetected-head-header-signature" ||
		reorg.OrphanedBlockHash != "0xorphaned-block" ||
		reorg.ReplacementBlockHash != "0xreplacement-block" ||
		reorg.OrphanedEventEvidenceHash !=
			"0x9999999999999999999999999999999999999999999999999999999999999999" ||
		reorg.OrphanedRawPayloadHash != "raw-gateway-payload" ||
		reorg.Owner != "chain-operations" ||
		reorg.EvidenceHash != "reorg-evidence" ||
		!reorg.SubmissionSubmittedAt.Equal(now.Add(-2*time.Hour)) ||
		!reorg.ResolutionDeadline.Equal(deadline) ||
		!strings.Contains(row.query, "reorg_kind = 'DEEP'") ||
		!strings.Contains(row.query, "orphaned_event_evidence_hash") ||
		!strings.Contains(row.query, "orphaned_raw_payload_hash") {
		t.Fatalf("durable reorg lost compensation evidence: %#v", reorg)
	}
}

func TestRecordDeepCompensationUsesAtomicDatabaseFunctionAndEvidenceOrder(
	t *testing.T,
) {
	input, authority := settlementtest.ConfirmedWithDeepReorg(t)
	reorg := authority.Evidence()
	verified, err := settlementintegration.AdaptVerifiedReorg(
		settlementaccounting.ReorgMetadata{
			ReorgID:            reorg.ReorgID,
			CanonicalizationID: "canonical-001",
			Owner:              "chain-operations",
			ResolutionDeadline: reorg.DetectedAt.Add(24 * time.Hour),
		},
		input,
		authority,
	)
	if err != nil {
		t.Fatal(err)
	}

	row := &fakeRow{values: []any{"compensation-001"}}
	repository := &Repository{queryer: fakeQueryer{row: row}}
	compensationID, err := repository.RecordDeepCompensation(
		context.Background(),
		DeepCompensationRequest{
			CompensationID:           "compensation-001",
			CompensationEvidenceHash: "compensation-evidence",
			ConfirmationID:           "confirmation-001",
			Reorg:                    verified,
		},
	)
	evidence := verified.Evidence()
	if err != nil ||
		compensationID != "compensation-001" ||
		!strings.Contains(row.query, "record_deep_canonical_settlement_compensation") ||
		len(row.args) != 33 ||
		row.args[9] != "0" ||
		row.args[16] != evidence.ReplacementHeaderSignatureHash ||
		row.args[17] != evidence.DetectedHeadHeaderSignatureHash ||
		row.args[25] != evidence.OrphanedEventEvidenceHash ||
		row.args[26] != evidence.OrphanedRawPayloadHash ||
		row.args[27] != evidence.EvidenceHash ||
		row.args[28] != evidence.SubmissionSubmittedAt ||
		row.args[29] != "compensation-evidence" {
		t.Fatalf(
			"atomic compensation call or evidence order failed: %q %v %#v",
			compensationID,
			err,
			row.args,
		)
	}
}

func TestCommitCanonicalSuccessUsesOpaqueProjectionAndReturnsExactBatch(
	t *testing.T,
) {
	confirmation, _ := settlementtest.ConfirmedWithDeepReorg(t)
	row := &fakeRow{values: []any{
		`{"confirmation_id":"confirmation:canonical-001",` +
			`"conversion_id":"conversion:canonical-001",` +
			`"gateway_event_id":"` + confirmation.EventID() + `",` +
			`"journal_ids":["journal-1","journal-2","journal-3",` +
			`"journal-4","journal-5","journal-6","journal-7"]}`,
	}}
	repository := &Repository{queryer: fakeQueryer{row: row}}
	convertedAt := confirmation.AccountingProjection().ConfirmedAt.Add(-time.Minute)
	result, err := repository.CommitCanonicalSuccess(
		context.Background(),
		CanonicalSuccessCommitRequest{
			Confirmation:           confirmation,
			ConversionEvidenceHash: "conversion-evidence",
			ConvertedAt:            convertedAt,
			TargetBookID:           "loan-subledger",
		},
	)
	if err != nil ||
		result.ConfirmationID != "confirmation:canonical-001" ||
		result.GatewayEventID != confirmation.EventID() ||
		len(result.JournalIDs) != 7 ||
		!strings.Contains(row.query, "commit_canonical_external_settlement") ||
		len(row.args) != 4 ||
		row.args[1] != "conversion-evidence" ||
		row.args[2] != convertedAt.UTC() ||
		row.args[3] != "loan-subledger" ||
		!strings.Contains(row.args[0].(string), `"PaymentID"`) ||
		!strings.Contains(row.args[0].(string), `"TransactionIndex"`) {
		t.Fatalf("atomic canonical success call failed: %#v %v %#v", result, err, row.args)
	}
}

func TestCommitCanonicalSuccessRejectsMissingOpaqueConfirmation(t *testing.T) {
	repository := &Repository{queryer: fakeQueryer{row: &fakeRow{}}}
	if _, err := repository.CommitCanonicalSuccess(
		context.Background(),
		CanonicalSuccessCommitRequest{
			ConversionEvidenceHash: "conversion-evidence",
			ConvertedAt:            time.Now().UTC(),
			TargetBookID:           "loan-subledger",
		},
	); !errors.Is(err, ErrInvalidRepository) {
		t.Fatalf("missing coordinator authority was accepted: %v", err)
	}
}
