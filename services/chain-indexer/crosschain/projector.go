// Package crosschain projects authenticated Phase 8 evidence from multiple
// independently configured chains. It never treats transport delivery as
// finality or execution authority.
package crosschain

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"sort"
	"sync"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/message"
	"golang.org/x/crypto/sha3"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const observerCommitmentDomain = "UNIFIED_OBSERVER_SIGNED_HEADER_V1"

const (
	reorganizationEvidenceDomain = "UNIFIED_XCHAIN_REORGANIZATION_EVIDENCE_V1"
	reorganizationHeaderDomain   = "UNIFIED_XCHAIN_REORGANIZATION_HEADER_V1"
	maxReorganizationMessages    = 256
)

var (
	ErrUnknownChain         = errors.New("unknown chain projection")
	ErrFinalityPolicy       = errors.New("finality policy mismatch")
	ErrProjectionConflict   = errors.New("canonical evidence conflict")
	ErrInsufficientFinality = errors.New("insufficient confirmation depth")
	ErrUnauthenticated      = errors.New("authenticated projection verification failed")
)

type Verification struct {
	CanonicalEvidenceHash [32]byte
	Final                 bool
}

// EvidenceVerifier must be backed by the existing authenticated header,
// transaction/receipt MPT, canonical-log, observer, and threshold-finality
// projection. Projector deliberately has no hash-only fallback.
type EvidenceVerifier interface {
	VerifySource(
		*unifiedv1.CrossChainMessageEnvelope,
		*unifiedv1.CrossChainSourceEventProof,
		*unifiedv1.CrossChainFinalityCertificate,
	) (Verification, error)
	VerifyExecution(
		*unifiedv1.CrossChainExecutionResult,
		*unifiedv1.CrossChainSourceEventProof,
	) (Verification, error)
	VerifyAcknowledgement(*unifiedv1.CrossChainAcknowledgement) (Verification, error)
	VerifyReorganization(
		*unifiedv1.CrossChainReorganizationEvidence,
	) (Verification, error)
}

type ChainConfig struct {
	ChainID            string
	Coordinator        []byte
	ConfigurationHash  [32]byte
	FinalityPolicyHash [32]byte
	ObserverAuthority  [32]byte
	RequiredDepth      uint64
}

type MessageProjection struct {
	MessageID                 [32]byte
	SourceChainID             string
	DestinationChainID        string
	Envelope                  *unifiedv1.CrossChainMessageEnvelope
	SourceProof               *unifiedv1.CrossChainSourceEventProof
	SourceFinalityCertificate *unifiedv1.CrossChainFinalityCertificate
	Execution                 *unifiedv1.CrossChainExecutionResult
	ExecutionProof            *unifiedv1.CrossChainSourceEventProof
	Acknowledgement           *unifiedv1.CrossChainAcknowledgement
	SourceFinal               bool
	SourceEvidenceHash        [32]byte
	ExecutionEvidenceHash     [32]byte
	Disputed                  bool
	Reorganization            *unifiedv1.CrossChainReorganizationEvidence
	Incident                  *unifiedv1.CrossChainIncident
}

type Projector struct {
	mu       sync.RWMutex
	chains   map[string]ChainConfig
	messages map[[32]byte]MessageProjection
	eventIDs map[string][32]byte
	routes   map[[32]byte]string
	verifier EvidenceVerifier
}

func NewProjector(verifier EvidenceVerifier, configs ...ChainConfig) (*Projector, error) {
	if verifier == nil {
		return nil, errors.New("authenticated evidence verifier is required")
	}
	if len(configs) < 2 {
		return nil, errors.New("multi-chain projector requires at least two chains")
	}
	projector := &Projector{
		chains:   make(map[string]ChainConfig, len(configs)),
		messages: make(map[[32]byte]MessageProjection),
		eventIDs: make(map[string][32]byte),
		routes:   make(map[[32]byte]string),
		verifier: verifier,
	}
	for _, config := range configs {
		if config.ChainID == "" || len(config.Coordinator) != 20 ||
			config.ConfigurationHash == ([32]byte{}) ||
			config.FinalityPolicyHash == ([32]byte{}) ||
			config.ObserverAuthority == ([32]byte{}) ||
			config.RequiredDepth == 0 {
			return nil, errors.New("invalid chain configuration")
		}
		if _, exists := projector.chains[config.ChainID]; exists {
			return nil, fmt.Errorf("duplicate chain %s", config.ChainID)
		}
		config.Coordinator = append([]byte(nil), config.Coordinator...)
		projector.chains[config.ChainID] = config
	}
	return projector, nil
}

// BindRoute registers the canonical route identity for a frozen policy hash.
// Reorganization incidents must use this identity verbatim so in-memory and
// SQL restart projections cannot synthesize different route IDs.
func (projector *Projector) BindRoute(routeID string, policyHash [32]byte) error {
	if projector == nil || routeID == "" || policyHash == ([32]byte{}) {
		return ErrProjectionConflict
	}
	projector.mu.Lock()
	defer projector.mu.Unlock()
	if existing, ok := projector.routes[policyHash]; ok && existing != routeID {
		return ErrProjectionConflict
	}
	projector.routes[policyHash] = routeID
	return nil
}

