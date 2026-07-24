package paymentaccounting

import (
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

func signedCallback(
	t *testing.T,
	privateKey ed25519.PrivateKey,
	callback payment.Callback,
) ([]byte, []byte) {
	t.Helper()
	raw, err := payment.EncodeCallback(callback)
	if err != nil {
		t.Fatalf("encode callback: %v", err)
	}
	return raw, ed25519.Sign(privateKey, payment.SigningMessage(raw))
}

func paymentIntent(rail payment.Rail, status payment.Status, now time.Time) payment.Intent {
	return payment.Intent{
		PaymentID:         "payment-001",
		LegalEntityID:     "entity-local",
		IdempotencyKey:    "intent-001",
		CorrelationID:     "correlation-001",
		PayerReference:    "payer-opaque-001",
		LoanID:            "loan-local-001",
		ProviderID:        "provider-local",
		ProviderReference: "provider-reference-001",
		Rail:              rail,
		Purpose:           "LOAN_REPAYMENT_UNALLOCATED",
		AssetID:           "asset:local:usd",
		Units:             "1000",
		ExpiresAt:         now.Add(time.Hour),
		SchemaVersion:     1,
		Status:            status,
		Version:           3,
		CreatedAt:         now,
		UpdatedAt:         now,
	}
}

func transition(
	intent payment.Intent,
	from payment.Status,
	to payment.Status,
	eventID string,
	now time.Time,
) payment.Transition {
	intent.Status = to
	switch to {
	case payment.StatusProvisional:
		intent.ProvisionalAt = now
	case payment.StatusFinal:
		intent.ProvisionalAt = now.Add(-time.Minute)
		intent.FinalizedAt = now
	case payment.StatusReversed:
		intent.ProvisionalAt = now.Add(-2 * time.Minute)
		if from == payment.StatusFinal {
			intent.FinalizedAt = now.Add(-time.Minute)
		}
		intent.ReversedAt = now
	}
	return payment.Transition{
		Payment:         intent,
		From:            from,
		To:              to,
		ProviderEventID: eventID,
		OccurredAt:      now,
		ReceivedAt:      now.Add(time.Second),
		EvidenceHash:    "evidence-" + eventID,
	}
}

func newPoster(t *testing.T) (*Poster, *ledger.Ledger) {
	t.Helper()
	book := ledger.New()
	poster, err := New(book, "entity-local", "protocol")
	if err != nil {
		t.Fatalf("new payment poster: %v", err)
	}
	return poster, book
}

func TestBankProvisionalAndFinalPostDistinctBalancedAccounts(t *testing.T) {
	poster, book := newPoster(t)
	now := time.Unix(1_750_100_000, 0).UTC()
	intent := paymentIntent(payment.RailBank, payment.StatusProvisional, now)
	provisional := transition(
		intent,
		payment.StatusProcessing,
		payment.StatusProvisional,
		"event-provisional",
		now.Add(time.Minute),
	)
	provisionalIDs, err := poster.Apply(provisional)
	if err != nil {
		t.Fatalf("post provisional: %v", err)
	}
	if !slices.Equal(provisionalIDs, []string{"payment:payment-001:provisional"}) {
		t.Fatalf("unexpected provisional IDs: %v", provisionalIDs)
	}
	provisionalJournal, _ := book.Get(provisionalIDs[0])
	if provisionalJournal.Entries[0].AccountCode != "9140" ||
		provisionalJournal.Entries[0].Side != ledger.Debit ||
		provisionalJournal.Entries[1].AccountCode != "9120" ||
		provisionalJournal.Entries[1].Side != ledger.Credit {
		t.Fatal("bank provisional mapping is not pending versus unallocated")
	}

	final := transition(
		intent,
		payment.StatusProvisional,
		payment.StatusFinal,
		"event-final",
		now.Add(2*time.Minute),
	)
	finalIDs, err := poster.Apply(final)
	if err != nil {
		t.Fatalf("post final: %v", err)
	}
	finalJournal, _ := book.Get(finalIDs[0])
	if finalJournal.Entries[0].AccountCode != "1100" ||
		finalJournal.Entries[1].AccountCode != "9140" {
		t.Fatal("bank final mapping did not clear pending settlement")
	}
	replayed, err := poster.Apply(final)
	if err != nil || !slices.Equal(replayed, finalIDs) || len(book.List()) != 2 {
		t.Fatal("final transition replay created a duplicate journal")
	}
}

func TestCardFinalReversalIsAtomicLinkedAndImmutable(t *testing.T) {
	poster, book := newPoster(t)
	now := time.Unix(1_750_200_000, 0).UTC()
	intent := paymentIntent(payment.RailCard, payment.StatusProvisional, now)
	if _, err := poster.Apply(transition(
		intent,
		payment.StatusProcessing,
		payment.StatusProvisional,
		"event-provisional",
		now.Add(time.Minute),
	)); err != nil {
		t.Fatalf("post provisional: %v", err)
	}
	if _, err := poster.Apply(transition(
		intent,
		payment.StatusProvisional,
		payment.StatusFinal,
		"event-final",
		now.Add(2*time.Minute),
	)); err != nil {
		t.Fatalf("post final: %v", err)
	}
	reversalIDs, err := poster.Apply(transition(
		intent,
		payment.StatusFinal,
		payment.StatusReversed,
		"event-reversal",
		now.Add(3*time.Minute),
	))
	if err != nil {
		t.Fatalf("post reversal: %v", err)
	}
	if len(reversalIDs) != 2 || len(book.List()) != 4 {
		t.Fatal("final reversal did not atomically offset both recognition stages")
	}
	final, _ := book.Get("payment:payment-001:final")
	if final.Entries[0].AccountCode != "1120" ||
		final.Entries[1].AccountCode != "9130" {
		t.Fatal("card final mapping is incorrect")
	}
	for _, reversalID := range reversalIDs {
		reversal, _ := book.Get(reversalID)
		if reversal.ReversalOf == "" || reversal.EntryType != "PAYMENT_REVERSAL" {
			t.Fatal("reversal journal lost its immutable original link")
		}
	}
	record, _ := poster.Record("payment-001")
	if !slices.Equal(record.ReversalJournalIDs, reversalIDs) {
		t.Fatal("payment accounting record lost reversal evidence")
	}
}

func TestAccountingRejectsSkippedOrConflictingTransitions(t *testing.T) {
	poster, book := newPoster(t)
	now := time.Unix(1_750_300_000, 0).UTC()
	intent := paymentIntent(payment.RailBank, payment.StatusFinal, now)
	if _, err := poster.Apply(transition(
		intent,
		payment.StatusProcessing,
		payment.StatusFinal,
		"event-final",
		now.Add(time.Minute),
	)); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("expected skipped-stage rejection, got %v", err)
	}
	provisional := transition(
		intent,
		payment.StatusProcessing,
		payment.StatusProvisional,
		"event-shared",
		now.Add(2*time.Minute),
	)
	if _, err := poster.Apply(provisional); err != nil {
		t.Fatalf("post provisional: %v", err)
	}
	conflict := provisional
	conflict.EvidenceHash = "different"
	if _, err := poster.Apply(conflict); !errors.Is(err, ErrTransitionConflict) {
		t.Fatalf("expected accounting event conflict, got %v", err)
	}
	if len(book.List()) != 1 {
		t.Fatal("rejected transition changed the ledger")
	}
}

