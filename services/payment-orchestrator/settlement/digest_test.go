package settlement

import (
	"fmt"
	"testing"
)

func TestSolidityInstructionDigestGolden(t *testing.T) {
	input := SolidityDigestInput{
		ChainID:       31337,
		Gateway:       "0x1111111111111111111111111111111111111111",
		Finalizer:     "0x2222222222222222222222222222222222222222",
		PolicySetHash: bytes32Uint(0x33),
		Instruction: SolidityInstruction{
			PaymentID:                bytes32Uint(1),
			AllocationID:             bytes32Uint(2),
			LoanID:                   bytes32Uint(3),
			SourceAssetID:            bytes32Uint(4),
			TargetAssetID:            bytes32Uint(5),
			SourceUnits:              "1000",
			TargetUnits:              "1000",
			ProviderIDHash:           bytes32Uint(6),
			ProviderReferenceHash:    bytes32Uint(7),
			ReconciliationID:         bytes32Uint(8),
			ReconciliationCommitment: bytes32Uint(9),
			OriginalJournalSetHash:   bytes32Uint(10),
			ConversionPolicyHash:     bytes32Uint(11),
			FinalityPolicyHash:       bytes32Uint(12),
			EvidenceHash:             bytes32Uint(13),
			JournalRef:               bytes32Uint(14),
			FinalizedAt:              1_700_000_000,
			ReversalDeadline:         1_700_086_400,
			ExpectedDebt:             "1200",
			ExpectedStateNonce:       7,
			Attester:                 "0x4444444444444444444444444444444444444444",
		},
	}
	got, err := SolidityInstructionDigest(input)
	if err != nil {
		t.Fatal(err)
	}
	const expected = "0x21e842e55f3dce5613f44771b5299608ea7154e8fc7fdb0fa709539373610c06"
	if got != expected {
		t.Fatalf("digest = %s", got)
	}
}

func bytes32Uint(value uint64) string {
	return fmt.Sprintf("0x%064x", value)
}
