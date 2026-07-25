package crosschain

import (
	"bytes"
	"errors"
	"fmt"
	"math"
	"sort"
	"testing"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/message"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type strictVerifier struct {
	sourceFinal bool
}

func bindObserverCommitment(t *testing.T, proof *unifiedv1.CrossChainSourceEventProof) {
	t.Helper()
	commitment, err := ComputeObserverHeaderCommitment(proof)
	if err != nil {
		t.Fatalf("observer commitment: %v", err)
	}
	proof.ObserverSignedHeaderCommitment = append([]byte(nil), commitment[:]...)
}

func (verifier *strictVerifier) VerifySource(
	_ *unifiedv1.CrossChainMessageEnvelope,
	proof *unifiedv1.CrossChainSourceEventProof,
	certificate *unifiedv1.CrossChainFinalityCertificate,
) (Verification, error) {
	if !bytes.Equal(proof.GetObserverSignature(), []byte("signed")) ||
		len(proof.GetReceiptProofHash()) != 32 || proof.GetReceiptProofHash()[0] == 0xff ||
		len(proof.GetObserverSignedHeaderCommitment()) != 32 ||
		proof.GetObserverSignedHeaderCommitment()[0] == 0xff {
		return Verification{}, ErrUnauthenticated
	}
	proofHash, err := ComputeSourceProofHash(proof)
	if err != nil {
		return Verification{}, err
	}
	if verifier.sourceFinal {
		if certificate == nil ||
			!bytes.Equal(certificate.GetMessageId(), proof.GetMessageId()) ||
			!bytes.Equal(certificate.GetSourceProofHash(), proofHash[:]) ||
			len(certificate.GetSignatures()) != 2 ||
			!bytes.Equal(certificate.GetSignatures()[0], []byte("signer-a")) ||
			!bytes.Equal(certificate.GetSignatures()[1], []byte("signer-b")) {
			return Verification{}, ErrUnauthenticated
		}
	}
	return Verification{CanonicalEvidenceHash: proofHash, Final: verifier.sourceFinal}, nil
}

func sourceFinalityFixture(
	t *testing.T,
	proof *unifiedv1.CrossChainSourceEventProof,
) *unifiedv1.CrossChainFinalityCertificate {
	t.Helper()
	proofHash, err := ComputeSourceProofHash(proof)
	if err != nil {
		t.Fatal(err)
	}
	return &unifiedv1.CrossChainFinalityCertificate{
		MessageId:        append([]byte(nil), proof.GetMessageId()...),
		SourceProofHash:  append([]byte(nil), proofHash[:]...),
		SignerSetHash:    bytes.Repeat([]byte{0x91}, 32),
		SignerSetVersion: 1,
		Threshold:        2,
		Signatures:       [][]byte{[]byte("signer-a"), []byte("signer-b")},
		ValidFrom:        timestamppb.New(time.Unix(1_699_999_900, 0).UTC()),
		ValidUntil:       timestamppb.New(time.Unix(1_700_003_600, 0).UTC()),
		CertificateHash:  bytes.Repeat([]byte{0x92}, 32),
	}
}

func (verifier *strictVerifier) VerifyExecution(
	_ *unifiedv1.CrossChainExecutionResult,
	proof *unifiedv1.CrossChainSourceEventProof,
) (Verification, error) {
	if !bytes.Equal(proof.GetObserverSignature(), []byte("signed")) ||
		len(proof.GetReceiptProofHash()) != 32 || proof.GetReceiptProofHash()[0] == 0xff ||
		len(proof.GetObserverSignedHeaderCommitment()) != 32 ||
		proof.GetObserverSignedHeaderCommitment()[0] == 0xff {
		return Verification{}, ErrUnauthenticated
	}
	proofHash, err := ComputeSourceProofHash(proof)
	if err != nil {
		return Verification{}, err
	}
	return Verification{CanonicalEvidenceHash: proofHash, Final: true}, nil
}

func (verifier *strictVerifier) VerifyAcknowledgement(
	acknowledgement *unifiedv1.CrossChainAcknowledgement,
) (Verification, error) {
	if len(acknowledgement.GetFinalityCertificate().GetSignatures()) < 2 {
		return Verification{}, ErrUnauthenticated
	}
	return Verification{CanonicalEvidenceHash: [32]byte{0xa3}, Final: true}, nil
}

func (verifier *strictVerifier) VerifyReorganization(
	evidence *unifiedv1.CrossChainReorganizationEvidence,
) (Verification, error) {
	if !bytes.Equal(
		evidence.GetReplacementObserverSignature(),
		[]byte("replacement-signed"),
	) ||
		!bytes.Equal(
			evidence.GetDetectedHeadObserverSignature(),
			[]byte("detected-head-signed"),
		) {
		return Verification{}, ErrUnauthenticated
	}
	for index, proof := range evidence.GetAffectedOrphanedSourceProofs() {
		if !bytes.Equal(proof.GetObserverSignature(), []byte("signed")) ||
			index >= len(evidence.GetAffectedOrphanedFinalityCertificates()) ||
			len(evidence.GetAffectedOrphanedFinalityCertificates()[index].
				GetSignatures()) < 2 {
			return Verification{}, ErrUnauthenticated
		}
	}
	hash, err := ComputeReorganizationEvidenceHash(evidence)
	if err != nil {
		return Verification{}, err
	}
	return Verification{CanonicalEvidenceHash: hash, Final: true}, nil
}

