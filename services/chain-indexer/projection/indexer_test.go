package projection

import (
	"crypto/ed25519"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"reflect"
	"strings"
	"testing"
	"time"
)

func canonicalBlocks() []Block {
	now := time.Unix(1_900_000_000, 0).UTC()
	return []Block{
		{
			Number: 1, Hash: "block-1", ObservedAt: now,
			Events: []Event{{
				ID: "event-tender", Type: TenderPublished, TxHash: "tx-1",
				TenderID: "tender-1", BorrowerID: "borrower-1",
			}},
		},
		{
			Number: 2, Hash: "block-2", ParentHash: "block-1",
			ObservedAt: now.Add(time.Minute),
			Events: []Event{
				{
					ID: "event-offer", Type: OfferSelected, TxHash: "tx-2",
					TenderID: "tender-1", OfferID: "offer-1",
				},
				{
					ID: "event-activation", Type: LoanActivated, TxHash: "tx-2",
					LoanID: "loan-1", BorrowerID: "borrower-1", LenderID: "lender-1",
					AssetID: "asset:local:usdc", AmountUnits: "1000",
				},
			},
		},
		{
			Number: 3, Hash: "block-3", ParentHash: "block-2",
			ObservedAt: now.Add(2 * time.Minute),
			Events: []Event{
				{
					ID: "event-payment", Type: PrincipalRepaid, TxHash: "tx-3",
					LoanID: "loan-1", PaymentID: "payment-1", AmountUnits: "1000",
				},
				{ID: "event-close", Type: LoanClosed, TxHash: "tx-3", LoanID: "loan-1"},
			},
		},
	}
}

func TestSyntheticProjectionRebuildAndReorg(t *testing.T) {
	indexer := New(1)
	for _, block := range canonicalBlocks() {
		if err := indexer.Ingest(block); err != nil {
			t.Fatalf("ingest block %d: %v", block.Number, err)
		}
	}
	before := indexer.Snapshot()
	if err := indexer.Rebuild(); err != nil {
		t.Fatalf("rebuild: %v", err)
	}
	if !reflect.DeepEqual(before, indexer.Snapshot()) {
		t.Fatal("projection changed during rebuild")
	}
	replacement := Block{
		Number: 3, Hash: "block-3b", ParentHash: "block-2",
		ObservedAt: before.HeadObservedAt.Add(time.Minute),
		Events: []Event{{
			ID: "event-payment-b", Type: PrincipalRepaid, TxHash: "tx-3b",
			LoanID: "loan-1", PaymentID: "payment-b", AmountUnits: "400",
		}},
	}
	if err := indexer.Ingest(replacement); err != nil {
		t.Fatalf("ingest replacement: %v", err)
	}
	loan := indexer.Snapshot().Loans["loan-1"]
	if loan.Status != "ACTIVE" || loan.OutstandingUnits != "600" {
		t.Fatalf("orphaned state was not rolled back: %#v", loan)
	}
}

func TestSyntheticProjectionRejectsUnknownParent(t *testing.T) {
	indexer := New(2)
	if err := indexer.Ingest(canonicalBlocks()[0]); err != nil {
		t.Fatal(err)
	}
	before := indexer.Snapshot()
	err := indexer.Ingest(Block{
		Number: 2, Hash: "bad", ParentHash: "unknown",
		ObservedAt: time.Unix(1_900_000_000, 0).UTC(),
	})
	if !errors.Is(err, ErrUnknownParent) ||
		!reflect.DeepEqual(before, indexer.Snapshot()) {
		t.Fatalf("unknown parent was not atomic: %v", err)
	}
}

func testHash(value uint64) string {
	return fmt.Sprintf("0x%064x", value)
}

func testAddress(value byte) string {
	encoded := make([]byte, 20)
	for index := range encoded {
		encoded[index] = value
	}
	return "0x" + hex.EncodeToString(encoded)
}

func testHashWord(value uint64) []byte {
	encoded, _ := hex.DecodeString(testHash(value)[2:])
	return encoded
}

func testAddressWord(value byte) []byte {
	encoded, _ := hex.DecodeString(testAddress(value)[2:])
	return append(make([]byte, 12), encoded...)
}

func testUintWord(value uint64) []byte {
	return new(big.Int).SetUint64(value).FillBytes(make([]byte, 32))
}

func canonicalRawLog() RawLog {
	words := [][]byte{
		testHashWord(15), testHashWord(0x33), testAddressWord(0x55),
		testAddressWord(0x22), testAddressWord(0x44), testHashWord(4),
		testHashWord(5), testAddressWord(0x10), testUintWord(1250),
		testUintWord(1250), testHashWord(6), testHashWord(7),
		testHashWord(8), testHashWord(9), testHashWord(10),
		testHashWord(11), testHashWord(12), testHashWord(13),
		testHashWord(14), testUintWord(1_700_000_000),
		testUintWord(1_700_086_400), testUintWord(1000),
		testUintWord(1000), testUintWord(250), testUintWord(0),
		testUintWord(7), testUintWord(9), testAddressWord(0x66),
		testAddressWord(0x77),
	}
	data := make([]byte, 0, 29*32)
	for _, word := range words {
		data = append(data, word...)
	}
	return RawLog{
		ChainID: 31_337, ContractAddress: testAddress(0x11),
		Topics: []string{
			CanonicalSettlementTopic(), testHash(1), testHash(2), testHash(3),
		},
		Data: data, TransactionHash: testHash(100), LogIndex: 7,
		BlockNumber: 2, BlockHash: testHash(200),
	}
}

