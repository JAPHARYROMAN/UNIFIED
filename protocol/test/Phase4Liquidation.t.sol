// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { LoanTypes } from "../src/loan/LoanTypes.sol";
import { CollateralManager } from "../src/collateral/CollateralManager.sol";
import { CollateralVault } from "../src/collateral/CollateralVault.sol";
import { LiquidationEngine } from "../src/collateral/LiquidationEngine.sol";
import { IOracleAdapter, OracleRouter } from "../src/risk/OracleRouter.sol";
import { RiskTypes } from "../src/risk/RiskTypes.sol";
import { ServicingEngine } from "../src/risk/ServicingEngine.sol";

interface LiquidationVm {
    function prank(address sender) external;
    function warp(uint256 timestamp) external;
}

contract LiquidationToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract LiquidationNFT is ERC721 {
    constructor(address owner) ERC721("Liquidation NFT", "LNFT") {
        _mint(owner, 1);
    }
}

contract LiquidationOracleAdapter is IOracleAdapter {
    uint256 public value;
    uint64 public observedAt;
    uint64 public roundId;

    function set(uint256 value_, uint64 observedAt_, uint64 roundId_) external {
        value = value_;
        observedAt = observedAt_;
        roundId = roundId_;
    }

    function latest(bytes32, bytes32) external view returns (uint256, uint8, uint64, uint64) {
        return (value, 18, observedAt, roundId);
    }
}

contract LiquidationLoanRegistry is ILoanRegistry {
    struct Loan {
        address account;
        address borrower;
        bool terminal;
    }

    mapping(bytes32 loanId => Loan loan) private _loans;

    function seed(bytes32 loanId, address account, address borrower) external {
        _loans[loanId] = Loan({ account: account, borrower: borrower, terminal: false });
    }

    function setTerminal(bytes32 loanId, bool terminal) external {
        _loans[loanId].terminal = terminal;
    }

    function registerLoan(bytes32, address, address, bytes32, uint32) external { }

    function loanAccount(bytes32 loanId) external view returns (address) {
        return _loans[loanId].account;
    }

    function borrowerOf(bytes32 loanId) external view returns (address) {
        return _loans[loanId].borrower;
    }

    function agreementHashOf(bytes32) external pure returns (bytes32) {
        return keccak256("LIQUIDATION_TEST_AGREEMENT");
    }

    function protocolVersionOf(bytes32) external pure returns (uint32) {
        return 4;
    }

    function exists(bytes32 loanId) external view returns (bool) {
        return _loans[loanId].account != address(0);
    }

    function isTerminal(bytes32 loanId) external view returns (bool) {
        return _loans[loanId].terminal;
    }

    function markTerminal(bytes32 loanId) external {
        _loans[loanId].terminal = true;
    }
}

contract LiquidationDebt {
    IERC20 public immutable settlementToken;
    LiquidationLoanRegistry public immutable registry;
    address public immutable lender;
    bytes32 public immutable loanId;
    uint256 public outstandingPrincipal;
    LoanTypes.UniversalLoanTerms private _terms;

    constructor(
        IERC20 token,
        LiquidationLoanRegistry registry_,
        bytes32 loanId_,
        bytes32 settlementAssetId,
        bytes32 policySetHash,
        address borrower,
        address lender_,
        uint256 principal
    ) {
        settlementToken = token;
        registry = registry_;
        loanId = loanId_;
        lender = lender_;
        outstandingPrincipal = principal;
        _terms.loanId = loanId_;
        _terms.agreementHash = keccak256("LIQUIDATION_TEST_AGREEMENT");
        _terms.parties.borrower = borrower;
        _terms.principal =
            LoanTypes.MonetaryAmount({ assetId: settlementAssetId, amount: principal });
        _terms.commencementTime = uint64(block.timestamp);
        _terms.finalMaturityTime = uint64(block.timestamp + 365 days);
        _terms.protocolVersion = 4;
        _terms.policySetHash = policySetHash;
        _terms.metadataHash = keccak256("LIQUIDATION_TEST_METADATA");
    }

    function setOutstanding(uint256 outstanding) external {
        outstandingPrincipal = outstanding;
    }

    function terms() external view returns (LoanTypes.UniversalLoanTerms memory) {
        return _terms;
    }

    function repay(bytes32 paymentId, uint256 amount, bytes32 journalRef) external {
        require(paymentId != bytes32(0) && journalRef != bytes32(0), "missing evidence");
        require(amount != 0 && amount <= outstandingPrincipal, "invalid recovery");
        outstandingPrincipal -= amount;
        require(settlementToken.transferFrom(msg.sender, lender, amount), "payment failed");
        if (outstandingPrincipal == 0) registry.markTerminal(loanId);
    }
}