func projectorFixture(t *testing.T) (*Projector, *unifiedv1.CrossChainMessageEnvelope, *unifiedv1.CrossChainSourceEventProof) {
	t.Helper()
	homePolicy := [32]byte{1}
	satellitePolicy := [32]byte{2}
	homeObserver := [32]byte{3}
	satelliteObserver := [32]byte{4}
	projector, err := NewProjector(
		&strictVerifier{sourceFinal: true},
		ChainConfig{
			ChainID: "31337", Coordinator: bytes.Repeat([]byte{0x11}, 20),
			ConfigurationHash: [32]byte{5}, FinalityPolicyHash: homePolicy,
			ObserverAuthority: homeObserver, RequiredDepth: 2,
		},
		ChainConfig{
			ChainID: "31338", Coordinator: bytes.Repeat([]byte{0x22}, 20),
			ConfigurationHash: [32]byte{6}, FinalityPolicyHash: satellitePolicy,
			ObserverAuthority: satelliteObserver, RequiredDepth: 2,
		},
	)
	if err != nil {
		t.Fatalf("projector: %v", err)
	}
	if err := projector.BindRoute(
		"route-home-satellite-v1",
		fixedBytes32(bytes.Repeat([]byte{0x51}, 32)),
	); err != nil {
		t.Fatalf("bind route: %v", err)
	}
	envelope := &unifiedv1.CrossChainMessageEnvelope{
		SchemaVersion:          1,
		ProtocolId:             bytes.Repeat([]byte{0x01}, 32),
		SourceChainId:          "31337",
		SourceCoordinator:      bytes.Repeat([]byte{0x11}, 20),
		SourceComponent:        bytes.Repeat([]byte{0x12}, 20),
		DestinationChainId:     "31338",
		DestinationCoordinator: bytes.Repeat([]byte{0x22}, 20),
		DestinationComponent:   bytes.Repeat([]byte{0x23}, 20),
		LaneId:                 bytes.Repeat([]byte{0x31}, 32),
		SourceNonce:            1,
		AggregateId:            bytes.Repeat([]byte{0x32}, 32),
		ActionType:             unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_CanonicalUftLock{
			CanonicalUftLock: &unifiedv1.CanonicalUftLockPayload{
				LockId:               bytes.Repeat([]byte{0x41}, 32),
				LoanId:               bytes.Repeat([]byte{0x42}, 32),
				CanonicalToken:       bytes.Repeat([]byte{0x43}, 20),
				HomeBridgeHub:        bytes.Repeat([]byte{0x44}, 20),
				WrappedToken:         bytes.Repeat([]byte{0x45}, 20),
				DestinationRecipient: bytes.Repeat([]byte{0x46}, 20),
				Amount:               "1",
			},
		},
		CreatedAt:                     timestamppb.New(time.Unix(1_700_000_000, 0).UTC()),
		ExpiresAt:                     timestamppb.New(time.Unix(1_700_003_600, 0).UTC()),
		RoutePolicyHash:               bytes.Repeat([]byte{0x51}, 32),
		AdapterSetPolicyHash:          bytes.Repeat([]byte{0x52}, 32),
		SourceFinalityPolicyHash:      homePolicy[:],
		DestinationFinalityPolicyHash: satellitePolicy[:],
		CorrelationId:                 bytes.Repeat([]byte{0x53}, 32),
		CausationMessageId:            make([]byte, 32),
		SupersededMessageId:           make([]byte, 32),
	}
	if err := message.BindTypedActionABI(envelope); err != nil {
		t.Fatalf("bind action: %v", err)
	}
	envelope, err = message.Seal(envelope)
	if err != nil {
		t.Fatalf("seal envelope: %v", err)
	}
	proof := &unifiedv1.CrossChainSourceEventProof{
		MessageId: envelope.MessageId, SourceChainId: "31337",
		SourceContract:  bytes.Repeat([]byte{0x11}, 20),
		SourceBlockHash: bytes.Repeat([]byte{1}, 32), SourceBlockNumber: 10,
		SourceBlockTimestamp: timestamppb.New(time.Unix(1_700_000_000, 0).UTC()),
		TransactionHash:      bytes.Repeat([]byte{2}, 32), TransactionIndex: 0,
		ReceiptRoot:      bytes.Repeat([]byte{3}, 32),
		ReceiptProofHash: bytes.Repeat([]byte{4}, 32), LogIndex: 1,
		EventHash:        bytes.Repeat([]byte{5}, 32),
		FinalityHeadHash: bytes.Repeat([]byte{6}, 32), FinalityHeadNumber: 12,
		RequiredDepth: 2, HeaderAuthorityHash: homeObserver[:],
		ObserverSignature: []byte("signed"), FinalityPolicyHash: homePolicy[:],
	}
	bindObserverCommitment(t, proof)
	return projector, envelope, proof
}

