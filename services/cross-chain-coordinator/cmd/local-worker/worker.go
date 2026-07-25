package main

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"math/big"
	"sort"
	"strconv"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	chaincrosschain "github.com/unified-finance/unified/services/chain-indexer/crosschain"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/message"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/provider"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/reconciliation"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/recovery"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const (
	localRouteID       = "route-local-worker-smoke-v1"
	localPublisher     = "local-worker-publisher-v1"
	localConsumer      = "local-worker-consumer-v1"
	localSourceID      = "31337"
	localDestinationID = "31338"
	localProviderAID   = "mock-bridge-provider-a"
	localProviderBID   = "mock-bridge-provider-b"
	localActionFamily  = "CANONICAL_UFT_V1"
)

var localBaseTime = time.Unix(1_900_000_000, 0).UTC()

var (
	localObserverPublicKey = mustHex(
		"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
	)
	localDestinationObserverPublicKey = mustHex(
		"3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
	)
	localObserverSignature = mustHex(
		"2a146dc97cfc21604757b1c4b51652179b78c94f0aa91068611ba8a164863db9" +
			"759f1647e2e71293ab40b69d9627ce4c02f9b327ba71db596a679dc8c5163d03",
	)
	localReplacementObserverSignature = mustHex(
		"ab3b22edbae40bc0c48cd518f5c7a1602af0eaec82937cb68eee6d55a534e5eb" +
			"b85bf1d5c47b7cee10c3a9db0e1618a77132e2d3677b9d48106abc9f49f3700f",
	)
	localDetectedHeadObserverSignature = mustHex(
		"4d85c0d7c97aa1e678ae75e5eab3e776446604cde14479d6217b583ccf76505b" +
			"84a7054778604da485248de15b1435eb49056b07c90ca1acf0f3ce36d8c83606",
	)
	localFinalitySigners = [3][20]byte{
		bytes20(mustHex("7e5f4552091a69125d5dfcb7b8c2659029395bdf")),
		bytes20(mustHex("2b5ad5c4795c026514f8317c7a215e218dccd6cf")),
		bytes20(mustHex("6813eb9362372eef6200f3b1dbc3f819671cba69")),
	}
	localFinalitySignatures = [][]byte{
		mustHex(
			"191b67352c983516388115cf8d43d18f5cf939f1c518458ab7c6c74cdc1d784f" +
				"0119062b5ec8549627e6172ab017fd2e5614c180cc6b2d673d8d54a05451ef3f00",
		),
		mustHex(
			"2f389b3bee6c683408d00feee2e8ac5abf167e0d8480aadab198bd1ed8368a23" +
				"6e19be6c7af5694256c44f213dcc4c2b6a0c094dc2537f5a763e52368d2c7d9f01",
		),
	}
	localRecoverySignatures = [][]byte{
		mustHex(
			"d7b0e32c771ed5ab3f8585400c06e44e15c87f08adc05cce00768504e964c818" +
				"5d2334782108fb827c1d93519b146132e155ae9372b89e2318135e73b06b7d6201",
		),
		mustHex(
			"8697a26d1fddda47cfa5645437c4a7d439ebd8d9047cd36ff54fd6069fdd2a2b" +
				"3741b4be938ae3a5cf37dc6b36cae2739294dd3063a90f752693ca7e66349a1c00",
		),
	}
)

type durableRepository interface {
	Route(string, uint64) (store.RouteVersion, error)
	CreateMessage(store.MessageRecord) (store.MessageRecord, error)
	CompareAndSet(
		[32]byte,
		uint64,
		unifiedv1.CrossChainMessageState,
		bool,
		[32]byte,
		time.Time,
	) (store.MessageRecord, error)
	Message([32]byte) (store.MessageRecord, error)
	ClaimOutbox(
		context.Context,
		string,
		time.Time,
		time.Time,
		int,
	) ([]store.OutboxRecord, error)
	MarkOutboxPublished(
		context.Context,
		string,
		string,
		uint32,
		string,
		time.Time,
	) (store.OutboxRecord, error)
	ConsumeInbox(
		context.Context,
		string,
		[32]byte,
		string,
		string,
		string,
		[32]byte,
		time.Time,
	) (store.InboxRecord, error)
	RecordProviderAttempt(
		context.Context,
		store.ProviderAttemptRecord,
	) (store.ProviderAttemptRecord, error)
	ProviderAttempt(
		context.Context,
		[32]byte,
		string,
		uint32,
	) (store.ProviderAttemptRecord, error)
}

type sourceEvidenceRepository interface {
	RecordSourceProof(
		context.Context,
		store.SourceProofRecord,
	) (store.SourceProofRecord, error)
}

type finalityEvidenceRepository interface {
	RecordFinalityCertificate(
		context.Context,
		store.FinalityCertificateRecord,
	) (store.FinalityCertificateRecord, error)
}

type smokeReport struct {
	MessageID                string `json:"message_id"`
	State                    string `json:"state"`
	ProviderFailover         bool   `json:"provider_failover"`
	ProviderAttempts         int    `json:"provider_attempts"`
	OutboxPublished          int    `json:"outbox_published"`
	InboxConsumed            int    `json:"inbox_consumed"`
	EvidencePersisted        bool   `json:"evidence_persisted"`
	RestartRehydrated        bool   `json:"restart_rehydrated"`
	ReorganizationRehydrated bool   `json:"reorganization_rehydrated"`
	DuplicatePrevented       bool   `json:"duplicate_prevented"`
	Reconciled               bool   `json:"reconciled"`
	RecoveryGuarded          bool   `json:"recovery_guarded"`
}

type messageResult struct {
	record            store.MessageRecord
	attempts          []store.ProviderAttemptRecord
	deliveredThisPass bool
}

func runMessagePass(
	ctx context.Context,
	repository durableRepository,
	observer sourceEvidenceRepository,
	finalityAttester finalityEvidenceRepository,
	evidenceStore immutableEvidenceStore,
	transports ...provider.Transport,
) (messageResult, error) {
	registration := localRegistration()
	if observer == nil || finalityAttester == nil {
		return messageResult{}, errors.New(
			"observer and finality-attester repositories are required",
		)
	}
	route, err := repository.Route(localRouteID, 1)
	if err != nil || route != registration.Route {
		return messageResult{}, errors.New("pinned local route is not provisioned")
	}
	envelope, serialized, err := localEnvelope(registration)
	if err != nil {
		return messageResult{}, err
	}
	record := store.MessageRecord{
		MessageID: bytes32(envelope.GetMessageId()),
		Envelope:  serialized,
		State:     unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED,
		Version:   1,
		Evidence:  bytes32(envelope.GetPayloadHash()),
		UpdatedAt: localBaseTime.Add(time.Minute),
	}
	if _, err := repository.CreateMessage(record); err != nil {
		return messageResult{}, err
	}
	current, err := repository.Message(record.MessageID)
	if err != nil {
		return messageResult{}, err
	}
	evidence, err := authenticateSource(envelope, registration)
	if err != nil {
		return messageResult{}, err
	}
	evidenceKey := fmt.Sprintf(
		"synthetic/%x/%x.source-proof.pb",
		record.MessageID,
		evidence.ContentHash,
	)
	if err := evidenceStore.PutImmutable(
		ctx,
		evidenceKey,
		evidence.Bytes,
		evidence.ContentHash,
	); err != nil {
		return messageResult{}, err
	}
	if _, err := observer.RecordSourceProof(ctx, evidence.ProofRecord); err != nil {
		return messageResult{}, err
	}
	if _, err := finalityAttester.RecordFinalityCertificate(
		ctx,
		evidence.CertificateRecord,
	); err != nil {
		return messageResult{}, err
	}
	router := provider.NewRouter()
	if err := router.RegisterRoute(registration.Route.PolicyHash, transports...); err != nil {
		return messageResult{}, err
	}
	result := messageResult{record: current}
	for {
		switch current.State {
		case unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED:
			current, err = repository.CompareAndSet(
				current.MessageID,
				current.Version,
				unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING,
				false,
				evidence.Projection.SourceEvidenceHash,
				localBaseTime.Add(2*time.Minute),
			)
		case unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING:
			current, err = repository.CompareAndSet(
				current.MessageID,
				current.Version,
				unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINAL,
				false,
				evidence.CertificateRecord.CertificateHash,
				localBaseTime.Add(3*time.Minute),
			)
		case unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINAL:
			persistedB, persistedErr := repository.ProviderAttempt(
				ctx,
				current.MessageID,
				"mock-bridge-provider-b",
				2,
			)
			if persistedErr == nil {
				if persistedB.Status != "DELIVERED" ||
					persistedB.EnvelopeHash != keccak(serialized) ||
					persistedB.SourceProofHash != evidence.ContentHash {
					return messageResult{}, errors.New("persisted provider delivery identity conflict")
				}
				current, err = repository.CompareAndSet(
					current.MessageID,
					current.Version,
					unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SENT,
					false,
					persistedB.ReceiptHash,
					localBaseTime.Add(5*time.Minute),
				)
				break
			}
			if !errors.Is(persistedErr, store.ErrNotFound) {
				return messageResult{}, persistedErr
			}
			delivery := provider.Delivery{
				MessageID:    current.MessageID,
				RoutePolicy:  registration.Route.PolicyHash,
				Envelope:     append([]byte(nil), serialized...),
				EnvelopeHash: keccak(serialized),
				SourceProof:  append([]byte(nil), evidence.Bytes...),
				ProofHash:    evidence.ContentHash,
				AttemptedAt:  localBaseTime.Add(4 * time.Minute),
			}
			receipt, deliveryErr := router.Deliver(ctx, delivery)
			if deliveryErr != nil {
				return messageResult{}, deliveryErr
			}
			for _, attempt := range router.Attempts(current.MessageID) {
				attemptNumber := uint32(0)
				switch attempt.ProviderID {
				case "mock-bridge-provider-a":
					attemptNumber = 1
				case "mock-bridge-provider-b":
					attemptNumber = 2
				default:
					return messageResult{}, errors.New("unapproved provider attempt")
				}
				status := "FAILED"
				var receiptHash [32]byte
				if attempt.Success {
					status = "DELIVERED"
					receiptHash = keccak(attempt.Receipt)
				}
				if _, persistErr := repository.RecordProviderAttempt(
					ctx,
					store.ProviderAttemptRecord{
						MessageID:       current.MessageID,
						ProviderID:      attempt.ProviderID,
						AttemptNumber:   attemptNumber,
						EnvelopeHash:    delivery.EnvelopeHash,
						SourceProofHash: delivery.ProofHash,
						Status:          status,
						ReceiptHash:     receiptHash,
						AttemptedAt:     attempt.AttemptedAt,
					},
				); persistErr != nil {
					return messageResult{}, persistErr
				}
			}
			current, err = repository.CompareAndSet(
				current.MessageID,
				current.Version,
				unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SENT,
				false,
				keccak(receipt.Receipt),
				localBaseTime.Add(5*time.Minute),
			)
			result.deliveredThisPass = true
		case unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SENT,
			unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_DISPUTED:
			result.record = current
			result.attempts, err = loadProviderAttempts(ctx, repository, current.MessageID)
			if err != nil {
				return messageResult{}, err
			}
			return result, nil
		default:
			return messageResult{}, fmt.Errorf(
				"local worker refuses unsupported state %s",
				current.State.String(),
			)
		}
		if err != nil {
			return messageResult{}, err
		}
	}
}

