package settlement

import (
	"crypto/ed25519"
	"encoding/hex"
	"errors"
	"math/big"
	"slices"
	"sync"
	"testing"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/chain-indexer/projectiontest"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

const fixtureFinalityDepth uint64 = 1

func prepareFixture(now time.Time, units string, debt string) PrepareRequest {
	builder := projectiontest.NewBuilder(31337)
	finalityPolicyHash, err := chainprojection.ComputeFinalityPolicyHash(
		31337,
		"0x1111111111111111111111111111111111111111",
		fixtureFinalityDepth,
		builder.PublicKey(),
	)
	if err != nil {
		panic(err)
	}
	request := PrepareRequest{
		PaymentID:                bytes32Uint(1),
		LoanID:                   bytes32Uint(3),
		ProviderID:               "provider-local",
		ProviderReference:        "provider-reference-001",
		PaymentStatus:            payment.StatusFinal,
		PaymentVersion:           4,
		SourceAssetID:            bytes32Uint(4),
		TargetAssetID:            bytes32Uint(5),
		TargetToken:              "0x0000000000000000000000000000000000000100",
		Denomination:             "USD",
		SourcePrecision:          6,
		TargetPrecision:          6,
		SourceUnits:              units,
		TargetUnits:              units,
		ReconciliationID:         bytes32Uint(8),
		DifferenceUnits:          "0",
		FinalityPolicyHash:       finalityPolicyHash,
		ConversionPolicyHash:     bytes32Uint(11),
		PolicySetHash:            bytes32Uint(0x33),
		EligibilityEvidenceHash:  bytes32Uint(13),
		OriginalJournalIDs:       []string{"provider-final", "unallocated-payment"},
		ExpectedDebtUnits:        debt,
		ExpectedStateNonce:       7,
		ChainID:                  31337,
		GatewayAddress:           "0x1111111111111111111111111111111111111111",
		FinalizerAddress:         "0x2222222222222222222222222222222222222222",
		ProviderIDHash:           bytes32Uint(6),
		ProviderReferenceHash:    bytes32Uint(7),
		ReconciliationCommitment: bytes32Uint(9),
		OriginalJournalSetHash:   bytes32Uint(10),
		JournalRef:               bytes32Uint(14),
		AttesterAddress:          "0x4444444444444444444444444444444444444444",
		FinalizedAt:              now,
		ReversalDeadline:         now.Add(24 * time.Hour),
		PreparedAt:               now.Add(25 * time.Hour),
		CorrelationID:            "correlation-001",
	}
	request.AllocationID = CalculateAllocationID(request)
	return request
}

func submitFixture(t *testing.T, coordinator *Coordinator, plan Plan) Plan {
	t.Helper()
	_, _, transactionHash := projectiontest.NewBuilder(plan.ChainID).BlockWithReceipt(
		1,
		bytes32Uint(0),
		plan.PreparedAt,
		100,
		true,
		nil,
	)
	submitted, err := coordinator.Submit(SubmissionRequest{
		PaymentID:         plan.PaymentID,
		AllocationID:      plan.AllocationID,
		InstructionDigest: plan.InstructionDigest,
		ExpectedVersion:   plan.Version,
		ChainID:           plan.ChainID,
		Gateway:           plan.GatewayAddress,
		Sender:            plan.FinalizerAddress,
		SenderNonce:       9,
		TransactionHash:   transactionHash,
		CalldataHash:      "calldata-001",
		SubmittedAt:       plan.PreparedAt.Add(time.Minute),
	})
	if err != nil {
		t.Fatalf("submit: %v", err)
	}
	return submitted
}

func eventFixture(t *testing.T, plan Plan) chainprojection.RawLog {
	t.Helper()
	data := make([]byte, 0, 29*32)
	for _, word := range [][]byte{
		hexWord(t, plan.InstructionDigest),
		hexWord(t, plan.PolicySetHash),
		addressWord(t, "0x5555555555555555555555555555555555555555"),
		addressWord(t, plan.FinalizerAddress),
		addressWord(t, plan.AttesterAddress),
		hexWord(t, plan.SourceAssetID),
		hexWord(t, plan.TargetAssetID),
		addressWord(t, plan.TargetToken),
		uintWord(t, plan.SourceUnits),
		uintWord(t, plan.TargetUnits),
		hexWord(t, plan.Instruction.ProviderIDHash),
		hexWord(t, plan.Instruction.ProviderReferenceHash),
		hexWord(t, plan.ReconciliationID),
		hexWord(t, plan.Instruction.ReconciliationCommitment),
		hexWord(t, plan.Instruction.OriginalJournalSetHash),
		hexWord(t, plan.ConversionPolicyHash),
		hexWord(t, plan.FinalityPolicyHash),
		hexWord(t, plan.Instruction.EvidenceHash),
		hexWord(t, plan.Instruction.JournalRef),
		uintWord(t, new(big.Int).SetUint64(plan.Instruction.FinalizedAt).String()),
		uintWord(t, new(big.Int).SetUint64(plan.Instruction.ReversalDeadline).String()),
		uintWord(t, plan.DebtBeforeUnits),
		uintWord(t, plan.PrincipalUnits),
		uintWord(t, plan.RefundableExcessUnits),
		uintWord(t, plan.DebtAfterUnits),
		uintWord(t, new(big.Int).SetUint64(plan.ExpectedStateNonce).String()),
		uintWord(t, new(big.Int).SetUint64(plan.ExpectedStateNonce+2).String()),
		addressWord(t, "0x6666666666666666666666666666666666666666"),
		addressWord(t, "0x7777777777777777777777777777777777777777"),
	} {
		data = append(data, word...)
	}
	raw := chainprojection.RawLog{
		ChainID:         plan.ChainID,
		ContractAddress: plan.GatewayAddress,
		Topics: []string{
			chainprojection.CanonicalSettlementTopic(),
			plan.PaymentID,
			plan.AllocationID,
			plan.LoanID,
		},
		Data:            data,
		TransactionHash: plan.Submission.TransactionHash,
		LogIndex:        0,
		BlockNumber:     2,
	}
	builder := projectiontest.NewBuilder(plan.ChainID)
	_, parentHash := builder.EmptyBlock(
		1,
		bytes32Uint(0),
		time.Unix(1_900_100_000, 0).UTC(),
	)
	_, blockHash, transactionHash := builder.BlockWithReceipt(
		2,
		parentHash,
		time.Unix(1_900_100_000, 0).UTC().Add(time.Minute),
		100,
		true,
		[]projectiontest.Log{{
			Address: raw.ContractAddress,
			Topics:  raw.Topics,
			Data:    raw.Data,
		}},
	)
	if transactionHash != raw.TransactionHash {
		t.Fatalf("fixture transaction hash does not match submitted hash")
	}
	raw.BlockHash = blockHash
	return raw
}

func finalProjection(
	t *testing.T,
	raw chainprojection.RawLog,
) chainprojection.VerifiedGatewayProjection {
	t.Helper()
	indexer, event := projectionIndexer(t, raw, true)
	projection, exists := indexer.FinalizedGatewayProjection(event.PaymentID)
	if !exists {
		t.Fatal("finalized gateway projection unavailable")
	}
	return projection
}

func projectionIndexer(
	t *testing.T,
	raw chainprojection.RawLog,
	advanceFinality bool,
) (*chainprojection.Indexer, chainprojection.Event) {
	t.Helper()
	event, err := chainprojection.DecodeCanonicalSettlementLog(raw)
	if err != nil {
		t.Fatal(err)
	}
	builder := projectiontest.NewBuilder(raw.ChainID)
	indexer, err := chainprojection.NewGateway(
		raw.ChainID,
		raw.ContractAddress,
		fixtureFinalityDepth,
		builder.PublicKey(),
	)
	if err != nil {
		t.Fatal(err)
	}
	observedAt := time.Unix(1_900_100_000, 0).UTC()
	first, firstHash := builder.EmptyBlock(1, bytes32Uint(0), observedAt)
	if err := indexer.IngestAuthenticated(first); err != nil {
		t.Fatal(err)
	}
	second, secondHash, transactionHash := builder.BlockWithReceipt(
		2,
		firstHash,
		observedAt.Add(time.Minute),
		100,
		true,
		[]projectiontest.Log{{
			Address: raw.ContractAddress,
			Topics:  raw.Topics,
			Data:    raw.Data,
		}},
	)
	if transactionHash != raw.TransactionHash {
		t.Fatal("authenticated fixture transaction mismatch")
	}
	if err := indexer.IngestAuthenticated(second); err != nil {
		t.Fatal(err)
	}
	if _, exists := indexer.FinalizedGatewayProjection(event.PaymentID); exists {
		t.Fatal("provisional gateway event was promoted before confirmation depth")
	}
	if advanceFinality {
		third, _ := builder.EmptyBlock(
			3,
			secondHash,
			observedAt.Add(2*time.Minute),
		)
		if err := indexer.IngestAuthenticated(third); err != nil {
			t.Fatal(err)
		}
	}
	return indexer, event
}

func reorgEnvelope(
	t *testing.T,
	raw chainprojection.RawLog,
	deep bool,
) chainprojection.VerifiedReorgEnvelope {
	t.Helper()
	indexer, event := projectionIndexer(t, raw, deep)
	builder := projectiontest.NewBuilder(raw.ChainID)
	_, firstHash := builder.EmptyBlock(
		1,
		bytes32Uint(0),
		time.Unix(1_900_100_000, 0).UTC(),
	)
	replacement, _ := builder.EmptyBlock(
		2,
		firstHash,
		time.Unix(1_900_100_000, 0).UTC().Add(3*time.Minute),
	)
	err := indexer.IngestAuthenticated(replacement)
	if err != nil {
		t.Fatal(err)
	}
	envelope, exists := indexer.ReorgEnvelope(event.ID)
	if !exists {
		t.Fatal("reorg envelope unavailable")
	}
	return envelope
}

func hexWord(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(value[2:])
	if err != nil || len(decoded) != 32 {
		t.Fatalf("invalid bytes32 %q", value)
	}
	return decoded
}

func addressWord(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(value[2:])
	if err != nil || len(decoded) != 20 {
		t.Fatalf("invalid address %q", value)
	}
	return append(make([]byte, 12), decoded...)
}

func uintWord(t *testing.T, value string) []byte {
	t.Helper()
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() < 0 || number.BitLen() > 256 {
		t.Fatalf("invalid uint256 %q", value)
	}
	return number.FillBytes(make([]byte, 32))
}

func TestPreparePlansPrincipalAndExcessWithoutPosting(t *testing.T) {
	now := time.Unix(1_770_000_000, 0).UTC()
	coordinator, err := NewInMemory(allocationmode.NewInMemory())
	if err != nil {
		t.Fatal(err)
	}
	plan, err := coordinator.Prepare(prepareFixture(now, "1250", "1000"))
	if err != nil {
		t.Fatalf("prepare: %v", err)
	}
	replay, err := coordinator.Prepare(prepareFixture(now, "1250", "1000"))
	if err != nil {
		t.Fatalf("prepare replay: %v", err)
	}
	if plan.PrincipalUnits != "1000" || plan.RefundableExcessUnits != "250" ||
		plan.DebtAfterUnits != "0" || plan.State != StatePrepared ||
		!replay.Replayed || replay.InstructionDigest != plan.InstructionDigest {
		t.Fatalf("non-posting waterfall is inconsistent: %#v %#v", plan, replay)
	}
}

func TestPrepareRequiresMatureMatchedOneToOneEvidence(t *testing.T) {
	now := time.Unix(1_770_000_000, 0).UTC()
	cases := []func(*PrepareRequest){
		func(value *PrepareRequest) { value.PreparedAt = value.ReversalDeadline.Add(-time.Second) },
		func(value *PrepareRequest) { value.PaymentStatus = payment.StatusProvisional },
		func(value *PrepareRequest) { value.DifferenceUnits = "1" },
		func(value *PrepareRequest) { value.UnmatchedItems = 1 },
		func(value *PrepareRequest) { value.TargetUnits = "999" },
		func(value *PrepareRequest) { value.TargetAssetID = value.SourceAssetID },
		func(value *PrepareRequest) { value.TargetPrecision++ },
	}
	for index, mutate := range cases {
		coordinator, _ := NewInMemory(allocationmode.NewInMemory())
		request := prepareFixture(now, "1000", "1000")
		mutate(&request)
		request.AllocationID = CalculateAllocationID(request)
		if _, err := coordinator.Prepare(request); !errors.Is(err, ErrInvalidPlan) {
			t.Fatalf("case %d expected invalid plan, got %v", index, err)
		}
	}
}

func TestSubmitConfirmReplayAndLedgerBoundary(t *testing.T) {
	now := time.Unix(1_770_000_000, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, _ := NewInMemory(modes)
	plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, plan)
	event := eventFixture(t, submitted)
	verified := finalProjection(t, event)
	confirmation, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        verified,
	})
	if err != nil {
		t.Fatalf("confirm: %v", err)
	}
	replayed, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        verified,
	})
	if err != nil {
		t.Fatalf("confirm replay: %v", err)
	}
	alteredEvent := event
	alteredEvent.Data = append([]byte(nil), event.Data...)
	copy(alteredEvent.Data[:32], hexWord(t, bytes32Uint(999)))
	if _, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        finalProjection(t, alteredEvent),
	}); !errors.Is(err, ErrPlanConflict) {
		t.Fatalf("altered event digest accepted as replay: %v", err)
	}
	claim, _ := modes.Lookup(plan.PaymentID)
	projection := confirmation.AccountingProjection()
	if projection.SourceAssetID == projection.TargetAssetID ||
		projection.PrincipalUnits != "400" ||
		projection.RefundableExcessUnits != "0" ||
		projection.EventID != verified.Settlement().EventID ||
		len(projection.OriginalJournalIDs) != 2 ||
		claim.State != allocationmode.CanonicalConfirmed || !replayed.Replayed() {
		t.Fatalf("confirmation lost ledger or canonical evidence: %#v", confirmation)
	}
}

