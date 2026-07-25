package settlementaccounting

import (
	"context"
	"errors"
	"math/big"
	"slices"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementtest"
)

type authorityTestQueryer struct {
	row   *authorityTestRow
	query string
	args  []any
}

func (queryer *authorityTestQueryer) QueryRowContext(
	_ context.Context,
	query string,
	args ...any,
) authorityRow {
	queryer.query = query
	queryer.args = args
	return queryer.row
}

type authorityTestRow struct {
	canonicalizationID string
	conversionHash     string
	err                error
}

func (row *authorityTestRow) Scan(dest ...any) error {
	if row.err != nil {
		return row.err
	}
	*dest[0].(*string) = row.canonicalizationID
	*dest[1].(*string) = row.conversionHash
	return nil
}

func TestDurableConfirmationAuthorityIsDerivedFromCoordinatorIdentity(t *testing.T) {
	input, _ := settlementtest.ConfirmedWithDeepReorg(t)
	projection := input.AccountingProjection()
	queryer := &authorityTestQueryer{row: &authorityTestRow{
		canonicalizationID: "canonical-from-database",
		conversionHash:     "conversion-from-database",
	}}
	authority, err := loadDurableConfirmationAuthority(
		context.Background(),
		queryer,
		input,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(queryer.args) != 20 ||
		queryer.args[0] != projection.PaymentID ||
		queryer.args[1] != projection.AllocationID ||
		queryer.args[2] != projection.InstructionDigest ||
		queryer.args[3] != projection.TransactionHash ||
		queryer.args[4] != projection.EventID ||
		queryer.args[5] != projection.GatewayPayloadHash ||
		queryer.args[6] != projection.FinalityEvidenceHash ||
		queryer.args[12] != "0" ||
		queryer.args[13] != projection.ReceiptsRoot ||
		queryer.args[14] != projection.InclusionProofHash ||
		queryer.args[15] != projection.FinalityPolicyHash ||
		queryer.args[16] != projection.HeaderAuthorityHash ||
		queryer.args[17] != projection.ReceiptHeaderSignatureHash ||
		queryer.args[18] != projection.HeadHeaderSignatureHash ||
		queryer.args[19] != projection.EventEvidenceHash {
		t.Fatalf("durable authority query lost coordinator identity: %#v", queryer.args)
	}
	verified, err := VerifyConfirmation(authority, input)
	evidence := verified.Evidence()
	if err != nil ||
		evidence.CanonicalizationID != "canonical-from-database" ||
		evidence.ConversionEvidenceHash != "conversion-from-database" ||
		evidence.TransactionIndex != projection.TransactionIndex ||
		evidence.ReceiptsRoot != projection.ReceiptsRoot ||
		evidence.InclusionProofHash != projection.InclusionProofHash ||
		evidence.HeaderAuthorityHash != projection.HeaderAuthorityHash ||
		evidence.ReceiptHeaderSignatureHash !=
			projection.ReceiptHeaderSignatureHash ||
		evidence.HeadHeaderSignatureHash !=
			projection.HeadHeaderSignatureHash ||
		evidence.EventEvidenceHash != projection.EventEvidenceHash {
		t.Fatalf("database authority was not preserved: %#v %v", verified, err)
	}
}

func TestVerifiedConfirmationRequiresMatchingDurableAuthority(t *testing.T) {
	input, _ := settlementtest.ConfirmedWithDeepReorg(t)
	projection := input.AccountingProjection()
	authority := DurableConfirmationAuthority{
		canonicalizationID:     "canonical-001",
		conversionEvidenceHash: "conversion-evidence-001",
		paymentID:              projection.PaymentID,
		allocationID:           projection.AllocationID,
		instructionDigest:      projection.InstructionDigest,
		transactionHash:        projection.TransactionHash,
		gatewayEventID:         projection.EventID,
		eventEvidenceHash:      projection.EventEvidenceHash,
		rawPayloadHash:         projection.GatewayPayloadHash,
		finalityEvidenceHash:   projection.FinalityEvidenceHash,
		transactionIndex:       projection.TransactionIndex,
		receiptsRoot:           projection.ReceiptsRoot,
		inclusionProofHash:     projection.InclusionProofHash,
		finalityPolicyHash:     projection.FinalityPolicyHash,
		headerAuthorityHash:    projection.HeaderAuthorityHash,
		receiptHeaderSigHash:   projection.ReceiptHeaderSignatureHash,
		headHeaderSigHash:      projection.HeadHeaderSignatureHash,
	}
	verified, err := VerifyConfirmation(authority, input)
	if err != nil || verified.Evidence().CanonicalizationID != "canonical-001" {
		t.Fatalf("matching durable authority was rejected: %#v %v", verified, err)
	}
	authority.paymentID = "caller-relabelled-payment"
	if _, err := VerifyConfirmation(authority, input); !errors.Is(
		err,
		ErrInvalidConfirmation,
	) {
		t.Fatalf("mismatched durable authority was accepted: %v", err)
	}
	if _, err := VerifyConfirmation(
		DurableConfirmationAuthority{},
		input,
	); !errors.Is(err, ErrInvalidConfirmation) {
		t.Fatalf("zero durable authority was accepted: %v", err)
	}
}

func TestConfirmationPostsOneBalancedBatchAndReplays(t *testing.T) {
	book := ledger.New()
	seedPhase7ASource(
		t, book, "payment-001", "loan-001", "1250",
		"fiat-usd", "borrower-001", "1100", "9140",
	)
	poster, err := New(book, "unified-protocol", "loan-subledger")
	if err != nil {
		t.Fatalf("new poster: %v", err)
	}
	confirmation := validFixture("1250", "1000", "250", "1000", "0")

	ids, err := poster.ApplyConfirmation(confirmation)
	if err != nil {
		t.Fatalf("apply confirmation: %v", err)
	}
	if len(ids) != 8 || len(book.List()) != 10 {
		t.Fatalf("expected one eight-journal batch, got ids=%d journals=%d",
			len(ids), len(book.List()))
	}
	evidence := confirmation.Evidence()
	stored := poster.records[evidence.CanonicalizationID]
	if evidence.InstructionEvidenceHash == evidence.EventEvidenceHash ||
		evidence.EventEvidenceHash == evidence.RawGatewayPayloadHash ||
		stored.instructionEvidenceHash != evidence.InstructionEvidenceHash ||
		stored.eventEvidenceHash != evidence.EventEvidenceHash ||
		stored.rawGatewayPayloadHash != evidence.RawGatewayPayloadHash {
		t.Fatalf(
			"poster conflated distinct instruction/event/raw evidence: %#v",
			stored,
		)
	}
	sourceConverted, _ := book.Get("canonical:canonical-001:source-converted")
	if sourceConverted.Entries[1].AccountCode != AccountProviderBankAsset {
		t.Fatal("source account was not derived from the Phase 7A final journal")
	}
	assertBalance(t, book, AccountProviderBankAsset, "fiat-usd", "0")
	assertBalance(t, book, AccountUnallocatedPayment, "fiat-usd", "0")
	assertBalance(t, book, AccountConversionClearing, "fiat-usd", "0")
	for _, account := range []string{
		AccountRestrictedToken,
		AccountConversionClearing,
		AccountUnallocatedPayment,
		AccountLenderRepaymentPayable,
		AccountRefundPayable,
	} {
		assertBalance(t, book, account, "usdc-mainnet", "0")
	}
	assertBalance(t, book, AccountPrincipalReceivable, "usdc-mainnet", "-1000")
	assertBalance(t, book, AccountLenderPrincipalClaims, "usdc-mainnet", "1000")

	replayed, err := poster.ApplyConfirmation(confirmation)
	if err != nil || !slices.Equal(replayed, ids) || len(book.List()) != 10 {
		t.Fatal("exact replay changed the economic result")
	}
	restarted, _ := New(book, "unified-protocol", "loan-subledger")
	replayed, err = restarted.ApplyConfirmation(confirmation)
	if err != nil || !slices.Equal(replayed, ids) || len(book.List()) != 10 {
		t.Fatal("restart replay changed the economic result")
	}
	other := confirmation
	other.evidence.CanonicalizationID = "canonical-002"
	other.evidence.AllocationID = "allocation-002"
	otherPoster, _ := New(book, "unified-protocol", "loan-subledger")
	if _, err := otherPoster.ApplyConfirmation(other); !errors.Is(
		err,
		ErrPaymentAlreadyClaimed,
	) {
		t.Fatalf("expected durable payment claim rejection, got %v", err)
	}
	conflict := confirmation
	conflict.evidence.RawGatewayPayloadHash = "different-evidence"
	if _, err := poster.ApplyConfirmation(conflict); !errors.Is(err, ErrConfirmationConflict) {
		t.Fatalf("expected confirmation conflict, got %v", err)
	}
}

func TestPartialConfirmationOmitsRefundJournal(t *testing.T) {
	book := ledger.New()
	seedPhase7ASource(
		t, book, "payment-001", "loan-001", "400",
		"fiat-usd", "borrower-001", "1120", "9130",
	)
	poster, _ := New(book, "unified-protocol", "loan-subledger")
	confirmation := validFixture("400", "400", "0", "1000", "600")

	ids, err := poster.ApplyConfirmation(confirmation)
	if err != nil {
		t.Fatalf("apply partial confirmation: %v", err)
	}
	if len(ids) != 7 {
		t.Fatalf("partial settlement posted %d journals, want 7", len(ids))
	}
	if _, exists := book.Get("canonical:canonical-001:borrower-refund"); exists {
		t.Fatal("zero excess created a refund journal")
	}
	sourceConverted, _ := book.Get("canonical:canonical-001:source-converted")
	if sourceConverted.Entries[1].AccountCode != AccountProviderCardAsset {
		t.Fatal("card provider account was not derived from final evidence")
	}
}

func TestConfirmationRejectsPhase7BDoublePostingAndPartialSourceUse(t *testing.T) {
	tests := []struct {
		name         string
		sourceSystem string
		want         error
	}{
		{
			name:         "phase 7b allocation",
			sourceSystem: "payment-allocation",
			want:         ErrPaymentAlreadyClaimed,
		},
		{
			name:         "other partial clearing",
			sourceSystem: "unexpected-source",
			want:         ErrInvalidSourceEvidence,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			book := ledger.New()
			seedPhase7ASource(
				t, book, "payment-001", "loan-001", "1250",
				"fiat-usd", "borrower-001", "1100", "9140",
			)
			_, err := book.Post(ledger.Journal{
				ID:             "prior-use:" + test.sourceSystem,
				LegalEntityID:  "unified-protocol",
				BookID:         "loan-subledger",
				SourceSystem:   test.sourceSystem,
				EntryType:      "PRIOR_ALLOCATION",
				SourceEventID:  "payment-001",
				LoanID:         "loan-001",
				IdempotencyKey: "prior-use:" + test.sourceSystem,
				CorrelationID:  "correlation-001",
				EffectiveAt:    time.Now().UTC(),
				Entries: []ledger.Entry{
					{
						AccountCode: AccountUnallocatedPayment,
						Side:        ledger.Debit,
						AssetID:     "fiat-usd",
						Units:       "250",
						LoanID:      "loan-001",
					},
					{
						AccountCode: AccountPrincipalReceivable,
						Side:        ledger.Credit,
						AssetID:     "fiat-usd",
						Units:       "250",
						LoanID:      "loan-001",
					},
				},
				EvidenceHash: "prior-evidence",
			})
			if err != nil {
				t.Fatalf("seed prior use: %v", err)
			}
			poster, _ := New(book, "unified-protocol", "loan-subledger")
			if _, err := poster.ApplyConfirmation(
				validFixture("1250", "1000", "250", "1000", "0"),
			); !errors.Is(err, test.want) {
				t.Fatalf("expected %v, got %v", test.want, err)
			}
			if len(book.List()) != 3 {
				t.Fatal("rejected confirmation posted a partial batch")
			}
		})
	}
}

