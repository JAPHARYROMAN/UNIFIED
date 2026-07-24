// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { IUnderwrittenCreditPolicy } from "../src/interfaces/IUnderwrittenCreditPolicy.sol";
import { CredentialRegistry } from "../src/identity/CredentialRegistry.sol";
import { CreditDecisionRegistry } from "../src/identity/CreditDecisionRegistry.sol";
import { ExposureManager } from "../src/identity/ExposureManager.sol";
import { IdentityProviderRegistry } from "../src/identity/IdentityProviderRegistry.sol";
import { IdentityTypes } from "../src/identity/IdentityTypes.sol";
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
import { UnderwrittenLoanFactory } from "../src/loan/UnderwrittenLoanFactory.sol";
import { UnderwrittenTypes } from "../src/loan/UnderwrittenTypes.sol";

interface Phase6BUnderwrittenVm {
    function addr(uint256 privateKey) external returns (address);
    function prank(address sender) external;
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 timestamp) external;
}

interface IPhase6BZeroInterestPolicy {
    function isZeroInterest() external view returns (bool);
}

contract Phase6BZeroInterestPolicy is IERC165, IPhase6BZeroInterestPolicy {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IPhase6BZeroInterestPolicy).interfaceId;
    }

    function isZeroInterest() external pure returns (bool) {
        return true;
    }
}

contract Phase6BUnderwrittenPolicy is IERC165, IUnderwrittenCreditPolicy {
    bytes32 private immutable _productHash;

    constructor(bytes32 productHash_) {
        _productHash = productHash_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IUnderwrittenCreditPolicy).interfaceId;
    }

    function requiresUnderwriting() external pure returns (bool) {
        return true;
    }

    function productHash() external view returns (bytes32) {
        return _productHash;
    }
}

contract Phase6BSettlementToken is ERC20 {
    constructor(address lender, address borrower) ERC20("Phase 6B Synthetic", "P6B") {
        _mint(lender, 10_000 ether);
        _mint(borrower, 100 ether);
    }
}