func TestProjectsTwoDomainFinalityAndAcknowledgement(t *testing.T) {
	projector, envelope, proof := projectorFixture(t)
	if _, err := projector.ProjectSource(envelope, proof, nil); !errors.Is(
		err,
		ErrUnauthenticated,
	) {
		t.Fatalf("source finalized without threshold certificate: %v", err)
	}
	forgedCertificate := sourceFinalityFixture(t, proof)
	forgedCertificate.Signatures[0] = []byte("forged")
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		forgedCertificate,
	); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("forged source finality certificate accepted: %v", err)
	}
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); err != nil {
		t.Fatalf("source: %v", err)
	}
	satellitePolicy := [32]byte{2}
	satelliteObserver := [32]byte{4}
	destinationProof := &unifiedv1.CrossChainSourceEventProof{
		MessageId: envelope.MessageId, SourceChainId: "31338",
		SourceContract:  bytes.Repeat([]byte{0x22}, 20),
		SourceBlockHash: bytes.Repeat([]byte{7}, 32), SourceBlockNumber: 20,
		SourceBlockTimestamp: timestamppb.New(time.Unix(1_700_000_100, 0).UTC()),
		TransactionHash:      bytes.Repeat([]byte{8}, 32), ReceiptRoot: bytes.Repeat([]byte{9}, 32),
		ReceiptProofHash: bytes.Repeat([]byte{10}, 32), EventHash: bytes.Repeat([]byte{11}, 32),
		FinalityHeadHash: bytes.Repeat([]byte{12}, 32), FinalityHeadNumber: 22,
		RequiredDepth: 2, HeaderAuthorityHash: satelliteObserver[:],
		ObserverSignature: []byte("signed"), FinalityPolicyHash: satellitePolicy[:],
	}
	bindObserverCommitment(t, destinationProof)
	resultHash := bytes.Repeat([]byte{0xbb}, 32)
	result := &unifiedv1.CrossChainExecutionResult{
		MessageId: envelope.MessageId, LaneId: envelope.LaneId,
		SourceNonce: envelope.SourceNonce, ActionType: envelope.ActionType,
		Target: envelope.DestinationComponent, ResultHash: resultHash,
		DestinationChainId: "31338", TransactionHash: destinationProof.TransactionHash,
		LogIndex:   destinationProof.LogIndex,
		ExecutedAt: timestamppb.New(time.Unix(1_700_000_100, 0).UTC()),
	}
	if _, err := projector.ProjectExecution(result, destinationProof); err != nil {
		t.Fatalf("execution: %v", err)
	}
	ack := &unifiedv1.CrossChainAcknowledgement{
		MessageId: envelope.MessageId, ExecutionResultHash: resultHash,
		DestinationExecutionProof: destinationProof,
		FinalityCertificate: &unifiedv1.CrossChainFinalityCertificate{
			MessageId: envelope.MessageId, CertificateHash: bytes.Repeat([]byte{0xcc}, 32),
			Signatures: [][]byte{[]byte("signer-a"), []byte("signer-b")},
		},
	}
	projection, err := projector.ProjectAcknowledgement(ack)
	if err != nil || projection.Acknowledgement == nil {
		t.Fatalf("acknowledgement: %#v err=%v", projection, err)
	}
}

func TestRejectsAlternateFinalityAuthority(t *testing.T) {
	projector, envelope, proof := projectorFixture(t)
	proof.HeaderAuthorityHash = bytes.Repeat([]byte{0xff}, 32)
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); !errors.Is(err, ErrFinalityPolicy) {
		t.Fatalf("expected finality policy rejection, got %v", err)
	}
}

func TestFinalityDepthCannotOverflowOrSubstitutePolicyDepth(t *testing.T) {
	projector, envelope, proof := projectorFixture(t)
	proof.SourceBlockNumber = math.MaxUint64
	proof.FinalityHeadNumber = 1
	bindObserverCommitment(t, proof)
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); !errors.Is(
		err,
		ErrInsufficientFinality,
	) {
		t.Fatalf("expected overflowing source depth rejection, got %v", err)
	}

	projector, envelope, proof = projectorFixture(t)
	proof.RequiredDepth = 1
	bindObserverCommitment(t, proof)
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); !errors.Is(
		err,
		ErrInsufficientFinality,
	) {
		t.Fatalf("expected policy-depth substitution rejection, got %v", err)
	}
}

func TestObserverHeaderCommitmentGolden(t *testing.T) {
	_, _, proof := projectorFixture(t)
	commitment, err := ComputeObserverHeaderCommitment(proof)
	if err != nil {
		t.Fatalf("commitment: %v", err)
	}
	const expected = "3258e807eeaa73eb0528906779f67b50526e4e2a8084106bbb8961a7ccf39346"
	if actual := fmt.Sprintf("%x", commitment); actual != expected {
		t.Fatalf("observer commitment changed: got %s want %s", actual, expected)
	}
}

func TestSourceProofHashGoldenCommitsObserverHeader(t *testing.T) {
	_, _, proof := projectorFixture(t)
	proofHash, err := ComputeSourceProofHash(proof)
	if err != nil {
		t.Fatalf("proof hash: %v", err)
	}
	const expected = "46a47903dd0e88dc3534cd332f184337976768e77cc83bc61197808591b12f40"
	if actual := fmt.Sprintf("%x", proofHash); actual != expected {
		t.Fatalf("source proof hash changed: got %s want %s", actual, expected)
	}
	changed := append([]byte(nil), proof.ObserverSignedHeaderCommitment...)
	changed[0] ^= 0xff
	proof.ObserverSignedHeaderCommitment = changed
	changedHash, err := ComputeSourceProofHash(proof)
	if err != nil {
		t.Fatalf("changed proof hash: %v", err)
	}
	if changedHash == proofHash {
		t.Fatal("source proof hash omitted observer signed-header commitment")
	}
}

func TestRejectsForgedReceiptProofAndInsufficientThreshold(t *testing.T) {
	projector, envelope, proof := projectorFixture(t)
	proof.ReceiptProofHash = bytes.Repeat([]byte{0xff}, 32)
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("expected forged proof rejection, got %v", err)
	}

	projector, envelope, proof = projectorFixture(t)
	proof.ObserverSignedHeaderCommitment = bytes.Repeat([]byte{0xff}, 32)
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("expected forged signed-header commitment rejection, got %v", err)
	}

	projector, envelope, proof = projectorFixture(t)
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); err != nil {
		t.Fatalf("source: %v", err)
	}
	satellitePolicy := [32]byte{2}
	satelliteObserver := [32]byte{4}
	destinationProof := &unifiedv1.CrossChainSourceEventProof{
		MessageId: envelope.MessageId, SourceChainId: "31338",
		SourceContract:    bytes.Repeat([]byte{0x22}, 20),
		SourceBlockNumber: 20, FinalityHeadNumber: 22, RequiredDepth: 2,
		SourceBlockHash:      bytes.Repeat([]byte{7}, 32),
		SourceBlockTimestamp: timestamppb.New(time.Unix(1_700_000_100, 0).UTC()),
		FinalityHeadHash:     bytes.Repeat([]byte{12}, 32),
		TransactionHash:      bytes.Repeat([]byte{8}, 32),
		ReceiptRoot:          bytes.Repeat([]byte{9}, 32),
		ReceiptProofHash:     bytes.Repeat([]byte{1}, 32),
		EventHash:            bytes.Repeat([]byte{11}, 32),
		ObserverSignature:    []byte("signed"),
		FinalityPolicyHash:   satellitePolicy[:], HeaderAuthorityHash: satelliteObserver[:],
	}
	bindObserverCommitment(t, destinationProof)
	resultHash := bytes.Repeat([]byte{2}, 32)
	if _, err := projector.ProjectExecution(&unifiedv1.CrossChainExecutionResult{
		MessageId: envelope.MessageId, LaneId: envelope.LaneId,
		SourceNonce: envelope.SourceNonce, ActionType: envelope.ActionType,
		Target: envelope.DestinationComponent, DestinationChainId: "31338",
		ResultHash: resultHash, TransactionHash: destinationProof.TransactionHash,
		LogIndex:   destinationProof.LogIndex,
		ExecutedAt: timestamppb.New(time.Unix(1_700_000_100, 0).UTC()),
	}, destinationProof); err != nil {
		t.Fatalf("execution: %v", err)
	}
	ack := &unifiedv1.CrossChainAcknowledgement{
		MessageId: envelope.MessageId, ExecutionResultHash: resultHash,
		DestinationExecutionProof: destinationProof,
		FinalityCertificate: &unifiedv1.CrossChainFinalityCertificate{
			MessageId: envelope.MessageId, Signatures: [][]byte{[]byte("only-one")},
		},
	}
	if _, err := projector.ProjectAcknowledgement(ack); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("expected insufficient threshold rejection, got %v", err)
	}
}