func TestPreFinalityReorgRetainsClaimAndAllowsExactRetry(t *testing.T) {
	now := time.Unix(1_770_000_000, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, _ := NewInMemory(modes)
	request := prepareFixture(now, "400", "1000")
	plan, _ := coordinator.Prepare(request)
	submitted := submitFixture(t, coordinator, plan)
	envelope := reorgEnvelope(t, eventFixture(t, submitted), false)
	authority, err := coordinator.RecordReorg(submitted.Version, envelope)
	evidence := authority.Evidence()
	if err != nil || evidence.Deep || evidence.CompensationRequired {
		t.Fatalf("pre-finality reorg: %#v %v", evidence, err)
	}
	retained, exists := modes.Lookup(plan.PaymentID)
	if !exists || retained.State != allocationmode.CanonicalFailed {
		t.Fatalf("pre-finality reorg lost permanent canonical mode: %#v", retained)
	}
	failed, _ := coordinator.Plan(plan.PaymentID)
	retried, err := coordinator.Retry(RetryRequest{
		PaymentID:         failed.PaymentID,
		AllocationID:      failed.AllocationID,
		InstructionDigest: failed.InstructionDigest,
		ExpectedVersion:   failed.Version,
		EvidenceHash:      "retry-evidence",
		RetriedAt:         submitted.Submission.SubmittedAt.Add(2 * time.Minute),
	})
	if err != nil || retried.State != StatePrepared || retried.Version != 4 {
		t.Fatalf("retry failed: %#v %v", retried, err)
	}
}

func TestPreFinalityReorgCannotReleaseSubmittedReversal(t *testing.T) {
	now := time.Unix(1_770_000_000, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, _ := NewInMemory(modes)
	plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, plan)
	reversal := reversalFixture(
		submitted,
		"quarantine-submitted",
		"provider-reversal-submitted",
		submitted.Submission.SubmittedAt.Add(time.Minute),
	)
	claim, disposition, err := coordinator.HandleProviderReversal(
		reversal,
		func() error { return nil },
	)
	if err != nil || disposition != allocationmode.ReversalQuarantined ||
		claim.State != allocationmode.CanonicalQuarantined {
		t.Fatalf("submitted reversal was not quarantined: %#v %s", claim, disposition)
	}
	envelope := reorgEnvelope(t, eventFixture(t, submitted), false)
	quarantinedBefore, _ := coordinator.Plan(plan.PaymentID)
	if _, err := coordinator.RecordReorg(quarantinedBefore.Version, envelope); err != nil {
		t.Fatalf("record reorg while reversal is pending: %v", err)
	}
	quarantined, _ := coordinator.Plan(plan.PaymentID)
	retained, exists := modes.Lookup(plan.PaymentID)
	if quarantined.State != StateQuarantined ||
		quarantined.FailureReason != "REORG_BEFORE_FINALITY_REVERSAL_PENDING" ||
		!exists || retained.State != allocationmode.CanonicalQuarantined {
		t.Fatalf("reorg released the pending reversal: %#v %#v", quarantined, retained)
	}
	if _, err := coordinator.Retry(RetryRequest{
		PaymentID:         quarantined.PaymentID,
		AllocationID:      quarantined.AllocationID,
		InstructionDigest: quarantined.InstructionDigest,
		ExpectedVersion:   quarantined.Version,
		EvidenceHash:      "unsafe-retry",
		RetriedAt:         submitted.Submission.SubmittedAt.Add(2 * time.Minute),
	}); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("pending reversal accepted canonical retry: %v", err)
	}
	reversal.ResolutionID = "resolution-submitted"
	reversal.AllocationID = plan.AllocationID
	reversal.InstructionDigest = plan.InstructionDigest
	reversal.FailureProof = verifiedFailureFixture(t, submitted)
	reversal.ResolutionEvidence = "resolution-evidence"
	reversal.ResolvedBy = "payment-operator"
	reversal.ReceivedAt = submitted.Submission.SubmittedAt.Add(4 * time.Minute)
	if _, err := coordinator.ResolveProviderReversal(
		reversal,
		func() ([]string, error) {
			return []string{"final-reversal", "provisional-reversal"}, nil
		},
	); err != nil {
		t.Fatalf("resolve Phase 7A reversal: %v", err)
	}
	reversed, _ := coordinator.Plan(plan.PaymentID)
	if reversed.State != StateFailed ||
		reversed.FailureReason != "PROVIDER_REVERSAL_RESOLVED" ||
		!modes.IsReversed(plan.PaymentID) {
		t.Fatalf("resolved reversal did not permanently cancel the plan: %#v", reversed)
	}
	if _, err := coordinator.Retry(RetryRequest{
		PaymentID:         reversed.PaymentID,
		AllocationID:      reversed.AllocationID,
		InstructionDigest: reversed.InstructionDigest,
		ExpectedVersion:   reversed.Version,
		EvidenceHash:      "stale-retry",
		RetriedAt:         submitted.Submission.SubmittedAt.Add(3 * time.Minute),
	}); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("reversed payment reacquired canonical mode: %v", err)
	}
}

