package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"sort"
	"strings"
)

var durableTableNames = []string{
	"crosschain.acknowledgements",
	"crosschain.action_projections",
	"crosschain.bridge_backing_snapshots",
	"crosschain.bridge_exposure_policies",
	"crosschain.bridge_exposure_snapshots",
	"crosschain.bridge_locks",
	"crosschain.bridge_reconciliation_differences",
	"crosschain.bridge_reconciliations",
	"crosschain.canonical_releases",
	"crosschain.canonical_burns",
	"crosschain.chain_versions",
	"crosschain.chains",
	"crosschain.collateral_positions",
	"crosschain.collateral_release_authorizations",
	"crosschain.collateral_release_results",
	"crosschain.compensations",
	"crosschain.direct_home_repayment_evidence",
	"crosschain.direct_home_repayment_results",
	"crosschain.disbursement_authorizations",
	"crosschain.disbursement_results",
	"crosschain.execution_results",
	"crosschain.finality_certificates",
	"crosschain.header_observations",
	"crosschain.incidents",
	"crosschain.inbox",
	"crosschain.loan_cancellation_completions",
	"crosschain.loan_cancellation_requests",
	"crosschain.loan_routes",
	"crosschain.message_transitions",
	"crosschain.messages",
	"crosschain.outbox",
	"crosschain.provider_attempts",
	"crosschain.repayment_results",
	"crosschain.recovery_authorizer_sets",
	"crosschain.recovery_requests",
	"crosschain.reorganizations",
	"crosschain.route_versions",
	"crosschain.routes",
	"crosschain.signer_sets",
	"crosschain.source_proofs",
	"crosschain.tombstones",
	"crosschain.wrapped_burns",
	"crosschain.wrapped_mints",
	"ledger.bridge_journal_links",
	"ledger.crosschain_recovery_journal_links",
	"ledger.satellite_custody_links",
	"ledger.satellite_settlement_links",
	"public.journal",
	"public.journal_entry",
}

var neverEmptyDurableTables = map[string]struct{}{
	"crosschain.acknowledgements":                  {},
	"crosschain.action_projections":                {},
	"crosschain.bridge_backing_snapshots":          {},
	"crosschain.bridge_exposure_policies":          {},
	"crosschain.bridge_exposure_snapshots":         {},
	"crosschain.bridge_locks":                      {},
	"crosschain.bridge_reconciliations":            {},
	"crosschain.canonical_releases":                {},
	"crosschain.chain_versions":                    {},
	"crosschain.chains":                            {},
	"crosschain.collateral_positions":              {},
	"crosschain.collateral_release_authorizations": {},
	"crosschain.collateral_release_results":        {},
	"crosschain.disbursement_authorizations":       {},
	"crosschain.disbursement_results":              {},
	"crosschain.execution_results":                 {},
	"crosschain.finality_certificates":             {},
	"crosschain.loan_routes":                       {},
	"crosschain.message_transitions":               {},
	"crosschain.messages":                          {},
	"crosschain.provider_attempts":                 {},
	"crosschain.repayment_results":                 {},
	"crosschain.route_versions":                    {},
	"crosschain.routes":                            {},
	"crosschain.signer_sets":                       {},
	"crosschain.source_proofs":                     {},
	"crosschain.wrapped_burns":                     {},
	"crosschain.wrapped_mints":                     {},
	"ledger.bridge_journal_links":                  {},
	"ledger.satellite_custody_links":               {},
	"ledger.satellite_settlement_links":            {},
	"public.journal":                               {},
	"public.journal_entry":                         {},
}

type durableTableEvidence struct {
	OrderedSHA256 string `json:"ordered_sha256"`
	RowCount      int64  `json:"row_count"`
}

type durableSQLEvidence struct {
	StateSHA256        string                          `json:"state_sha256"`
	AllowedEmptyTables []string                        `json:"allowed_empty_tables"`
	Tables             map[string]durableTableEvidence `json:"tables"`
}

type durableLedgerEvidence struct {
	JournalSetSHA256  string `json:"journal_set_sha256"`
	JournalCount      int64  `json:"journal_count"`
	EntryCount        int64  `json:"entry_count"`
	TotalDebitsUnits  string `json:"total_debits_units"`
	TotalCreditsUnits string `json:"total_credits_units"`
	Balanced          bool   `json:"balanced"`
}

