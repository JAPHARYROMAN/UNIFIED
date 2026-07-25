package main

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	chaincrosschain "github.com/unified-finance/unified/services/chain-indexer/crosschain"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/provider"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/recovery"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type testRepository struct {
	memory      *store.Memory
	attempts    map[string]store.ProviderAttemptRecord
	outbox      []store.OutboxRecord
	proof       *store.SourceProofRecord
	certificate *store.FinalityCertificateRecord
}

func (repository *testRepository) RecordSourceProof(
	_ context.Context,
	record store.SourceProofRecord,
) (store.SourceProofRecord, error) {
	if repository.proof != nil && !reflect.DeepEqual(*repository.proof, record) {
		return store.SourceProofRecord{}, store.ErrConflict
	}
	copied := record
	copied.ObserverSignature = append([]byte(nil), record.ObserverSignature...)
	repository.proof = &copied
	return copied, nil
}

func (repository *testRepository) RecordFinalityCertificate(
	_ context.Context,
	record store.FinalityCertificateRecord,
) (store.FinalityCertificateRecord, error) {
	if repository.certificate != nil && *repository.certificate != record {
		return store.FinalityCertificateRecord{}, store.ErrConflict
	}
	copied := record
	repository.certificate = &copied
	return copied, nil
}

func newTestRepository() *testRepository {
	return &testRepository{
		memory:   store.NewMemory(),
		attempts: make(map[string]store.ProviderAttemptRecord),
	}
}

func (repository *testRepository) PutRoute(route store.RouteVersion) error {
	return repository.memory.PutRoute(route)
}

func (repository *testRepository) Route(
	routeID string,
	version uint64,
) (store.RouteVersion, error) {
	return repository.memory.Route(routeID, version)
}

func (repository *testRepository) CreateMessage(
	record store.MessageRecord,
) (store.MessageRecord, error) {
	return repository.memory.CreateMessage(record)
}

func (repository *testRepository) CompareAndSet(
	messageID [32]byte,
	version uint64,
	next unifiedv1.CrossChainMessageState,
	retryable bool,
	evidence [32]byte,
	at time.Time,
) (store.MessageRecord, error) {
	return repository.memory.CompareAndSet(
		messageID,
		version,
		next,
		retryable,
		evidence,
		at,
	)
}

func (repository *testRepository) Message(
	messageID [32]byte,
) (store.MessageRecord, error) {
	return repository.memory.Message(messageID)
}

func (repository *testRepository) ClaimOutbox(
	context.Context,
	string,
	time.Time,
	time.Time,
	int,
) ([]store.OutboxRecord, error) {
	return append([]store.OutboxRecord(nil), repository.outbox...), nil
}

func (repository *testRepository) MarkOutboxPublished(
	_ context.Context,
	outboxID string,
	publisherID string,
	expectedAttemptCount uint32,
	brokerOffset string,
	publishedAt time.Time,
) (store.OutboxRecord, error) {
	for _, record := range repository.outbox {
		if record.OutboxID == outboxID &&
			record.AttemptCount == expectedAttemptCount {
			record.Status = "PUBLISHED"
			record.PublisherID = publisherID
			record.BrokerOffset = brokerOffset
			record.PublishedAt = &publishedAt
			return record, nil
		}
	}
	return store.OutboxRecord{}, store.ErrConflict
}

func (repository *testRepository) ConsumeInbox(
	_ context.Context,
	consumerID string,
	messageID [32]byte,
	topic string,
	partitionKey string,
	brokerOffset string,
	payloadHash [32]byte,
	consumedAt time.Time,
) (store.InboxRecord, error) {
	return store.InboxRecord{
		ConsumerID:   consumerID,
		MessageID:    messageID,
		Topic:        topic,
		PartitionKey: partitionKey,
		BrokerOffset: brokerOffset,
		PayloadHash:  payloadHash,
		ConsumedAt:   consumedAt,
	}, nil
}

func (repository *testRepository) RecordProviderAttempt(
	_ context.Context,
	record store.ProviderAttemptRecord,
) (store.ProviderAttemptRecord, error) {
	key := attemptKey(record.MessageID, record.ProviderID, record.AttemptNumber)
	if existing, ok := repository.attempts[key]; ok {
		if existing != record {
			return store.ProviderAttemptRecord{}, store.ErrConflict
		}
		return existing, nil
	}
	repository.attempts[key] = record
	return record, nil
}

