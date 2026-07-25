package main

import (
	"errors"
	"flag"
	"io"
	"net"
	"net/url"
	"path/filepath"
	"strings"
	"time"
)

const (
	databaseURLEnvironment            = "UNIFIED_CROSSCHAIN_DATABASE_URL"
	observerDatabaseEnvironment       = "UNIFIED_CROSSCHAIN_OBSERVER_DATABASE_URL"
	finalityDatabaseEnvironment       = "UNIFIED_CROSSCHAIN_FINALITY_DATABASE_URL"
	recoveryDatabaseEnvironment       = "UNIFIED_CROSSCHAIN_RECOVERY_DATABASE_URL"
	reorganizationDatabaseEnvironment = "UNIFIED_CROSSCHAIN_REORGANIZATION_DATABASE_URL"
	foundationDSNEnvironment          = "UNIFIED_POSTGRES_DSN"
	kafkaEnvironment                  = "UNIFIED_KAFKA_BROKERS"
	objectEnvironment                 = "UNIFIED_OBJECT_ENDPOINT"
	providerAEnvironment              = "UNIFIED_MOCK_BRIDGE_PROVIDER_A"
	providerBEnvironment              = "UNIFIED_MOCK_BRIDGE_PROVIDER_B"
	objectAccessEnvironment           = "UNIFIED_OBJECT_ACCESS_KEY"
	objectSecretEnvironment           = "UNIFIED_OBJECT_SECRET_KEY"
)

type configuration struct {
	mode                      string
	cancellationBundlePath    string
	bootstrapDatabaseURL      string
	databaseURL               string
	observerDatabaseURL       string
	finalityDatabaseURL       string
	recoveryDatabaseURL       string
	reorganizationDatabaseURL string
	kafkaBroker               string
	objectURL                 string
	objectAccess              string
	objectSecret              string
	providerAURL              string
	providerBURL              string
	timeout                   time.Duration
}

