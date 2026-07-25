package store

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"math/big"
	"strconv"
	"strings"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/message"
	"google.golang.org/protobuf/proto"
)

var ErrInvalidSQLRepository = errors.New("invalid cross-chain SQL repository")

type rowScanner interface {
	Scan(dest ...any) error
}

type rowQueryer interface {
	QueryRowContext(context.Context, string, ...any) rowScanner
}

type rowsScanner interface {
	Next() bool
	Scan(dest ...any) error
	Err() error
	Close() error
}

type rowsQueryer interface {
	QueryContext(context.Context, string, ...any) (rowsScanner, error)
}

type databaseQueryer struct {
	database *sql.DB
}

func (queryer databaseQueryer) QueryRowContext(
	ctx context.Context,
	query string,
	args ...any,
) rowScanner {
	return queryer.database.QueryRowContext(ctx, query, args...)
}

func (queryer databaseQueryer) QueryContext(
	ctx context.Context,
	query string,
	args ...any,
) (rowsScanner, error) {
	return queryer.database.QueryContext(ctx, query, args...)
}

// SQL is the production Repository implementation. Authoritative mutations
// call only the crosschain SECURITY DEFINER API; table access is read-only.
type SQL struct {
	queryer      rowQueryer
	provisioning map[string]RouteRegistration
}

var _ Repository = (*SQL)(nil)

func NewSQL(database *sql.DB) (*SQL, error) {
	if database == nil {
		return nil, ErrInvalidSQLRepository
	}
	return &SQL{queryer: databaseQueryer{database: database}}, nil
}

func NewSQLWithProvisioning(
	database *sql.DB,
	registrations []RouteRegistration,
) (*SQL, error) {
	if database == nil {
		return nil, ErrInvalidSQLRepository
	}
	return newSQLWithProvisioning(
		databaseQueryer{database: database},
		registrations,
	)
}

func newSQL(queryer rowQueryer) (*SQL, error) {
	if queryer == nil {
		return nil, ErrInvalidSQLRepository
	}
	return &SQL{queryer: queryer}, nil
}

func newSQLWithProvisioning(
	queryer rowQueryer,
	registrations []RouteRegistration,
) (*SQL, error) {
	if queryer == nil || len(registrations) == 0 {
		return nil, ErrInvalidSQLRepository
	}
	configured := make(map[string]RouteRegistration, len(registrations))
	for _, registration := range registrations {
		if !validRouteRegistration(registration) {
			return nil, ErrInvalidSQLRepository
		}
		key := routeKey(registration.Route.RouteID, registration.Route.Version)
		if prior, exists := configured[key]; exists &&
			!sameRouteRegistration(prior, registration) {
			return nil, ErrInvalidSQLRepository
		}
		configured[key] = cloneRouteRegistration(registration)
	}
	return &SQL{queryer: queryer, provisioning: configured}, nil
}

type ChainRegistration struct {
	ChainID               string
	Version               uint64
	Coordinator           [20]byte
	FinalityVerifier      [20]byte
	ConfigurationHash     [32]byte
	ObserverAuthorityHash [32]byte
	ActivatedAtBlock      string
}

// RouteRegistration is deployment-local provisioning input. Route policy
// authority remains the committed hashes and exact active chain versions; no
// provider credential or signing authority is accepted here.
type RouteRegistration struct {
	Route                         RouteVersion
	SourceChain                   ChainRegistration
	DestinationChain              ChainRegistration
	SourceComponent               [20]byte
	DestinationComponent          [20]byte
	ActionFamily                  string
	AdapterSetPolicyHash          [32]byte
	SourceFinalityPolicyHash      [32]byte
	DestinationFinalityPolicyHash [32]byte
	SourceSignerSetHash           [32]byte
	SourceSignerSetVersion        uint64
	DestinationSignerSetHash      [32]byte
	DestinationSignerSetVersion   uint64
	ActivatedAtBlock              string
}

const recordMessageSQL = `
SELECT
    message_id,
    serialized_envelope,
    state,
    state_version,
    updated_at
FROM crosschain.record_message(
    $1, $2, $3, $4::numeric, $5, $6, $7::numeric, $8, $9,
    $10, $11::numeric, $12, $13, $14, $15, $16, $17, $18,
    $19, $20, $21, $22, $23, $24, $25
)`

func (repository *SQL) CreateMessage(record MessageRecord) (MessageRecord, error) {
	if repository == nil || repository.queryer == nil {
		return MessageRecord{}, ErrInvalidSQLRepository
	}
	envelope, err := validateMessageCreation(record)
	if err != nil {
		return MessageRecord{}, err
	}
	if err := repository.verifyEnvelopeRoute(envelope); err != nil {
		return MessageRecord{}, err
	}
	row := repository.queryer.QueryRowContext(
		context.Background(),
		recordMessageSQL,
		record.MessageID[:],
		int32(envelope.GetSchemaVersion()),
		envelope.GetProtocolId(),
		envelope.GetSourceChainId(),
		envelope.GetSourceCoordinator(),
		envelope.GetSourceComponent(),
		envelope.GetDestinationChainId(),
		envelope.GetDestinationCoordinator(),
		envelope.GetDestinationComponent(),
		envelope.GetLaneId(),
		strconv.FormatUint(envelope.GetSourceNonce(), 10),
		envelope.GetAggregateId(),
		int16(envelope.GetActionType()),
		envelope.GetPayloadHash(),
		envelope.GetCreatedAt().AsTime().UTC(),
		envelope.GetExpiresAt().AsTime().UTC(),
		envelope.GetRoutePolicyHash(),
		envelope.GetAdapterSetPolicyHash(),
		envelope.GetSourceFinalityPolicyHash(),
		envelope.GetDestinationFinalityPolicyHash(),
		envelope.GetCorrelationId(),
		envelope.GetCausationMessageId(),
		envelope.GetSupersededMessageId(),
		record.Envelope,
		record.UpdatedAt.UTC(),
	)
	result, scanErr := scanMutationMessage(row)
	if scanErr != nil {
		reloaded, reloadErr := repository.messageSnapshot(record.MessageID)
		if reloadErr == nil {
			resolved, replayErr := repository.resolveCreationReplay(
				record,
				envelope,
				reloaded.record,
			)
			if replayErr == nil {
				return resolved, nil
			}
			return MessageRecord{}, ErrConflict
		}
		return MessageRecord{}, classifyMutationError(
			"record cross-chain message",
			scanErr,
			ErrConflict,
		)
	}
	result.Evidence = bytes32(envelope.GetPayloadHash())
	return repository.resolveCreationReplay(record, envelope, result)
}

const verifyEnvelopeRouteSQL = `
SELECT EXISTS (
    SELECT 1
    FROM crosschain.route_versions
    WHERE route_policy_hash = $1
      AND source_chain_id = $2::numeric
      AND source_coordinator = $3
      AND source_component = $4
      AND destination_chain_id = $5::numeric
      AND destination_coordinator = $6
      AND destination_component = $7
      AND adapter_set_policy_hash = $8
      AND source_finality_policy_hash = $9
      AND destination_finality_policy_hash = $10
      AND status = 'ACTIVE'
)`

func (repository *SQL) verifyEnvelopeRoute(
	envelope *unifiedv1.CrossChainMessageEnvelope,
) error {
	var matches bool
	err := repository.queryer.QueryRowContext(
		context.Background(),
		verifyEnvelopeRouteSQL,
		envelope.GetRoutePolicyHash(),
		envelope.GetSourceChainId(),
		envelope.GetSourceCoordinator(),
		envelope.GetSourceComponent(),
		envelope.GetDestinationChainId(),
		envelope.GetDestinationCoordinator(),
		envelope.GetDestinationComponent(),
		envelope.GetAdapterSetPolicyHash(),
		envelope.GetSourceFinalityPolicyHash(),
		envelope.GetDestinationFinalityPolicyHash(),
	).Scan(&matches)
	if err != nil {
		return fmt.Errorf("verify cross-chain message route: %w", err)
	}
	if !matches {
		return ErrConflict
	}
	return nil
}

const transitionMessageSQL = `
SELECT
    message_id,
    serialized_envelope,
    state,
    state_version,
    updated_at
FROM crosschain.transition_message($1, $2, $3, $4, $5, $6, $7)`

func (repository *SQL) CompareAndSet(
	messageID [32]byte,
	expectedVersion uint64,
	next unifiedv1.CrossChainMessageState,
	retryable bool,
	evidence [32]byte,
	updatedAt time.Time,
) (MessageRecord, error) {
	if repository == nil || repository.queryer == nil ||
		messageID == ([32]byte{}) ||
		expectedVersion == 0 || expectedVersion > math.MaxInt64 ||
		evidence == ([32]byte{}) || updatedAt.IsZero() {
		return MessageRecord{}, ErrConflict
	}
	current, err := repository.messageSnapshot(messageID)
	if err != nil {
		return MessageRecord{}, err
	}
	failureClass := transitionFailureClass(retryable)
	if current.record.Version != expectedVersion {
		if exactTransitionReplay(
			current,
			expectedVersion,
			next,
			failureClass,
			evidence,
			updatedAt,
		) {
			return current.record, nil
		}
		return MessageRecord{}, ErrConflict
	}
	if updatedAt.Before(current.record.UpdatedAt) ||
		!message.CanTransition(current.record.State, next, retryable) {
		return MessageRecord{}, ErrConflict
	}
	nextState, ok := stateToDatabase(next)
	if !ok {
		return MessageRecord{}, ErrConflict
	}
	currentState, ok := stateToDatabase(current.record.State)
	if !ok {
		return MessageRecord{}, ErrConflict
	}
	var failureArgument any
	if failureClass != "" {
		failureArgument = failureClass
	}
	row := repository.queryer.QueryRowContext(
		context.Background(),
		transitionMessageSQL,
		messageID[:],
		int64(expectedVersion),
		currentState,
		nextState,
		failureArgument,
		evidence[:],
		updatedAt.UTC(),
	)
	result, scanErr := scanMutationMessage(row)
	if scanErr != nil {
		// The database may have committed before the response was lost. Reload
		// and return success only for the exact persisted transition request.
		reloaded, reloadErr := repository.messageSnapshot(messageID)
		if reloadErr == nil && exactTransitionReplay(
			reloaded,
			expectedVersion,
			next,
			failureClass,
			evidence,
			updatedAt,
		) {
			return reloaded.record, nil
		}
		if reloadErr == nil {
			return MessageRecord{}, ErrConflict
		}
		return MessageRecord{}, classifyMutationError(
			"transition cross-chain message",
			scanErr,
			ErrConflict,
		)
	}
	result.Evidence = evidence
	if result.MessageID != messageID ||
		result.State != next ||
		result.Version != expectedVersion+1 ||
		!result.UpdatedAt.Equal(updatedAt.UTC()) {
		return MessageRecord{}, ErrInvalidSQLRepository
	}
	return result, nil
}

