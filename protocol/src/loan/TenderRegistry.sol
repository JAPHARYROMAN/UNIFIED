// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { LoanTypes } from "./LoanTypes.sol";

/// @notice Canonical on-chain tender identity and binding status.
contract TenderRegistry is RoleControlled {
    error InvalidTender();
    error TenderAlreadyRegistered(bytes32 tenderId);
    error UnknownTender(bytes32 tenderId);
    error InvalidTenderState(bytes32 tenderId, LoanTypes.TenderState state);
    error NotTenderBorrower(bytes32 tenderId, address account);

    struct Tender {
        address borrower;
        bytes32 metadataHash;
        uint64 expiry;
        LoanTypes.TenderState state;
        bytes32 selectedOfferId;
        bytes32 loanId;
    }

    mapping(bytes32 tenderId => Tender tender) private _tenders;

    event TenderRegistered(
        bytes32 indexed tenderId, address indexed borrower, bytes32 metadataHash
    );
    event TenderStateChanged(
        bytes32 indexed tenderId, LoanTypes.TenderState fromState, LoanTypes.TenderState toState
    );
    event OfferSelected(bytes32 indexed tenderId, bytes32 indexed offerId);
    event TenderFulfilled(bytes32 indexed tenderId, bytes32 indexed loanId);

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function registerTender(bytes32 tenderId, address borrower, bytes32 metadataHash, uint64 expiry)
        external
    {
        if (
            tenderId == bytes32(0) || borrower == address(0) || borrower != msg.sender
                || metadataHash == bytes32(0) || expiry <= block.timestamp
        ) {
            revert InvalidTender();
        }
        if (_tenders[tenderId].borrower != address(0)) {
            revert TenderAlreadyRegistered(tenderId);
        }
        _tenders[tenderId] = Tender({
            borrower: borrower,
            metadataHash: metadataHash,
            expiry: expiry,
            state: LoanTypes.TenderState.OPEN,
            selectedOfferId: bytes32(0),
            loanId: bytes32(0)
        });
        emit TenderRegistered(tenderId, borrower, metadataHash);
        emit TenderStateChanged(tenderId, LoanTypes.TenderState.NONE, LoanTypes.TenderState.OPEN);
    }

    function cancelTender(bytes32 tenderId) external {
        Tender storage record = _tender(tenderId);
        if (record.borrower != msg.sender) revert NotTenderBorrower(tenderId, msg.sender);
        _requireState(tenderId, record.state, LoanTypes.TenderState.OPEN);
        record.state = LoanTypes.TenderState.CANCELLED;
        emit TenderStateChanged(
            tenderId, LoanTypes.TenderState.OPEN, LoanTypes.TenderState.CANCELLED
        );
    }

    function selectOffer(bytes32 tenderId, bytes32 offerId)
        external
        onlyRole(ProtocolRoles.LOAN_FACTORY_ROLE)
    {
        if (offerId == bytes32(0)) revert InvalidTender();
        Tender storage record = _tender(tenderId);
        _requireState(tenderId, record.state, LoanTypes.TenderState.OPEN);
        if (record.expiry < block.timestamp) revert InvalidTender();
        record.selectedOfferId = offerId;
        record.state = LoanTypes.TenderState.COMMITMENT_PENDING;
        emit OfferSelected(tenderId, offerId);
        emit TenderStateChanged(
            tenderId, LoanTypes.TenderState.OPEN, LoanTypes.TenderState.COMMITMENT_PENDING
        );
    }

    function markFulfilled(bytes32 tenderId, bytes32 loanId)
        external
        onlyRole(ProtocolRoles.LOAN_FACTORY_ROLE)
    {
        if (loanId == bytes32(0)) revert InvalidTender();
        Tender storage record = _tender(tenderId);
        _requireState(tenderId, record.state, LoanTypes.TenderState.COMMITMENT_PENDING);
        record.loanId = loanId;
        record.state = LoanTypes.TenderState.FULFILLED;
        emit TenderFulfilled(tenderId, loanId);
        emit TenderStateChanged(
            tenderId, LoanTypes.TenderState.COMMITMENT_PENDING, LoanTypes.TenderState.FULFILLED
        );
    }

    function expireTender(bytes32 tenderId) external {
        Tender storage record = _tender(tenderId);
        _requireState(tenderId, record.state, LoanTypes.TenderState.OPEN);
        if (record.expiry >= block.timestamp) revert InvalidTender();
        record.state = LoanTypes.TenderState.EXPIRED;
        emit TenderStateChanged(tenderId, LoanTypes.TenderState.OPEN, LoanTypes.TenderState.EXPIRED);
    }

    function tender(bytes32 tenderId) external view returns (Tender memory) {
        return _tender(tenderId);
    }

    function tenderOwner(bytes32 tenderId) external view returns (address) {
        return _tenders[tenderId].borrower;
    }

    function tenderState(bytes32 tenderId) external view returns (LoanTypes.TenderState) {
        return _tenders[tenderId].state;
    }

    function _tender(bytes32 tenderId) private view returns (Tender storage record) {
        record = _tenders[tenderId];
        if (record.borrower == address(0)) revert UnknownTender(tenderId);
    }

    function _requireState(
        bytes32 tenderId,
        LoanTypes.TenderState actual,
        LoanTypes.TenderState expected
    ) private pure {
        if (actual != expected) {
            revert InvalidTenderState(tenderId, actual);
        }
    }
}
