package main

import (
	"bytes"
	"context"
	"errors"
	"testing"
)

type manifestObjectTestStore struct {
	objects map[string][]byte
}

func (store *manifestObjectTestStore) PutImmutable(
	_ context.Context,
	key string,
	value []byte,
	hash [32]byte,
) error {
	if store.objects == nil {
		store.objects = make(map[string][]byte)
	}
	if err := validateEvidenceIdentity(key, value, hash); err != nil {
		return err
	}
	if existing, ok := store.objects[key]; ok && !bytes.Equal(existing, value) {
		return errors.New("immutable evidence conflict")
	}
	store.objects[key] = append([]byte(nil), value...)
	return nil
}

func (store *manifestObjectTestStore) GetImmutable(
	_ context.Context,
	key string,
	hash [32]byte,
) ([]byte, error) {
	value, ok := store.objects[key]
	if !ok {
		return nil, errors.New("immutable evidence not found")
	}
	if err := validateEvidenceIdentity(key, value, hash); err != nil {
		return nil, err
	}
	return append([]byte(nil), value...), nil
}

func TestManifestAuthenticatedEvidencePersistsAndRehydratesExactBytes(
	t *testing.T,
) {
	flow := manifestObjectTestFlow(t)
	store := &manifestObjectTestStore{}
	objects, err := persistPhase8ManifestEvidence(
		context.Background(),
		store,
		flow,
	)
	if err != nil {
		t.Fatal(err)
	}
	report, err := rehydratePhase8ManifestEvidence(
		context.Background(),
		store,
		objects,
	)
	if err != nil {
		t.Fatal(err)
	}
	if !report.Rehydrated || report.ObjectCount != 2 ||
		len(report.Objects) != 2 || report.ObjectSetSHA256 == "" {
		t.Fatal("authenticated object restart evidence is incomplete")
	}
}

func TestCancellationEvidencePersistsFourObjectsAndRehydrates(t *testing.T) {
	flow := manifestObjectTestFlow(t)
	second := flow.Messages[0]
	second.Sequence = 2
	second.Envelope.MessageID = "0x" + repeatedHex("22", 32)
	messages := append(flow.Messages, second)
	store := &manifestObjectTestStore{}
	objects, err := persistPhase8MessageEvidence(
		context.Background(),
		store,
		messages,
	)
	if err != nil {
		t.Fatal(err)
	}
	report, err := rehydratePhase8ManifestEvidence(
		context.Background(),
		store,
		objects,
	)
	if err != nil {
		t.Fatal(err)
	}
	if report.ObjectCount != 4 || !report.Rehydrated ||
		len(report.Objects) != 4 {
		t.Fatalf("cancellation evidence was not restart durable: %#v", report)
	}
}

func TestManifestAuthenticatedEvidenceFailsClosedOnMissingOrSubstitutedBytes(
	t *testing.T,
) {
	for _, test := range []struct {
		name   string
		mutate func(map[string][]byte)
	}{
		{
			name: "missing",
			mutate: func(objects map[string][]byte) {
				for key := range objects {
					delete(objects, key)
					return
				}
			},
		},
		{
			name: "substituted",
			mutate: func(objects map[string][]byte) {
				for key := range objects {
					objects[key] = []byte(`{"substituted":true}`)
					return
				}
			},
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			flow := manifestObjectTestFlow(t)
			store := &manifestObjectTestStore{}
			objects, err := persistPhase8ManifestEvidence(
				context.Background(),
				store,
				flow,
			)
			if err != nil {
				t.Fatal(err)
			}
			test.mutate(store.objects)
			if _, err := rehydratePhase8ManifestEvidence(
				context.Background(),
				store,
				objects,
			); err == nil {
				t.Fatal("missing or substituted authenticated evidence was accepted")
			}
		})
	}
}

func manifestObjectTestFlow(t *testing.T) phase8ImportFlow {
	t.Helper()
	source := phase8AuthenticatedInclusion{
		HeaderRLP:                 "0x01",
		HeaderObservedAtUnixNanos: "1700000000000000000",
		HeaderSignatureEd25519:    "0x02",
	}
	acknowledgement := phase8AuthenticatedInclusion{
		HeaderRLP:                 "0x03",
		HeaderObservedAtUnixNanos: "1700000001000000000",
		HeaderSignatureEd25519:    "0x04",
	}
	sourceJSON, err := canonicalJSON(source)
	if err != nil {
		t.Fatal(err)
	}
	acknowledgementJSON, err := canonicalJSON(acknowledgement)
	if err != nil {
		t.Fatal(err)
	}
	return phase8ImportFlow{
		Messages: []phase8ImportMessage{
			{
				Sequence: 1,
				Envelope: phase8ImportEnvelope{
					MessageID: "0x" + repeatedHex("11", 32),
				},
				Source: phase8ImportSource{
					AuthenticatedInclusion: source,
					RawEvidenceObjectHash:  hexHash(keccak(sourceJSON)),
				},
				Acknowledgement: phase8ImportAcknowledgement{
					AuthenticatedInclusion: acknowledgement,
					RawEvidenceObjectHash:  hexHash(keccak(acknowledgementJSON)),
				},
			},
		},
	}
}

func repeatedHex(value string, count int) string {
	result := make([]byte, 0, len(value)*count)
	for range count {
		result = append(result, value...)
	}
	return string(result)
}