func (repository *testRepository) ProviderAttempt(
	_ context.Context,
	messageID [32]byte,
	providerID string,
	attemptNumber uint32,
) (store.ProviderAttemptRecord, error) {
	record, ok := repository.attempts[attemptKey(messageID, providerID, attemptNumber)]
	if !ok {
		return store.ProviderAttemptRecord{}, store.ErrNotFound
	}
	return record, nil
}

func attemptKey(messageID [32]byte, providerID string, number uint32) string {
	return hexString(messageID) + ":" + providerID + ":" + string(rune(number))
}

type testEvidenceStore struct {
	key   string
	value []byte
	hash  [32]byte
}

func (evidence *testEvidenceStore) PutImmutable(
	_ context.Context,
	key string,
	value []byte,
	hash [32]byte,
) error {
	if err := validateEvidenceIdentity(key, value, hash); err != nil {
		return err
	}
	if evidence.key != "" &&
		(evidence.key != key || evidence.hash != hash ||
			!bytes.Equal(evidence.value, value)) {
		return errors.New("immutable evidence conflict")
	}
	evidence.key = key
	evidence.value = append([]byte(nil), value...)
	evidence.hash = hash
	return nil
}

func (evidence *testEvidenceStore) GetImmutable(
	_ context.Context,
	key string,
	hash [32]byte,
) ([]byte, error) {
	if evidence.key != key || evidence.hash != hash ||
		len(evidence.value) == 0 {
		return nil, errors.New("immutable evidence not found")
	}
	return append([]byte(nil), evidence.value...), nil
}

type testTransport struct {
	id    string
	err   error
	calls int
}

func (transport *testTransport) ID() string { return transport.id }

func (transport *testTransport) Submit(
	_ context.Context,
	_ provider.Delivery,
) (provider.Receipt, error) {
	transport.calls++
	if transport.err != nil {
		return provider.Receipt{}, transport.err
	}
	return provider.Receipt{
		ProviderID: transport.id,
		Receipt:    []byte("transport-only-accepted"),
	}, nil
}

func TestMessagePassPersistsFailoverAndSuppressesRestartRedelivery(t *testing.T) {
	repository := newTestRepository()
	if err := repository.PutRoute(localRegistration().Route); err != nil {
		t.Fatal(err)
	}
	evidence := &testEvidenceStore{}
	first := &testTransport{
		id:  "mock-bridge-provider-a",
		err: provider.Retryable(errors.New("synthetic outage")),
	}
	second := &testTransport{id: "mock-bridge-provider-b"}
	result, err := runMessagePass(
		t.Context(), repository, repository, repository, evidence, first, second,
	)
	if err != nil {
		t.Fatal(err)
	}
	if !result.deliveredThisPass || first.calls != 1 || second.calls != 1 ||
		len(result.attempts) != 2 ||
		result.attempts[0].Status != "FAILED" ||
		result.attempts[1].Status != "DELIVERED" {
		t.Fatalf("unexpected first pass: %#v calls=%d/%d", result, first.calls, second.calls)
	}
	restartA := &testTransport{id: "mock-bridge-provider-a", err: first.err}
	restartB := &testTransport{id: "mock-bridge-provider-b"}
	replayed, err := runMessagePass(
		t.Context(),
		repository,
		repository,
		repository,
		evidence,
		restartA,
		restartB,
	)
	if err != nil {
		t.Fatal(err)
	}
	if replayed.deliveredThisPass || restartA.calls != 0 || restartB.calls != 0 ||
		len(replayed.attempts) != 2 ||
		replayed.record.State != unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SENT {
		t.Fatalf("restart replay redelivered: %#v calls=%d/%d", replayed, restartA.calls, restartB.calls)
	}
}

func TestEvidenceIdentityRequiresContentAddress(t *testing.T) {
	value := []byte("synthetic-proof")
	hash := keccak(value)
	key := "synthetic/message/" + hexString(hash) + ".source-proof.pb"
	if err := validateEvidenceIdentity(key, value, hash); err != nil {
		t.Fatalf("exact content identity rejected: %v", err)
	}
	changed := append([]byte(nil), value...)
	changed[0] ^= 0xff
	if err := validateEvidenceIdentity(key, changed, hash); err == nil {
		t.Fatal("changed content accepted under immutable key")
	}
	wrongHash := hash
	wrongHash[0] ^= 0xff
	if err := validateEvidenceIdentity(key, value, wrongHash); err == nil {
		t.Fatal("caller-supplied false evidence hash accepted")
	}
}

