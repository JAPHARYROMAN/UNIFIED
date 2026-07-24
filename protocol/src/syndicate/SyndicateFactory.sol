// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEmergencyController } from "../interfaces/IEmergencyController.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { AssetRegistry } from "../kernel/AssetRegistry.sol";
import { PolicyRegistry } from "../kernel/PolicyRegistry.sol";
import { ProtocolTypes } from "../kernel/ProtocolTypes.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { PositionManager } from "./PositionManager.sol";
import { SyndicateTypes } from "./SyndicateTypes.sol";
import { SyndicateVault } from "./SyndicateVault.sol";

/// @notice Deterministically creates and registers bounded syndicated-loan aggregates.
contract SyndicateFactory is RoleControlled, ReentrancyGuard {
    error InvalidSyndicate();
    error NewLoanActivationPaused();
    error UnapprovedPolicy(uint256 index);
    error UnsupportedAsset(bytes32 assetId);

    uint32 public constant IMPLEMENTATION_VERSION = 5;
    bytes32 public constant CAPABILITY_NEW_LOANS = keccak256("CAPABILITY_NEW_LOANS");

    ILoanRegistry public immutable loanRegistry;
    AssetRegistry public immutable assetRegistry;
    PolicyRegistry public immutable policyRegistry;
    IEmergencyController public immutable emergencyController;
    address public immutable vaultImplementation;
    address public immutable positionManagerImplementation;

    event SyndicateCreated(
        bytes32 indexed loanId,
        bytes32 indexed roundId,
        address indexed vault,
        address positionManager,
        address borrower,
        bytes32 policySetHash
    );

    constructor(
        IRoleManager roleManager_,
        ILoanRegistry loanRegistry_,
        AssetRegistry assetRegistry_,
        PolicyRegistry policyRegistry_,
        IEmergencyController emergencyController_,
        address vaultImplementation_,
        address positionManagerImplementation_
    ) RoleControlled(roleManager_) {
        if (
            address(loanRegistry_).code.length == 0 || address(assetRegistry_).code.length == 0
                || address(policyRegistry_).code.length == 0
                || address(emergencyController_).code.length == 0
                || vaultImplementation_.code.length == 0
                || positionManagerImplementation_.code.length == 0
        ) {
            revert InvalidSyndicate();
        }
        loanRegistry = loanRegistry_;
        assetRegistry = assetRegistry_;
        policyRegistry = policyRegistry_;
        emergencyController = emergencyController_;
        vaultImplementation = vaultImplementation_;
        positionManagerImplementation = positionManagerImplementation_;
    }

    function createSyndicate(
        SyndicateTypes.FundingRoundTerms calldata terms,
        SyndicateTypes.TrancheConfiguration[] calldata tranches,
        ProtocolTypes.PolicyRef[] calldata policies
    ) external nonReentrant returns (address vault, address manager) {
        _requireCreationAvailable();
        bytes32 expectedLoanId = calculateLoanId(terms.roundId, msg.sender);
        if (
            terms.borrower != msg.sender || terms.loanId != expectedLoanId
                || terms.protocolVersion != IMPLEMENTATION_VERSION
                || loanRegistry.exists(expectedLoanId)
                || terms.policySetHash != _approvedPolicySetHash(policies)
        ) {
            revert InvalidSyndicate();
        }
        AssetRegistry.AssetRecord memory asset = assetRegistry.resolve(terms.settlementAssetId);
        if (!asset.active) revert UnsupportedAsset(terms.settlementAssetId);

        (vault, manager) = _deployAggregate(terms, tranches, asset.token);
        loanRegistry.registerLoan(
            expectedLoanId, vault, msg.sender, terms.agreementHash, IMPLEMENTATION_VERSION
        );
        _emitCreated(terms, vault, manager);
    }

    function calculateLoanId(bytes32 roundId, address borrower) public view returns (bytes32) {
        return keccak256(
            abi.encode("UNIFIED_SYNDICATE_LOAN", block.chainid, address(this), roundId, borrower)
        );
    }

    function predictVault(bytes32 loanId) external view returns (address) {
        return Clones.predictDeterministicAddress(vaultImplementation, loanId, address(this));
    }

    function predictPositionManager(bytes32 loanId) external view returns (address) {
        return Clones.predictDeterministicAddress(
            positionManagerImplementation, positionManagerSalt(loanId), address(this)
        );
    }

    function positionManagerSalt(bytes32 loanId) public pure returns (bytes32) {
        return keccak256(abi.encode("POSITION_MANAGER", loanId));
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
        if (policies.length == 0) revert InvalidSyndicate();
        for (uint256 index = 0; index < policies.length; ++index) {
            if (!policyRegistry.isApproved(policies[index])) {
                revert UnapprovedPolicy(index);
            }
        }
        return keccak256(abi.encode(policies));
    }

    function _deployAggregate(
        SyndicateTypes.FundingRoundTerms calldata terms,
        SyndicateTypes.TrancheConfiguration[] calldata tranches,
        address token
    ) private returns (address vault, address manager) {
        address predictedVault = Clones.predictDeterministicAddress(
            vaultImplementation, terms.loanId, address(this)
        );
        manager = Clones.cloneDeterministic(
            positionManagerImplementation, positionManagerSalt(terms.loanId)
        );
        PositionManager(manager)
            .initialize(roleManager, predictedVault, IERC20(token), terms.loanId);
        vault = Clones.cloneDeterministic(vaultImplementation, terms.loanId);
        if (vault != predictedVault) revert InvalidSyndicate();
        SyndicateVault(vault)
            .initialize(
                address(this),
                loanRegistry,
                PositionManager(manager),
                IERC20(token),
                terms,
                tranches
            );
    }

    function _emitCreated(
        SyndicateTypes.FundingRoundTerms calldata terms,
        address vault,
        address manager
    ) private {
        emit SyndicateCreated(
            terms.loanId, terms.roundId, vault, manager, terms.borrower, terms.policySetHash
        );
    }

    function _requireCreationAvailable() private view {
        (bool paused,,) = emergencyController.emergencyState(CAPABILITY_NEW_LOANS);
        if (paused) revert NewLoanActivationPaused();
    }
}
