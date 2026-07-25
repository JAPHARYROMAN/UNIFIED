// Package store provides durable-store semantics used by coordinator workers.
// The memory implementation is a deterministic test double; production
// constructors must inject a SQL implementation.
package store

import (
	"bytes"
	"errors"
	"strconv"
	"sync"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/message"
)

var (
	ErrConflict       = errors.New("compare-and-set conflict")
	ErrImmutableRoute = errors.New("route version is immutable")
	ErrNotFound       = errors.New("record not found")
)

type RouteVersion struct {
	RouteID          string
	Version          uint64
	PolicyHash       [32]byte
	SourceChain      string
	DestinationChain string
	ActivatedAt      time.Time
	DeprecatedAt     *time.Time
}

type MessageRecord struct {
	MessageID [32]byte
	Envelope  []byte
	State     unifiedv1.CrossChainMessageState
	Version   uint64
	Evidence  [32]byte
	UpdatedAt time.Time
}

// OutboxRecord is a deterministic message-state event claimed for publication.
// PublisherID and BrokerOffset are empty, and the timestamp pointers are nil,
// when their corresponding database columns have not yet been assigned.
type OutboxRecord struct {
	OutboxID     string
	MessageID    [32]byte
	StateVersion uint64
	Topic        string
	PartitionKey string
	Payload      []byte
	PayloadHash  [32]byte
	Status       string
	AttemptCount uint32
	PublisherID  string
	LeaseUntil   *time.Time
	CreatedAt    time.Time
	PublishedAt  *time.Time
	BrokerOffset string
}

// InboxRecord is the durable consumer-side deduplication receipt for one
// broker event coordinate.
type InboxRecord struct {
	ConsumerID   string
	MessageID    [32]byte
	Topic        string
	PartitionKey string
	BrokerOffset string
	PayloadHash  [32]byte
	ConsumedAt   time.Time
}

type ProviderAttemptRecord struct {
	MessageID       [32]byte
	ProviderID      string
	AttemptNumber   uint32
	EnvelopeHash    [32]byte
	SourceProofHash [32]byte
	Status          string
	ReceiptHash     [32]byte
	AttemptedAt     time.Time
}

type SourceProofRecord struct {
	ProofID                        string
	MessageID                      [32]byte
	ChainID                        string
	TransactionHash                [32]byte
	TransactionIndex               string
	LogIndex                       string
	BlockNumber                    string
	BlockHash                      [32]byte
	ReceiptsRoot                   [32]byte
	InclusionProofHash             [32]byte
	EventHash                      [32]byte
	FinalityHeadNumber             string
	FinalityHeadHash               [32]byte
	ConfirmationDepth              string
	FinalityPolicyHash             [32]byte
	ObserverAuthorityHash          [32]byte
	ObserverSignedHeaderCommitment [32]byte
	ObserverSignature              []byte
	ProofHash                      [32]byte
	ObservedAt                     time.Time
}

type FinalityCertificateRecord struct {
	CertificateID    string
	MessageID        [32]byte
	ProofID          string
	SignerSetHash    [32]byte
	SignerSetVersion uint64
	SignerBitmap     string
	SignatureCount   uint32
	CertificateHash  [32]byte
	CertifiedAt      time.Time
}

type HeaderObservationRecord struct {
	ObservationID                  string
	ChainID                        string
	BlockHash                      [32]byte
	BlockNumber                    string
	HeaderAuthorityHash            [32]byte
	ObserverSignedHeaderCommitment [32]byte
	ObserverSignature              []byte
	FinalityPolicyHash             [32]byte
	ObservedAt                     time.Time
}

type ReorganizationRequest struct {
	RouteID                   string
	ChainID                   string
	OrphanedProofIDs          []string
	OrphanedCertificateIDs    []string
	ReplacementObservationID  string
	DetectedHeadObservationID string
	AffectedMessageIDs        [][32]byte
	EvidenceHash              [32]byte
	DetectedAt                time.Time
}

type ReorganizationRecord struct {
	ReorganizationID          string
	RouteID                   string
	ChainID                   string
	OrphanedBlockHash         [32]byte
	OrphanedBlockNumber       string
	OrphanedProofID           string
	OrphanedCertificateID     string
	OrphanedProofIDs          []string
	OrphanedCertificateIDs    []string
	ReplacementBlockHash      [32]byte
	ReplacementBlockNumber    string
	ReplacementObservationID  string
	DetectedHeadHash          [32]byte
	DetectedHeadNumber        string
	DetectedHeadObservationID string
	DepthClass                string
	AffectedMessageIDs        [][32]byte
	EvidenceHash              [32]byte
	DetectedAt                time.Time
	IncidentID                string
	IncidentReasonCode        string
	IncidentSeverity          string
	IncidentOwner             string
	IncidentStatus            string
	IncidentOpenedAt          time.Time
}

