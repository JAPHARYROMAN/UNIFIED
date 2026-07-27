// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IPhase9LoanAccount } from "../interfaces/phase9/IPhase9LoanAccount.sol";
import { IPhase9LoanFactory } from "../interfaces/phase9/IPhase9LoanFactory.sol";
import { IPositionManagerV2 } from "../interfaces/phase9/IPositionManagerV2.sol";
import { Phase9ImplementationNotFrozen } from "../interfaces/phase9/Phase9Errors.sol";
import { Phase9LocalSyntheticToken } from "../token/Phase9LocalSyntheticToken.sol";
import { Phase9Types } from "./Phase9Types.sol";

/// @notice ABI/storage freeze stub for version-9 loan creation.
contract Phase9LoanFactory is IPhase9LoanFactory {
    struct CreationResolution {
        Phase9Types.LoanConfiguration configuration;
        uint8 creationMode;
        bytes32 bootstrapId;
    }

    struct CreationIdentity {
        uint256 chainId;
        address factory;
        bytes32 loanId;
        bytes32 oldLoanId;
        address borrower;
        bytes32 refinanceId;
        uint64 newLoanNonce;
        uint64 loanNonce;
        bytes32 agreementHash;
        bytes32 policySetHash;
        uint8 creationMode;
        bytes32 bootstrapId;
        address predictedAccount;
        address predictedManager;
    }

    ILoanRegistry private _loanRegistry;
    address private _loanAccountImplementation;
    address private _positionManagerImplementation;
    address private _quotePolicyRegistry;
    address private _refinancePolicyRegistry;
    address private _amendmentPolicyRegistry;
    address private _protectionPolicyRegistry;
    address private _recoveryPolicyRegistry;
    uint64 private _nextLoanNonce;
    mapping(bytes32 loanId => address account) private _loanAccounts;
    mapping(bytes32 loanId => address manager) private _positionManagers;
    mapping(bytes32 creationId => Phase9Types.LoanCreationRequest request) private
        _creationRequests;
    mapping(bytes32 creationId => bool processed) private _processedCreationIds;

    constructor(
        ILoanRegistry loanRegistry_,
        address loanAccountImplementation_,
        address positionManagerImplementation_,
        address quotePolicyRegistry_,
        address refinancePolicyRegistry_,
        address amendmentPolicyRegistry_,
        address protectionPolicyRegistry_,
        address recoveryPolicyRegistry_
    ) {
        _loanRegistry = loanRegistry_;
        _loanAccountImplementation = loanAccountImplementation_;
        _positionManagerImplementation = positionManagerImplementation_;
        _quotePolicyRegistry = quotePolicyRegistry_;
        _refinancePolicyRegistry = refinancePolicyRegistry_;
        _amendmentPolicyRegistry = amendmentPolicyRegistry_;
        _protectionPolicyRegistry = protectionPolicyRegistry_;
        _recoveryPolicyRegistry = recoveryPolicyRegistry_;
        _nextLoanNonce = 1;
    }

    function createLoan(Phase9Types.LoanCreationRequest calldata)
        external
        override
        returns (address, address)
    {
        if (msg.data.length == 0) _phase9FrozenErrorCompatibilityMarker();
        Phase9Types.LoanCreationRequest memory request =
            abi.decode(msg.data[4:], (Phase9Types.LoanCreationRequest));

        if (_processedCreationIds[request.creationId]) {
            return _replayCreation(request);
        }
        if (request.creationId != bytes32(0)) revert InvalidPhase9LoanConfiguration();
        return _createFreshLoan(request);
    }

    function loanAccount(bytes32 loanId) external view override returns (address) {
        return _loanAccounts[loanId];
    }

    function positionManager(bytes32 loanId) external view override returns (address) {
        return _positionManagers[loanId];
    }

    function creationRequest(bytes32 creationId)
        external
        view
        override
        returns (Phase9Types.LoanCreationRequest memory)
    {
        return _creationRequests[creationId];
    }

    function nextLoanNonce() external view override returns (uint64) {
        return _nextLoanNonce;
    }

    function _replayCreation(Phase9Types.LoanCreationRequest memory supplied)
        private
        view
        returns (address loanAccount_, address positionManager_)
    {
        Phase9Types.LoanCreationRequest memory stored = _creationRequests[supplied.creationId];
        if (keccak256(abi.encode(stored)) != keccak256(abi.encode(supplied))) {
            revert InvalidPhase9LoanConfiguration();
        }

        CreationResolution memory resolution =
            _resolveCreation(stored.configuration.policySetHash, stored.configuration.loanId);
        loanAccount_ = _loanAccounts[stored.configuration.loanId];
        positionManager_ = _positionManagers[stored.configuration.loanId];
        if (
            keccak256(abi.encode(resolution.configuration))
                != keccak256(abi.encode(stored.configuration))
                || !_validMode(stored, resolution.creationMode, resolution.bootstrapId)
                || !_validConfiguration(stored.configuration, positionManager_, true)
                || msg.sender != resolution.configuration.refinanceCoordinator
                || loanAccount_ == address(0) || loanAccount_.code.length == 0
                || positionManager_ == address(0) || positionManager_.code.length == 0
                || !_validCloneRuntime(loanAccount_, _loanAccountImplementation)
                || !_validCloneRuntime(positionManager_, _positionManagerImplementation)
        ) {
            revert InvalidPhase9LoanConfiguration();
        }
        _requireRegistryIdentity(stored.configuration, loanAccount_, false);
    }

    function _createFreshLoan(Phase9Types.LoanCreationRequest memory supplied)
        private
        returns (address loanAccount_, address positionManager_)
    {
        if (!_validFactoryDependencies()) revert InvalidPhase9LoanConfiguration();

        Phase9Types.LoanCreationRequest memory request = supplied;
        CreationResolution memory resolution =
            _resolveCreation(request.configuration.policySetHash, request.configuration.loanId);
        if (
            keccak256(abi.encode(resolution.configuration))
                != keccak256(abi.encode(request.configuration))
                || msg.sender != resolution.configuration.refinanceCoordinator
        ) {
            revert InvalidPhase9LoanConfiguration();
        }

        bytes32 accountSalt = keccak256(
            abi.encode("UNIFIED_PHASE9_LOAN_ACCOUNT_CLONE_V1", request.configuration.loanId)
        );
        bytes32 managerSalt = keccak256(
            abi.encode("UNIFIED_PHASE9_POSITION_MANAGER_CLONE_V1", request.configuration.loanId)
        );
        loanAccount_ = _predictDeterministicAddress(_loanAccountImplementation, accountSalt);
        positionManager_ =
            _predictDeterministicAddress(_positionManagerImplementation, managerSalt);

        if (
            !_validMode(request, resolution.creationMode, resolution.bootstrapId)
                || !_validConfiguration(request.configuration, positionManager_, false)
        ) {
            revert InvalidPhase9LoanConfiguration();
        }
        _requireFreshLoan(request.configuration.loanId);

        uint64 loanNonce = _nextLoanNonce;
        if (loanNonce == 0 || loanNonce == type(uint64).max) {
            revert InvalidPhase9LoanConfiguration();
        }
        if (resolution.creationMode == 1) {
            if (loanNonce != 1) revert InvalidPhase9LoanConfiguration();
        } else {
            _requireCanonicalSourceLoan(
                request.oldLoanId, request.configuration.refinanceCoordinator
            );
        }
        if (loanAccount_.code.length != 0 || positionManager_.code.length != 0) {
            revert InvalidPhase9LoanConfiguration();
        }

        bytes32 creationId = _deriveCreationId(
            request,
            resolution.creationMode,
            resolution.bootstrapId,
            loanAccount_,
            positionManager_,
            loanNonce
        );
        if (creationId == bytes32(0) || _processedCreationIds[creationId]) {
            revert InvalidPhase9LoanConfiguration();
        }

        Phase9Types.DebtState memory initialDebt;
        if (resolution.creationMode == 1) {
            initialDebt = _resolveBootstrap(resolution.bootstrapId, request.configuration);
        } else {
            initialDebt.lifecycle = Phase9Types.LoanLifecycle.CREATED;
        }

        request.creationId = creationId;
        _creationRequests[creationId] = request;
        _processedCreationIds[creationId] = true;
        _loanAccounts[request.configuration.loanId] = loanAccount_;
        _positionManagers[request.configuration.loanId] = positionManager_;
        _nextLoanNonce = loanNonce + 1;

        address deployedAccount = _cloneDeterministic(_loanAccountImplementation, accountSalt);
        address deployedManager =
            _cloneDeterministic(_positionManagerImplementation, managerSalt);
        if (
            deployedAccount != loanAccount_ || deployedManager != positionManager_
                || !_validCloneRuntime(deployedAccount, _loanAccountImplementation)
                || !_validCloneRuntime(deployedManager, _positionManagerImplementation)
        ) {
            revert InvalidPhase9LoanConfiguration();
        }

        try IPhase9LoanAccount(deployedAccount).initialize(request.configuration, initialDebt) { }
        catch {
            revert InvalidPhase9LoanConfiguration();
        }
        try IPositionManagerV2(deployedManager).initialize(
            request.configuration.loanId, deployedAccount, request.configuration.settlementToken
        ) { }
        catch {
            revert InvalidPhase9LoanConfiguration();
        }

        try _loanRegistry.registerLoan(
            request.configuration.loanId,
            deployedAccount,
            request.configuration.borrower,
            request.configuration.agreementHash,
            9
        ) { }
        catch {
            revert InvalidPhase9LoanConfiguration();
        }
        _requireRegistryIdentity(request.configuration, deployedAccount, true);

        emit Phase9LoanCreated(
            request.configuration.loanId,
            request.refinanceId,
            deployedAccount,
            deployedManager,
            request.configuration.borrower,
            request.oldLoanId,
            request.newLoanNonce,
            loanNonce
        );
    }

    function _resolveCreation(bytes32 policySetHash, bytes32 loanId)
        private
        view
        returns (CreationResolution memory resolution)
    {
        try IPhase9RefinancePolicySource(_refinancePolicyRegistry).resolveLoanCreation(
            policySetHash, loanId
        ) returns (
            Phase9Types.LoanConfiguration memory configuration_,
            uint8 creationMode,
            bytes32 bootstrapId,
            bool active
        ) {
            if (!active) revert InvalidPhase9LoanConfiguration();
            resolution = CreationResolution({
                configuration: configuration_,
                creationMode: creationMode,
                bootstrapId: bootstrapId
            });
        } catch {
            revert InvalidPhase9LoanConfiguration();
        }
    }

    function _resolveBootstrap(
        bytes32 bootstrapId,
        Phase9Types.LoanConfiguration memory configuration_
    ) private view returns (Phase9Types.DebtState memory initialDebt) {
        try IPhase9RefinancePolicySource(_refinancePolicyRegistry).resolveBootstrap(bootstrapId)
        returns (
            bytes32 policySetHash,
            bytes32 loanId,
            Phase9Types.DebtState memory debt,
            Phase9Types.Tranche[] memory tranches,
            Phase9Types.Position[] memory positions,
            Phase9Types.CustodyRecord[] memory custodyRecords,
            Phase9Types.Lien[] memory liens,
            bool active
        ) {
            if (
                !active || policySetHash != configuration_.policySetHash
                    || loanId != configuration_.loanId || !_validActiveBootstrapDebt(debt)
                    || !_validBootstrapPositions(tranches, positions, debt)
                    || !_validBootstrapCollateral(configuration_, custodyRecords, liens)
            ) {
                revert InvalidPhase9LoanConfiguration();
            }
            initialDebt = debt;
        } catch {
            revert InvalidPhase9LoanConfiguration();
        }
    }

    function _validMode(
        Phase9Types.LoanCreationRequest memory request,
        uint8 creationMode,
        bytes32 bootstrapId
    ) private view returns (bool) {
        if (creationMode == 1) {
            bytes32 expectedBootstrapId = keccak256(
                abi.encode(
                    "UNIFIED_PHASE9_LOCAL_BOOTSTRAP_V1",
                    block.chainid,
                    address(this),
                    _refinancePolicyRegistry,
                    request.configuration.loanId,
                    request.configuration.borrower,
                    request.configuration.policySetHash
                )
            );
            return request.oldLoanId == bytes32(0) && request.refinanceId == bytes32(0)
                && request.newLoanNonce == 0 && bootstrapId != bytes32(0)
                && bootstrapId == expectedBootstrapId;
        }
        if (creationMode != 2 || bootstrapId != bytes32(0) || request.oldLoanId == bytes32(0)
            || request.refinanceId == bytes32(0) || request.newLoanNonce == 0
            || request.newLoanNonce >= type(uint64).max >> 1) {
            return false;
        }

        return request.configuration.loanId
            == keccak256(
                abi.encode(
                    "UNIFIED_PHASE9_REFINANCED_LOAN_V1",
                    block.chainid,
                    address(this),
                    request.oldLoanId,
                    request.configuration.borrower,
                    request.configuration.agreementHash,
                    request.configuration.policySetHash,
                    request.newLoanNonce
                )
            );
    }

    function _validConfiguration(
        Phase9Types.LoanConfiguration memory configuration_,
        address expectedManager,
        bool requireManagerCode
    ) private view returns (bool) {
        return configuration_.factory == address(this)
            && configuration_.loanRegistry == address(_loanRegistry)
            && configuration_.settlementToken != address(0)
            && configuration_.settlementToken.codehash
                == keccak256(type(Phase9LocalSyntheticToken).runtimeCode)
            && configuration_.settlementAssetId
                == 0x61737365743a7068617365393a7039756e697400000000000000000000000000
            && configuration_.borrower != address(0) && expectedManager != address(0)
            && configuration_.positionManager == expectedManager
            && (!requireManagerCode || expectedManager.code.length != 0)
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

    function _validFactoryDependencies() private view returns (bool) {
        return block.chainid == 31337 && address(_loanRegistry) != address(0)
            && address(_loanRegistry).code.length != 0 && _loanAccountImplementation != address(0)
            && _loanAccountImplementation.code.length != 0
            && _positionManagerImplementation != address(0)
            && _positionManagerImplementation.code.length != 0
            && _quotePolicyRegistry != address(0) && _quotePolicyRegistry.code.length != 0
            && _refinancePolicyRegistry != address(0)
            && _refinancePolicyRegistry.code.length != 0
            && _amendmentPolicyRegistry != address(0)
            && _amendmentPolicyRegistry.code.length != 0
            && _protectionPolicyRegistry != address(0)
            && _protectionPolicyRegistry.code.length != 0
            && _recoveryPolicyRegistry != address(0) && _recoveryPolicyRegistry.code.length != 0;
    }

    function _requireFreshLoan(bytes32 loanId) private view {
        address mappedAccount = _loanAccounts[loanId];
        address mappedManager = _positionManagers[loanId];
        address registeredAccount = _registryAddress(ILoanRegistry.loanAccount.selector, loanId);
        if (mappedAccount == address(0) && mappedManager == address(0)) {
            if (registeredAccount != address(0)) revert Phase9LoanAlreadyExists(loanId);
            return;
        }
        if (
            mappedAccount != address(0) && mappedManager != address(0)
                && registeredAccount == mappedAccount
        ) {
            revert Phase9LoanAlreadyExists(loanId);
        }
        revert InvalidPhase9LoanConfiguration();
    }

    function _requireCanonicalSourceLoan(bytes32 loanId, address refinanceCoordinator)
        private
        view
    {
        address account = _loanAccounts[loanId];
        address manager = _positionManagers[loanId];
        if (account == address(0) || account.code.length == 0 || manager == address(0)
            || manager.code.length == 0 || !_validCloneRuntime(account, _loanAccountImplementation)
            || !_validCloneRuntime(manager, _positionManagerImplementation)) {
            revert InvalidPhase9LoanConfiguration();
        }

        Phase9Types.LoanConfiguration memory configuration_;
        try IPhase9LoanAccount(account).configuration() returns (
            Phase9Types.LoanConfiguration memory resolved
        ) {
            configuration_ = resolved;
        } catch {
            revert InvalidPhase9LoanConfiguration();
        }
        if (
            configuration_.factory != address(this) || configuration_.loanRegistry != address(_loanRegistry)
                || configuration_.loanId != loanId || configuration_.positionManager != manager
                || configuration_.refinanceCoordinator != refinanceCoordinator
        ) {
            revert InvalidPhase9LoanConfiguration();
        }
        _requireRegistryIdentity(configuration_, account, true);
    }

    function _requireRegistryIdentity(
        Phase9Types.LoanConfiguration memory configuration_,
        address loanAccount_,
        bool requireNonterminal
    ) private view {
        if (
            _registryAddress(ILoanRegistry.loanAccount.selector, configuration_.loanId)
                != loanAccount_
                || _registryAddress(ILoanRegistry.borrowerOf.selector, configuration_.loanId)
                    != configuration_.borrower
                || _registryWord(ILoanRegistry.agreementHashOf.selector, configuration_.loanId)
                    != configuration_.agreementHash
                || uint256(
                    _registryWord(ILoanRegistry.protocolVersionOf.selector, configuration_.loanId)
                ) != 9
                || (requireNonterminal
                    && _registryBool(ILoanRegistry.isTerminal.selector, configuration_.loanId))
        ) {
            revert InvalidPhase9LoanConfiguration();
        }
    }

    function _validActiveBootstrapDebt(Phase9Types.DebtState memory debt)
        private
        pure
        returns (bool)
    {
        return debt.lifecycle == Phase9Types.LoanLifecycle.ACTIVE
            && debt.servicingState == Phase9Types.ServicingState.CURRENT && debt.termsVersion != 0
            && debt.capitalizedInterest == 0 && debt.recoverableCosts == 0
            && debt.activeRefinanceId == bytes32(0) && debt.activeRestructureId == bytes32(0);
    }

    function _validBootstrapPositions(
        Phase9Types.Tranche[] memory tranches,
        Phase9Types.Position[] memory positions,
        Phase9Types.DebtState memory debt
    ) private pure returns (bool) {
        uint256 trancheCount = tranches.length;
        uint256 positionCount = positions.length;
        if (trancheCount == 0 || trancheCount > 8 || positionCount == 0 || positionCount > 32) {
            return false;
        }
        for (uint256 index = 0; index < trancheCount; ++index) {
            Phase9Types.Tranche memory tranche_ = tranches[index];
            if (
                tranche_.trancheId == bytes32(0) || tranche_.originalClaim == 0
                    || tranche_.outstandingClaim == 0
                    || tranche_.originalClaim != tranche_.outstandingClaim
                    || tranche_.configurationHash == bytes32(0)
                    || (index != 0
                        && uint256(tranche_.trancheId)
                            <= uint256(tranches[index - 1].trancheId))
            ) return false;
        }
        address beneficiary = positions[0].owner;
        uint256 totalPositionClaims;
        for (uint256 index = 0; index < positionCount; ++index) {
            Phase9Types.Position memory position_ = positions[index];
            if (
                position_.positionId == bytes32(0) || position_.owner == address(0)
                    || position_.owner != beneficiary
                    || position_.claim == 0 || position_.state != Phase9Types.PositionState.ACTIVE
                    || (index != 0
                        && uint256(position_.positionId)
                            <= uint256(positions[index - 1].positionId))
                    || !_containsTranche(tranches, position_.trancheId)
            ) return false;
            if (position_.claim > type(uint256).max - totalPositionClaims) return false;
            totalPositionClaims += position_.claim;
        }
        for (uint256 trancheIndex = 0; trancheIndex < trancheCount; ++trancheIndex) {
            uint256 allocated;
            for (uint256 positionIndex = 0; positionIndex < positionCount; ++positionIndex) {
                if (positions[positionIndex].trancheId == tranches[trancheIndex].trancheId) {
                    if (positions[positionIndex].claim > type(uint256).max - allocated) return false;
                    allocated += positions[positionIndex].claim;
                }
            }
            if (allocated != tranches[trancheIndex].outstandingClaim) return false;
        }
        if (debt.accruedInterest > type(uint256).max - debt.outstandingPrincipal) return false;
        return totalPositionClaims == debt.outstandingPrincipal + debt.accruedInterest;
    }

    function _containsTranche(Phase9Types.Tranche[] memory tranches, bytes32 trancheId)
        private
        pure
        returns (bool)
    {
        for (uint256 index = 0; index < tranches.length; ++index) {
            if (tranches[index].trancheId == trancheId) return true;
        }
        return false;
    }

    function _validBootstrapCollateral(
        Phase9Types.LoanConfiguration memory configuration_,
        Phase9Types.CustodyRecord[] memory custodyRecords,
        Phase9Types.Lien[] memory liens
    ) private view returns (bool) {
        uint256 count = custodyRecords.length;
        if (count == 0 || count > 16 || liens.length != count) return false;
        for (uint256 index = 0; index < count; ++index) {
            Phase9Types.CustodyRecord memory custody = custodyRecords[index];
            Phase9Types.Lien memory lien = liens[index];
            if (
                custody.collateralId == bytes32(0) || custody.assetId == bytes32(0)
                    || custody.token == address(0) || custody.token.code.length == 0
                    || custody.borrower != configuration_.borrower || custody.quantity == 0
                    || custody.status != Phase9Types.CustodyStatus.HELD
                    || custody.identityHash == bytes32(0)
                    || lien.collateralId != custody.collateralId
                    || lien.collateralManager != configuration_.collateralCustody
                    || lien.collateralManager.code.length == 0 || lien.vault == address(0)
                    || lien.assetId != custody.assetId || lien.quantity != custody.quantity
                    || lien.borrower != configuration_.borrower
                    || lien.seniorLoanId != configuration_.loanId || lien.lienVersion == 0
                    || lien.status != Phase9Types.LienStatus.ACTIVE
                    || lien.pendingRefinanceId != bytes32(0)
                    || lien.pendingTargetLoanId != bytes32(0)
                    || (index != 0
                        && uint256(custody.collateralId)
                            <= uint256(custodyRecords[index - 1].collateralId))
            ) return false;
        }
        return true;
    }

    function _deriveCreationId(
        Phase9Types.LoanCreationRequest memory request,
        uint8 creationMode,
        bytes32 bootstrapId,
        address predictedAccount,
        address predictedManager,
        uint64 loanNonce
    ) private view returns (bytes32) {
        CreationIdentity memory identity;
        identity.chainId = block.chainid;
        identity.factory = address(this);
        identity.loanId = request.configuration.loanId;
        identity.oldLoanId = request.oldLoanId;
        identity.borrower = request.configuration.borrower;
        identity.refinanceId = request.refinanceId;
        identity.newLoanNonce = request.newLoanNonce;
        identity.loanNonce = loanNonce;
        identity.agreementHash = request.configuration.agreementHash;
        identity.policySetHash = request.configuration.policySetHash;
        identity.creationMode = creationMode;
        identity.bootstrapId = bootstrapId;
        identity.predictedAccount = predictedAccount;
        identity.predictedManager = predictedManager;
        return keccak256(abi.encode("UNIFIED_PHASE9_LOAN_CREATION_V1", identity));
    }

    function _cloneDeterministic(address implementation, bytes32 salt)
        private
        returns (address instance)
    {
        assembly ("memory-safe") {
            mstore(
                0x00,
                or(
                    shr(232, shl(96, implementation)),
                    0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000
                )
            )
            mstore(0x20, or(shl(120, implementation), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create2(0, 0x09, 0x37, salt)
        }
        if (instance == address(0)) revert InvalidPhase9LoanConfiguration();
    }

    function _predictDeterministicAddress(address implementation, bytes32 salt)
        private
        view
        returns (address predicted)
    {
        address deployer = address(this);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x38), deployer)
            mstore(add(ptr, 0x24), 0x5af43d82803e903d91602b57fd5bf3ff)
            mstore(add(ptr, 0x14), implementation)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73)
            mstore(add(ptr, 0x58), salt)
            mstore(add(ptr, 0x78), keccak256(add(ptr, 0x0c), 0x37))
            predicted := and(keccak256(add(ptr, 0x43), 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    function _validCloneRuntime(address instance, address implementation)
        private
        view
        returns (bool)
    {
        return instance.code.length == 45
            && instance.codehash
                == keccak256(
                    abi.encodePacked(
                        hex"363d3d373d3d3d363d73",
                        bytes20(implementation),
                        hex"5af43d82803e903d91602b57fd5bf3"
                    )
                );
    }

    function _registryAddress(bytes4 selector, bytes32 loanId) private view returns (address) {
        return address(uint160(uint256(_registryWord(selector, loanId))));
    }

    function _registryBool(bytes4 selector, bytes32 loanId) private view returns (bool) {
        uint256 value = uint256(_registryWord(selector, loanId));
        if (value > 1) revert InvalidPhase9LoanConfiguration();
        return value == 1;
    }

    function _registryWord(bytes4 selector, bytes32 loanId) private view returns (bytes32 word) {
        (bool success, bytes memory result) =
            address(_loanRegistry).staticcall(abi.encodeWithSelector(selector, loanId));
        if (!success || result.length != 32) revert InvalidPhase9LoanConfiguration();
        assembly ("memory-safe") {
            word := mload(add(result, 0x20))
        }
    }

    /// @dev Retains the frozen error in compiler ABI metadata; this path is intentionally unreachable.
    function _phase9FrozenErrorCompatibilityMarker() private pure {
        revert Phase9ImplementationNotFrozen();
    }
}

interface IPhase9RefinancePolicySource {
    function resolveLoanCreation(bytes32 policySetHash, bytes32 loanId)
        external
        view
        returns (
            Phase9Types.LoanConfiguration memory configuration,
            uint8 creationMode,
            bytes32 bootstrapId,
            bool active
        );

    function resolveBootstrap(bytes32 bootstrapId)
        external
        view
        returns (
            bytes32 policySetHash,
            bytes32 loanId,
            Phase9Types.DebtState memory initialDebt,
            Phase9Types.Tranche[] memory initialTranches,
            Phase9Types.Position[] memory initialPositions,
            Phase9Types.CustodyRecord[] memory custodyRecords,
            Phase9Types.Lien[] memory liens,
            bool active
        );
}
