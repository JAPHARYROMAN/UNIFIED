package projection

import (
	"bytes"
	"crypto/ed25519"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"math"
	"sort"
	"time"
)

var (
	ErrInvalidHeaderEvidence = errors.New("invalid authenticated EVM header evidence")
	ErrInvalidInclusionProof = errors.New("invalid EVM trie inclusion proof")
)

const (
	maxHeaderRLPBytes   = 64 << 10
	maxTransactionBytes = 1 << 20
	maxReceiptBytes     = 4 << 20
	maxProofNodeBytes   = 1 << 20
	maxProofNodes       = 64
	maxProofBytes       = 8 << 20
	maxReceiptsPerBlock = 4096
	maxBlockProofBytes  = 32 << 20
	maxBlockInputBytes  = 64 << 20
	maxReceiptLogs      = 4096
	maxLogTopics        = 16
	maxRLPDepth         = 64
	maxRLPListItems     = 1 << 16
)

// AuthenticatedBlock is the gateway indexer's only chain-ingestion boundary.
// HeaderRLP is the exact EVM header encoding authenticated by the configured
// header authority. Every supplied transaction and receipt must be proven at
// the same transaction index under that header's transaction and receipt roots.
type AuthenticatedBlock struct {
	HeaderRLP  []byte
	ObservedAt time.Time
	Signature  []byte
	Receipts   []ReceiptInclusionProof
}

type ReceiptInclusionProof struct {
	TransactionIndex      uint64
	TransactionRLP        []byte
	TransactionProofNodes [][]byte
	ReceiptRLP            []byte
	ReceiptProofNodes     [][]byte
}

type evmHeader struct {
	number           uint64
	hash             string
	parentHash       string
	transactionsRoot string
	receiptsRoot     string
	timestamp        uint64
}

type verifiedReceipt struct {
	TransactionHash     string
	ReceiptPayloadHash  string
	Status              TransactionReceiptStatus
	TransactionIndex    uint64
	BlockNumber         uint64
	BlockHash           string
	ReceiptsRoot        string
	InclusionProofHash  string
	HeaderSignatureHash string
}

// ComputeFinalityPolicyHash binds a consumer to one authenticated header
// authority for one chain, gateway, and confirmation-depth policy.
func ComputeFinalityPolicyHash(
	chainID uint64,
	gateway string,
	finalityDepth uint64,
	headerAuthority ed25519.PublicKey,
) (string, error) {
	gatewayBytes, gatewayOK := decodeCanonicalHex(gateway, 20)
	if chainID == 0 || !gatewayOK || finalityDepth == 0 ||
		len(headerAuthority) != ed25519.PublicKeySize {
		return "", ErrInvalidIndexerConfig
	}
	input := append([]byte(nil), []byte("UNIFIED_EVM_FINALITY_POLICY_V1\x00")...)
	var scalar [8]byte
	binary.BigEndian.PutUint64(scalar[:], chainID)
	input = append(input, scalar[:]...)
	input = append(input, gatewayBytes...)
	binary.BigEndian.PutUint64(scalar[:], finalityDepth)
	input = append(input, scalar[:]...)
	input = append(input, headerAuthority...)
	hash := keccak(input)
	return hex32(hash[:]), nil
}

type receiptLog struct {
	address string
	topics  []string
	data    []byte
}

type rlpValue struct {
	raw     []byte
	payload []byte
	list    []rlpValue
	isList  bool
}

// AuthenticatedHeaderSigningDigest is the domain-separated digest signed by a
// pinned header authority. The signature authenticates the chain domain,
// observed time, and the Keccak hash of the exact raw EVM header.
func AuthenticatedHeaderSigningDigest(
	chainID uint64,
	headerRLP []byte,
	observedAt time.Time,
) ([32]byte, error) {
	if chainID == 0 || observedAt.IsZero() || observedAt.UnixNano() <= 0 ||
		len(headerRLP) == 0 || len(headerRLP) > maxHeaderRLPBytes {
		return [32]byte{}, ErrInvalidHeaderEvidence
	}
	if _, err := parseEVMHeader(headerRLP); err != nil {
		return [32]byte{}, err
	}
	headerHash := keccak(headerRLP)
	input := make([]byte, 0, 42+8+8+32)
	input = append(input, []byte("UNIFIED_EVM_HEADER_AUTHORITY_V1\x00")...)
	var scalar [8]byte
	binary.BigEndian.PutUint64(scalar[:], chainID)
	input = append(input, scalar[:]...)
	binary.BigEndian.PutUint64(scalar[:], uint64(observedAt.UTC().UnixNano()))
	input = append(input, scalar[:]...)
	input = append(input, headerHash[:]...)
	return keccak(input), nil
}

