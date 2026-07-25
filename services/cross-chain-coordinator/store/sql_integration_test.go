package store

import (
	"bytes"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"reflect"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/message"
	"golang.org/x/crypto/sha3"
	"google.golang.org/protobuf/proto"
)

func TestSQLRepositoryPostgreSQLIntegration(t *testing.T) {
	databaseURL := os.Getenv("UNIFIED_CROSSCHAIN_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("UNIFIED_CROSSCHAIN_TEST_DATABASE_URL is not set")
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = database.Close() })
	database.SetMaxOpenConns(1)
	database.SetMaxIdleConns(1)
	registration := sqlTestRouteRegistration()
	registration.Route.RouteID = "route-sql-integration-v1"
	registration.Route.SourceChain = "99031337"
	registration.Route.DestinationChain = "99031338"
	registration.SourceChain.ChainID = registration.Route.SourceChain
	registration.DestinationChain.ChainID = registration.Route.DestinationChain
	registration.Route.PolicyHash = integrationHash(
		"UNIFIED_PHASE8_SQL_INTEGRATION_ROUTE_V1",
	)
	registration.AdapterSetPolicyHash = integrationHash(
		"UNIFIED_PHASE8_SQL_INTEGRATION_ADAPTER_V1",
	)
	registration.SourceFinalityPolicyHash = integrationHash(
		"UNIFIED_PHASE8_SQL_INTEGRATION_SOURCE_FINALITY_V1",
	)
	registration.DestinationFinalityPolicyHash = integrationHash(
		"UNIFIED_PHASE8_SQL_INTEGRATION_DESTINATION_FINALITY_V1",
	)
	bootstrapURL := os.Getenv("UNIFIED_CROSSCHAIN_TEST_BOOTSTRAP_DATABASE_URL")
	if bootstrapURL != "" {
		bootstrapDatabase, openErr := sql.Open("pgx", bootstrapURL)
		if openErr != nil {
			t.Fatal(openErr)
		}
		if seedErr := seedIntegrationSignerSet(
			bootstrapDatabase,
			registration.SourceSignerSetHash,
			registration.SourceSignerSetVersion,
			0x41,
		); seedErr != nil {
			_ = bootstrapDatabase.Close()
			t.Fatal(seedErr)
		}
		if seedErr := seedIntegrationSignerSet(
			bootstrapDatabase,
			registration.DestinationSignerSetHash,
			registration.DestinationSignerSetVersion,
			0x51,
		); seedErr != nil {
			_ = bootstrapDatabase.Close()
			t.Fatal(seedErr)
		}
		bootstrapRepository, repositoryErr := NewSQLWithProvisioning(
			bootstrapDatabase,
			[]RouteRegistration{registration},
		)
		if repositoryErr != nil {
			_ = bootstrapDatabase.Close()
			t.Fatal(repositoryErr)
		}
		if putErr := bootstrapRepository.PutRoute(registration.Route); putErr != nil {
			_ = bootstrapDatabase.Close()
			t.Fatalf("owner bootstrap route: %v", putErr)
		}
		if closeErr := bootstrapDatabase.Close(); closeErr != nil {
			t.Fatal(closeErr)
		}
	}
	repository, err := NewSQLWithProvisioning(
		database,
		[]RouteRegistration{registration},
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := seedIntegrationSignerSet(
		database,
		registration.SourceSignerSetHash,
		registration.SourceSignerSetVersion,
		0x41,
	); err != nil {
		t.Fatal(err)
	}
	if err := seedIntegrationSignerSet(
		database,
		registration.DestinationSignerSetHash,
		registration.DestinationSignerSetVersion,
		0x51,
	); err != nil {
		t.Fatal(err)
	}
	if err := repository.Health(t.Context()); err != nil {
		t.Fatal(err)
	}
	if bootstrapURL == "" {
		if err := repository.PutRoute(registration.Route); err != nil {
			t.Fatal(err)
		}
		if err := repository.PutRoute(registration.Route); err != nil {
			t.Fatalf("exact route replay: %v", err)
		}
	}
	if os.Getenv("UNIFIED_CROSSCHAIN_TEST_SET_ROLE") == "1" {
		if _, err := database.Exec("SET ROLE unified_crosschain_runtime"); err != nil {
			t.Fatal(err)
		}
		if _, err := database.Exec(
			"UPDATE crosschain.routes SET active_version = active_version WHERE false",
		); err == nil {
			t.Fatal("runtime role retained direct authoritative write privilege")
		}
		if _, err := database.Exec(
			"SELECT crosschain.register_chain_version(" +
				"999999, 1, decode(repeat('01', 20), 'hex'), " +
				"decode(repeat('02', 20), 'hex'), " +
				"decode(repeat('03', 32), 'hex'), " +
				"decode(repeat('04', 32), 'hex'), 1, 'ACTIVE', now())",
		); err == nil {
			t.Fatal("runtime role retained chain authority registration")
		}
	}
	loadedRoute, err := repository.Route(
		registration.Route.RouteID,
		registration.Route.Version,
	)
	if err != nil || !sameRoute(loadedRoute, registration.Route) {
		t.Fatalf("route restart load: %#v %v", loadedRoute, err)
	}

	record := integrationMessageRecord(t, registration)
	created, err := repository.CreateMessage(record)
	if err != nil {
		t.Fatal(err)
	}
	observerDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = observerDatabase.Close() })
	observerDatabase.SetMaxOpenConns(1)
	observerDatabase.SetMaxIdleConns(1)
	if _, err := observerDatabase.Exec("SET ROLE unified_crosschain_observer"); err != nil {
		t.Fatal(err)
	}
	observerRepository, err := NewSQL(observerDatabase)
	if err != nil {
		t.Fatal(err)
	}
	finalityDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = finalityDatabase.Close() })
	finalityDatabase.SetMaxOpenConns(1)
	finalityDatabase.SetMaxIdleConns(1)
	if _, err := finalityDatabase.Exec(
		"SET ROLE unified_crosschain_finality_attester",
	); err != nil {
		t.Fatal(err)
	}
	finalityRepository, err := NewSQL(finalityDatabase)
	if err != nil {
		t.Fatal(err)
	}
	proof := integrationSourceProof(record, registration)
	recordedProof, err := observerRepository.RecordSourceProof(t.Context(), proof)
	if err != nil || !sameSourceProof(recordedProof, proof) {
		t.Fatalf("observer proof ingestion: %#v %v", recordedProof, err)
	}
	replayedProof, err := observerRepository.RecordSourceProof(t.Context(), proof)
	if err != nil || !sameSourceProof(replayedProof, proof) {
		t.Fatalf("observer proof replay: %#v %v", replayedProof, err)
	}
	conflictingProof := proof
	conflictingProof.EventHash = integrationHash(
		"UNIFIED_PHASE8_OBSERVER_CONFLICT_V1",
	)
	if _, err := observerRepository.RecordSourceProof(
		t.Context(),
		conflictingProof,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("conflicting observer proof accepted: %v", err)
	}
	certificate := integrationFinalityCertificate(proof, registration)
	recordedCertificate, err := finalityRepository.RecordFinalityCertificate(
		t.Context(),
		certificate,
	)
	if err != nil ||
		!sameFinalityCertificate(recordedCertificate, certificate) {
		t.Fatalf(
			"observer certificate ingestion: %#v %v",
			recordedCertificate,
			err,
		)
	}
	replayedCertificate, err := finalityRepository.RecordFinalityCertificate(
		t.Context(),
		certificate,
	)
	if err != nil ||
		!sameFinalityCertificate(replayedCertificate, certificate) {
		t.Fatalf(
			"observer certificate replay: %#v %v",
			replayedCertificate,
			err,
		)
	}
	evidence := integrationHash("UNIFIED_PHASE8_SQL_INTEGRATION_TRANSITION_V1")
	transitionedAt := record.UpdatedAt.Add(time.Minute)
	transitioned, err := repository.CompareAndSet(
		record.MessageID,
		1,
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING,
		false,
		evidence,
		transitionedAt,
	)
	if err != nil {
		t.Fatal(err)
	}
	replayed, err := repository.CompareAndSet(
		record.MessageID,
		1,
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING,
		false,
		evidence,
		transitionedAt,
	)
	if err != nil || replayed.MessageID != transitioned.MessageID ||
		replayed.Version != transitioned.Version ||
		replayed.Evidence != transitioned.Evidence {
		t.Fatalf("exact CAS replay: %#v %v", replayed, err)
	}
	if _, err := repository.CompareAndSet(
		record.MessageID,
		1,
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING,
		false,
		integrationHash("UNIFIED_PHASE8_SQL_INTEGRATION_CONFLICT_V1"),
		transitionedAt,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("conflicting CAS replay accepted: %v", err)
	}
	providerAttempt := ProviderAttemptRecord{
		MessageID:       record.MessageID,
		ProviderID:      "provider-b",
		AttemptNumber:   2,
		EnvelopeHash:    integrationHash("UNIFIED_PHASE8_SQL_PROVIDER_ENVELOPE_V1"),
		SourceProofHash: integrationHash("UNIFIED_PHASE8_SQL_PROVIDER_PROOF_V1"),
		Status:          "DELIVERED",
		ReceiptHash:     integrationHash("UNIFIED_PHASE8_SQL_PROVIDER_RECEIPT_V1"),
		AttemptedAt:     transitionedAt.Add(time.Minute),
	}
	if _, err := repository.RecordProviderAttempt(t.Context(), providerAttempt); err != nil {
		t.Fatalf("record provider attempt: %v", err)
	}
	if _, err := repository.RecordProviderAttempt(t.Context(), providerAttempt); err != nil {
		t.Fatalf("exact provider attempt replay: %v", err)
	}

	claimAt := time.Date(2100, 1, 1, 0, 0, 0, 0, time.UTC)
	leaseUntil := claimAt.Add(time.Minute)
	publishedAt := claimAt.Add(30 * time.Second)
	claimed, err := repository.ClaimOutbox(
		t.Context(),
		"integration-publisher-v1",
		leaseUntil,
		claimAt,
		2,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(claimed) == 0 {
		// A repeated integration run sees the exact already-published rows.
		for version := uint64(1); version <= 2; version++ {
			outboxID := fmt.Sprintf(
				"crosschain.message-state.v1:%x:%d",
				record.MessageID,
				version,
			)
			existing, loadErr := repository.outbox(t.Context(), outboxID)
			if loadErr != nil {
				t.Fatal(loadErr)
			}
			claimed = append(claimed, existing)
		}
	}
	if len(claimed) != 2 {
		t.Fatalf("unexpected durable outbox batch size: %d", len(claimed))
	}
	for _, outbox := range claimed {
		if outbox.MessageID != record.MessageID {
			t.Fatalf("claimed another message's outbox record: %#v", outbox)
		}
		offset := fmt.Sprintf("integration-partition-0:%d", outbox.StateVersion)
		if outbox.Status == "CLAIMED" {
			outbox, err = repository.MarkOutboxPublished(
				t.Context(),
				outbox.OutboxID,
				"integration-publisher-v1",
				outbox.AttemptCount,
				offset,
				publishedAt,
			)
			if err != nil {
				t.Fatal(err)
			}
		} else if outbox.Status != "PUBLISHED" {
			t.Fatalf("unexpected outbox state after restart: %#v", outbox)
		}
		// Exact publication replay returns the durable row.
		replayedOutbox, replayErr := repository.MarkOutboxPublished(
			t.Context(),
			outbox.OutboxID,
			outbox.PublisherID,
			outbox.AttemptCount,
			outbox.BrokerOffset,
			*outbox.PublishedAt,
		)
		if replayErr != nil || replayedOutbox.OutboxID != outbox.OutboxID {
			t.Fatalf("publication restart replay: %#v %v", replayedOutbox, replayErr)
		}
		consumedAt := claimAt.Add(time.Duration(outbox.StateVersion) * time.Second)
		consumed, consumeErr := repository.ConsumeInbox(
			t.Context(),
			"integration-consumer-v1",
			outbox.MessageID,
			outbox.Topic,
			outbox.PartitionKey,
			outbox.BrokerOffset,
			outbox.PayloadHash,
			consumedAt,
		)
		if consumeErr != nil {
			t.Fatal(consumeErr)
		}
		replayedInbox, replayErr := repository.ConsumeInbox(
			t.Context(),
			"integration-consumer-v1",
			outbox.MessageID,
			outbox.Topic,
			outbox.PartitionKey,
			outbox.BrokerOffset,
			outbox.PayloadHash,
			consumedAt,
		)
		if replayErr != nil || replayedInbox != consumed {
			t.Fatalf("inbox restart replay: %#v %v", replayedInbox, replayErr)
		}
		if _, conflictErr := repository.ConsumeInbox(
			t.Context(),
			"integration-consumer-v1",
			outbox.MessageID,
			outbox.Topic,
			outbox.PartitionKey,
			outbox.BrokerOffset,
			integrationHash("UNIFIED_PHASE8_CONFLICTING_INBOX_PAYLOAD_V1"),
			consumedAt,
		); !errors.Is(conflictErr, ErrConflict) {
			t.Fatalf("conflicting inbox payload accepted: %v", conflictErr)
		}
		if _, conflictErr := repository.ConsumeInbox(
			t.Context(),
			"integration-consumer-v1",
			outbox.MessageID,
			outbox.Topic,
			"changed-partition-key",
			outbox.BrokerOffset,
			outbox.PayloadHash,
			consumedAt,
		); !errors.Is(conflictErr, ErrConflict) {
			t.Fatalf("changed inbox partition key accepted: %v", conflictErr)
		}
	}

	restarted, err := NewSQLWithProvisioning(
		database,
		[]RouteRegistration{registration},
	)
	if err != nil {
		t.Fatal(err)
	}
	rehydrated, err := restarted.Message(record.MessageID)
	if err != nil || rehydrated.Version != 2 ||
		rehydrated.State !=
			unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING ||
		!bytes.Equal(rehydrated.Envelope, created.Envelope) {
		t.Fatalf("restart rehydration: %#v %v", rehydrated, err)
	}
	restartedAttempt, err := restarted.ProviderAttempt(
		t.Context(),
		providerAttempt.MessageID,
		providerAttempt.ProviderID,
		providerAttempt.AttemptNumber,
	)
	if err != nil || !sameProviderAttempt(restartedAttempt, providerAttempt) {
		t.Fatalf("provider attempt restart rehydration: %#v %v", restartedAttempt, err)
	}
	sourceFinalizedAt := transitionedAt.Add(90 * time.Second)
	sourceFinal, err := restarted.CompareAndSet(
		record.MessageID,
		2,
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINAL,
		false,
		certificate.CertificateHash,
		sourceFinalizedAt,
	)
	if err != nil || sourceFinal.Version != 3 ||
		sourceFinal.Evidence != certificate.CertificateHash {
		t.Fatalf("source finality evidence was not retained: %#v %v", sourceFinal, err)
	}

	replacementObservation := HeaderObservationRecord{
		ObservationID:                  "integration-replacement-header-v1",
		ChainID:                        proof.ChainID,
		BlockHash:                      integrationHash("UNIFIED_PHASE8_REPLACEMENT_BLOCK_V1"),
		BlockNumber:                    proof.BlockNumber,
		HeaderAuthorityHash:            proof.ObserverAuthorityHash,
		ObserverSignedHeaderCommitment: integrationHash("UNIFIED_PHASE8_REPLACEMENT_HEADER_V1"),
		ObserverSignature:              []byte{4, 5, 6},
		FinalityPolicyHash:             proof.FinalityPolicyHash,
		ObservedAt:                     transitionedAt.Add(2 * time.Minute),
	}
	detectedHeadObservation := HeaderObservationRecord{
		ObservationID:       "integration-detected-head-v1",
		ChainID:             proof.ChainID,
		BlockHash:           integrationHash("UNIFIED_PHASE8_DETECTED_HEAD_BLOCK_V1"),
		BlockNumber:         "113",
		HeaderAuthorityHash: proof.ObserverAuthorityHash,
		ObserverSignedHeaderCommitment: integrationHash(
			"UNIFIED_PHASE8_DETECTED_HEAD_HEADER_V1",
		),
		ObserverSignature:  []byte{7, 8, 9},
		FinalityPolicyHash: proof.FinalityPolicyHash,
		ObservedAt:         transitionedAt.Add(3 * time.Minute),
	}
	for _, observation := range []HeaderObservationRecord{
		replacementObservation,
		detectedHeadObservation,
	} {
		recordedObservation, recordErr := observerRepository.RecordHeaderObservation(
			t.Context(),
			observation,
		)
		if recordErr != nil ||
			!sameHeaderObservation(recordedObservation, observation) {
			t.Fatalf(
				"header observation ingestion: %#v %v",
				recordedObservation,
				recordErr,
			)
		}
		replayedObservation, replayErr := observerRepository.RecordHeaderObservation(
			t.Context(),
			observation,
		)
		if replayErr != nil ||
			!sameHeaderObservation(replayedObservation, observation) {
			t.Fatalf(
				"header observation replay: %#v %v",
				replayedObservation,
				replayErr,
			)
		}
	}

	reorganizationDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = reorganizationDatabase.Close() })
	reorganizationDatabase.SetMaxOpenConns(1)
	reorganizationDatabase.SetMaxIdleConns(1)
	if _, err := reorganizationDatabase.Exec(
		"SET ROLE unified_crosschain_reorganization_verifier",
	); err != nil {
		t.Fatal(err)
	}
	reorganizationRepository, err := NewSQL(reorganizationDatabase)
	if err != nil {
		t.Fatal(err)
	}
	reorganizationRequest := ReorganizationRequest{
		RouteID:                   registration.Route.RouteID,
		ChainID:                   proof.ChainID,
		OrphanedProofIDs:          []string{proof.ProofID},
		OrphanedCertificateIDs:    []string{certificate.CertificateID},
		ReplacementObservationID:  replacementObservation.ObservationID,
		DetectedHeadObservationID: detectedHeadObservation.ObservationID,
		AffectedMessageIDs:        [][32]byte{record.MessageID},
		EvidenceHash: integrationHash(
			"UNIFIED_PHASE8_REORGANIZATION_EVIDENCE_V1",
		),
		DetectedAt: transitionedAt.Add(4 * time.Minute),
	}
	recordedReorganization, err := reorganizationRepository.RecordReorganization(
		t.Context(),
		reorganizationRequest,
	)
	if err != nil ||
		!reorganizationMatchesRequest(recordedReorganization, reorganizationRequest) {
		t.Fatalf(
			"reorganization authority ingestion: %#v %v",
			recordedReorganization,
			err,
		)
	}
	replayedReorganization, err := reorganizationRepository.RecordReorganization(
		t.Context(),
		reorganizationRequest,
	)
	if err != nil ||
		replayedReorganization.ReorganizationID !=
			recordedReorganization.ReorganizationID {
		t.Fatalf(
			"reorganization authority replay: %#v %v",
			replayedReorganization,
			err,
		)
	}
	rehydratedReorganization, err := restarted.Reorganization(
		t.Context(),
		reorganizationRequest.EvidenceHash,
	)
	if err != nil ||
		!reflect.DeepEqual(rehydratedReorganization, recordedReorganization) {
		t.Fatalf(
			"reorganization restart rehydration: %#v %v",
			rehydratedReorganization,
			err,
		)
	}
	disputed, err := restarted.Message(record.MessageID)
	if err != nil ||
		disputed.State !=
			unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_DISPUTED ||
		disputed.Version != 4 ||
		disputed.Evidence != reorganizationRequest.EvidenceHash {
		t.Fatalf("reorganization did not durably dispute message: %#v %v", disputed, err)
	}
}

