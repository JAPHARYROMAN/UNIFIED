// Command verify-phase8-inclusion validates an Anvil evidence bundle through
// the production Phase 7C signed-header and transaction/receipt MPT verifier.
package main

import (
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/unified-finance/unified/services/chain-indexer/projection"
	"golang.org/x/crypto/sha3"
)

type document struct {
	SchemaVersion          uint64                 `json:"schema_version"`
	ArtifactType           string                 `json:"artifact_type"`
	ProofBoundary          string                 `json:"proof_boundary"`
	Environment            string                 `json:"environment"`
	ContainsRealValue      bool                   `json:"contains_real_value"`
	Domain                 string                 `json:"domain"`
	ChainID                uint64                 `json:"chain_id"`
	CoordinatorAddress     string                 `json:"coordinator_address"`
	RequiredDepth          uint64                 `json:"required_depth"`
	TargetTransactionIndex uint64                 `json:"target_transaction_index"`
	ObserverPublicKey      string                 `json:"observer_public_key_ed25519"`
	RawEvidenceObjectHash  string                 `json:"raw_evidence_object_hash"`
	ExpectedLog            expectedLog            `json:"expected_log"`
	Inclusion              authenticatedInclusion `json:"authenticated_inclusion"`
	VerifiedFields         sourceEventProofFields `json:"verified_source_event_proof_fields"`
}

type sourceEventProofFields struct {
	TransactionHash    string `json:"transaction_hash"`
	SourceBlockNumber  uint64 `json:"source_block_number"`
	SourceBlockTime    uint64 `json:"source_block_timestamp"`
	SourceBlockHash    string `json:"source_block_hash"`
	TransactionIndex   uint64 `json:"transaction_index"`
	ReceiptRoot        string `json:"receipt_root"`
	ReceiptProofHash   string `json:"receipt_proof_hash"`
	FinalityHeadNumber uint64 `json:"finality_head_number"`
	FinalityHeadHash   string `json:"finality_head_hash"`
	RequiredDepth      uint64 `json:"required_depth"`
}

type expectedLog struct {
	Address  string   `json:"address"`
	Topics   []string `json:"topics"`
	Data     string   `json:"data"`
	LogIndex uint64   `json:"log_index"`
}

type authenticatedInclusion struct {
	HeaderRLP           string                `json:"header_rlp"`
	HeaderObservedNanos string                `json:"header_observed_at_unix_nanos"`
	HeaderSignature     string                `json:"header_signature_ed25519"`
	Receipts            []receiptProof        `json:"receipts"`
	ConfirmationHeaders []authenticatedHeader `json:"confirmation_headers"`
}

type authenticatedHeader struct {
	HeaderRLP           string `json:"header_rlp"`
	HeaderObservedNanos string `json:"header_observed_at_unix_nanos"`
	HeaderSignature     string `json:"header_signature_ed25519"`
}

type receiptProof struct {
	TransactionIndex      uint64   `json:"transaction_index"`
	TransactionRLP        string   `json:"transaction_rlp"`
	TransactionProofNodes []string `json:"transaction_proof_nodes"`
	ReceiptRLP            string   `json:"receipt_rlp"`
	ReceiptProofNodes     []string `json:"receipt_proof_nodes"`
}

type report struct {
	Status             string   `json:"status"`
	BlockNumber        uint64   `json:"block_number"`
	BlockHash          string   `json:"block_hash"`
	ReceiptsRoot       string   `json:"receipts_root"`
	TransactionHash    string   `json:"transaction_hash"`
	ReceiptProofHash   string   `json:"receipt_proof_hash"`
	FinalityHeadNumber uint64   `json:"finality_head_number"`
	FinalityHeadHash   string   `json:"finality_head_hash"`
	RequiredDepth      uint64   `json:"required_depth"`
	LogAddress         string   `json:"log_address"`
	LogTopics          []string `json:"log_topics"`
	LogData            string   `json:"log_data"`
	LogIndex           uint64   `json:"log_index"`
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "verify Phase 8 inclusion: %v\n", err)
		os.Exit(1)
	}
}