func (projector *Projector) ProjectSource(
	envelope *unifiedv1.CrossChainMessageEnvelope,
	proof *unifiedv1.CrossChainSourceEventProof,
	certificate *unifiedv1.CrossChainFinalityCertificate,
) (MessageProjection, error) {
	if envelope == nil || proof == nil ||
		message.ValidateEnvelope(envelope) != nil ||
		!bytes.Equal(envelope.GetMessageId(), proof.GetMessageId()) ||
		envelope.GetSourceChainId() != proof.GetSourceChainId() {
		return MessageProjection{}, ErrProjectionConflict
	}
	config, ok := projector.chains[proof.GetSourceChainId()]
	if !ok {
		return MessageProjection{}, ErrUnknownChain
	}
	destinationConfig, destinationOK := projector.chains[envelope.GetDestinationChainId()]
	if !destinationOK {
		return MessageProjection{}, ErrUnknownChain
	}
	if !bytes.Equal(config.Coordinator, envelope.GetSourceCoordinator()) ||
		!bytes.Equal(config.Coordinator, proof.GetSourceContract()) ||
		!bytes.Equal(destinationConfig.Coordinator, envelope.GetDestinationCoordinator()) ||
		!bytes.Equal(
			config.FinalityPolicyHash[:],
			envelope.GetSourceFinalityPolicyHash(),
		) ||
		!bytes.Equal(
			destinationConfig.FinalityPolicyHash[:],
			envelope.GetDestinationFinalityPolicyHash(),
		) ||
		!bytes.Equal(config.FinalityPolicyHash[:], proof.GetFinalityPolicyHash()) ||
		!bytes.Equal(config.ObserverAuthority[:], proof.GetHeaderAuthorityHash()) {
		return MessageProjection{}, ErrFinalityPolicy
	}
	if proof.GetRequiredDepth() != config.RequiredDepth ||
		len(proof.GetSourceContract()) != 20 ||
		len(proof.GetSourceBlockHash()) != 32 ||
		len(proof.GetTransactionHash()) != 32 || len(proof.GetReceiptRoot()) != 32 ||
		len(proof.GetReceiptProofHash()) != 32 || len(proof.GetEventHash()) != 32 ||
		len(proof.GetFinalityHeadHash()) != 32 ||
		len(proof.GetObserverSignedHeaderCommitment()) != 32 ||
		len(proof.GetObserverSignature()) == 0 {
		return MessageProjection{}, ErrInsufficientFinality
	}
	expectedCommitment, err := ComputeObserverHeaderCommitment(proof)
	if err != nil ||
		!bytes.Equal(expectedCommitment[:], proof.GetObserverSignedHeaderCommitment()) {
		return MessageProjection{}, ErrUnauthenticated
	}
	verification, err := projector.verifier.VerifySource(envelope, proof, certificate)
	if err != nil || verification.CanonicalEvidenceHash == ([32]byte{}) {
		return MessageProjection{}, ErrUnauthenticated
	}
	if !verification.Final && certificate != nil {
		return MessageProjection{}, ErrUnauthenticated
	}
	if verification.Final && !validSourceFinalityCertificate(
		proof,
		certificate,
	) {
		return MessageProjection{}, ErrUnauthenticated
	}
	if verification.Final && !hasRequiredDepth(
		proof.GetSourceBlockNumber(),
		proof.GetFinalityHeadNumber(),
		config.RequiredDepth,
	) {
		return MessageProjection{}, ErrInsufficientFinality
	}
	var messageID [32]byte
	copy(messageID[:], envelope.GetMessageId())
	eventKey := fmt.Sprintf(
		"%s:%x:%d",
		proof.GetSourceChainId(),
		proof.GetTransactionHash(),
		proof.GetLogIndex(),
	)
	projector.mu.Lock()
	defer projector.mu.Unlock()
	if existingID, exists := projector.eventIDs[eventKey]; exists && existingID != messageID {
		return MessageProjection{}, ErrProjectionConflict
	}
	if existing, exists := projector.messages[messageID]; exists {
		certificateConflict := !proto.Equal(
			existing.SourceFinalityCertificate,
			certificate,
		) && (existing.SourceFinal ||
			existing.SourceFinalityCertificate != nil)
		if !proto.Equal(existing.Envelope, envelope) ||
			!proto.Equal(existing.SourceProof, proof) ||
			certificateConflict ||
			existing.SourceChainID != envelope.GetSourceChainId() ||
			existing.DestinationChainID != envelope.GetDestinationChainId() ||
			existing.SourceEvidenceHash != verification.CanonicalEvidenceHash {
			return MessageProjection{}, ErrProjectionConflict
		}
		if verification.Final && !existing.SourceFinal {
			existing.SourceFinal = true
			existing.SourceFinalityCertificate =
				proto.Clone(certificate).(*unifiedv1.CrossChainFinalityCertificate)
			projector.messages[messageID] = existing
		}
		return cloneProjection(existing), nil
	}
	projection := MessageProjection{
		MessageID:          messageID,
		SourceChainID:      envelope.GetSourceChainId(),
		DestinationChainID: envelope.GetDestinationChainId(),
		Envelope:           proto.Clone(envelope).(*unifiedv1.CrossChainMessageEnvelope),
		SourceProof:        proto.Clone(proof).(*unifiedv1.CrossChainSourceEventProof),
		SourceFinal:        verification.Final,
		SourceEvidenceHash: verification.CanonicalEvidenceHash,
	}
	if verification.Final {
		projection.SourceFinalityCertificate =
			proto.Clone(certificate).(*unifiedv1.CrossChainFinalityCertificate)
	}
	projector.eventIDs[eventKey] = messageID
	projector.messages[messageID] = projection
	return cloneProjection(projection), nil
}

func validSourceFinalityCertificate(
	proof *unifiedv1.CrossChainSourceEventProof,
	certificate *unifiedv1.CrossChainFinalityCertificate,
) bool {
	if proof == nil || certificate == nil ||
		!bytes.Equal(certificate.GetMessageId(), proof.GetMessageId()) ||
		len(certificate.GetSignerSetHash()) != 32 ||
		certificate.GetSignerSetVersion() == 0 ||
		certificate.GetThreshold() < 2 ||
		certificate.GetThreshold() > 3 ||
		len(certificate.GetSignatures()) < int(certificate.GetThreshold()) ||
		len(certificate.GetSignatures()) > 3 ||
		len(certificate.GetCertificateHash()) != 32 ||
		certificate.GetValidFrom() == nil ||
		certificate.GetValidUntil() == nil ||
		!certificate.GetValidUntil().AsTime().After(
			certificate.GetValidFrom().AsTime(),
		) {
		return false
	}
	proofHash, err := ComputeSourceProofHash(proof)
	return err == nil && bytes.Equal(certificate.GetSourceProofHash(), proofHash[:])
}