func TestCanonicalLogDecoderCannotMintAuthority(t *testing.T) {
	raw := canonicalRawLog()
	event, err := DecodeCanonicalSettlementLog(raw)
	if err != nil {
		t.Fatalf("decode canonical log: %v", err)
	}
	if event.PaymentID != raw.Topics[1] || event.AllocationID != raw.Topics[2] ||
		event.InstructionDigest != testHash(15) || event.PrincipalUnits != "1000" ||
		event.RefundableExcessUnits != "250" || event.decodedCanonical {
		t.Fatalf("decoder either lost fields or minted authority: %#v", event)
	}
	indexer := New(1)
	if err := indexer.Ingest(Block{
		Number: 1, Hash: raw.BlockHash, ObservedAt: time.Now().UTC(),
		Events: []Event{event},
	}); !errors.Is(err, ErrInvalidEvent) {
		t.Fatalf("decode-only event became canonical: %v", err)
	}
	for name, mutate := range map[string]func(*RawLog){
		"truncated tuple": func(value *RawLog) {
			value.Data = append([]byte(nil), value.Data[:len(value.Data)-1]...)
		},
		"wrong topic": func(value *RawLog) {
			value.Topics = append([]string(nil), value.Topics...)
			value.Topics[0] = testHash(999)
		},
		"noncanonical address word": func(value *RawLog) {
			value.Data = append([]byte(nil), value.Data...)
			value.Data[2*32] = 1
		},
	} {
		t.Run(name, func(t *testing.T) {
			invalid := raw
			mutate(&invalid)
			if _, err := DecodeCanonicalSettlementLog(invalid); !errors.Is(err, ErrInvalidEvent) {
				t.Fatalf("invalid ABI log accepted: %v", err)
			}
		})
	}
}

type authenticatedTestChain struct {
	chainID uint64
	gateway string
	private ed25519.PrivateKey
	public  ed25519.PublicKey
}

func newAuthenticatedTestChain(chainID uint64, gateway string, keyByte byte) authenticatedTestChain {
	seed := make([]byte, ed25519.SeedSize)
	for index := range seed {
		seed[index] = keyByte
	}
	privateKey := ed25519.NewKeyFromSeed(seed)
	return authenticatedTestChain{
		chainID: chainID, gateway: gateway, private: privateKey,
		public: privateKey.Public().(ed25519.PublicKey),
	}
}