type durableStateSnapshot struct {
	SQL              durableSQLEvidence
	Ledger           durableLedgerEvidence
	ProviderAttempts int64
}

type durableStateCommitment struct {
	LedgerSHA256 string `json:"ledger_sha256"`
	SQLSHA256    string `json:"sql_sha256"`
}

var identifierPattern = regexp.MustCompile(`^[a-z_][a-z0-9_]*$`)

func openLocalSnapshotDatabase(
	ctx context.Context,
	databaseURL string,
) (*sql.DB, error) {
	if ctx == nil || databaseURL == "" {
		return nil, errors.New("local snapshot database URL is required")
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, errors.New("open local snapshot database")
	}
	database.SetMaxOpenConns(1)
	database.SetMaxIdleConns(1)
	if err := database.PingContext(ctx); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("ping local snapshot database: %w", err)
	}
	var (
		role       string
		canReadAll bool
	)
	if err := database.QueryRowContext(
		ctx,
		`SELECT current_user,
		        has_table_privilege(current_user, 'crosschain.messages', 'SELECT')
		        AND has_table_privilege(
		            current_user,
		            'ledger.bridge_journal_links',
		            'SELECT'
		        )
		        AND has_table_privilege(current_user, 'public.journal', 'SELECT')
		        AND has_table_privilege(
		            current_user,
		            'public.journal_entry',
		            'SELECT'
		        )
		        AND has_table_privilege(
		            current_user,
		            'public.journal_balance',
		            'SELECT'
		        )`,
	).Scan(&role, &canReadAll); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("validate local snapshot database: %w", err)
	}
	if (role != "unified_local" && role != "unified_crosschain_owner") ||
		!canReadAll {
		_ = database.Close()
		return nil, errors.New(
			"durable snapshot requires the validated local read-evidence owner",
		)
	}
	return database, nil
}

func captureDurableLedger(
	ctx context.Context,
	database *sql.DB,
) (durableLedgerEvidence, error) {
	if ctx == nil || database == nil {
		return durableLedgerEvidence{}, errors.New(
			"durable ledger snapshot database is required",
		)
	}
	transaction, err := database.BeginTx(ctx, &sql.TxOptions{
		Isolation: sql.LevelRepeatableRead,
		ReadOnly:  true,
	})
	if err != nil {
		return durableLedgerEvidence{}, err
	}
	defer func() { _ = transaction.Rollback() }()
	if _, err := transaction.ExecContext(ctx, "SET LOCAL TIME ZONE 'UTC'"); err != nil {
		return durableLedgerEvidence{}, err
	}
	ledger, err := captureLedgerEvidence(ctx, transaction)
	if err != nil {
		return durableLedgerEvidence{}, err
	}
	if err := transaction.Commit(); err != nil {
		return durableLedgerEvidence{}, err
	}
	return ledger, nil
}

func captureDurableState(
	ctx context.Context,
	database *sql.DB,
) (durableStateSnapshot, error) {
	if ctx == nil || database == nil {
		return durableStateSnapshot{}, errors.New("durable snapshot database is required")
	}
	transaction, err := database.BeginTx(ctx, &sql.TxOptions{
		Isolation: sql.LevelRepeatableRead,
		ReadOnly:  true,
	})
	if err != nil {
		return durableStateSnapshot{}, err
	}
	defer func() { _ = transaction.Rollback() }()
	if _, err := transaction.ExecContext(ctx, "SET LOCAL TIME ZONE 'UTC'"); err != nil {
		return durableStateSnapshot{}, err
	}
	sqlEvidence := durableSQLEvidence{
		Tables: make(map[string]durableTableEvidence, len(durableTableNames)),
	}
	for _, tableName := range durableTableNames {
		evidence, err := hashDurableTable(ctx, transaction, tableName)
		if err != nil {
			return durableStateSnapshot{}, err
		}
		sqlEvidence.Tables[tableName] = evidence
		if evidence.RowCount == 0 {
			if _, required := neverEmptyDurableTables[tableName]; required {
				return durableStateSnapshot{}, fmt.Errorf(
					"required durable table %s is empty",
					tableName,
				)
			}
			sqlEvidence.AllowedEmptyTables = append(
				sqlEvidence.AllowedEmptyTables,
				tableName,
			)
		}
	}
	sort.Strings(sqlEvidence.AllowedEmptyTables)
	stateJSON, err := json.Marshal(sqlEvidence.Tables)
	if err != nil {
		return durableStateSnapshot{}, err
	}
	stateHash := sha256.Sum256(stateJSON)
	sqlEvidence.StateSHA256 = hex.EncodeToString(stateHash[:])
	ledger, err := captureLedgerEvidence(ctx, transaction)
	if err != nil {
		return durableStateSnapshot{}, err
	}
	var providerAttempts int64
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT count(*) FROM crosschain.provider_attempts",
	).Scan(&providerAttempts); err != nil {
		return durableStateSnapshot{}, err
	}
	if err := transaction.Commit(); err != nil {
		return durableStateSnapshot{}, err
	}
	return durableStateSnapshot{
		SQL:              sqlEvidence,
		Ledger:           ledger,
		ProviderAttempts: providerAttempts,
	}, nil
}