func (projector *Projector) ProjectExecution(
	result *unifiedv1.CrossChainExecutionResult,
	proof *unifiedv1.CrossChainSourceEventProof,
) (MessageProjection, error) {
	if result == nil || proof == nil || len(result.GetMessageId()) != 32 ||
		!bytes.Equal(result.GetMessageId(), proof.GetMessageId()) ||
		result.GetDestinationChainId() != proof.GetSourceChainId() {
		return MessageProjection{}, ErrProjectionConflict
	}
	config, ok := projector.chains[result.GetDestinationChainId()]
	if !ok {
		return MessageProjection{}, ErrUnknownChain
	}
	if !bytes.Equal(config.Coordinator, proof.GetSourceContract()) ||
		!bytes.Equal(config.FinalityPolicyHash[:], proof.GetFinalityPolicyHash()) ||
		!bytes.Equal(config.ObserverAuthority[:], proof.GetHeaderAuthorityHash()) {
		return MessageProjection{}, ErrFinalityPolicy
	}
	if proof.GetRequiredDepth() != config.RequiredDepth ||
		len(proof.GetSourceContract()) != 20 ||
		len(proof.GetSourceBlockHash()) != 32 ||
		len(proof.GetTransactionHash()) != 32 ||
		len(proof.GetReceiptRoot()) != 32 ||
		len(proof.GetReceiptProofHash()) != 32 ||
		len(proof.GetEventHash()) != 32 ||
		len(proof.GetFinalityHeadHash()) != 32 ||
		len(proof.GetObserverSignedHeaderCommitment()) != 32 ||
		len(proof.GetObserverSignature()) == 0 {
		return MessageProjection{}, ErrUnauthenticated
	}
	expectedCommitment, err := ComputeObserverHeaderCommitment(proof)
	if err != nil ||
		!bytes.Equal(expectedCommitment[:], proof.GetObserverSignedHeaderCommitment()) {
		return MessageProjection{}, ErrUnauthenticated
	}
	if !hasRequiredDepth(
		proof.GetSourceBlockNumber(),
		proof.GetFinalityHeadNumber(),
		config.RequiredDepth,
	) {
		return MessageProjection{}, ErrInsufficientFinality
	}
	var messageID [32]byte
	copy(messageID[:], result.GetMessageId())
	projector.mu.RLock()
	original, exists := projector.messages[messageID]
	projector.mu.RUnlock()
	if !exists || original.Envelope == nil ||
		original.DestinationChainID != result.GetDestinationChainId() ||
		!bytes.Equal(result.GetLaneId(), original.Envelope.GetLaneId()) ||
		result.GetSourceNonce() != original.Envelope.GetSourceNonce() ||
		result.GetActionType() != original.Envelope.GetActionType() ||
		!bytes.Equal(result.GetTarget(), original.Envelope.GetDestinationComponent()) ||
		!bytes.Equal(result.GetTransactionHash(), proof.GetTransactionHash()) ||
		result.GetLogIndex() != proof.GetLogIndex() ||
		len(result.GetLaneId()) != 32 || len(result.GetTarget()) != 20 ||
		len(result.GetResultHash()) != 32 || len(result.GetTransactionHash()) != 32 ||
		result.GetExecutedAt() == nil ||
		result.GetExecutedAt().GetSeconds() < 0 ||
		result.GetExecutedAt().GetNanos() != 0 {
		return MessageProjection{}, ErrProjectionConflict
	}
	verification, err := projector.verifier.VerifyExecution(result, proof)
	if err != nil || !verification.Final ||
		verification.CanonicalEvidenceHash == ([32]byte{}) {
		return MessageProjection{}, ErrUnauthenticated
	}
	eventKey := fmt.Sprintf(
		"%s:%x:%d",
		proof.GetSourceChainId(),
		proof.GetTransactionHash(),
		proof.GetLogIndex(),
	)
	projector.mu.Lock()
	defer projector.mu.Unlock()
	projection, exists := projector.messages[messageID]
	if !exists || !proto.Equal(projection.Envelope, original.Envelope) {
		return MessageProjection{}, ErrProjectionConflict
	}
	if existingID, eventExists := projector.eventIDs[eventKey]; eventExists &&
		existingID != messageID {
		return MessageProjection{}, ErrProjectionConflict
	}
	if projection.Execution != nil && !proto.Equal(projection.Execution, result) {
		return MessageProjection{}, ErrProjectionConflict
	}
	if projection.ExecutionProof != nil && !proto.Equal(projection.ExecutionProof, proof) {
		return MessageProjection{}, ErrProjectionConflict
	}
	if projection.ExecutionEvidenceHash != ([32]byte{}) &&
		projection.ExecutionEvidenceHash != verification.CanonicalEvidenceHash {
		return MessageProjection{}, ErrProjectionConflict
	}
	projection.Execution = proto.Clone(result).(*unifiedv1.CrossChainExecutionResult)
	projection.ExecutionProof =
		proto.Clone(proof).(*unifiedv1.CrossChainSourceEventProof)
	projection.ExecutionEvidenceHash = verification.CanonicalEvidenceHash
	projector.eventIDs[eventKey] = messageID
	projector.messages[messageID] = projection
	return cloneProjection(projection), nil
}

