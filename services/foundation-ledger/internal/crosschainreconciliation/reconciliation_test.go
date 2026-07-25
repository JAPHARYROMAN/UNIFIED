package crosschainreconciliation

import (
	"testing"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/crosschainaccounting"
	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

func TestCompareLeavesMismatchVisibleAndOwned(t *testing.T) {
	asOf := time.Unix(1_700_000_000, 0).UTC()
	postings := []ledger.PostedJournal{{
		Journal: ledger.Journal{
			SourceEventID: "message:1", EffectiveAt: asOf,
			Entries: []ledger.Entry{{
				AccountCode: "1410", Side: ledger.Debit,
				AssetID: "asset:local:uft", Units: "99",
			}},
		},
	}}
	differences, err := Compare(postings, Expected{
		AssetID: "asset:local:uft", AccountCode: "1410",
		DebitUnits: "100", CreditUnits: "0", MessageCount: 1, AsOf: asOf,
	}, "accounting-risk", asOf.Add(time.Hour))
	if err != nil {
		t.Fatalf("compare: %v", err)
	}
	if len(differences) != 1 || differences[0].Owner != "accounting-risk" ||
		differences[0].Observed != "99" || differences[0].Expected != "100" {
		t.Fatalf("difference was not exact and owned: %#v", differences)
	}
}

func TestCompareManyChecksEveryDimensionAndDistinctMessageCount(t *testing.T) {
	asOf := time.Unix(1_700_000_000, 0).UTC()
	postings := []ledger.PostedJournal{
		{
			Journal: ledger.Journal{
				SourceEventID: "message:1", EffectiveAt: asOf.Add(-time.Minute),
				Entries: []ledger.Entry{
					{
						AccountCode: "1410", Side: ledger.Debit,
						AssetID: "asset:local:uft", Units: "100",
					},
					{
						AccountCode: "2230", Side: ledger.Credit,
						AssetID: "asset:local:uft", Units: "100",
					},
				},
			},
		},
		{
			Journal: ledger.Journal{
				SourceEventID: "message:future", EffectiveAt: asOf.Add(time.Minute),
				Entries: []ledger.Entry{{
					AccountCode: "1410", Side: ledger.Debit,
					AssetID: "asset:local:uft", Units: "1",
				}},
			},
		},
	}
	exact := []Expected{
		{
			AssetID: "asset:local:uft", AccountCode: "1410",
			DebitUnits: "100", CreditUnits: "0", MessageCount: 1, AsOf: asOf,
		},
		{
			AssetID: "asset:local:uft", AccountCode: "2230",
			DebitUnits: "0", CreditUnits: "100", MessageCount: 1, AsOf: asOf,
		},
	}
	if differences, err := CompareMany(
		postings,
		exact,
		"accounting-risk",
		asOf.Add(time.Hour),
	); err != nil || len(differences) != 0 {
		t.Fatalf("exact multi-dimensional snapshot differed: %#v %v", differences, err)
	}

	mismatched := append([]Expected(nil), exact...)
	mismatched[0].MessageCount = 2
	mismatched[1].CreditUnits = "99"
	differences, err := CompareMany(
		postings,
		mismatched,
		"accounting-risk",
		asOf.Add(time.Hour),
	)
	if err != nil || len(differences) != 2 {
		t.Fatalf("multi-dimensional differences were lost: %#v %v", differences, err)
	}
	metrics := map[string]bool{}
	for _, difference := range differences {
		metrics[difference.Metric] = true
	}
	if !metrics["MESSAGE_COUNT"] || !metrics["CREDIT_UNITS"] {
		t.Fatalf("wrong multi-dimensional difference set: %#v", differences)
	}
}

func TestCompareRejectsNoncanonicalAndDuplicateBoundaries(t *testing.T) {
	asOf := time.Unix(1_700_000_000, 0).UTC()
	expected := Expected{
		AssetID: "asset:local:uft", AccountCode: "1410",
		DebitUnits: "001", CreditUnits: "0", AsOf: asOf,
	}
	if _, err := Compare(nil, expected, "accounting-risk", asOf.Add(time.Hour)); err == nil {
		t.Fatal("noncanonical expected units were accepted")
	}
	expected.DebitUnits = "0"
	if _, err := CompareMany(
		nil,
		[]Expected{expected, expected},
		"accounting-risk",
		asOf.Add(time.Hour),
	); err == nil {
		t.Fatal("duplicate reconciliation boundaries were accepted")
	}
}

func TestRecoveredWrappedBurnReconcilesToRestoredSupplyAndUnchangedBacking(t *testing.T) {
	asOf := time.Unix(1_700_000_000, 0).UTC()
	const (
		canonicalAsset = "asset:local:uft"
		wrappedAsset   = "asset:local:wuft"
	)
	postings := []ledger.PostedJournal{
		{
			Journal: ledger.Journal{
				SourceEventID: "message:burn",
				EffectiveAt:   asOf.Add(-time.Minute),
				EvidenceHash:  "evidence:burn",
				Entries: []ledger.Entry{
					{
						AccountCode: crosschainaccounting.AccountWrappedUFTOutstandingControl,
						Side:        ledger.Debit,
						AssetID:     wrappedAsset,
						Units:       "100",
					},
					{
						AccountCode: crosschainaccounting.AccountPendingCrossChainSettlement,
						Side:        ledger.Credit,
						AssetID:     wrappedAsset,
						Units:       "100",
					},
				},
			},
		},
		{
			Journal: ledger.Journal{
				SourceEventID: "message:burn-recovery",
				EffectiveAt:   asOf,
				EvidenceHash:  "evidence:recovery:distinct",
				Entries: []ledger.Entry{
					{
						AccountCode: crosschainaccounting.AccountPendingCrossChainSettlement,
						Side:        ledger.Debit,
						AssetID:     wrappedAsset,
						Units:       "100",
					},
					{
						AccountCode: crosschainaccounting.AccountWrappedUFTOutstandingControl,
						Side:        ledger.Credit,
						AssetID:     wrappedAsset,
						Units:       "100",
					},
				},
			},
		},
	}
	expected := []Expected{
		{
			AssetID:     wrappedAsset,
			AccountCode: crosschainaccounting.AccountWrappedUFTOutstandingControl,
			DebitUnits:  "100", CreditUnits: "100", MessageCount: 2, AsOf: asOf,
		},
		{
			AssetID:     wrappedAsset,
			AccountCode: crosschainaccounting.AccountPendingCrossChainSettlement,
			DebitUnits:  "100", CreditUnits: "100", MessageCount: 2, AsOf: asOf,
		},
	}
	for _, account := range []string{
		crosschainaccounting.AccountCanonicalAssetsLocked,
		crosschainaccounting.AccountBridgeBackingLiability,
		crosschainaccounting.AccountUFTBridgeEscrowControl,
		crosschainaccounting.AccountPrincipalReceivable,
		crosschainaccounting.AccountLenderPrincipalClaims,
	} {
		expected = append(expected, Expected{
			AssetID: canonicalAsset, AccountCode: account,
			DebitUnits: "0", CreditUnits: "0", MessageCount: 0, AsOf: asOf,
		})
	}
	if differences, err := CompareMany(
		postings,
		expected,
		"accounting-risk",
		asOf.Add(time.Hour),
	); err != nil || len(differences) != 0 {
		t.Fatalf("recovered burn did not reconcile exactly: %#v %v", differences, err)
	}
}