func destinationExecutionFixture(
	t *testing.T,
	envelope *unifiedv1.CrossChainMessageEnvelope,
) (*unifiedv1.CrossChainExecutionResult, *unifiedv1.CrossChainSourceEventProof) {
	t.Helper()
	satelliteObserver := [32]byte{4}
	satellitePolicy := [32]byte{2}
	proof := &unifiedv1.CrossChainSourceEventProof{
		MessageId:            append([]byte(nil), envelope.GetMessageId()...),
		SourceChainId:        envelope.GetDestinationChainId(),
		SourceContract:       append([]byte(nil), envelope.GetDestinationCoordinator()...),
		SourceBlockHash:      bytes.Repeat([]byte{0x71}, 32),
		SourceBlockNumber:    20,
		SourceBlockTimestamp: timestamppb.New(time.Unix(1_700_000_100, 0).UTC()),
		TransactionHash:      bytes.Repeat([]byte{0x72}, 32),
		TransactionIndex:     2,
		ReceiptRoot:          bytes.Repeat([]byte{0x73}, 32),
		ReceiptProofHash:     bytes.Repeat([]byte{0x74}, 32),
		LogIndex:             3,
		EventHash:            bytes.Repeat([]byte{0x75}, 32),
		FinalityHeadHash:     bytes.Repeat([]byte{0x76}, 32),
		FinalityHeadNumber:   22,
		RequiredDepth:        2,
		HeaderAuthorityHash:  satelliteObserver[:],
		ObserverSignature:    []byte("signed"),
		FinalityPolicyHash:   satellitePolicy[:],
	}
	bindObserverCommitment(t, proof)
	return &unifiedv1.CrossChainExecutionResult{
		MessageId:          append([]byte(nil), envelope.GetMessageId()...),
		LaneId:             append([]byte(nil), envelope.GetLaneId()...),
		SourceNonce:        envelope.GetSourceNonce(),
		ActionType:         envelope.GetActionType(),
		Target:             append([]byte(nil), envelope.GetDestinationComponent()...),
		ResultHash:         bytes.Repeat([]byte{0x77}, 32),
		DestinationChainId: envelope.GetDestinationChainId(),
		TransactionHash:    append([]byte(nil), proof.GetTransactionHash()...),
		LogIndex:           proof.GetLogIndex(),
		ExecutedAt:         timestamppb.New(time.Unix(1_700_000_101, 0).UTC()),
	}, proof
}

func rebindReorganizationEvidence(
	t *testing.T,
	evidence *unifiedv1.CrossChainReorganizationEvidence,
) {
	t.Helper()
	for index, proof := range evidence.GetAffectedOrphanedSourceProofs() {
		orphanCommitment, err := ComputeObserverHeaderCommitment(proof)
		if err != nil {
			t.Fatal(err)
		}
		proof.ObserverSignedHeaderCommitment = orphanCommitment[:]
		proofHash, err := ComputeSourceProofHash(proof)
		if err != nil {
			t.Fatal(err)
		}
		evidence.AffectedOrphanedFinalityCertificates[index].SourceProofHash =
			proofHash[:]
	}
	evidence.OrphanedSourceProof = proto.Clone(
		evidence.GetAffectedOrphanedSourceProofs()[0],
	).(*unifiedv1.CrossChainSourceEventProof)
	evidence.OrphanedEventEvidenceHash = append(
		[]byte(nil),
		evidence.GetAffectedOrphanedEventEvidenceHashes()[0]...,
	)
	evidence.OrphanedFinalityCertificate = proto.Clone(
		evidence.GetAffectedOrphanedFinalityCertificates()[0],
	).(*unifiedv1.CrossChainFinalityCertificate)
	replacement, err := ComputeReorganizationHeaderCommitment("REPLACEMENT", evidence)
	if err != nil {
		t.Fatal(err)
	}
	evidence.ReplacementObserverSignedHeaderCommitment = replacement[:]
	detected, err := ComputeReorganizationHeaderCommitment("DETECTED_HEAD", evidence)
	if err != nil {
		t.Fatal(err)
	}
	evidence.DetectedHeadObserverSignedHeaderCommitment = detected[:]
	hash, err := ComputeReorganizationEvidenceHash(evidence)
	if err != nil {
		t.Fatal(err)
	}
	evidence.EvidenceHash = hash[:]
}

