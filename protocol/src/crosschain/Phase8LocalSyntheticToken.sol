// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test-only ERC-20 used by the reproducible two-Anvil Phase 8 release gate.
/// @dev This contract is synthetic-local infrastructure and must never hold real value.
contract Phase8LocalSyntheticToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000 ether;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
