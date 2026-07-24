// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { CollateralManager } from "../src/collateral/CollateralManager.sol";
import { CollateralVault } from "../src/collateral/CollateralVault.sol";
import { RiskTypes } from "../src/risk/RiskTypes.sol";

interface CollateralVm {
    function deal(address account, uint256 balance) external;
    function prank(address sender) external;
}

contract CollateralTestToken is ERC20 {
    constructor(string memory name_, string memory symbol_, address owner, uint256 amount)
        ERC20(name_, symbol_)
    {
        _mint(owner, amount);
    }
}

contract CollateralTestNFT is ERC721 {
    constructor(address owner) ERC721("Collateral NFT", "CNFT") {
        _mint(owner, 1);
        _mint(owner, 2);
    }
}

contract CollateralTest1155 is ERC1155 {
    constructor(address owner) ERC1155("example://collateral/{id}") {
        _mint(owner, 7, 100, "");
    }
}

contract CollateralDebt {
    uint256 public outstandingPrincipal;

    constructor(uint256 outstanding) {
        outstandingPrincipal = outstanding;
    }

    function setOutstanding(uint256 outstanding) external {
        outstandingPrincipal = outstanding;
    }
}

contract CollateralLoanRegistry is ILoanRegistry {
    struct Loan {
        address account;
        address borrower;
        bool terminal;
    }

    mapping(bytes32 => Loan) private _loans;

    function seed(bytes32 loanId, address account, address borrower) external {
        _loans[loanId] = Loan(account, borrower, false);
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
        return keccak256("TEST_AGREEMENT");
    }

    function protocolVersionOf(bytes32) external pure returns (uint32) {
        return 3;
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

contract Phase4CollateralTest {
    CollateralVm private constant vm =
        CollateralVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant LOAN_ID = keccak256("COLLATERAL_LOAN");
    bytes32 private constant UFT_ID = keccak256("ASSET:UFT");
    bytes32 private constant TOKEN_ID = keccak256("ASSET:TOKEN");
    bytes32 private constant NATIVE_ID = keccak256("ASSET:NATIVE");
    bytes32 private constant NFT_ID = keccak256("ASSET:NFT");
    bytes32 private constant MULTI_ID = keccak256("ASSET:1155");
    address private borrower = address(0xB0B);

    RoleManager private roles;
    AssetRegistry private assets;
    CollateralLoanRegistry private loans;
    CollateralManager private manager;
    CollateralDebt private debt;
    CollateralTestToken private uft;
    CollateralTestToken private token;
    CollateralTestNFT private nft;
    CollateralTest1155 private multi;

    function setUp() public {
        roles = new RoleManager(address(0xA11CE), address(this));
        roles.grantRole(ProtocolRoles.ASSET_REGISTRAR_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
        assets = new AssetRegistry(roles);
        uft = new CollateralTestToken("Unified", "UFT", borrower, 1_000_000 ether);
        token = new CollateralTestToken("Collateral", "COL", borrower, 10_000 ether);
        nft = new CollateralTestNFT(borrower);
        multi = new CollateralTest1155(borrower);
        assets.registerAsset(UFT_ID, address(uft), 18, keccak256("UFT"));
        assets.registerAsset(TOKEN_ID, address(token), 18, keccak256("TOKEN"));
        assets.registerAsset(NFT_ID, address(nft), 0, keccak256("NFT"));
        assets.registerAsset(MULTI_ID, address(multi), 0, keccak256("MULTI"));

        loans = new CollateralLoanRegistry();
        debt = new CollateralDebt(1_000 ether);
        loans.seed(LOAN_ID, address(debt), borrower);
        manager = new CollateralManager(roles, loans, assets, UFT_ID, uft);
        manager.configureAsset(UFT_ID, address(uft), RiskTypes.CollateralKind.ERC20, true, true);
        manager.configureAsset(
            TOKEN_ID, address(token), RiskTypes.CollateralKind.ERC20, true, false
        );
        manager.configureAsset(NATIVE_ID, address(0), RiskTypes.CollateralKind.NATIVE, true, false);
        manager.configureAsset(NFT_ID, address(nft), RiskTypes.CollateralKind.ERC721, true, false);
        manager.configureAsset(
            MULTI_ID, address(multi), RiskTypes.CollateralKind.ERC1155, true, false
        );
        manager.configureLiquidationEngine(address(this));
        vm.deal(borrower, 100 ether);
        vm.prank(borrower);
        address vault = manager.createVault(LOAN_ID);
        vm.prank(borrower);
        token.approve(vault, type(uint256).max);
        vm.prank(borrower);
        uft.approve(vault, type(uint256).max);
        vm.prank(borrower);
        nft.setApprovalForAll(vault, true);
        vm.prank(borrower);
        multi.setApprovalForAll(vault, true);
    }

    function testMixedCollateralCustodyAndFinalDebtRelease() public {
        vm.prank(borrower);
        manager.lockERC20(LOAN_ID, keccak256("COL-20"), TOKEN_ID, 100 ether);
        vm.prank(borrower);
        manager.lockNative{ value: 2 ether }(LOAN_ID, keccak256("COL-NATIVE"), NATIVE_ID);
        vm.prank(borrower);
        manager.lockERC721(LOAN_ID, keccak256("COL-721"), NFT_ID, 1);
        vm.prank(borrower);
        manager.lockERC1155(LOAN_ID, keccak256("COL-1155"), MULTI_ID, 7, 40, "");

        CollateralVault vault = CollateralVault(payable(manager.vaultOf(LOAN_ID)));
        require(token.balanceOf(address(vault)) == 100 ether, "ERC20 custody mismatch");
        require(address(vault).balance == 2 ether, "native custody mismatch");
        require(nft.ownerOf(1) == address(vault), "NFT custody mismatch");
        require(multi.balanceOf(address(vault), 7) == 40, "1155 custody mismatch");
        require(manager.collateralOf(LOAN_ID).length == 4, "mixed bundle incomplete");

        vm.prank(borrower);
        (bool premature,) = address(manager)
            .call(
                abi.encodeCall(
                    manager.releaseCollateral,
                    (LOAN_ID, keccak256("COL-20"), borrower, keccak256("EARLY_RELEASE"))
                )
            );
        require(!premature, "collateral released before debt settlement");

        debt.setOutstanding(0);
        loans.setTerminal(LOAN_ID, true);
        _release(keccak256("COL-20"));
        _release(keccak256("COL-NATIVE"));
        _release(keccak256("COL-721"));
        _release(keccak256("COL-1155"));
        require(token.balanceOf(borrower) == 10_000 ether, "ERC20 not returned");
        require(nft.ownerOf(1) == borrower, "NFT not returned");
        require(multi.balanceOf(borrower, 7) == 100, "1155 not returned");
        require(vault.balanceOfAsset(TOKEN_ID) == 0, "vault accounting not cleared");
    }

    function testUnsolicitedNFTCallbackIsRejected() public {
        vm.prank(borrower);
        manager.lockERC721(LOAN_ID, keccak256("COL-721"), NFT_ID, 1);
        address vault = manager.vaultOf(LOAN_ID);
        vm.prank(borrower);
        (bool accepted,) = address(nft)
            .call(
                abi.encodeWithSignature(
                    "safeTransferFrom(address,address,uint256)", borrower, vault, 2
                )
            );
        require(!accepted, "unsolicited NFT accepted");
        require(nft.ownerOf(2) == borrower, "failed callback moved NFT");
    }

    function testUFTDebtCeilingAndConcentrationBounds() public {
        manager.configureUFTDebtCeiling(1_000 ether, keccak256("UFT_DEBT_POLICY"));
        manager.bindUFTBackedDebt(LOAN_ID, 500 ether);
        vm.prank(borrower);
        manager.lockERC20(LOAN_ID, keccak256("UFT-COL"), UFT_ID, 2_500 ether);
        require(manager.loanExposure(LOAN_ID, UFT_ID) == 2_500 ether, "UFT exposure missing");
        require(manager.isUFTExposureCompliant(LOAN_ID, borrower), "UFT limits not compliant");
        vm.prank(borrower);
        (bool excess,) = address(manager)
            .call(abi.encodeCall(manager.lockERC20, (LOAN_ID, keccak256("UFT-EXCESS"), UFT_ID, 1)));
        require(!excess, "single-loan UFT concentration exceeded");
        (bool bypassed,) = address(manager)
            .call(
                abi.encodeCall(
                    manager.configureAsset,
                    (UFT_ID, address(uft), RiskTypes.CollateralKind.ERC20, true, false)
                )
            );
        require(!bypassed, "UFT controls disabled through asset reconfiguration");
    }

    function testPartialLiquidationCannotDoubleDispose() public {
        vm.prank(borrower);
        manager.lockERC1155(LOAN_ID, keccak256("PARTIAL"), MULTI_ID, 7, 10, "");
        manager.liquidateCollateral(LOAN_ID, keccak256("PARTIAL"), address(0xCAFE), 4);
        RiskTypes.CollateralItem[] memory items = manager.collateralOf(LOAN_ID);
        require(items[0].quantity == 6, "partial quantity mismatch");
        require(multi.balanceOf(address(0xCAFE), 7) == 4, "liquidator did not receive");
        (bool excess,) = address(manager)
            .call(
                abi.encodeCall(
                    manager.liquidateCollateral, (LOAN_ID, keccak256("PARTIAL"), address(0xCAFE), 7)
                )
            );
        require(!excess, "collateral disposed twice");
    }

    function _release(bytes32 collateralId) private {
        vm.prank(borrower);
        manager.releaseCollateral(
            LOAN_ID, collateralId, borrower, keccak256(abi.encode("RELEASE", collateralId))
        );
    }
}
