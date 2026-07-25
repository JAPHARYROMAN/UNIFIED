package store

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"reflect"
	"strings"
	"testing"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/message"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type scriptedSQLStep struct {
	queryContains string
	argumentCount int
	check         func(*testing.T, []any)
	values        []any
	rowsValues    [][]any
	err           error
}

type scriptedSQLQueryer struct {
	t     *testing.T
	steps []scriptedSQLStep
}

func (queryer *scriptedSQLQueryer) QueryRowContext(
	_ context.Context,
	query string,
	args ...any,
) rowScanner {
	queryer.t.Helper()
	if len(queryer.steps) == 0 {
		queryer.t.Fatalf("unexpected SQL query: %s", query)
	}
	step := queryer.steps[0]
	queryer.steps = queryer.steps[1:]
	if !strings.Contains(query, step.queryContains) {
		queryer.t.Fatalf(
			"SQL query missing %q: %s",
			step.queryContains,
			query,
		)
	}
	if step.argumentCount >= 0 && len(args) != step.argumentCount {
		queryer.t.Fatalf(
			"SQL argument count: got %d want %d",
			len(args),
			step.argumentCount,
		)
	}
	if step.check != nil {
		step.check(queryer.t, args)
	}
	return scriptedSQLRow{values: step.values, err: step.err}
}

func (queryer *scriptedSQLQueryer) QueryContext(
	_ context.Context,
	query string,
	args ...any,
) (rowsScanner, error) {
	queryer.t.Helper()
	if len(queryer.steps) == 0 {
		queryer.t.Fatalf("unexpected SQL query: %s", query)
	}
	step := queryer.steps[0]
	queryer.steps = queryer.steps[1:]
	if !strings.Contains(query, step.queryContains) {
		queryer.t.Fatalf(
			"SQL query missing %q: %s",
			step.queryContains,
			query,
		)
	}
	if step.argumentCount >= 0 && len(args) != step.argumentCount {
		queryer.t.Fatalf(
			"SQL argument count: got %d want %d",
			len(args),
			step.argumentCount,
		)
	}
	if step.check != nil {
		step.check(queryer.t, args)
	}
	if step.err != nil {
		return nil, step.err
	}
	return &scriptedSQLRows{values: step.rowsValues, index: -1}, nil
}

func (queryer *scriptedSQLQueryer) assertDone() {
	queryer.t.Helper()
	if len(queryer.steps) != 0 {
		queryer.t.Fatalf("%d SQL steps were not consumed", len(queryer.steps))
	}
}

type scriptedSQLRow struct {
	values []any
	err    error
}

func (row scriptedSQLRow) Scan(destinations ...any) error {
	if row.err != nil {
		return row.err
	}
	if len(destinations) != len(row.values) {
		return fmt.Errorf(
			"scan destination count: got %d want %d",
			len(destinations),
			len(row.values),
		)
	}
	for index, destination := range destinations {
		value := row.values[index]
		switch target := destination.(type) {
		case *[]byte:
			source, ok := value.([]byte)
			if !ok {
				return fmt.Errorf("column %d is not []byte", index)
			}
			*target = append([]byte(nil), source...)
		case *string:
			source, ok := value.(string)
			if !ok {
				return fmt.Errorf("column %d is not string", index)
			}
			*target = source
		case *int64:
			source, ok := value.(int64)
			if !ok {
				return fmt.Errorf("column %d is not int64", index)
			}
			*target = source
		case *time.Time:
			source, ok := value.(time.Time)
			if !ok {
				return fmt.Errorf("column %d is not time.Time", index)
			}
			*target = source
		case *sql.NullString:
			if value == nil {
				*target = sql.NullString{}
				continue
			}
			source, ok := value.(string)
			if !ok {
				return fmt.Errorf("column %d is not nullable string", index)
			}
			*target = sql.NullString{String: source, Valid: true}
		case *sql.NullTime:
			if value == nil {
				*target = sql.NullTime{}
				continue
			}
			source, ok := value.(time.Time)
			if !ok {
				return fmt.Errorf("column %d is not nullable time", index)
			}
			*target = sql.NullTime{Time: source, Valid: true}
		case *bool:
			source, ok := value.(bool)
			if !ok {
				return fmt.Errorf("column %d is not bool", index)
			}
			*target = source
		default:
			return fmt.Errorf("unsupported scan destination %T", destination)
		}
	}
	return nil
}

type scriptedSQLRows struct {
	values [][]any
	index  int
	err    error
}

func (rows *scriptedSQLRows) Next() bool {
	if rows.index+1 >= len(rows.values) {
		return false
	}
	rows.index++
	return true
}

func (rows *scriptedSQLRows) Scan(destinations ...any) error {
	if rows.index < 0 || rows.index >= len(rows.values) {
		return errors.New("scripted rows are not positioned")
	}
	return (scriptedSQLRow{values: rows.values[rows.index]}).Scan(destinations...)
}

func (rows *scriptedSQLRows) Err() error {
	return rows.err
}

func (rows *scriptedSQLRows) Close() error {
	return nil
}