func (chain authenticatedTestChain) policyHash(t *testing.T, depth uint64) string {
	t.Helper()
	hash, err := ComputeFinalityPolicyHash(chain.chainID, chain.gateway, depth, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	return hash
}

func (chain authenticatedTestChain) emptyBlock(
	t *testing.T,
	number uint64,
	parentHash string,
	observedAt time.Time,
) (AuthenticatedBlock, string) {
	t.Helper()
	emptyRoot := keccak([]byte{0x80})
	return chain.block(
		t, number, parentHash, observedAt, emptyRoot[:], emptyRoot[:], nil,
	)
}

func (chain authenticatedTestChain) receiptBlock(
	t *testing.T,
	number uint64,
	parentHash string,
	observedAt time.Time,
	transactionDiscriminator uint64,
	succeeded bool,
	logs []receiptLog,
) (AuthenticatedBlock, string, string) {
	t.Helper()
	transaction := testRLPList(testRLPUint(transactionDiscriminator))
	receipt := testReceiptRLP(succeeded, logs)
	return chain.valueBlock(t, number, parentHash, observedAt, transaction, receipt)
}

func (chain authenticatedTestChain) typedReceiptBlock(
	t *testing.T,
	number uint64,
	parentHash string,
	observedAt time.Time,
	transactionDiscriminator uint64,
	succeeded bool,
	logs []receiptLog,
) (AuthenticatedBlock, string, string) {
	t.Helper()
	transaction := append([]byte{0x02}, testRLPList(testRLPUint(transactionDiscriminator))...)
	receipt := append([]byte{0x02}, testReceiptRLP(succeeded, logs)...)
	return chain.valueBlock(t, number, parentHash, observedAt, transaction, receipt)
}

func (chain authenticatedTestChain) valueBlock(
	t *testing.T,
	number uint64,
	parentHash string,
	observedAt time.Time,
	transaction []byte,
	receipt []byte,
) (AuthenticatedBlock, string, string) {
	t.Helper()
	key := rlpEncodeUint(0)
	transactionLeaf := testTrieLeaf(key, transaction)
	receiptLeaf := testTrieLeaf(key, receipt)
	transactionRoot := keccak(transactionLeaf)
	receiptRoot := keccak(receiptLeaf)
	block, blockHash := chain.block(
		t,
		number,
		parentHash,
		observedAt,
		transactionRoot[:],
		receiptRoot[:],
		[]ReceiptInclusionProof{{
			TransactionIndex: 0, TransactionRLP: transaction,
			TransactionProofNodes: [][]byte{transactionLeaf},
			ReceiptRLP:            receipt, ReceiptProofNodes: [][]byte{receiptLeaf},
		}},
	)
	transactionHash := keccak(transaction)
	return block, blockHash, hex32(transactionHash[:])
}

func (chain authenticatedTestChain) block(
	t *testing.T,
	number uint64,
	parentHash string,
	observedAt time.Time,
	transactionRoot []byte,
	receiptRoot []byte,
	receipts []ReceiptInclusionProof,
) (AuthenticatedBlock, string) {
	t.Helper()
	parent := make([]byte, 32)
	if parentHash != "" {
		var err error
		parent, err = hex.DecodeString(parentHash[2:])
		if err != nil {
			t.Fatal(err)
		}
	}
	header := testRLPList(
		testRLPBytes(parent),
		testRLPBytes(make([]byte, 32)),
		testRLPBytes(make([]byte, 20)),
		testRLPBytes(make([]byte, 32)),
		testRLPBytes(transactionRoot),
		testRLPBytes(receiptRoot),
		testRLPBytes(make([]byte, 256)),
		testRLPUint(1),
		testRLPUint(number),
		testRLPUint(30_000_000),
		testRLPUint(21_000),
		testRLPUint(uint64(observedAt.Unix())),
	)
	digest, err := AuthenticatedHeaderSigningDigest(chain.chainID, header, observedAt)
	if err != nil {
		t.Fatal(err)
	}
	signature := ed25519.Sign(chain.private, digest[:])
	hash := keccak(header)
	return AuthenticatedBlock{
		HeaderRLP: header, ObservedAt: observedAt, Signature: signature, Receipts: receipts,
	}, hex32(hash[:])
}

func (chain authenticatedTestChain) resignBlock(
	t *testing.T,
	block AuthenticatedBlock,
	observedAt time.Time,
) AuthenticatedBlock {
	t.Helper()
	result := copyAuthenticatedBlock(block)
	result.ObservedAt = observedAt.UTC()
	digest, err := AuthenticatedHeaderSigningDigest(
		chain.chainID,
		result.HeaderRLP,
		result.ObservedAt,
	)
	if err != nil {
		t.Fatal(err)
	}
	result.Signature = ed25519.Sign(chain.private, digest[:])
	return result
}

func TestAuthenticatedGatewaySuccessFinalityAndReorg(t *testing.T) {
	const depth = uint64(1)
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x41)
	indexer, err := NewGateway(chain.chainID, chain.gateway, depth, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	raw := canonicalRawLog()
	raw.Data = append([]byte(nil), raw.Data...)
	policyBytes, _ := hex.DecodeString(chain.policyHash(t, depth)[2:])
	copy(raw.Data[16*32:17*32], policyBytes)
	now := time.Unix(1_930_000_000, 0).UTC()
	block1, hash1, _ := chain.receiptBlock(t, 1, "", now, 1, true, []receiptLog{{
		address: chain.gateway, topics: raw.Topics, data: raw.Data,
	}})
	if err := indexer.IngestAuthenticated(block1); err != nil {
		t.Fatalf("ingest verified receipt: %v", err)
	}
	settlement := indexer.Snapshot().CanonicalSettlements[raw.Topics[1]]
	if settlement.Finality != Provisional || settlement.TransactionIndex != 0 ||
		!canonicalHash(settlement.ReceiptsRoot) ||
		!canonicalHash(settlement.InclusionProofHash) ||
		!canonicalHash(settlement.ReceiptHeaderSignatureHash) {
		t.Fatalf("verified receipt evidence was not projected: %#v", settlement)
	}
	block2, hash2 := chain.emptyBlock(t, 2, hash1, now.Add(time.Minute))
	if err := indexer.IngestAuthenticated(block2); err != nil {
		t.Fatalf("advance authenticated finality: %v", err)
	}
	verified, ok := indexer.FinalizedGatewayProjection(raw.Topics[1])
	if !ok {
		t.Fatal("valid settlement did not finalize")
	}
	proof := verified.Proof()
	if proof.FinalityPolicyHash != chain.policyHash(t, depth) ||
		!canonicalHash(proof.HeaderAuthorityHash) ||
		!canonicalHash(proof.HeadHeaderSignatureHash) ||
		proof.HeadBlockHash != hash2 || !canonicalHash(proof.EvidenceHash) {
		t.Fatalf("finality authority is incomplete: %#v", proof)
	}

	replacement, replacementHash := chain.emptyBlock(t, 1, "", now.Add(2*time.Minute))
	if err := indexer.IngestAuthenticated(replacement); err != nil {
		t.Fatalf("ingest authenticated reorg: %v", err)
	}
	if _, exists := indexer.Snapshot().CanonicalSettlements[raw.Topics[1]]; exists {
		t.Fatal("orphaned verified event survived reorg")
	}
	envelope, ok := indexer.ReorgEnvelope(settlement.EventID)
	if !ok {
		t.Fatal("authenticated reorg evidence missing")
	}
	reorg := envelope.Evidence()
	if reorg.OrphanedBlockHash != hash1 ||
		reorg.ReplacementBlockHash != replacementHash ||
		reorg.OrphanedEventEvidenceHash != settlement.EvidenceHash ||
		reorg.DepthClass != ReorgDeepFinality ||
		!reorg.CompensationRequired ||
		reorg.ReceiptsRoot != settlement.ReceiptsRoot ||
		reorg.InclusionProofHash != settlement.InclusionProofHash ||
		reorg.OrphanedReceiptHeaderSignatureHash != settlement.ReceiptHeaderSignatureHash ||
		reorg.FinalityPolicyHash != chain.policyHash(t, depth) ||
		!canonicalHash(reorg.HeaderAuthorityHash) ||
		!canonicalHash(reorg.ReplacementHeaderSignatureHash) ||
		!canonicalHash(reorg.DetectedHeadHeaderSignatureHash) ||
		!reorg.DetectedAt.Equal(now.Add(2*time.Minute)) ||
		reorg.DetectedAt.Before(block2.ObservedAt) ||
		reorg.DetectedAt.Before(block1.ObservedAt) {
		t.Fatalf("reorg lost receipt authority: %#v", reorg)
	}
}

func TestReorgEnvelopeRejectsZeroEventEvidenceHash(t *testing.T) {
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x51)
	indexer, err := NewGateway(chain.chainID, chain.gateway, 1, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	raw := canonicalRawLog()
	raw.Data = append([]byte(nil), raw.Data...)
	policyBytes, _ := hex.DecodeString(chain.policyHash(t, 1)[2:])
	copy(raw.Data[16*32:17*32], policyBytes)
	clear(raw.Data[17*32 : 18*32])

	now := time.Unix(1_932_000_000, 0).UTC()
	block, hash, _ := chain.receiptBlock(t, 1, "", now, 1, true, []receiptLog{{
		address: chain.gateway,
		topics:  raw.Topics,
		data:    raw.Data,
	}})
	if err := indexer.IngestAuthenticated(block); err != nil {
		t.Fatalf("ingest zero-evidence event: %v", err)
	}
	settlement := indexer.Snapshot().CanonicalSettlements[raw.Topics[1]]
	if settlement.EvidenceHash != "0x"+strings.Repeat("0", 64) {
		t.Fatalf("fixture did not decode zero event evidence: %#v", settlement)
	}
	replacement, _ := chain.emptyBlock(t, 1, "", now.Add(time.Minute))
	if err := indexer.IngestAuthenticated(replacement); err != nil {
		t.Fatalf("ingest replacement: %v", err)
	}
	if _, exists := indexer.ReorgEnvelope(settlement.EventID); exists {
		t.Fatal("zero event-evidence hash minted a verified reorg envelope")
	}
	if indexer.Snapshot().HeadHash == hash {
		t.Fatal("replacement did not become canonical")
	}
}

func TestAuthenticatedObservationTimeIsMonotonicAcrossAppendAndReplacement(t *testing.T) {
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x61)
	indexer, err := NewGateway(chain.chainID, chain.gateway, 1, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_935_000_000, 0).UTC()
	block1, hash1 := chain.emptyBlock(t, 1, "", now)
	if err := indexer.IngestAuthenticated(block1); err != nil {
		t.Fatal(err)
	}
	block2, hash2 := chain.emptyBlock(t, 2, hash1, now.Add(time.Minute))
	if err := indexer.IngestAuthenticated(block2); err != nil {
		t.Fatal(err)
	}
	before := indexer.Snapshot()

	appendRollback, _ := chain.emptyBlock(
		t,
		3,
		hash2,
		now.Add(30*time.Second),
	)
	if err := indexer.IngestAuthenticated(appendRollback); !errors.Is(err, ErrInvalidBlock) {
		t.Fatalf("backdated canonical append accepted: %v", err)
	}
	replacementBehindHead, _ := chain.emptyBlock(
		t,
		1,
		"",
		now.Add(30*time.Second),
	)
	if err := indexer.IngestAuthenticated(replacementBehindHead); !errors.Is(
		err,
		ErrInvalidBlock,
	) {
		t.Fatalf("replacement backdated behind the prior head accepted: %v", err)
	}
	sameHeightRollback, _ := chain.emptyBlock(
		t,
		2,
		hash1,
		now.Add(30*time.Second),
	)
	if err := indexer.IngestAuthenticated(sameHeightRollback); !errors.Is(
		err,
		ErrInvalidBlock,
	) {
		t.Fatalf("same-height replacement rolled observation time backward: %v", err)
	}
	if !reflect.DeepEqual(before, indexer.Snapshot()) {
		t.Fatal("rejected observation rollback mutated canonical state")
	}

	replacement, replacementHash := chain.emptyBlock(
		t,
		1,
		"",
		before.HeadObservedAt.Add(time.Minute),
	)
	if err := indexer.IngestAuthenticated(replacement); err != nil {
		t.Fatalf("forward-observed replacement rejected: %v", err)
	}
	after := indexer.Snapshot()
	if after.Head != 1 || after.HeadHash != replacementHash ||
		!after.HeadObservedAt.Equal(before.HeadObservedAt.Add(time.Minute)) {
		t.Fatalf("replacement did not preserve monotonic observation: %#v", after)
	}
}

