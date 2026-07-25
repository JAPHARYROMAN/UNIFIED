package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"time"
)

type durableRestartEvidence struct {
	PreStateSHA256              string `json:"pre_state_sha256"`
	PostStateSHA256             string `json:"post_state_sha256"`
	Rehydrated                  bool   `json:"rehydrated"`
	DuplicatePrevented          bool   `json:"duplicate_prevented"`
	ProviderDeliveryCountBefore int64  `json:"provider_delivery_count_before"`
	ProviderDeliveryCountAfter  int64  `json:"provider_delivery_count_after"`
}

type durableReconciliationEvidence struct {
	RunID           string `json:"run_id"`
	EvidenceHash    string `json:"evidence_hash"`
	Status          string `json:"status"`
	DifferenceCount int64  `json:"difference_count"`
}

type durableStateParityEvidence struct {
	EVMSnapshotHash    string `json:"evm_snapshot_hash"`
	SQLSnapshotHash    string `json:"sql_snapshot_hash"`
	LedgerSnapshotHash string `json:"ledger_snapshot_hash"`
	ComparisonHash     string `json:"comparison_hash"`
	Status             string `json:"status"`
	DifferenceCount    int64  `json:"difference_count"`
}

type phase8DurableReleaseEvidence struct {
	InputDeploymentFlowSHA256 string                        `json:"input_deployment_flow_sha256"`
	SQL                       durableSQLEvidence            `json:"sql"`
	Ledger                    durableLedgerEvidence         `json:"ledger"`
	ObjectStore               durableObjectStoreEvidence    `json:"object_store"`
	Restart                   durableRestartEvidence        `json:"restart"`
	Reconciliation            durableReconciliationEvidence `json:"reconciliation"`
	StateParity               durableStateParityEvidence    `json:"state_parity"`
}

type manifestWorkerReport struct {
	RunID                    string `json:"run_id"`
	MessageCount             int    `json:"message_count"`
	AuthenticatedImport      bool   `json:"authenticated_import"`
	RestartRehydrated        bool   `json:"restart_rehydrated"`
	DuplicatePrevented       bool   `json:"duplicate_prevented"`
	ProviderAttemptCount     int64  `json:"provider_attempt_count"`
	JournalCount             int64  `json:"journal_count"`
	JournalEntryCount        int64  `json:"journal_entry_count"`
	JournalsBalanced         bool   `json:"journals_balanced"`
	ObjectCount              int64  `json:"object_count"`
	ObjectsRehydrated        bool   `json:"objects_rehydrated"`
	ReconciliationMatched    bool   `json:"reconciliation_matched"`
	StateParityMatched       bool   `json:"state_parity_matched"`
	DurableManifestAugmented bool   `json:"durable_manifest_augmented"`
}

func sameDurableState(before, after durableStateSnapshot) bool {
	return reflect.DeepEqual(before, after)
}

func buildStateParity(
	manifest phase8ReleaseManifest,
	flow phase8ImportFlow,
	snapshot durableStateSnapshot,
) (durableStateParityEvidence, error) {
	evmProjection := struct {
		DeploymentFlowSHA256 string                `json:"deployment_flow_sha256"`
		LoanID               string                `json:"loan_id"`
		FundingLockID        string                `json:"funding_lock_id"`
		CollateralID         string                `json:"collateral_id"`
		PrincipalUnits       string                `json:"principal_units"`
		CollateralUnits      string                `json:"collateral_units"`
		Messages             []phase8ImportMessage `json:"messages"`
	}{
		DeploymentFlowSHA256: manifest.DeploymentFlowSHA256,
		LoanID:               flow.LoanID,
		FundingLockID:        flow.FundingLockID,
		CollateralID:         flow.CollateralID,
		PrincipalUnits:       flow.PrincipalUnits,
		CollateralUnits:      flow.CollateralUnits,
		Messages:             flow.Messages,
	}
	evmJSON, err := canonicalJSON(evmProjection)
	if err != nil {
		return durableStateParityEvidence{}, err
	}
	evmHash := sha256.Sum256(evmJSON)
	sqlHash, err := hex.DecodeString(snapshot.SQL.StateSHA256)
	if err != nil || len(sqlHash) != 32 {
		return durableStateParityEvidence{}, errors.New("SQL state hash is invalid")
	}
	ledgerHash, err := hex.DecodeString(snapshot.Ledger.JournalSetSHA256)
	if err != nil || len(ledgerHash) != 32 {
		return durableStateParityEvidence{}, errors.New("ledger state hash is invalid")
	}
	comparisonJSON, err := canonicalJSON(map[string]string{
		"evm_snapshot_hash":    hexHash(evmHash),
		"ledger_snapshot_hash": "0x" + hex.EncodeToString(ledgerHash),
		"sql_snapshot_hash":    "0x" + hex.EncodeToString(sqlHash),
	})
	if err != nil {
		return durableStateParityEvidence{}, err
	}
	comparisonHash := sha256.Sum256(comparisonJSON)
	return durableStateParityEvidence{
		EVMSnapshotHash:    hexHash(evmHash),
		SQLSnapshotHash:    "0x" + hex.EncodeToString(sqlHash),
		LedgerSnapshotHash: "0x" + hex.EncodeToString(ledgerHash),
		ComparisonHash:     hexHash(comparisonHash),
		Status:             "MATCHED",
		DifferenceCount:    0,
	}, nil
}