func TestReconciliationMatchDifferenceResolutionAndAging(t *testing.T) {
	poster, _ := newPoster(t)
	now := time.Unix(1_750_400_000, 0).UTC()
	intent := paymentIntent(payment.RailBank, payment.StatusProvisional, now)
	provisional := transition(
		intent,
		payment.StatusProcessing,
		payment.StatusProvisional,
		"event-provisional",
		now.Add(time.Minute),
	)
	if _, err := poster.Apply(provisional); err != nil {
		t.Fatalf("post provisional: %v", err)
	}
	finalTransition := transition(
		intent,
		payment.StatusProvisional,
		payment.StatusFinal,
		"event-final",
		now.Add(2*time.Minute),
	)
	if _, err := poster.Apply(finalTransition); err != nil {
		t.Fatalf("post final: %v", err)
	}
	finalIntent := finalTransition.Payment
	reconciler, err := NewReconciler(poster)
	if err != nil {
		t.Fatalf("new reconciler: %v", err)
	}
	statement := []StatementEntry{{
		EntryID:           "statement-entry-001",
		ProviderID:        "provider-local",
		ProviderReference: "provider-reference-001",
		PaymentID:         "payment-001",
		AssetID:           "asset:local:usd",
		Units:             "1000",
		Kind:              StatementSettled,
		OccurredAt:        now.Add(2 * time.Minute),
	}}
	matched, err := reconciler.Run(
		"run-matched",
		"provider-local",
		"asset:local:usd",
		now.Add(3*time.Minute),
		"reconciliation-owner",
		now.Add(24*time.Hour),
		[]payment.Intent{finalIntent},
		statement,
	)
	if err != nil {
		t.Fatalf("matched reconciliation: %v", err)
	}
	if matched.Status != ReconciliationMatched || matched.DifferenceUnits != "0" {
		t.Fatal("equal provider and ledger snapshots did not match")
	}

	statement[0].Units = "900"
	difference, err := reconciler.Run(
		"run-difference",
		"provider-local",
		"asset:local:usd",
		now.Add(4*time.Minute),
		"reconciliation-owner",
		now.Add(24*time.Hour),
		[]payment.Intent{finalIntent},
		statement,
	)
	if err != nil {
		t.Fatalf("difference reconciliation: %v", err)
	}
	if difference.Status != ReconciliationException ||
		difference.DifferenceUnits != "-100" || difference.UnmatchedItems != 1 {
		t.Fatal("provider difference was not kept visible")
	}
	exception, exists := reconciler.Exception("run-difference:difference")
	if !exists || exception.Owner == "" || !exception.ResolutionDeadline.After(exception.DetectedAt) {
		t.Fatal("reconciliation exception is not owned and deadline-bound")
	}
	resolution, err := reconciler.Resolve(
		exception.ExceptionID,
		"resolution-001",
		"resolution-evidence",
		"",
		"reconciliation-owner",
		now.Add(5*time.Minute),
	)
	if err != nil {
		t.Fatalf("record resolution: %v", err)
	}
	if resolution.ExceptionID != exception.ExceptionID {
		t.Fatal("resolution lost exception linkage")
	}
	if _, err := reconciler.Resolve(
		exception.ExceptionID,
		"resolution-conflict",
		"different-evidence",
		"",
		"reconciliation-owner",
		now.Add(6*time.Minute),
	); !errors.Is(err, ErrInvalidResolution) {
		t.Fatalf("expected immutable resolution conflict, got %v", err)
	}
	aging, err := AgingClass(exception.DetectedAt, exception.DetectedAt.Add(9*24*time.Hour))
	if err != nil || aging != "8-30_DAYS" {
		t.Fatalf("unexpected suspense aging: %s, %v", aging, err)
	}
}

