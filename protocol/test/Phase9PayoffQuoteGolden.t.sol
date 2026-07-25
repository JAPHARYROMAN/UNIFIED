// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPayoffQuoteEngineV2 } from "../src/interfaces/phase9/IPayoffQuoteEngineV2.sol";

contract Phase9PayoffQuoteGoldenTest {
    function testPayoffQuotePreimageUsesTheFrozenConceptualOrder() public pure {
        bytes memory firstHead = abi.encode(
            uint256(20 * 32),
            address(0x1111111111111111111111111111111111111111),
            uint256(31_337),
            bytes32(uint256(0x22)),
            address(0x3333333333333333333333333333333333333333),
            bytes32(uint256(0x44)),
            uint64(5),
            uint256(90_000_000),
            uint256(5_000_000),
            uint256(3_000_000)
        );
        bytes memory secondHead = abi.encode(
            uint256(3_000_000),
            uint256(1_000_000),
            bytes32(uint256(0x55)),
            uint256(100_000_000),
            bytes32(uint256(0x66)),
            address(0x7777777777777777777777777777777777777777),
            bytes32(uint256(0x88)),
            uint64(1_900_000_000),
            uint64(1_900_003_600),
            uint64(9)
        );
        bytes memory stringTail = abi.encode(uint256(23), bytes32("UNIFIED_PAYOFF_QUOTE_V1"));
        bytes32 expected = keccak256(bytes.concat(firstHead, secondHead, stringTail));

        require(
            expected == 0xd09375e057dfcc27ec52eb62e16d0c0ea99ce3827d9577aa78e15d0dcc48b79b,
            "quote preimage drift"
        );
    }

    function testPayoffInterfaceTupleOrderAndEnumOrdinals() public pure {
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote = IPayoffQuoteEngineV2.PayoffQuoteV2({
            quoteId: bytes32(uint256(1)),
            loanId: bytes32(uint256(2)),
            loanAccount: address(3),
            policyHash: bytes32(uint256(4)),
            debtStateVersion: 5,
            principal: 6,
            accruedInterest: 7,
            fees: 8,
            penalties: 9,
            credits: 10,
            componentBeneficiaryHash: bytes32(uint256(11)),
            grossPayoff: 12,
            netPayoff: 13,
            settlementAssetId: bytes32(uint256(14)),
            settlementToken: address(15),
            settlementRouteHash: bytes32(uint256(16)),
            issuedAt: 17,
            validUntil: 18,
            quoteNonce: 19,
            state: IPayoffQuoteEngineV2.QuoteState.ISSUED
        });
        require(abi.encode(quote).length == 20 * 32, "quote tuple width");
        require(uint8(IPayoffQuoteEngineV2.QuoteState.INVALIDATED) == 4, "quote state ordinal");
        require(uint8(IPayoffQuoteEngineV2.ComponentKind.CREDIT) == 7, "component ordinal");
    }
}
