// Package creditevidence stores final, immutable Phase 6A control evidence.
// It intentionally contains no raw identity or underwriting feature values.
package creditevidence

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"sync"
	"time"
)

type RecordType string

const (
	ProviderRegistered      RecordType = "IDENTITY_PROVIDER_REGISTERED"
	ProviderStatusChanged   RecordType = "IDENTITY_PROVIDER_STATUS_CHANGED"
	CredentialSchemaAdded   RecordType = "IDENTITY_CREDENTIAL_SCHEMA_REGISTERED"
	CredentialSchemaChanged RecordType = "IDENTITY_CREDENTIAL_SCHEMA_STATUS_CHANGED"
	CredentialIssued        RecordType = "IDENTITY_CREDENTIAL_ISSUED"
	CredentialRevoked       RecordType = "IDENTITY_CREDENTIAL_REVOKED"
	DecisionIssued          RecordType = "CREDIT_DECISION_ISSUED"
	DecisionRevoked         RecordType = "CREDIT_DECISION_REVOKED"
	ExposureReserved        RecordType = "CREDIT_EXPOSURE_RESERVED"
	ExposureActivated       RecordType = "CREDIT_EXPOSURE_ACTIVATED"
	ExposureReleased        RecordType = "CREDIT_EXPOSURE_RELEASED"
	ExposureCancelled       RecordType = "CREDIT_EXPOSURE_CANCELLED"
)

var (
	ErrInvalidEvidence  = errors.New("invalid credit evidence")
	ErrEvidenceConflict = errors.New("credit evidence conflict")
)

type Evidence struct {
	EventID           string     `json:"event_id"`
	RecordType        RecordType `json:"record_type"`
	RecordID          string     `json:"record_id"`
	Sequence          uint64     `json:"sequence"`
	ProviderID        string     `json:"provider_id,omitempty"`
	SchemaID          string     `json:"schema_id,omitempty"`
	CredentialID      string     `json:"credential_id,omitempty"`
	DecisionID        string     `json:"decision_id,omitempty"`
	LoanID            string     `json:"loan_id,omitempty"`
	SubjectCommitment string     `json:"subject_commitment,omitempty"`
	AssetID           string     `json:"asset_id,omitempty"`
	Units             string     `json:"units,omitempty"`
	EvidenceHash      string     `json:"evidence_hash"`
	Finality          string     `json:"finality"`
	OccurredAt        time.Time  `json:"occurred_at"`
}

type StoredEvidence struct {
	Evidence
	ContentHash string
	RecordedAt  time.Time
}

type Store struct {
	mu      sync.RWMutex
	byEvent map[string]StoredEvidence
	byKey   map[recordKey]string
	order   []string
}

type recordKey struct {
	recordType RecordType
	recordID   string
	sequence   uint64
}

func New() *Store {
	return &Store{
		byEvent: make(map[string]StoredEvidence),
		byKey:   make(map[recordKey]string),
	}
}

func (store *Store) Record(evidence Evidence) (StoredEvidence, error) {
	contentHash, err := validateAndHash(evidence)
	if err != nil {
		return StoredEvidence{}, err
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if existing, ok := store.byEvent[evidence.EventID]; ok {
		if existing.ContentHash != contentHash {
			return StoredEvidence{}, ErrEvidenceConflict
		}
		return existing, nil
	}
	key := recordKey{
		recordType: evidence.RecordType,
		recordID:   evidence.RecordID,
		sequence:   evidence.Sequence,
	}
	if _, exists := store.byKey[key]; exists {
		return StoredEvidence{}, ErrEvidenceConflict
	}
	stored := StoredEvidence{
		Evidence: evidence, ContentHash: contentHash, RecordedAt: time.Now().UTC(),
	}
	store.byEvent[evidence.EventID] = stored
	store.byKey[key] = evidence.EventID
	store.order = append(store.order, evidence.EventID)
	return stored, nil
}

func (store *Store) List() []StoredEvidence {
	store.mu.RLock()
	defer store.mu.RUnlock()
	result := make([]StoredEvidence, 0, len(store.order))
	for _, eventID := range store.order {
		result = append(result, store.byEvent[eventID])
	}
	return result
}

func validateAndHash(evidence Evidence) (string, error) {
	if evidence.EventID == "" || evidence.RecordID == "" || evidence.Sequence == 0 ||
		evidence.EvidenceHash == "" || evidence.Finality != "FINAL" ||
		evidence.OccurredAt.IsZero() || !knownType(evidence.RecordType) {
		return "", ErrInvalidEvidence
	}
	switch evidence.RecordType {
	case ProviderRegistered, ProviderStatusChanged:
		if evidence.ProviderID == "" {
			return "", ErrInvalidEvidence
		}
	case CredentialSchemaAdded, CredentialSchemaChanged:
		if evidence.ProviderID == "" || evidence.SchemaID == "" {
			return "", ErrInvalidEvidence
		}
	case CredentialIssued, CredentialRevoked:
		if evidence.CredentialID == "" || evidence.SubjectCommitment == "" {
			return "", ErrInvalidEvidence
		}
	case DecisionIssued, DecisionRevoked:
		if evidence.DecisionID == "" || evidence.CredentialID == "" ||
			evidence.SubjectCommitment == "" {
			return "", ErrInvalidEvidence
		}
	case ExposureReserved, ExposureActivated, ExposureReleased, ExposureCancelled:
		units, ok := new(big.Int).SetString(evidence.Units, 10)
		if evidence.DecisionID == "" || evidence.LoanID == "" ||
			evidence.SubjectCommitment == "" || evidence.AssetID == "" ||
			!ok || units.Sign() <= 0 {
			return "", ErrInvalidEvidence
		}
	}
	payload, err := json.Marshal(evidence)
	if err != nil {
		return "", ErrInvalidEvidence
	}
	hash := sha256.Sum256(payload)
	return hex.EncodeToString(hash[:]), nil
}

func knownType(recordType RecordType) bool {
	switch recordType {
	case ProviderRegistered, ProviderStatusChanged, CredentialSchemaAdded,
		CredentialSchemaChanged, CredentialIssued, CredentialRevoked, DecisionIssued,
		DecisionRevoked, ExposureReserved, ExposureActivated, ExposureReleased,
		ExposureCancelled:
		return true
	default:
		return false
	}
}