func TestAuthenticatedSameHeaderReceiptEnrichmentIsAtomicAndIdempotent(t *testing.T) {
	const depth = uint64(1)
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x62)
	indexer, err := NewGateway(chain.chainID, chain.gateway, depth, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	raw := canonicalRawLog()
	raw.Data = append([]byte(nil), raw.Data...)
	policyBytes, _ := hex.DecodeString(chain.policyHash(t, depth)[2:])
	copy(raw.Data[16*32:17*32], policyBytes)
	now := time.Unix(1_936_000_000, 0).UTC()
	full, blockHash, transactionHash := chain.receiptBlock(
		t,
		1,
		"",
		now,
		17,
		true,
		[]receiptLog{{
			address: chain.gateway,
			topics:  raw.Topics,
			data:    raw.Data,
		}},
	)
	headerOnly := copyAuthenticatedBlock(full)
	headerOnly.Receipts = nil
	if err := indexer.IngestAuthenticated(headerOnly); err != nil {
		t.Fatalf("ingest header-only observation: %v", err)
	}
	before := indexer.Snapshot()
	if before.HeadHash != blockHash ||
		!before.HeadObservedAt.Equal(now) ||
		len(before.CanonicalSettlements) != 0 {
		t.Fatalf("unexpected header-only projection: %#v", before)
	}

	if err := indexer.IngestAuthenticated(full); err != nil {
		t.Fatalf("same-header proof enrichment rejected: %v", err)
	}
	enriched := indexer.Snapshot()
	settlement, exists := enriched.CanonicalSettlements[raw.Topics[1]]
	if !exists || settlement.TransactionHash != transactionHash ||
		enriched.HeadHash != before.HeadHash ||
		!enriched.HeadObservedAt.Equal(before.HeadObservedAt) ||
		len(enriched.SettlementReorgs) != 0 {
		t.Fatalf("proof enrichment changed chain identity or lost event: %#v", enriched)
	}
	if err := indexer.IngestAuthenticated(full); err != nil {
		t.Fatalf("exact enrichment replay rejected: %v", err)
	}
	if !reflect.DeepEqual(enriched, indexer.Snapshot()) {
		t.Fatal("exact enrichment replay was not idempotent")
	}

	header, verifiedReceipts, events, err := verifyAuthenticatedBlock(
		chain.chainID,
		chain.gateway,
		chain.public,
		full,
	)
	if err != nil {
		t.Fatal(err)
	}
	signatureHash := keccak(full.Signature)
	incoming := Block{
		Number:              1,
		Hash:                blockHash,
		ParentHash:          header.parentHash,
		ObservedAt:          now,
		Events:              events,
		HeaderSignatureHash: hex32(signatureHash[:]),
	}
	conflictingReceipts := append([]verifiedReceipt(nil), verifiedReceipts...)
	conflictingReceipts[0].Status = TransactionReverted
	receiptsBefore := make(map[string]verifiedReceipt, len(indexer.receipts))
	for hash, receipt := range indexer.receipts {
		receiptsBefore[hash] = receipt
	}
	if err := indexer.ingestBlock(incoming, conflictingReceipts); !errors.Is(
		err,
		ErrInvalidInclusionProof,
	) {
		t.Fatalf("conflicting receipt enrichment accepted: %v", err)
	}
	if !reflect.DeepEqual(receiptsBefore, indexer.receipts) ||
		!reflect.DeepEqual(enriched, indexer.Snapshot()) {
		t.Fatal("conflicting receipt enrichment was not atomic")
	}

	conflictingEvent := incoming
	conflictingEvent.Events = append([]Event(nil), events...)
	conflictingEvent.Events[0].AllocationID = testHash(999)
	if err := indexer.ingestBlock(conflictingEvent, verifiedReceipts); !errors.Is(
		err,
		ErrInvalidEvent,
	) {
		t.Fatalf("conflicting event enrichment accepted: %v", err)
	}
	if !reflect.DeepEqual(enriched, indexer.Snapshot()) {
		t.Fatal("conflicting event enrichment mutated projection")
	}
}