func TestPreparedReversalQuarantinesPlanAndPreventsRetry(t *testing.T) {
	now := time.Unix(1_770_000_000, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, _ := NewInMemory(modes)
	request := prepareFixture(now, "400", "1000")
	plan, err := coordinator.Prepare(request)
	if err != nil {
		t.Fatal(err)
	}
	_, disposition, err := coordinator.HandleProviderReversal(
		reversalFixture(
			plan,
			"quarantine-prepared",
			"provider-reversal-prepared",
			now.Add(time.Minute),
		),
		func() error { return nil },
	)
	if err != nil || disposition != allocationmode.ReversalQuarantined {
		t.Fatalf("prepared reversal disposition: %s", disposition)
	}
	cancelled, exists := coordinator.Plan(plan.PaymentID)
	if !exists || cancelled.State != StateQuarantined ||
		cancelled.FailureReason != "PROVIDER_REVERSAL_PENDING" ||
		cancelled.Version != 2 {
		t.Fatalf("prepared reversal did not durably quarantine plan: %#v", cancelled)
	}
	if replayed, err := coordinator.Prepare(request); err != nil ||
		replayed.State != StateQuarantined {
		t.Fatalf("quarantined prepare replay was not stable: %#v %v", replayed, err)
	}
	if _, err := coordinator.Submit(SubmissionRequest{
		PaymentID:         cancelled.PaymentID,
		AllocationID:      cancelled.AllocationID,
		InstructionDigest: cancelled.InstructionDigest,
		ExpectedVersion:   cancelled.Version,
		ChainID:           31337,
		Gateway:           cancelled.GatewayAddress,
		Sender:            cancelled.FinalizerAddress,
		TransactionHash:   "stale-transaction",
		CalldataHash:      "stale-calldata",
		SubmittedAt:       cancelled.PreparedAt.Add(time.Minute),
	}); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("cancelled plan accepted stale submit: %v", err)
	}
	_, err = coordinator.Retry(RetryRequest{
		PaymentID:         cancelled.PaymentID,
		AllocationID:      cancelled.AllocationID,
		InstructionDigest: cancelled.InstructionDigest,
		ExpectedVersion:   cancelled.Version,
		EvidenceHash:      "explicit-retry-evidence",
		RetriedAt:         cancelled.PreparedAt.Add(time.Minute),
	})
	if !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("reversed payment reacquired canonical mode: %v", err)
	}
}