const claimOutboxSQL = `
SELECT
    outbox_id,
    message_id,
    state_version,
    topic,
    partition_key,
    payload,
    payload_hash,
    status,
    attempt_count,
    publisher_id,
    lease_until,
    created_at,
    published_at,
    broker_offset
FROM crosschain.claim_outbox($1, $2, $3, $4)`

// ClaimOutbox leases an ordered batch of pending (or expired) durable events.
// A caller that loses the response can safely wait for the lease to expire and
// reclaim the same deterministic outbox record after restart.
func (repository *SQL) ClaimOutbox(
	ctx context.Context,
	publisherID string,
	leaseUntil time.Time,
	claimedAt time.Time,
	batchSize int,
) ([]OutboxRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		publisherID == "" || leaseUntil.IsZero() || claimedAt.IsZero() ||
		!leaseUntil.After(claimedAt) || batchSize < 1 || batchSize > 1000 {
		return nil, ErrConflict
	}
	queryer, ok := repository.queryer.(rowsQueryer)
	if !ok {
		return nil, ErrInvalidSQLRepository
	}
	rows, err := queryer.QueryContext(
		ctx,
		claimOutboxSQL,
		publisherID,
		leaseUntil.UTC(),
		claimedAt.UTC(),
		batchSize,
	)
	if err != nil {
		return nil, classifyMutationError("claim cross-chain outbox", err, ErrConflict)
	}
	defer func() { _ = rows.Close() }()

	records := make([]OutboxRecord, 0, batchSize)
	for rows.Next() {
		record, scanErr := scanOutbox(rows)
		if scanErr != nil {
			return nil, fmt.Errorf("scan claimed cross-chain outbox: %w", scanErr)
		}
		records = append(records, record)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate claimed cross-chain outbox: %w", err)
	}
	return records, nil
}

const markOutboxPublishedSQL = `
SELECT
    outbox_id,
    message_id,
    state_version,
    topic,
    partition_key,
    payload,
    payload_hash,
    status,
    attempt_count,
    publisher_id,
    lease_until,
    created_at,
    published_at,
    broker_offset
FROM crosschain.mark_outbox_published($1, $2, $3, $4, $5)`

func (repository *SQL) MarkOutboxPublished(
	ctx context.Context,
	outboxID string,
	publisherID string,
	expectedAttemptCount uint32,
	brokerOffset string,
	publishedAt time.Time,
) (OutboxRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		outboxID == "" || publisherID == "" || expectedAttemptCount == 0 ||
		expectedAttemptCount > math.MaxInt32 || brokerOffset == "" ||
		publishedAt.IsZero() {
		return OutboxRecord{}, ErrConflict
	}
	row := repository.queryer.QueryRowContext(
		ctx,
		markOutboxPublishedSQL,
		outboxID,
		publisherID,
		int32(expectedAttemptCount),
		brokerOffset,
		publishedAt.UTC(),
	)
	result, scanErr := scanOutbox(row)
	if scanErr != nil {
		// The update can commit before its response is lost. A read-only reload
		// distinguishes that exact replay from a conflicting publication.
		reloaded, reloadErr := repository.outbox(ctx, outboxID)
		if reloadErr == nil && exactOutboxPublication(
			reloaded,
			publisherID,
			expectedAttemptCount,
			brokerOffset,
			publishedAt,
		) {
			return reloaded, nil
		}
		if reloadErr == nil {
			return OutboxRecord{}, ErrConflict
		}
		return OutboxRecord{}, classifyMutationError(
			"mark cross-chain outbox published",
			scanErr,
			ErrConflict,
		)
	}
	if !exactOutboxPublication(
		result,
		publisherID,
		expectedAttemptCount,
		brokerOffset,
		publishedAt,
	) {
		return OutboxRecord{}, ErrConflict
	}
	return result, nil
}

const consumeInboxSQL = `
SELECT
    consumer_id,
    message_id,
    topic,
    partition_key,
    broker_offset,
    payload_hash,
    consumed_at
FROM crosschain.consume_inbox($1, $2, $3, $4, $5, $6, $7)`

func (repository *SQL) ConsumeInbox(
	ctx context.Context,
	consumerID string,
	messageID [32]byte,
	topic string,
	partitionKey string,
	brokerOffset string,
	payloadHash [32]byte,
	consumedAt time.Time,
) (InboxRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		consumerID == "" || messageID == ([32]byte{}) || topic == "" ||
		partitionKey == "" || brokerOffset == "" ||
		payloadHash == ([32]byte{}) || consumedAt.IsZero() {
		return InboxRecord{}, ErrConflict
	}
	row := repository.queryer.QueryRowContext(
		ctx,
		consumeInboxSQL,
		consumerID,
		messageID[:],
		topic,
		partitionKey,
		brokerOffset,
		payloadHash[:],
		consumedAt.UTC(),
	)
	result, scanErr := scanInbox(row)
	if scanErr != nil {
		reloaded, reloadErr := repository.inbox(
			ctx,
			consumerID,
			topic,
			partitionKey,
			brokerOffset,
		)
		if reloadErr == nil && exactInboxConsumption(
			reloaded,
			messageID,
			partitionKey,
			payloadHash,
			consumedAt,
		) {
			return reloaded, nil
		}
		if reloadErr == nil {
			return InboxRecord{}, ErrConflict
		}
		return InboxRecord{}, classifyMutationError(
			"consume cross-chain inbox",
			scanErr,
			ErrConflict,
		)
	}
	if result.ConsumerID != consumerID || result.Topic != topic ||
		result.PartitionKey != partitionKey ||
		result.BrokerOffset != brokerOffset ||
		!exactInboxConsumption(
			result,
			messageID,
			partitionKey,
			payloadHash,
			consumedAt,
		) {
		return InboxRecord{}, ErrConflict
	}
	return result, nil
}

const recordProviderAttemptSQL = `
SELECT
    message_id,
    provider_id,
    attempt_number,
    serialized_envelope_hash,
    source_proof_hash,
    status,
    provider_receipt_hash,
    attempted_at
FROM crosschain.record_provider_attempt($1, $2, $3, $4, $5, $6, $7, $8)`

func (repository *SQL) RecordProviderAttempt(
	ctx context.Context,
	record ProviderAttemptRecord,
) (ProviderAttemptRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		!validProviderAttempt(record) {
		return ProviderAttemptRecord{}, ErrConflict
	}
	var receipt any
	if record.Status == "DELIVERED" {
		receipt = record.ReceiptHash[:]
	}
	row := repository.queryer.QueryRowContext(
		ctx,
		recordProviderAttemptSQL,
		record.MessageID[:],
		record.ProviderID,
		int32(record.AttemptNumber),
		record.EnvelopeHash[:],
		record.SourceProofHash[:],
		record.Status,
		receipt,
		record.AttemptedAt.UTC(),
	)
	result, scanErr := scanProviderAttempt(row)
	if scanErr != nil {
		reloaded, reloadErr := repository.ProviderAttempt(
			ctx,
			record.MessageID,
			record.ProviderID,
			record.AttemptNumber,
		)
		if reloadErr == nil && sameProviderAttempt(reloaded, record) {
			return reloaded, nil
		}
		if reloadErr == nil {
			return ProviderAttemptRecord{}, ErrConflict
		}
		return ProviderAttemptRecord{}, classifyMutationError(
			"record cross-chain provider attempt",
			scanErr,
			ErrConflict,
		)
	}
	if !sameProviderAttempt(result, record) {
		return ProviderAttemptRecord{}, ErrConflict
	}
	return result, nil
}

const loadProviderAttemptSQL = `
SELECT
    message_id,
    provider_id,
    attempt_number,
    serialized_envelope_hash,
    source_proof_hash,
    status,
    provider_receipt_hash,
    attempted_at
FROM crosschain.provider_attempts
WHERE message_id = $1
  AND provider_id = $2
  AND attempt_number = $3`

func (repository *SQL) ProviderAttempt(
	ctx context.Context,
	messageID [32]byte,
	providerID string,
	attemptNumber uint32,
) (ProviderAttemptRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		messageID == ([32]byte{}) || providerID == "" ||
		attemptNumber == 0 || attemptNumber > math.MaxInt32 {
		return ProviderAttemptRecord{}, ErrNotFound
	}
	result, err := scanProviderAttempt(repository.queryer.QueryRowContext(
		ctx,
		loadProviderAttemptSQL,
		messageID[:],
		providerID,
		int32(attemptNumber),
	))
	if errors.Is(err, sql.ErrNoRows) {
		return ProviderAttemptRecord{}, ErrNotFound
	}
	if err != nil {
		return ProviderAttemptRecord{}, fmt.Errorf(
			"load cross-chain provider attempt: %w",
			err,
		)
	}
	return result, nil
}

func scanProviderAttempt(row rowScanner) (ProviderAttemptRecord, error) {
	var (
		messageID       []byte
		providerID      string
		attemptNumber   int64
		envelopeHash    []byte
		sourceProofHash []byte
		status          string
		receiptHash     []byte
		attemptedAt     time.Time
	)
	if err := row.Scan(
		&messageID,
		&providerID,
		&attemptNumber,
		&envelopeHash,
		&sourceProofHash,
		&status,
		&receiptHash,
		&attemptedAt,
	); err != nil {
		return ProviderAttemptRecord{}, err
	}
	if len(messageID) != 32 || attemptNumber <= 0 ||
		attemptNumber > math.MaxInt32 || len(envelopeHash) != 32 ||
		len(sourceProofHash) != 32 ||
		(status == "DELIVERED" && len(receiptHash) != 32) ||
		(status != "DELIVERED" && len(receiptHash) != 0) {
		return ProviderAttemptRecord{}, ErrInvalidSQLRepository
	}
	result := ProviderAttemptRecord{
		MessageID:       bytes32(messageID),
		ProviderID:      providerID,
		AttemptNumber:   uint32(attemptNumber),
		EnvelopeHash:    bytes32(envelopeHash),
		SourceProofHash: bytes32(sourceProofHash),
		Status:          status,
		AttemptedAt:     attemptedAt.UTC(),
	}
	if len(receiptHash) == 32 {
		result.ReceiptHash = bytes32(receiptHash)
	}
	if !validProviderAttempt(result) {
		return ProviderAttemptRecord{}, ErrInvalidSQLRepository
	}
	return result, nil
}

func validProviderAttempt(record ProviderAttemptRecord) bool {
	if record.MessageID == ([32]byte{}) || record.ProviderID == "" ||
		record.AttemptNumber == 0 || record.AttemptNumber > math.MaxInt32 ||
		record.EnvelopeHash == ([32]byte{}) ||
		record.SourceProofHash == ([32]byte{}) || record.AttemptedAt.IsZero() {
		return false
	}
	switch record.Status {
	case "DELIVERED":
		return record.ReceiptHash != ([32]byte{})
	case "FAILED", "REQUESTED":
		return record.ReceiptHash == ([32]byte{})
	default:
		return false
	}
}

func sameProviderAttempt(left, right ProviderAttemptRecord) bool {
	return left.MessageID == right.MessageID &&
		left.ProviderID == right.ProviderID &&
		left.AttemptNumber == right.AttemptNumber &&
		left.EnvelopeHash == right.EnvelopeHash &&
		left.SourceProofHash == right.SourceProofHash &&
		left.Status == right.Status &&
		left.ReceiptHash == right.ReceiptHash &&
		left.AttemptedAt.Equal(right.AttemptedAt)
}

