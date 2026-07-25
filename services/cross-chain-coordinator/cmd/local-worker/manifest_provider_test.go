package main

import (
	"strings"
	"testing"
)

func TestManifestProviderAttemptsRequireExactObservedFailoverPath(t *testing.T) {
	message := phase8ProviderTestMessage()
	if err := validatePhase8ProviderAttempts(message, 0, true); err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		name   string
		mutate func(*phase8ImportMessage)
	}{
		{
			name: "provider",
			mutate: func(value *phase8ImportMessage) {
				value.ProviderAttempts[0].ProviderID = localProviderBID
			},
		},
		{
			name: "status",
			mutate: func(value *phase8ImportMessage) {
				value.ProviderAttempts[0].Status = "DELIVERED"
			},
		},
		{
			name: "retryability",
			mutate: func(value *phase8ImportMessage) {
				value.ProviderAttempts[0].Retryable = false
			},
		},
		{
			name: "payload",
			mutate: func(value *phase8ImportMessage) {
				value.ProviderAttempts[0].PayloadHash = repeatedProviderHex("55")
			},
		},
		{
			name: "proof",
			mutate: func(value *phase8ImportMessage) {
				value.ProviderAttempts[0].SourceProofHash = repeatedProviderHex("66")
			},
		},
		{
			name: "order",
			mutate: func(value *phase8ImportMessage) {
				value.ProviderAttempts[0], value.ProviderAttempts[1] =
					value.ProviderAttempts[1], value.ProviderAttempts[0]
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			mutated := phase8ProviderTestMessage()
			test.mutate(&mutated)
			if err := validatePhase8ProviderAttempts(mutated, 0, true); err == nil {
				t.Fatal("substituted provider evidence was accepted")
			}
		})
	}
}

func phase8ProviderTestMessage() phase8ImportMessage {
	messageID := repeatedProviderHex("11")
	payloadHash := repeatedProviderHex("22")
	proofHash := repeatedProviderHex("33")
	return phase8ImportMessage{
		Envelope: phase8ImportEnvelope{
			MessageID:   messageID,
			PayloadHash: payloadHash,
		},
		Source: phase8ImportSource{ProofHash: proofHash},
		ProviderAttempts: []phase8PublicProviderAttempt{
			{
				ProviderID:           localProviderAID,
				AttemptNumber:        1,
				Status:               "FAILED",
				Retryable:            true,
				MessageID:            messageID,
				PayloadHash:          payloadHash,
				SourceProofHash:      proofHash,
				TransportReceiptHash: repeatedProviderHex("44"),
			},
			{
				ProviderID:           localProviderBID,
				AttemptNumber:        2,
				Status:               "DELIVERED",
				Retryable:            false,
				MessageID:            messageID,
				PayloadHash:          payloadHash,
				SourceProofHash:      proofHash,
				TransportReceiptHash: repeatedProviderHex("55"),
			},
		},
	}
}

func repeatedProviderHex(pair string) string {
	return "0x" + strings.Repeat(pair, 32)
}