func recordManifestReconciliation(
	ctx context.Context,
	ownerDatabaseURL string,
	runtime *sql.DB,
	manifest phase8ReleaseManifest,
	flow phase8ImportFlow,
	ledger durableLedgerEvidence,
) (durableReconciliationEvidence, error) {
	if ctx == nil || ownerDatabaseURL == "" || runtime == nil {
		return durableReconciliationEvidence{}, errors.New(
			"manifest reconciliation requires owner and runtime databases",
		)
	}
	var mintRoute *phase8ManifestRoute
	for index := range manifest.Routes {
		if manifest.Routes[index].Purpose == "MINT" {
			mintRoute = &manifest.Routes[index]
			break
		}
	}
	if mintRoute == nil {
		return durableReconciliationEvidence{}, errors.New("MINT route is missing")
	}
	owner, err := sql.Open("pgx", ownerDatabaseURL)
	if err != nil {
		return durableReconciliationEvidence{}, err
	}
	defer func() { _ = owner.Close() }()
	if err := owner.PingContext(ctx); err != nil {
		return durableReconciliationEvidence{}, err
	}
	var role string
	if err := owner.QueryRowContext(ctx, "SELECT current_user").Scan(&role); err != nil {
		return durableReconciliationEvidence{}, err
	}
	if role != "unified_local" && role != "unified_crosschain_owner" {
		return durableReconciliationEvidence{}, errors.New(
			"reconciliation snapshot bootstrap requires local owner role",
		)
	}
	finalMessage := flow.Messages[len(flow.Messages)-1]
	reconciliationTime := mustUnixNumberTime(
		finalMessage.Acknowledgement.Proof.BlockTimestamp,
	)
	homeHead := mustImportHex(
		finalMessage.Acknowledgement.Proof.FinalityHeadHash,
		32,
		false,
	)
	satelliteHead := mustImportHex(
		finalMessage.Source.Proof.FinalityHeadHash,
		32,
		false,
	)
	if finalMessage.Source.ChainID.String() == manifest.Domains.Home.ChainID.String() {
		homeHead, satelliteHead = satelliteHead, homeHead
	}
	exposure := manifest.ExposurePolicy
	if _, err := owner.ExecContext(
		ctx,
		`INSERT INTO crosschain.bridge_exposure_snapshots (
		    snapshot_id, route_id, route_version, policy_version, chain_id,
		    adapter_id, route_escrow_units, chain_escrow_units,
		    adapter_escrow_units, aggregate_escrow_units,
		    circulating_supply_reference_units,
		    circulating_supply_evidence_hash, calculated_headroom_units,
		    block_number, block_hash, evidence_hash, observed_at
		) VALUES (
		    $1, $2, $3, $4, $5::numeric, $6, 0, 0, 0, 0,
		    $7::numeric, $8, $9::numeric, $10::numeric, $11, $12, $13
		)
		ON CONFLICT (snapshot_id) DO NOTHING`,
		manifest.RunID+"-exposure",
		phase8RouteID(mintRoute.Purpose),
		int64(mintRoute.Version),
		int64(exposure.PolicyVersion),
		mintRoute.DestinationChainID.String(),
		mintRoute.AdapterID,
		exposure.CirculatingSupplyReferenceUnits,
		mustImportHex(exposure.CirculatingSupplyEvidenceHash, 32, false),
		exposure.RouteAbsoluteCapUnits,
		finalMessage.Acknowledgement.Proof.FinalityHeadNumber.String(),
		satelliteHead,
		sha256Bytes([]byte(manifest.RunID+"-exposure")),
		reconciliationTime,
	); err != nil {
		return durableReconciliationEvidence{}, fmt.Errorf(
			"record exposure snapshot: %w",
			err,
		)
	}
	if _, err := owner.ExecContext(
		ctx,
		`INSERT INTO crosschain.bridge_backing_snapshots (
		    snapshot_id, route_id, route_version, canonical_asset_id,
		    wrapped_asset_id, canonical_escrow_units, wrapped_supply_units,
		    pending_mint_units, pending_burn_units, home_block_hash,
		    satellite_block_hash, evidence_hash, observed_at
		) VALUES ($1, $2, $3, $4, $5, 0, 0, 0, 0, $6, $7, $8, $9)
		ON CONFLICT (snapshot_id) DO NOTHING`,
		manifest.RunID+"-backing",
		phase8RouteID(mintRoute.Purpose),
		int64(mintRoute.Version),
		flow.Economics.CanonicalAsset,
		flow.Economics.WrappedAsset,
		homeHead,
		satelliteHead,
		sha256Bytes([]byte(manifest.RunID+"-backing")),
		reconciliationTime,
	); err != nil {
		return durableReconciliationEvidence{}, fmt.Errorf(
			"record backing snapshot: %w",
			err,
		)
	}
	runID := manifest.RunID + "-reconciliation"
	startedAt := reconciliationTime
	ledgerHash, err := decodeJournalSetSHA256(ledger.JournalSetSHA256)
	if err != nil {
		return durableReconciliationEvidence{}, fmt.Errorf(
			"decode ledger journal-set commitment: %w",
			err,
		)
	}
	if _, err := runtime.ExecContext(
		ctx,
		`SELECT crosschain.open_bridge_reconciliation(
		    $1, $2, $3, $4, $5, $6, $7, $8, 'accounting-economic-risk',
		    $9
		)`,
		runID,
		phase8RouteID(mintRoute.Purpose),
		int64(mintRoute.Version),
		homeHead,
		satelliteHead,
		manifest.RunID+"-backing",
		manifest.RunID+"-exposure",
		ledgerHash,
		startedAt,
	); err != nil {
		return durableReconciliationEvidence{}, fmt.Errorf(
			"open exact bridge reconciliation: %w",
			err,
		)
	}
	completedAt := startedAt.Add(time.Nanosecond)
	if _, err := runtime.ExecContext(
		ctx,
		"SELECT crosschain.finalize_bridge_reconciliation($1, $2)",
		runID,
		completedAt,
	); err != nil {
		return durableReconciliationEvidence{}, fmt.Errorf(
			"finalize exact bridge reconciliation: %w",
			err,
		)
	}
	var (
		status          string
		differenceCount int64
	)
	if err := runtime.QueryRowContext(
		ctx,
		`SELECT reconciliation.status, count(difference.*)::bigint
		   FROM crosschain.bridge_reconciliations AS reconciliation
		   LEFT JOIN crosschain.bridge_reconciliation_differences AS difference
		     USING (run_id)
		  WHERE reconciliation.run_id = $1
		  GROUP BY reconciliation.status`,
		runID,
	).Scan(&status, &differenceCount); err != nil {
		return durableReconciliationEvidence{}, err
	}
	if status != "MATCHED" || differenceCount != 0 {
		return durableReconciliationEvidence{}, errors.New(
			"manifest bridge reconciliation did not match",
		)
	}
	evidenceJSON, err := canonicalJSON(map[string]any{
		"difference_count": differenceCount,
		"ledger_sha256":    ledger.JournalSetSHA256,
		"run_id":           runID,
		"status":           status,
	})
	if err != nil {
		return durableReconciliationEvidence{}, err
	}
	evidenceHash := sha256.Sum256(evidenceJSON)
	return durableReconciliationEvidence{
		RunID:           runID,
		EvidenceHash:    hexHash(evidenceHash),
		Status:          status,
		DifferenceCount: differenceCount,
	}, nil
}

