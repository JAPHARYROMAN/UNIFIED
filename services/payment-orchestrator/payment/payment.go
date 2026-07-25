// Package payment implements the synthetic Phase 7A payment-ingress boundary.
// It authenticates provider evidence and emits accounting transitions, but it cannot
// allocate loan debt, release collateral, move funds, or call a provider network.
package payment

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"slices"
	"sync"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
)

const (
	MaxCallbackBytes = 64 * 1024
	callbackDomain   = "UNIFIED_PHASE7A_CALLBACK_V1"
)

var (
	ErrInvalidIntent        = errors.New("invalid payment intent")
	ErrInvalidProvider      = errors.New("invalid payment provider")
	ErrIdempotencyConflict  = errors.New("payment idempotency conflict")
	ErrUnknownPayment       = errors.New("unknown payment")
	ErrUnauthorizedCallback = errors.New("unauthorized provider callback")
	ErrInvalidCallback      = errors.New("invalid provider callback")
	ErrCallbackConflict     = errors.New("provider callback conflict")
	ErrInvalidTransition    = errors.New("invalid payment transition")
	ErrAccounting           = errors.New("payment accounting failed")
	ErrInvalidResolution    = errors.New("invalid quarantine resolution")
	ErrCanonicalPending     = errors.New("canonical settlement outcome is pending")
	ErrCanonicalConfirmed   = errors.New("canonical settlement already confirmed")
	ErrCanonicalPersistence = errors.New("canonical settlement persistence failed")
)

type Rail string

const (
	RailBank Rail = "BANK"
	RailCard Rail = "CARD"
)

type Status string

const (
	StatusCreated     Status = "CREATED"
	StatusProcessing  Status = "PROCESSING"
	StatusProvisional Status = "PROVISIONAL"
	StatusFinal       Status = "FINAL"
	StatusFailed      Status = "FAILED"
	StatusReversed    Status = "REVERSED"
	StatusDisputed    Status = "DISPUTED"
)

type Provider struct {
	ID               string
	Rail             Rail
	PublicKey        ed25519.PublicKey
	Active           bool
	AssetID          string
	SupportsReversal bool
	Version          uint32
}

type Intent struct {
	PaymentID         string
	LegalEntityID     string
	IdempotencyKey    string
	CorrelationID     string
	PayerReference    string
	LoanID            string
	ProviderID        string
	ProviderReference string
	Rail              Rail
	Purpose           string
	AssetID           string
	Units             string
	ExpiresAt         time.Time
	SchemaVersion     uint32
	Status            Status
	Version           uint64
	CreatedAt         time.Time
	UpdatedAt         time.Time
	ProvisionalAt     time.Time
	FinalizedAt       time.Time
	ReversedAt        time.Time
}

// Callback is the only normalized provider payload accepted by the local mock boundary.
// Raw JSON must be the canonical encoding returned by EncodeCallback.
type Callback struct {
	ProviderID        string    `json:"provider_id"`
	ProviderEventID   string    `json:"provider_event_id"`
	PaymentID         string    `json:"payment_id"`
	ProviderReference string    `json:"provider_reference"`
	Status            Status    `json:"status"`
	AssetID           string    `json:"asset_id"`
	Units             string    `json:"units"`
	OccurredAt        time.Time `json:"occurred_at"`
	ExpiresAt         time.Time `json:"expires_at"`
	EvidenceHash      string    `json:"evidence_hash"`
}

type Transition struct {
	Payment         Intent
	From            Status
	To              Status
	ProviderEventID string
	OccurredAt      time.Time
	ReceivedAt      time.Time
	EvidenceHash    string
}

// Accounting is the narrow authority boundary between provider evidence and journals.
type Accounting interface {
	Apply(Transition) ([]string, error)
}

type CallbackResult struct {
	ProviderID      string
	ProviderEventID string
	RawHash         string
	Payment         Intent
	JournalIDs      []string
	Replayed        bool
	Disposition     string
}

type RawCallback struct {
	IngressID       uint64
	ProviderID      string
	ProviderEventID string
	RawPayload      []byte
	RawHash         string
	SignatureHash   string
	ReceivedAt      time.Time
}

type Quarantine struct {
	QuarantineID       string
	ProviderID         string
	ProviderEventID    string
	PaymentID          string
	RawHash            string
	EvidenceHash       string
	ReasonCode         string
	ReceivedAt         time.Time
	Owner              string
	ResolutionDeadline time.Time
}

type QuarantineResolution struct {
	ResolutionID                 string
	QuarantineID                 string
	CanonicalFailureEvidenceHash string
	EvidenceHash                 string
	ResolvedBy                   string
	ResolvedAt                   time.Time
}

type CanonicalReversalResolutionRequest struct {
	QuarantineID           string
	ResolutionID           string
	PaymentID              string
	AllocationID           string
	InstructionDigest      string
	FailureProof           chainprojection.VerifiedTransactionFailure
	ResolutionEvidenceHash string
	ResolvedBy             string
	ResolvedAt             time.Time
}

type CanonicalIncident struct {
	IncidentID        string
	PaymentID         string
	AllocationID      string
	ClaimDigest       string
	ProviderID        string
	ProviderEventID   string
	ProviderReference string
	RawHash           string
	EvidenceHash      string
	ReasonCode        string
	OccurredAt        time.Time
	ReceivedAt        time.Time
}

type storedEvent struct {
	rawHash string
	result  CallbackResult
	err     error
}

type pendingCanonicalReversal struct {
	eventKey      string
	ingressID     uint64
	callback      Callback
	rawHash       string
	signatureHash string
	receivedAt    time.Time
	claim         allocationmode.Claim
}

type CanonicalReversalRecord struct {
	QuarantineID         string
	ResolutionID         string
	IngressID            uint64
	PaymentID            string
	AllocationID         string
	InstructionDigest    string
	ProviderID           string
	ProviderEventID      string
	ReversalEventID      string
	ProviderReference    string
	AssetID              string
	Units                string
	RawHash              string
	SignatureHash        string
	CallbackEvidenceHash string
	CallbackExpiresAt    time.Time
	FailureProof         chainprojection.VerifiedTransactionFailure
	ResolutionEvidence   string
	ResolvedBy           string
	OccurredAt           time.Time
	ReceivedAt           time.Time
}