// ComputeObserverHeaderCommitment mirrors
// keccak256(abi.encode("UNIFIED_OBSERVER_SIGNED_HEADER_V1", ...)) in
// CrossChainTypes.observerHeaderCommitment.
func ComputeObserverHeaderCommitment(
	proof *unifiedv1.CrossChainSourceEventProof,
) ([32]byte, error) {
	var zero [32]byte
	if proof == nil || len(proof.GetSourceBlockHash()) != 32 ||
		len(proof.GetFinalityHeadHash()) != 32 ||
		len(proof.GetHeaderAuthorityHash()) != 32 ||
		len(proof.GetFinalityPolicyHash()) != 32 ||
		proof.GetSourceBlockTimestamp() == nil ||
		proof.GetSourceBlockTimestamp().GetSeconds() < 0 ||
		proof.GetSourceBlockTimestamp().GetNanos() != 0 {
		return zero, ErrUnauthenticated
	}
	const argumentCount = 9
	encoded := make([]byte, 0, (argumentCount+2)*32)
	encoded = append(encoded, abiUint64(uint64(argumentCount*32))...)
	encoded = append(encoded, proof.GetSourceBlockHash()...)
	encoded = append(encoded, abiUint64(proof.GetSourceBlockNumber())...)
	encoded = append(encoded, abiUint64(uint64(proof.GetSourceBlockTimestamp().GetSeconds()))...)
	encoded = append(encoded, proof.GetFinalityHeadHash()...)
	encoded = append(encoded, abiUint64(proof.GetFinalityHeadNumber())...)
	encoded = append(encoded, abiUint64(proof.GetRequiredDepth())...)
	encoded = append(encoded, proof.GetHeaderAuthorityHash()...)
	encoded = append(encoded, proof.GetFinalityPolicyHash()...)
	tag := []byte(observerCommitmentDomain)
	encoded = append(encoded, abiUint64(uint64(len(tag)))...)
	encoded = append(encoded, tag...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	hash := sha3.NewLegacyKeccak256()
	_, _ = hash.Write(encoded)
	hash.Sum(zero[:0])
	return zero, nil
}

// ComputeSourceProofHash mirrors keccak256(abi.encode(SourceEventProof)) and
// therefore commits the signed-header commitment before observerSignature.
func ComputeSourceProofHash(
	proof *unifiedv1.CrossChainSourceEventProof,
) ([32]byte, error) {
	var zero [32]byte
	if proof == nil || len(proof.GetSourceBlockHash()) != 32 ||
		len(proof.GetTransactionHash()) != 32 || len(proof.GetReceiptRoot()) != 32 ||
		len(proof.GetReceiptProofHash()) != 32 || len(proof.GetEventHash()) != 32 ||
		len(proof.GetFinalityHeadHash()) != 32 ||
		len(proof.GetHeaderAuthorityHash()) != 32 ||
		len(proof.GetObserverSignedHeaderCommitment()) != 32 ||
		len(proof.GetObserverSignature()) == 0 ||
		len(proof.GetFinalityPolicyHash()) != 32 ||
		proof.GetTransactionIndex() > uint64(^uint32(0)) ||
		proof.GetLogIndex() > uint64(^uint32(0)) ||
		proof.GetSourceBlockTimestamp() == nil ||
		proof.GetSourceBlockTimestamp().GetSeconds() < 0 ||
		proof.GetSourceBlockTimestamp().GetNanos() != 0 {
		return zero, ErrUnauthenticated
	}
	const fieldCount = 16
	signature := proof.GetObserverSignature()
	encoded := make([]byte, 0, (fieldCount+3)*32)
	// The single struct argument is dynamic because it contains bytes.
	encoded = append(encoded, abiUint64(32)...)
	encoded = append(encoded, proof.GetSourceBlockHash()...)
	encoded = append(encoded, abiUint64(proof.GetSourceBlockNumber())...)
	encoded = append(encoded, abiUint64(uint64(proof.GetSourceBlockTimestamp().GetSeconds()))...)
	encoded = append(encoded, proof.GetTransactionHash()...)
	encoded = append(encoded, abiUint64(proof.GetTransactionIndex())...)
	encoded = append(encoded, proof.GetReceiptRoot()...)
	encoded = append(encoded, proof.GetReceiptProofHash()...)
	encoded = append(encoded, abiUint64(proof.GetLogIndex())...)
	encoded = append(encoded, proof.GetEventHash()...)
	encoded = append(encoded, proof.GetFinalityHeadHash()...)
	encoded = append(encoded, abiUint64(proof.GetFinalityHeadNumber())...)
	encoded = append(encoded, abiUint64(proof.GetRequiredDepth())...)
	encoded = append(encoded, proof.GetHeaderAuthorityHash()...)
	encoded = append(encoded, proof.GetObserverSignedHeaderCommitment()...)
	encoded = append(encoded, abiUint64(uint64(fieldCount*32))...)
	encoded = append(encoded, proof.GetFinalityPolicyHash()...)
	encoded = append(encoded, abiUint64(uint64(len(signature)))...)
	encoded = append(encoded, signature...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	hash := sha3.NewLegacyKeccak256()
	_, _ = hash.Write(encoded)
	hash.Sum(zero[:0])
	return zero, nil
}

func abiUint64(value uint64) []byte {
	word := make([]byte, 32)
	binary.BigEndian.PutUint64(word[24:], value)
	return word
}

func hasRequiredDepth(sourceBlock, finalityHead, requiredDepth uint64) bool {
	return requiredDepth != 0 &&
		sourceBlock <= math.MaxUint64-requiredDepth &&
		finalityHead >= sourceBlock+requiredDepth
}

func (projector *Projector) ProjectAcknowledgement(
	acknowledgement *unifiedv1.CrossChainAcknowledgement,
) (MessageProjection, error) {
	if acknowledgement == nil || len(acknowledgement.GetMessageId()) != 32 ||
		acknowledgement.GetDestinationExecutionProof() == nil ||
		acknowledgement.GetFinalityCertificate() == nil {
		return MessageProjection{}, ErrProjectionConflict
	}
	verification, err := projector.verifier.VerifyAcknowledgement(acknowledgement)
	if err != nil || !verification.Final ||
		verification.CanonicalEvidenceHash == ([32]byte{}) {
		return MessageProjection{}, ErrUnauthenticated
	}
	var messageID [32]byte
	copy(messageID[:], acknowledgement.GetMessageId())
	projector.mu.Lock()
	defer projector.mu.Unlock()
	projection, exists := projector.messages[messageID]
	if !exists || projection.Execution == nil ||
		projection.ExecutionProof == nil ||
		!bytes.Equal(acknowledgement.GetExecutionResultHash(), projection.Execution.GetResultHash()) ||
		!proto.Equal(
			acknowledgement.GetDestinationExecutionProof(),
			projection.ExecutionProof,
		) ||
		!bytes.Equal(acknowledgement.GetDestinationExecutionProof().GetMessageId(), messageID[:]) ||
		!bytes.Equal(acknowledgement.GetFinalityCertificate().GetMessageId(), messageID[:]) {
		return MessageProjection{}, ErrProjectionConflict
	}
	if projection.Acknowledgement != nil &&
		!proto.Equal(projection.Acknowledgement, acknowledgement) {
		return MessageProjection{}, ErrProjectionConflict
	}
	projection.Acknowledgement = proto.Clone(acknowledgement).(*unifiedv1.CrossChainAcknowledgement)
	projector.messages[messageID] = projection
	return cloneProjection(projection), nil
}

// ComputeReorganizationEvidenceHash binds the complete, ordered reorganization
// report except its self-referential evidence_hash field.
func ComputeReorganizationEvidenceHash(
	evidence *unifiedv1.CrossChainReorganizationEvidence,
) ([32]byte, error) {
	var zero [32]byte
	if evidence == nil || evidence.GetChainId() == "" ||
		len(evidence.GetOrphanedBlockHash()) != 32 ||
		len(evidence.GetReplacementBlockHash()) != 32 ||
		len(evidence.GetDetectedHeadHash()) != 32 ||
		bytes.Equal(
			evidence.GetOrphanedBlockHash(),
			evidence.GetReplacementBlockHash(),
		) ||
		evidence.GetBlockNumber() == 0 ||
		evidence.GetDetectedHeadNumber() < evidence.GetBlockNumber() ||
		evidence.GetReplacementBlockNumber() != evidence.GetBlockNumber() ||
		len(evidence.GetAffectedMessageIds()) == 0 ||
		len(evidence.GetAffectedMessageIds()) > maxReorganizationMessages ||
		evidence.GetOrphanedSourceProof() == nil ||
		len(evidence.GetOrphanedEventEvidenceHash()) != 32 ||
		len(evidence.GetReplacementHeaderAuthorityHash()) != 32 ||
		len(evidence.GetReplacementObserverSignedHeaderCommitment()) != 32 ||
		len(evidence.GetReplacementObserverSignature()) == 0 ||
		len(evidence.GetDetectedHeadHeaderAuthorityHash()) != 32 ||
		len(evidence.GetDetectedHeadObserverSignedHeaderCommitment()) != 32 ||
		len(evidence.GetDetectedHeadObserverSignature()) == 0 ||
		len(evidence.GetFinalityPolicyHash()) != 32 ||
		evidence.GetOrphanedFinalityCertificate() == nil ||
		len(evidence.GetAffectedOrphanedSourceProofs()) !=
			len(evidence.GetAffectedMessageIds()) ||
		len(evidence.GetAffectedOrphanedEventEvidenceHashes()) !=
			len(evidence.GetAffectedMessageIds()) ||
		len(evidence.GetAffectedOrphanedFinalityCertificates()) !=
			len(evidence.GetAffectedMessageIds()) ||
		evidence.GetDetectedAt() == nil ||
		evidence.GetDetectedAt().GetSeconds() < 0 ||
		evidence.GetDetectedAt().GetNanos() != 0 {
		return zero, ErrProjectionConflict
	}
	var previous []byte
	for _, messageID := range evidence.GetAffectedMessageIds() {
		if len(messageID) != 32 ||
			(previous != nil && bytes.Compare(previous, messageID) >= 0) {
			return zero, ErrProjectionConflict
		}
		previous = messageID
	}
	if !proto.Equal(
		evidence.GetOrphanedSourceProof(),
		evidence.GetAffectedOrphanedSourceProofs()[0],
	) ||
		!bytes.Equal(
			evidence.GetOrphanedEventEvidenceHash(),
			evidence.GetAffectedOrphanedEventEvidenceHashes()[0],
		) ||
		!proto.Equal(
			evidence.GetOrphanedFinalityCertificate(),
			evidence.GetAffectedOrphanedFinalityCertificates()[0],
		) {
		return zero, ErrProjectionConflict
	}
	for index := range evidence.GetAffectedMessageIds() {
		if err := validateReorganizationFact(evidence, index); err != nil {
			return zero, err
		}
	}
	canonical := proto.Clone(evidence).(*unifiedv1.CrossChainReorganizationEvidence)
	canonical.EvidenceHash = nil
	encoded, err := proto.MarshalOptions{Deterministic: true}.Marshal(canonical)
	if err != nil {
		return zero, ErrProjectionConflict
	}
	hash := sha3.NewLegacyKeccak256()
	_, _ = hash.Write([]byte(reorganizationEvidenceDomain))
	_, _ = hash.Write([]byte{0})
	_, _ = hash.Write(encoded)
	hash.Sum(zero[:0])
	return zero, nil
}

// MarshalReorganizationEvidenceBlob creates a content-addressed durable form
// whose Keccak hash is exactly evidence_hash. The self-referential field is
// omitted and the frozen hash domain is prepended.
func MarshalReorganizationEvidenceBlob(
	evidence *unifiedv1.CrossChainReorganizationEvidence,
) ([]byte, [32]byte, error) {
	evidenceHash, err := ComputeReorganizationEvidenceHash(evidence)
	if err != nil ||
		(len(evidence.GetEvidenceHash()) != 0 &&
			!bytes.Equal(evidence.GetEvidenceHash(), evidenceHash[:])) {
		return nil, [32]byte{}, ErrProjectionConflict
	}
	canonical := proto.Clone(evidence).(*unifiedv1.CrossChainReorganizationEvidence)
	canonical.EvidenceHash = nil
	encoded, err := proto.MarshalOptions{Deterministic: true}.Marshal(canonical)
	if err != nil {
		return nil, [32]byte{}, ErrProjectionConflict
	}
	blob := make([]byte, 0, len(reorganizationEvidenceDomain)+1+len(encoded))
	blob = append(blob, []byte(reorganizationEvidenceDomain)...)
	blob = append(blob, 0)
	blob = append(blob, encoded...)
	if keccakDigest(blob) != evidenceHash {
		return nil, [32]byte{}, ErrProjectionConflict
	}
	return blob, evidenceHash, nil
}

// UnmarshalReorganizationEvidenceBlob verifies the content address before
// restoring evidence_hash and re-running every structural validation.
func UnmarshalReorganizationEvidenceBlob(
	blob []byte,
	expectedHash [32]byte,
) (*unifiedv1.CrossChainReorganizationEvidence, error) {
	prefix := append([]byte(reorganizationEvidenceDomain), 0)
	if expectedHash == ([32]byte{}) || !bytes.HasPrefix(blob, prefix) ||
		keccakDigest(blob) != expectedHash {
		return nil, ErrProjectionConflict
	}
	var evidence unifiedv1.CrossChainReorganizationEvidence
	if err := proto.Unmarshal(blob[len(prefix):], &evidence); err != nil ||
		len(evidence.GetEvidenceHash()) != 0 {
		return nil, ErrProjectionConflict
	}
	evidence.EvidenceHash = append([]byte(nil), expectedHash[:]...)
	actual, err := ComputeReorganizationEvidenceHash(&evidence)
	if err != nil || actual != expectedHash {
		return nil, ErrProjectionConflict
	}
	return &evidence, nil
}

func keccakDigest(value []byte) [32]byte {
	hash := sha3.NewLegacyKeccak256()
	_, _ = hash.Write(value)
	var result [32]byte
	hash.Sum(result[:0])
	return result
}

func validateReorganizationFact(
	evidence *unifiedv1.CrossChainReorganizationEvidence,
	index int,
) error {
	if evidence == nil || index < 0 ||
		index >= len(evidence.GetAffectedMessageIds()) ||
		index >= len(evidence.GetAffectedOrphanedSourceProofs()) ||
		index >= len(evidence.GetAffectedOrphanedEventEvidenceHashes()) ||
		index >= len(evidence.GetAffectedOrphanedFinalityCertificates()) {
		return ErrProjectionConflict
	}
	messageID := evidence.GetAffectedMessageIds()[index]
	proof := evidence.GetAffectedOrphanedSourceProofs()[index]
	eventEvidenceHash := evidence.GetAffectedOrphanedEventEvidenceHashes()[index]
	certificate := evidence.GetAffectedOrphanedFinalityCertificates()[index]
	if proof == nil || certificate == nil || len(eventEvidenceHash) != 32 {
		return ErrProjectionConflict
	}
	proofHash, err := ComputeSourceProofHash(proof)
	if err != nil ||
		!bytes.Equal(proof.GetMessageId(), messageID) ||
		proof.GetSourceChainId() != evidence.GetChainId() ||
		proof.GetSourceBlockNumber() != evidence.GetBlockNumber() ||
		!bytes.Equal(proof.GetSourceBlockHash(), evidence.GetOrphanedBlockHash()) ||
		!bytes.Equal(proof.GetFinalityPolicyHash(), evidence.GetFinalityPolicyHash()) ||
		!bytes.Equal(certificate.GetMessageId(), messageID) ||
		!bytes.Equal(certificate.GetSourceProofHash(), proofHash[:]) ||
		len(certificate.GetSignerSetHash()) != 32 ||
		certificate.GetSignerSetVersion() == 0 ||
		certificate.GetThreshold() < 2 ||
		certificate.GetThreshold() > 3 ||
		len(certificate.GetSignatures()) < int(certificate.GetThreshold()) ||
		len(certificate.GetSignatures()) > 3 ||
		len(certificate.GetCertificateHash()) != 32 ||
		certificate.GetValidFrom() == nil ||
		certificate.GetValidUntil() == nil ||
		!certificate.GetValidUntil().AsTime().After(certificate.GetValidFrom().AsTime()) {
		return ErrProjectionConflict
	}
	return nil
}

// ComputeReorganizationHeaderCommitment binds an observer signature to either
// the replacement block or the detected canonical head.
func ComputeReorganizationHeaderCommitment(
	kind string,
	evidence *unifiedv1.CrossChainReorganizationEvidence,
) ([32]byte, error) {
	var zero [32]byte
	if evidence == nil || evidence.GetChainId() == "" ||
		len(evidence.GetFinalityPolicyHash()) != 32 {
		return zero, ErrProjectionConflict
	}
	var (
		blockHash   []byte
		blockNumber uint64
		authority   []byte
	)
	switch kind {
	case "REPLACEMENT":
		blockHash = evidence.GetReplacementBlockHash()
		blockNumber = evidence.GetReplacementBlockNumber()
		authority = evidence.GetReplacementHeaderAuthorityHash()
	case "DETECTED_HEAD":
		blockHash = evidence.GetDetectedHeadHash()
		blockNumber = evidence.GetDetectedHeadNumber()
		authority = evidence.GetDetectedHeadHeaderAuthorityHash()
	default:
		return zero, ErrProjectionConflict
	}
	if len(blockHash) != 32 || blockNumber == 0 || len(authority) != 32 {
		return zero, ErrProjectionConflict
	}
	encoded := make([]byte, 0, 32*9)
	for _, value := range []string{reorganizationHeaderDomain, kind, evidence.GetChainId()} {
		encoded = append(encoded, abiUint64(uint64(len(value)))...)
		encoded = append(encoded, []byte(value)...)
		if remainder := len(encoded) % 32; remainder != 0 {
			encoded = append(encoded, make([]byte, 32-remainder)...)
		}
	}
	encoded = append(encoded, blockHash...)
	encoded = append(encoded, abiUint64(blockNumber)...)
	encoded = append(encoded, evidence.GetDetectedHeadHash()...)
	encoded = append(encoded, abiUint64(evidence.GetDetectedHeadNumber())...)
	encoded = append(encoded, evidence.GetFinalityPolicyHash()...)
	encoded = append(encoded, authority...)
	hash := sha3.NewLegacyKeccak256()
	_, _ = hash.Write(encoded)
	hash.Sum(zero[:0])
	return zero, nil
}

// ProjectReorganization retains finalized facts, marks every affected
// projection disputed, and opens one deterministic incident. Authentication
// remains the EvidenceVerifier's responsibility; there is no hash-only path.
func (projector *Projector) ProjectReorganization(
	evidence *unifiedv1.CrossChainReorganizationEvidence,
) (*unifiedv1.CrossChainIncident, []MessageProjection, error) {
	evidenceHash, err := ComputeReorganizationEvidenceHash(evidence)
	if err != nil || !bytes.Equal(evidence.GetEvidenceHash(), evidenceHash[:]) {
		return nil, nil, ErrProjectionConflict
	}
	config, exists := projector.chains[evidence.GetChainId()]
	if !exists {
		return nil, nil, ErrUnknownChain
	}
	replacementCommitment, replacementErr := ComputeReorganizationHeaderCommitment(
		"REPLACEMENT",
		evidence,
	)
	detectedCommitment, detectedErr := ComputeReorganizationHeaderCommitment(
		"DETECTED_HEAD",
		evidence,
	)
	if replacementErr != nil || detectedErr != nil ||
		!bytes.Equal(
			evidence.GetReplacementObserverSignedHeaderCommitment(),
			replacementCommitment[:],
		) ||
		!bytes.Equal(
			evidence.GetDetectedHeadObserverSignedHeaderCommitment(),
			detectedCommitment[:],
		) ||
		!bytes.Equal(config.FinalityPolicyHash[:], evidence.GetFinalityPolicyHash()) ||
		!bytes.Equal(
			config.ObserverAuthority[:],
			evidence.GetReplacementHeaderAuthorityHash(),
		) ||
		!bytes.Equal(
			config.ObserverAuthority[:],
			evidence.GetDetectedHeadHeaderAuthorityHash(),
		) {
		return nil, nil, ErrFinalityPolicy
	}
	for _, proof := range evidence.GetAffectedOrphanedSourceProofs() {
		orphanCommitment, commitmentErr := ComputeObserverHeaderCommitment(proof)
		if commitmentErr != nil ||
			!bytes.Equal(
				proof.GetObserverSignedHeaderCommitment(),
				orphanCommitment[:],
			) ||
			!bytes.Equal(
				config.FinalityPolicyHash[:],
				proof.GetFinalityPolicyHash(),
			) ||
			!bytes.Equal(
				config.ObserverAuthority[:],
				proof.GetHeaderAuthorityHash(),
			) ||
			proof.GetRequiredDepth() != config.RequiredDepth {
			return nil, nil, ErrFinalityPolicy
		}
	}
	verification, err := projector.verifier.VerifyReorganization(evidence)
	if err != nil || !verification.Final ||
		verification.CanonicalEvidenceHash != evidenceHash {
		return nil, nil, ErrUnauthenticated
	}
	projector.mu.Lock()
	defer projector.mu.Unlock()
	affected := make([]MessageProjection, 0, len(evidence.GetAffectedMessageIds()))
	var routePolicyHash [32]byte
	for index, rawMessageID := range evidence.GetAffectedMessageIds() {
		orphanedProof := evidence.GetAffectedOrphanedSourceProofs()[index]
		orphanedEventEvidenceHash :=
			evidence.GetAffectedOrphanedEventEvidenceHashes()[index]
		var messageID [32]byte
		copy(messageID[:], rawMessageID)
		projection, present := projector.messages[messageID]
		if !present || projection.Envelope == nil {
			return nil, nil, ErrProjectionConflict
		}
		currentPolicy := fixedBytes32(projection.Envelope.GetRoutePolicyHash())
		if index == 0 {
			routePolicyHash = currentPolicy
		} else if currentPolicy != routePolicyHash {
			return nil, nil, ErrProjectionConflict
		}
		if projection.Disputed {
			if !proto.Equal(projection.Reorganization, evidence) {
				return nil, nil, ErrProjectionConflict
			}
			affected = append(affected, cloneProjection(projection))
			continue
		}
		sourceAffected := projection.SourceFinal &&
			projection.SourceChainID == config.ChainID &&
			projection.SourceProof != nil &&
			projection.SourceProof.GetSourceBlockNumber() == evidence.GetBlockNumber() &&
			bytes.Equal(
				projection.SourceProof.GetSourceBlockHash(),
				evidence.GetOrphanedBlockHash(),
			) &&
			proto.Equal(
				projection.SourceProof,
				orphanedProof,
			) &&
			proto.Equal(
				projection.SourceFinalityCertificate,
				evidence.GetAffectedOrphanedFinalityCertificates()[index],
			) &&
			bytes.Equal(
				projection.SourceEvidenceHash[:],
				orphanedEventEvidenceHash,
			)
		executionAffected := projection.DestinationChainID == config.ChainID &&
			projection.Execution != nil &&
			projection.ExecutionProof != nil &&
			projection.ExecutionProof.GetSourceBlockNumber() == evidence.GetBlockNumber() &&
			bytes.Equal(
				projection.ExecutionProof.GetSourceBlockHash(),
				evidence.GetOrphanedBlockHash(),
			) &&
			proto.Equal(
				projection.ExecutionProof,
				orphanedProof,
			) &&
			(projection.Acknowledgement == nil ||
				proto.Equal(
					projection.Acknowledgement.GetFinalityCertificate(),
					evidence.GetAffectedOrphanedFinalityCertificates()[index],
				)) &&
			bytes.Equal(
				projection.ExecutionEvidenceHash[:],
				orphanedEventEvidenceHash,
			)
		if !sourceAffected && !executionAffected {
			return nil, nil, ErrProjectionConflict
		}
	}
	incident := &unifiedv1.CrossChainIncident{
		IncidentId: &unifiedv1.Identifier{
			Value: fmt.Sprintf("crosschain-incident:%x", evidenceHash),
		},
		RouteId: &unifiedv1.Identifier{
			Value: projector.routes[routePolicyHash],
		},
		AffectedMessageIds: cloneByteSlices(evidence.GetAffectedMessageIds()),
		ReasonCode:         "POST_FINALITY_REORGANIZATION",
		Owner:              "cross-chain-security",
		EvidenceHash:       append([]byte(nil), evidenceHash[:]...),
		OpenedAt:           proto.Clone(evidence.GetDetectedAt()).(*timestamppb.Timestamp),
		Status:             "OPEN",
	}
	if incident.GetRouteId().GetValue() == "" {
		return nil, nil, ErrProjectionConflict
	}
	affected = affected[:0]
	for _, rawMessageID := range evidence.GetAffectedMessageIds() {
		var messageID [32]byte
		copy(messageID[:], rawMessageID)
		projection := projector.messages[messageID]
		if !projection.Disputed {
			projection.Disputed = true
			projection.Reorganization =
				proto.Clone(evidence).(*unifiedv1.CrossChainReorganizationEvidence)
			projection.Incident =
				proto.Clone(incident).(*unifiedv1.CrossChainIncident)
			projector.messages[messageID] = projection
		}
		affected = append(affected, cloneProjection(projection))
	}
	return proto.Clone(incident).(*unifiedv1.CrossChainIncident), affected, nil
}

// RemovePreFinality removes only a provisional source fact. Once a source proof
// has reached its configured depth, replacement must be handled as an incident.
func (projector *Projector) RemovePreFinality(chainID string, transactionHash []byte, logIndex uint64) error {
	key := fmt.Sprintf("%s:%x:%d", chainID, transactionHash, logIndex)
	projector.mu.Lock()
	defer projector.mu.Unlock()
	messageID, exists := projector.eventIDs[key]
	if !exists {
		return ErrProjectionConflict
	}
	projection := projector.messages[messageID]
	if projection.SourceFinal {
		return ErrInsufficientFinality
	}
	delete(projector.eventIDs, key)
	delete(projector.messages, messageID)
	return nil
}

func (projector *Projector) Get(messageID [32]byte) (MessageProjection, bool) {
	projector.mu.RLock()
	defer projector.mu.RUnlock()
	projection, ok := projector.messages[messageID]
	return cloneProjection(projection), ok
}

// Snapshot returns a deterministic deep copy suitable for durable persistence.
func (projector *Projector) Snapshot() []MessageProjection {
	projector.mu.RLock()
	defer projector.mu.RUnlock()
	messageIDs := make([][32]byte, 0, len(projector.messages))
	for messageID := range projector.messages {
		messageIDs = append(messageIDs, messageID)
	}
	sort.Slice(messageIDs, func(left, right int) bool {
		return bytes.Compare(messageIDs[left][:], messageIDs[right][:]) < 0
	})
	result := make([]MessageProjection, 0, len(messageIDs))
	for _, messageID := range messageIDs {
		result = append(result, cloneProjection(projector.messages[messageID]))
	}
	return result
}

// RestoreSnapshot replays every authenticated boundary into an empty
// projector before atomically installing the rebuilt state.
func (projector *Projector) RestoreSnapshot(snapshot []MessageProjection) error {
	if projector == nil || projector.verifier == nil {
		return ErrProjectionConflict
	}
	projector.mu.RLock()
	configs := make([]ChainConfig, 0, len(projector.chains))
	for _, config := range projector.chains {
		configs = append(configs, config)
	}
	routes := make(map[[32]byte]string, len(projector.routes))
	for policyHash, routeID := range projector.routes {
		routes[policyHash] = routeID
	}
	occupied := len(projector.messages) != 0 || len(projector.eventIDs) != 0
	projector.mu.RUnlock()
	if occupied {
		return ErrProjectionConflict
	}
	sort.Slice(configs, func(left, right int) bool {
		return configs[left].ChainID < configs[right].ChainID
	})
	rebuilt, err := NewProjector(projector.verifier, configs...)
	if err != nil {
		return err
	}
	policyHashes := make([][32]byte, 0, len(routes))
	for policyHash := range routes {
		policyHashes = append(policyHashes, policyHash)
	}
	sort.Slice(policyHashes, func(left, right int) bool {
		return bytes.Compare(policyHashes[left][:], policyHashes[right][:]) < 0
	})
	for _, policyHash := range policyHashes {
		if err := rebuilt.BindRoute(routes[policyHash], policyHash); err != nil {
			return ErrProjectionConflict
		}
	}
	for _, expected := range snapshot {
		actual, projectErr := rebuilt.ProjectSource(
			expected.Envelope,
			expected.SourceProof,
			expected.SourceFinalityCertificate,
		)
		if projectErr != nil || actual.SourceFinal != expected.SourceFinal ||
			actual.SourceEvidenceHash != expected.SourceEvidenceHash {
			return ErrProjectionConflict
		}
	}
	for _, expected := range snapshot {
		if expected.Execution == nil {
			continue
		}
		actual, projectErr := rebuilt.ProjectExecution(
			expected.Execution,
			expected.ExecutionProof,
		)
		if projectErr != nil ||
			actual.ExecutionEvidenceHash != expected.ExecutionEvidenceHash {
			return ErrProjectionConflict
		}
	}
	for _, expected := range snapshot {
		if expected.Acknowledgement == nil {
			continue
		}
		if _, projectErr := rebuilt.ProjectAcknowledgement(
			expected.Acknowledgement,
		); projectErr != nil {
			return ErrProjectionConflict
		}
	}
	reorganizations := make(map[[32]byte]*unifiedv1.CrossChainReorganizationEvidence)
	for _, expected := range snapshot {
		if !expected.Disputed || expected.Reorganization == nil ||
			expected.Incident == nil {
			if expected.Disputed || expected.Reorganization != nil ||
				expected.Incident != nil {
				return ErrProjectionConflict
			}
			continue
		}
		hash := fixedBytes32(expected.Reorganization.GetEvidenceHash())
		if hash == ([32]byte{}) {
			return ErrProjectionConflict
		}
		if existing, found := reorganizations[hash]; found &&
			!proto.Equal(existing, expected.Reorganization) {
			return ErrProjectionConflict
		}
		reorganizations[hash] = expected.Reorganization
	}
	reorganizationHashes := make([][32]byte, 0, len(reorganizations))
	for hash := range reorganizations {
		reorganizationHashes = append(reorganizationHashes, hash)
	}
	sort.Slice(reorganizationHashes, func(left, right int) bool {
		return bytes.Compare(
			reorganizationHashes[left][:],
			reorganizationHashes[right][:],
		) < 0
	})
	for _, hash := range reorganizationHashes {
		if _, _, projectErr := rebuilt.ProjectReorganization(
			reorganizations[hash],
		); projectErr != nil {
			return ErrProjectionConflict
		}
	}
	for _, expected := range snapshot {
		actual, found := rebuilt.Get(expected.MessageID)
		if !found || !sameProjection(actual, expected) {
			return ErrProjectionConflict
		}
	}
	projector.mu.Lock()
	defer projector.mu.Unlock()
	if len(projector.messages) != 0 || len(projector.eventIDs) != 0 ||
		!sameRouteBindings(projector.routes, routes) {
		return ErrProjectionConflict
	}
	projector.messages = rebuilt.messages
	projector.eventIDs = rebuilt.eventIDs
	projector.routes = rebuilt.routes
	return nil
}

func sameRouteBindings(left, right map[[32]byte]string) bool {
	if len(left) != len(right) {
		return false
	}
	for policyHash, routeID := range left {
		if right[policyHash] != routeID {
			return false
		}
	}
	return true
}

func cloneProjection(source MessageProjection) MessageProjection {
	if source.Envelope != nil {
		source.Envelope =
			proto.Clone(source.Envelope).(*unifiedv1.CrossChainMessageEnvelope)
	}
	if source.SourceProof != nil {
		source.SourceProof = proto.Clone(source.SourceProof).(*unifiedv1.CrossChainSourceEventProof)
	}
	if source.SourceFinalityCertificate != nil {
		source.SourceFinalityCertificate = proto.Clone(
			source.SourceFinalityCertificate,
		).(*unifiedv1.CrossChainFinalityCertificate)
	}
	if source.Execution != nil {
		source.Execution = proto.Clone(source.Execution).(*unifiedv1.CrossChainExecutionResult)
	}
	if source.ExecutionProof != nil {
		source.ExecutionProof =
			proto.Clone(source.ExecutionProof).(*unifiedv1.CrossChainSourceEventProof)
	}
	if source.Acknowledgement != nil {
		source.Acknowledgement = proto.Clone(source.Acknowledgement).(*unifiedv1.CrossChainAcknowledgement)
	}
	if source.Reorganization != nil {
		source.Reorganization =
			proto.Clone(source.Reorganization).(*unifiedv1.CrossChainReorganizationEvidence)
	}
	if source.Incident != nil {
		source.Incident = proto.Clone(source.Incident).(*unifiedv1.CrossChainIncident)
	}
	return source
}

func sameProjection(left, right MessageProjection) bool {
	return left.MessageID == right.MessageID &&
		left.SourceChainID == right.SourceChainID &&
		left.DestinationChainID == right.DestinationChainID &&
		left.SourceFinal == right.SourceFinal &&
		left.SourceEvidenceHash == right.SourceEvidenceHash &&
		left.ExecutionEvidenceHash == right.ExecutionEvidenceHash &&
		left.Disputed == right.Disputed &&
		proto.Equal(left.Envelope, right.Envelope) &&
		proto.Equal(left.SourceProof, right.SourceProof) &&
		proto.Equal(
			left.SourceFinalityCertificate,
			right.SourceFinalityCertificate,
		) &&
		proto.Equal(left.Execution, right.Execution) &&
		proto.Equal(left.ExecutionProof, right.ExecutionProof) &&
		proto.Equal(left.Acknowledgement, right.Acknowledgement) &&
		proto.Equal(left.Reorganization, right.Reorganization) &&
		proto.Equal(left.Incident, right.Incident)
}

func cloneByteSlices(source [][]byte) [][]byte {
	result := make([][]byte, len(source))
	for index := range source {
		result[index] = append([]byte(nil), source[index]...)
	}
	return result
}

func fixedBytes32(source []byte) (result [32]byte) {
	if len(source) == len(result) {
		copy(result[:], source)
	}
	return result
}
