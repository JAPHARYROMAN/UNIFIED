package projection

import (
	"errors"
	"fmt"
	"math/big"
	"sort"
)

var (
	ErrInvalidBlock   = errors.New("invalid block")
	ErrUnknownParent  = errors.New("canonical parent is unknown")
	ErrDuplicateEvent = errors.New("event identity is already canonical")
	ErrInvalidEvent   = errors.New("invalid canonical event")
	maxUint256        = new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), 256), big.NewInt(1))
)

type Finality string

const (
	Provisional Finality = "PROVISIONAL"
	Final       Finality = "FINAL"
)

type EventType string

const (
	TenderPublished EventType = "TenderPublished"
	OfferSelected   EventType = "OfferSelected"
	LoanActivated   EventType = "LoanActivated"
	PrincipalRepaid EventType = "PrincipalRepaid"
	LoanClosed      EventType = "LoanClosed"
)

type Event struct {
	ID          string
	Type        EventType
	TxHash      string
	LogIndex    uint32
	TenderID    string
	OfferID     string
	LoanID      string
	BorrowerID  string
	LenderID    string
	AssetID     string
	AmountUnits string
	PaymentID   string
}

type Block struct {
	Number     uint64
	Hash       string
	ParentHash string
	Events     []Event
}

type Tender struct {
	ID              string
	BorrowerID      string
	State           string
	SelectedOfferID string
	UpdatedInBlock  uint64
	Finality        Finality
}

type Loan struct {
	ID               string
	BorrowerID       string
	LenderID         string
	AssetID          string
	PrincipalUnits   string
	OutstandingUnits string
	Status           string
	LastPaymentID    string
	UpdatedInBlock   uint64
	Finality         Finality
}

type Snapshot struct {
	HeadHash string
	Head     uint64
	Tenders  map[string]Tender
	Loans    map[string]Loan
	Payments map[string]string
}

type Indexer struct {
	finalityDepth uint64
	blocks        map[uint64]Block
	eventBlocks   map[string]uint64
	snapshot      Snapshot
}

func New(finalityDepth uint64) *Indexer {
	return &Indexer{
		finalityDepth: finalityDepth,
		blocks:        make(map[uint64]Block),
		eventBlocks:   make(map[string]uint64),
		snapshot: Snapshot{
			Tenders:  make(map[string]Tender),
			Loans:    make(map[string]Loan),
			Payments: make(map[string]string),
		},
	}
}

func (indexer *Indexer) Ingest(block Block) error {
	if block.Number == 0 || block.Hash == "" {
		return ErrInvalidBlock
	}
	if existing, ok := indexer.blocks[block.Number]; ok && existing.Hash == block.Hash {
		return nil
	}
	if block.Number > 1 {
		parent, ok := indexer.blocks[block.Number-1]
		if !ok || parent.Hash != block.ParentHash {
			return ErrUnknownParent
		}
	}
	blocks := make(map[uint64]Block, len(indexer.blocks)+1)
	for height, canonical := range indexer.blocks {
		blocks[height] = copyBlock(canonical)
	}
	eventBlocks := make(map[string]uint64, len(indexer.eventBlocks)+len(block.Events))
	for eventID, height := range indexer.eventBlocks {
		eventBlocks[eventID] = height
	}
	for height := block.Number; height <= indexer.snapshot.Head; height++ {
		if removed, ok := blocks[height]; ok {
			for _, event := range removed.Events {
				delete(eventBlocks, event.ID)
			}
			delete(blocks, height)
		}
	}
	for _, event := range block.Events {
		if event.ID == "" || event.TxHash == "" {
			return ErrInvalidEvent
		}
		if existingHeight, exists := eventBlocks[event.ID]; exists {
			return fmt.Errorf("%w: %s at block %d", ErrDuplicateEvent, event.ID, existingHeight)
		}
		eventBlocks[event.ID] = block.Number
	}
	blocks[block.Number] = copyBlock(block)
	candidate := &Indexer{
		finalityDepth: indexer.finalityDepth,
		blocks:        blocks,
		eventBlocks:   eventBlocks,
	}
	if err := candidate.Rebuild(); err != nil {
		return err
	}
	indexer.blocks = candidate.blocks
	indexer.eventBlocks = candidate.eventBlocks
	indexer.snapshot = candidate.snapshot
	return nil
}