type CanonicalReversalResolution struct {
	JournalIDs          []string
	FailureEvidenceHash string
}

// CanonicalReversalResolutionRecord is the durable result of one canonical
// reversal resolution. It is returned only after the coordinator has matched
// the caller's complete resolution request to the stored request digest.
type CanonicalReversalResolutionRecord struct {
	QuarantineID                 string
	ResolutionID                 string
	PaymentID                    string
	AllocationID                 string
	InstructionDigest            string
	ProviderID                   string
	ProviderEventID              string
	ProviderReference            string
	AssetID                      string
	Units                        string
	RawHash                      string
	RequestDigest                string
	CanonicalFailureEvidenceHash string
	ResolutionEvidenceHash       string
	ResolvedBy                   string
	ResolvedAt                   time.Time
	JournalIDs                   []string
}

// CanonicalReversalConsumption records that a finalized canonical transaction
// won the race with a previously quarantined provider reversal. The Phase 7A
// payment remains FINAL and the callback becomes an owned contradiction
// incident; it is never applied as a reversal.
type CanonicalReversalConsumption struct {
	QuarantineID           string
	IngressID              uint64
	PaymentID              string
	AllocationID           string
	InstructionDigest      string
	ProviderID             string
	ProviderEventID        string
	ProviderReference      string
	AssetID                string
	Units                  string
	RawHash                string
	SignatureHash          string
	CallbackEvidenceHash   string
	CallbackExpiresAt      time.Time
	CallbackOccurredAt     time.Time
	CallbackReceivedAt     time.Time
	ResolutionID           string
	ResolutionEvidenceHash string
	ResolvedBy             string
	ResolvedAt             time.Time
	GatewayEventID         string
	GatewayTransactionHash string
	GatewayRawPayloadHash  string
	FinalityEvidenceHash   string
}

// CanonicalReversalCoordinator is implemented by the durable Phase 7C
// coordinator without creating a payment<->settlement import cycle.
type CanonicalReversalCoordinator interface {
	HandleProviderReversal(
		record CanonicalReversalRecord,
		commit func() error,
	) (allocationmode.Claim, allocationmode.ReversalDisposition, error)
	ResolveProviderReversal(
		record CanonicalReversalRecord,
		localFallback func() ([]string, error),
	) (CanonicalReversalResolution, error)
	ResolvedProviderReversal(
		request CanonicalReversalResolutionRequest,
	) (CanonicalReversalResolutionRecord, bool, error)
	PendingProviderReversals() []CanonicalReversalRecord
	ConsumedProviderReversals() []CanonicalReversalConsumption
}

type Orchestrator struct {
	mu                    sync.RWMutex
	providers             map[string]Provider
	payments              map[string]Intent
	intentKeys            map[string]string
	intentHashes          map[string]string
	events                map[string]storedEvent
	rawCallbacks          []RawCallback
	quarantines           []Quarantine
	canonicalIncidents    []CanonicalIncident
	quarantineResolutions map[string]QuarantineResolution
	pendingReversals      map[string]pendingCanonicalReversal
	consumedReversals     map[string]CanonicalReversalConsumption
	accounting            Accounting
	modes                 *allocationmode.Registry
	canonical             CanonicalReversalCoordinator
}

// New requires the allocation-mode registry shared by the callback,
// allocation, and canonical-settlement paths. No constructor creates a
// private registry.
func New(
	providers []Provider,
	accounting Accounting,
	modes *allocationmode.Registry,
	canonical CanonicalReversalCoordinator,
) (*Orchestrator, error) {
	if len(providers) == 0 || accounting == nil || modes == nil || canonical == nil {
		return nil, ErrInvalidProvider
	}
	configured := make(map[string]Provider, len(providers))
	for _, provider := range providers {
		if provider.ID == "" || !validRail(provider.Rail) ||
			len(provider.PublicKey) != ed25519.PublicKeySize || provider.AssetID == "" ||
			provider.Version == 0 {
			return nil, ErrInvalidProvider
		}
		if _, exists := configured[provider.ID]; exists {
			return nil, ErrInvalidProvider
		}
		provider.PublicKey = slices.Clone(provider.PublicKey)
		configured[provider.ID] = provider
	}
	orchestrator := &Orchestrator{
		providers:             configured,
		payments:              make(map[string]Intent),
		intentKeys:            make(map[string]string),
		intentHashes:          make(map[string]string),
		events:                make(map[string]storedEvent),
		quarantineResolutions: make(map[string]QuarantineResolution),
		pendingReversals:      make(map[string]pendingCanonicalReversal),
		consumedReversals:     make(map[string]CanonicalReversalConsumption),
		accounting:            accounting,
		modes:                 modes,
		canonical:             canonical,
	}
	for _, record := range canonical.PendingProviderReversals() {
		if record.QuarantineID == "" || record.IngressID == 0 ||
			record.PaymentID == "" ||
			record.AllocationID == "" || record.InstructionDigest == "" ||
			record.ProviderID == "" || record.ProviderEventID == "" ||
			record.AssetID == "" || record.Units == "" ||
			record.RawHash == "" || record.SignatureHash == "" ||
			record.CallbackEvidenceHash == "" ||
			record.CallbackExpiresAt.IsZero() || record.OccurredAt.IsZero() ||
			record.ReceivedAt.IsZero() {
			return nil, ErrCanonicalPersistence
		}
		if _, exists := configured[record.ProviderID]; !exists {
			return nil, ErrCanonicalPersistence
		}
		if _, exists := orchestrator.pendingReversals[record.QuarantineID]; exists {
			return nil, ErrCanonicalPersistence
		}
		callback := Callback{
			ProviderID:        record.ProviderID,
			ProviderEventID:   record.ProviderEventID,
			PaymentID:         record.PaymentID,
			ProviderReference: record.ProviderReference,
			Status:            StatusReversed,
			AssetID:           record.AssetID,
			Units:             record.Units,
			OccurredAt:        record.OccurredAt.UTC(),
			ExpiresAt:         record.CallbackExpiresAt.UTC(),
			EvidenceHash:      record.CallbackEvidenceHash,
		}
		orchestrator.quarantines = append(orchestrator.quarantines, Quarantine{
			QuarantineID:       record.QuarantineID,
			ProviderID:         record.ProviderID,
			ProviderEventID:    record.ProviderEventID,
			PaymentID:          record.PaymentID,
			RawHash:            record.RawHash,
			EvidenceHash:       record.CallbackEvidenceHash,
			ReasonCode:         "CANONICAL_SETTLEMENT_SUBMITTED",
			ReceivedAt:         record.ReceivedAt.UTC(),
			Owner:              "payment-operations",
			ResolutionDeadline: record.ReceivedAt.UTC().Add(24 * time.Hour),
		})
		orchestrator.pendingReversals[record.QuarantineID] =
			pendingCanonicalReversal{
				eventKey:      record.ProviderID + "\x00" + record.ProviderEventID,
				ingressID:     record.IngressID,
				callback:      callback,
				rawHash:       record.RawHash,
				signatureHash: record.SignatureHash,
				receivedAt:    record.ReceivedAt.UTC(),
				claim: allocationmode.Claim{
					PaymentID:    record.PaymentID,
					AllocationID: record.AllocationID,
					Mode:         allocationmode.ModeCanonicalGateway,
					Digest:       record.InstructionDigest,
					State:        allocationmode.CanonicalQuarantined,
				},
			}
	}
	if err := orchestrator.refreshCanonicalConsumptionsLocked(); err != nil {
		return nil, err
	}
	return orchestrator, nil
}