func TestAuthenticatedSameHeaderEnrichmentRejectsObservationRollback(t *testing.T) {
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x63)
	indexer, err := NewGateway(chain.chainID, chain.gateway, 1, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	headerTime := time.Unix(1_937_000_000, 0).UTC()
	full, _, _ := chain.receiptBlock(t, 1, "", headerTime, 19, false, nil)
	firstObservation := chain.resignBlock(t, full, headerTime.Add(2*time.Minute))
	firstObservation.Receipts = nil
	if err := indexer.IngestAuthenticated(firstObservation); err != nil {
		t.Fatal(err)
	}
	before := indexer.Snapshot()
	rollback := chain.resignBlock(t, full, headerTime.Add(time.Minute))
	if err := indexer.IngestAuthenticated(rollback); !errors.Is(err, ErrInvalidBlock) {
		t.Fatalf("backdated same-header enrichment accepted: %v", err)
	}
	if !reflect.DeepEqual(before, indexer.Snapshot()) || len(indexer.receipts) != 0 {
		t.Fatal("backdated enrichment mutated state")
	}
}

func TestAuthenticatedRevertedReceiptIsDerivedAndReorgRemoved(t *testing.T) {
	const depth = uint64(1)
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x42)
	indexer, err := NewGateway(chain.chainID, chain.gateway, depth, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_940_000_000, 0).UTC()
	block1, hash1, transactionHash := chain.receiptBlock(
		t, 1, "", now, 7, false, nil,
	)
	if err := indexer.IngestAuthenticated(block1); err != nil {
		t.Fatal(err)
	}
	expected := ExpectedTransaction{
		ChainID: chain.chainID, Gateway: chain.gateway, TransactionHash: transactionHash,
	}
	if _, err := indexer.VerifyTransactionFailure(expected); !errors.Is(
		err, ErrInvalidTransactionFailure,
	) {
		t.Fatalf("shallow receipt was accepted: %v", err)
	}
	block2, _ := chain.emptyBlock(t, 2, hash1, now.Add(time.Minute))
	if err := indexer.IngestAuthenticated(block2); err != nil {
		t.Fatal(err)
	}
	verified, err := indexer.VerifyTransactionFailure(expected)
	if err != nil {
		t.Fatalf("verified reverted receipt rejected: %v", err)
	}
	evidence := verified.Evidence()
	if evidence.TransactionHash != transactionHash ||
		evidence.Status != TransactionReverted || evidence.TransactionIndex != 0 ||
		evidence.FinalityPolicyHash != chain.policyHash(t, depth) ||
		!canonicalHash(evidence.ReceiptPayloadHash) ||
		!canonicalHash(evidence.ReceiptsRoot) ||
		!canonicalHash(evidence.InclusionProofHash) ||
		!canonicalHash(evidence.HeaderAuthorityHash) ||
		!canonicalHash(evidence.ReceiptHeaderSignatureHash) ||
		!canonicalHash(evidence.HeadHeaderSignatureHash) ||
		!canonicalHash(evidence.EvidenceHash) {
		t.Fatalf("failure was not derived from complete evidence: %#v", evidence)
	}
	invalid := expected
	invalid.TransactionHash = testHash(999)
	if _, err := indexer.VerifyTransactionFailure(invalid); !errors.Is(
		err, ErrInvalidTransactionFailure,
	) {
		t.Fatalf("unknown transaction accepted: %v", err)
	}
	replacement, _ := chain.emptyBlock(t, 1, "", now.Add(2*time.Minute))
	if err := indexer.IngestAuthenticated(replacement); err != nil {
		t.Fatal(err)
	}
	if _, err := indexer.VerifyTransactionFailure(expected); !errors.Is(
		err, ErrInvalidTransactionFailure,
	) {
		t.Fatalf("orphaned receipt remained authoritative: %v", err)
	}
}

func TestAuthenticatedTypedTransactionAndReceipt(t *testing.T) {
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x44)
	indexer, err := NewGateway(chain.chainID, chain.gateway, 1, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_945_000_000, 0).UTC()
	block1, hash1, transactionHash := chain.typedReceiptBlock(
		t, 1, "", now, 11, false, nil,
	)
	if err := indexer.IngestAuthenticated(block1); err != nil {
		t.Fatalf("typed EIP-2718 values rejected: %v", err)
	}
	block2, _ := chain.emptyBlock(t, 2, hash1, now.Add(time.Minute))
	if err := indexer.IngestAuthenticated(block2); err != nil {
		t.Fatal(err)
	}
	if _, err := indexer.VerifyTransactionFailure(ExpectedTransaction{
		ChainID: chain.chainID, Gateway: chain.gateway, TransactionHash: transactionHash,
	}); err != nil {
		t.Fatalf("typed receipt did not produce derived failure: %v", err)
	}
}