func hashDurableTable(
	ctx context.Context,
	transaction *sql.Tx,
	tableName string,
) (durableTableEvidence, error) {
	parts := strings.Split(tableName, ".")
	if len(parts) != 2 || !identifierPattern.MatchString(parts[0]) ||
		!identifierPattern.MatchString(parts[1]) {
		return durableTableEvidence{}, errors.New("invalid durable table allowlist entry")
	}
	rows, err := transaction.QueryContext(
		ctx,
		`SELECT attribute.attname
		   FROM pg_index AS index_record
		   JOIN pg_class AS relation ON relation.oid = index_record.indrelid
		   JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
		   JOIN unnest(index_record.indkey) WITH ORDINALITY AS key(attnum, position)
		     ON true
		   JOIN pg_attribute AS attribute
		     ON attribute.attrelid = relation.oid AND attribute.attnum = key.attnum
		  WHERE namespace.nspname = $1
		    AND relation.relname = $2
		    AND index_record.indisprimary
		  ORDER BY key.position`,
		parts[0],
		parts[1],
	)
	if err != nil {
		return durableTableEvidence{}, err
	}
	var primaryKey []string
	for rows.Next() {
		var column string
		if err := rows.Scan(&column); err != nil {
			_ = rows.Close()
			return durableTableEvidence{}, err
		}
		if !identifierPattern.MatchString(column) {
			_ = rows.Close()
			return durableTableEvidence{}, errors.New("invalid primary-key identifier")
		}
		primaryKey = append(primaryKey, `"`+column+`"`)
	}
	if err := rows.Close(); err != nil {
		return durableTableEvidence{}, err
	}
	if len(primaryKey) == 0 {
		return durableTableEvidence{}, fmt.Errorf(
			"durable table %s has no primary key",
			tableName,
		)
	}
	query := fmt.Sprintf(
		`SELECT to_jsonb(record)::text FROM "%s"."%s" AS record ORDER BY %s`,
		parts[0],
		parts[1],
		strings.Join(primaryKey, ", "),
	)
	tableRows, err := transaction.QueryContext(ctx, query)
	if err != nil {
		return durableTableEvidence{}, err
	}
	defer func() { _ = tableRows.Close() }()
	canonicalRows := make([]any, 0)
	var count int64
	for tableRows.Next() {
		var row string
		if err := tableRows.Scan(&row); err != nil {
			return durableTableEvidence{}, err
		}
		var decoded any
		decoder := json.NewDecoder(strings.NewReader(row))
		decoder.UseNumber()
		if err := decoder.Decode(&decoded); err != nil {
			return durableTableEvidence{}, fmt.Errorf(
				"decode %s canonical row: %w",
				tableName,
				err,
			)
		}
		canonicalRows = append(canonicalRows, decoded)
		count++
	}
	if err := tableRows.Err(); err != nil {
		return durableTableEvidence{}, err
	}
	encoded, err := json.Marshal(canonicalRows)
	if err != nil {
		return durableTableEvidence{}, err
	}
	hash := sha256.Sum256(encoded)
	return durableTableEvidence{
		OrderedSHA256: hex.EncodeToString(hash[:]),
		RowCount:      count,
	}, nil
}