func TestConfirmationRejectsReversedOrInvalidSource(t *testing.T) {
	book := ledger.New()
	seedPhase7ASource(
		t, book, "payment-001", "loan-001", "1250",
		"fiat-usd", "borrower-001", "1100", "9140",
	)
	_, err := book.Reverse(
		"payment:payment-001:final",
		"payment:payment-001:final-reversal",
		"payment-001:final-reversal",
		"provider:event-reversal",
		"provider reversal",
		time.Now().UTC(),
	)
	if err != nil {
		t.Fatalf("reverse final source: %v", err)
	}
	poster, _ := New(book, "unified-protocol", "loan-subledger")
	if _, err := poster.ApplyConfirmation(
		validFixture("1250", "1000", "250", "1000", "0"),
	); !errors.Is(err, ErrInvalidSourceEvidence) {
		t.Fatalf("expected reversed source rejection, got %v", err)
	}

	for _, mutate := range []func(*Confirmation){
		func(item *Confirmation) { item.TargetUnits = "1249" },
		func(item *Confirmation) { item.SourceAssetID = item.TargetAssetID },
		func(item *Confirmation) { item.RefundableExcessUnits = "249" },
		func(item *Confirmation) { item.DebtAfterUnits = "1" },
		func(item *Confirmation) { item.InstructionDigest = "" },
		func(item *Confirmation) { item.BorrowerID = item.LenderID },
	} {
		item := validFixture("1250", "1000", "250", "1000", "0")
		mutate(&item.evidence)
		if _, err := poster.ApplyConfirmation(item); !errors.Is(err, ErrInvalidConfirmation) {
			t.Fatalf("invalid conservation was accepted: %v", err)
		}
	}
}

