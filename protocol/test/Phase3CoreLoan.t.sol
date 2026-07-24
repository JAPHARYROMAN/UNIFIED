// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { ProtocolTypes } from "../src/kernel/ProtocolTypes.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { CoreLoanAccount } from "../src/loan/CoreLoanAccount.sol";
import { CoreLoanFactory } from "../src/loan/CoreLoanFactory.sol";
import { FundingManager } from "../src/loan/FundingManager.sol";
import { LoanTypes } from "../src/loan/LoanTypes.sol";
import { OfferManager } from "../src/loan/OfferManager.sol";
import { TenderRegistry } from "../src/loan/TenderRegistry.sol";

interface Phase3Vm {
    function addr(uint256 privateKey) external returns (address);
    function prank(address sender) external;
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
}

interface IZeroInterestPolicy {
    function isZeroInterest() external pure returns (bool);
}

contract ZeroInterestPolicy is IERC165, IZeroInterestPolicy {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IZeroInterestPolicy).interfaceId;
    }

    function isZeroInterest() external pure returns (bool) {
        return true;
    }
}

contract TestSettlementToken is ERC20 {
    constructor(address lender, address borrower) ERC20("Test Settlement", "TST") {
        _mint(lender, 10_000 ether);
        _mint(borrower, 100 ether);
    }
}

contract FeeSettlementToken is ERC20 {
    constructor(address lender) ERC20("Fee Settlement", "FEE") {
        _mint(lender, 10_000 ether);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
            return;
        }
        super._update(from, to, value);
    }
}