const linkedJournalCTE = `
WITH linked_journals AS (
    SELECT journal_id FROM ledger.bridge_journal_links
    UNION
    SELECT journal_id FROM ledger.satellite_custody_links
    UNION
    SELECT journal_id FROM ledger.satellite_settlement_links
    UNION
    SELECT journal_id FROM ledger.crosschain_recovery_journal_links
)`

func captureLedgerEvidence(
	ctx context.Context,
	transaction *sql.Tx,
) (durableLedgerEvidence, error) {
	rows, err := transaction.QueryContext(
		ctx,
		linkedJournalCTE+`
SELECT jsonb_build_object(
           'journal', to_jsonb(journal),
           'entries', (
               SELECT jsonb_agg(to_jsonb(entry) ORDER BY entry.line_number)
               FROM public.journal_entry AS entry
               WHERE entry.journal_id = journal.journal_id
           )
       )::text
FROM public.journal AS journal
JOIN linked_journals USING (journal_id)
ORDER BY journal.journal_id`,
	)
	if err != nil {
		return durableLedgerEvidence{}, err
	}
	canonicalJournals := make([]any, 0)
	var journalCount int64
	for rows.Next() {
		var row string
		if err := rows.Scan(&row); err != nil {
			_ = rows.Close()
			return durableLedgerEvidence{}, err
		}
		var decoded any
		decoder := json.NewDecoder(strings.NewReader(row))
		decoder.UseNumber()
		if err := decoder.Decode(&decoded); err != nil {
			_ = rows.Close()
			return durableLedgerEvidence{}, err
		}
		canonicalJournals = append(canonicalJournals, decoded)
		journalCount++
	}
	if err := rows.Close(); err != nil {
		return durableLedgerEvidence{}, err
	}
	var (
		entryCount int64
		debits     string
		credits    string
		unbalanced int64
	)
	if err := transaction.QueryRowContext(
		ctx,
		linkedJournalCTE+`
SELECT count(*)::bigint,
       coalesce(sum(CASE WHEN entry.side = 'DEBIT' THEN entry.units ELSE 0 END), 0)::text,
       coalesce(sum(CASE WHEN entry.side = 'CREDIT' THEN entry.units ELSE 0 END), 0)::text,
       (
           SELECT count(*)::bigint
           FROM public.journal_balance AS balance
           JOIN linked_journals USING (journal_id)
           WHERE balance.debit_units <> balance.credit_units
       )
FROM public.journal_entry AS entry
JOIN linked_journals USING (journal_id)`,
	).Scan(&entryCount, &debits, &credits, &unbalanced); err != nil {
		return durableLedgerEvidence{}, err
	}
	debitValue, debitOK := new(big.Int).SetString(debits, 10)
	creditValue, creditOK := new(big.Int).SetString(credits, 10)
	balanced := debitOK && creditOK && debitValue.Cmp(creditValue) == 0 &&
		unbalanced == 0 && journalCount > 0 && entryCount > 0
	if !balanced {
		return durableLedgerEvidence{}, errors.New("linked Phase 8 journals are not balanced")
	}
	encodedJournals, err := json.Marshal(canonicalJournals)
	if err != nil {
		return durableLedgerEvidence{}, err
	}
	journalHash := sha256.Sum256(encodedJournals)
	return durableLedgerEvidence{
		JournalSetSHA256:  hex.EncodeToString(journalHash[:]),
		JournalCount:      journalCount,
		EntryCount:        entryCount,
		TotalDebitsUnits:  debits,
		TotalCreditsUnits: credits,
		Balanced:          true,
	}, nil
}

func durableCommitment(snapshot durableStateSnapshot) (string, error) {
	ledgerJSON, err := json.Marshal(snapshot.Ledger)
	if err != nil {
		return "", err
	}
	ledgerHash := sha256.Sum256(ledgerJSON)
	commitmentJSON, err := json.Marshal(durableStateCommitment{
		LedgerSHA256: hex.EncodeToString(ledgerHash[:]),
		SQLSHA256:    snapshot.SQL.StateSHA256,
	})
	if err != nil {
		return "", err
	}
	commitment := sha256.Sum256(commitmentJSON)
	return hex.EncodeToString(commitment[:]), nil
}
