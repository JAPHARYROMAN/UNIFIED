package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
)

func TestLocalWorkerPostgreSQLRedpandaMinIOIntegration(t *testing.T) {
	runtimeURL := os.Getenv("UNIFIED_LOCAL_WORKER_TEST_DATABASE_URL")
	bootstrapURL := os.Getenv("UNIFIED_LOCAL_WORKER_TEST_BOOTSTRAP_DATABASE_URL")
	observerURL := os.Getenv("UNIFIED_LOCAL_WORKER_TEST_OBSERVER_DATABASE_URL")
	finalityURL := os.Getenv("UNIFIED_LOCAL_WORKER_TEST_FINALITY_DATABASE_URL")
	recoveryURL := os.Getenv("UNIFIED_LOCAL_WORKER_TEST_RECOVERY_DATABASE_URL")
	reorganizationURL := os.Getenv(
		"UNIFIED_LOCAL_WORKER_TEST_REORGANIZATION_DATABASE_URL",
	)
	if runtimeURL == "" || bootstrapURL == "" || observerURL == "" ||
		finalityURL == "" || recoveryURL == "" || reorganizationURL == "" {
		t.Skip("local worker integration database URLs are not set")
	}
	bootstrap, err := sql.Open("pgx", bootstrapURL)
	if err != nil {
		t.Fatal(err)
	}
	registration := localRegistration()
	sortedSigners := localSortedFinalitySigners()
	for _, signerSetHash := range [][32]byte{
		registration.SourceSignerSetHash,
		registration.DestinationSignerSetHash,
	} {
		if _, err := bootstrap.ExecContext(
			t.Context(),
			`INSERT INTO crosschain.signer_sets (
			    signer_set_hash, version, threshold, signer_addresses,
			    valid_from, valid_until, status
			) VALUES (
			    $1, 1, 2, ARRAY[$2::bytea, $3::bytea, $4::bytea],
			    $5, $6, 'ACTIVE'
			)
			ON CONFLICT (signer_set_hash, version) DO NOTHING`,
			signerSetHash[:],
			sortedSigners[0][:],
			sortedSigners[1][:],
			sortedSigners[2][:],
			localBaseTime.Add(-time.Hour),
			localBaseTime.Add(24*time.Hour),
		); err != nil {
			_ = bootstrap.Close()
			t.Fatalf("owner signer-set bootstrap: %v", err)
		}
	}
	bootstrapRepository, err := store.NewSQLWithProvisioning(
		bootstrap,
		[]store.RouteRegistration{registration},
	)
	if err != nil {
		_ = bootstrap.Close()
		t.Fatal(err)
	}
	if err := bootstrapRepository.PutRoute(registration.Route); err != nil {
		_ = bootstrap.Close()
		t.Fatalf("owner route bootstrap: %v", err)
	}
	if err := bootstrap.Close(); err != nil {
		t.Fatal(err)
	}

	values := map[string]string{
		foundationDSNEnvironment:          bootstrapURL,
		databaseURLEnvironment:            runtimeURL,
		observerDatabaseEnvironment:       observerURL,
		finalityDatabaseEnvironment:       finalityURL,
		recoveryDatabaseEnvironment:       recoveryURL,
		reorganizationDatabaseEnvironment: reorganizationURL,
		kafkaEnvironment:                  "127.0.0.1:19092",
		objectEnvironment:                 "http://127.0.0.1:59000",
		providerAEnvironment:              "http://127.0.0.1:58081",
		providerBEnvironment:              "http://127.0.0.1:58082",
	}
	getenv := func(key string) string { return values[key] }
	var first bytes.Buffer
	if err := execute(
		[]string{"--mode", "smoke", "--timeout", "60s"},
		getenv,
		&first,
	); err != nil {
		t.Fatal(err)
	}
	var report smokeReport
	if err := json.Unmarshal(first.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	t.Logf("first local worker report: %s", first.String())
	if !report.ProviderFailover || report.ProviderAttempts != 2 ||
		report.OutboxPublished != 5 || report.InboxConsumed != 5 ||
		!report.EvidencePersisted || !report.RestartRehydrated ||
		!report.ReorganizationRehydrated ||
		!report.DuplicatePrevented || !report.Reconciled ||
		!report.RecoveryGuarded {
		t.Fatalf("incomplete local worker report: %#v", report)
	}

	var replay bytes.Buffer
	if err := execute(
		[]string{"--mode", "smoke", "--timeout", "60s"},
		getenv,
		&replay,
	); err != nil {
		t.Fatalf("restart smoke replay: %v", err)
	}
	var replayed smokeReport
	if err := json.Unmarshal(replay.Bytes(), &replayed); err != nil {
		t.Fatal(err)
	}
	t.Logf("restart local worker report: %s", replay.String())
	if replayed.MessageID != report.MessageID ||
		replayed.ProviderAttempts != 2 ||
		replayed.OutboxPublished != 0 ||
		replayed.InboxConsumed != 0 ||
		!replayed.DuplicatePrevented ||
		!replayed.RestartRehydrated {
		t.Fatalf("unexpected restart report: %#v", replayed)
	}
}