func TestRejectsCanonicalEnvelopeAndExecutionSubstitution(t *testing.T) {
	projector, envelope, proof := projectorFixture(t)
	changedPayload := proto.Clone(envelope).(*unifiedv1.CrossChainMessageEnvelope)
	changedPayload.GetCanonicalUftLock().Amount = "2"
	if _, err := projector.ProjectSource(
		changedPayload,
		proof,
		sourceFinalityFixture(t, proof),
	); !errors.Is(
		err,
		ErrProjectionConflict,
	) {
		t.Fatalf("typed payload substitution accepted: %v", err)
	}

	changedCoordinator := proto.Clone(envelope).(*unifiedv1.CrossChainMessageEnvelope)
	changedCoordinator.DestinationCoordinator = bytes.Repeat([]byte{0x24}, 20)
	changedCoordinator.MessageId = nil
	changedCoordinator, err := message.Seal(changedCoordinator)
	if err != nil {
		t.Fatal(err)
	}
	changedProof := proto.Clone(proof).(*unifiedv1.CrossChainSourceEventProof)
	changedProof.MessageId = append([]byte(nil), changedCoordinator.GetMessageId()...)
	if _, err := projector.ProjectSource(
		changedCoordinator,
		changedProof,
		sourceFinalityFixture(t, changedProof),
	); !errors.Is(
		err,
		ErrFinalityPolicy,
	) {
		t.Fatalf("destination coordinator substitution accepted: %v", err)
	}

	if _, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	); err != nil {
		t.Fatalf("source: %v", err)
	}
	result, destinationProof := destinationExecutionFixture(t, envelope)
	mutations := map[string]func(
		*unifiedv1.CrossChainExecutionResult,
		*unifiedv1.CrossChainSourceEventProof,
	){
		"destination-coordinator": func(
			_ *unifiedv1.CrossChainExecutionResult,
			value *unifiedv1.CrossChainSourceEventProof,
		) {
			value.SourceContract = bytes.Repeat([]byte{0x24}, 20)
		},
		"target": func(
			value *unifiedv1.CrossChainExecutionResult,
			_ *unifiedv1.CrossChainSourceEventProof,
		) {
			value.Target = bytes.Repeat([]byte{0x25}, 20)
		},
		"lane": func(
			value *unifiedv1.CrossChainExecutionResult,
			_ *unifiedv1.CrossChainSourceEventProof,
		) {
			value.LaneId = bytes.Repeat([]byte{0x26}, 32)
		},
		"nonce": func(
			value *unifiedv1.CrossChainExecutionResult,
			_ *unifiedv1.CrossChainSourceEventProof,
		) {
			value.SourceNonce++
		},
		"action": func(
			value *unifiedv1.CrossChainExecutionResult,
			_ *unifiedv1.CrossChainSourceEventProof,
		) {
			value.ActionType =
				unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_WRAPPED_UFT_MINTED_V1
		},
		"transaction": func(
			value *unifiedv1.CrossChainExecutionResult,
			_ *unifiedv1.CrossChainSourceEventProof,
		) {
			value.TransactionHash = bytes.Repeat([]byte{0x27}, 32)
		},
		"log-index": func(
			value *unifiedv1.CrossChainExecutionResult,
			_ *unifiedv1.CrossChainSourceEventProof,
		) {
			value.LogIndex++
		},
	}
	for name, mutate := range mutations {
		changedResult :=
			proto.Clone(result).(*unifiedv1.CrossChainExecutionResult)
		changedDestinationProof :=
			proto.Clone(destinationProof).(*unifiedv1.CrossChainSourceEventProof)
		mutate(changedResult, changedDestinationProof)
		if _, err := projector.ProjectExecution(
			changedResult,
			changedDestinationProof,
		); !errors.Is(err, ErrProjectionConflict) &&
			!errors.Is(err, ErrFinalityPolicy) {
			t.Fatalf("%s substitution accepted: %v", name, err)
		}
	}
	if _, err := projector.ProjectExecution(result, destinationProof); err != nil {
		t.Fatalf("valid execution after substitutions: %v", err)
	}
}

