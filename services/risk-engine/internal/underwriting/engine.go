// Package underwriting implements a synthetic deterministic Phase 6A rules engine.
// It consumes only authenticated feature evidence and never accepts raw identity data.
package underwriting

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"hash"
	"math/big"
	"slices"
	"strings"
	"time"
)

const (
	FeatureVerifiedIncome     = "verified_income_units"
	FeatureExistingObligation = "existing_obligations_units"

	ReasonApproved             = "APPROVED"
	ReasonAssuranceLow         = "CREDENTIAL_ASSURANCE_LOW"
	ReasonCapacityInsufficient = "CAPACITY_INSUFFICIENT"
	ReasonDurationExceeded     = "DURATION_EXCEEDED"
	ReasonScopeMismatch        = "CREDENTIAL_SCOPE_MISMATCH"
)

var (
	ErrInvalidApplication = errors.New("invalid underwriting application")
	ErrInvalidEvidence    = errors.New("invalid underwriting feature evidence")
	ErrInvalidPolicy      = errors.New("invalid underwriting policy")
)

type FeatureEvidence struct {
	FeatureID        string
	ValueUnits       string
	SourceID         string
	TransformVersion string
	EvidenceHash     string
	ObservedAt       time.Time
}

type Policy struct {
	PolicyID             string
	Version              string
	RuleSetHash          string
	FeatureSchemaHash    string
	CredentialScope      string
	SettlementAssetID    string
	ProductID            string
	MaximumExposureUnits string
	MaximumDurationDays  uint32
	MinimumAssurance     uint16
	IncomeAdvanceBps     uint32
	MaximumFeatureAge    time.Duration
}

type Application struct {
	DecisionID          string
	SubjectCommitment   string
	BorrowerAccount     string
	CredentialScope     string
	CredentialAssurance uint16
	SettlementAssetID   string
	ProductID           string
	RequestedUnits      string
	DurationDays        uint32
	Features            []FeatureEvidence
}

type Decision struct {
	Approved             bool
	MaximumExposureUnits string
	ReasonCodes          []string
	FeatureEvidenceRoot  string
	PolicyID             string
	PolicyVersion        string
	RuleSetHash          string
	FeatureSchemaHash    string
	DecidedAt            time.Time
}

type Engine struct {
	policy Policy
}

func New(policy Policy) (*Engine, error) {
	maximum, ok := positiveInteger(policy.MaximumExposureUnits)
	if policy.PolicyID == "" || policy.Version == "" || policy.RuleSetHash == "" ||
		policy.FeatureSchemaHash == "" || policy.CredentialScope == "" ||
		policy.SettlementAssetID == "" || policy.ProductID == "" || !ok ||
		maximum.Sign() <= 0 || policy.MaximumDurationDays == 0 ||
		policy.MinimumAssurance == 0 || policy.IncomeAdvanceBps == 0 ||
		policy.IncomeAdvanceBps > 10_000 || policy.MaximumFeatureAge <= 0 {
		return nil, ErrInvalidPolicy
	}
	return &Engine{policy: policy}, nil
}