func TestFixedPyTrieVectorsCoverExtensionBranchAndEmbeddedNodes(t *testing.T) {
	// These constants were independently produced with Python HexaryTrie/rlp.
	shortRoot := mustHex(t, "640e7e4bbc62784560bdbc9c528f1eff5eafcb08474acb3529e8d5a535ceda86")
	shortProof12 := mustHexProof(t,
		"dd11db8080c52083636174c52083646f6780808080808080808080808080",
		"db8080c52083636174c52083646f6780808080808080808080808080",
		"c52083636174",
	)
	shortProof13 := mustHexProof(t,
		"dd11db8080c52083636174c52083646f6780808080808080808080808080",
		"db8080c52083636174c52083646f6780808080808080808080808080",
		"c52083646f67",
	)
	if !verifyTrieInclusion(shortRoot, []byte{0x12}, []byte("cat"), shortProof12) ||
		!verifyTrieInclusion(shortRoot, []byte{0x13}, []byte("dog"), shortProof13) {
		t.Fatal("fixed extension/branch/embedded-child proof rejected")
	}
	pathProof := copyByteSlices(shortProof12)
	pathProof[0][1] = 0x12
	pathRoot := keccak(pathProof[0])
	if verifyTrieInclusion(pathRoot[:], []byte{0x12}, []byte("cat"), pathProof) {
		t.Fatal("wrong extension path accepted under its recomputed root")
	}
	referenceProof := copyByteSlices(shortProof12)
	referenceProof[1][4] ^= 1
	if verifyTrieInclusion(shortRoot, []byte{0x12}, []byte("cat"), referenceProof) {
		t.Fatal("mutated embedded-node reference accepted")
	}
	if verifyTrieInclusion(shortRoot, []byte{0x12}, []byte("cap"), shortProof12) {
		t.Fatal("wrong embedded leaf value accepted")
	}

	receiptRoot := mustHex(t, "0e4b7fa81e57abf92faf8fb7fce9fac2e86854486d2573ffaef7828584598ca2")
	receiptValue := testRLPList(
		testRLPBytes([]byte{1}),
		testRLPBytes([]byte{0xa4, 0x10}),
		testRLPBytes(make([]byte, 256)),
		testRLPList(),
	)
	receiptProof := mustHexProof(t,
		"f851a086ac492ba69fb8a11a7b23b8cb3c73bc61dfe2b6e0188cc23be867e16efd2f0f80808080808080a04de834bd23b53a3d82923ae5f359239b326c66758f2ae636ab934844dba2b9658080808080808080",
		"f9010f31b9010bf901080182a410b9010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0",
	)
	if !verifyTrieInclusion(receiptRoot, []byte{0x01}, receiptValue, receiptProof) {
		t.Fatal("independent two-receipt Ethereum trie proof rejected")
	}
	mutatedReceiptProof := copyByteSlices(receiptProof)
	mutatedReceiptProof[1][len(mutatedReceiptProof[1])-1] ^= 1
	if verifyTrieInclusion(receiptRoot, []byte{0x01}, receiptValue, mutatedReceiptProof) {
		t.Fatal("mutated hashed receipt leaf accepted")
	}
}

func TestTrieChildReferencesRejectShortStringsAndAcceptEmbeddedLists(t *testing.T) {
	leaf := testRLPList(
		testRLPBytes([]byte{0x30}),
		testRLPBytes([]byte("cat")),
	)
	children := make([][]byte, 17)
	for index := range children {
		children[index] = testRLPBytes(nil)
	}
	children[0] = leaf
	embeddedListBranch := testRLPList(children...)
	embeddedListRoot := keccak(embeddedListBranch)
	if !verifyTrieInclusion(
		embeddedListRoot[:],
		[]byte{0x00},
		[]byte("cat"),
		[][]byte{embeddedListBranch, leaf},
	) {
		t.Fatal("canonical embedded-list child was rejected")
	}

	children[0] = testRLPBytes(leaf)
	shortStringBranch := testRLPList(children...)
	shortStringRoot := keccak(shortStringBranch)
	if verifyTrieInclusion(
		shortStringRoot[:],
		[]byte{0x00},
		[]byte("cat"),
		[][]byte{shortStringBranch, leaf},
	) {
		t.Fatal("noncanonical short-string child reference was accepted")
	}
}

func TestReceiptDecoderRequiresCanonicalGasAndExactBloom(t *testing.T) {
	valid := testReceiptRLP(true, nil)
	if _, _, err := decodeReceipt(valid); err != nil {
		t.Fatalf("valid receipt rejected: %v", err)
	}
	status := testRLPBytes([]byte{1})
	logs := testRLPList()
	tests := map[string][]byte{
		"zero byte gas": testRLPList(
			status,
			testRLPBytes([]byte{0}),
			testRLPBytes(make([]byte, 256)),
			logs,
		),
		"leading-zero gas": testRLPList(
			status,
			testRLPBytes([]byte{0, 1}),
			testRLPBytes(make([]byte, 256)),
			logs,
		),
		"oversize gas": testRLPList(
			status,
			testRLPBytes(make([]byte, 9)),
			testRLPBytes(make([]byte, 256)),
			logs,
		),
		"short bloom": testRLPList(
			status,
			testRLPUint(21_000),
			testRLPBytes(make([]byte, 255)),
			logs,
		),
		"long bloom": testRLPList(
			status,
			testRLPUint(21_000),
			testRLPBytes(make([]byte, 257)),
			logs,
		),
		"list bloom": testRLPList(
			status,
			testRLPUint(21_000),
			testRLPList(),
			logs,
		),
	}
	for name, receipt := range tests {
		t.Run(name, func(t *testing.T) {
			if _, _, err := decodeReceipt(receipt); !errors.Is(
				err,
				ErrInvalidInclusionProof,
			) {
				t.Fatalf("malformed receipt accepted: %v", err)
			}
		})
	}
}