func TestAuthenticatedFinalizedReorganizationOpensDurableIncident(t *testing.T) {
	projector, envelope, proof := projectorFixture(t)
	sourceProjection, err := projector.ProjectSource(
		envelope,
		proof,
		sourceFinalityFixture(t, proof),
	)
	if err != nil {
		t.Fatalf("source: %v", err)
	}
	proofHash, err := ComputeSourceProofHash(proof)
	if err != nil {
		t.Fatal(err)
	}
	homeAuthority := [32]byte{3}
	homePolicy := [32]byte{1}
	evidence := &unifiedv1.CrossChainReorganizationEvidence{
		ChainId:                envelope.GetSourceChainId(),
		OrphanedBlockHash:      append([]byte(nil), proof.GetSourceBlockHash()...),
		ReplacementBlockHash:   bytes.Repeat([]byte{0x81}, 32),
		DetectedHeadHash:       bytes.Repeat([]byte{0x82}, 32),
		BlockNumber:            proof.GetSourceBlockNumber(),
		ReplacementBlockNumber: proof.GetSourceBlockNumber(),
		DetectedHeadNumber:     proof.GetFinalityHeadNumber() + 1,
		AffectedMessageIds:     [][]byte{append([]byte(nil), envelope.GetMessageId()...)},
		DetectedAt:             timestamppb.New(time.Unix(1_700_000_200, 0).UTC()),
		OrphanedSourceProof:    proto.Clone(proof).(*unifiedv1.CrossChainSourceEventProof),
		OrphanedEventEvidenceHash: append(
			[]byte(nil),
			sourceProjection.SourceEvidenceHash[:]...,
		),
		ReplacementHeaderAuthorityHash:  append([]byte(nil), homeAuthority[:]...),
		ReplacementObserverSignature:    []byte("replacement-signed"),
		DetectedHeadHeaderAuthorityHash: append([]byte(nil), homeAuthority[:]...),
		DetectedHeadObserverSignature:   []byte("detected-head-signed"),
		FinalityPolicyHash:              append([]byte(nil), homePolicy[:]...),
		OrphanedFinalityCertificate: &unifiedv1.CrossChainFinalityCertificate{
			MessageId:        append([]byte(nil), envelope.GetMessageId()...),
			SourceProofHash:  append([]byte(nil), proofHash[:]...),
			SignerSetHash:    bytes.Repeat([]byte{0x91}, 32),
			SignerSetVersion: 1,
			Threshold:        2,
			Signatures:       [][]byte{[]byte("signer-a"), []byte("signer-b")},
			ValidFrom:        timestamppb.New(time.Unix(1_699_999_900, 0).UTC()),
			ValidUntil:       timestamppb.New(time.Unix(1_700_003_600, 0).UTC()),
			CertificateHash:  bytes.Repeat([]byte{0x92}, 32),
		},
	}
	evidence.AffectedOrphanedSourceProofs = []*unifiedv1.CrossChainSourceEventProof{
		proto.Clone(evidence.GetOrphanedSourceProof()).(*unifiedv1.CrossChainSourceEventProof),
	}
	evidence.AffectedOrphanedEventEvidenceHashes = [][]byte{
		append([]byte(nil), evidence.GetOrphanedEventEvidenceHash()...),
	}
	evidence.AffectedOrphanedFinalityCertificates =
		[]*unifiedv1.CrossChainFinalityCertificate{
			proto.Clone(evidence.GetOrphanedFinalityCertificate()).(*unifiedv1.CrossChainFinalityCertificate),
		}
	replacementCommitment, err := ComputeReorganizationHeaderCommitment(
		"REPLACEMENT",
		evidence,
	)
	if err != nil {
		t.Fatal(err)
	}
	evidence.ReplacementObserverSignedHeaderCommitment = replacementCommitment[:]
	detectedCommitment, err := ComputeReorganizationHeaderCommitment(
		"DETECTED_HEAD",
		evidence,
	)
	if err != nil {
		t.Fatal(err)
	}
	evidence.DetectedHeadObserverSignedHeaderCommitment = detectedCommitment[:]
	evidenceHash, err := ComputeReorganizationEvidenceHash(evidence)
	if err != nil {
		t.Fatal(err)
	}
	evidence.EvidenceHash = evidenceHash[:]
	const expectedReorganizationEvidenceHash = "2b23865344c586ba7ce8a044071eeb04fcc271ab63efe549016de06b1bc9a006"
	if fmt.Sprintf("%x", evidenceHash) != expectedReorganizationEvidenceHash {
		t.Fatalf(
			"reorganization evidence hash changed: got %x want %s",
			evidenceHash,
			expectedReorganizationEvidenceHash,
		)
	}
	substitutions := map[string]func(*unifiedv1.CrossChainReorganizationEvidence){
		"orphan-receipt-proof": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.AffectedOrphanedSourceProofs[0].ReceiptProofHash[0] ^= 0xff
		},
		"orphan-observer-signature": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.AffectedOrphanedSourceProofs[0].ObserverSignature = []byte("forged")
		},
		"replacement-authority": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.ReplacementHeaderAuthorityHash[0] ^= 0xff
		},
		"replacement-signature": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.ReplacementObserverSignature = []byte("forged")
		},
		"detected-head-signature": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.DetectedHeadObserverSignature = []byte("forged")
		},
		"finality-policy": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.FinalityPolicyHash[0] ^= 0xff
			value.AffectedOrphanedSourceProofs[0].FinalityPolicyHash =
				append([]byte(nil), value.FinalityPolicyHash...)
		},
		"threshold-certificate": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.AffectedOrphanedFinalityCertificates[0].Signatures =
				value.AffectedOrphanedFinalityCertificates[0].Signatures[:1]
		},
		"orphan-certificate-substitution": func(value *unifiedv1.CrossChainReorganizationEvidence) {
			value.AffectedOrphanedFinalityCertificates[0].CertificateHash[0] ^= 0x01
		},
	}
	for name, mutate := range substitutions {
		changed :=
			proto.Clone(evidence).(*unifiedv1.CrossChainReorganizationEvidence)
		mutate(changed)
		if name != "threshold-certificate" {
			rebindReorganizationEvidence(t, changed)
		}
		if _, _, err := projector.ProjectReorganization(changed); err == nil {
			t.Fatalf("%s substitution accepted", name)
		}
	}
	incident, affected, err := projector.ProjectReorganization(evidence)
	if err != nil || incident.GetStatus() != "OPEN" || len(affected) != 1 ||
		!affected[0].Disputed || affected[0].SourceProof == nil ||
		!proto.Equal(affected[0].SourceProof, proof) {
		t.Fatalf("deep reorg projection: incident=%v affected=%#v err=%v", incident, affected, err)
	}
	expectedIncidentID := fmt.Sprintf("crosschain-incident:%x", evidenceHash)
	if incident.GetIncidentId().GetValue() != expectedIncidentID ||
		incident.GetRouteId().GetValue() != "route-home-satellite-v1" ||
		len(incident.GetAffectedMessageIds()) != 1 ||
		!bytes.Equal(
			incident.GetAffectedMessageIds()[0],
			envelope.GetMessageId(),
		) ||
		incident.GetReasonCode() != "POST_FINALITY_REORGANIZATION" ||
		incident.GetOwner() != "cross-chain-security" ||
		!bytes.Equal(incident.GetEvidenceHash(), evidenceHash[:]) ||
		!proto.Equal(incident.GetOpenedAt(), evidence.GetDetectedAt()) ||
		incident.GetStatus() != "OPEN" {
		t.Fatalf("incident identity diverged from durable SQL contract: %v", incident)
	}
	if _, replayed, err := projector.ProjectReorganization(evidence); err != nil ||
		len(replayed) != 1 || !replayed[0].Disputed {
		t.Fatalf("exact deep reorg replay: %#v err=%v", replayed, err)
	}
	if err := projector.RemovePreFinality(
		proof.GetSourceChainId(),
		proof.GetTransactionHash(),
		proof.GetLogIndex(),
	); !errors.Is(err, ErrInsufficientFinality) {
		t.Fatalf("finalized fact was removable after reorg: %v", err)
	}
	conflict := proto.Clone(evidence).(*unifiedv1.CrossChainReorganizationEvidence)
	conflict.ReplacementBlockHash = bytes.Repeat([]byte{0x83}, 32)
	rebindReorganizationEvidence(t, conflict)
	if _, _, err := projector.ProjectReorganization(conflict); !errors.Is(
		err,
		ErrProjectionConflict,
	) {
		t.Fatalf("conflicting deep reorg accepted: %v", err)
	}

	snapshot := projector.Snapshot()
	restarted, _, _ := projectorFixture(t)
	if err := restarted.RestoreSnapshot(snapshot); err != nil {
		t.Fatalf("restore disputed snapshot: %v", err)
	}
	var messageID [32]byte
	copy(messageID[:], envelope.GetMessageId())
	restored, ok := restarted.Get(messageID)
	if !ok || !restored.Disputed || restored.Incident == nil ||
		!proto.Equal(restored.SourceProof, proof) ||
		!proto.Equal(restored.Reorganization, evidence) ||
		!proto.Equal(restored.Incident, incident) {
		t.Fatalf("restarted dispute projection lost evidence: %#v", restored)
	}
}

