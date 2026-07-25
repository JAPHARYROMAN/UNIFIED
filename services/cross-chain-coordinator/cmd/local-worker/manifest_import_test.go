package main

import "testing"

func TestPhase8CanonicalTransitionsKeepVerifiedSourceAuthorityBound(
	t *testing.T,
) {
	sourceProof := phase8ImportProof{
		ProofHash:  "source-proof",
		ObservedAt: "source-time",
	}
	sourceCertificate := phase8ImportCertificate{
		CertificateHash: "source-certificate",
	}
	destinationProof := phase8ImportProof{
		ProofHash:  "destination-proof",
		ObservedAt: "destination-time",
	}
	transitions := phase8CanonicalTransitions(
		sourceProof,
		sourceCertificate,
		destinationProof,
		"destination-result",
	)
	if len(transitions) != 8 {
		t.Fatalf("canonical transition count = %d, want 8", len(transitions))
	}
	if transitions[1].EvidenceHash != sourceCertificate.CertificateHash ||
		transitions[4].EvidenceHash != sourceCertificate.CertificateHash {
		t.Fatalf(
			"source finality/verification lost source authority: %#v",
			transitions,
		)
	}
	if transitions[3].EvidenceHash != destinationProof.ProofHash ||
		transitions[5].EvidenceHash != "destination-result" ||
		transitions[7].EvidenceHash != "destination-result" {
		t.Fatalf(
			"destination relay/execution/ack evidence drifted: %#v",
			transitions,
		)
	}
	if transitions[4].OccurredAt != destinationProof.ObservedAt {
		t.Fatalf(
			"verification occurrence time = %q, want destination observation",
			transitions[4].OccurredAt,
		)
	}
}
