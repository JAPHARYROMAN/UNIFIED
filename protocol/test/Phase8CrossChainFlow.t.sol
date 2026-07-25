// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUnifiedToken } from "../src/interfaces/IUnifiedToken.sol";
import { BridgeExposurePolicy } from "../src/crosschain/BridgeExposurePolicy.sol";
import { ChainRegistry } from "../src/crosschain/ChainRegistry.sol";
import { CrossChainCoordinator } from "../src/crosschain/CrossChainCoordinator.sol";
import { CrossChainLoanAccount } from "../src/crosschain/CrossChainLoanAccount.sol";
import { CrossChainLoanAccountDeployer } from "../src/crosschain/CrossChainLoanAccountDeployer.sol";
import { CrossChainLoanFactory } from "../src/crosschain/CrossChainLoanFactory.sol";
import { CrossChainLoanPolicy } from "../src/crosschain/CrossChainLoanPolicy.sol";
import { CrossChainMessageBuilder } from "../src/crosschain/CrossChainMessageBuilder.sol";
import { CrossChainRecoveryController } from "../src/crosschain/CrossChainRecoveryController.sol";
import { CrossChainTypes } from "../src/crosschain/CrossChainTypes.sol";
import { RouteRegistry } from "../src/crosschain/RouteRegistry.sol";
import { SatelliteCollateralVault } from "../src/crosschain/SatelliteCollateralVault.sol";
import { SatelliteLoanComponent } from "../src/crosschain/SatelliteLoanComponent.sol";
import { SatelliteSettlementVault } from "../src/crosschain/SatelliteSettlementVault.sol";
import { SyntheticFinalityVerifier } from "../src/crosschain/SyntheticFinalityVerifier.sol";
import { UFTBridgeHub } from "../src/crosschain/UFTBridgeHub.sol";
import { WrappedUFT } from "../src/crosschain/WrappedUFT.sol";
import { ICrossChainLoanPolicy } from "../src/interfaces/ICrossChainLoanPolicy.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";

interface Phase8FlowVm {
    function addr(uint256 privateKey) external returns (address);
    function chainId(uint256 newChainId) external;
    function prank(address sender) external;
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 timestamp) external;
}

contract Phase8FlowToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000 ether;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract Phase8MaliciousWrappedSource {
    CrossChainCoordinator private immutable _coordinator;
    RouteRegistry private immutable _routes;

    constructor(CrossChainCoordinator coordinator_, RouteRegistry routes_) {
        _coordinator = coordinator_;
        _routes = routes_;
    }

    function sendClaim(
        bytes32 routePolicyHash,
        bytes32 aggregateId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload,
        uint64 expiresAt
    ) external returns (bytes32 messageId) {
        CrossChainTypes.MessageEnvelope memory envelope =
            CrossChainMessageBuilder.build(
                _coordinator,
                _routes,
                CrossChainMessageBuilder.BuildRequest({
                    routePolicyHash: routePolicyHash,
                    sourceComponent: address(this),
                    aggregateId: aggregateId,
                    actionType: actionType,
                    payloadHash: keccak256(payload),
                    expiresAt: expiresAt,
                    correlationId: aggregateId,
                    causationMessageId: bytes32(0),
                    supersededMessageId: bytes32(0)
                })
            );
        return _coordinator.sendMessage(envelope, payload);
    }
}