contract Phase3CoreLoanTest {
    Phase3Vm private constant vm =
        Phase3Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant LENDER_KEY = 0xBEEF;
    bytes32 private constant ASSET_ID = keccak256("ASSET:TST");
    bytes32 private constant FEE_ASSET_ID = keccak256("ASSET:FEE");
    bytes32 private constant POLICY_ID = keccak256("POLICY:ZERO_INTEREST");

    RoleManager private roles;
    LoanRegistry private loans;
    TenderRegistry private tenders;
    OfferManager private offers;
    AssetRegistry private assets;
    PolicyRegistry private policies;
    EmergencyController private emergency;
    FundingManager private funding;
    CoreLoanFactory private factory;
    TestSettlementToken private token;
    address private lender;
    address private borrower = address(0xB0B);
    address private feeReceiver = address(0xFEE);
    ProtocolTypes.PolicyRef private policy;

    function setUp() public {
        lender = vm.addr(LENDER_KEY);
        roles = new RoleManager(address(0xA11CE), address(this));
        _grant(ProtocolRoles.ASSET_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.POLICY_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.PAUSER_ROLE, address(this));

        loans = new LoanRegistry(roles);
        tenders = new TenderRegistry(roles);
        offers = new OfferManager(roles);
        assets = new AssetRegistry(roles);
        policies = new PolicyRegistry(roles);
        emergency = new EmergencyController(roles);
        token = new TestSettlementToken(lender, borrower);
        assets.registerAsset(ASSET_ID, address(token), 18, keccak256("TST_METADATA"));

        ZeroInterestPolicy policyImplementation = new ZeroInterestPolicy();
        bytes32 codeHash;
        address implementationAddress = address(policyImplementation);
        assembly ("memory-safe") {
            codeHash := extcodehash(implementationAddress)
        }
        policy = ProtocolTypes.PolicyRef({
            policyId: POLICY_ID,
            implementation: implementationAddress,
            major: 1,
            minor: 0,
            patch: 0,
            interfaceId: type(IZeroInterestPolicy).interfaceId,
            configurationSchemaHash: keccak256("ZERO_INTEREST_V1")
        });
        policies.registerPolicy(policy, codeHash);

        funding = new FundingManager(roles, assets, feeReceiver);
        CoreLoanAccount loanImplementation = new CoreLoanAccount();
        factory = new CoreLoanFactory(
            roles,
            loans,
            tenders,
            offers,
            funding,
            assets,
            policies,
            emergency,
            address(loanImplementation)
        );
        _grant(ProtocolRoles.LOAN_FACTORY_ROLE, address(factory));
        vm.prank(lender);
        token.approve(address(funding), type(uint256).max);
    }

    function testCanonicalOriginationRepaymentAndClosureFlow() public {
        (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareOrigination(1);

        vm.prank(borrower);
        (, address accountAddress) = factory.createAndActivate(
            terms, policySet, offer, signature, keccak256("ACTIVATION_JOURNAL")
        );
        CoreLoanAccount account = CoreLoanAccount(accountAddress);

        require(loans.loanAccount(terms.loanId) == accountAddress, "loan not registered");
        require(
            tenders.tenderState(terms.tenderId) == LoanTypes.TenderState.FULFILLED,
            "tender not fulfilled"
        );
        require(
            offers.offerState(offer.offerId) == LoanTypes.OfferState.CONSUMED, "offer not consumed"
        );
        require(offers.isNonceUsed(lender, offer.nonce), "nonce not consumed");
        require(token.balanceOf(borrower) == 1_090 ether, "net proceeds");
        require(token.balanceOf(feeReceiver) == 10 ether, "fee not routed");
        require(account.outstandingPrincipal() == 1_000 ether, "principal not initialized");
        require(
            account.stateVector().lifecycle == LoanTypes.LoanLifecycle.ACTIVE, "loan not active"
        );

        vm.prank(borrower);
        token.approve(accountAddress, 1_000 ether);
        vm.prank(borrower);
        account.repay(keccak256("PAYMENT-1"), 400 ether, keccak256("REPAYMENT-JOURNAL-1"));
        require(account.outstandingPrincipal() == 600 ether, "partial repayment");

        vm.prank(borrower);
        (bool duplicateAccepted,) = accountAddress.call(
            abi.encodeCall(
                account.repay,
                (keccak256("PAYMENT-1"), 400 ether, keccak256("REPAYMENT-JOURNAL-DUPLICATE"))
            )
        );
        require(!duplicateAccepted, "payment replay accepted");
        require(account.outstandingPrincipal() == 600 ether, "replay changed debt");

        vm.prank(borrower);
        account.repay(keccak256("PAYMENT-2"), 600 ether, keccak256("REPAYMENT-JOURNAL-2"));
        require(account.outstandingPrincipal() == 0, "principal remains");
        require(loans.isTerminal(terms.loanId), "registry not terminal");
        require(
            account.stateVector().lifecycle == LoanTypes.LoanLifecycle.CLOSED, "loan not closed"
        );
        require(token.balanceOf(lender) == 10_000 ether, "lender not repaid");
        vm.prank(address(factory));
        (bool reactivated,) =
            accountAddress.call(abi.encodeCall(account.activate, (keccak256("REACTIVATION"))));
        require(!reactivated, "terminal loan reactivated");
    }

    function testFundingFailureRollsBackEveryActivationEffect() public {
        (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareOrigination(2);
        vm.prank(lender);
        token.approve(address(funding), 0);

        vm.prank(borrower);
        (bool success,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.createAndActivate,
                    (terms, policySet, offer, signature, keccak256("FAILED_ACTIVATION_JOURNAL"))
                )
            );
        require(!success, "unfunded activation succeeded");
        require(!loans.exists(terms.loanId), "failed loan registered");
        require(
            tenders.tenderState(terms.tenderId) == LoanTypes.TenderState.OPEN,
            "tender changed on failure"
        );
        require(
            offers.offerState(offer.offerId) == LoanTypes.OfferState.ACTIVE,
            "offer consumed on failure"
        );
        require(!offers.isNonceUsed(lender, offer.nonce), "nonce consumed on failure");
        require(factory.predictLoanAddress(terms.loanId).code.length == 0, "clone remains");
    }

    function testCounterofferLineageAndNonceCancellation() public {
        (
            LoanTypes.UniversalLoanTerms memory parentTerms,
            LoanTypes.Offer memory parent,
            bytes memory parentSignature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareOrigination(3);
        bytes32 parentOfferId = parent.offerId;
        LoanTypes.Offer memory counter = parent;
        counter.offerId = keccak256("COUNTER-OFFER");
        counter.parentOfferId = parentOfferId;
        counter.nonce = 4;
        counter.originationFee = 5 ether;
        bytes memory counterSignature = _sign(counter);
        offers.submitOffer(counter, counterSignature);
        require(
            offers.offerState(parentOfferId) == LoanTypes.OfferState.COUNTERED,
            "parent lineage missing"
        );
        vm.prank(borrower);
        (bool supersededAccepted,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.createAndActivate,
                    (
                        parentTerms,
                        policySet,
                        parent,
                        parentSignature,
                        keccak256("SUPERSEDED_OFFER_JOURNAL")
                    )
                )
            );
        require(!supersededAccepted, "superseded offer was accepted");

        vm.prank(lender);
        offers.cancelNonce(counter.nonce);
        require(offers.isNonceUsed(lender, counter.nonce), "nonce cancellation missing");
    }

    function testNewLoanPauseDoesNotCreatePartialState() public {
        (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareOrigination(5);
        emergency.pauseCapability(
            factory.CAPABILITY_NEW_LOANS(),
            uint64(block.timestamp + 1 days),
            keccak256("ORIGINATION_INCIDENT")
        );
        vm.prank(borrower);
        (bool success,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.createAndActivate,
                    (terms, policySet, offer, signature, keccak256("PAUSED_JOURNAL"))
                )
            );
        require(!success, "paused origination succeeded");
        require(!loans.exists(terms.loanId), "paused loan registered");
    }

    function testUnsupportedTransferFeeTokenRollsBackFunding() public {
        FeeSettlementToken feeToken = new FeeSettlementToken(lender);
        assets.registerAsset(
            FEE_ASSET_ID, address(feeToken), 18, keccak256("FEE_TOKEN_TEST_METADATA")
        );
        vm.prank(lender);
        feeToken.approve(address(funding), type(uint256).max);
        (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareOriginationWithAsset(7, FEE_ASSET_ID);

        vm.prank(borrower);
        (bool success,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.createAndActivate,
                    (terms, policySet, offer, signature, keccak256("FEE_TOKEN_JOURNAL"))
                )
            );
        require(!success, "fee-on-transfer token was admitted");
        require(!loans.exists(terms.loanId), "failed fee-token loan registered");
        require(feeToken.balanceOf(lender) == 10_000 ether, "failed funding changed lender");
        require(feeToken.balanceOf(borrower) == 0, "failed funding changed borrower");
    }

    function testRegistryTerminalMarkerCannotBlockRepaymentClosure() public {
        (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareOrigination(8);
        vm.prank(borrower);
        (, address accountAddress) = factory.createAndActivate(
            terms, policySet, offer, signature, keccak256("PREMARK_ACTIVATION")
        );
        _grant(ProtocolRoles.SERVICER_ROLE, address(this));
        loans.markTerminal(terms.loanId);

        vm.prank(borrower);
        token.approve(accountAddress, terms.principal.amount);
        vm.prank(borrower);
        CoreLoanAccount(accountAddress)
            .repay(
                keccak256("PREMARK_PAYMENT"), terms.principal.amount, keccak256("PREMARK_REPAYMENT")
            );
        require(
            CoreLoanAccount(accountAddress).stateVector().lifecycle
                == LoanTypes.LoanLifecycle.CLOSED,
            "terminal registry marker blocked repayment"
        );
    }

    function testFuzzRepaymentReducesPrincipalExactlyOnce(uint96 seed) public {
        (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareOrigination(6);
        vm.prank(borrower);
        (, address accountAddress) = factory.createAndActivate(
            terms, policySet, offer, signature, keccak256("FUZZ_ACTIVATION")
        );
        CoreLoanAccount account = CoreLoanAccount(accountAddress);
        uint256 amount = uint256(seed) % terms.principal.amount + 1;
        vm.prank(borrower);
        token.approve(accountAddress, amount);
        vm.prank(borrower);
        account.repay(
            keccak256(abi.encode("FUZZ_PAYMENT", seed)), amount, keccak256("FUZZ_JOURNAL")
        );
        require(
            account.outstandingPrincipal() == terms.principal.amount - amount,
            "principal reduction mismatch"
        );
    }

    function _prepareOrigination(uint256 nonce)
        private
        returns (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        )
    {
        return _prepareOriginationWithAsset(nonce, ASSET_ID);
    }

    function _prepareOriginationWithAsset(uint256 nonce, bytes32 assetId)
        private
        returns (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        )
    {
        bytes32 tenderId = keccak256(abi.encode("TENDER", nonce));
        bytes32 offerId = keccak256(abi.encode("OFFER", nonce));
        bytes32 metadataHash = keccak256(abi.encode("METADATA", nonce));
        bytes32 agreementHash = keccak256(abi.encode("AGREEMENT", nonce));
        policySet = new ProtocolTypes.PolicyRef[](1);
        policySet[0] = policy;
        bytes32 policyHash = keccak256(abi.encode(policySet));
        vm.prank(borrower);
        tenders.registerTender(tenderId, borrower, metadataHash, uint64(block.timestamp + 4 days));

        offer = LoanTypes.Offer({
            offerId: offerId,
            tenderId: tenderId,
            parentOfferId: bytes32(0),
            lender: lender,
            borrower: borrower,
            assetId: assetId,
            principalAmount: 1_000 ether,
            originationFee: 10 ether,
            fundingDeadline: uint64(block.timestamp + 2 days),
            activationDeadline: uint64(block.timestamp + 3 days),
            finalMaturityTime: uint64(block.timestamp + 30 days),
            gracePeriod: 3 days,
            protocolVersion: factory.IMPLEMENTATION_VERSION(),
            policySetHash: policyHash,
            agreementHash: agreementHash,
            metadataHash: metadataHash,
            nonce: nonce,
            expiry: uint64(block.timestamp + 1 days)
        });
        signature = _sign(offer);
        offers.submitOffer(offer, signature);
        bytes32 loanId = factory.calculateLoanId(tenderId, offerId, borrower);
        terms = LoanTypes.UniversalLoanTerms({
            loanId: loanId,
            tenderId: tenderId,
            acceptedOfferId: offerId,
            agreementHash: agreementHash,
            parties: LoanTypes.AgreementParties({
                borrower: borrower,
                arranger: address(0),
                servicer: address(this),
                collateralAgent: address(0),
                paymentAgent: address(0)
            }),
            principal: LoanTypes.MonetaryAmount({ assetId: assetId, amount: 1_000 ether }),
            fundingDeadline: offer.fundingDeadline,
            activationDeadline: offer.activationDeadline,
            commencementTime: 0,
            finalMaturityTime: offer.finalMaturityTime,
            gracePeriod: offer.gracePeriod,
            protocolVersion: offer.protocolVersion,
            policySetHash: policyHash,
            metadataHash: metadataHash
        });
    }

    function _sign(LoanTypes.Offer memory offer) private returns (bytes memory) {
        bytes32 digest = offers.hashOffer(offer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LENDER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _grant(bytes32 role, address account) private {
        roles.grantRole(role, account, type(uint64).max);
    }
}
