package settlement

import (
	"encoding/hex"
	"errors"
	"math/big"
	"strings"

	"golang.org/x/crypto/sha3"
)

const EligibilityDomainLabel = "UNIFIED_PHASE7C_ELIGIBILITY_V1"

var ErrInvalidDigestInput = errors.New("invalid Solidity settlement digest input")

// SolidityInstruction is the exact static Solidity tuple signed by the
// accounting attester. Bytes32 and address values use canonical 0x-prefixed
// hexadecimal strings; integer values use canonical unsigned decimal strings.
type SolidityInstruction struct {
	PaymentID                string
	AllocationID             string
	LoanID                   string
	SourceAssetID            string
	TargetAssetID            string
	SourceUnits              string
	TargetUnits              string
	ProviderIDHash           string
	ProviderReferenceHash    string
	ReconciliationID         string
	ReconciliationCommitment string
	OriginalJournalSetHash   string
	ConversionPolicyHash     string
	FinalityPolicyHash       string
	EvidenceHash             string
	JournalRef               string
	FinalizedAt              uint64
	ReversalDeadline         uint64
	ExpectedDebt             string
	ExpectedStateNonce       uint64
	Attester                 string
}

// SolidityDigestInput is abi.encode(
//
//	ELIGIBILITY_DOMAIN, chainid, gateway, finalizer, policySetHash, instruction
//
// )
// where instruction is the 21-field static tuple above.
type SolidityDigestInput struct {
	ChainID       uint64
	Gateway       string
	Finalizer     string
	PolicySetHash string
	Instruction   SolidityInstruction
}

// SolidityInstructionDigest implements Solidity's legacy Keccak-256 over the
// exact 26 static ABI words used by CanonicalExternalSettlementGateway.
func SolidityInstructionDigest(input SolidityDigestInput) (string, error) {
	if input.ChainID == 0 {
		return "", ErrInvalidDigestInput
	}
	encoded := make([]byte, 0, 26*32)
	domain := legacyKeccak256([]byte(EligibilityDomainLabel))
	encoded = append(encoded, domain[:]...)
	encoded = appendUint64Word(encoded, input.ChainID)
	var err error
	if encoded, err = appendAddressWord(encoded, input.Gateway); err != nil {
		return "", err
	}
	if encoded, err = appendAddressWord(encoded, input.Finalizer); err != nil {
		return "", err
	}
	if encoded, err = appendBytes32Word(encoded, input.PolicySetHash); err != nil {
		return "", err
	}

	instruction := input.Instruction
	for _, value := range []string{
		instruction.PaymentID,
		instruction.AllocationID,
		instruction.LoanID,
		instruction.SourceAssetID,
		instruction.TargetAssetID,
	} {
		if encoded, err = appendBytes32Word(encoded, value); err != nil {
			return "", err
		}
	}
	if encoded, err = appendUint256Word(encoded, instruction.SourceUnits); err != nil {
		return "", err
	}
	if encoded, err = appendUint256Word(encoded, instruction.TargetUnits); err != nil {
		return "", err
	}
	for _, value := range []string{
		instruction.ProviderIDHash,
		instruction.ProviderReferenceHash,
		instruction.ReconciliationID,
		instruction.ReconciliationCommitment,
		instruction.OriginalJournalSetHash,
		instruction.ConversionPolicyHash,
		instruction.FinalityPolicyHash,
		instruction.EvidenceHash,
		instruction.JournalRef,
	} {
		if encoded, err = appendBytes32Word(encoded, value); err != nil {
			return "", err
		}
	}
	encoded = appendUint64Word(encoded, instruction.FinalizedAt)
	encoded = appendUint64Word(encoded, instruction.ReversalDeadline)
	if encoded, err = appendUint256Word(encoded, instruction.ExpectedDebt); err != nil {
		return "", err
	}
	encoded = appendUint64Word(encoded, instruction.ExpectedStateNonce)
	if encoded, err = appendAddressWord(encoded, instruction.Attester); err != nil {
		return "", err
	}
	if len(encoded) != 26*32 {
		return "", ErrInvalidDigestInput
	}
	digest := legacyKeccak256(encoded)
	return "0x" + hex.EncodeToString(digest[:]), nil
}

func legacyKeccak256(value []byte) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(value)
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}

func appendBytes32Word(encoded []byte, value string) ([]byte, error) {
	decoded, err := decodeFixedHex(value, 32)
	if err != nil {
		return nil, err
	}
	return append(encoded, decoded...), nil
}

func appendAddressWord(encoded []byte, value string) ([]byte, error) {
	decoded, err := decodeFixedHex(value, 20)
	if err != nil {
		return nil, err
	}
	encoded = append(encoded, make([]byte, 12)...)
	return append(encoded, decoded...), nil
}

func appendUint64Word(encoded []byte, value uint64) []byte {
	word := make([]byte, 32)
	new(big.Int).SetUint64(value).FillBytes(word)
	return append(encoded, word...)
}

func appendUint256Word(encoded []byte, value string) ([]byte, error) {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() < 0 || number.BitLen() > 256 || number.String() != value {
		return nil, ErrInvalidDigestInput
	}
	word := make([]byte, 32)
	number.FillBytes(word)
	return append(encoded, word...), nil
}

func decodeFixedHex(value string, size int) ([]byte, error) {
	if value != strings.ToLower(value) ||
		!strings.HasPrefix(value, "0x") ||
		len(value) != 2+size*2 {
		return nil, ErrInvalidDigestInput
	}
	decoded, err := hex.DecodeString(value[2:])
	if err != nil || len(decoded) != size {
		return nil, ErrInvalidDigestInput
	}
	return decoded, nil
}