func TestLocalChainConfigurationCommitmentCoversEveryAuthorityField(
	t *testing.T,
) {
	registration := localRegistration()
	baseline := registration.SourceChain
	expected, err := localChainConfigurationHash(baseline)
	if err != nil {
		t.Fatal(err)
	}
	if expected != baseline.ConfigurationHash {
		t.Fatal("source configuration is not bound to its canonical fields")
	}
	mutations := map[string]func(*store.ChainRegistration){
		"chain ID": func(value *store.ChainRegistration) {
			value.ChainID = "31339"
		},
		"version": func(value *store.ChainRegistration) {
			value.Version++
		},
		"coordinator": func(value *store.ChainRegistration) {
			value.Coordinator[0] ^= 0xff
		},
		"finality verifier": func(value *store.ChainRegistration) {
			value.FinalityVerifier[0] ^= 0xff
		},
		"observer authority": func(value *store.ChainRegistration) {
			value.ObserverAuthorityHash[0] ^= 0xff
		},
		"activation block": func(value *store.ChainRegistration) {
			value.ActivatedAtBlock = "2"
		},
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			changed := baseline
			mutate(&changed)
			actual, err := localChainConfigurationHash(changed)
			if err != nil {
				t.Fatal(err)
			}
			if actual == expected {
				t.Fatal("authority-field mutation did not change commitment")
			}
		})
	}
	changed := baseline
	changed.ConfigurationHash[0] ^= 0xff
	actual, err := localChainConfigurationHash(changed)
	if err != nil {
		t.Fatal(err)
	}
	if actual != expected {
		t.Fatal("configuration commitment became self-referential")
	}
}

func TestLocalCrossChainPolicyCommitmentCoversNonrecursivePolicy(
	t *testing.T,
) {
	registration := localRegistration()
	baseline, err := localCrossChainPolicyForRegistration(registration)
	if err != nil {
		t.Fatal(err)
	}
	expected, err := localCrossChainPolicyCommitment(baseline)
	if err != nil {
		t.Fatal(err)
	}
	mutations := map[string]func(*localCrossChainPolicyDefinition){
		"protocol": func(value *localCrossChainPolicyDefinition) {
			value.ProtocolID[0] ^= 0xff
		},
		"route ID": func(value *localCrossChainPolicyDefinition) {
			value.RouteID += "-changed"
		},
		"route version": func(value *localCrossChainPolicyDefinition) {
			value.RouteVersion++
		},
		"source configuration": func(value *localCrossChainPolicyDefinition) {
			value.SourceConfigurationHash[0] ^= 0xff
		},
		"destination configuration": func(value *localCrossChainPolicyDefinition) {
			value.DestinationConfigurationHash[0] ^= 0xff
		},
		"source component": func(value *localCrossChainPolicyDefinition) {
			value.SourceComponent[0] ^= 0xff
		},
		"destination component": func(value *localCrossChainPolicyDefinition) {
			value.DestinationComponent[0] ^= 0xff
		},
		"action family": func(value *localCrossChainPolicyDefinition) {
			value.ActionFamily += "_CHANGED"
		},
		"message timeout": func(value *localCrossChainPolicyDefinition) {
			value.MessageTimeoutSeconds++
		},
		"recovery action": func(value *localCrossChainPolicyDefinition) {
			value.RecoveryAction++
		},
		"recovery authorizer set": func(value *localCrossChainPolicyDefinition) {
			value.RecoveryAuthorizerSetHash[0] ^= 0xff
		},
		"recovery authorizer-set version": func(value *localCrossChainPolicyDefinition) {
			value.RecoveryAuthorizerSetVersion++
		},
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			changed := baseline
			mutate(&changed)
			actual, err := localCrossChainPolicyCommitment(changed)
			if err != nil {
				t.Fatal(err)
			}
			if actual == expected {
				t.Fatal("cross-chain policy mutation did not change commitment")
			}
		})
	}
}

