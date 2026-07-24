// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { LoanTypes } from "../loan/LoanTypes.sol";
import { CreditDecisionRegistry } from "./CreditDecisionRegistry.sol";
import { IdentityTypes } from "./IdentityTypes.sol";

interface IExposureLoan {
    function debtSnapshot(uint64 asOf) external view returns (LoanTypes.DebtSnapshot memory);
}

/// @notice Conservative exact-asset exposure reservations aggregated by subject commitment.
contract ExposureManager is RoleControlled {
    error InvalidExposure();
    error ExposureLimitExceeded();
    error InvalidExposureState(IdentityTypes.ExposureStatus status);

    uint64 public constant RESERVATION_TTL = 15 minutes;

    CreditDecisionRegistry public immutable decisionRegistry;
    ILoanRegistry public immutable loanRegistry;
    mapping(bytes32 loanId => IdentityTypes.ExposureReservation reservation_) private _reservations;
    bytes32[] private _reservationIds;
    mapping(
        bytes32 subjectCommitment => mapping(bytes32 assetId => IdentityTypes.ExposureTotals)
    ) private _exposure;

    event ExposureReserved(
        bytes32 indexed loanId,
        bytes32 indexed decisionId,
        bytes32 indexed subjectCommitment,
        address borrower,
        bytes32 settlementAssetId,
        bytes32 productHash,
        uint256 amount,
        uint64 duration,
        uint64 reservationExpiresAt,
        address factory,
        bytes32 evidenceHash
    );
    event ExposureActivated(
        bytes32 indexed loanId, uint256 amount, address indexed loanAccount, bytes32 evidenceHash
    );
    event ExposureReleased(bytes32 indexed loanId, uint256 amount, bytes32 indexed evidenceHash);
    event ExposureReservationCancelled(
        bytes32 indexed loanId, uint256 amount, bytes32 indexed evidenceHash
    );

    constructor(
        IRoleManager roleManager_,
        CreditDecisionRegistry decisionRegistry_,
        ILoanRegistry loanRegistry_
    ) RoleControlled(roleManager_) {
        if (address(decisionRegistry_).code.length == 0 || address(loanRegistry_).code.length == 0)
        {
            revert InvalidExposure();
        }
        decisionRegistry = decisionRegistry_;
        loanRegistry = loanRegistry_;
    }

    function reserve(
        bytes32 decisionId,
        bytes32 loanId,
        address borrower,
        uint256 amount,
        uint64 duration,
        bytes32 productHash,
        bytes32 evidenceHash
    ) external onlyRole(ProtocolRoles.EXPOSURE_FACTORY_ROLE) {
        if (
            msg.sender.code.length == 0 || loanId == bytes32(0) || borrower == address(0)
                || amount == 0 || duration == 0 || productHash == bytes32(0)
                || evidenceHash == bytes32(0)
                || _reservations[loanId].status != IdentityTypes.ExposureStatus.NONE
                || loanRegistry.exists(loanId)
        ) {
            revert InvalidExposure();
        }
        IdentityTypes.CreditDecision memory decision_ = decisionRegistry.decision(decisionId);
        if (!decisionRegistry.isUsable(
                decisionId,
                borrower,
                decision_.subjectCommitment,
                decision_.settlementAssetId,
                productHash,
                amount,
                duration
            )) {
            revert InvalidExposure();
        }
        IdentityTypes.ExposureTotals storage totals =
            _exposure[decision_.subjectCommitment][decision_.settlementAssetId];
        if (totals.reserved + totals.active + amount > decision_.maximumExposure) {
            revert ExposureLimitExceeded();
        }
        uint64 expiresAt = uint64(block.timestamp + RESERVATION_TTL);
        _reservations[loanId] = IdentityTypes.ExposureReservation({
            loanId: loanId,
            decisionId: decisionId,
            subjectCommitment: decision_.subjectCommitment,
            borrower: borrower,
            settlementAssetId: decision_.settlementAssetId,
            productHash: productHash,
            amount: amount,
            duration: duration,
            reservedAt: uint64(block.timestamp),
            reservationExpiresAt: expiresAt,
            factory: msg.sender,
            status: IdentityTypes.ExposureStatus.RESERVED
        });
        _reservationIds.push(loanId);
        totals.reserved += amount;
        emit ExposureReserved(
            loanId,
            decisionId,
            decision_.subjectCommitment,
            borrower,
            decision_.settlementAssetId,
            productHash,
            amount,
            duration,
            expiresAt,
            msg.sender,
            evidenceHash
        );
    }

    function activate(bytes32 loanId, bytes32 evidenceHash) external {
        IdentityTypes.ExposureReservation storage reservation_ = _reservation(loanId);
        if (
            msg.sender != reservation_.factory
                || reservation_.status != IdentityTypes.ExposureStatus.RESERVED
                || block.timestamp >= reservation_.reservationExpiresAt
                || evidenceHash == bytes32(0) || !loanRegistry.exists(loanId)
                || loanRegistry.isTerminal(loanId)
                || loanRegistry.borrowerOf(loanId) != reservation_.borrower
                || !decisionRegistry.isUsable(
                    reservation_.decisionId,
                    reservation_.borrower,
                    reservation_.subjectCommitment,
                    reservation_.settlementAssetId,
                    reservation_.productHash,
                    reservation_.amount,
                    reservation_.duration
                )
        ) {
            revert InvalidExposureState(reservation_.status);
        }
        address account = loanRegistry.loanAccount(loanId);
        LoanTypes.DebtSnapshot memory debt =
            IExposureLoan(account).debtSnapshot(uint64(block.timestamp));
        if (debt.outstandingPrincipal != reservation_.amount) revert InvalidExposure();
        reservation_.status = IdentityTypes.ExposureStatus.ACTIVE;
        IdentityTypes.ExposureTotals storage totals =
            _exposure[reservation_.subjectCommitment][reservation_.settlementAssetId];
        totals.reserved -= reservation_.amount;
        totals.active += reservation_.amount;
        emit ExposureActivated(loanId, reservation_.amount, account, evidenceHash);
    }

    function cancelReservation(bytes32 loanId, bytes32 evidenceHash) external {
        IdentityTypes.ExposureReservation storage reservation_ = _reservation(loanId);
        if (
            reservation_.status != IdentityTypes.ExposureStatus.RESERVED
                || evidenceHash == bytes32(0)
        ) {
            revert InvalidExposureState(reservation_.status);
        }
        bool factoryCancellation =
            msg.sender == reservation_.factory && !loanRegistry.exists(loanId);
        bool expiredCancellation =
            block.timestamp >= reservation_.reservationExpiresAt && !loanRegistry.exists(loanId);
        bool terminalCancellation = loanRegistry.exists(loanId) && loanRegistry.isTerminal(loanId)
            && _outstandingPrincipal(loanId) == 0;
        if (!factoryCancellation && !expiredCancellation && !terminalCancellation) {
            revert InvalidExposure();
        }
        reservation_.status = IdentityTypes.ExposureStatus.CANCELLED;
        _exposure[reservation_.subjectCommitment][reservation_.settlementAssetId].reserved -= reservation_.amount;
        emit ExposureReservationCancelled(loanId, reservation_.amount, evidenceHash);
    }

    function release(bytes32 loanId, bytes32 evidenceHash) external {
        IdentityTypes.ExposureReservation storage reservation_ = _reservation(loanId);
        if (
            reservation_.status != IdentityTypes.ExposureStatus.ACTIVE || evidenceHash == bytes32(0)
                || !loanRegistry.isTerminal(loanId) || _outstandingPrincipal(loanId) != 0
        ) {
            revert InvalidExposureState(reservation_.status);
        }
        reservation_.status = IdentityTypes.ExposureStatus.RELEASED;
        _exposure[reservation_.subjectCommitment][reservation_.settlementAssetId].active -= reservation_.amount;
        emit ExposureReleased(loanId, reservation_.amount, evidenceHash);
    }

    function reservation(bytes32 loanId)
        external
        view
        returns (IdentityTypes.ExposureReservation memory)
    {
        return _reservation(loanId);
    }

    function reservationIds() external view returns (bytes32[] memory) {
        return _reservationIds;
    }

    function exposure(bytes32 subjectCommitment, bytes32 settlementAssetId)
        external
        view
        returns (IdentityTypes.ExposureTotals memory)
    {
        return _exposure[subjectCommitment][settlementAssetId];
    }

    function _reservation(bytes32 loanId)
        private
        view
        returns (IdentityTypes.ExposureReservation storage reservation_)
    {
        reservation_ = _reservations[loanId];
        if (reservation_.status == IdentityTypes.ExposureStatus.NONE) {
            revert InvalidExposure();
        }
    }

    function _outstandingPrincipal(bytes32 loanId) private view returns (uint256) {
        address account = loanRegistry.loanAccount(loanId);
        return IExposureLoan(account).debtSnapshot(uint64(block.timestamp)).outstandingPrincipal;
    }
}
