package settlement

import (
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"slices"
	"testing"
	"time"

	chainprojection "github.com/unified-finance/unified/services/chain-indexer/projection"
	"github.com/unified-finance/unified/services/chain-indexer/projectiontest"
	"github.com/unified-finance/unified/services/payment-orchestrator/allocationmode"
	"github.com/unified-finance/unified/services/payment-orchestrator/payment"
)

func TestCoordinatorRestoresEveryDurableState(t *testing.T) {
	now := time.Unix(1_770_500_000, 0).UTC()
	tests := []struct {
		name  string
		state State
		drive func(*testing.T, *Coordinator, Plan) Plan
	}{
		{
			name:  "prepared",
			state: StatePrepared,
			drive: func(_ *testing.T, _ *Coordinator, plan Plan) Plan {
				return plan
			},
		},
		{
			name:  "submitted",
			state: StateSubmitted,
			drive: submitFixture,
		},
		{
			name:  "failed",
			state: StateFailed,
			drive: func(t *testing.T, coordinator *Coordinator, plan Plan) Plan {
				submitted := submitFixture(t, coordinator, plan)
				if _, err := coordinator.RecordReorg(
					submitted.Version,
					reorgEnvelope(t, eventFixture(t, submitted), false),
				); err != nil {
					t.Fatalf("record pre-finality reorg: %v", err)
				}
				failed, _ := coordinator.Plan(plan.PaymentID)
				return failed
			},
		},
		{
			name:  "confirmed",
			state: StateConfirmed,
			drive: func(t *testing.T, coordinator *Coordinator, plan Plan) Plan {
				submitted := submitFixture(t, coordinator, plan)
				if _, err := coordinator.Confirm(ConfirmationRequest{
					PaymentID:         submitted.PaymentID,
					AllocationID:      submitted.AllocationID,
					InstructionDigest: submitted.InstructionDigest,
					ExpectedVersion:   submitted.Version,
					Projection:        finalProjection(t, eventFixture(t, submitted)),
				}); err != nil {
					t.Fatalf("confirm: %v", err)
				}
				confirmed, _ := coordinator.Plan(plan.PaymentID)
				return confirmed
			},
		},
		{
			name:  "quarantined",
			state: StateQuarantined,
			drive: func(t *testing.T, coordinator *Coordinator, plan Plan) Plan {
				submitted := submitFixture(t, coordinator, plan)
				record := reversalFixture(
					submitted,
					"quarantine-restart",
					"reversal-restart",
					submitted.Submission.SubmittedAt.Add(time.Minute),
				)
				if _, disposition, err := coordinator.HandleProviderReversal(
					record,
					func() error { return nil },
				); err != nil ||
					disposition != allocationmode.ReversalQuarantined {
					t.Fatalf("quarantine reversal: %s %v", disposition, err)
				}
				quarantined, _ := coordinator.Plan(plan.PaymentID)
				return quarantined
			},
		},
		{
			name:  "incident",
			state: StateIncident,
			drive: func(t *testing.T, coordinator *Coordinator, plan Plan) Plan {
				submitted := submitFixture(t, coordinator, plan)
				if _, err := coordinator.Confirm(ConfirmationRequest{
					PaymentID:         submitted.PaymentID,
					AllocationID:      submitted.AllocationID,
					InstructionDigest: submitted.InstructionDigest,
					ExpectedVersion:   submitted.Version,
					Projection:        finalProjection(t, eventFixture(t, submitted)),
				}); err != nil {
					t.Fatalf("confirm: %v", err)
				}
				confirmed, _ := coordinator.Plan(plan.PaymentID)
				record := reversalFixture(
					confirmed,
					"quarantine-incident",
					"reversal-incident",
					confirmed.PreparedAt.Add(3*time.Minute),
				)
				if _, disposition, err := coordinator.HandleProviderReversal(
					record,
					func() error { return nil },
				); err != nil ||
					disposition != allocationmode.ReversalIncident {
					t.Fatalf("incident reversal: %s %v", disposition, err)
				}
				incident, _ := coordinator.Plan(plan.PaymentID)
				return incident
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			store := NewMemoryStore()
			modeStore := allocationmode.NewMemoryStore()
			modes, err := allocationmode.New(modeStore)
			if err != nil {
				t.Fatal(err)
			}
			coordinator, err := New(modes, store)
			if err != nil {
				t.Fatal(err)
			}
			plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
			if err != nil {
				t.Fatal(err)
			}
			expected := test.drive(t, coordinator, plan)
			restartedModes, err := allocationmode.New(modeStore)
			if err != nil {
				t.Fatal(err)
			}
			restarted, err := New(restartedModes, store)
			if err != nil {
				t.Fatalf("restart coordinator: %v", err)
			}
			actual, exists := restarted.Plan(expected.PaymentID)
			claim, claimed := restartedModes.Lookup(expected.PaymentID)
			if !exists || !claimed || actual.State != test.state ||
				actual.Version != expected.Version ||
				claim.State != canonicalFromState(test.state) {
				t.Fatalf(
					"restored state mismatch: plan=%#v claim=%#v",
					actual,
					claim,
				)
			}
			if test.state == StateConfirmed || test.state == StateIncident {
				if _, exists := restarted.Confirmation(expected.PaymentID); !exists {
					t.Fatal("restart lost opaque confirmation")
				}
			}
			if test.state == StateQuarantined &&
				len(restarted.PendingProviderReversals()) != 1 {
				t.Fatal("restart lost pending reversal metadata")
			}
		})
	}
}

