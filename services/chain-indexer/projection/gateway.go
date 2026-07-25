package projection

import (
	"encoding/hex"
	"fmt"
	"math/big"
	"strings"

	"golang.org/x/crypto/sha3"
)

const canonicalSettlementEventSignature = "CanonicalSettlementExecuted(bytes32,bytes32,bytes32,(bytes32,bytes32,address,address,address,bytes32,bytes32,address,uint256,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint256,uint256,uint256,uint64,uint64,address,address))"

// RawLog is the lossless receipt input required to decode one canonical
// gateway event. Topics and identity hashes are canonical lowercase hex.
type RawLog struct {
	ChainID         uint64
	ContractAddress string
	Topics          []string
	Data            []byte
	TransactionHash string
	LogIndex        uint32
	BlockNumber     uint64
	BlockHash       string
}

func CanonicalSettlementTopic() string {
	hash := keccak([]byte(canonicalSettlementEventSignature))
	return hex32(hash[:])
}

func DecodeCanonicalSettlementLog(raw RawLog) (Event, error) {
	return decodeCanonicalSettlementLog(raw, 0, "", "", false)
}

func decodeCanonicalSettlementLog(
	raw RawLog,
	transactionIndex uint64,
	receiptsRoot string,
	inclusionProofHash string,
	verified bool,
) (Event, error) {
	if raw.ChainID == 0 || !canonicalAddress(raw.ContractAddress) ||
		len(raw.Topics) != 4 || raw.Topics[0] != CanonicalSettlementTopic() ||
		!canonicalHash(raw.TransactionHash) || raw.BlockNumber == 0 ||
		!canonicalHash(raw.BlockHash) || len(raw.Data) != 29*32 ||
		(verified && (!canonicalHash(receiptsRoot) ||
			!canonicalHash(inclusionProofHash))) {
		return Event{}, ErrInvalidEvent
	}
	for _, topic := range raw.Topics[1:] {
		if !canonicalHash(topic) {
			return Event{}, ErrInvalidEvent
		}
	}
	word := func(index int) []byte {
		return raw.Data[index*32 : (index+1)*32]
	}
	address := func(index int) (string, bool) {
		value := word(index)
		for _, prefix := range value[:12] {
			if prefix != 0 {
				return "", false
			}
		}
		return "0x" + hex.EncodeToString(value[12:]), true
	}
	uint256 := func(index int) string {
		return new(big.Int).SetBytes(word(index)).String()
	}
	uint64Value := func(index int) (uint64, bool) {
		value := new(big.Int).SetBytes(word(index))
		return value.Uint64(), value.BitLen() <= 64
	}

	loanAccount, loanAccountOK := address(2)
	finalizer, finalizerOK := address(3)
	attester, attesterOK := address(4)
	targetToken, targetTokenOK := address(7)
	finalizedAt, finalizedAtOK := uint64Value(19)
	reversalDeadline, reversalDeadlineOK := uint64Value(20)
	stateNonceBefore, stateNonceBeforeOK := uint64Value(25)
	stateNonceAfter, stateNonceAfterOK := uint64Value(26)
	lender, lenderOK := address(27)
	borrower, borrowerOK := address(28)
	if !loanAccountOK || !finalizerOK || !attesterOK || !targetTokenOK ||
		!finalizedAtOK || !reversalDeadlineOK ||
		!stateNonceBeforeOK || !stateNonceAfterOK ||
		!lenderOK || !borrowerOK {
		return Event{}, ErrInvalidEvent
	}
	eventIDHash := keccak([]byte(fmt.Sprintf(
		"%d\x00%s\x00%s\x00%d",
		raw.ChainID,
		raw.BlockHash,
		raw.TransactionHash,
		raw.LogIndex,
	)))
	evidenceInput := make([]byte, 0, len(raw.Data)+len(raw.Topics)*32)
	for _, topic := range raw.Topics {
		decoded, _ := hex.DecodeString(topic[2:])
		evidenceInput = append(evidenceInput, decoded...)
	}
	evidenceInput = append(evidenceInput, raw.Data...)
	evidenceHash := keccak(evidenceInput)

	return Event{
		ID:                       hex32(eventIDHash[:]),
		Type:                     CanonicalSettlementExecuted,
		TxHash:                   raw.TransactionHash,
		LogIndex:                 raw.LogIndex,
		BlockNumber:              raw.BlockNumber,
		BlockHash:                raw.BlockHash,
		ChainID:                  raw.ChainID,
		Gateway:                  raw.ContractAddress,
		PaymentID:                raw.Topics[1],
		AllocationID:             raw.Topics[2],
		LoanID:                   raw.Topics[3],
		InstructionDigest:        hex32(word(0)),
		PolicySetHash:            hex32(word(1)),
		LoanAccount:              loanAccount,
		Finalizer:                finalizer,
		Attester:                 attester,
		SourceAssetID:            hex32(word(5)),
		AssetID:                  hex32(word(6)),
		TargetToken:              targetToken,
		SourceUnits:              uint256(8),
		GrossUnits:               uint256(9),
		ProviderIDHash:           hex32(word(10)),
		ProviderReferenceHash:    hex32(word(11)),
		ReconciliationID:         hex32(word(12)),
		ReconciliationCommitment: hex32(word(13)),
		OriginalJournalSetHash:   hex32(word(14)),
		ConversionPolicyHash:     hex32(word(15)),
		FinalityPolicyHash:       hex32(word(16)),
		EvidenceHash:             hex32(word(17)),
		JournalRef:               hex32(word(18)),
		ProviderFinalizedAt:      finalizedAt,
		ReversalDeadline:         reversalDeadline,
		DebtBeforeUnits:          uint256(21),
		PrincipalUnits:           uint256(22),
		RefundableExcessUnits:    uint256(23),
		DebtAfterUnits:           uint256(24),
		StateNonceBefore:         stateNonceBefore,
		StateNonceAfter:          stateNonceAfter,
		LenderID:                 lender,
		BorrowerID:               borrower,
		RawEvidenceHash:          hex32(evidenceHash[:]),
		TransactionIndex:         transactionIndex,
		ReceiptsRoot:             receiptsRoot,
		InclusionProofHash:       inclusionProofHash,
		decodedCanonical:         verified,
	}, nil
}

func canonicalHash(value string) bool {
	return canonicalHex(value, 32)
}

func nonzeroCanonicalHash(value string) bool {
	decoded, ok := decodeCanonicalHex(value, 32)
	if !ok {
		return false
	}
	for _, item := range decoded {
		if item != 0 {
			return true
		}
	}
	return false
}

func canonicalAddress(value string) bool {
	return canonicalHex(value, 20)
}

func canonicalHex(value string, size int) bool {
	if value != strings.ToLower(value) || !strings.HasPrefix(value, "0x") ||
		len(value) != 2+size*2 {
		return false
	}
	decoded, err := hex.DecodeString(value[2:])
	return err == nil && len(decoded) == size
}

func hex32(value []byte) string {
	return "0x" + hex.EncodeToString(value)
}

func keccak(value []byte) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(value)
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}
