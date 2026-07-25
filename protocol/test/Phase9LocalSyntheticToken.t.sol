// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";

interface Phase9TokenVm {
    function chainId(uint256 chainId) external;
    function prank(address sender) external;
}

contract Phase9LocalSyntheticTokenTest {
    Phase9TokenVm private constant vm =
        Phase9TokenVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testExactLocalMetadataSupplyAndTransfers() public {
        vm.chainId(31_337);
        address allocator = address(0xA110CA7E);
        address recipient = address(0xBEEF);
        Phase9LocalSyntheticToken token = new Phase9LocalSyntheticToken(allocator);

        require(
            keccak256(bytes(token.name()))
                == keccak256(bytes("Unified Phase 9 Local Synthetic Unit")),
            "name"
        );
        require(keccak256(bytes(token.symbol())) == keccak256(bytes("P9UNIT")), "symbol");
        require(token.decimals() == 6, "decimals");
        require(token.FIXED_SUPPLY_UNITS() == 1_000_000_000_000_000, "fixed supply");
        require(token.totalSupply() == token.FIXED_SUPPLY_UNITS(), "total supply");
        require(token.balanceOf(allocator) == token.FIXED_SUPPLY_UNITS(), "allocation");

        vm.prank(allocator);
        require(token.transfer(recipient, 123_456), "transfer");
        require(token.balanceOf(recipient) == 123_456, "recipient balance");
        require(token.totalSupply() == token.FIXED_SUPPLY_UNITS(), "supply changed");
    }

    function testRejectsNonLocalChainAndZeroAllocator() public {
        vm.chainId(1);
        try new Phase9LocalSyntheticToken(address(this)) {
            revert("non-local deployment succeeded");
        } catch (bytes memory reason) {
            require(
                bytes4(reason) == Phase9LocalSyntheticToken.InvalidLocalChain.selector,
                "wrong chain error"
            );
        }

        vm.chainId(31_337);
        try new Phase9LocalSyntheticToken(address(0)) {
            revert("zero allocator succeeded");
        } catch (bytes memory reason) {
            require(
                bytes4(reason) == Phase9LocalSyntheticToken.InvalidFixtureAllocator.selector,
                "wrong allocator error"
            );
        }
    }
}
