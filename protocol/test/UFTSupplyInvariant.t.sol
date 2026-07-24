// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ProtocolTypes } from "../src/kernel/ProtocolTypes.sol";
import { UnifiedToken } from "../src/token/UnifiedToken.sol";

contract BurnHandler {
    UnifiedToken public token;
    uint256 public cumulativeBurned;

    function bind(UnifiedToken token_) external {
        require(address(token) == address(0), "already bound");
        token = token_;
    }

    function burn(uint256 seed) external {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 amount = seed % (balance + 1);
        if (amount == 0) return;
        token.burn(amount);
        cumulativeBurned += amount;
    }
}

contract UFTSupplyInvariantTest {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    UnifiedToken private token;
    BurnHandler private handler;
    address[] private _targetedContracts;

    function setUp() public {
        handler = new BurnHandler();
        ProtocolTypes.GenesisDestinations memory destinations = ProtocolTypes.GenesisDestinations({
            community: address(handler),
            treasury: address(0x2002),
            stakingRewards: address(0x2003),
            insurance: address(0x2004),
            contributors: address(0x2005),
            investors: address(0x2006),
            publicDistribution: address(0x2007),
            liquidity: address(0x2008),
            partners: address(0x2009)
        });
        token = new UnifiedToken(destinations);
        handler.bind(token);
        _targetedContracts.push(address(handler));
    }

    function invariantSupplyNeverExceedsCap() public view {
        require(token.totalSupply() <= token.MAX_SUPPLY(), "supply cap exceeded");
    }

    function invariantSupplyEquationAccountsForEveryBurn() public view {
        require(
            token.totalSupply() + handler.cumulativeBurned() == token.MAX_SUPPLY(),
            "supply equation broken"
        );
    }

    function targetSelectors() external view returns (FuzzSelector[] memory targets) {
        targets = new FuzzSelector[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.burn.selector;
        targets[0] = FuzzSelector({ addr: address(handler), selectors: selectors });
    }

    function targetContracts() external view returns (address[] memory) {
        return _targetedContracts;
    }
}
