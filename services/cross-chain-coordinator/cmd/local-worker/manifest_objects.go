package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"strings"
)

const phase8AuthenticatedEvidencePrefix = "phase8/authenticated-inclusion/v1"

type durableObjectEvidence struct {
	Keccak256 string `json:"keccak256"`
	SizeBytes int64  `json:"size_bytes"`
}

type durableObjectStoreEvidence struct {
	Bucket          string                           `json:"bucket"`
	ObjectCount     int64                            `json:"object_count"`
	ObjectSetSHA256 string                           `json:"object_set_sha256"`
	Rehydrated      bool                             `json:"rehydrated"`
	Objects         map[string]durableObjectEvidence `json:"objects"`
}

type manifestEvidenceObject struct {
	Key       string
	Value     []byte
	Keccak256 [32]byte
}

func phase8ManifestEvidenceObjects(
	flow phase8ImportFlow,
) ([]manifestEvidenceObject, error) {
	return phase8MessageEvidenceObjects(flow.Messages)
}

func phase8MessageEvidenceObjects(
	messages []phase8ImportMessage,
) ([]manifestEvidenceObject, error) {
	if len(messages) == 0 {
		return nil, errors.New("authenticated evidence flow is empty")
	}
	objects := make([]manifestEvidenceObject, 0, len(messages)*2)
	for _, message := range messages {
		messageID := strings.ToLower(strings.TrimPrefix(
			message.Envelope.MessageID,
			"0x",
		))
		if len(messageID) != 64 {
			return nil, fmt.Errorf(
				"message sequence %d has an invalid evidence identity",
				message.Sequence,
			)
		}
		for _, candidate := range []struct {
			kind         string
			inclusion    phase8AuthenticatedInclusion
			declaredHash string
		}{
			{
				kind:         "source",
				inclusion:    message.Source.AuthenticatedInclusion,
				declaredHash: message.Source.RawEvidenceObjectHash,
			},
			{
				kind:         "acknowledgement",
				inclusion:    message.Acknowledgement.AuthenticatedInclusion,
				declaredHash: message.Acknowledgement.RawEvidenceObjectHash,
			},
		} {
			value, err := canonicalJSON(candidate.inclusion)
			if err != nil {
				return nil, fmt.Errorf(
					"canonicalize message %d %s inclusion: %w",
					message.Sequence,
					candidate.kind,
					err,
				)
			}
			hash := keccak(value)
			if !sameHex(candidate.declaredHash, hash[:]) {
				return nil, fmt.Errorf(
					"message %d %s raw evidence hash does not bind canonical inclusion",
					message.Sequence,
					candidate.kind,
				)
			}
			hashText := hex.EncodeToString(hash[:])
			objects = append(objects, manifestEvidenceObject{
				Key: fmt.Sprintf(
					"%s/%s/%s/%s.json",
					phase8AuthenticatedEvidencePrefix,
					messageID,
					candidate.kind,
					hashText,
				),
				Value:     value,
				Keccak256: hash,
			})
		}
	}
	sort.Slice(objects, func(left, right int) bool {
		return objects[left].Key < objects[right].Key
	})
	for index := 1; index < len(objects); index++ {
		if objects[index-1].Key == objects[index].Key {
			return nil, errors.New("authenticated evidence object identity is duplicated")
		}
	}
	return objects, nil
}

func persistPhase8ManifestEvidence(
	ctx context.Context,
	store immutableEvidenceStore,
	flow phase8ImportFlow,
) ([]manifestEvidenceObject, error) {
	if ctx == nil || store == nil {
		return nil, errors.New("authenticated evidence object store is required")
	}
	return persistPhase8MessageEvidence(ctx, store, flow.Messages)
}

func persistPhase8MessageEvidence(
	ctx context.Context,
	store immutableEvidenceStore,
	messages []phase8ImportMessage,
) ([]manifestEvidenceObject, error) {
	if ctx == nil || store == nil {
		return nil, errors.New("authenticated evidence object store is required")
	}
	objects, err := phase8MessageEvidenceObjects(messages)
	if err != nil {
		return nil, err
	}
	for _, object := range objects {
		if err := store.PutImmutable(
			ctx,
			object.Key,
			object.Value,
			object.Keccak256,
		); err != nil {
			return nil, fmt.Errorf("persist %s: %w", object.Key, err)
		}
	}
	return objects, nil
}

func rehydratePhase8ManifestEvidence(
	ctx context.Context,
	store immutableEvidenceStore,
	objects []manifestEvidenceObject,
) (durableObjectStoreEvidence, error) {
	if ctx == nil || store == nil || len(objects) == 0 {
		return durableObjectStoreEvidence{}, errors.New(
			"authenticated evidence objects are required for restart verification",
		)
	}
	report := durableObjectStoreEvidence{
		Bucket:      evidenceBucket,
		ObjectCount: int64(len(objects)),
		Rehydrated:  true,
		Objects:     make(map[string]durableObjectEvidence, len(objects)),
	}
	for _, object := range objects {
		reloaded, err := store.GetImmutable(ctx, object.Key, object.Keccak256)
		if err != nil {
			return durableObjectStoreEvidence{}, fmt.Errorf(
				"rehydrate %s: %w",
				object.Key,
				err,
			)
		}
		if !bytes.Equal(reloaded, object.Value) ||
			keccak(reloaded) != object.Keccak256 {
			return durableObjectStoreEvidence{}, fmt.Errorf(
				"rehydrated evidence object %s was substituted",
				object.Key,
			)
		}
		report.Objects[object.Key] = durableObjectEvidence{
			Keccak256: hexHash(object.Keccak256),
			SizeBytes: int64(len(object.Value)),
		}
	}
	setJSON, err := canonicalJSON(report.Objects)
	if err != nil {
		return durableObjectStoreEvidence{}, err
	}
	setHash := sha256.Sum256(setJSON)
	report.ObjectSetSHA256 = hex.EncodeToString(setHash[:])
	return report, nil
}
