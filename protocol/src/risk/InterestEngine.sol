// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { RiskTypes } from "./RiskTypes.sol";

/// @notice Deterministic actual/365 simple-interest calculations rounded down.
contract InterestEngine {
    error InvalidInterestTerms();
    error StaleBenchmark();

    uint256 public constant YEAR_SECONDS = 365 days;
    uint256 public constant MAX_ANNUAL_RATE_RAY = 10e27;

    function boundedRate(uint256 benchmarkRateRay, RiskTypes.InterestTerms calldata terms)
        public
        pure
        returns (uint256 annualRateRay)
    {
        if (
            terms.capRateRay == 0 || terms.floorRateRay > terms.capRateRay
                || terms.capRateRay > MAX_ANNUAL_RATE_RAY
        ) {
            revert InvalidInterestTerms();
        }
        annualRateRay = benchmarkRateRay + terms.spreadRay;
        if (annualRateRay < terms.floorRateRay) annualRateRay = terms.floorRateRay;
        if (annualRateRay > terms.capRateRay) annualRateRay = terms.capRateRay;
    }

    function accrueFixed(
        uint256 principal,
        uint64 from,
        uint64 to,
        RiskTypes.InterestTerms calldata terms
    ) external pure returns (uint256) {
        if (
            principal == 0 || to < from || terms.annualRateRay > MAX_ANNUAL_RATE_RAY
                || terms.spreadRay != 0 || terms.maximumBenchmarkAge != 0 || terms.capRateRay == 0
                || terms.floorRateRay > terms.annualRateRay
                || terms.annualRateRay > terms.capRateRay
        ) {
            revert InvalidInterestTerms();
        }
        return _accrue(principal, terms.annualRateRay, to - from);
    }

    function accrueVariable(
        uint256 principal,
        uint64 from,
        uint64 to,
        uint256 benchmarkRateRay,
        uint64 benchmarkObservedAt,
        RiskTypes.InterestTerms calldata terms
    ) external pure returns (uint256 interest, uint256 appliedRateRay) {
        if (principal == 0 || to < from || terms.annualRateRay != 0) {
            revert InvalidInterestTerms();
        }
        if (
            terms.maximumBenchmarkAge == 0 || benchmarkObservedAt > to
                || uint256(benchmarkObservedAt) + terms.maximumBenchmarkAge < to
        ) {
            revert StaleBenchmark();
        }
        appliedRateRay = boundedRate(benchmarkRateRay, terms);
        interest = _accrue(principal, appliedRateRay, to - from);
    }

    function accrueFixedTotal(
        uint256 fixedTotalInterest,
        uint64 accrualStart,
        uint64 accrualEnd,
        uint64 from,
        uint64 to
    ) external pure returns (uint256) {
        if (accrualEnd <= accrualStart || from < accrualStart || to < from || to > accrualEnd) {
            revert InvalidInterestTerms();
        }
        return Math.mulDiv(fixedTotalInterest, to - from, accrualEnd - accrualStart);
    }

    function _accrue(uint256 principal, uint256 annualRateRay, uint256 elapsed)
        private
        pure
        returns (uint256)
    {
        uint256 annualInterest = Math.mulDiv(principal, annualRateRay, RiskTypes.RAY);
        return Math.mulDiv(annualInterest, elapsed, YEAR_SECONDS);
    }
}