func loadProviderAttempts(
	ctx context.Context,
	repository durableRepository,
	messageID [32]byte,
) ([]store.ProviderAttemptRecord, error) {
	expected := []struct {
		providerID string
		number     uint32
	}{
		{providerID: localProviderAID, number: 1},
		{providerID: localProviderBID, number: 2},
	}
	result := make([]store.ProviderAttemptRecord, 0, 2)
	for _, identity := range expected {
		record, err := repository.ProviderAttempt(
			ctx,
			messageID,
			identity.providerID,
			identity.number,
		)
		if err != nil {
			return nil, err
		}
		result = append(result, record)
	}
	return result, nil
}

func publishOutbox(
	ctx context.Context,
	repository durableRepository,
	broker eventBroker,
) (int, int, error) {
	claimedAt := localBaseTime.Add(6 * time.Minute)
	leaseUntil := claimedAt.Add(time.Minute)
	records, err := repository.ClaimOutbox(
		ctx,
		localPublisher,
		leaseUntil,
		claimedAt,
		100,
	)
	if err != nil {
		return 0, 0, err
	}
	expected := make(map[string]store.OutboxRecord, len(records))
	expectedOffsets := make(map[string]string, len(records))
	for index, record := range records {
		if record.Topic != outboxTopic || len(record.Payload) == 0 ||
			record.PayloadHash == ([32]byte{}) {
			return 0, 0, errors.New("invalid claimed outbox identity")
		}
		offset, publishErr := broker.Publish(ctx, brokerMessage{
			MessageID:    record.MessageID,
			PartitionKey: record.PartitionKey,
			Payload:      append([]byte(nil), record.Payload...),
			PayloadHash:  record.PayloadHash,
			OutboxID:     record.OutboxID,
		})
		if publishErr != nil {
			return index, 0, publishErr
		}
		publishedAt := claimedAt.Add(time.Duration(index+1) * time.Second)
		if !publishedAt.Before(leaseUntil) {
			return index, 0, errors.New(
				"synthetic publication timestamp exceeded its lease",
			)
		}
		if _, markErr := repository.MarkOutboxPublished(
			ctx,
			record.OutboxID,
			localPublisher,
			record.AttemptCount,
			offset,
			publishedAt,
		); markErr != nil {
			return index, 0, markErr
		}
		expected[record.OutboxID] = record
		expectedOffsets[record.OutboxID] = offset
	}
	if len(records) == 0 {
		return 0, 0, nil
	}
	consumed, err := broker.Consume(ctx, len(records))
	if err != nil {
		return len(records), 0, err
	}
	for index, event := range consumed {
		expectedRecord, ok := expected[event.OutboxID]
		if !ok || expectedRecord.MessageID != event.MessageID ||
			expectedRecord.PartitionKey != event.PartitionKey ||
			expectedRecord.PayloadHash != event.PayloadHash ||
			expectedOffsets[event.OutboxID] != event.BrokerOffset ||
			!bytes.Equal(expectedRecord.Payload, event.Payload) {
			return len(records), index, errors.New("broker event identity conflict")
		}
		consumedAt := localBaseTime.Add(time.Duration(20+index) * time.Minute)
		first, consumeErr := repository.ConsumeInbox(
			ctx,
			localConsumer,
			event.MessageID,
			outboxTopic,
			event.PartitionKey,
			event.BrokerOffset,
			event.PayloadHash,
			consumedAt,
		)
		if consumeErr != nil {
			return len(records), index, consumeErr
		}
		replayed, replayErr := repository.ConsumeInbox(
			ctx,
			localConsumer,
			event.MessageID,
			outboxTopic,
			event.PartitionKey,
			event.BrokerOffset,
			event.PayloadHash,
			consumedAt,
		)
		if replayErr != nil || first != replayed {
			return len(records), index, errors.New("inbox exact replay failed")
		}
	}
	return len(records), len(consumed), nil
}

type authenticatedSource struct {
	Projection        chaincrosschain.MessageProjection
	Proof             *unifiedv1.CrossChainSourceEventProof
	Certificate       *unifiedv1.CrossChainFinalityCertificate
	Bytes             []byte
	ContentHash       [32]byte
	ProofRecord       store.SourceProofRecord
	CertificateRecord store.FinalityCertificateRecord
}

func authenticateSource(
	envelope *unifiedv1.CrossChainMessageEnvelope,
	registration store.RouteRegistration,
) (authenticatedSource, error) {
	projector, err := chaincrosschain.NewProjector(
		localEvidenceVerifier{
			registration:      registration,
			observerPublicKey: localObserverPublicKey,
		},
		chaincrosschain.ChainConfig{
			ChainID:            registration.SourceChain.ChainID,
			Coordinator:        registration.SourceChain.Coordinator[:],
			ConfigurationHash:  registration.SourceChain.ConfigurationHash,
			FinalityPolicyHash: registration.SourceFinalityPolicyHash,
			ObserverAuthority:  registration.SourceChain.ObserverAuthorityHash,
			RequiredDepth:      2,
		},
		chaincrosschain.ChainConfig{
			ChainID:            registration.DestinationChain.ChainID,
			Coordinator:        registration.DestinationChain.Coordinator[:],
			ConfigurationHash:  registration.DestinationChain.ConfigurationHash,
			FinalityPolicyHash: registration.DestinationFinalityPolicyHash,
			ObserverAuthority:  registration.DestinationChain.ObserverAuthorityHash,
			RequiredDepth:      2,
		},
	)
	if err != nil {
		return authenticatedSource{}, err
	}
	proof := &unifiedv1.CrossChainSourceEventProof{
		MessageId:            append([]byte(nil), envelope.GetMessageId()...),
		SourceChainId:        registration.SourceChain.ChainID,
		SourceContract:       registration.SourceChain.Coordinator[:],
		SourceBlockHash:      repeatedBytes(0x31, 32),
		SourceBlockNumber:    100,
		SourceBlockTimestamp: timestamppb.New(localBaseTime),
		TransactionHash:      repeatedBytes(0x32, 32),
		TransactionIndex:     0,
		ReceiptRoot:          repeatedBytes(0x33, 32),
		ReceiptProofHash:     repeatedBytes(0x34, 32),
		LogIndex:             1,
		EventHash:            repeatedBytes(0x35, 32),
		FinalityHeadHash:     repeatedBytes(0x36, 32),
		FinalityHeadNumber:   102,
		RequiredDepth:        2,
		HeaderAuthorityHash:  registration.SourceChain.ObserverAuthorityHash[:],
		ObserverSignature:    append([]byte(nil), localObserverSignature...),
		FinalityPolicyHash:   registration.SourceFinalityPolicyHash[:],
	}
	commitment, err := chaincrosschain.ComputeObserverHeaderCommitment(proof)
	if err != nil {
		return authenticatedSource{}, err
	}
	proof.ObserverSignedHeaderCommitment = commitment[:]
	proofHash, err := chaincrosschain.ComputeSourceProofHash(proof)
	if err != nil {
		return authenticatedSource{}, err
	}
	certificate, err := localFinalityCertificate(
		envelope,
		proofHash,
		registration,
	)
	if err != nil {
		return authenticatedSource{}, err
	}
	certificateProto := &unifiedv1.CrossChainFinalityCertificate{
		MessageId:        append([]byte(nil), envelope.GetMessageId()...),
		SourceProofHash:  append([]byte(nil), proofHash[:]...),
		SignerSetHash:    append([]byte(nil), registration.SourceSignerSetHash[:]...),
		SignerSetVersion: uint32(registration.SourceSignerSetVersion),
		Threshold:        2,
		Signatures:       cloneByteSlices(certificate.Signatures),
		ValidFrom:        timestamppb.New(localBaseTime.Add(-time.Hour)),
		ValidUntil:       timestamppb.New(localBaseTime.Add(24 * time.Hour)),
		CertificateHash:  append([]byte(nil), certificate.Hash[:]...),
	}
	projection, err := projector.ProjectSource(envelope, proof, certificateProto)
	if err != nil || !projection.SourceFinal {
		return authenticatedSource{}, errors.New(
			"synthetic source evidence did not authenticate as final",
		)
	}
	// Exercise the exact proof+certificate replay boundary before transport.
	replayed, err := projector.ProjectSource(
		envelope,
		proto.Clone(proof).(*unifiedv1.CrossChainSourceEventProof),
		proto.Clone(certificateProto).(*unifiedv1.CrossChainFinalityCertificate),
	)
	if err != nil || replayed.SourceEvidenceHash != projection.SourceEvidenceHash {
		return authenticatedSource{}, errors.New(
			"source projection exact replay failed",
		)
	}
	proofBytes, err := proto.MarshalOptions{Deterministic: true}.Marshal(proof)
	if err != nil {
		return authenticatedSource{}, err
	}
	proofID := "source-proof:" + hex.EncodeToString(proofHash[:])
	return authenticatedSource{
		Projection:  projection,
		Proof:       proto.Clone(proof).(*unifiedv1.CrossChainSourceEventProof),
		Certificate: proto.Clone(certificateProto).(*unifiedv1.CrossChainFinalityCertificate),
		Bytes:       proofBytes,
		ContentHash: keccak(proofBytes),
		ProofRecord: store.SourceProofRecord{
			ProofID:                        proofID,
			MessageID:                      bytes32(proof.GetMessageId()),
			ChainID:                        proof.GetSourceChainId(),
			TransactionHash:                bytes32(proof.GetTransactionHash()),
			TransactionIndex:               strconv.FormatUint(proof.GetTransactionIndex(), 10),
			LogIndex:                       strconv.FormatUint(proof.GetLogIndex(), 10),
			BlockNumber:                    strconv.FormatUint(proof.GetSourceBlockNumber(), 10),
			BlockHash:                      bytes32(proof.GetSourceBlockHash()),
			ReceiptsRoot:                   bytes32(proof.GetReceiptRoot()),
			InclusionProofHash:             bytes32(proof.GetReceiptProofHash()),
			EventHash:                      bytes32(proof.GetEventHash()),
			FinalityHeadNumber:             strconv.FormatUint(proof.GetFinalityHeadNumber(), 10),
			FinalityHeadHash:               bytes32(proof.GetFinalityHeadHash()),
			ConfirmationDepth:              strconv.FormatUint(proof.GetRequiredDepth(), 10),
			FinalityPolicyHash:             bytes32(proof.GetFinalityPolicyHash()),
			ObserverAuthorityHash:          bytes32(proof.GetHeaderAuthorityHash()),
			ObserverSignedHeaderCommitment: bytes32(proof.GetObserverSignedHeaderCommitment()),
			ObserverSignature:              append([]byte(nil), proof.GetObserverSignature()...),
			ProofHash:                      proofHash,
			ObservedAt:                     localBaseTime.Add(90 * time.Second),
		},
		CertificateRecord: store.FinalityCertificateRecord{
			CertificateID:    "finality-certificate:" + hex.EncodeToString(certificate.Hash[:]),
			MessageID:        bytes32(envelope.GetMessageId()),
			ProofID:          proofID,
			SignerSetHash:    registration.SourceSignerSetHash,
			SignerSetVersion: registration.SourceSignerSetVersion,
			SignerBitmap:     "110",
			SignatureCount:   2,
			CertificateHash:  certificate.Hash,
			CertifiedAt:      localBaseTime.Add(100 * time.Second),
		},
	}, nil
}

