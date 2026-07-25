package main

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/recovery"
)

type phase8ImportFlow struct {
	LoanID          string                 `json:"loan_id"`
	LoanAccount     phase8AddressReference `json:"loan_account"`
	FundingLockID   string                 `json:"funding_lock_id"`
	CollateralID    string                 `json:"collateral_id"`
	PrincipalUnits  string                 `json:"principal_units"`
	CollateralUnits string                 `json:"collateral_units"`
	CanonicalAsset  phase8AddressReference `json:"canonical_asset"`
	WrappedAsset    phase8AddressReference `json:"wrapped_asset"`
	CollateralAsset phase8AddressReference `json:"collateral_asset"`
	Messages        []phase8ImportMessage  `json:"messages"`
	Replays         json.RawMessage        `json:"replays"`
	FinalState      json.RawMessage        `json:"final_state"`
	Economics       phase8FlowEconomics    `json:"-"`
}

type phase8AddressReference struct {
	Domain  string      `json:"domain"`
	ChainID json.Number `json:"chain_id"`
	Address string      `json:"address"`
}

type phase8ImportMessage struct {
	Sequence            uint32                        `json:"sequence"`
	RoutePurpose        string                        `json:"route_purpose"`
	Envelope            phase8ImportEnvelope          `json:"envelope"`
	Payload             string                        `json:"payload"`
	Source              phase8ImportSource            `json:"source"`
	ProviderAttempts    []phase8PublicProviderAttempt `json:"provider_attempts"`
	Destination         phase8ImportDestination       `json:"destination"`
	Acknowledgement     phase8ImportAcknowledgement   `json:"acknowledgement"`
	SourceFinal         bool                          `json:"source_final"`
	DestinationExecuted bool                          `json:"destination_executed"`
}

type phase8SQLImport struct {
	SerializedEnvelope     string                      `json:"serialized_envelope"`
	Envelope               phase8ImportEnvelope        `json:"envelope"`
	SourceProof            phase8ImportProof           `json:"source_proof"`
	SourceCertificate      phase8ImportCertificate     `json:"source_certificate"`
	DestinationProof       phase8ImportProof           `json:"destination_proof"`
	DestinationCertificate phase8ImportCertificate     `json:"destination_certificate"`
	ProviderAttempts       []phase8ProviderAttempt     `json:"provider_attempts"`
	Execution              phase8ImportExecution       `json:"execution"`
	Acknowledgement        phase8ImportAcknowledgement `json:"acknowledgement"`
	ActionProjection       phase8ImportProjection      `json:"action_projection"`
	ActionEconomics        phase8ActionEconomics       `json:"-"`
	Transitions            []phase8ImportTransition    `json:"transitions"`
}

type phase8ImportEnvelope struct {
	SchemaVersion                 uint32      `json:"schema_version"`
	MessageID                     string      `json:"message_id"`
	ProtocolID                    string      `json:"protocol_id"`
	SourceChainID                 json.Number `json:"source_chain_id"`
	SourceCoordinator             string      `json:"source_coordinator"`
	SourceComponent               string      `json:"source_component"`
	DestinationChainID            json.Number `json:"destination_chain_id"`
	DestinationCoordinator        string      `json:"destination_coordinator"`
	DestinationComponent          string      `json:"destination_component"`
	LaneID                        string      `json:"lane_id"`
	SourceNonce                   json.Number `json:"source_nonce"`
	AggregateID                   string      `json:"aggregate_id"`
	ActionType                    uint32      `json:"action_ordinal"`
	PayloadHash                   string      `json:"payload_hash"`
	CreatedAt                     json.Number `json:"created_at"`
	ExpiresAt                     json.Number `json:"expires_at"`
	RoutePolicyHash               string      `json:"route_policy_hash"`
	AdapterSetPolicyHash          string      `json:"adapter_set_policy_hash"`
	SourceFinalityPolicyHash      string      `json:"source_finality_policy_hash"`
	DestinationFinalityPolicyHash string      `json:"destination_finality_policy_hash"`
	CorrelationID                 string      `json:"correlation_id"`
	CausationMessageID            string      `json:"causation_message_id"`
	SupersededMessageID           string      `json:"superseded_message_id"`
}

type phase8ImportProof struct {
	ProofABI                       string      `json:"-"`
	ProofID                        string      `json:"-"`
	ChainID                        json.Number `json:"-"`
	TransactionHash                string      `json:"transaction_hash"`
	TransactionIndex               json.Number `json:"transaction_index"`
	LogIndex                       json.Number `json:"log_index"`
	BlockNumber                    json.Number `json:"source_block_number"`
	BlockTimestamp                 json.Number `json:"source_block_timestamp"`
	BlockHash                      string      `json:"source_block_hash"`
	ReceiptsRoot                   string      `json:"receipt_root"`
	InclusionProofHash             string      `json:"receipt_proof_hash"`
	EventHash                      string      `json:"event_hash"`
	FinalityHeadNumber             json.Number `json:"finality_head_number"`
	FinalityHeadHash               string      `json:"finality_head_hash"`
	ConfirmationDepth              json.Number `json:"required_depth"`
	FinalityPolicyHash             string      `json:"finality_policy_hash"`
	ObserverAuthorityHash          string      `json:"header_authority_hash"`
	ObserverSignedHeaderCommitment string      `json:"observer_signed_header_commitment"`
	ObserverSignature              string      `json:"observer_signature"`
	ProofHash                      string      `json:"-"`
	RawEvidenceObjectHash          string      `json:"-"`
	ObservedAt                     string      `json:"-"`
}

type phase8ImportCertificate struct {
	CertificateABI   string   `json:"-"`
	CertificateID    string   `json:"-"`
	MessageID        string   `json:"message_id"`
	SourceProofHash  string   `json:"source_proof_hash"`
	SignerSetHash    string   `json:"signer_set_hash"`
	SignerSetVersion uint64   `json:"signer_set_version"`
	SignerBitmap     string   `json:"-"`
	SignatureCount   uint32   `json:"-"`
	CertificateHash  string   `json:"-"`
	Signatures       []string `json:"signatures"`
	CertifiedAt      string   `json:"-"`
}

type phase8PublicProviderAttempt struct {
	ProviderID           string `json:"provider_id"`
	AttemptNumber        uint32 `json:"attempt_number"`
	Status               string `json:"status"`
	Retryable            bool   `json:"retryable"`
	MessageID            string `json:"message_id"`
	PayloadHash          string `json:"payload_hash"`
	SourceProofHash      string `json:"source_proof_hash"`
	TransportReceiptHash string `json:"transport_receipt_hash"`
}

type phase8ProviderAttempt struct {
	ProviderID             string  `json:"provider_id"`
	AttemptNumber          uint32  `json:"attempt_number"`
	SerializedEnvelopeHash string  `json:"serialized_envelope_hash"`
	SourceProofHash        string  `json:"source_proof_hash"`
	Status                 string  `json:"status"`
	ProviderReceiptHash    *string `json:"provider_receipt_hash"`
	AttemptedAt            string  `json:"attempted_at"`
}

type phase8ImportExecution struct {
	DestinationChainID json.Number `json:"destination_chain_id"`
	TransactionHash    string      `json:"transaction_hash"`
	LogIndex           json.Number `json:"log_index"`
	ResultHash         string      `json:"result_hash"`
	EffectCommitment   string      `json:"effect_commitment"`
	ExecutedAt         string      `json:"executed_at"`
}

type phase8ImportAcknowledgement struct {
	TransactionHash        string                       `json:"transaction_hash"`
	BlockHash              string                       `json:"block_hash"`
	BlockNumber            json.Number                  `json:"block_number"`
	TransactionIndex       json.Number                  `json:"transaction_index"`
	LogIndex               json.Number                  `json:"log_index"`
	RawEvidenceObjectHash  string                       `json:"raw_evidence_object_hash"`
	Commitment             string                       `json:"commitment"`
	Finalized              bool                         `json:"finalized"`
	ProofID                string                       `json:"proof_id"`
	ProofHash              string                       `json:"proof_hash"`
	CertificateID          string                       `json:"certificate_id"`
	CertificateHash        string                       `json:"certificate_hash"`
	Proof                  phase8ImportProof            `json:"proof"`
	Certificate            phase8ImportCertificate      `json:"certificate"`
	AuthenticatedInclusion phase8AuthenticatedInclusion `json:"authenticated_inclusion"`
	ExecutionResultHash    string                       `json:"execution_result_hash"`
	DestinationProofID     string                       `json:"destination_proof_id"`
	AcknowledgedAt         string                       `json:"acknowledged_at"`
}

type phase8ImportSource struct {
	ChainID                json.Number                  `json:"chain_id"`
	TransactionHash        string                       `json:"transaction_hash"`
	BlockHash              string                       `json:"block_hash"`
	BlockNumber            json.Number                  `json:"block_number"`
	TransactionIndex       json.Number                  `json:"transaction_index"`
	LogIndex               json.Number                  `json:"log_index"`
	RawEvidenceObjectHash  string                       `json:"raw_evidence_object_hash"`
	ProofID                string                       `json:"proof_id"`
	ProofHash              string                       `json:"proof_hash"`
	CertificateID          string                       `json:"certificate_id"`
	CertificateHash        string                       `json:"certificate_hash"`
	Proof                  phase8ImportProof            `json:"proof"`
	Certificate            phase8ImportCertificate      `json:"certificate"`
	AuthenticatedInclusion phase8AuthenticatedInclusion `json:"authenticated_inclusion"`
}