func TestLocalFinalityPolicyCommitmentCoversEveryVerifierInput(
	t *testing.T,
) {
	registration := localRegistration()
	crossChainPolicy, err := localCrossChainPolicyForRegistration(registration)
	if err != nil {
		t.Fatal(err)
	}
	crossChainPolicyHash, err := localCrossChainPolicyCommitment(
		crossChainPolicy,
	)
	if err != nil {
		t.Fatal(err)
	}
	baseline := localFinalityPolicyDefinition{
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
	}
	expected, err := localFinalityPolicyCommitment(baseline)
	if err != nil {
		t.Fatal(err)
	}
	if expected != registration.SourceFinalityPolicyHash {
		t.Fatal("source verifier inputs are not canonically committed")
	}
	mutations := map[string]func(*localFinalityPolicyDefinition){
		"chain ID": func(value *localFinalityPolicyDefinition) {
			value.ChainID = "31339"
		},
		"configuration": func(value *localFinalityPolicyDefinition) {
			value.ConfigurationHash[0] ^= 0xff
		},
		"source contract": func(value *localFinalityPolicyDefinition) {
			value.SourceContract[0] ^= 0xff
		},
		"required depth": func(value *localFinalityPolicyDefinition) {
			value.RequiredDepth++
		},
		"observer authority": func(value *localFinalityPolicyDefinition) {
			value.ObserverAuthority[0] ^= 0xff
		},
		"signer set": func(value *localFinalityPolicyDefinition) {
			value.SignerSetHash[0] ^= 0xff
		},
		"threshold": func(value *localFinalityPolicyDefinition) {
			value.Threshold++
		},
		"signer-set version": func(value *localFinalityPolicyDefinition) {
			value.SignerSetVersion++
		},
		"cross-chain policy": func(value *localFinalityPolicyDefinition) {
			value.CrossChainPolicyHash[0] ^= 0xff
		},
		"action family": func(value *localFinalityPolicyDefinition) {
			value.ActionFamily += "_CHANGED"
		},
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			changed := baseline
			mutate(&changed)
			actual, err := localFinalityPolicyCommitment(changed)
			if err != nil {
				t.Fatal(err)
			}
			if actual == expected {
				t.Fatal("finality verifier mutation did not change commitment")
			}
		})
	}
	if registration.SourceFinalityPolicyHash ==
		registration.DestinationFinalityPolicyHash {
		t.Fatal("distinct local domains share a finality-policy commitment")
	}
}

func TestLocalAdapterSetCommitmentCoversOrderedTransportAuthorities(
	t *testing.T,
) {
	baseline := localAdapterAuthorities()
	expected, err := localAdapterSetPolicyCommitment(baseline)
	if err != nil {
		t.Fatal(err)
	}
	if expected != localRegistration().AdapterSetPolicyHash {
		t.Fatal("adapter authorities are not canonically committed")
	}
	tests := map[string][]localAdapterAuthority{
		"provider identity": {
			{ProviderID: localProviderAID + "-changed", Authority: "TRANSPORT_ONLY"},
			{ProviderID: localProviderBID, Authority: "TRANSPORT_ONLY"},
		},
		"provider authority": {
			{ProviderID: localProviderAID, Authority: "MESSAGE_AUTHORITY"},
			{ProviderID: localProviderBID, Authority: "TRANSPORT_ONLY"},
		},
		"provider count": {
			{ProviderID: localProviderAID, Authority: "TRANSPORT_ONLY"},
		},
	}
	for name, changed := range tests {
		t.Run(name, func(t *testing.T) {
			actual, err := localAdapterSetPolicyCommitment(changed)
			if err != nil {
				t.Fatal(err)
			}
			if actual == expected {
				t.Fatal("adapter-set mutation did not change commitment")
			}
		})
	}
	reordered := []localAdapterAuthority{baseline[1], baseline[0]}
	actual, err := localAdapterSetPolicyCommitment(reordered)
	if err != nil {
		t.Fatal(err)
	}
	if actual != expected {
		t.Fatal("operational provider preference changed economic identity")
	}
	duplicate := []localAdapterAuthority{baseline[0], baseline[0]}
	if _, err := localAdapterSetPolicyCommitment(duplicate); err == nil {
		t.Fatal("duplicate adapter identity was accepted")
	}
}

