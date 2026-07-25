// Package crosschainaccounting converts independently authorized, finalized
// Phase 8 effects into exact, balanced, idempotent ledger batches.
package crosschainaccounting

import (
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

const (
	AccountCanonicalAssetsLocked        = "1410"
	AccountCrossChainReceivable         = "1420"
	AccountSatelliteAssetReceivable     = "1430"
	AccountBridgeBackingLiability       = "2230"
	AccountPrincipalReceivable          = "1310"
	AccountLenderPrincipalClaims        = "2310"
	AccountCrossChainMessagingExpense   = "5120"
	AccountUFTBridgeEscrowControl       = "7150"
	AccountWrappedUFTOutstandingControl = "7160"
	AccountPendingCrossChainSettlement  = "9150"
	AccountReconciliationDifference     = "9180"
)

type Effect string

const (
	CanonicalLock             Effect = "CANONICAL_LOCK"
	WrappedMint               Effect = "WRAPPED_MINT"
	WrappedBurn               Effect = "WRAPPED_BURN"
	CanonicalRelease          Effect = "CANONICAL_RELEASE"
	LoanActivation            Effect = "LOAN_ACTIVATION"
	RemoteRepayment           Effect = "REMOTE_REPAYMENT"
	DirectHomeRepayment       Effect = "DIRECT_HOME_REPAYMENT"
	SatelliteCustody          Effect = "SATELLITE_CUSTODY"
	CollateralRelease         Effect = "COLLATERAL_RELEASE"
	LoanCancellationComplete  Effect = "LOAN_CANCELLATION_COMPLETE"
	CanonicalLockCompensation Effect = "CANONICAL_LOCK_COMPENSATION"
	WrappedBurnCompensation   Effect = "WRAPPED_BURN_COMPENSATION"
	PermanentCanonicalBurn    Effect = "PERMANENT_CANONICAL_BURN"
	ReconciliationDiff        Effect = "RECONCILIATION_DIFFERENCE"
	MessagingExpense          Effect = "MESSAGING_EXPENSE"
)

// SourceCompensation is retained as a source-compatible alias for canonical
// lock compensation. New callers must choose the compensated effect explicitly.
const SourceCompensation = CanonicalLockCompensation

type AuthorityKind string

const (
	CrossChainAuthority AuthorityKind = "CROSS_CHAIN"
	DirectHomeAuthority AuthorityKind = "DIRECT_HOME"
	InternalAuthority   AuthorityKind = "INTERNAL_CONTROL"
)

type AuthorityStage string

const (
	AuthorityStageSourceFinal         AuthorityStage = "SOURCE_FINAL"
	AuthorityStageDestinationExecuted AuthorityStage = "DESTINATION_EXECUTED"
	AuthorityStageSourceCompensated   AuthorityStage = "SOURCE_COMPENSATED"
	AuthorityStageDirectHomeFinal     AuthorityStage = "DIRECT_HOME_FINAL"
	AuthorityStageInternalFinal       AuthorityStage = "INTERNAL_FINAL"
)

// FinalizedAuthority is returned by an independently authenticated chain
// projection or canonical home-ledger source. It is never constructed from
// caller-selected posting fields.
type FinalizedAuthority struct {
	CanonicalEventID         string
	Kind                     AuthorityKind
	Stage                    AuthorityStage
	ActionOrdinal            uint32
	RouteID                  string
	RoutePurpose             string
	ActionFamilyHash         string
	SourceComponent          string
	TypedAction              string
	LenderID                 string
	CanonicalAssetID         string
	WrappedAssetID           string
	Cancellation             CancellationCompletion
	EvidenceHash             string
	CompensatedMessageID     string
	CompensatedActionOrdinal uint32
	Finalized                bool
}

// Authority binds a requested effect to canonical finalized evidence.
type Authority interface {
	Authorize(Intent) (FinalizedAuthority, error)
}

// CancellationCompletion is the exact action-14 economic authority projection.
// All fields are independently projected from the authenticated typed payload.
type CancellationCompletion struct {
	CancellationID            string
	LoanID                    string
	FundingLockID             string
	DisbursementMessageID     string
	DisbursementTombstoneHash string
	EscrowBurnResultHash      string
	HomeLoanAccount           string
	Lender                    string
	WrappedToken              string
	Amount                    string
	PolicyHash                string
}

type Intent struct {
	// ID is descriptive only. It is deliberately excluded from idempotency.
	ID                   string
	Effect               Effect
	MessageID            string
	HomeEventID          string
	LoanID               string
	RouteID              string
	AssetID              string
	WrappedAssetID       string
	WrappedTokenAddress  string
	CompensatedMessageID string
	Units                string
	PartyID              string
	LenderAddress        string
	RoutePurpose         string
	ActionFamilyHash     string
	SourceComponent      string
	TypedAction          string
	Cancellation         CancellationCompletion
	EvidenceHash         string
	CorrelationID        string
	EffectiveAt          time.Time
}

type Poster struct {
	book                *ledger.Ledger
	authority           Authority
	maxMessagingExpense *big.Int
}

func NewPoster(
	book *ledger.Ledger,
	authority Authority,
	maxMessagingExpenseUnits string,
) (*Poster, error) {
	if book == nil || authority == nil {
		return nil, errors.New("ledger and finalized authority are required")
	}
	capUnits, ok := new(big.Int).SetString(maxMessagingExpenseUnits, 10)
	if !ok || capUnits.Sign() <= 0 {
		return nil, errors.New("positive messaging expense cap is required")
	}
	return &Poster{book: book, authority: authority, maxMessagingExpense: capUnits}, nil
}

func (poster *Poster) Post(intent Intent) ([]ledger.PostedJournal, error) {
	if intent.RouteID == "" || intent.AssetID == "" || intent.Units == "" ||
		intent.EvidenceHash == "" || intent.CorrelationID == "" ||
		intent.EffectiveAt.IsZero() {
		return nil, errors.New("invalid cross-chain posting intent")
	}
	if (intent.Effect == WrappedMint || intent.Effect == WrappedBurn ||
		intent.Effect == WrappedBurnCompensation ||
		intent.Effect == LoanCancellationComplete) &&
		intent.WrappedAssetID == "" {
		return nil, errors.New("wrapped asset identity is required")
	}
	units, ok := new(big.Int).SetString(intent.Units, 10)
	if !ok || units.Sign() <= 0 || units.String() != intent.Units {
		return nil, errors.New("posting units must be a canonical positive integer")
	}
	if intent.Effect == MessagingExpense && units.Cmp(poster.maxMessagingExpense) > 0 {
		return nil, errors.New("cross-chain messaging expense exceeds configured cap")
	}

	authority, err := poster.authority.Authorize(intent)
	if err != nil {
		return nil, fmt.Errorf("authorize canonical effect: %w", err)
	}
	if err := validateAuthority(intent, authority); err != nil {
		return nil, err
	}
	journals, err := journals(intent, authority.CanonicalEventID)
	if err != nil {
		return nil, err
	}
	return poster.book.PostBatch(journals)
}

func validateAuthority(intent Intent, authority FinalizedAuthority) error {
	if !authority.Finalized || authority.CanonicalEventID == "" ||
		authority.EvidenceHash == "" || authority.EvidenceHash != intent.EvidenceHash {
		return errors.New("effect lacks matching finalized canonical evidence")
	}
	switch authority.Kind {
	case CrossChainAuthority:
		if intent.MessageID == "" || intent.HomeEventID != "" ||
			authority.CanonicalEventID != intent.MessageID ||
			!authorityAllowsEffect(
				authority.Stage,
				authority.ActionOrdinal,
				intent.Effect,
			) {
			return errors.New("cross-chain action does not authorize requested effect")
		}
		if isCompensation(intent.Effect) &&
			(intent.CompensatedMessageID == "" ||
				authority.CompensatedMessageID != intent.CompensatedMessageID ||
				intent.CompensatedMessageID == intent.MessageID ||
				!compensatedActionAllowsEffect(
					authority.CompensatedActionOrdinal,
					intent.Effect,
				)) {
			return errors.New("compensation lacks exact original-message binding")
		}
		if intent.Effect == LoanCancellationComplete &&
			!validCancellationAuthority(intent, authority) {
			return errors.New(
				"loan cancellation lacks exact authenticated action-14 completion authority",
			)
		}
	case DirectHomeAuthority:
		if intent.Effect != DirectHomeRepayment || intent.MessageID != "" ||
			intent.HomeEventID == "" || authority.CanonicalEventID != intent.HomeEventID ||
			authority.ActionOrdinal != 0 ||
			authority.Stage != AuthorityStageDirectHomeFinal {
			return errors.New("direct-home effect lacks canonical home event identity")
		}
	case InternalAuthority:
		if intent.MessageID != "" || intent.HomeEventID == "" ||
			authority.CanonicalEventID != intent.HomeEventID ||
			authority.Stage != AuthorityStageInternalFinal ||
			(intent.Effect != ReconciliationDiff && intent.Effect != MessagingExpense) {
			return errors.New("internal control authority cannot post requested effect")
		}
	default:
		return errors.New("unknown accounting authority kind")
	}
	return nil
}

func authorityAllowsEffect(
	stage AuthorityStage,
	action uint32,
	effect Effect,
) bool {
	switch effect {
	case CanonicalLock:
		return stage == AuthorityStageSourceFinal && action == 1
	case WrappedMint:
		return stage == AuthorityStageSourceFinal && action == 2
	case WrappedBurn:
		return stage == AuthorityStageSourceFinal &&
			(action == 3 || action == 8 || action == 15)
	case CanonicalRelease:
		return stage == AuthorityStageDestinationExecuted &&
			(action == 3 || action == 8)
	case SatelliteCustody:
		return stage == AuthorityStageSourceFinal && action == 5
	case LoanActivation:
		return stage == AuthorityStageDestinationExecuted && action == 7
	case RemoteRepayment:
		return stage == AuthorityStageDestinationExecuted && action == 8
	case CollateralRelease:
		return stage == AuthorityStageSourceFinal && action == 10
	case LoanCancellationComplete:
		return stage == AuthorityStageDestinationExecuted && action == 14
	case CanonicalLockCompensation, WrappedBurnCompensation:
		return stage == AuthorityStageSourceCompensated && action == 14
	case PermanentCanonicalBurn:
		return stage == AuthorityStageDestinationExecuted && action == 15
	default:
		return false
	}
}

func validCancellationAuthority(intent Intent, authority FinalizedAuthority) bool {
	completion := intent.Cancellation
	return authority.RouteID == intent.RouteID &&
		authority.RoutePurpose == "REPORT" &&
		intent.RoutePurpose == authority.RoutePurpose &&
		authority.ActionFamilyHash != "" &&
		intent.ActionFamilyHash == authority.ActionFamilyHash &&
		authority.SourceComponent != "" &&
		intent.SourceComponent == authority.SourceComponent &&
		authority.TypedAction == "SATELLITE_FUNDING_CANCELLED" &&
		intent.TypedAction == authority.TypedAction &&
		authority.LenderID == intent.PartyID &&
		authority.CanonicalAssetID == intent.AssetID &&
		authority.WrappedAssetID == intent.WrappedAssetID &&
		authority.Cancellation == completion &&
		completion.CancellationID != "" &&
		completion.LoanID == intent.LoanID &&
		completion.FundingLockID != "" &&
		completion.DisbursementMessageID != "" &&
		completion.DisbursementTombstoneHash != "" &&
		completion.EscrowBurnResultHash != "" &&
		completion.HomeLoanAccount != "" &&
		completion.Lender == intent.LenderAddress &&
		completion.WrappedToken == intent.WrappedTokenAddress &&
		completion.Amount == intent.Units &&
		completion.PolicyHash != ""
}

func isCompensation(effect Effect) bool {
	return effect == CanonicalLockCompensation || effect == WrappedBurnCompensation
}

func compensatedActionAllowsEffect(action uint32, effect Effect) bool {
	switch effect {
	case CanonicalLockCompensation:
		return action == 1
	case WrappedBurnCompensation:
		return action == 3 || action == 8 || action == 15
	default:
		return false
	}
}

func journals(intent Intent, canonicalEventID string) ([]ledger.Journal, error) {
	switch intent.Effect {
	case CanonicalLock:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "bridge-lock-financial", intent.AssetID,
				AccountCanonicalAssetsLocked, AccountBridgeBackingLiability),
			journal(intent, canonicalEventID, "bridge-lock-control", intent.AssetID,
				AccountUFTBridgeEscrowControl, AccountPendingCrossChainSettlement),
		}, nil
	case WrappedMint:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "wrapped-mint-control", intent.WrappedAssetID,
				AccountPendingCrossChainSettlement, AccountWrappedUFTOutstandingControl),
		}, nil
	case WrappedBurn:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "wrapped-burn-control", intent.WrappedAssetID,
				AccountWrappedUFTOutstandingControl, AccountPendingCrossChainSettlement),
		}, nil
	case CanonicalRelease, PermanentCanonicalBurn, CanonicalLockCompensation:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "bridge-disposition-financial", intent.AssetID,
				AccountBridgeBackingLiability, AccountCanonicalAssetsLocked),
			journal(intent, canonicalEventID, "bridge-disposition-control", intent.AssetID,
				AccountPendingCrossChainSettlement, AccountUFTBridgeEscrowControl),
		}, nil
	case WrappedBurnCompensation:
		// A recovered wrapped burn restores the satellite supply/control
		// position. Canonical backing and loan debt remain untouched because no
		// canonical release/permanent burn or repayment result completed.
		return []ledger.Journal{
			journal(intent, canonicalEventID, "wrapped-burn-compensation-control",
				intent.WrappedAssetID, AccountPendingCrossChainSettlement,
				AccountWrappedUFTOutstandingControl),
		}, nil
	case LoanActivation:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "loan-activation", intent.AssetID,
				AccountPrincipalReceivable, AccountLenderPrincipalClaims),
		}, nil
	case RemoteRepayment, DirectHomeRepayment:
		// Bridge backing is disposed only by a distinct canonical-release or
		// permanent-burn event. Repayment itself changes debt exactly once.
		return []ledger.Journal{
			journal(intent, canonicalEventID, "repayment-debt", intent.AssetID,
				AccountLenderPrincipalClaims, AccountPrincipalReceivable),
		}, nil
	case SatelliteCustody:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "satellite-custody", intent.AssetID,
				AccountSatelliteAssetReceivable, AccountCrossChainReceivable),
		}, nil
	case CollateralRelease:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "satellite-custody-release", intent.AssetID,
				AccountCrossChainReceivable, AccountSatelliteAssetReceivable),
		}, nil
	case LoanCancellationComplete:
		// The authenticated action-14 report binds the satellite escrow burn
		// and the resulting canonical refund. A generic recovery compensation
		// cannot reach this branch.
		return []ledger.Journal{
			journal(intent, canonicalEventID, "loan-cancellation-burn-control",
				intent.WrappedAssetID, AccountWrappedUFTOutstandingControl,
				AccountPendingCrossChainSettlement),
			journal(intent, canonicalEventID, "loan-cancellation-refund-financial",
				intent.AssetID, AccountBridgeBackingLiability,
				AccountCanonicalAssetsLocked),
			journal(intent, canonicalEventID, "loan-cancellation-refund-control",
				intent.AssetID, AccountPendingCrossChainSettlement,
				AccountUFTBridgeEscrowControl),
		}, nil
	case ReconciliationDiff:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "reconciliation-difference", intent.AssetID,
				AccountReconciliationDifference, AccountPendingCrossChainSettlement),
		}, nil
	case MessagingExpense:
		return []ledger.Journal{
			journal(intent, canonicalEventID, "messaging-expense", intent.AssetID,
				AccountCrossChainMessagingExpense, AccountPendingCrossChainSettlement),
		}, nil
	default:
		return nil, fmt.Errorf("unsupported cross-chain effect %q", intent.Effect)
	}
}

func journal(
	intent Intent,
	canonicalEventID string,
	suffix string,
	assetID string,
	debit string,
	credit string,
) ledger.Journal {
	id := "crosschain:" + canonicalEventID + ":" + string(intent.Effect) + ":" + suffix
	return ledger.Journal{
		ID:             id,
		LegalEntityID:  "unified-protocol",
		BookID:         "cross-chain-subledger",
		SourceSystem:   "cross-chain-coordinator",
		EntryType:      string(intent.Effect),
		SourceEventID:  canonicalEventID,
		LoanID:         intent.LoanID,
		IdempotencyKey: id,
		CorrelationID:  intent.CorrelationID,
		EffectiveAt:    intent.EffectiveAt,
		Entries: []ledger.Entry{
			{
				AccountCode: debit, Side: ledger.Debit, AssetID: assetID,
				Units: intent.Units, PartyID: intent.PartyID, LoanID: intent.LoanID,
			},
			{
				AccountCode: credit, Side: ledger.Credit, AssetID: assetID,
				Units: intent.Units, PartyID: intent.PartyID, LoanID: intent.LoanID,
			},
		},
		EvidenceHash: authorityEvidence(intent),
	}
}

func authorityEvidence(intent Intent) string {
	return intent.EvidenceHash
}