type phase8AuthenticatedInclusion struct {
	HeaderRLP                 string                       `json:"header_rlp"`
	HeaderObservedAtUnixNanos string                       `json:"header_observed_at_unix_nanos"`
	HeaderSignatureEd25519    string                       `json:"header_signature_ed25519"`
	Receipts                  []phase8AuthenticatedReceipt `json:"receipts"`
	ConfirmationHeaders       []phase8AuthenticatedHeader  `json:"confirmation_headers"`
}

type phase8AuthenticatedReceipt struct {
	TransactionIndex      json.Number `json:"transaction_index"`
	TransactionRLP        string      `json:"transaction_rlp"`
	TransactionProofNodes []string    `json:"transaction_proof_nodes"`
	ReceiptRLP            string      `json:"receipt_rlp"`
	ReceiptProofNodes     []string    `json:"receipt_proof_nodes"`
}

type phase8AuthenticatedHeader struct {
	HeaderRLP                 string `json:"header_rlp"`
	HeaderObservedAtUnixNanos string `json:"header_observed_at_unix_nanos"`
	HeaderSignatureEd25519    string `json:"header_signature_ed25519"`
}

type phase8ImportDestination struct {
	ChainID          json.Number `json:"chain_id"`
	TransactionHash  string      `json:"transaction_hash"`
	BlockHash        string      `json:"block_hash"`
	BlockNumber      json.Number `json:"block_number"`
	TransactionIndex json.Number `json:"transaction_index"`
	LogIndex         json.Number `json:"log_index"`
	ResultHash       string      `json:"result_hash"`
}

type phase8ImportProjection struct {
	Projection  json.RawMessage `json:"projection"`
	ProjectedAt string          `json:"projected_at"`
}

type phase8ImportTransition struct {
	ExpectedVersion uint64  `json:"expected_version"`
	ExpectedState   string  `json:"expected_state"`
	NextState       string  `json:"next_state"`
	FailureClass    *string `json:"failure_class"`
	EvidenceHash    string  `json:"evidence_hash"`
	OccurredAt      string  `json:"occurred_at"`
}

const (
	importMessageSQL = `
SELECT crosschain.record_message(
    $1, $2, $3, $4::numeric, $5, $6, $7::numeric, $8, $9,
    $10, $11::numeric, $12, $13, $14, $15, $16, $17, $18,
    $19, $20, $21, $22, $23, $24, $25
)`
	importProofSQL = `
SELECT crosschain.record_source_proof(
    $1, $2, $3::numeric, $4, $5::numeric, $6::numeric, $7::numeric,
    $8, $9, $10, $11, $12::numeric, $13, $14::numeric, $15, $16,
    $17, $18, $19, $20, $21, $22
)`
	importCertificateSQL = `
SELECT crosschain.record_finality_certificate(
    $1, $2, $3, $4, $5, $6::bit varying, $7, $8, $9, $10, $11
)`
	importProviderAttemptSQL = `
SELECT crosschain.record_provider_attempt(
    $1, $2, $3, $4, $5, $6, $7, $8
)`
	importExecutionSQL = `
SELECT crosschain.record_evm_execution(
    $1, $2::numeric, $3, $4::numeric, $5, $6, $7, $8, $9::jsonb, $10
)`
	importAcknowledgementSQL = `
SELECT crosschain.record_evm_acknowledgement($1, $2, $3, $4, $5, $6)`
	importProjectionSQL = `
SELECT crosschain.record_action_projection($1, $2::jsonb, $3)`
	importTransitionSQL = `
SELECT crosschain.transition_message($1, $2, $3, $4, $5, $6, $7)`
)

func decodePhase8ImportFlow(
	raw json.RawMessage,
	manifest phase8ReleaseManifest,
) (phase8ImportFlow, error) {
	var flow phase8ImportFlow
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&flow); err != nil {
		return flow, fmt.Errorf("decode manifest SQL import flow: %w", err)
	}
	if len(flow.Messages) == 0 {
		return flow, errors.New("manifest flow has no importable messages")
	}
	economics, err := derivePhase8FlowEconomics(flow, manifest)
	if err != nil {
		return phase8ImportFlow{}, err
	}
	flow.Economics = economics
	for index, message := range flow.Messages {
		if err := validatePhase8ImportMessage(
			message,
			index,
			uint32(index+1),
			index == 0,
			manifest,
			economics,
		); err != nil {
			return phase8ImportFlow{}, err
		}
	}
	return flow, nil
}

func derivePhase8SQLImport(
	message phase8ImportMessage,
	manifest phase8ReleaseManifest,
	economics phase8FlowEconomics,
) (phase8SQLImport, error) {
	payload, err := importHex(message.Payload, -1, false)
	if err != nil {
		return phase8SQLImport{}, err
	}
	payloadHash := keccak(payload)
	if !sameHex(message.Envelope.PayloadHash, payloadHash[:]) {
		return phase8SQLImport{}, errors.New("payload hash does not bind exact payload ABI")
	}
	if !message.Acknowledgement.Finalized {
		return phase8SQLImport{}, errors.New("acknowledgement is not finalized")
	}
	serialized, err := encodeImportEnvelopePayloadABI(message.Envelope, payload)
	if err != nil {
		return phase8SQLImport{}, err
	}
	sourceProof := message.Source.Proof
	sourceProof.ProofID = message.Source.ProofID
	sourceProof.ChainID = message.Source.ChainID
	sourceProof.ProofHash = message.Source.ProofHash
	sourceProof.RawEvidenceObjectHash = message.Source.RawEvidenceObjectHash
	sourceProof.ObservedAt = unixNumberRFC3339(sourceProof.BlockTimestamp)
	sourceProofABI, err := encodeImportProofABI(sourceProof)
	if err != nil {
		return phase8SQLImport{}, err
	}
	sourceProof.ProofABI = "0x" + hex.EncodeToString(sourceProofABI)
	sourceProofHash := keccak(sourceProofABI)
	if !sameHex(sourceProof.ProofHash, sourceProofHash[:]) ||
		!sameHex(message.Source.ProofHash, sourceProofHash[:]) {
		return phase8SQLImport{}, errors.New("source proof hash differs from exact expanded proof")
	}
	sourceEventHash := computeSourceMessageEventHash(message.Envelope)
	if !sameHex(sourceProof.EventHash, sourceEventHash[:]) {
		return phase8SQLImport{}, errors.New("source proof event hash is not canonical")
	}
	sourceCertificate := message.Source.Certificate
	sourceCertificate.CertificateID = message.Source.CertificateID
	sourceCertificate.CertificateHash = message.Source.CertificateHash
	sourceCertificate.SignatureCount = uint32(len(sourceCertificate.Signatures))
	sourceCertificate.CertifiedAt = sourceProof.ObservedAt
	sourceCertificateABI, err := encodeImportCertificateABI(sourceCertificate)
	if err != nil {
		return phase8SQLImport{}, err
	}
	sourceCertificate.CertificateABI =
		"0x" + hex.EncodeToString(sourceCertificateABI)
	sourceCertificateHash := keccak(sourceCertificateABI)
	if !sameHex(sourceCertificate.CertificateHash, sourceCertificateHash[:]) {
		return phase8SQLImport{}, errors.New("source certificate hash differs from exact expanded certificate")
	}
	sourceCertificate.SignerBitmap, err = certificateSignerBitmap(
		sourceCertificate,
		sourceProof,
		message.Envelope,
		manifest,
	)
	if err != nil {
		return phase8SQLImport{}, err
	}
	destinationProof := message.Acknowledgement.Proof
	destinationProof.ProofID = message.Acknowledgement.ProofID
	destinationProof.ChainID = message.Destination.ChainID
	destinationProof.ProofHash = message.Acknowledgement.ProofHash
	destinationInclusionJSON, err := canonicalJSON(
		message.Acknowledgement.AuthenticatedInclusion,
	)
	if err != nil {
		return phase8SQLImport{}, err
	}
	destinationRawEvidenceHash := keccak(destinationInclusionJSON)
	destinationProof.RawEvidenceObjectHash = hexHash(destinationRawEvidenceHash)
	destinationProof.ObservedAt = unixNumberRFC3339(
		destinationProof.BlockTimestamp,
	)
	destinationProofABI, err := encodeImportProofABI(destinationProof)
	if err != nil {
		return phase8SQLImport{}, err
	}
	destinationProof.ProofABI =
		"0x" + hex.EncodeToString(destinationProofABI)
	destinationProofHash := keccak(destinationProofABI)
	if !sameHex(destinationProof.ProofHash, destinationProofHash[:]) ||
		!sameHex(message.Acknowledgement.ProofHash, destinationProofHash[:]) {
		return phase8SQLImport{}, errors.New("acknowledgement proof hash differs from exact expanded proof")
	}
	acknowledgementCommitment := computeAcknowledgementEventHash(
		message.Envelope,
		message.Destination.ResultHash,
	)
	if !sameHex(message.Acknowledgement.Commitment, acknowledgementCommitment[:]) ||
		!sameHex(destinationProof.EventHash, acknowledgementCommitment[:]) {
		return phase8SQLImport{}, errors.New("acknowledgement commitment is not Solidity-canonical")
	}
	destinationCertificate := message.Acknowledgement.Certificate
	destinationCertificate.CertificateID =
		message.Acknowledgement.CertificateID
	destinationCertificate.CertificateHash =
		message.Acknowledgement.CertificateHash
	destinationCertificate.SignatureCount =
		uint32(len(destinationCertificate.Signatures))
	destinationCertificate.CertifiedAt = destinationProof.ObservedAt
	destinationCertificateABI, err := encodeImportCertificateABI(
		destinationCertificate,
	)
	if err != nil {
		return phase8SQLImport{}, err
	}
	destinationCertificate.CertificateABI =
		"0x" + hex.EncodeToString(destinationCertificateABI)
	destinationCertificateHash := keccak(destinationCertificateABI)
	if !sameHex(destinationCertificate.CertificateHash, destinationCertificateHash[:]) {
		return phase8SQLImport{}, errors.New("acknowledgement certificate hash differs from exact expanded certificate")
	}
	destinationCertificate.SignerBitmap, err = certificateSignerBitmap(
		destinationCertificate,
		destinationProof,
		message.Envelope,
		manifest,
	)
	if err != nil {
		return phase8SQLImport{}, err
	}
	envelopeHash := keccak(serialized)
	providerAttempts := make(
		[]phase8ProviderAttempt,
		len(message.ProviderAttempts),
	)
	for index, public := range message.ProviderAttempts {
		if public.MessageID != message.Envelope.MessageID ||
			public.PayloadHash != message.Envelope.PayloadHash ||
			public.SourceProofHash != message.Source.ProofHash {
			return phase8SQLImport{}, errors.New(
				"provider attempt does not bind exact message evidence",
			)
		}
		if _, err := importHex(public.TransportReceiptHash, 32, false); err != nil {
			return phase8SQLImport{}, errors.New(
				"provider attempt lacks an observed transport receipt hash",
			)
		}
		var receiptPointer *string
		if public.Status != "FAILED" {
			receipt := public.TransportReceiptHash
			receiptPointer = &receipt
		}
		providerAttempts[index] = phase8ProviderAttempt{
			ProviderID:             public.ProviderID,
			AttemptNumber:          public.AttemptNumber,
			SerializedEnvelopeHash: hexHash(envelopeHash),
			SourceProofHash:        public.SourceProofHash,
			Status:                 public.Status,
			ProviderReceiptHash:    receiptPointer,
			AttemptedAt: unixSecondsRFC3339(
				mustUnixInt64(message.Envelope.CreatedAt) +
					int64(public.AttemptNumber),
			),
		}
	}
	projectionFields := map[string]any{
		"action_ordinal":                 message.Envelope.ActionType,
		"destination_result_hash":        message.Destination.ResultHash,
		"evm_acknowledgement_commitment": message.Acknowledgement.Commitment,
		"payload_abi":                    message.Payload,
		"proof_boundary":                 manifest.ProofBoundary,
		"route_purpose":                  message.RoutePurpose,
	}
	actionEconomics, err := projectPhase8Action(
		message,
		manifest,
		economics,
		projectionFields,
	)
	if err != nil {
		return phase8SQLImport{}, err
	}
	projection, err := json.Marshal(projectionFields)
	if err != nil {
		return phase8SQLImport{}, err
	}
	projectedAt := actionEconomics.FinalizedAt
	if actionEconomics.Action == 8 {
		projectedAt = actionEconomics.ReleaseFinalizedAt
	}
	destinationTime := destinationProof.ObservedAt
	transitions := phase8CanonicalTransitions(
		sourceProof,
		sourceCertificate,
		destinationProof,
		message.Destination.ResultHash,
	)
	return phase8SQLImport{
		SerializedEnvelope:     "0x" + hex.EncodeToString(serialized),
		Envelope:               message.Envelope,
		SourceProof:            sourceProof,
		SourceCertificate:      sourceCertificate,
		DestinationProof:       destinationProof,
		DestinationCertificate: destinationCertificate,
		ProviderAttempts:       providerAttempts,
		Execution: phase8ImportExecution{
			DestinationChainID: message.Destination.ChainID,
			TransactionHash:    message.Destination.TransactionHash,
			LogIndex:           message.Destination.LogIndex,
			ResultHash:         message.Destination.ResultHash,
			ExecutedAt:         destinationTime,
		},
		Acknowledgement: phase8ImportAcknowledgement{
			ExecutionResultHash: message.Destination.ResultHash,
			DestinationProofID:  message.Acknowledgement.ProofID,
			CertificateID:       message.Acknowledgement.CertificateID,
			Commitment:          message.Acknowledgement.Commitment,
			AcknowledgedAt:      destinationTime,
		},
		ActionProjection: phase8ImportProjection{
			Projection:  projection,
			ProjectedAt: projectedAt,
		},
		ActionEconomics: actionEconomics,
		Transitions:     transitions,
	}, nil
}