// RestorePayment explicitly supplies the Phase 7A aggregate required to resume
// a pending reversal after process restart. Canonical metadata is restored by
// New; the payment aggregate remains owned by the Phase 7A repository.
func (orchestrator *Orchestrator) RestorePayment(intent Intent) error {
	if orchestrator == nil || intent.PaymentID == "" || intent.ProviderID == "" ||
		intent.AssetID == "" || intent.Units == "" || intent.Version == 0 ||
		intent.CreatedAt.IsZero() || intent.UpdatedAt.IsZero() {
		return ErrInvalidIntent
	}
	orchestrator.mu.Lock()
	defer orchestrator.mu.Unlock()
	provider, exists := orchestrator.providers[intent.ProviderID]
	if !exists || provider.Rail != intent.Rail ||
		provider.AssetID != intent.AssetID {
		return ErrInvalidIntent
	}
	if existing, exists := orchestrator.payments[intent.PaymentID]; exists {
		if existing == intent {
			return nil
		}
		return ErrIdempotencyConflict
	}
	orchestrator.payments[intent.PaymentID] = intent
	if err := orchestrator.applyCanonicalConsumptionsLocked(intent.PaymentID); err != nil {
		delete(orchestrator.payments, intent.PaymentID)
		return err
	}
	return nil
}

func (orchestrator *Orchestrator) CreateIntent(intent Intent, now time.Time) (Intent, error) {
	if orchestrator == nil || now.IsZero() || intent.PaymentID == "" ||
		intent.LegalEntityID == "" || intent.IdempotencyKey == "" ||
		intent.CorrelationID == "" || intent.PayerReference == "" ||
		intent.ProviderID == "" || intent.ProviderReference != "" ||
		intent.Purpose == "" || intent.AssetID == "" ||
		intent.SchemaVersion == 0 || !intent.ExpiresAt.After(now) ||
		intent.Status != "" || intent.Version != 0 || !intent.CreatedAt.IsZero() ||
		!intent.UpdatedAt.IsZero() || !intent.ProvisionalAt.IsZero() ||
		!intent.FinalizedAt.IsZero() || !intent.ReversedAt.IsZero() {
		return Intent{}, ErrInvalidIntent
	}
	units, ok := positiveInteger(intent.Units)
	if !ok || units.Sign() <= 0 {
		return Intent{}, ErrInvalidIntent
	}

	orchestrator.mu.Lock()
	defer orchestrator.mu.Unlock()
	provider, exists := orchestrator.providers[intent.ProviderID]
	if !exists || !provider.Active || provider.Rail != intent.Rail ||
		provider.AssetID != intent.AssetID {
		return Intent{}, ErrInvalidIntent
	}
	contentHash := intentHash(intent)
	scope := intent.LegalEntityID + "\x00" + intent.IdempotencyKey
	if paymentID, exists := orchestrator.intentKeys[scope]; exists {
		if orchestrator.intentHashes[paymentID] != contentHash {
			return Intent{}, ErrIdempotencyConflict
		}
		return orchestrator.payments[paymentID], nil
	}
	if _, exists := orchestrator.payments[intent.PaymentID]; exists {
		return Intent{}, ErrIdempotencyConflict
	}
	intent.Status = StatusCreated
	intent.Version = 1
	intent.CreatedAt = now.UTC()
	intent.UpdatedAt = now.UTC()
	orchestrator.payments[intent.PaymentID] = intent
	orchestrator.intentKeys[scope] = intent.PaymentID
	orchestrator.intentHashes[intent.PaymentID] = contentHash
	return intent, nil
}

func EncodeCallback(callback Callback) ([]byte, error) {
	if callback.ProviderID == "" || callback.ProviderEventID == "" ||
		callback.PaymentID == "" || callback.ProviderReference == "" ||
		!callbackStatus(callback.Status) || callback.AssetID == "" ||
		callback.OccurredAt.IsZero() || callback.ExpiresAt.IsZero() ||
		callback.OccurredAt.After(callback.ExpiresAt) || callback.EvidenceHash == "" {
		return nil, ErrInvalidCallback
	}
	units, ok := positiveInteger(callback.Units)
	if !ok || units.Sign() <= 0 {
		return nil, ErrInvalidCallback
	}
	encoded, err := json.Marshal(callback)
	if err != nil {
		return nil, ErrInvalidCallback
	}
	return encoded, nil
}

// SigningMessage returns the domain-separated digest signed by synthetic providers.
func SigningMessage(raw []byte) []byte {
	digest := sha256.New()
	_, _ = digest.Write([]byte(callbackDomain))
	_, _ = digest.Write([]byte{0})
	_, _ = digest.Write(raw)
	return digest.Sum(nil)
}

