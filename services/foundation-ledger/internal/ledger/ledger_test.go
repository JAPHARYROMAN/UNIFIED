package ledger

import (
	"errors"
	"testing"
	"time"
)

func balancedJournal() Journal {
	return Journal{
		ID:             "journal-001",
		LegalEntityID:  "entity-local",
		BookID:         "protocol",
		SourceSystem:   "foundation-test",
		EntryType:      "FOUNDATION_TEST",
		SourceEventID:  "event-001",
		IdempotencyKey: "command-001",
		CorrelationID:  "correlation-001",
		EffectiveAt:    time.Unix(1_700_000_000, 0).UTC(),
		Entries: []Entry{
			{AccountCode: "1000", Side: Debit, AssetID: "asset:local:usd", Units: "1000"},
			{AccountCode: "2000", Side: Credit, AssetID: "asset:local:usd", Units: "1000"},
		},
		EvidenceHash: "evidence-local",
	}
}

func TestPostBalancedJournal(t *testing.T) {
	book := New()
	posted, err := book.Post(balancedJournal())
	if err != nil {
		t.Fatalf("post balanced journal: %v", err)
	}
	if posted.ContentHash == "" {
		t.Fatal("expected content hash")
	}
}

func TestRejectsUnbalancedJournal(t *testing.T) {
	book := New()
	journal := balancedJournal()
	journal.Entries[1].Units = "999"
	_, err := book.Post(journal)
	if !errors.Is(err, ErrUnbalancedJournal) {
		t.Fatalf("expected unbalanced error, got %v", err)
	}
}

func TestIdempotentReplayReturnsOriginal(t *testing.T) {
	book := New()
	first, err := book.Post(balancedJournal())
	if err != nil {
		t.Fatalf("first post: %v", err)
	}
	second, err := book.Post(balancedJournal())
	if err != nil {
		t.Fatalf("idempotent replay: %v", err)
	}
	if first.ContentHash != second.ContentHash || !first.PostedAt.Equal(second.PostedAt) {
		t.Fatal("replay did not return original posting")
	}
}

func TestIdempotencyConflict(t *testing.T) {
	book := New()
	if _, err := book.Post(balancedJournal()); err != nil {
		t.Fatalf("first post: %v", err)
	}
	conflict := balancedJournal()
	conflict.ID = "journal-002"
	conflict.EvidenceHash = "different"
	_, err := book.Post(conflict)
	if !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("expected idempotency conflict, got %v", err)
	}
}

func TestPostedJournalIsImmutableThroughCopies(t *testing.T) {
	book := New()
	posted, err := book.Post(balancedJournal())
	if err != nil {
		t.Fatalf("post: %v", err)
	}
	posted.Entries[0].Units = "5000"
	stored, ok := book.Get("journal-001")
	if !ok {
		t.Fatal("stored journal missing")
	}
	if stored.Entries[0].Units != "1000" {
		t.Fatal("stored journal was mutated through returned copy")
	}
}

func TestReversalPostsAnImmutableOppositeJournal(t *testing.T) {
	book := New()
	if _, err := book.Post(balancedJournal()); err != nil {
		t.Fatalf("post original: %v", err)
	}
	reversal, err := book.Reverse(
		"journal-001",
		"journal-001-reversal",
		"command-001-reversal",
		"event-001-reversal",
		"canonical source event was reorged",
		time.Unix(1_700_000_100, 0).UTC(),
	)
	if err != nil {
		t.Fatalf("reverse: %v", err)
	}
	if reversal.ReversalOf != "journal-001" ||
		reversal.Entries[0].Side != Credit ||
		reversal.Entries[1].Side != Debit {
		t.Fatal("reversal did not preserve its link and invert every posting side")
	}
	if _, err := book.Reverse(
		"journal-001",
		"journal-001-second-reversal",
		"command-001-second-reversal",
		"event-001-second-reversal",
		"duplicate",
		time.Unix(1_700_000_200, 0).UTC(),
	); !errors.Is(err, ErrAlreadyReversed) {
		t.Fatalf("expected duplicate reversal rejection, got %v", err)
	}
}

func TestBatchFailureCommitsNothing(t *testing.T) {
	book := New()
	first := balancedJournal()
	second := balancedJournal()
	second.IdempotencyKey = "command-002"
	if _, err := book.PostBatch([]Journal{first, second}); !errors.Is(err, ErrInvalidJournal) {
		t.Fatalf("expected duplicate journal rejection, got %v", err)
	}
	if len(book.List()) != 0 {
		t.Fatal("failed batch left a partial posting")
	}
}
