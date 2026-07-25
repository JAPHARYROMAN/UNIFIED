// Command server composes the Phase 8 coordinator's durable PostgreSQL
// repository for local health and smoke checks. It deliberately has no
// provider, signing, chain, or production credential surface.
package main

import (
	"context"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/store"
)

const databaseURLEnvironment = "UNIFIED_CROSSCHAIN_DATABASE_URL"

type configuration struct {
	mode        string
	databaseURL string
	timeout     time.Duration
}

func main() {
	if err := execute(os.Args[1:], os.Getenv, os.Stdout); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "cross-chain coordinator: %v\n", err)
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
	ctx, cancel := context.WithTimeout(context.Background(), config.timeout)
	defer cancel()
	database, err := sql.Open("pgx", config.databaseURL)
	if err != nil {
		return errors.New("open local PostgreSQL")
	}
	defer func() { _ = database.Close() }()
	database.SetMaxOpenConns(2)
	database.SetMaxIdleConns(1)
	database.SetConnMaxLifetime(time.Minute)
	if err := database.PingContext(ctx); err != nil {
		return fmt.Errorf("ping local PostgreSQL: %w", err)
	}
	repository, err := store.NewSQL(database)
	if err != nil {
		return err
	}
	return reportStatus(ctx, output, config.mode, repository)
}

type healthRepository interface {
	Health(context.Context) error
}

func reportStatus(
	ctx context.Context,
	output io.Writer,
	mode string,
	repository healthRepository,
) error {
	if ctx == nil || output == nil || repository == nil ||
		(mode != "health" && mode != "smoke") {
		return errors.New("invalid local coordinator status request")
	}
	if err := repository.Health(ctx); err != nil {
		return err
	}
	_, err := fmt.Fprintf(
		output,
		"{\"mode\":\"%s\",\"repository\":\"crosschain\",\"status\":\"ok\"}\n",
		mode,
	)
	return err
}

func loadConfiguration(
	arguments []string,
	getenv func(string) string,
) (configuration, error) {
	if getenv == nil {
		return configuration{}, errors.New("environment reader is required")
	}
	flags := flag.NewFlagSet("cross-chain-coordinator", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	mode := flags.String("mode", "health", "local health or smoke check")
	timeout := flags.Duration("timeout", 5*time.Second, "bounded database check timeout")
	if err := flags.Parse(arguments); err != nil || flags.NArg() != 0 {
		return configuration{}, errors.New("invalid command arguments")
	}
	if *mode != "health" && *mode != "smoke" {
		return configuration{}, errors.New("mode must be health or smoke")
	}
	if *timeout <= 0 || *timeout > time.Minute {
		return configuration{}, errors.New("timeout must be between zero and one minute")
	}
	databaseURL := strings.TrimSpace(getenv(databaseURLEnvironment))
	if err := validateLocalDatabaseURL(databaseURL); err != nil {
		return configuration{}, err
	}
	return configuration{
		mode:        *mode,
		databaseURL: databaseURL,
		timeout:     *timeout,
	}, nil
}

func validateLocalDatabaseURL(databaseURL string) error {
	parsed, err := url.Parse(databaseURL)
	if err != nil ||
		(parsed.Scheme != "postgres" && parsed.Scheme != "postgresql") ||
		parsed.User == nil || parsed.User.Username() == "" ||
		parsed.Path == "" || parsed.Path == "/" {
		return errors.New("a PostgreSQL URL for a named local database is required")
	}
	host := strings.ToLower(parsed.Hostname())
	if host == "localhost" {
		return nil
	}
	address := net.ParseIP(host)
	if address == nil || !address.IsLoopback() {
		return errors.New("coordinator command accepts loopback PostgreSQL only")
	}
	return nil
}