func (orchestrator *Orchestrator) IngestCallback(
	providerID string,
	providerEventID string,
	raw []byte,
	signature []byte,
	receivedAt time.Time,
) (CallbackResult, error) {
	if orchestrator == nil || receivedAt.IsZero() {
		return CallbackResult{}, ErrInvalidCallback
	}
	rawHash := hashBytes(raw)
	signatureHash := hashBytes(signature)
	retainedRaw := raw
	if len(raw) > MaxCallbackBytes {
		retainedRaw = nil
	}

	orchestrator.mu.Lock()
	defer orchestrator.mu.Unlock()
	if err := orchestrator.refreshCanonicalConsumptionsLocked(); err != nil {
		return CallbackResult{}, err
	}
	ingressID := uint64(len(orchestrator.rawCallbacks) + 1)
	orchestrator.rawCallbacks = append(orchestrator.rawCallbacks, RawCallback{
		IngressID:       ingressID,
		ProviderID:      providerID,
		ProviderEventID: providerEventID,
		RawPayload:      slices.Clone(retainedRaw),
		RawHash:         rawHash,
		SignatureHash:   signatureHash,
		ReceivedAt:      receivedAt.UTC(),
	})
	if providerID == "" || providerEventID == "" || len(raw) == 0 ||
		len(raw) > MaxCallbackBytes {
		orchestrator.quarantine(providerID, providerEventID, "", rawHash, "",
			"CALLBACK_ENVELOPE_INVALID", receivedAt)
		return CallbackResult{}, ErrInvalidCallback
	}
	provider, exists := orchestrator.providers[providerID]
	if !exists || !provider.Active ||
		!ed25519.Verify(provider.PublicKey, SigningMessage(raw), signature) {
		orchestrator.quarantine(providerID, providerEventID, "", rawHash, "",
			"CALLBACK_AUTHENTICATION_FAILED", receivedAt)
		return CallbackResult{}, ErrUnauthorizedCallback
	}
	callback, err := decodeCallback(raw)
	if err != nil || callback.ProviderID != providerID ||
		callback.ProviderEventID != providerEventID ||
		callback.AssetID != provider.AssetID || receivedAt.After(callback.ExpiresAt) {
		orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
			callback.EvidenceHash, "CALLBACK_BINDING_INVALID", receivedAt)
		return CallbackResult{}, ErrInvalidCallback
	}

	eventKey := providerID + "\x00" + providerEventID
	if existing, exists := orchestrator.events[eventKey]; exists {
		if existing.rawHash != rawHash {
			orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
				callback.EvidenceHash, "CALLBACK_EVENT_CONFLICT", receivedAt)
			return CallbackResult{}, ErrCallbackConflict
		}
		replayed := cloneResult(existing.result)
		replayed.Replayed = true
		return replayed, existing.err
	}

	current, exists := orchestrator.payments[callback.PaymentID]
	if !exists {
		orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
			callback.EvidenceHash, "UNKNOWN_PAYMENT", receivedAt)
		return CallbackResult{}, ErrUnknownPayment
	}
	if current.ProviderID != providerID || current.Rail != provider.Rail ||
		current.AssetID != callback.AssetID || current.Units != callback.Units ||
		(current.ProviderReference != "" &&
			current.ProviderReference != callback.ProviderReference) ||
		(current.Status == StatusCreated && receivedAt.After(current.ExpiresAt)) {
		orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
			callback.EvidenceHash, "PAYMENT_BINDING_INVALID", receivedAt)
		return CallbackResult{}, ErrInvalidCallback
	}
	if callback.Status == StatusReversed && !provider.SupportsReversal {
		orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
			callback.EvidenceHash, "REVERSAL_UNSUPPORTED", receivedAt)
		return CallbackResult{}, ErrInvalidTransition
	}
	if callback.Status == StatusReversed && current.Status == StatusReversed {
		orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
			callback.EvidenceHash, "CALLBACK_ORDER_INVALID", receivedAt)
		return CallbackResult{}, ErrInvalidTransition
	}
	if callback.Status != current.Status &&
		!allowedTransition(current.Status, callback.Status) {
		orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
			callback.EvidenceHash, "CALLBACK_ORDER_INVALID", receivedAt)
		return CallbackResult{}, ErrInvalidTransition
	}
	if callback.Status == StatusReversed {
		next := current
		next.Status = StatusReversed
		next.Version++
		next.UpdatedAt = receivedAt.UTC()
		next.ReversedAt = receivedAt.UTC()
		if next.ProviderReference == "" {
			next.ProviderReference = callback.ProviderReference
		}
		var journalIDs []string
		reversalCommitted := false
		reversalRecord := CanonicalReversalRecord{
			QuarantineID:    fmt.Sprintf("quarantine-%06d", len(orchestrator.quarantines)+1),
			IngressID:       ingressID,
			PaymentID:       callback.PaymentID,
			ProviderID:      callback.ProviderID,
			ProviderEventID: callback.ProviderEventID,
			ReversalEventID: canonicalPaymentEventID(
				callback.ProviderID,
				callback.ProviderEventID,
			),
			ProviderReference:    callback.ProviderReference,
			AssetID:              callback.AssetID,
			Units:                callback.Units,
			RawHash:              rawHash,
			SignatureHash:        signatureHash,
			CallbackEvidenceHash: callback.EvidenceHash,
			CallbackExpiresAt:    callback.ExpiresAt.UTC(),
			OccurredAt:           callback.OccurredAt.UTC(),
			ReceivedAt:           receivedAt.UTC(),
		}
		claim, disposition, err := orchestrator.canonical.HandleProviderReversal(
			reversalRecord,
			func() error {
				var applyErr error
				journalIDs, applyErr = orchestrator.accounting.Apply(Transition{
					Payment:         next,
					From:            current.Status,
					To:              StatusReversed,
					ProviderEventID: callback.ProviderEventID,
					OccurredAt:      callback.OccurredAt.UTC(),
					ReceivedAt:      receivedAt.UTC(),
					EvidenceHash:    callback.EvidenceHash,
				})
				if applyErr != nil {
					return fmt.Errorf("%w: %v", ErrAccounting, applyErr)
				}
				reversalCommitted = true
				return nil
			},
		)
		if err != nil {
			return CallbackResult{}, errors.Join(ErrCanonicalPersistence, err)
		}
		switch disposition {
		case allocationmode.ReversalQuarantined:
			quarantine := orchestrator.quarantine(
				providerID,
				providerEventID,
				callback.PaymentID,
				rawHash,
				callback.EvidenceHash,
				"CANONICAL_SETTLEMENT_SUBMITTED",
				receivedAt,
			)
			result := CallbackResult{
				ProviderID:      providerID,
				ProviderEventID: providerEventID,
				RawHash:         rawHash,
				Payment:         current,
				Disposition:     "QUARANTINED",
			}
			orchestrator.events[eventKey] = storedEvent{
				rawHash: rawHash,
				result:  result,
				err:     ErrCanonicalPending,
			}
			orchestrator.pendingReversals[quarantine.QuarantineID] =
				pendingCanonicalReversal{
					eventKey:      eventKey,
					ingressID:     ingressID,
					callback:      callback,
					rawHash:       rawHash,
					signatureHash: signatureHash,
					receivedAt:    receivedAt.UTC(),
					claim:         claim,
				}
			return cloneResult(result), ErrCanonicalPending
		case allocationmode.ReversalIncident:
			incident := CanonicalIncident{
				IncidentID: fmt.Sprintf(
					"canonical-incident-%06d",
					len(orchestrator.canonicalIncidents)+1,
				),
				PaymentID:         callback.PaymentID,
				AllocationID:      claim.AllocationID,
				ClaimDigest:       claim.Digest,
				ProviderID:        providerID,
				ProviderEventID:   providerEventID,
				ProviderReference: callback.ProviderReference,
				RawHash:           rawHash,
				EvidenceHash:      callback.EvidenceHash,
				ReasonCode:        "PROVIDER_CONTRADICTION_AFTER_CANONICAL_SETTLEMENT",
				OccurredAt:        callback.OccurredAt.UTC(),
				ReceivedAt:        receivedAt.UTC(),
			}
			orchestrator.canonicalIncidents = append(
				orchestrator.canonicalIncidents,
				incident,
			)
			result := CallbackResult{
				ProviderID:      providerID,
				ProviderEventID: providerEventID,
				RawHash:         rawHash,
				Payment:         current,
				Disposition:     "INCIDENT",
			}
			orchestrator.events[eventKey] = storedEvent{
				rawHash: rawHash,
				result:  result,
				err:     ErrCanonicalConfirmed,
			}
			return cloneResult(result), ErrCanonicalConfirmed
		case allocationmode.ReversalUnclaimed,
			allocationmode.ReversalSynthetic,
			allocationmode.ReversalReleased:
			if !reversalCommitted {
				return CallbackResult{}, ErrCanonicalPersistence
			}
			result := CallbackResult{
				ProviderID:      providerID,
				ProviderEventID: providerEventID,
				RawHash:         rawHash,
				Payment:         next,
				JournalIDs:      slices.Clone(journalIDs),
				Disposition:     string(disposition),
			}
			orchestrator.payments[next.PaymentID] = next
			orchestrator.events[eventKey] = storedEvent{
				rawHash: rawHash,
				result:  result,
			}
			return cloneResult(result), nil
		}
	}

	next := current
	journalIDs := []string(nil)
	if callback.Status != current.Status {
		next.Status = callback.Status
		next.Version++
		next.UpdatedAt = receivedAt.UTC()
		if next.ProviderReference == "" {
			next.ProviderReference = callback.ProviderReference
		}
		switch callback.Status {
		case StatusProvisional:
			next.ProvisionalAt = receivedAt.UTC()
		case StatusFinal:
			next.FinalizedAt = receivedAt.UTC()
		case StatusReversed:
			next.ReversedAt = receivedAt.UTC()
		}
		if accountingTransition(callback.Status) {
			journalIDs, err = orchestrator.accounting.Apply(Transition{
				Payment:         next,
				From:            current.Status,
				To:              callback.Status,
				ProviderEventID: callback.ProviderEventID,
				OccurredAt:      callback.OccurredAt.UTC(),
				ReceivedAt:      receivedAt.UTC(),
				EvidenceHash:    callback.EvidenceHash,
			})
			if err != nil {
				return CallbackResult{}, fmt.Errorf("%w: %v", ErrAccounting, err)
			}
		}
		orchestrator.payments[next.PaymentID] = next
	}
	result := CallbackResult{
		ProviderID:      providerID,
		ProviderEventID: providerEventID,
		RawHash:         rawHash,
		Payment:         next,
		JournalIDs:      slices.Clone(journalIDs),
	}
	orchestrator.events[eventKey] = storedEvent{rawHash: rawHash, result: result}
	return cloneResult(result), nil
}

