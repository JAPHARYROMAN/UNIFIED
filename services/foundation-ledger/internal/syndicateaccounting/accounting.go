package syndicateaccounting

import (
	"errors"
	"math/big"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

const (
	AccountProtocolSettlementAsset = "1220"
	AccountPrincipalReceivable     = "1310"
	AccountLenderPrincipalClaims   = "2310"
	AccountFundingCommitments      = "2320"
)

var ErrInvalidEvent = errors.New("invalid syndicate accounting event")

type Service struct {
	book *ledger.Ledger
}

type BaseEvent struct {
	EventID       string
	LoanID        string
	AssetID       string
	CorrelationID string
	EvidenceHash  string
	Finality      string
	EffectiveAt   time.Time
}

type Commitment struct {
	BaseEvent
	CommitmentID string
	LenderID     string
	Units        string
}

type Activation struct {
	BaseEvent
	BorrowerID string
	Units      string
	Positions  []PositionRight
}

type Refund struct {
	BaseEvent
	CommitmentID string
	LenderID     string
	Units        string
}

type Allocation struct {
	PositionID string
	TrancheID  string
	OwnerID    string
	Units      string
}

type PositionRight struct {
	PositionID string
	TrancheID  string
	OwnerID    string
	Units      string
}

type Distribution struct {
	BaseEvent
	PaymentID   string
	BorrowerID  string
	Units       string
	Allocations []Allocation
}

type PositionTransfer struct {
	BaseEvent
	TransferID  string
	PositionID  string
	SellerID    string
	BuyerID     string
	TrancheID   string
	ShareUnits  string
	ClaimUnits  string
	CutoffBlock uint64
}

func New(book *ledger.Ledger) *Service {
	return &Service{book: book}
}

func (service *Service) PostCommitment(event Commitment) (ledger.PostedJournal, error) {
	if !service.validBase(event.BaseEvent) || event.CommitmentID == "" ||
		event.LenderID == "" || !positiveInteger(event.Units) {
		return ledger.PostedJournal{}, ErrInvalidEvent
	}
	return service.book.Post(ledger.Journal{
		ID:             "syndicate-commitment:" + event.CommitmentID,
		LegalEntityID:  "unified-protocol",
		BookID:         "syndicate-subledger",
		SourceSystem:   "chain-indexer",
		EntryType:      "SYNDICATE_COMMITMENT_FUNDED",
		SourceEventID:  event.EventID,
		LoanID:         event.LoanID,
		IdempotencyKey: event.EventID,
		CorrelationID:  event.CorrelationID,
		EffectiveAt:    event.EffectiveAt,
		EvidenceHash:   event.EvidenceHash,
		Entries: []ledger.Entry{
			{
				AccountCode: AccountProtocolSettlementAsset,
				Side:        ledger.Debit,
				AssetID:     event.AssetID,
				Units:       event.Units,
				LoanID:      event.LoanID,
			},
			{
				AccountCode: AccountFundingCommitments,
				Side:        ledger.Credit,
				AssetID:     event.AssetID,
				Units:       event.Units,
				PartyID:     event.LenderID,
				LoanID:      event.LoanID,
			},
		},
	})
}

func (service *Service) PostActivation(event Activation) ([]ledger.PostedJournal, error) {
	if !service.validBase(event.BaseEvent) || event.BorrowerID == "" ||
		!positiveInteger(event.Units) || len(event.Positions) == 0 {
		return nil, ErrInvalidEvent
	}
	claimEntries, err := activatedClaimEntries(event)
	if err != nil {
		return nil, err
	}
	return service.book.PostBatch([]ledger.Journal{
		{
			ID:             "syndicate-disbursement:" + event.LoanID,
			LegalEntityID:  "unified-protocol",
			BookID:         "syndicate-subledger",
			SourceSystem:   "chain-indexer",
			EntryType:      "SYNDICATE_PRINCIPAL_DISBURSED",
			SourceEventID:  event.EventID,
			LoanID:         event.LoanID,
			IdempotencyKey: event.EventID + ":disbursement",
			CorrelationID:  event.CorrelationID,
			EffectiveAt:    event.EffectiveAt,
			EvidenceHash:   event.EvidenceHash,
			Entries: []ledger.Entry{
				{
					AccountCode: AccountPrincipalReceivable,
					Side:        ledger.Debit,
					AssetID:     event.AssetID,
					Units:       event.Units,
					PartyID:     event.BorrowerID,
					LoanID:      event.LoanID,
				},
				{
					AccountCode: AccountProtocolSettlementAsset,
					Side:        ledger.Credit,
					AssetID:     event.AssetID,
					Units:       event.Units,
					LoanID:      event.LoanID,
				},
			},
		},
		{
			ID:             "syndicate-rights:" + event.LoanID,
			LegalEntityID:  "unified-protocol",
			BookID:         "syndicate-subledger",
			SourceSystem:   "chain-indexer",
			EntryType:      "SYNDICATE_RIGHTS_ACTIVATED",
			SourceEventID:  event.EventID,
			LoanID:         event.LoanID,
			IdempotencyKey: event.EventID + ":rights",
			CorrelationID:  event.CorrelationID,
			EffectiveAt:    event.EffectiveAt,
			EvidenceHash:   event.EvidenceHash,
			Entries:        claimEntries,
		},
	})
}

func (service *Service) PostRefund(event Refund) (ledger.PostedJournal, error) {
	if !service.validBase(event.BaseEvent) || event.CommitmentID == "" ||
		event.LenderID == "" || !positiveInteger(event.Units) {
		return ledger.PostedJournal{}, ErrInvalidEvent
	}
	return service.book.Post(ledger.Journal{
		ID:             "syndicate-refund:" + event.CommitmentID,
		LegalEntityID:  "unified-protocol",
		BookID:         "syndicate-subledger",
		SourceSystem:   "chain-indexer",
		EntryType:      "SYNDICATE_COMMITMENT_REFUNDED",
		SourceEventID:  event.EventID,
		LoanID:         event.LoanID,
		IdempotencyKey: event.EventID,
		CorrelationID:  event.CorrelationID,
		EffectiveAt:    event.EffectiveAt,
		EvidenceHash:   event.EvidenceHash,
		Entries: []ledger.Entry{
			{
				AccountCode: AccountFundingCommitments,
				Side:        ledger.Debit,
				AssetID:     event.AssetID,
				Units:       event.Units,
				PartyID:     event.LenderID,
				LoanID:      event.LoanID,
			},
			{
				AccountCode: AccountProtocolSettlementAsset,
				Side:        ledger.Credit,
				AssetID:     event.AssetID,
				Units:       event.Units,
				LoanID:      event.LoanID,
			},
		},
	})
}

func (service *Service) PostDistribution(
	event Distribution,
) (ledger.PostedJournal, error) {
	if !service.validBase(event.BaseEvent) || event.PaymentID == "" ||
		event.BorrowerID == "" || !positiveInteger(event.Units) ||
		len(event.Allocations) == 0 {
		return ledger.PostedJournal{}, ErrInvalidEvent
	}
	expected, _ := new(big.Int).SetString(event.Units, 10)
	allocated := new(big.Int)
	entries := make([]ledger.Entry, 0, len(event.Allocations)+1)
	for _, allocation := range event.Allocations {
		units, ok := new(big.Int).SetString(allocation.Units, 10)
		if allocation.PositionID == "" || allocation.TrancheID == "" ||
			allocation.OwnerID == "" ||
			!ok || units.Sign() <= 0 {
			return ledger.PostedJournal{}, ErrInvalidEvent
		}
		allocated.Add(allocated, units)
		entries = append(entries, ledger.Entry{
			AccountCode: AccountLenderPrincipalClaims,
			Side:        ledger.Debit,
			AssetID:     event.AssetID,
			Units:       allocation.Units,
			PartyID:     allocation.OwnerID,
			LoanID:      event.LoanID,
			TrancheID:   allocation.TrancheID,
		})
	}
	if allocated.Cmp(expected) != 0 {
		return ledger.PostedJournal{}, ErrInvalidEvent
	}
	entries = append(entries, ledger.Entry{
		AccountCode: AccountPrincipalReceivable,
		Side:        ledger.Credit,
		AssetID:     event.AssetID,
		Units:       event.Units,
		PartyID:     event.BorrowerID,
		LoanID:      event.LoanID,
	})
	return service.book.Post(ledger.Journal{
		ID:             "syndicate-distribution:" + event.PaymentID,
		LegalEntityID:  "unified-protocol",
		BookID:         "syndicate-subledger",
		SourceSystem:   "chain-indexer",
		EntryType:      "SYNDICATE_PRINCIPAL_DISTRIBUTED",
		SourceEventID:  event.EventID,
		LoanID:         event.LoanID,
		IdempotencyKey: event.EventID,
		CorrelationID:  event.CorrelationID,
		EffectiveAt:    event.EffectiveAt,
		EvidenceHash:   event.EvidenceHash,
		Entries:        entries,
	})
}

func (service *Service) PostPositionTransfer(
	event PositionTransfer,
) (ledger.PostedJournal, error) {
	if !service.validBase(event.BaseEvent) || event.TransferID == "" ||
		event.PositionID == "" || event.SellerID == "" || event.BuyerID == "" ||
		event.TrancheID == "" || event.SellerID == event.BuyerID ||
		event.CutoffBlock == 0 || !positiveInteger(event.ShareUnits) ||
		!positiveInteger(event.ClaimUnits) {
		return ledger.PostedJournal{}, ErrInvalidEvent
	}
	return service.book.Post(ledger.Journal{
		ID:             "position-transfer:" + event.TransferID,
		LegalEntityID:  "unified-protocol",
		BookID:         "syndicate-subledger",
		SourceSystem:   "chain-indexer",
		EntryType:      "LENDER_POSITION_TRANSFERRED",
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
				Units:       event.ClaimUnits,
				PartyID:     event.SellerID,
				LoanID:      event.LoanID,
				TrancheID:   event.TrancheID,
			},
			{
				AccountCode: AccountLenderPrincipalClaims,
				Side:        ledger.Credit,
				AssetID:     event.AssetID,
				Units:       event.ClaimUnits,
				PartyID:     event.BuyerID,
				LoanID:      event.LoanID,
				TrancheID:   event.TrancheID,
			},
		},
	})
}