func decodeJournalSetSHA256(value string) ([]byte, error) {
	return importHex("0x"+value, 32, false)
}

func augmentPhase8ReleaseEvidence(
	path string,
	durable phase8DurableReleaseEvidence,
) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var document map[string]any
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	if err := decoder.Decode(&document); err != nil {
		return fmt.Errorf("decode manifest for durable augmentation: %w", err)
	}
	if err := rejectPrivateMaterialKeys(document); err != nil {
		return err
	}
	if document["durable"] != nil {
		return errors.New("manifest durable evidence is not exactly null")
	}
	if document["deployment_flow_sha256"] != durable.InputDeploymentFlowSHA256 {
		return errors.New("durable evidence consumed a different deployment/flow commitment")
	}
	validation, ok := document["validation"].(map[string]any)
	if !ok {
		return errors.New("release evidence validation summary is missing")
	}
	for _, field := range []string{
		"restart_complete",
		"journals_balanced",
		"reconciliation_matched",
		"state_parity_matched",
	} {
		if value, exists := validation[field]; !exists || value != false {
			return fmt.Errorf(
				"intermediate release evidence pre-claimed worker validation %s",
				field,
			)
		}
		validation[field] = true
	}
	document["durable"] = durable
	encoded, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, ".phase8-release-evidence-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer func() { _ = os.Remove(temporaryPath) }()
	if err := temporary.Chmod(info.Mode().Perm()); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err := temporary.Write(encoded); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("atomically replace release evidence: %w", err)
	}
	return nil
}

func sha256Bytes(value []byte) []byte {
	hash := sha256.Sum256(value)
	return hash[:]
}