func verifyAuthenticatedBlock(
	chainID uint64,
	gateway string,
	authority ed25519.PublicKey,
	block AuthenticatedBlock,
) (evmHeader, []verifiedReceipt, []Event, error) {
	if len(authority) != ed25519.PublicKeySize ||
		len(block.Signature) != ed25519.SignatureSize ||
		block.ObservedAt.IsZero() || block.ObservedAt.UnixNano() <= 0 ||
		len(block.HeaderRLP) == 0 || len(block.HeaderRLP) > maxHeaderRLPBytes ||
		!validAuthenticatedBlockSize(block) {
		return evmHeader{}, nil, nil, ErrInvalidHeaderEvidence
	}
	header, err := parseEVMHeader(block.HeaderRLP)
	if err != nil {
		return evmHeader{}, nil, nil, err
	}
	if block.ObservedAt.Unix() < int64(header.timestamp) {
		return evmHeader{}, nil, nil, ErrInvalidHeaderEvidence
	}
	digest, err := AuthenticatedHeaderSigningDigest(chainID, block.HeaderRLP, block.ObservedAt)
	if err != nil || !ed25519.Verify(authority, digest[:], block.Signature) {
		return evmHeader{}, nil, nil, ErrInvalidHeaderEvidence
	}

	proofs := append([]ReceiptInclusionProof(nil), block.Receipts...)
	signatureHash := keccak(block.Signature)
	sort.Slice(proofs, func(left, right int) bool {
		return proofs[left].TransactionIndex < proofs[right].TransactionIndex
	})
	receipts := make([]verifiedReceipt, 0, len(proofs))
	events := make([]Event, 0)
	var globalLogIndex uint64
	for position, proof := range proofs {
		// A prefix-complete receipt set makes the block-global log indexes derived
		// facts. A caller cannot omit preceding receipts and choose a log index.
		if proof.TransactionIndex != uint64(position) ||
			len(proof.TransactionRLP) == 0 ||
			len(proof.TransactionRLP) > maxTransactionBytes ||
			len(proof.ReceiptRLP) == 0 ||
			len(proof.ReceiptRLP) > maxReceiptBytes ||
			!validProofSize(proof.TransactionProofNodes) ||
			!validProofSize(proof.ReceiptProofNodes) {
			return evmHeader{}, nil, nil, ErrInvalidInclusionProof
		}
		key := rlpEncodeUint(proof.TransactionIndex)
		transactionRoot, _ := decodeCanonicalHex(header.transactionsRoot, 32)
		receiptsRoot, _ := decodeCanonicalHex(header.receiptsRoot, 32)
		if !verifyTrieInclusion(
			transactionRoot,
			key,
			proof.TransactionRLP,
			proof.TransactionProofNodes,
		) ||
			!verifyTrieInclusion(
				receiptsRoot,
				key,
				proof.ReceiptRLP,
				proof.ReceiptProofNodes,
			) {
			return evmHeader{}, nil, nil, ErrInvalidInclusionProof
		}
		status, logs, err := decodeReceipt(proof.ReceiptRLP)
		if err != nil {
			return evmHeader{}, nil, nil, ErrInvalidInclusionProof
		}
		transactionHash := keccak(proof.TransactionRLP)
		receiptHash := keccak(proof.ReceiptRLP)
		proofHash := receiptInclusionProofHash(header, proof)
		record := verifiedReceipt{
			TransactionHash:     hex32(transactionHash[:]),
			ReceiptPayloadHash:  hex32(receiptHash[:]),
			Status:              status,
			TransactionIndex:    proof.TransactionIndex,
			BlockNumber:         header.number,
			BlockHash:           header.hash,
			ReceiptsRoot:        header.receiptsRoot,
			InclusionProofHash:  proofHash,
			HeaderSignatureHash: hex32(signatureHash[:]),
		}
		receipts = append(receipts, record)
		for _, log := range logs {
			if globalLogIndex > math.MaxUint32 {
				return evmHeader{}, nil, nil, ErrInvalidInclusionProof
			}
			if status == TransactionSucceeded && log.address == "" {
				return evmHeader{}, nil, nil, ErrInvalidInclusionProof
			}
			if status == TransactionSucceeded && log.address == gateway &&
				len(log.topics) > 0 &&
				log.topics[0] == CanonicalSettlementTopic() {
				event, decodeErr := decodeCanonicalSettlementLog(
					RawLog{
						ChainID:         chainID,
						ContractAddress: log.address,
						Topics:          log.topics,
						Data:            log.data,
						TransactionHash: record.TransactionHash,
						LogIndex:        uint32(globalLogIndex),
						BlockNumber:     header.number,
						BlockHash:       header.hash,
					},
					proof.TransactionIndex,
					header.receiptsRoot,
					proofHash,
					true,
				)
				if decodeErr != nil {
					return evmHeader{}, nil, nil, ErrInvalidInclusionProof
				}
				event.ReceiptHeaderSignatureHash = record.HeaderSignatureHash
				events = append(events, event)
			}
			globalLogIndex++
		}
	}
	return header, receipts, events, nil
}

