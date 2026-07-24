package creditevidence

import (
	"errors"
	"testing"
	"time"
)

func TestFinalEvidenceIsImmutableAndIdempotent(t *testing.T) {
	store := New()
	evidence := Evidence{
		EventID: "event-1", RecordType: ExposureReserved, RecordID: "reservation-1",
		Sequence: 1, DecisionID: "decision-1", LoanID: "loan-1",
		SubjectCommitment: "8f1c-randomized-commitment", AssetID: "asset:synthetic",
		Units: "100", EvidenceHash: "block:1:tx:1", Finality: "FINAL",
		OccurredAt: time.Unix(1_900_000_000, 0).UTC(),
	}
	first, err := store.Record(evidence)
	if err != nil {
		t.Fatalf("record evidence: %v", err)
	}
	replayed, err := store.Record(evidence)
	if err != nil || replayed.ContentHash != first.ContentHash ||
		!replayed.RecordedAt.Equal(first.RecordedAt) {
		t.Fatalf("replay was not idempotent: %v", err)
	}
	evidence.Units = "101"
	if _, err := store.Record(evidence); !errors.Is(err, ErrEvidenceConflict) {
		t.Fatalf("expected immutable conflict, got %v", err)
	}
	if len(store.List()) != 1 {
		t.Fatal("evidence history changed after replay")
	}
}

func TestProvisionalIncompleteAndUnknownEvidenceFailsClosed(t *testing.T) {
	store := New()
	base := Evidence{
		EventID: "event-1", RecordType: CredentialIssued, RecordID: "credential-1",
		Sequence: 1, CredentialID: "credential-1",
		SubjectCommitment: "8f1c-randomized-commitment",
		EvidenceHash:      "block:1:tx:1", Finality: "FINAL",
		OccurredAt: time.Unix(1_900_000_000, 0).UTC(),
	}
	cases := []Evidence{
		func() Evidence { invalid := base; invalid.Finality = "PROVISIONAL"; return invalid }(),
		func() Evidence {
			invalid := base
			invalid.SubjectCommitment = ""
			return invalid
		}(),
		func() Evidence { invalid := base; invalid.RecordType = "RAW_IDENTITY"; return invalid }(),
	}
	for _, invalid := range cases {
		if _, err := store.Record(invalid); !errors.Is(err, ErrInvalidEvidence) {
			t.Fatalf("expected invalid evidence, got %v", err)
		}
	}
}

func TestDecisionAndExposureEvidenceRequireOpaqueReferences(t *testing.T) {
	store := New()
	decision := Evidence{
		EventID: "event-decision", RecordType: DecisionIssued, RecordID: "decision-1",
		Sequence: 1, CredentialID: "credential-1", DecisionID: "decision-1",
		SubjectCommitment: "8f1c-randomized-commitment",
		EvidenceHash:      "block:2:tx:1", Finality: "FINAL",
		OccurredAt: time.Unix(1_900_000_000, 0).UTC(),
	}
	if _, err := store.Record(decision); err != nil {
		t.Fatalf("record decision: %v", err)
	}
	exposure := Evidence{
		EventID: "event-exposure", RecordType: ExposureActivated, RecordID: "loan-1",
		Sequence: 1, DecisionID: "decision-1", LoanID: "loan-1",
		SubjectCommitment: "8f1c-randomized-commitment", AssetID: "asset:synthetic",
		Units: "100", EvidenceHash: "block:3:tx:1", Finality: "FINAL",
		OccurredAt: time.Unix(1_900_000_100, 0).UTC(),
	}
	if _, err := store.Record(exposure); err != nil {
		t.Fatalf("record exposure: %v", err)
	}
	if len(store.List()) != 2 {
		t.Fatal("expected decision and exposure evidence")
	}
}

func TestControlEventsAndRecordSequenceConflicts(t *testing.T) {
	store := New()
	schema := Evidence{
		EventID: "event-schema", RecordType: CredentialSchemaAdded, RecordID: "schema-1",
		Sequence: 1, ProviderID: "provider-1", SchemaID: "schema-1",
		EvidenceHash: "block:4:tx:1", Finality: "FINAL",
		OccurredAt: time.Unix(1_900_000_200, 0).UTC(),
	}
	if _, err := store.Record(schema); err != nil {
		t.Fatalf("record schema evidence: %v", err)
	}
	conflict := schema
	conflict.EventID = "event-schema-conflict"
	conflict.EvidenceHash = "block:4:tx:2"
	if _, err := store.Record(conflict); !errors.Is(err, ErrEvidenceConflict) {
		t.Fatalf("expected record-sequence conflict, got %v", err)
	}
	incomplete := schema
	incomplete.EventID = "event-schema-incomplete"
	incomplete.Sequence = 2
	incomplete.SchemaID = ""
	if _, err := store.Record(incomplete); !errors.Is(err, ErrInvalidEvidence) {
		t.Fatalf("expected incomplete schema evidence to fail, got %v", err)
	}
}
