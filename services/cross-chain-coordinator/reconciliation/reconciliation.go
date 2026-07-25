// Package reconciliation compares chain, bridge, custody, loan, message, and
// ledger control totals without treating an operator assertion as authority.
package reconciliation

import (
	"errors"
	"fmt"
	"math/big"
	"time"
)

type Snapshot struct {
	RouteID                     string
	CanonicalEscrowUnits        string
	WrappedSupplyUnits          string
	FinalizedPendingMintUnits   string
	FinalizedPendingBurnUnits   string
	HubTokenBalanceUnits        string
	RouteObligationsUnits       string
	HubSurplusUnits             string
	RouteExposureUnits          string
	RouteExposureCapUnits       string
	AggregateExposureUnits      string
	AggregateExposureCapUnits   string
	CollateralCustodyUnits      string
	CollateralPositionUnits     string
	SettlementVaultUnits        string
	SettlementAuthorizedUnits   string
	CanonicalDebtUnits          string
	LedgerDebtUnits             string
	CanonicalLenderReleaseUnits string
	LedgerLenderReleaseUnits    string
	JournalBridgeControlUnits   string
	ChainBridgeControlUnits     string
	ChainMessageCount           uint64
	SQLMessageCount             uint64
	ChainNonce                  uint64
	SQLNonce                    uint64
	ExecutionResultCount        uint64
	AcknowledgementCount        uint64
	RecoveryRequestCount        uint64
	TombstoneCount              uint64
	CompensationCount           uint64
	RecoveredCount              uint64
	ConflictingTerminalCount    uint64
	EvidenceHash                string
	AsOf                        time.Time
}

type Difference struct {
	Dimension     string
	ExpectedUnits string
	ObservedUnits string
	ReasonCode    string
	Severity      string
	Owner         string
	DetectedAt    time.Time
	Deadline      time.Time
}

type Result struct {
	Differences  []Difference
	PauseRoute   bool
	OpenIncident bool
}