func (engine *Engine) Decide(application Application, asOf time.Time) (Decision, error) {
	if engine == nil || asOf.IsZero() || application.DecisionID == "" ||
		application.SubjectCommitment == "" || application.BorrowerAccount == "" ||
		application.SettlementAssetID != engine.policy.SettlementAssetID ||
		application.ProductID != engine.policy.ProductID || application.DurationDays == 0 {
		return Decision{}, ErrInvalidApplication
	}
	requested, ok := positiveInteger(application.RequestedUnits)
	if !ok || requested.Sign() <= 0 {
		return Decision{}, ErrInvalidApplication
	}
	features, root, err := authenticatedFeatures(application.Features, asOf, engine.policy)
	if err != nil {
		return Decision{}, err
	}
	income := features[FeatureVerifiedIncome]
	obligations := features[FeatureExistingObligation]
	capacity := new(big.Int).Mul(income, big.NewInt(int64(engine.policy.IncomeAdvanceBps)))
	capacity.Quo(capacity, big.NewInt(10_000))
	capacity.Sub(capacity, obligations)
	if capacity.Sign() < 0 {
		capacity.SetInt64(0)
	}
	policyMaximum, _ := positiveInteger(engine.policy.MaximumExposureUnits)
	if capacity.Cmp(policyMaximum) > 0 {
		capacity.Set(policyMaximum)
	}

	reasons := make([]string, 0, 4)
	if application.CredentialScope != engine.policy.CredentialScope {
		reasons = append(reasons, ReasonScopeMismatch)
	}
	if application.CredentialAssurance < engine.policy.MinimumAssurance {
		reasons = append(reasons, ReasonAssuranceLow)
	}
	if application.DurationDays > engine.policy.MaximumDurationDays {
		reasons = append(reasons, ReasonDurationExceeded)
	}
	if requested.Cmp(capacity) > 0 {
		reasons = append(reasons, ReasonCapacityInsufficient)
	}
	approved := len(reasons) == 0
	if approved {
		reasons = append(reasons, ReasonApproved)
	}
	return Decision{
		Approved:             approved,
		MaximumExposureUnits: capacity.String(),
		ReasonCodes:          reasons,
		FeatureEvidenceRoot:  root,
		PolicyID:             engine.policy.PolicyID,
		PolicyVersion:        engine.policy.Version,
		RuleSetHash:          engine.policy.RuleSetHash,
		FeatureSchemaHash:    engine.policy.FeatureSchemaHash,
		DecidedAt:            asOf.UTC(),
	}, nil
}

func authenticatedFeatures(
	evidence []FeatureEvidence,
	asOf time.Time,
	policy Policy,
) (map[string]*big.Int, string, error) {
	if len(evidence) != 2 {
		return nil, "", ErrInvalidEvidence
	}
	ordered := slices.Clone(evidence)
	slices.SortFunc(ordered, func(left, right FeatureEvidence) int {
		return strings.Compare(left.FeatureID, right.FeatureID)
	})
	values := make(map[string]*big.Int, len(ordered))
	hash := sha256.New()
	for _, feature := range ordered {
		value, ok := positiveInteger(feature.ValueUnits)
		if feature.FeatureID == "" || feature.SourceID == "" ||
			feature.TransformVersion == "" || feature.EvidenceHash == "" ||
			feature.ObservedAt.IsZero() || feature.ObservedAt.After(asOf) ||
			asOf.Sub(feature.ObservedAt) > policy.MaximumFeatureAge || !ok ||
			value.Sign() < 0 || values[feature.FeatureID] != nil {
			return nil, "", ErrInvalidEvidence
		}
		if feature.FeatureID != FeatureVerifiedIncome &&
			feature.FeatureID != FeatureExistingObligation {
			return nil, "", ErrInvalidEvidence
		}
		values[feature.FeatureID] = value
		writeCanonical(hash, feature.FeatureID)
		writeCanonical(hash, feature.ValueUnits)
		writeCanonical(hash, feature.SourceID)
		writeCanonical(hash, feature.TransformVersion)
		writeCanonical(hash, feature.EvidenceHash)
		writeCanonical(hash, feature.ObservedAt.UTC().Format(time.RFC3339Nano))
	}
	if values[FeatureVerifiedIncome] == nil || values[FeatureExistingObligation] == nil {
		return nil, "", ErrInvalidEvidence
	}
	return values, hex.EncodeToString(hash.Sum(nil)), nil
}

func positiveInteger(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.String() == value
}

func writeCanonical(destination hash.Hash, value string) {
	var length [8]byte
	binary.BigEndian.PutUint64(length[:], uint64(len(value)))
	_, _ = destination.Write(length[:])
	_, _ = destination.Write([]byte(value))
}
