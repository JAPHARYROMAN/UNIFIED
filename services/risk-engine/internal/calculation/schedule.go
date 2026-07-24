package calculation

import "math/big"

type ScheduleKind string

const (
	Bullet         ScheduleKind = "BULLET"
	EqualPrincipal ScheduleKind = "EQUAL_PRINCIPAL"
	Annuity        ScheduleKind = "ANNUITY"
	InterestOnly   ScheduleKind = "INTEREST_ONLY"
	Balloon        ScheduleKind = "BALLOON"
)

type SchedulePlan struct {
	Kind                ScheduleKind
	Principal           string
	TotalInterest       string
	PeriodicRateRay     string
	BalloonPrincipal    string
	StartTime           uint64
	PeriodSeconds       uint64
	InstallmentCount    uint32
	PaymentHolidayCount uint32
}

type Installment struct {
	Index        uint32
	DueTime      uint64
	PrincipalDue string
	InterestDue  string
}

func Generate(plan SchedulePlan) ([]Installment, error) {
	principal, totalInterest, balloon, periodicRate, err := validateSchedule(plan)
	if err != nil {
		return nil, err
	}
	installments := make([]Installment, plan.InstallmentCount)
	allocatedPrincipal := new(big.Int)
	allocatedInterest := new(big.Int)
	balance := new(big.Int).Set(principal)
	annuity := new(big.Int)
	if plan.Kind == Annuity {
		annuity = annuityPayment(principal, periodicRate, plan.InstallmentCount)
	}
	count := new(big.Int).SetUint64(uint64(plan.InstallmentCount))

	for index := uint32(0); index < plan.InstallmentCount; index++ {
		principalDue := new(big.Int)
		interestDue := new(big.Int)
		last := index+1 == plan.InstallmentCount
		switch plan.Kind {
		case Bullet:
			if last {
				principalDue.Set(principal)
				interestDue.Set(totalInterest)
			}
		case EqualPrincipal:
			principalDue.Quo(principal, count)
			interestDue.Quo(totalInterest, count)
		case InterestOnly:
			if last {
				principalDue.Set(principal)
			}
			interestDue.Quo(totalInterest, count)
		case Balloon:
			if last {
				principalDue.Set(balloon)
			} else {
				nonBalloon := new(big.Int).Sub(principal, balloon)
				principalDue.Quo(nonBalloon, new(big.Int).Sub(count, big.NewInt(1)))
			}
			interestDue.Quo(totalInterest, count)
		case Annuity:
			interestDue = mulDiv(balance, periodicRate, ray)
			if annuity.Cmp(interestDue) > 0 {
				principalDue.Sub(annuity, interestDue)
			}
			if principalDue.Cmp(balance) > 0 {
				principalDue.Set(balance)
			}
		default:
			return nil, ErrInvalidCalculation
		}
		if last {
			principalDue.Sub(principal, allocatedPrincipal)
			if plan.Kind != Annuity {
				interestDue.Sub(totalInterest, allocatedInterest)
			}
		}
		allocatedPrincipal.Add(allocatedPrincipal, principalDue)
		allocatedInterest.Add(allocatedInterest, interestDue)
		balance.Sub(balance, principalDue)
		installments[index] = Installment{
			Index: index,
			DueTime: plan.StartTime +
				uint64(index+1+plan.PaymentHolidayCount)*plan.PeriodSeconds,
			PrincipalDue: principalDue.String(),
			InterestDue:  interestDue.String(),
		}
	}
	if allocatedPrincipal.Cmp(principal) != 0 {
		return nil, ErrInvalidCalculation
	}
	return installments, nil
}

func validateSchedule(
	plan SchedulePlan,
) (principal *big.Int, totalInterest *big.Int, balloon *big.Int, periodicRate *big.Int, err error) {
	principal, principalOK := positiveInteger(plan.Principal)
	totalInterest, interestOK := nonNegativeInteger(plan.TotalInterest)
	balloon, balloonOK := nonNegativeInteger(plan.BalloonPrincipal)
	periodicRate, periodicOK := nonNegativeInteger(plan.PeriodicRateRay)
	if !principalOK || !interestOK || !balloonOK || !periodicOK ||
		plan.StartTime == 0 || plan.PeriodSeconds == 0 || plan.InstallmentCount == 0 ||
		plan.InstallmentCount > 600 || plan.PaymentHolidayCount > 120 {
		return nil, nil, nil, nil, ErrInvalidCalculation
	}
	if plan.Kind == Balloon {
		if plan.InstallmentCount < 2 || balloon.Sign() == 0 || balloon.Cmp(principal) >= 0 {
			return nil, nil, nil, nil, ErrInvalidCalculation
		}
	} else if balloon.Sign() != 0 {
		return nil, nil, nil, nil, ErrInvalidCalculation
	}
	if plan.Kind == Annuity {
		if periodicRate.Sign() == 0 || totalInterest.Sign() != 0 {
			return nil, nil, nil, nil, ErrInvalidCalculation
		}
	} else if periodicRate.Sign() != 0 {
		return nil, nil, nil, nil, ErrInvalidCalculation
	}
	return principal, totalInterest, balloon, periodicRate, nil
}

func annuityPayment(principal *big.Int, periodicRateRay *big.Int, periods uint32) *big.Int {
	factor := rayPower(new(big.Int).Add(ray, periodicRateRay), periods)
	numerator := mulDiv(principal, periodicRateRay, ray)
	return mulDiv(numerator, factor, new(big.Int).Sub(factor, ray))
}

func rayPower(baseRay *big.Int, exponent uint32) *big.Int {
	result := new(big.Int).Set(ray)
	base := new(big.Int).Set(baseRay)
	power := exponent
	for power != 0 {
		if power&1 != 0 {
			result = mulDiv(result, base, ray)
		}
		power >>= 1
		if power != 0 {
			base = mulDiv(base, base, ray)
		}
	}
	return result
}
