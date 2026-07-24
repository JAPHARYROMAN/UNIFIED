package calculation

import "testing"

func TestInterestMatchesCanonicalSolidityVectors(t *testing.T) {
	fixed, err := AccrueFixed(
		"1000000000000000000000",
		1_800_000_000,
		1_800_000_000+YearSeconds,
		InterestTerms{
			AnnualRateRay: "100000000000000000000000000",
			SpreadRay:     "0",
			FloorRateRay:  "0",
			CapRateRay:    "10000000000000000000000000000",
		},
	)
	if err != nil {
		t.Fatalf("fixed accrual: %v", err)
	}
	if fixed != "100000000000000000000" {
		t.Fatalf("fixed vector mismatch: %s", fixed)
	}

	variable, applied, err := AccrueVariable(
		"1000000000000000000000",
		1_800_000_000,
		1_800_000_000+YearSeconds,
		"50000000000000000000000000",
		1_800_000_000+YearSeconds-3600,
		InterestTerms{
			AnnualRateRay:       "0",
			SpreadRay:           "20000000000000000000000000",
			FloorRateRay:        "40000000000000000000000000",
			CapRateRay:          "60000000000000000000000000",
			MaximumBenchmarkAge: 3600,
		},
	)
	if err != nil {
		t.Fatalf("variable accrual: %v", err)
	}
	if applied != "60000000000000000000000000" ||
		variable != "60000000000000000000" {
		t.Fatalf("variable vector mismatch: rate=%s interest=%s", applied, variable)
	}
}

func TestScheduleMatchesCanonicalSolidityRemainderVector(t *testing.T) {
	installments, err := Generate(SchedulePlan{
		Kind: EqualPrincipal, Principal: "1000", TotalInterest: "101",
		PeriodicRateRay: "0", BalloonPrincipal: "0", StartTime: 1_800_000_000,
		PeriodSeconds: 30 * 24 * 60 * 60, InstallmentCount: 3, PaymentHolidayCount: 1,
	})
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	if installments[0].PrincipalDue != "333" || installments[1].PrincipalDue != "333" ||
		installments[2].PrincipalDue != "334" {
		t.Fatalf("principal vector mismatch: %#v", installments)
	}
	if installments[0].InterestDue != "33" || installments[2].InterestDue != "35" {
		t.Fatalf("interest vector mismatch: %#v", installments)
	}
	if installments[0].DueTime != 1_800_000_000+60*24*60*60 {
		t.Fatal("holiday due date mismatch")
	}
}

func TestStaleBenchmarkIsRejected(t *testing.T) {
	_, _, err := AccrueVariable(
		"1000",
		1_800_000_000,
		1_800_007_200,
		"20000000000000000000000000",
		1_800_000_000,
		InterestTerms{
			AnnualRateRay:       "0",
			SpreadRay:           "10000000000000000000000000",
			FloorRateRay:        "10000000000000000000000000",
			CapRateRay:          "50000000000000000000000000",
			MaximumBenchmarkAge: 3600,
		},
	)
	if err != ErrInvalidCalculation {
		t.Fatalf("expected stale benchmark rejection, got %v", err)
	}
}

func TestAnnuityConservesPrincipal(t *testing.T) {
	installments, err := Generate(SchedulePlan{
		Kind: Annuity, Principal: "1000000", TotalInterest: "0",
		PeriodicRateRay: "10000000000000000000000000", BalloonPrincipal: "0",
		StartTime: 1_800_000_000, PeriodSeconds: 30 * 24 * 60 * 60, InstallmentCount: 12,
	})
	if err != nil {
		t.Fatalf("generate annuity: %v", err)
	}
	total := mustInteger("0")
	for _, installment := range installments {
		value, _ := positiveInteger(installment.PrincipalDue)
		total.Add(total, value)
	}
	if total.String() != "1000000" {
		t.Fatalf("annuity principal mismatch: %s", total)
	}
}