func TestStoreRejectsStaleCoordinatorWriterBeforePublication(t *testing.T) {
	now := time.Unix(1_770_600_000, 0).UTC()
	store := NewMemoryStore()
	first, err := New(allocationmode.NewInMemory(), store)
	if err != nil {
		t.Fatal(err)
	}
	plan, err := first.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	second, err := New(allocationmode.NewInMemory(), store)
	if err != nil {
		t.Fatal(err)
	}
	submission := SubmissionRequest{
		PaymentID:         plan.PaymentID,
		AllocationID:      plan.AllocationID,
		InstructionDigest: plan.InstructionDigest,
		ExpectedVersion:   plan.Version,
		ChainID:           plan.ChainID,
		Gateway:           plan.GatewayAddress,
		Sender:            plan.FinalizerAddress,
		SenderNonce:       9,
		TransactionHash:   bytes32Uint(100),
		CalldataHash:      "calldata-stale-writer",
		SubmittedAt:       plan.PreparedAt.Add(time.Minute),
	}
	if _, err := first.Submit(submission); err != nil {
		t.Fatalf("first writer: %v", err)
	}
	if _, err := second.Submit(submission); !errors.Is(err, ErrStoreConflict) {
		t.Fatalf("stale writer was not rejected by durable CAS: %v", err)
	}
	stale, _ := second.Plan(plan.PaymentID)
	if stale.State != StatePrepared || stale.Version != 1 {
		t.Fatalf("failed CAS leaked in-memory publication: %#v", stale)
	}
	restarted, err := New(allocationmode.NewInMemory(), store)
	if err != nil {
		t.Fatal(err)
	}
	current, _ := restarted.Plan(plan.PaymentID)
	if current.State != StateSubmitted || current.Version != 2 {
		t.Fatalf("durable winner was not authoritative: %#v", current)
	}
}

