// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IEmergencyController } from "../interfaces/IEmergencyController.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { IUnderwrittenCreditPolicy } from "../interfaces/IUnderwrittenCreditPolicy.sol";
import { CreditDecisionRegistry } from "../identity/CreditDecisionRegistry.sol";
import { ExposureManager } from "../identity/ExposureManager.sol";
import { IdentityTypes } from "../identity/IdentityTypes.sol";
import { AssetRegistry } from "../kernel/AssetRegistry.sol";
import { PolicyRegistry } from "../kernel/PolicyRegistry.sol";
import { ProtocolTypes } from "../kernel/ProtocolTypes.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CoreLoanAccount } from "./CoreLoanAccount.sol";
import { FundingManager } from "./FundingManager.sol";
import { LoanTypes } from "./LoanTypes.sol";
import { OfferManager } from "./OfferManager.sol";
import { TenderRegistry } from "./TenderRegistry.sol";
import { UnderwrittenTypes } from "./UnderwrittenTypes.sol";

interface IUnderwrittenZeroInterestPolicy {
    function isZeroInterest() external view returns (bool);
}

/// @notice Atomic same-chain activation against a current Phase 6 credit decision.
contract UnderwrittenLoanFactory is RoleControlled, ReentrancyGuard {
    error InvalidConfiguration();
    error InvalidActivation();
    error NewLoanActivationPaused(bytes32 capability);
    error MissingZeroInterestPolicy();
    error MissingUnderwrittenPolicy();
    error UnapprovedPolicy(uint256 index);
    error UnsupportedAsset(bytes32 assetId);

    uint32 public constant IMPLEMENTATION_VERSION = 3;
    bytes32 public constant CAPABILITY_NEW_LOANS = keccak256("CAPABILITY_NEW_LOANS");
    bytes32 public constant CAPABILITY_UNDERWRITTEN_NEW_LOANS =
        keccak256("CAPABILITY_UNDERWRITTEN_NEW_LOANS");

    ILoanRegistry public immutable loanRegistry;
    TenderRegistry public immutable tenderRegistry;
    OfferManager public immutable offerManager;
    FundingManager public immutable fundingManager;
    AssetRegistry public immutable assetRegistry;
    PolicyRegistry public immutable policyRegistry;
    IEmergencyController public immutable emergencyController;
    ExposureManager public immutable exposureManager;
    CreditDecisionRegistry public immutable decisionRegistry;
    address public immutable implementation;

    event UnderwrittenLoanActivated(
        bytes32 indexed loanId,
        bytes32 indexed decisionId,
        address indexed borrower,
        address loanAccount,
        bytes32 productHash,
        bytes32 activationEvidenceHash,
        bytes32 journalRef
    );

    constructor(
        IRoleManager roleManager_,
        ILoanRegistry loanRegistry_,
        TenderRegistry tenderRegistry_,
        OfferManager offerManager_,
        FundingManager fundingManager_,
        AssetRegistry assetRegistry_,
        PolicyRegistry policyRegistry_,
        IEmergencyController emergencyController_,
        ExposureManager exposureManager_,
        address implementation_
    ) RoleControlled(roleManager_) {
        if (
            address(loanRegistry_).code.length == 0 || address(tenderRegistry_).code.length == 0
                || address(offerManager_).code.length == 0
                || address(fundingManager_).code.length == 0
                || address(assetRegistry_).code.length == 0
                || address(policyRegistry_).code.length == 0
                || address(emergencyController_).code.length == 0
                || address(exposureManager_).code.length == 0 || implementation_.code.length == 0
                || address(exposureManager_.loanRegistry()) != address(loanRegistry_)
        ) {
            revert InvalidConfiguration();
        }
        loanRegistry = loanRegistry_;
        tenderRegistry = tenderRegistry_;
        offerManager = offerManager_;
        fundingManager = fundingManager_;
        assetRegistry = assetRegistry_;
        policyRegistry = policyRegistry_;
        emergencyController = emergencyController_;
        exposureManager = exposureManager_;
        decisionRegistry = exposureManager_.decisionRegistry();
        implementation = implementation_;
    }

    function createAndActivate(
        LoanTypes.UniversalLoanTerms calldata proposedTerms,
        ProtocolTypes.PolicyRef[] calldata policies,
        LoanTypes.Offer calldata offer,
        bytes calldata offerSignature,
        UnderwrittenTypes.ActivationAuthorization calldata authorization
    ) external nonReentrant returns (bytes32 loanId, address loanAccount) {
        _requireActivationAvailable();
        _validateTermsAndOffer(proposedTerms, offer, authorization);
        loanId = calculateLoanId(
            proposedTerms.tenderId,
            proposedTerms.acceptedOfferId,
            msg.sender,
            authorization.decisionId,
            authorization.productHash
        );
        if (loanId != proposedTerms.loanId || loanRegistry.exists(loanId)) {
            revert InvalidActivation();
        }

        _validateDecisionPolicies(proposedTerms, offer, policies, authorization);
        _validateTender(proposedTerms);
        loanAccount = _executeActivation(proposedTerms, offer, offerSignature, authorization);
    }

    function _executeActivation(
        LoanTypes.UniversalLoanTerms calldata proposedTerms,
        LoanTypes.Offer calldata offer,
        bytes calldata offerSignature,
        UnderwrittenTypes.ActivationAuthorization calldata authorization
    ) private returns (address loanAccount) {
        address settlementToken = _activeSettlementToken(proposedTerms.principal.assetId);
        uint64 duration = proposedTerms.finalMaturityTime - uint64(block.timestamp);
        _reserveExposure(proposedTerms, authorization, duration);

        tenderRegistry.selectOffer(proposedTerms.tenderId, proposedTerms.acceptedOfferId);
        offerManager.consumeOffer(offer, offerSignature, proposedTerms.loanId);
        loanAccount = _deployAndRegister(proposedTerms, offer.lender, settlementToken);
        _fundAndActivate(proposedTerms, offer, authorization, loanAccount, duration);
    }

    function _validateDecisionPolicies(
        LoanTypes.UniversalLoanTerms calldata proposedTerms,
        LoanTypes.Offer calldata offer,
        ProtocolTypes.PolicyRef[] calldata policies,
        UnderwrittenTypes.ActivationAuthorization calldata authorization
    ) private view {
        IdentityTypes.CreditDecision memory decision_ =
            decisionRegistry.decision(authorization.decisionId);
        if (
            decision_.borrower != msg.sender
                || decision_.settlementAssetId != proposedTerms.principal.assetId
                || decision_.productHash != authorization.productHash
        ) {
            revert InvalidActivation();
        }
        bytes32 approvedPolicySetHash =
            _approvedPolicySetHash(policies, decision_, authorization.productHash);
        if (
            approvedPolicySetHash != proposedTerms.policySetHash
                || approvedPolicySetHash != offer.policySetHash
        ) {
            revert InvalidActivation();
        }
    }

    function _reserveExposure(
        LoanTypes.UniversalLoanTerms calldata terms,
        UnderwrittenTypes.ActivationAuthorization calldata authorization,
        uint64 duration
    ) private {
        bytes32 reserveEvidence = keccak256(
            abi.encode(
                "UNIFIED_PHASE6B_RESERVE",
                terms.agreementHash,
                authorization.consentEvidenceHash,
                authorization.journalRef
            )
        );
        exposureManager.reserve(
            authorization.decisionId,
            terms.loanId,
            msg.sender,
            terms.principal.amount,
            duration,
            authorization.productHash,
            reserveEvidence
        );
    }

    function calculateLoanId(
        bytes32 tenderId,
        bytes32 offerId,
        address borrower,
        bytes32 decisionId,
        bytes32 productHash
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_UNDERWRITTEN_LOAN",
                block.chainid,
                address(this),
                tenderId,
                offerId,
                borrower,
                decisionId,
                productHash
            )
        );
    }

    function activationAgreementHash(
        LoanTypes.UniversalLoanTerms calldata terms,
        UnderwrittenTypes.ActivationAuthorization calldata authorization
    ) public view returns (bytes32) {
        bytes32 identityHash = keccak256(
            abi.encode(
                "UNIFIED_UNDERWRITTEN_ACTIVATION_IDENTITY_V1",
                block.chainid,
                address(this),
                terms.loanId,
                terms.tenderId,
                terms.acceptedOfferId,
                terms.parties.borrower,
                authorization.decisionId,
                authorization.productHash
            )
        );
        bytes32 economicsHash = keccak256(
            abi.encode(
                "UNIFIED_UNDERWRITTEN_ACTIVATION_ECONOMICS_V1",
                terms.principal.assetId,
                terms.principal.amount,
                terms.finalMaturityTime,
                terms.policySetHash,
                terms.metadataHash,
                authorization.consentEvidenceHash
            )
        );
        return
            keccak256(abi.encode("UNIFIED_UNDERWRITTEN_ACTIVATION_V1", identityHash, economicsHash));
    }

    function predictLoanAddress(bytes32 loanId) external view returns (address) {
        return Clones.predictDeterministicAddress(implementation, loanId, address(this));
    }

    function policySetHash(ProtocolTypes.PolicyRef[] calldata policies)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(policies));
    }

    function _approvedPolicySetHash(
        ProtocolTypes.PolicyRef[] calldata policies,
        IdentityTypes.CreditDecision memory decision_,
        bytes32 productHash
    ) private view returns (bytes32) {
        if (policies.length == 0) revert InvalidActivation();
        bool hasZeroInterestPolicy;
        bool hasUnderwrittenPolicy;
        for (uint256 index = 0; index < policies.length; ++index) {
            ProtocolTypes.PolicyRef calldata policy = policies[index];
            if (!policyRegistry.isApproved(policy)) {
                revert UnapprovedPolicy(index);
            }
            if (policy.interfaceId == type(IUnderwrittenZeroInterestPolicy).interfaceId) {
                try IUnderwrittenZeroInterestPolicy(policy.implementation)
                    .isZeroInterest() returns (
                    bool confirmed
                ) {
                    if (confirmed) hasZeroInterestPolicy = true;
                } catch {
                    revert UnapprovedPolicy(index);
                }
            }
            if (policy.interfaceId == type(IUnderwrittenCreditPolicy).interfaceId) {
                if (
                    hasUnderwrittenPolicy || policy.policyId != decision_.policyId
                        || policy.major != decision_.policyMajor
                        || policy.minor != decision_.policyMinor
                        || policy.patch != decision_.policyPatch
                ) {
                    revert UnapprovedPolicy(index);
                }
                try IUnderwrittenCreditPolicy(policy.implementation)
                    .requiresUnderwriting() returns (
                    bool required
                ) {
                    if (!required) revert UnapprovedPolicy(index);
                } catch {
                    revert UnapprovedPolicy(index);
                }
                try IUnderwrittenCreditPolicy(policy.implementation).productHash() returns (
                    bytes32 policyProductHash
                ) {
                    if (policyProductHash != productHash) {
                        revert UnapprovedPolicy(index);
                    }
                } catch {
                    revert UnapprovedPolicy(index);
                }
                hasUnderwrittenPolicy = true;
            }
        }
        if (!hasZeroInterestPolicy) revert MissingZeroInterestPolicy();
        if (!hasUnderwrittenPolicy) revert MissingUnderwrittenPolicy();
        return keccak256(abi.encode(policies));
    }

    function _requireActivationAvailable() private view {
        (bool globalPaused,,) = emergencyController.emergencyState(CAPABILITY_NEW_LOANS);
        if (globalPaused) revert NewLoanActivationPaused(CAPABILITY_NEW_LOANS);
        (bool underwrittenPaused,,) =
            emergencyController.emergencyState(CAPABILITY_UNDERWRITTEN_NEW_LOANS);
        if (underwrittenPaused) {
            revert NewLoanActivationPaused(CAPABILITY_UNDERWRITTEN_NEW_LOANS);
        }
    }

    function _validateTender(LoanTypes.UniversalLoanTerms calldata terms) private view {
        TenderRegistry.Tender memory tender = tenderRegistry.tender(terms.tenderId);
        if (
            tender.borrower != msg.sender || tender.state != LoanTypes.TenderState.OPEN
                || tender.metadataHash != terms.metadataHash || tender.expiry < block.timestamp
        ) {
            revert InvalidActivation();
        }
    }

    function _activeSettlementToken(bytes32 assetId) private view returns (address) {
        AssetRegistry.AssetRecord memory asset = assetRegistry.resolve(assetId);
        if (!asset.active) revert UnsupportedAsset(assetId);
        return asset.token;
    }

    function _deployAndRegister(
        LoanTypes.UniversalLoanTerms calldata proposedTerms,
        address lender,
        address settlementToken
    ) private returns (address loanAccount) {
        loanAccount = Clones.cloneDeterministic(implementation, proposedTerms.loanId);
        LoanTypes.UniversalLoanTerms memory activeTerms = proposedTerms;
        activeTerms.commencementTime = uint64(block.timestamp);
        CoreLoanAccount(loanAccount).initialize(activeTerms, lender, settlementToken, loanRegistry);
        loanRegistry.registerLoan(
            proposedTerms.loanId,
            loanAccount,
            proposedTerms.parties.borrower,
            proposedTerms.agreementHash,
            IMPLEMENTATION_VERSION
        );
    }

    function _fundAndActivate(
        LoanTypes.UniversalLoanTerms calldata terms,
        LoanTypes.Offer calldata offer,
        UnderwrittenTypes.ActivationAuthorization calldata authorization,
        address loanAccount,
        uint64 duration
    ) private {
        fundingManager.fundAndDisburse(
            terms.loanId,
            offer.lender,
            terms.parties.borrower,
            terms.principal.assetId,
            terms.principal.amount,
            offer.originationFee,
            authorization.journalRef
        );
        CoreLoanAccount(loanAccount).activate(authorization.journalRef);
        bytes32 termsHash = keccak256(abi.encode(terms));
        bytes32 authorizationHash = keccak256(abi.encode(authorization));
        bytes32 activationEvidence = keccak256(
            abi.encode(
                "UNIFIED_PHASE6B_ACTIVATE",
                termsHash,
                offer.offerId,
                offer.lender,
                authorizationHash,
                loanAccount,
                duration,
                authorization.journalRef
            )
        );
        exposureManager.activate(terms.loanId, activationEvidence);
        tenderRegistry.markFulfilled(terms.tenderId, terms.loanId);
        emit UnderwrittenLoanActivated(
            terms.loanId,
            authorization.decisionId,
            terms.parties.borrower,
            loanAccount,
            authorization.productHash,
            activationEvidence,
            authorization.journalRef
        );
    }

    function _validateTermsAndOffer(
        LoanTypes.UniversalLoanTerms calldata terms,
        LoanTypes.Offer calldata offer,
        UnderwrittenTypes.ActivationAuthorization calldata authorization
    ) private view {
        if (
            authorization.journalRef == bytes32(0) || authorization.decisionId == bytes32(0)
                || authorization.productHash == bytes32(0)
                || authorization.consentEvidenceHash == bytes32(0) || terms.loanId == bytes32(0)
                || terms.tenderId == bytes32(0) || terms.acceptedOfferId == bytes32(0)
                || terms.acceptedOfferId != offer.offerId || terms.tenderId != offer.tenderId
                || terms.agreementHash == bytes32(0) || terms.agreementHash != offer.agreementHash
                || terms.agreementHash != activationAgreementHash(terms, authorization)
                || terms.parties.borrower != msg.sender || offer.borrower != msg.sender
                || terms.principal.assetId == bytes32(0) || terms.principal.assetId != offer.assetId
                || terms.principal.amount == 0 || terms.principal.amount != offer.principalAmount
                || terms.fundingDeadline != offer.fundingDeadline
                || terms.activationDeadline != offer.activationDeadline
                || terms.commencementTime != 0 || terms.finalMaturityTime != offer.finalMaturityTime
                || terms.finalMaturityTime <= block.timestamp
                || terms.gracePeriod != offer.gracePeriod
                || terms.protocolVersion != IMPLEMENTATION_VERSION
                || offer.protocolVersion != IMPLEMENTATION_VERSION
                || terms.metadataHash != offer.metadataHash
                || terms.fundingDeadline < block.timestamp
                || terms.activationDeadline < block.timestamp || offer.expiry < block.timestamp
        ) {
            revert InvalidActivation();
        }
    }
}