func loadConfiguration(arguments []string, getenv func(string) string) (configuration, error) {
	if getenv == nil {
		return configuration{}, errors.New("environment reader is required")
	}
	flags := flag.NewFlagSet("cross-chain-local-worker", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	mode := flags.String("mode", "", "bounded worker mode")
	cancellationBundle := flags.String(
		"cancellation-bundle",
		"",
		"exact authenticated action 12/14 bundle",
	)
	timeout := flags.Duration("timeout", 45*time.Second, "overall smoke timeout")
	if err := flags.Parse(arguments); err != nil || flags.NArg() != 0 ||
		(*mode != "smoke" && *mode != "cancellation") {
		return configuration{}, errors.New(
			"local worker requires --mode smoke or --mode cancellation",
		)
	}
	bundlePath := strings.TrimSpace(*cancellationBundle)
	if *mode == "smoke" && bundlePath != "" {
		return configuration{}, errors.New(
			"smoke mode does not accept a cancellation bundle",
		)
	}
	if *mode == "cancellation" {
		if bundlePath == "" {
			return configuration{}, errors.New(
				"cancellation mode requires --cancellation-bundle",
			)
		}
		absolute, err := filepath.Abs(bundlePath)
		if err != nil {
			return configuration{}, errors.New("invalid cancellation bundle path")
		}
		bundlePath = filepath.Clean(absolute)
	}
	if *timeout <= 0 || *timeout > 2*time.Minute {
		return configuration{}, errors.New("timeout must be between zero and two minutes")
	}
	databaseURL := strings.TrimSpace(getenv(databaseURLEnvironment))
	if err := validateLocalDatabaseURL(databaseURL); err != nil {
		return configuration{}, err
	}
	bootstrapDatabaseURL := strings.TrimSpace(getenv(foundationDSNEnvironment))
	if err := validateLocalDatabaseURL(bootstrapDatabaseURL); err != nil {
		return configuration{}, errors.New("bootstrap database: " + err.Error())
	}
	observerDatabaseURL := strings.TrimSpace(getenv(observerDatabaseEnvironment))
	if err := validateLocalDatabaseURL(observerDatabaseURL); err != nil {
		return configuration{}, errors.New("observer database: " + err.Error())
	}
	finalityDatabaseURL := strings.TrimSpace(getenv(finalityDatabaseEnvironment))
	if err := validateLocalDatabaseURL(finalityDatabaseURL); err != nil {
		return configuration{}, errors.New("finality database: " + err.Error())
	}
	recoveryDatabaseURL := strings.TrimSpace(getenv(recoveryDatabaseEnvironment))
	if err := validateLocalDatabaseURL(recoveryDatabaseURL); err != nil {
		return configuration{}, errors.New("recovery database: " + err.Error())
	}
	reorganizationDatabaseURL := strings.TrimSpace(
		getenv(reorganizationDatabaseEnvironment),
	)
	if err := validateLocalDatabaseURL(reorganizationDatabaseURL); err != nil {
		return configuration{}, errors.New("reorganization database: " + err.Error())
	}
	broker, err := singleLocalBroker(getenv(kafkaEnvironment))
	if err != nil {
		return configuration{}, err
	}
	objectURL := defaultValue(getenv(objectEnvironment), "http://127.0.0.1:59000")
	providerAURL := defaultValue(getenv(providerAEnvironment), "http://127.0.0.1:58081")
	providerBURL := defaultValue(getenv(providerBEnvironment), "http://127.0.0.1:58082")
	for label, endpoint := range map[string]string{
		"object store": objectURL,
		"provider A":   providerAURL,
		"provider B":   providerBURL,
	} {
		if err := validateLoopbackHTTP(endpoint); err != nil {
			return configuration{}, errors.New(label + ": " + err.Error())
		}
	}
	access := defaultValue(getenv(objectAccessEnvironment), "unified_local")
	secret := defaultValue(getenv(objectSecretEnvironment), "local-only-not-a-secret")
	if access == "" || secret == "" {
		return configuration{}, errors.New("local object-store credentials are required")
	}
	return configuration{
		mode:                      *mode,
		cancellationBundlePath:    bundlePath,
		bootstrapDatabaseURL:      bootstrapDatabaseURL,
		databaseURL:               databaseURL,
		observerDatabaseURL:       observerDatabaseURL,
		finalityDatabaseURL:       finalityDatabaseURL,
		recoveryDatabaseURL:       recoveryDatabaseURL,
		reorganizationDatabaseURL: reorganizationDatabaseURL,
		kafkaBroker:               broker,
		objectURL:                 objectURL,
		objectAccess:              access,
		objectSecret:              secret,
		providerAURL:              providerAURL,
		providerBURL:              providerBURL,
		timeout:                   *timeout,
	}, nil
}

func defaultValue(value, fallback string) string {
	if value = strings.TrimSpace(value); value != "" {
		return value
	}
	return fallback
}

func validateLocalDatabaseURL(databaseURL string) error {
	parsed, err := url.Parse(databaseURL)
	if err != nil ||
		(parsed.Scheme != "postgres" && parsed.Scheme != "postgresql") ||
		parsed.User == nil || parsed.User.Username() == "" ||
		parsed.Path == "" || parsed.Path == "/" {
		return errors.New("a PostgreSQL URL for a named local database is required")
	}
	if !localHost(parsed.Hostname()) {
		return errors.New("local worker accepts loopback PostgreSQL only")
	}
	return nil
}

func singleLocalBroker(value string) (string, error) {
	parts := strings.Split(strings.TrimSpace(value), ",")
	if len(parts) != 1 {
		return "", errors.New("exactly one local Kafka broker is required")
	}
	broker := strings.TrimSpace(parts[0])
	host, port, err := net.SplitHostPort(broker)
	if err != nil || port == "" || !localHost(host) {
		return "", errors.New("local worker accepts one loopback Kafka broker only")
	}
	return broker, nil
}

func validateLoopbackHTTP(value string) error {
	parsed, err := url.Parse(strings.TrimSpace(value))
	if err != nil || parsed.Scheme != "http" || parsed.Host == "" ||
		parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" ||
		!localHost(parsed.Hostname()) {
		return errors.New("local worker accepts loopback HTTP endpoints only")
	}
	return nil
}

func localHost(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	address := net.ParseIP(host)
	return address != nil && address.IsLoopback()
}