func sqlTestRecord(t *testing.T, nonce uint64) MessageRecord {
	t.Helper()
	hash := bytes.Repeat([]byte{0x11}, 32)
	zero := make([]byte, 32)
	createdAt := time.Unix(1_800_000_000, 0).UTC()
	envelope := &unifiedv1.CrossChainMessageEnvelope{
		SchemaVersion:          1,
		ProtocolId:             bytes.Repeat([]byte{0x01}, 32),
		SourceChainId:          "31337",
		SourceCoordinator:      bytes.Repeat([]byte{0x02}, 20),
		SourceComponent:        bytes.Repeat([]byte{0x03}, 20),
		DestinationChainId:     "31338",
		DestinationCoordinator: bytes.Repeat([]byte{0x04}, 20),
		DestinationComponent:   bytes.Repeat([]byte{0x05}, 20),
		LaneId:                 bytes.Repeat([]byte{0x06}, 32),
		SourceNonce:            nonce,
		AggregateId:            bytes.Repeat([]byte{0x07}, 32),
		ActionType:             unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1,
		TypedAction: &unifiedv1.CrossChainMessageEnvelope_CanonicalUftLock{
			CanonicalUftLock: &unifiedv1.CanonicalUftLockPayload{
				LockId:               bytes.Repeat([]byte{0x11}, 32),
				LoanId:               bytes.Repeat([]byte{0x22}, 32),
				CanonicalToken:       bytes.Repeat([]byte{0x11}, 20),
				HomeBridgeHub:        bytes.Repeat([]byte{0x22}, 20),
				WrappedToken:         bytes.Repeat([]byte{0x33}, 20),
				DestinationRecipient: bytes.Repeat([]byte{0x44}, 20),
				Amount:               "100",
			},
		},
		CreatedAt:                     timestamppb.New(createdAt),
		ExpiresAt:                     timestamppb.New(createdAt.Add(time.Hour)),
		RoutePolicyHash:               append([]byte(nil), hash...),
		AdapterSetPolicyHash:          append([]byte(nil), hash...),
		SourceFinalityPolicyHash:      append([]byte(nil), hash...),
		DestinationFinalityPolicyHash: append([]byte(nil), hash...),
		CorrelationId:                 append([]byte(nil), hash...),
		CausationMessageId:            append([]byte(nil), zero...),
		SupersededMessageId:           append([]byte(nil), zero...),
	}
	if err := message.BindTypedActionABI(envelope); err != nil {
		t.Fatal(err)
	}
	envelope, err := message.Seal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	serialized, err := message.DeterministicBytes(envelope)
	if err != nil {
		t.Fatal(err)
	}
	return MessageRecord{
		MessageID: bytes32(envelope.GetMessageId()),
		Envelope:  serialized,
		State:     unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED,
		Version:   1,
		Evidence:  bytes32(envelope.GetPayloadHash()),
		UpdatedAt: createdAt.Add(time.Minute),
	}
}

func mutationMessageValues(record MessageRecord) []any {
	state, _ := stateToDatabase(record.State)
	return []any{
		record.MessageID[:],
		record.Envelope,
		state,
		int64(record.Version),
		record.UpdatedAt,
	}
}

func loadedMessageValues(record MessageRecord, failureClass any) []any {
	state, _ := stateToDatabase(record.State)
	return []any{
		record.MessageID[:],
		record.Envelope,
		state,
		int64(record.Version),
		record.Evidence[:],
		record.UpdatedAt,
		record.UpdatedAt,
		failureClass,
	}
}

func providerAttemptValues(record ProviderAttemptRecord) []any {
	receipt := []byte{}
	if record.ReceiptHash != ([32]byte{}) {
		receipt = record.ReceiptHash[:]
	}
	return []any{
		record.MessageID[:],
		record.ProviderID,
		int64(record.AttemptNumber),
		record.EnvelopeHash[:],
		record.SourceProofHash[:],
		record.Status,
		receipt,
		record.AttemptedAt,
	}
}

func TestSQLProviderAttemptExactReplayAndLoad(t *testing.T) {
	record := ProviderAttemptRecord{
		MessageID:       repeated32(0x31),
		ProviderID:      "provider-b",
		AttemptNumber:   2,
		EnvelopeHash:    repeated32(0x32),
		SourceProofHash: repeated32(0x33),
		Status:          "DELIVERED",
		ReceiptHash:     repeated32(0x34),
		AttemptedAt:     time.Unix(1_800_200_000, 0).UTC(),
	}
	queryer := &scriptedSQLQueryer{t: t, steps: []scriptedSQLStep{
		{
			queryContains: "crosschain.record_provider_attempt",
			argumentCount: 8,
			values:        providerAttemptValues(record),
		},
		{
			queryContains: "crosschain.provider_attempts",
			argumentCount: 3,
			values:        providerAttemptValues(record),
		},
	}}
	repository, err := newSQL(queryer)
	if err != nil {
		t.Fatal(err)
	}
	persisted, err := repository.RecordProviderAttempt(t.Context(), record)
	if err != nil || !sameProviderAttempt(persisted, record) {
		t.Fatalf("record provider attempt: %#v %v", persisted, err)
	}
	loaded, err := repository.ProviderAttempt(
		t.Context(),
		record.MessageID,
		record.ProviderID,
		record.AttemptNumber,
	)
	if err != nil || !sameProviderAttempt(loaded, record) {
		t.Fatalf("load provider attempt: %#v %v", loaded, err)
	}
	queryer.assertDone()
}