func Compare(snapshot Snapshot, owner string, deadline time.Time) (Result, error) {
	if snapshot.RouteID == "" || snapshot.EvidenceHash == "" || snapshot.AsOf.IsZero() ||
		owner == "" || !deadline.After(snapshot.AsOf) {
		return Result{}, errors.New("invalid reconciliation input")
	}
	values := make(map[string]*big.Int)
	for name, raw := range map[string]string{
		"canonical escrow":         snapshot.CanonicalEscrowUnits,
		"wrapped supply":           snapshot.WrappedSupplyUnits,
		"pending mint":             snapshot.FinalizedPendingMintUnits,
		"pending burn":             snapshot.FinalizedPendingBurnUnits,
		"hub balance":              snapshot.HubTokenBalanceUnits,
		"route obligations":        snapshot.RouteObligationsUnits,
		"hub surplus":              snapshot.HubSurplusUnits,
		"route exposure":           snapshot.RouteExposureUnits,
		"route cap":                snapshot.RouteExposureCapUnits,
		"aggregate exposure":       snapshot.AggregateExposureUnits,
		"aggregate cap":            snapshot.AggregateExposureCapUnits,
		"collateral custody":       snapshot.CollateralCustodyUnits,
		"collateral positions":     snapshot.CollateralPositionUnits,
		"settlement vault":         snapshot.SettlementVaultUnits,
		"settlement authorized":    snapshot.SettlementAuthorizedUnits,
		"canonical debt":           snapshot.CanonicalDebtUnits,
		"ledger debt":              snapshot.LedgerDebtUnits,
		"canonical lender release": snapshot.CanonicalLenderReleaseUnits,
		"ledger lender release":    snapshot.LedgerLenderReleaseUnits,
		"journal bridge control":   snapshot.JournalBridgeControlUnits,
		"chain bridge control":     snapshot.ChainBridgeControlUnits,
	} {
		value, err := units(raw)
		if err != nil {
			return Result{}, fmt.Errorf("%s: %w", name, err)
		}
		values[name] = value
	}

	var result Result
	add := func(dimension string, expected, observed *big.Int, reason, severity string) {
		if expected.Cmp(observed) == 0 {
			return
		}
		result.Differences = append(result.Differences, difference(
			dimension, expected.String(), observed.String(), reason, severity,
			owner, snapshot.AsOf, deadline,
		))
		if severity == "CRITICAL" || severity == "EXISTENTIAL" {
			result.PauseRoute = true
			result.OpenIncident = true
		}
	}
	// In the strict local model, every escrowed unit is either represented by
	// outstanding wUFT, reserved for a finalized pending mint, or awaiting home
	// release after a finalized pending burn.
	expectedEscrow := new(big.Int).Add(
		new(big.Int).Add(
			new(big.Int).Set(values["wrapped supply"]),
			values["pending mint"],
		),
		values["pending burn"],
	)
	add("BACKING", expectedEscrow, values["canonical escrow"], "BACKING_EQUATION_MISMATCH", "CRITICAL")
	expectedHubBalance := new(big.Int).Add(
		new(big.Int).Set(values["route obligations"]),
		values["hub surplus"],
	)
	add(
		"HUB_ESCROW",
		expectedHubBalance,
		values["hub balance"],
		"HUB_BALANCE_OR_QUARANTINED_SURPLUS_MISMATCH",
		"CRITICAL",
	)
	add("COLLATERAL", values["collateral positions"], values["collateral custody"], "COLLATERAL_CUSTODY_MISMATCH", "CRITICAL")
	add("SETTLEMENT_VAULT", values["settlement authorized"], values["settlement vault"], "SETTLEMENT_VAULT_MISMATCH", "CRITICAL")
	add("LOAN_DEBT", values["canonical debt"], values["ledger debt"], "LEDGER_DEBT_MISMATCH", "HIGH")
	add("LENDER_RELEASE", values["canonical lender release"], values["ledger lender release"], "LENDER_RELEASE_MISMATCH", "HIGH")
	add("BRIDGE_CONTROL", values["chain bridge control"], values["journal bridge control"], "JOURNAL_CONTROL_MISMATCH", "HIGH")
	if values["route exposure"].Cmp(values["route cap"]) > 0 {
		add("ROUTE_EXPOSURE_CAP", values["route cap"], values["route exposure"], "ROUTE_CAP_EXCEEDED", "CRITICAL")
	}
	if values["aggregate exposure"].Cmp(values["aggregate cap"]) > 0 {
		add("AGGREGATE_EXPOSURE_CAP", values["aggregate cap"], values["aggregate exposure"], "AGGREGATE_CAP_EXCEEDED", "CRITICAL")
	}
	add(
		"MESSAGE_COUNT",
		new(big.Int).SetUint64(snapshot.ChainMessageCount),
		new(big.Int).SetUint64(snapshot.SQLMessageCount),
		"MESSAGE_PROJECTION_MISMATCH",
		"HIGH",
	)
	add(
		"LANE_NONCE",
		new(big.Int).SetUint64(snapshot.ChainNonce),
		new(big.Int).SetUint64(snapshot.SQLNonce),
		"NONCE_PROJECTION_MISMATCH",
		"HIGH",
	)
	add(
		"ACKNOWLEDGEMENT",
		new(big.Int).SetUint64(snapshot.ExecutionResultCount),
		new(big.Int).SetUint64(snapshot.AcknowledgementCount),
		"EXECUTION_ACK_MISMATCH",
		"HIGH",
	)
	if snapshot.ConflictingTerminalCount > 0 {
		add(
			"TERMINAL_EXCLUSION",
			big.NewInt(0),
			new(big.Int).SetUint64(snapshot.ConflictingTerminalCount),
			"EXECUTION_TOMBSTONE_CONFLICT",
			"CRITICAL",
		)
	}
	if snapshot.RecoveryRequestCount > snapshot.ChainMessageCount {
		add(
			"RECOVERY_REQUEST_COUNT",
			new(big.Int).SetUint64(snapshot.ChainMessageCount),
			new(big.Int).SetUint64(snapshot.RecoveryRequestCount),
			"RECOVERY_REQUEST_COUNT_EXCEEDS_MESSAGES",
			"CRITICAL",
		)
	}
	addRecoveryStageDifference := func(
		dimension string,
		parent uint64,
		child uint64,
		gapReason string,
		orderReason string,
	) {
		severity := "HIGH"
		reason := gapReason
		if child > parent {
			severity = "CRITICAL"
			reason = orderReason
		}
		add(
			dimension,
			new(big.Int).SetUint64(parent),
			new(big.Int).SetUint64(child),
			reason,
			severity,
		)
	}
	addRecoveryStageDifference(
		"RECOVERY_REQUEST_TOMBSTONE",
		snapshot.RecoveryRequestCount,
		snapshot.TombstoneCount,
		"RECOVERY_TOMBSTONE_GAP",
		"TOMBSTONE_WITHOUT_RECOVERY_REQUEST",
	)
	addRecoveryStageDifference(
		"RECOVERY_TOMBSTONE_COMPENSATION",
		snapshot.TombstoneCount,
		snapshot.CompensationCount,
		"RECOVERY_COMPENSATION_GAP",
		"COMPENSATION_WITHOUT_TOMBSTONE",
	)
	addRecoveryStageDifference(
		"RECOVERY_COMPENSATION_COMPLETION",
		snapshot.CompensationCount,
		snapshot.RecoveredCount,
		"RECOVERY_COMPLETION_GAP",
		"RECOVERED_WITHOUT_COMPENSATION",
	)
	return result, nil
}

func units(value string) (*big.Int, error) {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() < 0 || number.String() != value {
		return nil, errors.New("must be a canonical nonnegative integer")
	}
	return number, nil
}

func difference(
	dimension, expected, observed, reason, severity, owner string,
	detectedAt, deadline time.Time,
) Difference {
	return Difference{
		Dimension: dimension, ExpectedUnits: expected, ObservedUnits: observed,
		ReasonCode: reason, Severity: severity, Owner: owner,
		DetectedAt: detectedAt, Deadline: deadline,
	}
}