const recordSourceProofSQL = `
SELECT
    proof_id,
    message_id,
    chain_id::text,
    transaction_hash,
    transaction_index::text,
    log_index::text,
    block_number::text,
    block_hash,
    receipts_root,
    inclusion_proof_hash,
    event_hash,
    finality_head_number::text,
    finality_head_hash,
    confirmation_depth::text,
    finality_policy_hash,
    observer_authority_hash,
    observer_signed_header_commitment,
    observer_signature,
    proof_hash,
    observed_at
FROM crosschain.record_source_proof(
    $1, $2, $3::numeric, $4, $5::numeric, $6::numeric, $7::numeric,
    $8, $9, $10, $11, $12::numeric, $13, $14::numeric, $15, $16,
    $17, $18, $19, $20
)`

func (repository *SQL) RecordSourceProof(
	ctx context.Context,
	record SourceProofRecord,
) (SourceProofRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		!validSourceProof(record) {
		return SourceProofRecord{}, ErrConflict
	}
	result, scanErr := scanSourceProof(repository.queryer.QueryRowContext(
		ctx,
		recordSourceProofSQL,
		record.ProofID,
		record.MessageID[:],
		record.ChainID,
		record.TransactionHash[:],
		record.TransactionIndex,
		record.LogIndex,
		record.BlockNumber,
		record.BlockHash[:],
		record.ReceiptsRoot[:],
		record.InclusionProofHash[:],
		record.EventHash[:],
		record.FinalityHeadNumber,
		record.FinalityHeadHash[:],
		record.ConfirmationDepth,
		record.FinalityPolicyHash[:],
		record.ObserverAuthorityHash[:],
		record.ObserverSignedHeaderCommitment[:],
		record.ObserverSignature,
		record.ProofHash[:],
		record.ObservedAt.UTC(),
	))
	if scanErr != nil {
		reloaded, reloadErr := repository.SourceProof(ctx, record.ProofID)
		if reloadErr == nil && sameSourceProof(reloaded, record) {
			return reloaded, nil
		}
		if reloadErr == nil {
			return SourceProofRecord{}, ErrConflict
		}
		return SourceProofRecord{}, classifyMutationError(
			"record cross-chain source proof",
			scanErr,
			ErrConflict,
		)
	}
	if !sameSourceProof(result, record) {
		return SourceProofRecord{}, ErrConflict
	}
	return result, nil
}

const loadSourceProofSQL = `
SELECT
    proof_id,
    message_id,
    chain_id::text,
    transaction_hash,
    transaction_index::text,
    log_index::text,
    block_number::text,
    block_hash,
    receipts_root,
    inclusion_proof_hash,
    event_hash,
    finality_head_number::text,
    finality_head_hash,
    confirmation_depth::text,
    finality_policy_hash,
    observer_authority_hash,
    observer_signed_header_commitment,
    observer_signature,
    proof_hash,
    observed_at
FROM crosschain.load_source_proof($1)`

func (repository *SQL) SourceProof(
	ctx context.Context,
	proofID string,
) (SourceProofRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		proofID == "" {
		return SourceProofRecord{}, ErrNotFound
	}
	result, err := scanSourceProof(repository.queryer.QueryRowContext(
		ctx,
		loadSourceProofSQL,
		proofID,
	))
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "not found") {
			return SourceProofRecord{}, ErrNotFound
		}
		return SourceProofRecord{}, fmt.Errorf("load cross-chain source proof: %w", err)
	}
	return result, nil
}

func scanSourceProof(row rowScanner) (SourceProofRecord, error) {
	var (
		result                         SourceProofRecord
		messageID                      []byte
		transactionHash                []byte
		blockHash                      []byte
		receiptsRoot                   []byte
		inclusionProofHash             []byte
		eventHash                      []byte
		finalityHeadHash               []byte
		finalityPolicyHash             []byte
		observerAuthorityHash          []byte
		observerSignedHeaderCommitment []byte
		proofHash                      []byte
	)
	if err := row.Scan(
		&result.ProofID,
		&messageID,
		&result.ChainID,
		&transactionHash,
		&result.TransactionIndex,
		&result.LogIndex,
		&result.BlockNumber,
		&blockHash,
		&receiptsRoot,
		&inclusionProofHash,
		&eventHash,
		&result.FinalityHeadNumber,
		&finalityHeadHash,
		&result.ConfirmationDepth,
		&finalityPolicyHash,
		&observerAuthorityHash,
		&observerSignedHeaderCommitment,
		&result.ObserverSignature,
		&proofHash,
		&result.ObservedAt,
	); err != nil {
		return SourceProofRecord{}, err
	}
	hashes := [][]byte{
		messageID, transactionHash, blockHash, receiptsRoot,
		inclusionProofHash, eventHash, finalityHeadHash, finalityPolicyHash,
		observerAuthorityHash, observerSignedHeaderCommitment, proofHash,
	}
	for _, value := range hashes {
		if len(value) != 32 {
			return SourceProofRecord{}, ErrConflict
		}
	}
	copy(result.MessageID[:], messageID)
	copy(result.TransactionHash[:], transactionHash)
	copy(result.BlockHash[:], blockHash)
	copy(result.ReceiptsRoot[:], receiptsRoot)
	copy(result.InclusionProofHash[:], inclusionProofHash)
	copy(result.EventHash[:], eventHash)
	copy(result.FinalityHeadHash[:], finalityHeadHash)
	copy(result.FinalityPolicyHash[:], finalityPolicyHash)
	copy(result.ObserverAuthorityHash[:], observerAuthorityHash)
	copy(
		result.ObserverSignedHeaderCommitment[:],
		observerSignedHeaderCommitment,
	)
	copy(result.ProofHash[:], proofHash)
	result.ObserverSignature = append([]byte(nil), result.ObserverSignature...)
	result.ObservedAt = result.ObservedAt.UTC()
	if !validSourceProof(result) {
		return SourceProofRecord{}, ErrConflict
	}
	return result, nil
}

func validSourceProof(record SourceProofRecord) bool {
	if record.ProofID == "" || record.MessageID == ([32]byte{}) ||
		record.TransactionHash == ([32]byte{}) ||
		record.BlockHash == ([32]byte{}) ||
		record.ReceiptsRoot == ([32]byte{}) ||
		record.InclusionProofHash == ([32]byte{}) ||
		record.EventHash == ([32]byte{}) ||
		record.FinalityHeadHash == ([32]byte{}) ||
		record.FinalityPolicyHash == ([32]byte{}) ||
		record.ObserverAuthorityHash == ([32]byte{}) ||
		record.ObserverSignedHeaderCommitment == ([32]byte{}) ||
		len(record.ObserverSignature) == 0 ||
		record.ProofHash == ([32]byte{}) || record.ObservedAt.IsZero() ||
		!canonicalUint256(record.ChainID, false) ||
		!canonicalUint256(record.TransactionIndex, true) ||
		!canonicalUint256(record.LogIndex, true) ||
		!canonicalUint256(record.BlockNumber, true) ||
		!canonicalUint256(record.FinalityHeadNumber, true) ||
		!canonicalUint256(record.ConfirmationDepth, false) {
		return false
	}
	block, _ := new(big.Int).SetString(record.BlockNumber, 10)
	head, _ := new(big.Int).SetString(record.FinalityHeadNumber, 10)
	depth, _ := new(big.Int).SetString(record.ConfirmationDepth, 10)
	return head.Cmp(new(big.Int).Add(block, depth)) >= 0
}

func sameSourceProof(left, right SourceProofRecord) bool {
	return left.ProofID == right.ProofID &&
		left.MessageID == right.MessageID &&
		left.ChainID == right.ChainID &&
		left.TransactionHash == right.TransactionHash &&
		left.TransactionIndex == right.TransactionIndex &&
		left.LogIndex == right.LogIndex &&
		left.BlockNumber == right.BlockNumber &&
		left.BlockHash == right.BlockHash &&
		left.ReceiptsRoot == right.ReceiptsRoot &&
		left.InclusionProofHash == right.InclusionProofHash &&
		left.EventHash == right.EventHash &&
		left.FinalityHeadNumber == right.FinalityHeadNumber &&
		left.FinalityHeadHash == right.FinalityHeadHash &&
		left.ConfirmationDepth == right.ConfirmationDepth &&
		left.FinalityPolicyHash == right.FinalityPolicyHash &&
		left.ObserverAuthorityHash == right.ObserverAuthorityHash &&
		left.ObserverSignedHeaderCommitment ==
			right.ObserverSignedHeaderCommitment &&
		bytes.Equal(left.ObserverSignature, right.ObserverSignature) &&
		left.ProofHash == right.ProofHash &&
		left.ObservedAt.Equal(right.ObservedAt)
}

const recordFinalityCertificateSQL = `
SELECT
    certificate_id,
    message_id,
    proof_id,
    signer_set_hash,
    signer_set_version,
    signer_bitmap::text,
    signature_count,
    certificate_hash,
    certified_at
FROM crosschain.record_finality_certificate(
    $1, $2, $3, $4, $5, $6::bit varying, $7, $8, $9
)`

func (repository *SQL) RecordFinalityCertificate(
	ctx context.Context,
	record FinalityCertificateRecord,
) (FinalityCertificateRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		!validFinalityCertificate(record) {
		return FinalityCertificateRecord{}, ErrConflict
	}
	result, scanErr := scanFinalityCertificate(
		repository.queryer.QueryRowContext(
			ctx,
			recordFinalityCertificateSQL,
			record.CertificateID,
			record.MessageID[:],
			record.ProofID,
			record.SignerSetHash[:],
			int64(record.SignerSetVersion),
			record.SignerBitmap,
			int32(record.SignatureCount),
			record.CertificateHash[:],
			record.CertifiedAt.UTC(),
		),
	)
	if scanErr != nil {
		reloaded, reloadErr := repository.FinalityCertificate(
			ctx,
			record.CertificateID,
		)
		if reloadErr == nil && sameFinalityCertificate(reloaded, record) {
			return reloaded, nil
		}
		if reloadErr == nil {
			return FinalityCertificateRecord{}, ErrConflict
		}
		return FinalityCertificateRecord{}, classifyMutationError(
			"record cross-chain finality certificate",
			scanErr,
			ErrConflict,
		)
	}
	if !sameFinalityCertificate(result, record) {
		return FinalityCertificateRecord{}, ErrConflict
	}
	return result, nil
}

const loadFinalityCertificateSQL = `
SELECT
    certificate_id,
    message_id,
    proof_id,
    signer_set_hash,
    signer_set_version,
    signer_bitmap::text,
    signature_count,
    certificate_hash,
    certified_at
FROM crosschain.load_finality_certificate($1)`