func parseEVMHeader(encoded []byte) (evmHeader, error) {
	if len(encoded) == 0 || len(encoded) > maxHeaderRLPBytes {
		return evmHeader{}, ErrInvalidHeaderEvidence
	}
	value, consumed, err := decodeRLP(encoded)
	if err != nil || consumed != len(encoded) || !value.isList || len(value.list) < 12 {
		return evmHeader{}, ErrInvalidHeaderEvidence
	}
	parent := value.list[0]
	transactionsRoot := value.list[4]
	receiptsRoot := value.list[5]
	number := value.list[8]
	timestamp := value.list[11]
	if parent.isList || transactionsRoot.isList || receiptsRoot.isList ||
		number.isList || timestamp.isList ||
		len(parent.payload) != 32 || len(transactionsRoot.payload) != 32 ||
		len(receiptsRoot.payload) != 32 {
		return evmHeader{}, ErrInvalidHeaderEvidence
	}
	blockNumber, ok := rlpUint64(number.payload)
	if !ok || blockNumber == 0 {
		return evmHeader{}, ErrInvalidHeaderEvidence
	}
	blockTimestamp, ok := rlpUint64(timestamp.payload)
	if !ok || blockTimestamp == 0 {
		return evmHeader{}, ErrInvalidHeaderEvidence
	}
	hash := keccak(encoded)
	return evmHeader{
		number:           blockNumber,
		hash:             hex32(hash[:]),
		parentHash:       hex32(parent.payload),
		transactionsRoot: hex32(transactionsRoot.payload),
		receiptsRoot:     hex32(receiptsRoot.payload),
		timestamp:        blockTimestamp,
	}, nil
}

