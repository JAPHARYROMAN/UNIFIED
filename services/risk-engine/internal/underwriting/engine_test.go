package underwriting

import (
	"errors"
	"slices"
	"testing"
	"time"
)

func TestApprovedDecisionIsDeterministicAndExplainable(t *testing.T) {
	asOf := time.Unix(1_900_000_000, 0).UTC()
	engine := testEngine(t)
	application := testApplication(asOf)
	first, err := engine.Decide(application, asOf)
	if err != nil {
		t.Fatalf("decide: %v", err)
	}
	slices.Reverse(application.Features)
	second, err := engine.Decide(application, asOf)
	if err != nil {
		t.Fatalf("decide reordered: %v", err)
	}
	if !first.Approved || first.MaximumExposureUnits != "400" ||
		!slices.Equal(first.ReasonCodes, []string{ReasonApproved}) {
		t.Fatalf("unexpected approved decision: %+v", first)
	}
	if first.FeatureEvidenceRoot != second.FeatureEvidenceRoot {
		t.Fatal("feature root changed with input order")
	}
	if first.PolicyID == "" || first.PolicyVersion == "" ||
		first.RuleSetHash == "" || first.FeatureSchemaHash == "" {
		t.Fatal("decision provenance is incomplete")
	}
}

func TestPolicyReasonsAreStableAndDoNotExposeFeatures(t *testing.T) {
	asOf := time.Unix(1_900_000_000, 0).UTC()
	engine := testEngine(t)
	application := testApplication(asOf)
	application.CredentialScope = "wrong-scope"
	application.CredentialAssurance = 1
	application.DurationDays = 366
	application.RequestedUnits = "401"
	decision, err := engine.Decide(application, asOf)
	if err != nil {
		t.Fatalf("decide: %v", err)
	}
	expected := []string{
		ReasonScopeMismatch,
		ReasonAssuranceLow,
		ReasonDurationExceeded,
		ReasonCapacityInsufficient,
	}
	if decision.Approved || !slices.Equal(decision.ReasonCodes, expected) {
		t.Fatalf("unexpected decline reasons: %+v", decision)
	}
}

func TestStaleFutureDuplicateAndUnknownEvidenceFailClosed(t *testing.T) {
	asOf := time.Unix(1_900_000_000, 0).UTC()
	engine := testEngine(t)
	cases := []struct {
		name   string
		mutate func(*Application)
	}{
		{
			name: "stale",
			mutate: func(application *Application) {
				application.Features[0].ObservedAt = asOf.Add(-25 * time.Hour)
			},
		},
		{
			name: "future",
			mutate: func(application *Application) {
				application.Features[0].ObservedAt = asOf.Add(time.Second)
			},
		},
		{
			name: "duplicate",
			mutate: func(application *Application) {
				application.Features[1].FeatureID = application.Features[0].FeatureID
			},
		},
		{
			name: "unknown",
			mutate: func(application *Application) {
				application.Features[1].FeatureID = "raw_identity_attribute"
			},
		},
		{
			name: "noncanonical numeric encoding",
			mutate: func(application *Application) {
				application.Features[0].ValueUnits = "01000"
			},
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			application := testApplication(asOf)
			testCase.mutate(&application)
			if _, err := engine.Decide(application, asOf); !errors.Is(err, ErrInvalidEvidence) {
				t.Fatalf("expected invalid evidence, got %v", err)
			}
		})
	}
}

func TestCapacityFloorsAtZeroAndPolicyCeiling(t *testing.T) {
	asOf := time.Unix(1_900_000_000, 0).UTC()
	engine := testEngine(t)
	application := testApplication(asOf)
	application.Features[0].ValueUnits = "3000"
	decision, err := engine.Decide(application, asOf)
	if err != nil || decision.MaximumExposureUnits != "1000" {
		t.Fatalf("policy ceiling failed: decision=%+v err=%v", decision, err)
	}
	application.Features[0].ValueUnits = "100"
	application.Features[1].ValueUnits = "100"
	decision, err = engine.Decide(application, asOf)
	if err != nil || decision.MaximumExposureUnits != "0" ||
		decision.ReasonCodes[0] != ReasonCapacityInsufficient {
		t.Fatalf("zero floor failed: decision=%+v err=%v", decision, err)
	}
}

func testEngine(t *testing.T) *Engine {
	t.Helper()
	engine, err := New(Policy{
		PolicyID:             "policy:synthetic:v1",
		Version:              "1.0.0",
		RuleSetHash:          "sha256:rules",
		FeatureSchemaHash:    "sha256:features",
		CredentialScope:      "scope:unsecured:local",
		SettlementAssetID:    "asset:synthetic",
		ProductID:            "product:unsecured:local",
		MaximumExposureUnits: "1000",
		MaximumDurationDays:  365,
		MinimumAssurance:     3,
		IncomeAdvanceBps:     5_000,
		MaximumFeatureAge:    24 * time.Hour,
	})
	if err != nil {
		t.Fatalf("new engine: %v", err)
	}
	return engine
}

func testApplication(asOf time.Time) Application {
	return Application{
		DecisionID:          "decision:synthetic:1",
		SubjectCommitment:   "commitment:randomized:1",
		BorrowerAccount:     "account:local:1",
		CredentialScope:     "scope:unsecured:local",
		CredentialAssurance: 4,
		SettlementAssetID:   "asset:synthetic",
		ProductID:           "product:unsecured:local",
		RequestedUnits:      "300",
		DurationDays:        180,
		Features: []FeatureEvidence{
			{
				FeatureID: FeatureVerifiedIncome, ValueUnits: "1000",
				SourceID: "provider:synthetic:income", TransformVersion: "1.0.0",
				EvidenceHash: "sha256:income", ObservedAt: asOf.Add(-time.Hour),
			},
			{
				FeatureID: FeatureExistingObligation, ValueUnits: "100",
				SourceID: "provider:synthetic:obligation", TransformVersion: "1.0.0",
				EvidenceHash: "sha256:obligation", ObservedAt: asOf.Add(-time.Hour),
			},
		},
	}
}