func TestConfirmationBatchFailureIsAtomic(t *testing.T) {
	book := ledger.New()
	seedPhase7ASource(
		t, book, "payment-001", "loan-001", "1250",
		"fiat-usd", "borrower-001", "1100", "9140",
	)
	_, err := book.Post(ledger.Journal{
		ID:             "canonical:canonical-001:target-custody",
		LegalEntityID:  "unified-protocol",
		BookID:         "loan-subledger",
		SourceSystem:   "conflicting-source",
		EntryType:      "CONFLICT",
		SourceEventID:  "conflicting-event",
		LoanID:         "loan-001",
		IdempotencyKey: "conflicting-idempotency",
		CorrelationID:  "correlation-001",
		EffectiveAt:    time.Now().UTC(),
		Entries: []ledger.Entry{
			{
				AccountCode: AccountRestrictedToken,
				Side:        ledger.Debit,
				AssetID:     "usdc-mainnet",
				Units:       "1",
				LoanID:      "loan-001",
			},
			{
				AccountCode: AccountConversionClearing,
				Side:        ledger.Credit,
				AssetID:     "usdc-mainnet",
				Units:       "1",
				LoanID:      "loan-001",
			},
		},
		EvidenceHash: "conflicting-evidence",
	})
	if err != nil {
		t.Fatalf("seed conflict: %v", err)
	}
	before := len(book.List())
	poster, _ := New(book, "unified-protocol", "loan-subledger")
	if _, err := poster.ApplyConfirmation(
		validFixture("1250", "1000", "250", "1000", "0"),
	); err == nil {
		t.Fatal("expected batch conflict")
	}
	if len(book.List()) != before {
		t.Fatal("failed batch committed partial canonical journals")
	}
}