func (repository *SQL) FinalityCertificate(
	ctx context.Context,
	certificateID string,
) (FinalityCertificateRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		certificateID == "" {
		return FinalityCertificateRecord{}, ErrNotFound
	}
	result, err := scanFinalityCertificate(repository.queryer.QueryRowContext(
		ctx,
		loadFinalityCertificateSQL,
		certificateID,
	))
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "not found") {
			return FinalityCertificateRecord{}, ErrNotFound
		}
		return FinalityCertificateRecord{}, fmt.Errorf(
			"load cross-chain finality certificate: %w",
			err,
		)
	}
	return result, nil
}

func scanFinalityCertificate(
	row rowScanner,
) (FinalityCertificateRecord, error) {
	var (
		result           FinalityCertificateRecord
		messageID        []byte
		signerSetHash    []byte
		signerSetVersion int64
		signatureCount   int64
		certificateHash  []byte
	)
	if err := row.Scan(
		&result.CertificateID,
		&messageID,
		&result.ProofID,
		&signerSetHash,
		&signerSetVersion,
		&result.SignerBitmap,
		&signatureCount,
		&certificateHash,
		&result.CertifiedAt,
	); err != nil {
		return FinalityCertificateRecord{}, err
	}
	if len(messageID) != 32 || len(signerSetHash) != 32 ||
		len(certificateHash) != 32 || signerSetVersion <= 0 ||
		signatureCount < 0 || signatureCount > math.MaxUint32 {
		return FinalityCertificateRecord{}, ErrConflict
	}
	copy(result.MessageID[:], messageID)
	copy(result.SignerSetHash[:], signerSetHash)
	copy(result.CertificateHash[:], certificateHash)
	result.SignerSetVersion = uint64(signerSetVersion)
	result.SignatureCount = uint32(signatureCount)
	result.CertifiedAt = result.CertifiedAt.UTC()
	if !validFinalityCertificate(result) {
		return FinalityCertificateRecord{}, ErrConflict
	}
	return result, nil
}

func validFinalityCertificate(record FinalityCertificateRecord) bool {
	if record.CertificateID == "" || record.MessageID == ([32]byte{}) ||
		record.ProofID == "" || record.SignerSetHash == ([32]byte{}) ||
		record.SignerSetVersion == 0 ||
		record.SignerSetVersion > math.MaxUint32 ||
		record.CertificateHash == ([32]byte{}) ||
		record.CertifiedAt.IsZero() || len(record.SignerBitmap) != 3 {
		return false
	}
	count := uint32(0)
	for _, bit := range record.SignerBitmap {
		if bit == '1' {
			count++
		} else if bit != '0' {
			return false
		}
	}
	return count == record.SignatureCount && count >= 2
}

func sameFinalityCertificate(
	left FinalityCertificateRecord,
	right FinalityCertificateRecord,
) bool {
	return left.CertificateID == right.CertificateID &&
		left.MessageID == right.MessageID &&
		left.ProofID == right.ProofID &&
		left.SignerSetHash == right.SignerSetHash &&
		left.SignerSetVersion == right.SignerSetVersion &&
		left.SignerBitmap == right.SignerBitmap &&
		left.SignatureCount == right.SignatureCount &&
		left.CertificateHash == right.CertificateHash &&
		left.CertifiedAt.Equal(right.CertifiedAt)
}

const recordHeaderObservationSQL = `
SELECT
    observation_id,
    chain_id::text,
    block_hash,
    block_number::text,
    header_authority_hash,
    observer_signed_header_commitment,
    observer_signature,
    finality_policy_hash,
    observed_at
FROM crosschain.record_header_observation(
    $1, $2::numeric, $3, $4::numeric, $5, $6, $7, $8, $9
)`

const loadHeaderObservationSQL = `
SELECT
    observation_id,
    chain_id::text,
    block_hash,
    block_number::text,
    header_authority_hash,
    observer_signed_header_commitment,
    observer_signature,
    finality_policy_hash,
    observed_at
FROM crosschain.header_observations
WHERE observation_id = $1`

func (repository *SQL) RecordHeaderObservation(
	ctx context.Context,
	record HeaderObservationRecord,
) (HeaderObservationRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		!validHeaderObservation(record) {
		return HeaderObservationRecord{}, ErrConflict
	}
	arguments := []any{
		record.ObservationID,
		record.ChainID,
		record.BlockHash[:],
		record.BlockNumber,
		record.HeaderAuthorityHash[:],
		record.ObserverSignedHeaderCommitment[:],
		record.ObserverSignature,
		record.FinalityPolicyHash[:],
		record.ObservedAt.UTC(),
	}
	result, scanErr := scanHeaderObservation(
		repository.queryer.QueryRowContext(
			ctx,
			recordHeaderObservationSQL,
			arguments...,
		),
	)
	if scanErr != nil {
		result, scanErr = scanHeaderObservation(
			repository.queryer.QueryRowContext(
				ctx,
				recordHeaderObservationSQL,
				arguments...,
			),
		)
	}
	if scanErr != nil {
		return HeaderObservationRecord{}, classifyMutationError(
			"record cross-chain header observation",
			scanErr,
			ErrConflict,
		)
	}
	if !sameHeaderObservation(result, record) {
		return HeaderObservationRecord{}, ErrConflict
	}
	return result, nil
}

