package settlement

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"slices"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

// HandleProviderReversal implements payment.CanonicalReversalCoordinator. The
// Phase 7A commit runs only for a reversal that may proceed; submitted work is
// durably quarantined and confirmed work becomes an incident.
func (coordinator *Coordinator) HandleProviderReversal(
	record payment.CanonicalReversalRecord,
	commit func() error,
) (allocationmode.Claim, allocationmode.ReversalDisposition, error) {
	if coordinator == nil || commit == nil || !validReversalRecord(record) {
		return allocationmode.Claim{}, allocationmode.ReversalUnclaimed,
			ErrInvalidTransition
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()

	if plan, exists := coordinator.plans[record.PaymentID]; exists &&
		plan.State == StateQuarantined {
		pending, pendingExists := coordinator.pending[record.PaymentID]
		claim, claimExists := coordinator.modes.Lookup(record.PaymentID)
		if !pendingExists || !claimExists ||
			!claimMatchesPlan(claim, plan) ||
			!samePendingReversal(pending, record) {
			return allocationmode.Claim{}, allocationmode.ReversalQuarantined,
				ErrPlanConflict
		}
		return claim, allocationmode.ReversalQuarantined, nil
	}

	var committedPlan *Plan
	var committedPending *PendingReversalSnapshot
	claim, disposition, err := coordinator.modes.HandleReversalWithCommit(
		record.PaymentID,
		func(
			currentClaim allocationmode.Claim,
			currentDisposition allocationmode.ReversalDisposition,
			_ bool,
		) error {
			switch currentDisposition {
			case allocationmode.ReversalUnclaimed,
				allocationmode.ReversalSynthetic:
				if err := commit(); err != nil {
					return err
				}
				return coordinator.store.CreateTombstone(StoredTombstone{
					PaymentID:       record.PaymentID,
					ReversalEventID: record.ReversalEventID,
					EvidenceHash:    record.CallbackEvidenceHash,
					OccurredAt:      record.ReceivedAt.UTC(),
				})
			case allocationmode.ReversalQuarantined:
				plan, exists := coordinator.plans[record.PaymentID]
				if !exists ||
					(plan.State != StatePrepared &&
						plan.State != StateSubmitted &&
						plan.State != StateFailed) ||
					!claimMatchesPlan(currentClaim, plan) {
					return ErrInvalidTransition
				}
				expectedState := plan.State
				nextPlan := clonePlan(plan)
				nextPlan.State = StateQuarantined
				nextPlan.Version++
				nextPlan.FailureReason = "PROVIDER_REVERSAL_PENDING"
				nextClaim := currentClaim
				nextClaim.State = allocationmode.CanonicalQuarantined
				pending := pendingSnapshot(record, nextPlan, expectedState)
				nextRecord, err := coordinator.durableRecordWith(
					nextPlan,
					nextClaim,
					false,
					&pending,
				)
				if err != nil {
					return err
				}
				if err := coordinator.store.QuarantinePendingReversal(
					expectedState,
					plan.Version,
					nextRecord,
					pending,
				); err != nil {
					return err
				}
				committedPlan = &nextPlan
				committedPending = &pending
				return nil
			case allocationmode.ReversalIncident:
				plan, exists := coordinator.plans[record.PaymentID]
				if !exists || plan.State != StateConfirmed ||
					!claimMatchesPlan(currentClaim, plan) {
					return ErrInvalidTransition
				}
				nextPlan := clonePlan(plan)
				nextPlan.State = StateIncident
				nextPlan.Version++
				nextPlan.FailureReason = "PROVIDER_REVERSAL_AFTER_CONFIRMATION"
				nextClaim := currentClaim
				nextClaim.State = allocationmode.CanonicalIncident
				nextRecord, err := coordinator.durableRecordWith(
					nextPlan,
					nextClaim,
					false,
					nil,
				)
				if err != nil {
					return err
				}
				if err := coordinator.store.CompareAndSwap(
					StateConfirmed,
					plan.Version,
					nextRecord,
					record.CallbackEvidenceHash,
					record.ReceivedAt.UTC(),
				); err != nil {
					return err
				}
				committedPlan = &nextPlan
				return nil
			default:
				return ErrInvalidTransition
			}
		},
	)
	if err != nil {
		return allocationmode.Claim{}, disposition,
			errors.Join(ErrInvalidTransition, err)
	}
	if committedPlan != nil {
		coordinator.plans[record.PaymentID] = *committedPlan
	}
	if committedPending != nil {
		coordinator.pending[record.PaymentID] = *committedPending
	}
	return claim, disposition, nil
}

// ResolveProviderReversal asks the store to atomically post Phase 7A reversal
// accounting, resolve the quarantine, tombstone the allocation, and advance
// QUARANTINED to FAILED before publishing any in-memory transition. SQL stores
// own that entire transaction; the callback is an explicit local-store fallback.
func (coordinator *Coordinator) ResolveProviderReversal(
	record payment.CanonicalReversalRecord,
	localFallback func() ([]string, error),
) (payment.CanonicalReversalResolution, error) {
	if coordinator == nil || localFallback == nil ||
		!validResolutionRecord(record) {
		return payment.CanonicalReversalResolution{}, ErrInvalidTransition
	}
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	if stored, resolved := coordinator.resolutions[record.QuarantineID]; resolved {
		if !resolvedReversalMatchesRecord(stored, record) {
			return payment.CanonicalReversalResolution{}, ErrInvalidTransition
		}
		return payment.CanonicalReversalResolution{
			JournalIDs:          slices.Clone(stored.JournalIDs),
			FailureEvidenceHash: stored.Resolution.FailureEvidenceHash,
		}, nil
	}
	plan, exists := coordinator.plans[record.PaymentID]
	pending, pendingExists := coordinator.pending[record.PaymentID]
	if !exists || !pendingExists || plan.State != StateQuarantined ||
		plan.AllocationID != record.AllocationID ||
		plan.InstructionDigest != record.InstructionDigest ||
		!samePendingReversal(pending, record) ||
		record.ReceivedAt.Before(pending.ReceivedAt) {
		return payment.CanonicalReversalResolution{}, ErrInvalidTransition
	}
	claim, claimExists := coordinator.modes.Lookup(record.PaymentID)
	if !claimExists || claim.State != allocationmode.CanonicalQuarantined ||
		!claimMatchesPlan(claim, plan) {
		return payment.CanonicalReversalResolution{}, ErrInvalidTransition
	}
	failureEvidenceHash, failureProof, err :=
		validateReversalFailureProof(plan, pending, record)
	if err != nil {
		return payment.CanonicalReversalResolution{}, err
	}
	nextPlan := clonePlan(plan)
	nextPlan.State = StateFailed
	nextPlan.Version++
	nextPlan.FailureReason = "PROVIDER_REVERSAL_RESOLVED"
	nextClaim := claim
	nextClaim.State = allocationmode.CanonicalFailed
	nextRecord, err := coordinator.durableRecordWith(
		nextPlan,
		nextClaim,
		true,
		nil,
	)
	if err != nil {
		return payment.CanonicalReversalResolution{}, err
	}
	requestDigest := reversalResolutionRequestDigest(
		pending,
		record.ResolutionID,
		failureEvidenceHash,
		failureProof,
		record.ResolutionEvidence,
		record.ResolvedBy,
		record.ReceivedAt,
	)
	resolution := PendingReversalResolution{
		Pending:             pending,
		RequestDigest:       requestDigest,
		ResolutionID:        record.ResolutionID,
		ReversalEventID:     record.ReversalEventID,
		FailureEvidenceHash: failureEvidenceHash,
		FailureProof:        failureProof,
		ResolutionEvidence:  record.ResolutionEvidence,
		ResolvedBy:          record.ResolvedBy,
		ResolvedAt:          record.ReceivedAt.UTC(),
	}
	var journalIDs []string
	err = coordinator.modes.ResolveQuarantinedReversal(claim, func() error {
		var storeErr error
		journalIDs, storeErr = coordinator.store.ResolvePendingReversal(
			StateQuarantined,
			plan.Version,
			nextRecord,
			resolution,
			localFallback,
		)
		return storeErr
	})
	if err != nil {
		return payment.CanonicalReversalResolution{},
			errors.Join(ErrInvalidTransition, err)
	}
	coordinator.plans[record.PaymentID] = nextPlan
	delete(coordinator.pending, record.PaymentID)
	coordinator.resolutions[record.QuarantineID] = StoredReversalResolution{
		Resolution: resolution,
		JournalIDs: slices.Clone(journalIDs),
	}
	return payment.CanonicalReversalResolution{
		JournalIDs:          slices.Clone(journalIDs),
		FailureEvidenceHash: failureEvidenceHash,
	}, nil
}

func (coordinator *Coordinator) ResolvedProviderReversal(
	request payment.CanonicalReversalResolutionRequest,
) (payment.CanonicalReversalResolutionRecord, bool, error) {
	if coordinator == nil || request.QuarantineID == "" ||
		request.ResolutionID == "" || request.PaymentID == "" ||
		request.AllocationID == "" || request.InstructionDigest == "" ||
		request.ResolutionEvidenceHash == "" || request.ResolvedBy == "" ||
		request.ResolvedAt.IsZero() {
		return payment.CanonicalReversalResolutionRecord{}, false,
			ErrInvalidTransition
	}
	coordinator.mu.RLock()
	defer coordinator.mu.RUnlock()
	stored, exists := coordinator.resolutions[request.QuarantineID]
	if !exists {
		return payment.CanonicalReversalResolutionRecord{}, false, nil
	}
	resolution := stored.Resolution
	failure := request.FailureProof.Evidence()
	digest := reversalResolutionRequestDigest(
		resolution.Pending,
		request.ResolutionID,
		resolution.FailureEvidenceHash,
		failure,
		request.ResolutionEvidenceHash,
		request.ResolvedBy,
		request.ResolvedAt,
	)
	if resolution.Pending.PaymentID != request.PaymentID ||
		resolution.Pending.AllocationID != request.AllocationID ||
		resolution.Pending.InstructionDigest != request.InstructionDigest ||
		resolution.ResolutionID != request.ResolutionID ||
		resolution.ResolutionEvidence != request.ResolutionEvidenceHash ||
		resolution.ResolvedBy != request.ResolvedBy ||
		!resolution.ResolvedAt.Equal(request.ResolvedAt.UTC()) ||
		resolution.FailureProof != failure ||
		resolution.RequestDigest != digest {
		return payment.CanonicalReversalResolutionRecord{}, false,
			ErrInvalidTransition
	}
	return payment.CanonicalReversalResolutionRecord{
		QuarantineID:                 resolution.Pending.QuarantineID,
		ResolutionID:                 resolution.ResolutionID,
		PaymentID:                    resolution.Pending.PaymentID,
		AllocationID:                 resolution.Pending.AllocationID,
		InstructionDigest:            resolution.Pending.InstructionDigest,
		ProviderID:                   resolution.Pending.ProviderID,
		ProviderEventID:              resolution.Pending.ProviderEventID,
		ProviderReference:            resolution.Pending.ProviderReference,
		AssetID:                      resolution.Pending.AssetID,
		Units:                        resolution.Pending.Units,
		RawHash:                      resolution.Pending.RawHash,
		RequestDigest:                resolution.RequestDigest,
		CanonicalFailureEvidenceHash: resolution.FailureEvidenceHash,
		ResolutionEvidenceHash:       resolution.ResolutionEvidence,
		ResolvedBy:                   resolution.ResolvedBy,
		ResolvedAt:                   resolution.ResolvedAt.UTC(),
		JournalIDs:                   slices.Clone(stored.JournalIDs),
	}, true, nil
}

func (coordinator *Coordinator) PendingProviderReversals() []payment.CanonicalReversalRecord {
	if coordinator == nil {
		return nil
	}
	coordinator.mu.RLock()
	defer coordinator.mu.RUnlock()
	result := make([]payment.CanonicalReversalRecord, 0, len(coordinator.pending))
	for _, pending := range coordinator.pending {
		result = append(result, payment.CanonicalReversalRecord{
			QuarantineID:      pending.QuarantineID,
			IngressID:         pending.IngressID,
			PaymentID:         pending.PaymentID,
			AllocationID:      pending.AllocationID,
			InstructionDigest: pending.InstructionDigest,
			ProviderID:        pending.ProviderID,
			ProviderEventID:   pending.ProviderEventID,
			ReversalEventID: canonicalPaymentEventID(
				pending.ProviderID,
				pending.ProviderEventID,
			),
			ProviderReference:    pending.ProviderReference,
			AssetID:              pending.AssetID,
			Units:                pending.Units,
			RawHash:              pending.RawHash,
			SignatureHash:        pending.SignatureHash,
			CallbackEvidenceHash: pending.CallbackEvidenceHash,
			CallbackExpiresAt:    pending.CallbackExpiresAt.UTC(),
			OccurredAt:           pending.OccurredAt.UTC(),
			ReceivedAt:           pending.ReceivedAt.UTC(),
		})
	}
	slices.SortFunc(result, func(left, right payment.CanonicalReversalRecord) int {
		switch {
		case left.PaymentID < right.PaymentID:
			return -1
		case left.PaymentID > right.PaymentID:
			return 1
		default:
			return 0
		}
	})
	return result
}

func (coordinator *Coordinator) ConsumedProviderReversals() []payment.CanonicalReversalConsumption {
	if coordinator == nil {
		return nil
	}
	coordinator.mu.RLock()
	defer coordinator.mu.RUnlock()
	result := make([]payment.CanonicalReversalConsumption, 0, len(coordinator.consumed))
	for _, consumed := range coordinator.consumed {
		pending := consumed.Pending
		result = append(result, payment.CanonicalReversalConsumption{
			QuarantineID:           pending.QuarantineID,
			IngressID:              pending.IngressID,
			PaymentID:              pending.PaymentID,
			AllocationID:           pending.AllocationID,
			InstructionDigest:      pending.InstructionDigest,
			ProviderID:             pending.ProviderID,
			ProviderEventID:        pending.ProviderEventID,
			ProviderReference:      pending.ProviderReference,
			AssetID:                pending.AssetID,
			Units:                  pending.Units,
			RawHash:                pending.RawHash,
			SignatureHash:          pending.SignatureHash,
			CallbackEvidenceHash:   pending.CallbackEvidenceHash,
			CallbackExpiresAt:      pending.CallbackExpiresAt.UTC(),
			CallbackOccurredAt:     pending.OccurredAt.UTC(),
			CallbackReceivedAt:     pending.ReceivedAt.UTC(),
			ResolutionID:           consumed.ResolutionID,
			ResolutionEvidenceHash: consumed.ResolutionEvidenceHash,
			ResolvedBy:             consumed.ResolvedBy,
			ResolvedAt:             consumed.ResolvedAt.UTC(),
			GatewayEventID:         consumed.GatewayEventID,
			GatewayTransactionHash: consumed.GatewayTransactionHash,
			GatewayRawPayloadHash:  consumed.GatewayRawPayloadHash,
			FinalityEvidenceHash:   consumed.FinalityEvidenceHash,
		})
	}
	slices.SortFunc(result, func(left, right payment.CanonicalReversalConsumption) int {
		switch {
		case left.QuarantineID < right.QuarantineID:
			return -1
		case left.QuarantineID > right.QuarantineID:
			return 1
		default:
			return 0
		}
	})
	return result
}

func pendingSnapshot(
	record payment.CanonicalReversalRecord,
	plan Plan,
	originState State,
) PendingReversalSnapshot {
	pending := PendingReversalSnapshot{
		QuarantineID:         record.QuarantineID,
		IngressID:            record.IngressID,
		ProviderID:           record.ProviderID,
		ProviderEventID:      record.ProviderEventID,
		ProviderReference:    record.ProviderReference,
		AssetID:              record.AssetID,
		Units:                record.Units,
		RawHash:              record.RawHash,
		SignatureHash:        record.SignatureHash,
		PaymentID:            plan.PaymentID,
		AllocationID:         plan.AllocationID,
		InstructionDigest:    plan.InstructionDigest,
		CallbackEvidenceHash: record.CallbackEvidenceHash,
		CallbackExpiresAt:    record.CallbackExpiresAt.UTC(),
		OccurredAt:           record.OccurredAt.UTC(),
		ReceivedAt:           record.ReceivedAt.UTC(),
		OriginState:          originState,
	}
	if originState == StateSubmitted {
		pending.SubmissionChainID = plan.Submission.ChainID
		pending.SubmissionGateway = plan.Submission.Gateway
		pending.SubmissionTxHash = plan.Submission.TransactionHash
		pending.SubmissionSubmittedAt = plan.Submission.SubmittedAt.UTC()
	}
	return pending
}

func validReversalRecord(record payment.CanonicalReversalRecord) bool {
	return record.QuarantineID != "" &&
		record.IngressID > 0 &&
		record.PaymentID != "" &&
		record.ProviderID != "" &&
		record.ProviderEventID != "" &&
		record.ReversalEventID ==
			canonicalPaymentEventID(record.ProviderID, record.ProviderEventID) &&
		record.AssetID != "" &&
		record.Units != "" &&
		record.RawHash != "" &&
		record.SignatureHash != "" &&
		record.CallbackEvidenceHash != "" &&
		!record.CallbackExpiresAt.IsZero() &&
		!record.OccurredAt.IsZero() &&
		!record.ReceivedAt.IsZero() &&
		!record.ReceivedAt.Before(record.OccurredAt)
}

func validResolutionRecord(record payment.CanonicalReversalRecord) bool {
	return validReversalRecord(record) &&
		record.ResolutionID != "" &&
		record.AllocationID != "" &&
		record.InstructionDigest != "" &&
		record.ResolutionEvidence != "" &&
		record.ResolvedBy != ""
}

func samePendingReversal(
	pending PendingReversalSnapshot,
	record payment.CanonicalReversalRecord,
) bool {
	return pending.QuarantineID == record.QuarantineID &&
		pending.IngressID == record.IngressID &&
		pending.PaymentID == record.PaymentID &&
		pending.ProviderID == record.ProviderID &&
		pending.ProviderEventID == record.ProviderEventID &&
		pending.ProviderReference == record.ProviderReference &&
		pending.AssetID == record.AssetID &&
		pending.Units == record.Units &&
		pending.RawHash == record.RawHash &&
		pending.SignatureHash == record.SignatureHash &&
		pending.CallbackEvidenceHash == record.CallbackEvidenceHash &&
		pending.CallbackExpiresAt.Equal(record.CallbackExpiresAt.UTC()) &&
		pending.OccurredAt.Equal(record.OccurredAt.UTC())
}

func validateReversalFailureProof(
	plan Plan,
	pending PendingReversalSnapshot,
	record payment.CanonicalReversalRecord,
) (string, chainprojection.TransactionFailureEvidence, error) {
	failure := record.FailureProof.Evidence()
	switch pending.OriginState {
	case StateSubmitted:
		if failure.Status != chainprojection.TransactionReverted ||
			failure.EvidenceHash == "" ||
			failure.ReceiptPayloadHash == "" ||
			failure.ChainID != plan.Submission.ChainID ||
			failure.Gateway != plan.Submission.Gateway ||
			failure.TransactionHash != plan.Submission.TransactionHash ||
			failure.FinalityPolicyHash != plan.FinalityPolicyHash ||
			failure.HeaderAuthorityHash == "" ||
			failure.ReceiptHeaderSignatureHash == "" ||
			failure.HeadHeaderSignatureHash == "" ||
			failure.ObservedAt.IsZero() ||
			failure.ObservedAt.Before(plan.Submission.SubmittedAt) ||
			failure.ObservedAt.After(record.ReceivedAt) ||
			failure.BlockNumber == 0 || failure.BlockHash == "" ||
			failure.ReceiptsRoot == "" || failure.InclusionProofHash == "" ||
			failure.ConfirmationDepth == 0 ||
			failure.HeadBlockNumber < failure.BlockNumber ||
			failure.HeadBlockNumber-failure.BlockNumber <
				failure.ConfirmationDepth ||
			failure.HeadBlockHash == "" {
			return "", chainprojection.TransactionFailureEvidence{},
				ErrInvalidTransition
		}
		return failure.EvidenceHash, failure, nil
	case StatePrepared, StateFailed:
		if failure != (chainprojection.TransactionFailureEvidence{}) {
			return "", chainprojection.TransactionFailureEvidence{},
				ErrInvalidTransition
		}
		return preSubmissionFailureEvidenceHash(plan, pending),
			chainprojection.TransactionFailureEvidence{}, nil
	default:
		return "", chainprojection.TransactionFailureEvidence{},
			ErrInvalidTransition
	}
}

func preSubmissionFailureEvidenceHash(
	plan Plan,
	pending PendingReversalSnapshot,
) string {
	encoded, _ := json.Marshal(struct {
		PaymentID            string
		AllocationID         string
		InstructionDigest    string
		OriginState          State
		QuarantineID         string
		ProviderID           string
		ProviderEventID      string
		RawHash              string
		CallbackEvidenceHash string
		OccurredAt           time.Time
		ReceivedAt           time.Time
	}{
		PaymentID:            plan.PaymentID,
		AllocationID:         plan.AllocationID,
		InstructionDigest:    plan.InstructionDigest,
		OriginState:          pending.OriginState,
		QuarantineID:         pending.QuarantineID,
		ProviderID:           pending.ProviderID,
		ProviderEventID:      pending.ProviderEventID,
		RawHash:              pending.RawHash,
		CallbackEvidenceHash: pending.CallbackEvidenceHash,
		OccurredAt:           pending.OccurredAt.UTC(),
		ReceivedAt:           pending.ReceivedAt.UTC(),
	})
	hash := sha256.Sum256(append(
		[]byte("UNIFIED_PHASE7C_PRE_SUBMISSION_REVERSAL_V1\x00"),
		encoded...,
	))
	return hex.EncodeToString(hash[:])
}

func reversalResolutionRequestDigest(
	pending PendingReversalSnapshot,
	resolutionID string,
	failureEvidenceHash string,
	failureProof chainprojection.TransactionFailureEvidence,
	resolutionEvidence string,
	resolvedBy string,
	resolvedAt time.Time,
) string {
	encoded, _ := json.Marshal(struct {
		Pending             PendingReversalSnapshot
		ResolutionID        string
		FailureEvidenceHash string
		FailureProof        chainprojection.TransactionFailureEvidence
		ResolutionEvidence  string
		ResolvedBy          string
		ResolvedAt          time.Time
	}{
		Pending:             pending,
		ResolutionID:        resolutionID,
		FailureEvidenceHash: failureEvidenceHash,
		FailureProof:        failureProof,
		ResolutionEvidence:  resolutionEvidence,
		ResolvedBy:          resolvedBy,
		ResolvedAt:          resolvedAt.UTC(),
	})
	hash := sha256.Sum256(append(
		[]byte("UNIFIED_PHASE7C_REVERSAL_RESOLUTION_V1\x00"),
		encoded...,
	))
	return hex.EncodeToString(hash[:])
}

func resolvedReversalMatchesRecord(
	stored StoredReversalResolution,
	record payment.CanonicalReversalRecord,
) bool {
	resolution := stored.Resolution
	failure := record.FailureProof.Evidence()
	digest := reversalResolutionRequestDigest(
		resolution.Pending,
		record.ResolutionID,
		resolution.FailureEvidenceHash,
		failure,
		record.ResolutionEvidence,
		record.ResolvedBy,
		record.ReceivedAt,
	)
	return samePendingReversal(resolution.Pending, record) &&
		resolution.Pending.AllocationID == record.AllocationID &&
		resolution.Pending.InstructionDigest == record.InstructionDigest &&
		resolution.ResolutionID == record.ResolutionID &&
		resolution.ReversalEventID == record.ReversalEventID &&
		resolution.FailureProof == failure &&
		resolution.ResolutionEvidence == record.ResolutionEvidence &&
		resolution.ResolvedBy == record.ResolvedBy &&
		resolution.ResolvedAt.Equal(record.ReceivedAt.UTC()) &&
		resolution.RequestDigest == digest
}

func canonicalPaymentEventID(providerID string, providerEventID string) string {
	return providerID + ":" + providerEventID
}
