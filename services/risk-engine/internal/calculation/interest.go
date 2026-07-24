package calculation

import (
	"errors"
	"math/big"
)

const YearSeconds uint64 = 365 * 24 * 60 * 60

var (
	ErrInvalidCalculation = errors.New("invalid deterministic calculation")
	ray                   = mustInteger("1000000000000000000000000000")
	maxAnnualRateRay      = mustInteger("10000000000000000000000000000")
)

type InterestTerms struct {
	AnnualRateRay       string
	SpreadRay           string
	FloorRateRay        string
	CapRateRay          string
	MaximumBenchmarkAge uint64
}

func AccrueFixed(
	principal string,
	from uint64,
	to uint64,
	terms InterestTerms,
) (string, error) {
	principalUnits, ok := positiveInteger(principal)
	if !ok || to < from {
		return "", ErrInvalidCalculation
	}
	rate, ok := nonNegativeInteger(terms.AnnualRateRay)
	floor, floorOK := nonNegativeInteger(terms.FloorRateRay)
	capRate, capOK := positiveInteger(terms.CapRateRay)
	if !ok || !floorOK || !capOK || rate.Cmp(maxAnnualRateRay) > 0 ||
		terms.SpreadRay != "0" || terms.MaximumBenchmarkAge != 0 ||
		floor.Cmp(rate) > 0 || rate.Cmp(capRate) > 0 {
		return "", ErrInvalidCalculation
	}
	return accrue(principalUnits, rate, to-from).String(), nil
}

func AccrueVariable(
	principal string,
	from uint64,
	to uint64,
	benchmarkRateRay string,
	benchmarkObservedAt uint64,
	terms InterestTerms,
) (interest string, appliedRateRay string, err error) {
	principalUnits, ok := positiveInteger(principal)
	if !ok || to < from || terms.AnnualRateRay != "0" || terms.MaximumBenchmarkAge == 0 ||
		benchmarkObservedAt > to || to-benchmarkObservedAt > terms.MaximumBenchmarkAge {
		return "", "", ErrInvalidCalculation
	}
	rate, err := BoundedRate(benchmarkRateRay, terms)
	if err != nil {
		return "", "", err
	}
	return accrue(principalUnits, rate, to-from).String(), rate.String(), nil
}

func BoundedRate(benchmarkRateRay string, terms InterestTerms) (*big.Int, error) {
	benchmark, benchmarkOK := nonNegativeInteger(benchmarkRateRay)
	spread, spreadOK := nonNegativeInteger(terms.SpreadRay)
	floor, floorOK := nonNegativeInteger(terms.FloorRateRay)
	capRate, capOK := positiveInteger(terms.CapRateRay)
	if !benchmarkOK || !spreadOK || !floorOK || !capOK ||
		floor.Cmp(capRate) > 0 || capRate.Cmp(maxAnnualRateRay) > 0 {
		return nil, ErrInvalidCalculation
	}
	rate := new(big.Int).Add(benchmark, spread)
	if rate.Cmp(floor) < 0 {
		rate.Set(floor)
	}
	if rate.Cmp(capRate) > 0 {
		rate.Set(capRate)
	}
	return rate, nil
}

func accrue(principal *big.Int, annualRateRay *big.Int, elapsed uint64) *big.Int {
	annualInterest := mulDiv(principal, annualRateRay, ray)
	return mulDiv(annualInterest, new(big.Int).SetUint64(elapsed), new(big.Int).SetUint64(YearSeconds))
}

func mulDiv(left *big.Int, right *big.Int, denominator *big.Int) *big.Int {
	product := new(big.Int).Mul(left, right)
	return product.Quo(product, denominator)
}

func positiveInteger(value string) (*big.Int, bool) {
	integer, ok := nonNegativeInteger(value)
	return integer, ok && integer.Sign() > 0
}

func nonNegativeInteger(value string) (*big.Int, bool) {
	integer, ok := new(big.Int).SetString(value, 10)
	return integer, ok && integer.Sign() >= 0 && integer.String() == value
}

func mustInteger(value string) *big.Int {
	integer, ok := new(big.Int).SetString(value, 10)
	if !ok {
		panic("invalid integer constant")
	}
	return integer
}
