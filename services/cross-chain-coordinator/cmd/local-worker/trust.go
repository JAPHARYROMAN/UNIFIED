package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"strings"
)

// validateLocalTrustConfiguration deliberately ignores environment overrides.
// The combined release-evidence bundle at the repository-pinned path is the
// only deployment, route, signer, finality, recovery, and provider authority.
func validateLocalTrustConfiguration(_ func(string) string) error {
	path, err := locatePhase8ReleaseEvidence()
	if err != nil {
		return err
	}
	if _, _, err := loadPhase8ReleaseManifest(path); err != nil {
		return fmt.Errorf("validate Phase 8 release evidence: %w", err)
	}
	return nil
}

func sameHex(configured string, expected []byte) bool {
	value := strings.TrimPrefix(strings.TrimSpace(configured), "0x")
	decoded, err := hex.DecodeString(value)
	return err == nil && bytes.Equal(decoded, expected)
}
