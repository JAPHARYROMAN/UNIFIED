// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { CrossChainTypes } from "../src/crosschain/CrossChainTypes.sol";

contract Phase8CrossChainSchemaTest {
    uint256 private constant AMOUNT = 1 ether;

    function testLoanCancellationAuthorizationLayoutGolden() public pure {
        CrossChainTypes.LoanCancellationAuthorization memory authorization =
            CrossChainTypes.LoanCancellationAuthorization({
                loanRouter: 0x1111111111111111111111111111111111111111,
                loanId: bytes32(uint256(type(uint256).max / 0xff * 0x22)),
                fundingLockId: bytes32(uint256(type(uint256).max / 0xff * 0x33)),
                disbursementMessageId: bytes32(uint256(type(uint256).max / 0xff * 0x44)),
                disbursementTombstoneHash: bytes32(uint256(type(uint256).max / 0xff * 0x55)),
                amount: AMOUNT,
                policyHash: bytes32(uint256(type(uint256).max / 0xff * 0x66)),
                authorizationNonce: 7,
                validUntil: 1_700_003_600,
                reasonCode: bytes32(uint256(type(uint256).max / 0xff * 0x77)),
                authorizerSetHash: bytes32(uint256(type(uint256).max / 0xff * 0x88)),
                authorizerSetVersion: 1
            });

        assert(
            keccak256(abi.encode(authorization))
                == 0x6559f566fae044a0b47fad5ad54de9a09b55e0cba3bd34290293e4e3e36b0bc0
        );
        assert(abi.encode(authorization).length == 12 * 32);
    }

    function testLoanCancellationRequestedLayoutGolden() public pure {
        CrossChainTypes.LoanCancellationRequestedPayload memory request =
            CrossChainTypes.LoanCancellationRequestedPayload({
                cancellationId: bytes32(uint256(type(uint256).max / 0xff * 0x99)),
                loanId: bytes32(uint256(type(uint256).max / 0xff * 0x22)),
                fundingLockId: bytes32(uint256(type(uint256).max / 0xff * 0x33)),
                disbursementMessageId: bytes32(uint256(type(uint256).max / 0xff * 0x44)),
                disbursementTombstoneHash: bytes32(uint256(type(uint256).max / 0xff * 0x55)),
                homeLoanAccount: 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa,
                lender: 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB,
                wrappedToken: 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC,
                amount: AMOUNT,
                policyHash: bytes32(uint256(type(uint256).max / 0xff * 0x66)),
                reasonCode: bytes32(uint256(type(uint256).max / 0xff * 0x77))
            });

        assert(
            keccak256(abi.encode(request))
                == 0xd8b5a830c89f14d7eaebe14c1c819a2526194c05491fb357bf972464612fb992
        );
        assert(abi.encode(request).length == 11 * 32);
    }

    function testSatelliteFundingCancelledLayoutGolden() public pure {
        CrossChainTypes.SatelliteFundingCancelledPayload memory completion =
            CrossChainTypes.SatelliteFundingCancelledPayload({
                cancellationId: bytes32(uint256(type(uint256).max / 0xff * 0x99)),
                loanId: bytes32(uint256(type(uint256).max / 0xff * 0x22)),
                fundingLockId: bytes32(uint256(type(uint256).max / 0xff * 0x33)),
                disbursementMessageId: bytes32(uint256(type(uint256).max / 0xff * 0x44)),
                disbursementTombstoneHash: bytes32(uint256(type(uint256).max / 0xff * 0x55)),
                escrowBurnResultHash: bytes32(uint256(type(uint256).max / 0xff * 0xdd)),
                homeLoanAccount: 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa,
                lender: 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB,
                wrappedToken: 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC,
                amount: AMOUNT,
                policyHash: bytes32(uint256(type(uint256).max / 0xff * 0x66))
            });

        assert(
            keccak256(abi.encode(completion))
                == 0xe272800252a7b96d69aba58e658c1151e5211a1c7137700ff341cbe2d9c23dba
        );
        assert(abi.encode(completion).length == 11 * 32);
    }
}
