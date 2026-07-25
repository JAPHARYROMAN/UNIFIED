package reconciliation

import (
	"testing"
	"time"
)

func balancedSnapshot() Snapshot {
	return Snapshot{
		RouteID:              "route-local",
		CanonicalEscrowUnits: "100", WrappedSupplyUnits: "70",
		FinalizedPendingMintUnits: "20", FinalizedPendingBurnUnits: "10",
		HubTokenBalanceUnits: "100", RouteObligationsUnits: "100",
		HubSurplusUnits:    "0",
		RouteExposureUnits: "100", RouteExposureCapUnits: "100",
		AggregateExposureUnits: "100", AggregateExposureCapUnits: "150",
		CollateralCustodyUnits: "50", CollateralPositionUnits: "50",
		SettlementVaultUnits: "0", SettlementAuthorizedUnits: "0",
		CanonicalDebtUnits: "40", LedgerDebtUnits: "40",
		CanonicalLenderReleaseUnits: "60", LedgerLenderReleaseUnits: "60",
		JournalBridgeControlUnits: "100", ChainBridgeControlUnits: "100",
		ChainMessageCount: 4, SQLMessageCount: 4, ChainNonce: 4, SQLNonce: 4,
		ExecutionResultCount: 3, AcknowledgementCount: 3,
		RecoveryRequestCount: 1, TombstoneCount: 1,
		CompensationCount: 1, RecoveredCount: 1,
		ConflictingTerminalCount: 0,
		EvidenceHash:             "evidence", AsOf: time.Unix(1_700_000_000, 0).UTC(),
	}
}

func TestCompareFindsEveryCriticalControlClass(t *testing.T) {
	snapshot := balancedSnapshot()
	snapshot.CanonicalEscrowUnits = "99"
	snapshot.HubTokenBalanceUnits = "98"
	snapshot.CollateralCustodyUnits = "49"
	snapshot.SettlementVaultUnits = "1"
	snapshot.RouteExposureUnits = "101"
	snapshot.ConflictingTerminalCount = 1
	result, err := Compare(snapshot, "accounting-risk", snapshot.AsOf.Add(time.Hour))
	if err != nil {
		t.Fatalf("compare: %v", err)
	}
	if len(result.Differences) != 6 || !result.PauseRoute || !result.OpenIncident {
		t.Fatalf("critical differences did not request pause/incident: %#v", result)
	}
	for _, difference := range result.Differences {
		if difference.Owner == "" || !difference.Deadline.After(difference.DetectedAt) {
			t.Fatalf("difference is not owned and deadline-bound: %#v", difference)
		}
	}
}

func TestCompareRejectsHiddenExcessBackingAndWrongPendingSigns(t *testing.T) {
	snapshot := balancedSnapshot()
	snapshot.CanonicalEscrowUnits = "101"
	result, err := Compare(snapshot, "accounting-risk", snapshot.AsOf.Add(time.Hour))
	if err != nil {
		t.Fatalf("compare: %v", err)
	}
	if len(result.Differences) != 1 ||
		result.Differences[0].ReasonCode != "BACKING_EQUATION_MISMATCH" {
		t.Fatalf("hidden excess backing was accepted: %#v", result)
	}
}

func TestCompareAcceptsExactFullSnapshot(t *testing.T) {
	snapshot := balancedSnapshot()
	result, err := Compare(snapshot, "accounting-risk", snapshot.AsOf.Add(time.Hour))
	if err != nil || len(result.Differences) != 0 || result.PauseRoute {
		t.Fatalf("expected exact match, result=%#v err=%v", result, err)
	}
}

func TestCompareAcceptsQuarantinedHubSurplusButRejectsUnclassifiedBalance(t *testing.T) {
	snapshot := balancedSnapshot()
	snapshot.HubTokenBalanceUnits = "125"
	snapshot.HubSurplusUnits = "25"
	result, err := Compare(snapshot, "accounting-risk", snapshot.AsOf.Add(time.Hour))
	if err != nil || len(result.Differences) != 0 {
		t.Fatalf("quarantined unsolicited surplus caused a false mismatch: %#v %v", result, err)
	}

	snapshot.HubSurplusUnits = "0"
	result, err = Compare(snapshot, "accounting-risk", snapshot.AsOf.Add(time.Hour))
	if err != nil || len(result.Differences) != 1 ||
		result.Differences[0].ReasonCode !=
			"HUB_BALANCE_OR_QUARANTINED_SURPLUS_MISMATCH" {
		t.Fatalf("unclassified hub balance was hidden: %#v %v", result, err)
	}
}

func TestCompareKeepsRecoveryGapsAndOrderingViolationsVisible(t *testing.T) {
	snapshot := balancedSnapshot()
	snapshot.CompensationCount = 0
	snapshot.RecoveredCount = 0
	result, err := Compare(snapshot, "accounting-risk", snapshot.AsOf.Add(time.Hour))
	if err != nil || len(result.Differences) != 1 ||
		result.Differences[0].Dimension != "RECOVERY_TOMBSTONE_COMPENSATION" ||
		result.Differences[0].ReasonCode != "RECOVERY_COMPENSATION_GAP" {
		t.Fatalf("recovery compensation gap disappeared: %#v %v", result, err)
	}

	snapshot = balancedSnapshot()
	snapshot.RecoveredCount = 2
	result, err = Compare(snapshot, "accounting-risk", snapshot.AsOf.Add(time.Hour))
	if err != nil || len(result.Differences) != 1 ||
		result.Differences[0].ReasonCode != "RECOVERED_WITHOUT_COMPENSATION" ||
		!result.PauseRoute || !result.OpenIncident {
		t.Fatalf("recovery ordering violation was not critical: %#v %v", result, err)
	}
}
