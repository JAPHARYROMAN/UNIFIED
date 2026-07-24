// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IEmergencyController } from "../interfaces/IEmergencyController.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { IUnderwrittenCreditPolicy } from "../interfaces/IUnderwrittenCreditPolicy.sol";
import { AssetRegistry } from "../kernel/AssetRegistry.sol";
import { PolicyRegistry } from "../kernel/PolicyRegistry.sol";
import { ProtocolTypes } from "../kernel/ProtocolTypes.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CoreLoanAccount } from "./CoreLoanAccount.sol";
import { FundingManager } from "./FundingManager.sol";
import { LoanTypes } from "./LoanTypes.sol";
import { OfferManager } from "./OfferManager.sol";
import { TenderRegistry } from "./TenderRegistry.sol";

interface ICoreZeroInterestPolicy {
    function isZeroInterest() external view returns (bool);
}

/// @notice Atomic same-chain, single-lender, principal-only origination controller.
contract CoreLoanFactory is RoleControlled, ReentrancyGuard {
    error InvalidOrigination();
    error NewLoanActivationPaused();
    error MissingZeroInterestPolicy();
    error UnapprovedPolicy(uint256 index);
    error UnsupportedAsset(bytes32 assetId);

    uint32 public constant IMPLEMENTATION_VERSION = 2;
    bytes32 public constant CAPABILITY_NEW_LOANS = keccak256("CAPABILITY_NEW_LOANS");

    ILoanRegistry public immutable loanRegistry;
    TenderRegistry public immutable tenderRegistry;
    OfferManager public immutable offerManager;
    FundingManager public immutable fundingManager;
    AssetRegistry public immutable assetRegistry;
    PolicyRegistry public immutable policyRegistry;
    IEmergencyController public immutable emergencyController;
    address public immutable implementation;

    event LoanCreated(bytes32 indexed loanId, address indexed borrower, bytes32 agreementHash);
    event CoreLoanActivated(
        bytes32 indexed loanId,
        address indexed loanAccount,
        address indexed lender,
        bytes32 tenderId,
        bytes32 offerId,
        uint256 principalAmount,
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
        address implementation_
    ) RoleControlled(roleManager_) {
        require(
            address(loanRegistry_) != address(0) && address(tenderRegistry_) != address(0)
                && address(offerManager_) != address(0) && address(fundingManager_) != address(0)
                && address(assetRegistry_) != address(0) && address(policyRegistry_) != address(0)
                && address(emergencyController_) != address(0) && implementation_.code.length != 0,
            "invalid core factory"
        );
        loanRegistry = loanRegistry_;
        tenderRegistry = tenderRegistry_;
        offerManager = offerManager_;
        fundingManager = fundingManager_;
        assetRegistry = assetRegistry_;
        policyRegistry = policyRegistry_;
        emergencyController = emergencyController_;
        implementation = implementation_;
    }

    function createAndActivate(
        LoanTypes.UniversalLoanTerms calldata proposedTerms,
        ProtocolTypes.PolicyRef[] calldata policies,
        LoanTypes.Offer calldata offer,
        bytes calldata offerSignature,
        bytes32 journalRef
    ) external nonReentrant returns (bytes32 loanId, address loanAccount) {
        _requireActivationAvailable();
        _validateTermsAndOffer(proposedTerms, offer, journalRef);
        loanId = calculateLoanId(proposedTerms.tenderId, proposedTerms.acceptedOfferId, msg.sender);
        if (loanId != proposedTerms.loanId || loanRegistry.exists(loanId)) {
            revert InvalidOrigination();
        }
        bytes32 approvedPolicySetHash = _approvedPolicySetHash(policies);
        if (
            approvedPolicySetHash != proposedTerms.policySetHash
                || approvedPolicySetHash != offer.policySetHash
        ) {
            revert InvalidOrigination();
        }

        _validateTender(proposedTerms);
        address settlementToken = _activeSettlementToken(proposedTerms.principal.assetId);

        tenderRegistry.selectOffer(proposedTerms.tenderId, proposedTerms.acceptedOfferId);
        offerManager.consumeOffer(offer, offerSignature, loanId);
        loanAccount = _deployAndRegister(proposedTerms, offer.lender, settlementToken);
        _fundActivateAndFulfill(proposedTerms, offer, loanAccount, journalRef);
    }

    function calculateLoanId(bytes32 tenderId, bytes32 offerId, address borrower)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_CORE_LOAN", block.chainid, address(this), tenderId, offerId, borrower
            )
        );
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

    function _approvedPolicySetHash(ProtocolTypes.PolicyRef[] calldata policies)
        private
        view
        returns (bytes32)
    {
        if (policies.length == 0) revert InvalidOrigination();
        bool hasZeroInterestPolicy;
        for (uint256 index = 0; index < policies.length; ++index) {
            if (policies[index].interfaceId == type(IUnderwrittenCreditPolicy).interfaceId) {
                revert UnapprovedPolicy(index);
            }
            if (!policyRegistry.isApproved(policies[index])) {
                revert UnapprovedPolicy(index);
            }
            if (policies[index].interfaceId == type(ICoreZeroInterestPolicy).interfaceId) {
                try ICoreZeroInterestPolicy(policies[index].implementation)
                    .isZeroInterest() returns (
                    bool confirmed
                ) {
                    if (confirmed) hasZeroInterestPolicy = true;
                } catch {
                    revert UnapprovedPolicy(index);
                }
            }
        }
        if (!hasZeroInterestPolicy) revert MissingZeroInterestPolicy();
        return keccak256(abi.encode(policies));
    }

    function _requireActivationAvailable() private view {
        (bool paused,,) = emergencyController.emergencyState(CAPABILITY_NEW_LOANS);
        if (paused) revert NewLoanActivationPaused();
    }

    function _validateTender(LoanTypes.UniversalLoanTerms calldata terms) private view {
        TenderRegistry.Tender memory tender = tenderRegistry.tender(terms.tenderId);
        if (
            tender.borrower != msg.sender || tender.state != LoanTypes.TenderState.OPEN
                || tender.metadataHash != terms.metadataHash || tender.expiry < block.timestamp
        ) {
            revert InvalidOrigination();
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

    function _fundActivateAndFulfill(
        LoanTypes.UniversalLoanTerms calldata terms,
        LoanTypes.Offer calldata offer,
        address loanAccount,
        bytes32 journalRef
    ) private {
        fundingManager.fundAndDisburse(
            terms.loanId,
            offer.lender,
            terms.parties.borrower,
            terms.principal.assetId,
            terms.principal.amount,
            offer.originationFee,
            journalRef
        );
        CoreLoanAccount(loanAccount).activate(journalRef);
        tenderRegistry.markFulfilled(terms.tenderId, terms.loanId);
        emit LoanCreated(terms.loanId, terms.parties.borrower, terms.agreementHash);
        emit CoreLoanActivated(
            terms.loanId,
            loanAccount,
            offer.lender,
            terms.tenderId,
            terms.acceptedOfferId,
            terms.principal.amount,
            journalRef
        );
    }

    function _validateTermsAndOffer(
        LoanTypes.UniversalLoanTerms calldata terms,
        LoanTypes.Offer calldata offer,
        bytes32 journalRef
    ) private view {
        if (
            journalRef == bytes32(0) || terms.loanId == bytes32(0) || terms.tenderId == bytes32(0)
                || terms.acceptedOfferId == bytes32(0) || terms.acceptedOfferId != offer.offerId
                || terms.tenderId != offer.tenderId || terms.agreementHash == bytes32(0)
                || terms.agreementHash != offer.agreementHash
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
            revert InvalidOrigination();
        }
    }
}
