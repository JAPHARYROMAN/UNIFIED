// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { RiskTypes } from "./RiskTypes.sol";

/// @notice Deterministic schedule generation with all division remainder in the final item.
contract ScheduleEngine {
    error InvalidSchedule();

    function generate(RiskTypes.SchedulePlan calldata plan)
        external
        pure
        returns (RiskTypes.Installment[] memory installments)
    {
        _validate(plan);
        installments = new RiskTypes.Installment[](plan.installmentCount);
        uint256 allocatedPrincipal;
        uint256 allocatedInterest;
        uint256 annuity = plan.kind == RiskTypes.ScheduleKind.ANNUITY
            ? annuityPayment(plan.principal, plan.periodicRateRay, plan.installmentCount)
            : 0;
        uint256 balance = plan.principal;

        for (uint32 index = 0; index < plan.installmentCount; ++index) {
            (uint256 principalDue, uint256 interestDue) = _amounts(plan, index, balance, annuity);
            if (index + 1 == plan.installmentCount) {
                principalDue = plan.principal - allocatedPrincipal;
                if (plan.kind != RiskTypes.ScheduleKind.ANNUITY) {
                    interestDue = plan.totalInterest - allocatedInterest;
                }
            }
            allocatedPrincipal += principalDue;
            allocatedInterest += interestDue;
            balance -= principalDue;
            installments[index] = RiskTypes.Installment({
                index: index,
                dueTime: plan.startTime + uint64(index + 1 + plan.paymentHolidayCount)
                    * plan.periodSeconds,
                principalDue: principalDue,
                interestDue: interestDue,
                state: RiskTypes.InstallmentState.SCHEDULED
            });
        }
        if (allocatedPrincipal != plan.principal) revert InvalidSchedule();
    }

    function custom(
        uint64[] calldata dueTimes,
        uint256[] calldata principalAmounts,
        uint256[] calldata interestAmounts,
        uint256 expectedPrincipal
    ) external pure returns (RiskTypes.Installment[] memory installments) {
        if (
            dueTimes.length == 0 || dueTimes.length != principalAmounts.length
                || dueTimes.length != interestAmounts.length
        ) {
            revert InvalidSchedule();
        }
        installments = new RiskTypes.Installment[](dueTimes.length);
        uint256 totalPrincipal;
        uint64 priorDue;
        for (uint32 index = 0; index < dueTimes.length; ++index) {
            if (dueTimes[index] <= priorDue) revert InvalidSchedule();
            priorDue = dueTimes[index];
            totalPrincipal += principalAmounts[index];
            installments[index] = RiskTypes.Installment({
                index: index,
                dueTime: dueTimes[index],
                principalDue: principalAmounts[index],
                interestDue: interestAmounts[index],
                state: RiskTypes.InstallmentState.SCHEDULED
            });
        }
        if (totalPrincipal != expectedPrincipal) revert InvalidSchedule();
    }

    function annuityPayment(uint256 principal, uint256 periodicRateRay, uint32 periods)
        public
        pure
        returns (uint256)
    {
        if (principal == 0 || periodicRateRay == 0 || periods == 0 || periods > 600) {
            revert InvalidSchedule();
        }
        uint256 factor = _rpow(RiskTypes.RAY + periodicRateRay, periods);
        uint256 numerator = Math.mulDiv(principal, periodicRateRay, RiskTypes.RAY);
        return Math.mulDiv(numerator, factor, factor - RiskTypes.RAY);
    }

    function _amounts(
        RiskTypes.SchedulePlan calldata plan,
        uint32 index,
        uint256 balance,
        uint256 annuity
    ) private pure returns (uint256 principalDue, uint256 interestDue) {
        uint256 count = plan.installmentCount;
        if (plan.kind == RiskTypes.ScheduleKind.BULLET) {
            principalDue = index + 1 == count ? plan.principal : 0;
            interestDue = index + 1 == count ? plan.totalInterest : 0;
        } else if (plan.kind == RiskTypes.ScheduleKind.EQUAL_PRINCIPAL) {
            principalDue = plan.principal / count;
            interestDue = plan.totalInterest / count;
        } else if (plan.kind == RiskTypes.ScheduleKind.INTEREST_ONLY) {
            principalDue = index + 1 == count ? plan.principal : 0;
            interestDue = plan.totalInterest / count;
        } else if (plan.kind == RiskTypes.ScheduleKind.BALLOON) {
            if (index + 1 == count) {
                principalDue = plan.balloonPrincipal;
            } else {
                principalDue = (plan.principal - plan.balloonPrincipal) / (count - 1);
            }
            interestDue = plan.totalInterest / count;
        } else if (plan.kind == RiskTypes.ScheduleKind.ANNUITY) {
            interestDue = Math.mulDiv(balance, plan.periodicRateRay, RiskTypes.RAY);
            principalDue = annuity > interestDue ? annuity - interestDue : 0;
            if (principalDue > balance) principalDue = balance;
        } else {
            revert InvalidSchedule();
        }
    }

    function _validate(RiskTypes.SchedulePlan calldata plan) private pure {
        if (
            plan.kind == RiskTypes.ScheduleKind.NONE || plan.kind == RiskTypes.ScheduleKind.CUSTOM
                || plan.principal == 0 || plan.startTime == 0 || plan.periodSeconds == 0
                || plan.installmentCount == 0 || plan.installmentCount > 600
                || plan.paymentHolidayCount > 120
                || (plan.kind == RiskTypes.ScheduleKind.BALLOON
                    && (plan.installmentCount < 2
                        || plan.balloonPrincipal == 0
                        || plan.balloonPrincipal >= plan.principal))
                || (plan.kind != RiskTypes.ScheduleKind.BALLOON && plan.balloonPrincipal != 0)
                || (plan.kind == RiskTypes.ScheduleKind.ANNUITY && plan.periodicRateRay == 0)
                || (plan.kind == RiskTypes.ScheduleKind.ANNUITY && plan.totalInterest != 0)
                || (plan.kind != RiskTypes.ScheduleKind.ANNUITY && plan.periodicRateRay != 0)
        ) {
            revert InvalidSchedule();
        }
    }

    function _rpow(uint256 baseRay, uint32 exponent) private pure returns (uint256 result) {
        result = RiskTypes.RAY;
        uint256 base = baseRay;
        uint32 power = exponent;
        while (power != 0) {
            if (power & 1 != 0) result = Math.mulDiv(result, base, RiskTypes.RAY);
            power >>= 1;
            if (power != 0) base = Math.mulDiv(base, base, RiskTypes.RAY);
        }
    }
}