func TestSQLProviderAttemptRejectsReceiptOnFailure(t *testing.T) {
	repository, err := newSQL(&scriptedSQLQueryer{t: t})
	if err != nil {
		t.Fatal(err)
	}
	record := ProviderAttemptRecord{
		MessageID:       repeated32(0x31),
		ProviderID:      "provider-a",
		AttemptNumber:   1,
		EnvelopeHash:    repeated32(0x32),
		SourceProofHash: repeated32(0x33),
		Status:          "FAILED",
		ReceiptHash:     repeated32(0x34),
		AttemptedAt:     time.Unix(1_800_200_000, 0).UTC(),
	}
	if _, err := repository.RecordProviderAttempt(t.Context(), record); !errors.Is(err, ErrConflict) {
		t.Fatalf("failure receipt accepted: %v", err)
	}
}

func outboxValues(record OutboxRecord) []any {
	var leaseUntil any
	if record.LeaseUntil != nil {
		leaseUntil = *record.LeaseUntil
	}
	var publishedAt any
	if record.PublishedAt != nil {
		publishedAt = *record.PublishedAt
	}
	var publisherID any
	if record.PublisherID != "" {
		publisherID = record.PublisherID
	}
	var brokerOffset any
	if record.BrokerOffset != "" {
		brokerOffset = record.BrokerOffset
	}
	return []any{
		record.OutboxID,
		record.MessageID[:],
		int64(record.StateVersion),
		record.Topic,
		record.PartitionKey,
		record.Payload,
		record.PayloadHash[:],
		record.Status,
		int64(record.AttemptCount),
		publisherID,
		leaseUntil,
		record.CreatedAt,
		publishedAt,
		brokerOffset,
	}
}

func inboxValues(record InboxRecord) []any {
	return []any{
		record.ConsumerID,
		record.MessageID[:],
		record.Topic,
		record.PartitionKey,
		record.BrokerOffset,
		record.PayloadHash[:],
		record.ConsumedAt,
	}
}

func sourceProofValues(record SourceProofRecord) []any {
	return []any{
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
		record.ObservedAt,
	}
}

func sqlTestSourceProof() SourceProofRecord {
	return SourceProofRecord{
		ProofID:                        "proof-observer-v1",
		MessageID:                      repeated32(0x81),
		ChainID:                        "31337",
		TransactionHash:                repeated32(0x82),
		TransactionIndex:               "0",
		LogIndex:                       "7",
		BlockNumber:                    "100",
		BlockHash:                      repeated32(0x83),
		ReceiptsRoot:                   repeated32(0x84),
		InclusionProofHash:             repeated32(0x85),
		EventHash:                      repeated32(0x86),
		FinalityHeadNumber:             "112",
		FinalityHeadHash:               repeated32(0x87),
		ConfirmationDepth:              "12",
		FinalityPolicyHash:             repeated32(0x88),
		ObserverAuthorityHash:          repeated32(0x89),
		ObserverSignedHeaderCommitment: repeated32(0x8a),
		ObserverSignature:              []byte{1, 2, 3},
		ProofHash:                      repeated32(0x8b),
		ObservedAt:                     time.Unix(1_800_500_000, 0).UTC(),
	}
}

func finalityCertificateValues(record FinalityCertificateRecord) []any {
	return []any{
		record.CertificateID,
		record.MessageID[:],
		record.ProofID,
		record.SignerSetHash[:],
		int64(record.SignerSetVersion),
		record.SignerBitmap,
		int64(record.SignatureCount),
		record.CertificateHash[:],
		record.CertifiedAt,
	}
}

func sqlTestOutbox(
	messageID [32]byte,
	stateVersion uint64,
	status string,
) OutboxRecord {
	payload := []byte(fmt.Sprintf(
		`{"message_id":"%x","state_version":%d}`,
		messageID,
		stateVersion,
	))
	createdAt := time.Unix(1_800_200_000, int64(stateVersion)).UTC()
	return OutboxRecord{
		OutboxID:     fmt.Sprintf("crosschain.message-state.v1:%x:%d", messageID, stateVersion),
		MessageID:    messageID,
		StateVersion: stateVersion,
		Topic:        "unified.crosschain.message-state.v1",
		PartitionKey: fmt.Sprintf("%x", messageID),
		Payload:      payload,
		PayloadHash:  sha256.Sum256(payload),
		Status:       status,
		CreatedAt:    createdAt,
	}
}

func headerObservationValues(record HeaderObservationRecord) []any {
	return []any{
		record.ObservationID,
		record.ChainID,
		record.BlockHash[:],
		record.BlockNumber,
		record.HeaderAuthorityHash[:],
		record.ObserverSignedHeaderCommitment[:],
		append([]byte(nil), record.ObserverSignature...),
		record.FinalityPolicyHash[:],
		record.ObservedAt,
	}
}

func reorganizationValues(
	record ReorganizationRecord,
	withIncident bool,
) []any {
	proofIDsJSON, _ := json.Marshal(record.OrphanedProofIDs)
	certificateIDsJSON, _ := json.Marshal(record.OrphanedCertificateIDs)
	affected := make([]string, len(record.AffectedMessageIDs))
	for index, messageID := range record.AffectedMessageIDs {
		affected[index] = fmt.Sprintf("%x", messageID)
	}
	values := []any{
		record.ReorganizationID,
		record.RouteID,
		record.ChainID,
		record.OrphanedBlockHash[:],
		record.OrphanedBlockNumber,
		record.OrphanedProofID,
		record.OrphanedCertificateID,
		string(proofIDsJSON),
		string(certificateIDsJSON),
		record.ReplacementBlockHash[:],
		record.ReplacementBlockNumber,
		record.ReplacementObservationID,
		record.DetectedHeadHash[:],
		record.DetectedHeadNumber,
		record.DetectedHeadObservationID,
		record.DepthClass,
		strings.Join(affected, ","),
		record.EvidenceHash[:],
		record.DetectedAt,
	}
	if withIncident {
		values = append(
			values,
			record.IncidentID,
			record.IncidentReasonCode,
			record.IncidentSeverity,
			record.IncidentOwner,
			record.IncidentStatus,
			record.IncidentOpenedAt,
		)
	}
	return values
}

