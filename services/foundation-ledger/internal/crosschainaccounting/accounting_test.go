package crosschainaccounting

import (
	"errors"
	"math/big"
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

type fakeAuthority struct {
	events map[string]FinalizedAuthority
}

func (authority fakeAuthority) Authorize(intent Intent) (FinalizedAuthority, error) {
	key := intent.MessageID
	if key == "" {
		key = intent.HomeEventID
	}
	event, ok := authority.events[key]
	if !ok {
		return FinalizedAuthority{}, errors.New("unknown canonical event")
	}
	return event, nil
}

func intentFixture(effect Effect, eventID string, action uint32) (Intent, FinalizedAuthority) {
	stage := AuthorityStageSourceFinal
	switch effect {
	case CanonicalRelease, LoanActivation, RemoteRepayment, PermanentCanonicalBurn,
		LoanCancellationComplete:
		stage = AuthorityStageDestinationExecuted
	case CanonicalLockCompensation, WrappedBurnCompensation:
		stage = AuthorityStageSourceCompensated
	}
	return Intent{
			ID: "caller-selected-id", Effect: effect, MessageID: eventID, LoanID: "loan-1",
			RouteID: "route-1", AssetID: "asset:local:uft",
			WrappedAssetID: "asset:local:wuft", Units: "100",
			PartyID: "lender-1", EvidenceHash: "evidence:" + eventID,
			CorrelationID: "correlation", EffectiveAt: time.Unix(1_700_000_000, 0).UTC(),
		}, FinalizedAuthority{
			CanonicalEventID: eventID, Kind: CrossChainAuthority,
			Stage: stage, ActionOrdinal: action,
			EvidenceHash: "evidence:" + eventID, Finalized: true,
		}
}

func cancellationFixture() (Intent, FinalizedAuthority) {
	intent, authority := intentFixture(
		LoanCancellationComplete,
		"message:cancellation-complete",
		14,
	)
	completion := CancellationCompletion{
		CancellationID:            "0xcancellation",
		LoanID:                    intent.LoanID,
		FundingLockID:             "0xfunding-lock",
		DisbursementMessageID:     "0xdisbursement",
		DisbursementTombstoneHash: "0xtombstone",
		EscrowBurnResultHash:      "0xburn-result",
		HomeLoanAccount:           "0xhome-loan",
		Lender:                    "0xlender-address",
		WrappedToken:              "0xwrapped-token-address",
		Amount:                    intent.Units,
		PolicyHash:                "0xpolicy",
	}
	intent.RoutePurpose = "REPORT"
	intent.ActionFamilyHash = "0x1111111111111111111111111111111111111111111111111111111111111111"
	intent.SourceComponent = "0xsatellite-loan-component"
	intent.TypedAction = "SATELLITE_FUNDING_CANCELLED"
	intent.LenderAddress = completion.Lender
	intent.WrappedTokenAddress = completion.WrappedToken
	intent.Cancellation = completion
	authority.RouteID = intent.RouteID
	authority.RoutePurpose = intent.RoutePurpose
	authority.ActionFamilyHash = intent.ActionFamilyHash
	authority.SourceComponent = intent.SourceComponent
	authority.TypedAction = intent.TypedAction
	authority.LenderID = intent.PartyID
	authority.CanonicalAssetID = intent.AssetID
	authority.WrappedAssetID = intent.WrappedAssetID
	authority.Cancellation = completion
	return intent, authority
}

func newPoster(t *testing.T, authorities ...FinalizedAuthority) (*Poster, *ledger.Ledger) {
	t.Helper()
	events := make(map[string]FinalizedAuthority, len(authorities))
	for _, authority := range authorities {
		events[authority.CanonicalEventID] = authority
	}
	book := ledger.New()
	poster, err := NewPoster(book, fakeAuthority{events: events}, "10")
	if err != nil {
		t.Fatalf("poster: %v", err)
	}
	return poster, book
}

func TestRemoteRepaymentChangesDebtOnlyAndCanonicalReleaseDisposesBacking(t *testing.T) {
	repayment, repaymentAuthority := intentFixture(RemoteRepayment, "message:repayment", 8)
	release, releaseAuthority := intentFixture(CanonicalRelease, "message:release", 3)
	poster, _ := newPoster(t, repaymentAuthority, releaseAuthority)

	posted, err := poster.Post(repayment)
	if err != nil {
		t.Fatalf("repayment: %v", err)
	}
	if len(posted) != 1 {
		t.Fatalf("remote repayment duplicated bridge disposition: %d journals", len(posted))
	}
	for _, entry := range posted[0].Entries {
		if entry.AccountCode == AccountBridgeBackingLiability ||
			entry.AccountCode == AccountCanonicalAssetsLocked {
			t.Fatalf("repayment changed backing before canonical release: %s", entry.AccountCode)
		}
	}
	if disposition, err := poster.Post(release); err != nil || len(disposition) != 2 {
		t.Fatalf("canonical release did not atomically dispose backing: %d %v", len(disposition), err)
	}
}

func TestAuthorityRejectsWrongActionUnfinalizedAndDoubleEffect(t *testing.T) {
	intent, authority := intentFixture(CanonicalRelease, "message:action-2", 2)
	poster, _ := newPoster(t, authority)
	if _, err := poster.Post(intent); err == nil {
		t.Fatal("action 2 was allowed to post canonical release")
	}

	intent, authority = intentFixture(CanonicalRelease, "message:pre-execution", 3)
	authority.Stage = AuthorityStageSourceFinal
	poster, _ = newPoster(t, authority)
	if _, err := poster.Post(intent); err == nil {
		t.Fatal("source-final burn was allowed to release canonical backing")
	}

	intent, authority = intentFixture(WrappedBurn, "message:late-burn", 3)
	authority.Stage = AuthorityStageDestinationExecuted
	poster, _ = newPoster(t, authority)
	if _, err := poster.Post(intent); err == nil {
		t.Fatal("destination execution was substituted for source-final burn control")
	}

	intent, authority = intentFixture(LoanActivation, "message:early-activation", 7)
	authority.Stage = AuthorityStageSourceFinal
	poster, _ = newPoster(t, authority)
	if _, err := poster.Post(intent); err == nil {
		t.Fatal("source-final report activated home debt before destination execution")
	}

	intent, authority = intentFixture(WrappedBurn, "message:unfinalized", 3)
	authority.Finalized = false
	poster, _ = newPoster(t, authority)
	if _, err := poster.Post(intent); err == nil {
		t.Fatal("unfinalized chain evidence was accepted")
	}

	intent, authority = intentFixture(RemoteRepayment, "message:repayment", 8)
	poster, _ = newPoster(t, authority)
	if _, err := poster.Post(intent); err != nil {
		t.Fatalf("first effect: %v", err)
	}
	conflict := intent
	conflict.Effect = PermanentCanonicalBurn
	conflict.ID = "changed-caller-id"
	if _, err := poster.Post(conflict); err == nil {
		t.Fatal("changed caller id posted a second unauthorized effect")
	}
}

func TestDirectHomeRepaymentUsesCanonicalHomeEventAndPreservesBacking(t *testing.T) {
	intent := Intent{
		ID: "ignored", Effect: DirectHomeRepayment, HomeEventID: "home:tx:7",
		LoanID: "loan-1", RouteID: "route-1", AssetID: "asset:local:uft",
		Units: "100", PartyID: "lender-1", EvidenceHash: "home-proof",
		CorrelationID: "correlation", EffectiveAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	authority := FinalizedAuthority{
		CanonicalEventID: "home:tx:7", Kind: DirectHomeAuthority,
		Stage:        AuthorityStageDirectHomeFinal,
		EvidenceHash: "home-proof", Finalized: true,
	}
	poster, _ := newPoster(t, authority)
	posted, err := poster.Post(intent)
	if err != nil {
		t.Fatalf("post: %v", err)
	}
	if len(posted) != 1 || posted[0].SourceEventID != "home:tx:7" {
		t.Fatalf("direct repayment lacks canonical event identity: %#v", posted)
	}
	for _, entry := range posted[0].Entries {
		if entry.AccountCode == AccountBridgeBackingLiability ||
			entry.AccountCode == AccountCanonicalAssetsLocked ||
			entry.AccountCode == AccountUFTBridgeEscrowControl {
			t.Fatalf("direct repayment changed bridge backing: %s", entry.AccountCode)
		}
	}
}

func TestCompensationAndCollateralReleaseUseBoundCanonicalEffects(t *testing.T) {
	custody, custodyAuthority := intentFixture(SatelliteCustody, "message:custody", 5)
	release, releaseAuthority := intentFixture(CollateralRelease, "message:collateral-release", 10)
	lock, lockAuthority := intentFixture(CanonicalLock, "message:lock", 1)
	compensation, compensationAuthority := intentFixture(
		CanonicalLockCompensation,
		"message:compensation",
		14,
	)
	compensation.CompensatedMessageID = lock.MessageID
	compensationAuthority.CompensatedMessageID = lock.MessageID
	compensationAuthority.CompensatedActionOrdinal = 1
	poster, _ := newPoster(
		t,
		custodyAuthority,
		releaseAuthority,
		lockAuthority,
		compensationAuthority,
	)
	if _, err := poster.Post(custody); err != nil {
		t.Fatalf("custody: %v", err)
	}
	if _, err := poster.Post(release); err != nil {
		t.Fatalf("release: %v", err)
	}
	if _, err := poster.Post(lock); err != nil {
		t.Fatalf("lock: %v", err)
	}
	wrongKind := compensation
	wrongKind.Effect = WrappedBurnCompensation
	if _, err := poster.Post(wrongKind); err == nil {
		t.Fatal("canonical-lock recovery was substituted with wrapped-burn compensation")
	}
	if posted, err := poster.Post(compensation); err != nil || len(posted) != 2 {
		t.Fatalf("compensation: %d %v", len(posted), err)
	}
}

func TestRecoveredWrappedBurnRestoresSupplyWithoutBackingOrDebt(t *testing.T) {
	burn, burnAuthority := intentFixture(WrappedBurn, "message:burn", 8)
	compensation, compensationAuthority := intentFixture(
		WrappedBurnCompensation,
		"message:burn-recovery",
		14,
	)
	compensation.CompensatedMessageID = burn.MessageID
	compensationAuthority.CompensatedMessageID = burn.MessageID
	compensationAuthority.CompensatedActionOrdinal = 8
	compensation.EvidenceHash = "evidence:recovery:distinct"
	compensationAuthority.EvidenceHash = compensation.EvidenceHash

	poster, book := newPoster(t, burnAuthority, compensationAuthority)
	if _, err := poster.Post(burn); err != nil {
		t.Fatalf("burn: %v", err)
	}
	wrongOriginal := compensation
	wrongOriginal.CompensatedMessageID = "message:unrelated-burn"
	if _, err := poster.Post(wrongOriginal); err == nil {
		t.Fatal("recovery compensation accepted an unrelated original burn")
	}
	wrongKind := compensation
	wrongKind.Effect = CanonicalLockCompensation
	if _, err := poster.Post(wrongKind); err == nil {
		t.Fatal("wrapped-burn recovery was substituted with canonical-lock compensation")
	}
	first, err := poster.Post(compensation)
	if err != nil {
		t.Fatalf("compensation: %v", err)
	}
	replay := compensation
	replay.ID = "different-caller-selected-id"
	second, err := poster.Post(replay)
	if err != nil || len(first) != 1 || len(second) != 1 ||
		!first[0].PostedAt.Equal(second[0].PostedAt) {
		t.Fatalf("compensation replay was not exact and idempotent: %#v %#v %v", first, second, err)
	}

	controlBalances := map[string]*big.Int{
		AccountWrappedUFTOutstandingControl: new(big.Int),
		AccountPendingCrossChainSettlement:  new(big.Int),
	}
	posted := book.List()
	if len(posted) != 2 {
		t.Fatalf("burn recovery created unexpected economic effects: %#v", posted)
	}
	for _, journal := range posted {
		if journal.SourceEventID == compensation.MessageID &&
			journal.EvidenceHash == burn.EvidenceHash {
			t.Fatal("recovery reused the original burn evidence")
		}
		for _, entry := range journal.Entries {
			switch entry.AccountCode {
			case AccountBridgeBackingLiability,
				AccountCanonicalAssetsLocked,
				AccountUFTBridgeEscrowControl:
				t.Fatalf("recovered burn changed canonical backing: %s", entry.AccountCode)
			case AccountPrincipalReceivable, AccountLenderPrincipalClaims:
				t.Fatalf("recovered burn consumed repayment capacity: %s", entry.AccountCode)
			}
			balance := controlBalances[entry.AccountCode]
			if balance == nil {
				continue
			}
			value, _ := new(big.Int).SetString(entry.Units, 10)
			if entry.Side == ledger.Debit {
				balance.Add(balance, value)
			} else {
				balance.Sub(balance, value)
			}
		}
	}
	for account, balance := range controlBalances {
		if balance.Sign() != 0 {
			t.Fatalf("recovered burn failed to restore supply control %s=%s", account, balance)
		}
	}
}

func TestBridgeRoundTripHasZeroControlBalanceAndExactReplay(t *testing.T) {
	intents := make([]Intent, 0, 4)
	authorities := make([]FinalizedAuthority, 0, 4)
	for _, item := range []struct {
		effect Effect
		id     string
		action uint32
	}{
		{CanonicalLock, "message:lock", 1},
		{WrappedMint, "message:mint", 2},
		{WrappedBurn, "message:burn", 3},
		{CanonicalRelease, "message:release", 3},
	} {
		intent, authority := intentFixture(item.effect, item.id, item.action)
		intents = append(intents, intent)
		authorities = append(authorities, authority)
	}
	poster, book := newPoster(t, authorities...)
	for _, intent := range intents {
		if _, err := poster.Post(intent); err != nil {
			t.Fatalf("%s: %v", intent.Effect, err)
		}
	}
	first, err := poster.Post(intents[0])
	if err != nil {
		t.Fatalf("exact replay: %v", err)
	}
	replayed := intents[0]
	replayed.ID = "different-caller-id"
	second, err := poster.Post(replayed)
	if err != nil || !first[0].PostedAt.Equal(second[0].PostedAt) {
		t.Fatalf("canonical id replay changed posting: %v", err)
	}

	balances := map[string]*big.Int{}
	for _, posting := range book.List() {
		for _, entry := range posting.Entries {
			if entry.AccountCode != AccountUFTBridgeEscrowControl &&
				entry.AccountCode != AccountWrappedUFTOutstandingControl &&
				entry.AccountCode != AccountPendingCrossChainSettlement {
				continue
			}
			if balances[entry.AccountCode] == nil {
				balances[entry.AccountCode] = new(big.Int)
			}
			value, _ := new(big.Int).SetString(entry.Units, 10)
			if entry.Side == ledger.Debit {
				balances[entry.AccountCode].Add(balances[entry.AccountCode], value)
			} else {
				balances[entry.AccountCode].Sub(balances[entry.AccountCode], value)
			}
		}
	}
	for account, balance := range balances {
		if balance.Sign() != 0 {
			t.Fatalf("round trip left control balance %s=%s", account, balance)
		}
	}
}

func TestMessagingExpenseIsBounded(t *testing.T) {
	intent := Intent{
		Effect: MessagingExpense, HomeEventID: "internal:fee", RouteID: "route-1",
		AssetID: "asset:local:uft", Units: "11", EvidenceHash: "fee-proof",
		CorrelationID: "correlation", EffectiveAt: time.Unix(1_700_000_000, 0).UTC(),
	}
	authority := FinalizedAuthority{
		CanonicalEventID: "internal:fee", Kind: InternalAuthority,
		Stage:        AuthorityStageInternalFinal,
		EvidenceHash: "fee-proof", Finalized: true,
	}
	poster, _ := newPoster(t, authority)
	if _, err := poster.Post(intent); err == nil {
		t.Fatal("messaging expense over configured cap was accepted")
	}
}

func TestPostRejectsNoncanonicalUnitsBeforeAuthorityOrLedgerMutation(t *testing.T) {
	intent, authority := intentFixture(CanonicalLock, "message:noncanonical", 1)
	intent.Units = "00100"
	poster, book := newPoster(t, authority)
	if _, err := poster.Post(intent); err == nil {
		t.Fatal("noncanonical posting units were accepted")
	}
	if posted := book.List(); len(posted) != 0 {
		t.Fatalf("noncanonical posting mutated the ledger: %#v", posted)
	}
}

func TestCancellationCompletionRequiresExactTypedAction14Authority(t *testing.T) {
	intent, authority := cancellationFixture()
	poster, book := newPoster(t, authority)
	posted, err := poster.Post(intent)
	if err != nil {
		t.Fatalf("post cancellation completion: %v", err)
	}
	if len(posted) != 3 {
		t.Fatalf("cancellation completion posted %d journals, want burn plus refund pair", len(posted))
	}
	for _, item := range posted {
		if len(item.Entries) != 2 || item.Entries[0].Side != ledger.Debit ||
			item.Entries[1].Side != ledger.Credit ||
			item.Entries[0].Units != item.Entries[1].Units {
			t.Fatalf("cancellation journal is not balanced: %#v", item)
		}
	}

	replayed := intent
	replayed.ID = "caller-selected-replay-id"
	replay, err := poster.Post(replayed)
	if err != nil || len(replay) != 3 || len(book.List()) != 3 {
		t.Fatalf("cancellation replay was not exact: %#v %v", replay, err)
	}
}

func TestCancellationIntentAndGenericCompensationCannotAuthorizeRefund(t *testing.T) {
	intent, authority := cancellationFixture()
	for name, mutate := range map[string]func(*FinalizedAuthority){
		"action-12 intent": func(value *FinalizedAuthority) {
			value.ActionOrdinal = 12
			value.Stage = AuthorityStageSourceFinal
		},
		"generic compensation": func(value *FinalizedAuthority) {
			value.Stage = AuthorityStageSourceCompensated
			value.TypedAction = ""
			value.Cancellation = CancellationCompletion{}
		},
	} {
		t.Run(name, func(t *testing.T) {
			rejected := authority
			mutate(&rejected)
			poster, book := newPoster(t, rejected)
			if _, err := poster.Post(intent); err == nil {
				t.Fatal("non-completion authority posted cancellation economics")
			}
			if len(book.List()) != 0 {
				t.Fatal("rejected cancellation authority mutated the ledger")
			}
		})
	}
}

func TestCancellationCompletionBindsEveryEconomicField(t *testing.T) {
	intent, authority := cancellationFixture()
	mutations := map[string]func(*FinalizedAuthority){
		"route":         func(value *FinalizedAuthority) { value.RouteID = "route:wrong" },
		"purpose":       func(value *FinalizedAuthority) { value.RoutePurpose = "RECOVERY" },
		"family hash":   func(value *FinalizedAuthority) { value.ActionFamilyHash = "0x22" },
		"source":        func(value *FinalizedAuthority) { value.SourceComponent = "0xwrong" },
		"typed action":  func(value *FinalizedAuthority) { value.TypedAction = "SOURCE_COMPENSATED" },
		"cancellation":  func(value *FinalizedAuthority) { value.Cancellation.CancellationID = "0xwrong" },
		"loan":          func(value *FinalizedAuthority) { value.Cancellation.LoanID = "loan:wrong" },
		"amount":        func(value *FinalizedAuthority) { value.Cancellation.Amount = "99" },
		"tombstone":     func(value *FinalizedAuthority) { value.Cancellation.DisbursementTombstoneHash = "0xwrong" },
		"burn result":   func(value *FinalizedAuthority) { value.Cancellation.EscrowBurnResultHash = "0xwrong" },
		"policy":        func(value *FinalizedAuthority) { value.Cancellation.PolicyHash = "0xwrong" },
		"home loan":     func(value *FinalizedAuthority) { value.Cancellation.HomeLoanAccount = "0xwrong" },
		"wrapped token": func(value *FinalizedAuthority) { value.Cancellation.WrappedToken = "0xwrong" },
		"lender":        func(value *FinalizedAuthority) { value.Cancellation.Lender = "wrong" },
		"wrapped ID":    func(value *FinalizedAuthority) { value.WrappedAssetID = "asset:wrong" },
		"canonical ID":  func(value *FinalizedAuthority) { value.CanonicalAssetID = "asset:wrong" },
		"lender ID":     func(value *FinalizedAuthority) { value.LenderID = "party:wrong" },
		"funding lock":  func(value *FinalizedAuthority) { value.Cancellation.FundingLockID = "0xwrong" },
		"disbursement":  func(value *FinalizedAuthority) { value.Cancellation.DisbursementMessageID = "0xwrong" },
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			rejected := authority
			mutate(&rejected)
			poster, book := newPoster(t, rejected)
			if _, err := poster.Post(intent); err == nil {
				t.Fatal("mutated cancellation authority posted economics")
			}
			if len(book.List()) != 0 {
				t.Fatal("mutated cancellation authority changed the ledger")
			}
		})
	}
	for name, mutate := range map[string]func(*Intent){
		"intent lender address": func(value *Intent) { value.LenderAddress = "0xwrong" },
		"intent token address":  func(value *Intent) { value.WrappedTokenAddress = "0xwrong" },
		"intent lender ID":      func(value *Intent) { value.PartyID = "party:wrong" },
		"intent canonical ID":   func(value *Intent) { value.AssetID = "asset:wrong" },
		"intent asset ID":       func(value *Intent) { value.WrappedAssetID = "asset:wrong" },
	} {
		t.Run(name, func(t *testing.T) {
			rejected := intent
			mutate(&rejected)
			poster, book := newPoster(t, authority)
			if _, err := poster.Post(rejected); err == nil {
				t.Fatal("substituted cancellation intent posted economics")
			}
			if len(book.List()) != 0 {
				t.Fatal("substituted cancellation intent changed the ledger")
			}
		})
	}
}
