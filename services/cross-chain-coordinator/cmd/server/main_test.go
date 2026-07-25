package main

import (
	"bytes"
	"context"
	"errors"
	"testing"
	"time"
)

type stubHealthRepository struct {
	err error
}

func (repository stubHealthRepository) Health(context.Context) error {
	return repository.err
}

func TestLoadConfigurationIsLocalOnlyAndCredentialFree(t *testing.T) {
	getenv := func(name string) string {
		if name != databaseURLEnvironment {
			t.Fatalf("unexpected environment read: %s", name)
		}
		return "postgres://local_runtime@127.0.0.1:5432/unified?sslmode=disable"
	}
	config, err := loadConfiguration(
		[]string{"-mode=smoke", "-timeout=3s"},
		getenv,
	)
	if err != nil {
		t.Fatal(err)
	}
	if config.mode != "smoke" || config.timeout != 3*time.Second ||
		config.databaseURL != getenv(databaseURLEnvironment) {
		t.Fatalf("configuration mismatch: %#v", config)
	}
}

func TestLoadConfigurationRejectsRemoteOrMissingDatabase(t *testing.T) {
	for name, databaseURL := range map[string]string{
		"missing": "",
		"remote":  "postgres://runtime@db.example.com/unified",
		"unnamed": "postgres://runtime@localhost/",
		"keyword": "host=localhost dbname=unified",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := loadConfiguration(
				nil,
				func(string) string { return databaseURL },
			); err == nil {
				t.Fatal("unsafe database configuration accepted")
			}
		})
	}
}

func TestReportStatusIsDeterministic(t *testing.T) {
	var output bytes.Buffer
	if err := reportStatus(
		context.Background(),
		&output,
		"health",
		stubHealthRepository{},
	); err != nil {
		t.Fatal(err)
	}
	const expected = `{"mode":"health","repository":"crosschain","status":"ok"}` + "\n"
	if output.String() != expected {
		t.Fatalf("status output mismatch: %q", output.String())
	}

	sentinel := errors.New("database unavailable")
	if err := reportStatus(
		context.Background(),
		&output,
		"smoke",
		stubHealthRepository{err: sentinel},
	); !errors.Is(err, sentinel) {
		t.Fatalf("health failure was hidden: %v", err)
	}
}
