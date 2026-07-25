// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPhase9LoanAccount } from "../interfaces/phase9/IPhase9LoanAccount.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for the non-upgradeable version-9 debt authority.
contract Phase9LoanAccount is IPhase9LoanAccount {
    address private _factory;
    address private _loanRegistry;
    address private _settlementToken;
    bytes32 private _settlementAssetId;
    address private _borrower;
    address private _positionManager;
    address private _collateralCustody;
    address private _lienRegistry;
    address private _payoffQuoteEngine;
    address private _refinanceCoordinator;
    address private _restructuringController;
    address private _insuranceManager;
    address private _recoveryManager;
    bytes32 private _loanId;
    bytes32 private _agreementHash;
    bytes32 private _policySetHash;
    bytes32 private _amendmentPolicyHash;
    bytes32 private _protectionPolicyHash;
    bytes32 private _recoveryPolicyHash;
    uint32 private _protocolVersion;

    Phase9Types.LoanLifecycle private _lifecycle;
    Phase9Types.ServicingState private _servicingState;
    uint64 private _termsVersion;
    uint64 private _debtStateVersion;
    uint64 private _stateNonce;
    uint64 private _commencementTime;
    uint64 private _maturityTime;
    bytes32 private _scheduleHash;
    uint256 private _outstandingPrincipal;
    uint256 private _accruedInterest;
    uint256 private _capitalizedInterest;
    uint256 private _accruedFees;
    uint256 private _accruedPenalties;
    uint256 private _recoverableCosts;
    uint256 private _unappliedCredit;
    uint256 private _coveredLossExposure;
    uint256 private _realizedLoss;
    uint256 private _writtenOffAmount;
    uint256 private _recoveredAfterWriteoff;
    bytes32 private _activeRefinanceId;
    bytes32 private _activeRestructureId;
    mapping(uint64 agreementVersion => bytes32 agreementHash) private _agreementVersionHashes;
    mapping(bytes32 operationId => bool processed) private _processedOperationIds;
    bool private _initialized;

    function initialize(Phase9Types.LoanConfiguration calldata, Phase9Types.DebtState calldata)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function configuration() external view override returns (Phase9Types.LoanConfiguration memory) {
        return Phase9Types.LoanConfiguration({
            factory: _factory,
            loanRegistry: _loanRegistry,
            settlementToken: _settlementToken,
            settlementAssetId: _settlementAssetId,
            borrower: _borrower,
            positionManager: _positionManager,
            collateralCustody: _collateralCustody,
            lienRegistry: _lienRegistry,
            payoffQuoteEngine: _payoffQuoteEngine,
            refinanceCoordinator: _refinanceCoordinator,
            restructuringController: _restructuringController,
            insuranceManager: _insuranceManager,
            recoveryManager: _recoveryManager,
            loanId: _loanId,
            agreementHash: _agreementHash,
            policySetHash: _policySetHash,
            amendmentPolicyHash: _amendmentPolicyHash,
            protectionPolicyHash: _protectionPolicyHash,
            recoveryPolicyHash: _recoveryPolicyHash
        });
    }

    function debtState() external view override returns (Phase9Types.DebtState memory) {
        return Phase9Types.DebtState({
            lifecycle: _lifecycle,
            servicingState: _servicingState,
            termsVersion: _termsVersion,
            debtStateVersion: _debtStateVersion,
            stateNonce: _stateNonce,
            commencementTime: _commencementTime,
            maturityTime: _maturityTime,
            scheduleHash: _scheduleHash,
            outstandingPrincipal: _outstandingPrincipal,
            accruedInterest: _accruedInterest,
            capitalizedInterest: _capitalizedInterest,
            accruedFees: _accruedFees,
            accruedPenalties: _accruedPenalties,
            recoverableCosts: _recoverableCosts,
            unappliedCredit: _unappliedCredit,
            coveredLossExposure: _coveredLossExposure,
            realizedLoss: _realizedLoss,
            writtenOffAmount: _writtenOffAmount,
            recoveredAfterWriteoff: _recoveredAfterWriteoff,
            activeRefinanceId: _activeRefinanceId,
            activeRestructureId: _activeRestructureId
        });
    }

    function agreementVersionHash(uint64 version) external view override returns (bytes32) {
        return _agreementVersionHashes[version];
    }

    function operationProcessed(bytes32 operationId) external view override returns (bool) {
        return _processedOperationIds[operationId];
    }

    function recordRefinancePayoff(bytes32, uint256, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function activateReplacementLoan(bytes32, Phase9Types.DebtState calldata, bytes32)
        external
        override
    {
        revert Phase9ImplementationNotFrozen();
    }

    function applyRestructuring(Phase9Types.LoanAmendment calldata, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function recordCoveredLoss(bytes32, uint256, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function recordRealizedLoss(bytes32, uint256, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function recordWriteOff(bytes32, uint256, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function recordPostWriteOffRecovery(bytes32, uint256, bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }

    function closeLoan(bytes32) external override {
        revert Phase9ImplementationNotFrozen();
    }
}
