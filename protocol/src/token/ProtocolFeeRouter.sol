// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUnifiedToken } from "../interfaces/IUnifiedToken.sol";
import { IUFTBurner } from "../interfaces/IUFTBurner.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { AssetRegistry } from "../kernel/AssetRegistry.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { ProtocolTypes } from "../kernel/ProtocolTypes.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";

/// @notice Asset-conserving fee collection and bounded revenue allocation skeleton.
contract ProtocolFeeRouter is RoleControlled, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidConfiguration();
    error InvalidSplit();
    error UnsupportedAsset(bytes32 assetId);
    error InsufficientCollected(bytes32 assetId);

    uint16 public constant BPS = 10_000;
    uint8 public constant SUSPEND_INSURANCE_BELOW_FLOOR = 1 << 0;
    uint8 public constant SUSPEND_MATERIAL_BAD_DEBT = 1 << 1;
    uint8 public constant SUSPEND_BRIDGE_DEFICIT = 1 << 2;
    uint8 public constant SUSPEND_TREASURY_RUNWAY = 1 << 3;
    uint8 public constant SUSPEND_EMERGENCY_RESERVE_MODE = 1 << 4;
    uint8 private constant VALID_SUSPENSION_FLAGS = (1 << 5) - 1;

    AssetRegistry public immutable assetRegistry;
    IUnifiedToken public immutable uft;
    IUFTBurner public immutable burner;
    bytes32 public immutable uftAssetId;
    address public immutable insuranceReceiver;
    address public immutable stakerReceiver;
    address public immutable treasuryReceiver;
    address public immutable burnReserve;
    address public immutable liquidityReceiver;
    address public immutable publicGoodsReceiver;

    ProtocolTypes.RevenueSplit private _revenueSplit;
    uint8 private _burnSuspensionFlags;
    uint256 private _distributionNonce;
    mapping(bytes32 assetId => uint256 amount) public undistributed;

    event FeeCollected(
        bytes32 indexed sourceId,
        bytes32 indexed assetId,
        uint256 requestedAmount,
        uint256 receivedAmount,
        bytes32 indexed journalRef
    );
    event RevenueDistributed(
        bytes32 indexed assetId,
        uint256 amount,
        uint256 insuranceAmount,
        uint256 stakerAmount,
        uint256 treasuryAmount,
        uint256 burnAmount,
        uint256 liquidityAmount,
        uint256 publicGoodsAmount
    );
    event RevenueSplitChanged(ProtocolTypes.RevenueSplit split);
    event ReserveDeficiencyChanged(bool deficient, bytes32 indexed evidenceReference);
    event BurnSuspensionFlagsChanged(uint8 flags, bytes32 indexed evidenceReference);

    constructor(
        IRoleManager roleManager_,
        AssetRegistry assetRegistry_,
        IUnifiedToken uft_,
        IUFTBurner burner_,
        bytes32 uftAssetId_,
        address[6] memory receivers
    ) RoleControlled(roleManager_) {
        if (
            address(assetRegistry_) == address(0) || address(uft_) == address(0)
                || address(burner_) == address(0) || uftAssetId_ == bytes32(0)
        ) {
            revert InvalidConfiguration();
        }
        for (uint256 index = 0; index < receivers.length; ++index) {
            if (receivers[index] == address(0)) revert InvalidConfiguration();
        }
        assetRegistry = assetRegistry_;
        uft = uft_;
        burner = burner_;
        uftAssetId = uftAssetId_;
        insuranceReceiver = receivers[0];
        stakerReceiver = receivers[1];
        treasuryReceiver = receivers[2];
        burnReserve = receivers[3];
        liquidityReceiver = receivers[4];
        publicGoodsReceiver = receivers[5];
        _revenueSplit = ProtocolTypes.RevenueSplit({
            insuranceBps: 3000,
            stakerBps: 2500,
            treasuryBps: 2500,
            burnBps: 1000,
            liquidityBps: 500,
            publicGoodsBps: 500
        });
    }

    function collectFee(bytes32 sourceId, bytes32 assetId, uint256 amount, bytes32 journalRef)
        external
        nonReentrant
        onlyRole(ProtocolRoles.SERVICER_ROLE)
    {
        if (sourceId == bytes32(0) || amount == 0 || journalRef == bytes32(0)) {
            revert InvalidConfiguration();
        }
        AssetRegistry.AssetRecord memory asset = assetRegistry.resolve(assetId);
        if (!asset.active) revert UnsupportedAsset(assetId);
        IERC20 token = IERC20(asset.token);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received == 0) revert UnsupportedAsset(assetId);
        undistributed[assetId] += received;
        emit FeeCollected(sourceId, assetId, amount, received, journalRef);
    }

    function distribute(bytes32 assetId, uint256 amount)
        external
        nonReentrant
        onlyRole(ProtocolRoles.TREASURY_OPERATOR_ROLE)
    {
        if (amount == 0) revert InvalidConfiguration();
        if (undistributed[assetId] < amount) revert InsufficientCollected(assetId);
        AssetRegistry.AssetRecord memory asset = assetRegistry.resolve(assetId);
        IERC20 token = IERC20(asset.token);
        ProtocolTypes.RevenueSplit memory split = _revenueSplit;

        uint256 insuranceAmount = amount * split.insuranceBps / BPS;
        uint256 stakerAmount = amount * split.stakerBps / BPS;
        uint256 treasuryAmount = amount * split.treasuryBps / BPS;
        uint256 burnAmount = amount * split.burnBps / BPS;
        uint256 liquidityAmount = amount * split.liquidityBps / BPS;
        uint256 publicGoodsAmount =
            amount - insuranceAmount - stakerAmount - treasuryAmount - burnAmount - liquidityAmount;

        undistributed[assetId] -= amount;
        token.safeTransfer(insuranceReceiver, insuranceAmount);
        token.safeTransfer(stakerReceiver, stakerAmount);
        token.safeTransfer(treasuryReceiver, treasuryAmount);
        token.safeTransfer(liquidityReceiver, liquidityAmount);
        token.safeTransfer(publicGoodsReceiver, publicGoodsAmount);
        if (burnAmount != 0) {
            if (burnSuspended() || assetId != uftAssetId) {
                token.safeTransfer(burnReserve, burnAmount);
            } else {
                token.safeTransfer(address(burner), burnAmount);
                ++_distributionNonce;
                burner.burnFromRevenue(
                    burnAmount,
                    keccak256(abi.encode(block.chainid, assetId, _distributionNonce)),
                    keccak256(abi.encode("FEE_DISTRIBUTION", assetId, _distributionNonce))
                );
            }
        }
        emit RevenueDistributed(
            assetId,
            amount,
            insuranceAmount,
            stakerAmount,
            treasuryAmount,
            burnAmount,
            liquidityAmount,
            publicGoodsAmount
        );
    }

    function setRevenueSplit(ProtocolTypes.RevenueSplit calldata split)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        uint256 total = uint256(split.insuranceBps) + split.stakerBps + split.treasuryBps
            + split.burnBps + split.liquidityBps + split.publicGoodsBps;
        if (
            total != BPS || split.insuranceBps < 2000 || split.insuranceBps > 5000
                || split.stakerBps < 1000 || split.stakerBps > 3500 || split.treasuryBps < 1500
                || split.treasuryBps > 4000 || split.burnBps > 2000 || split.liquidityBps > 1500
                || split.publicGoodsBps > 1500
                || ((_burnSuspensionFlags & SUSPEND_INSURANCE_BELOW_FLOOR) != 0
                    && split.insuranceBps < 3000)
        ) {
            revert InvalidSplit();
        }
        _revenueSplit = split;
        emit RevenueSplitChanged(split);
    }

    function setReserveDeficient(bool deficient, bytes32 evidenceReference)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
    {
        if (evidenceReference == bytes32(0)) revert InvalidConfiguration();
        if (deficient) {
            _burnSuspensionFlags |= SUSPEND_INSURANCE_BELOW_FLOOR;
        } else {
            _burnSuspensionFlags &= ~SUSPEND_INSURANCE_BELOW_FLOOR;
        }
        emit ReserveDeficiencyChanged(deficient, evidenceReference);
        emit BurnSuspensionFlagsChanged(_burnSuspensionFlags, evidenceReference);
    }

    function setBurnSuspensionFlags(uint8 flags, bytes32 evidenceReference)
        external
        onlyRole(ProtocolRoles.RISK_COUNCIL_ROLE)
    {
        if (evidenceReference == bytes32(0) || (flags & ~VALID_SUSPENSION_FLAGS) != 0) {
            revert InvalidConfiguration();
        }
        _burnSuspensionFlags = flags;
        emit BurnSuspensionFlagsChanged(flags, evidenceReference);
    }

    function revenueSplit() external view returns (ProtocolTypes.RevenueSplit memory) {
        return _revenueSplit;
    }

    function burnSuspended() public view returns (bool) {
        return _burnSuspensionFlags != 0;
    }

    function burnSuspensionFlags() external view returns (uint8) {
        return _burnSuspensionFlags;
    }
}