func decodeReceipt(encoded []byte) (
	TransactionReceiptStatus,
	[]receiptLog,
	error,
) {
	payload := encoded
	if len(payload) == 0 {
		return "", nil, ErrInvalidInclusionProof
	}
	// EIP-2718 typed receipts prefix the RLP payload with one byte in [1, 0x7f].
	if payload[0] > 0 && payload[0] < 0x80 {
		payload = payload[1:]
	}
	value, consumed, err := decodeRLP(payload)
	if err != nil || consumed != len(payload) || !value.isList || len(value.list) != 4 {
		return "", nil, ErrInvalidInclusionProof
	}
	statusField := value.list[0]
	if statusField.isList {
		return "", nil, ErrInvalidInclusionProof
	}
	cumulativeGasUsed := value.list[1]
	bloom := value.list[2]
	if cumulativeGasUsed.isList {
		return "", nil, ErrInvalidInclusionProof
	}
	if _, ok := rlpUint64(cumulativeGasUsed.payload); !ok {
		return "", nil, ErrInvalidInclusionProof
	}
	if bloom.isList || len(bloom.payload) != 256 {
		return "", nil, ErrInvalidInclusionProof
	}
	var status TransactionReceiptStatus
	switch {
	case len(statusField.payload) == 0:
		status = TransactionReverted
	case len(statusField.payload) == 1 && statusField.payload[0] == 1:
		status = TransactionSucceeded
	default:
		// Pre-Byzantium state-root receipts are intentionally outside this
		// boundary because they do not contain an explicit success bit.
		return "", nil, ErrInvalidInclusionProof
	}
	logsField := value.list[3]
	if !logsField.isList || len(logsField.list) > maxReceiptLogs {
		return "", nil, ErrInvalidInclusionProof
	}
	logs := make([]receiptLog, 0, len(logsField.list))
	if status == TransactionReverted && len(logsField.list) != 0 {
		return "", nil, ErrInvalidInclusionProof
	}
	for _, encodedLog := range logsField.list {
		if !encodedLog.isList || len(encodedLog.list) != 3 {
			return "", nil, ErrInvalidInclusionProof
		}
		address := encodedLog.list[0]
		topics := encodedLog.list[1]
		data := encodedLog.list[2]
		if address.isList || len(address.payload) != 20 || !topics.isList ||
			len(topics.list) > maxLogTopics || data.isList ||
			len(data.payload) > maxReceiptBytes {
			return "", nil, ErrInvalidInclusionProof
		}
		decodedTopics := make([]string, 0, len(topics.list))
		for _, topic := range topics.list {
			if topic.isList || len(topic.payload) != 32 {
				return "", nil, ErrInvalidInclusionProof
			}
			decodedTopics = append(decodedTopics, hex32(topic.payload))
		}
		logs = append(logs, receiptLog{
			address: "0x" + hex.EncodeToString(address.payload),
			topics:  decodedTopics,
			data:    append([]byte(nil), data.payload...),
		})
	}
	return status, logs, nil
}

func receiptInclusionProofHash(header evmHeader, proof ReceiptInclusionProof) string {
	input := make([]byte, 0)
	input = append(input, []byte("UNIFIED_EVM_TRANSACTION_RECEIPT_INCLUSION_V1\x00")...)
	input = appendLengthPrefixed(input, []byte(header.hash))
	var scalar [8]byte
	binary.BigEndian.PutUint64(scalar[:], proof.TransactionIndex)
	input = append(input, scalar[:]...)
	input = appendLengthPrefixed(input, proof.TransactionRLP)
	for _, node := range proof.TransactionProofNodes {
		input = appendLengthPrefixed(input, node)
	}
	input = appendLengthPrefixed(input, proof.ReceiptRLP)
	for _, node := range proof.ReceiptProofNodes {
		input = appendLengthPrefixed(input, node)
	}
	hash := keccak(input)
	return hex32(hash[:])
}

func appendLengthPrefixed(target, value []byte) []byte {
	var length [8]byte
	binary.BigEndian.PutUint64(length[:], uint64(len(value)))
	target = append(target, length[:]...)
	return append(target, value...)
}

func verifyTrieInclusion(root, key, expected []byte, proof [][]byte) bool {
	if len(root) != 32 || !validProofSize(proof) {
		return false
	}
	keyNibbles := bytesToNibbles(key)
	reference := append([]byte(nil), root...)
	position := 0
	for proofIndex, encodedNode := range proof {
		if !matchesTrieReference(reference, encodedNode) {
			return false
		}
		node, consumed, err := decodeRLP(encodedNode)
		if err != nil || consumed != len(encodedNode) || !node.isList {
			return false
		}
		switch len(node.list) {
		case 17:
			if position == len(keyNibbles) {
				value := node.list[16]
				return proofIndex == len(proof)-1 && !value.isList &&
					bytes.Equal(value.payload, expected)
			}
			child, ok := trieReference(node.list[keyNibbles[position]])
			if !ok {
				return false
			}
			position++
			reference = child
		case 2:
			pathField := node.list[0]
			if pathField.isList {
				return false
			}
			path, leaf, ok := decodeCompactPath(pathField.payload)
			if !ok || len(keyNibbles)-position < len(path) ||
				!bytes.Equal(keyNibbles[position:position+len(path)], path) {
				return false
			}
			position += len(path)
			if leaf {
				value := node.list[1]
				return position == len(keyNibbles) &&
					proofIndex == len(proof)-1 &&
					!value.isList && bytes.Equal(value.payload, expected)
			}
			child, ok := trieReference(node.list[1])
			if !ok {
				return false
			}
			reference = child
		default:
			return false
		}
	}
	return false
}