// ResolveCanonicalReversal commits a quarantined submitted reversal through
// the ordinary Phase 7A accounting path only after a canonical failure proof
// is supplied. The registry keeps canonical retry blocked while this method is
// pending and creates a permanent tombstone in the same critical section as
// the payment transition.
func (orchestrator *Orchestrator) ResolveCanonicalReversal(
	request CanonicalReversalResolutionRequest,
) (CallbackResult, QuarantineResolution, error) {
	if orchestrator == nil || request.QuarantineID == "" ||
		request.ResolutionID == "" || request.PaymentID == "" ||
		request.AllocationID == "" || request.InstructionDigest == "" ||
		request.ResolutionEvidenceHash == "" || request.ResolvedBy == "" ||
		request.ResolvedAt.IsZero() {
		return CallbackResult{}, QuarantineResolution{}, ErrInvalidResolution
	}
	orchestrator.mu.Lock()
	defer orchestrator.mu.Unlock()
	if err := orchestrator.refreshCanonicalConsumptionsLocked(); err != nil {
		return CallbackResult{}, QuarantineResolution{}, err
	}
	if replay, exists, err := orchestrator.canonical.ResolvedProviderReversal(
		request,
	); err != nil {
		return CallbackResult{}, QuarantineResolution{},
			errors.Join(ErrInvalidResolution, err)
	} else if exists {
		current, paymentExists := orchestrator.payments[request.PaymentID]
		if !paymentExists ||
			current.ProviderID != replay.ProviderID ||
			current.AssetID != replay.AssetID ||
			current.Units != replay.Units ||
			(current.ProviderReference != "" &&
				current.ProviderReference != replay.ProviderReference) {
			return CallbackResult{}, QuarantineResolution{}, ErrInvalidTransition
		}
		next := current
		switch current.Status {
		case StatusFinal:
			next.Status = StatusReversed
			next.Version++
			next.UpdatedAt = replay.ResolvedAt.UTC()
			next.ReversedAt = replay.ResolvedAt.UTC()
			if next.ProviderReference == "" {
				next.ProviderReference = replay.ProviderReference
			}
		case StatusReversed:
			if !current.ReversedAt.Equal(replay.ResolvedAt.UTC()) ||
				!current.UpdatedAt.Equal(replay.ResolvedAt.UTC()) {
				return CallbackResult{}, QuarantineResolution{},
					ErrInvalidTransition
			}
		default:
			return CallbackResult{}, QuarantineResolution{},
				ErrInvalidTransition
		}
		resolution := QuarantineResolution{
			ResolutionID:                 replay.ResolutionID,
			QuarantineID:                 replay.QuarantineID,
			CanonicalFailureEvidenceHash: replay.CanonicalFailureEvidenceHash,
			EvidenceHash:                 replay.ResolutionEvidenceHash,
			ResolvedBy:                   replay.ResolvedBy,
			ResolvedAt:                   replay.ResolvedAt.UTC(),
		}
		result := CallbackResult{
			ProviderID:      replay.ProviderID,
			ProviderEventID: replay.ProviderEventID,
			RawHash:         replay.RawHash,
			Payment:         next,
			JournalIDs:      slices.Clone(replay.JournalIDs),
			Replayed:        true,
			Disposition:     "REVERSED",
		}
		orchestrator.payments[next.PaymentID] = next
		orchestrator.events[replay.ProviderID+"\x00"+replay.ProviderEventID] =
			storedEvent{
				rawHash: replay.RawHash,
				result:  result,
			}
		orchestrator.quarantineResolutions[request.QuarantineID] = resolution
		delete(orchestrator.pendingReversals, request.QuarantineID)
		return result, resolution, nil
	}
	if _, exists := orchestrator.quarantineResolutions[request.QuarantineID]; exists {
		return CallbackResult{}, QuarantineResolution{}, ErrInvalidResolution
	}
	pending, exists := orchestrator.pendingReversals[request.QuarantineID]
	if !exists || pending.claim.PaymentID != request.PaymentID ||
		pending.claim.AllocationID != request.AllocationID ||
		pending.claim.Digest != request.InstructionDigest ||
		request.ResolvedAt.Before(pending.receivedAt) {
		return CallbackResult{}, QuarantineResolution{}, ErrInvalidResolution
	}
	current, exists := orchestrator.payments[request.PaymentID]
	if !exists || current.Status != StatusFinal {
		return CallbackResult{}, QuarantineResolution{}, ErrInvalidTransition
	}

	var result CallbackResult
	var resolution QuarantineResolution
	record := CanonicalReversalRecord{
		QuarantineID:      request.QuarantineID,
		ResolutionID:      request.ResolutionID,
		IngressID:         pending.ingressID,
		PaymentID:         request.PaymentID,
		AllocationID:      request.AllocationID,
		InstructionDigest: request.InstructionDigest,
		ProviderID:        pending.callback.ProviderID,
		ProviderEventID:   pending.callback.ProviderEventID,
		ReversalEventID: canonicalPaymentEventID(
			pending.callback.ProviderID,
			pending.callback.ProviderEventID,
		),
		ProviderReference:    pending.callback.ProviderReference,
		AssetID:              pending.callback.AssetID,
		Units:                pending.callback.Units,
		RawHash:              pending.rawHash,
		SignatureHash:        pending.signatureHash,
		CallbackEvidenceHash: pending.callback.EvidenceHash,
		CallbackExpiresAt:    pending.callback.ExpiresAt.UTC(),
		FailureProof:         request.FailureProof,
		ResolutionEvidence:   request.ResolutionEvidenceHash,
		ResolvedBy:           request.ResolvedBy,
		OccurredAt:           pending.callback.OccurredAt.UTC(),
		ReceivedAt:           request.ResolvedAt.UTC(),
	}
	next := current
	next.Status = StatusReversed
	next.Version++
	next.UpdatedAt = request.ResolvedAt.UTC()
	next.ReversedAt = request.ResolvedAt.UTC()
	canonicalResolution, err := orchestrator.canonical.ResolveProviderReversal(
		record,
		func() ([]string, error) {
			journalIDs, applyErr := orchestrator.accounting.Apply(Transition{
				Payment:         next,
				From:            current.Status,
				To:              StatusReversed,
				ProviderEventID: pending.callback.ProviderEventID,
				OccurredAt:      pending.callback.OccurredAt.UTC(),
				ReceivedAt:      pending.receivedAt,
				EvidenceHash:    pending.callback.EvidenceHash,
			})
			if applyErr != nil {
				return nil, fmt.Errorf("%w: %v", ErrAccounting, applyErr)
			}
			return journalIDs, nil
		},
	)
	if err == nil {
		resolution = QuarantineResolution{
			ResolutionID:                 request.ResolutionID,
			QuarantineID:                 request.QuarantineID,
			CanonicalFailureEvidenceHash: canonicalResolution.FailureEvidenceHash,
			EvidenceHash:                 request.ResolutionEvidenceHash,
			ResolvedBy:                   request.ResolvedBy,
			ResolvedAt:                   request.ResolvedAt.UTC(),
		}
		result = CallbackResult{
			ProviderID:      pending.callback.ProviderID,
			ProviderEventID: pending.callback.ProviderEventID,
			RawHash:         pending.rawHash,
			Payment:         next,
			JournalIDs:      slices.Clone(canonicalResolution.JournalIDs),
			Disposition:     "REVERSED",
		}
	}
	if err != nil {
		return CallbackResult{}, QuarantineResolution{}, err
	}
	orchestrator.payments[result.Payment.PaymentID] = result.Payment
	orchestrator.events[pending.eventKey] = storedEvent{
		rawHash: pending.rawHash,
		result:  result,
	}
	orchestrator.quarantineResolutions[request.QuarantineID] = resolution
	delete(orchestrator.pendingReversals, request.QuarantineID)
	return cloneResult(result), resolution, nil
}