contract Phase8CrossChainFlowTest {
    Phase8FlowVm private constant vm =
        Phase8FlowVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant HOME_CHAIN = 31_337;
    uint256 private constant SATELLITE_CHAIN = 31_338;
    uint64 private constant NOW = 1_900_000_000;
    uint256 private constant SIGNER_ONE_KEY = 1;
    uint256 private constant SIGNER_TWO_KEY = 2;
    uint256 private constant SIGNER_THREE_KEY = 3;
    uint256 private constant UNAUTHORIZED_SIGNER_KEY = 4;
    bytes32 private constant PROTOCOL_ID = keccak256("UNIFIED_PHASE8_LOCAL");
    bytes32 private constant OBSERVER_AUTHORITY = keccak256("SYNTHETIC_OBSERVER");
    bytes32 private constant POLICY_HASH = keccak256("CROSS_CHAIN_LOAN_POLICY");
    bytes32 private constant LOAN_ID = keccak256("PHASE8_LOAN");
    bytes32 private constant LOCK_ID = keccak256("PHASE8_FUNDING_LOCK");
    bytes32 private constant COLLATERAL_ID = keccak256("PHASE8_COLLATERAL");
    uint256 private constant PRINCIPAL = 100 ether;
    uint256 private constant COLLATERAL = 250 ether;

    struct CancellationFixture {
        CrossChainLoanAccount account;
        address accountAddress;
        bytes32 mintReportMessageId;
        bytes32 collateralReportMessageId;
    }

    address private administrator = address(0xA11);
    address private lender = address(0x1EAD);
    address private borrower = address(0xB077);

    RoleManager private roles;
    Phase8FlowToken private canonical;
    Phase8FlowToken private collateral;
    LoanRegistry private loanRegistry;
    ChainRegistry private homeChains;
    ChainRegistry private satelliteChains;
    EmergencyController private homeEmergency;
    EmergencyController private satelliteEmergency;
    RouteRegistry private homeRoutes;
    RouteRegistry private satelliteRoutes;
    SyntheticFinalityVerifier private homeVerifier;
    SyntheticFinalityVerifier private satelliteVerifier;
    CrossChainCoordinator private homeCoordinator;
    CrossChainCoordinator private satelliteCoordinator;
    CrossChainRecoveryController private homeRecovery;
    CrossChainRecoveryController private satelliteRecovery;
    BridgeExposurePolicy private exposurePolicy;
    UFTBridgeHub private bridgeHub;
    WrappedUFT private wrapped;
    SatelliteLoanComponent private satelliteComponent;
    SatelliteCollateralVault private collateralVault;
    SatelliteSettlementVault private settlementVault;
    CrossChainLoanAccountDeployer private accountDeployer;
    CrossChainLoanFactory private loanFactory;
    CrossChainLoanPolicy private loanPolicy;

    address[3] private signers;
    bytes32 private signerSetHash;
    bytes32 private mintRoute;
    bytes32 private reportRoute;
    bytes32 private repaymentRoute;
    bytes32 private alternateRepaymentRoute;
    bytes32 private bridgeExitRoute;
    bytes32 private disbursementRoute;
    bytes32 private collateralReleaseRoute;

    function setUp() public {
        vm.chainId(HOME_CHAIN);
        vm.warp(NOW);
        _deployDomains();
        _deployComponents();
        _registerRoutes();
        _bindPolicies();
        canonical.transfer(lender, 1_000 ether);
        collateral.transfer(borrower, 1_000 ether);
    }

    function testFullLoanLockMintCollateralRepayReleaseAndNoDoubleUnlock() public {
        canonical.transfer(address(bridgeHub), 1 ether);
        bridgeHub.reconcileSurplus();
        require(bridgeHub.bridgeSurplus() == 1 ether, "donation not surplus");

        vm.chainId(HOME_CHAIN);
        vm.prank(lender);
        canonical.approve(address(bridgeHub), PRINCIPAL);
        CrossChainTypes.CrossChainLoanTerms memory terms = _terms();
        vm.prank(lender);
        (address accountAddress, bytes32 mintMessageId) =
            loanFactory.createLoan(terms, NOW + 2 days);
        CrossChainLoanAccount account = CrossChainLoanAccount(accountAddress);

        CrossChainTypes.SatelliteLoanProvisioning memory provisioning =
            loanFactory.satelliteProvisioning(LOAN_ID);
        vm.chainId(SATELLITE_CHAIN);
        satelliteComponent.provisionLoan(provisioning);
        vm.prank(borrower);
        collateral.approve(address(collateralVault), COLLATERAL);
        vm.prank(borrower);
        bytes32 collateralReportMessageId = collateralVault.lockCollateral(LOAN_ID);

        bytes memory mintPayload = abi.encode(
            CrossChainTypes.CanonicalUftLockPayload({
                lockId: LOCK_ID,
                loanId: LOAN_ID,
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(wrapped),
                destinationRecipient: address(settlementVault),
                amount: PRINCIPAL
            })
        );
        _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            mintMessageId,
            mintPayload
        );
        bytes32 mintReportMessageId = satelliteComponent.reportMessage(
            LOAN_ID, CrossChainTypes.ACTION_SATELLITE_MINT_CONFIRMED
        );
        require(mintReportMessageId != bytes32(0), "mint report");

        bytes memory collateralReportPayload = abi.encode(
            CrossChainTypes.SatelliteCollateralLockedPayload({
                loanId: LOAN_ID,
                collateralId: COLLATERAL_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                collateralToken: address(collateral),
                amount: COLLATERAL,
                policyHash: POLICY_HASH
            })
        );
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            collateralReportMessageId,
            collateralReportPayload
        );
        _assertChangedReplayRejected(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            collateralReportMessageId,
            collateralReportPayload
        );

        bytes memory mintReportPayload = abi.encode(
            CrossChainTypes.WrappedUftMintedPayload({
                loanId: LOAN_ID,
                lockId: LOCK_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            })
        );
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            mintReportMessageId,
            mintReportPayload
        );

        bytes32 disbursementMessageId = account.disbursementMessageId();
        require(disbursementMessageId != bytes32(0), "disbursement authorization");
        bytes memory disbursementPayload = abi.encode(
            CrossChainTypes.HomeDisbursementAuthorizedPayload({
                loanId: LOAN_ID,
                fundingLockId: LOCK_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            })
        );
        bytes32 disbursementResult = _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            disbursementMessageId,
            disbursementPayload
        );
        _assertDisbursementReplayAndBackingRoute(
            disbursementMessageId, disbursementPayload, disbursementResult
        );

        bytes32 settledReportMessageId = satelliteComponent.reportMessage(
            LOAN_ID, CrossChainTypes.ACTION_SATELLITE_DISBURSEMENT_SETTLED
        );
        bytes memory settledPayload = abi.encode(
            CrossChainTypes.SatelliteDisbursementSettledPayload({
                loanId: LOAN_ID,
                fundingLockId: LOCK_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            })
        );
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            settledReportMessageId,
            settledPayload
        );
        require(account.state() == CrossChainTypes.CrossChainLoanState.ACTIVE, "loan not active");
        require(account.outstandingPrincipal() == PRINCIPAL, "principal");
        _repayReleaseAndClose(account, accountAddress);
    }

    function _assertDisbursementReplayAndBackingRoute(
        bytes32 disbursementMessageId,
        bytes memory disbursementPayload,
        bytes32 disbursementResult
    ) private {
        require(wrapped.balanceOf(borrower) == PRINCIPAL, "exact borrower disbursement");
        vm.prank(borrower);
        (bool wrongBackingRoute,) = address(wrapped)
            .call(
                abi.encodeCall(
                    WrappedUFT.burnForBridge,
                    (
                        keccak256("WRONG_BACKING_BURN"),
                        keccak256("WRONG_BACKING_ROUTE"),
                        repaymentRoute,
                        borrower,
                        1 ether,
                        false,
                        uint64(block.timestamp + 2 days)
                    )
                )
            );
        require(!wrongBackingRoute, "wrong backing route accepted");
        _acknowledge(homeCoordinator, homeVerifier, disbursementMessageId, disbursementResult);
        satelliteRoutes.setRoutePaused(disbursementRoute, true);
        require(
            _execute(
                homeCoordinator,
                satelliteCoordinator,
                satelliteVerifier,
                SATELLITE_CHAIN,
                disbursementMessageId,
                disbursementPayload
            ) == disbursementResult,
            "paused exact replay"
        );
        satelliteRoutes.deprecateRoute(disbursementRoute);
        require(
            _execute(
                homeCoordinator,
                satelliteCoordinator,
                satelliteVerifier,
                SATELLITE_CHAIN,
                disbursementMessageId,
                disbursementPayload
            ) == disbursementResult,
            "deprecated exact replay"
        );
    }

    function _repayReleaseAndClose(CrossChainLoanAccount account, address accountAddress) private {
        _assertAlternateRepaymentRouteRejected();
        satelliteRoutes.setRoutePaused(repaymentRoute, true);
        _assertRepaymentBurnRecoveryRestoresRetry(account);
        _assertDirectRepaymentSurvivesRouteOutage(account);
        _burnAndExecuteRepayment(account, 40 ether, keccak256("PAYMENT_ONE"));
        _burnAndExecuteRepayment(account, account.outstandingPrincipal(), keccak256("PAYMENT_TWO"));
        require(account.state() == CrossChainTypes.CrossChainLoanState.CLOSING, "loan not closing");
        require(bridgeHub.loanBacking(LOAN_ID) == 0, "loan backing not reclassified");
        require(bridgeHub.totalBridgeBacking() == 0, "aggregate backing");
        require(bridgeHub.bridgeSurplus() == 1 ether, "surplus consumed");
        _releaseCollateralAndClose(account, accountAddress);
    }

    function _releaseCollateralAndClose(CrossChainLoanAccount account, address accountAddress)
        private
    {
        bytes32 releaseMessageId = account.collateralReleaseMessageId();
        bytes memory releasePayload = abi.encode(
            CrossChainTypes.HomeCollateralReleaseAuthorizedPayload({
                loanId: LOAN_ID,
                collateralId: COLLATERAL_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                collateralToken: address(collateral),
                amount: COLLATERAL,
                policyHash: POLICY_HASH
            })
        );
        uint256 borrowerCollateralBefore = collateral.balanceOf(borrower);
        bytes32 releaseResult = _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            releaseMessageId,
            releasePayload
        );
        require(
            collateral.balanceOf(borrower) - borrowerCollateralBefore == COLLATERAL,
            "collateral release"
        );
        bytes32 replayResult = _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            releaseMessageId,
            releasePayload
        );
        require(replayResult == releaseResult, "release replay result");
        require(
            collateral.balanceOf(borrower) == borrowerCollateralBefore + COLLATERAL,
            "double collateral release"
        );

        bytes32 releaseReportMessageId = satelliteComponent.reportMessage(
            LOAN_ID, CrossChainTypes.ACTION_SATELLITE_COLLATERAL_RELEASED
        );
        bytes memory releaseReportPayload = abi.encode(
            CrossChainTypes.SatelliteCollateralReleasedPayload({
                loanId: LOAN_ID,
                collateralId: COLLATERAL_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                collateralToken: address(collateral),
                amount: COLLATERAL,
                policyHash: POLICY_HASH
            })
        );
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            releaseReportMessageId,
            releaseReportPayload
        );
        require(account.state() == CrossChainTypes.CrossChainLoanState.CLOSED, "loan not closed");
        require(loanRegistry.isTerminal(LOAN_ID), "registry not terminal");
        require(wrapped.totalSupply() == 0, "wrapped supply");
    }

    function _assertRepaymentBurnRecoveryRestoresRetry(CrossChainLoanAccount account) private {
        bytes32 paymentId = keccak256("RECOVERED_REPAYMENT_PAYMENT");
        uint256 backingBefore = bridgeHub.totalBridgeBacking();
        _recoverFailedRepaymentBurn(paymentId, backingBefore, wrapped.totalSupply());
        _retryRecoveredRepayment(account, paymentId, backingBefore);
    }

    function _recoverFailedRepaymentBurn(
        bytes32 paymentId,
        uint256 backingBefore,
        uint256 supplyBefore
    ) private {
        bytes32 failedBurnId = keccak256("RECOVERED_REPAYMENT_FAILED_BURN");
        vm.chainId(SATELLITE_CHAIN);
        vm.prank(borrower);
        bytes32 failedMessageId = wrapped.burnForLoanRepayment(
            failedBurnId,
            LOAN_ID,
            paymentId,
            repaymentRoute,
            1 ether,
            uint64(block.timestamp + 1 hours)
        );
        require(settlementVault.consumedPayment(paymentId), "payment not reserved");
        CrossChainTypes.MessageEnvelope memory envelope =
            satelliteCoordinator.messageEnvelope(failedMessageId);
        bytes memory compensationPayload = abi.encode(failedBurnId, borrower);
        vm.warp(envelope.expiresAt);
        vm.chainId(HOME_CHAIN);
        CrossChainRecoveryController.RecoveryRequest memory request = _recoveryRequest(
            homeRecovery,
            envelope,
            1,
            keccak256("REPAYMENT_BURN_TIMEOUT"),
            keccak256(compensationPayload)
        );
        bytes[] memory signatures = _recoverySignatures(homeRecovery, envelope, request);
        bytes32 tombstone = homeRecovery.recordDestinationTombstone(envelope, request, signatures);
        vm.chainId(SATELLITE_CHAIN);
        CrossChainTypes.SourceEventProof memory proof =
            _proof(envelope, tombstone, envelope.destinationFinalityPolicyHash);
        CrossChainTypes.FinalityCertificate memory certificate =
            _certificate(satelliteVerifier, envelope, proof);
        satelliteRecovery.compensateSource(
            envelope, request, signatures, tombstone, compensationPayload, proof, certificate
        );
        require(!settlementVault.consumedPayment(paymentId), "payment retry not restored");
        require(wrapped.totalSupply() == supplyBefore, "repayment supply not restored");
        require(bridgeHub.totalBridgeBacking() == backingBefore, "failed burn released home");
    }

    function _retryRecoveredRepayment(
        CrossChainLoanAccount account,
        bytes32 paymentId,
        uint256 backingBefore
    ) private {
        bytes32 retryBurnId = keccak256("RECOVERED_REPAYMENT_RETRY_BURN");
        vm.prank(borrower);
        bytes32 retryMessageId = wrapped.burnForLoanRepayment(
            retryBurnId,
            LOAN_ID,
            paymentId,
            repaymentRoute,
            1 ether,
            uint64(block.timestamp + 2 days)
        );
        bytes memory retryPayload = abi.encode(
            CrossChainTypes.SatelliteRepaymentBurnedPayload({
                burnId: retryBurnId,
                loanId: LOAN_ID,
                paymentId: paymentId,
                backingRoutePolicyHash: mintRoute,
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(wrapped),
                lender: lender,
                amount: 1 ether
            })
        );
        uint256 principalBefore = account.outstandingPrincipal();
        _execute(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            retryMessageId,
            retryPayload
        );
        require(account.outstandingPrincipal() == principalBefore - 1 ether, "retry debt");
        require(bridgeHub.totalBridgeBacking() == backingBefore - 1 ether, "retry backing");
    }

    function _assertDirectRepaymentSurvivesRouteOutage(CrossChainLoanAccount account) private {
        bytes32 paymentId = keccak256("DIRECT_ROUTE_OUTAGE_PAYMENT");
        uint256 backingBeforeExit = bridgeHub.totalBridgeBacking();
        uint256 loanBackingBeforeExit = bridgeHub.loanBacking(LOAN_ID);
        uint256 wrappedBeforeExit = wrapped.totalSupply();
        bytes32 burnId = keccak256("GENERIC_EXIT_BEFORE_DIRECT_REPAYMENT");
        vm.chainId(SATELLITE_CHAIN);
        vm.prank(borrower);
        bytes32 messageId = wrapped.burnForBridge(
            burnId,
            mintRoute,
            bridgeExitRoute,
            borrower,
            10 ether,
            false,
            uint64(block.timestamp + 2 days)
        );
        bytes memory payload = abi.encode(
            CrossChainTypes.WrappedUftBurnedPayload({
                burnId: burnId,
                backingRoutePolicyHash: mintRoute,
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(wrapped),
                recipient: borrower,
                amount: 10 ether
            })
        );
        _execute(
            satelliteCoordinator, homeCoordinator, homeVerifier, HOME_CHAIN, messageId, payload
        );
        require(
            bridgeHub.totalBridgeBacking() == backingBeforeExit - 10 ether, "generic exit backing"
        );
        require(
            bridgeHub.loanBacking(LOAN_ID) == loanBackingBeforeExit, "generic exit loan attribution"
        );
        require(wrapped.totalSupply() == wrappedBeforeExit - 10 ether, "generic exit supply");

        uint256 payerBefore = canonical.balanceOf(borrower);
        uint256 lenderBefore = canonical.balanceOf(lender);
        uint256 backingBefore = bridgeHub.totalBridgeBacking();
        uint256 loanBackingBefore = bridgeHub.loanBacking(LOAN_ID);
        uint256 wrappedBefore = wrapped.totalSupply();
        uint256 principalBefore = account.outstandingPrincipal();
        vm.chainId(HOME_CHAIN);
        vm.prank(borrower);
        canonical.approve(address(account), 10 ether);
        vm.prank(borrower);
        account.directHomeRepayment(paymentId, 10 ether);
        require(account.outstandingPrincipal() == principalBefore - 10 ether, "direct debt");
        require(payerBefore - canonical.balanceOf(borrower) == 10 ether, "direct debit");
        require(canonical.balanceOf(lender) - lenderBefore == 10 ether, "direct credit");
        require(bridgeHub.totalBridgeBacking() == backingBefore, "direct backing changed");
        require(
            bridgeHub.loanBacking(LOAN_ID) == loanBackingBefore - 10 ether,
            "direct loan backing not reclassified"
        );
        require(wrapped.totalSupply() == wrappedBefore, "direct wrapped supply changed");
        vm.prank(borrower);
        (bool duplicate,) = address(account)
            .call(abi.encodeCall(CrossChainLoanAccount.directHomeRepayment, (paymentId, 10 ether)));
        require(!duplicate, "direct payment duplicated");
    }

    function _assertAlternateRepaymentRouteRejected() private {
        bytes32 paymentId = keccak256("ALTERNATE_ROUTE_PAYMENT");
        uint256 borrowerBefore = wrapped.balanceOf(borrower);
        vm.chainId(SATELLITE_CHAIN);
        vm.prank(borrower);
        (bool accepted,) = address(wrapped)
            .call(
                abi.encodeCall(
                    WrappedUFT.burnForLoanRepayment,
                    (
                        keccak256("ALTERNATE_ROUTE_BURN"),
                        LOAN_ID,
                        paymentId,
                        alternateRepaymentRoute,
                        1 ether,
                        uint64(block.timestamp + 2 days)
                    )
                )
            );
        require(!accepted, "alternate repayment route accepted");
        require(wrapped.balanceOf(borrower) == borrowerBefore, "alternate route burned funds");
        require(!settlementVault.consumedPayment(paymentId), "alternate route consumed payment");
    }

    function testCancellationAfterMintBurnsEscrowRefundsAndReleasesLockedCollateral() public {
        CancellationFixture memory fixture = _originateCancellationFixture(true);
        bytes32 disbursementMessageId = fixture.account.disbursementMessageId();
        require(disbursementMessageId != bytes32(0), "missing disbursement");
        bytes32 tombstone = _tombstoneDisbursement(disbursementMessageId);
        CrossChainTypes.LoanCancellationAuthorization memory authorization =
            _cancellationAuthorization(
                fixture.account, tombstone, 1, uint64(block.timestamp + 2 days)
            );
        _assertCancellationAuthorizationNegatives(fixture.account, tombstone);
        bytes32 cancellationMessageId = _authorizeCancellation(authorization);
        _executeTombstonedCancellation(fixture, authorization, cancellationMessageId, tombstone);
        _completeCancellationAndClose(fixture, authorization);
    }

    function _authorizeCancellation(
        CrossChainTypes.LoanCancellationAuthorization memory authorization
    ) private returns (bytes32 cancellationMessageId) {
        bytes[] memory signatures = _cancellationSignatures(authorization);
        vm.chainId(HOME_CHAIN);
        cancellationMessageId = loanFactory.authorizeCancellation(authorization, signatures);
        require(
            loanFactory.authorizeCancellation(authorization, signatures) == cancellationMessageId,
            "authorization replay changed"
        );
    }

    function _executeTombstonedCancellation(
        CancellationFixture memory fixture,
        CrossChainTypes.LoanCancellationAuthorization memory authorization,
        bytes32 cancellationMessageId,
        bytes32 tombstone
    ) private {
        CrossChainTypes.LoanCancellationRequestedPayload memory cancellation =
            _cancellationPayload(fixture.account, authorization);
        CrossChainTypes.LoanCancellationRequestedPayload memory forged = abi.decode(
            abi.encode(cancellation), (CrossChainTypes.LoanCancellationRequestedPayload)
        );
        forged.amount += 1;
        _assertExecutionRejected(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            cancellationMessageId,
            abi.encode(forged)
        );
        forged = abi.decode(
            abi.encode(cancellation), (CrossChainTypes.LoanCancellationRequestedPayload)
        );
        forged.disbursementTombstoneHash = bytes32(uint256(tombstone) ^ 1);
        _assertExecutionRejected(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            cancellationMessageId,
            abi.encode(forged)
        );
        uint256 supplyBefore = wrapped.totalSupply();
        bytes memory payload = abi.encode(cancellation);
        bytes32 result = _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            cancellationMessageId,
            payload
        );
        require(supplyBefore - wrapped.totalSupply() == PRINCIPAL, "escrow burn");
        require(wrapped.balanceOf(address(settlementVault)) == 0, "vault retained funds");
        require(
            _execute(
                homeCoordinator,
                satelliteCoordinator,
                satelliteVerifier,
                SATELLITE_CHAIN,
                cancellationMessageId,
                payload
            ) == result,
            "action12 replay changed"
        );
        _assertExecutionRejected(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            fixture.account.disbursementMessageId(),
            _disbursementPayload(fixture.accountAddress)
        );
    }

    function testCancellationWithoutDisbursementWaitsForLateCollateralTruth() public {
        CancellationFixture memory fixture = _originateCancellationFixture(false);
        require(fixture.account.disbursementMessageId() == bytes32(0), "unexpected disbursement");
        CrossChainTypes.LoanCancellationAuthorization memory authorization =
            _cancellationAuthorization(
                fixture.account, bytes32(0), 1, uint64(block.timestamp + 2 days)
            );
        bytes[] memory signatures = _cancellationSignatures(authorization);
        vm.chainId(HOME_CHAIN);
        bytes32 cancellationMessageId = loanFactory.authorizeCancellation(authorization, signatures);
        CrossChainTypes.LoanCancellationRequestedPayload memory cancellation =
            _cancellationPayload(fixture.account, authorization);
        _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            cancellationMessageId,
            abi.encode(cancellation)
        );
        _completeCancellationReport(fixture, authorization);
        require(
            fixture.account.state() == CrossChainTypes.CrossChainLoanState.RECOVERY_PENDING,
            "missing collateral closed early"
        );
        require(fixture.account.fundingRefunded(), "home refund missing");

        vm.chainId(SATELLITE_CHAIN);
        vm.prank(borrower);
        collateral.approve(address(collateralVault), COLLATERAL);
        vm.prank(borrower);
        bytes32 collateralReportMessageId = collateralVault.lockCollateral(LOAN_ID);
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            collateralReportMessageId,
            _collateralReportPayload(fixture.accountAddress)
        );
        require(
            fixture.account.state() == CrossChainTypes.CrossChainLoanState.CLOSING,
            "late collateral truth not released"
        );
        _releaseCollateralAndClose(fixture.account, fixture.accountAddress);
    }

    function testDisbursementWinningRacePreventsCancellationBurnAndRefund() public {
        CancellationFixture memory fixture = _originateCancellationFixture(true);
        bytes32 disbursementMessageId = fixture.account.disbursementMessageId();
        bytes memory disbursementPayload = _disbursementPayload(fixture.accountAddress);
        _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            disbursementMessageId,
            disbursementPayload
        );
        require(wrapped.balanceOf(borrower) == PRINCIPAL, "borrower not paid");
        _assertExecutedDisbursementCannotBeTombstoned(disbursementMessageId);
        (
            bytes32 cancellationMessageId,
            CrossChainTypes.LoanCancellationAuthorization memory cancellationAuthorization
        ) = _assertCancellationCannotDefeatDisbursement(fixture);
        bytes32 settledReportMessageId = satelliteComponent.reportMessage(
            LOAN_ID, CrossChainTypes.ACTION_SATELLITE_DISBURSEMENT_SETTLED
        );
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            settledReportMessageId,
            _disbursementReportPayload(fixture.accountAddress)
        );
        require(
            fixture.account.state() == CrossChainTypes.CrossChainLoanState.ACTIVE,
            "winning disbursement did not activate"
        );
        require(
            fixture.account.outstandingPrincipal() == PRINCIPAL, "winning disbursement debt missing"
        );
        require(!fixture.account.fundingRefunded(), "winning disbursement refunded");
        _assertExecutionRejected(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            cancellationMessageId,
            abi.encode(_cancellationPayload(fixture.account, cancellationAuthorization))
        );
        _assertLateCancellationReportRejected(fixture, cancellationAuthorization);
        _assertRaceWinnerRemainsRepayable(fixture.account);
    }

    function _assertExecutedDisbursementCannotBeTombstoned(bytes32 disbursementMessageId) private {
        CrossChainTypes.MessageEnvelope memory envelope =
            homeCoordinator.messageEnvelope(disbursementMessageId);
        vm.warp(envelope.expiresAt);
        vm.chainId(SATELLITE_CHAIN);
        CrossChainRecoveryController.RecoveryRequest memory recoveryRequest = _recoveryRequest(
            satelliteRecovery,
            envelope,
            1,
            keccak256("DISBURSEMENT_ALREADY_EXECUTED"),
            keccak256("NO_SOURCE_COMPENSATION")
        );
        bytes[] memory recoverySignatures =
            _recoverySignatures(satelliteRecovery, envelope, recoveryRequest);
        (bool tombstoned,) = address(satelliteRecovery)
            .call(
                abi.encodeCall(
                    CrossChainRecoveryController.recordDestinationTombstone,
                    (envelope, recoveryRequest, recoverySignatures)
                )
            );
        require(!tombstoned, "executed disbursement tombstoned");
    }

    function _assertCancellationCannotDefeatDisbursement(CancellationFixture memory fixture)
        private
        returns (
            bytes32 cancellationMessageId,
            CrossChainTypes.LoanCancellationAuthorization memory authorization
        )
    {
        bytes32 fabricatedTombstone = keccak256("FABRICATED_TOMBSTONE");
        authorization = _cancellationAuthorization(
            fixture.account, fabricatedTombstone, 1, uint64(block.timestamp + 2 days)
        );
        vm.chainId(HOME_CHAIN);
        cancellationMessageId = loanFactory.authorizeCancellation(
            authorization, _cancellationSignatures(authorization)
        );
        uint256 lenderBefore = canonical.balanceOf(lender);
        uint256 backingBefore = bridgeHub.totalBridgeBacking();
        _assertExecutionRejected(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            cancellationMessageId,
            abi.encode(_cancellationPayload(fixture.account, authorization))
        );
        require(wrapped.balanceOf(borrower) == PRINCIPAL, "borrower funds cancelled");
        require(wrapped.totalSupply() == PRINCIPAL, "disbursed supply burned");
        require(canonical.balanceOf(lender) == lenderBefore, "lender double refunded");
        require(bridgeHub.totalBridgeBacking() == backingBefore, "backing released");
    }

    function _assertLateCancellationReportRejected(
        CancellationFixture memory fixture,
        CrossChainTypes.LoanCancellationAuthorization memory authorization
    ) private {
        CrossChainTypes.SatelliteFundingCancelledPayload memory report =
            CrossChainTypes.SatelliteFundingCancelledPayload({
                cancellationId: fixture.account.cancellationId(),
                loanId: LOAN_ID,
                fundingLockId: LOCK_ID,
                disbursementMessageId: fixture.account.disbursementMessageId(),
                disbursementTombstoneHash: authorization.disbursementTombstoneHash,
                escrowBurnResultHash: keccak256("IMPOSSIBLE_LATE_CANCELLATION_BURN"),
                homeLoanAccount: fixture.accountAddress,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            });
        vm.chainId(HOME_CHAIN);
        vm.prank(address(homeCoordinator));
        (bool accepted,) = address(loanFactory)
            .call(
                abi.encodeCall(
                    CrossChainLoanFactory.handleCrossChainMessage,
                    (
                        keccak256("IMPOSSIBLE_LATE_CANCELLATION_REPORT"),
                        CrossChainTypes.ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED,
                        abi.encode(report)
                    )
                )
            );
        require(!accepted, "late cancellation report defeated disbursement");
    }

    function _assertRaceWinnerRemainsRepayable(CrossChainLoanAccount account) private {
        vm.chainId(HOME_CHAIN);
        canonical.approve(address(account), 1 ether);
        account.directHomeRepayment(keccak256("RACE_DIRECT_PAYMENT"), 1 ether);
        require(account.outstandingPrincipal() == PRINCIPAL - 1 ether, "direct repayment blocked");
        _burnAndExecuteRepayment(account, 1 ether, keccak256("RACE_REMOTE_PAYMENT"));
        require(account.outstandingPrincipal() == PRINCIPAL - 2 ether, "remote repayment blocked");
    }

    function _originateCancellationFixture(bool lockCollateral)
        private
        returns (CancellationFixture memory fixture)
    {
        vm.chainId(HOME_CHAIN);
        vm.prank(lender);
        canonical.approve(address(bridgeHub), PRINCIPAL);
        vm.prank(lender);
        bytes32 mintMessageId;
        (fixture.accountAddress, mintMessageId) =
            loanFactory.createLoan(_terms(), uint64(block.timestamp + 2 days));
        fixture.account = CrossChainLoanAccount(fixture.accountAddress);
        vm.chainId(SATELLITE_CHAIN);
        satelliteComponent.provisionLoan(loanFactory.satelliteProvisioning(LOAN_ID));
        if (lockCollateral) {
            vm.prank(borrower);
            collateral.approve(address(collateralVault), COLLATERAL);
            vm.prank(borrower);
            fixture.collateralReportMessageId = collateralVault.lockCollateral(LOAN_ID);
        }
        _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            mintMessageId,
            _mintPayload()
        );
        fixture.mintReportMessageId = satelliteComponent.reportMessage(
            LOAN_ID, CrossChainTypes.ACTION_SATELLITE_MINT_CONFIRMED
        );
        if (lockCollateral) {
            _executeReportAfterExpiry(
                satelliteCoordinator,
                homeCoordinator,
                homeVerifier,
                HOME_CHAIN,
                fixture.collateralReportMessageId,
                _collateralReportPayload(fixture.accountAddress)
            );
        }
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            fixture.mintReportMessageId,
            _mintReportPayload(fixture.accountAddress)
        );
    }

    function _tombstoneDisbursement(bytes32 disbursementMessageId)
        private
        returns (bytes32 tombstone)
    {
        CrossChainTypes.MessageEnvelope memory envelope =
            homeCoordinator.messageEnvelope(disbursementMessageId);
        vm.warp(envelope.expiresAt);
        vm.chainId(SATELLITE_CHAIN);
        CrossChainRecoveryController.RecoveryRequest memory request = _recoveryRequest(
            satelliteRecovery,
            envelope,
            1,
            keccak256("PRE_DISBURSEMENT_CANCELLATION"),
            keccak256("CANCELLATION_HAS_NO_SOURCE_COMPENSATION")
        );
        tombstone = satelliteRecovery.recordDestinationTombstone(
            envelope, request, _recoverySignatures(satelliteRecovery, envelope, request)
        );
    }

    function _assertCancellationAuthorizationNegatives(
        CrossChainLoanAccount account,
        bytes32 tombstone
    ) private {
        CrossChainTypes.LoanCancellationAuthorization memory valid =
            _cancellationAuthorization(account, tombstone, 1, uint64(block.timestamp + 2 days));
        bytes[] memory validSignatures = _cancellationSignatures(valid);
        bytes[] memory oneSignature = new bytes[](1);
        oneSignature[0] = validSignatures[0];
        _assertCancellationAuthorizationRejected(valid, oneSignature);

        bytes[] memory duplicateSigner = new bytes[](2);
        duplicateSigner[0] = validSignatures[0];
        duplicateSigner[1] = validSignatures[0];
        _assertCancellationAuthorizationRejected(valid, duplicateSigner);

        bytes[] memory unauthorizedSigner = new bytes[](2);
        unauthorizedSigner[0] = validSignatures[0];
        unauthorizedSigner[1] = _signature(
            UNAUTHORIZED_SIGNER_KEY, homeRecovery.loanCancellationAuthorizationDigest(valid)
        );
        _assertCancellationAuthorizationRejected(valid, unauthorizedSigner);

        CrossChainTypes.LoanCancellationAuthorization memory wrongNonce =
            _cancellationAuthorization(account, tombstone, 2, uint64(block.timestamp + 2 days));
        _assertCancellationAuthorizationRejected(wrongNonce, _cancellationSignatures(wrongNonce));
        CrossChainTypes.LoanCancellationAuthorization memory expired =
            _cancellationAuthorization(account, tombstone, 1, uint64(block.timestamp - 1));
        _assertCancellationAuthorizationRejected(expired, _cancellationSignatures(expired));
        require(account.cancellationId() == bytes32(0), "rejected authorization consumed");
        require(
            homeRecovery.nextLoanCancellationNonce(address(loanFactory), LOAN_ID) == 0,
            "rejected authorization advanced nonce"
        );
        require(
            homeRecovery.cancellationForLoan(address(loanFactory), LOAN_ID) == bytes32(0),
            "rejected authorization stored"
        );
    }

    function _assertCancellationAuthorizationRejected(
        CrossChainTypes.LoanCancellationAuthorization memory authorization,
        bytes[] memory signatures
    ) private {
        vm.chainId(HOME_CHAIN);
        (bool accepted,) = address(loanFactory)
            .call(
                abi.encodeCall(
                    CrossChainLoanFactory.authorizeCancellation, (authorization, signatures)
                )
            );
        require(!accepted, "invalid cancellation authorization");
    }

    function _cancellationAuthorization(
        CrossChainLoanAccount account,
        bytes32 tombstone,
        uint64 nonce,
        uint64 validUntil
    ) private view returns (CrossChainTypes.LoanCancellationAuthorization memory authorization) {
        authorization = CrossChainTypes.LoanCancellationAuthorization({
            loanRouter: address(loanFactory),
            loanId: LOAN_ID,
            fundingLockId: LOCK_ID,
            disbursementMessageId: account.disbursementMessageId(),
            disbursementTombstoneHash: tombstone,
            amount: PRINCIPAL,
            policyHash: POLICY_HASH,
            authorizationNonce: nonce,
            validUntil: validUntil,
            reasonCode: keccak256("GOVERNED_PRE_DISBURSEMENT_CANCELLATION"),
            authorizerSetHash: homeRecovery.authorizerSetHash(),
            authorizerSetVersion: homeRecovery.AUTHORIZER_SET_VERSION()
        });
    }

    function _cancellationSignatures(
        CrossChainTypes.LoanCancellationAuthorization memory authorization
    ) private returns (bytes[] memory signatures) {
        vm.chainId(HOME_CHAIN);
        bytes32 digest = homeRecovery.loanCancellationAuthorizationDigest(authorization);
        signatures = new bytes[](2);
        signatures[0] = _signature(SIGNER_ONE_KEY, digest);
        signatures[1] = _signature(SIGNER_TWO_KEY, digest);
    }

    function _cancellationPayload(
        CrossChainLoanAccount account,
        CrossChainTypes.LoanCancellationAuthorization memory authorization
    ) private view returns (CrossChainTypes.LoanCancellationRequestedPayload memory) {
        bytes32 cancellationId = account.cancellationId();
        return CrossChainTypes.LoanCancellationRequestedPayload({
            cancellationId: cancellationId,
            loanId: LOAN_ID,
            fundingLockId: LOCK_ID,
            disbursementMessageId: account.disbursementMessageId(),
            disbursementTombstoneHash: authorization.disbursementTombstoneHash,
            homeLoanAccount: address(account),
            lender: lender,
            wrappedToken: address(wrapped),
            amount: PRINCIPAL,
            policyHash: POLICY_HASH,
            reasonCode: authorization.reasonCode
        });
    }

    function _completeCancellationAndClose(
        CancellationFixture memory fixture,
        CrossChainTypes.LoanCancellationAuthorization memory authorization
    ) private {
        _completeCancellationReport(fixture, authorization);
        require(
            fixture.account.state() == CrossChainTypes.CrossChainLoanState.CLOSING,
            "locked collateral not closing"
        );
        _releaseCollateralAndClose(fixture.account, fixture.accountAddress);
    }

    function _completeCancellationReport(
        CancellationFixture memory fixture,
        CrossChainTypes.LoanCancellationAuthorization memory authorization
    ) private {
        bytes32 cancellationId = fixture.account.cancellationId();
        bytes32 reportMessageId = satelliteComponent.reportMessage(
            LOAN_ID, CrossChainTypes.ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED
        );
        CrossChainTypes.SatelliteFundingCancelledPayload memory report =
            CrossChainTypes.SatelliteFundingCancelledPayload({
                cancellationId: cancellationId,
                loanId: LOAN_ID,
                fundingLockId: LOCK_ID,
                disbursementMessageId: fixture.account.disbursementMessageId(),
                disbursementTombstoneHash: authorization.disbursementTombstoneHash,
                escrowBurnResultHash: wrapped.cancellationBurnResult(cancellationId),
                homeLoanAccount: fixture.accountAddress,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            });
        CrossChainTypes.SatelliteFundingCancelledPayload memory forged =
            abi.decode(abi.encode(report), (CrossChainTypes.SatelliteFundingCancelledPayload));
        forged.amount += 1;
        _assertExecutionRejected(reportMessageId, abi.encode(forged));
        forged = abi.decode(abi.encode(report), (CrossChainTypes.SatelliteFundingCancelledPayload));
        forged.escrowBurnResultHash = bytes32(uint256(report.escrowBurnResultHash) ^ 1);
        _assertExecutionRejected(reportMessageId, abi.encode(forged));
        forged = abi.decode(abi.encode(report), (CrossChainTypes.SatelliteFundingCancelledPayload));
        forged.disbursementTombstoneHash = bytes32(uint256(report.disbursementTombstoneHash) ^ 1);
        _assertExecutionRejected(reportMessageId, abi.encode(forged));
        uint256 lenderBefore = canonical.balanceOf(lender);
        _executeReportAfterExpiry(
            satelliteCoordinator,
            homeCoordinator,
            homeVerifier,
            HOME_CHAIN,
            reportMessageId,
            abi.encode(report)
        );
        require(canonical.balanceOf(lender) - lenderBefore == PRINCIPAL, "home refund");
        require(bridgeHub.loanBacking(LOAN_ID) == 0, "loan backing retained");
        require(bridgeHub.totalBridgeBacking() == 0, "bridge backing retained");
        require(fixture.account.fundingRefunded(), "account refund state");
    }

    function _mintPayload() private view returns (bytes memory) {
        return abi.encode(
            CrossChainTypes.CanonicalUftLockPayload({
                lockId: LOCK_ID,
                loanId: LOAN_ID,
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(wrapped),
                destinationRecipient: address(settlementVault),
                amount: PRINCIPAL
            })
        );
    }

    function _mintReportPayload(address accountAddress) private view returns (bytes memory) {
        return abi.encode(
            CrossChainTypes.WrappedUftMintedPayload({
                loanId: LOAN_ID,
                lockId: LOCK_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            })
        );
    }

    function _collateralReportPayload(address accountAddress) private view returns (bytes memory) {
        return abi.encode(
            CrossChainTypes.SatelliteCollateralLockedPayload({
                loanId: LOAN_ID,
                collateralId: COLLATERAL_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                collateralToken: address(collateral),
                amount: COLLATERAL,
                policyHash: POLICY_HASH
            })
        );
    }

    function _disbursementPayload(address accountAddress) private view returns (bytes memory) {
        return abi.encode(
            CrossChainTypes.HomeDisbursementAuthorizedPayload({
                loanId: LOAN_ID,
                fundingLockId: LOCK_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            })
        );
    }

    function _disbursementReportPayload(address accountAddress)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(
            CrossChainTypes.SatelliteDisbursementSettledPayload({
                loanId: LOAN_ID,
                fundingLockId: LOCK_ID,
                homeLoanAccount: accountAddress,
                borrower: borrower,
                lender: lender,
                wrappedToken: address(wrapped),
                amount: PRINCIPAL,
                policyHash: POLICY_HASH
            })
        );
    }

    function testTombstoneMustPrecedeCompensationAndRecoveryNonceIsOrdered() public {
        vm.chainId(HOME_CHAIN);
        bytes32 lockId = keccak256("RECOVERY_LOCK");
        uint256 amount = 25 ether;
        canonical.approve(address(bridgeHub), amount);
        uint256 balanceBefore = canonical.balanceOf(address(this));
        bytes32 messageId =
            bridgeHub.lockForBridge(lockId, mintRoute, borrower, amount, NOW + 1 hours);
        CrossChainTypes.MessageEnvelope memory envelope = homeCoordinator.messageEnvelope(messageId);
        vm.warp(NOW + 1 hours);
        vm.chainId(SATELLITE_CHAIN);

        bytes32 reason = keccak256("DESTINATION_TIMEOUT");
        {
            CrossChainRecoveryController.RecoveryRequest memory outOfOrderRequest = _recoveryRequest(
                satelliteRecovery, envelope, 2, reason, keccak256(abi.encode(lockId))
            );
            bytes[] memory outOfOrder =
                _recoverySignatures(satelliteRecovery, envelope, outOfOrderRequest);
            (bool skippedNonce,) = address(satelliteRecovery)
                .call(
                    abi.encodeCall(
                        CrossChainRecoveryController.recordDestinationTombstone,
                        (envelope, outOfOrderRequest, outOfOrder)
                    )
                );
            require(!skippedNonce, "out-of-order recovery nonce");
        }
        {
            CrossChainTypes.MessageEnvelope memory mismatched = envelope;
            mismatched.actionType = CrossChainTypes.CrossChainActionType.ROUTE_GOVERNANCE_V1;
            mismatched.messageId = CrossChainTypes.messageId(mismatched);
            CrossChainRecoveryController.RecoveryRequest memory mismatchRequest = _recoveryRequest(
                satelliteRecovery, mismatched, 1, reason, keccak256(abi.encode(lockId))
            );
            bytes[] memory mismatchSignatures =
                _recoverySignatures(satelliteRecovery, mismatched, mismatchRequest);
            (bool routeMismatch,) = address(satelliteRecovery)
                .call(
                    abi.encodeCall(
                        CrossChainRecoveryController.recordDestinationTombstone,
                        (mismatched, mismatchRequest, mismatchSignatures)
                    )
                );
            require(!routeMismatch, "route-mismatched tombstone");
        }

        // Solidity memory-struct assignment aliases; reload the immutable outbound
        // envelope so the deliberately corrupted copy cannot taint the valid case.
        envelope = homeCoordinator.messageEnvelope(messageId);
        CrossChainRecoveryController.RecoveryRequest memory request = _recoveryRequest(
            satelliteRecovery, envelope, 1, reason, keccak256(abi.encode(lockId))
        );
        bytes[] memory signatures = _recoverySignatures(satelliteRecovery, envelope, request);
        {
            bytes[] memory oversizedAuthorization = new bytes[](4);
            oversizedAuthorization[0] = signatures[0];
            oversizedAuthorization[1] = signatures[1];
            oversizedAuthorization[2] = signatures[0];
            oversizedAuthorization[3] = signatures[1];
            (bool oversizedAccepted,) = address(satelliteRecovery)
                .call(
                    abi.encodeCall(
                        CrossChainRecoveryController.recordDestinationTombstone,
                        (envelope, request, oversizedAuthorization)
                    )
                );
            require(!oversizedAccepted, "oversized recovery authorization");
        }
        bytes32 tombstone =
            satelliteRecovery.recordDestinationTombstone(envelope, request, signatures);
        require(
            satelliteRecovery.recordDestinationTombstone(envelope, request, signatures)
                == tombstone,
            "exact recovery replay"
        );
        {
            CrossChainRecoveryController.RecoveryRequest memory conflictingRequest = _recoveryRequest(
                satelliteRecovery,
                envelope,
                1,
                keccak256("CONFLICTING_REASON"),
                keccak256(abi.encode(lockId))
            );
            bytes[] memory conflictingSignatures =
                _recoverySignatures(satelliteRecovery, envelope, conflictingRequest);
            (bool conflictingAccepted,) = address(satelliteRecovery)
                .call(
                    abi.encodeCall(
                        CrossChainRecoveryController.recordDestinationTombstone,
                        (envelope, conflictingRequest, conflictingSignatures)
                    )
                );
            require(!conflictingAccepted, "conflicting recovery accepted");
        }
        require(satelliteRecovery.nextRecoveryNonce(envelope.laneId) == 1, "recovery nonce");

        vm.chainId(HOME_CHAIN);
        _compensate(envelope, request, signatures, tombstone, lockId);
        require(canonical.balanceOf(address(this)) == balanceBefore, "refund");
        require(bridgeHub.totalBridgeBacking() == 0, "recovery backing");
    }

    function testExpiredOutboundAndDuplicateCollateralProvisioningFailClosed() public {
        bytes memory payload = abi.encode(
            CrossChainTypes.CanonicalUftLockPayload({
                lockId: keccak256("EXPIRED_LOCK"),
                loanId: bytes32(0),
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(wrapped),
                destinationRecipient: borrower,
                amount: 1 ether
            })
        );
        vm.chainId(HOME_CHAIN);
        CrossChainTypes.MessageEnvelope memory envelope = CrossChainMessageBuilder.build(
            homeCoordinator,
            homeRoutes,
            CrossChainMessageBuilder.BuildRequest({
                routePolicyHash: mintRoute,
                sourceComponent: address(bridgeHub),
                aggregateId: keccak256("EXPIRED_AGGREGATE"),
                actionType: CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED,
                payloadHash: keccak256(payload),
                expiresAt: NOW + 10,
                correlationId: keccak256("EXPIRED_AGGREGATE"),
                causationMessageId: bytes32(0),
                supersededMessageId: bytes32(0)
            })
        );
        vm.warp(NOW + 10);
        vm.prank(address(bridgeHub));
        (bool sent,) = address(homeCoordinator)
            .call(abi.encodeCall(CrossChainCoordinator.sendMessage, (envelope, payload)));
        require(!sent, "exact-expiry outbound accepted");

        vm.warp(NOW);
        bytes32 inboundAggregate = keccak256("EXPIRED_INBOUND_AGGREGATE");
        envelope = CrossChainMessageBuilder.build(
            homeCoordinator,
            homeRoutes,
            CrossChainMessageBuilder.BuildRequest({
                routePolicyHash: mintRoute,
                sourceComponent: address(bridgeHub),
                aggregateId: inboundAggregate,
                actionType: CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED,
                payloadHash: keccak256(payload),
                expiresAt: NOW + 10,
                correlationId: inboundAggregate,
                causationMessageId: bytes32(0),
                supersededMessageId: bytes32(0)
            })
        );
        vm.prank(address(bridgeHub));
        require(
            homeCoordinator.sendMessage(envelope, payload) == envelope.messageId,
            "pre-expiry outbound rejected"
        );
        vm.warp(envelope.expiresAt);
        _assertExecutionRejected(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            envelope.messageId,
            payload
        );

        vm.warp(NOW);
        vm.chainId(SATELLITE_CHAIN);
        CrossChainTypes.SatelliteLoanProvisioning memory first =
            _syntheticProvisioning(keccak256("LOAN_A"), address(0xA001));
        satelliteComponent.provisionLoan(first);
        CrossChainTypes.SatelliteLoanProvisioning memory duplicate =
            _syntheticProvisioning(keccak256("LOAN_B"), address(0xA002));
        (bool provisioned,) = address(satelliteComponent)
            .call(abi.encodeCall(SatelliteLoanComponent.provisionLoan, (duplicate)));
        require(!provisioned, "duplicate collateral provisioned");
    }

    function testAlternateWrappedCannotClaimVictimBackingForReleaseOrBurn() public {
        vm.chainId(HOME_CHAIN);
        canonical.approve(address(bridgeHub), 10 ether);
        bridgeHub.lockForBridge(
            keccak256("VICTIM_LOCK"), mintRoute, address(this), 10 ether, NOW + 2 days
        );
        Phase8MaliciousWrappedSource malicious =
            new Phase8MaliciousWrappedSource(satelliteCoordinator, satelliteRoutes);
        bytes32 maliciousExitRoute = _registerBoth(
            _route(
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(malicious),
                HOME_CHAIN,
                address(homeCoordinator),
                address(bridgeHub),
                (uint32(1) << 3) | (uint32(1) << 15),
                keccak256("MALICIOUS_BRIDGE_EXIT")
            )
        );

        bytes32 releaseBurnId = keccak256("MALICIOUS_RELEASE");
        bytes memory releasePayload = abi.encode(
            CrossChainTypes.WrappedUftBurnedPayload({
                burnId: releaseBurnId,
                backingRoutePolicyHash: mintRoute,
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(malicious),
                recipient: address(this),
                amount: 1 ether
            })
        );
        vm.chainId(SATELLITE_CHAIN);
        bytes32 releaseMessageId = malicious.sendClaim(
            maliciousExitRoute,
            releaseBurnId,
            CrossChainTypes.ACTION_SATELLITE_UFT_BURNED,
            releasePayload,
            NOW + 2 days
        );
        _assertExecutionRejected(releaseMessageId, releasePayload);

        bytes32 permanentBurnId = keccak256("MALICIOUS_PERMANENT_BURN");
        bytes memory permanentPayload = abi.encode(
            CrossChainTypes.SatelliteUftPermanentBurnedPayload({
                burnId: permanentBurnId,
                backingRoutePolicyHash: mintRoute,
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(malicious),
                amount: 1 ether
            })
        );
        vm.chainId(SATELLITE_CHAIN);
        bytes32 permanentMessageId = malicious.sendClaim(
            maliciousExitRoute,
            permanentBurnId,
            CrossChainTypes.ACTION_SATELLITE_UFT_PERMANENT_BURNED,
            permanentPayload,
            NOW + 2 days
        );
        _assertExecutionRejected(permanentMessageId, permanentPayload);

        require(bridgeHub.totalBridgeBacking() == 10 ether, "victim backing changed");
        require(!bridgeHub.consumedBurn(releaseBurnId), "malicious release consumed");
        require(!bridgeHub.consumedBurn(permanentBurnId), "malicious burn consumed");
    }

    function testExpiredWrappedExitsRestoreSupplyWithoutHomeDisposition() public {
        vm.chainId(HOME_CHAIN);
        canonical.approve(address(bridgeHub), 10 ether);
        bytes32 lockId = keccak256("RECOVERABLE_WRAPPED_LOCK");
        bytes32 mintMessageId =
            bridgeHub.lockForBridge(lockId, mintRoute, borrower, 10 ether, NOW + 2 days);
        bytes memory mintPayload = abi.encode(
            CrossChainTypes.CanonicalUftLockPayload({
                lockId: lockId,
                loanId: bytes32(0),
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(wrapped),
                destinationRecipient: borrower,
                amount: 10 ether
            })
        );
        _execute(
            homeCoordinator,
            satelliteCoordinator,
            satelliteVerifier,
            SATELLITE_CHAIN,
            mintMessageId,
            mintPayload
        );
        _expireAndCompensateWrappedExit(false, 3 ether, keccak256("RECOVER_NORMAL"));
        _expireAndCompensateWrappedExit(true, 2 ether, keccak256("RECOVER_PERMANENT"));
        require(wrapped.balanceOf(borrower) == 10 ether, "wrapped supply not restored");
        require(wrapped.totalSupply() == 10 ether, "wrapped total not restored");
        require(bridgeHub.totalBridgeBacking() == 10 ether, "home backing disposed");
    }

    function _expireAndCompensateWrappedExit(bool permanent, uint256 amount, bytes32 burnId)
        private
    {
        vm.chainId(SATELLITE_CHAIN);
        vm.prank(borrower);
        bytes32 messageId = wrapped.burnForBridge(
            burnId,
            mintRoute,
            bridgeExitRoute,
            borrower,
            amount,
            permanent,
            uint64(block.timestamp + 1 hours)
        );
        CrossChainTypes.MessageEnvelope memory envelope =
            satelliteCoordinator.messageEnvelope(messageId);
        bytes memory compensationPayload = abi.encode(burnId, borrower);
        vm.warp(envelope.expiresAt);
        vm.chainId(HOME_CHAIN);
        CrossChainRecoveryController.RecoveryRequest memory request = _recoveryRequest(
            homeRecovery,
            envelope,
            1,
            keccak256(abi.encode("WRAPPED_EXIT_TIMEOUT", burnId)),
            keccak256(compensationPayload)
        );
        bytes[] memory signatures = _recoverySignatures(homeRecovery, envelope, request);
        bytes32 tombstone = homeRecovery.recordDestinationTombstone(envelope, request, signatures);
        require(bridgeHub.totalBridgeBacking() == 10 ether, "tombstone released backing");

        vm.chainId(SATELLITE_CHAIN);
        CrossChainTypes.SourceEventProof memory proof =
            _proof(envelope, tombstone, envelope.destinationFinalityPolicyHash);
        CrossChainTypes.FinalityCertificate memory certificate =
            _certificate(satelliteVerifier, envelope, proof);
        bytes32 result = satelliteRecovery.compensateSource(
            envelope, request, signatures, tombstone, compensationPayload, proof, certificate
        );
        require(
            satelliteRecovery.compensateSource(
                envelope, request, signatures, tombstone, compensationPayload, proof, certificate
            ) == result,
            "wrapped compensation replay"
        );
        bytes memory changedAccount = abi.encode(burnId, address(this));
        (bool changedAccepted,) = address(satelliteRecovery)
            .call(
                abi.encodeCall(
                    CrossChainRecoveryController.compensateSource,
                    (envelope, request, signatures, tombstone, changedAccount, proof, certificate)
                )
            );
        require(!changedAccepted, "changed compensation account");
        vm.prank(address(satelliteRecovery));
        (bool changedAction,) = address(wrapped)
            .call(
                abi.encodeCall(
                    WrappedUFT.compensateMessage,
                    (
                        messageId,
                        CrossChainTypes.ACTION_SATELLITE_REPAYMENT_BURNED,
                        compensationPayload
                    )
                )
            );
        require(!changedAction, "changed compensation action");
    }

    function _deployDomains() private {
        roles = new RoleManager(administrator, address(this));
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
        canonical = new Phase8FlowToken("Canonical UFT", "UFT");
        collateral = new Phase8FlowToken("Satellite Collateral", "COL");
        loanRegistry = new LoanRegistry(roles);

        homeChains = new ChainRegistry(roles, HOME_CHAIN);
        satelliteChains = new ChainRegistry(roles, SATELLITE_CHAIN);
        homeEmergency = new EmergencyController(roles);
        satelliteEmergency = new EmergencyController(roles);
        homeRoutes = new RouteRegistry(roles, homeChains, homeEmergency);
        satelliteRoutes = new RouteRegistry(roles, satelliteChains, satelliteEmergency);
        homeVerifier = new SyntheticFinalityVerifier(roles, homeChains);
        satelliteVerifier = new SyntheticFinalityVerifier(roles, satelliteChains);
        homeCoordinator =
            new CrossChainCoordinator(roles, PROTOCOL_ID, HOME_CHAIN, homeRoutes, homeVerifier);
        satelliteCoordinator = new CrossChainCoordinator(
            roles, PROTOCOL_ID, SATELLITE_CHAIN, satelliteRoutes, satelliteVerifier
        );
        signers = [vm.addr(SIGNER_TWO_KEY), vm.addr(SIGNER_THREE_KEY), vm.addr(SIGNER_ONE_KEY)];
        signerSetHash =
            homeVerifier.registerSignerSet(OBSERVER_AUTHORITY, 1, signers, NOW, NOW + 30 days);
        require(
            satelliteVerifier.registerSignerSet(OBSERVER_AUTHORITY, 1, signers, NOW, NOW + 30 days)
                == signerSetHash,
            "signer set mismatch"
        );
        _registerChains(homeChains);
        _registerChains(satelliteChains);
        homeRecovery =
            new CrossChainRecoveryController(homeCoordinator, homeRoutes, homeVerifier, signers);
        satelliteRecovery = new CrossChainRecoveryController(
            satelliteCoordinator, satelliteRoutes, satelliteVerifier, signers
        );
        homeCoordinator.configureRecoveryController(address(homeRecovery));
        satelliteCoordinator.configureRecoveryController(address(satelliteRecovery));
    }

    function _deployComponents() private {
        exposurePolicy = new BridgeExposurePolicy(roles, IUnifiedToken(address(canonical)));
        bridgeHub = new UFTBridgeHub(
            roles,
            IUnifiedToken(address(canonical)),
            homeCoordinator,
            homeRoutes,
            exposurePolicy,
            address(homeRecovery)
        );
        wrapped = new WrappedUFT(
            roles,
            HOME_CHAIN,
            address(canonical),
            address(bridgeHub),
            satelliteCoordinator,
            satelliteRoutes,
            address(satelliteRecovery)
        );
        satelliteComponent =
            new SatelliteLoanComponent(roles, satelliteCoordinator, satelliteRoutes);
        collateralVault = new SatelliteCollateralVault(
            address(satelliteComponent), satelliteCoordinator, IERC20(address(collateral))
        );
        settlementVault = new SatelliteSettlementVault(
            address(satelliteComponent), satelliteCoordinator, IERC20(address(wrapped))
        );
        accountDeployer = new CrossChainLoanAccountDeployer(roles);
        loanFactory = new CrossChainLoanFactory(
            roles, loanRegistry, bridgeHub, homeCoordinator, homeRoutes, accountDeployer
        );
        accountDeployer.bindFactory(address(loanFactory));
        roles.grantRole(ProtocolRoles.LOAN_FACTORY_ROLE, address(loanFactory), type(uint64).max);
    }

    function _registerRoutes() private {
        mintRoute = _registerBoth(
            _route(
                HOME_CHAIN,
                address(homeCoordinator),
                address(bridgeHub),
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(wrapped),
                uint32(1) << 1,
                keccak256("BRIDGE_LOCK")
            )
        );
        reportRoute = _registerBoth(
            _route(
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(satelliteComponent),
                HOME_CHAIN,
                address(homeCoordinator),
                address(loanFactory),
                (uint32(1) << 2) | (uint32(1) << 5) | (uint32(1) << 7) | (uint32(1) << 10)
                    | (uint32(1) << 14),
                keccak256("LOAN_REPORT")
            )
        );
        repaymentRoute = _registerBoth(
            _route(
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(wrapped),
                HOME_CHAIN,
                address(homeCoordinator),
                address(loanFactory),
                uint32(1) << 8,
                keccak256("LOAN_REPAYMENT")
            )
        );
        alternateRepaymentRoute = _registerBoth(
            _route(
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(wrapped),
                HOME_CHAIN,
                address(homeCoordinator),
                address(loanFactory),
                uint32(1) << 8,
                keccak256("ALTERNATE_LOAN_REPAYMENT")
            )
        );
        bridgeExitRoute = _registerBoth(
            _route(
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(wrapped),
                HOME_CHAIN,
                address(homeCoordinator),
                address(bridgeHub),
                (uint32(1) << 3) | (uint32(1) << 15),
                keccak256("BRIDGE_EXIT")
            )
        );
        disbursementRoute = _registerBoth(
            _route(
                HOME_CHAIN,
                address(homeCoordinator),
                address(loanFactory),
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(settlementVault),
                (uint32(1) << 6) | (uint32(1) << 12),
                keccak256("LOAN_DISBURSEMENT")
            )
        );
        collateralReleaseRoute = _registerBoth(
            _route(
                HOME_CHAIN,
                address(homeCoordinator),
                address(loanFactory),
                SATELLITE_CHAIN,
                address(satelliteCoordinator),
                address(collateralVault),
                uint32(1) << 9,
                keccak256("COLLATERAL_RELEASE")
            )
        );
    }

    function _bindPolicies() private {
        bytes32 exposureHash = exposurePolicy.registerPolicy(
            BridgeExposurePolicy.ExposureConfig({
                circulatingSupplyReference: canonical.totalSupply(),
                circulatingSupplyEvidenceHash: keccak256("GENESIS_CIRCULATION"),
                routeAbsoluteCap: 50_000 ether,
                chainAbsoluteCap: 100_000 ether,
                adapterAbsoluteCap: 100_000 ether,
                aggregateAbsoluteCap: 150_000 ether,
                routePercentageCeilingBps: 500,
                aggregatePercentageCeilingBps: 1_500,
                activationDelay: 0,
                activeFrom: NOW
            })
        );
        exposurePolicy.activateForRoute(mintRoute, exposureHash);
        wrapped.configureCanonicalBackingRoute(mintRoute);
        satelliteComponent.configureInfrastructure(
            address(loanFactory),
            address(wrapped),
            address(collateral),
            address(collateralVault),
            address(settlementVault),
            reportRoute,
            mintRoute,
            repaymentRoute
        );
        wrapped.configureLoanSettlementVault(address(settlementVault));
        ICrossChainLoanPolicy.Configuration memory config = ICrossChainLoanPolicy.Configuration({
            protocolId: PROTOCOL_ID,
            homeChainId: HOME_CHAIN,
            satelliteChainId: SATELLITE_CHAIN,
            homeCoordinator: address(homeCoordinator),
            satelliteCoordinator: address(satelliteCoordinator),
            homeLoanRouter: address(loanFactory),
            homeBridgeHub: address(bridgeHub),
            wrappedUFT: address(wrapped),
            satelliteComponent: address(satelliteComponent),
            satelliteCollateralVault: address(collateralVault),
            satelliteSettlementVault: address(settlementVault),
            canonicalUFT: address(canonical),
            collateralToken: address(collateral),
            mintRouteHash: mintRoute,
            reportRouteHash: reportRoute,
            repaymentRouteHash: repaymentRoute,
            disbursementRouteHash: disbursementRoute,
            collateralReleaseRouteHash: collateralReleaseRoute,
            policyHash: POLICY_HASH
        });
        loanPolicy = new CrossChainLoanPolicy(config);
        loanFactory.bindPolicy(loanPolicy);
    }

    function _burnAndExecuteRepayment(
        CrossChainLoanAccount account,
        uint256 amount,
        bytes32 paymentId
    ) private {
        uint256 principalBefore = account.outstandingPrincipal();
        vm.chainId(SATELLITE_CHAIN);
        bytes32 burnId = keccak256(abi.encode("BURN", paymentId));
        vm.prank(borrower);
        bytes32 messageId = wrapped.burnForLoanRepayment(
            burnId, LOAN_ID, paymentId, repaymentRoute, amount, uint64(block.timestamp + 2 days)
        );
        bytes memory payload = abi.encode(
            CrossChainTypes.SatelliteRepaymentBurnedPayload({
                burnId: burnId,
                loanId: LOAN_ID,
                paymentId: paymentId,
                backingRoutePolicyHash: mintRoute,
                canonicalToken: address(canonical),
                homeBridgeHub: address(bridgeHub),
                wrappedToken: address(wrapped),
                lender: lender,
                amount: amount
            })
        );
        _execute(
            satelliteCoordinator, homeCoordinator, homeVerifier, HOME_CHAIN, messageId, payload
        );
        require(
            account.outstandingPrincipal() == principalBefore - amount,
            "payment did not reduce debt exactly once"
        );
        bytes32 repaymentKey = account.repaymentOperationKey(paymentId);
        require(account.processedOperations(repaymentKey), "repayment key not consumed");
        if (account.state() == CrossChainTypes.CrossChainLoanState.ACTIVE) {
            vm.chainId(HOME_CHAIN);
            (bool duplicateAcrossChannels,) = address(account)
                .call(abi.encodeCall(CrossChainLoanAccount.directHomeRepayment, (paymentId, 1)));
            require(!duplicateAcrossChannels, "cross-channel payment replay");
        }
    }

    function _execute(
        CrossChainCoordinator source,
        CrossChainCoordinator destination,
        SyntheticFinalityVerifier destinationVerifier,
        uint256 destinationChainId,
        bytes32 messageId,
        bytes memory payload
    ) private returns (bytes32 resultHash) {
        CrossChainTypes.MessageEnvelope memory envelope = source.messageEnvelope(messageId);
        vm.chainId(destinationChainId);
        CrossChainTypes.SourceEventProof memory proof = _proof(
            envelope, source.sourceMessageEventHash(envelope), envelope.sourceFinalityPolicyHash
        );
        CrossChainTypes.FinalityCertificate memory certificate =
            _certificate(destinationVerifier, envelope, proof);
        resultHash = destination.executeMessage(envelope, payload, proof, certificate);
    }

    function _executeReportAfterExpiry(
        CrossChainCoordinator source,
        CrossChainCoordinator destination,
        SyntheticFinalityVerifier destinationVerifier,
        uint256 destinationChainId,
        bytes32 messageId,
        bytes memory payload
    ) private returns (bytes32 resultHash) {
        CrossChainTypes.MessageEnvelope memory envelope = source.messageEnvelope(messageId);
        require(CrossChainTypes.isReportAction(envelope.actionType), "not report");
        vm.warp(uint256(envelope.expiresAt) + 1);
        resultHash = _execute(
            source, destination, destinationVerifier, destinationChainId, messageId, payload
        );
        require(
            _execute(
                source, destination, destinationVerifier, destinationChainId, messageId, payload
            ) == resultHash,
            "late report replay changed"
        );
    }

    function _assertExecutionRejected(bytes32 messageId, bytes memory payload) private {
        _assertExecutionRejected(
            satelliteCoordinator, homeCoordinator, homeVerifier, HOME_CHAIN, messageId, payload
        );
    }

    function _assertExecutionRejected(
        CrossChainCoordinator source,
        CrossChainCoordinator destination,
        SyntheticFinalityVerifier destinationVerifier,
        uint256 destinationChainId,
        bytes32 messageId,
        bytes memory payload
    ) private {
        CrossChainTypes.MessageEnvelope memory envelope = source.messageEnvelope(messageId);
        vm.chainId(destinationChainId);
        CrossChainTypes.SourceEventProof memory proof = _proof(
            envelope, source.sourceMessageEventHash(envelope), envelope.sourceFinalityPolicyHash
        );
        CrossChainTypes.FinalityCertificate memory certificate =
            _certificate(destinationVerifier, envelope, proof);
        (bool accepted,) = address(destination)
            .call(
                abi.encodeCall(
                    CrossChainCoordinator.executeMessage, (envelope, payload, proof, certificate)
                )
            );
        require(!accepted, "expired/malicious message executed");
    }

    function _compensate(
        CrossChainTypes.MessageEnvelope memory envelope,
        CrossChainRecoveryController.RecoveryRequest memory request,
        bytes[] memory signatures,
        bytes32 tombstone,
        bytes32 lockId
    ) private {
        CrossChainTypes.SourceEventProof memory proof = _proof(
            envelope, tombstone, envelope.destinationFinalityPolicyHash
        );
        CrossChainTypes.FinalityCertificate memory certificate =
            _certificate(homeVerifier, envelope, proof);
        bytes32 result = homeRecovery.compensateSource(
            envelope, request, signatures, tombstone, abi.encode(lockId), proof, certificate
        );
        require(
            homeRecovery.compensateSource(
                envelope, request, signatures, tombstone, abi.encode(lockId), proof, certificate
            ) == result,
            "exact compensation replay"
        );
        (bool changedPayload,) = address(homeRecovery)
            .call(
                abi.encodeCall(
                    CrossChainRecoveryController.compensateSource,
                    (
                        envelope,
                        request,
                        signatures,
                        tombstone,
                        abi.encode(bytes32(uint256(lockId) ^ 1)),
                        proof,
                        certificate
                    )
                )
            );
        require(!changedPayload, "changed compensation payload replay");
        (bool changedTombstone,) = address(homeRecovery)
            .call(
                abi.encodeCall(
                    CrossChainRecoveryController.compensateSource,
                    (
                        envelope,
                        request,
                        signatures,
                        bytes32(uint256(tombstone) ^ 1),
                        abi.encode(lockId),
                        proof,
                        certificate
                    )
                )
            );
        require(!changedTombstone, "changed tombstone replay");
    }

    function _acknowledge(
        CrossChainCoordinator source,
        SyntheticFinalityVerifier sourceVerifier,
        bytes32 messageId,
        bytes32 destinationResultHash
    ) private {
        CrossChainTypes.MessageEnvelope memory envelope = source.messageEnvelope(messageId);
        bytes32 commitment = source.acknowledgementEventHash(envelope, destinationResultHash);
        vm.chainId(source.localChainId());
        CrossChainTypes.SourceEventProof memory proof =
            _proof(envelope, commitment, envelope.destinationFinalityPolicyHash);
        CrossChainTypes.FinalityCertificate memory certificate =
            _certificate(sourceVerifier, envelope, proof);
        require(
            source.recordAcknowledgement(envelope, destinationResultHash, proof, certificate)
                == commitment,
            "acknowledgement"
        );
        require(
            source.recordAcknowledgement(envelope, destinationResultHash, proof, certificate)
                == commitment,
            "acknowledgement replay"
        );
        (bool conflict,) = address(source)
            .call(
                abi.encodeCall(
                    CrossChainCoordinator.recordAcknowledgement,
                    (envelope, bytes32(uint256(destinationResultHash) ^ 1), proof, certificate)
                )
            );
        require(!conflict, "acknowledgement conflict");
    }

    function _assertChangedReplayRejected(
        CrossChainCoordinator source,
        CrossChainCoordinator destination,
        SyntheticFinalityVerifier destinationVerifier,
        uint256 destinationChainId,
        bytes32 messageId,
        bytes memory exactPayload
    ) private {
        CrossChainTypes.MessageEnvelope memory envelope = source.messageEnvelope(messageId);
        vm.chainId(destinationChainId);
        CrossChainTypes.SourceEventProof memory proof = _proof(
            envelope, source.sourceMessageEventHash(envelope), envelope.sourceFinalityPolicyHash
        );
        CrossChainTypes.FinalityCertificate memory certificate =
            _certificate(destinationVerifier, envelope, proof);
        bytes memory changed = bytes.concat(exactPayload, hex"00");
        (bool success,) = address(destination)
            .call(
                abi.encodeCall(
                    CrossChainCoordinator.executeMessage, (envelope, changed, proof, certificate)
                )
            );
        require(!success, "changed replay payload");
    }

    function _proof(
        CrossChainTypes.MessageEnvelope memory envelope,
        bytes32 eventHash,
        bytes32 finalityPolicy
    ) private pure returns (CrossChainTypes.SourceEventProof memory proof) {
        proof = CrossChainTypes.SourceEventProof({
            sourceBlockHash: keccak256(abi.encode("BLOCK", envelope.messageId)),
            sourceBlockNumber: 100,
            sourceBlockTimestamp: envelope.createdAt,
            transactionHash: keccak256(abi.encode("TX", envelope.messageId)),
            transactionIndex: 1,
            receiptRoot: keccak256(abi.encode("ROOT", envelope.messageId)),
            receiptProofHash: keccak256(abi.encode("PROOF", envelope.messageId)),
            logIndex: 1,
            eventHash: eventHash,
            finalityHeadHash: keccak256(abi.encode("HEAD", envelope.messageId)),
            finalityHeadNumber: 112,
            requiredDepth: 12,
            headerAuthorityHash: OBSERVER_AUTHORITY,
            observerSignedHeaderCommitment: bytes32(0),
            observerSignature: hex"01020304",
            finalityPolicyHash: finalityPolicy
        });
        proof.observerSignedHeaderCommitment = CrossChainTypes.observerHeaderCommitment(proof);
    }

    function _certificate(
        SyntheticFinalityVerifier destinationVerifier,
        CrossChainTypes.MessageEnvelope memory envelope,
        CrossChainTypes.SourceEventProof memory proof
    ) private returns (CrossChainTypes.FinalityCertificate memory certificate) {
        bytes32 proofHash = CrossChainTypes.sourceProofHash(proof);
        bytes32 digest = CrossChainTypes.finalityCertificateDigest(
            address(destinationVerifier),
            block.chainid,
            envelope.messageId,
            proofHash,
            signerSetHash,
            1
        );
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signature(SIGNER_ONE_KEY, digest);
        signatures[1] = _signature(SIGNER_TWO_KEY, digest);
        certificate = CrossChainTypes.FinalityCertificate({
            messageId: envelope.messageId,
            sourceProofHash: proofHash,
            signerSetHash: signerSetHash,
            signerSetVersion: 1,
            signatures: signatures
        });
    }

    function _recoverySignatures(
        CrossChainRecoveryController controller,
        CrossChainTypes.MessageEnvelope memory envelope,
        CrossChainRecoveryController.RecoveryRequest memory request
    ) private returns (bytes[] memory signatures) {
        bytes32 digest = controller.recoveryAuthorizationDigest(envelope, request);
        signatures = new bytes[](2);
        signatures[0] = _signature(SIGNER_ONE_KEY, digest);
        signatures[1] = _signature(SIGNER_TWO_KEY, digest);
    }

    function _recoveryRequest(
        CrossChainRecoveryController controller,
        CrossChainTypes.MessageEnvelope memory envelope,
        uint64 nonce,
        bytes32 reason,
        bytes32 compensationPayloadHash
    ) private view returns (CrossChainRecoveryController.RecoveryRequest memory request) {
        request = CrossChainRecoveryController.RecoveryRequest({
            messageId: envelope.messageId,
            envelopeHash: keccak256(abi.encode(envelope)),
            routePolicyHash: envelope.routePolicyHash,
            assetAmountCommitment: keccak256(
                abi.encode(
                    "UNIFIED_RECOVERY_ASSET_AMOUNT_COMMITMENT_V1",
                    envelope.actionType,
                    envelope.payloadHash
                )
            ),
            sourceStateCommitment: keccak256("SOURCE_LOCKED"),
            destinationStateCommitment: keccak256("DESTINATION_NOT_EXECUTED"),
            compensationPayloadHash: compensationPayloadHash,
            messageExpiresAt: envelope.expiresAt,
            recoveryNonce: nonce,
            reasonCode: reason,
            action: CrossChainRecoveryController.RecoveryAction.TOMBSTONE_THEN_COMPENSATE,
            authorizerSetHash: controller.authorizerSetHash(),
            authorizerSetVersion: controller.AUTHORIZER_SET_VERSION()
        });
    }

    function _signature(uint256 key, bytes32 digest) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _registerChains(ChainRegistry registry) private {
        registry.registerChain(
            HOME_CHAIN,
            address(homeCoordinator),
            address(homeVerifier),
            address(homeCoordinator).codehash,
            address(homeVerifier).codehash,
            keccak256("HOME_CONFIGURATION"),
            NOW
        );
        registry.registerChain(
            SATELLITE_CHAIN,
            address(satelliteCoordinator),
            address(satelliteVerifier),
            address(satelliteCoordinator).codehash,
            address(satelliteVerifier).codehash,
            keccak256("SATELLITE_CONFIGURATION"),
            NOW
        );
    }

    function _registerBoth(RouteRegistry.RouteConfig memory config)
        private
        returns (bytes32 routeHash)
    {
        config.sourceFinalityPolicyHash =
            _registerFinalityPolicyBoth(_finalityPolicy(config, false));
        config.destinationFinalityPolicyHash =
            _registerFinalityPolicyBoth(_finalityPolicy(config, true));
        routeHash = homeRoutes.registerRoute(config);
        require(satelliteRoutes.registerRoute(config) == routeHash, "route hash");
    }

    function _registerFinalityPolicyBoth(
        SyntheticFinalityVerifier.FinalityPolicyConfig memory config
    ) private returns (bytes32 policyHash) {
        policyHash = homeVerifier.registerFinalityPolicy(config);
        require(
            satelliteVerifier.registerFinalityPolicy(config) == policyHash,
            "finality policy mismatch"
        );
    }

    function _finalityPolicy(RouteRegistry.RouteConfig memory route, bool destinationEvidence)
        private
        view
        returns (SyntheticFinalityVerifier.FinalityPolicyConfig memory)
    {
        uint256 evidenceChainId =
            destinationEvidence ? route.destinationChainId : route.sourceChainId;
        return SyntheticFinalityVerifier.FinalityPolicyConfig({
            destinationEvidence: destinationEvidence,
            sourceChainId: route.sourceChainId,
            sourceCoordinator: route.sourceCoordinator,
            sourceComponent: route.sourceComponent,
            destinationChainId: route.destinationChainId,
            destinationCoordinator: route.destinationCoordinator,
            destinationComponent: route.destinationComponent,
            evidenceChainVersion: destinationEvidence
                ? route.destinationChainVersion
                : route.sourceChainVersion,
            evidenceChainConfigurationHash: evidenceChainId == HOME_CHAIN
                ? keccak256("HOME_CONFIGURATION")
                : keccak256("SATELLITE_CONFIGURATION"),
            actionFamily: route.actionFamily,
            allowedActionsBitmap: route.allowedActionsBitmap,
            requiredDepth: 12,
            observerAuthorityHash: OBSERVER_AUTHORITY,
            signerSetHash: signerSetHash,
            signerSetVersion: 1
        });
    }

    function _route(
        uint256 sourceChainId,
        address sourceCoordinator,
        address sourceComponent,
        uint256 destinationChainId,
        address destinationCoordinator,
        address destinationComponent,
        uint32 allowedActions,
        bytes32 actionFamily
    ) private view returns (RouteRegistry.RouteConfig memory config) {
        bytes32 adapterId = keccak256(abi.encode("ADAPTER", actionFamily));
        config = RouteRegistry.RouteConfig({
            sourceChainVersion: 1,
            destinationChainVersion: 1,
            sourceChainId: sourceChainId,
            sourceCoordinator: sourceCoordinator,
            sourceComponent: sourceComponent,
            sourceComponentCodeHash: sourceComponent.codehash,
            destinationChainId: destinationChainId,
            destinationCoordinator: destinationCoordinator,
            destinationComponent: destinationComponent,
            destinationComponentCodeHash: destinationComponent.codehash,
            actionFamily: actionFamily,
            allowedActionsBitmap: allowedActions,
            adapterId: adapterId,
            adapterCodeHash: keccak256(abi.encode("ADAPTER_CODE", adapterId)),
            adapterSetPolicyHash: keccak256(abi.encode("ADAPTER_SET", adapterId)),
            sourceFinalityPolicyHash: bytes32(0),
            destinationFinalityPolicyHash: bytes32(0),
            sourceSignerSetHash: signerSetHash,
            destinationSignerSetHash: signerSetHash,
            absoluteCap: 50_000 ether,
            chainCap: 100_000 ether,
            adapterCap: 100_000 ether,
            activatedAt: NOW
        });
    }

    function _terms() private view returns (CrossChainTypes.CrossChainLoanTerms memory) {
        return CrossChainTypes.CrossChainLoanTerms({
            loanId: LOAN_ID,
            agreementHash: keccak256("PHASE8_AGREEMENT"),
            fundingLockId: LOCK_ID,
            collateralId: COLLATERAL_ID,
            borrower: borrower,
            lender: lender,
            principalAmount: PRINCIPAL,
            collateralAmount: COLLATERAL,
            policyHash: POLICY_HASH
        });
    }

    function _syntheticProvisioning(bytes32 loanId, address homeAccount)
        private
        view
        returns (CrossChainTypes.SatelliteLoanProvisioning memory)
    {
        return CrossChainTypes.SatelliteLoanProvisioning({
            loanId: loanId,
            fundingLockId: keccak256(abi.encode("LOCK", loanId)),
            homeLoanAccount: homeAccount,
            homeLoanRouter: address(loanFactory),
            borrower: borrower,
            lender: lender,
            wrappedToken: address(wrapped),
            collateralToken: address(collateral),
            collateralId: keccak256("SHARED_COLLATERAL"),
            principalAmount: PRINCIPAL,
            collateralAmount: COLLATERAL,
            repaymentRoutePolicyHash: repaymentRoute,
            policyHash: POLICY_HASH
        });
    }
}
