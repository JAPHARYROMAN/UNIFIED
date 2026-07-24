// Package projectiontest builds deterministic, cryptographically valid local
// EVM header and trie-proof fixtures. It is test support, not an RPC or
// production trust adapter.
package projectiontest

import (
	"crypto/ed25519"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/unified-finance/unified/services/chain-indexer/projection"
	"golang.org/x/crypto/sha3"
)

type Log struct {
	Address string
	Topics  []string
	Data    []byte
}

type Builder struct {
	chainID    uint64
	privateKey ed25519.PrivateKey
}

func NewBuilder(chainID uint64) *Builder {
	seed := make([]byte, ed25519.SeedSize)
	binary.BigEndian.PutUint64(seed[len(seed)-8:], chainID)
	var fixedSeed [ed25519.SeedSize]byte
	copy(fixedSeed[:], seed)
	return NewBuilderWithSeed(chainID, fixedSeed)
}

// NewBuilderWithSeed creates an independent deterministic header authority for
// adversarial cross-authority tests.
func NewBuilderWithSeed(
	chainID uint64,
	seed [ed25519.SeedSize]byte,
) *Builder {
	return &Builder{
		chainID:    chainID,
		privateKey: ed25519.NewKeyFromSeed(seed[:]),
	}
}

func (builder *Builder) PublicKey() ed25519.PublicKey {
	publicKey := builder.privateKey.Public().(ed25519.PublicKey)
	return append(ed25519.PublicKey(nil), publicKey...)
}

func (builder *Builder) EmptyBlock(
	number uint64,
	parentHash string,
	observedAt time.Time,
) (projection.AuthenticatedBlock, string) {
	emptyRoot := keccak([]byte{0x80})
	return builder.block(number, parentHash, observedAt, emptyRoot[:], emptyRoot[:], nil)
}

func (builder *Builder) BlockWithReceipt(
	number uint64,
	parentHash string,
	observedAt time.Time,
	transactionDiscriminator uint64,
	succeeded bool,
	logs []Log,
) (projection.AuthenticatedBlock, string, string) {
	transaction := rlpList(rlpUint(transactionDiscriminator))
	receipt := receiptRLP(succeeded, logs)
	key := rlpUint(0)
	transactionLeaf := trieLeaf(key, transaction)
	receiptLeaf := trieLeaf(key, receipt)
	transactionRoot := keccak(transactionLeaf)
	receiptRoot := keccak(receiptLeaf)
	proof := projection.ReceiptInclusionProof{
		TransactionIndex:      0,
		TransactionRLP:        transaction,
		TransactionProofNodes: [][]byte{transactionLeaf},
		ReceiptRLP:            receipt,
		ReceiptProofNodes:     [][]byte{receiptLeaf},
	}
	block, blockHash := builder.block(
		number,
		parentHash,
		observedAt,
		transactionRoot[:],
		receiptRoot[:],
		[]projection.ReceiptInclusionProof{proof},
	)
	transactionHash := keccak(transaction)
	return block, blockHash, "0x" + hex.EncodeToString(transactionHash[:])
}

func (builder *Builder) block(
	number uint64,
	parentHash string,
	observedAt time.Time,
	transactionsRoot []byte,
	receiptsRoot []byte,
	receipts []projection.ReceiptInclusionProof,
) (projection.AuthenticatedBlock, string) {
	parent := decodeFixedHex(parentHash, 32)
	if number == 1 && parentHash == "" {
		parent = make([]byte, 32)
	}
	header := rlpList(
		rlpBytes(parent),
		rlpBytes(make([]byte, 32)),
		rlpBytes(make([]byte, 20)),
		rlpBytes(make([]byte, 32)),
		rlpBytes(transactionsRoot),
		rlpBytes(receiptsRoot),
		rlpBytes(make([]byte, 256)),
		rlpUint(1),
		rlpUint(number),
		rlpUint(30_000_000),
		rlpUint(21_000),
		rlpUint(uint64(observedAt.Unix())),
	)
	digest, err := projection.AuthenticatedHeaderSigningDigest(
		builder.chainID,
		header,
		observedAt,
	)
	if err != nil {
		panic(err)
	}
	signature := ed25519.Sign(builder.privateKey, digest[:])
	hash := keccak(header)
	return projection.AuthenticatedBlock{
		HeaderRLP:  header,
		ObservedAt: observedAt,
		Signature:  signature,
		Receipts:   receipts,
	}, "0x" + hex.EncodeToString(hash[:])
}