func TestRouteBindingIsFrozen(t *testing.T) {
	projector, _, _ := projectorFixture(t)
	policyHash := fixedBytes32(bytes.Repeat([]byte{0x51}, 32))
	if err := projector.BindRoute("route-home-satellite-v1", policyHash); err != nil {
		t.Fatalf("exact route replay: %v", err)
	}
	if err := projector.BindRoute("route-conflict", policyHash); !errors.Is(
		err,
		ErrProjectionConflict,
	) {
		t.Fatalf("route policy identity changed without conflict: %v", err)
	}
}

func TestProvisionalSourceUpgradesOnlyWithExactFinalityCertificate(t *testing.T) {
	projector, envelope, proof := projectorFixture(t)
	verifier := &strictVerifier{sourceFinal: false}
	projector.verifier = verifier
	malformed := sourceFinalityFixture(t, proof)
	malformed.Signatures[0] = []byte("forged")
	if _, err := projector.ProjectSource(
		envelope,
		proof,
		malformed,
	); !errors.Is(err, ErrUnauthenticated) {
		t.Fatalf("provisional projection retained malformed certificate: %v", err)
	}
	provisional, err := projector.ProjectSource(envelope, proof, nil)
	if err != nil || provisional.SourceFinal ||
		provisional.SourceFinalityCertificate != nil {
		t.Fatalf("provisional source projection failed: %#v %v", provisional, err)
	}
	verifier.sourceFinal = true
	certificate := sourceFinalityFixture(t, proof)
	finalized, err := projector.ProjectSource(envelope, proof, certificate)
	if err != nil || !finalized.SourceFinal ||
		!proto.Equal(finalized.SourceFinalityCertificate, certificate) {
		t.Fatalf("provisional source did not upgrade exactly: %#v %v", finalized, err)
	}
}