func TestSubmittedReversalResolutionRequiresMatchingOpaqueFailure(
	t *testing.T,
) {
	now := time.Unix(1_770_050_000, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, err := NewInMemory(modes)
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, prepared)
	reversal := reversalFixture(
		submitted,
		"quarantine-proof",
		"provider-reversal-proof",
		submitted.Submission.SubmittedAt.Add(time.Minute),
	)
	if _, disposition, err := coordinator.HandleProviderReversal(
		reversal,
		func() error { return nil },
	); err != nil || disposition != allocationmode.ReversalQuarantined {
		t.Fatalf("quarantine submitted reversal: %s %v", disposition, err)
	}
	reversal.ResolutionID = "resolution-proof"
	reversal.AllocationID = submitted.AllocationID
	reversal.InstructionDigest = submitted.InstructionDigest
	reversal.ResolutionEvidence = "resolution-proof-evidence"
	reversal.ResolvedBy = "payment-operator"
	reversal.ReceivedAt = submitted.Submission.SubmittedAt.Add(5 * time.Minute)
	fallback := func() ([]string, error) {
		return []string{"final-reversal", "provisional-reversal"}, nil
	}
	if _, err := coordinator.ResolveProviderReversal(
		reversal,
		fallback,
	); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("zero submitted failure proof was accepted: %v", err)
	}

	otherSubmission := submitted
	_, _, otherTransactionHash := projectiontest.NewBuilder(
		submitted.Submission.ChainID,
	).BlockWithReceipt(
		1,
		bytes32Uint(0),
		submitted.Submission.SubmittedAt,
		991,
		false,
		nil,
	)
	otherSubmission.Submission.TransactionHash = otherTransactionHash
	reversal.FailureProof = verifiedFailureFixtureFor(t, otherSubmission, 991)
	if _, err := coordinator.ResolveProviderReversal(
		reversal,
		fallback,
	); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("mismatched opaque failure proof was accepted: %v", err)
	}
	retained, _ := coordinator.Plan(submitted.PaymentID)
	if retained.State != StateQuarantined ||
		modes.IsReversed(submitted.PaymentID) {
		t.Fatalf("rejected proof changed durable state: %#v", retained)
	}

	reversal.FailureProof = verifiedFailureFixture(t, submitted)
	result, err := coordinator.ResolveProviderReversal(reversal, fallback)
	if err != nil || len(result.JournalIDs) != 2 ||
		result.FailureEvidenceHash !=
			reversal.FailureProof.Evidence().EvidenceHash {
		t.Fatalf("matching opaque failure proof was rejected: %#v %v", result, err)
	}
	replayed, err := coordinator.ResolveProviderReversal(
		reversal,
		func() ([]string, error) {
			return nil, errors.New("exact replay invoked accounting")
		},
	)
	if err != nil ||
		!slices.Equal(replayed.JournalIDs, result.JournalIDs) ||
		replayed.FailureEvidenceHash != result.FailureEvidenceHash {
		t.Fatalf("exact resolution replay changed its result: %#v %v", replayed, err)
	}
	altered := reversal
	altered.ResolutionEvidence = "altered-resolution-evidence"
	if _, err := coordinator.ResolveProviderReversal(
		altered,
		fallback,
	); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("altered resolution replay was accepted: %v", err)
	}
}