func TestDeepReorgCompensatesWholeBatchOnce(t *testing.T) {
	input, durableReorg := settlementtest.ConfirmedWithDeepReorg(t)
	projection := input.AccountingProjection()
	if projection.EligibilityEvidenceHash != projection.EventEvidenceHash ||
		projection.EligibilityEvidenceHash == projection.GatewayPayloadHash ||
		projection.EventEvidenceHash == projection.GatewayPayloadHash {
		t.Fatal("composed fixture violated canonical event binding or raw separation")
	}
	confirmationAuthority := DurableConfirmationAuthority{
		canonicalizationID:     "canonical-001",
		conversionEvidenceHash: "conversion-evidence-001",
		paymentID:              projection.PaymentID,
		allocationID:           projection.AllocationID,
		instructionDigest:      projection.InstructionDigest,
		transactionHash:        projection.TransactionHash,
		gatewayEventID:         projection.EventID,
		eventEvidenceHash:      projection.EventEvidenceHash,
		rawPayloadHash:         projection.GatewayPayloadHash,
		finalityEvidenceHash:   projection.FinalityEvidenceHash,
		transactionIndex:       projection.TransactionIndex,
		receiptsRoot:           projection.ReceiptsRoot,
		inclusionProofHash:     projection.InclusionProofHash,
		finalityPolicyHash:     projection.FinalityPolicyHash,
		headerAuthorityHash:    projection.HeaderAuthorityHash,
		receiptHeaderSigHash:   projection.ReceiptHeaderSignatureHash,
		headHeaderSigHash:      projection.HeadHeaderSignatureHash,
	}
	confirmation, err := VerifyConfirmation(confirmationAuthority, input)
	if err != nil {
		t.Fatalf("verify composed confirmation: %v", err)
	}
	confirmationEvidence := confirmation.Evidence()
	if confirmationEvidence.InstructionEvidenceHash !=
		projection.EligibilityEvidenceHash ||
		confirmationEvidence.EventEvidenceHash != projection.EventEvidenceHash ||
		confirmationEvidence.RawGatewayPayloadHash !=
			projection.GatewayPayloadHash {
		t.Fatalf(
			"verified confirmation conflated instruction/event/raw evidence: %#v",
			confirmationEvidence,
		)
	}

	book := ledger.New()
	seedPhase7ASource(
		t,
		book,
		confirmationEvidence.PaymentID,
		confirmationEvidence.LoanID,
		confirmationEvidence.SourceUnits,
		confirmationEvidence.SourceAssetID,
		confirmationEvidence.BorrowerID,
		"1100",
		"9140",
	)
	poster, _ := New(book, "unified-protocol", "loan-subledger")
	originalIDs, err := poster.ApplyConfirmation(confirmation)
	if err != nil {
		t.Fatalf("apply confirmation: %v", err)
	}
	restarted, _ := New(book, "unified-protocol", "loan-subledger")
	rehydratedIDs, err := restarted.ApplyConfirmation(confirmation)
	if err != nil || !slices.Equal(rehydratedIDs, originalIDs) {
		t.Fatalf("restart did not rehydrate confirmation evidence: %v", err)
	}
	poster = restarted
	stored := poster.records[confirmationEvidence.CanonicalizationID]
	if stored.instructionEvidenceHash !=
		confirmationEvidence.InstructionEvidenceHash ||
		stored.eventEvidenceHash != confirmationEvidence.EventEvidenceHash ||
		stored.rawGatewayPayloadHash !=
			confirmationEvidence.RawGatewayPayloadHash {
		t.Fatalf(
			"poster record conflated instruction/event/raw evidence: %#v",
			stored,
		)
	}

	durableEvidence := durableReorg.Evidence()
	verified, err := VerifyReorg(
		ReorgMetadata{
			ReorgID:            durableEvidence.ReorgID,
			CanonicalizationID: confirmationEvidence.CanonicalizationID,
			Owner:              "chain-operations",
			ResolutionDeadline: durableEvidence.DetectedAt.Add(24 * time.Hour),
		},
		input,
		durableReorg,
	)
	if err != nil {
		t.Fatalf("verify composed reorg: %v", err)
	}
	reorg := verified.Evidence()
	if reorg.OrphanedEventEvidenceHash != projection.EventEvidenceHash ||
		reorg.OrphanedRawPayloadHash != projection.GatewayPayloadHash {
		t.Fatalf("verified reorg lost event/raw separation: %#v", reorg)
	}

	journalCountBeforeReorg := len(book.List())
	missingEventEvidence := reorg
	missingEventEvidence.OrphanedEventEvidenceHash = ""
	if _, err := poster.CompensateReorg(
		VerifiedReorg{evidence: missingEventEvidence},
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("expected missing event-evidence rejection, got %v", err)
	}
	if len(book.List()) != journalCountBeforeReorg || len(poster.Incidents()) != 0 {
		t.Fatal("missing event evidence posted partial compensation")
	}
	mismatchedEventEvidence := reorg
	mismatchedEventEvidence.OrphanedEventEvidenceHash =
		"0x9999999999999999999999999999999999999999999999999999999999999999"
	if _, err := poster.CompensateReorg(
		VerifiedReorg{evidence: mismatchedEventEvidence},
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("expected event-evidence mismatch rejection, got %v", err)
	}
	if len(book.List()) != journalCountBeforeReorg || len(poster.Incidents()) != 0 {
		t.Fatal("mutated event evidence posted partial compensation")
	}
	mismatched := reorg
	mismatched.GatewayTransactionHash = "0xdifferent"
	if _, err := poster.CompensateReorg(
		VerifiedReorg{evidence: mismatched},
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("expected orphaned transaction mismatch rejection, got %v", err)
	}
	mismatched = reorg
	mismatched.InstructionDigest = "different-instruction"
	if _, err := poster.CompensateReorg(
		VerifiedReorg{evidence: mismatched},
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("expected instruction mismatch rejection, got %v", err)
	}
	shallow := reorg
	shallow.Deep = false
	if _, err := poster.CompensateReorg(
		VerifiedReorg{evidence: shallow},
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("shallow reorg unexpectedly posted compensation: %v", err)
	}
	reversalIDs, err := poster.CompensateReorg(verified)
	if err != nil {
		t.Fatalf("compensate reorg: %v", err)
	}
	if len(reversalIDs) != len(originalIDs) {
		t.Fatal("reorg did not compensate the complete batch")
	}
	incidents := poster.Incidents()
	if len(incidents) != 1 ||
		incidents[0].ReorgID != reorg.ReorgID ||
		incidents[0].InstructionDigest != confirmationEvidence.InstructionDigest {
		t.Fatalf("deep reorg did not atomically create its owned incident: %#v", incidents)
	}
	for index, reversalID := range reversalIDs {
		reversal, exists := book.Get(reversalID)
		if !exists || reversal.ReversalOf != originalIDs[index] {
			t.Fatal("reorg compensation lost original linkage")
		}
	}
	assertBalance(
		t,
		book,
		AccountProviderBankAsset,
		confirmationEvidence.SourceAssetID,
		confirmationEvidence.SourceUnits,
	)
	assertBalance(
		t,
		book,
		AccountUnallocatedPayment,
		confirmationEvidence.SourceAssetID,
		"-"+confirmationEvidence.SourceUnits,
	)
	for _, account := range []string{
		AccountRestrictedToken,
		AccountConversionClearing,
		AccountUnallocatedPayment,
		AccountPrincipalReceivable,
		AccountLenderPrincipalClaims,
		AccountLenderRepaymentPayable,
		AccountRefundPayable,
	} {
		assertBalance(t, book, account, confirmationEvidence.TargetAssetID, "0")
	}

	replayed, err := poster.CompensateReorg(verified)
	if err != nil || !slices.Equal(replayed, reversalIDs) || len(poster.Incidents()) != 1 {
		t.Fatal("exact reorg replay changed the compensation")
	}
	conflict := reorg
	conflict.EvidenceHash = "different-reorg-evidence"
	if _, err := poster.CompensateReorg(
		VerifiedReorg{evidence: conflict},
	); !errors.Is(err, ErrReorgConflict) {
		t.Fatalf("expected reorg conflict, got %v", err)
	}
}