func phase8CanonicalTransitions(
	sourceProof phase8ImportProof,
	sourceCertificate phase8ImportCertificate,
	destinationProof phase8ImportProof,
	destinationResultHash string,
) []phase8ImportTransition {
	sourceTime := sourceProof.ObservedAt
	destinationTime := destinationProof.ObservedAt
	return []phase8ImportTransition{
		{1, "CREATED", "SOURCE_FINALIZING", nil, sourceProof.ProofHash, sourceTime},
		{2, "SOURCE_FINALIZING", "SOURCE_FINAL", nil, sourceCertificate.CertificateHash, sourceTime},
		{3, "SOURCE_FINAL", "SENT", nil, sourceCertificate.CertificateHash, sourceTime},
		{4, "SENT", "RELAYED", nil, destinationProof.ProofHash, destinationTime},
		{5, "RELAYED", "VERIFIED", nil, sourceCertificate.CertificateHash, destinationTime},
		{6, "VERIFIED", "EXECUTED", nil, destinationResultHash, destinationTime},
		{7, "EXECUTED", "ACK_PENDING", nil, destinationResultHash, destinationTime},
		{8, "ACK_PENDING", "ACKNOWLEDGED", nil, destinationResultHash, destinationTime},
	}
}

func validatePhase8ImportMessage(
	message phase8ImportMessage,
	index int,
	expectedSequence uint32,
	expectFailover bool,
	manifest phase8ReleaseManifest,
	economics phase8FlowEconomics,
) error {
	if message.Sequence != expectedSequence {
		return fmt.Errorf("message %d sequence is not canonical", index)
	}
	if !message.SourceFinal || !message.DestinationExecuted ||
		message.RoutePurpose == "" {
		return fmt.Errorf("message %d is not terminal EVM evidence", index)
	}
	sqlImport, err := derivePhase8SQLImport(message, manifest, economics)
	if err != nil {
		return fmt.Errorf("message %d SQL derivation: %w", index, err)
	}
	messageID, err := importHex(message.Envelope.MessageID, 32, false)
	if err != nil {
		return fmt.Errorf("message %d ID: %w", index, err)
	}
	envelope, err := importHex(sqlImport.SerializedEnvelope, -1, false)
	if err != nil || len(envelope) == 0 {
		return fmt.Errorf("message %d serialized envelope is invalid", index)
	}
	if sqlImport.Envelope.SchemaVersion != 1 ||
		sqlImport.Envelope.ActionType == 0 ||
		sqlImport.Envelope.ActionType > 16 {
		return fmt.Errorf("message %d envelope metadata is invalid", index)
	}
	for label, value := range map[string]string{
		"message_id":                       sqlImport.Envelope.MessageID,
		"protocol_id":                      sqlImport.Envelope.ProtocolID,
		"lane_id":                          sqlImport.Envelope.LaneID,
		"aggregate_id":                     sqlImport.Envelope.AggregateID,
		"payload_hash":                     sqlImport.Envelope.PayloadHash,
		"route_policy_hash":                sqlImport.Envelope.RoutePolicyHash,
		"adapter_set_policy_hash":          sqlImport.Envelope.AdapterSetPolicyHash,
		"source_finality_policy_hash":      sqlImport.Envelope.SourceFinalityPolicyHash,
		"destination_finality_policy_hash": sqlImport.Envelope.DestinationFinalityPolicyHash,
		"correlation_id":                   sqlImport.Envelope.CorrelationID,
	} {
		if _, err := importHex(value, 32, false); err != nil {
			return fmt.Errorf("message %d %s: %w", index, label, err)
		}
	}
	for label, value := range map[string]string{
		"source_coordinator":      sqlImport.Envelope.SourceCoordinator,
		"source_component":        sqlImport.Envelope.SourceComponent,
		"destination_coordinator": sqlImport.Envelope.DestinationCoordinator,
		"destination_component":   sqlImport.Envelope.DestinationComponent,
	} {
		if _, err := importHex(value, 20, false); err != nil {
			return fmt.Errorf("message %d %s: %w", index, label, err)
		}
	}
	if _, err := importHex(sqlImport.Envelope.CausationMessageID, 32, true); err != nil {
		return err
	}
	if _, err := importHex(sqlImport.Envelope.SupersededMessageID, 32, true); err != nil {
		return err
	}
	if _, err := canonicalManifestNumber(sqlImport.Envelope.SourceChainID, false); err != nil {
		return err
	}
	if _, err := canonicalManifestNumber(sqlImport.Envelope.DestinationChainID, false); err != nil {
		return err
	}
	if _, err := canonicalManifestNumber(sqlImport.Envelope.SourceNonce, false); err != nil {
		return err
	}
	computedMessageID, err := computeImportMessageID(sqlImport.Envelope)
	if err != nil || !bytes.Equal(messageID, computedMessageID[:]) ||
		!sameHex(sqlImport.Envelope.MessageID, computedMessageID[:]) {
		return fmt.Errorf("message %d ID is not Solidity-canonical", index)
	}
	if err := validateImportProof(
		sqlImport.SourceProof,
		sqlImport.Envelope,
		manifest,
	); err != nil {
		return fmt.Errorf("message %d source proof: %w", index, err)
	}
	if err := validatePhase8OuterProofIdentity(
		"source",
		message.Source.TransactionHash,
		message.Source.BlockHash,
		message.Source.BlockNumber,
		message.Source.TransactionIndex,
		message.Source.LogIndex,
		sqlImport.SourceProof,
	); err != nil {
		return fmt.Errorf("message %d: %w", index, err)
	}
	if err := validateImportProof(
		sqlImport.DestinationProof,
		sqlImport.Envelope,
		manifest,
	); err != nil {
		return fmt.Errorf("message %d destination proof: %w", index, err)
	}
	if err := validatePhase8OuterProofIdentity(
		"destination",
		message.Destination.TransactionHash,
		message.Destination.BlockHash,
		message.Destination.BlockNumber,
		message.Destination.TransactionIndex,
		message.Destination.LogIndex,
		sqlImport.DestinationProof,
	); err != nil {
		return fmt.Errorf("message %d: %w", index, err)
	}
	if err := validateAuthenticatedInclusion(
		message.Source.AuthenticatedInclusion,
		message.Source.RawEvidenceObjectHash,
		sqlImport.SourceProof,
		sqlImport.Envelope,
		manifest,
		expectedSourceCoordinatorLog(
			sqlImport.Envelope,
			mustJSONUint64(sqlImport.SourceProof.LogIndex),
		),
	); err != nil {
		return fmt.Errorf("message %d source authenticated inclusion: %w", index, err)
	}
	if err := validateAuthenticatedInclusion(
		message.Acknowledgement.AuthenticatedInclusion,
		message.Acknowledgement.RawEvidenceObjectHash,
		sqlImport.DestinationProof,
		sqlImport.Envelope,
		manifest,
		expectedExecutionCoordinatorLog(
			sqlImport.Envelope,
			message.Destination.ResultHash,
			mustJSONUint64(sqlImport.DestinationProof.LogIndex),
		),
	); err != nil {
		return fmt.Errorf("message %d destination authenticated inclusion: %w", index, err)
	}
	if err := validateImportCertificate(
		sqlImport.SourceCertificate,
		sqlImport.SourceProof,
		sqlImport.Envelope,
		manifest,
	); err != nil {
		return fmt.Errorf("message %d source certificate: %w", index, err)
	}
	if err := validateImportCertificate(
		sqlImport.DestinationCertificate,
		sqlImport.DestinationProof,
		sqlImport.Envelope,
		manifest,
	); err != nil {
		return fmt.Errorf("message %d destination certificate: %w", index, err)
	}
	if len(sqlImport.ProviderAttempts) == 0 {
		return fmt.Errorf("message %d has no provider attempts", index)
	}
	if err := validatePhase8ProviderAttempts(
		message,
		index,
		expectFailover,
	); err != nil {
		return err
	}
	expectedStates := [][2]string{
		{"CREATED", "SOURCE_FINALIZING"},
		{"SOURCE_FINALIZING", "SOURCE_FINAL"},
		{"SOURCE_FINAL", "SENT"},
		{"SENT", "RELAYED"},
		{"RELAYED", "VERIFIED"},
		{"VERIFIED", "EXECUTED"},
		{"EXECUTED", "ACK_PENDING"},
		{"ACK_PENDING", "ACKNOWLEDGED"},
	}
	if len(sqlImport.Transitions) != len(expectedStates) {
		return fmt.Errorf("message %d transition path is incomplete", index)
	}
	for transitionIndex, transition := range sqlImport.Transitions {
		if transition.ExpectedVersion != uint64(transitionIndex+1) ||
			transition.ExpectedState != expectedStates[transitionIndex][0] ||
			transition.NextState != expectedStates[transitionIndex][1] {
			return fmt.Errorf("message %d transition path is not canonical", index)
		}
		if _, err := importHex(transition.EvidenceHash, 32, false); err != nil {
			return err
		}
		if _, err := importTime(transition.OccurredAt); err != nil {
			return err
		}
	}
	if !bytes.Equal(messageID, mustImportHex(message.Envelope.MessageID, 32, false)) {
		return errors.New("unreachable message ID mismatch")
	}
	return nil
}