func validProofSize(proof [][]byte) bool {
	if len(proof) == 0 || len(proof) > maxProofNodes {
		return false
	}
	total := 0
	for _, node := range proof {
		if len(node) == 0 || len(node) > maxProofNodeBytes {
			return false
		}
		total += len(node)
		if total > maxProofBytes {
			return false
		}
	}
	return true
}

func validAuthenticatedBlockSize(block AuthenticatedBlock) bool {
	if len(block.Receipts) > maxReceiptsPerBlock {
		return false
	}
	inputBytes := 0
	proofBytes := 0
	if !addWithinLimit(&inputBytes, len(block.HeaderRLP), maxBlockInputBytes) ||
		!addWithinLimit(&inputBytes, len(block.Signature), maxBlockInputBytes) {
		return false
	}
	for _, receipt := range block.Receipts {
		if !addWithinLimit(&inputBytes, len(receipt.TransactionRLP), maxBlockInputBytes) ||
			!addWithinLimit(&inputBytes, len(receipt.ReceiptRLP), maxBlockInputBytes) {
			return false
		}
		for _, proof := range [][][]byte{
			receipt.TransactionProofNodes,
			receipt.ReceiptProofNodes,
		} {
			for _, node := range proof {
				if !addWithinLimit(&proofBytes, len(node), maxBlockProofBytes) ||
					!addWithinLimit(&inputBytes, len(node), maxBlockInputBytes) {
					return false
				}
			}
		}
	}
	return true
}

func addWithinLimit(total *int, value, limit int) bool {
	if value < 0 || *total > limit || value > limit-*total {
		return false
	}
	*total += value
	return true
}

func matchesTrieReference(reference, encodedNode []byte) bool {
	if len(reference) == 32 {
		hash := keccak(encodedNode)
		return bytes.Equal(reference, hash[:])
	}
	return len(reference) > 0 && len(reference) < 32 &&
		bytes.Equal(reference, encodedNode)
}

func trieReference(value rlpValue) ([]byte, bool) {
	if value.isList {
		if len(value.raw) >= 32 {
			return nil, false
		}
		return append([]byte(nil), value.raw...), true
	}
	// Ethereum's MPT encodes an embedded child as an RLP list. A string child
	// is valid only when it is the 32-byte Keccak hash of another node.
	if len(value.payload) != 32 {
		return nil, false
	}
	return append([]byte(nil), value.payload...), true
}

func decodeCompactPath(encoded []byte) ([]byte, bool, bool) {
	nibbles := bytesToNibbles(encoded)
	if len(nibbles) == 0 || nibbles[0] > 3 {
		return nil, false, false
	}
	leaf := nibbles[0] >= 2
	odd := nibbles[0]%2 == 1
	offset := 2
	if odd {
		offset = 1
	} else if len(nibbles) < 2 || nibbles[1] != 0 {
		return nil, false, false
	}
	return append([]byte(nil), nibbles[offset:]...), leaf, true
}

func bytesToNibbles(value []byte) []byte {
	result := make([]byte, 0, len(value)*2)
	for _, item := range value {
		result = append(result, item>>4, item&0x0f)
	}
	return result
}

func rlpEncodeUint(value uint64) []byte {
	if value == 0 {
		return []byte{0x80}
	}
	var encoded [8]byte
	binary.BigEndian.PutUint64(encoded[:], value)
	first := 0
	for encoded[first] == 0 {
		first++
	}
	payload := encoded[first:]
	if len(payload) == 1 && payload[0] < 0x80 {
		return append([]byte(nil), payload...)
	}
	return append([]byte{0x80 + byte(len(payload))}, payload...)
}

