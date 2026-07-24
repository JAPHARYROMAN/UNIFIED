// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { LoanTypes } from "./LoanTypes.sol";

/// @notice EIP-712 offer submission, counteroffer lineage, cancellation, and consumption.
contract OfferManager is EIP712, RoleControlled {
    error InvalidOffer();
    error OfferAlreadySubmitted(bytes32 offerId);
    error UnknownOffer(bytes32 offerId);
    error InvalidOfferState(bytes32 offerId, LoanTypes.OfferState state);
    error InvalidOfferSignature(address recovered, address expected);
    error OfferNonceUnavailable(address lender, uint256 nonce);

    bytes32 public constant OFFER_TYPEHASH =
        keccak256("Offer(bytes32 identityHash,bytes32 termsHash,uint256 nonce,uint64 expiry)");
    bytes32 public constant IDENTITY_TYPEHASH = keccak256(
        "OfferIdentity(bytes32 offerId,bytes32 tenderId,bytes32 parentOfferId,address lender,address borrower)"
    );
    bytes32 public constant ECONOMICS_TYPEHASH =
        keccak256("OfferEconomics(bytes32 assetId,uint256 principalAmount,uint256 originationFee)");
    bytes32 public constant TIMING_TYPEHASH = keccak256(
        "OfferTiming(uint64 fundingDeadline,uint64 activationDeadline,uint64 finalMaturityTime,uint64 gracePeriod)"
    );
    bytes32 public constant TERMS_TYPEHASH = keccak256(
        "OfferTerms(bytes32 economicsHash,bytes32 timingHash,uint32 protocolVersion,bytes32 policySetHash,bytes32 agreementHash,bytes32 metadataHash)"
    );

    struct OfferRecord {
        bytes32 offerHash;
        bytes32 tenderId;
        bytes32 parentOfferId;
        address lender;
        uint64 expiry;
        uint256 nonce;
        LoanTypes.OfferState state;
    }

    mapping(bytes32 offerId => OfferRecord record) private _offers;
    mapping(address lender => mapping(uint256 nonce => bool used)) private _nonceUsed;
    mapping(address lender => uint256 minimumNonce) public minimumValidNonce;

    event OfferSubmitted(
        bytes32 indexed offerId,
        bytes32 indexed tenderId,
        address indexed lender,
        bytes32 offerHash,
        uint64 expiry
    );
    event OfferCountered(bytes32 indexed parentOfferId, bytes32 indexed counterOfferId);
    event OfferConsumed(bytes32 indexed offerId, bytes32 indexed loanId, address indexed lender);
    event OfferCancelled(bytes32 indexed offerId, address indexed lender);
    event OfferExpired(bytes32 indexed offerId);
    event OfferNonceCancelled(address indexed lender, uint256 indexed nonce);
    event OfferNonceRangeCancelled(address indexed lender, uint256 minimumValidNonce);

    constructor(IRoleManager roleManager_)
        EIP712("Unified Offer", "1")
        RoleControlled(roleManager_)
    { }

    function submitOffer(LoanTypes.Offer calldata offer, bytes calldata signature)
        external
        returns (bytes32 offerHash)
    {
        _validateOfferFields(offer);
        if (_offers[offer.offerId].lender != address(0)) {
            revert OfferAlreadySubmitted(offer.offerId);
        }
        if (isNonceUsed(offer.lender, offer.nonce)) {
            revert OfferNonceUnavailable(offer.lender, offer.nonce);
        }
        offerHash = hashOffer(offer);
        address recovered = ECDSA.recover(offerHash, signature);
        if (recovered != offer.lender) {
            revert InvalidOfferSignature(recovered, offer.lender);
        }
        if (offer.parentOfferId != bytes32(0)) {
            OfferRecord storage parent = _offer(offer.parentOfferId);
            if (
                parent.tenderId != offer.tenderId
                    || (parent.state != LoanTypes.OfferState.ACTIVE
                        && parent.state != LoanTypes.OfferState.COUNTERED)
            ) {
                revert InvalidOffer();
            }
            parent.state = LoanTypes.OfferState.COUNTERED;
            emit OfferCountered(offer.parentOfferId, offer.offerId);
        }
        _offers[offer.offerId] = OfferRecord({
            offerHash: offerHash,
            tenderId: offer.tenderId,
            parentOfferId: offer.parentOfferId,
            lender: offer.lender,
            expiry: offer.expiry,
            nonce: offer.nonce,
            state: LoanTypes.OfferState.ACTIVE
        });
        emit OfferSubmitted(offer.offerId, offer.tenderId, offer.lender, offerHash, offer.expiry);
    }

    function consumeOffer(LoanTypes.Offer calldata offer, bytes calldata signature, bytes32 loanId)
        external
        onlyRole(ProtocolRoles.LOAN_FACTORY_ROLE)
    {
        if (loanId == bytes32(0)) revert InvalidOffer();
        OfferRecord storage record = _offer(offer.offerId);
        if (record.state != LoanTypes.OfferState.ACTIVE) {
            revert InvalidOfferState(offer.offerId, record.state);
        }
        if (
            record.offerHash != hashOffer(offer) || record.expiry < block.timestamp
                || isNonceUsed(offer.lender, offer.nonce)
        ) {
            revert InvalidOffer();
        }
        address recovered = ECDSA.recover(record.offerHash, signature);
        if (recovered != record.lender || recovered != offer.lender) {
            revert InvalidOfferSignature(recovered, offer.lender);
        }
        _nonceUsed[offer.lender][offer.nonce] = true;
        record.state = LoanTypes.OfferState.CONSUMED;
        emit OfferConsumed(offer.offerId, loanId, offer.lender);
    }

    function cancelOffer(bytes32 offerId) external {
        OfferRecord storage record = _offer(offerId);
        if (record.lender != msg.sender) revert InvalidOffer();
        if (
            record.state != LoanTypes.OfferState.ACTIVE
                && record.state != LoanTypes.OfferState.COUNTERED
        ) {
            revert InvalidOfferState(offerId, record.state);
        }
        record.state = LoanTypes.OfferState.CANCELLED;
        _nonceUsed[msg.sender][record.nonce] = true;
        emit OfferCancelled(offerId, msg.sender);
    }

    function expireOffer(bytes32 offerId) external {
        OfferRecord storage record = _offer(offerId);
        if (
            record.state != LoanTypes.OfferState.ACTIVE
                && record.state != LoanTypes.OfferState.COUNTERED
        ) {
            revert InvalidOfferState(offerId, record.state);
        }
        if (record.expiry >= block.timestamp) revert InvalidOffer();
        record.state = LoanTypes.OfferState.EXPIRED;
        emit OfferExpired(offerId);
    }

    function cancelNonce(uint256 nonce) external {
        if (isNonceUsed(msg.sender, nonce)) {
            revert OfferNonceUnavailable(msg.sender, nonce);
        }
        _nonceUsed[msg.sender][nonce] = true;
        emit OfferNonceCancelled(msg.sender, nonce);
    }

    function cancelNonceRange(uint256 newMinimumNonce) external {
        if (newMinimumNonce <= minimumValidNonce[msg.sender]) revert InvalidOffer();
        minimumValidNonce[msg.sender] = newMinimumNonce;
        emit OfferNonceRangeCancelled(msg.sender, newMinimumNonce);
    }

    function isNonceUsed(address lender, uint256 nonce) public view returns (bool) {
        return nonce < minimumValidNonce[lender] || _nonceUsed[lender][nonce];
    }

    function hashOffer(LoanTypes.Offer calldata offer) public view returns (bytes32) {
        bytes32 economicsHash = keccak256(
            abi.encode(
                ECONOMICS_TYPEHASH, offer.assetId, offer.principalAmount, offer.originationFee
            )
        );
        bytes32 timingHash = keccak256(
            abi.encode(
                TIMING_TYPEHASH,
                offer.fundingDeadline,
                offer.activationDeadline,
                offer.finalMaturityTime,
                offer.gracePeriod
            )
        );
        bytes32 identityHash = keccak256(
            abi.encode(
                IDENTITY_TYPEHASH,
                offer.offerId,
                offer.tenderId,
                offer.parentOfferId,
                offer.lender,
                offer.borrower
            )
        );
        bytes32 termsHash = keccak256(
            abi.encode(
                TERMS_TYPEHASH,
                economicsHash,
                timingHash,
                offer.protocolVersion,
                offer.policySetHash,
                offer.agreementHash,
                offer.metadataHash
            )
        );
        return _hashTypedDataV4(
            keccak256(
                abi.encode(OFFER_TYPEHASH, identityHash, termsHash, offer.nonce, offer.expiry)
            )
        );
    }

    function verifyOffer(LoanTypes.Offer calldata offer, bytes calldata signature)
        external
        view
        returns (address)
    {
        return ECDSA.recover(hashOffer(offer), signature);
    }

    function offerRecord(bytes32 offerId) external view returns (OfferRecord memory) {
        return _offer(offerId);
    }

    function offerState(bytes32 offerId) external view returns (LoanTypes.OfferState) {
        return _offers[offerId].state;
    }

    function _validateOfferFields(LoanTypes.Offer calldata offer) private view {
        if (
            offer.offerId == bytes32(0) || offer.tenderId == bytes32(0)
                || offer.lender == address(0) || offer.borrower == address(0)
                || offer.lender == offer.borrower || offer.assetId == bytes32(0)
                || offer.principalAmount == 0 || offer.originationFee >= offer.principalAmount
                || offer.fundingDeadline < block.timestamp
                || offer.activationDeadline < offer.fundingDeadline
                || offer.finalMaturityTime <= offer.activationDeadline || offer.protocolVersion == 0
                || offer.policySetHash == bytes32(0) || offer.agreementHash == bytes32(0)
                || offer.metadataHash == bytes32(0) || offer.expiry <= block.timestamp
                || offer.expiry > offer.fundingDeadline
        ) {
            revert InvalidOffer();
        }
    }

    function _offer(bytes32 offerId) private view returns (OfferRecord storage record) {
        record = _offers[offerId];
        if (record.lender == address(0)) revert UnknownOffer(offerId);
    }
}