func (orchestrator *Orchestrator) refreshCanonicalConsumptionsLocked() error {
	for _, consumption := range orchestrator.canonical.ConsumedProviderReversals() {
		if !validCanonicalConsumption(consumption) {
			return ErrCanonicalPersistence
		}
		if _, exists := orchestrator.providers[consumption.ProviderID]; !exists {
			return ErrCanonicalPersistence
		}
		if existing, exists := orchestrator.consumedReversals[consumption.QuarantineID]; exists {
			if existing != consumption {
				return ErrCanonicalPersistence
			}
			if err := orchestrator.applyCanonicalConsumptionsLocked(
				consumption.PaymentID,
			); err != nil {
				return err
			}
			continue
		}
		orchestrator.consumedReversals[consumption.QuarantineID] = consumption
		delete(orchestrator.pendingReversals, consumption.QuarantineID)
		quarantineExists := false
		for _, quarantine := range orchestrator.quarantines {
			if quarantine.QuarantineID == consumption.QuarantineID {
				quarantineExists = true
				break
			}
		}
		if !quarantineExists {
			orchestrator.quarantines = append(orchestrator.quarantines, Quarantine{
				QuarantineID:    consumption.QuarantineID,
				ProviderID:      consumption.ProviderID,
				ProviderEventID: consumption.ProviderEventID,
				PaymentID:       consumption.PaymentID,
				RawHash:         consumption.RawHash,
				EvidenceHash:    consumption.CallbackEvidenceHash,
				ReasonCode:      "CANONICAL_SETTLEMENT_SUBMITTED",
				ReceivedAt:      consumption.CallbackReceivedAt.UTC(),
				Owner:           "payment-operations",
				ResolutionDeadline: consumption.CallbackReceivedAt.UTC().
					Add(24 * time.Hour),
			})
		}
		orchestrator.quarantineResolutions[consumption.QuarantineID] =
			QuarantineResolution{
				ResolutionID: consumption.ResolutionID,
				QuarantineID: consumption.QuarantineID,
				EvidenceHash: consumption.ResolutionEvidenceHash,
				ResolvedBy:   consumption.ResolvedBy,
				ResolvedAt:   consumption.ResolvedAt.UTC(),
			}
		incidentExists := false
		incidentID := "canonical-success:" + consumption.QuarantineID
		for _, incident := range orchestrator.canonicalIncidents {
			if incident.IncidentID == incidentID {
				incidentExists = true
				break
			}
		}
		if !incidentExists {
			orchestrator.canonicalIncidents = append(
				orchestrator.canonicalIncidents,
				CanonicalIncident{
					IncidentID:        incidentID,
					PaymentID:         consumption.PaymentID,
					AllocationID:      consumption.AllocationID,
					ClaimDigest:       consumption.InstructionDigest,
					ProviderID:        consumption.ProviderID,
					ProviderEventID:   consumption.ProviderEventID,
					ProviderReference: consumption.ProviderReference,
					RawHash:           consumption.RawHash,
					EvidenceHash:      consumption.ResolutionEvidenceHash,
					ReasonCode: "PROVIDER_REVERSAL_CONTRADICTED_BY_" +
						"CANONICAL_SETTLEMENT",
					OccurredAt: consumption.CallbackOccurredAt.UTC(),
					ReceivedAt: consumption.ResolvedAt.UTC(),
				},
			)
		}
		if err := orchestrator.applyCanonicalConsumptionsLocked(
			consumption.PaymentID,
		); err != nil {
			return err
		}
	}
	return nil
}