func integrationMessageRecord(
	t *testing.T,
	registration RouteRegistration,
) MessageRecord {
	t.Helper()
	record := sqlTestRecord(t, 7_777)
	var envelope unifiedv1.CrossChainMessageEnvelope
	if err := proto.Unmarshal(record.Envelope, &envelope); err != nil {
		t.Fatal(err)
	}
	envelope.MessageId = nil
	envelope.SourceChainId = registration.SourceChain.ChainID
	envelope.SourceCoordinator = append(
		[]byte(nil),
		registration.SourceChain.Coordinator[:]...,
	)
	envelope.SourceComponent = append(
		[]byte(nil),
		registration.SourceComponent[:]...,
	)
	envelope.DestinationChainId = registration.DestinationChain.ChainID
	envelope.DestinationCoordinator = append(
		[]byte(nil),
		registration.DestinationChain.Coordinator[:]...,
	)
	envelope.DestinationComponent = append(
		[]byte(nil),
		registration.DestinationComponent[:]...,
	)
	envelope.RoutePolicyHash = append(
		[]byte(nil),
		registration.Route.PolicyHash[:]...,
	)
	envelope.AdapterSetPolicyHash = append(
		[]byte(nil),
		registration.AdapterSetPolicyHash[:]...,
	)
	envelope.SourceFinalityPolicyHash = append(
		[]byte(nil),
		registration.SourceFinalityPolicyHash[:]...,
	)
	envelope.DestinationFinalityPolicyHash = append(
		[]byte(nil),
		registration.DestinationFinalityPolicyHash[:]...,
	)
	sealed, err := message.Seal(&envelope)
	if err != nil {
		t.Fatal(err)
	}
	serialized, err := message.DeterministicBytes(sealed)
	if err != nil {
		t.Fatal(err)
	}
	record.MessageID = bytes32(sealed.GetMessageId())
	record.Envelope = serialized
	record.Evidence = bytes32(sealed.GetPayloadHash())
	return record
}

