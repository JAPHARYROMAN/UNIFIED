// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ICrossChainCompensable, ICrossChainReceiver } from "../interfaces/ICrossChainReceiver.sol";
import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { IUFTBridgeHub } from "../interfaces/IUFTBridgeHub.sol";
import { IUnifiedToken } from "../interfaces/IUnifiedToken.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { BridgeExposurePolicy } from "./BridgeExposurePolicy.sol";
import { CrossChainMessageBuilder } from "./CrossChainMessageBuilder.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { RouteRegistry } from "./RouteRegistry.sol";

interface IFundingCompensationReceiver {
    function onFundingCompensated(bytes32 lockId) external;
}

/// @notice Canonical UFT restricted escrow. Canonical UFT is never minted by this contract.
contract UFTBridgeHub is
    IUFTBridgeHub,
    ICrossChainReceiver,
    ICrossChainCompensable,
    RoleControlled,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    error InvalidBridgeConfiguration();
    error InvalidBridgeOperation();
    error DuplicateBridgeOperation(bytes32 operationId);
    error BridgeBalanceMismatch();
    error ExposureExceeded();
    error UnauthorizedBridgeCaller(address caller);

    struct LockRecord {
        bytes32 lockId;
        bytes32 messageId;
        bytes32 loanId;
        bytes32 routePolicyHash;
        address locker;
        address recipient;
        address loanAccount;
        uint256 amount;
        CrossChainTypes.BridgeOperationState state;
    }

    struct LockRequest {
        bytes32 lockId;
        bytes32 loanId;
        address loanAccount;
        address locker;
        address recipient;
        uint256 amount;
        bytes32 routePolicyHash;
        uint64 expiresAt;
    }

    struct BurnDisposition {
        bytes32 burnId;
        bytes32 loanId;
        bytes32 backingRoutePolicyHash;
        address recipient;
        uint256 amount;
        CrossChainTypes.CrossChainActionType actionType;
        bytes32 resultHash;
    }

    IUnifiedToken public immutable canonicalUFT;
    ICrossChainCoordinator public immutable coordinator;
    RouteRegistry public immutable routeRegistry;
    BridgeExposurePolicy public immutable exposurePolicy;
    address public immutable recoveryController;

    mapping(bytes32 lockId => LockRecord lock) private _locks;
    mapping(bytes32 messageId => bytes32 lockId) public messageLock;
    mapping(bytes32 burnId => bool consumed) public consumedBurn;
    mapping(bytes32 burnId => BurnDisposition disposition) public burnDisposition;
    mapping(bytes32 routePolicyHash => uint256 amount) public routeBacking;
    mapping(uint256 chainId => uint256 amount) public override backingForChain;
    mapping(bytes32 adapterId => uint256 amount) public adapterBacking;
    mapping(bytes32 loanId => uint256 amount) public override loanBacking;
    mapping(bytes32 loanId => address account) public loanAccount;
    mapping(bytes32 loanId => bytes32 lockId) public loanLock;
    mapping(bytes32 cancellationId => bytes32 loanId) public cancellationRefund;
    uint256 public override totalBridgeBacking;
    uint256 public lastReportedSurplus;

    event UFTLocked(
        bytes32 indexed lockId,
        bytes32 indexed messageId,
        bytes32 indexed routePolicyHash,
        address locker,
        address recipient,
        uint256 amount,
        bytes32 loanId
    );
    event CanonicalUFTReleased(
        bytes32 indexed burnId, bytes32 indexed loanId, address indexed recipient, uint256 amount
    );
    event CanonicalUFTBurned(bytes32 indexed burnId, uint256 amount);
    event LoanBackingReclassified(bytes32 indexed loanId, uint256 amount, uint256 remaining);
    event BridgeLockCompensated(
        bytes32 indexed lockId, bytes32 indexed messageId, address indexed locker, uint256 amount
    );
    event LoanCancellationRefunded(
        bytes32 indexed cancellationId,
        bytes32 indexed loanId,
        address indexed lender,
        uint256 amount
    );
    event BridgeSurplusReconciled(uint256 priorSurplus, uint256 currentSurplus);

    constructor(
        IRoleManager roleManager_,
        IUnifiedToken canonicalUFT_,
        ICrossChainCoordinator coordinator_,
        RouteRegistry routeRegistry_,
        BridgeExposurePolicy exposurePolicy_,
        address recoveryController_
    ) RoleControlled(roleManager_) {
        if (
            address(canonicalUFT_).code.length == 0 || address(coordinator_) == address(0)
                || address(routeRegistry_) == address(0) || address(exposurePolicy_) == address(0)
                || recoveryController_.code.length == 0
        ) {
            revert InvalidBridgeConfiguration();
        }
        canonicalUFT = canonicalUFT_;
        coordinator = coordinator_;
        routeRegistry = routeRegistry_;
        exposurePolicy = exposurePolicy_;
        recoveryController = recoveryController_;
    }

    function lockForBridge(
        bytes32 lockId,
        bytes32 routePolicyHash,
        address recipient,
        uint256 amount,
        uint64 expiresAt
    ) external nonReentrant returns (bytes32 messageId) {
        return _lock(
            LockRequest({
                lockId: lockId,
                loanId: bytes32(0),
                loanAccount: address(0),
                locker: msg.sender,
                recipient: recipient,
                amount: amount,
                routePolicyHash: routePolicyHash,
                expiresAt: expiresAt
            })
        );
    }

    function lockForLoan(
        bytes32 lockId,
        bytes32 loanId,
        address loanAccount_,
        address lender,
        address destinationRecipient,
        uint256 amount,
        bytes32 routePolicyHash,
        uint64 expiresAt
    )
        external
        override
        onlyRole(ProtocolRoles.LOAN_FACTORY_ROLE)
        nonReentrant
        returns (bytes32 messageId)
    {
        if (
            loanId == bytes32(0) || loanAccount_.code.length == 0
                || loanAccount[loanId] != address(0)
        ) {
            revert InvalidBridgeOperation();
        }
        loanAccount[loanId] = loanAccount_;
        loanLock[loanId] = lockId;
        messageId = _lock(
            LockRequest({
                lockId: lockId,
                loanId: loanId,
                loanAccount: loanAccount_,
                locker: lender,
                recipient: destinationRecipient,
                amount: amount,
                routePolicyHash: routePolicyHash,
                expiresAt: expiresAt
            })
        );
        loanBacking[loanId] = amount;
    }

    function handleCrossChainMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external override nonReentrant returns (bytes32 resultHash) {
        if (msg.sender != address(coordinator)) {
            revert UnauthorizedBridgeCaller(msg.sender);
        }
        if (
            actionType != CrossChainTypes.ACTION_SATELLITE_UFT_BURNED
                && actionType != CrossChainTypes.ACTION_SATELLITE_UFT_PERMANENT_BURNED
        ) {
            revert InvalidBridgeOperation();
        }
        CrossChainTypes.MessageEnvelope memory envelope =
            CoordinatorEnvelope(address(coordinator)).messageEnvelope(messageId);
        bytes32 burnId;
        bytes32 backingRoutePolicyHash;
        address recipient;
        uint256 amount;
        if (actionType == CrossChainTypes.ACTION_SATELLITE_UFT_PERMANENT_BURNED) {
            CrossChainTypes.SatelliteUftPermanentBurnedPayload memory burn =
                abi.decode(payload, (CrossChainTypes.SatelliteUftPermanentBurnedPayload));
            if (
                burn.burnId == bytes32(0) || burn.canonicalToken != address(canonicalUFT)
                    || burn.homeBridgeHub != address(this)
                    || burn.wrappedToken != envelope.sourceComponent || burn.amount == 0
                    || consumedBurn[burn.burnId]
            ) {
                revert InvalidBridgeOperation();
            }
            burnId = burn.burnId;
            backingRoutePolicyHash = burn.backingRoutePolicyHash;
            amount = burn.amount;
            _validateBackingRoute(backingRoutePolicyHash, envelope);
            consumedBurn[burnId] = true;
            _decreaseExposure(burn.backingRoutePolicyHash, amount);
            canonicalUFT.burn(amount);
            emit CanonicalUFTBurned(burnId, amount);
        } else {
            CrossChainTypes.WrappedUftBurnedPayload memory burn =
                abi.decode(payload, (CrossChainTypes.WrappedUftBurnedPayload));
            if (
                burn.burnId == bytes32(0) || burn.canonicalToken != address(canonicalUFT)
                    || burn.homeBridgeHub != address(this)
                    || burn.wrappedToken != envelope.sourceComponent || burn.recipient == address(0)
                    || burn.amount == 0 || consumedBurn[burn.burnId]
            ) {
                revert InvalidBridgeOperation();
            }
            burnId = burn.burnId;
            backingRoutePolicyHash = burn.backingRoutePolicyHash;
            recipient = burn.recipient;
            amount = burn.amount;
            _validateBackingRoute(backingRoutePolicyHash, envelope);
            consumedBurn[burnId] = true;
            _decreaseExposure(burn.backingRoutePolicyHash, amount);
            _transferExact(burn.recipient, amount);
            emit CanonicalUFTReleased(burnId, bytes32(0), burn.recipient, amount);
        }
        _requireBackingBalance();
        resultHash = keccak256(
            abi.encode("UNIFIED_UFT_BURN_RESULT_V1", messageId, burnId, amount, actionType)
        );
        burnDisposition[burnId] = BurnDisposition({
            burnId: burnId,
            loanId: bytes32(0),
            backingRoutePolicyHash: backingRoutePolicyHash,
            recipient: recipient,
            amount: amount,
            actionType: actionType,
            resultHash: resultHash
        });
    }

    function releaseLoanBacking(bytes32 loanId, bytes32 burnId, address lender, uint256 amount)
        external
        override
        nonReentrant
    {
        if (
            loanId == bytes32(0) || burnId == bytes32(0) || lender == address(0) || amount == 0
                || msg.sender != loanAccount[loanId] || consumedBurn[burnId]
                || amount > loanBacking[loanId]
        ) {
            revert InvalidBridgeOperation();
        }
        consumedBurn[burnId] = true;
        loanBacking[loanId] -= amount;
        LockRecord storage lock = _locks[loanLock[loanId]];
        _decreaseExposure(lock.routePolicyHash, amount);
        _transferExact(lender, amount);
        bytes32 resultHash = keccak256(
            abi.encode(
                "UNIFIED_LOAN_BACKING_RELEASE_RESULT_V1",
                loanId,
                burnId,
                lender,
                amount,
                lock.routePolicyHash
            )
        );
        burnDisposition[burnId] = BurnDisposition({
            burnId: burnId,
            loanId: loanId,
            backingRoutePolicyHash: lock.routePolicyHash,
            recipient: lender,
            amount: amount,
            actionType: CrossChainTypes.ACTION_SATELLITE_REPAYMENT_BURNED,
            resultHash: resultHash
        });
        emit CanonicalUFTReleased(burnId, loanId, lender, amount);
        _requireBackingBalance();
    }

    function refundCancelledLoan(
        bytes32 loanId,
        bytes32 cancellationId,
        address lender,
        uint256 amount
    ) external override nonReentrant {
        LockRecord storage lock = _locks[loanLock[loanId]];
        if (
            loanId == bytes32(0) || cancellationId == bytes32(0) || lender == address(0)
                || amount == 0 || msg.sender != loanAccount[loanId] || lock.loanId != loanId
                || lock.loanAccount != msg.sender || lock.locker != lender || lock.amount != amount
                || lock.state != CrossChainTypes.BridgeOperationState.LOCKED
                || loanBacking[loanId] != amount || cancellationRefund[cancellationId] != bytes32(0)
        ) {
            revert InvalidBridgeOperation();
        }
        lock.state = CrossChainTypes.BridgeOperationState.COMPENSATED;
        loanBacking[loanId] = 0;
        cancellationRefund[cancellationId] = loanId;
        _decreaseExposure(lock.routePolicyHash, amount);
        _transferExact(lender, amount);
        _requireBackingBalance();
        emit LoanCancellationRefunded(cancellationId, loanId, lender, amount);
    }

    /// @notice Removes the loan-specific attribution after canonical direct repayment while
    /// preserving the fungible backing for still-circulating wrapped UFT.
    function reclassifyLoanBacking(bytes32 loanId, uint256 amount) external override nonReentrant {
        if (
            loanId == bytes32(0) || amount == 0 || msg.sender != loanAccount[loanId]
                || amount > loanBacking[loanId]
        ) {
            revert InvalidBridgeOperation();
        }
        loanBacking[loanId] -= amount;
        emit LoanBackingReclassified(loanId, amount, loanBacking[loanId]);
    }

    function compensateMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata compensationPayload
    ) external override nonReentrant returns (bytes32 resultHash) {
        if (msg.sender != recoveryController) revert UnauthorizedBridgeCaller(msg.sender);
        if (actionType != CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED) {
            revert InvalidBridgeOperation();
        }
        bytes32 lockId = abi.decode(compensationPayload, (bytes32));
        LockRecord storage lock = _locks[lockId];
        if (
            lock.lockId == bytes32(0) || lock.messageId != messageId
                || lock.state != CrossChainTypes.BridgeOperationState.LOCKED
        ) {
            revert InvalidBridgeOperation();
        }
        lock.state = CrossChainTypes.BridgeOperationState.COMPENSATED;
        _decreaseExposure(lock.routePolicyHash, lock.amount);
        if (lock.loanId != bytes32(0)) {
            loanBacking[lock.loanId] = 0;
            IFundingCompensationReceiver(lock.loanAccount).onFundingCompensated(lockId);
        }
        _transferExact(lock.locker, lock.amount);
        _requireBackingBalance();
        resultHash = keccak256(
            abi.encode("UNIFIED_BRIDGE_COMPENSATION_V1", messageId, lockId, lock.amount)
        );
        emit BridgeLockCompensated(lockId, messageId, lock.locker, lock.amount);
    }

    function lockRecord(bytes32 lockId) external view returns (LockRecord memory) {
        return _locks[lockId];
    }

    function bridgeSurplus() public view returns (uint256) {
        uint256 balance = canonicalUFT.balanceOf(address(this));
        return balance > totalBridgeBacking ? balance - totalBridgeBacking : 0;
    }

    function reconcileSurplus() external returns (uint256 currentSurplus) {
        _requireBackingBalance();
        return lastReportedSurplus;
    }

    function _lock(LockRequest memory request) private returns (bytes32 messageId) {
        if (
            request.lockId == bytes32(0) || request.locker == address(0)
                || request.recipient == address(0) || request.amount == 0
                || request.expiresAt <= block.timestamp
                || _locks[request.lockId].state != CrossChainTypes.BridgeOperationState.NONE
        ) {
            revert InvalidBridgeOperation();
        }
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(request.routePolicyHash);
        if (
            route_.config.sourceComponent != address(this)
                || !routeRegistry.isActionAllowed(
                    request.routePolicyHash, CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED
                )
        ) {
            revert InvalidBridgeOperation();
        }
        {
            uint256 routeAfter = routeBacking[request.routePolicyHash] + request.amount;
            uint256 chainAfter = backingForChain[route_.config.destinationChainId] + request.amount;
            uint256 adapterAfter = adapterBacking[route_.config.adapterId] + request.amount;
            uint256 aggregateAfter = totalBridgeBacking + request.amount;
            if (
                routeAfter > route_.config.absoluteCap || chainAfter > route_.config.chainCap
                    || adapterAfter > route_.config.adapterCap
            ) {
                revert ExposureExceeded();
            }
            exposurePolicy.validateLock(
                request.routePolicyHash, routeAfter, chainAfter, adapterAfter, aggregateAfter
            );
            routeBacking[request.routePolicyHash] = routeAfter;
            backingForChain[route_.config.destinationChainId] = chainAfter;
            adapterBacking[route_.config.adapterId] = adapterAfter;
            totalBridgeBacking = aggregateAfter;
        }

        _collectExact(request.locker, request.amount);
        {
            CrossChainTypes.CanonicalUftLockPayload memory mint =
                CrossChainTypes.CanonicalUftLockPayload({
                    lockId: request.lockId,
                    loanId: request.loanId,
                    canonicalToken: address(canonicalUFT),
                    homeBridgeHub: address(this),
                    wrappedToken: route_.config.destinationComponent,
                    destinationRecipient: request.recipient,
                    amount: request.amount
                });
            bytes memory payload = abi.encode(mint);
            CrossChainTypes.MessageEnvelope memory envelope = CrossChainMessageBuilder.build(
                coordinator,
                routeRegistry,
                CrossChainMessageBuilder.BuildRequest({
                    routePolicyHash: request.routePolicyHash,
                    sourceComponent: address(this),
                    aggregateId: request.loanId == bytes32(0) ? request.lockId : request.loanId,
                    actionType: CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED,
                    payloadHash: keccak256(payload),
                    expiresAt: request.expiresAt,
                    correlationId: request.loanId == bytes32(0) ? request.lockId : request.loanId,
                    causationMessageId: bytes32(0),
                    supersededMessageId: bytes32(0)
                })
            );
            messageId = coordinator.sendMessage(envelope, payload);
        }
        _locks[request.lockId] = LockRecord({
            lockId: request.lockId,
            messageId: messageId,
            loanId: request.loanId,
            routePolicyHash: request.routePolicyHash,
            locker: request.locker,
            recipient: request.recipient,
            loanAccount: request.loanAccount,
            amount: request.amount,
            state: CrossChainTypes.BridgeOperationState.LOCKED
        });
        messageLock[messageId] = request.lockId;
        _requireBackingBalance();
        emit UFTLocked(
            request.lockId,
            messageId,
            request.routePolicyHash,
            request.locker,
            request.recipient,
            request.amount,
            request.loanId
        );
    }

    function _validateBackingRoute(
        bytes32 backingRoutePolicyHash,
        CrossChainTypes.MessageEnvelope memory exitEnvelope
    ) private view {
        RouteRegistry.RouteVersion memory backingRoute = routeRegistry.route(backingRoutePolicyHash);
        if (
            backingRoute.config.sourceChainId != coordinator.localChainId()
                || backingRoute.config.sourceCoordinator != address(coordinator)
                || backingRoute.config.sourceComponent != address(this)
                || backingRoute.config.destinationChainId != exitEnvelope.sourceChainId
                || backingRoute.config.destinationCoordinator != exitEnvelope.sourceCoordinator
                || backingRoute.config.destinationComponent != exitEnvelope.sourceComponent
                || !routeRegistry.isActionAllowed(
                    backingRoutePolicyHash, CrossChainTypes.ACTION_HOME_UFT_MINT_AUTHORIZED
                )
        ) {
            revert InvalidBridgeOperation();
        }
    }

    function _decreaseExposure(bytes32 routePolicyHash, uint256 amount) private {
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(routePolicyHash);
        if (
            routeBacking[routePolicyHash] < amount
                || backingForChain[route_.config.destinationChainId] < amount
                || adapterBacking[route_.config.adapterId] < amount || totalBridgeBacking < amount
        ) {
            revert InvalidBridgeOperation();
        }
        routeBacking[routePolicyHash] -= amount;
        backingForChain[route_.config.destinationChainId] -= amount;
        adapterBacking[route_.config.adapterId] -= amount;
        totalBridgeBacking -= amount;
    }

    function _transferExact(address recipient, uint256 amount) private {
        IERC20 token = IERC20(address(canonicalUFT));
        uint256 hubBefore = token.balanceOf(address(this));
        uint256 recipientBefore = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        if (
            hubBefore - token.balanceOf(address(this)) != amount
                || token.balanceOf(recipient) - recipientBefore != amount
        ) {
            revert BridgeBalanceMismatch();
        }
    }

    function _collectExact(address locker, uint256 amount) private {
        IERC20 token = IERC20(address(canonicalUFT));
        uint256 lockerBefore = token.balanceOf(locker);
        uint256 hubBefore = token.balanceOf(address(this));
        token.safeTransferFrom(locker, address(this), amount);
        if (
            lockerBefore - token.balanceOf(locker) != amount
                || token.balanceOf(address(this)) - hubBefore != amount
        ) {
            revert BridgeBalanceMismatch();
        }
    }

    function _requireBackingBalance() private {
        uint256 balance = canonicalUFT.balanceOf(address(this));
        if (balance < totalBridgeBacking) {
            revert BridgeBalanceMismatch();
        }
        uint256 currentSurplus = balance - totalBridgeBacking;
        if (currentSurplus != lastReportedSurplus) {
            emit BridgeSurplusReconciled(lastReportedSurplus, currentSurplus);
            lastReportedSurplus = currentSurplus;
        }
    }
}

    interface CoordinatorEnvelope {
        function messageEnvelope(bytes32 messageId)
            external
            view
            returns (CrossChainTypes.MessageEnvelope memory);
    }
