package loanaccounting

import (
	"errors"
	"math/big"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

const (
	AccountPrincipalReceivable     = "1310"
	AccountProtocolSettlementAsset = "1220"
	AccountLenderPrincipalClaims   = "2310"
	AccountOriginationFeeRevenue   = "4100"
	AccountLiquidationFeeRevenue   = "4110"
)

var ErrInvalidEvent = errors.New("invalid loan accounting event")

type Service struct {
	book *ledger.Ledger
}

type Activation struct {
	EventID             string
	LoanID              string
	BorrowerID          string
	LenderID            string
	AssetID             string
	PrincipalUnits      string
	OriginationFeeUnits string
	CorrelationID       string
	EvidenceHash        string
	Finality            string
	EffectiveAt         time.Time
}

type PrincipalRepayment struct {
	EventID       string
	PaymentID     string
	LoanID        string
	BorrowerID    string
	LenderID      string
	AssetID       string
	Units         string
	CorrelationID string
	EvidenceHash  string
	Finality      string
	EffectiveAt   time.Time
}

type LiquidationSettlement struct {
	EventID                   string
	LiquidationID             string
	LoanID                    string
	BorrowerID                string
	LenderID                  string
	AssetID                   string
	GrossProceedsUnits        string
	ExecutionCostsUnits       string
	LiquidationIncentiveUnits string
	SecuredClaimPaidUnits     string
	BorrowerSurplusUnits      string
	DebtBeforeUnits           string
	ResidualBadDebtUnits      string
	CorrelationID             string
	EvidenceHash              string
	Finality                  string
	EffectiveAt               time.Time
}

func New(book *ledger.Ledger) *Service {
	return &Service{book: book}
}

func (service *Service) PostActivation(event Activation) ([]ledger.PostedJournal, error) {
	if service.book == nil || event.EventID == "" || event.LoanID == "" ||
		event.BorrowerID == "" || event.LenderID == "" || event.AssetID == "" ||
		event.PrincipalUnits == "" || event.CorrelationID == "" ||
		event.EvidenceHash == "" || event.Finality != "FINAL" || event.EffectiveAt.IsZero() {
		return nil, ErrInvalidEvent
	}
	journals := []ledger.Journal{{
		ID:             "activation:" + event.LoanID,
		LegalEntityID:  "unified-protocol",
		BookID:         "loan-subledger",
		SourceSystem:   "chain-indexer",
		EntryType:      "LOAN_ACTIVATION",
		SourceEventID:  event.EventID,
		LoanID:         event.LoanID,
		IdempotencyKey: event.EventID + ":obligation",
		CorrelationID:  event.CorrelationID,
		EffectiveAt:    event.EffectiveAt,
		EvidenceHash:   event.EvidenceHash,
		Entries: []ledger.Entry{
			{
				AccountCode: AccountPrincipalReceivable,
				Side:        ledger.Debit,
				AssetID:     event.AssetID,
				Units:       event.PrincipalUnits,
				PartyID:     event.BorrowerID,
				LoanID:      event.LoanID,
			},
			{
				AccountCode: AccountLenderPrincipalClaims,
				Side:        ledger.Credit,
				AssetID:     event.AssetID,
				Units:       event.PrincipalUnits,
				PartyID:     event.LenderID,
				LoanID:      event.LoanID,
			},
		},
	}}
	if event.OriginationFeeUnits == "" || event.OriginationFeeUnits == "0" {
		return service.book.PostBatch(journals)
	}
	journals = append(journals, ledger.Journal{
		ID:             "origination-fee:" + event.LoanID,
		LegalEntityID:  "unified-protocol",
		BookID:         "general-ledger",
		SourceSystem:   "chain-indexer",
		EntryType:      "ORIGINATION_FEE_SETTLED",
		SourceEventID:  event.EventID,
		LoanID:         event.LoanID,
		IdempotencyKey: event.EventID + ":fee",
		CorrelationID:  event.CorrelationID,
		EffectiveAt:    event.EffectiveAt,
		EvidenceHash:   event.EvidenceHash,
		Entries: []ledger.Entry{
			{
				AccountCode: AccountProtocolSettlementAsset,
				Side:        ledger.Debit,
				AssetID:     event.AssetID,
				Units:       event.OriginationFeeUnits,
				LoanID:      event.LoanID,
			},
			{
				AccountCode: AccountOriginationFeeRevenue,
				Side:        ledger.Credit,
				AssetID:     event.AssetID,
				Units:       event.OriginationFeeUnits,
				LoanID:      event.LoanID,
			},
		},
	})
	return service.book.PostBatch(journals)
}

func (service *Service) PostPrincipalRepayment(
	event PrincipalRepayment,
) (ledger.PostedJournal, error) {
	if service.book == nil || event.EventID == "" || event.PaymentID == "" ||
		event.LoanID == "" || event.BorrowerID == "" || event.LenderID == "" ||
		event.AssetID == "" || event.Units == "" || event.CorrelationID == "" ||
		event.EvidenceHash == "" || event.Finality != "FINAL" || event.EffectiveAt.IsZero() {
		return ledger.PostedJournal{}, ErrInvalidEvent
	}
	return service.book.Post(ledger.Journal{
		ID:             "repayment:" + event.PaymentID,
		LegalEntityID:  "unified-protocol",
		BookID:         "loan-subledger",
		SourceSystem:   "chain-indexer",
		EntryType:      "PRINCIPAL_REPAID",
		SourceEventID:  event.EventID,
		LoanID:         event.LoanID,
		IdempotencyKey: event.EventID,
		CorrelationID:  event.CorrelationID,
		EffectiveAt:    event.EffectiveAt,
		EvidenceHash:   event.EvidenceHash,
		Entries: []ledger.Entry{
			{
				AccountCode: AccountLenderPrincipalClaims,
				Side:        ledger.Debit,
				AssetID:     event.AssetID,
				Units:       event.Units,
				PartyID:     event.LenderID,
				LoanID:      event.LoanID,
			},
			{
				AccountCode: AccountPrincipalReceivable,
				Side:        ledger.Credit,
				AssetID:     event.AssetID,
				Units:       event.Units,
				PartyID:     event.BorrowerID,
				LoanID:      event.LoanID,
			},
		},
	})
}

func (service *Service) PostLiquidationSettlement(
	event LiquidationSettlement,
) ([]ledger.PostedJournal, error) {
	if service.book == nil || event.EventID == "" || event.LiquidationID == "" ||
		event.LoanID == "" || event.BorrowerID == "" || event.LenderID == "" ||
		event.AssetID == "" || event.CorrelationID == "" || event.EvidenceHash == "" ||
		event.Finality != "FINAL" || event.EffectiveAt.IsZero() {
		return nil, ErrInvalidEvent
	}
	gross, ok := nonNegativeInteger(event.GrossProceedsUnits)
	if !ok || gross.Sign() == 0 {
		return nil, ErrInvalidEvent
	}
	costs, costsOK := nonNegativeInteger(event.ExecutionCostsUnits)
	incentive, incentiveOK := nonNegativeInteger(event.LiquidationIncentiveUnits)
	secured, securedOK := nonNegativeInteger(event.SecuredClaimPaidUnits)
	surplus, surplusOK := nonNegativeInteger(event.BorrowerSurplusUnits)
	debtBefore, debtBeforeOK := nonNegativeInteger(event.DebtBeforeUnits)
	badDebt, badDebtOK := nonNegativeInteger(event.ResidualBadDebtUnits)
	if !costsOK || !incentiveOK || !securedOK || !surplusOK ||
		!debtBeforeOK || !badDebtOK {
		return nil, ErrInvalidEvent
	}
	allocated := new(big.Int).Add(costs, incentive)
	allocated.Add(allocated, secured)
	allocated.Add(allocated, surplus)
	reconciledDebt := new(big.Int).Add(new(big.Int).Set(secured), badDebt)
	if gross.Cmp(allocated) != 0 || debtBefore.Cmp(reconciledDebt) != 0 {
		return nil, ErrInvalidEvent
	}

	journals := make([]ledger.Journal, 0, 2)
	if secured.Sign() != 0 {
		journals = append(journals, ledger.Journal{
			ID:             "liquidation-recovery:" + event.LiquidationID,
			LegalEntityID:  "unified-protocol",
			BookID:         "loan-subledger",
			SourceSystem:   "chain-indexer",
			EntryType:      "LIQUIDATION_PRINCIPAL_RECOVERY",
			SourceEventID:  event.EventID,
			LoanID:         event.LoanID,
			IdempotencyKey: event.EventID + ":principal",
			CorrelationID:  event.CorrelationID,
			EffectiveAt:    event.EffectiveAt,
			EvidenceHash:   event.EvidenceHash,
			Entries: []ledger.Entry{
				{
					AccountCode: AccountLenderPrincipalClaims,
					Side:        ledger.Debit,
					AssetID:     event.AssetID,
					Units:       event.SecuredClaimPaidUnits,
					PartyID:     event.LenderID,
					LoanID:      event.LoanID,
				},
				{
					AccountCode: AccountPrincipalReceivable,
					Side:        ledger.Credit,
					AssetID:     event.AssetID,
					Units:       event.SecuredClaimPaidUnits,
					PartyID:     event.BorrowerID,
					LoanID:      event.LoanID,
				},
			},
		})
	}
	if costs.Sign() != 0 {
		journals = append(journals, ledger.Journal{
			ID:             "liquidation-cost:" + event.LiquidationID,
			LegalEntityID:  "unified-protocol",
			BookID:         "general-ledger",
			SourceSystem:   "chain-indexer",
			EntryType:      "LIQUIDATION_COST_RECOVERED",
			SourceEventID:  event.EventID,
			LoanID:         event.LoanID,
			IdempotencyKey: event.EventID + ":cost",
			CorrelationID:  event.CorrelationID,
			EffectiveAt:    event.EffectiveAt,
			EvidenceHash:   event.EvidenceHash,
			Entries: []ledger.Entry{
				{
					AccountCode: AccountProtocolSettlementAsset,
					Side:        ledger.Debit,
					AssetID:     event.AssetID,
					Units:       event.ExecutionCostsUnits,
					LoanID:      event.LoanID,
				},
				{
					AccountCode: AccountLiquidationFeeRevenue,
					Side:        ledger.Credit,
					AssetID:     event.AssetID,
					Units:       event.ExecutionCostsUnits,
					LoanID:      event.LoanID,
				},
			},
		})
	}
	if len(journals) == 0 {
		return []ledger.PostedJournal{}, nil
	}
	return service.book.PostBatch(journals)
}

func nonNegativeInteger(value string) (*big.Int, bool) {
	parsed, ok := new(big.Int).SetString(value, 10)
	return parsed, ok && parsed.Sign() >= 0
}