func TestDeepReorgAuthoritySurvivesCrashAndRestart(t *testing.T) {
	now := time.Unix(1_770_750_000, 0).UTC()
	store := NewMemoryStore()
	modeStore := allocationmode.NewMemoryStore()
	modes, err := allocationmode.New(modeStore)
	if err != nil {
		t.Fatal(err)
	}
	coordinator, err := New(modes, store)
	if err != nil {
		t.Fatal(err)
	}
	plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, plan)
	event := eventFixture(t, submitted)
	projection := finalProjection(t, event)
	if _, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        projection,
	}); err != nil {
		t.Fatal(err)
	}
	confirmed, _ := coordinator.Plan(submitted.PaymentID)
	envelope := reorgEnvelope(t, event, true)
	authority, err := coordinator.RecordReorg(
		confirmed.Version,
		envelope,
	)
	if err != nil {
		t.Fatal(err)
	}
	expected := authority.Evidence()
	if expected.TransactionIndex != projection.Settlement().TransactionIndex ||
		expected.OrphanedEventEvidenceHash !=
			projection.Settlement().EvidenceHash ||
		expected.ReceiptsRoot == "" ||
		expected.InclusionProofHash == "" ||
		expected.FinalityPolicyHash != submitted.FinalityPolicyHash ||
		expected.HeaderAuthorityHash != projection.Proof().HeaderAuthorityHash ||
		expected.OrphanedReceiptHeaderSignatureHash == "" ||
		expected.ReplacementHeaderSignatureHash == "" ||
		expected.DetectedHeadHeaderSignatureHash == "" {
		t.Fatalf("durable authority lost authenticated provenance: %#v", expected)
	}

	// Simulate process loss after the coordinator's INCIDENT CAS and before any
	// accounting compensation consumes the returned opaque authority.
	restartedModes, err := allocationmode.New(modeStore)
	if err != nil {
		t.Fatal(err)
	}
	restarted, err := New(restartedModes, store)
	if err != nil {
		t.Fatalf("restart coordinator: %v", err)
	}
	recovered, exists := restarted.ReorgAuthority(expected.ReorgID)
	if !exists || recovered.Evidence() != expected {
		t.Fatalf(
			"restart did not reconstruct exact opaque reorg authority: %#v %#v",
			recovered.Evidence(),
			expected,
		)
	}
	replayed, err := restarted.RecordReorg(confirmed.Version, envelope)
	if err != nil || replayed.Evidence() != expected {
		t.Fatalf(
			"restart exact replay changed durable authority: %#v %v",
			replayed.Evidence(),
			err,
		)
	}
	if zero := (DurableReorgAuthority{}).Evidence(); zero.ReorgID != "" {
		t.Fatalf("zero authority unexpectedly carried evidence: %#v", zero)
	}

	originalRecord := cloneStoredCoordinator(store.records[submitted.PaymentID])
	for _, test := range []struct {
		name   string
		mutate func(*ReorgEvidence)
	}{
		{
			name: "omitted event evidence",
			mutate: func(reorg *ReorgEvidence) {
				reorg.OrphanedEventEvidenceHash = ""
			},
		},
		{
			name: "mutated event evidence",
			mutate: func(reorg *ReorgEvidence) {
				reorg.OrphanedEventEvidenceHash = bytes32Uint(777)
			},
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			record := cloneStoredCoordinator(originalRecord)
			snapshot, err := decodeDurableSnapshot(record.Snapshot)
			if err != nil || len(snapshot.Reorgs) != 1 {
				t.Fatalf("decode durable authority: %#v %v", snapshot, err)
			}
			test.mutate(&snapshot.Reorgs[0])
			record.Snapshot, err = encodeDurableSnapshot(snapshot)
			if err != nil {
				t.Fatal(err)
			}
			tamperedStore := NewMemoryStore()
			tamperedStore.records[record.PaymentID] = record
			if _, err := New(
				allocationmode.NewInMemory(),
				tamperedStore,
			); !errors.Is(err, ErrInvalidPlan) {
				t.Fatalf("invalid durable event evidence restored: %v", err)
			}
		})
	}
}

func TestImmutableReplayIgnoresHeadAdvancementAndStaleVersion(t *testing.T) {
	now := time.Unix(1_770_700_000, 0).UTC()
	coordinator, err := NewInMemory(allocationmode.NewInMemory())
	if err != nil {
		t.Fatal(err)
	}
	plan, _ := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	submitted := submitFixture(t, coordinator, plan)
	raw := eventFixture(t, submitted)
	indexer, event := projectionIndexer(t, raw, true)
	firstProjection, _ := indexer.FinalizedGatewayProjection(event.PaymentID)
	first, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        firstProjection,
	})
	if err != nil {
		t.Fatal(err)
	}
	head := firstProjection.Proof()
	advancedBlock, _ := projectiontest.NewBuilder(submitted.ChainID).EmptyBlock(
		head.HeadBlockNumber+1,
		head.HeadBlockHash,
		first.AccountingProjection().ConfirmedAt.Add(time.Minute),
	)
	if err := indexer.IngestAuthenticated(advancedBlock); err != nil {
		t.Fatal(err)
	}
	advancedProjection, _ := indexer.FinalizedGatewayProjection(event.PaymentID)
	replayed, err := coordinator.Confirm(ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        advancedProjection,
	})
	if err != nil || !replayed.Replayed() ||
		replayed.EventID() != first.EventID() {
		t.Fatalf("head advancement broke immutable replay: %#v %v", replayed, err)
	}
}

func TestFailConsumesOnlyIndexerVerifiedRevertedReceipt(t *testing.T) {
	now := time.Unix(1_770_750_000, 0).UTC()
	coordinator, _ := NewInMemory(allocationmode.NewInMemory())
	plan, _ := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	submitted := submitFixture(t, coordinator, plan)
	verified := verifiedFailureFixture(t, submitted)
	request := FailureRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Proof:             verified,
	}
	failed, err := coordinator.Fail(request)
	if err != nil || failed.State != StateFailed ||
		failed.FailureProof != verified.Evidence() {
		t.Fatalf("verified failure was not retained: %#v %v", failed, err)
	}
	replayed, err := coordinator.Fail(request)
	if err != nil || !replayed.Replayed ||
		replayed.Version != failed.Version {
		t.Fatalf("verified failure replay was not stable: %#v %v", replayed, err)
	}
	if _, err := coordinator.Fail(FailureRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
	}); !errors.Is(err, ErrInvalidTransition) {
		t.Fatalf("forgeable empty failure proof was accepted: %v", err)
	}
}