func TestAuthenticatedBlockAggregateLimits(t *testing.T) {
	atReceiptLimit := AuthenticatedBlock{
		HeaderRLP: []byte{0x80},
		Signature: make([]byte, ed25519.SignatureSize),
		Receipts:  make([]ReceiptInclusionProof, maxReceiptsPerBlock),
	}
	if !validAuthenticatedBlockSize(atReceiptLimit) {
		t.Fatal("receipt-count boundary rejected")
	}
	overReceiptLimit := atReceiptLimit
	overReceiptLimit.Receipts = make(
		[]ReceiptInclusionProof,
		maxReceiptsPerBlock+1,
	)
	if validAuthenticatedBlockSize(overReceiptLimit) {
		t.Fatal("receipt-count limit was not enforced")
	}

	proofNode := make([]byte, maxProofNodeBytes)
	atProofLimit := AuthenticatedBlock{
		HeaderRLP: []byte{0x80},
		Signature: make([]byte, ed25519.SignatureSize),
		Receipts: make(
			[]ReceiptInclusionProof,
			maxBlockProofBytes/maxProofBytes,
		),
	}
	for receiptIndex := range atProofLimit.Receipts {
		atProofLimit.Receipts[receiptIndex].TransactionProofNodes = make(
			[][]byte,
			maxProofBytes/maxProofNodeBytes,
		)
		for proofIndex := range atProofLimit.Receipts[receiptIndex].TransactionProofNodes {
			atProofLimit.Receipts[receiptIndex].TransactionProofNodes[proofIndex] = proofNode
		}
	}
	if !validAuthenticatedBlockSize(atProofLimit) {
		t.Fatal("aggregate proof-byte boundary rejected")
	}
	overProofLimit := atProofLimit
	overProofLimit.Receipts = append(
		[]ReceiptInclusionProof(nil),
		atProofLimit.Receipts...,
	)
	overProofLimit.Receipts = append(
		overProofLimit.Receipts,
		ReceiptInclusionProof{TransactionProofNodes: [][]byte{{0x01}}},
	)
	if validAuthenticatedBlockSize(overProofLimit) {
		t.Fatal("aggregate proof-byte limit was not enforced")
	}

	atInputLimit := AuthenticatedBlock{
		HeaderRLP: []byte{0x80},
		Signature: make([]byte, ed25519.SignatureSize),
	}
	remaining := maxBlockInputBytes -
		len(atInputLimit.HeaderRLP) -
		len(atInputLimit.Signature)
	fullTransaction := make([]byte, maxTransactionBytes)
	fullReceipt := make([]byte, maxReceiptBytes)
	for remaining >= maxTransactionBytes+maxReceiptBytes {
		atInputLimit.Receipts = append(
			atInputLimit.Receipts,
			ReceiptInclusionProof{
				TransactionRLP: fullTransaction,
				ReceiptRLP:     fullReceipt,
			},
		)
		remaining -= maxTransactionBytes + maxReceiptBytes
	}
	last := ReceiptInclusionProof{}
	if remaining > maxTransactionBytes {
		last.TransactionRLP = fullTransaction
		last.ReceiptRLP = make([]byte, remaining-maxTransactionBytes)
	} else {
		last.TransactionRLP = make([]byte, remaining)
	}
	atInputLimit.Receipts = append(atInputLimit.Receipts, last)
	if !validAuthenticatedBlockSize(atInputLimit) {
		t.Fatal("aggregate input-byte boundary rejected")
	}
	overInputLimit := atInputLimit
	overInputLimit.Receipts = append(
		[]ReceiptInclusionProof(nil),
		atInputLimit.Receipts...,
	)
	lastIndex := len(overInputLimit.Receipts) - 1
	overInputLimit.Receipts[lastIndex].ReceiptRLP = append(
		overInputLimit.Receipts[lastIndex].ReceiptRLP,
		0x00,
	)
	if validAuthenticatedBlockSize(overInputLimit) {
		t.Fatal("aggregate input-byte limit was not enforced")
	}
}

func TestAuthenticatedBoundaryRejectsFabricationAndResourceAbuse(t *testing.T) {
	chain := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x43)
	now := time.Unix(1_950_000_000, 0).UTC()
	valid, _, _ := chain.receiptBlock(t, 1, "", now, 9, false, nil)
	mutations := map[string]func(*AuthenticatedBlock){
		"signature": func(block *AuthenticatedBlock) {
			block.Signature = append([]byte(nil), block.Signature...)
			block.Signature[0] ^= 1
		},
		"header": func(block *AuthenticatedBlock) {
			block.HeaderRLP = append([]byte(nil), block.HeaderRLP...)
			block.HeaderRLP[len(block.HeaderRLP)-1] ^= 1
		},
		"receipt": func(block *AuthenticatedBlock) {
			block.Receipts[0].ReceiptRLP = append(
				[]byte(nil), block.Receipts[0].ReceiptRLP...,
			)
			block.Receipts[0].ReceiptRLP[len(block.Receipts[0].ReceiptRLP)-1] ^= 1
		},
		"receipt proof": func(block *AuthenticatedBlock) {
			block.Receipts[0].ReceiptProofNodes = [][]byte{{0xc0}}
		},
		"transaction": func(block *AuthenticatedBlock) {
			block.Receipts[0].TransactionRLP = []byte{0xc0}
		},
		"transaction proof": func(block *AuthenticatedBlock) {
			block.Receipts[0].TransactionProofNodes = [][]byte{{0xc0}}
		},
		"transaction index": func(block *AuthenticatedBlock) {
			block.Receipts[0].TransactionIndex = 1
		},
		"oversize header": func(block *AuthenticatedBlock) {
			block.HeaderRLP = make([]byte, maxHeaderRLPBytes+1)
		},
		"oversize proof": func(block *AuthenticatedBlock) {
			block.Receipts[0].ReceiptProofNodes = [][]byte{
				make([]byte, maxProofNodeBytes+1),
			}
		},
		"too many receipts": func(block *AuthenticatedBlock) {
			block.Receipts = make(
				[]ReceiptInclusionProof,
				maxReceiptsPerBlock+1,
			)
		},
		"aggregate proof bytes": func(block *AuthenticatedBlock) {
			node := make([]byte, maxProofNodeBytes)
			block.Receipts = make(
				[]ReceiptInclusionProof,
				maxBlockProofBytes/maxProofBytes+1,
			)
			for receiptIndex := range block.Receipts {
				block.Receipts[receiptIndex].TransactionProofNodes = make(
					[][]byte,
					maxProofBytes/maxProofNodeBytes,
				)
				for proofIndex := range block.Receipts[receiptIndex].TransactionProofNodes {
					block.Receipts[receiptIndex].TransactionProofNodes[proofIndex] = node
				}
			}
		},
		"aggregate input bytes": func(block *AuthenticatedBlock) {
			transaction := make([]byte, maxTransactionBytes)
			receipt := make([]byte, maxReceiptBytes)
			count := maxBlockInputBytes/(maxTransactionBytes+maxReceiptBytes) + 1
			block.Receipts = make([]ReceiptInclusionProof, count)
			for index := range block.Receipts {
				block.Receipts[index].TransactionRLP = transaction
				block.Receipts[index].ReceiptRLP = receipt
			}
		},
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			indexer, err := NewGateway(chain.chainID, chain.gateway, 1, chain.public)
			if err != nil {
				t.Fatal(err)
			}
			invalid := copyAuthenticatedBlock(valid)
			mutate(&invalid)
			if err := indexer.IngestAuthenticated(invalid); err == nil {
				t.Fatal("fabricated/oversized evidence was accepted")
			}
			if indexer.Snapshot().Head != 0 {
				t.Fatal("invalid evidence mutated canonical state")
			}
		})
	}

	indexer, err := NewGateway(chain.chainID, chain.gateway, 1, chain.public)
	if err != nil {
		t.Fatal(err)
	}
	if err := indexer.Ingest(Block{
		Number: 1, Hash: testHash(1), ObservedAt: now,
	}); !errors.Is(err, ErrUnauthenticatedBlock) {
		t.Fatalf("gateway accepted synthetic block: %v", err)
	}
}

