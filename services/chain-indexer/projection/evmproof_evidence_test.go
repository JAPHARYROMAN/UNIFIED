package projection_test

import (
	"bytes"
	"errors"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/chain-indexer/projectiontest"
)

func TestAuthenticatedReceiptEvidenceBindsMPTLogAndFinalityHead(t *testing.T) {
	const (
		chainID     = uint64(31_337)
		coordinator = "0x1111111111111111111111111111111111111111"
		topic       = "0x2222222222222222222222222222222222222222222222222222222222222222"
	)
	builder := projectiontest.NewBuilder(chainID)
	observed := time.Unix(1_946_000_000, 0).UTC()
	source, sourceHash, transactionHash := builder.BlockWithReceipt(
		1,
		"0x0000000000000000000000000000000000000000000000000000000000000000",
		observed,
		7,
		true,
		[]projectiontest.Log{{
			Address: coordinator,
			Topics:  []string{topic},
			Data:    []byte("message-sent"),
		}},
	)
	confirmation1, hash2 := builder.EmptyBlock(
		2,
		sourceHash,
		observed.Add(time.Second),
	)
	confirmation2, hash3 := builder.EmptyBlock(
		3,
		hash2,
		observed.Add(2*time.Second),
	)
	headers := []projection.AuthenticatedHeader{
		authenticatedHeader(confirmation1),
		authenticatedHeader(confirmation2),
	}
	expectedLog := projection.ExpectedReceiptLog{
		Address:  coordinator,
		Topics:   []string{topic},
		Data:     []byte("message-sent"),
		LogIndex: 0,
	}
	verified, err := projection.VerifyAuthenticatedReceiptEvidence(
		chainID,
		coordinator,
		builder.PublicKey(),
		source,
		headers,
		0,
		2,
		expectedLog,
	)
	if err != nil {
		t.Fatal(err)
	}
	if verified.TransactionHash != transactionHash ||
		verified.FinalityHeadHash != hash3 ||
		verified.FinalityHeadNumber != 3 ||
		verified.Log.Address != coordinator ||
		!bytes.Equal(verified.Log.Data, expectedLog.Data) ||
		verified.Log.LogIndex != 0 {
		t.Fatalf("unexpected verified evidence: %#v", verified)
	}

	t.Run("mutated MPT node", func(t *testing.T) {
		mutated := copyAuthenticatedBlock(source)
		mutated.Receipts[0].ReceiptProofNodes[0][0] ^= 1
		_, err := projection.VerifyAuthenticatedReceiptEvidence(
			chainID,
			coordinator,
			builder.PublicKey(),
			mutated,
			headers,
			0,
			2,
			expectedLog,
		)
		if !errors.Is(err, projection.ErrInvalidInclusionProof) {
			t.Fatalf("mutated receipt proof was not rejected: %v", err)
		}
	})

	t.Run("wrong exact log", func(t *testing.T) {
		wrong := expectedLog
		wrong.Topics = []string{
			"0x3333333333333333333333333333333333333333333333333333333333333333",
		}
		_, err := projection.VerifyAuthenticatedReceiptEvidence(
			chainID,
			coordinator,
			builder.PublicKey(),
			source,
			headers,
			0,
			2,
			wrong,
		)
		if !errors.Is(err, projection.ErrInvalidInclusionProof) {
			t.Fatalf("wrong coordinator log was not rejected: %v", err)
		}
	})

	t.Run("broken confirmation chain", func(t *testing.T) {
		swapped := []projection.AuthenticatedHeader{headers[1], headers[0]}
		_, err := projection.VerifyAuthenticatedReceiptEvidence(
			chainID,
			coordinator,
			builder.PublicKey(),
			source,
			swapped,
			0,
			2,
			expectedLog,
		)
		if !errors.Is(err, projection.ErrInvalidHeaderEvidence) {
			t.Fatalf("broken confirmation chain was not rejected: %v", err)
		}
	})

	t.Run("reordered receipt prefix", func(t *testing.T) {
		reordered := copyAuthenticatedBlock(source)
		first := copyReceiptProof(reordered.Receipts[0])
		first.TransactionIndex = 1
		second := copyReceiptProof(reordered.Receipts[0])
		second.TransactionIndex = 0
		reordered.Receipts = []projection.ReceiptInclusionProof{first, second}
		_, err := projection.VerifyAuthenticatedReceiptEvidence(
			chainID,
			coordinator,
			builder.PublicKey(),
			reordered,
			headers,
			1,
			2,
			expectedLog,
		)
		if !errors.Is(err, projection.ErrInvalidInclusionProof) {
			t.Fatalf("reordered receipt prefix was not rejected: %v", err)
		}
	})
}

func authenticatedHeader(block projection.AuthenticatedBlock) projection.AuthenticatedHeader {
	return projection.AuthenticatedHeader{
		HeaderRLP:  append([]byte(nil), block.HeaderRLP...),
		ObservedAt: block.ObservedAt,
		Signature:  append([]byte(nil), block.Signature...),
	}
}

func copyAuthenticatedBlock(block projection.AuthenticatedBlock) projection.AuthenticatedBlock {
	result := projection.AuthenticatedBlock{
		HeaderRLP:  append([]byte(nil), block.HeaderRLP...),
		ObservedAt: block.ObservedAt,
		Signature:  append([]byte(nil), block.Signature...),
		Receipts:   make([]projection.ReceiptInclusionProof, len(block.Receipts)),
	}
	for index, proof := range block.Receipts {
		result.Receipts[index] = copyReceiptProof(proof)
	}
	return result
}

func copyReceiptProof(
	proof projection.ReceiptInclusionProof,
) projection.ReceiptInclusionProof {
	return projection.ReceiptInclusionProof{
		TransactionIndex:      proof.TransactionIndex,
		TransactionRLP:        append([]byte(nil), proof.TransactionRLP...),
		TransactionProofNodes: copyNodes(proof.TransactionProofNodes),
		ReceiptRLP:            append([]byte(nil), proof.ReceiptRLP...),
		ReceiptProofNodes:     copyNodes(proof.ReceiptProofNodes),
	}
}

func copyNodes(nodes [][]byte) [][]byte {
	result := make([][]byte, len(nodes))
	for index, node := range nodes {
		result[index] = append([]byte(nil), node...)
	}
	return result
}