func run(input io.Reader, output io.Writer) error {
	decoder := json.NewDecoder(input)
	decoder.DisallowUnknownFields()
	var evidence document
	if err := decoder.Decode(&evidence); err != nil {
		return fmt.Errorf("decode evidence: %w", err)
	}
	var trailing json.RawMessage
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return errors.New("evidence contains trailing JSON")
	}
	if evidence.ChainID == 0 || evidence.RequiredDepth == 0 ||
		evidence.SchemaVersion != 1 ||
		evidence.ArtifactType != "PHASE8_ANVIL_AUTHENTICATED_INCLUSION" ||
		evidence.ProofBoundary != "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT" ||
		evidence.Environment != "local" || evidence.ContainsRealValue ||
		(evidence.Domain != "home" && evidence.Domain != "satellite") ||
		uint64(len(evidence.Inclusion.ConfirmationHeaders)) != evidence.RequiredDepth {
		return errors.New("invalid chain or confirmation depth")
	}
	canonicalInclusion, err := canonicalJSON(evidence.Inclusion)
	if err != nil {
		return fmt.Errorf("canonicalize authenticated inclusion: %w", err)
	}
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(canonicalInclusion)
	if evidence.RawEvidenceObjectHash != "0x"+hex.EncodeToString(hasher.Sum(nil)) {
		return errors.New("raw evidence object hash differs from authenticated inclusion")
	}
	publicKey, err := decodeHex(evidence.ObserverPublicKey, ed25519.PublicKeySize)
	if err != nil {
		return fmt.Errorf("observer public key: %w", err)
	}
	logData, err := decodeHexAllowEmpty(evidence.ExpectedLog.Data)
	if err != nil {
		return fmt.Errorf("expected log data: %w", err)
	}
	source, err := decodeBlock(
		evidence.Inclusion.HeaderRLP,
		evidence.Inclusion.HeaderObservedNanos,
		evidence.Inclusion.HeaderSignature,
		evidence.Inclusion.Receipts,
	)
	if err != nil {
		return fmt.Errorf("source block: %w", err)
	}
	confirmationHeaders := make([]projection.AuthenticatedHeader, 0, evidence.RequiredDepth)
	for index, header := range evidence.Inclusion.ConfirmationHeaders {
		next, verifyErr := decodeBlock(
			header.HeaderRLP,
			header.HeaderObservedNanos,
			header.HeaderSignature,
			nil,
		)
		if verifyErr != nil {
			return fmt.Errorf("confirmation header %d: %w", index, verifyErr)
		}
		confirmationHeaders = append(confirmationHeaders, projection.AuthenticatedHeader{
			HeaderRLP:  next.HeaderRLP,
			ObservedAt: next.ObservedAt,
			Signature:  next.Signature,
		})
	}
	verified, err := projection.VerifyAuthenticatedReceiptEvidence(
		evidence.ChainID,
		evidence.CoordinatorAddress,
		ed25519.PublicKey(publicKey),
		source,
		confirmationHeaders,
		evidence.TargetTransactionIndex,
		evidence.RequiredDepth,
		projection.ExpectedReceiptLog{
			Address:  evidence.ExpectedLog.Address,
			Topics:   evidence.ExpectedLog.Topics,
			Data:     logData,
			LogIndex: evidence.ExpectedLog.LogIndex,
		},
	)
	if err != nil {
		return err
	}
	fields := evidence.VerifiedFields
	if fields.TransactionHash != verified.TransactionHash ||
		fields.SourceBlockNumber != verified.BlockNumber ||
		fields.SourceBlockTime != verified.BlockTimestamp ||
		fields.SourceBlockHash != verified.BlockHash ||
		fields.TransactionIndex != verified.TransactionIndex ||
		fields.ReceiptRoot != verified.ReceiptsRoot ||
		fields.ReceiptProofHash != verified.InclusionProofHash ||
		fields.FinalityHeadNumber != verified.FinalityHeadNumber ||
		fields.FinalityHeadHash != verified.FinalityHeadHash ||
		fields.RequiredDepth != evidence.RequiredDepth {
		return errors.New("expanded SourceEventProof fields differ from verified evidence")
	}
	return json.NewEncoder(output).Encode(report{
		Status:             "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT",
		BlockNumber:        verified.BlockNumber,
		BlockHash:          verified.BlockHash,
		ReceiptsRoot:       verified.ReceiptsRoot,
		TransactionHash:    verified.TransactionHash,
		ReceiptProofHash:   verified.InclusionProofHash,
		FinalityHeadNumber: verified.FinalityHeadNumber,
		FinalityHeadHash:   verified.FinalityHeadHash,
		RequiredDepth:      evidence.RequiredDepth,
		LogAddress:         verified.Log.Address,
		LogTopics:          verified.Log.Topics,
		LogData:            "0x" + hex.EncodeToString(verified.Log.Data),
		LogIndex:           verified.Log.LogIndex,
	})
}