func integrationHash(value string) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write([]byte(value))
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}

func seedIntegrationSignerSet(
	database *sql.DB,
	hash [32]byte,
	version uint64,
	addressPrefix byte,
) error {
	_, err := database.Exec(
		`INSERT INTO crosschain.signer_sets (
		    signer_set_hash, version, threshold, signer_addresses,
		    valid_from, valid_until, status
		) VALUES (
		    $1, $2, 2, ARRAY[$3::bytea, $4::bytea, $5::bytea],
		    '2025-01-01 00:00:00+00', '2101-01-01 00:00:00+00', 'ACTIVE'
		)
		ON CONFLICT (signer_set_hash, version) DO NOTHING`,
		hash[:],
		int64(version),
		bytes.Repeat([]byte{addressPrefix}, 20),
		bytes.Repeat([]byte{addressPrefix + 1}, 20),
		bytes.Repeat([]byte{addressPrefix + 2}, 20),
	)
	return err
}

func integrationSourceProof(
	record MessageRecord,
	registration RouteRegistration,
) SourceProofRecord {
	return SourceProofRecord{
		ProofID:          fmt.Sprintf("proof-%x", record.MessageID),
		MessageID:        record.MessageID,
		ChainID:          registration.SourceChain.ChainID,
		TransactionHash:  integrationHash("UNIFIED_PHASE8_OBSERVER_TX_V1"),
		TransactionIndex: "0",
		LogIndex:         "7",
		BlockNumber:      "100",
		BlockHash:        integrationHash("UNIFIED_PHASE8_OBSERVER_BLOCK_V1"),
		ReceiptsRoot:     integrationHash("UNIFIED_PHASE8_OBSERVER_RECEIPTS_V1"),
		InclusionProofHash: integrationHash(
			"UNIFIED_PHASE8_OBSERVER_INCLUSION_V1",
		),
		EventHash:          record.Evidence,
		FinalityHeadNumber: "112",
		FinalityHeadHash: integrationHash(
			"UNIFIED_PHASE8_OBSERVER_HEAD_V1",
		),
		ConfirmationDepth:     "12",
		FinalityPolicyHash:    registration.SourceFinalityPolicyHash,
		ObserverAuthorityHash: registration.SourceChain.ObserverAuthorityHash,
		ObserverSignedHeaderCommitment: integrationHash(
			"UNIFIED_PHASE8_OBSERVER_HEADER_V1",
		),
		ObserverSignature: []byte{1, 2, 3},
		ProofHash: integrationHash(
			"UNIFIED_PHASE8_OBSERVER_PROOF_V1",
		),
		ObservedAt: record.UpdatedAt,
	}
}

func integrationFinalityCertificate(
	proof SourceProofRecord,
	registration RouteRegistration,
) FinalityCertificateRecord {
	return FinalityCertificateRecord{
		CertificateID:    fmt.Sprintf("certificate-%x", proof.MessageID),
		MessageID:        proof.MessageID,
		ProofID:          proof.ProofID,
		SignerSetHash:    registration.SourceSignerSetHash,
		SignerSetVersion: registration.SourceSignerSetVersion,
		SignerBitmap:     "110",
		SignatureCount:   2,
		CertificateHash: integrationHash(
			"UNIFIED_PHASE8_OBSERVER_CERTIFICATE_V1",
		),
		CertifiedAt: proof.ObservedAt,
	}
}