func sqlTestRouteRegistration() RouteRegistration {
	activatedAt := time.Unix(1_800_100_000, 0).UTC()
	return RouteRegistration{
		Route: RouteVersion{
			RouteID:          "route-sql",
			Version:          1,
			PolicyHash:       repeated32(0x11),
			SourceChain:      "31337",
			DestinationChain: "31338",
			ActivatedAt:      activatedAt,
		},
		SourceChain: ChainRegistration{
			ChainID:               "31337",
			Version:               1,
			Coordinator:           repeated20(0x02),
			FinalityVerifier:      [20]byte{0x12},
			ConfigurationHash:     [32]byte{0x13},
			ObserverAuthorityHash: [32]byte{0x14},
			ActivatedAtBlock:      "100",
		},
		DestinationChain: ChainRegistration{
			ChainID:               "31338",
			Version:               1,
			Coordinator:           repeated20(0x04),
			FinalityVerifier:      [20]byte{0x22},
			ConfigurationHash:     [32]byte{0x23},
			ObserverAuthorityHash: [32]byte{0x24},
			ActivatedAtBlock:      "200",
		},
		SourceComponent:               repeated20(0x03),
		DestinationComponent:          repeated20(0x05),
		ActionFamily:                  "LOAN_LIFECYCLE_V1",
		AdapterSetPolicyHash:          repeated32(0x11),
		SourceFinalityPolicyHash:      repeated32(0x11),
		DestinationFinalityPolicyHash: repeated32(0x11),
		SourceSignerSetHash:           repeated32(0x31),
		SourceSignerSetVersion:        1,
		DestinationSignerSetHash:      repeated32(0x32),
		DestinationSignerSetVersion:   1,
		ActivatedAtBlock:              "300",
	}
}

func repeated20(value byte) [20]byte {
	var result [20]byte
	for index := range result {
		result[index] = value
	}
	return result
}

func repeated32(value byte) [32]byte {
	var result [32]byte
	for index := range result {
		result[index] = value
	}
	return result
}

func chainRegistrationValues(registration ChainRegistration) []any {
	return []any{
		registration.ChainID,
		int64(registration.Version),
		registration.Coordinator[:],
		registration.FinalityVerifier[:],
		registration.ConfigurationHash[:],
		registration.ObserverAuthorityHash[:],
		registration.ActivatedAtBlock,
		"ACTIVE",
	}
}

func routeRegistrationValues(registration RouteRegistration) []any {
	return []any{
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
	}
}

func matchingEnvelopeRouteStep() scriptedSQLStep {
	return scriptedSQLStep{
		queryContains: "FROM crosschain.route_versions",
		argumentCount: 10,
		values:        []any{true},
	}
}

func TestSQLCreateMessageUsesCallableAndPreservesFullNonce(t *testing.T) {
	record := sqlTestRecord(t, math.MaxUint64)
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			matchingEnvelopeRouteStep(),
			{
				queryContains: "crosschain.record_message",
				argumentCount: 25,
				check: func(t *testing.T, args []any) {
					t.Helper()
					if args[10] != "18446744073709551615" {
						t.Fatalf("source nonce was narrowed: %#v", args[10])
					}
				},
				values: mutationMessageValues(record),
			},
		},
	}
	repository, err := newSQL(queryer)
	if err != nil {
		t.Fatal(err)
	}
	created, err := repository.CreateMessage(record)
	if err != nil {
		t.Fatal(err)
	}
	if created.MessageID != record.MessageID ||
		!bytes.Equal(created.Envelope, record.Envelope) ||
		created.Evidence != record.Evidence {
		t.Fatalf("created message mismatch: %#v", created)
	}
	queryer.assertDone()
}

func TestSQLCreateMessageRecoversResponseLossAndRejectsConflict(t *testing.T) {
	record := sqlTestRecord(t, 1)
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			matchingEnvelopeRouteStep(),
			{
				queryContains: "crosschain.record_message",
				argumentCount: 25,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(record, nil),
			},
		},
	}
	repository, _ := newSQL(queryer)
	recovered, err := repository.CreateMessage(record)
	if err != nil || recovered.MessageID != record.MessageID {
		t.Fatalf("response-loss recovery failed: %#v %v", recovered, err)
	}
	queryer.assertDone()

	conflicting := record
	conflicting.UpdatedAt = record.UpdatedAt.Add(time.Second)
	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			matchingEnvelopeRouteStep(),
			{
				queryContains: "crosschain.record_message",
				argumentCount: 25,
				err:           errors.New("message identity conflict"),
			},
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(record, nil),
			},
		},
	}
	repository, _ = newSQL(queryer)
	if _, err := repository.CreateMessage(conflicting); !errors.Is(err, ErrConflict) {
		t.Fatalf("non-exact create replay accepted: %v", err)
	}
	queryer.assertDone()
}