func TestReorgReplayPrecedesExpectedVersionCheck(t *testing.T) {
	now := time.Unix(1_770_800_000, 0).UTC()
	coordinator, _ := NewInMemory(allocationmode.NewInMemory())
	plan, _ := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	submitted := submitFixture(t, coordinator, plan)
	envelope := reorgEnvelope(t, eventFixture(t, submitted), false)
	first, err := coordinator.RecordReorg(submitted.Version, envelope)
	if err != nil {
		t.Fatal(err)
	}
	replayed, err := coordinator.RecordReorg(submitted.Version, envelope)
	replayedEvidence := replayed.Evidence()
	if err != nil || replayedEvidence != first.Evidence() ||
		replayedEvidence.ReorgID != "reorg:"+replayedEvidence.EvidenceHash {
		t.Fatalf("stale-version reorg replay failed: %#v %v", replayed, err)
	}
}

func TestPaymentRestartResolvesRecoveredPendingReversal(t *testing.T) {
	now := time.Unix(1_770_900_000, 0).UTC()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	store := NewMemoryStore()
	modeStore := allocationmode.NewMemoryStore()
	modes, err := allocationmode.New(modeStore)
	if err != nil {
		t.Fatal(err)
	}
	coordinator, err := New(modes, store)
	if err != nil {
		t.Fatal(err)
	}
	plan, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, plan)
	provider := payment.Provider{
		ID:               plan.ProviderID,
		Rail:             payment.RailBank,
		PublicKey:        publicKey,
		Active:           true,
		AssetID:          plan.SourceAssetID,
		SupportsReversal: true,
		Version:          1,
	}
	firstAccounting := &restartAccounting{}
	firstPayment, err := payment.New(
		[]payment.Provider{provider},
		firstAccounting,
		modes,
		coordinator,
	)
	if err != nil {
		t.Fatal(err)
	}
	finalIntent := restoredFinalIntent(plan, now)
	if err := firstPayment.RestorePayment(finalIntent); err != nil {
		t.Fatal(err)
	}
	callback := payment.Callback{
		ProviderID:        plan.ProviderID,
		ProviderEventID:   "provider-reversal-restart",
		PaymentID:         plan.PaymentID,
		ProviderReference: plan.ProviderReference,
		Status:            payment.StatusReversed,
		AssetID:           plan.SourceAssetID,
		Units:             plan.SourceUnits,
		OccurredAt:        submitted.Submission.SubmittedAt.Add(time.Minute),
		ExpiresAt:         submitted.Submission.SubmittedAt.Add(time.Hour),
		EvidenceHash:      "provider-reversal-restart-evidence",
	}
	raw, err := payment.EncodeCallback(callback)
	if err != nil {
		t.Fatal(err)
	}
	signature := ed25519.Sign(
		privateKey,
		payment.SigningMessage(raw),
	)
	receivedAt := callback.OccurredAt.Add(time.Minute)
	if _, err := firstPayment.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		receivedAt,
	); !errors.Is(err, payment.ErrCanonicalPending) {
		t.Fatalf("submitted reversal was not quarantined: %v", err)
	}

	restartedModes, err := allocationmode.New(modeStore)
	if err != nil {
		t.Fatal(err)
	}
	restartedCoordinator, err := New(restartedModes, store)
	if err != nil {
		t.Fatal(err)
	}
	restartedAccounting := &restartAccounting{}
	restartedPayment, err := payment.New(
		[]payment.Provider{provider},
		restartedAccounting,
		restartedModes,
		restartedCoordinator,
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := restartedPayment.RestorePayment(finalIntent); err != nil {
		t.Fatal(err)
	}
	pending := restartedCoordinator.PendingProviderReversals()
	recoveredPending := restartedCoordinator.pending[plan.PaymentID]
	if len(pending) != 1 ||
		recoveredPending.OriginState != StateSubmitted {
		t.Fatalf("restart lost pending reversal: %#v", pending)
	}
	resolutionRequest := payment.CanonicalReversalResolutionRequest{
		QuarantineID:           pending[0].QuarantineID,
		ResolutionID:           "resolution-after-restart",
		PaymentID:              plan.PaymentID,
		AllocationID:           plan.AllocationID,
		InstructionDigest:      plan.InstructionDigest,
		FailureProof:           verifiedFailureFixture(t, submitted),
		ResolutionEvidenceHash: "resolution-after-restart-evidence",
		ResolvedBy:             "payment-operator",
		ResolvedAt:             receivedAt.Add(time.Minute),
	}
	result, resolution, err := restartedPayment.ResolveCanonicalReversal(
		resolutionRequest,
	)
	if err != nil || result.Payment.Status != payment.StatusReversed ||
		len(restartedAccounting.transitions) != 1 ||
		len(restartedCoordinator.PendingProviderReversals()) != 0 {
		t.Fatalf("restart resolution failed: %#v %v", result, err)
	}
	exactResult, exactResolution, err :=
		restartedPayment.ResolveCanonicalReversal(resolutionRequest)
	if err != nil || !exactResult.Replayed ||
		!slices.Equal(exactResult.JournalIDs, result.JournalIDs) ||
		exactResolution != resolution ||
		len(restartedAccounting.transitions) != 1 {
		t.Fatalf(
			"same-process exact resolution replay changed result: %#v %#v %v",
			exactResult,
			exactResolution,
			err,
		)
	}
	alteredRequest := resolutionRequest
	alteredRequest.ResolutionEvidenceHash = "altered-resolution-after-restart"
	if _, _, err := restartedPayment.ResolveCanonicalReversal(
		alteredRequest,
	); !errors.Is(err, payment.ErrInvalidResolution) {
		t.Fatalf("altered resolution replay was accepted: %v", err)
	}
	finalPlan, _ := restartedCoordinator.Plan(plan.PaymentID)
	if finalPlan.State != StateFailed ||
		!restartedModes.IsReversed(plan.PaymentID) {
		t.Fatalf("resolution was not durably tombstoned: %#v", finalPlan)
	}
	finalModes, err := allocationmode.New(modeStore)
	if err != nil {
		t.Fatal(err)
	}
	finalCoordinator, err := New(finalModes, store)
	if err != nil {
		t.Fatalf("tombstoned restart: %v", err)
	}
	tombstonedPlan, _ := finalCoordinator.Plan(plan.PaymentID)
	if tombstonedPlan.State != StateFailed ||
		!finalModes.IsReversed(plan.PaymentID) {
		t.Fatalf("tombstone rollback on restart: %#v", tombstonedPlan)
	}
	finalAccounting := &restartAccounting{}
	finalPayment, err := payment.New(
		[]payment.Provider{provider},
		finalAccounting,
		finalModes,
		finalCoordinator,
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := finalPayment.RestorePayment(finalIntent); err != nil {
		t.Fatal(err)
	}
	recoveredResult, recoveredResolution, err :=
		finalPayment.ResolveCanonicalReversal(resolutionRequest)
	if err != nil || !recoveredResult.Replayed ||
		recoveredResult.Payment.Status != payment.StatusReversed ||
		!slices.Equal(recoveredResult.JournalIDs, result.JournalIDs) ||
		recoveredResolution != resolution ||
		len(finalAccounting.transitions) != 0 {
		t.Fatalf(
			"restart exact resolution replay changed result: %#v %#v %v",
			recoveredResult,
			recoveredResolution,
			err,
		)
	}
	callbackReplay, err := finalPayment.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		receivedAt,
	)
	if err != nil || !callbackReplay.Replayed ||
		callbackReplay.Payment.Status != payment.StatusReversed ||
		!slices.Equal(callbackReplay.JournalIDs, result.JournalIDs) {
		t.Fatalf("restart callback replay lost resolved result: %#v %v", callbackReplay, err)
	}
}

