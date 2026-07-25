// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply settlement fixture limited to the disposable local chain.
contract Phase9LocalSyntheticToken is ERC20 {
    error InvalidLocalChain(uint256 chainId);
    error InvalidFixtureAllocator();

    uint256 public constant FIXED_SUPPLY_UNITS = 1_000_000_000_000_000;

    constructor(address fixtureAllocator)
        ERC20("Unified Phase 9 Local Synthetic Unit", "P9UNIT")
    {
        if (block.chainid != 31337) revert InvalidLocalChain(block.chainid);
        if (fixtureAllocator == address(0)) revert InvalidFixtureAllocator();
        _mint(fixtureAllocator, FIXED_SUPPLY_UNITS);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