func TestSQLCreateMessageRejectsEnvelopeOutsidePinnedRoute(t *testing.T) {
	record := sqlTestRecord(t, 5)
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{{
			queryContains: "FROM crosschain.route_versions",
			argumentCount: 10,
			values:        []any{false},
		}},
	}
	repository, _ := newSQL(queryer)
	if _, err := repository.CreateMessage(record); !errors.Is(err, ErrConflict) {
		t.Fatalf("unbound route envelope accepted: %v", err)
	}
	queryer.assertDone()
}

func TestSQLCreateMessageExactReplayReturnsProgressedDurableState(t *testing.T) {
	record := sqlTestRecord(t, 6)
	progressed := record
	progressed.State = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING
	progressed.Version = 2
	progressed.Evidence = [32]byte{0x66}
	progressed.UpdatedAt = record.UpdatedAt.Add(time.Minute)
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			matchingEnvelopeRouteStep(),
			{
				queryContains: "crosschain.record_message",
				argumentCount: 25,
				values:        mutationMessageValues(progressed),
			},
			{
				queryContains: "state_version = 1",
				argumentCount: 1,
				values: []any{
					record.Evidence[:],
					record.UpdatedAt,
				},
			},
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(progressed, nil),
			},
		},
	}
	repository, _ := newSQL(queryer)
	replayed, err := repository.CreateMessage(record)
	if err != nil || !reflect.DeepEqual(replayed, progressed) {
		t.Fatalf("progressed exact create replay failed: %#v %v", replayed, err)
	}
	queryer.assertDone()
}

func TestSQLCASRecoversExactResponseLossAndRejectsDivergence(t *testing.T) {
	created := sqlTestRecord(t, 2)
	evidence := [32]byte{0x92}
	transitioned := created
	transitioned.State = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING
	transitioned.Version = 2
	transitioned.Evidence = evidence
	transitioned.UpdatedAt = created.UpdatedAt.Add(time.Minute)
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(created, nil),
			},
			{
				queryContains: "crosschain.transition_message",
				argumentCount: 7,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(transitioned, nil),
			},
		},
	}
	repository, _ := newSQL(queryer)
	result, err := repository.CompareAndSet(
		created.MessageID,
		1,
		transitioned.State,
		false,
		evidence,
		transitioned.UpdatedAt,
	)
	if err != nil || !reflect.DeepEqual(result, transitioned) {
		t.Fatalf("exact CAS response loss was not recovered: %#v %v", result, err)
	}
	queryer.assertDone()

	divergent := transitioned
	divergent.Evidence = [32]byte{0x93}
	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(created, nil),
			},
			{
				queryContains: "crosschain.transition_message",
				argumentCount: 7,
				err:           errors.New("message compare-and-set conflict"),
			},
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(divergent, nil),
			},
		},
	}
	repository, _ = newSQL(queryer)
	if _, err := repository.CompareAndSet(
		created.MessageID,
		1,
		transitioned.State,
		false,
		evidence,
		transitioned.UpdatedAt,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("divergent CAS replay accepted: %v", err)
	}
	queryer.assertDone()
}

func TestSQLRepositoryIsStatelessAcrossRestartAndUsesNoDirectWrites(t *testing.T) {
	record := sqlTestRecord(t, 3)
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "FROM crosschain.messages",
				argumentCount: 1,
				values:        loadedMessageValues(record, nil),
			},
			{
				queryContains: "to_regclass",
				argumentCount: 0,
				values:        []any{true},
			},
		},
	}
	restarted, _ := newSQL(queryer)
	rehydrated, err := restarted.Message(record.MessageID)
	if err != nil || !reflect.DeepEqual(rehydrated, record) {
		t.Fatalf("restart rehydration failed: %#v %v", rehydrated, err)
	}
	if err := restarted.Health(context.Background()); err != nil {
		t.Fatalf("health failed: %v", err)
	}
	for name, query := range map[string]string{
		"record":         recordMessageSQL,
		"transition":     transitionMessageSQL,
		"register chain": registerChainVersionSQL,
		"register route": registerRouteVersionSQL,
	} {
		upper := strings.ToUpper(query)
		if strings.Contains(upper, "INSERT ") ||
			strings.Contains(upper, "UPDATE ") ||
			strings.Contains(upper, "DELETE ") {
			t.Fatalf("%s bypasses callable authority: %s", name, query)
		}
	}
	queryer.assertDone()
}

func TestSQLRouteProvisioningAndRestartReadUseOnlyReviewedCallables(t *testing.T) {
	registration := sqlTestRouteRegistration()
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.register_chain_version",
				argumentCount: 9,
				values:        chainRegistrationValues(registration.SourceChain),
			},
			{
				queryContains: "crosschain.register_chain_version",
				argumentCount: 9,
				values:        chainRegistrationValues(registration.DestinationChain),
			},
			{
				queryContains: "crosschain.register_route_version",
				argumentCount: 22,
				values:        routeRegistrationValues(registration),
			},
			{
				queryContains: "FROM crosschain.route_versions",
				argumentCount: 2,
				values:        routeRegistrationValues(registration),
			},
		},
	}
	repository, err := newSQLWithProvisioning(
		queryer,
		[]RouteRegistration{registration},
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.PutRoute(registration.Route); err != nil {
		t.Fatalf("provision route: %v", err)
	}
	restarted, err := newSQLWithProvisioning(
		queryer,
		[]RouteRegistration{registration},
	)
	if err != nil {
		t.Fatal(err)
	}
	route, err := restarted.Route(
		registration.Route.RouteID,
		registration.Route.Version,
	)
	if err != nil || !sameRoute(route, registration.Route) {
		t.Fatalf("route restart read mismatch: %#v %v", route, err)
	}
	queryer.assertDone()
}