func TestCanonicalSuccessAndSubmittedReversalRaceEndsInIncident(t *testing.T) {
	now := time.Unix(1_770_075_000, 0).UTC()
	for attempt := 0; attempt < 32; attempt++ {
		modes := allocationmode.NewInMemory()
		coordinator, err := NewInMemory(modes)
		if err != nil {
			t.Fatal(err)
		}
		prepared, err := coordinator.Prepare(
			prepareFixture(now.Add(time.Duration(attempt)*time.Second), "400", "1000"),
		)
		if err != nil {
			t.Fatal(err)
		}
		submitted := submitFixture(t, coordinator, prepared)
		projection := finalProjection(t, eventFixture(t, submitted))
		reversal := reversalFixture(
			submitted,
			"quarantine-race",
			"provider-reversal-race",
			submitted.Submission.SubmittedAt.Add(time.Minute),
		)
		var wait sync.WaitGroup
		wait.Add(2)
		start := make(chan struct{})
		confirmErrors := make(chan error, 1)
		reversalErrors := make(chan error, 1)
		committed := false
		go func() {
			defer wait.Done()
			<-start
			_, confirmErr := coordinator.Confirm(ConfirmationRequest{
				PaymentID:         submitted.PaymentID,
				AllocationID:      submitted.AllocationID,
				InstructionDigest: submitted.InstructionDigest,
				ExpectedVersion:   submitted.Version,
				Projection:        projection,
			})
			confirmErrors <- confirmErr
		}()
		go func() {
			defer wait.Done()
			<-start
			_, _, reversalErr := coordinator.HandleProviderReversal(
				reversal,
				func() error {
					committed = true
					return nil
				},
			)
			reversalErrors <- reversalErr
		}()
		close(start)
		wait.Wait()
		if err := <-confirmErrors; err != nil {
			t.Fatalf("attempt %d confirmation lost race: %v", attempt, err)
		}
		if err := <-reversalErrors; err != nil {
			t.Fatalf("attempt %d reversal lost race unsafely: %v", attempt, err)
		}
		current, _ := coordinator.Plan(submitted.PaymentID)
		claim, _ := modes.Lookup(submitted.PaymentID)
		if current.State != StateIncident ||
			claim.State != allocationmode.CanonicalIncident ||
			len(coordinator.PendingProviderReversals()) != 0 ||
			committed {
			t.Fatalf(
				"attempt %d race escaped incident containment: %#v %#v",
				attempt,
				current,
				claim,
			)
		}
	}
}

