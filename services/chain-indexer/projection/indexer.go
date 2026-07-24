package projection

import (
	"crypto/ed25519"
	"errors"
	"fmt"
	"math/big"
	"sort"
	"time"
)

var (
	ErrInvalidBlock              = errors.New("invalid block")
	ErrUnknownParent             = errors.New("canonical parent is unknown")
	ErrDuplicateEvent            = errors.New("event identity is already canonical")
	ErrInvalidEvent              = errors.New("invalid canonical event")
	ErrInvalidIndexerConfig      = errors.New("invalid indexer configuration")
	ErrInvalidTransactionFailure = errors.New("invalid transaction failure observation")
	ErrUnauthenticatedBlock      = errors.New("gateway indexer requires authenticated block evidence")
	maxUint256                   = new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), 256), big.NewInt(1))
)

type Finality string

const (
	Provisional Finality = "PROVISIONAL"
	Final       Finality = "FINAL"
)

type EventType string

const (
	TenderPublished             EventType = "TenderPublished"
	OfferSelected               EventType = "OfferSelected"
	LoanActivated               EventType = "LoanActivated"
	PrincipalRepaid             EventType = "PrincipalRepaid"
	LoanClosed                  EventType = "LoanClosed"
	CanonicalSettlementExecuted EventType = "CanonicalSettlementExecuted"
)

type Event struct {
	ID                         string
	Type                       EventType
	TxHash                     string
	LogIndex                   uint32
	BlockNumber                uint64
	BlockHash                  string
	ChainID                    uint64
	TenderID                   string
	OfferID                    string
	LoanID                     string
	BorrowerID                 string
	LenderID                   string
	AssetID                    string
	AmountUnits                string
	PaymentID                  string
	AllocationID               string
	InstructionDigest          string
	PolicySetHash              string
	LoanAccount                string
	Finalizer                  string
	Attester                   string
	SourceAssetID              string
	TargetToken                string
	SourceUnits                string
	GrossUnits                 string
	ProviderIDHash             string
	ProviderReferenceHash      string
	ReconciliationID           string
	ReconciliationCommitment   string
	OriginalJournalSetHash     string
	ConversionPolicyHash       string
	FinalityPolicyHash         string
	EvidenceHash               string
	JournalRef                 string
	ProviderFinalizedAt        uint64
	ReversalDeadline           uint64
	PrincipalUnits             string
	RefundableExcessUnits      string
	DebtBeforeUnits            string
	DebtAfterUnits             string
	StateNonceBefore           uint64
	StateNonceAfter            uint64
	Gateway                    string
	RawEvidenceHash            string
	TransactionIndex           uint64
	ReceiptsRoot               string
	InclusionProofHash         string
	ReceiptHeaderSignatureHash string
	decodedCanonical           bool
}