func validatePhase8ProviderAttempts(
	message phase8ImportMessage,
	index int,
	expectFailover bool,
) error {
	expected := []phase8PublicProviderAttempt{
		{
			ProviderID:    localProviderAID,
			AttemptNumber: 1,
			Status:        "DELIVERED",
			Retryable:     false,
		},
	}
	if expectFailover {
		expected = []phase8PublicProviderAttempt{
			{
				ProviderID:    localProviderAID,
				AttemptNumber: 1,
				Status:        "FAILED",
				Retryable:     true,
			},
			{
				ProviderID:    localProviderBID,
				AttemptNumber: 2,
				Status:        "DELIVERED",
				Retryable:     false,
			},
		}
	}
	if len(message.ProviderAttempts) != len(expected) {
		return fmt.Errorf(
			"message %d provider attempt path is not the frozen live failover path",
			index,
		)
	}
	for attemptIndex, attempt := range message.ProviderAttempts {
		want := expected[attemptIndex]
		if attempt.ProviderID != want.ProviderID ||
			attempt.AttemptNumber != want.AttemptNumber ||
			attempt.Status != want.Status ||
			attempt.Retryable != want.Retryable ||
			!sameHex(attempt.MessageID, mustImportHex(
				message.Envelope.MessageID,
				32,
				false,
			)) ||
			!sameHex(attempt.PayloadHash, mustImportHex(
				message.Envelope.PayloadHash,
				32,
				false,
			)) ||
			!sameHex(attempt.SourceProofHash, mustImportHex(
				message.Source.ProofHash,
				32,
				false,
			)) {
			return fmt.Errorf(
				"message %d provider attempt %d is not exact response-derived evidence",
				index,
				attemptIndex,
			)
		}
	}
	return nil
}

func validatePhase8OuterProofIdentity(
	label string,
	transactionHash string,
	blockHash string,
	blockNumber json.Number,
	transactionIndex json.Number,
	logIndex json.Number,
	proof phase8ImportProof,
) error {
	for field, value := range map[string]json.Number{
		"block number":      blockNumber,
		"transaction index": transactionIndex,
		"log index":         logIndex,
	} {
		if _, err := canonicalManifestNumber(value, true); err != nil {
			return fmt.Errorf("%s %s is invalid: %w", label, field, err)
		}
	}
	if !sameHex(transactionHash, mustImportHex(proof.TransactionHash, 32, false)) ||
		!sameHex(blockHash, mustImportHex(proof.BlockHash, 32, false)) ||
		blockNumber.String() != proof.BlockNumber.String() ||
		transactionIndex.String() != proof.TransactionIndex.String() ||
		logIndex.String() != proof.LogIndex.String() {
		return fmt.Errorf("%s receipt identity differs from retained proof", label)
	}
	return nil
}

