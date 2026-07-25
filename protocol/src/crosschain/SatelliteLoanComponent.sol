// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import {
    ISatelliteLoanComponent,
    ISatelliteLoanProvisioner
} from "../interfaces/ISatelliteLoanComponent.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CrossChainMessageBuilder } from "./CrossChainMessageBuilder.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { RouteRegistry } from "./RouteRegistry.sol";

interface IWrappedRouteIdentity {
    function canonicalHomeChainId() external view returns (uint256);
    function homeBridgeHub() external view returns (address);
}

/// @notice Satellite message router. It owns no funds and can call only the two fixed vaults.
contract SatelliteLoanComponent is ISatelliteLoanComponent, RoleControlled {
    error InvalidSatelliteConfiguration();
    error InvalidSatelliteLoan();
    error UnauthorizedSatelliteCaller(address caller);

    ICrossChainCoordinator public immutable coordinator;
    RouteRegistry public immutable routeRegistry;

    address public homeLoanRouter;
    address public wrappedUFT;
    address public collateralToken;
    address public collateralVault;
    address public settlementVault;
    bytes32 public reportRoutePolicyHash;
    bytes32 public override backingRoutePolicyHash;
    bytes32 public repaymentRoutePolicyHash;
    bool public configured;

    mapping(bytes32 loanId => CrossChainTypes.SatelliteLoanProvisioning provisioning) private
        _provisionedLoans;
    mapping(
        bytes32 loanId
            => mapping(CrossChainTypes.CrossChainActionType actionType => bytes32 messageId)
    ) public reportMessage;

    event SatelliteInfrastructureConfigured(
        address indexed homeLoanRouter,
        address indexed collateralVault,
        address indexed settlementVault,
        bytes32 reportRoutePolicyHash,
        bytes32 backingRoutePolicyHash,
        bytes32 repaymentRoutePolicyHash
    );
    event SatelliteLoanProvisioned(
        bytes32 indexed loanId,
        address indexed homeLoanAccount,
        address indexed borrower,
        bytes32 fundingLockId,
        bytes32 policyHash
    );
    event SatelliteLoanReportSent(
        bytes32 indexed loanId,
        bytes32 indexed messageId,
        CrossChainTypes.CrossChainActionType indexed actionType,
        bytes32 operationId,
        uint256 amount
    );

    constructor(
        IRoleManager roleManager_,
        ICrossChainCoordinator coordinator_,
        RouteRegistry routeRegistry_
    ) RoleControlled(roleManager_) {
        if (address(coordinator_) == address(0) || address(routeRegistry_) == address(0)) {
            revert InvalidSatelliteConfiguration();
        }
        coordinator = coordinator_;
        routeRegistry = routeRegistry_;
    }

    function configureInfrastructure(
        address homeLoanRouter_,
        address wrappedUFT_,
        address collateralToken_,
        address collateralVault_,
        address settlementVault_,
        bytes32 reportRoutePolicyHash_,
        bytes32 backingRoutePolicyHash_,
        bytes32 repaymentRoutePolicyHash_
    ) external onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE) {
        if (
            configured || homeLoanRouter_ == address(0) || wrappedUFT_.code.length == 0
                || collateralToken_.code.length == 0 || collateralVault_.code.length == 0
                || settlementVault_.code.length == 0 || reportRoutePolicyHash_ == bytes32(0)
                || backingRoutePolicyHash_ == bytes32(0) || repaymentRoutePolicyHash_ == bytes32(0)
        ) {
            revert InvalidSatelliteConfiguration();
        }
        RouteRegistry.RouteVersion memory reportRoute = routeRegistry.route(reportRoutePolicyHash_);
        RouteRegistry.RouteVersion memory backingRoute =
            routeRegistry.route(backingRoutePolicyHash_);
        RouteRegistry.RouteVersion memory repaymentRoute =
            routeRegistry.route(repaymentRoutePolicyHash_);
        uint256 homeChainId = IWrappedRouteIdentity(wrappedUFT_).canonicalHomeChainId();
        address homeBridgeHub = IWrappedRouteIdentity(wrappedUFT_).homeBridgeHub();
        if (
            reportRoute.status != CrossChainTypes.RegistryStatus.ACTIVE
                || reportRoute.config.sourceChainId != coordinator.localChainId()
                || reportRoute.config.sourceCoordinator != address(coordinator)
                || reportRoute.config.sourceComponent != address(this)
                || reportRoute.config.destinationChainId != homeChainId
                || reportRoute.config.destinationCoordinator
                    != backingRoute.config.sourceCoordinator
                || reportRoute.config.destinationComponent != homeLoanRouter_
                || reportRoute.config.allowedActionsBitmap
                    != ((uint32(1) << 2) | (uint32(1) << 5) | (uint32(1) << 7) | (uint32(1) << 10)
                            | (uint32(1) << 14))
                || backingRoute.status != CrossChainTypes.RegistryStatus.ACTIVE
                || backingRoute.config.sourceChainId != homeChainId
                || backingRoute.config.sourceComponent != homeBridgeHub
                || backingRoute.config.destinationChainId != coordinator.localChainId()
                || backingRoute.config.destinationCoordinator != address(coordinator)
                || backingRoute.config.destinationComponent != wrappedUFT_
                || backingRoute.config.allowedActionsBitmap != uint32(1) << 1
                || repaymentRoute.status != CrossChainTypes.RegistryStatus.ACTIVE
                || repaymentRoute.config.sourceChainId != coordinator.localChainId()
                || repaymentRoute.config.sourceCoordinator != address(coordinator)
                || repaymentRoute.config.sourceComponent != wrappedUFT_
                || repaymentRoute.config.destinationChainId != homeChainId
                || repaymentRoute.config.destinationCoordinator
                    != backingRoute.config.sourceCoordinator
                || repaymentRoute.config.destinationComponent != homeLoanRouter_
                || repaymentRoute.config.allowedActionsBitmap != uint32(1) << 8
        ) {
            revert InvalidSatelliteConfiguration();
        }
        homeLoanRouter = homeLoanRouter_;
        wrappedUFT = wrappedUFT_;
        collateralToken = collateralToken_;
        collateralVault = collateralVault_;
        settlementVault = settlementVault_;
        reportRoutePolicyHash = reportRoutePolicyHash_;
        backingRoutePolicyHash = backingRoutePolicyHash_;
        repaymentRoutePolicyHash = repaymentRoutePolicyHash_;
        configured = true;
        emit SatelliteInfrastructureConfigured(
            homeLoanRouter_,
            collateralVault_,
            settlementVault_,
            reportRoutePolicyHash_,
            backingRoutePolicyHash_,
            repaymentRoutePolicyHash_
        );
    }

    /// @notice Synthetic-local provisioning performed before the first cross-domain loan action.
    function provisionLoan(CrossChainTypes.SatelliteLoanProvisioning calldata provisioning)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (!configured) revert InvalidSatelliteLoan();
        _validateProvisioning(provisioning);
        if (_provisionedLoans[provisioning.loanId].loanId != bytes32(0)) {
            revert InvalidSatelliteLoan();
        }
        _provisionedLoans[provisioning.loanId] = provisioning;
        ISatelliteLoanProvisioner(collateralVault).provisionLoan(provisioning);
        ISatelliteLoanProvisioner(settlementVault).provisionLoan(provisioning);
        emit SatelliteLoanProvisioned(
            provisioning.loanId,
            provisioning.homeLoanAccount,
            provisioning.borrower,
            provisioning.fundingLockId,
            provisioning.policyHash
        );
    }

    function provisionedLoan(bytes32 loanId)
        external
        view
        override
        returns (CrossChainTypes.SatelliteLoanProvisioning memory)
    {
        return _provisionedLoans[loanId];
    }

    function reportMintConfirmed(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        override
        returns (bytes32 messageId)
    {
        if (msg.sender != settlementVault) revert UnauthorizedSatelliteCaller(msg.sender);
        CrossChainTypes.SatelliteLoanProvisioning storage provisioning =
            _reportProvisioning(loanId, operationId, amount);
        return _sendReport(
            loanId,
            operationId,
            amount,
            CrossChainTypes.ACTION_SATELLITE_MINT_CONFIRMED,
            abi.encode(
                CrossChainTypes.WrappedUftMintedPayload({
                        loanId: loanId,
                        lockId: operationId,
                        homeLoanAccount: provisioning.homeLoanAccount,
                        borrower: provisioning.borrower,
                        lender: provisioning.lender,
                        wrappedToken: wrappedUFT,
                        amount: amount,
                        policyHash: provisioning.policyHash
                    })
            )
        );
    }

    function reportCollateralLocked(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        override
        returns (bytes32 messageId)
    {
        if (msg.sender != collateralVault) revert UnauthorizedSatelliteCaller(msg.sender);
        CrossChainTypes.SatelliteLoanProvisioning storage provisioning =
            _reportProvisioning(loanId, operationId, amount);
        return _sendReport(
            loanId,
            operationId,
            amount,
            CrossChainTypes.ACTION_SATELLITE_COLLATERAL_LOCKED,
            abi.encode(
                CrossChainTypes.SatelliteCollateralLockedPayload({
                        loanId: loanId,
                        collateralId: operationId,
                        homeLoanAccount: provisioning.homeLoanAccount,
                        borrower: provisioning.borrower,
                        lender: provisioning.lender,
                        collateralToken: collateralToken,
                        amount: amount,
                        policyHash: provisioning.policyHash
                    })
            )
        );
    }

    function reportDisbursementSettled(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        override
        returns (bytes32 messageId)
    {
        if (msg.sender != settlementVault) revert UnauthorizedSatelliteCaller(msg.sender);
        CrossChainTypes.SatelliteLoanProvisioning storage provisioning =
            _reportProvisioning(loanId, operationId, amount);
        return _sendReport(
            loanId,
            operationId,
            amount,
            CrossChainTypes.ACTION_SATELLITE_DISBURSEMENT_SETTLED,
            abi.encode(
                CrossChainTypes.SatelliteDisbursementSettledPayload({
                        loanId: loanId,
                        fundingLockId: operationId,
                        homeLoanAccount: provisioning.homeLoanAccount,
                        borrower: provisioning.borrower,
                        lender: provisioning.lender,
                        wrappedToken: wrappedUFT,
                        amount: amount,
                        policyHash: provisioning.policyHash
                    })
            )
        );
    }

    function reportCollateralReleased(bytes32 loanId, bytes32 operationId, uint256 amount)
        external
        override
        returns (bytes32 messageId)
    {
        if (msg.sender != collateralVault) revert UnauthorizedSatelliteCaller(msg.sender);
        CrossChainTypes.SatelliteLoanProvisioning storage provisioning =
            _reportProvisioning(loanId, operationId, amount);
        return _sendReport(
            loanId,
            operationId,
            amount,
            CrossChainTypes.ACTION_SATELLITE_COLLATERAL_RELEASED,
            abi.encode(
                CrossChainTypes.SatelliteCollateralReleasedPayload({
                        loanId: loanId,
                        collateralId: operationId,
                        homeLoanAccount: provisioning.homeLoanAccount,
                        borrower: provisioning.borrower,
                        lender: provisioning.lender,
                        collateralToken: collateralToken,
                        amount: amount,
                        policyHash: provisioning.policyHash
                    })
            )
        );
    }

    function reportFundingCancellation(
        CrossChainTypes.SatelliteFundingCancelledPayload calldata cancellation
    ) external override returns (bytes32 messageId) {
        if (msg.sender != settlementVault || cancellation.escrowBurnResultHash == bytes32(0)) {
            revert UnauthorizedSatelliteCaller(msg.sender);
        }
        CrossChainTypes.SatelliteLoanProvisioning storage provisioning = _reportProvisioning(
            cancellation.loanId, cancellation.cancellationId, cancellation.amount
        );
        if (
            cancellation.fundingLockId != provisioning.fundingLockId
                || cancellation.homeLoanAccount != provisioning.homeLoanAccount
                || cancellation.lender != provisioning.lender
                || cancellation.wrappedToken != wrappedUFT
                || cancellation.amount != provisioning.principalAmount
                || cancellation.policyHash != provisioning.policyHash
                || (cancellation.disbursementMessageId == bytes32(0))
                    != (cancellation.disbursementTombstoneHash == bytes32(0))
        ) {
            revert InvalidSatelliteLoan();
        }
        return _sendReport(
            cancellation.loanId,
            cancellation.cancellationId,
            cancellation.amount,
            CrossChainTypes.ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED,
            abi.encode(cancellation)
        );
    }

    function _sendReport(
        bytes32 loanId,
        bytes32 operationId,
        uint256 amount,
        CrossChainTypes.CrossChainActionType actionType,
        bytes memory payload
    ) private returns (bytes32 messageId) {
        CrossChainTypes.MessageEnvelope memory envelope =
            CrossChainMessageBuilder.build(
                coordinator,
                routeRegistry,
                CrossChainMessageBuilder.BuildRequest({
                    routePolicyHash: reportRoutePolicyHash,
                    sourceComponent: address(this),
                    aggregateId: loanId,
                    actionType: actionType,
                    payloadHash: keccak256(payload),
                    expiresAt: uint64(block.timestamp + 2 days),
                    correlationId: loanId,
                    causationMessageId: bytes32(0),
                    supersededMessageId: bytes32(0)
                })
            );
        messageId = coordinator.sendMessage(envelope, payload);
        reportMessage[loanId][actionType] = messageId;
        emit SatelliteLoanReportSent(loanId, messageId, actionType, operationId, amount);
    }

    function _reportProvisioning(bytes32 loanId, bytes32 operationId, uint256 amount)
        private
        view
        returns (CrossChainTypes.SatelliteLoanProvisioning storage provisioning)
    {
        provisioning = _provisionedLoans[loanId];
        if (
            !configured || provisioning.loanId == bytes32(0) || operationId == bytes32(0)
                || amount == 0
        ) {
            revert InvalidSatelliteLoan();
        }
    }

    function _validateProvisioning(CrossChainTypes.SatelliteLoanProvisioning memory provisioning)
        private
        view
    {
        if (
            provisioning.loanId == bytes32(0) || provisioning.fundingLockId == bytes32(0)
                || provisioning.homeLoanAccount == address(0)
                || provisioning.homeLoanRouter != homeLoanRouter
                || provisioning.borrower == address(0) || provisioning.lender == address(0)
                || provisioning.borrower == provisioning.lender
                || provisioning.wrappedToken != wrappedUFT
                || provisioning.collateralToken != collateralToken
                || provisioning.collateralId == bytes32(0) || provisioning.principalAmount == 0
                || provisioning.collateralAmount == 0
                || provisioning.repaymentRoutePolicyHash != repaymentRoutePolicyHash
                || provisioning.policyHash == bytes32(0)
        ) {
            revert InvalidSatelliteLoan();
        }
    }
}
