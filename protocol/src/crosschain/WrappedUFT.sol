// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import {
    ICrossChainCompensable,
    ICrossChainReceiver,
    IWrappedMintReceiver
} from "../interfaces/ICrossChainReceiver.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CrossChainMessageBuilder } from "./CrossChainMessageBuilder.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { RouteRegistry } from "./RouteRegistry.sol";

interface ISatelliteRepaymentAuthorizer {
    struct RepaymentAuthorization {
        address lender;
        address homeLoanRouter;
        bytes32 policyHash;
        bytes32 backingRoutePolicyHash;
        bytes32 repaymentRoutePolicyHash;
    }

    function authorizeRepaymentBurn(
        bytes32 loanId,
        bytes32 paymentId,
        address borrower,
        uint256 amount
    ) external returns (RepaymentAuthorization memory authorization);
}

interface ISatelliteRepaymentCompensator {
    function reverseRepaymentBurn(
        bytes32 loanId,
        bytes32 paymentId,
        address borrower,
        uint256 amount
    ) external;
}

interface IWrappedCoordinatorEnvelope {
    function messageEnvelope(bytes32 messageId)
        external
        view
        returns (CrossChainTypes.MessageEnvelope memory);
}

/// @notice Fully backed satellite representation. It has one coordinator-only issuance surface.
contract WrappedUFT is
    ERC20,
    ICrossChainReceiver,
    ICrossChainCompensable,
    RoleControlled,
    ReentrancyGuard
{
    error InvalidWrappedConfiguration();
    error InvalidWrappedOperation();
    error DuplicateWrappedOperation(bytes32 operationId);
    error UnauthorizedWrappedCaller(address caller);

    struct BurnDispatch {
        bytes32 burnId;
        bytes32 loanId;
        bytes32 paymentId;
        bytes32 backingRoutePolicyHash;
        uint256 amount;
        bytes32 routePolicyHash;
        CrossChainTypes.CrossChainActionType actionType;
        address account;
        uint64 expiresAt;
        bytes32 aggregateId;
    }

    enum BurnRecoveryState {
        NONE,
        BURNED,
        COMPENSATED
    }

    struct BurnRecord {
        bytes32 burnId;
        bytes32 messageId;
        bytes32 loanId;
        bytes32 paymentId;
        bytes32 backingRoutePolicyHash;
        bytes32 exitRoutePolicyHash;
        address account;
        uint256 amount;
        CrossChainTypes.CrossChainActionType actionType;
        BurnRecoveryState state;
        bytes32 compensationResult;
    }

    uint256 public immutable canonicalHomeChainId;
    address public immutable canonicalUFT;
    address public immutable homeBridgeHub;
    ICrossChainCoordinator public immutable coordinator;
    RouteRegistry public immutable routeRegistry;
    address public immutable recoveryController;
    address public loanSettlementVault;
    bytes32 public canonicalBackingRoutePolicyHash;

    mapping(bytes32 lockId => bytes32 messageId) public mintMessage;
    mapping(bytes32 burnId => bytes32 messageId) public burnMessage;
    mapping(bytes32 burnId => BurnRecord record) private _burnRecords;
    mapping(bytes32 messageId => bytes32 burnId) public messageBurn;
    mapping(bytes32 loanId => bytes32 cancellationId) public loanCancellationBurn;
    mapping(bytes32 cancellationId => bytes32 resultHash) public cancellationBurnResult;

    event WrappedUFTMinted(
        bytes32 indexed lockId,
        bytes32 indexed messageId,
        bytes32 indexed loanId,
        address recipient,
        uint256 amount
    );
    event WrappedUFTBurned(
        bytes32 indexed burnId,
        bytes32 indexed messageId,
        bytes32 indexed loanId,
        address account,
        uint256 amount,
        bool permanent
    );
    event LoanSettlementVaultConfigured(address indexed vault);
    event CanonicalBackingRouteConfigured(bytes32 indexed routePolicyHash);
    event WrappedBurnCompensated(
        bytes32 indexed burnId, bytes32 indexed messageId, address indexed account, uint256 amount
    );
    event WrappedLoanEscrowBurned(
        bytes32 indexed cancellationId,
        bytes32 indexed loanId,
        address indexed settlementVault,
        uint256 amount,
        bytes32 resultHash
    );

    constructor(
        IRoleManager roleManager_,
        uint256 canonicalHomeChainId_,
        address canonicalUFT_,
        address homeBridgeHub_,
        ICrossChainCoordinator coordinator_,
        RouteRegistry routeRegistry_,
        address recoveryController_
    ) ERC20("Wrapped Unified Coin", "wUFT") RoleControlled(roleManager_) {
        if (
            canonicalHomeChainId_ == 0 || canonicalUFT_ == address(0)
                || homeBridgeHub_ == address(0) || address(coordinator_) == address(0)
                || address(routeRegistry_) == address(0) || recoveryController_.code.length == 0
        ) {
            revert InvalidWrappedConfiguration();
        }
        canonicalHomeChainId = canonicalHomeChainId_;
        canonicalUFT = canonicalUFT_;
        homeBridgeHub = homeBridgeHub_;
        coordinator = coordinator_;
        routeRegistry = routeRegistry_;
        recoveryController = recoveryController_;
    }

    function configureLoanSettlementVault(address vault)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (vault.code.length == 0 || loanSettlementVault != address(0)) {
            revert InvalidWrappedConfiguration();
        }
        loanSettlementVault = vault;
        emit LoanSettlementVaultConfigured(vault);
    }

    function configureCanonicalBackingRoute(bytes32 routePolicyHash)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (routePolicyHash == bytes32(0) || canonicalBackingRoutePolicyHash != bytes32(0)) revert InvalidWrappedConfiguration();
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(routePolicyHash);
        if (
            route_.status != CrossChainTypes.RegistryStatus.ACTIVE
                || route_.config.sourceChainId != canonicalHomeChainId
                || route_.config.sourceComponent != homeBridgeHub
                || route_.config.destinationChainId != coordinator.localChainId()
                || route_.config.destinationCoordinator != address(coordinator)
                || route_.config.destinationComponent != address(this)
                || !routeRegistry.isActionAllowed(
                    routePolicyHash, CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED
                )
        ) revert InvalidWrappedConfiguration();
        canonicalBackingRoutePolicyHash = routePolicyHash;
        emit CanonicalBackingRouteConfigured(routePolicyHash);
    }

    function handleCrossChainMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external override nonReentrant returns (bytes32 resultHash) {
        if (msg.sender != address(coordinator)) {
            revert UnauthorizedWrappedCaller(msg.sender);
        }
        if (actionType != CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED) {
            revert InvalidWrappedOperation();
        }
        CrossChainTypes.CanonicalUftLockPayload memory lock =
            abi.decode(payload, (CrossChainTypes.CanonicalUftLockPayload));
        CrossChainTypes.MessageEnvelope memory envelope =
            IWrappedCoordinatorEnvelope(address(coordinator)).messageEnvelope(messageId);
        if (
            canonicalBackingRoutePolicyHash == bytes32(0)
                || envelope.routePolicyHash != canonicalBackingRoutePolicyHash
                || lock.lockId == bytes32(0) || lock.canonicalToken != canonicalUFT
                || lock.homeBridgeHub != homeBridgeHub || lock.wrappedToken != address(this)
                || lock.destinationRecipient == address(0) || lock.amount == 0
                || mintMessage[lock.lockId] != bytes32(0)
        ) {
            revert InvalidWrappedOperation();
        }
        mintMessage[lock.lockId] = messageId;
        _mint(lock.destinationRecipient, lock.amount);
        if (lock.destinationRecipient.code.length != 0) {
            IWrappedMintReceiver(lock.destinationRecipient)
                .onWrappedMint(lock.lockId, lock.loanId, lock.amount);
        }
        resultHash = keccak256(
            abi.encode(
                "UNIFIED_WRAPPED_MINT_RESULT_V1",
                messageId,
                lock.lockId,
                lock.loanId,
                lock.destinationRecipient,
                lock.amount
            )
        );
        emit WrappedUFTMinted(
            lock.lockId, messageId, lock.loanId, lock.destinationRecipient, lock.amount
        );
    }

    function burnForBridge(
        bytes32 burnId,
        bytes32 backingRoutePolicyHash,
        bytes32 burnRoutePolicyHash,
        address recipient,
        uint256 amount,
        bool permanent,
        uint64 expiresAt
    ) external nonReentrant returns (bytes32 messageId) {
        if (
            burnId == bytes32(0) || backingRoutePolicyHash != canonicalBackingRoutePolicyHash
                || recipient == address(0) || amount == 0 || expiresAt <= block.timestamp
                || burnMessage[burnId] != bytes32(0)
        ) {
            revert InvalidWrappedOperation();
        }
        CrossChainTypes.CrossChainActionType actionType = permanent
            ? CrossChainTypes.ACTION_SATELLITE_UFT_PERMANENT_BURNED
            : CrossChainTypes.ACTION_SATELLITE_UFT_BURNED;
        _validateBurnRoute(burnRoutePolicyHash, actionType);
        bytes memory payload;
        if (permanent) {
            payload = abi.encode(
                CrossChainTypes.SatelliteUftPermanentBurnedPayload({
                    burnId: burnId,
                    backingRoutePolicyHash: backingRoutePolicyHash,
                    canonicalToken: canonicalUFT,
                    homeBridgeHub: homeBridgeHub,
                    wrappedToken: address(this),
                    amount: amount
                })
            );
        } else {
            payload = abi.encode(
                CrossChainTypes.WrappedUftBurnedPayload({
                    burnId: burnId,
                    backingRoutePolicyHash: backingRoutePolicyHash,
                    canonicalToken: canonicalUFT,
                    homeBridgeHub: homeBridgeHub,
                    wrappedToken: address(this),
                    recipient: recipient,
                    amount: amount
                })
            );
        }
        messageId = _burnAndSend(
            BurnDispatch({
                burnId: burnId,
                loanId: bytes32(0),
                paymentId: bytes32(0),
                backingRoutePolicyHash: backingRoutePolicyHash,
                amount: amount,
                routePolicyHash: burnRoutePolicyHash,
                actionType: actionType,
                account: msg.sender,
                expiresAt: expiresAt,
                aggregateId: burnId
            }),
            payload
        );
    }

    function burnForLoanRepayment(
        bytes32 burnId,
        bytes32 loanId,
        bytes32 paymentId,
        bytes32 repaymentRoutePolicyHash,
        uint256 amount,
        uint64 expiresAt
    ) external nonReentrant returns (bytes32 messageId) {
        if (
            loanSettlementVault == address(0) || burnId == bytes32(0) || loanId == bytes32(0)
                || paymentId == bytes32(0) || amount == 0 || expiresAt <= block.timestamp
                || burnMessage[burnId] != bytes32(0)
        ) {
            revert InvalidWrappedOperation();
        }
        ISatelliteRepaymentAuthorizer.RepaymentAuthorization memory authorization =
            ISatelliteRepaymentAuthorizer(loanSettlementVault)
                .authorizeRepaymentBurn(loanId, paymentId, msg.sender, amount);
        if (
            repaymentRoutePolicyHash != authorization.repaymentRoutePolicyHash
                || authorization.backingRoutePolicyHash != canonicalBackingRoutePolicyHash
        ) {
            revert InvalidWrappedOperation();
        }
        CrossChainTypes.SatelliteRepaymentBurnedPayload memory burn =
            CrossChainTypes.SatelliteRepaymentBurnedPayload({
                burnId: burnId,
                loanId: loanId,
                paymentId: paymentId,
                backingRoutePolicyHash: authorization.backingRoutePolicyHash,
                canonicalToken: canonicalUFT,
                homeBridgeHub: homeBridgeHub,
                wrappedToken: address(this),
                lender: authorization.lender,
                amount: amount
            });
        messageId = _burnAndSend(
            BurnDispatch({
                burnId: burnId,
                loanId: loanId,
                paymentId: paymentId,
                backingRoutePolicyHash: authorization.backingRoutePolicyHash,
                amount: amount,
                routePolicyHash: repaymentRoutePolicyHash,
                actionType: CrossChainTypes.ACTION_SATELLITE_REPAYMENT_BURNED,
                account: msg.sender,
                expiresAt: expiresAt,
                aggregateId: loanId
            }),
            abi.encode(burn)
        );
        if (
            routeRegistry.route(repaymentRoutePolicyHash).config.destinationComponent
                != authorization.homeLoanRouter
        ) {
            revert InvalidWrappedOperation();
        }
    }

    function burnEscrowedLoanCancellation(bytes32 cancellationId, bytes32 loanId, uint256 amount)
        external
        nonReentrant
        returns (bytes32 resultHash)
    {
        if (
            msg.sender != loanSettlementVault || cancellationId == bytes32(0)
                || loanId == bytes32(0) || amount == 0 || loanCancellationBurn[loanId] != bytes32(0)
                || cancellationBurnResult[cancellationId] != bytes32(0)
                || balanceOf(msg.sender) < amount
        ) {
            revert InvalidWrappedOperation();
        }
        _burn(msg.sender, amount);
        resultHash = keccak256(
            abi.encode(
                "UNIFIED_WRAPPED_LOAN_ESCROW_CANCELLATION_V1",
                cancellationId,
                loanId,
                msg.sender,
                amount,
                totalSupply()
            )
        );
        loanCancellationBurn[loanId] = cancellationId;
        cancellationBurnResult[cancellationId] = resultHash;
        emit WrappedLoanEscrowBurned(cancellationId, loanId, msg.sender, amount, resultHash);
    }

    function _burnAndSend(BurnDispatch memory dispatch, bytes memory payload)
        private
        returns (bytes32 messageId)
    {
        _burn(dispatch.account, dispatch.amount);
        CrossChainTypes.MessageEnvelope memory envelope = CrossChainMessageBuilder.build(
            coordinator,
            routeRegistry,
            CrossChainMessageBuilder.BuildRequest({
                routePolicyHash: dispatch.routePolicyHash,
                sourceComponent: address(this),
                aggregateId: dispatch.aggregateId,
                actionType: dispatch.actionType,
                payloadHash: keccak256(payload),
                expiresAt: dispatch.expiresAt,
                correlationId: dispatch.loanId == bytes32(0) ? dispatch.burnId : dispatch.loanId,
                causationMessageId: bytes32(0),
                supersededMessageId: bytes32(0)
            })
        );
        messageId = coordinator.sendMessage(envelope, payload);
        burnMessage[dispatch.burnId] = messageId;
        messageBurn[messageId] = dispatch.burnId;
        _burnRecords[dispatch.burnId] = BurnRecord({
            burnId: dispatch.burnId,
            messageId: messageId,
            loanId: dispatch.loanId,
            paymentId: dispatch.paymentId,
            backingRoutePolicyHash: dispatch.backingRoutePolicyHash,
            exitRoutePolicyHash: dispatch.routePolicyHash,
            account: dispatch.account,
            amount: dispatch.amount,
            actionType: dispatch.actionType,
            state: BurnRecoveryState.BURNED,
            compensationResult: bytes32(0)
        });
        emit WrappedUFTBurned(
            dispatch.burnId,
            messageId,
            dispatch.loanId,
            dispatch.account,
            dispatch.amount,
            dispatch.actionType == CrossChainTypes.ACTION_SATELLITE_UFT_PERMANENT_BURNED
        );
    }

    function compensateMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata compensationPayload
    ) external override nonReentrant returns (bytes32 resultHash) {
        if (msg.sender != recoveryController) revert UnauthorizedWrappedCaller(msg.sender);
        (bytes32 burnId, address account) = abi.decode(compensationPayload, (bytes32, address));
        BurnRecord storage record = _burnRecords[burnId];
        if (
            record.burnId == bytes32(0) || record.messageId != messageId
                || record.actionType != actionType || record.account != account
                || messageBurn[messageId] != burnId
        ) revert InvalidWrappedOperation();
        if (record.state == BurnRecoveryState.COMPENSATED) return record.compensationResult;
        if (record.state != BurnRecoveryState.BURNED) revert InvalidWrappedOperation();
        if (record.paymentId != bytes32(0)) {
            ISatelliteRepaymentCompensator(loanSettlementVault)
                .reverseRepaymentBurn(
                    record.loanId, record.paymentId, record.account, record.amount
                );
        }
        record.state = BurnRecoveryState.COMPENSATED;
        _mint(record.account, record.amount);
        resultHash = keccak256(
            abi.encode(
                "UNIFIED_WRAPPED_BURN_COMPENSATION_V1",
                record.burnId,
                record.messageId,
                record.account,
                record.amount,
                record.actionType
            )
        );
        record.compensationResult = resultHash;
        emit WrappedBurnCompensated(record.burnId, record.messageId, record.account, record.amount);
    }

    function burnRecord(bytes32 burnId) external view returns (BurnRecord memory) {
        return _burnRecords[burnId];
    }

    function _validateBurnRoute(
        bytes32 burnRoutePolicyHash,
        CrossChainTypes.CrossChainActionType actionType
    ) private view {
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(burnRoutePolicyHash);
        RouteRegistry.RouteVersion memory backingRoute =
            routeRegistry.route(canonicalBackingRoutePolicyHash);
        if (
            route_.config.sourceChainId != coordinator.localChainId()
                || route_.config.sourceCoordinator != address(coordinator)
                || route_.config.sourceComponent != address(this)
                || route_.config.destinationChainId != canonicalHomeChainId
                || route_.config.destinationCoordinator != backingRoute.config.sourceCoordinator
                || route_.config.destinationComponent != homeBridgeHub
                || !routeRegistry.isActionAllowed(burnRoutePolicyHash, actionType)
        ) revert InvalidWrappedOperation();
    }
}