func seedPhase7ASource(
	t *testing.T,
	book *ledger.Ledger,
	paymentID string,
	loanID string,
	units string,
	sourceAssetID string,
	borrowerID string,
	sourceAccount string,
	pendingAccount string,
) {
	t.Helper()
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	entry := func(account string, side ledger.Side) ledger.Entry {
		return ledger.Entry{
			AccountCode: account,
			Side:        side,
			AssetID:     sourceAssetID,
			Units:       units,
			PartyID:     borrowerID,
			LoanID:      loanID,
		}
	}
	_, err := book.PostBatch([]ledger.Journal{
		{
			ID:             "payment:" + paymentID + ":provisional",
			LegalEntityID:  "unified-protocol",
			BookID:         "settlement-subledger",
			SourceSystem:   "payment-orchestrator",
			EntryType:      "PAYMENT_PROVISIONAL",
			SourceEventID:  "provider:event-provisional",
			LoanID:         loanID,
			IdempotencyKey: "payment:" + paymentID + ":provisional",
			CorrelationID:  "correlation-001",
			EffectiveAt:    now,
			Entries: []ledger.Entry{
				entry(pendingAccount, ledger.Debit),
				entry(AccountUnallocatedPayment, ledger.Credit),
			},
			EvidenceHash: "provisional-evidence",
		},
		{
			ID:             "payment:" + paymentID + ":final",
			LegalEntityID:  "unified-protocol",
			BookID:         "settlement-subledger",
			SourceSystem:   "payment-orchestrator",
			EntryType:      "PAYMENT_FINAL",
			SourceEventID:  "provider:event-final",
			LoanID:         loanID,
			IdempotencyKey: "payment:" + paymentID + ":final",
			CorrelationID:  "correlation-001",
			EffectiveAt:    now.Add(time.Minute),
			Entries: []ledger.Entry{
				entry(sourceAccount, ledger.Debit),
				entry(pendingAccount, ledger.Credit),
			},
			EvidenceHash: "final-evidence",
		},
	})
	if err != nil {
		t.Fatalf("seed Phase 7A source: %v", err)
	}
}