type Repository interface {
	PutRoute(RouteVersion) error
	Route(string, uint64) (RouteVersion, error)
	CreateMessage(MessageRecord) (MessageRecord, error)
	CompareAndSet([32]byte, uint64, unifiedv1.CrossChainMessageState, bool, [32]byte, time.Time) (MessageRecord, error)
	Message([32]byte) (MessageRecord, error)
}

type Memory struct {
	mu       sync.RWMutex
	routes   map[string]RouteVersion
	messages map[[32]byte]MessageRecord
}

func NewMemory() *Memory {
	return &Memory{
		routes:   make(map[string]RouteVersion),
		messages: make(map[[32]byte]MessageRecord),
	}
}

func (memory *Memory) PutRoute(route RouteVersion) error {
	if route.RouteID == "" || route.Version == 0 || route.SourceChain == "" ||
		route.DestinationChain == "" || route.SourceChain == route.DestinationChain ||
		route.PolicyHash == ([32]byte{}) || route.ActivatedAt.IsZero() ||
		(route.DeprecatedAt != nil && !route.DeprecatedAt.After(route.ActivatedAt)) {
		return errors.New("invalid route version")
	}
	key := routeKey(route.RouteID, route.Version)
	memory.mu.Lock()
	defer memory.mu.Unlock()
	if existing, ok := memory.routes[key]; ok {
		if !sameRoute(existing, route) {
			return ErrImmutableRoute
		}
		return nil
	}
	memory.routes[key] = route
	return nil
}

func (memory *Memory) Route(routeID string, version uint64) (RouteVersion, error) {
	memory.mu.RLock()
	defer memory.mu.RUnlock()
	route, ok := memory.routes[routeKey(routeID, version)]
	if !ok {
		return RouteVersion{}, ErrNotFound
	}
	return route, nil
}

func (memory *Memory) CreateMessage(record MessageRecord) (MessageRecord, error) {
	if len(record.Envelope) == 0 || record.Version != 1 || record.UpdatedAt.IsZero() {
		return MessageRecord{}, errors.New("invalid message record")
	}
	memory.mu.Lock()
	defer memory.mu.Unlock()
	if existing, ok := memory.messages[record.MessageID]; ok {
		if !bytes.Equal(existing.Envelope, record.Envelope) {
			return MessageRecord{}, ErrConflict
		}
		return cloneRecord(existing), nil
	}
	record.Envelope = append([]byte(nil), record.Envelope...)
	memory.messages[record.MessageID] = record
	return cloneRecord(record), nil
}

func (memory *Memory) CompareAndSet(
	messageID [32]byte,
	expectedVersion uint64,
	next unifiedv1.CrossChainMessageState,
	retryable bool,
	evidence [32]byte,
	updatedAt time.Time,
) (MessageRecord, error) {
	memory.mu.Lock()
	defer memory.mu.Unlock()
	current, ok := memory.messages[messageID]
	if !ok {
		return MessageRecord{}, ErrNotFound
	}
	if current.Version != expectedVersion {
		return MessageRecord{}, ErrConflict
	}
	if evidence == ([32]byte{}) || updatedAt.IsZero() || updatedAt.Before(current.UpdatedAt) ||
		!message.CanTransition(current.State, next, retryable) {
		return MessageRecord{}, ErrConflict
	}
	current.Version++
	current.State = next
	current.Evidence = evidence
	current.UpdatedAt = updatedAt
	memory.messages[messageID] = current
	return cloneRecord(current), nil
}

func (memory *Memory) Message(messageID [32]byte) (MessageRecord, error) {
	memory.mu.RLock()
	defer memory.mu.RUnlock()
	current, ok := memory.messages[messageID]
	if !ok {
		return MessageRecord{}, ErrNotFound
	}
	return cloneRecord(current), nil
}

func cloneRecord(source MessageRecord) MessageRecord {
	source.Envelope = append([]byte(nil), source.Envelope...)
	return source
}

func routeKey(routeID string, version uint64) string {
	return routeID + "\x00" + strconv.FormatUint(version, 10)
}

func sameRoute(left, right RouteVersion) bool {
	if left.RouteID != right.RouteID || left.Version != right.Version ||
		left.PolicyHash != right.PolicyHash || left.SourceChain != right.SourceChain ||
		left.DestinationChain != right.DestinationChain ||
		!left.ActivatedAt.Equal(right.ActivatedAt) {
		return false
	}
	if left.DeprecatedAt == nil || right.DeprecatedAt == nil {
		return left.DeprecatedAt == nil && right.DeprecatedAt == nil
	}
	return left.DeprecatedAt.Equal(*right.DeprecatedAt)
}