type localEvidenceVerifier struct {
	registration      store.RouteRegistration
	observerPublicKey []byte
}

func (verifier localEvidenceVerifier) VerifySource(
	_ *unifiedv1.CrossChainMessageEnvelope,
	proof *unifiedv1.CrossChainSourceEventProof,
	certificate *unifiedv1.CrossChainFinalityCertificate,
) (chaincrosschain.Verification, error) {
	if len(verifier.observerPublicKey) != ed25519.PublicKeySize {
		return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
	}
	authority := keccak(verifier.observerPublicKey)
	if !bytes.Equal(proof.GetHeaderAuthorityHash(), authority[:]) {
		return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
	}
	commitment, err := chaincrosschain.ComputeObserverHeaderCommitment(proof)
	if err != nil || !ed25519.Verify(
		ed25519.PublicKey(verifier.observerPublicKey),
		commitment[:],
		proof.GetObserverSignature(),
	) {
		return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
	}
	hash, err := chaincrosschain.ComputeSourceProofHash(proof)
	if err != nil {
		return chaincrosschain.Verification{}, err
	}
	if err := verifyLocalFinalityCertificate(
		certificate,
		bytes32(proof.GetMessageId()),
		hash,
		verifier.registration,
	); err != nil {
		return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
	}
	return chaincrosschain.Verification{CanonicalEvidenceHash: hash, Final: true}, nil
}

func (localEvidenceVerifier) VerifyExecution(
	*unifiedv1.CrossChainExecutionResult,
	*unifiedv1.CrossChainSourceEventProof,
) (chaincrosschain.Verification, error) {
	return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
}

func (localEvidenceVerifier) VerifyAcknowledgement(
	*unifiedv1.CrossChainAcknowledgement,
) (chaincrosschain.Verification, error) {
	return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
}

func (localEvidenceVerifier) VerifyReorganization(
	*unifiedv1.CrossChainReorganizationEvidence,
) (chaincrosschain.Verification, error) {
	return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
}

type localReorganizationVerifier struct {
	registration      store.RouteRegistration
	observerPublicKey []byte
}

func (verifier localReorganizationVerifier) VerifySource(
	envelope *unifiedv1.CrossChainMessageEnvelope,
	proof *unifiedv1.CrossChainSourceEventProof,
	certificate *unifiedv1.CrossChainFinalityCertificate,
) (chaincrosschain.Verification, error) {
	return (localEvidenceVerifier{
		registration:      verifier.registration,
		observerPublicKey: verifier.observerPublicKey,
	}).VerifySource(
		envelope,
		proof,
		certificate,
	)
}

func (localReorganizationVerifier) VerifyExecution(
	*unifiedv1.CrossChainExecutionResult,
	*unifiedv1.CrossChainSourceEventProof,
) (chaincrosschain.Verification, error) {
	return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
}

func (localReorganizationVerifier) VerifyAcknowledgement(
	*unifiedv1.CrossChainAcknowledgement,
) (chaincrosschain.Verification, error) {
	return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
}

func (verifier localReorganizationVerifier) VerifyReorganization(
	evidence *unifiedv1.CrossChainReorganizationEvidence,
) (chaincrosschain.Verification, error) {
	evidenceHash, err := chaincrosschain.ComputeReorganizationEvidenceHash(evidence)
	if err != nil {
		return chaincrosschain.Verification{}, err
	}
	replacementCommitment, err := chaincrosschain.ComputeReorganizationHeaderCommitment(
		"REPLACEMENT",
		evidence,
	)
	if err != nil ||
		!ed25519.Verify(
			ed25519.PublicKey(localObserverPublicKey),
			replacementCommitment[:],
			evidence.GetReplacementObserverSignature(),
		) {
		return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
	}
	detectedCommitment, err := chaincrosschain.ComputeReorganizationHeaderCommitment(
		"DETECTED_HEAD",
		evidence,
	)
	if err != nil ||
		!ed25519.Verify(
			ed25519.PublicKey(localObserverPublicKey),
			detectedCommitment[:],
			evidence.GetDetectedHeadObserverSignature(),
		) {
		return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
	}
	for index, proof := range evidence.GetAffectedOrphanedSourceProofs() {
		if index >= len(evidence.GetAffectedOrphanedFinalityCertificates()) {
			return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
		}
		certificate := evidence.GetAffectedOrphanedFinalityCertificates()[index]
		sourceVerification, verifyErr :=
			(localEvidenceVerifier{
				registration:      verifier.registration,
				observerPublicKey: verifier.observerPublicKey,
			}).
				VerifySource(nil, proof, certificate)
		if verifyErr != nil || !sourceVerification.Final {
			return chaincrosschain.Verification{}, chaincrosschain.ErrUnauthenticated
		}
	}
	return chaincrosschain.Verification{
		CanonicalEvidenceHash: evidenceHash,
		Final:                 true,
	}, nil
}

func verifyLocalFinalityCertificate(
	certificate *unifiedv1.CrossChainFinalityCertificate,
	messageID [32]byte,
	proofHash [32]byte,
	registration store.RouteRegistration,
) error {
	if certificate == nil ||
		!bytes.Equal(certificate.GetMessageId(), messageID[:]) ||
		!bytes.Equal(certificate.GetSourceProofHash(), proofHash[:]) ||
		!bytes.Equal(
			certificate.GetSignerSetHash(),
			registration.SourceSignerSetHash[:],
		) ||
		certificate.GetSignerSetVersion() !=
			uint32(registration.SourceSignerSetVersion) ||
		certificate.GetThreshold() != 2 ||
		len(certificate.GetSignatures()) != 2 ||
		certificate.GetValidFrom() == nil ||
		certificate.GetValidUntil() == nil ||
		!certificate.GetValidFrom().AsTime().Equal(localBaseTime.Add(-time.Hour)) ||
		!certificate.GetValidUntil().AsTime().Equal(localBaseTime.Add(24*time.Hour)) {
		return errors.New("invalid local finality certificate")
	}
	digest, err := localFinalityDigest(
		registration.DestinationChain.ChainID,
		registration.DestinationChain.FinalityVerifier,
		bytes32(certificate.GetMessageId()),
		proofHash,
		registration.SourceSignerSetHash,
		registration.SourceSignerSetVersion,
	)
	if err != nil {
		return err
	}
	seen := make(map[[20]byte]struct{}, 2)
	for _, signature := range certificate.GetSignatures() {
		signer, recoverErr := recovery.VerifyEthereumSignature(digest, signature)
		if recoverErr != nil {
			return recoverErr
		}
		approved := false
		for _, expected := range localFinalitySigners {
			if signer == expected {
				approved = true
				break
			}
		}
		if !approved {
			return errors.New("unapproved local finality signer")
		}
		if _, duplicate := seen[signer]; duplicate {
			return errors.New("duplicate local finality signer")
		}
		seen[signer] = struct{}{}
	}
	signatureOneHash := keccak(certificate.GetSignatures()[0])
	signatureTwoHash := keccak(certificate.GetSignatures()[1])
	expectedHash := abiHash(
		"UNIFIED_SYNTHETIC_FINALITY_CERTIFICATE_RECORD_V1",
		wordBytes32(bytes32(certificate.GetMessageId())),
		wordBytes32(proofHash),
		wordBytes32(registration.SourceSignerSetHash),
		wordUint64(registration.SourceSignerSetVersion),
		wordBytes32(signatureOneHash),
		wordBytes32(signatureTwoHash),
	)
	if !bytes.Equal(certificate.GetCertificateHash(), expectedHash[:]) {
		return errors.New("local finality certificate hash conflict")
	}
	return nil
}

type localReorganization struct {
	Evidence               *unifiedv1.CrossChainReorganizationEvidence
	ReplacementObservation store.HeaderObservationRecord
	DetectedObservation    store.HeaderObservationRecord
	Bytes                  []byte
	ContentHash            [32]byte
	Key                    string
}