type Block struct {
	Number              uint64
	Hash                string
	ParentHash          string
	ObservedAt          time.Time
	Events              []Event
	HeaderSignatureHash string
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

type CanonicalSettlement struct {
	PaymentID                  string
	AllocationID               string
	InstructionDigest          string
	PolicySetHash              string
	LoanID                     string
	LoanAccount                string
	Finalizer                  string
	Attester                   string
	SourceAssetID              string
	TargetAssetID              string
	TargetToken                string
	SourceUnits                string
	GrossUnits                 string
	ProviderIDHash             string
	ProviderReferenceHash      string
	ReconciliationID           string
	ReconciliationCommitment   string
	OriginalJournalSetHash     string
	ConversionPolicyHash       string
	FinalityPolicyHash         string
	EvidenceHash               string
	JournalRef                 string
	ProviderFinalizedAt        uint64
	ReversalDeadline           uint64
	PrincipalUnits             string
	RefundableExcessUnits      string
	DebtBeforeUnits            string
	DebtAfterUnits             string
	StateNonceBefore           uint64
	StateNonceAfter            uint64
	LenderID                   string
	BorrowerID                 string
	ChainID                    uint64
	Gateway                    string
	TransactionHash            string
	EventID                    string
	LogIndex                   uint32
	BlockHash                  string
	RawEvidenceHash            string
	TransactionIndex           uint64
	ReceiptsRoot               string
	InclusionProofHash         string
	ReceiptHeaderSignatureHash string
	UpdatedInBlock             uint64
	Finality                   Finality
}

type ReorgDepthClass string

const (
	ReorgPreFinality  ReorgDepthClass = "PRE_FINALITY"
	ReorgDeepFinality ReorgDepthClass = "DEEP_FINALITY"
)

type SettlementReorg struct {
	PaymentID                          string
	AllocationID                       string
	InstructionDigest                  string
	ChainID                            uint64
	Gateway                            string
	EventID                            string
	TransactionHash                    string
	OrphanedEventEvidenceHash          string
	RawEvidenceHash                    string
	TransactionIndex                   uint64
	ReceiptsRoot                       string
	InclusionProofHash                 string
	OrphanedReceiptHeaderSignatureHash string
	OrphanedBlockHash                  string
	OrphanedBlock                      uint64
	ReplacementBlockHash               string
	ReplacementBlock                   uint64
	DepthClass                         ReorgDepthClass
	ConfirmationDepth                  uint64
	DetectedHead                       uint64
	DetectedHeadHash                   string
	FinalityPolicyHash                 string
	HeaderAuthorityHash                string
	ReplacementHeaderSignatureHash     string
	DetectedHeadHeaderSignatureHash    string
	CompensationRequired               bool
	EvidenceHash                       string
	DetectedAt                         time.Time
}

type Snapshot struct {
	HeadHash                string
	Head                    uint64
	HeadObservedAt          time.Time
	HeadHeaderSignatureHash string
	Tenders                 map[string]Tender
	Loans                   map[string]Loan
	Payments                map[string]string
	CanonicalSettlements    map[string]CanonicalSettlement
	SettlementReorgs        map[string]SettlementReorg
}

type Indexer struct {
	chainID             uint64
	gateway             string
	finalityDepth       uint64
	headerAuthority     ed25519.PublicKey
	headerAuthorityHash string
	finalityPolicyHash  string
	blocks              map[uint64]Block
	eventBlocks         map[string]uint64
	receipts            map[string]verifiedReceipt
	settlementReorgs    map[string]SettlementReorg
	snapshot            Snapshot
}

type FinalityProof struct {
	Finality                Finality
	ConfirmationDepth       uint64
	HeadBlockNumber         uint64
	HeadBlockHash           string
	EvidenceHash            string
	ObservedAt              time.Time
	FinalityPolicyHash      string
	HeaderAuthorityHash     string
	HeadHeaderSignatureHash string
}

// VerifiedGatewayProjection has no public constructor. Only an Indexer whose
// canonical snapshot has advanced through the configured confirmation depth
// can produce one.
type VerifiedGatewayProjection struct {
	settlement CanonicalSettlement
	proof      FinalityProof
}

type VerifiedReorgEnvelope struct {
	evidence SettlementReorg
}

type TransactionReceiptStatus string

const (
	TransactionReverted  TransactionReceiptStatus = "REVERTED"
	TransactionSucceeded TransactionReceiptStatus = "SUCCEEDED"
)

// ExpectedTransaction contains identity only. Receipt status, inclusion,
// canonical block membership, head, and finality are indexer-owned facts.
type ExpectedTransaction struct {
	ChainID         uint64
	Gateway         string
	TransactionHash string
}

type TransactionFailureEvidence struct {
	ChainID                    uint64
	Gateway                    string
	TransactionHash            string
	ReceiptPayloadHash         string
	Status                     TransactionReceiptStatus
	TransactionIndex           uint64
	BlockNumber                uint64
	BlockHash                  string
	ReceiptsRoot               string
	InclusionProofHash         string
	FinalityPolicyHash         string
	HeaderAuthorityHash        string
	ReceiptHeaderSignatureHash string
	HeadHeaderSignatureHash    string
	ConfirmationDepth          uint64
	HeadBlockNumber            uint64
	HeadBlockHash              string
	EvidenceHash               string
	ObservedAt                 time.Time
}

// VerifiedTransactionFailure has no public constructor. Only an Indexer bound
// to one chain and gateway can produce it after observing a canonical reverted
// receipt at the configured confirmation depth.
type VerifiedTransactionFailure struct {
	evidence TransactionFailureEvidence
}

func (projection VerifiedGatewayProjection) Settlement() CanonicalSettlement {
	return projection.settlement
}

func (projection VerifiedGatewayProjection) Proof() FinalityProof {
	return projection.proof
}

func (envelope VerifiedReorgEnvelope) Evidence() SettlementReorg {
	return envelope.evidence
}

func (failure VerifiedTransactionFailure) Evidence() TransactionFailureEvidence {
	return failure.evidence
}

func New(finalityDepth uint64) *Indexer {
	return &Indexer{
		finalityDepth:    finalityDepth,
		blocks:           make(map[uint64]Block),
		eventBlocks:      make(map[string]uint64),
		receipts:         make(map[string]verifiedReceipt),
		settlementReorgs: make(map[string]SettlementReorg),
		snapshot: Snapshot{
			Tenders:              make(map[string]Tender),
			Loans:                make(map[string]Loan),
			Payments:             make(map[string]string),
			CanonicalSettlements: make(map[string]CanonicalSettlement),
			SettlementReorgs:     make(map[string]SettlementReorg),
		},
	}
}

func NewGateway(
	chainID uint64,
	gateway string,
	finalityDepth uint64,
	headerAuthority ed25519.PublicKey,
) (*Indexer, error) {
	if chainID == 0 || !canonicalAddress(gateway) || finalityDepth == 0 ||
		len(headerAuthority) != ed25519.PublicKeySize {
		return nil, ErrInvalidIndexerConfig
	}
	indexer := New(finalityDepth)
	indexer.chainID = chainID
	indexer.gateway = gateway
	indexer.headerAuthority = append(ed25519.PublicKey(nil), headerAuthority...)
	authorityHash := keccak(headerAuthority)
	indexer.headerAuthorityHash = hex32(authorityHash[:])
	policyHash, err := ComputeFinalityPolicyHash(
		chainID,
		gateway,
		finalityDepth,
		headerAuthority,
	)
	if err != nil {
		return nil, err
	}
	indexer.finalityPolicyHash = policyHash
	return indexer, nil
}

func (indexer *Indexer) FinalizedGatewayProjection(
	paymentID string,
) (VerifiedGatewayProjection, bool) {
	if indexer == nil || indexer.finalityDepth == 0 ||
		len(indexer.headerAuthority) != ed25519.PublicKeySize {
		return VerifiedGatewayProjection{}, false
	}
	settlement, exists := indexer.snapshot.CanonicalSettlements[paymentID]
	if !exists || settlement.Finality != Final ||
		settlement.UpdatedInBlock == 0 ||
		indexer.snapshot.Head < settlement.UpdatedInBlock ||
		indexer.snapshot.Head-settlement.UpdatedInBlock < indexer.finalityDepth ||
		indexer.snapshot.HeadHash == "" ||
		!canonicalHash(indexer.snapshot.HeadHeaderSignatureHash) ||
		settlement.FinalityPolicyHash != indexer.finalityPolicyHash ||
		!canonicalHash(settlement.ReceiptsRoot) ||
		!canonicalHash(settlement.InclusionProofHash) ||
		!canonicalHash(settlement.ReceiptHeaderSignatureHash) ||
		indexer.snapshot.HeadObservedAt.IsZero() {
		return VerifiedGatewayProjection{}, false
	}
	proof := FinalityProof{
		Finality:                Final,
		ConfirmationDepth:       indexer.finalityDepth,
		HeadBlockNumber:         indexer.snapshot.Head,
		HeadBlockHash:           indexer.snapshot.HeadHash,
		ObservedAt:              indexer.snapshot.HeadObservedAt,
		FinalityPolicyHash:      indexer.finalityPolicyHash,
		HeaderAuthorityHash:     indexer.headerAuthorityHash,
		HeadHeaderSignatureHash: indexer.snapshot.HeadHeaderSignatureHash,
	}
	proof.EvidenceHash = finalityEvidenceHash(settlement, proof)
	return VerifiedGatewayProjection{
		settlement: settlement,
		proof:      proof,
	}, true
}

func (indexer *Indexer) ReorgEnvelope(
	eventID string,
) (VerifiedReorgEnvelope, bool) {
	if indexer == nil || len(indexer.headerAuthority) != ed25519.PublicKeySize {
		return VerifiedReorgEnvelope{}, false
	}
	evidence, exists := indexer.settlementReorgs[eventID]
	if !exists || evidence.EventID == "" || !canonicalHash(evidence.EvidenceHash) ||
		evidence.FinalityPolicyHash != indexer.finalityPolicyHash ||
		evidence.HeaderAuthorityHash != indexer.headerAuthorityHash ||
		!nonzeroCanonicalHash(evidence.OrphanedEventEvidenceHash) ||
		!canonicalHash(evidence.ReceiptsRoot) ||
		!canonicalHash(evidence.InclusionProofHash) ||
		!canonicalHash(evidence.OrphanedReceiptHeaderSignatureHash) ||
		!canonicalHash(evidence.ReplacementHeaderSignatureHash) ||
		!canonicalHash(evidence.DetectedHeadHeaderSignatureHash) {
		return VerifiedReorgEnvelope{}, false
	}
	return VerifiedReorgEnvelope{evidence: evidence}, true
}

func (indexer *Indexer) VerifyTransactionFailure(
	expected ExpectedTransaction,
) (VerifiedTransactionFailure, error) {
	if indexer == nil || indexer.chainID == 0 || indexer.gateway == "" ||
		indexer.finalityDepth == 0 ||
		len(indexer.headerAuthority) != ed25519.PublicKeySize ||
		expected.ChainID != indexer.chainID ||
		expected.Gateway != indexer.gateway ||
		!canonicalAddress(expected.Gateway) ||
		!canonicalHash(expected.TransactionHash) {
		return VerifiedTransactionFailure{}, ErrInvalidTransactionFailure
	}
	receipt, exists := indexer.receipts[expected.TransactionHash]
	if !exists || receipt.Status != TransactionReverted {
		return VerifiedTransactionFailure{}, ErrInvalidTransactionFailure
	}
	receiptBlock, exists := indexer.blocks[receipt.BlockNumber]
	if !exists || receiptBlock.Hash != receipt.BlockHash ||
		indexer.snapshot.Head < receipt.BlockNumber ||
		indexer.snapshot.Head-receipt.BlockNumber < indexer.finalityDepth ||
		!canonicalHash(indexer.snapshot.HeadHash) ||
		!canonicalHash(indexer.snapshot.HeadHeaderSignatureHash) ||
		!canonicalHash(receipt.ReceiptsRoot) ||
		!canonicalHash(receipt.InclusionProofHash) ||
		!canonicalHash(receipt.HeaderSignatureHash) ||
		indexer.snapshot.HeadObservedAt.IsZero() {
		return VerifiedTransactionFailure{}, ErrInvalidTransactionFailure
	}
	evidence := TransactionFailureEvidence{
		ChainID:                    expected.ChainID,
		Gateway:                    expected.Gateway,
		TransactionHash:            receipt.TransactionHash,
		ReceiptPayloadHash:         receipt.ReceiptPayloadHash,
		Status:                     receipt.Status,
		TransactionIndex:           receipt.TransactionIndex,
		BlockNumber:                receipt.BlockNumber,
		BlockHash:                  receipt.BlockHash,
		ReceiptsRoot:               receipt.ReceiptsRoot,
		InclusionProofHash:         receipt.InclusionProofHash,
		FinalityPolicyHash:         indexer.finalityPolicyHash,
		HeaderAuthorityHash:        indexer.headerAuthorityHash,
		ReceiptHeaderSignatureHash: receipt.HeaderSignatureHash,
		HeadHeaderSignatureHash:    indexer.snapshot.HeadHeaderSignatureHash,
		ConfirmationDepth:          indexer.finalityDepth,
		HeadBlockNumber:            indexer.snapshot.Head,
		HeadBlockHash:              indexer.snapshot.HeadHash,
		ObservedAt:                 indexer.snapshot.HeadObservedAt,
	}
	evidence.EvidenceHash = transactionFailureEvidenceHash(evidence)
	return VerifiedTransactionFailure{evidence: evidence}, nil
}

func (indexer *Indexer) Ingest(block Block) error {
	if indexer == nil || len(indexer.headerAuthority) != 0 {
		return ErrUnauthenticatedBlock
	}
	return indexer.ingestBlock(block, nil)
}

func (indexer *Indexer) IngestAuthenticated(block AuthenticatedBlock) error {
	if indexer == nil || indexer.chainID == 0 || indexer.gateway == "" ||
		len(indexer.headerAuthority) != ed25519.PublicKeySize {
		return ErrInvalidIndexerConfig
	}
	header, receipts, events, err := verifyAuthenticatedBlock(
		indexer.chainID,
		indexer.gateway,
		indexer.headerAuthority,
		block,
	)
	if err != nil {
		return err
	}
	return indexer.ingestBlock(
		Block{
			Number:     header.number,
			Hash:       header.hash,
			ParentHash: header.parentHash,
			ObservedAt: block.ObservedAt.UTC(),
			Events:     events,
			HeaderSignatureHash: func() string {
				signatureHash := keccak(block.Signature)
				return hex32(signatureHash[:])
			}(),
		},
		receipts,
	)
}

func (indexer *Indexer) ingestBlock(
	block Block,
	verifiedReceipts []verifiedReceipt,
) error {
	if block.Number == 0 || block.Hash == "" || block.ObservedAt.IsZero() {
		return ErrInvalidBlock
	}
	block.ObservedAt = block.ObservedAt.UTC()
	if existing, ok := indexer.blocks[block.Number]; ok && existing.Hash == block.Hash {
		if len(indexer.headerAuthority) == 0 {
			return nil
		}
		return indexer.enrichAuthenticatedBlock(existing, block, verifiedReceipts)
	}
	if block.Number > 1 {
		parent, ok := indexer.blocks[block.Number-1]
		if !ok || parent.Hash != block.ParentHash {
			return ErrUnknownParent
		}
	}
	// A newly appended or replacement header is a fresh authority observation.
	// Requiring it to be no earlier than the prior canonical head prevents both
	// append-time rollback and backdated reorg detection.
	if !indexer.snapshot.HeadObservedAt.IsZero() &&
		block.ObservedAt.Before(indexer.snapshot.HeadObservedAt) {
		return ErrInvalidBlock
	}
	blocks := make(map[uint64]Block, len(indexer.blocks)+1)
	for height, canonical := range indexer.blocks {
		blocks[height] = copyBlock(canonical)
	}
	eventBlocks := make(map[string]uint64, len(indexer.eventBlocks)+len(block.Events))
	for eventID, height := range indexer.eventBlocks {
		eventBlocks[eventID] = height
	}
	receipts := make(map[string]verifiedReceipt, len(indexer.receipts)+len(verifiedReceipts))
	for transactionHash, receipt := range indexer.receipts {
		receipts[transactionHash] = receipt
	}
	settlementReorgs := make(map[string]SettlementReorg, len(indexer.settlementReorgs))
	for eventID, evidence := range indexer.settlementReorgs {
		settlementReorgs[eventID] = evidence
	}
	finalHeight := uint64(0)
	if indexer.snapshot.Head > indexer.finalityDepth {
		finalHeight = indexer.snapshot.Head - indexer.finalityDepth
	}
	for height := block.Number; height <= indexer.snapshot.Head; height++ {
		if removed, ok := blocks[height]; ok {
			for transactionHash, receipt := range receipts {
				if receipt.BlockNumber == height {
					delete(receipts, transactionHash)
				}
			}
			for _, event := range removed.Events {
				delete(eventBlocks, event.ID)
				if event.Type == CanonicalSettlementExecuted {
					deep := height <= finalHeight
					depthClass := ReorgPreFinality
					if deep {
						depthClass = ReorgDeepFinality
					}
					evidence := SettlementReorg{
						PaymentID:                          event.PaymentID,
						AllocationID:                       event.AllocationID,
						InstructionDigest:                  event.InstructionDigest,
						ChainID:                            event.ChainID,
						Gateway:                            event.Gateway,
						EventID:                            event.ID,
						TransactionHash:                    event.TxHash,
						OrphanedEventEvidenceHash:          event.EvidenceHash,
						RawEvidenceHash:                    event.RawEvidenceHash,
						TransactionIndex:                   event.TransactionIndex,
						ReceiptsRoot:                       event.ReceiptsRoot,
						InclusionProofHash:                 event.InclusionProofHash,
						OrphanedReceiptHeaderSignatureHash: event.ReceiptHeaderSignatureHash,
						OrphanedBlockHash:                  removed.Hash,
						OrphanedBlock:                      height,
						ReplacementBlockHash:               block.Hash,
						ReplacementBlock:                   block.Number,
						DepthClass:                         depthClass,
						ConfirmationDepth:                  indexer.finalityDepth,
						DetectedHead:                       indexer.snapshot.Head,
						DetectedHeadHash:                   indexer.snapshot.HeadHash,
						FinalityPolicyHash:                 indexer.finalityPolicyHash,
						HeaderAuthorityHash:                indexer.headerAuthorityHash,
						ReplacementHeaderSignatureHash:     block.HeaderSignatureHash,
						DetectedHeadHeaderSignatureHash:    indexer.snapshot.HeadHeaderSignatureHash,
						CompensationRequired:               deep,
						DetectedAt:                         block.ObservedAt.UTC(),
					}
					evidence.EvidenceHash = settlementReorgEvidenceHash(evidence)
					settlementReorgs[event.ID] = evidence
				}
			}
			delete(blocks, height)
		}
		if height == indexer.snapshot.Head {
			break
		}
	}
	for _, receipt := range verifiedReceipts {
		if receipt.BlockNumber != block.Number || receipt.BlockHash != block.Hash ||
			!canonicalHash(receipt.TransactionHash) ||
			!canonicalHash(receipt.ReceiptPayloadHash) ||
			!canonicalHash(receipt.ReceiptsRoot) ||
			!canonicalHash(receipt.InclusionProofHash) {
			return ErrInvalidInclusionProof
		}
		if prior, exists := receipts[receipt.TransactionHash]; exists &&
			(prior.BlockNumber != receipt.BlockNumber ||
				prior.TransactionIndex != receipt.TransactionIndex) {
			return ErrInvalidInclusionProof
		}
		receipts[receipt.TransactionHash] = receipt
	}
	for _, event := range block.Events {
		if event.ID == "" || event.TxHash == "" {
			return ErrInvalidEvent
		}
		if event.Type == CanonicalSettlementExecuted &&
			(!event.decodedCanonical ||
				event.BlockNumber != block.Number ||
				event.BlockHash != block.Hash ||
				(indexer.finalityPolicyHash != "" &&
					event.FinalityPolicyHash != indexer.finalityPolicyHash) ||
				(indexer.chainID != 0 &&
					(event.ChainID != indexer.chainID ||
						event.Gateway != indexer.gateway))) {
			return ErrInvalidEvent
		}
		if existingHeight, exists := eventBlocks[event.ID]; exists {
			return fmt.Errorf("%w: %s at block %d", ErrDuplicateEvent, event.ID, existingHeight)
		}
		eventBlocks[event.ID] = block.Number
	}
	blocks[block.Number] = copyBlock(block)
	candidate := &Indexer{
		chainID:             indexer.chainID,
		gateway:             indexer.gateway,
		finalityDepth:       indexer.finalityDepth,
		headerAuthority:     append(ed25519.PublicKey(nil), indexer.headerAuthority...),
		headerAuthorityHash: indexer.headerAuthorityHash,
		finalityPolicyHash:  indexer.finalityPolicyHash,
		blocks:              blocks,
		eventBlocks:         eventBlocks,
		receipts:            receipts,
		settlementReorgs:    settlementReorgs,
	}
	if err := candidate.Rebuild(); err != nil {
		return err
	}
	indexer.blocks = candidate.blocks
	indexer.eventBlocks = candidate.eventBlocks
	indexer.receipts = candidate.receipts
	indexer.settlementReorgs = candidate.settlementReorgs
	indexer.snapshot = candidate.snapshot
	return nil
}

func (indexer *Indexer) enrichAuthenticatedBlock(
	existing Block,
	incoming Block,
	verifiedReceipts []verifiedReceipt,
) error {
	// Proof enrichment is a second delivery of the same authenticated header,
	// not a new chain observation. Requiring the original observation and
	// signature prevents enrichment from changing canonical time or reorg
	// provenance.
	if existing.ParentHash != incoming.ParentHash ||
		!existing.ObservedAt.Equal(incoming.ObservedAt) ||
		existing.HeaderSignatureHash != incoming.HeaderSignatureHash {
		return ErrInvalidBlock
	}

	blocks := make(map[uint64]Block, len(indexer.blocks))
	for height, canonical := range indexer.blocks {
		blocks[height] = copyBlock(canonical)
	}
	eventBlocks := make(map[string]uint64, len(indexer.eventBlocks)+len(incoming.Events))
	for eventID, height := range indexer.eventBlocks {
		eventBlocks[eventID] = height
	}
	receipts := make(map[string]verifiedReceipt, len(indexer.receipts)+len(verifiedReceipts))
	receiptIndexes := make(map[uint64]verifiedReceipt)
	for transactionHash, receipt := range indexer.receipts {
		receipts[transactionHash] = receipt
		if receipt.BlockNumber == existing.Number && receipt.BlockHash == existing.Hash {
			if prior, duplicate := receiptIndexes[receipt.TransactionIndex]; duplicate &&
				prior != receipt {
				return ErrInvalidInclusionProof
			}
			receiptIndexes[receipt.TransactionIndex] = receipt
		}
	}
	changed := false
	for _, receipt := range verifiedReceipts {
		if receipt.BlockNumber != existing.Number || receipt.BlockHash != existing.Hash {
			return ErrInvalidInclusionProof
		}
		if prior, exists := receiptIndexes[receipt.TransactionIndex]; exists {
			if prior != receipt {
				return ErrInvalidInclusionProof
			}
			continue
		}
		if prior, exists := receipts[receipt.TransactionHash]; exists {
			if prior != receipt {
				return ErrInvalidInclusionProof
			}
			continue
		}
		receiptIndexes[receipt.TransactionIndex] = receipt
		receipts[receipt.TransactionHash] = receipt
		changed = true
	}

	merged := copyBlock(existing)
	existingEvents := make(map[string]Event, len(existing.Events))
	existingLogIndexes := make(map[uint32]Event, len(existing.Events))
	for _, event := range existing.Events {
		existingEvents[event.ID] = event
		existingLogIndexes[event.LogIndex] = event
	}
	for _, event := range incoming.Events {
		if event.ID == "" || event.TxHash == "" ||
			(event.Type == CanonicalSettlementExecuted &&
				(!event.decodedCanonical ||
					event.BlockNumber != existing.Number ||
					event.BlockHash != existing.Hash ||
					event.FinalityPolicyHash != indexer.finalityPolicyHash ||
					event.ChainID != indexer.chainID ||
					event.Gateway != indexer.gateway)) {
			return ErrInvalidEvent
		}
		if prior, exists := existingEvents[event.ID]; exists {
			if prior != event {
				return ErrInvalidEvent
			}
			continue
		}
		if prior, exists := existingLogIndexes[event.LogIndex]; exists && prior != event {
			return ErrInvalidEvent
		}
		if height, exists := eventBlocks[event.ID]; exists {
			return fmt.Errorf("%w: %s at block %d", ErrDuplicateEvent, event.ID, height)
		}
		merged.Events = append(merged.Events, event)
		existingEvents[event.ID] = event
		existingLogIndexes[event.LogIndex] = event
		eventBlocks[event.ID] = existing.Number
		changed = true
	}
	if !changed {
		return nil
	}
	sort.SliceStable(merged.Events, func(left, right int) bool {
		return merged.Events[left].LogIndex < merged.Events[right].LogIndex
	})
	blocks[existing.Number] = merged

	settlementReorgs := make(map[string]SettlementReorg, len(indexer.settlementReorgs))
	for eventID, evidence := range indexer.settlementReorgs {
		settlementReorgs[eventID] = evidence
	}
	candidate := &Indexer{
		chainID:             indexer.chainID,
		gateway:             indexer.gateway,
		finalityDepth:       indexer.finalityDepth,
		headerAuthority:     append(ed25519.PublicKey(nil), indexer.headerAuthority...),
		headerAuthorityHash: indexer.headerAuthorityHash,
		finalityPolicyHash:  indexer.finalityPolicyHash,
		blocks:              blocks,
		eventBlocks:         eventBlocks,
		receipts:            receipts,
		settlementReorgs:    settlementReorgs,
	}
	if err := candidate.Rebuild(); err != nil {
		return err
	}
	indexer.blocks = candidate.blocks
	indexer.eventBlocks = candidate.eventBlocks
	indexer.receipts = candidate.receipts
	indexer.settlementReorgs = candidate.settlementReorgs
	indexer.snapshot = candidate.snapshot
	return nil
}

func (indexer *Indexer) Rebuild() error {
	snapshot := Snapshot{
		Tenders:              make(map[string]Tender),
		Loans:                make(map[string]Loan),
		Payments:             make(map[string]string),
		CanonicalSettlements: make(map[string]CanonicalSettlement),
		SettlementReorgs:     make(map[string]SettlementReorg, len(indexer.settlementReorgs)),
	}
	for eventID, evidence := range indexer.settlementReorgs {
		snapshot.SettlementReorgs[eventID] = evidence
	}
	heights := make([]uint64, 0, len(indexer.blocks))
	for height := range indexer.blocks {
		heights = append(heights, height)
	}
	sort.Slice(heights, func(left, right int) bool { return heights[left] < heights[right] })
	var priorObservedAt time.Time
	for _, height := range heights {
		block := indexer.blocks[height]
		if block.Number != height || block.ObservedAt.IsZero() ||
			(!priorObservedAt.IsZero() && block.ObservedAt.Before(priorObservedAt)) {
			return ErrInvalidBlock
		}
		for _, event := range block.Events {
			if err := apply(&snapshot, event, height); err != nil {
				return err
			}
		}
		snapshot.Head = height
		snapshot.HeadHash = block.Hash
		snapshot.HeadObservedAt = block.ObservedAt.UTC()
		snapshot.HeadHeaderSignatureHash = block.HeaderSignatureHash
		priorObservedAt = block.ObservedAt
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
	for id, settlement := range snapshot.CanonicalSettlements {
		settlement.Finality = Provisional
		if settlement.UpdatedInBlock <= finalHeight {
			settlement.Finality = Final
		}
		snapshot.CanonicalSettlements[id] = settlement
	}
	indexer.snapshot = snapshot
	return nil
}

func (indexer *Indexer) Snapshot() Snapshot {
	result := indexer.snapshot
	result.Tenders = make(map[string]Tender, len(indexer.snapshot.Tenders))
	result.Loans = make(map[string]Loan, len(indexer.snapshot.Loans))
	result.Payments = make(map[string]string, len(indexer.snapshot.Payments))
	result.CanonicalSettlements = make(
		map[string]CanonicalSettlement,
		len(indexer.snapshot.CanonicalSettlements),
	)
	result.SettlementReorgs = make(
		map[string]SettlementReorg,
		len(indexer.snapshot.SettlementReorgs),
	)
	for id, tender := range indexer.snapshot.Tenders {
		result.Tenders[id] = tender
	}
	for id, loan := range indexer.snapshot.Loans {
		result.Loans[id] = loan
	}
	for id, loanID := range indexer.snapshot.Payments {
		result.Payments[id] = loanID
	}
	for id, settlement := range indexer.snapshot.CanonicalSettlements {
		result.CanonicalSettlements[id] = settlement
	}
	for id, evidence := range indexer.snapshot.SettlementReorgs {
		result.SettlementReorgs[id] = evidence
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
	case CanonicalSettlementExecuted:
		loan, loanExists := snapshot.Loans[event.LoanID]
		source, sourceOK := parseUnits(event.SourceUnits)
		gross, grossOK := parseUnits(event.GrossUnits)
		principal, principalOK := parseUnits(event.PrincipalUnits)
		excess, excessOK := parseNonNegativeUnits(event.RefundableExcessUnits)
		debtBefore, debtBeforeOK := parseUnits(event.DebtBeforeUnits)
		debtAfter, debtAfterOK := parseNonNegativeUnits(event.DebtAfterUnits)
		if !event.decodedCanonical ||
			event.PaymentID == "" || event.AllocationID == "" ||
			event.InstructionDigest == "" || event.PolicySetHash == "" ||
			event.LoanAccount == "" || event.Finalizer == "" ||
			event.Attester == "" || event.SourceAssetID == "" ||
			event.AssetID == "" || event.TargetToken == "" ||
			event.SourceAssetID == event.AssetID || event.Gateway == "" ||
			event.ProviderIDHash == "" || event.ProviderReferenceHash == "" ||
			event.ReconciliationID == "" ||
			event.ReconciliationCommitment == "" ||
			event.OriginalJournalSetHash == "" ||
			event.ConversionPolicyHash == "" ||
			event.FinalityPolicyHash == "" ||
			event.EvidenceHash == "" || event.JournalRef == "" ||
			event.RawEvidenceHash == "" ||
			event.ProviderFinalizedAt == 0 ||
			event.ReversalDeadline <= event.ProviderFinalizedAt ||
			event.StateNonceBefore == 0 ||
			event.StateNonceAfter <= event.StateNonceBefore ||
			!sourceOK || !grossOK || source.Cmp(gross) != 0 ||
			!principalOK || !excessOK ||
			!debtBeforeOK || !debtAfterOK ||
			new(big.Int).Add(new(big.Int).Set(principal), excess).Cmp(gross) != 0 ||
			new(big.Int).Add(new(big.Int).Set(principal), debtAfter).Cmp(debtBefore) != 0 {
			return ErrInvalidEvent
		}
		if loanExists &&
			(event.LenderID != loan.LenderID ||
				event.BorrowerID != loan.BorrowerID ||
				loan.AssetID != event.AssetID ||
				loan.OutstandingUnits != event.DebtAfterUnits) {
			return ErrInvalidEvent
		}
		if paymentLoan, exists := snapshot.Payments[event.PaymentID]; exists &&
			paymentLoan != event.LoanID {
			return ErrInvalidEvent
		}
		if _, exists := snapshot.CanonicalSettlements[event.PaymentID]; exists {
			return ErrInvalidEvent
		}
		for _, existing := range snapshot.CanonicalSettlements {
			if existing.AllocationID == event.AllocationID {
				return ErrInvalidEvent
			}
		}
		snapshot.Payments[event.PaymentID] = event.LoanID
		snapshot.CanonicalSettlements[event.PaymentID] = CanonicalSettlement{
			PaymentID:                  event.PaymentID,
			AllocationID:               event.AllocationID,
			InstructionDigest:          event.InstructionDigest,
			PolicySetHash:              event.PolicySetHash,
			LoanID:                     event.LoanID,
			LoanAccount:                event.LoanAccount,
			Finalizer:                  event.Finalizer,
			Attester:                   event.Attester,
			SourceAssetID:              event.SourceAssetID,
			TargetAssetID:              event.AssetID,
			TargetToken:                event.TargetToken,
			SourceUnits:                event.SourceUnits,
			GrossUnits:                 event.GrossUnits,
			ProviderIDHash:             event.ProviderIDHash,
			ProviderReferenceHash:      event.ProviderReferenceHash,
			ReconciliationID:           event.ReconciliationID,
			ReconciliationCommitment:   event.ReconciliationCommitment,
			OriginalJournalSetHash:     event.OriginalJournalSetHash,
			ConversionPolicyHash:       event.ConversionPolicyHash,
			FinalityPolicyHash:         event.FinalityPolicyHash,
			EvidenceHash:               event.EvidenceHash,
			JournalRef:                 event.JournalRef,
			ProviderFinalizedAt:        event.ProviderFinalizedAt,
			ReversalDeadline:           event.ReversalDeadline,
			PrincipalUnits:             event.PrincipalUnits,
			RefundableExcessUnits:      event.RefundableExcessUnits,
			DebtBeforeUnits:            event.DebtBeforeUnits,
			DebtAfterUnits:             event.DebtAfterUnits,
			StateNonceBefore:           event.StateNonceBefore,
			StateNonceAfter:            event.StateNonceAfter,
			LenderID:                   event.LenderID,
			BorrowerID:                 event.BorrowerID,
			ChainID:                    event.ChainID,
			Gateway:                    event.Gateway,
			TransactionHash:            event.TxHash,
			EventID:                    event.ID,
			LogIndex:                   event.LogIndex,
			BlockHash:                  event.BlockHash,
			RawEvidenceHash:            event.RawEvidenceHash,
			TransactionIndex:           event.TransactionIndex,
			ReceiptsRoot:               event.ReceiptsRoot,
			InclusionProofHash:         event.InclusionProofHash,
			ReceiptHeaderSignatureHash: event.ReceiptHeaderSignatureHash,
			UpdatedInBlock:             blockNumber,
		}
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

func parseNonNegativeUnits(value string) (*big.Int, bool) {
	units, ok := new(big.Int).SetString(value, 10)
	return units, ok && units.Sign() >= 0 && units.Cmp(maxUint256) <= 0 &&
		units.String() == value
}

func finalityEvidenceHash(
	settlement CanonicalSettlement,
	proof FinalityProof,
) string {
	value := fmt.Sprintf(
		"UNIFIED_PHASE7C_FINALITY_V3\x00%d\x00%s\x00%s\x00%s\x00%s\x00%s\x00%s\x00%s\x00%d\x00%d\x00%s\x00%d\x00%s\x00%s\x00%s\x00%s\x00%d\x00%d\x00%s\x00%s\x00%s\x00%s\x00%d",
		settlement.ChainID,
		settlement.Gateway,
		settlement.PaymentID,
		settlement.AllocationID,
		settlement.InstructionDigest,
		settlement.EventID,
		settlement.TransactionHash,
		settlement.BlockHash,
		settlement.UpdatedInBlock,
		settlement.LogIndex,
		settlement.RawEvidenceHash,
		settlement.TransactionIndex,
		settlement.ReceiptsRoot,
		settlement.InclusionProofHash,
		settlement.ReceiptHeaderSignatureHash,
		proof.Finality,
		proof.ConfirmationDepth,
		proof.HeadBlockNumber,
		proof.HeadBlockHash,
		proof.FinalityPolicyHash,
		proof.HeaderAuthorityHash,
		proof.HeadHeaderSignatureHash,
		proof.ObservedAt.UnixNano(),
	)
	hash := keccak([]byte(value))
	return hex32(hash[:])
}

func settlementReorgEvidenceHash(evidence SettlementReorg) string {
	value := fmt.Sprintf(
		"UNIFIED_PHASE7C_REORG_V5\x00%s\x00%s\x00%s\x00%d\x00%s\x00%s\x00%s\x00%s\x00%s\x00%d\x00%s\x00%s\x00%s\x00%d\x00%s\x00%d\x00%s\x00%d\x00%s\x00%s\x00%d\x00%s\x00%s\x00%s\x00%s\x00%t\x00%d",
		evidence.PaymentID,
		evidence.AllocationID,
		evidence.InstructionDigest,
		evidence.ChainID,
		evidence.Gateway,
		evidence.EventID,
		evidence.TransactionHash,
		evidence.OrphanedEventEvidenceHash,
		evidence.RawEvidenceHash,
		evidence.TransactionIndex,
		evidence.ReceiptsRoot,
		evidence.InclusionProofHash,
		evidence.OrphanedReceiptHeaderSignatureHash,
		evidence.OrphanedBlock,
		evidence.OrphanedBlockHash,
		evidence.ReplacementBlock,
		evidence.ReplacementBlockHash,
		evidence.DetectedHead,
		evidence.DetectedHeadHash,
		evidence.DepthClass,
		evidence.ConfirmationDepth,
		evidence.FinalityPolicyHash,
		evidence.HeaderAuthorityHash,
		evidence.ReplacementHeaderSignatureHash,
		evidence.DetectedHeadHeaderSignatureHash,
		evidence.CompensationRequired,
		evidence.DetectedAt.UnixNano(),
	)
	hash := keccak([]byte(value))
	return hex32(hash[:])
}

func transactionFailureEvidenceHash(evidence TransactionFailureEvidence) string {
	value := fmt.Sprintf(
		"UNIFIED_PHASE7C_TRANSACTION_FAILURE_V3\x00%d\x00%s\x00%s\x00%s\x00%s\x00%d\x00%d\x00%s\x00%s\x00%s\x00%s\x00%s\x00%s\x00%d\x00%d\x00%s\x00%s\x00%d",
		evidence.ChainID,
		evidence.Gateway,
		evidence.TransactionHash,
		evidence.ReceiptPayloadHash,
		evidence.Status,
		evidence.TransactionIndex,
		evidence.BlockNumber,
		evidence.BlockHash,
		evidence.ReceiptsRoot,
		evidence.InclusionProofHash,
		evidence.ReceiptHeaderSignatureHash,
		evidence.FinalityPolicyHash,
		evidence.HeaderAuthorityHash,
		evidence.ConfirmationDepth,
		evidence.HeadBlockNumber,
		evidence.HeadBlockHash,
		evidence.HeadHeaderSignatureHash,
		evidence.ObservedAt.UnixNano(),
	)
	hash := keccak([]byte(value))
	return hex32(hash[:])
}
