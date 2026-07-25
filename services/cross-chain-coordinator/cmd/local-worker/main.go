// Command local-worker consumes the frozen local Phase 8 authenticated EVM
// evidence manifest, imports it through isolated database roles, proves exact
// restart durability, and atomically adds the durable release evidence. It has
// no key custody, signing, EVM execution authority, or real-value surface.
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
)

func main() {
	if err := execute(os.Args[1:], os.Getenv, os.Stdout); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "cross-chain local worker: %v\n", err)
		os.Exit(1)
	}
}

func execute(
	arguments []string,
	getenv func(string) string,
	output io.Writer,
) error {
	config, err := loadConfiguration(arguments, getenv)
	if err != nil {
		return err
	}
	if err := validateLocalTrustConfiguration(getenv); err != nil {
		return err
	}
	if output == nil {
		return errors.New("output is required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), config.timeout)
	defer cancel()
	manifestPath, err := locatePhase8ReleaseEvidence()
	if err != nil {
		return err
	}
	manifest, registrations, err := loadPhase8ReleaseManifest(manifestPath)
	if err != nil {
		return err
	}
	if config.mode == "cancellation" {
		return executePhase8CancellationImport(
			ctx,
			config,
			manifest,
			registrations,
			output,
		)
	}
	flow, err := decodePhase8ImportFlow(manifest.Flow, manifest)
	if err != nil {
		return err
	}
	if err := bootstrapManifestTrust(
		ctx,
		config.bootstrapDatabaseURL,
		manifest,
		registrations,
	); err != nil {
		return err
	}
	if err := bootstrapManifestEconomics(
		ctx,
		config.bootstrapDatabaseURL,
		manifest,
		flow,
	); err != nil {
		return err
	}
	objectStore, err := newMinIOEvidenceStore(config)
	if err != nil {
		return err
	}
	evidenceObjects, err := persistPhase8ManifestEvidence(
		ctx,
		objectStore,
		flow,
	)
	if err != nil {
		return err
	}
	firstRoles, err := openPhase8RoleSet(ctx, config)
	if err != nil {
		return err
	}
	if err := importPhase8Flow(
		ctx,
		firstRoles.runtime,
		firstRoles.observer,
		firstRoles.finality,
		flow,
		manifest,
	); err != nil {
		_ = firstRoles.Close()
		return err
	}
	snapshotDatabase, err := openLocalSnapshotDatabase(
		ctx,
		config.bootstrapDatabaseURL,
	)
	if err != nil {
		_ = firstRoles.Close()
		return err
	}
	defer func() { _ = snapshotDatabase.Close() }()
	preliminaryLedger, err := captureDurableLedger(ctx, snapshotDatabase)
	if err != nil {
		_ = firstRoles.Close()
		return err
	}
	reconciliation, err := recordManifestReconciliation(
		ctx,
		config.bootstrapDatabaseURL,
		firstRoles.runtime,
		manifest,
		flow,
		preliminaryLedger,
	)
	if err != nil {
		_ = firstRoles.Close()
		return err
	}
	before, err := captureDurableState(ctx, snapshotDatabase)
	if err != nil {
		_ = firstRoles.Close()
		return err
	}
	if before.ProviderAttempts != 9 {
		_ = firstRoles.Close()
		return errors.New("authenticated flow did not persist exactly nine provider attempts")
	}
	if err := firstRoles.Close(); err != nil {
		return err
	}
	restartedRoles, err := openPhase8RoleSet(ctx, config)
	if err != nil {
		return err
	}
	defer func() { _ = restartedRoles.Close() }()
	objectEvidence, err := rehydratePhase8ManifestEvidence(
		ctx,
		objectStore,
		evidenceObjects,
	)
	if err != nil {
		return err
	}
	if err := importPhase8Flow(
		ctx,
		restartedRoles.runtime,
		restartedRoles.observer,
		restartedRoles.finality,
		flow,
		manifest,
	); err != nil {
		return fmt.Errorf("restart replay: %w", err)
	}
	after, err := captureDurableState(ctx, snapshotDatabase)
	if err != nil {
		return err
	}
	if !sameDurableState(before, after) ||
		before.ProviderAttempts != after.ProviderAttempts ||
		after.ProviderAttempts != 9 {
		return errors.New("restart replay changed authenticated durable state")
	}
	parity, err := buildStateParity(manifest, flow, after)
	if err != nil {
		return err
	}
	durable := phase8DurableReleaseEvidence{
		InputDeploymentFlowSHA256: manifest.DeploymentFlowSHA256,
		SQL:                       after.SQL,
		Ledger:                    after.Ledger,
		ObjectStore:               objectEvidence,
		Restart: durableRestartEvidence{
			PreStateSHA256:              before.SQL.StateSHA256,
			PostStateSHA256:             after.SQL.StateSHA256,
			Rehydrated:                  true,
			DuplicatePrevented:          true,
			ProviderDeliveryCountBefore: before.ProviderAttempts,
			ProviderDeliveryCountAfter:  after.ProviderAttempts,
		},
		Reconciliation: reconciliation,
		StateParity:    parity,
	}
	if err := augmentPhase8ReleaseEvidence(manifestPath, durable); err != nil {
		return err
	}
	report := manifestWorkerReport{
		RunID:                    manifest.RunID,
		MessageCount:             len(flow.Messages),
		AuthenticatedImport:      true,
		RestartRehydrated:        true,
		DuplicatePrevented:       true,
		ProviderAttemptCount:     after.ProviderAttempts,
		JournalCount:             after.Ledger.JournalCount,
		JournalEntryCount:        after.Ledger.EntryCount,
		JournalsBalanced:         after.Ledger.Balanced,
		ObjectCount:              objectEvidence.ObjectCount,
		ObjectsRehydrated:        objectEvidence.Rehydrated,
		ReconciliationMatched:    reconciliation.Status == "MATCHED",
		StateParityMatched:       parity.Status == "MATCHED",
		DurableManifestAugmented: true,
	}
	return json.NewEncoder(output).Encode(report)
}

type phase8RoleSet struct {
	runtime        *sql.DB
	observer       *sql.DB
	finality       *sql.DB
	recovery       *sql.DB
	reorganization *sql.DB
}

func openPhase8RoleSet(
	ctx context.Context,
	config configuration,
) (*phase8RoleSet, error) {
	roles := &phase8RoleSet{}
	var err error
	roles.runtime, _, err = openRuntimeRepository(ctx, config)
	if err != nil {
		return nil, err
	}
	roles.observer, _, err = openObserverRepository(ctx, config)
	if err != nil {
		_ = roles.Close()
		return nil, err
	}
	roles.finality, _, err = openFinalityRepository(ctx, config)
	if err != nil {
		_ = roles.Close()
		return nil, err
	}
	roles.recovery, _, err = openRecoveryRepository(ctx, config)
	if err != nil {
		_ = roles.Close()
		return nil, err
	}
	roles.reorganization, _, err = openReorganizationRepository(ctx, config)
	if err != nil {
		_ = roles.Close()
		return nil, err
	}
	if err := assertRoleIsolation(
		ctx,
		roles.runtime,
		roles.observer,
		roles.finality,
		roles.recovery,
		roles.reorganization,
	); err != nil {
		_ = roles.Close()
		return nil, err
	}
	return roles, nil
}

func (roles *phase8RoleSet) Close() error {
	if roles == nil {
		return nil
	}
	var joined error
	for _, database := range []*sql.DB{
		roles.runtime,
		roles.observer,
		roles.finality,
		roles.recovery,
		roles.reorganization,
	} {
		if database != nil {
			joined = errors.Join(joined, database.Close())
		}
	}
	return joined
}

func openRuntimeRepository(
	ctx context.Context,
	config configuration,
) (*sql.DB, *store.SQL, error) {
	database, err := openRoleDatabase(
		ctx,
		config.databaseURL,
		"unified_crosschain_runtime",
	)
	if err != nil {
		return nil, nil, err
	}
	repository, err := store.NewSQL(database)
	if err != nil {
		_ = database.Close()
		return nil, nil, err
	}
	if err := repository.Health(ctx); err != nil {
		_ = database.Close()
		return nil, nil, err
	}
	return database, repository, nil
}

func openObserverRepository(
	ctx context.Context,
	config configuration,
) (*sql.DB, *store.SQL, error) {
	database, err := openRoleDatabase(
		ctx,
		config.observerDatabaseURL,
		"unified_crosschain_observer",
	)
	if err != nil {
		return nil, nil, err
	}
	repository, err := store.NewSQL(database)
	if err != nil {
		_ = database.Close()
		return nil, nil, err
	}
	if err := repository.Health(ctx); err != nil {
		_ = database.Close()
		return nil, nil, err
	}
	return database, repository, nil
}

func openFinalityRepository(
	ctx context.Context,
	config configuration,
) (*sql.DB, *store.SQL, error) {
	return openEvidenceRepository(
		ctx,
		config.finalityDatabaseURL,
		"unified_crosschain_finality_attester",
	)
}

func openRecoveryRepository(
	ctx context.Context,
	config configuration,
) (*sql.DB, *store.SQL, error) {
	return openEvidenceRepository(
		ctx,
		config.recoveryDatabaseURL,
		"unified_crosschain_recovery_verifier",
	)
}

func openReorganizationRepository(
	ctx context.Context,
	config configuration,
) (*sql.DB, *store.SQL, error) {
	return openEvidenceRepository(
		ctx,
		config.reorganizationDatabaseURL,
		"unified_crosschain_reorganization_verifier",
	)
}

func openEvidenceRepository(
	ctx context.Context,
	databaseURL string,
	role string,
) (*sql.DB, *store.SQL, error) {
	database, err := openRoleDatabase(ctx, databaseURL, role)
	if err != nil {
		return nil, nil, err
	}
	repository, err := store.NewSQL(database)
	if err != nil {
		_ = database.Close()
		return nil, nil, err
	}
	if err := repository.Health(ctx); err != nil {
		_ = database.Close()
		return nil, nil, err
	}
	return database, repository, nil
}

func assertRoleIsolation(
	ctx context.Context,
	runtime *sql.DB,
	observer *sql.DB,
	finality *sql.DB,
	recovery *sql.DB,
	reorganization *sql.DB,
) error {
	expected := []struct {
		database       *sql.DB
		role           string
		source         bool
		finality       bool
		recovery       bool
		header         bool
		reorganization bool
		evmExecution   bool
		evmAck         bool
	}{
		{runtime, "unified_crosschain_runtime", false, false, false, false, false, true, false},
		{observer, "unified_crosschain_observer", true, false, false, true, false, false, true},
		{finality, "unified_crosschain_finality_attester", false, true, false, false, false, false, false},
		{recovery, "unified_crosschain_recovery_verifier", false, false, true, false, false, false, false},
		{reorganization, "unified_crosschain_reorganization_verifier", false, false, false, false, true, false, false},
	}
	const query = `
SELECT
    current_user,
    has_function_privilege(
        current_user,
        'crosschain.record_source_proof(text,bytea,numeric,bytea,numeric,numeric,numeric,bytea,bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,timestamp with time zone,bytea,bytea)',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_finality_certificate(text,bytea,text,bytea,bigint,bit varying,integer,bytea,timestamp with time zone,bytea,bytea[])',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_recovery_request(bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,bytea,bytea,numeric,numeric,bytea,smallint,bytea,bigint,bytea,bit varying,integer,bytea,timestamp with time zone)',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_header_observation(text,numeric,bytea,numeric,bytea,bytea,bytea,bytea,timestamp with time zone)',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_reorganization(text,numeric,text[],text[],text,text,bytea[],bytea,timestamp with time zone)',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_evm_execution(bytea,numeric,bytea,numeric,bytea,bytea,text,text,jsonb,timestamp with time zone)',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_evm_acknowledgement(bytea,bytea,bytea,text,text,timestamp with time zone)',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_execution(bytea,numeric,bytea,numeric,bytea,bytea,timestamp with time zone)',
        'EXECUTE'
    ),
    has_function_privilege(
        current_user,
        'crosschain.record_acknowledgement(bytea,bytea,text,text,timestamp with time zone)',
        'EXECUTE'
    )`
	for _, role := range expected {
		if role.database == nil {
			return errors.New("role-isolation database is required")
		}
		var (
			current                  string
			canRecordSource          bool
			canRecordFinality        bool
			canRecordRecovery        bool
			canRecordHeader          bool
			canRecordReorganization  bool
			canRecordEVMExecution    bool
			canRecordEVMAck          bool
			canRecordLegacyExecution bool
			canRecordLegacyAck       bool
		)
		if err := role.database.QueryRowContext(ctx, query).Scan(
			&current,
			&canRecordSource,
			&canRecordFinality,
			&canRecordRecovery,
			&canRecordHeader,
			&canRecordReorganization,
			&canRecordEVMExecution,
			&canRecordEVMAck,
			&canRecordLegacyExecution,
			&canRecordLegacyAck,
		); err != nil {
			return fmt.Errorf("inspect %s privileges: %w", role.role, err)
		}
		if current != role.role ||
			canRecordSource != role.source ||
			canRecordFinality != role.finality ||
			canRecordRecovery != role.recovery ||
			canRecordHeader != role.header ||
			canRecordReorganization != role.reorganization ||
			canRecordEVMExecution != role.evmExecution ||
			canRecordEVMAck != role.evmAck ||
			canRecordLegacyExecution ||
			canRecordLegacyAck {
			return fmt.Errorf(
				"cross-chain role privilege drift for %s: source=%t finality=%t recovery=%t header=%t reorganization=%t evm_execution=%t evm_ack=%t legacy_execution=%t legacy_ack=%t",
				current,
				canRecordSource,
				canRecordFinality,
				canRecordRecovery,
				canRecordHeader,
				canRecordReorganization,
				canRecordEVMExecution,
				canRecordEVMAck,
				canRecordLegacyExecution,
				canRecordLegacyAck,
			)
		}
	}
	return nil
}

func openRoleDatabase(
	ctx context.Context,
	databaseURL string,
	expectedRole string,
) (*sql.DB, error) {
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, errors.New("open local PostgreSQL")
	}
	database.SetMaxOpenConns(2)
	database.SetMaxIdleConns(1)
	database.SetConnMaxLifetime(time.Minute)
	if err := database.PingContext(ctx); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("ping local PostgreSQL: %w", err)
	}
	var effectiveRole string
	if err := database.QueryRowContext(ctx, "SELECT current_user").Scan(&effectiveRole); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("read effective PostgreSQL role: %w", err)
	}
	if effectiveRole != expectedRole {
		_ = database.Close()
		return nil, fmt.Errorf(
			"local worker requires effective role %s",
			expectedRole,
		)
	}
	return database, nil
}

func hexString(value [32]byte) string {
	const digits = "0123456789abcdef"
	result := make([]byte, 64)
	for index, item := range value {
		result[index*2] = digits[item>>4]
		result[index*2+1] = digits[item&0x0f]
	}
	return string(result)
}

func hexHash(value [32]byte) string {
	return "0x" + hexString(value)
}