func rlpUint64(payload []byte) (uint64, bool) {
	if len(payload) > 8 || (len(payload) > 0 && payload[0] == 0) {
		return 0, false
	}
	var result uint64
	for _, value := range payload {
		result = result<<8 | uint64(value)
	}
	return result, true
}

func decodeRLP(input []byte) (rlpValue, int, error) {
	return decodeRLPDepth(input, 0)
}

func decodeRLPDepth(input []byte, depth int) (rlpValue, int, error) {
	if depth > maxRLPDepth {
		return rlpValue{}, 0, ErrInvalidInclusionProof
	}
	if len(input) == 0 {
		return rlpValue{}, 0, ErrInvalidInclusionProof
	}
	prefix := input[0]
	switch {
	case prefix <= 0x7f:
		return rlpValue{
			raw:     append([]byte(nil), input[:1]...),
			payload: append([]byte(nil), input[:1]...),
		}, 1, nil
	case prefix <= 0xb7:
		length := int(prefix - 0x80)
		if len(input) < 1+length ||
			(length == 1 && input[1] < 0x80) {
			return rlpValue{}, 0, ErrInvalidInclusionProof
		}
		return rlpValue{
			raw:     append([]byte(nil), input[:1+length]...),
			payload: append([]byte(nil), input[1:1+length]...),
		}, 1 + length, nil
	case prefix <= 0xbf:
		lengthOfLength := int(prefix - 0xb7)
		length, ok := decodeRLPLength(input, lengthOfLength)
		offset := 1 + lengthOfLength
		if !ok || length < 56 || offset > len(input) ||
			length > len(input)-offset {
			return rlpValue{}, 0, ErrInvalidInclusionProof
		}
		return rlpValue{
			raw:     append([]byte(nil), input[:offset+length]...),
			payload: append([]byte(nil), input[offset:offset+length]...),
		}, offset + length, nil
	case prefix <= 0xf7:
		length := int(prefix - 0xc0)
		return decodeRLPList(input, 1, length, depth)
	default:
		lengthOfLength := int(prefix - 0xf7)
		length, ok := decodeRLPLength(input, lengthOfLength)
		offset := 1 + lengthOfLength
		if !ok || length < 56 || offset > len(input) ||
			length > len(input)-offset {
			return rlpValue{}, 0, ErrInvalidInclusionProof
		}
		return decodeRLPList(input, offset, length, depth)
	}
}

func decodeRLPLength(input []byte, lengthOfLength int) (int, bool) {
	if lengthOfLength == 0 || lengthOfLength > 8 ||
		len(input) < 1+lengthOfLength || input[1] == 0 {
		return 0, false
	}
	var length uint64
	for _, value := range input[1 : 1+lengthOfLength] {
		length = length<<8 | uint64(value)
	}
	if length > uint64(math.MaxInt) {
		return 0, false
	}
	return int(length), true
}

func decodeRLPList(input []byte, offset, length, depth int) (rlpValue, int, error) {
	if offset < 0 || length < 0 || offset > len(input) ||
		length > len(input)-offset {
		return rlpValue{}, 0, ErrInvalidInclusionProof
	}
	items := make([]rlpValue, 0)
	position := offset
	end := offset + length
	for position < end {
		if len(items) >= maxRLPListItems {
			return rlpValue{}, 0, ErrInvalidInclusionProof
		}
		item, consumed, err := decodeRLPDepth(input[position:end], depth+1)
		if err != nil || consumed == 0 || position+consumed > end {
			return rlpValue{}, 0, ErrInvalidInclusionProof
		}
		items = append(items, item)
		position += consumed
	}
	if position != end {
		return rlpValue{}, 0, ErrInvalidInclusionProof
	}
	return rlpValue{
		raw:    append([]byte(nil), input[:end]...),
		list:   items,
		isList: true,
	}, end, nil
}

func decodeCanonicalHex(value string, size int) ([]byte, bool) {
	if !canonicalHex(value, size) {
		return nil, false
	}
	decoded, err := hex.DecodeString(value[2:])
	return decoded, err == nil
}
