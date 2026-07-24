// Package settlementtest builds a complete synthetic coordinator/indexer fixture for
// foundation-ledger integration tests. It has no production runtime wiring.
package settlementtest

import (
	"encoding/hex"
	"fmt"
	"math/big"
	"testing"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/chain-indexer/projectiontest"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
	"github.com/unified-finance/unified/services/payment-orchestrator/settlement"
)

func ConfirmedWithDeepReorg(
	t testing.TB,
) (settlement.Confirmation, settlement.DurableReorgAuthority) {
	t.Helper()
	now := time.Unix(1_900_000_000, 0).UTC()
	builder := projectiontest.NewBuilder(31337)
	finalityPolicyHash, err := chainprojection.ComputeFinalityPolicyHash(
		31337,
		"0x1111111111111111111111111111111111111111",
		1,
		builder.PublicKey(),
	)
	if err != nil {
		t.Fatal(err)
	}
	request := settlement.PrepareRequest{
		PaymentID:                bytes32(1),
		LoanID:                   bytes32(3),
		ProviderID:               "provider-local",
		ProviderReference:        "provider-reference-001",
		PaymentStatus:            payment.StatusFinal,
		PaymentVersion:           4,
		SourceAssetID:            bytes32(4),
		TargetAssetID:            bytes32(5),
		TargetToken:              "0x0000000000000000000000000000000000000100",
		Denomination:             "USD",
		SourcePrecision:          6,
		TargetPrecision:          6,
		SourceUnits:              "1250",
		TargetUnits:              "1250",
		ReconciliationID:         bytes32(8),
		DifferenceUnits:          "0",
		FinalityPolicyHash:       finalityPolicyHash,
		ConversionPolicyHash:     bytes32(11),
		PolicySetHash:            bytes32(0x33),
		EligibilityEvidenceHash:  bytes32(13),
		ExpectedDebtUnits:        "1000",
		ExpectedStateNonce:       7,
		ChainID:                  31337,
		GatewayAddress:           "0x1111111111111111111111111111111111111111",
		FinalizerAddress:         "0x2222222222222222222222222222222222222222",
		ProviderIDHash:           bytes32(6),
		ProviderReferenceHash:    bytes32(7),
		ReconciliationCommitment: bytes32(9),
		OriginalJournalSetHash:   bytes32(10),
		JournalRef:               bytes32(14),
		AttesterAddress:          "0x4444444444444444444444444444444444444444",
		FinalizedAt:              now,
		ReversalDeadline:         now.Add(24 * time.Hour),
		PreparedAt:               now.Add(25 * time.Hour),
		CorrelationID:            "correlation-001",
	}
	request.OriginalJournalIDs = []string{
		"payment:" + request.PaymentID + ":final",
		"payment:" + request.PaymentID + ":provisional",
	}
	request.AllocationID = settlement.CalculateAllocationID(request)
	coordinator, err := settlement.NewInMemory(allocationmode.NewInMemory())
	if err != nil {
		t.Fatal(err)
	}
	plan, err := coordinator.Prepare(request)
	if err != nil {
		t.Fatal(err)
	}
	observedAt := time.Unix(1_900_100_000, 0).UTC()
	raw := gatewayLog(t, plan)
	settlementBlock, settlementBlockHash, transactionHash :=
		builder.BlockWithReceipt(
			1,
			bytes32(0),
			observedAt,
			100,
			true,
			[]projectiontest.Log{{
				Address: plan.GatewayAddress,
				Topics:  raw.Topics,
				Data:    raw.Data,
			}},
		)
	plan, err = coordinator.Submit(settlement.SubmissionRequest{
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
		t.Fatal(err)
	}

	indexer, err := chainprojection.NewGateway(
		plan.ChainID,
		plan.GatewayAddress,
		1,
		builder.PublicKey(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := indexer.IngestAuthenticated(settlementBlock); err != nil {
		t.Fatal(err)
	}
	headBlock, _ := builder.EmptyBlock(
		2,
		settlementBlockHash,
		observedAt.Add(time.Minute),
	)
	if err := indexer.IngestAuthenticated(headBlock); err != nil {
		t.Fatal(err)
	}
	projection, ok := indexer.FinalizedGatewayProjection(plan.PaymentID)
	if !ok {
		t.Fatal("finalized projection unavailable")
	}
	confirmation, err := coordinator.Confirm(settlement.ConfirmationRequest{
		PaymentID:         plan.PaymentID,
		AllocationID:      plan.AllocationID,
		InstructionDigest: plan.InstructionDigest,
		ExpectedVersion:   plan.Version,
		Projection:        projection,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement, _ := builder.EmptyBlock(
		1,
		bytes32(0),
		observedAt.Add(2*time.Minute),
	)
	if err := indexer.IngestAuthenticated(replacement); err != nil {
		t.Fatal(err)
	}
	reorg, ok := indexer.ReorgEnvelope(projection.Settlement().EventID)
	if !ok {
		t.Fatal("verified reorg envelope unavailable")
	}
	incidentPlan, ok := coordinator.Plan(plan.PaymentID)
	if !ok {
		t.Fatal("confirmed plan unavailable")
	}
	authority, err := coordinator.RecordReorg(incidentPlan.Version, reorg)
	if err != nil {
		t.Fatal(err)
	}
	return confirmation, authority
}

func gatewayLog(t testing.TB, plan settlement.Plan) chainprojection.RawLog {
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
		uintWord(t, fmt.Sprint(plan.Instruction.FinalizedAt)),
		uintWord(t, fmt.Sprint(plan.Instruction.ReversalDeadline)),
		uintWord(t, plan.DebtBeforeUnits),
		uintWord(t, plan.PrincipalUnits),
		uintWord(t, plan.RefundableExcessUnits),
		uintWord(t, plan.DebtAfterUnits),
		uintWord(t, fmt.Sprint(plan.ExpectedStateNonce)),
		uintWord(t, fmt.Sprint(plan.ExpectedStateNonce+2)),
		addressWord(t, "0x6666666666666666666666666666666666666666"),
		addressWord(t, "0x7777777777777777777777777777777777777777"),
	} {
		data = append(data, word...)
	}
	return chainprojection.RawLog{
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
		LogIndex:        4,
		BlockNumber:     2,
		BlockHash:       bytes32(200),
	}
}

func bytes32(value uint64) string {
	return fmt.Sprintf("0x%064x", value)
}

func hexWord(t testing.TB, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(value[2:])
	if err != nil || len(decoded) != 32 {
		t.Fatalf("invalid bytes32 %q", value)
	}
	return decoded
}

func addressWord(t testing.TB, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(value[2:])
	if err != nil || len(decoded) != 20 {
		t.Fatalf("invalid address %q", value)
	}
	return append(make([]byte, 12), decoded...)
}

func uintWord(t testing.TB, value string) []byte {
	t.Helper()
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() < 0 || number.BitLen() > 256 {
		t.Fatalf("invalid uint256 %q", value)
	}
	word := make([]byte, 32)
	number.FillBytes(word)
	return word
}