contract Phase6UnderwrittenLoanTest {
    Phase6BUnderwrittenVm private constant vm =
        Phase6BUnderwrittenVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 private constant NOW = 1_900_000_000;
    uint256 private constant LENDER_KEY = 0xBEEF6;
    bytes32 private constant ASSET = keccak256("ASSET:PHASE6B:SYNTHETIC");
    bytes32 private constant OTHER_ASSET = keccak256("ASSET:PHASE6B:OTHER");
    bytes32 private constant PRODUCT = keccak256("PRODUCT:PHASE6B:UNSECURED");
    bytes32 private constant OTHER_PRODUCT = keccak256("PRODUCT:PHASE6B:OTHER");
    bytes32 private constant PROVIDER = keccak256("PROVIDER:PHASE6B:SYNTHETIC");
    bytes32 private constant SCHEMA = keccak256("SCHEMA:PHASE6B:ELIGIBILITY");
    bytes32 private constant SCOPE = keccak256("SCOPE:PHASE6B:UNSECURED");
    bytes32 private constant ZERO_POLICY_ID = keccak256("POLICY:PHASE6B:ZERO_INTEREST");
    bytes32 private constant UNDERWRITTEN_POLICY_ID = keccak256("POLICY:PHASE6B:UNDERWRITTEN");

    address private issuer = address(0x1556);
    address private underwriter = address(0xA116);
    address private borrower = address(0xB0B6);
    address private feeReceiver = address(0xFEE6);
    address private outsider = address(0xBAD6);
    address private lender;

    RoleManager private roles;
    LoanRegistry private loans;
    TenderRegistry private tenders;
    OfferManager private offers;
    AssetRegistry private assets;
    PolicyRegistry private policies;
    EmergencyController private emergency;
    FundingManager private funding;
    IdentityProviderRegistry private providers;
    CredentialRegistry private credentials;
    CreditDecisionRegistry private decisions;
    ExposureManager private exposure;
    UnderwrittenLoanFactory private factory;
    CoreLoanFactory private legacyFactory;
    Phase6BSettlementToken private token;
    ProtocolTypes.PolicyRef private zeroPolicy;
    ProtocolTypes.PolicyRef private underwrittenPolicy;

    struct Prepared {
        LoanTypes.UniversalLoanTerms terms;
        LoanTypes.Offer offer;
        bytes signature;
        ProtocolTypes.PolicyRef[] policySet;
        UnderwrittenTypes.ActivationAuthorization authorization;
    }

    struct PreparationConfig {
        uint256 nonce;
        bytes32 decisionAsset;
        bytes32 activationAsset;
        bytes32 decisionProduct;
        bytes32 activationProduct;
        uint256 maximumExposure;
        uint64 maximumDuration;
    }

    function setUp() public {
        vm.warp(NOW);
        lender = vm.addr(LENDER_KEY);
        roles = new RoleManager(address(0xA11CE), address(this));
        _grant(ProtocolRoles.ASSET_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.POLICY_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.PAUSER_ROLE, address(this));
        _grant(ProtocolRoles.IDENTITY_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.CREDENTIAL_ISSUER_ROLE, issuer);
        _grant(ProtocolRoles.UNDERWRITER_ROLE, underwriter);

        loans = new LoanRegistry(IRoleManager(address(roles)));
        tenders = new TenderRegistry(IRoleManager(address(roles)));
        offers = new OfferManager(IRoleManager(address(roles)));
        assets = new AssetRegistry(IRoleManager(address(roles)));
        policies = new PolicyRegistry(IRoleManager(address(roles)));
        emergency = new EmergencyController(IRoleManager(address(roles)));
        token = new Phase6BSettlementToken(lender, borrower);
        assets.registerAsset(ASSET, address(token), 18, keccak256("PHASE6B_ASSET_METADATA"));
        assets.registerAsset(
            OTHER_ASSET, address(token), 18, keccak256("PHASE6B_OTHER_ASSET_METADATA")
        );
        _registerPolicies();

        funding = new FundingManager(IRoleManager(address(roles)), assets, feeReceiver);
        providers = new IdentityProviderRegistry(IRoleManager(address(roles)));
        providers.registerProvider(PROVIDER, issuer, keccak256("PHASE6B_PROVIDER_METADATA"), 5);
        providers.registerSchema(SCHEMA, PROVIDER, keccak256("PHASE6B_SCHEMA"), 4);
        credentials = new CredentialRegistry(IRoleManager(address(roles)), providers);
        decisions = new CreditDecisionRegistry(IRoleManager(address(roles)), credentials);
        exposure = new ExposureManager(
            IRoleManager(address(roles)), decisions, ILoanRegistry(address(loans))
        );

        CoreLoanAccount accountImplementation = new CoreLoanAccount();
        factory = new UnderwrittenLoanFactory(
            IRoleManager(address(roles)),
            ILoanRegistry(address(loans)),
            tenders,
            offers,
            funding,
            assets,
            policies,
            emergency,
            exposure,
            address(accountImplementation)
        );
        legacyFactory = new CoreLoanFactory(
            IRoleManager(address(roles)),
            ILoanRegistry(address(loans)),
            tenders,
            offers,
            funding,
            assets,
            policies,
            emergency,
            address(accountImplementation)
        );
        _grant(ProtocolRoles.LOAN_FACTORY_ROLE, address(factory));
        _grant(ProtocolRoles.EXPOSURE_FACTORY_ROLE, address(factory));
        _grant(ProtocolRoles.LOAN_FACTORY_ROLE, address(legacyFactory));
        vm.prank(lender);
        token.approve(address(funding), type(uint256).max);
    }

    function testAtomicActivationRepaymentPauseAndTerminalRelease() public {
        Prepared memory prepared = _prepare(1);
        vm.prank(borrower);
        (bytes32 loanId, address accountAddress) = factory.createAndActivate(
            prepared.terms,
            prepared.policySet,
            prepared.offer,
            prepared.signature,
            prepared.authorization
        );
        require(loanId == prepared.terms.loanId, "loan identity mismatch");
        require(loans.loanAccount(loanId) == accountAddress, "loan not registered");
        require(loans.protocolVersionOf(loanId) == 3, "wrong protocol version");
        require(
            tenders.tenderState(prepared.terms.tenderId) == LoanTypes.TenderState.FULFILLED,
            "tender not fulfilled"
        );
        require(
            offers.offerState(prepared.offer.offerId) == LoanTypes.OfferState.CONSUMED,
            "offer not consumed"
        );
        require(funding.fundedAmount(loanId) == 1_000 ether, "funding not recorded");
        IdentityTypes.ExposureTotals memory active = exposure.exposure(
            decisions.decision(prepared.authorization.decisionId).subjectCommitment, ASSET
        );
        require(active.reserved == 0 && active.active == 1_000 ether, "exposure not active");
        require(token.balanceOf(lender) == 9_000 ether, "lender funding mismatch");
        require(token.balanceOf(borrower) == 1_090 ether, "borrower proceeds mismatch");
        require(token.balanceOf(feeReceiver) == 10 ether, "fee mismatch");

        emergency.pauseCapability(
            factory.CAPABILITY_UNDERWRITTEN_NEW_LOANS(),
            uint64(block.timestamp + 1 days),
            keccak256("PHASE6B_PAUSE")
        );
        vm.prank(borrower);
        token.approve(accountAddress, 1_000 ether);
        vm.prank(borrower);
        CoreLoanAccount(accountAddress)
            .repay(
                keccak256("PHASE6B_PAYMENT"), 1_000 ether, keccak256("PHASE6B_REPAYMENT_JOURNAL")
            );
        require(loans.isTerminal(loanId), "loan not terminal");
        vm.prank(outsider);
        exposure.release(loanId, keccak256("PHASE6B_TERMINAL_RELEASE"));
        IdentityTypes.ExposureTotals memory released = exposure.exposure(
            decisions.decision(prepared.authorization.decisionId).subjectCommitment, ASSET
        );
        require(released.reserved == 0 && released.active == 0, "exposure not released");
        require(token.balanceOf(lender) == 10_000 ether, "lender not repaid");
    }

    function testFundingFailureRollsBackEveryActivationEffect() public {
        Prepared memory prepared = _prepare(2);
        vm.prank(lender);
        token.approve(address(funding), 0);
        uint256 lenderBefore = token.balanceOf(lender);
        uint256 borrowerBefore = token.balanceOf(borrower);
        uint256 feeBefore = token.balanceOf(feeReceiver);

        require(!_activate(prepared), "unfunded activation succeeded");
        _requireNoActivationState(prepared);
        require(token.balanceOf(lender) == lenderBefore, "failed funding changed lender");
        require(token.balanceOf(borrower) == borrowerBefore, "failed funding changed borrower");
        require(token.balanceOf(feeReceiver) == feeBefore, "failed funding changed fee receiver");
        require(
            factory.predictLoanAddress(prepared.terms.loanId).code.length == 0,
            "failed clone remains"
        );
    }

    function testRevokedAndSupersededDecisionsFailClosed() public {
        Prepared memory revoked = _prepare(3);
        vm.prank(underwriter);
        decisions.revokeDecision(
            revoked.authorization.decisionId, keccak256("PHASE6B_DECISION_REVOKED")
        );
        require(!_activate(revoked), "revoked decision activated");
        _requireNoActivationState(revoked);

        Prepared memory superseded = _prepare(4);
        IdentityTypes.CreditDecision memory prior =
            decisions.decision(superseded.authorization.decisionId);
        _issueDecision(
            keccak256("PHASE6B_SUPERSEDING_DECISION"),
            prior.credentialId,
            prior.subjectCommitment,
            ASSET,
            PRODUCT,
            1_000 ether,
            365 days
        );
        require(!_activate(superseded), "superseded decision activated");
        _requireNoActivationState(superseded);
    }

    function testConsentProductAssetAmountAndDurationMismatchFailClosed() public {
        Prepared memory consent = _prepare(5);
        consent.authorization.consentEvidenceHash = keccak256("DIFFERENT_CONSENT");
        require(!_activate(consent), "consent mismatch activated");
        _requireNoActivationState(consent);

        Prepared memory product =
            _prepareConfigured(6, ASSET, ASSET, PRODUCT, OTHER_PRODUCT, 1_000 ether, 365 days);
        require(!_activate(product), "product mismatch activated");
        _requireNoActivationState(product);

        Prepared memory asset =
            _prepareConfigured(7, ASSET, OTHER_ASSET, PRODUCT, PRODUCT, 1_000 ether, 365 days);
        require(!_activate(asset), "asset mismatch activated");
        _requireNoActivationState(asset);

        Prepared memory amount =
            _prepareConfigured(8, ASSET, ASSET, PRODUCT, PRODUCT, 999 ether, 365 days);
        require(!_activate(amount), "amount above decision activated");
        _requireNoActivationState(amount);

        Prepared memory duration =
            _prepareConfigured(9, ASSET, ASSET, PRODUCT, PRODUCT, 1_000 ether, 30 days);
        require(!_activate(duration), "duration above decision activated");
        _requireNoActivationState(duration);
    }

    function testReplayCannotDuplicateLoanOrExposure() public {
        Prepared memory prepared = _prepare(10);
        vm.prank(borrower);
        factory.createAndActivate(
            prepared.terms,
            prepared.policySet,
            prepared.offer,
            prepared.signature,
            prepared.authorization
        );
        require(!_activate(prepared), "activation replay succeeded");
        IdentityTypes.CreditDecision memory decision_ =
            decisions.decision(prepared.authorization.decisionId);
        IdentityTypes.ExposureTotals memory totals =
            exposure.exposure(decision_.subjectCommitment, ASSET);
        require(totals.active == 1_000 ether && totals.reserved == 0, "replay changed exposure");
        require(
            funding.fundedAmount(prepared.terms.loanId) == 1_000 ether, "replay changed funding"
        );
    }

    function testBothNewLoanPausesFailBeforeStateMutation() public {
        Prepared memory dedicated = _prepare(11);
        emergency.pauseCapability(
            factory.CAPABILITY_UNDERWRITTEN_NEW_LOANS(),
            uint64(block.timestamp + 1 hours),
            keccak256("DEDICATED_PAUSE")
        );
        require(!_activate(dedicated), "dedicated pause ignored");
        _requireNoActivationState(dedicated);

        vm.warp(block.timestamp + 1 hours + 1);
        Prepared memory global = _prepare(12);
        emergency.pauseCapability(
            factory.CAPABILITY_NEW_LOANS(),
            uint64(block.timestamp + 1 hours),
            keccak256("GLOBAL_PAUSE")
        );
        require(!_activate(global), "global pause ignored");
        _requireNoActivationState(global);
    }

    function testLegacyFactoryRejectsUnderwrittenPolicyMarker() public {
        (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        ) = _prepareLegacy(13);
        vm.prank(borrower);
        (bool success,) = address(legacyFactory)
            .call(
                abi.encodeCall(
                    legacyFactory.createAndActivate,
                    (terms, policySet, offer, signature, keccak256("LEGACY_BYPASS_JOURNAL"))
                )
            );
        require(!success, "legacy factory accepted underwritten policy");
        require(!loans.exists(terms.loanId), "legacy bypass registered loan");
        require(
            tenders.tenderState(terms.tenderId) == LoanTypes.TenderState.OPEN,
            "legacy bypass changed tender"
        );
        require(
            offers.offerState(offer.offerId) == LoanTypes.OfferState.ACTIVE,
            "legacy bypass consumed offer"
        );
    }

    function _prepare(uint256 nonce) private returns (Prepared memory) {
        return _prepareConfigured(nonce, ASSET, ASSET, PRODUCT, PRODUCT, 1_000 ether, 365 days);
    }

    function _prepareConfigured(
        uint256 nonce,
        bytes32 decisionAsset,
        bytes32 activationAsset,
        bytes32 decisionProduct,
        bytes32 activationProduct,
        uint256 maximumExposure,
        uint64 maximumDuration
    ) private returns (Prepared memory prepared) {
        return _prepareConfig(
            PreparationConfig({
                nonce: nonce,
                decisionAsset: decisionAsset,
                activationAsset: activationAsset,
                decisionProduct: decisionProduct,
                activationProduct: activationProduct,
                maximumExposure: maximumExposure,
                maximumDuration: maximumDuration
            })
        );
    }

    function _prepareConfig(PreparationConfig memory config)
        private
        returns (Prepared memory prepared)
    {
        bytes32 subject = keccak256(abi.encode("PHASE6B_SALTED_SUBJECT", config.nonce));
        bytes32 credentialId = _issueCredential(config.nonce, subject);
        bytes32 decisionId = keccak256(abi.encode("PHASE6B_DECISION", config.nonce));
        _issueDecision(
            decisionId,
            credentialId,
            subject,
            config.decisionAsset,
            config.decisionProduct,
            config.maximumExposure,
            config.maximumDuration
        );

        prepared.policySet = _policySet();
        bytes32 policyHash = keccak256(abi.encode(prepared.policySet));
        bytes32 tenderId = keccak256(abi.encode("PHASE6B_TENDER", config.nonce));
        bytes32 offerId = keccak256(abi.encode("PHASE6B_OFFER", config.nonce));
        bytes32 metadataHash = keccak256(abi.encode("PHASE6B_METADATA", config.nonce));
        prepared.authorization = UnderwrittenTypes.ActivationAuthorization({
            decisionId: decisionId,
            productHash: config.activationProduct,
            consentEvidenceHash: keccak256(abi.encode("PHASE6B_CONSENT", config.nonce)),
            journalRef: keccak256(abi.encode("PHASE6B_ACTIVATION_JOURNAL", config.nonce))
        });
        bytes32 loanId = factory.calculateLoanId(
            tenderId, offerId, borrower, decisionId, config.activationProduct
        );
        prepared.terms = LoanTypes.UniversalLoanTerms({
            loanId: loanId,
            tenderId: tenderId,
            acceptedOfferId: offerId,
            agreementHash: bytes32(0),
            parties: LoanTypes.AgreementParties({
                borrower: borrower,
                arranger: address(0),
                servicer: address(this),
                collateralAgent: address(0),
                paymentAgent: address(0)
            }),
            principal: LoanTypes.MonetaryAmount({
                assetId: config.activationAsset, amount: 1_000 ether
            }),
            fundingDeadline: uint64(block.timestamp + 2 days),
            activationDeadline: uint64(block.timestamp + 3 days),
            commencementTime: 0,
            finalMaturityTime: uint64(block.timestamp + 180 days),
            gracePeriod: 3 days,
            protocolVersion: factory.IMPLEMENTATION_VERSION(),
            policySetHash: policyHash,
            metadataHash: metadataHash
        });
        prepared.terms.agreementHash =
            factory.activationAgreementHash(prepared.terms, prepared.authorization);
        prepared.offer = LoanTypes.Offer({
            offerId: offerId,
            tenderId: tenderId,
            parentOfferId: bytes32(0),
            lender: lender,
            borrower: borrower,
            assetId: config.activationAsset,
            principalAmount: 1_000 ether,
            originationFee: 10 ether,
            fundingDeadline: prepared.terms.fundingDeadline,
            activationDeadline: prepared.terms.activationDeadline,
            finalMaturityTime: prepared.terms.finalMaturityTime,
            gracePeriod: prepared.terms.gracePeriod,
            protocolVersion: prepared.terms.protocolVersion,
            policySetHash: policyHash,
            agreementHash: prepared.terms.agreementHash,
            metadataHash: metadataHash,
            nonce: config.nonce,
            expiry: uint64(block.timestamp + 1 days)
        });
        prepared.signature = _sign(prepared.offer);
        vm.prank(borrower);
        tenders.registerTender(tenderId, borrower, metadataHash, uint64(block.timestamp + 4 days));
        offers.submitOffer(prepared.offer, prepared.signature);
    }

    function _prepareLegacy(uint256 nonce)
        private
        returns (
            LoanTypes.UniversalLoanTerms memory terms,
            LoanTypes.Offer memory offer,
            bytes memory signature,
            ProtocolTypes.PolicyRef[] memory policySet
        )
    {
        bytes32 tenderId = keccak256(abi.encode("PHASE6B_LEGACY_TENDER", nonce));
        bytes32 offerId = keccak256(abi.encode("PHASE6B_LEGACY_OFFER", nonce));
        bytes32 metadataHash = keccak256(abi.encode("PHASE6B_LEGACY_METADATA", nonce));
        bytes32 agreementHash = keccak256(abi.encode("PHASE6B_LEGACY_AGREEMENT", nonce));
        policySet = _policySet();
        bytes32 policyHash = keccak256(abi.encode(policySet));
        vm.prank(borrower);
        tenders.registerTender(tenderId, borrower, metadataHash, uint64(block.timestamp + 4 days));
        offer = LoanTypes.Offer({
            offerId: offerId,
            tenderId: tenderId,
            parentOfferId: bytes32(0),
            lender: lender,
            borrower: borrower,
            assetId: ASSET,
            principalAmount: 1_000 ether,
            originationFee: 10 ether,
            fundingDeadline: uint64(block.timestamp + 2 days),
            activationDeadline: uint64(block.timestamp + 3 days),
            finalMaturityTime: uint64(block.timestamp + 30 days),
            gracePeriod: 3 days,
            protocolVersion: legacyFactory.IMPLEMENTATION_VERSION(),
            policySetHash: policyHash,
            agreementHash: agreementHash,
            metadataHash: metadataHash,
            nonce: nonce,
            expiry: uint64(block.timestamp + 1 days)
        });
        signature = _sign(offer);
        offers.submitOffer(offer, signature);
        terms = LoanTypes.UniversalLoanTerms({
            loanId: legacyFactory.calculateLoanId(tenderId, offerId, borrower),
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
            principal: LoanTypes.MonetaryAmount({ assetId: ASSET, amount: 1_000 ether }),
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

    function _issueCredential(uint256 nonce, bytes32 subject)
        private
        returns (bytes32 credentialId)
    {
        credentialId = keccak256(abi.encode("PHASE6B_CREDENTIAL", nonce));
        IdentityTypes.CredentialInput memory input = IdentityTypes.CredentialInput({
            credentialId: credentialId,
            subjectCommitment: subject,
            boundAccount: borrower,
            providerId: PROVIDER,
            schemaId: SCHEMA,
            claimsCommitment: keccak256(abi.encode("PHASE6B_SYNTHETIC_CLAIMS", nonce)),
            scopeHash: SCOPE,
            epoch: 1,
            assurance: 4,
            validFrom: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 365 days)
        });
        vm.prank(issuer);
        credentials.issueCredential(input);
    }

    function _issueDecision(
        bytes32 decisionId,
        bytes32 credentialId,
        bytes32 subject,
        bytes32 settlementAsset,
        bytes32 productHash,
        uint256 maximumExposure,
        uint64 maximumDuration
    ) private {
        bytes32 previousDecisionId = decisions.currentDecisionId(
            subject, settlementAsset, productHash
        );
        uint64 sequence = previousDecisionId == bytes32(0)
            ? 1
            : decisions.decision(previousDecisionId).sequence + 1;
        IdentityTypes.CreditDecisionInput memory input = IdentityTypes.CreditDecisionInput({
            decisionId: decisionId,
            previousDecisionId: previousDecisionId,
            credentialId: credentialId,
            subjectCommitment: subject,
            borrower: borrower,
            credentialScopeHash: SCOPE,
            credentialEpoch: 1,
            minimumAssurance: 3,
            policyId: UNDERWRITTEN_POLICY_ID,
            policyMajor: 1,
            policyMinor: 0,
            policyPatch: 0,
            ruleSetHash: keccak256("PHASE6B_RULES_V1"),
            modelSetHash: keccak256("PHASE6B_RULES_ONLY_V1"),
            featureEvidenceRoot: keccak256(abi.encode("PHASE6B_FEATURES", decisionId)),
            featureSchemaHash: keccak256("PHASE6B_FEATURE_SCHEMA_V1"),
            featuresAsOf: uint64(block.timestamp),
            settlementAssetId: settlementAsset,
            productHash: productHash,
            maximumExposure: maximumExposure,
            maximumDuration: maximumDuration,
            expiresAt: uint64(block.timestamp + 30 days),
            sequence: sequence,
            reasonCodesHash: keccak256("PHASE6B_APPROVED_SYNTHETIC")
        });
        vm.prank(underwriter);
        decisions.issueDecision(input);
    }

    function _registerPolicies() private {
        Phase6BZeroInterestPolicy zeroImplementation = new Phase6BZeroInterestPolicy();
        zeroPolicy = ProtocolTypes.PolicyRef({
            policyId: ZERO_POLICY_ID,
            implementation: address(zeroImplementation),
            major: 1,
            minor: 0,
            patch: 0,
            interfaceId: type(IPhase6BZeroInterestPolicy).interfaceId,
            configurationSchemaHash: keccak256("PHASE6B_ZERO_INTEREST_V1")
        });
        policies.registerPolicy(zeroPolicy, _codeHash(address(zeroImplementation)));

        Phase6BUnderwrittenPolicy underwrittenImplementation =
            new Phase6BUnderwrittenPolicy(PRODUCT);
        underwrittenPolicy = ProtocolTypes.PolicyRef({
            policyId: UNDERWRITTEN_POLICY_ID,
            implementation: address(underwrittenImplementation),
            major: 1,
            minor: 0,
            patch: 0,
            interfaceId: type(IUnderwrittenCreditPolicy).interfaceId,
            configurationSchemaHash: keccak256("PHASE6B_UNDERWRITTEN_POLICY_V1")
        });
        policies.registerPolicy(underwrittenPolicy, _codeHash(address(underwrittenImplementation)));
    }

    function _policySet() private view returns (ProtocolTypes.PolicyRef[] memory policySet) {
        policySet = new ProtocolTypes.PolicyRef[](2);
        policySet[0] = zeroPolicy;
        policySet[1] = underwrittenPolicy;
    }

    function _activate(Prepared memory prepared) private returns (bool success) {
        vm.prank(borrower);
        (success,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.createAndActivate,
                    (
                        prepared.terms,
                        prepared.policySet,
                        prepared.offer,
                        prepared.signature,
                        prepared.authorization
                    )
                )
            );
    }

    function _requireNoActivationState(Prepared memory prepared) private view {
        require(!loans.exists(prepared.terms.loanId), "failed activation registered loan");
        require(
            tenders.tenderState(prepared.terms.tenderId) == LoanTypes.TenderState.OPEN,
            "failed activation changed tender"
        );
        require(
            offers.offerState(prepared.offer.offerId) == LoanTypes.OfferState.ACTIVE,
            "failed activation consumed offer"
        );
        require(funding.fundedAmount(prepared.terms.loanId) == 0, "failed activation funded loan");
        IdentityTypes.CreditDecision memory decision_ =
            decisions.decision(prepared.authorization.decisionId);
        IdentityTypes.ExposureTotals memory totals =
            exposure.exposure(decision_.subjectCommitment, decision_.settlementAssetId);
        require(totals.reserved == 0 && totals.active == 0, "failed activation changed exposure");
    }

    function _sign(LoanTypes.Offer memory offer) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LENDER_KEY, offers.hashOffer(offer));
        return abi.encodePacked(r, s, v);
    }

    function _codeHash(address implementation) private view returns (bytes32 codeHash) {
        assembly ("memory-safe") {
            codeHash := extcodehash(implementation)
        }
    }

    function _grant(bytes32 role, address account) private {
        roles.grantRole(role, account, type(uint64).max);
    }
}