func TestCoordinatorRejectsEvidenceFromAlternateHeaderAuthority(t *testing.T) {
	now := time.Unix(1_770_080_000, 0).UTC()
	trustedRequest := prepareFixture(now, "400", "1000")
	alternateSeed := make([]byte, ed25519.SeedSize)
	alternateSeed[0] = 0xa7
	alternatePublic := ed25519.NewKeyFromSeed(alternateSeed).
		Public().(ed25519.PublicKey)
	alternatePolicy, err := chainprojection.ComputeFinalityPolicyHash(
		trustedRequest.ChainID,
		trustedRequest.GatewayAddress,
		fixtureFinalityDepth,
		alternatePublic,
	)
	if err != nil {
		t.Fatal(err)
	}
	if alternatePolicy == trustedRequest.FinalityPolicyHash {
		t.Fatal("alternate authority produced the trusted policy hash")
	}
	alternateRequest := trustedRequest
	alternateRequest.FinalityPolicyHash = alternatePolicy
	alternateRequest.AllocationID = CalculateAllocationID(alternateRequest)

	t.Run("confirm", func(t *testing.T) {
		coordinator, _ := NewInMemory(allocationmode.NewInMemory())
		prepared, err := coordinator.Prepare(alternateRequest)
		if err != nil {
			t.Fatal(err)
		}
		submitted := submitFixture(t, coordinator, prepared)
		raw := eventFixture(t, submitted)
		raw.Data = append([]byte(nil), raw.Data...)
		copy(
			raw.Data[16*32:17*32],
			hexWord(t, trustedRequest.FinalityPolicyHash),
		)
		projection := finalProjection(t, raw)
		if projection.Proof().FinalityPolicyHash == submitted.FinalityPolicyHash {
			t.Fatal("fixture did not create an alternate-authority proof")
		}
		if _, err := coordinator.Confirm(ConfirmationRequest{
			PaymentID:         submitted.PaymentID,
			AllocationID:      submitted.AllocationID,
			InstructionDigest: submitted.InstructionDigest,
			ExpectedVersion:   submitted.Version,
			Projection:        projection,
		}); !errors.Is(err, ErrInvalidEvent) {
			t.Fatalf("alternate-authority confirmation was accepted: %v", err)
		}
	})

	t.Run("failure", func(t *testing.T) {
		coordinator, _ := NewInMemory(allocationmode.NewInMemory())
		prepared, err := coordinator.Prepare(alternateRequest)
		if err != nil {
			t.Fatal(err)
		}
		submitted := submitFixture(t, coordinator, prepared)
		proof := verifiedFailureFixture(t, submitted)
		if proof.Evidence().FinalityPolicyHash == submitted.FinalityPolicyHash {
			t.Fatal("fixture did not create an alternate-authority proof")
		}
		if _, err := coordinator.Fail(FailureRequest{
			PaymentID:         submitted.PaymentID,
			AllocationID:      submitted.AllocationID,
			InstructionDigest: submitted.InstructionDigest,
			ExpectedVersion:   submitted.Version,
			Proof:             proof,
		}); !errors.Is(err, ErrInvalidTransition) {
			t.Fatalf("alternate-authority failure was accepted: %v", err)
		}
	})

	t.Run("submitted reversal", func(t *testing.T) {
		modes := allocationmode.NewInMemory()
		coordinator, _ := NewInMemory(modes)
		prepared, err := coordinator.Prepare(alternateRequest)
		if err != nil {
			t.Fatal(err)
		}
		submitted := submitFixture(t, coordinator, prepared)
		reversal := reversalFixture(
			submitted,
			"quarantine-alternate-authority",
			"provider-reversal-alternate-authority",
			submitted.Submission.SubmittedAt.Add(time.Minute),
		)
		if _, disposition, err := coordinator.HandleProviderReversal(
			reversal,
			func() error { return nil },
		); err != nil || disposition != allocationmode.ReversalQuarantined {
			t.Fatalf("quarantine reversal: %s %v", disposition, err)
		}
		reversal.ResolutionID = "resolution-alternate-authority"
		reversal.AllocationID = submitted.AllocationID
		reversal.InstructionDigest = submitted.InstructionDigest
		reversal.ResolutionEvidence = "resolution-alternate-authority-evidence"
		reversal.ResolvedBy = "payment-operator"
		reversal.ReceivedAt =
			submitted.Submission.SubmittedAt.Add(5 * time.Minute)
		reversal.FailureProof = verifiedFailureFixture(t, submitted)
		if reversal.FailureProof.Evidence().FinalityPolicyHash ==
			submitted.FinalityPolicyHash {
			t.Fatal("fixture did not create an alternate-authority proof")
		}
		if _, err := coordinator.ResolveProviderReversal(
			reversal,
			func() ([]string, error) {
				return []string{"unexpected-accounting"}, nil
			},
		); !errors.Is(err, ErrInvalidTransition) {
			t.Fatalf("alternate-authority reversal proof was accepted: %v", err)
		}
		current, _ := coordinator.Plan(submitted.PaymentID)
		if current.State != StateQuarantined ||
			modes.IsReversed(submitted.PaymentID) {
			t.Fatalf("rejected alternate proof changed state: %#v", current)
		}
	})
}