func validateAuthenticatedInclusion(
	inclusion phase8AuthenticatedInclusion,
	declaredRawEvidenceObjectHash string,
	proof phase8ImportProof,
	envelope phase8ImportEnvelope,
	manifest phase8ReleaseManifest,
	expectedLog projection.ExpectedReceiptLog,
) error {
	canonical, err := canonicalJSON(inclusion)
	if err != nil {
		return err
	}
	rawEvidenceHash := keccak(canonical)
	if _, err := importHex(declaredRawEvidenceObjectHash, 32, false); err != nil {
		return errors.New("authenticated inclusion lacks a canonical raw evidence object hash")
	}
	if !sameHex(declaredRawEvidenceObjectHash, rawEvidenceHash[:]) {
		return errors.New("raw evidence object hash does not bind authenticated inclusion")
	}
	domain, err := importProofDomain(proof, envelope, manifest)
	if err != nil {
		return err
	}
	chainText, err := canonicalManifestNumber(proof.ChainID, false)
	if err != nil {
		return err
	}
	chainID, err := strconv.ParseUint(chainText, 10, 64)
	if err != nil {
		return errors.New("authenticated inclusion chain ID exceeds uint64")
	}
	targetIndex, err := strconv.ParseUint(proof.TransactionIndex.String(), 10, 64)
	if err != nil {
		return errors.New("authenticated inclusion target index is invalid")
	}
	authority, err := importHex(
		domain.ObserverPublicKey,
		ed25519.PublicKeySize,
		false,
	)
	if err != nil {
		return err
	}
	headerRLP, err := importHex(inclusion.HeaderRLP, -1, false)
	if err != nil {
		return fmt.Errorf("header RLP: %w", err)
	}
	headerSignature, err := importHex(
		inclusion.HeaderSignatureEd25519,
		ed25519.SignatureSize,
		false,
	)
	if err != nil {
		return fmt.Errorf("header signature: %w", err)
	}
	observedAt, err := unixNanosTime(inclusion.HeaderObservedAtUnixNanos)
	if err != nil {
		return err
	}
	receipts := make(
		[]projection.ReceiptInclusionProof,
		len(inclusion.Receipts),
	)
	for index, item := range inclusion.Receipts {
		transactionIndex, parseErr := strconv.ParseUint(
			item.TransactionIndex.String(),
			10,
			64,
		)
		if parseErr != nil || transactionIndex != uint64(index) {
			return errors.New("authenticated receipt evidence is not prefix-complete")
		}
		transactionRLP, parseErr := importHex(item.TransactionRLP, -1, false)
		if parseErr != nil {
			return parseErr
		}
		receiptRLP, parseErr := importHex(item.ReceiptRLP, -1, false)
		if parseErr != nil {
			return parseErr
		}
		transactionNodes, parseErr := importHexList(
			item.TransactionProofNodes,
			"transaction proof",
		)
		if parseErr != nil {
			return parseErr
		}
		receiptNodes, parseErr := importHexList(
			item.ReceiptProofNodes,
			"receipt proof",
		)
		if parseErr != nil {
			return parseErr
		}
		receipts[index] = projection.ReceiptInclusionProof{
			TransactionIndex:      transactionIndex,
			TransactionRLP:        transactionRLP,
			TransactionProofNodes: transactionNodes,
			ReceiptRLP:            receiptRLP,
			ReceiptProofNodes:     receiptNodes,
		}
	}
	confirmationHeaders := make(
		[]projection.AuthenticatedHeader,
		len(inclusion.ConfirmationHeaders),
	)
	for index, item := range inclusion.ConfirmationHeaders {
		header, parseErr := importHex(item.HeaderRLP, -1, false)
		if parseErr != nil {
			return parseErr
		}
		signature, parseErr := importHex(
			item.HeaderSignatureEd25519,
			ed25519.SignatureSize,
			false,
		)
		if parseErr != nil {
			return parseErr
		}
		observed, parseErr := unixNanosTime(item.HeaderObservedAtUnixNanos)
		if parseErr != nil {
			return parseErr
		}
		confirmationHeaders[index] = projection.AuthenticatedHeader{
			HeaderRLP:  header,
			ObservedAt: observed,
			Signature:  signature,
		}
	}
	verified, err := projection.VerifyAuthenticatedReceiptEvidence(
		chainID,
		domain.Contracts["coordinator"].Address,
		ed25519.PublicKey(authority),
		projection.AuthenticatedBlock{
			HeaderRLP:  headerRLP,
			ObservedAt: observedAt,
			Signature:  headerSignature,
			Receipts:   receipts,
		},
		confirmationHeaders,
		targetIndex,
		mustJSONUint64(proof.ConfirmationDepth),
		expectedLog,
	)
	if err != nil {
		return fmt.Errorf("Phase 7C MPT verification: %w", err)
	}
	if verified.TransactionHash != proof.TransactionHash ||
		verified.TransactionIndex != targetIndex ||
		verified.BlockHash != proof.BlockHash ||
		verified.BlockNumber != mustJSONUint64(proof.BlockNumber) ||
		verified.BlockTimestamp != mustJSONUint64(proof.BlockTimestamp) ||
		verified.ReceiptsRoot != proof.ReceiptsRoot ||
		verified.InclusionProofHash != proof.InclusionProofHash ||
		verified.FinalityHeadHash != proof.FinalityHeadHash ||
		verified.FinalityHeadNumber != mustJSONUint64(proof.FinalityHeadNumber) {
		return errors.New("authenticated inclusion differs from expanded SourceEventProof")
	}
	return nil
}

func expectedSourceCoordinatorLog(
	envelope phase8ImportEnvelope,
	logIndex uint64,
) projection.ExpectedReceiptLog {
	signature := keccak([]byte(
		"MessageSent(bytes32,bytes32,uint64,bytes32,uint8,bytes32,uint256,address)",
	))
	sourceNonce := mustUintWord(envelope.SourceNonce)
	destinationChain, _ := wordUint256(envelope.DestinationChainID.String())
	data := make([]byte, 0, 5*32)
	data = append(data, wordBytes32(mustManifestHash(envelope.AggregateID))...)
	data = append(data, wordUint64(uint64(envelope.ActionType))...)
	data = append(data, wordBytes32(mustManifestHash(envelope.PayloadHash))...)
	data = append(data, destinationChain...)
	data = append(data, wordAddress(mustAddress(envelope.DestinationComponent))...)
	return projection.ExpectedReceiptLog{
		Address: strings.ToLower(envelope.SourceCoordinator),
		Topics: []string{
			hexHash(signature),
			envelope.MessageID,
			envelope.LaneID,
			"0x" + hex.EncodeToString(sourceNonce),
		},
		Data:     data,
		LogIndex: logIndex,
	}
}

func expectedExecutionCoordinatorLog(
	envelope phase8ImportEnvelope,
	resultHash string,
	logIndex uint64,
) projection.ExpectedReceiptLog {
	signature := keccak([]byte(
		"MessageExecuted(bytes32,bytes32,uint64,address,bytes32)",
	))
	sourceNonce := mustUintWord(envelope.SourceNonce)
	data := make([]byte, 0, 2*32)
	data = append(data, wordAddress(mustAddress(envelope.DestinationComponent))...)
	data = append(data, wordBytes32(mustManifestHash(resultHash))...)
	return projection.ExpectedReceiptLog{
		Address: strings.ToLower(envelope.DestinationCoordinator),
		Topics: []string{
			hexHash(signature),
			envelope.MessageID,
			envelope.LaneID,
			"0x" + hex.EncodeToString(sourceNonce),
		},
		Data:     data,
		LogIndex: logIndex,
	}
}

func canonicalJSON(value any) ([]byte, error) {
	intermediate, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	var generic any
	decoder := json.NewDecoder(bytes.NewReader(intermediate))
	decoder.UseNumber()
	if err := decoder.Decode(&generic); err != nil {
		return nil, err
	}
	return json.Marshal(generic)
}

func importHexList(values []string, label string) ([][]byte, error) {
	if len(values) == 0 {
		return nil, fmt.Errorf("%s nodes are required", label)
	}
	result := make([][]byte, len(values))
	for index, value := range values {
		raw, err := importHex(value, -1, false)
		if err != nil {
			return nil, fmt.Errorf("%s node %d: %w", label, index, err)
		}
		result[index] = raw
	}
	return result, nil
}

func importCertificateSignatures(values []string) [][]byte {
	result := make([][]byte, len(values))
	for index, value := range values {
		result[index] = mustImportHex(value, 65, false)
	}
	return result
}

func unixNanosTime(value string) (time.Time, error) {
	if value == "" || (len(value) > 1 && value[0] == '0') {
		return time.Time{}, errors.New("header observed nanos is not canonical")
	}
	nanos, err := strconv.ParseInt(value, 10, 64)
	if err != nil || nanos <= 0 {
		return time.Time{}, errors.New("header observed nanos is invalid")
	}
	return time.Unix(0, nanos).UTC(), nil
}

func mustJSONUint64(value json.Number) uint64 {
	result, err := strconv.ParseUint(value.String(), 10, 64)
	if err != nil {
		panic(err)
	}
	return result
}

func validateImportProof(
	proof phase8ImportProof,
	envelope phase8ImportEnvelope,
	manifest phase8ReleaseManifest,
) error {
	if proof.ProofID == "" {
		return errors.New("proof ID is required")
	}
	for _, value := range []json.Number{
		proof.ChainID,
		proof.TransactionIndex,
		proof.LogIndex,
		proof.BlockNumber,
		proof.BlockTimestamp,
		proof.FinalityHeadNumber,
		proof.ConfirmationDepth,
	} {
		if _, err := canonicalManifestNumber(value, true); err != nil {
			return err
		}
	}
	for _, value := range []string{
		proof.TransactionHash,
		proof.BlockHash,
		proof.ReceiptsRoot,
		proof.InclusionProofHash,
		proof.EventHash,
		proof.FinalityHeadHash,
		proof.FinalityPolicyHash,
		proof.ObserverAuthorityHash,
		proof.ObserverSignedHeaderCommitment,
		proof.ProofHash,
	} {
		if _, err := importHex(value, 32, false); err != nil {
			return err
		}
	}
	if _, err := importHex(proof.ObserverSignature, -1, false); err != nil {
		return err
	}
	signature := mustImportHex(proof.ObserverSignature, -1, false)
	if len(signature) != ed25519.SignatureSize {
		return errors.New("observer signature must be Ed25519")
	}
	proofABI := mustImportHex(proof.ProofABI, -1, false)
	reconstructed, err := encodeImportProofABI(proof)
	if err != nil || !bytes.Equal(proofABI, reconstructed) {
		return errors.New("proof ABI does not match expanded evidence")
	}
	proofHash := keccak(proofABI)
	if !sameHex(proof.ProofHash, proofHash[:]) {
		return errors.New("proof hash does not bind exact proof ABI")
	}
	domain, err := importProofDomain(proof, envelope, manifest)
	if err != nil {
		return err
	}
	publicKey := mustImportHex(domain.ObserverPublicKey, ed25519.PublicKeySize, false)
	authority := keccak(publicKey)
	if !sameHex(proof.ObserverAuthorityHash, authority[:]) {
		return errors.New("proof observer authority does not bind manifest public key")
	}
	commitment := mustImportHex(
		proof.ObserverSignedHeaderCommitment,
		32,
		false,
	)
	expectedCommitment, err := computeImportObserverCommitment(proof)
	if err != nil || !bytes.Equal(commitment, expectedCommitment[:]) {
		return errors.New("proof observer commitment is not Solidity-canonical")
	}
	if !ed25519.Verify(ed25519.PublicKey(publicKey), commitment, signature) {
		return errors.New("proof observer Ed25519 signature is invalid")
	}
	_, err = importTime(proof.ObservedAt)
	return err
}