func TestCanonicalSuccessConsumesSubmittedReversalAcrossRestart(t *testing.T) {
	now := time.Unix(1_770_950_000, 0).UTC()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	store := NewMemoryStore()
	modeStore := allocationmode.NewMemoryStore()
	modes, err := allocationmode.New(modeStore)
	if err != nil {
		t.Fatal(err)
	}
	coordinator, err := New(modes, store)
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, prepared)
	provider := payment.Provider{
		ID:               submitted.ProviderID,
		Rail:             payment.RailBank,
		PublicKey:        publicKey,
		Active:           true,
		AssetID:          submitted.SourceAssetID,
		SupportsReversal: true,
		Version:          1,
	}
	accounting := &restartAccounting{}
	payments, err := payment.New(
		[]payment.Provider{provider},
		accounting,
		modes,
		coordinator,
	)
	if err != nil {
		t.Fatal(err)
	}
	finalIntent := restoredFinalIntent(submitted, now)
	if err := payments.RestorePayment(finalIntent); err != nil {
		t.Fatal(err)
	}
	callback := payment.Callback{
		ProviderID:        submitted.ProviderID,
		ProviderEventID:   "provider-reversal-canonical-success",
		PaymentID:         submitted.PaymentID,
		ProviderReference: submitted.ProviderReference,
		Status:            payment.StatusReversed,
		AssetID:           submitted.SourceAssetID,
		Units:             submitted.SourceUnits,
		OccurredAt:        submitted.Submission.SubmittedAt.Add(time.Minute),
		ExpiresAt:         submitted.Submission.SubmittedAt.Add(time.Hour),
		EvidenceHash:      "provider-reversal-canonical-success-evidence",
	}
	raw, err := payment.EncodeCallback(callback)
	if err != nil {
		t.Fatal(err)
	}
	signature := ed25519.Sign(privateKey, payment.SigningMessage(raw))
	receivedAt := callback.OccurredAt.Add(time.Minute)
	if _, err := payments.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		receivedAt,
	); !errors.Is(err, payment.ErrCanonicalPending) {
		t.Fatalf("submitted reversal was not quarantined: %v", err)
	}

	projection := finalProjection(t, eventFixture(t, submitted))
	request := ConfirmationRequest{
		PaymentID:         submitted.PaymentID,
		AllocationID:      submitted.AllocationID,
		InstructionDigest: submitted.InstructionDigest,
		ExpectedVersion:   submitted.Version,
		Projection:        projection,
	}
	confirmation, err := coordinator.Confirm(request)
	if err != nil {
		t.Fatalf("canonical success did not consume quarantine: %v", err)
	}
	accountingProjection := confirmation.AccountingProjection()
	current, _ := coordinator.Plan(submitted.PaymentID)
	if current.State != StateIncident || !accountingProjection.Incident ||
		len(coordinator.PendingProviderReversals()) != 0 ||
		len(coordinator.ConsumedProviderReversals()) != 1 ||
		accountingProjection.ReceiptsRoot == "" ||
		accountingProjection.InclusionProofHash == "" ||
		accountingProjection.HeaderAuthorityHash == "" ||
		accountingProjection.ReceiptHeaderSignatureHash == "" ||
		accountingProjection.HeadHeaderSignatureHash == "" ||
		len(accounting.transitions) != 0 {
		t.Fatalf(
			"canonical success lost incident or authenticated provenance: %#v %#v",
			current,
			accountingProjection,
		)
	}
	replayed, err := coordinator.Confirm(request)
	if err != nil || !replayed.Replayed() {
		t.Fatalf("exact incident confirmation did not replay: %#v %v", replayed, err)
	}
	alteredEvent := eventFixture(t, submitted)
	alteredEvent.Data = append([]byte(nil), alteredEvent.Data...)
	copy(alteredEvent.Data[:32], hexWord(t, bytes32Uint(999)))
	alteredRequest := request
	alteredRequest.Projection = finalProjection(t, alteredEvent)
	if _, err := coordinator.Confirm(alteredRequest); !errors.Is(err, ErrPlanConflict) {
		t.Fatalf("altered canonical event replay was accepted: %v", err)
	}
	incidentResult, err := payments.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		receivedAt,
	)
	if !errors.Is(err, payment.ErrCanonicalConfirmed) ||
		incidentResult.Disposition != "INCIDENT" ||
		incidentResult.Payment.Status != payment.StatusFinal {
		t.Fatalf("consumed callback did not replay as incident: %#v %v", incidentResult, err)
	}
	alteredCallback := callback
	alteredCallback.EvidenceHash = "altered-provider-reversal-evidence"
	alteredRaw, err := payment.EncodeCallback(alteredCallback)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := payments.IngestCallback(
		alteredCallback.ProviderID,
		alteredCallback.ProviderEventID,
		alteredRaw,
		ed25519.Sign(privateKey, payment.SigningMessage(alteredRaw)),
		receivedAt,
	); !errors.Is(err, payment.ErrCallbackConflict) {
		t.Fatalf("altered consumed callback was accepted: %v", err)
	}

	restartedModes, err := allocationmode.New(modeStore)
	if err != nil {
		t.Fatal(err)
	}
	restartedCoordinator, err := New(restartedModes, store)
	if err != nil {
		t.Fatalf("restart coordinator: %v", err)
	}
	restartedAccounting := &restartAccounting{}
	restartedPayments, err := payment.New(
		[]payment.Provider{provider},
		restartedAccounting,
		restartedModes,
		restartedCoordinator,
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := restartedPayments.RestorePayment(finalIntent); err != nil {
		t.Fatal(err)
	}
	restartedResult, err := restartedPayments.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		receivedAt,
	)
	restartedPlan, _ := restartedCoordinator.Plan(submitted.PaymentID)
	if !errors.Is(err, payment.ErrCanonicalConfirmed) ||
		restartedResult.Disposition != "INCIDENT" ||
		restartedPlan.State != StateIncident ||
		len(restartedCoordinator.ConsumedProviderReversals()) != 1 ||
		len(restartedAccounting.transitions) != 0 {
		t.Fatalf(
			"restart lost consumed reversal incident: %#v %#v %v",
			restartedResult,
			restartedPlan,
			err,
		)
	}
}

