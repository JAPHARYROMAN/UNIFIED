// Package crosschainreconciliation reconciles finalized chain control totals
// against immutable ledger postings.
package crosschainreconciliation

import (
	"errors"
	"math/big"
	"time"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

type Expected struct {
	AssetID      string
	AccountCode  string
	DebitUnits   string
	CreditUnits  string
	MessageCount uint64
	AsOf         time.Time
}

type Difference struct {
	AssetID     string
	AccountCode string
	Side        ledger.Side
	Metric      string
	Expected    string
	Observed    string
	Owner       string
	DetectedAt  time.Time
	Deadline    time.Time
}

func Compare(
	postings []ledger.PostedJournal,
	expected Expected,
	owner string,
	deadline time.Time,
) ([]Difference, error) {
	return CompareMany(postings, []Expected{expected}, owner, deadline)
}

// CompareMany evaluates every account/asset boundary from one immutable
// posting snapshot. A source event is counted once per boundary even when it
// produced more than one journal or matching entry.
func CompareMany(
	postings []ledger.PostedJournal,
	expected []Expected,
	owner string,
	deadline time.Time,
) ([]Difference, error) {
	if len(expected) == 0 || owner == "" {
		return nil, errors.New("invalid reconciliation boundary")
	}
	seenBoundaries := make(map[string]struct{}, len(expected))
	var differences []Difference
	for _, boundary := range expected {
		if boundary.AssetID == "" || boundary.AccountCode == "" ||
			boundary.AsOf.IsZero() || !deadline.After(boundary.AsOf) {
			return nil, errors.New("invalid reconciliation boundary")
		}
		key := boundary.AssetID + "\x00" + boundary.AccountCode
		if _, duplicate := seenBoundaries[key]; duplicate {
			return nil, errors.New("duplicate reconciliation boundary")
		}
		seenBoundaries[key] = struct{}{}
		boundaryDifferences, err := compareBoundary(postings, boundary, owner, deadline)
		if err != nil {
			return nil, err
		}
		differences = append(differences, boundaryDifferences...)
	}
	return differences, nil
}

func compareBoundary(
	postings []ledger.PostedJournal,
	expected Expected,
	owner string,
	deadline time.Time,
) ([]Difference, error) {
	expectedDebit, err := units(expected.DebitUnits)
	if err != nil {
		return nil, err
	}
	expectedCredit, err := units(expected.CreditUnits)
	if err != nil {
		return nil, err
	}
	observedDebit := new(big.Int)
	observedCredit := new(big.Int)
	messageIDs := make(map[string]struct{})
	for _, posting := range postings {
		if posting.EffectiveAt.After(expected.AsOf) {
			continue
		}
		matched := false
		for _, entry := range posting.Entries {
			if entry.AssetID != expected.AssetID || entry.AccountCode != expected.AccountCode {
				continue
			}
			value, err := units(entry.Units)
			if err != nil {
				return nil, err
			}
			switch entry.Side {
			case ledger.Debit:
				observedDebit.Add(observedDebit, value)
			case ledger.Credit:
				observedCredit.Add(observedCredit, value)
			default:
				return nil, errors.New("unknown ledger side in reconciliation snapshot")
			}
			matched = true
		}
		if matched {
			if posting.SourceEventID == "" {
				return nil, errors.New("matching journal lacks canonical source event")
			}
			messageIDs[posting.SourceEventID] = struct{}{}
		}
	}
	var differences []Difference
	add := func(metric string, side ledger.Side, wanted, observed string) {
		if wanted == observed {
			return
		}
		differences = append(differences, Difference{
			AssetID: expected.AssetID, AccountCode: expected.AccountCode,
			Side: side, Metric: metric, Expected: wanted, Observed: observed,
			Owner: owner, DetectedAt: expected.AsOf, Deadline: deadline,
		})
	}
	add("DEBIT_UNITS", ledger.Debit, expectedDebit.String(), observedDebit.String())
	add("CREDIT_UNITS", ledger.Credit, expectedCredit.String(), observedCredit.String())
	add(
		"MESSAGE_COUNT",
		"",
		new(big.Int).SetUint64(expected.MessageCount).String(),
		new(big.Int).SetUint64(uint64(len(messageIDs))).String(),
	)
	return differences, nil
}

func units(value string) (*big.Int, error) {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() < 0 || number.String() != value {
		return nil, errors.New("units must be a canonical nonnegative integer")
	}
	return number, nil
}