func TestLocalRoutePolicyCommitmentCoversEveryRegistrationField(
	t *testing.T,
) {
	baseline := localRegistration()
	expected, err := localRoutePolicyHash(baseline)
	if err != nil {
		t.Fatal(err)
	}
	if expected != baseline.Route.PolicyHash {
		t.Fatal("route policy is not bound to its canonical fields")
	}
	if err := validateLocalRegistrationCommitments(baseline); err != nil {
		t.Fatal(err)
	}
	mutations := map[string]func(*store.RouteRegistration){
		"route ID": func(value *store.RouteRegistration) {
			value.Route.RouteID += "-changed"
		},
		"route version": func(value *store.RouteRegistration) {
			value.Route.Version++
		},
		"route source chain": func(value *store.RouteRegistration) {
			value.Route.SourceChain = "31339"
		},
		"route destination chain": func(value *store.RouteRegistration) {
			value.Route.DestinationChain = "31339"
		},
		"route activated at": func(value *store.RouteRegistration) {
			value.Route.ActivatedAt = value.Route.ActivatedAt.Add(time.Second)
		},
		"route deprecated at": func(value *store.RouteRegistration) {
			deprecatedAt := localBaseTime.Add(time.Hour)
			value.Route.DeprecatedAt = &deprecatedAt
		},
		"source chain ID": func(value *store.RouteRegistration) {
			value.SourceChain.ChainID = "31339"
		},
		"source chain version": func(value *store.RouteRegistration) {
			value.SourceChain.Version++
		},
		"source coordinator": func(value *store.RouteRegistration) {
			value.SourceChain.Coordinator[0] ^= 0xff
		},
		"source finality verifier": func(value *store.RouteRegistration) {
			value.SourceChain.FinalityVerifier[0] ^= 0xff
		},
		"source configuration": func(value *store.RouteRegistration) {
			value.SourceChain.ConfigurationHash[0] ^= 0xff
		},
		"source observer authority": func(value *store.RouteRegistration) {
			value.SourceChain.ObserverAuthorityHash[0] ^= 0xff
		},
		"source chain activation block": func(value *store.RouteRegistration) {
			value.SourceChain.ActivatedAtBlock = "2"
		},
		"destination chain ID": func(value *store.RouteRegistration) {
			value.DestinationChain.ChainID = "31339"
		},
		"destination chain version": func(value *store.RouteRegistration) {
			value.DestinationChain.Version++
		},
		"destination coordinator": func(value *store.RouteRegistration) {
			value.DestinationChain.Coordinator[0] ^= 0xff
		},
		"destination finality verifier": func(value *store.RouteRegistration) {
			value.DestinationChain.FinalityVerifier[0] ^= 0xff
		},
		"destination configuration": func(value *store.RouteRegistration) {
			value.DestinationChain.ConfigurationHash[0] ^= 0xff
		},
		"destination observer authority": func(value *store.RouteRegistration) {
			value.DestinationChain.ObserverAuthorityHash[0] ^= 0xff
		},
		"destination chain activation block": func(value *store.RouteRegistration) {
			value.DestinationChain.ActivatedAtBlock = "2"
		},
		"source component": func(value *store.RouteRegistration) {
			value.SourceComponent[0] ^= 0xff
		},
		"destination component": func(value *store.RouteRegistration) {
			value.DestinationComponent[0] ^= 0xff
		},
		"action family": func(value *store.RouteRegistration) {
			value.ActionFamily += "_CHANGED"
		},
		"adapter-set policy": func(value *store.RouteRegistration) {
			value.AdapterSetPolicyHash[0] ^= 0xff
		},
		"source finality policy": func(value *store.RouteRegistration) {
			value.SourceFinalityPolicyHash[0] ^= 0xff
		},
		"destination finality policy": func(value *store.RouteRegistration) {
			value.DestinationFinalityPolicyHash[0] ^= 0xff
		},
		"source signer set": func(value *store.RouteRegistration) {
			value.SourceSignerSetHash[0] ^= 0xff
		},
		"source signer-set version": func(value *store.RouteRegistration) {
			value.SourceSignerSetVersion++
		},
		"destination signer set": func(value *store.RouteRegistration) {
			value.DestinationSignerSetHash[0] ^= 0xff
		},
		"destination signer-set version": func(value *store.RouteRegistration) {
			value.DestinationSignerSetVersion++
		},
		"route activation block": func(value *store.RouteRegistration) {
			value.ActivatedAtBlock = "2"
		},
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			changed := baseline
			mutate(&changed)
			actual, err := localRoutePolicyHash(changed)
			if err != nil {
				t.Fatal(err)
			}
			if actual == expected {
				t.Fatal("registration-field mutation did not change policy")
			}
			if err := validateLocalRegistrationCommitments(changed); err == nil {
				t.Fatal("registration mutation retained the prior commitments")
			}
		})
	}

	selfChanged := baseline
	selfChanged.Route.PolicyHash[0] ^= 0xff
	actual, err := localRoutePolicyHash(selfChanged)
	if err != nil {
		t.Fatal(err)
	}
	if actual != expected {
		t.Fatal("route policy commitment became self-referential")
	}
	if err := validateLocalRegistrationCommitments(selfChanged); err == nil {
		t.Fatal("changed route policy was accepted")
	}
}