func TestResolutionResponseLossRecoversWithoutRepostingAccounting(t *testing.T) {
	now := time.Unix(1_770_975_000, 0).UTC()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	durableStore := NewMemoryStore()
	store := &responseLossStore{
		Store: durableStore,
		fail:  true,
	}
	modes := allocationmode.NewInMemory()
	coordinator, err := New(modes, store)
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := coordinator.Prepare(prepareFixture(now, "400", "1000"))
	if err != nil {
		t.Fatal(err)
	}
	submitted := submitFixture(t, coordinator, prepared)
	provider := payment.Provider{
		ID:               submitted.ProviderID,
		Rail:             payment.RailBank,
		PublicKey:        publicKey,
		Active:           true,
		AssetID:          submitted.SourceAssetID,
		SupportsReversal: true,
		Version:          1,
	}
	accounting := &restartAccounting{}
	payments, err := payment.New(
		[]payment.Provider{provider},
		accounting,
		modes,
		coordinator,
	)
	if err != nil {
		t.Fatal(err)
	}
	finalIntent := restoredFinalIntent(submitted, now)
	if err := payments.RestorePayment(finalIntent); err != nil {
		t.Fatal(err)
	}
	callback := payment.Callback{
		ProviderID:        submitted.ProviderID,
		ProviderEventID:   "provider-reversal-response-loss",
		PaymentID:         submitted.PaymentID,
		ProviderReference: submitted.ProviderReference,
		Status:            payment.StatusReversed,
		AssetID:           submitted.SourceAssetID,
		Units:             submitted.SourceUnits,
		OccurredAt:        submitted.Submission.SubmittedAt.Add(time.Minute),
		ExpiresAt:         submitted.Submission.SubmittedAt.Add(time.Hour),
		EvidenceHash:      "provider-reversal-response-loss-evidence",
	}
	raw, err := payment.EncodeCallback(callback)
	if err != nil {
		t.Fatal(err)
	}
	signature := ed25519.Sign(privateKey, payment.SigningMessage(raw))
	receivedAt := callback.OccurredAt.Add(time.Minute)
	if _, err := payments.IngestCallback(
		callback.ProviderID,
		callback.ProviderEventID,
		raw,
		signature,
		receivedAt,
	); !errors.Is(err, payment.ErrCanonicalPending) {
		t.Fatalf("submitted reversal was not quarantined: %v", err)
	}
	pending := coordinator.PendingProviderReversals()
	if len(pending) != 1 {
		t.Fatalf("missing pending resolution fixture: %#v", pending)
	}
	request := payment.CanonicalReversalResolutionRequest{
		QuarantineID:           pending[0].QuarantineID,
		ResolutionID:           "resolution-response-loss",
		PaymentID:              submitted.PaymentID,
		AllocationID:           submitted.AllocationID,
		InstructionDigest:      submitted.InstructionDigest,
		FailureProof:           verifiedFailureFixture(t, submitted),
		ResolutionEvidenceHash: "resolution-response-loss-evidence",
		ResolvedBy:             "payment-operator",
		ResolvedAt:             receivedAt.Add(time.Minute),
	}
	if _, _, err := payments.ResolveCanonicalReversal(request); err == nil {
		t.Fatal("injected post-commit response loss was not surfaced")
	}
	retained, _ := payments.Payment(submitted.PaymentID)
	inMemoryPlan, _ := coordinator.Plan(submitted.PaymentID)
	if retained.Status != payment.StatusFinal ||
		inMemoryPlan.State != StateQuarantined ||
		len(accounting.transitions) != 1 {
		t.Fatalf(
			"response loss leaked partial in-memory publication: %#v %#v",
			retained,
			inMemoryPlan,
		)
	}
	result, _, err := payments.ResolveCanonicalReversal(request)
	if err != nil || result.Payment.Status != payment.StatusReversed ||
		len(accounting.transitions) != 1 {
		t.Fatalf("exact retry after response loss failed: %#v %v", result, err)
	}
	recovered, _ := coordinator.Plan(submitted.PaymentID)
	if recovered.State != StateFailed || !modes.IsReversed(submitted.PaymentID) {
		t.Fatalf("exact retry did not publish durable winner: %#v", recovered)
	}
}