func buildLocalReorganization(
	source authenticatedSource,
	registration store.RouteRegistration,
) (localReorganization, error) {
	if source.Proof == nil || source.Certificate == nil {
		return localReorganization{}, errors.New("source evidence is required")
	}
	authority := registration.SourceChain.ObserverAuthorityHash
	policy := registration.SourceFinalityPolicyHash
	detectedAt := localBaseTime.Add(10 * time.Minute)
	evidence := &unifiedv1.CrossChainReorganizationEvidence{
		ChainId:                registration.SourceChain.ChainID,
		OrphanedBlockHash:      append([]byte(nil), source.Proof.GetSourceBlockHash()...),
		ReplacementBlockHash:   repeatedBytes(0x81, 32),
		DetectedHeadHash:       repeatedBytes(0x82, 32),
		BlockNumber:            source.Proof.GetSourceBlockNumber(),
		ReplacementBlockNumber: source.Proof.GetSourceBlockNumber(),
		DetectedHeadNumber:     source.Proof.GetFinalityHeadNumber() + 1,
		AffectedMessageIds: [][]byte{
			append([]byte(nil), source.Proof.GetMessageId()...),
		},
		DetectedAt:          timestamppb.New(detectedAt),
		OrphanedSourceProof: proto.Clone(source.Proof).(*unifiedv1.CrossChainSourceEventProof),
		OrphanedEventEvidenceHash: append(
			[]byte(nil),
			source.Projection.SourceEvidenceHash[:]...,
		),
		ReplacementHeaderAuthorityHash:  append([]byte(nil), authority[:]...),
		ReplacementObserverSignature:    append([]byte(nil), localReplacementObserverSignature...),
		DetectedHeadHeaderAuthorityHash: append([]byte(nil), authority[:]...),
		DetectedHeadObserverSignature:   append([]byte(nil), localDetectedHeadObserverSignature...),
		FinalityPolicyHash:              append([]byte(nil), policy[:]...),
		OrphanedFinalityCertificate:     proto.Clone(source.Certificate).(*unifiedv1.CrossChainFinalityCertificate),
		AffectedOrphanedSourceProofs: []*unifiedv1.CrossChainSourceEventProof{
			proto.Clone(source.Proof).(*unifiedv1.CrossChainSourceEventProof),
		},
		AffectedOrphanedEventEvidenceHashes: [][]byte{
			append([]byte(nil), source.Projection.SourceEvidenceHash[:]...),
		},
		AffectedOrphanedFinalityCertificates: []*unifiedv1.CrossChainFinalityCertificate{
			proto.Clone(source.Certificate).(*unifiedv1.CrossChainFinalityCertificate),
		},
	}
	replacementCommitment, err := chaincrosschain.ComputeReorganizationHeaderCommitment(
		"REPLACEMENT",
		evidence,
	)
	if err != nil {
		return localReorganization{}, err
	}
	evidence.ReplacementObserverSignedHeaderCommitment = replacementCommitment[:]
	detectedCommitment, err := chaincrosschain.ComputeReorganizationHeaderCommitment(
		"DETECTED_HEAD",
		evidence,
	)
	if err != nil {
		return localReorganization{}, err
	}
	evidence.DetectedHeadObserverSignedHeaderCommitment = detectedCommitment[:]
	evidenceHash, err := chaincrosschain.ComputeReorganizationEvidenceHash(evidence)
	if err != nil {
		return localReorganization{}, err
	}
	evidence.EvidenceHash = evidenceHash[:]
	encoded, contentHash, err :=
		chaincrosschain.MarshalReorganizationEvidenceBlob(evidence)
	if err != nil {
		return localReorganization{}, err
	}
	key := fmt.Sprintf(
		"synthetic/reorganizations/%x.reorganization.pb",
		contentHash,
	)
	return localReorganization{
		Evidence:    evidence,
		Bytes:       encoded,
		ContentHash: contentHash,
		Key:         key,
		ReplacementObservation: store.HeaderObservationRecord{
			ObservationID: "header-observation:replacement:" +
				hex.EncodeToString(replacementCommitment[:]),
			ChainID:                        evidence.GetChainId(),
			BlockHash:                      bytes32(evidence.GetReplacementBlockHash()),
			BlockNumber:                    strconv.FormatUint(evidence.GetReplacementBlockNumber(), 10),
			HeaderAuthorityHash:            authority,
			ObserverSignedHeaderCommitment: replacementCommitment,
			ObserverSignature:              append([]byte(nil), evidence.GetReplacementObserverSignature()...),
			FinalityPolicyHash:             policy,
			ObservedAt:                     detectedAt.Add(-2 * time.Minute),
		},
		DetectedObservation: store.HeaderObservationRecord{
			ObservationID: "header-observation:detected-head:" +
				hex.EncodeToString(detectedCommitment[:]),
			ChainID:                        evidence.GetChainId(),
			BlockHash:                      bytes32(evidence.GetDetectedHeadHash()),
			BlockNumber:                    strconv.FormatUint(evidence.GetDetectedHeadNumber(), 10),
			HeaderAuthorityHash:            authority,
			ObserverSignedHeaderCommitment: detectedCommitment,
			ObserverSignature:              append([]byte(nil), evidence.GetDetectedHeadObserverSignature()...),
			FinalityPolicyHash:             policy,
			ObservedAt:                     detectedAt.Add(-time.Minute),
		},
	}, nil
}

func newLocalProjector(
	registration store.RouteRegistration,
) (*chaincrosschain.Projector, error) {
	projector, err := chaincrosschain.NewProjector(
		localReorganizationVerifier{
			registration:      registration,
			observerPublicKey: localObserverPublicKey,
		},
		chaincrosschain.ChainConfig{
			ChainID:            registration.SourceChain.ChainID,
			Coordinator:        registration.SourceChain.Coordinator[:],
			ConfigurationHash:  registration.SourceChain.ConfigurationHash,
			FinalityPolicyHash: registration.SourceFinalityPolicyHash,
			ObserverAuthority:  registration.SourceChain.ObserverAuthorityHash,
			RequiredDepth:      2,
		},
		chaincrosschain.ChainConfig{
			ChainID:            registration.DestinationChain.ChainID,
			Coordinator:        registration.DestinationChain.Coordinator[:],
			ConfigurationHash:  registration.DestinationChain.ConfigurationHash,
			FinalityPolicyHash: registration.DestinationFinalityPolicyHash,
			ObserverAuthority:  registration.DestinationChain.ObserverAuthorityHash,
			RequiredDepth:      2,
		},
	)
	if err != nil {
		return nil, err
	}
	if err := projector.BindRoute(
		registration.Route.RouteID,
		registration.Route.PolicyHash,
	); err != nil {
		return nil, err
	}
	return projector, nil
}

type persistedLocalReorganization struct {
	Record store.ReorganizationRecord
	Key    string
}

func persistLocalReorganization(
	ctx context.Context,
	observer *store.SQL,
	reorganizationVerifier *store.SQL,
	evidenceStore immutableEvidenceStore,
) (persistedLocalReorganization, error) {
	if observer == nil || reorganizationVerifier == nil || evidenceStore == nil {
		return persistedLocalReorganization{}, errors.New(
			"reorganization authority repositories are required",
		)
	}
	registration := localRegistration()
	envelope, _, err := localEnvelope(registration)
	if err != nil {
		return persistedLocalReorganization{}, err
	}
	source, err := authenticateSource(envelope, registration)
	if err != nil {
		return persistedLocalReorganization{}, err
	}
	reorganization, err := buildLocalReorganization(source, registration)
	if err != nil {
		return persistedLocalReorganization{}, err
	}
	projector, err := newLocalProjector(registration)
	if err != nil {
		return persistedLocalReorganization{}, err
	}
	if _, err := projector.ProjectSource(
		envelope,
		source.Proof,
		source.Certificate,
	); err != nil {
		return persistedLocalReorganization{}, err
	}
	if _, _, err := projector.ProjectReorganization(
		reorganization.Evidence,
	); err != nil {
		return persistedLocalReorganization{}, err
	}
	if err := evidenceStore.PutImmutable(
		ctx,
		reorganization.Key,
		reorganization.Bytes,
		reorganization.ContentHash,
	); err != nil {
		return persistedLocalReorganization{}, err
	}
	if _, err := observer.RecordHeaderObservation(
		ctx,
		reorganization.ReplacementObservation,
	); err != nil {
		return persistedLocalReorganization{}, err
	}
	if _, err := observer.RecordHeaderObservation(
		ctx,
		reorganization.DetectedObservation,
	); err != nil {
		return persistedLocalReorganization{}, err
	}
	record, err := reorganizationVerifier.RecordReorganization(
		ctx,
		store.ReorganizationRequest{
			RouteID:                registration.Route.RouteID,
			ChainID:                reorganization.Evidence.GetChainId(),
			OrphanedProofIDs:       []string{source.ProofRecord.ProofID},
			OrphanedCertificateIDs: []string{source.CertificateRecord.CertificateID},
			ReplacementObservationID: reorganization.
				ReplacementObservation.ObservationID,
			DetectedHeadObservationID: reorganization.
				DetectedObservation.ObservationID,
			AffectedMessageIDs: [][32]byte{
				bytes32(reorganization.Evidence.GetAffectedMessageIds()[0]),
			},
			EvidenceHash: reorganization.ContentHash,
			DetectedAt:   reorganization.Evidence.GetDetectedAt().AsTime(),
		},
	)
	if err != nil {
		return persistedLocalReorganization{}, err
	}
	return persistedLocalReorganization{
		Record: record,
		Key:    reorganization.Key,
	}, nil
}

func rehydrateLocalReorganization(
	ctx context.Context,
	runtime *store.SQL,
	evidenceStore immutableEvidenceStore,
	expectedHash [32]byte,
) (store.MessageRecord, error) {
	if runtime == nil || evidenceStore == nil || expectedHash == ([32]byte{}) {
		return store.MessageRecord{}, errors.New("rehydration inputs are required")
	}
	record, err := runtime.Reorganization(ctx, expectedHash)
	if err != nil {
		return store.MessageRecord{}, err
	}
	key := fmt.Sprintf(
		"synthetic/reorganizations/%x.reorganization.pb",
		expectedHash,
	)
	blob, err := evidenceStore.GetImmutable(ctx, key, expectedHash)
	if err != nil {
		return store.MessageRecord{}, err
	}
	evidence, err := chaincrosschain.UnmarshalReorganizationEvidenceBlob(
		blob,
		expectedHash,
	)
	if err != nil || len(evidence.GetAffectedMessageIds()) != 1 {
		return store.MessageRecord{}, errors.New(
			"durable reorganization evidence failed authentication",
		)
	}
	messageID := bytes32(evidence.GetAffectedMessageIds()[0])
	messageRecord, err := runtime.Message(messageID)
	if err != nil {
		return store.MessageRecord{}, err
	}
	if messageRecord.State !=
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_DISPUTED ||
		messageRecord.Evidence != expectedHash {
		return store.MessageRecord{}, errors.New(
			"reorganization did not durably dispute the affected message",
		)
	}
	var envelope unifiedv1.CrossChainMessageEnvelope
	if err := proto.Unmarshal(messageRecord.Envelope, &envelope); err != nil {
		return store.MessageRecord{}, err
	}
	projector, err := newLocalProjector(localRegistration())
	if err != nil {
		return store.MessageRecord{}, err
	}
	if _, err := projector.ProjectSource(
		&envelope,
		evidence.GetAffectedOrphanedSourceProofs()[0],
		evidence.GetAffectedOrphanedFinalityCertificates()[0],
	); err != nil {
		return store.MessageRecord{}, err
	}
	incident, affected, err := projector.ProjectReorganization(evidence)
	if err != nil || len(affected) != 1 || !affected[0].Disputed {
		return store.MessageRecord{}, errors.New(
			"restarted projector did not restore the dispute",
		)
	}
	proofHash, err := chaincrosschain.ComputeSourceProofHash(
		evidence.GetAffectedOrphanedSourceProofs()[0],
	)
	if err != nil {
		return store.MessageRecord{}, err
	}
	expectedProofID := "source-proof:" + hex.EncodeToString(proofHash[:])
	expectedCertificateID := "finality-certificate:" + hex.EncodeToString(
		evidence.GetAffectedOrphanedFinalityCertificates()[0].
			GetCertificateHash(),
	)
	expected := store.ReorganizationRecord{
		ReorganizationID:      "crosschain-reorg:" + hex.EncodeToString(expectedHash[:]),
		RouteID:               incident.GetRouteId().GetValue(),
		ChainID:               evidence.GetChainId(),
		OrphanedBlockHash:     bytes32(evidence.GetOrphanedBlockHash()),
		OrphanedBlockNumber:   strconv.FormatUint(evidence.GetBlockNumber(), 10),
		OrphanedProofID:       expectedProofID,
		OrphanedCertificateID: expectedCertificateID,
		OrphanedProofIDs:      []string{expectedProofID},
		OrphanedCertificateIDs: []string{
			expectedCertificateID,
		},
		ReplacementBlockHash: bytes32(evidence.GetReplacementBlockHash()),
		ReplacementBlockNumber: strconv.FormatUint(
			evidence.GetReplacementBlockNumber(),
			10,
		),
		ReplacementObservationID: "header-observation:replacement:" +
			hex.EncodeToString(
				evidence.GetReplacementObserverSignedHeaderCommitment(),
			),
		DetectedHeadHash: bytes32(evidence.GetDetectedHeadHash()),
		DetectedHeadNumber: strconv.FormatUint(
			evidence.GetDetectedHeadNumber(),
			10,
		),
		DetectedHeadObservationID: "header-observation:detected-head:" +
			hex.EncodeToString(
				evidence.GetDetectedHeadObserverSignedHeaderCommitment(),
			),
		DepthClass:         "DEEP_FINALITY",
		AffectedMessageIDs: [][32]byte{messageID},
		EvidenceHash:       expectedHash,
		DetectedAt:         evidence.GetDetectedAt().AsTime().UTC(),
		IncidentID:         incident.GetIncidentId().GetValue(),
		IncidentReasonCode: incident.GetReasonCode(),
		IncidentSeverity:   "CRITICAL",
		IncidentOwner:      incident.GetOwner(),
		IncidentStatus:     incident.GetStatus(),
		IncidentOpenedAt:   incident.GetOpenedAt().AsTime().UTC(),
	}
	if !sameLocalReorganizationRecord(record, expected) {
		return store.MessageRecord{}, errors.New(
			"SQL and projector reorganization identities diverged",
		)
	}
	return messageRecord, nil
}