func TestLocalObserverEvidenceRejectsSignatureAuthorityAndCommitmentChanges(t *testing.T) {
	registration := localRegistration()
	envelope, _, err := localEnvelope(registration)
	if err != nil {
		t.Fatal(err)
	}
	evidence, err := authenticateSource(envelope, registration)
	if err != nil {
		t.Fatal(err)
	}
	var original unifiedv1.CrossChainSourceEventProof
	if err := proto.Unmarshal(evidence.Bytes, &original); err != nil {
		t.Fatal(err)
	}
	tests := map[string]func(*unifiedv1.CrossChainSourceEventProof){
		"signature": func(proof *unifiedv1.CrossChainSourceEventProof) {
			proof.ObserverSignature[0] ^= 0xff
		},
		"authority": func(proof *unifiedv1.CrossChainSourceEventProof) {
			proof.HeaderAuthorityHash[0] ^= 0xff
		},
		"commitment": func(proof *unifiedv1.CrossChainSourceEventProof) {
			proof.SourceBlockNumber++
		},
	}
	for name, mutate := range tests {
		changed := proto.Clone(&original).(*unifiedv1.CrossChainSourceEventProof)
		mutate(changed)
		if _, err := (localEvidenceVerifier{
			registration:      registration,
			observerPublicKey: localObserverPublicKey,
		}).VerifySource(
			envelope,
			changed,
			evidence.Certificate,
		); !errors.Is(err, chaincrosschain.ErrUnauthenticated) {
			t.Fatalf("%s mutation accepted: %v", name, err)
		}
	}
}

func TestFinalityDigestUsesReceivingDestinationDomain(t *testing.T) {
	solidityGolden, err := localFinalityDigest(
		"31338",
		bytes20(mustHex("5555555555555555555555555555555555555555")),
		bytes32(mustHex(
			"f8d9ef5672d829229110e480489155be0440e916833a1290a8955a8acf9c4801",
		)),
		bytes32(mustHex(
			"48d3a5bd4a6edfa6da4ceb1fb19fb7d7d975e24ac53af96bc4bc39947a566caf",
		)),
		bytes32(mustHex(
			"7777777777777777777777777777777777777777777777777777777777777777",
		)),
		1,
	)
	if err != nil {
		t.Fatal(err)
	}
	const expectedSolidityGolden = "6ebe5277d0c32b531c792319523fd367e073607937dea0c3949c5f8d43ca8820"
	if hexString(solidityGolden) != expectedSolidityGolden {
		t.Fatalf("Solidity finality digest mismatch: %x", solidityGolden)
	}

	registration := localRegistration()
	envelope, _, err := localEnvelope(registration)
	if err != nil {
		t.Fatal(err)
	}
	evidence, err := authenticateSource(envelope, registration)
	if err != nil {
		t.Fatal(err)
	}
	proofHash, err := chaincrosschain.ComputeSourceProofHash(evidence.Proof)
	if err != nil {
		t.Fatal(err)
	}
	destinationDigest, err := localFinalityDigest(
		registration.DestinationChain.ChainID,
		registration.DestinationChain.FinalityVerifier,
		bytes32(envelope.GetMessageId()),
		proofHash,
		registration.SourceSignerSetHash,
		registration.SourceSignerSetVersion,
	)
	if err != nil {
		t.Fatal(err)
	}
	const expectedLocalDigest = "d98755a6955ac64e9ee937274c75d8c2bc50ea6ba6635085110dd4e5eb67340f"
	if hexString(destinationDigest) != expectedLocalDigest {
		t.Fatalf("local destination digest changed: %x", destinationDigest)
	}
	sourceDigest, err := localFinalityDigest(
		registration.SourceChain.ChainID,
		registration.SourceChain.FinalityVerifier,
		bytes32(envelope.GetMessageId()),
		proofHash,
		registration.SourceSignerSetHash,
		registration.SourceSignerSetVersion,
	)
	if err != nil {
		t.Fatal(err)
	}
	for index, signature := range localFinalitySignatures {
		recovered, err := recovery.VerifyEthereumSignature(
			destinationDigest,
			signature,
		)
		if err != nil || recovered != localFinalitySigners[index] {
			t.Fatalf("destination-domain signature %d rejected: %v", index, err)
		}
		recovered, err = recovery.VerifyEthereumSignature(sourceDigest, signature)
		if err == nil && recovered == localFinalitySigners[index] {
			t.Fatalf("source-domain substitution accepted for signer %d", index)
		}
	}
}