func TestFinalityPolicySeparatesHeaderAuthorities(t *testing.T) {
	first := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x51)
	second := newAuthenticatedTestChain(31_337, testAddress(0x11), 0x52)
	firstHash := first.policyHash(t, 2)
	secondHash := second.policyHash(t, 2)
	if firstHash == secondHash || !canonicalHash(firstHash) || !canonicalHash(secondHash) {
		t.Fatalf("authority was not bound into finality policy: %s %s", firstHash, secondHash)
	}
}

func TestRLPDepthLimitRejectsNestedPayload(t *testing.T) {
	nested := []byte{0x80}
	for index := 0; index < maxRLPDepth+2; index++ {
		nested = testRLPList(nested)
	}
	if _, _, err := decodeRLP(nested); err == nil {
		t.Fatal("deeply nested RLP was accepted")
	}
}

func copyAuthenticatedBlock(source AuthenticatedBlock) AuthenticatedBlock {
	result := source
	result.HeaderRLP = append([]byte(nil), source.HeaderRLP...)
	result.Signature = append([]byte(nil), source.Signature...)
	result.Receipts = append([]ReceiptInclusionProof(nil), source.Receipts...)
	for index := range result.Receipts {
		result.Receipts[index].TransactionRLP = append(
			[]byte(nil), source.Receipts[index].TransactionRLP...,
		)
		result.Receipts[index].ReceiptRLP = append(
			[]byte(nil), source.Receipts[index].ReceiptRLP...,
		)
		result.Receipts[index].TransactionProofNodes = copyByteSlices(
			source.Receipts[index].TransactionProofNodes,
		)
		result.Receipts[index].ReceiptProofNodes = copyByteSlices(
			source.Receipts[index].ReceiptProofNodes,
		)
	}
	return result
}

func copyByteSlices(source [][]byte) [][]byte {
	result := make([][]byte, len(source))
	for index := range source {
		result[index] = append([]byte(nil), source[index]...)
	}
	return result
}

func testReceiptRLP(succeeded bool, logs []receiptLog) []byte {
	status := []byte{}
	if succeeded {
		status = []byte{1}
	}
	encodedLogs := make([][]byte, 0, len(logs))
	for _, log := range logs {
		address, _ := hex.DecodeString(log.address[2:])
		topics := make([][]byte, 0, len(log.topics))
		for _, topic := range log.topics {
			decoded, _ := hex.DecodeString(topic[2:])
			topics = append(topics, testRLPBytes(decoded))
		}
		encodedLogs = append(encodedLogs, testRLPList(
			testRLPBytes(address), testRLPList(topics...), testRLPBytes(log.data),
		))
	}
	return testRLPList(
		testRLPBytes(status),
		testRLPUint(21_000),
		testRLPBytes(make([]byte, 256)),
		testRLPList(encodedLogs...),
	)
}

func testTrieLeaf(key, value []byte) []byte {
	nibbles := bytesToNibbles(key)
	if len(nibbles)%2 == 0 {
		nibbles = append([]byte{2, 0}, nibbles...)
	} else {
		nibbles = append([]byte{3}, nibbles...)
	}
	compact := make([]byte, (len(nibbles)+1)/2)
	for index := range compact {
		compact[index] = nibbles[index*2] << 4
		if index*2+1 < len(nibbles) {
			compact[index] |= nibbles[index*2+1]
		}
	}
	return testRLPList(testRLPBytes(compact), testRLPBytes(value))
}

func testRLPUint(value uint64) []byte {
	if value == 0 {
		return []byte{0x80}
	}
	var encoded [8]byte
	binary.BigEndian.PutUint64(encoded[:], value)
	first := 0
	for encoded[first] == 0 {
		first++
	}
	return testRLPBytes(encoded[first:])
}

func testRLPBytes(value []byte) []byte {
	if len(value) == 1 && value[0] < 0x80 {
		return append([]byte(nil), value...)
	}
	if len(value) < 56 {
		return append([]byte{0x80 + byte(len(value))}, value...)
	}
	length := testLength(len(value))
	result := []byte{0xb7 + byte(len(length))}
	result = append(result, length...)
	return append(result, value...)
}

func testRLPList(values ...[]byte) []byte {
	var payload []byte
	for _, value := range values {
		payload = append(payload, value...)
	}
	if len(payload) < 56 {
		return append([]byte{0xc0 + byte(len(payload))}, payload...)
	}
	length := testLength(len(payload))
	result := []byte{0xf7 + byte(len(length))}
	result = append(result, length...)
	return append(result, payload...)
}

func testLength(length int) []byte {
	var encoded [8]byte
	binary.BigEndian.PutUint64(encoded[:], uint64(length))
	first := 0
	for encoded[first] == 0 {
		first++
	}
	return encoded[first:]
}

func mustHex(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(value)
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}

func mustHexProof(t *testing.T, values ...string) [][]byte {
	t.Helper()
	result := make([][]byte, len(values))
	for index, value := range values {
		result[index] = mustHex(t, value)
	}
	return result
}