func (indexer *Indexer) Rebuild() error {
	snapshot := Snapshot{
		Tenders:  make(map[string]Tender),
		Loans:    make(map[string]Loan),
		Payments: make(map[string]string),
	}
	heights := make([]uint64, 0, len(indexer.blocks))
	for height := range indexer.blocks {
		heights = append(heights, height)
	}
	sort.Slice(heights, func(left, right int) bool { return heights[left] < heights[right] })
	for _, height := range heights {
		block := indexer.blocks[height]
		for _, event := range block.Events {
			if err := apply(&snapshot, event, height); err != nil {
				return err
			}
		}
		snapshot.Head = height
		snapshot.HeadHash = block.Hash
	}
	finalHeight := uint64(0)
	if snapshot.Head > indexer.finalityDepth {
		finalHeight = snapshot.Head - indexer.finalityDepth
	}
	for id, tender := range snapshot.Tenders {
		tender.Finality = Provisional
		if tender.UpdatedInBlock <= finalHeight {
			tender.Finality = Final
		}
		snapshot.Tenders[id] = tender
	}
	for id, loan := range snapshot.Loans {
		loan.Finality = Provisional
		if loan.UpdatedInBlock <= finalHeight {
			loan.Finality = Final
		}
		snapshot.Loans[id] = loan
	}
	indexer.snapshot = snapshot
	return nil
}

func (indexer *Indexer) Snapshot() Snapshot {
	result := indexer.snapshot
	result.Tenders = make(map[string]Tender, len(indexer.snapshot.Tenders))
	result.Loans = make(map[string]Loan, len(indexer.snapshot.Loans))
	result.Payments = make(map[string]string, len(indexer.snapshot.Payments))
	for id, tender := range indexer.snapshot.Tenders {
		result.Tenders[id] = tender
	}
	for id, loan := range indexer.snapshot.Loans {
		result.Loans[id] = loan
	}
	for id, loanID := range indexer.snapshot.Payments {
		result.Payments[id] = loanID
	}
	return result
}

func apply(snapshot *Snapshot, event Event, blockNumber uint64) error {
	switch event.Type {
	case TenderPublished:
		if event.TenderID == "" || event.BorrowerID == "" {
			return ErrInvalidEvent
		}
		snapshot.Tenders[event.TenderID] = Tender{
			ID:             event.TenderID,
			BorrowerID:     event.BorrowerID,
			State:          "OPEN",
			UpdatedInBlock: blockNumber,
		}
	case OfferSelected:
		tender, ok := snapshot.Tenders[event.TenderID]
		if !ok || event.OfferID == "" {
			return ErrInvalidEvent
		}
		tender.State = "OFFER_SELECTED"
		tender.SelectedOfferID = event.OfferID
		tender.UpdatedInBlock = blockNumber
		snapshot.Tenders[event.TenderID] = tender
	case LoanActivated:
		if event.LoanID == "" || event.BorrowerID == "" || event.LenderID == "" ||
			event.AssetID == "" {
			return ErrInvalidEvent
		}
		if _, ok := parseUnits(event.AmountUnits); !ok {
			return ErrInvalidEvent
		}
		if _, exists := snapshot.Loans[event.LoanID]; exists {
			return ErrInvalidEvent
		}
		snapshot.Loans[event.LoanID] = Loan{
			ID:               event.LoanID,
			BorrowerID:       event.BorrowerID,
			LenderID:         event.LenderID,
			AssetID:          event.AssetID,
			PrincipalUnits:   event.AmountUnits,
			OutstandingUnits: event.AmountUnits,
			Status:           "ACTIVE",
			UpdatedInBlock:   blockNumber,
		}
	case PrincipalRepaid:
		loan, ok := snapshot.Loans[event.LoanID]
		amount, amountOK := parseUnits(event.AmountUnits)
		outstanding, outstandingOK := parseUnits(loan.OutstandingUnits)
		if !ok || loan.Status != "ACTIVE" || event.PaymentID == "" ||
			!amountOK || !outstandingOK || amount.Cmp(outstanding) > 0 {
			return ErrInvalidEvent
		}
		if _, exists := snapshot.Payments[event.PaymentID]; exists {
			return ErrInvalidEvent
		}
		loan.OutstandingUnits = new(big.Int).Sub(outstanding, amount).String()
		loan.LastPaymentID = event.PaymentID
		loan.UpdatedInBlock = blockNumber
		snapshot.Loans[event.LoanID] = loan
		snapshot.Payments[event.PaymentID] = event.LoanID
	case LoanClosed:
		loan, ok := snapshot.Loans[event.LoanID]
		if !ok || loan.OutstandingUnits != "0" {
			return ErrInvalidEvent
		}
		loan.Status = "CLOSED"
		loan.UpdatedInBlock = blockNumber
		snapshot.Loans[event.LoanID] = loan
	default:
		return ErrInvalidEvent
	}
	return nil
}

func copyBlock(block Block) Block {
	block.Events = append([]Event(nil), block.Events...)
	return block
}

func parseUnits(value string) (*big.Int, bool) {
	units, ok := new(big.Int).SetString(value, 10)
	return units, ok && units.Sign() > 0 && units.Cmp(maxUint256) <= 0 && units.String() == value
}