func receiptRLP(succeeded bool, logs []Log) []byte {
	status := []byte{}
	if succeeded {
		status = []byte{1}
	}
	encodedLogs := make([][]byte, 0, len(logs))
	for _, log := range logs {
		topics := make([][]byte, 0, len(log.Topics))
		for _, topic := range log.Topics {
			topics = append(topics, rlpBytes(decodeFixedHex(topic, 32)))
		}
		encodedLogs = append(encodedLogs, rlpList(
			rlpBytes(decodeFixedHex(log.Address, 20)),
			rlpList(topics...),
			rlpBytes(log.Data),
		))
	}
	return rlpList(
		rlpBytes(status),
		rlpUint(21_000),
		rlpBytes(make([]byte, 256)),
		rlpList(encodedLogs...),
	)
}

func trieLeaf(key, value []byte) []byte {
	nibbles := make([]byte, 0, len(key)*2)
	for _, item := range key {
		nibbles = append(nibbles, item>>4, item&0x0f)
	}
	prefix := byte(2)
	if len(nibbles)%2 == 1 {
		prefix = 3
		nibbles = append([]byte{prefix}, nibbles...)
	} else {
		nibbles = append([]byte{prefix, 0}, nibbles...)
	}
	compact := make([]byte, (len(nibbles)+1)/2)
	for index := range compact {
		compact[index] = nibbles[index*2] << 4
		if index*2+1 < len(nibbles) {
			compact[index] |= nibbles[index*2+1]
		}
	}
	return rlpList(rlpBytes(compact), rlpBytes(value))
}

func rlpUint(value uint64) []byte {
	if value == 0 {
		return []byte{0x80}
	}
	var encoded [8]byte
	binary.BigEndian.PutUint64(encoded[:], value)
	first := 0
	for encoded[first] == 0 {
		first++
	}
	return rlpBytes(encoded[first:])
}

func rlpBytes(value []byte) []byte {
	if len(value) == 1 && value[0] < 0x80 {
		return append([]byte(nil), value...)
	}
	if len(value) < 56 {
		return append([]byte{0x80 + byte(len(value))}, value...)
	}
	length := encodeLength(len(value))
	result := []byte{0xb7 + byte(len(length))}
	result = append(result, length...)
	return append(result, value...)
}

func rlpList(values ...[]byte) []byte {
	var payload []byte
	for _, value := range values {
		payload = append(payload, value...)
	}
	if len(payload) < 56 {
		return append([]byte{0xc0 + byte(len(payload))}, payload...)
	}
	length := encodeLength(len(payload))
	result := []byte{0xf7 + byte(len(length))}
	result = append(result, length...)
	return append(result, payload...)
}

func encodeLength(length int) []byte {
	var encoded [8]byte
	binary.BigEndian.PutUint64(encoded[:], uint64(length))
	first := 0
	for encoded[first] == 0 {
		first++
	}
	return append([]byte(nil), encoded[first:]...)
}

func decodeFixedHex(value string, size int) []byte {
	if len(value) != 2+size*2 || value[:2] != "0x" {
		panic(fmt.Sprintf("invalid %d-byte fixture hex %q", size, value))
	}
	decoded, err := hex.DecodeString(value[2:])
	if err != nil {
		panic(err)
	}
	return decoded
}

func keccak(value []byte) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(value)
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}