func sameLocalReorganizationRecord(
	left store.ReorganizationRecord,
	right store.ReorganizationRecord,
) bool {
	if left.ReorganizationID != right.ReorganizationID ||
		left.RouteID != right.RouteID ||
		left.ChainID != right.ChainID ||
		left.OrphanedBlockHash != right.OrphanedBlockHash ||
		left.OrphanedBlockNumber != right.OrphanedBlockNumber ||
		left.OrphanedProofID != right.OrphanedProofID ||
		left.OrphanedCertificateID != right.OrphanedCertificateID ||
		left.ReplacementBlockHash != right.ReplacementBlockHash ||
		left.ReplacementBlockNumber != right.ReplacementBlockNumber ||
		left.ReplacementObservationID != right.ReplacementObservationID ||
		left.DetectedHeadHash != right.DetectedHeadHash ||
		left.DetectedHeadNumber != right.DetectedHeadNumber ||
		left.DetectedHeadObservationID != right.DetectedHeadObservationID ||
		left.DepthClass != right.DepthClass ||
		left.EvidenceHash != right.EvidenceHash ||
		!left.DetectedAt.Equal(right.DetectedAt) ||
		left.IncidentID != right.IncidentID ||
		left.IncidentReasonCode != right.IncidentReasonCode ||
		left.IncidentSeverity != right.IncidentSeverity ||
		left.IncidentOwner != right.IncidentOwner ||
		left.IncidentStatus != right.IncidentStatus ||
		!left.IncidentOpenedAt.Equal(right.IncidentOpenedAt) ||
		len(left.OrphanedProofIDs) != len(right.OrphanedProofIDs) ||
		len(left.OrphanedCertificateIDs) != len(right.OrphanedCertificateIDs) ||
		len(left.AffectedMessageIDs) != len(right.AffectedMessageIDs) {
		return false
	}
	for index := range left.OrphanedProofIDs {
		if left.OrphanedProofIDs[index] != right.OrphanedProofIDs[index] ||
			left.OrphanedCertificateIDs[index] !=
				right.OrphanedCertificateIDs[index] ||
			left.AffectedMessageIDs[index] != right.AffectedMessageIDs[index] {
			return false
		}
	}
	return true
}

type finalityCertificateEvidence struct {
	Hash       [32]byte
	Signatures [][]byte
}

func localFinalityCertificate(
	envelope *unifiedv1.CrossChainMessageEnvelope,
	proofHash [32]byte,
	registration store.RouteRegistration,
) (finalityCertificateEvidence, error) {
	digest, err := localFinalityDigest(
		registration.DestinationChain.ChainID,
		registration.DestinationChain.FinalityVerifier,
		bytes32(envelope.GetMessageId()),
		proofHash,
		registration.SourceSignerSetHash,
		registration.SourceSignerSetVersion,
	)
	if err != nil {
		return finalityCertificateEvidence{}, err
	}
	seen := make(map[[20]byte]struct{}, 2)
	signatures := make([][]byte, len(localFinalitySignatures))
	for index, signature := range localFinalitySignatures {
		recovered, recoverErr := recovery.VerifyEthereumSignature(digest, signature)
		if recoverErr != nil {
			return finalityCertificateEvidence{}, errors.New(
				"synthetic finality certificate signature rejected",
			)
		}
		approved := false
		for _, signer := range localFinalitySigners {
			if recovered == signer {
				approved = true
				break
			}
		}
		if !approved {
			return finalityCertificateEvidence{}, errors.New(
				"synthetic finality certificate signer is not approved",
			)
		}
		if _, duplicate := seen[recovered]; duplicate {
			return finalityCertificateEvidence{}, errors.New(
				"duplicate synthetic finality certificate signer",
			)
		}
		seen[recovered] = struct{}{}
		signatures[index] = append([]byte(nil), signature...)
	}
	if len(seen) != 2 {
		return finalityCertificateEvidence{}, errors.New(
			"synthetic finality certificate is below threshold",
		)
	}
	signatureOneHash := keccak(signatures[0])
	signatureTwoHash := keccak(signatures[1])
	certificateHash := abiHash(
		"UNIFIED_SYNTHETIC_FINALITY_CERTIFICATE_RECORD_V1",
		wordBytes32(bytes32(envelope.GetMessageId())),
		wordBytes32(proofHash),
		wordBytes32(registration.SourceSignerSetHash),
		wordUint64(registration.SourceSignerSetVersion),
		wordBytes32(signatureOneHash),
		wordBytes32(signatureTwoHash),
	)
	return finalityCertificateEvidence{
		Hash: certificateHash, Signatures: signatures,
	}, nil
}

func localFinalityDigest(
	chainID string,
	verifier [20]byte,
	messageID [32]byte,
	proofHash [32]byte,
	signerSetHash [32]byte,
	signerSetVersion uint64,
) ([32]byte, error) {
	chainWord, err := wordUint256(chainID)
	if err != nil || verifier == ([20]byte{}) ||
		messageID == ([32]byte{}) || proofHash == ([32]byte{}) ||
		signerSetHash == ([32]byte{}) || signerSetVersion == 0 {
		return [32]byte{}, errors.New("invalid synthetic finality digest input")
	}
	return abiHash(
		"UNIFIED_SYNTHETIC_FINALITY_V1",
		chainWord,
		wordAddress(verifier),
		wordBytes32(messageID),
		wordBytes32(proofHash),
		wordBytes32(signerSetHash),
		wordUint64(signerSetVersion),
	), nil
}

func localSignerSetHash(observerAuthority [32]byte) [32]byte {
	sorted := localSortedFinalitySigners()
	return abiHash(
		"UNIFIED_SYNTHETIC_SIGNER_SET_V1",
		wordBytes32(observerAuthority),
		wordUint64(1),
		wordAddress(sorted[0]),
		wordAddress(sorted[1]),
		wordAddress(sorted[2]),
		wordUint64(2),
		wordUint64(uint64(localBaseTime.Add(-time.Hour).Unix())),
		wordUint64(uint64(localBaseTime.Add(24*time.Hour).Unix())),
	)
}

func localSortedFinalitySigners() [3][20]byte {
	sorted := localFinalitySigners
	for left := 0; left < len(sorted)-1; left++ {
		for right := left + 1; right < len(sorted); right++ {
			if bytes.Compare(sorted[left][:], sorted[right][:]) > 0 {
				sorted[left], sorted[right] = sorted[right], sorted[left]
			}
		}
	}
	return sorted
}

