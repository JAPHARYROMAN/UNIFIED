package payment

import "github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"

// LocalCanonicalReversalCoordinator is an explicit test-only adapter. It has no
// persistence and must not be used as runtime Phase 7C wiring.
type LocalCanonicalReversalCoordinator struct {
	modes *allocationmode.Registry
}

func NewLocalCanonicalReversalCoordinator(
	modes *allocationmode.Registry,
) (*LocalCanonicalReversalCoordinator, error) {
	if modes == nil {
		return nil, ErrCanonicalPersistence
	}
	return &LocalCanonicalReversalCoordinator{modes: modes}, nil
}

func (coordinator *LocalCanonicalReversalCoordinator) HandleProviderReversal(
	record CanonicalReversalRecord,
	commit func() error,
) (allocationmode.Claim, allocationmode.ReversalDisposition, error) {
	return coordinator.modes.HandleReversalWithCommit(
		record.PaymentID,
		func(
			_ allocationmode.Claim,
			disposition allocationmode.ReversalDisposition,
			_ bool,
		) error {
			switch disposition {
			case allocationmode.ReversalUnclaimed,
				allocationmode.ReversalSynthetic,
				allocationmode.ReversalReleased:
				if commit == nil {
					return ErrCanonicalPersistence
				}
				return commit()
			}
			return nil
		},
	)
}

func (coordinator *LocalCanonicalReversalCoordinator) ResolveProviderReversal(
	record CanonicalReversalRecord,
	localFallback func() ([]string, error),
) (CanonicalReversalResolution, error) {
	if localFallback == nil {
		return CanonicalReversalResolution{}, ErrCanonicalPersistence
	}
	var result CanonicalReversalResolution
	err := coordinator.modes.ResolveQuarantinedReversal(
		allocationmode.Claim{
			PaymentID:    record.PaymentID,
			AllocationID: record.AllocationID,
			Mode:         allocationmode.ModeCanonicalGateway,
			Digest:       record.InstructionDigest,
			State:        allocationmode.CanonicalQuarantined,
		},
		func() error {
			journalIDs, err := localFallback()
			if err != nil {
				return err
			}
			result.JournalIDs = journalIDs
			result.FailureEvidenceHash =
				record.FailureProof.Evidence().EvidenceHash
			if result.FailureEvidenceHash == "" {
				result.FailureEvidenceHash = record.CallbackEvidenceHash
			}
			return nil
		},
	)
	return result, err
}

func (*LocalCanonicalReversalCoordinator) PendingProviderReversals() []CanonicalReversalRecord {
	return nil
}

func (*LocalCanonicalReversalCoordinator) ResolvedProviderReversal(
	CanonicalReversalResolutionRequest,
) (CanonicalReversalResolutionRecord, bool, error) {
	return CanonicalReversalResolutionRecord{}, false, nil
}

func (*LocalCanonicalReversalCoordinator) ConsumedProviderReversals() []CanonicalReversalConsumption {
	return nil
}