func TestPublicTrustConfigurationUsesSoleReleaseEvidencePath(t *testing.T) {
	if phase8ReleaseEvidencePath !=
		"protocol/deployments/local/phase8-release-evidence.json" {
		t.Fatal("worker trust authority path drifted")
	}
}

func TestRecoveryGuardUsesSignedCanonicalEconomics(t *testing.T) {
	if err := recoveryGuard(); err != nil {
		t.Fatal(err)
	}
}

func TestReorganizationVerifierPinsFinalityValidityWindow(t *testing.T) {
	registration := localRegistration()
	envelope, _, err := localEnvelope(registration)
	if err != nil {
		t.Fatal(err)
	}
	source, err := authenticateSource(envelope, registration)
	if err != nil {
		t.Fatal(err)
	}
	reorganization, err := buildLocalReorganization(source, registration)
	if err != nil {
		t.Fatal(err)
	}
	verifier := localReorganizationVerifier{
		registration:      registration,
		observerPublicKey: localObserverPublicKey,
	}
	if _, err := verifier.VerifyReorganization(reorganization.Evidence); err != nil {
		t.Fatalf("valid reorganization rejected: %v", err)
	}
	changed := proto.Clone(reorganization.Evidence).(*unifiedv1.CrossChainReorganizationEvidence)
	changed.AffectedOrphanedFinalityCertificates[0].ValidUntil =
		timestamppb.New(localBaseTime.Add(24*time.Hour + time.Minute))
	changed.OrphanedFinalityCertificate = proto.Clone(
		changed.AffectedOrphanedFinalityCertificates[0],
	).(*unifiedv1.CrossChainFinalityCertificate)
	hash, err := chaincrosschain.ComputeReorganizationEvidenceHash(changed)
	if err != nil {
		t.Fatal(err)
	}
	changed.EvidenceHash = hash[:]
	if _, err := verifier.VerifyReorganization(changed); err == nil {
		t.Fatal("altered finality validity window was accepted")
	}
}

func TestReorganizationRestartEqualityRejectsTamperedDurableField(t *testing.T) {
	record := store.ReorganizationRecord{
		ReorganizationID:          "crosschain-reorg:test",
		RouteID:                   localRouteID,
		ChainID:                   "31337",
		OrphanedBlockHash:         [32]byte{1},
		OrphanedBlockNumber:       "100",
		OrphanedProofID:           "proof-1",
		OrphanedCertificateID:     "certificate-1",
		OrphanedProofIDs:          []string{"proof-1"},
		OrphanedCertificateIDs:    []string{"certificate-1"},
		ReplacementBlockHash:      [32]byte{2},
		ReplacementBlockNumber:    "100",
		ReplacementObservationID:  "replacement-1",
		DetectedHeadHash:          [32]byte{3},
		DetectedHeadNumber:        "103",
		DetectedHeadObservationID: "head-1",
		DepthClass:                "DEEP_FINALITY",
		AffectedMessageIDs:        [][32]byte{{4}},
		EvidenceHash:              [32]byte{5},
		DetectedAt:                localBaseTime.Add(10 * time.Minute),
		IncidentID:                "crosschain-incident:test",
		IncidentReasonCode:        "POST_FINALITY_REORGANIZATION",
		IncidentSeverity:          "CRITICAL",
		IncidentOwner:             "cross-chain-security",
		IncidentStatus:            "OPEN",
		IncidentOpenedAt:          localBaseTime.Add(10 * time.Minute),
	}
	if !sameLocalReorganizationRecord(record, record) {
		t.Fatal("exact durable reorganization identity did not match")
	}
	tampered := record
	tampered.DetectedHeadNumber = "104"
	if sameLocalReorganizationRecord(record, tampered) {
		t.Fatal("tampered durable reorganization field was accepted")
	}
}

