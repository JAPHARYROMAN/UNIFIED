package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
)

type phase8CancellationImportBundle struct {
	LoanID         string                `json:"loan_id"`
	FundingLockID  string                `json:"funding_lock_id"`
	MintMessageID  string                `json:"mint_message_id"`
	PrincipalUnits string                `json:"principal_units"`
	HomeLoan       string                `json:"home_loan"`
	Lender         string                `json:"lender"`
	WrappedAsset   string                `json:"wrapped_asset"`
	PolicyHash     string                `json:"policy_hash"`
	Messages       []phase8ImportMessage `json:"messages"`
	Economics      phase8FlowEconomics   `json:"-"`
}

type phase8CancellationWorkerReport struct {
	CancellationID     string `json:"cancellation_id"`
	MessageCount       int    `json:"message_count"`
	Authenticated      bool   `json:"authenticated"`
	DuplicatePrevented bool   `json:"duplicate_prevented"`
	ObjectCount        int64  `json:"object_count"`
	ObjectsRehydrated  bool   `json:"objects_rehydrated"`
}

func decodePhase8CancellationImportBundle(
	raw []byte,
	manifest phase8ReleaseManifest,
) (phase8CancellationImportBundle, error) {
	var bundle phase8CancellationImportBundle
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&bundle); err != nil {
		return bundle, fmt.Errorf("decode cancellation import bundle: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return bundle, errors.New("cancellation import bundle has trailing JSON")
	}
	context := phase8FlowEconomics{
		LoanID:         bundle.LoanID,
		FundingLockID:  bundle.FundingLockID,
		HomeLoan:       bundle.HomeLoan,
		Lender:         bundle.Lender,
		WrappedAsset:   bundle.WrappedAsset,
		PrincipalUnits: bundle.PrincipalUnits,
		PolicyHash:     bundle.PolicyHash,
	}
	if err := validatePhase8CancellationOrder(
		bundle.Messages,
		bundle.MintMessageID,
	); err != nil {
		return phase8CancellationImportBundle{}, err
	}
	for index, message := range bundle.Messages {
		if err := validatePhase8ImportMessage(
			message,
			index,
			uint32(index+1),
			false,
			manifest,
			context,
		); err != nil {
			return phase8CancellationImportBundle{}, err
		}
	}
	bundle.Economics = context
	return bundle, nil
}

func importPhase8CancellationBundle(
	ctx context.Context,
	runtime *sql.DB,
	observer *sql.DB,
	finality *sql.DB,
	bundle phase8CancellationImportBundle,
	manifest phase8ReleaseManifest,
) error {
	if len(bundle.Messages) != 2 {
		return errors.New("cancellation import requires exactly two messages")
	}
	for _, message := range bundle.Messages {
		if err := importPhase8Message(
			ctx,
			runtime,
			observer,
			finality,
			message,
			manifest,
			bundle.Economics,
		); err != nil {
			return fmt.Errorf(
				"import cancellation message sequence %d: %w",
				message.Sequence,
				err,
			)
		}
	}
	return nil
}

func executePhase8CancellationImport(
	ctx context.Context,
	config configuration,
	manifest phase8ReleaseManifest,
	registrations []store.RouteRegistration,
	output io.Writer,
) error {
	raw, err := os.ReadFile(config.cancellationBundlePath)
	if err != nil {
		return fmt.Errorf("read cancellation import bundle: %w", err)
	}
	bundle, err := decodePhase8CancellationImportBundle(raw, manifest)
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
	objectStore, err := newMinIOEvidenceStore(config)
	if err != nil {
		return err
	}
	evidenceObjects, err := persistPhase8MessageEvidence(
		ctx,
		objectStore,
		bundle.Messages,
	)
	if err != nil {
		return err
	}
	roles, err := openPhase8RoleSet(ctx, config)
	if err != nil {
		return err
	}
	if err := importPhase8CancellationBundle(
		ctx,
		roles.runtime,
		roles.observer,
		roles.finality,
		bundle,
		manifest,
	); err != nil {
		_ = roles.Close()
		return err
	}
	if err := roles.Close(); err != nil {
		return err
	}
	objectEvidence, err := rehydratePhase8ManifestEvidence(
		ctx,
		objectStore,
		evidenceObjects,
	)
	if err != nil {
		return err
	}
	restartedRoles, err := openPhase8RoleSet(ctx, config)
	if err != nil {
		return err
	}
	defer func() { _ = restartedRoles.Close() }()
	if err := importPhase8CancellationBundle(
		ctx,
		restartedRoles.runtime,
		restartedRoles.observer,
		restartedRoles.finality,
		bundle,
		manifest,
	); err != nil {
		return fmt.Errorf("cancellation exact replay: %w", err)
	}
	payload, _ := decodePhase8ActionPayload(12, bundle.Messages[0].Payload)
	return json.NewEncoder(output).Encode(phase8CancellationWorkerReport{
		CancellationID:     payload.Words[0],
		MessageCount:       len(bundle.Messages),
		Authenticated:      true,
		DuplicatePrevented: true,
		ObjectCount:        objectEvidence.ObjectCount,
		ObjectsRehydrated:  objectEvidence.Rehydrated,
	})
}