func decodeBlock(
	headerRLP string,
	observedNanos string,
	signature string,
	receipts []receiptProof,
) (projection.AuthenticatedBlock, error) {
	header, err := decodeHex(headerRLP, -1)
	if err != nil {
		return projection.AuthenticatedBlock{}, fmt.Errorf("header RLP: %w", err)
	}
	observed, err := strconv.ParseUint(observedNanos, 10, 64)
	if err != nil || observed == 0 || observed > math.MaxInt64 {
		return projection.AuthenticatedBlock{}, errors.New("invalid observed nanos")
	}
	signed, err := decodeHex(signature, ed25519.SignatureSize)
	if err != nil {
		return projection.AuthenticatedBlock{}, fmt.Errorf("header signature: %w", err)
	}
	proofs := make([]projection.ReceiptInclusionProof, 0, len(receipts))
	for index, receipt := range receipts {
		if receipt.TransactionIndex != uint64(index) {
			return projection.AuthenticatedBlock{}, errors.New(
				"receipt proof set is not prefix-complete",
			)
		}
		transaction, decodeErr := decodeHex(receipt.TransactionRLP, -1)
		if decodeErr != nil {
			return projection.AuthenticatedBlock{}, decodeErr
		}
		encodedReceipt, decodeErr := decodeHex(receipt.ReceiptRLP, -1)
		if decodeErr != nil {
			return projection.AuthenticatedBlock{}, decodeErr
		}
		transactionNodes, decodeErr := decodeNodes(receipt.TransactionProofNodes)
		if decodeErr != nil {
			return projection.AuthenticatedBlock{}, decodeErr
		}
		receiptNodes, decodeErr := decodeNodes(receipt.ReceiptProofNodes)
		if decodeErr != nil {
			return projection.AuthenticatedBlock{}, decodeErr
		}
		proofs = append(proofs, projection.ReceiptInclusionProof{
			TransactionIndex:      receipt.TransactionIndex,
			TransactionRLP:        transaction,
			TransactionProofNodes: transactionNodes,
			ReceiptRLP:            encodedReceipt,
			ReceiptProofNodes:     receiptNodes,
		})
	}
	return projection.AuthenticatedBlock{
		HeaderRLP:  header,
		ObservedAt: time.Unix(0, int64(observed)).UTC(),
		Signature:  signed,
		Receipts:   proofs,
	}, nil
}

func decodeNodes(values []string) ([][]byte, error) {
	result := make([][]byte, 0, len(values))
	for _, value := range values {
		decoded, err := decodeHex(value, -1)
		if err != nil {
			return nil, err
		}
		result = append(result, decoded)
	}
	return result, nil
}

func decodeHex(value string, expected int) ([]byte, error) {
	if !strings.HasPrefix(value, "0x") || value != strings.ToLower(value) {
		return nil, errors.New("value is not canonical lower-case hex")
	}
	decoded, err := hex.DecodeString(value[2:])
	if err != nil || len(decoded) == 0 || (expected >= 0 && len(decoded) != expected) {
		return nil, errors.New("value has invalid hex length")
	}
	return decoded, nil
}

func decodeHexAllowEmpty(value string) ([]byte, error) {
	if value == "0x" {
		return []byte{}, nil
	}
	return decodeHex(value, -1)
}

func canonicalJSON(value any) ([]byte, error) {
	raw, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.UseNumber()
	var generic any
	if err := decoder.Decode(&generic); err != nil {
		return nil, err
	}
	return json.Marshal(generic)
}
