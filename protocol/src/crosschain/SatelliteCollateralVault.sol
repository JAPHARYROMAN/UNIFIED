// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ICrossChainCoordinator } from "../interfaces/ICrossChainCoordinator.sol";
import { ICrossChainReceiver } from "../interfaces/ICrossChainReceiver.sol";
import {
    ISatelliteLoanComponent,
    ISatelliteLoanProvisioner
} from "../interfaces/ISatelliteLoanComponent.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";

/// @notice Exact-amount satellite collateral custody with borrower-only release.
contract SatelliteCollateralVault is
    ICrossChainReceiver,
    ISatelliteLoanProvisioner,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    error InvalidSatelliteCollateral();
    error UnauthorizedSatelliteCollateralCaller(address caller);
    error SatelliteCollateralBalanceMismatch();

    struct CollateralRecord {
        bytes32 loanId;
        bytes32 collateralId;
        address homeLoanAccount;
        address borrower;
        address lender;
        address token;
        uint256 amount;
        bytes32 policyHash;
        CrossChainTypes.SatelliteCollateralState state;
    }

    address public immutable component;
    ICrossChainCoordinator public immutable coordinator;
    IERC20 public immutable collateralToken;
    mapping(bytes32 loanId => CollateralRecord record) private _records;
    mapping(bytes32 collateralId => bytes32 loanId) public collateralLoan;

    event SatelliteCollateralProvisioned(
        bytes32 indexed loanId,
        bytes32 indexed collateralId,
        address indexed borrower,
        uint256 amount
    );
    event SatelliteCollateralLocked(
        bytes32 indexed loanId, bytes32 indexed collateralId, uint256 amount
    );
    event SatelliteCollateralReleased(
        bytes32 indexed loanId, bytes32 indexed collateralId, uint256 amount
    );

    constructor(address component_, ICrossChainCoordinator coordinator_, IERC20 collateralToken_) {
        if (
            component_.code.length == 0 || address(coordinator_) == address(0)
                || address(collateralToken_).code.length == 0
        ) {
            revert InvalidSatelliteCollateral();
        }
        component = component_;
        coordinator = coordinator_;
        collateralToken = collateralToken_;
    }

    function provisionLoan(CrossChainTypes.SatelliteLoanProvisioning calldata provisioning)
        external
        override
    {
        if (msg.sender != component) {
            revert UnauthorizedSatelliteCollateralCaller(msg.sender);
        }
        if (
            provisioning.loanId == bytes32(0) || provisioning.collateralId == bytes32(0)
                || provisioning.borrower == address(0)
                || provisioning.collateralToken != address(collateralToken)
                || provisioning.collateralAmount == 0
                || _records[provisioning.loanId].loanId != bytes32(0)
                || collateralLoan[provisioning.collateralId] != bytes32(0)
        ) {
            revert InvalidSatelliteCollateral();
        }
        _records[provisioning.loanId] = CollateralRecord({
            loanId: provisioning.loanId,
            collateralId: provisioning.collateralId,
            homeLoanAccount: provisioning.homeLoanAccount,
            borrower: provisioning.borrower,
            lender: provisioning.lender,
            token: provisioning.collateralToken,
            amount: provisioning.collateralAmount,
            policyHash: provisioning.policyHash,
            state: CrossChainTypes.SatelliteCollateralState.NONE
        });
        collateralLoan[provisioning.collateralId] = provisioning.loanId;
        emit SatelliteCollateralProvisioned(
            provisioning.loanId,
            provisioning.collateralId,
            provisioning.borrower,
            provisioning.collateralAmount
        );
    }

    function lockCollateral(bytes32 loanId) external nonReentrant returns (bytes32 messageId) {
        CollateralRecord storage record = _records[loanId];
        if (
            record.loanId == bytes32(0) || msg.sender != record.borrower
                || record.state != CrossChainTypes.SatelliteCollateralState.NONE
        ) {
            revert InvalidSatelliteCollateral();
        }
        uint256 borrowerBefore = collateralToken.balanceOf(record.borrower);
        uint256 vaultBefore = collateralToken.balanceOf(address(this));
        collateralToken.safeTransferFrom(record.borrower, address(this), record.amount);
        if (
            borrowerBefore - collateralToken.balanceOf(record.borrower) != record.amount
                || collateralToken.balanceOf(address(this)) - vaultBefore != record.amount
        ) {
            revert SatelliteCollateralBalanceMismatch();
        }
        record.state = CrossChainTypes.SatelliteCollateralState.LOCKED;
        messageId = ISatelliteLoanComponent(component)
            .reportCollateralLocked(loanId, record.collateralId, record.amount);
        emit SatelliteCollateralLocked(loanId, record.collateralId, record.amount);
    }

    function handleCrossChainMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external override nonReentrant returns (bytes32 resultHash) {
        if (msg.sender != address(coordinator)) {
            revert UnauthorizedSatelliteCollateralCaller(msg.sender);
        }
        if (actionType != CrossChainTypes.ACTION_HOME_COLLATERAL_RELEASE_AUTHORIZED) {
            revert InvalidSatelliteCollateral();
        }
        CrossChainTypes.HomeCollateralReleaseAuthorizedPayload memory action =
            abi.decode(payload, (CrossChainTypes.HomeCollateralReleaseAuthorizedPayload));
        CollateralRecord storage record = _records[action.loanId];
        if (
            record.loanId == bytes32(0)
                || record.state != CrossChainTypes.SatelliteCollateralState.LOCKED
                || action.collateralId != record.collateralId
                || action.homeLoanAccount != record.homeLoanAccount
                || action.borrower != record.borrower || action.lender != record.lender
                || action.collateralToken != address(collateralToken)
                || action.amount != record.amount || action.policyHash != record.policyHash
        ) {
            revert InvalidSatelliteCollateral();
        }
        record.state = CrossChainTypes.SatelliteCollateralState.RELEASED;
        uint256 vaultBefore = collateralToken.balanceOf(address(this));
        uint256 borrowerBefore = collateralToken.balanceOf(record.borrower);
        collateralToken.safeTransfer(record.borrower, record.amount);
        if (
            vaultBefore - collateralToken.balanceOf(address(this)) != record.amount
                || collateralToken.balanceOf(record.borrower) - borrowerBefore != record.amount
        ) {
            revert SatelliteCollateralBalanceMismatch();
        }
        bytes32 reportMessageId = ISatelliteLoanComponent(component)
            .reportCollateralReleased(action.loanId, record.collateralId, record.amount);
        resultHash = keccak256(
            abi.encode(
                "UNIFIED_SATELLITE_COLLATERAL_RELEASE_RESULT_V1",
                messageId,
                reportMessageId,
                action.loanId,
                record.collateralId,
                record.amount
            )
        );
        emit SatelliteCollateralReleased(action.loanId, record.collateralId, record.amount);
    }

    function collateralRecord(bytes32 loanId) external view returns (CollateralRecord memory) {
        return _records[loanId];
    }
}
