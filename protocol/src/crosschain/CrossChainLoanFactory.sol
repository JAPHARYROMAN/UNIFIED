// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import { ICrossChainLoanPolicy } from "../interfaces/ICrossChainLoanPolicy.sol";
import { ICrossChainReceiver } from "../interfaces/ICrossChainReceiver.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { IUFTBridgeHub } from "../interfaces/IUFTBridgeHub.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CrossChainLoanAccount } from "./CrossChainLoanAccount.sol";
import { CrossChainLoanAccountDeployer } from "./CrossChainLoanAccountDeployer.sol";
import { CrossChainMessageBuilder } from "./CrossChainMessageBuilder.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { RouteRegistry } from "./RouteRegistry.sol";

interface ILoanCancellationRecoveryAuthorizer {
    function loanCancellationAuthorizationDigest(
        CrossChainTypes.LoanCancellationAuthorization calldata request
    ) external view returns (bytes32);

    function consumeLoanCancellationAuthorization(
        CrossChainTypes.LoanCancellationAuthorization calldata request,
        bytes[] calldata signatures
    ) external returns (bytes32 cancellationId);
}

/// @notice Home loan factory and fixed typed-message router for Phase 8 accounts.
contract CrossChainLoanFactory is ICrossChainReceiver, RoleControlled {
    error InvalidCrossChainOrigination();
    error InvalidCrossChainLoanMessage();
    error UnauthorizedLoanAccount(address caller);

    uint32 public constant IMPLEMENTATION_VERSION = 8;

    ILoanRegistry public immutable loanRegistry;
    IUFTBridgeHub public immutable bridgeHub;
    ICrossChainCoordinator public immutable coordinator;
    RouteRegistry public immutable routeRegistry;
    CrossChainLoanAccountDeployer public immutable accountDeployer;
    ICrossChainLoanPolicy public policy;
    bytes32 public policyConfigurationHash;
    mapping(bytes32 loanId => address account) public loanAccount;
    mapping(bytes32 cancellationId => bytes32 messageId) public cancellationMessage;

    event CrossChainLoanPolicyBound(address indexed policy, bytes32 indexed configurationHash);
    event CrossChainLoanCreated(
        bytes32 indexed loanId,
        address indexed account,
        address indexed lender,
        address borrower,
        bytes32 mintMessageId
    );
    event CrossChainLoanCancellationSent(
        bytes32 indexed loanId,
        bytes32 indexed cancellationId,
        bytes32 indexed messageId,
        bytes32 disbursementMessageId,
        bytes32 disbursementTombstoneHash
    );

    constructor(
        IRoleManager roleManager_,
        ILoanRegistry loanRegistry_,
        IUFTBridgeHub bridgeHub_,
        ICrossChainCoordinator coordinator_,
        RouteRegistry routeRegistry_,
        CrossChainLoanAccountDeployer accountDeployer_
    ) RoleControlled(roleManager_) {
        if (
            address(loanRegistry_) == address(0) || address(bridgeHub_) == address(0)
                || address(coordinator_) == address(0) || address(routeRegistry_) == address(0)
                || address(accountDeployer_) == address(0)
        ) {
            revert InvalidCrossChainOrigination();
        }
        loanRegistry = loanRegistry_;
        bridgeHub = bridgeHub_;
        coordinator = coordinator_;
        routeRegistry = routeRegistry_;
        accountDeployer = accountDeployer_;
    }

    function bindPolicy(ICrossChainLoanPolicy policy_)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (address(policy) != address(0) || address(policy_).code.length == 0) {
            revert InvalidCrossChainOrigination();
        }
        ICrossChainLoanPolicy.Configuration memory config = policy_.configuration();
        if (
            config.homeLoanRouter != address(this) || config.homeCoordinator != address(coordinator)
                || config.homeBridgeHub != address(bridgeHub)
                || config.homeChainId != coordinator.localChainId()
                || config.protocolId != coordinator.protocolId()
        ) {
            revert InvalidCrossChainOrigination();
        }
        _validatePolicyRoutes(config);
        policy = policy_;
        policyConfigurationHash = policy_.configurationHash();
        emit CrossChainLoanPolicyBound(address(policy_), policyConfigurationHash);
    }

    function _validatePolicyRoutes(ICrossChainLoanPolicy.Configuration memory config) private view {
        _requireRoute(
            config.mintRouteHash,
            config.homeChainId,
            config.homeCoordinator,
            config.homeBridgeHub,
            config.satelliteChainId,
            config.satelliteCoordinator,
            config.wrappedUFT,
            uint32(1) << 1
        );
        _requireRoute(
            config.reportRouteHash,
            config.satelliteChainId,
            config.satelliteCoordinator,
            config.satelliteComponent,
            config.homeChainId,
            config.homeCoordinator,
            address(this),
            (uint32(1) << 2) | (uint32(1) << 5) | (uint32(1) << 7) | (uint32(1) << 10)
                | (uint32(1) << 14)
        );
        _requireRoute(
            config.repaymentRouteHash,
            config.satelliteChainId,
            config.satelliteCoordinator,
            config.wrappedUFT,
            config.homeChainId,
            config.homeCoordinator,
            address(this),
            uint32(1) << 8
        );
        _requireRoute(
            config.disbursementRouteHash,
            config.homeChainId,
            config.homeCoordinator,
            address(this),
            config.satelliteChainId,
            config.satelliteCoordinator,
            config.satelliteSettlementVault,
            (uint32(1) << 6) | (uint32(1) << 12)
        );
        _requireRoute(
            config.collateralReleaseRouteHash,
            config.homeChainId,
            config.homeCoordinator,
            address(this),
            config.satelliteChainId,
            config.satelliteCoordinator,
            config.satelliteCollateralVault,
            uint32(1) << 9
        );
    }

    function _requireRoute(
        bytes32 routeHash,
        uint256 sourceChainId,
        address sourceCoordinator,
        address sourceComponent,
        uint256 destinationChainId,
        address destinationCoordinator,
        address destinationComponent,
        uint32 exactActions
    ) private view {
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(routeHash);
        if (
            route_.status != CrossChainTypes.RegistryStatus.ACTIVE
                || route_.config.sourceChainId != sourceChainId
                || route_.config.sourceCoordinator != sourceCoordinator
                || route_.config.sourceComponent != sourceComponent
                || route_.config.destinationChainId != destinationChainId
                || route_.config.destinationCoordinator != destinationCoordinator
                || route_.config.destinationComponent != destinationComponent
                || route_.config.allowedActionsBitmap != exactActions
        ) revert InvalidCrossChainOrigination();
    }

    function createLoan(CrossChainTypes.CrossChainLoanTerms calldata terms, uint64 messageExpiresAt)
        external
        returns (address account, bytes32 mintMessageId)
    {
        ICrossChainLoanPolicy.Configuration memory config = _configuration();
        if (
            msg.sender != terms.lender || terms.loanId == bytes32(0)
                || terms.agreementHash == bytes32(0) || terms.fundingLockId == bytes32(0)
                || terms.collateralId == bytes32(0) || terms.borrower == address(0)
                || terms.lender == address(0) || terms.borrower == terms.lender
                || terms.principalAmount == 0 || terms.collateralAmount == 0
                || terms.policyHash != config.policyHash || messageExpiresAt <= block.timestamp
                || loanRegistry.exists(terms.loanId)
        ) {
            revert InvalidCrossChainOrigination();
        }
        CrossChainLoanAccount account_ = accountDeployer.deployAccount(
            terms,
            loanRegistry,
            bridgeHub,
            IERC20(config.canonicalUFT),
            config.wrappedUFT,
            policyConfigurationHash
        );
        account = address(account_);
        loanAccount[terms.loanId] = account;
        loanRegistry.registerLoan(
            terms.loanId, account, terms.borrower, terms.agreementHash, IMPLEMENTATION_VERSION
        );

        mintMessageId = bridgeHub.lockForLoan(
            terms.fundingLockId,
            terms.loanId,
            account,
            terms.lender,
            config.satelliteSettlementVault,
            terms.principalAmount,
            config.mintRouteHash,
            messageExpiresAt
        );
        account_.bindOrigination(mintMessageId);
        emit CrossChainLoanCreated(
            terms.loanId, account, terms.lender, terms.borrower, mintMessageId
        );
    }

    /// @notice Exact terms used by synthetic-local satellite provisioning.
    function satelliteProvisioning(bytes32 loanId)
        external
        view
        returns (CrossChainTypes.SatelliteLoanProvisioning memory provisioning)
    {
        CrossChainLoanAccount account = _account(loanId);
        CrossChainTypes.CrossChainLoanTerms memory terms = account.terms();
        ICrossChainLoanPolicy.Configuration memory config = _configuration();
        provisioning = CrossChainTypes.SatelliteLoanProvisioning({
            loanId: terms.loanId,
            fundingLockId: terms.fundingLockId,
            homeLoanAccount: address(account),
            homeLoanRouter: address(this),
            borrower: terms.borrower,
            lender: terms.lender,
            wrappedToken: config.wrappedUFT,
            collateralToken: config.collateralToken,
            collateralId: terms.collateralId,
            principalAmount: terms.principalAmount,
            collateralAmount: terms.collateralAmount,
            repaymentRoutePolicyHash: config.repaymentRouteHash,
            policyHash: terms.policyHash
        });
    }

    function handleCrossChainMessage(
        bytes32,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external override returns (bytes32 resultHash) {
        if (msg.sender != address(coordinator)) {
            revert InvalidCrossChainLoanMessage();
        }
        if (actionType == CrossChainTypes.ACTION_SATELLITE_REPAYMENT_BURNED) {
            CrossChainTypes.SatelliteRepaymentBurnedPayload memory burn =
                abi.decode(payload, (CrossChainTypes.SatelliteRepaymentBurnedPayload));
            CrossChainLoanAccount account = _account(burn.loanId);
            if (burn.lender != account.lender()) revert InvalidCrossChainLoanMessage();
            account.recordRemoteRepayment(burn);
            return keccak256(
                abi.encode(
                    "UNIFIED_REMOTE_REPAYMENT_RESULT_V1",
                    burn.loanId,
                    burn.paymentId,
                    burn.amount,
                    account.outstandingPrincipal()
                )
            );
        }
        if (actionType == CrossChainTypes.ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED) {
            CrossChainTypes.SatelliteFundingCancelledPayload memory cancellation =
                abi.decode(payload, (CrossChainTypes.SatelliteFundingCancelledPayload));
            CrossChainLoanAccount cancellationAccount = _account(cancellation.loanId);
            ICrossChainLoanPolicy.Configuration memory cancellationConfig = _configuration();
            if (
                cancellation.homeLoanAccount != address(cancellationAccount)
                    || cancellation.lender != cancellationAccount.lender()
                    || cancellation.wrappedToken != cancellationConfig.wrappedUFT
            ) {
                revert InvalidCrossChainLoanMessage();
            }
            cancellationAccount.recordCancellationCompensated(cancellation);
            return keccak256(
                abi.encode(
                    "UNIFIED_HOME_LOAN_CANCELLATION_RESULT_V1",
                    cancellation.cancellationId,
                    cancellation.loanId,
                    cancellation.amount,
                    cancellation.escrowBurnResultHash,
                    cancellationAccount.stateNonce()
                )
            );
        }
        bytes32 loanId;
        bytes32 operationId;
        uint256 amount;
        CrossChainLoanAccount account_;
        if (actionType == CrossChainTypes.ACTION_SATELLITE_MINT_CONFIRMED) {
            CrossChainTypes.WrappedUftMintedPayload memory action =
                abi.decode(payload, (CrossChainTypes.WrappedUftMintedPayload));
            account_ = _validatedAccount(
                action.loanId, action.homeLoanAccount, action.borrower, action.lender
            );
            account_.recordMintConfirmed(action.lockId, action.amount, action.policyHash);
            (loanId, operationId, amount) = (action.loanId, action.lockId, action.amount);
        } else if (actionType == CrossChainTypes.ACTION_SATELLITE_COLLATERAL_LOCKED) {
            CrossChainTypes.SatelliteCollateralLockedPayload memory action =
                abi.decode(payload, (CrossChainTypes.SatelliteCollateralLockedPayload));
            account_ = _validatedAccount(
                action.loanId, action.homeLoanAccount, action.borrower, action.lender
            );
            account_.recordCollateralLocked(action.collateralId, action.amount, action.policyHash);
            (loanId, operationId, amount) = (action.loanId, action.collateralId, action.amount);
        } else if (actionType == CrossChainTypes.ACTION_SATELLITE_DISBURSEMENT_SETTLED) {
            CrossChainTypes.SatelliteDisbursementSettledPayload memory action =
                abi.decode(payload, (CrossChainTypes.SatelliteDisbursementSettledPayload));
            account_ = _validatedAccount(
                action.loanId, action.homeLoanAccount, action.borrower, action.lender
            );
            account_.recordDisbursement(action.fundingLockId, action.amount, action.policyHash);
            (loanId, operationId, amount) = (action.loanId, action.fundingLockId, action.amount);
        } else if (actionType == CrossChainTypes.ACTION_SATELLITE_COLLATERAL_RELEASED) {
            CrossChainTypes.SatelliteCollateralReleasedPayload memory action =
                abi.decode(payload, (CrossChainTypes.SatelliteCollateralReleasedPayload));
            account_ = _validatedAccount(
                action.loanId, action.homeLoanAccount, action.borrower, action.lender
            );
            account_.recordCollateralReleased(action.collateralId, action.amount, action.policyHash);
            (loanId, operationId, amount) = (action.loanId, action.collateralId, action.amount);
        } else {
            revert InvalidCrossChainLoanMessage();
        }
        resultHash = keccak256(
            abi.encode(
                "UNIFIED_SATELLITE_LOAN_ACTION_RESULT_V1",
                actionType,
                loanId,
                operationId,
                amount,
                account_.stateNonce()
            )
        );
    }

    function authorizeDisbursement(bytes32 loanId) external returns (bytes32 messageId) {
        CrossChainLoanAccount account = _authorizedAccount(loanId);
        ICrossChainLoanPolicy.Configuration memory config = _configuration();
        CrossChainTypes.CrossChainLoanTerms memory terms = account.terms();
        CrossChainTypes.HomeDisbursementAuthorizedPayload memory action =
            CrossChainTypes.HomeDisbursementAuthorizedPayload({
                loanId: loanId,
                fundingLockId: terms.fundingLockId,
                homeLoanAccount: address(account),
                borrower: terms.borrower,
                lender: terms.lender,
                wrappedToken: config.wrappedUFT,
                amount: terms.principalAmount,
                policyHash: terms.policyHash
            });
        messageId = _send(
            config.disbursementRouteHash,
            loanId,
            CrossChainTypes.ACTION_HOME_DISBURSEMENT_AUTHORIZED,
            abi.encode(action),
            uint64(block.timestamp + 2 days),
            loanId,
            bytes32(0)
        );
    }

    function authorizeCancellation(
        CrossChainTypes.LoanCancellationAuthorization calldata authorization,
        bytes[] calldata signatures
    ) external returns (bytes32 messageId) {
        CrossChainLoanAccount account = _account(authorization.loanId);
        CrossChainTypes.CrossChainLoanTerms memory terms = account.terms();
        if (
            authorization.loanRouter != address(this)
                || authorization.fundingLockId != terms.fundingLockId
                || authorization.disbursementMessageId != account.disbursementMessageId()
                || authorization.amount != terms.principalAmount
                || authorization.policyHash != terms.policyHash
        ) {
            revert InvalidCrossChainLoanMessage();
        }
        ILoanCancellationRecoveryAuthorizer recovery =
            ILoanCancellationRecoveryAuthorizer(coordinator.recoveryController());
        bytes32 cancellationId = recovery.loanCancellationAuthorizationDigest(authorization);
        messageId = cancellationMessage[cancellationId];
        if (messageId != bytes32(0)) return messageId;
        if (
            recovery.consumeLoanCancellationAuthorization(authorization, signatures)
                != cancellationId
        ) {
            revert InvalidCrossChainLoanMessage();
        }
        messageId = _dispatchCancellation(account, terms, authorization, cancellationId);
    }

    function _dispatchCancellation(
        CrossChainLoanAccount account,
        CrossChainTypes.CrossChainLoanTerms memory terms,
        CrossChainTypes.LoanCancellationAuthorization calldata authorization,
        bytes32 cancellationId
    ) private returns (bytes32 messageId) {
        ICrossChainLoanPolicy.Configuration memory config = _configuration();
        CrossChainTypes.LoanCancellationRequestedPayload memory cancellation;
        cancellation.cancellationId = cancellationId;
        cancellation.loanId = terms.loanId;
        cancellation.fundingLockId = terms.fundingLockId;
        cancellation.disbursementMessageId = authorization.disbursementMessageId;
        cancellation.disbursementTombstoneHash = authorization.disbursementTombstoneHash;
        cancellation.homeLoanAccount = address(account);
        cancellation.lender = terms.lender;
        cancellation.wrappedToken = config.wrappedUFT;
        cancellation.amount = terms.principalAmount;
        cancellation.policyHash = terms.policyHash;
        cancellation.reasonCode = authorization.reasonCode;
        messageId = _send(
            config.disbursementRouteHash,
            authorization.loanId,
            CrossChainTypes.ACTION_HOME_LOAN_CANCELLATION_REQUESTED,
            abi.encode(cancellation),
            authorization.validUntil,
            authorization.loanId,
            authorization.disbursementMessageId == bytes32(0)
                ? account.mintMessageId()
                : authorization.disbursementMessageId
        );
        cancellationMessage[cancellationId] = messageId;
        account.requestCancellation(
            cancellationId, messageId, authorization.disbursementTombstoneHash
        );
        emit CrossChainLoanCancellationSent(
            authorization.loanId,
            cancellationId,
            messageId,
            authorization.disbursementMessageId,
            authorization.disbursementTombstoneHash
        );
    }

    function authorizeCollateralRelease(bytes32 loanId) external returns (bytes32 messageId) {
        CrossChainLoanAccount account = _authorizedAccount(loanId);
        ICrossChainLoanPolicy.Configuration memory config = _configuration();
        CrossChainTypes.CrossChainLoanTerms memory terms = account.terms();
        CrossChainTypes.HomeCollateralReleaseAuthorizedPayload memory action =
            CrossChainTypes.HomeCollateralReleaseAuthorizedPayload({
                loanId: loanId,
                collateralId: terms.collateralId,
                homeLoanAccount: address(account),
                borrower: terms.borrower,
                lender: terms.lender,
                collateralToken: config.collateralToken,
                amount: terms.collateralAmount,
                policyHash: terms.policyHash
            });
        messageId = _send(
            config.collateralReleaseRouteHash,
            loanId,
            CrossChainTypes.ACTION_HOME_COLLATERAL_RELEASE_AUTHORIZED,
            abi.encode(action),
            uint64(block.timestamp + 2 days),
            loanId,
            bytes32(0)
        );
    }

    function _authorizedAccount(bytes32 loanId)
        private
        view
        returns (CrossChainLoanAccount account)
    {
        account = _account(loanId);
        if (msg.sender != address(account)) revert UnauthorizedLoanAccount(msg.sender);
    }

    function _account(bytes32 loanId) private view returns (CrossChainLoanAccount account) {
        address accountAddress = loanAccount[loanId];
        if (accountAddress == address(0) || loanRegistry.loanAccount(loanId) != accountAddress) {
            revert InvalidCrossChainLoanMessage();
        }
        account = CrossChainLoanAccount(accountAddress);
    }

    function _validatedAccount(
        bytes32 loanId,
        address homeLoanAccount,
        address borrower,
        address lender
    ) private view returns (CrossChainLoanAccount account) {
        account = _account(loanId);
        if (
            homeLoanAccount != address(account) || borrower != account.borrower()
                || lender != account.lender()
        ) {
            revert InvalidCrossChainLoanMessage();
        }
    }

    function _configuration()
        private
        view
        returns (ICrossChainLoanPolicy.Configuration memory config)
    {
        if (address(policy) == address(0)) revert InvalidCrossChainOrigination();
        config = policy.configuration();
        if (policy.configurationHash() != policyConfigurationHash) {
            revert InvalidCrossChainOrigination();
        }
    }

    function _send(
        bytes32 routePolicyHash,
        bytes32 aggregateId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes memory payload,
        uint64 expiresAt,
        bytes32 correlationId,
        bytes32 causationMessageId
    ) private returns (bytes32 messageId) {
        CrossChainTypes.MessageEnvelope memory envelope =
            CrossChainMessageBuilder.build(
                coordinator,
                routeRegistry,
                CrossChainMessageBuilder.BuildRequest({
                    routePolicyHash: routePolicyHash,
                    sourceComponent: address(this),
                    aggregateId: aggregateId,
                    actionType: actionType,
                    payloadHash: keccak256(payload),
                    expiresAt: expiresAt,
                    correlationId: correlationId,
                    causationMessageId: causationMessageId,
                    supersededMessageId: bytes32(0)
                })
            );
        messageId = coordinator.sendMessage(envelope, payload);
    }
}