func TestReconciliationDoesNotHideOffsettingReferenceMismatch(t *testing.T) {
	poster, _ := newPoster(t)
	now := time.Unix(1_750_450_000, 0).UTC()
	intent := paymentIntent(payment.RailBank, payment.StatusProvisional, now)
	if _, err := poster.Apply(transition(
		intent,
		payment.StatusProcessing,
		payment.StatusProvisional,
		"event-provisional",
		now.Add(time.Minute),
	)); err != nil {
		t.Fatalf("post provisional: %v", err)
	}
	finalTransition := transition(
		intent,
		payment.StatusProvisional,
		payment.StatusFinal,
		"event-final",
		now.Add(2*time.Minute),
	)
	if _, err := poster.Apply(finalTransition); err != nil {
		t.Fatalf("post final: %v", err)
	}
	reconciler, _ := NewReconciler(poster)
	run, err := reconciler.Run(
		"run-offsetting-mismatch",
		"provider-local",
		"asset:local:usd",
		now.Add(3*time.Minute),
		"reconciliation-owner",
		now.Add(24*time.Hour),
		[]payment.Intent{finalTransition.Payment},
		[]StatementEntry{{
			EntryID:           "statement-entry-unknown",
			ProviderID:        "provider-local",
			ProviderReference: "provider-reference-unknown",
			PaymentID:         "payment-unknown",
			AssetID:           "asset:local:usd",
			Units:             "1000",
			Kind:              StatementSettled,
			OccurredAt:        now.Add(2 * time.Minute),
		}},
	)
	if err != nil {
		t.Fatalf("reconcile offsetting mismatch: %v", err)
	}
	if run.DifferenceUnits != "0" || run.UnmatchedItems != 2 ||
		run.Status != ReconciliationException {
		t.Fatal("equal aggregate totals hid mismatched payment references")
	}
}