func TestSQLRouteProvisioningRejectsUnconfiguredOrChangedRoute(t *testing.T) {
	registration := sqlTestRouteRegistration()
	queryer := &scriptedSQLQueryer{t: t}
	repository, err := newSQLWithProvisioning(
		queryer,
		[]RouteRegistration{registration},
	)
	if err != nil {
		t.Fatal(err)
	}
	changed := registration.Route
	changed.PolicyHash[0] ^= 0xff
	if err := repository.PutRoute(changed); !errors.Is(err, ErrImmutableRoute) {
		t.Fatalf("changed configured route accepted: %v", err)
	}
	if err := repository.PutRoute(RouteVersion{
		RouteID:          "route-unconfigured",
		Version:          1,
		PolicyHash:       [32]byte{1},
		SourceChain:      "1",
		DestinationChain: "2",
		ActivatedAt:      time.Now().UTC(),
	}); !errors.Is(err, ErrInvalidSQLRepository) {
		t.Fatalf("unconfigured route accepted: %v", err)
	}
	queryer.assertDone()
}

func TestSQLRejectsSignerSetVersionsWiderThanCanonicalUint32(t *testing.T) {
	registration := sqlTestRouteRegistration()
	registration.SourceSignerSetVersion = math.MaxUint32 + 1
	if _, err := newSQLWithProvisioning(
		&scriptedSQLQueryer{t: t},
		[]RouteRegistration{registration},
	); !errors.Is(err, ErrInvalidSQLRepository) {
		t.Fatalf("wide source signer-set version accepted: %v", err)
	}
	registration = sqlTestRouteRegistration()
	registration.DestinationSignerSetVersion = math.MaxUint32 + 1
	if _, err := newSQLWithProvisioning(
		&scriptedSQLQueryer{t: t},
		[]RouteRegistration{registration},
	); !errors.Is(err, ErrInvalidSQLRepository) {
		t.Fatalf("wide destination signer-set version accepted: %v", err)
	}
}

func TestSQLCASRejectsInvalidTransitionBeforeMutation(t *testing.T) {
	record := sqlTestRecord(t, 4)
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{{
			queryContains: "FROM crosschain.messages",
			argumentCount: 1,
			values:        loadedMessageValues(record, nil),
		}},
	}
	repository, _ := newSQL(queryer)
	if _, err := repository.CompareAndSet(
		record.MessageID,
		1,
		unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXECUTED,
		false,
		[32]byte{1},
		record.UpdatedAt,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("invalid transition accepted: %v", err)
	}
	queryer.assertDone()
}

func TestSQLClaimOutboxReturnsDeterministicLeaseBatch(t *testing.T) {
	messageID := repeated32(0x91)
	claimedAt := time.Unix(1_800_300_000, 0).UTC()
	leaseUntil := claimedAt.Add(time.Minute)
	first := sqlTestOutbox(messageID, 1, "CLAIMED")
	first.AttemptCount = 1
	first.PublisherID = "publisher-a"
	first.LeaseUntil = &leaseUntil
	second := sqlTestOutbox(messageID, 2, "CLAIMED")
	second.AttemptCount = 2
	second.PublisherID = "publisher-a"
	second.LeaseUntil = &leaseUntil

	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{{
			queryContains: "crosschain.claim_outbox",
			argumentCount: 4,
			check: func(t *testing.T, args []any) {
				t.Helper()
				if args[0] != "publisher-a" ||
					!args[1].(time.Time).Equal(leaseUntil) ||
					!args[2].(time.Time).Equal(claimedAt) ||
					args[3] != 2 {
					t.Fatalf("unexpected claim arguments: %#v", args)
				}
			},
			rowsValues: [][]any{outboxValues(first), outboxValues(second)},
		}},
	}
	repository, _ := newSQL(queryer)
	claimed, err := repository.ClaimOutbox(
		t.Context(),
		"publisher-a",
		leaseUntil,
		claimedAt,
		2,
	)
	if err != nil || !reflect.DeepEqual(claimed, []OutboxRecord{first, second}) {
		t.Fatalf("claimed outbox mismatch: %#v %v", claimed, err)
	}
	queryer.assertDone()
}

func TestSQLMarkOutboxPublishedRecoversLostResponseAndRejectsConflict(
	t *testing.T,
) {
	record := sqlTestOutbox(repeated32(0x92), 1, "PUBLISHED")
	record.AttemptCount = 1
	record.PublisherID = "publisher-a"
	record.BrokerOffset = "partition-0:17"
	publishedAt := record.CreatedAt.Add(time.Minute)
	record.PublishedAt = &publishedAt

	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.mark_outbox_published",
				argumentCount: 5,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "FROM crosschain.outbox",
				argumentCount: 1,
				values:        outboxValues(record),
			},
		},
	}
	repository, _ := newSQL(queryer)
	replayed, err := repository.MarkOutboxPublished(
		t.Context(),
		record.OutboxID,
		record.PublisherID,
		record.AttemptCount,
		record.BrokerOffset,
		publishedAt,
	)
	if err != nil || !reflect.DeepEqual(replayed, record) {
		t.Fatalf("lost publication response was not recovered: %#v %v", replayed, err)
	}
	queryer.assertDone()

	conflicting := record
	conflicting.BrokerOffset = "partition-0:18"
	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.mark_outbox_published",
				argumentCount: 5,
				err:           errors.New("conflicting outbox publication replay"),
			},
			{
				queryContains: "FROM crosschain.outbox",
				argumentCount: 1,
				values:        outboxValues(record),
			},
		},
	}
	repository, _ = newSQL(queryer)
	if _, err := repository.MarkOutboxPublished(
		t.Context(),
		record.OutboxID,
		record.PublisherID,
		record.AttemptCount,
		conflicting.BrokerOffset,
		publishedAt,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("conflicting publication replay accepted: %v", err)
	}
	queryer.assertDone()
}