func TestCoordinatorRejectsReorgWithMismatchedFinalityPolicy(
	t *testing.T,
) {
	now := time.Unix(1_770_085_000, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, err := NewInMemory(modes)
	if err != nil {
		t.Fatal(err)
	}
	plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, plan)

	var alternateSeed [ed25519.SeedSize]byte
	alternateSeed[0] = 0xa8
	builder := projectiontest.NewBuilderWithSeed(submitted.ChainID, alternateSeed)
	alternatePolicy, err := chainprojection.ComputeFinalityPolicyHash(
		submitted.ChainID,
		submitted.GatewayAddress,
		fixtureFinalityDepth,
		builder.PublicKey(),
	)
	if err != nil {
		t.Fatal(err)
	}
	raw := eventFixture(t, submitted)
	raw.Data = append([]byte(nil), raw.Data...)
	copy(raw.Data[16*32:17*32], hexWord(t, alternatePolicy))
	indexer, err := chainprojection.NewGateway(
		submitted.ChainID,
		submitted.GatewayAddress,
		fixtureFinalityDepth,
		builder.PublicKey(),
	)
	if err != nil {
		t.Fatal(err)
	}
	observedAt := time.Unix(1_900_200_000, 0).UTC()
	first, firstHash := builder.EmptyBlock(1, bytes32Uint(0), observedAt)
	if err := indexer.IngestAuthenticated(first); err != nil {
		t.Fatal(err)
	}
	second, _, transactionHash := builder.BlockWithReceipt(
		2,
		firstHash,
		observedAt.Add(time.Minute),
		100,
		true,
		[]projectiontest.Log{{
			Address: raw.ContractAddress,
			Topics:  raw.Topics,
			Data:    raw.Data,
		}},
	)
	if transactionHash != submitted.Submission.TransactionHash {
		t.Fatal("alternate authority fixture changed the submitted transaction hash")
	}
	if err := indexer.IngestAuthenticated(second); err != nil {
		t.Fatal(err)
	}
	indexed, exists := indexer.Snapshot().
		CanonicalSettlements[submitted.PaymentID]
	if !exists {
		t.Fatal("alternate authority gateway event was not indexed")
	}
	replacement, _ := builder.EmptyBlock(
		2,
		firstHash,
		observedAt.Add(2*time.Minute),
	)
	if err := indexer.IngestAuthenticated(replacement); err != nil {
		t.Fatal(err)
	}
	envelope, exists := indexer.ReorgEnvelope(indexed.EventID)
	if !exists ||
		envelope.Evidence().FinalityPolicyHash == submitted.FinalityPolicyHash {
		t.Fatal("mismatched finality-policy reorg fixture was not created")
	}
	if _, err := coordinator.RecordReorg(
		submitted.Version,
		envelope,
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("mismatched finality-policy reorg was accepted: %v", err)
	}
	current, _ := coordinator.Plan(submitted.PaymentID)
	claim, _ := modes.Lookup(submitted.PaymentID)
	if current.State != StateSubmitted ||
		claim.State != allocationmode.CanonicalSubmitted ||
		len(coordinator.Reorgs()) != 0 {
		t.Fatalf("rejected mismatched reorg changed state: %#v %#v", current, claim)
	}
}