contract Phase4LiquidationTest {
    LiquidationVm private constant vm =
        LiquidationVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 private constant NOW = 1_800_000_000;
    bytes32 private constant LOAN_ID = keccak256("LIQUIDATION_LOAN");
    bytes32 private constant POLICY_SET = keccak256("POLICY_SET_V4");
    bytes32 private constant SETTLEMENT_ID = keccak256("ASSET:SETTLEMENT");
    bytes32 private constant COLLATERAL_ID = keccak256("ASSET:COLLATERAL");
    bytes32 private constant NFT_ASSET_ID = keccak256("ASSET:NFT");
    bytes32 private constant UFT_ID = keccak256("ASSET:UFT");
    bytes32 private constant FUNGIBLE_POSITION = keccak256("COLLATERAL:FUNGIBLE");
    bytes32 private constant NFT_POSITION = keccak256("COLLATERAL:NFT");

    address private borrower = address(0xB0B);
    address private lender = address(0x1EAD);
    address private treasury = address(0x7EA5);
    address private firstBidder = address(0xB1D1);
    address private secondBidder = address(0xB1D2);

    RoleManager private roles;
    AssetRegistry private assets;
    LiquidationLoanRegistry private loans;
    LiquidationDebt private debt;
    LiquidationToken private settlementToken;
    LiquidationToken private collateralToken;
    LiquidationToken private uft;
    LiquidationNFT private nft;
    CollateralManager private collateral;
    OracleRouter private oracle;
    ServicingEngine private servicing;
    LiquidationEngine private engine;
    LiquidationOracleAdapter[3] private adapters;

    function setUp() public {
        vm.warp(NOW);
        roles = new RoleManager(address(0xA11CE), address(this));
        roles.grantRole(ProtocolRoles.ASSET_REGISTRAR_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.ORACLE_MANAGER_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.SERVICER_ROLE, address(this), type(uint64).max);

        assets = new AssetRegistry(roles);
        settlementToken = new LiquidationToken("Settlement", "SET");
        collateralToken = new LiquidationToken("Collateral", "COL");
        uft = new LiquidationToken("Unified", "UFT");
        nft = new LiquidationNFT(borrower);
        assets.registerAsset(SETTLEMENT_ID, address(settlementToken), 18, keccak256("SET"));
        assets.registerAsset(COLLATERAL_ID, address(collateralToken), 18, keccak256("COL"));
        assets.registerAsset(NFT_ASSET_ID, address(nft), 0, keccak256("NFT"));
        assets.registerAsset(UFT_ID, address(uft), 18, keccak256("UFT"));

        loans = new LiquidationLoanRegistry();
        debt = new LiquidationDebt(
            settlementToken, loans, LOAN_ID, SETTLEMENT_ID, POLICY_SET, borrower, lender, 150 ether
        );
        loans.seed(LOAN_ID, address(debt), borrower);
        collateral = new CollateralManager(roles, loans, assets, UFT_ID, uft);
        collateral.configureAsset(
            COLLATERAL_ID, address(collateralToken), RiskTypes.CollateralKind.ERC20, true, false
        );
        collateral.configureAsset(
            NFT_ASSET_ID, address(nft), RiskTypes.CollateralKind.ERC721, true, false
        );

        oracle = new OracleRouter(roles);
        servicing = new ServicingEngine(roles);
        _configureOracle(COLLATERAL_ID);
        _configureOracle(NFT_ASSET_ID);
        engine =
            new LiquidationEngine(roles, loans, collateral, servicing, oracle, assets, treasury);
        collateral.configureLiquidationEngine(address(engine));

        collateralToken.mint(borrower, 100 ether);
        settlementToken.mint(firstBidder, 1_000 ether);
        settlementToken.mint(secondBidder, 1_000 ether);
        vm.prank(borrower);
        address vault = collateral.createVault(LOAN_ID);
        vm.prank(borrower);
        collateralToken.approve(vault, type(uint256).max);
        vm.prank(borrower);
        nft.setApprovalForAll(vault, true);
        vm.prank(borrower);
        collateral.lockERC20(LOAN_ID, FUNGIBLE_POSITION, COLLATERAL_ID, 100 ether);
        vm.prank(borrower);
        collateral.lockERC721(LOAN_ID, NFT_POSITION, NFT_ASSET_ID, 1);
        servicing.configure(LOAN_ID, 150 ether, NOW + 10, NOW + 20, NOW + 30);

        vm.prank(firstBidder);
        settlementToken.approve(address(engine), type(uint256).max);
        vm.prank(secondBidder);
        settlementToken.approve(address(engine), type(uint256).max);
    }

    function testNoPrematureLiquidationPlan() public {
        LiquidationEngine.PlanRequest memory request = _request(
            keccak256("PREMATURE"),
            FUNGIBLE_POSITION,
            LiquidationEngine.SaleKind.DIRECT,
            50 ether,
            8_000,
            0,
            0,
            0
        );
        RiskTypes.OracleObservation memory observation = oracle.price(COLLATERAL_ID, SETTLEMENT_ID);
        (bool accepted,) =
            address(engine).call(abi.encodeCall(engine.startLiquidation, (request, observation)));
        require(!accepted, "liquidation started before default");
        require(
            collateralToken.balanceOf(collateral.vaultOf(LOAN_ID)) == 100 ether,
            "premature path moved collateral"
        );
    }

    function testPartialDirectSaleRecordsResidualBadDebt() public {
        _defaultLoan();
        bytes32 liquidationId = keccak256("PARTIAL_DIRECT");
        _start(
            _request(
                liquidationId,
                FUNGIBLE_POSITION,
                LiquidationEngine.SaleKind.DIRECT,
                50 ether,
                8_000,
                1 ether,
                500,
                0
            ),
            COLLATERAL_ID
        );
        vm.prank(firstBidder);
        engine.executeDirect(liquidationId, 80 ether);

        LiquidationEngine.Settlement memory result = engine.settlement(liquidationId);
        require(result.grossProceeds == 80 ether, "gross mismatch");
        require(result.executionCosts == 1 ether, "cost mismatch");
        require(result.liquidationIncentive == 4 ether, "incentive mismatch");
        require(result.securedClaimPaid == 75 ether, "claim mismatch");
        require(result.residualBadDebt == 75 ether, "bad debt hidden");
        require(debt.outstandingPrincipal() == 75 ether, "claim not reduced");
        require(collateralToken.balanceOf(firstBidder) == 50 ether, "buyer did not receive lot");
        require(settlementToken.balanceOf(treasury) == 1 ether, "costs not routed");

        vm.prank(secondBidder);
        (bool repeated,) =
            address(engine).call(abi.encodeCall(engine.executeDirect, (liquidationId, 80 ether)));
        require(!repeated, "liquidation executed twice");
    }

    function testDutchPriceAndBorrowerSurplusAreDeterministic() public {
        debt.setOutstanding(100 ether);
        _defaultLoan();
        bytes32 liquidationId = keccak256("DUTCH");
        _start(
            _request(
                liquidationId,
                FUNGIBLE_POSITION,
                LiquidationEngine.SaleKind.DUTCH,
                100 ether,
                8_000,
                0,
                0,
                0
            ),
            COLLATERAL_ID
        );
        vm.warp(block.timestamp + 30 minutes);
        require(engine.currentDutchPrice(liquidationId) == 180 ether, "curve mismatch");
        vm.prank(firstBidder);
        engine.executeDutch(liquidationId, 180 ether);

        LiquidationEngine.Settlement memory result = engine.settlement(liquidationId);
        require(result.securedClaimPaid == 100 ether, "lender claim not capped");
        require(result.borrowerSurplus == 80 ether, "surplus mismatch");
        require(result.residualBadDebt == 0, "repaid debt remained");
        require(settlementToken.balanceOf(lender) == 100 ether, "lender underpaid");
        require(settlementToken.balanceOf(borrower) == 80 ether, "surplus not returned");
    }

    function testEnglishAuctionRefundAndFinalSettlement() public {
        _defaultLoan();
        bytes32 liquidationId = keccak256("ENGLISH");
        _start(
            _request(
                liquidationId,
                FUNGIBLE_POSITION,
                LiquidationEngine.SaleKind.ENGLISH,
                100 ether,
                8_000,
                0,
                0,
                50
            ),
            COLLATERAL_ID
        );
        vm.prank(firstBidder);
        engine.bid(liquidationId, 160 ether);
        vm.prank(secondBidder);
        engine.bid(liquidationId, 170 ether);
        require(
            engine.refundable(address(settlementToken), firstBidder) == 160 ether,
            "outbid refund missing"
        );

        vm.warp(block.timestamp + 1 hours + 1);
        engine.settleEnglish(liquidationId);
        LiquidationEngine.Settlement memory result = engine.settlement(liquidationId);
        require(result.buyer == secondBidder, "wrong auction winner");
        require(result.securedClaimPaid == 150 ether, "secured claim mismatch");
        require(result.borrowerSurplus == 20 ether, "auction surplus mismatch");
        require(collateralToken.balanceOf(secondBidder) == 100 ether, "lot not final");

        vm.prank(firstBidder);
        engine.withdrawRefund(address(settlementToken));
        require(settlementToken.balanceOf(firstBidder) == 1_000 ether, "refund not exact");
    }

    function testExpiredNftAuctionLeavesCollateralLocked() public {
        _defaultLoan();
        bytes32 liquidationId = keccak256("NFT_EXPIRED");
        _start(
            _request(
                liquidationId, NFT_POSITION, LiquidationEngine.SaleKind.ENGLISH, 1, 8_000, 0, 0, 100
            ),
            NFT_ASSET_ID
        );
        vm.warp(block.timestamp + 1 hours + 1);
        engine.expire(liquidationId);
        require(
            engine.plan(liquidationId).status == LiquidationEngine.PlanStatus.FAILED,
            "expired auction not failed"
        );
        require(nft.ownerOf(1) == collateral.vaultOf(LOAN_ID), "failed auction moved NFT");
        require(
            CollateralVault(payable(collateral.vaultOf(LOAN_ID))).collateral(NFT_POSITION).status
                == RiskTypes.CollateralStatus.LOCKED,
            "failed auction changed custody state"
        );
    }

    function testStaleEnglishAuctionRefundsWithoutDisposition() public {
        _defaultLoan();
        bytes32 liquidationId = keccak256("STALE_ENGLISH");
        _start(
            _request(
                liquidationId,
                FUNGIBLE_POSITION,
                LiquidationEngine.SaleKind.ENGLISH,
                100 ether,
                8_000,
                0,
                0,
                100
            ),
            COLLATERAL_ID
        );
        vm.prank(firstBidder);
        engine.bid(liquidationId, 160 ether);
        vm.warp(block.timestamp + 1 days + 1);
        engine.expire(liquidationId);
        require(
            engine.plan(liquidationId).status == LiquidationEngine.PlanStatus.FAILED,
            "stale auction not failed"
        );
        require(
            engine.refundable(address(settlementToken), firstBidder) == 160 ether,
            "stale auction did not refund"
        );
        require(
            collateralToken.balanceOf(collateral.vaultOf(LOAN_ID)) == 100 ether,
            "stale auction moved collateral"
        );
    }

    function testRepaymentBeforeExecutionCancelsLiquidation() public {
        _defaultLoan();
        bytes32 liquidationId = keccak256("CURED");
        _start(
            _request(
                liquidationId,
                FUNGIBLE_POSITION,
                LiquidationEngine.SaleKind.DIRECT,
                100 ether,
                8_000,
                0,
                0,
                0
            ),
            COLLATERAL_ID
        );
        debt.setOutstanding(0);
        loans.setTerminal(LOAN_ID, true);
        engine.cancelInvalidated(liquidationId);
        require(
            engine.plan(liquidationId).status == LiquidationEngine.PlanStatus.CANCELLED,
            "cure did not cancel"
        );
        require(
            collateralToken.balanceOf(collateral.vaultOf(LOAN_ID)) == 100 ether,
            "cancelled liquidation moved collateral"
        );
    }

    function _configureOracle(bytes32 assetId) private {
        oracle.configurePair(assetId, SETTLEMENT_ID, 1 days, 500, 3);
        for (uint256 index = 0; index < adapters.length; ++index) {
            if (address(adapters[index]) == address(0)) {
                adapters[index] = new LiquidationOracleAdapter();
                adapters[index].set(2 ether, NOW, uint64(index + 1));
            }
            oracle.configureSource(
                assetId,
                SETTLEMENT_ID,
                keccak256(abi.encode(assetId, index)),
                address(adapters[index]),
                true
            );
        }
        require(oracle.updatePrice(assetId, SETTLEMENT_ID), "oracle update failed");
    }

    function _defaultLoan() private {
        vm.warp(NOW + 21);
        servicing.evaluate(LOAN_ID);
        vm.warp(NOW + 31);
        servicing.confirmDefault(LOAN_ID, keccak256("DEFAULT_EVIDENCE"));
    }

    function _start(LiquidationEngine.PlanRequest memory request, bytes32 assetId) private {
        engine.startLiquidation(request, oracle.price(assetId, SETTLEMENT_ID));
    }

    function _request(
        bytes32 liquidationId,
        bytes32 collateralId,
        LiquidationEngine.SaleKind saleKind,
        uint256 quantity,
        uint16 minimumProceedsBps,
        uint256 executionCostCap,
        uint16 incentiveBps,
        uint16 minimumBidIncrementBps
    ) private view returns (LiquidationEngine.PlanRequest memory) {
        return LiquidationEngine.PlanRequest({
            liquidationId: liquidationId,
            loanId: LOAN_ID,
            collateralId: collateralId,
            saleKind: saleKind,
            quantity: quantity,
            minimumProceedsBps: minimumProceedsBps,
            incentiveBps: incentiveBps,
            minimumBidIncrementBps: minimumBidIncrementBps,
            executionCostCap: executionCostCap,
            startsAt: uint64(block.timestamp),
            endsAt: uint64(block.timestamp + 1 hours),
            policySetHash: POLICY_SET,
            triggerSnapshotHash: keccak256(abi.encode("TRIGGER", liquidationId))
        });
    }
}