func TestSQLConsumeInboxRecoversLostResponseAndRejectsPayloadConflict(
	t *testing.T,
) {
	consumed := InboxRecord{
		ConsumerID:   "consumer-a",
		MessageID:    repeated32(0x93),
		Topic:        "unified.crosschain.message-state.v1",
		PartitionKey: strings.Repeat("93", 32),
		BrokerOffset: "partition-1:9",
		PayloadHash:  repeated32(0x94),
		ConsumedAt:   time.Unix(1_800_400_000, 0).UTC(),
	}
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.consume_inbox",
				argumentCount: 7,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "FROM crosschain.inbox",
				argumentCount: 3,
				values:        inboxValues(consumed),
			},
		},
	}
	repository, _ := newSQL(queryer)
	replayed, err := repository.ConsumeInbox(
		t.Context(),
		consumed.ConsumerID,
		consumed.MessageID,
		consumed.Topic,
		consumed.PartitionKey,
		consumed.BrokerOffset,
		consumed.PayloadHash,
		consumed.ConsumedAt,
	)
	if err != nil || replayed != consumed {
		t.Fatalf("lost inbox response was not recovered: %#v %v", replayed, err)
	}
	queryer.assertDone()

	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.consume_inbox",
				argumentCount: 7,
				err:           errors.New("conflicting inbox consumption replay"),
			},
			{
				queryContains: "FROM crosschain.inbox",
				argumentCount: 3,
				values:        inboxValues(consumed),
			},
		},
	}
	repository, _ = newSQL(queryer)
	if _, err := repository.ConsumeInbox(
		t.Context(),
		consumed.ConsumerID,
		consumed.MessageID,
		consumed.Topic,
		consumed.PartitionKey,
		consumed.BrokerOffset,
		repeated32(0xff),
		consumed.ConsumedAt,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("conflicting inbox payload accepted: %v", err)
	}
	queryer.assertDone()

	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.consume_inbox",
				argumentCount: 7,
				err:           errors.New("conflicting inbox consumption replay"),
			},
			{
				queryContains: "FROM crosschain.inbox",
				argumentCount: 3,
				values:        inboxValues(consumed),
			},
		},
	}
	repository, _ = newSQL(queryer)
	if _, err := repository.ConsumeInbox(
		t.Context(),
		consumed.ConsumerID,
		consumed.MessageID,
		consumed.Topic,
		"changed-partition-key",
		consumed.BrokerOffset,
		consumed.PayloadHash,
		consumed.ConsumedAt,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("changed inbox partition key accepted: %v", err)
	}
	queryer.assertDone()
}

func TestSQLObserverEvidenceRecoversLostResponsesAndRejectsConflicts(
	t *testing.T,
) {
	proof := sqlTestSourceProof()
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.record_source_proof",
				argumentCount: 20,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "crosschain.load_source_proof",
				argumentCount: 1,
				values:        sourceProofValues(proof),
			},
		},
	}
	repository, _ := newSQL(queryer)
	replayedProof, err := repository.RecordSourceProof(t.Context(), proof)
	if err != nil || !sameSourceProof(replayedProof, proof) {
		t.Fatalf("lost proof response was not recovered: %#v %v", replayedProof, err)
	}
	queryer.assertDone()

	certificate := FinalityCertificateRecord{
		CertificateID:    "certificate-observer-v1",
		MessageID:        proof.MessageID,
		ProofID:          proof.ProofID,
		SignerSetHash:    repeated32(0x91),
		SignerSetVersion: 1,
		SignerBitmap:     "110",
		SignatureCount:   2,
		CertificateHash:  repeated32(0x92),
		CertifiedAt:      proof.ObservedAt,
	}
	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.record_finality_certificate",
				argumentCount: 9,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "crosschain.load_finality_certificate",
				argumentCount: 1,
				values:        finalityCertificateValues(certificate),
			},
		},
	}
	repository, _ = newSQL(queryer)
	replayedCertificate, err := repository.RecordFinalityCertificate(
		t.Context(),
		certificate,
	)
	if err != nil ||
		!sameFinalityCertificate(replayedCertificate, certificate) {
		t.Fatalf(
			"lost certificate response was not recovered: %#v %v",
			replayedCertificate,
			err,
		)
	}
	queryer.assertDone()

	invalid := certificate
	invalid.SignatureCount = 3
	if _, err := repository.RecordFinalityCertificate(
		t.Context(),
		invalid,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("false certificate bitmap count accepted: %v", err)
	}
	invalid = certificate
	invalid.SignerSetVersion = math.MaxUint32 + 1
	if _, err := repository.RecordFinalityCertificate(
		t.Context(),
		invalid,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("wide finality signer-set version accepted: %v", err)
	}
}