func (orchestrator *Orchestrator) applyCanonicalConsumptionsLocked(
	paymentID string,
) error {
	current, exists := orchestrator.payments[paymentID]
	if !exists {
		return nil
	}
	for _, consumption := range orchestrator.consumedReversals {
		if consumption.PaymentID != paymentID {
			continue
		}
		if current.Status != StatusFinal ||
			current.ProviderID != consumption.ProviderID ||
			current.ProviderReference != consumption.ProviderReference ||
			current.AssetID != consumption.AssetID ||
			current.Units != consumption.Units {
			return ErrCanonicalPersistence
		}
		eventKey := consumption.ProviderID + "\x00" + consumption.ProviderEventID
		orchestrator.events[eventKey] = storedEvent{
			rawHash: consumption.RawHash,
			result: CallbackResult{
				ProviderID:      consumption.ProviderID,
				ProviderEventID: consumption.ProviderEventID,
				RawHash:         consumption.RawHash,
				Payment:         current,
				Disposition:     "INCIDENT",
			},
			err: ErrCanonicalConfirmed,
		}
	}
	return nil
}

func validCanonicalConsumption(consumption CanonicalReversalConsumption) bool {
	return consumption.QuarantineID != "" && consumption.IngressID > 0 &&
		consumption.PaymentID != "" && consumption.AllocationID != "" &&
		consumption.InstructionDigest != "" && consumption.ProviderID != "" &&
		consumption.ProviderEventID != "" &&
		consumption.ProviderReference != "" && consumption.AssetID != "" &&
		consumption.Units != "" && consumption.RawHash != "" &&
		consumption.SignatureHash != "" &&
		consumption.CallbackEvidenceHash != "" &&
		!consumption.CallbackExpiresAt.IsZero() &&
		!consumption.CallbackOccurredAt.IsZero() &&
		!consumption.CallbackReceivedAt.IsZero() &&
		!consumption.CallbackReceivedAt.Before(
			consumption.CallbackOccurredAt,
		) &&
		!consumption.CallbackReceivedAt.After(
			consumption.CallbackExpiresAt,
		) &&
		consumption.ResolutionID ==
			"canonical-success:"+consumption.GatewayEventID &&
		consumption.ResolutionEvidenceHash != "" &&
		consumption.ResolvedBy == "canonical-chain-indexer" &&
		!consumption.ResolvedAt.IsZero() &&
		!consumption.ResolvedAt.Before(consumption.CallbackReceivedAt) &&
		consumption.GatewayEventID != "" &&
		consumption.GatewayTransactionHash != "" &&
		consumption.GatewayRawPayloadHash != "" &&
		consumption.FinalityEvidenceHash ==
			consumption.ResolutionEvidenceHash
}