func validFixture(
	gross string,
	principal string,
	excess string,
	debtBefore string,
	debtAfter string,
) VerifiedConfirmation {
	return VerifiedConfirmation{evidence: Confirmation{
		CanonicalizationID:           "canonical-001",
		InstructionDigest:            "instruction-digest-001",
		PaymentID:                    "payment-001",
		AllocationID:                 "allocation-001",
		LoanID:                       "loan-001",
		ChainID:                      31337,
		Gateway:                      "0xgateway",
		LoanAccount:                  "0xloanaccount",
		Finalizer:                    "0xfinalizer",
		Attester:                     "0xattester",
		BorrowerID:                   "borrower-001",
		LenderID:                     "lender-001",
		SourceAssetID:                "fiat-usd",
		TargetAssetID:                "usdc-mainnet",
		TargetToken:                  "0xtoken",
		SourceUnits:                  gross,
		TargetUnits:                  gross,
		PrincipalUnits:               principal,
		RefundableExcessUnits:        excess,
		DebtBeforeUnits:              debtBefore,
		DebtAfterUnits:               debtAfter,
		StateNonceBefore:             1,
		StateNonceAfter:              2,
		PolicySetHash:                "policy-set",
		ProviderIDHash:               "provider-id-hash",
		ProviderReferenceHash:        "provider-reference-hash",
		ReconciliationCommitment:     "reconciliation-commitment",
		OriginalJournalSetHash:       "original-journal-set-hash",
		ConversionPolicyHash:         "conversion-policy",
		FinalityPolicyHash:           "0x1111111111111111111111111111111111111111111111111111111111111111",
		InstructionEvidenceHash:      "0x7777777777777777777777777777777777777777777777777777777777777777",
		JournalRef:                   "journal-ref",
		ProviderFinalizedAt:          1_753_353_000,
		ReversalDeadline:             1_753_356_600,
		OriginalProvisionalJournalID: "payment:payment-001:provisional",
		OriginalFinalJournalID:       "payment:payment-001:final",
		ReconciliationID:             "reconciliation-001",
		ConversionEvidenceHash:       "conversion-evidence",
		GatewayTransactionHash:       "0xtransaction",
		GatewayEventID:               "gateway-event-001",
		GatewayBlockHash:             "0xblock-100",
		GatewayBlockNumber:           100,
		GatewayLogIndex:              4,
		TransactionIndex:             0,
		ReceiptsRoot:                 "0x2222222222222222222222222222222222222222222222222222222222222222",
		InclusionProofHash:           "0x3333333333333333333333333333333333333333333333333333333333333333",
		ConfirmationDepth:            12,
		FinalityHeadBlock:            112,
		FinalityHeadHash:             "0xblock-112",
		HeaderAuthorityHash:          "0x4444444444444444444444444444444444444444444444444444444444444444",
		ReceiptHeaderSignatureHash:   "0x5555555555555555555555555555555555555555555555555555555555555555",
		HeadHeaderSignatureHash:      "0x6666666666666666666666666666666666666666666666666666666666666666",
		FinalityEvidenceHash:         "finality-evidence",
		EventEvidenceHash:            "0x8888888888888888888888888888888888888888888888888888888888888888",
		CorrelationID:                "correlation-001",
		RawGatewayPayloadHash:        "raw-gateway-payload-hash",
		ConfirmedAt:                  time.Date(2026, 7, 24, 13, 0, 0, 0, time.UTC),
	}}
}

func assertBalance(
	t *testing.T,
	book *ledger.Ledger,
	account string,
	asset string,
	expected string,
) {
	t.Helper()
	balance := new(big.Int)
	for _, item := range book.List() {
		for _, line := range item.Entries {
			if line.AccountCode != account || line.AssetID != asset {
				continue
			}
			units, ok := new(big.Int).SetString(line.Units, 10)
			if !ok {
				t.Fatalf("invalid units in journal %s", item.ID)
			}
			if line.Side == ledger.Debit {
				balance.Add(balance, units)
			} else {
				balance.Sub(balance, units)
			}
		}
	}
	if balance.String() != expected {
		t.Fatalf("account %s asset %s balance %s, want %s",
			account, asset, balance.String(), expected)
	}
}
