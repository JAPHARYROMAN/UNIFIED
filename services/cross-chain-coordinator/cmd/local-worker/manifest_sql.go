package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
)

const registerManifestSignerSetSQL = `
SELECT crosschain.register_signer_set(
    $1, $2, $3, ARRAY[$4::bytea, $5::bytea, $6::bytea],
    $7, $8, 'ACTIVE', $9
)`

// bootstrapManifestTrust provisions only public, append-only authorities from
// the validated bundle. It uses the local owner connection because signer-set,
// chain, and route registration are privileged configuration operations. The
// durable worker roles never receive these privileges.
func bootstrapManifestTrust(
	ctx context.Context,
	databaseURL string,
	manifest phase8ReleaseManifest,
	registrations []store.RouteRegistration,
) error {
	if ctx == nil || databaseURL == "" || len(registrations) == 0 {
		return errors.New("manifest trust bootstrap requires owner database and routes")
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return fmt.Errorf("open manifest bootstrap database: %w", err)
	}
	defer func() { _ = database.Close() }()
	if err := database.PingContext(ctx); err != nil {
		return fmt.Errorf("ping manifest bootstrap database: %w", err)
	}
	var role string
	if err := database.QueryRowContext(ctx, "SELECT current_user").Scan(&role); err != nil {
		return fmt.Errorf("read manifest bootstrap role: %w", err)
	}
	if role != "unified_local" && role != "unified_crosschain_owner" {
		return fmt.Errorf("manifest bootstrap requires local owner role, got %s", role)
	}
	for name, domain := range map[string]phase8ManifestDomain{
		"home":      manifest.Domains.Home,
		"satellite": manifest.Domains.Satellite,
	} {
		hash, err := parseManifestHash(domain.SignerSet.Hash, name+" signer set")
		if err != nil {
			return err
		}
		addresses, err := validateSortedAddresses(domain.SignerSet.SortedAddresses)
		if err != nil {
			return err
		}
		validFrom := time.Unix(int64(domain.SignerSet.ValidFrom), 0).UTC()
		validUntil := time.Unix(int64(domain.SignerSet.ValidUntil), 0).UTC()
		if _, err := database.ExecContext(
			ctx,
			registerManifestSignerSetSQL,
			hash[:],
			int64(domain.SignerSet.Version),
			int64(domain.SignerSet.Threshold),
			addresses[0][:],
			addresses[1][:],
			addresses[2][:],
			validFrom,
			validUntil,
			validFrom,
		); err != nil {
			return fmt.Errorf("register %s manifest signer set: %w", name, err)
		}
	}
	repository, err := store.NewSQLWithProvisioning(database, registrations)
	if err != nil {
		return fmt.Errorf("create manifest provisioning repository: %w", err)
	}
	for _, registration := range registrations {
		if err := repository.PutRoute(registration.Route); err != nil {
			return fmt.Errorf(
				"register manifest route %s: %w",
				registration.Route.RouteID,
				err,
			)
		}
	}
	return nil
}