func validateImportCertificate(
	certificate phase8ImportCertificate,
	proof phase8ImportProof,
	envelope phase8ImportEnvelope,
	manifest phase8ReleaseManifest,
) error {
	if certificate.CertificateID == "" || certificate.SignerSetVersion == 0 ||
		certificate.SignatureCount < 2 || certificate.SignatureCount > 3 ||
		len(certificate.Signatures) < 2 || len(certificate.Signatures) > 3 ||
		int(certificate.SignatureCount) != len(certificate.Signatures) {
		return errors.New("certificate identity, signer set, or bitmap is invalid")
	}
	if _, err := importHex(certificate.SignerSetHash, 32, false); err != nil {
		return err
	}
	if _, err := importHex(certificate.CertificateHash, 32, false); err != nil {
		return err
	}
	messageID := envelopeMessageID(envelope)
	if !sameHex(certificate.MessageID, messageID[:]) ||
		!sameHex(certificate.SourceProofHash, mustImportHex(proof.ProofHash, 32, false)) {
		return errors.New("certificate does not bind message and exact proof")
	}
	certificateABI := mustImportHex(certificate.CertificateABI, -1, false)
	reconstructed, err := encodeImportCertificateABI(certificate)
	if err != nil || !bytes.Equal(certificateABI, reconstructed) {
		return errors.New("certificate ABI does not match expanded evidence")
	}
	certificateHash := keccak(certificateABI)
	if !sameHex(certificate.CertificateHash, certificateHash[:]) {
		return errors.New("certificate hash does not bind exact certificate ABI")
	}
	evidenceDomain, err := importProofDomain(proof, envelope, manifest)
	if err != nil {
		return err
	}
	evidenceSignerSet := mustManifestHash(evidenceDomain.SignerSet.Hash)
	if !sameHex(certificate.SignerSetHash, evidenceSignerSet[:]) ||
		certificate.SignerSetVersion != uint64(evidenceDomain.SignerSet.Version) {
		return errors.New("certificate signer set does not match evidence domain")
	}
	verificationDomain, err := oppositeImportDomain(proof, envelope, manifest)
	if err != nil {
		return err
	}
	verifier := mustAddress(
		verificationDomain.Contracts["finality_verifier"].Address,
	)
	verificationChainID, _ := canonicalManifestNumber(
		verificationDomain.ChainID,
		false,
	)
	chainWord, _ := wordUint256(verificationChainID)
	proofHash := mustManifestHash(certificate.SourceProofHash)
	digest := abiHash(
		"UNIFIED_SYNTHETIC_FINALITY_V1",
		chainWord,
		wordAddress(verifier),
		wordBytes32(messageID),
		wordBytes32(proofHash),
		wordBytes32(evidenceSignerSet),
		wordUint64(certificate.SignerSetVersion),
	)
	sorted, err := validateSortedAddresses(
		evidenceDomain.SignerSet.SortedAddresses,
	)
	if err != nil {
		return err
	}
	bitmap := []byte("000")
	seen := make(map[[20]byte]struct{}, len(certificate.Signatures))
	for _, encodedSignature := range certificate.Signatures {
		signature := mustImportHex(encodedSignature, 65, false)
		recovered, err := recovery.VerifyEthereumSignature(digest, signature)
		if err != nil {
			return errors.New("certificate ECDSA signature is invalid")
		}
		if _, duplicate := seen[recovered]; duplicate {
			return errors.New("certificate repeats an ECDSA signer")
		}
		seen[recovered] = struct{}{}
		found := false
		for signerIndex, allowed := range sorted {
			if recovered == allowed {
				bitmap[signerIndex] = '1'
				found = true
				break
			}
		}
		if !found {
			return errors.New("certificate ECDSA signer is not manifest-authorized")
		}
	}
	if certificate.SignerBitmap != string(bitmap) {
		return errors.New("certificate signer bitmap does not match recovered signers")
	}
	_, err = importTime(certificate.CertifiedAt)
	return err
}

func importPhase8Flow(
	ctx context.Context,
	runtime *sql.DB,
	observer *sql.DB,
	finality *sql.DB,
	flow phase8ImportFlow,
	manifest phase8ReleaseManifest,
) error {
	if ctx == nil || runtime == nil || observer == nil || finality == nil {
		return errors.New("manifest import requires isolated runtime, observer, and finality roles")
	}
	for _, message := range flow.Messages {
		if err := importPhase8Message(
			ctx,
			runtime,
			observer,
			finality,
			message,
			manifest,
			flow.Economics,
		); err != nil {
			return fmt.Errorf("import message sequence %d: %w", message.Sequence, err)
		}
	}
	return nil
}

func importPhase8Message(
	ctx context.Context,
	runtime *sql.DB,
	observer *sql.DB,
	finality *sql.DB,
	message phase8ImportMessage,
	manifest phase8ReleaseManifest,
	economics phase8FlowEconomics,
) error {
	messageID := mustImportHex(message.Envelope.MessageID, 32, false)
	input, err := derivePhase8SQLImport(message, manifest, economics)
	if err != nil {
		return err
	}
	envelope := input.Envelope
	if _, err := runtime.ExecContext(
		ctx,
		importMessageSQL,
		messageID,
		int64(envelope.SchemaVersion),
		mustImportHex(envelope.ProtocolID, 32, false),
		envelope.SourceChainID.String(),
		mustImportHex(envelope.SourceCoordinator, 20, false),
		mustImportHex(envelope.SourceComponent, 20, false),
		envelope.DestinationChainID.String(),
		mustImportHex(envelope.DestinationCoordinator, 20, false),
		mustImportHex(envelope.DestinationComponent, 20, false),
		mustImportHex(envelope.LaneID, 32, false),
		envelope.SourceNonce.String(),
		mustImportHex(envelope.AggregateID, 32, false),
		int64(envelope.ActionType),
		mustImportHex(envelope.PayloadHash, 32, false),
		mustUnixNumberTime(envelope.CreatedAt),
		mustUnixNumberTime(envelope.ExpiresAt),
		mustImportHex(envelope.RoutePolicyHash, 32, false),
		mustImportHex(envelope.AdapterSetPolicyHash, 32, false),
		mustImportHex(envelope.SourceFinalityPolicyHash, 32, false),
		mustImportHex(envelope.DestinationFinalityPolicyHash, 32, false),
		mustImportHex(envelope.CorrelationID, 32, false),
		mustImportHex(envelope.CausationMessageID, 32, true),
		mustImportHex(envelope.SupersededMessageID, 32, true),
		mustImportHex(input.SerializedEnvelope, -1, false),
		mustUnixNumberTime(envelope.CreatedAt),
	); err != nil {
		return fmt.Errorf("record message: %w", err)
	}
	if err := importProofAndCertificate(
		ctx,
		observer,
		finality,
		messageID,
		input.SourceProof,
		input.SourceCertificate,
	); err != nil {
		return fmt.Errorf("source evidence: %w", err)
	}
	if err := importProofAndCertificate(
		ctx,
		observer,
		finality,
		messageID,
		input.DestinationProof,
		input.DestinationCertificate,
	); err != nil {
		return fmt.Errorf("destination evidence: %w", err)
	}
	for _, attempt := range input.ProviderAttempts {
		var receipt any
		if attempt.ProviderReceiptHash != nil {
			receipt = mustImportHex(*attempt.ProviderReceiptHash, 32, false)
		}
		if _, err := runtime.ExecContext(
			ctx,
			importProviderAttemptSQL,
			messageID,
			attempt.ProviderID,
			int64(attempt.AttemptNumber),
			mustImportHex(attempt.SerializedEnvelopeHash, 32, false),
			mustImportHex(attempt.SourceProofHash, 32, false),
			attempt.Status,
			receipt,
			mustImportTime(attempt.AttemptedAt),
		); err != nil {
			return fmt.Errorf("record provider attempt: %w", err)
		}
	}
	for _, transition := range input.Transitions {
		switch transition.NextState {
		case "EXECUTED":
			execution := input.Execution
			if _, err := runtime.ExecContext(
				ctx,
				importExecutionSQL,
				messageID,
				execution.DestinationChainID.String(),
				mustImportHex(execution.TransactionHash, 32, false),
				execution.LogIndex.String(),
				mustImportHex(execution.ResultHash, 32, false),
				mustImportHex(input.DestinationProof.EventHash, 32, false),
				input.DestinationProof.ProofID,
				input.DestinationCertificate.CertificateID,
				string(input.ActionProjection.Projection),
				mustImportTime(execution.ExecutedAt),
			); err != nil {
				return fmt.Errorf("record execution: %w", err)
			}
		case "ACKNOWLEDGED":
			acknowledgement := input.Acknowledgement
			if _, err := observer.ExecContext(
				ctx,
				importAcknowledgementSQL,
				messageID,
				mustImportHex(acknowledgement.ExecutionResultHash, 32, false),
				mustImportHex(acknowledgement.Commitment, 32, false),
				acknowledgement.DestinationProofID,
				acknowledgement.CertificateID,
				mustImportTime(acknowledgement.AcknowledgedAt),
			); err != nil {
				return fmt.Errorf("record acknowledgement: %w", err)
			}
		}
		var failure any
		if transition.FailureClass != nil {
			failure = *transition.FailureClass
		}
		if _, err := runtime.ExecContext(
			ctx,
			importTransitionSQL,
			messageID,
			int64(transition.ExpectedVersion),
			transition.ExpectedState,
			transition.NextState,
			failure,
			mustImportHex(transition.EvidenceHash, 32, false),
			mustImportTime(transition.OccurredAt),
		); err != nil {
			return fmt.Errorf("transition to %s: %w", transition.NextState, err)
		}
	}
	projection := input.ActionProjection
	if _, err := observer.ExecContext(
		ctx,
		importProjectionSQL,
		messageID,
		string(projection.Projection),
		mustImportTime(projection.ProjectedAt),
	); err != nil {
		return fmt.Errorf("record action projection: %w", err)
	}
	if err := commitPhase8Action(ctx, runtime, messageID, input); err != nil {
		return fmt.Errorf("commit authenticated action economics: %w", err)
	}
	return nil
}

