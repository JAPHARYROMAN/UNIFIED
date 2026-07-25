package settlementintegration

import (
	"errors"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementaccounting"
	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementtest"
	"github.com/unified-finance/unified/services/payment-orchestrator/settlement"
)

func TestAdaptConfirmationPreservesCompleteCanonicalProvenance(t *testing.T) {
	input, authority := settlementtest.ConfirmedWithDeepReorg(t)
	reorg := authority.Evidence()
	projection := input.AccountingProjection()
	verified, err := AdaptVerifiedReorg(
		settlementaccounting.ReorgMetadata{
			ReorgID:            reorg.ReorgID,
			CanonicalizationID: "canonical-001",
			Owner:              "chain-operations",
			ResolutionDeadline: reorg.DetectedAt.Add(24 * time.Hour),
		},
		input,
		authority,
	)
	if err != nil ||
		verified.Evidence().OrphanedEventEvidenceHash !=
			projection.EventEvidenceHash ||
		verified.Evidence().OrphanedRawPayloadHash !=
			projection.GatewayPayloadHash {
		t.Fatalf("verified reorg lost event or raw authority: %#v, %v", verified.Evidence(), err)
	}
	if _, err := AdaptVerifiedReorg(
		settlementaccounting.ReorgMetadata{
			ReorgID:            "caller-selected-reorg-id",
			CanonicalizationID: "canonical-001",
			Owner:              "chain-operations",
			ResolutionDeadline: reorg.DetectedAt.Add(24 * time.Hour),
		},
		input,
		authority,
	); !errors.Is(err, settlementaccounting.ErrInvalidReorg) {
		t.Fatalf("caller-selected reorg identity was accepted: %v", err)
	}
}

func TestAdaptConfirmationRejectsNonCoordinatorValue(t *testing.T) {
	_, err := AdaptConfirmation(
		settlementaccounting.DurableConfirmationAuthority{},
		settlement.Confirmation{},
	)
	if !errors.Is(err, ErrInvalidConfirmation) {
		t.Fatalf("expected opaque zero confirmation rejection, got %v", err)
	}
}