type restartAccounting struct {
	transitions []payment.Transition
}

func (accounting *restartAccounting) Apply(
	transition payment.Transition,
) ([]string, error) {
	accounting.transitions = append(accounting.transitions, transition)
	return []string{"journal:" + transition.ProviderEventID}, nil
}

type responseLossStore struct {
	Store
	fail bool
}

func (store *responseLossStore) ResolvePendingReversal(
	expectedState State,
	expectedVersion uint64,
	next StoredCoordinator,
	resolution PendingReversalResolution,
	localFallback func() ([]string, error),
) ([]string, error) {
	journalIDs, err := store.Store.ResolvePendingReversal(
		expectedState,
		expectedVersion,
		next,
		resolution,
		localFallback,
	)
	if err != nil {
		return nil, err
	}
	if store.fail {
		store.fail = false
		return nil, errors.New("injected response loss after durable commit")
	}
	return journalIDs, nil
}

func reversalFixture(
	plan Plan,
	quarantineID string,
	providerEventID string,
	occurredAt time.Time,
) payment.CanonicalReversalRecord {
	return payment.CanonicalReversalRecord{
		QuarantineID:         quarantineID,
		IngressID:            1,
		PaymentID:            plan.PaymentID,
		ProviderID:           plan.ProviderID,
		ProviderEventID:      providerEventID,
		ReversalEventID:      plan.ProviderID + ":" + providerEventID,
		ProviderReference:    plan.ProviderReference,
		AssetID:              plan.SourceAssetID,
		Units:                plan.SourceUnits,
		RawHash:              "raw:" + providerEventID,
		SignatureHash:        "signature:" + providerEventID,
		CallbackEvidenceHash: "evidence:" + providerEventID,
		CallbackExpiresAt:    occurredAt.Add(time.Hour).UTC(),
		OccurredAt:           occurredAt.UTC(),
		ReceivedAt:           occurredAt.Add(time.Minute).UTC(),
	}
}