func TestReorganizationEvidenceAlignsEveryAffectedMessage(t *testing.T) {
	projector, firstEnvelope, firstProof := projectorFixture(t)
	firstProjection, err := projector.ProjectSource(
		firstEnvelope,
		firstProof,
		sourceFinalityFixture(t, firstProof),
	)
	if err != nil {
		t.Fatal(err)
	}

	secondEnvelope := proto.Clone(firstEnvelope).(*unifiedv1.CrossChainMessageEnvelope)
	secondEnvelope.MessageId = nil
	secondEnvelope.SourceNonce = 2
	secondEnvelope.AggregateId = bytes.Repeat([]byte{0xa1}, 32)
	secondEnvelope.CorrelationId = bytes.Repeat([]byte{0xa2}, 32)
	secondEnvelope.GetCanonicalUftLock().LockId = bytes.Repeat([]byte{0xa3}, 32)
	if err := message.BindTypedActionABI(secondEnvelope); err != nil {
		t.Fatal(err)
	}
	secondEnvelope, err = message.Seal(secondEnvelope)
	if err != nil {
		t.Fatal(err)
	}
	secondProof := proto.Clone(firstProof).(*unifiedv1.CrossChainSourceEventProof)
	secondProof.MessageId = append([]byte(nil), secondEnvelope.GetMessageId()...)
	secondProof.TransactionHash = bytes.Repeat([]byte{0xa4}, 32)
	secondProof.LogIndex++
	secondProof.EventHash = bytes.Repeat([]byte{0xa5}, 32)
	secondProof.ObserverSignedHeaderCommitment = nil
	bindObserverCommitment(t, secondProof)
	secondProjection, err := projector.ProjectSource(
		secondEnvelope,
		secondProof,
		sourceFinalityFixture(t, secondProof),
	)
	if err != nil {
		t.Fatal(err)
	}

	type affectedFact struct {
		messageID    []byte
		proof        *unifiedv1.CrossChainSourceEventProof
		evidenceHash []byte
	}
	facts := []affectedFact{
		{
			messageID:    append([]byte(nil), firstEnvelope.GetMessageId()...),
			proof:        proto.Clone(firstProof).(*unifiedv1.CrossChainSourceEventProof),
			evidenceHash: append([]byte(nil), firstProjection.SourceEvidenceHash[:]...),
		},
		{
			messageID:    append([]byte(nil), secondEnvelope.GetMessageId()...),
			proof:        proto.Clone(secondProof).(*unifiedv1.CrossChainSourceEventProof),
			evidenceHash: append([]byte(nil), secondProjection.SourceEvidenceHash[:]...),
		},
	}
	sort.Slice(facts, func(left, right int) bool {
		return bytes.Compare(facts[left].messageID, facts[right].messageID) < 0
	})
	certificates := make([]*unifiedv1.CrossChainFinalityCertificate, len(facts))
	for index, fact := range facts {
		proofHash, hashErr := ComputeSourceProofHash(fact.proof)
		if hashErr != nil {
			t.Fatal(hashErr)
		}
		certificates[index] = &unifiedv1.CrossChainFinalityCertificate{
			MessageId:        append([]byte(nil), fact.messageID...),
			SourceProofHash:  append([]byte(nil), proofHash[:]...),
			SignerSetHash:    bytes.Repeat([]byte{0x91}, 32),
			SignerSetVersion: 1,
			Threshold:        2,
			Signatures:       [][]byte{[]byte("signer-a"), []byte("signer-b")},
			ValidFrom:        timestamppb.New(time.Unix(1_699_999_900, 0).UTC()),
			ValidUntil:       timestamppb.New(time.Unix(1_700_003_600, 0).UTC()),
			CertificateHash:  bytes.Repeat([]byte{0x92}, 32),
		}
	}
	homeAuthority := [32]byte{3}
	homePolicy := [32]byte{1}
	evidence := &unifiedv1.CrossChainReorganizationEvidence{
		ChainId:                         firstEnvelope.GetSourceChainId(),
		OrphanedBlockHash:               append([]byte(nil), firstProof.GetSourceBlockHash()...),
		ReplacementBlockHash:            bytes.Repeat([]byte{0xb1}, 32),
		DetectedHeadHash:                bytes.Repeat([]byte{0xb2}, 32),
		BlockNumber:                     firstProof.GetSourceBlockNumber(),
		ReplacementBlockNumber:          firstProof.GetSourceBlockNumber(),
		DetectedHeadNumber:              firstProof.GetFinalityHeadNumber() + 1,
		DetectedAt:                      timestamppb.New(time.Unix(1_700_000_200, 0).UTC()),
		ReplacementHeaderAuthorityHash:  append([]byte(nil), homeAuthority[:]...),
		ReplacementObserverSignature:    []byte("replacement-signed"),
		DetectedHeadHeaderAuthorityHash: append([]byte(nil), homeAuthority[:]...),
		DetectedHeadObserverSignature:   []byte("detected-head-signed"),
		FinalityPolicyHash:              append([]byte(nil), homePolicy[:]...),
		AffectedMessageIds: [][]byte{
			append([]byte(nil), facts[0].messageID...),
			append([]byte(nil), facts[1].messageID...),
		},
		AffectedOrphanedSourceProofs: []*unifiedv1.CrossChainSourceEventProof{
			facts[0].proof,
			facts[1].proof,
		},
		AffectedOrphanedEventEvidenceHashes: [][]byte{
			facts[0].evidenceHash,
			facts[1].evidenceHash,
		},
		AffectedOrphanedFinalityCertificates: certificates,
	}
	rebindReorganizationEvidence(t, evidence)

	incident, affected, err := projector.ProjectReorganization(evidence)
	if err != nil || incident == nil || len(affected) != 2 ||
		!affected[0].Disputed || !affected[1].Disputed {
		t.Fatalf("aligned multi-message reorganization failed: %#v %v", affected, err)
	}

	swapped := proto.Clone(evidence).(*unifiedv1.CrossChainReorganizationEvidence)
	swapped.AffectedOrphanedSourceProofs[0], swapped.AffectedOrphanedSourceProofs[1] =
		swapped.AffectedOrphanedSourceProofs[1], swapped.AffectedOrphanedSourceProofs[0]
	swapped.AffectedOrphanedFinalityCertificates[0],
		swapped.AffectedOrphanedFinalityCertificates[1] =
		swapped.AffectedOrphanedFinalityCertificates[1],
		swapped.AffectedOrphanedFinalityCertificates[0]
	swapped.AffectedOrphanedEventEvidenceHashes[0],
		swapped.AffectedOrphanedEventEvidenceHashes[1] =
		swapped.AffectedOrphanedEventEvidenceHashes[1],
		swapped.AffectedOrphanedEventEvidenceHashes[0]
	if _, err := ComputeReorganizationEvidenceHash(swapped); !errors.Is(
		err,
		ErrProjectionConflict,
	) {
		t.Fatalf("misaligned per-message reorganization evidence accepted: %v", err)
	}
}

func TestPreFinalityProjectionCanBeRemoved(t *testing.T) {
	_, envelope, proof := projectorFixture(t)
	homePolicy := [32]byte{1}
	homeObserver := [32]byte{3}
	projector, err := NewProjector(
		&strictVerifier{sourceFinal: false},
		ChainConfig{
			ChainID: "31337", Coordinator: bytes.Repeat([]byte{0x11}, 20),
			ConfigurationHash: [32]byte{5}, FinalityPolicyHash: homePolicy,
			ObserverAuthority: homeObserver, RequiredDepth: 2,
		},
		ChainConfig{
			ChainID: "31338", Coordinator: bytes.Repeat([]byte{0x22}, 20),
			ConfigurationHash: [32]byte{6}, FinalityPolicyHash: [32]byte{2},
			ObserverAuthority: [32]byte{4}, RequiredDepth: 2,
		},
	)
	if err != nil {
		t.Fatalf("projector: %v", err)
	}
	transactionHash := append([]byte(nil), proof.GetTransactionHash()...)
	proof.FinalityHeadNumber = proof.SourceBlockNumber
	bindObserverCommitment(t, proof)
	projection, err := projector.ProjectSource(
		envelope,
		proof,
		nil,
	)
	if err != nil || projection.SourceFinal {
		t.Fatalf("provisional source: %#v err=%v", projection, err)
	}
	if err := projector.RemovePreFinality("31337", transactionHash, 1); err != nil {
		t.Fatalf("remove provisional: %v", err)
	}
	var key [32]byte
	copy(key[:], envelope.GetMessageId())
	if _, ok := projector.Get(key); ok {
		t.Fatal("pre-finality reorganization left a canonical projection")
	}
}