func TestCoordinatorRejectsReorgWithMismatchedEventEvidence(t *testing.T) {
	now := time.Unix(1_770_085_500, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, err := NewInMemory(modes)
	if err != nil {
		t.Fatal(err)
	}
	plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, plan)
	raw := eventFixture(t, submitted)
	raw.Data = append([]byte(nil), raw.Data...)
	copy(raw.Data[17*32:18*32], hexWord(t, bytes32Uint(999)))
	builder := projectiontest.NewBuilder(submitted.ChainID)
	_, parentHash := builder.EmptyBlock(
		1,
		bytes32Uint(0),
		time.Unix(1_900_100_000, 0).UTC(),
	)
	_, raw.BlockHash, _ = builder.BlockWithReceipt(
		2,
		parentHash,
		time.Unix(1_900_100_000, 0).UTC().Add(time.Minute),
		100,
		true,
		[]projectiontest.Log{{
			Address: raw.ContractAddress,
			Topics:  raw.Topics,
			Data:    raw.Data,
		}},
	)
	envelope := reorgEnvelope(t, raw, false)
	if envelope.Evidence().OrphanedEventEvidenceHash ==
		submitted.EligibilityEvidenceHash {
		t.Fatal("fixture did not change orphaned event evidence")
	}
	if _, err := coordinator.RecordReorg(
		submitted.Version,
		envelope,
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("mismatched event-evidence reorg was accepted: %v", err)
	}
	current, _ := coordinator.Plan(submitted.PaymentID)
	claim, _ := modes.Lookup(submitted.PaymentID)
	if current.State != StateSubmitted ||
		claim.State != allocationmode.CanonicalSubmitted ||
		len(coordinator.Reorgs()) != 0 {
		t.Fatalf("rejected mismatched reorg changed state: %#v %#v", current, claim)
	}
}

func TestCoordinatorRejectsObservationBeforeSubmission(t *testing.T) {
	now := time.Unix(1_900_200_000, 0).UTC()
	coordinator, err := NewInMemory(allocationmode.NewInMemory())
	if err != nil {
		t.Fatal(err)
	}
	plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, plan)
	event := eventFixture(t, submitted)
	if projection := finalProjection(t, event); !projection.Proof().ObservedAt.Before(
		submitted.Submission.SubmittedAt,
	) {
		t.Fatal("fixture does not place finality observation before submission")
	} else if _, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        projection,
	}); !errors.Is(err, ErrInvalidEvent) {
		t.Fatalf("backdated confirmation was accepted: %v", err)
	}
	envelope := reorgEnvelope(t, event, false)
	if !envelope.Evidence().DetectedAt.Before(submitted.Submission.SubmittedAt) {
		t.Fatal("fixture does not place reorg observation before submission")
	}
	if _, err := coordinator.RecordReorg(
		submitted.Version,
		envelope,
	); !errors.Is(err, ErrInvalidReorg) {
		t.Fatalf("backdated reorg was accepted: %v", err)
	}
}

func TestPrepareRejectsZeroAddresses(t *testing.T) {
	now := time.Unix(1_770_086_000, 0).UTC()
	for _, field := range []string{
		"target-token",
		"gateway",
		"finalizer",
		"attester",
	} {
		t.Run(field, func(t *testing.T) {
			request := prepareFixture(now, "400", "1000")
			switch field {
			case "target-token":
				request.TargetToken = "0x0000000000000000000000000000000000000000"
			case "gateway":
				request.GatewayAddress = "0x0000000000000000000000000000000000000000"
			case "finalizer":
				request.FinalizerAddress = "0x0000000000000000000000000000000000000000"
			case "attester":
				request.AttesterAddress = "0x0000000000000000000000000000000000000000"
			}
			coordinator, err := NewInMemory(allocationmode.NewInMemory())
			if err != nil {
				t.Fatal(err)
			}
			if _, err := coordinator.Prepare(request); !errors.Is(err, ErrInvalidPlan) {
				t.Fatalf("zero %s address was accepted: %v", field, err)
			}
		})
	}
}

func TestDeepReorgAfterConfirmationCreatesCompensatingIncident(t *testing.T) {
	now := time.Unix(1_770_000_000, 0).UTC()
	modes := allocationmode.NewInMemory()
	coordinator, _ := NewInMemory(modes)
	plan, _ := coordinator.Prepare(prepareFixture(now, "1000", "1000"))
	submitted := submitFixture(t, coordinator, plan)
	event := eventFixture(t, submitted)
	verified := finalProjection(t, event)
	if _, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        verified,
	}); err != nil {
		t.Fatal(err)
	}
	current, _ := coordinator.Plan(plan.PaymentID)
	envelope := reorgEnvelope(t, event, true)
	authority, err := coordinator.RecordReorg(current.Version, envelope)
	reorg := authority.Evidence()
	if err != nil || !reorg.CompensationRequired {
		t.Fatalf("deep reorg: %#v %v", reorg, err)
	}
	current, _ = coordinator.Plan(plan.PaymentID)
	if current.State != StateIncident || len(coordinator.Reorgs()) != 1 {
		t.Fatalf("deep reorg did not preserve incident evidence: %#v", current)
	}
}