func activatedClaimEntries(event Activation) ([]ledger.Entry, error) {
	expected, _ := new(big.Int).SetString(event.Units, 10)
	allocated := new(big.Int)
	entries := []ledger.Entry{{
		AccountCode: AccountFundingCommitments,
		Side:        ledger.Debit,
		AssetID:     event.AssetID,
		Units:       event.Units,
		LoanID:      event.LoanID,
	}}
	for _, position := range event.Positions {
		units, ok := new(big.Int).SetString(position.Units, 10)
		if position.PositionID == "" || position.TrancheID == "" ||
			position.OwnerID == "" || !ok || units.Sign() <= 0 {
			return nil, ErrInvalidEvent
		}
		allocated.Add(allocated, units)
		entries = append(entries, ledger.Entry{
			AccountCode: AccountLenderPrincipalClaims,
			Side:        ledger.Credit,
			AssetID:     event.AssetID,
			Units:       position.Units,
			PartyID:     position.OwnerID,
			LoanID:      event.LoanID,
			TrancheID:   position.TrancheID,
		})
	}
	if allocated.Cmp(expected) != 0 {
		return nil, ErrInvalidEvent
	}
	return entries, nil
}

func (service *Service) validBase(event BaseEvent) bool {
	return service.book != nil && event.EventID != "" && event.LoanID != "" &&
		event.AssetID != "" && event.CorrelationID != "" && event.EvidenceHash != "" &&
		event.Finality == "FINAL" && !event.EffectiveAt.IsZero()
}

func positiveInteger(value string) bool {
	parsed, ok := new(big.Int).SetString(value, 10)
	return ok && parsed.Sign() > 0
}
