// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IUFTBridgeHub } from "../src/interfaces/IUFTBridgeHub.sol";
import {
    CrossChainLoanAccount,
    ICrossChainLoanRouter
} from "../src/crosschain/CrossChainLoanAccount.sol";
import { CrossChainTypes } from "../src/crosschain/CrossChainTypes.sol";

contract Phase8OrderingToken is ERC20 {
    constructor() ERC20("Ordering Token", "ORD") { }
}

contract Phase8OrderingRegistry is ILoanRegistry {
    function registerLoan(bytes32, address, address, bytes32, uint32) external { }

    function loanAccount(bytes32) external pure returns (address) {
        return address(0);
    }

    function borrowerOf(bytes32) external pure returns (address) {
        return address(0);
    }

    function agreementHashOf(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function protocolVersionOf(bytes32) external pure returns (uint32) {
        return 0;
    }

    function exists(bytes32) external pure returns (bool) {
        return false;
    }

    function isTerminal(bytes32) external pure returns (bool) {
        return false;
    }
    function markTerminal(bytes32) external { }
}

contract Phase8OrderingHub is IUFTBridgeHub {
    function compensate(CrossChainLoanAccount account, bytes32 lockId) external {
        account.onFundingCompensated(lockId);
    }

    function lockForLoan(bytes32, bytes32, address, address, address, uint256, bytes32, uint64)
        external
        pure
        returns (bytes32)
    {
        return bytes32(0);
    }

    function releaseLoanBacking(bytes32, bytes32, address, uint256) external { }
    function refundCancelledLoan(bytes32, bytes32, address, uint256) external { }
    function reclassifyLoanBacking(bytes32, uint256) external { }

    function loanBacking(bytes32) external pure returns (uint256) {
        return 0;
    }

    function backingForChain(uint256) external pure returns (uint256) {
        return 0;
    }

    function totalBridgeBacking() external pure returns (uint256) {
        return 0;
    }
}

contract Phase8OrderingRouter is ICrossChainLoanRouter {
    uint256 public disbursementCount;
    uint256 public releaseCount;

    function deploy(
        CrossChainTypes.CrossChainLoanTerms memory terms,
        ILoanRegistry registry,
        IUFTBridgeHub hub,
        ERC20 token
    ) external returns (CrossChainLoanAccount) {
        return new CrossChainLoanAccount(
            terms, address(this), registry, hub, token, address(0xBEEF), keccak256("CONFIG")
        );
    }

    function recordCollateral(
        CrossChainLoanAccount account,
        bytes32 collateralId,
        uint256 amount,
        bytes32 policyHash
    ) external {
        account.recordCollateralLocked(collateralId, amount, policyHash);
    }

    function authorizeDisbursement(bytes32 loanId) external returns (bytes32 messageId) {
        ++disbursementCount;
        return keccak256(abi.encode("DISBURSE", loanId, disbursementCount));
    }

    function authorizeCollateralRelease(bytes32 loanId) external returns (bytes32 messageId) {
        ++releaseCount;
        return keccak256(abi.encode("RELEASE", loanId, releaseCount));
    }
}

contract Phase8CrossChainRecoveryOrderingTest {
    bytes32 private constant POLICY = keccak256("ORDERING_POLICY");
    bytes32 private constant COLLATERAL = keccak256("ORDERING_COLLATERAL");
    bytes32 private constant LOCK = keccak256("ORDERING_LOCK");

    Phase8OrderingToken private token;
    Phase8OrderingRegistry private registry;
    Phase8OrderingHub private hub;
    Phase8OrderingRouter private router;

    function setUp() public {
        token = new Phase8OrderingToken();
        registry = new Phase8OrderingRegistry();
        hub = new Phase8OrderingHub();
        router = new Phase8OrderingRouter();
    }

    function testCollateralReportBeforeCompensationClosesWithoutDebt() public {
        CrossChainLoanAccount account = _account(keccak256("BEFORE"));
        router.recordCollateral(account, COLLATERAL, 250 ether, POLICY);
        require(account.collateralConfirmed(), "collateral not recorded");
        require(account.state() == CrossChainTypes.CrossChainLoanState.ACTIVATING, "pre-state");
        hub.compensate(account, LOCK);
        _assertSafeClosing(account);
        _assertDuplicateCollateralRejected(account);
    }

    function testCollateralReportAfterCompensationClosesWithoutDebt() public {
        CrossChainLoanAccount account = _account(keccak256("AFTER"));
        hub.compensate(account, LOCK);
        require(
            account.state() == CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING,
            "not recovery pending"
        );
        router.recordCollateral(account, COLLATERAL, 250 ether, POLICY);
        _assertSafeClosing(account);
        _assertDuplicateCollateralRejected(account);
    }

    function _account(bytes32 loanId) private returns (CrossChainLoanAccount) {
        return router.deploy(
            CrossChainTypes.CrossChainLoanTerms({
                loanId: loanId,
                agreementHash: keccak256(abi.encode("AGREEMENT", loanId)),
                fundingLockId: LOCK,
                collateralId: COLLATERAL,
                borrower: address(0xB077),
                lender: address(0x1EAD),
                principalAmount: 100 ether,
                collateralAmount: 250 ether,
                policyHash: POLICY
            }),
            registry,
            hub,
            token
        );
    }

    function _assertSafeClosing(CrossChainLoanAccount account) private view {
        require(account.state() == CrossChainTypes.CrossChainLoanState.CLOSING, "not closing");
        require(account.outstandingPrincipal() == 0, "debt activated");
        require(account.disbursementMessageId() == bytes32(0), "disbursement authorized");
        require(account.collateralReleaseMessageId() != bytes32(0), "release absent");
        require(router.disbursementCount() == 0, "disbursement count");
        require(router.releaseCount() == 1, "release count");
    }

    function _assertDuplicateCollateralRejected(CrossChainLoanAccount account) private {
        (bool accepted,) = address(router)
            .call(
                abi.encodeCall(
                    Phase8OrderingRouter.recordCollateral, (account, COLLATERAL, 250 ether, POLICY)
                )
            );
        require(!accepted, "duplicate collateral report");
        require(router.releaseCount() == 1, "duplicate release");
    }
}
