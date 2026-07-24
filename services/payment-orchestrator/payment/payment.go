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
	ResolutionID string
	QuarantineID string
	EvidenceHash string
	ResolvedBy   string
	ResolvedAt   time.Time
}

type storedEvent struct {
	rawHash string
	result  CallbackResult
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
	quarantineResolutions map[string]QuarantineResolution
	accounting            Accounting
}

func New(providers []Provider, accounting Accounting) (*Orchestrator, error) {
	if len(providers) == 0 || accounting == nil {
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
	return &Orchestrator{
		providers:             configured,
		payments:              make(map[string]Intent),
		intentKeys:            make(map[string]string),
		intentHashes:          make(map[string]string),
		events:                make(map[string]storedEvent),
		quarantineResolutions: make(map[string]QuarantineResolution),
		accounting:            accounting,
	}, nil
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
	orchestrator.rawCallbacks = append(orchestrator.rawCallbacks, RawCallback{
		IngressID:       uint64(len(orchestrator.rawCallbacks) + 1),
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
		return replayed, nil
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
	if callback.Status != current.Status &&
		!allowedTransition(current.Status, callback.Status) {
		orchestrator.quarantine(providerID, providerEventID, callback.PaymentID, rawHash,
			callback.EvidenceHash, "CALLBACK_ORDER_INVALID", receivedAt)
		return CallbackResult{}, ErrInvalidTransition
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

func (orchestrator *Orchestrator) quarantine(
	providerID string,
	eventID string,
	paymentID string,
	rawHash string,
	evidenceHash string,
	reason string,
	receivedAt time.Time,
) {
	sequence := len(orchestrator.quarantines) + 1
	orchestrator.quarantines = append(orchestrator.quarantines, Quarantine{
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
	})
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

func cloneResult(result CallbackResult) CallbackResult {
	result.JournalIDs = slices.Clone(result.JournalIDs)
	return result
}