func (orchestrator *Orchestrator) ResolveQuarantine(
	quarantineID string,
	resolutionID string,
	evidenceHash string,
	resolvedBy string,
	resolvedAt time.Time,
) (QuarantineResolution, error) {
	if orchestrator == nil || quarantineID == "" || resolutionID == "" ||
		evidenceHash == "" || resolvedBy == "" || resolvedAt.IsZero() {
		return QuarantineResolution{}, ErrInvalidResolution
	}
	orchestrator.mu.Lock()
	defer orchestrator.mu.Unlock()
	if _, pending := orchestrator.pendingReversals[quarantineID]; pending {
		return QuarantineResolution{}, ErrInvalidResolution
	}
	if _, exists := orchestrator.quarantineResolutions[quarantineID]; exists {
		return QuarantineResolution{}, ErrInvalidResolution
	}
	found := false
	for _, record := range orchestrator.quarantines {
		if record.QuarantineID == quarantineID && !resolvedAt.Before(record.ReceivedAt) {
			found = true
			break
		}
	}
	if !found {
		return QuarantineResolution{}, ErrInvalidResolution
	}
	resolution := QuarantineResolution{
		ResolutionID: resolutionID,
		QuarantineID: quarantineID,
		EvidenceHash: evidenceHash,
		ResolvedBy:   resolvedBy,
		ResolvedAt:   resolvedAt.UTC(),
	}
	orchestrator.quarantineResolutions[quarantineID] = resolution
	return resolution, nil
}

func (orchestrator *Orchestrator) Payment(paymentID string) (Intent, bool) {
	orchestrator.mu.RLock()
	defer orchestrator.mu.RUnlock()
	intent, exists := orchestrator.payments[paymentID]
	return intent, exists
}

func (orchestrator *Orchestrator) Payments() []Intent {
	orchestrator.mu.RLock()
	defer orchestrator.mu.RUnlock()
	result := make([]Intent, 0, len(orchestrator.payments))
	for _, intent := range orchestrator.payments {
		result = append(result, intent)
	}
	slices.SortFunc(result, func(left, right Intent) int {
		if left.PaymentID < right.PaymentID {
			return -1
		}
		if left.PaymentID > right.PaymentID {
			return 1
		}
		return 0
	})
	return result
}

func (orchestrator *Orchestrator) RawCallbacks() []RawCallback {
	orchestrator.mu.RLock()
	defer orchestrator.mu.RUnlock()
	result := make([]RawCallback, len(orchestrator.rawCallbacks))
	for index, callback := range orchestrator.rawCallbacks {
		result[index] = callback
		result[index].RawPayload = slices.Clone(callback.RawPayload)
	}
	return result
}

func (orchestrator *Orchestrator) Quarantines() []Quarantine {
	orchestrator.mu.RLock()
	defer orchestrator.mu.RUnlock()
	return slices.Clone(orchestrator.quarantines)
}

func (orchestrator *Orchestrator) CanonicalIncidents() []CanonicalIncident {
	orchestrator.mu.RLock()
	defer orchestrator.mu.RUnlock()
	return slices.Clone(orchestrator.canonicalIncidents)
}

func (orchestrator *Orchestrator) quarantine(
	providerID string,
	eventID string,
	paymentID string,
	rawHash string,
	evidenceHash string,
	reason string,
	receivedAt time.Time,
) Quarantine {
	sequence := len(orchestrator.quarantines) + 1
	record := Quarantine{
		QuarantineID:       fmt.Sprintf("quarantine-%06d", sequence),
		ProviderID:         providerID,
		ProviderEventID:    eventID,
		PaymentID:          paymentID,
		RawHash:            rawHash,
		EvidenceHash:       evidenceHash,
		ReasonCode:         reason,
		ReceivedAt:         receivedAt.UTC(),
		Owner:              "payment-operations",
		ResolutionDeadline: receivedAt.UTC().Add(24 * time.Hour),
	}
	orchestrator.quarantines = append(orchestrator.quarantines, record)
	return record
}

func decodeCallback(raw []byte) (Callback, error) {
	var callback Callback
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&callback); err != nil {
		return Callback{}, ErrInvalidCallback
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return Callback{}, ErrInvalidCallback
	}
	canonical, err := EncodeCallback(callback)
	if err != nil || !bytes.Equal(canonical, raw) {
		return Callback{}, ErrInvalidCallback
	}
	return callback, nil
}

func allowedTransition(from Status, to Status) bool {
	switch from {
	case StatusCreated:
		return to == StatusProcessing || to == StatusFailed
	case StatusProcessing:
		return to == StatusProvisional || to == StatusFailed
	case StatusProvisional:
		return to == StatusFinal || to == StatusReversed
	case StatusFinal:
		return to == StatusReversed
	default:
		return false
	}
}

func accountingTransition(status Status) bool {
	return status == StatusProvisional || status == StatusFinal || status == StatusReversed
}

func callbackStatus(status Status) bool {
	switch status {
	case StatusProcessing, StatusProvisional, StatusFinal, StatusFailed, StatusReversed:
		return true
	default:
		return false
	}
}

func validRail(rail Rail) bool {
	return rail == RailBank || rail == RailCard
}

func positiveInteger(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.String() == value
}

func intentHash(intent Intent) string {
	encoded, _ := json.Marshal(struct {
		PaymentID      string
		LegalEntityID  string
		IdempotencyKey string
		CorrelationID  string
		PayerReference string
		LoanID         string
		ProviderID     string
		Rail           Rail
		Purpose        string
		AssetID        string
		Units          string
		ExpiresAt      time.Time
		SchemaVersion  uint32
	}{
		PaymentID:      intent.PaymentID,
		LegalEntityID:  intent.LegalEntityID,
		IdempotencyKey: intent.IdempotencyKey,
		CorrelationID:  intent.CorrelationID,
		PayerReference: intent.PayerReference,
		LoanID:         intent.LoanID,
		ProviderID:     intent.ProviderID,
		Rail:           intent.Rail,
		Purpose:        intent.Purpose,
		AssetID:        intent.AssetID,
		Units:          intent.Units,
		ExpiresAt:      intent.ExpiresAt.UTC(),
		SchemaVersion:  intent.SchemaVersion,
	})
	return hashBytes(encoded)
}

func hashBytes(value []byte) string {
	sum := sha256.Sum256(value)
	return hex.EncodeToString(sum[:])
}

func canonicalPaymentEventID(providerID string, providerEventID string) string {
	return providerID + ":" + providerEventID
}

func cloneResult(result CallbackResult) CallbackResult {
	result.JournalIDs = slices.Clone(result.JournalIDs)
	return result
}
