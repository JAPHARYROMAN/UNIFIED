// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPhase9LoanAccount } from "../interfaces/phase9/IPhase9LoanAccount.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9LocalSyntheticToken } from "../token/Phase9LocalSyntheticToken.sol";
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
    bool private _initialized = true;

    function initialize(Phase9Types.LoanConfiguration calldata, Phase9Types.DebtState calldata)
        external
        override
    {
        (
            Phase9Types.LoanConfiguration memory configuration_,
            Phase9Types.DebtState memory initialDebt
        ) = abi.decode(msg.data[4:], (Phase9Types.LoanConfiguration, Phase9Types.DebtState));
        address expectedFactory = _initialized ? _factory : configuration_.factory;
        if (msg.sender != expectedFactory) {
            revert UnauthorizedPhase9LoanCaller(msg.sender);
        }
        if (_initialized || !_validConfiguration(configuration_)) {
            revert InvalidPhase9LoanOperation();
        }

        bool activeBootstrap = _validActiveBootstrapDebt(initialDebt);
        if (!activeBootstrap && !_validDormantReplacementDebt(initialDebt)) {
            revert InvalidPhase9LoanOperation();
        }

        _initialized = true;
        _storeConfiguration(configuration_);
        _storeDebt(initialDebt);
        _protocolVersion = 9;

        if (activeBootstrap) {
            _agreementVersionHashes[initialDebt.termsVersion] = configuration_.agreementHash;
        }
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

    function _validConfiguration(Phase9Types.LoanConfiguration memory configuration_)
        private
        view
        returns (bool)
    {
        return block.chainid == 31337 && configuration_.factory != address(0)
            && configuration_.factory.code.length != 0 && configuration_.loanRegistry != address(0)
            && configuration_.loanRegistry.code.length != 0
            && configuration_.settlementToken != address(0)
            && configuration_.settlementToken.codehash
                == keccak256(type(Phase9LocalSyntheticToken).runtimeCode)
            && configuration_.settlementAssetId
                == 0x61737365743a7068617365393a7039756e697400000000000000000000000000
            && configuration_.borrower != address(0) && configuration_.positionManager != address(0)
            && configuration_.positionManager.code.length != 0
            && configuration_.collateralCustody != address(0)
            && configuration_.collateralCustody.code.length != 0
            && configuration_.lienRegistry != address(0)
            && configuration_.lienRegistry.code.length != 0
            && configuration_.payoffQuoteEngine != address(0)
            && configuration_.payoffQuoteEngine.code.length != 0
            && configuration_.refinanceCoordinator != address(0)
            && configuration_.refinanceCoordinator.code.length != 0
            && configuration_.restructuringController != address(0)
            && configuration_.restructuringController.code.length != 0
            && configuration_.insuranceManager != address(0)
            && configuration_.insuranceManager.code.length != 0
            && configuration_.recoveryManager != address(0)
            && configuration_.recoveryManager.code.length != 0
            && configuration_.loanId != bytes32(0) && configuration_.agreementHash != bytes32(0)
            && configuration_.policySetHash != bytes32(0)
            && configuration_.amendmentPolicyHash != bytes32(0)
            && configuration_.protectionPolicyHash != bytes32(0)
            && configuration_.recoveryPolicyHash != bytes32(0);
    }

    function _validActiveBootstrapDebt(Phase9Types.DebtState memory debt)
        private
        pure
        returns (bool)
    {
        return debt.lifecycle == Phase9Types.LoanLifecycle.ACTIVE
            && debt.servicingState == Phase9Types.ServicingState.CURRENT && debt.termsVersion != 0
            && debt.activeRefinanceId == bytes32(0) && debt.activeRestructureId == bytes32(0);
    }

    function _validDormantReplacementDebt(Phase9Types.DebtState memory debt)
        private
        pure
        returns (bool)
    {
        return debt.lifecycle == Phase9Types.LoanLifecycle.CREATED
            && debt.servicingState == Phase9Types.ServicingState.NONE && debt.termsVersion == 0
            && debt.debtStateVersion == 0 && debt.stateNonce == 0 && debt.commencementTime == 0
            && debt.maturityTime == 0 && debt.scheduleHash == bytes32(0)
            && debt.outstandingPrincipal == 0 && debt.accruedInterest == 0
            && debt.capitalizedInterest == 0 && debt.accruedFees == 0 && debt.accruedPenalties == 0
            && debt.recoverableCosts == 0 && debt.unappliedCredit == 0
            && debt.coveredLossExposure == 0 && debt.realizedLoss == 0 && debt.writtenOffAmount == 0
            && debt.recoveredAfterWriteoff == 0 && debt.activeRefinanceId == bytes32(0)
            && debt.activeRestructureId == bytes32(0);
    }

    function _storeConfiguration(Phase9Types.LoanConfiguration memory configuration_) private {
        _factory = configuration_.factory;
        _loanRegistry = configuration_.loanRegistry;
        _settlementToken = configuration_.settlementToken;
        _settlementAssetId = configuration_.settlementAssetId;
        _borrower = configuration_.borrower;
        _positionManager = configuration_.positionManager;
        _collateralCustody = configuration_.collateralCustody;
        _lienRegistry = configuration_.lienRegistry;
        _payoffQuoteEngine = configuration_.payoffQuoteEngine;
        _refinanceCoordinator = configuration_.refinanceCoordinator;
        _restructuringController = configuration_.restructuringController;
        _insuranceManager = configuration_.insuranceManager;
        _recoveryManager = configuration_.recoveryManager;
        _loanId = configuration_.loanId;
        _agreementHash = configuration_.agreementHash;
        _policySetHash = configuration_.policySetHash;
        _amendmentPolicyHash = configuration_.amendmentPolicyHash;
        _protectionPolicyHash = configuration_.protectionPolicyHash;
        _recoveryPolicyHash = configuration_.recoveryPolicyHash;
    }

    function _storeDebt(Phase9Types.DebtState memory debt) private {
        _lifecycle = debt.lifecycle;
        _servicingState = debt.servicingState;
        _termsVersion = debt.termsVersion;
        _debtStateVersion = debt.debtStateVersion;
        _stateNonce = debt.stateNonce;
        _commencementTime = debt.commencementTime;
        _maturityTime = debt.maturityTime;
        _scheduleHash = debt.scheduleHash;
        _outstandingPrincipal = debt.outstandingPrincipal;
        _accruedInterest = debt.accruedInterest;
        _capitalizedInterest = debt.capitalizedInterest;
        _accruedFees = debt.accruedFees;
        _accruedPenalties = debt.accruedPenalties;
        _recoverableCosts = debt.recoverableCosts;
        _unappliedCredit = debt.unappliedCredit;
        _coveredLossExposure = debt.coveredLossExposure;
        _realizedLoss = debt.realizedLoss;
        _writtenOffAmount = debt.writtenOffAmount;
        _recoveredAfterWriteoff = debt.recoveredAfterWriteoff;
        _activeRefinanceId = debt.activeRefinanceId;
        _activeRestructureId = debt.activeRestructureId;
    }
}