func TestHTTPTransportRejectsFabricatedAuthorityWithoutFailover(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(
		writer http.ResponseWriter,
		_ *http.Request,
	) {
		writer.Header().Set("Content-Type", "application/json")
		writer.WriteHeader(http.StatusAccepted)
		_, _ = writer.Write([]byte(
			`{"authority":"FABRICATED_FINALITY","contains_real_value":false}`,
		))
	}))
	defer server.Close()
	fabricated, err := newHTTPTransport(
		"mock-bridge-provider-a",
		server.URL,
		"/v1/messages",
		server.Client(),
	)
	if err != nil {
		t.Fatal(err)
	}
	fallback := &testTransport{id: "mock-bridge-provider-b"}
	router := provider.NewRouter()
	route := [32]byte{1}
	if err := router.RegisterRoute(route, fabricated, fallback); err != nil {
		t.Fatal(err)
	}
	delivery := provider.Delivery{
		MessageID:    [32]byte{2},
		RoutePolicy:  route,
		Envelope:     []byte("envelope"),
		EnvelopeHash: keccak([]byte("envelope")),
		SourceProof:  []byte("proof"),
		ProofHash:    keccak([]byte("proof")),
		AttemptedAt:  time.Unix(1_700_000_000, 0).UTC(),
	}
	if _, err := router.Deliver(t.Context(), delivery); err == nil {
		t.Fatal("fabricated provider authority was accepted")
	}
	if fallback.calls != 0 {
		t.Fatal("fabricated authority reached fallback provider")
	}
}

func TestConfigurationRejectsNonLoopbackDependencies(t *testing.T) {
	values := map[string]string{
		foundationDSNEnvironment:          "postgres://owner:test@127.0.0.1:55432/local",
		databaseURLEnvironment:            "postgres://local:test@127.0.0.1:55432/local",
		observerDatabaseEnvironment:       "postgres://observer:test@127.0.0.1:55432/local",
		finalityDatabaseEnvironment:       "postgres://finality:test@127.0.0.1:55432/local",
		recoveryDatabaseEnvironment:       "postgres://recovery:test@127.0.0.1:55432/local",
		reorganizationDatabaseEnvironment: "postgres://reorganization:test@127.0.0.1:55432/local",
		kafkaEnvironment:                  "127.0.0.1:19092",
		objectEnvironment:                 "http://127.0.0.1:59000",
		providerAEnvironment:              "http://127.0.0.1:58081",
		providerBEnvironment:              "http://127.0.0.1:58082",
	}
	getenv := func(key string) string { return values[key] }
	if _, err := loadConfiguration([]string{"--mode", "smoke"}, getenv); err != nil {
		t.Fatalf("local configuration rejected: %v", err)
	}
	cancellation, err := loadConfiguration(
		[]string{
			"--mode", "cancellation",
			"--cancellation-bundle", "cancellation.json",
		},
		getenv,
	)
	if err != nil || cancellation.mode != "cancellation" ||
		cancellation.cancellationBundlePath == "" {
		t.Fatalf("bounded cancellation mode is unreachable: %#v %v", cancellation, err)
	}
	if _, err := loadConfiguration(
		[]string{"--mode", "cancellation"},
		getenv,
	); err == nil {
		t.Fatal("cancellation mode accepted a missing bundle")
	}
	values[providerBEnvironment] = "https://provider.example"
	if _, err := loadConfiguration([]string{"--mode", "smoke"}, getenv); err == nil {
		t.Fatal("remote provider endpoint accepted")
	}
	values[providerBEnvironment] = "http://127.0.0.1:58082"
	values[kafkaEnvironment] = "127.0.0.1:19092,127.0.0.1:29092"
	if _, err := loadConfiguration([]string{"--mode", "smoke"}, getenv); err == nil {
		t.Fatal("multi-broker surface accepted")
	}
	values[kafkaEnvironment] = "127.0.0.1:19092"
	values[observerDatabaseEnvironment] = "postgres://observer:test@db.example:5432/local"
	if _, err := loadConfiguration([]string{"--mode", "smoke"}, getenv); err == nil {
		t.Fatal("remote observer database accepted")
	}
}