func TestSQLReorganizationAuthorityRecoversLostResponsesAndRehydrates(
	t *testing.T,
) {
	observedAt := time.Unix(1_800_600_000, 0).UTC()
	header := HeaderObservationRecord{
		ObservationID:                  "header-observation-replacement-v1",
		ChainID:                        "31337",
		BlockHash:                      repeated32(0xa1),
		BlockNumber:                    "101",
		HeaderAuthorityHash:            repeated32(0xa2),
		ObserverSignedHeaderCommitment: repeated32(0xa3),
		ObserverSignature:              []byte{0xa4, 0xa5},
		FinalityPolicyHash:             repeated32(0xa6),
		ObservedAt:                     observedAt,
	}
	queryer := &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.record_header_observation",
				argumentCount: 9,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "crosschain.record_header_observation",
				argumentCount: 9,
				values:        headerObservationValues(header),
			},
		},
	}
	observerRepository, _ := newSQL(queryer)
	replayedHeader, err := observerRepository.RecordHeaderObservation(
		t.Context(),
		header,
	)
	if err != nil || !sameHeaderObservation(replayedHeader, header) {
		t.Fatalf(
			"lost header response was not recovered: %#v %v",
			replayedHeader,
			err,
		)
	}
	queryer.assertDone()

	affectedMessageIDs := [][32]byte{repeated32(0x01), repeated32(0x02)}
	request := ReorganizationRequest{
		RouteID: "route-sql",
		ChainID: "31337",
		OrphanedProofIDs: []string{
			"proof-orphaned-v1",
			"proof-orphaned-v2",
		},
		OrphanedCertificateIDs: []string{
			"certificate-orphaned-v1",
			"certificate-orphaned-v2",
		},
		ReplacementObservationID:  header.ObservationID,
		DetectedHeadObservationID: "header-observation-head-v1",
		AffectedMessageIDs:        affectedMessageIDs,
		EvidenceHash:              repeated32(0xb1),
		DetectedAt:                observedAt.Add(time.Minute),
	}
	reorganization := ReorganizationRecord{
		ReorganizationID:          "crosschain-reorg:" + strings.Repeat("b1", 32),
		RouteID:                   request.RouteID,
		ChainID:                   request.ChainID,
		OrphanedBlockHash:         repeated32(0xb2),
		OrphanedBlockNumber:       "100",
		OrphanedProofID:           request.OrphanedProofIDs[0],
		OrphanedCertificateID:     request.OrphanedCertificateIDs[0],
		OrphanedProofIDs:          request.OrphanedProofIDs,
		OrphanedCertificateIDs:    request.OrphanedCertificateIDs,
		ReplacementBlockHash:      header.BlockHash,
		ReplacementBlockNumber:    header.BlockNumber,
		ReplacementObservationID:  request.ReplacementObservationID,
		DetectedHeadHash:          repeated32(0xb3),
		DetectedHeadNumber:        "112",
		DetectedHeadObservationID: request.DetectedHeadObservationID,
		DepthClass:                "DEEP_FINALITY",
		AffectedMessageIDs:        affectedMessageIDs,
		EvidenceHash:              request.EvidenceHash,
		DetectedAt:                request.DetectedAt,
		IncidentID:                "crosschain-incident:" + strings.Repeat("b1", 32),
		IncidentReasonCode:        "POST_FINALITY_REORGANIZATION",
		IncidentSeverity:          "CRITICAL",
		IncidentOwner:             "cross-chain-security",
		IncidentStatus:            "OPEN",
		IncidentOpenedAt:          request.DetectedAt,
	}
	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "crosschain.record_reorganization",
				argumentCount: 9,
				err:           io.ErrUnexpectedEOF,
			},
			{
				queryContains: "crosschain.record_reorganization",
				argumentCount: 9,
				values:        reorganizationValues(reorganization, false),
			},
		},
	}
	reorganizationRepository, _ := newSQL(queryer)
	recorded, err := reorganizationRepository.RecordReorganization(
		t.Context(),
		request,
	)
	if err != nil || !reflect.DeepEqual(recorded, reorganization) {
		t.Fatalf(
			"lost reorganization response was not recovered: %#v %v",
			recorded,
			err,
		)
	}
	queryer.assertDone()

	queryer = &scriptedSQLQueryer{
		t: t,
		steps: []scriptedSQLStep{
			{
				queryContains: "FROM crosschain.reorganizations",
				argumentCount: 1,
				values:        reorganizationValues(reorganization, true),
			},
		},
	}
	runtimeRepository, _ := newSQL(queryer)
	rehydrated, err := runtimeRepository.Reorganization(
		t.Context(),
		request.EvidenceHash,
	)
	if err != nil || !reflect.DeepEqual(rehydrated, reorganization) {
		t.Fatalf("reorganization restart rehydration: %#v %v", rehydrated, err)
	}
	queryer.assertDone()

	invalid := request
	invalid.AffectedMessageIDs = [][32]byte{
		affectedMessageIDs[1],
		affectedMessageIDs[0],
	}
	if _, err := runtimeRepository.RecordReorganization(
		t.Context(),
		invalid,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("unsorted affected message ids accepted: %v", err)
	}
	invalid = request
	invalid.OrphanedCertificateIDs = invalid.OrphanedCertificateIDs[:1]
	if _, err := runtimeRepository.RecordReorganization(
		t.Context(),
		invalid,
	); !errors.Is(err, ErrConflict) {
		t.Fatalf("misaligned certificate ids accepted: %v", err)
	}
}