func abiHash(domain string, words ...[]byte) [32]byte {
	encoded := make([]byte, 0, (len(words)+3)*32)
	encoded = append(encoded, wordUint64(uint64((len(words)+1)*32))...)
	for _, word := range words {
		if len(word) != 32 {
			panic("ABI word is not 32 bytes")
		}
		encoded = append(encoded, word...)
	}
	encoded = append(encoded, wordUint64(uint64(len(domain)))...)
	encoded = append(encoded, []byte(domain)...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	return keccak(encoded)
}

func wordBytes32(value [32]byte) []byte {
	return append([]byte(nil), value[:]...)
}

func wordAddress(value [20]byte) []byte {
	result := make([]byte, 32)
	copy(result[12:], value[:])
	return result
}

func wordUint64(value uint64) []byte {
	result := make([]byte, 32)
	for index := 0; index < 8; index++ {
		result[31-index] = byte(value)
		value >>= 8
	}
	return result
}

func wordUint256(value string) ([]byte, error) {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() <= 0 || number.BitLen() > 256 ||
		number.String() != value {
		return nil, errors.New("invalid uint256")
	}
	result := make([]byte, 32)
	number.FillBytes(result)
	return result, nil
}

func wordNonnegativeUint256(value string) ([]byte, error) {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() < 0 || number.BitLen() > 256 ||
		number.String() != value {
		return nil, errors.New("invalid nonnegative uint256")
	}
	result := make([]byte, 32)
	number.FillBytes(result)
	return result, nil
}

type localCrossChainPolicyDefinition struct {
	ProtocolID                   [32]byte
	RouteID                      string
	RouteVersion                 uint64
	SourceConfigurationHash      [32]byte
	DestinationConfigurationHash [32]byte
	SourceComponent              [20]byte
	DestinationComponent         [20]byte
	ActionFamily                 string
	MessageTimeoutSeconds        uint64
	RecoveryAction               uint8
	RecoveryAuthorizerSetHash    [32]byte
	RecoveryAuthorizerSetVersion uint32
}

// localCrossChainPolicyCommitment is deliberately nonrecursive: it excludes
// route, adapter-set, and finality-policy hashes. Those commitments bind this
// value, while the envelope and finality certificate separately bind the final
// route policy.
func localCrossChainPolicyCommitment(
	policy localCrossChainPolicyDefinition,
) ([32]byte, error) {
	if policy.ProtocolID == ([32]byte{}) || policy.RouteID == "" ||
		policy.RouteVersion == 0 || policy.RouteVersion > math.MaxInt64 ||
		policy.SourceConfigurationHash == ([32]byte{}) ||
		policy.DestinationConfigurationHash == ([32]byte{}) ||
		policy.SourceComponent == ([20]byte{}) ||
		policy.DestinationComponent == ([20]byte{}) ||
		policy.ActionFamily == "" || policy.MessageTimeoutSeconds == 0 ||
		policy.RecoveryAction == 0 ||
		policy.RecoveryAuthorizerSetHash == ([32]byte{}) ||
		policy.RecoveryAuthorizerSetVersion == 0 {
		return [32]byte{}, errors.New(
			"invalid local cross-chain policy definition",
		)
	}
	return abiHash(
		"UNIFIED_LOCAL_CROSS_CHAIN_POLICY_V1",
		wordBytes32(policy.ProtocolID),
		wordBytes32(keccak([]byte(policy.RouteID))),
		wordUint64(policy.RouteVersion),
		wordBytes32(policy.SourceConfigurationHash),
		wordBytes32(policy.DestinationConfigurationHash),
		wordAddress(policy.SourceComponent),
		wordAddress(policy.DestinationComponent),
		wordBytes32(keccak([]byte(policy.ActionFamily))),
		wordUint64(policy.MessageTimeoutSeconds),
		wordUint64(uint64(policy.RecoveryAction)),
		wordBytes32(policy.RecoveryAuthorizerSetHash),
		wordUint64(uint64(policy.RecoveryAuthorizerSetVersion)),
	), nil
}

func localCrossChainPolicyForRegistration(
	registration store.RouteRegistration,
) (localCrossChainPolicyDefinition, error) {
	authorizerSetHash, err := recovery.AuthorizerSetHash(
		1,
		localFinalitySigners,
	)
	if err != nil {
		return localCrossChainPolicyDefinition{}, err
	}
	return localCrossChainPolicyDefinition{
		ProtocolID:                   bytes32(repeatedBytes(0x01, 32)),
		RouteID:                      registration.Route.RouteID,
		RouteVersion:                 registration.Route.Version,
		SourceConfigurationHash:      registration.SourceChain.ConfigurationHash,
		DestinationConfigurationHash: registration.DestinationChain.ConfigurationHash,
		SourceComponent:              registration.SourceComponent,
		DestinationComponent:         registration.DestinationComponent,
		ActionFamily:                 registration.ActionFamily,
		MessageTimeoutSeconds:        uint64((24 * time.Hour) / time.Second),
		RecoveryAction:               1,
		RecoveryAuthorizerSetHash:    authorizerSetHash,
		RecoveryAuthorizerSetVersion: 1,
	}, nil
}

type localFinalityPolicyDefinition struct {
	ChainID              string
	ConfigurationHash    [32]byte
	SourceContract       [20]byte
	RequiredDepth        uint64
	ObserverAuthority    [32]byte
	SignerSetHash        [32]byte
	Threshold            uint32
	SignerSetVersion     uint32
	CrossChainPolicyHash [32]byte
	ActionFamily         string
}

func localFinalityPolicyCommitment(
	policy localFinalityPolicyDefinition,
) ([32]byte, error) {
	if policy.ConfigurationHash == ([32]byte{}) ||
		policy.SourceContract == ([20]byte{}) ||
		policy.RequiredDepth == 0 ||
		policy.ObserverAuthority == ([32]byte{}) ||
		policy.SignerSetHash == ([32]byte{}) || policy.Threshold == 0 ||
		policy.SignerSetVersion == 0 ||
		policy.CrossChainPolicyHash == ([32]byte{}) ||
		policy.ActionFamily == "" {
		return [32]byte{}, errors.New("invalid local finality policy definition")
	}
	chainID, err := wordUint256(policy.ChainID)
	if err != nil {
		return [32]byte{}, fmt.Errorf("finality-policy chain ID: %w", err)
	}
	return abiHash(
		"UNIFIED_LOCAL_FINALITY_POLICY_V1",
		chainID,
		wordBytes32(policy.ConfigurationHash),
		wordAddress(policy.SourceContract),
		wordUint64(policy.RequiredDepth),
		wordBytes32(policy.ObserverAuthority),
		wordBytes32(policy.SignerSetHash),
		wordUint64(uint64(policy.Threshold)),
		wordUint64(uint64(policy.SignerSetVersion)),
		wordBytes32(policy.CrossChainPolicyHash),
		wordBytes32(keccak([]byte(policy.ActionFamily))),
	), nil
}

type localAdapterAuthority struct {
	ProviderID string
	Authority  string
}

func localAdapterAuthorities() []localAdapterAuthority {
	return []localAdapterAuthority{
		{ProviderID: localProviderAID, Authority: "TRANSPORT_ONLY"},
		{ProviderID: localProviderBID, Authority: "TRANSPORT_ONLY"},
	}
}

func localAdapterSetPolicyCommitment(
	authorities []localAdapterAuthority,
) ([32]byte, error) {
	if len(authorities) == 0 || len(authorities) > 16 {
		return [32]byte{}, errors.New("invalid local adapter-set size")
	}
	canonical := append([]localAdapterAuthority(nil), authorities...)
	sort.Slice(canonical, func(left, right int) bool {
		if canonical[left].ProviderID == canonical[right].ProviderID {
			return canonical[left].Authority < canonical[right].Authority
		}
		return canonical[left].ProviderID < canonical[right].ProviderID
	})
	words := make([][]byte, 0, 1+(2*len(canonical)))
	words = append(words, wordUint64(uint64(len(canonical))))
	seen := make(map[string]struct{}, len(canonical))
	for _, authority := range canonical {
		if authority.ProviderID == "" || authority.Authority == "" {
			return [32]byte{}, errors.New(
				"adapter identity and authority are required",
			)
		}
		if _, duplicate := seen[authority.ProviderID]; duplicate {
			return [32]byte{}, errors.New("duplicate local adapter identity")
		}
		seen[authority.ProviderID] = struct{}{}
		words = append(
			words,
			wordBytes32(keccak([]byte(authority.ProviderID))),
			wordBytes32(keccak([]byte(authority.Authority))),
		)
	}
	return abiHash("UNIFIED_LOCAL_ADAPTER_SET_POLICY_V1", words...), nil
}

// localChainConfigurationHash is the synthetic deployment's canonical chain
// authority commitment. The field order is frozen as chain ID, version,
// coordinator, finality verifier, observer authority, and activation block.
// ConfigurationHash is intentionally excluded to avoid self-reference.
func localChainConfigurationHash(
	chain store.ChainRegistration,
) ([32]byte, error) {
	if chain.Version == 0 || chain.Version > math.MaxUint32 {
		return [32]byte{}, errors.New("chain version is not canonical uint32")
	}
	chainID, err := wordUint256(chain.ChainID)
	if err != nil {
		return [32]byte{}, fmt.Errorf("chain ID: %w", err)
	}
	activatedAtBlock, err := wordNonnegativeUint256(chain.ActivatedAtBlock)
	if err != nil {
		return [32]byte{}, fmt.Errorf("chain activation block: %w", err)
	}
	return abiHash(
		"UNIFIED_LOCAL_CHAIN_CONFIGURATION_V1",
		chainID,
		wordUint64(chain.Version),
		wordAddress(chain.Coordinator),
		wordAddress(chain.FinalityVerifier),
		wordBytes32(chain.ObserverAuthorityHash),
		activatedAtBlock,
	), nil
}

// localRoutePolicyHash commits every RouteRegistration field except the route
// policy hash itself. Strings are committed as keccak256(UTF-8), and nested
// chain registrations include their canonical configuration hashes.
func localRoutePolicyHash(
	registration store.RouteRegistration,
) ([32]byte, error) {
	route := registration.Route
	if route.Version == 0 || route.Version > math.MaxInt64 {
		return [32]byte{}, errors.New("route version is not canonical")
	}
	if route.ActivatedAt.IsZero() || route.ActivatedAt.Unix() < 0 ||
		route.ActivatedAt.Nanosecond() != 0 {
		return [32]byte{}, errors.New("route activation time is not canonical")
	}
	if registration.SourceSignerSetVersion == 0 ||
		registration.SourceSignerSetVersion > math.MaxUint32 ||
		registration.DestinationSignerSetVersion == 0 ||
		registration.DestinationSignerSetVersion > math.MaxUint32 {
		return [32]byte{}, errors.New("signer-set version is not canonical uint32")
	}
	sourceChainID, err := wordUint256(registration.SourceChain.ChainID)
	if err != nil {
		return [32]byte{}, fmt.Errorf("source chain ID: %w", err)
	}
	sourceActivatedAtBlock, err := wordNonnegativeUint256(
		registration.SourceChain.ActivatedAtBlock,
	)
	if err != nil {
		return [32]byte{}, fmt.Errorf("source chain activation block: %w", err)
	}
	destinationChainID, err := wordUint256(
		registration.DestinationChain.ChainID,
	)
	if err != nil {
		return [32]byte{}, fmt.Errorf("destination chain ID: %w", err)
	}
	destinationActivatedAtBlock, err := wordNonnegativeUint256(
		registration.DestinationChain.ActivatedAtBlock,
	)
	if err != nil {
		return [32]byte{}, fmt.Errorf(
			"destination chain activation block: %w",
			err,
		)
	}
	routeActivatedAtBlock, err := wordNonnegativeUint256(
		registration.ActivatedAtBlock,
	)
	if err != nil {
		return [32]byte{}, fmt.Errorf("route activation block: %w", err)
	}
	deprecatedPresent := uint64(0)
	deprecatedAt := uint64(0)
	if route.DeprecatedAt != nil {
		if route.DeprecatedAt.Unix() < 0 ||
			route.DeprecatedAt.Nanosecond() != 0 {
			return [32]byte{}, errors.New(
				"route deprecation time is not canonical",
			)
		}
		deprecatedPresent = 1
		deprecatedAt = uint64(route.DeprecatedAt.Unix())
	}

	// Frozen order: route identity/lifecycle; complete source chain;
	// complete destination chain; components/action; adapter/finality/signer
	// authorities; and the route activation block.
	return abiHash(
		"UNIFIED_LOCAL_ROUTE_REGISTRATION_V1",
		wordBytes32(keccak([]byte(route.RouteID))),
		wordUint64(route.Version),
		wordBytes32(keccak([]byte(route.SourceChain))),
		wordBytes32(keccak([]byte(route.DestinationChain))),
		wordUint64(uint64(route.ActivatedAt.Unix())),
		wordUint64(deprecatedPresent),
		wordUint64(deprecatedAt),
		sourceChainID,
		wordUint64(registration.SourceChain.Version),
		wordAddress(registration.SourceChain.Coordinator),
		wordAddress(registration.SourceChain.FinalityVerifier),
		wordBytes32(registration.SourceChain.ConfigurationHash),
		wordBytes32(registration.SourceChain.ObserverAuthorityHash),
		sourceActivatedAtBlock,
		destinationChainID,
		wordUint64(registration.DestinationChain.Version),
		wordAddress(registration.DestinationChain.Coordinator),
		wordAddress(registration.DestinationChain.FinalityVerifier),
		wordBytes32(registration.DestinationChain.ConfigurationHash),
		wordBytes32(registration.DestinationChain.ObserverAuthorityHash),
		destinationActivatedAtBlock,
		wordAddress(registration.SourceComponent),
		wordAddress(registration.DestinationComponent),
		wordBytes32(keccak([]byte(registration.ActionFamily))),
		wordBytes32(registration.AdapterSetPolicyHash),
		wordBytes32(registration.SourceFinalityPolicyHash),
		wordBytes32(registration.DestinationFinalityPolicyHash),
		wordBytes32(registration.SourceSignerSetHash),
		wordUint64(registration.SourceSignerSetVersion),
		wordBytes32(registration.DestinationSignerSetHash),
		wordUint64(registration.DestinationSignerSetVersion),
		routeActivatedAtBlock,
	), nil
}

func validateLocalRegistrationCommitments(
	registration store.RouteRegistration,
) error {
	if registration.Route.SourceChain != registration.SourceChain.ChainID ||
		registration.Route.DestinationChain !=
			registration.DestinationChain.ChainID {
		return errors.New("route and chain identities diverged")
	}
	sourceConfiguration, err := localChainConfigurationHash(
		registration.SourceChain,
	)
	if err != nil {
		return err
	}
	if sourceConfiguration != registration.SourceChain.ConfigurationHash {
		return errors.New("source chain configuration commitment drifted")
	}
	destinationConfiguration, err := localChainConfigurationHash(
		registration.DestinationChain,
	)
	if err != nil {
		return err
	}
	if destinationConfiguration !=
		registration.DestinationChain.ConfigurationHash {
		return errors.New("destination chain configuration commitment drifted")
	}
	crossChainPolicy, err := localCrossChainPolicyForRegistration(registration)
	if err != nil {
		return err
	}
	crossChainPolicyHash, err := localCrossChainPolicyCommitment(
		crossChainPolicy,
	)
	if err != nil {
		return err
	}
	adapterSetPolicy, err := localAdapterSetPolicyCommitment(
		localAdapterAuthorities(),
	)
	if err != nil {
		return err
	}
	if adapterSetPolicy != registration.AdapterSetPolicyHash {
		return errors.New("adapter-set policy commitment drifted")
	}
	sourceFinalityPolicy, err := localFinalityPolicyCommitment(
		localFinalityPolicyDefinition{
			ChainID:              registration.SourceChain.ChainID,
			ConfigurationHash:    registration.SourceChain.ConfigurationHash,
			SourceContract:       registration.SourceChain.Coordinator,
			RequiredDepth:        2,
			ObserverAuthority:    registration.SourceChain.ObserverAuthorityHash,
			SignerSetHash:        registration.SourceSignerSetHash,
			Threshold:            2,
			SignerSetVersion:     uint32(registration.SourceSignerSetVersion),
			CrossChainPolicyHash: crossChainPolicyHash,
			ActionFamily:         registration.ActionFamily,
		},
	)
	if err != nil {
		return err
	}
	if sourceFinalityPolicy != registration.SourceFinalityPolicyHash {
		return errors.New("source finality-policy commitment drifted")
	}
	destinationFinalityPolicy, err := localFinalityPolicyCommitment(
		localFinalityPolicyDefinition{
			ChainID:              registration.DestinationChain.ChainID,
			ConfigurationHash:    registration.DestinationChain.ConfigurationHash,
			SourceContract:       registration.DestinationChain.Coordinator,
			RequiredDepth:        2,
			ObserverAuthority:    registration.DestinationChain.ObserverAuthorityHash,
			SignerSetHash:        registration.DestinationSignerSetHash,
			Threshold:            2,
			SignerSetVersion:     uint32(registration.DestinationSignerSetVersion),
			CrossChainPolicyHash: crossChainPolicyHash,
			ActionFamily:         registration.ActionFamily,
		},
	)
	if err != nil {
		return err
	}
	if destinationFinalityPolicy !=
		registration.DestinationFinalityPolicyHash {
		return errors.New("destination finality-policy commitment drifted")
	}
	routePolicy, err := localRoutePolicyHash(registration)
	if err != nil {
		return err
	}
	if routePolicy != registration.Route.PolicyHash {
		return errors.New("route policy commitment drifted")
	}
	return nil
}

func localRegistration() store.RouteRegistration {
	activatedAt := localBaseTime.Add(-time.Hour)
	sourceObserver := keccak(localObserverPublicKey)
	destinationObserver := keccak(localDestinationObserverPublicKey)
	registration := store.RouteRegistration{
		Route: store.RouteVersion{
			RouteID:          localRouteID,
			Version:          1,
			SourceChain:      localSourceID,
			DestinationChain: localDestinationID,
			ActivatedAt:      activatedAt,
		},
		SourceChain: store.ChainRegistration{
			ChainID:               localSourceID,
			Version:               1,
			Coordinator:           repeated20(0x11),
			FinalityVerifier:      repeated20(0x12),
			ObserverAuthorityHash: sourceObserver,
			ActivatedAtBlock:      "1",
		},
		DestinationChain: store.ChainRegistration{
			ChainID:               localDestinationID,
			Version:               1,
			Coordinator:           repeated20(0x21),
			FinalityVerifier:      repeated20(0x22),
			ObserverAuthorityHash: destinationObserver,
			ActivatedAtBlock:      "1",
		},
		SourceComponent:             repeated20(0x13),
		DestinationComponent:        repeated20(0x23),
		ActionFamily:                localActionFamily,
		SourceSignerSetHash:         localSignerSetHash(sourceObserver),
		SourceSignerSetVersion:      1,
		DestinationSignerSetHash:    localSignerSetHash(destinationObserver),
		DestinationSignerSetVersion: 1,
		ActivatedAtBlock:            "1",
	}
	sourceConfiguration, err := localChainConfigurationHash(
		registration.SourceChain,
	)
	if err != nil {
		panic(err)
	}
	registration.SourceChain.ConfigurationHash = sourceConfiguration
	destinationConfiguration, err := localChainConfigurationHash(
		registration.DestinationChain,
	)
	if err != nil {
		panic(err)
	}
	registration.DestinationChain.ConfigurationHash =
		destinationConfiguration
	crossChainPolicy, err := localCrossChainPolicyForRegistration(registration)
	if err != nil {
		panic(err)
	}
	crossChainPolicyHash, err := localCrossChainPolicyCommitment(
		crossChainPolicy,
	)
	if err != nil {
		panic(err)
	}
	registration.AdapterSetPolicyHash, err =
		localAdapterSetPolicyCommitment(localAdapterAuthorities())
	if err != nil {
		panic(err)
	}
	registration.SourceFinalityPolicyHash, err =
		localFinalityPolicyCommitment(localFinalityPolicyDefinition{
			ChainID:              registration.SourceChain.ChainID,
			ConfigurationHash:    registration.SourceChain.ConfigurationHash,
			SourceContract:       registration.SourceChain.Coordinator,
			RequiredDepth:        2,
			ObserverAuthority:    registration.SourceChain.ObserverAuthorityHash,
			SignerSetHash:        registration.SourceSignerSetHash,
			Threshold:            2,
			SignerSetVersion:     uint32(registration.SourceSignerSetVersion),
			CrossChainPolicyHash: crossChainPolicyHash,
			ActionFamily:         registration.ActionFamily,
		})
	if err != nil {
		panic(err)
	}
	registration.DestinationFinalityPolicyHash, err =
		localFinalityPolicyCommitment(localFinalityPolicyDefinition{
			ChainID:              registration.DestinationChain.ChainID,
			ConfigurationHash:    registration.DestinationChain.ConfigurationHash,
			SourceContract:       registration.DestinationChain.Coordinator,
			RequiredDepth:        2,
			ObserverAuthority:    registration.DestinationChain.ObserverAuthorityHash,
			SignerSetHash:        registration.DestinationSignerSetHash,
			Threshold:            2,
			SignerSetVersion:     uint32(registration.DestinationSignerSetVersion),
			CrossChainPolicyHash: crossChainPolicyHash,
			ActionFamily:         registration.ActionFamily,
		})
	if err != nil {
		panic(err)
	}
	routePolicy, err := localRoutePolicyHash(registration)
	if err != nil {
		panic(err)
	}
	registration.Route.PolicyHash = routePolicy
	if err := validateLocalRegistrationCommitments(registration); err != nil {
		panic(err)
	}
	return registration
}

func localEnvelope(
	registration store.RouteRegistration,
) (*unifiedv1.CrossChainMessageEnvelope, []byte, error) {
	zero := make([]byte, 32)
	envelope := &unifiedv1.CrossChainMessageEnvelope{
		SchemaVersion:          1,
		ProtocolId:             repeatedBytes(0x01, 32),
		SourceChainId:          registration.SourceChain.ChainID,
		SourceCoordinator:      registration.SourceChain.Coordinator[:],
		SourceComponent:        registration.SourceComponent[:],
		DestinationChainId:     registration.DestinationChain.ChainID,
		DestinationCoordinator: registration.DestinationChain.Coordinator[:],
		DestinationComponent:   registration.DestinationComponent[:],
		LaneId:                 repeatedBytes(0x41, 32),
		SourceNonce:            1,
		AggregateId:            repeatedBytes(0x42, 32),
		ActionType:             unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_CanonicalUftLock{
			CanonicalUftLock: &unifiedv1.CanonicalUftLockPayload{
				LockId:               repeatedBytes(0x43, 32),
				LoanId:               repeatedBytes(0x44, 32),
				CanonicalToken:       repeatedBytes(0x45, 20),
				HomeBridgeHub:        repeatedBytes(0x46, 20),
				WrappedToken:         repeatedBytes(0x47, 20),
				DestinationRecipient: repeatedBytes(0x48, 20),
				Amount:               "1",
			},
		},
		CreatedAt:                     timestamppb.New(localBaseTime),
		ExpiresAt:                     timestamppb.New(localBaseTime.Add(24 * time.Hour)),
		RoutePolicyHash:               registration.Route.PolicyHash[:],
		AdapterSetPolicyHash:          registration.AdapterSetPolicyHash[:],
		SourceFinalityPolicyHash:      registration.SourceFinalityPolicyHash[:],
		DestinationFinalityPolicyHash: registration.DestinationFinalityPolicyHash[:],
		CorrelationId:                 repeatedBytes(0x49, 32),
		CausationMessageId:            zero,
		SupersededMessageId:           zero,
	}
	if err := message.BindTypedActionABI(envelope); err != nil {
		return nil, nil, err
	}
	sealed, err := message.Seal(envelope)
	if err != nil {
		return nil, nil, err
	}
	serialized, err := message.DeterministicBytes(sealed)
	return sealed, serialized, err
}

func runReconciliation(messageID [32]byte) error {
	result, err := reconciliation.Compare(reconciliation.Snapshot{
		RouteID:                     localRouteID,
		CanonicalEscrowUnits:        "0",
		WrappedSupplyUnits:          "0",
		FinalizedPendingMintUnits:   "0",
		FinalizedPendingBurnUnits:   "0",
		HubTokenBalanceUnits:        "0",
		RouteObligationsUnits:       "0",
		HubSurplusUnits:             "0",
		RouteExposureUnits:          "0",
		RouteExposureCapUnits:       "0",
		AggregateExposureUnits:      "0",
		AggregateExposureCapUnits:   "0",
		CollateralCustodyUnits:      "0",
		CollateralPositionUnits:     "0",
		SettlementVaultUnits:        "0",
		SettlementAuthorizedUnits:   "0",
		CanonicalDebtUnits:          "0",
		LedgerDebtUnits:             "0",
		CanonicalLenderReleaseUnits: "0",
		LedgerLenderReleaseUnits:    "0",
		JournalBridgeControlUnits:   "0",
		ChainBridgeControlUnits:     "0",
		ChainMessageCount:           1,
		SQLMessageCount:             1,
		ChainNonce:                  1,
		SQLNonce:                    1,
		EvidenceHash:                hex.EncodeToString(messageID[:]),
		AsOf:                        localBaseTime.Add(30 * time.Minute),
	}, "local-worker", localBaseTime.Add(time.Hour))
	if err != nil {
		return err
	}
	if len(result.Differences) != 0 || result.PauseRoute || result.OpenIncident {
		return errors.New("local reconciliation produced a difference")
	}
	return nil
}

type localRecoveryDestination struct {
	requestedAt time.Time
}

func (destination localRecoveryDestination) ExecutionResult([32]byte) ([32]byte, bool) {
	return [32]byte{}, false
}

func (destination localRecoveryDestination) CreateTombstone(
	request recovery.Request,
) (recovery.Tombstone, error) {
	return recovery.Tombstone{
		OriginalMessageID: request.OriginalMessageID,
		Hash:              keccak([]byte("LOCAL_RECOVERY_TOMBSTONE_V1")),
		FinalityProofHash: keccak([]byte("LOCAL_RECOVERY_TOMBSTONE_FINALITY_V1")),
		FinalizedAt:       destination.requestedAt.Add(time.Minute),
	}, nil
}

func localRecoveryRequest() (recovery.Request, []byte, error) {
	registration := localRegistration()
	envelope, serialized, err := localEnvelope(registration)
	if err != nil {
		return recovery.Request{}, nil, err
	}
	authorizerSetHash, err := recovery.AuthorizerSetHash(1, localFinalitySigners)
	if err != nil {
		return recovery.Request{}, nil, err
	}
	assetAmountCommitment, err := recovery.AssetAmountCommitment(
		uint8(envelope.GetActionType()),
		bytes32(envelope.GetPayloadHash()),
	)
	if err != nil {
		return recovery.Request{}, nil, err
	}
	asset := bytes20(envelope.GetCanonicalUftLock().GetCanonicalToken())
	compensationRecipient := repeated20(0x4a)
	compensationPayload, err := recovery.EncodeCompensationPayload(
		asset,
		envelope.GetCanonicalUftLock().GetAmount(),
		compensationRecipient,
	)
	if err != nil {
		return recovery.Request{}, nil, err
	}
	authorization := &recovery.Authorization{
		ProtocolID:             bytes32(envelope.GetProtocolId()),
		SourceChainID:          envelope.GetSourceChainId(),
		SourceCoordinator:      bytes20(envelope.GetSourceCoordinator()),
		DestinationChainID:     envelope.GetDestinationChainId(),
		DestinationCoordinator: bytes20(envelope.GetDestinationCoordinator()),
		Request: recovery.AuthorizationRequest{
			MessageID:                  bytes32(envelope.GetMessageId()),
			EnvelopeHash:               keccak(serialized),
			RoutePolicyHash:            bytes32(envelope.GetRoutePolicyHash()),
			AssetAmountCommitment:      assetAmountCommitment,
			SourceStateCommitment:      keccak([]byte("LOCAL_RECOVERY_SOURCE_STATE_V1")),
			DestinationStateCommitment: keccak([]byte("LOCAL_RECOVERY_DESTINATION_STATE_V1")),
			CompensationPayloadHash:    keccak(compensationPayload),
			MessageExpiresAt:           uint64(envelope.GetExpiresAt().AsTime().Unix()),
			RecoveryNonce:              1,
			ReasonCode:                 recovery.ReasonCodeCommitment("LOCAL_EXPIRED"),
			Action:                     1,
			AuthorizerSetHash:          authorizerSetHash,
			AuthorizerSetVersion:       1,
		},
	}
	recoveryID, err := recovery.RecoveryID(authorization.Request)
	if err != nil {
		return recovery.Request{}, nil, err
	}
	return recovery.Request{
		RecoveryID:                 hex.EncodeToString(recoveryID[:]),
		OriginalMessageID:          authorization.Request.MessageID,
		ImmutableEnvelopeHash:      authorization.Request.EnvelopeHash,
		RecoveryNonce:              authorization.Request.RecoveryNonce,
		RouteVersion:               registration.Route.Version,
		OriginalActionType:         uint8(envelope.GetActionType()),
		OriginalActionPayload:      append([]byte(nil), envelope.GetTypedActionPayload()...),
		AssetID:                    "0x" + hex.EncodeToString(asset[:]),
		Units:                      envelope.GetCanonicalUftLock().GetAmount(),
		CompensationRecipient:      "0x" + hex.EncodeToString(compensationRecipient[:]),
		CompensationPayload:        append([]byte(nil), compensationPayload...),
		ReasonCode:                 "LOCAL_EXPIRED",
		SourceStateCommitment:      authorization.Request.SourceStateCommitment,
		DestinationStateCommitment: authorization.Request.DestinationStateCommitment,
		AuthorizerPolicyHash:       authorizerSetHash,
		RoutePolicyHash:            authorization.Request.RoutePolicyHash,
		AssetAmountCommitment:      authorization.Request.AssetAmountCommitment,
		CompensationPayloadHash:    authorization.Request.CompensationPayloadHash,
		MessageExpiresAt:           authorization.Request.MessageExpiresAt,
		Action:                     authorization.Request.Action,
		AuthorizerSetVersion:       authorization.Request.AuthorizerSetVersion,
		Authorization:              authorization,
		Approvals: []recovery.Approval{
			{
				SignerID:  "local-council-a",
				Signature: append([]byte(nil), localRecoverySignatures[0]...),
			},
			{
				SignerID:  "local-council-b",
				Signature: append([]byte(nil), localRecoverySignatures[1]...),
			},
		},
		RequestedAt: localBaseTime.Add(40 * time.Minute),
	}, compensationPayload, nil
}

func recoveryGuard() error {
	request, compensationPayload, err := localRecoveryRequest()
	if err != nil {
		return err
	}
	authorizer, err := recovery.NewSecp256k1Authorizer(recovery.Secp256k1Policy{
		PolicyHash: request.AuthorizerPolicyHash,
		Signers: map[string][20]byte{
			"local-council-a": localFinalitySigners[0],
			"local-council-b": localFinalitySigners[1],
			"local-council-c": localFinalitySigners[2],
		},
	})
	if err != nil {
		return err
	}
	manager, err := recovery.NewManager(authorizer)
	if err != nil {
		return err
	}
	if _, err := manager.Request(request); err != nil {
		return fmt.Errorf("valid local recovery authorization rejected: %w", err)
	}
	if _, err := manager.Request(request); err != nil {
		return fmt.Errorf("exact local recovery replay rejected: %w", err)
	}
	reordered := request
	reordered.Approvals = append([]recovery.Approval(nil), request.Approvals...)
	reordered.Approvals[0], reordered.Approvals[1] =
		reordered.Approvals[1], reordered.Approvals[0]
	if _, err := manager.Request(reordered); err != nil {
		return fmt.Errorf("reordered recovery replay rejected: %w", err)
	}
	alteredUnits := request
	alteredUnits.Units = "2"
	if _, err := manager.Request(alteredUnits); !errors.Is(
		err,
		recovery.ErrInsufficientApproval,
	) {
		return errors.New("unsigned recovery units were not rejected")
	}
	alteredAsset := request
	alteredAsset.AssetID = "0x" + hex.EncodeToString(repeatedBytes(0x4b, 20))
	if _, err := manager.Request(alteredAsset); !errors.Is(
		err,
		recovery.ErrInsufficientApproval,
	) {
		return errors.New("unsigned recovery asset was not rejected")
	}
	wrongDomain := request
	wrongAuthorization := *request.Authorization
	wrongAuthorization.DestinationChainID = localSourceID
	wrongDomain.Authorization = &wrongAuthorization
	if _, err := manager.Request(wrongDomain); !errors.Is(
		err,
		recovery.ErrInsufficientApproval,
	) {
		return errors.New("wrong recovery domain was not rejected")
	}
	duplicate := request
	duplicate.Approvals = []recovery.Approval{
		request.Approvals[0],
		request.Approvals[0],
	}
	if _, err := manager.Request(duplicate); !errors.Is(
		err,
		recovery.ErrInsufficientApproval,
	) {
		return errors.New("duplicate recovery signer was not rejected")
	}
	compensation := recovery.Compensation{
		OriginalMessageID: request.OriginalMessageID,
		TombstoneHash:     keccak([]byte("LOCAL_RECOVERY_TOMBSTONE_V1")),
		Payload:           append([]byte(nil), compensationPayload...),
		ResultHash:        keccak([]byte("LOCAL_RECOVERY_RESULT_V1")),
		AssetID:           request.AssetID,
		Recipient:         request.CompensationRecipient,
		Units:             request.Units,
		CompensatedAt:     request.RequestedAt.Add(2 * time.Minute),
	}
	if _, err := manager.Compensate(compensation); !errors.Is(
		err,
		recovery.ErrNotTombstoned,
	) {
		return errors.New("recovery compensation was not blocked before tombstone")
	}
	destination := localRecoveryDestination{requestedAt: request.RequestedAt}
	if _, err := manager.Tombstone(request.OriginalMessageID, destination); err != nil {
		return err
	}
	changedPayload := compensation
	changedPayload.Payload = []byte("LOCAL_RECOVERY_COMPENSATION_V2")
	if _, err := manager.Compensate(changedPayload); !errors.Is(
		err,
		recovery.ErrRecoveryConflict,
	) {
		return errors.New("changed recovery compensation payload was not rejected")
	}
	if _, err := manager.Compensate(compensation); err != nil {
		return err
	}
	if _, err := manager.Compensate(compensation); err != nil {
		return fmt.Errorf("exact recovery compensation replay rejected: %w", err)
	}
	if _, err := manager.Finalize(
		request.OriginalMessageID,
		keccak([]byte("LOCAL_RECOVERY_ACKNOWLEDGEMENT_V1")),
	); err != nil {
		return err
	}
	return nil
}

func repeatedBytes(value byte, count int) []byte {
	return bytes.Repeat([]byte{value}, count)
}

func cloneByteSlices(source [][]byte) [][]byte {
	result := make([][]byte, len(source))
	for index := range source {
		result[index] = append([]byte(nil), source[index]...)
	}
	return result
}

func repeated20(value byte) [20]byte {
	var result [20]byte
	for index := range result {
		result[index] = value
	}
	return result
}

func bytes32(value []byte) [32]byte {
	var result [32]byte
	copy(result[:], value)
	return result
}

func bytes20(value []byte) [20]byte {
	var result [20]byte
	copy(result[:], value)
	return result
}

func mustHex(value string) []byte {
	decoded, err := hex.DecodeString(value)
	if err != nil {
		panic(err)
	}
	return decoded
}