func verifiedFailureFixture(
	t *testing.T,
	submitted Plan,
) chainprojection.VerifiedTransactionFailure {
	return verifiedFailureFixtureFor(t, submitted, 100)
}

func verifiedFailureFixtureFor(
	t *testing.T,
	submitted Plan,
	transactionDiscriminator uint64,
) chainprojection.VerifiedTransactionFailure {
	t.Helper()
	builder := projectiontest.NewBuilder(submitted.Submission.ChainID)
	indexer, err := chainprojection.NewGateway(
		submitted.Submission.ChainID,
		submitted.Submission.Gateway,
		fixtureFinalityDepth,
		builder.PublicKey(),
	)
	if err != nil {
		t.Fatal(err)
	}
	receipt, receiptHash, transactionHash := builder.BlockWithReceipt(
		1,
		bytes32Uint(0),
		submitted.Submission.SubmittedAt.Add(time.Minute),
		transactionDiscriminator,
		false,
		nil,
	)
	if transactionHash != submitted.Submission.TransactionHash {
		t.Fatal("failure fixture transaction mismatch")
	}
	if err := indexer.IngestAuthenticated(receipt); err != nil {
		t.Fatal(err)
	}
	head, _ := builder.EmptyBlock(
		2,
		receiptHash,
		submitted.Submission.SubmittedAt.Add(2*time.Minute),
	)
	if err := indexer.IngestAuthenticated(head); err != nil {
		t.Fatal(err)
	}
	proof, err := indexer.VerifyTransactionFailure(
		chainprojection.ExpectedTransaction{
			ChainID:         submitted.Submission.ChainID,
			Gateway:         submitted.Submission.Gateway,
			TransactionHash: submitted.Submission.TransactionHash,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	return proof
}

func canonicalFromState(state State) allocationmode.CanonicalState {
	switch state {
	case StatePrepared:
		return allocationmode.CanonicalPrepared
	case StateSubmitted:
		return allocationmode.CanonicalSubmitted
	case StateConfirmed:
		return allocationmode.CanonicalConfirmed
	case StateFailed:
		return allocationmode.CanonicalFailed
	case StateQuarantined:
		return allocationmode.CanonicalQuarantined
	case StateIncident:
		return allocationmode.CanonicalIncident
	default:
		return ""
	}
}

func restoredFinalIntent(plan Plan, now time.Time) payment.Intent {
	return payment.Intent{
		PaymentID:         plan.PaymentID,
		LegalEntityID:     "entity-restart",
		IdempotencyKey:    "intent-restart",
		CorrelationID:     plan.CorrelationID,
		PayerReference:    "payer-restart",
		LoanID:            plan.LoanID,
		ProviderID:        plan.ProviderID,
		ProviderReference: plan.ProviderReference,
		Rail:              payment.RailBank,
		Purpose:           "LOAN_REPAYMENT_UNALLOCATED",
		AssetID:           plan.SourceAssetID,
		Units:             plan.SourceUnits,
		ExpiresAt:         now.Add(48 * time.Hour),
		SchemaVersion:     1,
		Status:            payment.StatusFinal,
		Version:           4,
		CreatedAt:         now,
		UpdatedAt:         now.Add(3 * time.Minute),
		ProvisionalAt:     now.Add(2 * time.Minute),
		FinalizedAt:       now.Add(3 * time.Minute),
	}
}