func importProofAndCertificate(
	ctx context.Context,
	observer *sql.DB,
	finality *sql.DB,
	messageID []byte,
	proof phase8ImportProof,
	certificate phase8ImportCertificate,
) error {
	if _, err := observer.ExecContext(
		ctx,
		importProofSQL,
		proof.ProofID,
		messageID,
		proof.ChainID.String(),
		mustImportHex(proof.TransactionHash, 32, false),
		proof.TransactionIndex.String(),
		proof.LogIndex.String(),
		proof.BlockNumber.String(),
		mustImportHex(proof.BlockHash, 32, false),
		mustImportHex(proof.ReceiptsRoot, 32, false),
		mustImportHex(proof.InclusionProofHash, 32, false),
		mustImportHex(proof.EventHash, 32, false),
		proof.FinalityHeadNumber.String(),
		mustImportHex(proof.FinalityHeadHash, 32, false),
		proof.ConfirmationDepth.String(),
		mustImportHex(proof.FinalityPolicyHash, 32, false),
		mustImportHex(proof.ObserverAuthorityHash, 32, false),
		mustImportHex(proof.ObserverSignedHeaderCommitment, 32, false),
		mustImportHex(proof.ObserverSignature, -1, false),
		mustImportHex(proof.ProofHash, 32, false),
		mustImportTime(proof.ObservedAt),
		mustImportHex(proof.RawEvidenceObjectHash, 32, false),
		mustImportHex(proof.ProofABI, -1, false),
	); err != nil {
		return fmt.Errorf("record proof: %w", err)
	}
	if _, err := finality.ExecContext(
		ctx,
		importCertificateSQL,
		certificate.CertificateID,
		messageID,
		proof.ProofID,
		mustImportHex(certificate.SignerSetHash, 32, false),
		int64(certificate.SignerSetVersion),
		certificate.SignerBitmap,
		int64(certificate.SignatureCount),
		mustImportHex(certificate.CertificateHash, 32, false),
		mustImportTime(certificate.CertifiedAt),
		mustImportHex(certificate.CertificateABI, -1, false),
		importCertificateSignatures(certificate.Signatures),
	); err != nil {
		return fmt.Errorf("record certificate: %w", err)
	}
	return nil
}

func computeImportMessageID(envelope phase8ImportEnvelope) ([32]byte, error) {
	sourceChain, err := wordUint256(envelope.SourceChainID.String())
	if err != nil {
		return [32]byte{}, err
	}
	destinationChain, err := wordUint256(envelope.DestinationChainID.String())
	if err != nil {
		return [32]byte{}, err
	}
	sourceCoordinator := mustAddress(envelope.SourceCoordinator)
	sourceComponent := mustAddress(envelope.SourceComponent)
	destinationCoordinator := mustAddress(envelope.DestinationCoordinator)
	destinationComponent := mustAddress(envelope.DestinationComponent)
	return abiHash(
		"UNIFIED_XCHAIN_MESSAGE_V1",
		wordUint64(uint64(envelope.SchemaVersion)),
		wordBytes32(mustManifestHash(envelope.ProtocolID)),
		sourceChain,
		wordAddress(sourceCoordinator),
		wordAddress(sourceComponent),
		destinationChain,
		wordAddress(destinationCoordinator),
		wordAddress(destinationComponent),
		wordBytes32(mustManifestHash(envelope.LaneID)),
		mustUintWord(envelope.SourceNonce),
		wordBytes32(mustManifestHash(envelope.AggregateID)),
		wordUint64(uint64(envelope.ActionType)),
		wordBytes32(mustManifestHash(envelope.PayloadHash)),
		mustTimestampWord(envelope.CreatedAt),
		mustTimestampWord(envelope.ExpiresAt),
		wordBytes32(mustManifestHash(envelope.RoutePolicyHash)),
		wordBytes32(mustManifestHash(envelope.AdapterSetPolicyHash)),
		wordBytes32(mustManifestHash(envelope.SourceFinalityPolicyHash)),
		wordBytes32(mustManifestHash(envelope.DestinationFinalityPolicyHash)),
		wordBytes32(mustManifestHash(envelope.CorrelationID)),
		wordBytes32(mustImportBytes32(envelope.CausationMessageID, true)),
		wordBytes32(mustImportBytes32(envelope.SupersededMessageID, true)),
	), nil
}

func computeImportObserverCommitment(proof phase8ImportProof) ([32]byte, error) {
	return abiHash(
		"UNIFIED_OBSERVER_SIGNED_HEADER_V1",
		wordBytes32(mustManifestHash(proof.BlockHash)),
		mustUintWord(proof.BlockNumber),
		mustUintWord(proof.BlockTimestamp),
		wordBytes32(mustManifestHash(proof.FinalityHeadHash)),
		mustUintWord(proof.FinalityHeadNumber),
		mustUintWord(proof.ConfirmationDepth),
		wordBytes32(mustManifestHash(proof.ObserverAuthorityHash)),
		wordBytes32(mustManifestHash(proof.FinalityPolicyHash)),
	), nil
}

func encodeImportProofABI(proof phase8ImportProof) ([]byte, error) {
	signature, err := importHex(proof.ObserverSignature, -1, false)
	if err != nil {
		return nil, err
	}
	encoded := make([]byte, 0, 19*32)
	encoded = append(encoded, wordUint64(32)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.BlockHash))...)
	encoded = append(encoded, mustUintWord(proof.BlockNumber)...)
	encoded = append(encoded, mustUintWord(proof.BlockTimestamp)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.TransactionHash))...)
	encoded = append(encoded, mustUintWord(proof.TransactionIndex)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.ReceiptsRoot))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.InclusionProofHash))...)
	encoded = append(encoded, mustUintWord(proof.LogIndex)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.EventHash))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.FinalityHeadHash))...)
	encoded = append(encoded, mustUintWord(proof.FinalityHeadNumber)...)
	encoded = append(encoded, mustUintWord(proof.ConfirmationDepth)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.ObserverAuthorityHash))...)
	encoded = append(
		encoded,
		wordBytes32(mustManifestHash(proof.ObserverSignedHeaderCommitment))...,
	)
	encoded = append(encoded, wordUint64(16*32)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(proof.FinalityPolicyHash))...)
	encoded = append(encoded, encodeABIDynamicBytes(signature)...)
	return encoded, nil
}

func encodeImportCertificateABI(
	certificate phase8ImportCertificate,
) ([]byte, error) {
	if len(certificate.Signatures) < 2 || len(certificate.Signatures) > 3 {
		return nil, errors.New("certificate requires two or three signatures")
	}
	signatures := make([][]byte, len(certificate.Signatures))
	for index, value := range certificate.Signatures {
		decoded, err := importHex(value, 65, false)
		if err != nil {
			return nil, err
		}
		signatures[index] = decoded
	}
	tails := make([][]byte, len(signatures))
	for index, signature := range signatures {
		tails[index] = encodeABIDynamicBytes(signature)
	}
	encoded := make([]byte, 0, (10+4*len(signatures))*32)
	encoded = append(encoded, wordUint64(32)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(certificate.MessageID))...)
	encoded = append(
		encoded,
		wordBytes32(mustManifestHash(certificate.SourceProofHash))...,
	)
	encoded = append(encoded, wordBytes32(mustManifestHash(certificate.SignerSetHash))...)
	encoded = append(encoded, wordUint64(certificate.SignerSetVersion)...)
	encoded = append(encoded, wordUint64(5*32)...)
	encoded = append(encoded, wordUint64(uint64(len(signatures)))...)
	offset := uint64(len(signatures) * 32)
	for _, tail := range tails {
		encoded = append(encoded, wordUint64(offset)...)
		offset += uint64(len(tail))
	}
	for _, tail := range tails {
		encoded = append(encoded, tail...)
	}
	return encoded, nil
}