func (repository *SQL) HeaderObservation(
	ctx context.Context,
	observationID string,
) (HeaderObservationRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		observationID == "" {
		return HeaderObservationRecord{}, ErrNotFound
	}
	result, err := scanHeaderObservation(repository.queryer.QueryRowContext(
		ctx,
		loadHeaderObservationSQL,
		observationID,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return HeaderObservationRecord{}, ErrNotFound
	}
	if err != nil {
		return HeaderObservationRecord{}, fmt.Errorf(
			"load cross-chain header observation: %w",
			err,
		)
	}
	return result, nil
}

func scanHeaderObservation(row rowScanner) (HeaderObservationRecord, error) {
	var (
		result                 HeaderObservationRecord
		blockHash              []byte
		headerAuthorityHash    []byte
		signedHeaderCommitment []byte
		finalityPolicyHash     []byte
	)
	if err := row.Scan(
		&result.ObservationID,
		&result.ChainID,
		&blockHash,
		&result.BlockNumber,
		&headerAuthorityHash,
		&signedHeaderCommitment,
		&result.ObserverSignature,
		&finalityPolicyHash,
		&result.ObservedAt,
	); err != nil {
		return HeaderObservationRecord{}, err
	}
	if len(blockHash) != 32 || len(headerAuthorityHash) != 32 ||
		len(signedHeaderCommitment) != 32 || len(finalityPolicyHash) != 32 {
		return HeaderObservationRecord{}, ErrConflict
	}
	copy(result.BlockHash[:], blockHash)
	copy(result.HeaderAuthorityHash[:], headerAuthorityHash)
	copy(result.ObserverSignedHeaderCommitment[:], signedHeaderCommitment)
	copy(result.FinalityPolicyHash[:], finalityPolicyHash)
	result.ObserverSignature = append([]byte(nil), result.ObserverSignature...)
	result.ObservedAt = result.ObservedAt.UTC()
	if !validHeaderObservation(result) {
		return HeaderObservationRecord{}, ErrConflict
	}
	return result, nil
}

func validHeaderObservation(record HeaderObservationRecord) bool {
	return record.ObservationID != "" &&
		canonicalUint256(record.ChainID, false) &&
		record.BlockHash != ([32]byte{}) &&
		canonicalUint256(record.BlockNumber, false) &&
		record.HeaderAuthorityHash != ([32]byte{}) &&
		record.ObserverSignedHeaderCommitment != ([32]byte{}) &&
		len(record.ObserverSignature) > 0 &&
		record.FinalityPolicyHash != ([32]byte{}) &&
		!record.ObservedAt.IsZero()
}

func sameHeaderObservation(
	left HeaderObservationRecord,
	right HeaderObservationRecord,
) bool {
	return left.ObservationID == right.ObservationID &&
		left.ChainID == right.ChainID &&
		left.BlockHash == right.BlockHash &&
		left.BlockNumber == right.BlockNumber &&
		left.HeaderAuthorityHash == right.HeaderAuthorityHash &&
		left.ObserverSignedHeaderCommitment ==
			right.ObserverSignedHeaderCommitment &&
		bytes.Equal(left.ObserverSignature, right.ObserverSignature) &&
		left.FinalityPolicyHash == right.FinalityPolicyHash &&
		left.ObservedAt.Equal(right.ObservedAt)
}

const recordReorganizationSQL = `
SELECT
    reorganization.reorganization_id,
    reorganization.route_id,
    reorganization.chain_id::text,
    reorganization.orphaned_block_hash,
    reorganization.orphaned_block_number::text,
    reorganization.orphaned_proof_id,
    reorganization.orphaned_certificate_id,
    array_to_json(reorganization.orphaned_proof_ids)::text,
    array_to_json(reorganization.orphaned_certificate_ids)::text,
    reorganization.replacement_block_hash,
    reorganization.replacement_block_number::text,
    reorganization.replacement_observation_id,
    reorganization.detected_head_hash,
    reorganization.detected_head_number::text,
    reorganization.detected_head_observation_id,
    reorganization.depth_class,
    COALESCE((
        SELECT string_agg(encode(affected.message_id, 'hex'), ',' ORDER BY affected.item_order)
        FROM unnest(reorganization.affected_message_ids) WITH ORDINALITY
            AS affected(message_id, item_order)
    ), ''),
    reorganization.evidence_hash,
    reorganization.detected_at
FROM crosschain.record_reorganization(
    $1, $2::numeric, $3::text[], $4::text[], $5, $6, $7::bytea[], $8, $9
) AS reorganization`

const loadReorganizationSQL = `
SELECT
    reorganization.reorganization_id,
    reorganization.route_id,
    reorganization.chain_id::text,
    reorganization.orphaned_block_hash,
    reorganization.orphaned_block_number::text,
    reorganization.orphaned_proof_id,
    reorganization.orphaned_certificate_id,
    array_to_json(reorganization.orphaned_proof_ids)::text,
    array_to_json(reorganization.orphaned_certificate_ids)::text,
    reorganization.replacement_block_hash,
    reorganization.replacement_block_number::text,
    reorganization.replacement_observation_id,
    reorganization.detected_head_hash,
    reorganization.detected_head_number::text,
    reorganization.detected_head_observation_id,
    reorganization.depth_class,
    COALESCE((
        SELECT string_agg(encode(affected.message_id, 'hex'), ',' ORDER BY affected.item_order)
        FROM unnest(reorganization.affected_message_ids) WITH ORDINALITY
            AS affected(message_id, item_order)
    ), ''),
    reorganization.evidence_hash,
    reorganization.detected_at,
    incident.incident_id,
    incident.reason_code,
    incident.severity,
    incident.owner,
    incident.status,
    incident.opened_at
FROM crosschain.reorganizations AS reorganization
JOIN crosschain.incidents AS incident
  ON incident.reorganization_id = reorganization.reorganization_id
WHERE reorganization.evidence_hash = $1`

func (repository *SQL) RecordReorganization(
	ctx context.Context,
	request ReorganizationRequest,
) (ReorganizationRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		!validReorganizationRequest(request) {
		return ReorganizationRecord{}, ErrConflict
	}
	arguments := []any{
		request.RouteID,
		request.ChainID,
		textArrayLiteral(request.OrphanedProofIDs),
		textArrayLiteral(request.OrphanedCertificateIDs),
		request.ReplacementObservationID,
		request.DetectedHeadObservationID,
		byteaArrayLiteral(request.AffectedMessageIDs),
		request.EvidenceHash[:],
		request.DetectedAt.UTC(),
	}
	result, scanErr := scanReorganization(
		repository.queryer.QueryRowContext(
			ctx,
			recordReorganizationSQL,
			arguments...,
		),
		false,
	)
	if scanErr != nil {
		result, scanErr = scanReorganization(
			repository.queryer.QueryRowContext(
				ctx,
				recordReorganizationSQL,
				arguments...,
			),
			false,
		)
	}
	if scanErr != nil {
		return ReorganizationRecord{}, classifyMutationError(
			"record cross-chain reorganization",
			scanErr,
			ErrConflict,
		)
	}
	result.IncidentID = "crosschain-incident:" +
		hex.EncodeToString(request.EvidenceHash[:])
	result.IncidentReasonCode = "POST_FINALITY_REORGANIZATION"
	result.IncidentSeverity = "CRITICAL"
	result.IncidentOwner = "cross-chain-security"
	result.IncidentStatus = "OPEN"
	result.IncidentOpenedAt = request.DetectedAt.UTC()
	if !reorganizationMatchesRequest(result, request) {
		return ReorganizationRecord{}, ErrConflict
	}
	return result, nil
}

func (repository *SQL) Reorganization(
	ctx context.Context,
	evidenceHash [32]byte,
) (ReorganizationRecord, error) {
	if repository == nil || repository.queryer == nil || ctx == nil ||
		evidenceHash == ([32]byte{}) {
		return ReorganizationRecord{}, ErrNotFound
	}
	result, err := scanReorganization(repository.queryer.QueryRowContext(
		ctx,
		loadReorganizationSQL,
		evidenceHash[:],
	), true)
	if errors.Is(err, sql.ErrNoRows) {
		return ReorganizationRecord{}, ErrNotFound
	}
	if err != nil {
		return ReorganizationRecord{}, fmt.Errorf(
			"load cross-chain reorganization: %w",
			err,
		)
	}
	return result, nil
}

func scanReorganization(
	row rowScanner,
	withIncident bool,
) (ReorganizationRecord, error) {
	var (
		result                ReorganizationRecord
		orphanedBlockHash     []byte
		replacementBlockHash  []byte
		detectedHeadHash      []byte
		affectedMessageIDsHex string
		orphanedProofIDsJSON  string
		orphanedCertIDsJSON   string
		evidenceHash          []byte
	)
	destinations := []any{
		&result.ReorganizationID,
		&result.RouteID,
		&result.ChainID,
		&orphanedBlockHash,
		&result.OrphanedBlockNumber,
		&result.OrphanedProofID,
		&result.OrphanedCertificateID,
		&orphanedProofIDsJSON,
		&orphanedCertIDsJSON,
		&replacementBlockHash,
		&result.ReplacementBlockNumber,
		&result.ReplacementObservationID,
		&detectedHeadHash,
		&result.DetectedHeadNumber,
		&result.DetectedHeadObservationID,
		&result.DepthClass,
		&affectedMessageIDsHex,
		&evidenceHash,
		&result.DetectedAt,
	}
	if withIncident {
		destinations = append(
			destinations,
			&result.IncidentID,
			&result.IncidentReasonCode,
			&result.IncidentSeverity,
			&result.IncidentOwner,
			&result.IncidentStatus,
			&result.IncidentOpenedAt,
		)
	}
	if err := row.Scan(destinations...); err != nil {
		return ReorganizationRecord{}, err
	}
	if len(orphanedBlockHash) != 32 || len(replacementBlockHash) != 32 ||
		len(detectedHeadHash) != 32 || len(evidenceHash) != 32 {
		return ReorganizationRecord{}, ErrConflict
	}
	copy(result.OrphanedBlockHash[:], orphanedBlockHash)
	copy(result.ReplacementBlockHash[:], replacementBlockHash)
	copy(result.DetectedHeadHash[:], detectedHeadHash)
	copy(result.EvidenceHash[:], evidenceHash)
	affected, err := parseAffectedMessageIDs(affectedMessageIDsHex)
	if err != nil {
		return ReorganizationRecord{}, ErrConflict
	}
	if err := json.Unmarshal(
		[]byte(orphanedProofIDsJSON),
		&result.OrphanedProofIDs,
	); err != nil {
		return ReorganizationRecord{}, ErrConflict
	}
	if err := json.Unmarshal(
		[]byte(orphanedCertIDsJSON),
		&result.OrphanedCertificateIDs,
	); err != nil {
		return ReorganizationRecord{}, ErrConflict
	}
	result.AffectedMessageIDs = affected
	result.DetectedAt = result.DetectedAt.UTC()
	if withIncident {
		result.IncidentOpenedAt = result.IncidentOpenedAt.UTC()
	}
	if !validReorganizationRecord(result, withIncident) {
		return ReorganizationRecord{}, ErrConflict
	}
	return result, nil
}

func validReorganizationRequest(request ReorganizationRequest) bool {
	if request.RouteID == "" || !canonicalUint256(request.ChainID, false) ||
		request.ReplacementObservationID == "" ||
		request.DetectedHeadObservationID == "" ||
		request.EvidenceHash == ([32]byte{}) ||
		request.DetectedAt.IsZero() ||
		len(request.AffectedMessageIDs) == 0 ||
		len(request.AffectedMessageIDs) > 256 ||
		len(request.OrphanedProofIDs) != len(request.AffectedMessageIDs) ||
		len(request.OrphanedCertificateIDs) !=
			len(request.AffectedMessageIDs) {
		return false
	}
	var previous [32]byte
	for index, messageID := range request.AffectedMessageIDs {
		if messageID == ([32]byte{}) ||
			request.OrphanedProofIDs[index] == "" ||
			request.OrphanedCertificateIDs[index] == "" ||
			(index > 0 && bytes.Compare(previous[:], messageID[:]) >= 0) {
			return false
		}
		previous = messageID
	}
	return true
}

func validReorganizationRecord(
	record ReorganizationRecord,
	withIncident bool,
) bool {
	if record.ReorganizationID == "" || record.RouteID == "" ||
		!canonicalUint256(record.ChainID, false) ||
		record.OrphanedBlockHash == ([32]byte{}) ||
		!canonicalUint256(record.OrphanedBlockNumber, false) ||
		record.OrphanedProofID == "" ||
		record.OrphanedCertificateID == "" ||
		len(record.OrphanedProofIDs) == 0 ||
		len(record.OrphanedCertificateIDs) == 0 ||
		record.OrphanedProofID != record.OrphanedProofIDs[0] ||
		record.OrphanedCertificateID != record.OrphanedCertificateIDs[0] ||
		record.ReplacementBlockHash == ([32]byte{}) ||
		!canonicalUint256(record.ReplacementBlockNumber, false) ||
		record.ReplacementObservationID == "" ||
		record.DetectedHeadHash == ([32]byte{}) ||
		!canonicalUint256(record.DetectedHeadNumber, false) ||
		record.DetectedHeadObservationID == "" ||
		record.DepthClass != "DEEP_FINALITY" ||
		record.EvidenceHash == ([32]byte{}) ||
		record.DetectedAt.IsZero() {
		return false
	}
	request := ReorganizationRequest{
		RouteID:                   record.RouteID,
		ChainID:                   record.ChainID,
		OrphanedProofIDs:          record.OrphanedProofIDs,
		OrphanedCertificateIDs:    record.OrphanedCertificateIDs,
		ReplacementObservationID:  record.ReplacementObservationID,
		DetectedHeadObservationID: record.DetectedHeadObservationID,
		AffectedMessageIDs:        record.AffectedMessageIDs,
		EvidenceHash:              record.EvidenceHash,
		DetectedAt:                record.DetectedAt,
	}
	if !validReorganizationRequest(request) {
		return false
	}
	if !withIncident {
		return true
	}
	return record.IncidentID != "" &&
		record.IncidentReasonCode == "POST_FINALITY_REORGANIZATION" &&
		record.IncidentSeverity == "CRITICAL" &&
		record.IncidentOwner == "cross-chain-security" &&
		record.IncidentStatus == "OPEN" &&
		record.IncidentOpenedAt.Equal(record.DetectedAt)
}

func reorganizationMatchesRequest(
	record ReorganizationRecord,
	request ReorganizationRequest,
) bool {
	return record.RouteID == request.RouteID &&
		record.ChainID == request.ChainID &&
		sameStrings(record.OrphanedProofIDs, request.OrphanedProofIDs) &&
		sameStrings(
			record.OrphanedCertificateIDs,
			request.OrphanedCertificateIDs,
		) &&
		record.ReplacementObservationID == request.ReplacementObservationID &&
		record.DetectedHeadObservationID ==
			request.DetectedHeadObservationID &&
		sameMessageIDs(record.AffectedMessageIDs, request.AffectedMessageIDs) &&
		record.EvidenceHash == request.EvidenceHash &&
		record.DetectedAt.Equal(request.DetectedAt)
}

func byteaArrayLiteral(values [][32]byte) string {
	items := make([]string, len(values))
	for index, value := range values {
		items[index] = `"\\x` + hex.EncodeToString(value[:]) + `"`
	}
	return "{" + strings.Join(items, ",") + "}"
}

func textArrayLiteral(values []string) string {
	items := make([]string, len(values))
	for index, value := range values {
		escaped := strings.ReplaceAll(value, `\`, `\\`)
		escaped = strings.ReplaceAll(escaped, `"`, `\"`)
		items[index] = `"` + escaped + `"`
	}
	return "{" + strings.Join(items, ",") + "}"
}

func parseAffectedMessageIDs(value string) ([][32]byte, error) {
	if value == "" {
		return nil, ErrConflict
	}
	parts := strings.Split(value, ",")
	result := make([][32]byte, len(parts))
	for index, part := range parts {
		decoded, err := hex.DecodeString(part)
		if err != nil || len(decoded) != 32 {
			return nil, ErrConflict
		}
		copy(result[index][:], decoded)
	}
	return result, nil
}

func sameMessageIDs(left, right [][32]byte) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func sameStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

const loadMessageSQL = `
SELECT
    message.message_id,
    message.serialized_envelope,
    message.state,
    message.state_version,
    transition.evidence_hash,
    message.updated_at,
    transition.occurred_at,
    transition.failure_class
FROM crosschain.messages AS message
JOIN LATERAL (
    SELECT evidence_hash, occurred_at, failure_class
    FROM crosschain.message_transitions
    WHERE message_id = message.message_id
      AND state_version = message.state_version
    LIMIT 1
) AS transition ON TRUE
WHERE message.message_id = $1`

func (repository *SQL) Message(messageID [32]byte) (MessageRecord, error) {
	snapshot, err := repository.messageSnapshot(messageID)
	if err != nil {
		return MessageRecord{}, err
	}
	return snapshot.record, nil
}

type storedMessageSnapshot struct {
	record       MessageRecord
	failureClass string
}

func (repository *SQL) messageSnapshot(
	messageID [32]byte,
) (storedMessageSnapshot, error) {
	if repository == nil || repository.queryer == nil ||
		messageID == ([32]byte{}) {
		return storedMessageSnapshot{}, ErrNotFound
	}
	var (
		rawMessageID []byte
		envelope     []byte
		state        string
		version      int64
		evidence     []byte
		updatedAt    time.Time
		occurredAt   time.Time
		failureClass sql.NullString
	)
	err := repository.queryer.QueryRowContext(
		context.Background(),
		loadMessageSQL,
		messageID[:],
	).Scan(
		&rawMessageID,
		&envelope,
		&state,
		&version,
		&evidence,
		&updatedAt,
		&occurredAt,
		&failureClass,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return storedMessageSnapshot{}, ErrNotFound
	}
	if err != nil {
		return storedMessageSnapshot{}, fmt.Errorf("load cross-chain message: %w", err)
	}
	record, err := materializeMessage(
		rawMessageID,
		envelope,
		state,
		version,
		evidence,
		updatedAt,
	)
	if err != nil || record.MessageID != messageID ||
		!occurredAt.Equal(updatedAt) {
		return storedMessageSnapshot{}, ErrInvalidSQLRepository
	}
	return storedMessageSnapshot{
		record:       record,
		failureClass: failureClass.String,
	}, nil
}

func scanMutationMessage(row rowScanner) (MessageRecord, error) {
	var (
		rawMessageID []byte
		envelope     []byte
		state        string
		version      int64
		updatedAt    time.Time
	)
	if err := row.Scan(
		&rawMessageID,
		&envelope,
		&state,
		&version,
		&updatedAt,
	); err != nil {
		return MessageRecord{}, err
	}
	return materializeMessage(
		rawMessageID,
		envelope,
		state,
		version,
		make([]byte, 32),
		updatedAt,
	)
}

func materializeMessage(
	rawMessageID []byte,
	envelope []byte,
	databaseState string,
	version int64,
	evidence []byte,
	updatedAt time.Time,
) (MessageRecord, error) {
	state, ok := stateFromDatabase(databaseState)
	if len(rawMessageID) != 32 || len(envelope) == 0 ||
		!ok || version <= 0 || len(evidence) != 32 || updatedAt.IsZero() {
		return MessageRecord{}, ErrInvalidSQLRepository
	}
	record := MessageRecord{
		MessageID: bytes32(rawMessageID),
		Envelope:  append([]byte(nil), envelope...),
		State:     state,
		Version:   uint64(version),
		Evidence:  bytes32(evidence),
		UpdatedAt: updatedAt.UTC(),
	}
	var decoded unifiedv1.CrossChainMessageEnvelope
	if proto.Unmarshal(record.Envelope, &decoded) != nil ||
		message.ValidateEnvelope(&decoded) != nil ||
		!bytes.Equal(decoded.GetMessageId(), record.MessageID[:]) {
		return MessageRecord{}, ErrInvalidSQLRepository
	}
	deterministic, err := message.DeterministicBytes(&decoded)
	if err != nil || !bytes.Equal(deterministic, record.Envelope) {
		return MessageRecord{}, ErrInvalidSQLRepository
	}
	return record, nil
}

func validateMessageCreation(
	record MessageRecord,
) (*unifiedv1.CrossChainMessageEnvelope, error) {
	if len(record.Envelope) == 0 ||
		record.MessageID == ([32]byte{}) ||
		record.State != unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED ||
		record.Version != 1 || record.UpdatedAt.IsZero() {
		return nil, ErrInvalidSQLRepository
	}
	var envelope unifiedv1.CrossChainMessageEnvelope
	if proto.Unmarshal(record.Envelope, &envelope) != nil ||
		message.ValidateEnvelope(&envelope) != nil ||
		!bytes.Equal(envelope.GetMessageId(), record.MessageID[:]) {
		return nil, ErrInvalidSQLRepository
	}
	deterministic, err := message.DeterministicBytes(&envelope)
	if err != nil || !bytes.Equal(deterministic, record.Envelope) ||
		record.UpdatedAt.Before(envelope.GetCreatedAt().AsTime()) {
		return nil, ErrInvalidSQLRepository
	}
	payloadHash := bytes32(envelope.GetPayloadHash())
	if record.Evidence != ([32]byte{}) && record.Evidence != payloadHash {
		return nil, ErrInvalidSQLRepository
	}
	return &envelope, nil
}

func validateCreatedResult(
	request MessageRecord,
	result MessageRecord,
) error {
	if result.MessageID != request.MessageID ||
		!bytes.Equal(result.Envelope, request.Envelope) ||
		result.State != unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED ||
		result.Version != 1 ||
		!result.UpdatedAt.Equal(request.UpdatedAt.UTC()) {
		return ErrConflict
	}
	return nil
}

const loadCreationTransitionSQL = `
SELECT evidence_hash, occurred_at
FROM crosschain.message_transitions
WHERE message_id = $1
  AND state_version = 1
  AND from_state = 'CREATED'
  AND to_state = 'CREATED'`

func (repository *SQL) resolveCreationReplay(
	request MessageRecord,
	envelope *unifiedv1.CrossChainMessageEnvelope,
	current MessageRecord,
) (MessageRecord, error) {
	payloadHash := bytes32(envelope.GetPayloadHash())
	if current.State ==
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED &&
		current.Version == 1 {
		current.Evidence = payloadHash
		if validateCreatedResult(request, current) != nil {
			return MessageRecord{}, ErrConflict
		}
		return current, nil
	}
	if current.MessageID != request.MessageID ||
		!bytes.Equal(current.Envelope, request.Envelope) ||
		current.Version <= 1 || current.UpdatedAt.Before(request.UpdatedAt) {
		return MessageRecord{}, ErrConflict
	}
	var (
		creationEvidence []byte
		createdAt        time.Time
	)
	err := repository.queryer.QueryRowContext(
		context.Background(),
		loadCreationTransitionSQL,
		request.MessageID[:],
	).Scan(&creationEvidence, &createdAt)
	if err != nil || len(creationEvidence) != 32 ||
		bytes32(creationEvidence) != payloadHash ||
		!createdAt.Equal(request.UpdatedAt.UTC()) {
		return MessageRecord{}, ErrConflict
	}
	latest, err := repository.messageSnapshot(request.MessageID)
	if err != nil ||
		latest.record.State != current.State ||
		latest.record.Version != current.Version ||
		!latest.record.UpdatedAt.Equal(current.UpdatedAt) ||
		!bytes.Equal(latest.record.Envelope, current.Envelope) {
		return MessageRecord{}, ErrConflict
	}
	return latest.record, nil
}

func exactTransitionReplay(
	current storedMessageSnapshot,
	expectedVersion uint64,
	next unifiedv1.CrossChainMessageState,
	failureClass string,
	evidence [32]byte,
	updatedAt time.Time,
) bool {
	return expectedVersion < math.MaxUint64 &&
		current.record.Version == expectedVersion+1 &&
		current.record.State == next &&
		current.record.Evidence == evidence &&
		current.failureClass == failureClass &&
		current.record.UpdatedAt.Equal(updatedAt.UTC())
}

func transitionFailureClass(retryable bool) string {
	if retryable {
		// The bool-only Repository contract cannot distinguish target from
		// transport retry. Persist the conservative transport class so the
		// database-owned retry gate remains explicit and replay-comparable.
		return "RETRYABLE_TRANSPORT"
	}
	return ""
}

func stateToDatabase(
	state unifiedv1.CrossChainMessageState,
) (string, bool) {
	const prefix = "CROSS_CHAIN_MESSAGE_STATE_"
	name, ok := unifiedv1.CrossChainMessageState_name[int32(state)]
	if !ok || name == prefix+"UNSPECIFIED" || !strings.HasPrefix(name, prefix) {
		return "", false
	}
	return strings.TrimPrefix(name, prefix), true
}

func stateFromDatabase(
	state string,
) (unifiedv1.CrossChainMessageState, bool) {
	key := "CROSS_CHAIN_MESSAGE_STATE_" + state
	value, ok := unifiedv1.CrossChainMessageState_value[key]
	if !ok || value == 0 {
		return unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_UNSPECIFIED, false
	}
	return unifiedv1.CrossChainMessageState(value), true
}

func bytes32(value []byte) [32]byte {
	var result [32]byte
	copy(result[:], value)
	return result
}

func classifyMutationError(
	operation string,
	err error,
	conflict error,
) error {
	if err == nil {
		return nil
	}
	message := strings.ToLower(err.Error())
	if strings.Contains(message, "conflict") ||
		strings.Contains(message, "duplicate key") ||
		strings.Contains(message, "unique constraint") ||
		strings.Contains(message, "cannot move backwards") {
		return fmt.Errorf("%s: %w", operation, conflict)
	}
	return fmt.Errorf("%s: %w", operation, err)
}

const registerChainVersionSQL = `
SELECT
    chain_id::text,
    version,
    coordinator,
    finality_verifier,
    configuration_hash,
    observer_authority_hash,
    activated_at_block::text,
    status
FROM crosschain.register_chain_version(
    $1::numeric, $2, $3, $4, $5, $6, $7::numeric, $8, $9
)`

const registerRouteVersionSQL = `
SELECT
    route_id,
    version,
    source_chain_id::text,
    source_chain_version,
    source_coordinator,
    source_component,
    destination_chain_id::text,
    destination_chain_version,
    destination_coordinator,
    destination_component,
    action_family,
    adapter_set_policy_hash,
    source_finality_policy_hash,
    destination_finality_policy_hash,
    source_signer_set_hash,
    source_signer_set_version,
    destination_signer_set_hash,
    destination_signer_set_version,
    route_policy_hash,
    activated_at_block::text,
    status
FROM crosschain.register_route_version(
    $1, $2, $3::numeric, $4, $5, $6, $7::numeric, $8, $9, $10,
    $11, $12, $13, $14, $15, $16, $17, $18, $19, $20::numeric, $21, $22
)`

// PutRoute provisions the exact configured chain and route versions through
// the migration-owned SECURITY DEFINER functions. It never falls back to
// direct table writes.
func (repository *SQL) PutRoute(route RouteVersion) error {
	if repository == nil || repository.queryer == nil {
		return ErrInvalidSQLRepository
	}
	key := routeKey(route.RouteID, route.Version)
	registration, exists := repository.provisioning[key]
	if !exists {
		return ErrInvalidSQLRepository
	}
	if !sameRoute(route, registration.Route) {
		return ErrImmutableRoute
	}
	if err := repository.registerChain(registration.SourceChain, route.ActivatedAt); err != nil {
		return err
	}
	if err := repository.registerChain(
		registration.DestinationChain,
		route.ActivatedAt,
	); err != nil {
		return err
	}
	var (
		routeID                   string
		version                   int64
		sourceChainID             string
		sourceChainVersion        int64
		sourceCoordinator         []byte
		sourceComponent           []byte
		destinationChainID        string
		destinationChainVersion   int64
		destinationCoordinator    []byte
		destinationComponent      []byte
		actionFamily              string
		adapterPolicy             []byte
		sourceFinalityPolicy      []byte
		destinationFinalityPolicy []byte
		sourceSignerSet           []byte
		sourceSignerSetVersion    int64
		destinationSignerSet      []byte
		destinationSignerVersion  int64
		routePolicy               []byte
		activatedAtBlock          string
		status                    string
	)
	err := repository.queryer.QueryRowContext(
		context.Background(),
		registerRouteVersionSQL,
		registration.Route.RouteID,
		int64(registration.Route.Version),
		registration.SourceChain.ChainID,
		int64(registration.SourceChain.Version),
		registration.SourceChain.Coordinator[:],
		registration.SourceComponent[:],
		registration.DestinationChain.ChainID,
		int64(registration.DestinationChain.Version),
		registration.DestinationChain.Coordinator[:],
		registration.DestinationComponent[:],
		registration.ActionFamily,
		registration.AdapterSetPolicyHash[:],
		registration.SourceFinalityPolicyHash[:],
		registration.DestinationFinalityPolicyHash[:],
		registration.SourceSignerSetHash[:],
		int64(registration.SourceSignerSetVersion),
		registration.DestinationSignerSetHash[:],
		int64(registration.DestinationSignerSetVersion),
		registration.Route.PolicyHash[:],
		registration.ActivatedAtBlock,
		"ACTIVE",
		registration.Route.ActivatedAt.UTC(),
	).Scan(
		&routeID,
		&version,
		&sourceChainID,
		&sourceChainVersion,
		&sourceCoordinator,
		&sourceComponent,
		&destinationChainID,
		&destinationChainVersion,
		&destinationCoordinator,
		&destinationComponent,
		&actionFamily,
		&adapterPolicy,
		&sourceFinalityPolicy,
		&destinationFinalityPolicy,
		&sourceSignerSet,
		&sourceSignerSetVersion,
		&destinationSignerSet,
		&destinationSignerVersion,
		&routePolicy,
		&activatedAtBlock,
		&status,
	)
	if err != nil {
		return classifyMutationError(
			"register cross-chain route version",
			err,
			ErrImmutableRoute,
		)
	}
	if routeID != registration.Route.RouteID ||
		version != int64(registration.Route.Version) ||
		sourceChainID != registration.SourceChain.ChainID ||
		sourceChainVersion != int64(registration.SourceChain.Version) ||
		!bytes.Equal(sourceCoordinator, registration.SourceChain.Coordinator[:]) ||
		!bytes.Equal(sourceComponent, registration.SourceComponent[:]) ||
		destinationChainID != registration.DestinationChain.ChainID ||
		destinationChainVersion != int64(registration.DestinationChain.Version) ||
		!bytes.Equal(
			destinationCoordinator,
			registration.DestinationChain.Coordinator[:],
		) ||
		!bytes.Equal(destinationComponent, registration.DestinationComponent[:]) ||
		actionFamily != registration.ActionFamily ||
		!bytes.Equal(adapterPolicy, registration.AdapterSetPolicyHash[:]) ||
		!bytes.Equal(sourceFinalityPolicy, registration.SourceFinalityPolicyHash[:]) ||
		!bytes.Equal(
			destinationFinalityPolicy,
			registration.DestinationFinalityPolicyHash[:],
		) ||
		!bytes.Equal(sourceSignerSet, registration.SourceSignerSetHash[:]) ||
		sourceSignerSetVersion != int64(registration.SourceSignerSetVersion) ||
		!bytes.Equal(
			destinationSignerSet,
			registration.DestinationSignerSetHash[:],
		) ||
		destinationSignerVersion !=
			int64(registration.DestinationSignerSetVersion) ||
		!bytes.Equal(routePolicy, registration.Route.PolicyHash[:]) ||
		activatedAtBlock != registration.ActivatedAtBlock ||
		status != "ACTIVE" {
		return ErrImmutableRoute
	}
	return nil
}

func (repository *SQL) registerChain(
	registration ChainRegistration,
	createdAt time.Time,
) error {
	var (
		chainID               string
		version               int64
		coordinator           []byte
		finalityVerifier      []byte
		configurationHash     []byte
		observerAuthorityHash []byte
		activatedAtBlock      string
		status                string
	)
	err := repository.queryer.QueryRowContext(
		context.Background(),
		registerChainVersionSQL,
		registration.ChainID,
		int64(registration.Version),
		registration.Coordinator[:],
		registration.FinalityVerifier[:],
		registration.ConfigurationHash[:],
		registration.ObserverAuthorityHash[:],
		registration.ActivatedAtBlock,
		"ACTIVE",
		createdAt.UTC(),
	).Scan(
		&chainID,
		&version,
		&coordinator,
		&finalityVerifier,
		&configurationHash,
		&observerAuthorityHash,
		&activatedAtBlock,
		&status,
	)
	if err != nil {
		return classifyMutationError(
			"register cross-chain chain version",
			err,
			ErrImmutableRoute,
		)
	}
	if chainID != registration.ChainID ||
		version != int64(registration.Version) ||
		!bytes.Equal(coordinator, registration.Coordinator[:]) ||
		!bytes.Equal(finalityVerifier, registration.FinalityVerifier[:]) ||
		!bytes.Equal(configurationHash, registration.ConfigurationHash[:]) ||
		!bytes.Equal(
			observerAuthorityHash,
			registration.ObserverAuthorityHash[:],
		) ||
		activatedAtBlock != registration.ActivatedAtBlock ||
		status != "ACTIVE" {
		return ErrImmutableRoute
	}
	return nil
}

const loadRouteVersionSQL = `
SELECT
    route_id,
    version,
    source_chain_id::text,
    source_chain_version,
    source_coordinator,
    source_component,
    destination_chain_id::text,
    destination_chain_version,
    destination_coordinator,
    destination_component,
    action_family,
    adapter_set_policy_hash,
    source_finality_policy_hash,
    destination_finality_policy_hash,
    source_signer_set_hash,
    source_signer_set_version,
    destination_signer_set_hash,
    destination_signer_set_version,
    route_policy_hash,
    activated_at_block::text,
    status
FROM crosschain.route_versions
WHERE route_id = $1 AND version = $2`

func (repository *SQL) Route(routeID string, version uint64) (RouteVersion, error) {
	if repository == nil || repository.queryer == nil ||
		routeID == "" || version == 0 || version > math.MaxInt64 {
		return RouteVersion{}, ErrNotFound
	}
	registration, configured := repository.provisioning[routeKey(routeID, version)]
	if !configured {
		return RouteVersion{}, ErrInvalidSQLRepository
	}
	var (
		storedRouteID             string
		storedVersion             int64
		sourceChainID             string
		sourceChainVersion        int64
		sourceCoordinator         []byte
		sourceComponent           []byte
		destinationChainID        string
		destinationChainVersion   int64
		destinationCoordinator    []byte
		destinationComponent      []byte
		actionFamily              string
		adapterPolicy             []byte
		sourceFinalityPolicy      []byte
		destinationFinalityPolicy []byte
		sourceSignerSet           []byte
		sourceSignerSetVersion    int64
		destinationSignerSet      []byte
		destinationSignerVersion  int64
		routePolicy               []byte
		activatedAtBlock          string
		status                    string
	)
	err := repository.queryer.QueryRowContext(
		context.Background(),
		loadRouteVersionSQL,
		routeID,
		int64(version),
	).Scan(
		&storedRouteID,
		&storedVersion,
		&sourceChainID,
		&sourceChainVersion,
		&sourceCoordinator,
		&sourceComponent,
		&destinationChainID,
		&destinationChainVersion,
		&destinationCoordinator,
		&destinationComponent,
		&actionFamily,
		&adapterPolicy,
		&sourceFinalityPolicy,
		&destinationFinalityPolicy,
		&sourceSignerSet,
		&sourceSignerSetVersion,
		&destinationSignerSet,
		&destinationSignerVersion,
		&routePolicy,
		&activatedAtBlock,
		&status,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return RouteVersion{}, ErrNotFound
	}
	if err != nil {
		return RouteVersion{}, fmt.Errorf("load cross-chain route version: %w", err)
	}
	if storedRouteID != registration.Route.RouteID ||
		storedVersion != int64(registration.Route.Version) ||
		sourceChainID != registration.SourceChain.ChainID ||
		sourceChainVersion != int64(registration.SourceChain.Version) ||
		!bytes.Equal(sourceCoordinator, registration.SourceChain.Coordinator[:]) ||
		!bytes.Equal(sourceComponent, registration.SourceComponent[:]) ||
		destinationChainID != registration.DestinationChain.ChainID ||
		destinationChainVersion != int64(registration.DestinationChain.Version) ||
		!bytes.Equal(
			destinationCoordinator,
			registration.DestinationChain.Coordinator[:],
		) ||
		!bytes.Equal(destinationComponent, registration.DestinationComponent[:]) ||
		actionFamily != registration.ActionFamily ||
		!bytes.Equal(adapterPolicy, registration.AdapterSetPolicyHash[:]) ||
		!bytes.Equal(sourceFinalityPolicy, registration.SourceFinalityPolicyHash[:]) ||
		!bytes.Equal(
			destinationFinalityPolicy,
			registration.DestinationFinalityPolicyHash[:],
		) ||
		!bytes.Equal(sourceSignerSet, registration.SourceSignerSetHash[:]) ||
		sourceSignerSetVersion != int64(registration.SourceSignerSetVersion) ||
		!bytes.Equal(
			destinationSignerSet,
			registration.DestinationSignerSetHash[:],
		) ||
		destinationSignerVersion !=
			int64(registration.DestinationSignerSetVersion) ||
		!bytes.Equal(routePolicy, registration.Route.PolicyHash[:]) ||
		activatedAtBlock != registration.ActivatedAtBlock ||
		status != "ACTIVE" {
		return RouteVersion{}, ErrImmutableRoute
	}
	return registration.Route, nil
}

func validRouteRegistration(registration RouteRegistration) bool {
	route := registration.Route
	if route.RouteID == "" || route.Version == 0 || route.Version > math.MaxInt64 ||
		route.PolicyHash == ([32]byte{}) ||
		route.SourceChain == "" || route.DestinationChain == "" ||
		route.SourceChain == route.DestinationChain ||
		route.ActivatedAt.IsZero() || route.DeprecatedAt != nil ||
		registration.SourceChain.ChainID != route.SourceChain ||
		registration.DestinationChain.ChainID != route.DestinationChain ||
		registration.SourceComponent == ([20]byte{}) ||
		registration.DestinationComponent == ([20]byte{}) ||
		registration.ActionFamily == "" ||
		registration.AdapterSetPolicyHash == ([32]byte{}) ||
		registration.SourceFinalityPolicyHash == ([32]byte{}) ||
		registration.DestinationFinalityPolicyHash == ([32]byte{}) ||
		registration.SourceSignerSetHash == ([32]byte{}) ||
		registration.SourceSignerSetVersion == 0 ||
		registration.SourceSignerSetVersion > math.MaxUint32 ||
		registration.DestinationSignerSetHash == ([32]byte{}) ||
		registration.DestinationSignerSetVersion == 0 ||
		registration.DestinationSignerSetVersion > math.MaxUint32 ||
		!canonicalUint256(registration.ActivatedAtBlock, true) {
		return false
	}
	return validChainRegistration(registration.SourceChain) &&
		validChainRegistration(registration.DestinationChain)
}

func validChainRegistration(registration ChainRegistration) bool {
	return canonicalUint256(registration.ChainID, false) &&
		registration.Version > 0 && registration.Version <= math.MaxInt64 &&
		registration.Coordinator != ([20]byte{}) &&
		registration.FinalityVerifier != ([20]byte{}) &&
		registration.ConfigurationHash != ([32]byte{}) &&
		registration.ObserverAuthorityHash != ([32]byte{}) &&
		canonicalUint256(registration.ActivatedAtBlock, true)
}

func canonicalUint256(value string, allowZero bool) bool {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.BitLen() > 256 || number.String() != value {
		return false
	}
	if allowZero {
		return number.Sign() >= 0
	}
	return number.Sign() > 0
}

func sameRouteRegistration(left, right RouteRegistration) bool {
	return sameRoute(left.Route, right.Route) &&
		left.SourceChain == right.SourceChain &&
		left.DestinationChain == right.DestinationChain &&
		left.SourceComponent == right.SourceComponent &&
		left.DestinationComponent == right.DestinationComponent &&
		left.ActionFamily == right.ActionFamily &&
		left.AdapterSetPolicyHash == right.AdapterSetPolicyHash &&
		left.SourceFinalityPolicyHash == right.SourceFinalityPolicyHash &&
		left.DestinationFinalityPolicyHash == right.DestinationFinalityPolicyHash &&
		left.SourceSignerSetHash == right.SourceSignerSetHash &&
		left.SourceSignerSetVersion == right.SourceSignerSetVersion &&
		left.DestinationSignerSetHash == right.DestinationSignerSetHash &&
		left.DestinationSignerSetVersion == right.DestinationSignerSetVersion &&
		left.ActivatedAtBlock == right.ActivatedAtBlock
}

func cloneRouteRegistration(source RouteRegistration) RouteRegistration {
	result := source
	if source.Route.DeprecatedAt != nil {
		deprecatedAt := *source.Route.DeprecatedAt
		result.Route.DeprecatedAt = &deprecatedAt
	}
	return result
}

const loadOutboxSQL = `
SELECT
    outbox_id,
    message_id,
    state_version,
    topic,
    partition_key,
    payload,
    payload_hash,
    status,
    attempt_count,
    publisher_id,
    lease_until,
    created_at,
    published_at,
    broker_offset
FROM crosschain.outbox
WHERE outbox_id = $1`

func (repository *SQL) outbox(
	ctx context.Context,
	outboxID string,
) (OutboxRecord, error) {
	result, err := scanOutbox(
		repository.queryer.QueryRowContext(ctx, loadOutboxSQL, outboxID),
	)
	if errors.Is(err, sql.ErrNoRows) {
		return OutboxRecord{}, ErrNotFound
	}
	if err != nil {
		return OutboxRecord{}, fmt.Errorf("load cross-chain outbox: %w", err)
	}
	return result, nil
}

const loadInboxSQL = `
SELECT
    consumer_id,
    message_id,
    topic,
    partition_key,
    broker_offset,
    payload_hash,
    consumed_at
FROM crosschain.inbox
WHERE consumer_id = $1
  AND topic = $2
  AND broker_offset = $3`

func (repository *SQL) inbox(
	ctx context.Context,
	consumerID string,
	topic string,
	partitionKey string,
	brokerOffset string,
) (InboxRecord, error) {
	result, err := scanInbox(repository.queryer.QueryRowContext(
		ctx,
		loadInboxSQL,
		consumerID,
		topic,
		brokerOffset,
	))
	if errors.Is(err, sql.ErrNoRows) {
		return InboxRecord{}, ErrNotFound
	}
	if err != nil {
		return InboxRecord{}, fmt.Errorf("load cross-chain inbox: %w", err)
	}
	return result, nil
}

func scanOutbox(row rowScanner) (OutboxRecord, error) {
	var (
		result       OutboxRecord
		messageID    []byte
		stateVersion int64
		payloadHash  []byte
		attemptCount int64
		publisherID  sql.NullString
		leaseUntil   sql.NullTime
		publishedAt  sql.NullTime
		brokerOffset sql.NullString
	)
	if err := row.Scan(
		&result.OutboxID,
		&messageID,
		&stateVersion,
		&result.Topic,
		&result.PartitionKey,
		&result.Payload,
		&payloadHash,
		&result.Status,
		&attemptCount,
		&publisherID,
		&leaseUntil,
		&result.CreatedAt,
		&publishedAt,
		&brokerOffset,
	); err != nil {
		return OutboxRecord{}, err
	}
	if len(messageID) != 32 || len(payloadHash) != 32 ||
		result.OutboxID == "" || stateVersion <= 0 ||
		attemptCount < 0 || attemptCount > math.MaxUint32 ||
		result.Topic == "" || result.PartitionKey == "" ||
		len(result.Payload) == 0 || result.CreatedAt.IsZero() ||
		sha256.Sum256(result.Payload) != bytes32(payloadHash) {
		return OutboxRecord{}, ErrConflict
	}
	copy(result.MessageID[:], messageID)
	copy(result.PayloadHash[:], payloadHash)
	result.StateVersion = uint64(stateVersion)
	result.AttemptCount = uint32(attemptCount)
	result.PublisherID = publisherID.String
	result.BrokerOffset = brokerOffset.String
	if leaseUntil.Valid {
		value := leaseUntil.Time.UTC()
		result.LeaseUntil = &value
	}
	if publishedAt.Valid {
		value := publishedAt.Time.UTC()
		result.PublishedAt = &value
	}
	result.CreatedAt = result.CreatedAt.UTC()
	if !validOutboxRecord(result) {
		return OutboxRecord{}, ErrConflict
	}
	result.Payload = append([]byte(nil), result.Payload...)
	return result, nil
}

func validOutboxRecord(record OutboxRecord) bool {
	switch record.Status {
	case "PENDING":
		return record.AttemptCount == 0 && record.PublisherID == "" &&
			record.LeaseUntil == nil && record.PublishedAt == nil &&
			record.BrokerOffset == ""
	case "CLAIMED":
		return record.AttemptCount > 0 && record.PublisherID != "" &&
			record.LeaseUntil != nil && record.PublishedAt == nil &&
			record.BrokerOffset == ""
	case "PUBLISHED":
		return record.AttemptCount > 0 && record.PublisherID != "" &&
			record.LeaseUntil == nil && record.PublishedAt != nil &&
			record.BrokerOffset != ""
	default:
		return false
	}
}

func exactOutboxPublication(
	record OutboxRecord,
	publisherID string,
	expectedAttemptCount uint32,
	brokerOffset string,
	publishedAt time.Time,
) bool {
	return record.Status == "PUBLISHED" &&
		record.PublisherID == publisherID &&
		record.AttemptCount == expectedAttemptCount &&
		record.BrokerOffset == brokerOffset &&
		record.PublishedAt != nil &&
		record.PublishedAt.Equal(publishedAt.UTC())
}

func scanInbox(row rowScanner) (InboxRecord, error) {
	var (
		result      InboxRecord
		messageID   []byte
		payloadHash []byte
	)
	if err := row.Scan(
		&result.ConsumerID,
		&messageID,
		&result.Topic,
		&result.PartitionKey,
		&result.BrokerOffset,
		&payloadHash,
		&result.ConsumedAt,
	); err != nil {
		return InboxRecord{}, err
	}
	if result.ConsumerID == "" || len(messageID) != 32 ||
		result.Topic == "" || result.PartitionKey == "" ||
		result.BrokerOffset == "" || len(payloadHash) != 32 ||
		result.ConsumedAt.IsZero() {
		return InboxRecord{}, ErrConflict
	}
	copy(result.MessageID[:], messageID)
	copy(result.PayloadHash[:], payloadHash)
	result.ConsumedAt = result.ConsumedAt.UTC()
	return result, nil
}

func exactInboxConsumption(
	record InboxRecord,
	messageID [32]byte,
	partitionKey string,
	payloadHash [32]byte,
	consumedAt time.Time,
) bool {
	return record.MessageID == messageID &&
		record.PartitionKey == partitionKey &&
		record.PayloadHash == payloadHash &&
		record.ConsumedAt.Equal(consumedAt.UTC())
}

const healthSQL = `
SELECT
    to_regclass('crosschain.messages') IS NOT NULL
    AND to_regclass('crosschain.message_transitions') IS NOT NULL
    AND to_regprocedure(
        'crosschain.record_message(bytea,integer,bytea,numeric,bytea,bytea,numeric,bytea,bytea,bytea,numeric,bytea,smallint,bytea,timestamp with time zone,timestamp with time zone,bytea,bytea,bytea,bytea,bytea,bytea,bytea,bytea,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.transition_message(bytea,bigint,text,text,text,bytea,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.register_chain_version(numeric,bigint,bytea,bytea,bytea,bytea,numeric,text,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.register_route_version(text,bigint,numeric,bigint,bytea,bytea,numeric,bigint,bytea,bytea,text,bytea,bytea,bytea,bytea,bigint,bytea,bigint,bytea,numeric,text,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.claim_outbox(text,timestamp with time zone,timestamp with time zone,integer)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.mark_outbox_published(text,text,integer,text,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.consume_inbox(text,bytea,text,text,text,bytea,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.record_provider_attempt(bytea,text,integer,bytea,bytea,text,bytea,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.record_source_proof(text,bytea,numeric,bytea,numeric,numeric,numeric,bytea,bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,timestamp with time zone,bytea,bytea)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.record_finality_certificate(text,bytea,text,bytea,bigint,bit varying,integer,bytea,timestamp with time zone,bytea,bytea[])'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.record_header_observation(text,numeric,bytea,numeric,bytea,bytea,bytea,bytea,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure(
        'crosschain.record_reorganization(text,numeric,text[],text[],text,text,bytea[],bytea,timestamp with time zone)'
    ) IS NOT NULL
    AND to_regprocedure('crosschain.load_source_proof(text)') IS NOT NULL
    AND to_regprocedure(
        'crosschain.load_finality_certificate(text)'
    ) IS NOT NULL`

func (repository *SQL) Health(ctx context.Context) error {
	if repository == nil || repository.queryer == nil || ctx == nil {
		return ErrInvalidSQLRepository
	}
	var healthy bool
	if err := repository.queryer.QueryRowContext(ctx, healthSQL).Scan(&healthy); err != nil {
		return fmt.Errorf("cross-chain repository health: %w", err)
	}
	if !healthy {
		return ErrInvalidSQLRepository
	}
	return nil
}
