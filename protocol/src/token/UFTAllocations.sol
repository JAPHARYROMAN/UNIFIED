// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library UFTAllocations {
    uint256 internal constant UNIT = 1 ether;
    uint256 internal constant COMMUNITY = 240_000_000 * UNIT;
    uint256 internal constant TREASURY = 180_000_000 * UNIT;
    uint256 internal constant STAKING_REWARDS = 120_000_000 * UNIT;
    uint256 internal constant INSURANCE = 100_000_000 * UNIT;
    uint256 internal constant CONTRIBUTORS = 150_000_000 * UNIT;
    uint256 internal constant INVESTORS = 100_000_000 * UNIT;
    uint256 internal constant PUBLIC_DISTRIBUTION = 60_000_000 * UNIT;
    uint256 internal constant LIQUIDITY = 40_000_000 * UNIT;
    uint256 internal constant PARTNERS = 10_000_000 * UNIT;
    uint256 internal constant MAX_SUPPLY = 1_000_000_000 * UNIT;
}