func encodeImportEnvelopePayloadABI(
	envelope phase8ImportEnvelope,
	payload []byte,
) ([]byte, error) {
	sourceChain, err := wordUint256(envelope.SourceChainID.String())
	if err != nil {
		return nil, err
	}
	destinationChain, err := wordUint256(envelope.DestinationChainID.String())
	if err != nil {
		return nil, err
	}
	encoded := make([]byte, 0, 25*32+len(payload))
	encoded = append(encoded, wordUint64(uint64(envelope.SchemaVersion))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.MessageID))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.ProtocolID))...)
	encoded = append(encoded, sourceChain...)
	encoded = append(encoded, wordAddress(mustAddress(envelope.SourceCoordinator))...)
	encoded = append(encoded, wordAddress(mustAddress(envelope.SourceComponent))...)
	encoded = append(encoded, destinationChain...)
	encoded = append(encoded, wordAddress(mustAddress(envelope.DestinationCoordinator))...)
	encoded = append(encoded, wordAddress(mustAddress(envelope.DestinationComponent))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.LaneID))...)
	encoded = append(encoded, mustUintWord(envelope.SourceNonce)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.AggregateID))...)
	encoded = append(encoded, wordUint64(uint64(envelope.ActionType))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.PayloadHash))...)
	encoded = append(encoded, mustUintWord(envelope.CreatedAt)...)
	encoded = append(encoded, mustUintWord(envelope.ExpiresAt)...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.RoutePolicyHash))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.AdapterSetPolicyHash))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.SourceFinalityPolicyHash))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.DestinationFinalityPolicyHash))...)
	encoded = append(encoded, wordBytes32(mustManifestHash(envelope.CorrelationID))...)
	encoded = append(encoded, wordBytes32(mustImportBytes32(envelope.CausationMessageID, true))...)
	encoded = append(encoded, wordBytes32(mustImportBytes32(envelope.SupersededMessageID, true))...)
	encoded = append(encoded, wordUint64(24*32)...)
	encoded = append(encoded, encodeABIDynamicBytes(payload)...)
	return encoded, nil
}

func certificateSignerBitmap(
	certificate phase8ImportCertificate,
	proof phase8ImportProof,
	envelope phase8ImportEnvelope,
	manifest phase8ReleaseManifest,
) (string, error) {
	evidenceDomain, err := importProofDomain(proof, envelope, manifest)
	if err != nil {
		return "", err
	}
	verificationDomain, err := oppositeImportDomain(proof, envelope, manifest)
	if err != nil {
		return "", err
	}
	messageID := envelopeMessageID(envelope)
	evidenceSignerSet := mustManifestHash(evidenceDomain.SignerSet.Hash)
	verificationChainID, err := canonicalManifestNumber(
		verificationDomain.ChainID,
		false,
	)
	if err != nil {
		return "", err
	}
	chainWord, err := wordUint256(verificationChainID)
	if err != nil {
		return "", err
	}
	digest := abiHash(
		"UNIFIED_SYNTHETIC_FINALITY_V1",
		chainWord,
		wordAddress(mustAddress(verificationDomain.Contracts["finality_verifier"].Address)),
		wordBytes32(messageID),
		wordBytes32(mustManifestHash(certificate.SourceProofHash)),
		wordBytes32(evidenceSignerSet),
		wordUint64(certificate.SignerSetVersion),
	)
	sorted, err := validateSortedAddresses(evidenceDomain.SignerSet.SortedAddresses)
	if err != nil {
		return "", err
	}
	bitmap := []byte("000")
	seen := make(map[[20]byte]struct{}, len(certificate.Signatures))
	for _, encodedSignature := range certificate.Signatures {
		signature, err := importHex(encodedSignature, 65, false)
		if err != nil {
			return "", err
		}
		recovered, err := recovery.VerifyEthereumSignature(digest, signature)
		if err != nil {
			return "", errors.New("certificate ECDSA signature is invalid")
		}
		if _, duplicate := seen[recovered]; duplicate {
			return "", errors.New("certificate repeats an ECDSA signer")
		}
		seen[recovered] = struct{}{}
		found := false
		for signerIndex, allowed := range sorted {
			if recovered == allowed {
				bitmap[signerIndex] = '1'
				found = true
				break
			}
		}
		if !found {
			return "", errors.New("certificate ECDSA signer is not manifest-authorized")
		}
	}
	return string(bitmap), nil
}

func computeSourceMessageEventHash(envelope phase8ImportEnvelope) [32]byte {
	return abiHash(
		"UNIFIED_MESSAGE_SENT_V1",
		wordAddress(mustAddress(envelope.SourceCoordinator)),
		wordBytes32(mustManifestHash(envelope.MessageID)),
		wordBytes32(mustManifestHash(envelope.LaneID)),
		mustUintWord(envelope.SourceNonce),
		wordUint64(uint64(envelope.ActionType)),
		wordBytes32(mustManifestHash(envelope.PayloadHash)),
	)
}

func computeAcknowledgementEventHash(
	envelope phase8ImportEnvelope,
	resultHash string,
) [32]byte {
	return abiHash(
		"UNIFIED_XCHAIN_EXECUTION_ACKNOWLEDGEMENT_V1",
		wordAddress(mustAddress(envelope.DestinationCoordinator)),
		wordBytes32(mustManifestHash(envelope.MessageID)),
		wordBytes32(mustManifestHash(resultHash)),
	)
}

func encodeABIDynamicBytes(value []byte) []byte {
	encoded := make([]byte, 0, 32+((len(value)+31)/32)*32)
	encoded = append(encoded, wordUint64(uint64(len(value)))...)
	encoded = append(encoded, value...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	return encoded
}

func importProofDomain(
	proof phase8ImportProof,
	envelope phase8ImportEnvelope,
	manifest phase8ReleaseManifest,
) (phase8ManifestDomain, error) {
	chainID, err := canonicalManifestNumber(proof.ChainID, false)
	if err != nil {
		return phase8ManifestDomain{}, err
	}
	sourceID, _ := canonicalManifestNumber(envelope.SourceChainID, false)
	destinationID, _ := canonicalManifestNumber(envelope.DestinationChainID, false)
	switch chainID {
	case sourceID:
		return manifestDomainByChainID(manifest, sourceID)
	case destinationID:
		return manifestDomainByChainID(manifest, destinationID)
	default:
		return phase8ManifestDomain{}, errors.New("proof chain is outside envelope domains")
	}
}

func oppositeImportDomain(
	proof phase8ImportProof,
	envelope phase8ImportEnvelope,
	manifest phase8ReleaseManifest,
) (phase8ManifestDomain, error) {
	chainID, err := canonicalManifestNumber(proof.ChainID, false)
	if err != nil {
		return phase8ManifestDomain{}, err
	}
	sourceID, _ := canonicalManifestNumber(envelope.SourceChainID, false)
	destinationID, _ := canonicalManifestNumber(envelope.DestinationChainID, false)
	switch chainID {
	case sourceID:
		return manifestDomainByChainID(manifest, destinationID)
	case destinationID:
		return manifestDomainByChainID(manifest, sourceID)
	default:
		return phase8ManifestDomain{}, errors.New("proof chain is outside envelope domains")
	}
}

func manifestDomainByChainID(
	manifest phase8ReleaseManifest,
	chainID string,
) (phase8ManifestDomain, error) {
	for _, domain := range []phase8ManifestDomain{
		manifest.Domains.Home,
		manifest.Domains.Satellite,
	} {
		value, _ := canonicalManifestNumber(domain.ChainID, false)
		if value == chainID {
			return domain, nil
		}
	}
	return phase8ManifestDomain{}, errors.New("manifest domain not found")
}

func envelopeMessageID(envelope phase8ImportEnvelope) [32]byte {
	return mustManifestHash(envelope.MessageID)
}

func mustImportBytes32(value string, allowZero bool) [32]byte {
	raw := mustImportHex(value, 32, allowZero)
	var result [32]byte
	copy(result[:], raw)
	return result
}

func mustUintWord(value json.Number) []byte {
	result, err := wordNonnegativeUint256(value.String())
	if err != nil {
		panic(err)
	}
	return result
}

func mustTimestampWord(value json.Number) []byte {
	return mustUintWord(value)
}

func mustUnixNumberTime(value json.Number) time.Time {
	seconds, err := value.Int64()
	if err != nil || seconds <= 0 {
		panic("invalid Unix timestamp")
	}
	return time.Unix(seconds, 0).UTC()
}

func mustUnixInt64(value json.Number) int64 {
	seconds, err := value.Int64()
	if err != nil || seconds <= 0 {
		panic("invalid Unix timestamp")
	}
	return seconds
}

func unixSecondsRFC3339(seconds int64) string {
	if seconds <= 0 {
		panic("invalid Unix timestamp")
	}
	return time.Unix(seconds, 0).UTC().Format(time.RFC3339Nano)
}

func unixNumberRFC3339(value json.Number) string {
	return unixSecondsRFC3339(mustUnixInt64(value))
}

func sameProviderAttempts(left, right []phase8ProviderAttempt) bool {
	if len(left) != len(right) {
		return false
	}
	leftJSON, leftErr := json.Marshal(left)
	rightJSON, rightErr := json.Marshal(right)
	return leftErr == nil && rightErr == nil && bytes.Equal(leftJSON, rightJSON)
}

func importHex(value string, length int, allowZero bool) ([]byte, error) {
	if value != strings.ToLower(value) || !strings.HasPrefix(value, "0x") {
		return nil, errors.New("value must be lowercase 0x-prefixed hex")
	}
	raw, err := hex.DecodeString(strings.TrimPrefix(value, "0x"))
	if err != nil || (length >= 0 && len(raw) != length) || len(raw) == 0 {
		return nil, errors.New("value has invalid hex length")
	}
	if !allowZero {
		allZero := true
		for _, item := range raw {
			if item != 0 {
				allZero = false
				break
			}
		}
		if allZero {
			return nil, errors.New("value must not be zero")
		}
	}
	return raw, nil
}

func mustImportHex(value string, length int, allowZero bool) []byte {
	raw, err := importHex(value, length, allowZero)
	if err != nil {
		panic(err)
	}
	return raw
}

func importTime(value string) (time.Time, error) {
	result, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return time.Time{}, errors.New("timestamp is not RFC3339")
	}
	return result.UTC(), nil
}

func mustImportTime(value string) time.Time {
	result, err := importTime(value)
	if err != nil {
		panic(err)
	}
	return result
}