func TestProvisionalPaymentIsNotExpectedFinalSettlement(t *testing.T) {
	poster, _ := newPoster(t)
	now := time.Unix(1_750_500_000, 0).UTC()
	intent := paymentIntent(payment.RailBank, payment.StatusProvisional, now)
	provisional := transition(
		intent,
		payment.StatusProcessing,
		payment.StatusProvisional,
		"event-provisional",
		now.Add(time.Minute),
	)
	if _, err := poster.Apply(provisional); err != nil {
		t.Fatalf("post provisional: %v", err)
	}
	reconciler, _ := NewReconciler(poster)
	run, err := reconciler.Run(
		"run-provisional",
		"provider-local",
		"asset:local:usd",
		now.Add(2*time.Minute),
		"reconciliation-owner",
		now.Add(24*time.Hour),
		[]payment.Intent{provisional.Payment},
		nil,
	)
	if err != nil {
		t.Fatalf("reconcile provisional: %v", err)
	}
	if run.ExpectedUnits != "0" || run.Status != ReconciliationMatched {
		t.Fatal("provisional evidence was treated as final settlement")
	}
}

func TestOrchestratorAndLedgerPosterIntegrateEndToEnd(t *testing.T) {
	poster, book := newPoster(t)
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate provider key: %v", err)
	}
	orchestrator, err := payment.New([]payment.Provider{{
		ID:               "provider-local",
		Rail:             payment.RailBank,
		PublicKey:        publicKey,
		Active:           true,
		AssetID:          "asset:local:usd",
		SupportsReversal: true,
		Version:          1,
	}}, poster)
	if err != nil {
		t.Fatalf("new orchestrator: %v", err)
	}
	now := time.Unix(1_750_600_000, 0).UTC()
	intent := paymentIntent(payment.RailBank, "", now)
	intent.ProviderReference = ""
	intent.Status = ""
	intent.Version = 0
	intent.CreatedAt = time.Time{}
	intent.UpdatedAt = time.Time{}
	if _, err := orchestrator.CreateIntent(intent, now); err != nil {
		t.Fatalf("create intent: %v", err)
	}
	statuses := []payment.Status{
		payment.StatusProcessing,
		payment.StatusProvisional,
		payment.StatusFinal,
	}
	for index, status := range statuses {
		eventID := "event-" + string(status)
		callback := payment.Callback{
			ProviderID:        "provider-local",
			ProviderEventID:   eventID,
			PaymentID:         "payment-001",
			ProviderReference: "provider-reference-001",
			Status:            status,
			AssetID:           "asset:local:usd",
			Units:             "1000",
			OccurredAt:        now.Add(time.Duration(index+1) * time.Minute),
			ExpiresAt:         now.Add(time.Duration(index+10) * time.Minute),
			EvidenceHash:      "evidence-" + eventID,
		}
		raw, signature := signedCallback(t, privateKey, callback)
		if _, err := orchestrator.IngestCallback(
			callback.ProviderID,
			callback.ProviderEventID,
			raw,
			signature,
			now.Add(time.Duration(index+2)*time.Minute),
		); err != nil {
			t.Fatalf("ingest %s: %v", status, err)
		}
	}
	current, _ := orchestrator.Payment("payment-001")
	if current.Status != payment.StatusFinal || len(book.List()) != 2 {
		t.Fatal("end-to-end provider evidence did not produce one provisional and one final journal")
	}
}
