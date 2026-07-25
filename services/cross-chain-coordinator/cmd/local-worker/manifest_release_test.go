package main

import (
	"strings"
	"testing"
)

func TestDecodeJournalSetSHA256HasExplicitStorageBoundary(t *testing.T) {
	stored := strings.Repeat("ab", 32)
	decoded, err := decodeJournalSetSHA256(stored)
	if err != nil {
		t.Fatalf("canonical unprefixed stored hash was rejected: %v", err)
	}
	if len(decoded) != 32 {
		t.Fatalf("decoded journal-set hash length = %d, want 32", len(decoded))
	}
	for _, invalid := range []string{
		"0x" + stored,
		strings.ToUpper(stored),
		stored[:len(stored)-1],
	} {
		if _, err := decodeJournalSetSHA256(invalid); err == nil {
			t.Fatalf("invalid stored journal-set hash was accepted: %q", invalid)
		}
	}
}

func TestEvidenceBucketMatchesFrozenReleaseVocabulary(t *testing.T) {
	if evidenceBucket != "crosschain-evidence" {
		t.Fatalf("release evidence bucket drifted: %q", evidenceBucket)
	}
}

func TestDurableTableSetIncludesCancellationAuthority(t *testing.T) {
	if len(durableTableNames) != 49 {
		t.Fatalf("durable table count = %d, want 49", len(durableTableNames))
	}
	seen := make(map[string]struct{}, len(durableTableNames))
	for _, table := range durableTableNames {
		if _, duplicate := seen[table]; duplicate {
			t.Fatalf("duplicate durable table: %s", table)
		}
		seen[table] = struct{}{}
	}
	for _, table := range []string{
		"crosschain.loan_cancellation_requests",
		"crosschain.loan_cancellation_completions",
	} {
		if _, present := seen[table]; !present {
			t.Fatalf("cancellation authority table is missing: %s", table)
		}
		if _, required := neverEmptyDurableTables[table]; required {
			t.Fatalf("happy-path cancellation table cannot be never-empty: %s", table)
		}
	}
}
