// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { SyndicateTypes } from "./SyndicateTypes.sol";

/// @notice Canonical non-tokenized lender rights for one syndicated loan.
contract PositionManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error UnauthorizedPositionCaller();
    error InvalidTranche();
    error InvalidPosition();
    error InvalidPositionState();
    error PositionLimitExceeded();
    error PositionBalanceMismatch();

    uint256 public constant BPS = 10_000;
    uint8 public constant MAX_TRANCHES = 8;
    uint8 public constant MAX_POSITIONS = 64;

    struct Tranche {
        SyndicateTypes.TrancheConfiguration configuration;
        uint256 fundedPrincipal;
        uint256 outstandingPrincipal;
        uint256 totalShares;
        uint256 issuedShares;
        bytes32 residualPositionId;
    }

    struct Checkpoint {
        uint64 fromBlock;
        uint192 value;
    }

    IRoleManager public roleManager;
    address public vault;
    IERC20 public settlementToken;
    bytes32 public loanId;
    bool public fundingActivated;
    uint256 public totalIssuedShares;
    uint256 public totalOutstandingPrincipal;
    mapping(bytes32 trancheId => Tranche tranche_) private _tranches;
    bytes32[] private _trancheIds;
    mapping(bytes32 positionId => SyndicateTypes.Position position_) private _positions;
    bytes32[] private _positionIds;
    mapping(bytes32 trancheId => bytes32[] positionIds) private _positionsByTranche;
    mapping(bytes32 positionId => uint256 amount) public accruedDistribution;
    mapping(address owner => uint256 amount) public withdrawable;
    mapping(address owner => uint256 votes) private _currentVotes;
    mapping(address owner => Checkpoint[] checkpoints) private _voteCheckpoints;
    Checkpoint[] private _totalVoteCheckpoints;
    bool private _initialized;

    event TrancheConfigured(
        bytes32 indexed trancheId,
        uint8 seniorityRank,
        uint256 targetSize,
        uint16 couponBps,
        uint16 votingBps,
        SyndicateTypes.TransferPolicy transferPolicy
    );
    event PositionIssued(
        bytes32 indexed positionId, bytes32 indexed trancheId, address indexed owner, uint256 shares
    );
    event FundingRightsActivated(bytes32 indexed loanId, uint256 totalShares);
    event PositionDistributionRecorded(
        bytes32 indexed trancheId, uint256 amount, uint256 remainingPrincipal
    );
    event PositionTransferred(
        bytes32 indexed positionId,
        address indexed seller,
        address indexed buyer,
        uint256 shares,
        uint256 claimUnits,
        uint64 cutoffBlock,
        bytes32 evidenceHash
    );
    event PositionSplit(
        bytes32 indexed positionId,
        bytes32 indexed newPositionId,
        address indexed newOwner,
        uint256 shares
    );
    event PositionMerged(bytes32 indexed primaryPositionId, bytes32 indexed mergedPositionId);
    event PositionPledged(
        bytes32 indexed positionId,
        address indexed owner,
        address indexed pledgee,
        bytes32 evidenceHash
    );
    event PositionPledgeReleased(bytes32 indexed positionId, address indexed pledgee);
    event PositionFreezeChanged(
        bytes32 indexed positionId, bool frozen, bytes32 indexed evidenceHash
    );
    event DistributionWithdrawn(address indexed owner, uint256 amount);
    event PositionRedeemed(bytes32 indexed positionId, address indexed owner);

    modifier onlyVault() {
        if (msg.sender != vault) revert UnauthorizedPositionCaller();
        _;
    }

    constructor() {
        _initialized = true;
    }

    function initialize(
        IRoleManager roleManager_,
        address vault_,
        IERC20 settlementToken_,
        bytes32 loanId_
    ) external {
        if (_initialized) revert AlreadyInitialized();
        if (
            address(roleManager_).code.length == 0 || vault_ == address(0)
                || address(settlementToken_).code.length == 0 || loanId_ == bytes32(0)
        ) {
            revert InvalidPosition();
        }
        _initialized = true;
        roleManager = roleManager_;
        vault = vault_;
        settlementToken = settlementToken_;
        loanId = loanId_;
    }

    function configureTranche(SyndicateTypes.TrancheConfiguration calldata configuration)
        external
        onlyVault
    {
        if (
            fundingActivated || configuration.trancheId == bytes32(0)
                || configuration.nameHash == bytes32(0) || configuration.targetSize == 0
                || configuration.seniorityRank != _trancheIds.length + 1
                || configuration.votingBps > BPS
                || configuration.transferPolicy == SyndicateTypes.TransferPolicy.NONE
                || _trancheIds.length >= MAX_TRANCHES
                || _tranches[configuration.trancheId].configuration.trancheId != bytes32(0)
        ) {
            revert InvalidTranche();
        }
        _tranches[configuration.trancheId].configuration = configuration;
        _trancheIds.push(configuration.trancheId);
        emit TrancheConfigured(
            configuration.trancheId,
            configuration.seniorityRank,
            configuration.targetSize,
            configuration.couponBps,
            configuration.votingBps,
            configuration.transferPolicy
        );
    }

    function issuePending(bytes32 positionId, bytes32 trancheId, address owner, uint256 shares)
        external
        onlyVault
    {
        Tranche storage tranche_ = _tranche(trancheId);
        if (
            fundingActivated || positionId == bytes32(0) || owner == address(0) || shares == 0
                || _positions[positionId].status != SyndicateTypes.PositionStatus.NONE
                || _positionIds.length >= MAX_POSITIONS
                || tranche_.fundedPrincipal + shares > tranche_.configuration.targetSize
        ) {
            revert InvalidPosition();
        }
        _positions[positionId] = SyndicateTypes.Position({
            positionId: positionId,
            loanId: loanId,
            trancheId: trancheId,
            owner: owner,
            pledgee: address(0),
            shares: shares,
            votingPower: _votingPower(trancheId, shares),
            acquiredAt: uint64(block.timestamp),
            status: SyndicateTypes.PositionStatus.PENDING
        });
        _positionIds.push(positionId);
        _positionsByTranche[trancheId].push(positionId);
        tranche_.fundedPrincipal += shares;
        tranche_.totalShares += shares;
        tranche_.issuedShares += shares;
        if (tranche_.residualPositionId == bytes32(0)) {
            tranche_.residualPositionId = positionId;
        }
        totalIssuedShares += shares;
        emit PositionIssued(positionId, trancheId, owner, shares);
    }

    function activateFunding(uint256 fundedPrincipal) external onlyVault {
        if (
            fundingActivated || fundedPrincipal == 0 || fundedPrincipal != totalIssuedShares
                || _trancheIds.length == 0
        ) {
            revert InvalidPosition();
        }
        fundingActivated = true;
        totalOutstandingPrincipal = fundedPrincipal;
        for (uint256 index = 0; index < _trancheIds.length; ++index) {
            Tranche storage tranche_ = _tranches[_trancheIds[index]];
            tranche_.outstandingPrincipal = tranche_.fundedPrincipal;
        }
        for (uint256 index = 0; index < _positionIds.length; ++index) {
            SyndicateTypes.Position storage position_ = _positions[_positionIds[index]];
            position_.status = SyndicateTypes.PositionStatus.ACTIVE;
            _moveVotes(address(0), position_.owner, position_.votingPower);
        }
        emit FundingRightsActivated(loanId, fundedPrincipal);
    }

    function cancelPending(bytes32 positionId) external onlyVault {
        SyndicateTypes.Position storage position_ = _position(positionId);
        if (fundingActivated || position_.status != SyndicateTypes.PositionStatus.PENDING) {
            revert InvalidPositionState();
        }
        Tranche storage tranche_ = _tranches[position_.trancheId];
        uint256 shares = position_.shares;
        position_.shares = 0;
        position_.votingPower = 0;
        position_.status = SyndicateTypes.PositionStatus.CANCELLED;
        tranche_.fundedPrincipal -= shares;
        tranche_.totalShares -= shares;
        tranche_.issuedShares -= shares;
        totalIssuedShares -= shares;
    }

    function recordDistribution(bytes32 trancheId, uint256 amount) external onlyVault nonReentrant {
        Tranche storage tranche_ = _tranche(trancheId);
        if (!fundingActivated || amount == 0 || amount > tranche_.outstandingPrincipal) {
            revert InvalidTranche();
        }
        uint256 beforeBalance = settlementToken.balanceOf(address(this));
        settlementToken.safeTransferFrom(msg.sender, address(this), amount);
        if (settlementToken.balanceOf(address(this)) - beforeBalance != amount) {
            revert PositionBalanceMismatch();
        }

        uint256 allocated;
        bytes32[] storage ids = _positionsByTranche[trancheId];
        for (uint256 index = 0; index < ids.length; ++index) {
            SyndicateTypes.Position storage position_ = _positions[ids[index]];
            if (position_.shares == 0) continue;
            uint256 allocation = Math.mulDiv(amount, position_.shares, tranche_.totalShares);
            accruedDistribution[position_.positionId] += allocation;
            allocated += allocation;
        }
        uint256 residual = amount - allocated;
        if (residual != 0) {
            SyndicateTypes.Position storage residualPosition =
                _positions[tranche_.residualPositionId];
            if (residualPosition.shares == 0) revert PositionBalanceMismatch();
            accruedDistribution[residualPosition.positionId] += residual;
        }
        tranche_.outstandingPrincipal -= amount;
        totalOutstandingPrincipal -= amount;
        emit PositionDistributionRecorded(trancheId, amount, tranche_.outstandingPrincipal);
    }

    function transferPosition(bytes32 positionId, address buyer, bytes32 evidenceHash) external {
        SyndicateTypes.Position storage position_ = _position(positionId);
        Tranche storage tranche_ = _tranches[position_.trancheId];
        if (
            position_.owner != msg.sender || buyer == address(0) || buyer == msg.sender
                || evidenceHash == bytes32(0)
                || position_.status != SyndicateTypes.PositionStatus.ACTIVE
                || tranche_.configuration.transferPolicy
                    != SyndicateTypes.TransferPolicy.FREELY_TRANSFERABLE
        ) {
            revert InvalidPositionState();
        }
        uint256 claimUnits_ = _claimUnits(position_);
        if (claimUnits_ == 0) revert InvalidPositionState();
        address seller = position_.owner;
        _settleAccrued(position_);
        _moveVotes(seller, buyer, position_.votingPower);
        position_.owner = buyer;
        position_.acquiredAt = uint64(block.timestamp);
        emit PositionTransferred(
            positionId,
            seller,
            buyer,
            position_.shares,
            claimUnits_,
            uint64(block.number),
            evidenceHash
        );
    }

    function splitPosition(
        bytes32 positionId,
        bytes32 newPositionId,
        uint256 splitShares,
        address newOwner
    ) external {
        SyndicateTypes.Position storage position_ = _position(positionId);
        Tranche storage tranche_ = _tranches[position_.trancheId];
        if (
            position_.owner != msg.sender || newPositionId == bytes32(0)
                || _positions[newPositionId].status != SyndicateTypes.PositionStatus.NONE
                || newOwner != position_.owner || splitShares == 0
                || splitShares >= position_.shares
                || position_.status != SyndicateTypes.PositionStatus.ACTIVE
                || tranche_.configuration.transferPolicy
                    != SyndicateTypes.TransferPolicy.FREELY_TRANSFERABLE
                || _positionIds.length >= MAX_POSITIONS
        ) {
            revert InvalidPositionState();
        }
        _settleAccrued(position_);
        uint256 splitVotingPower = Math.mulDiv(position_.votingPower, splitShares, position_.shares);
        _moveVotes(position_.owner, newOwner, splitVotingPower);
        position_.shares -= splitShares;
        position_.votingPower -= splitVotingPower;
        SyndicateTypes.Position memory split = SyndicateTypes.Position({
            positionId: newPositionId,
            loanId: loanId,
            trancheId: position_.trancheId,
            owner: newOwner,
            pledgee: address(0),
            shares: splitShares,
            votingPower: splitVotingPower,
            acquiredAt: uint64(block.timestamp),
            status: SyndicateTypes.PositionStatus.ACTIVE
        });
        _positions[newPositionId] = split;
        _positionIds.push(newPositionId);
        _positionsByTranche[position_.trancheId].push(newPositionId);
        emit PositionSplit(positionId, newPositionId, newOwner, splitShares);
    }

    function mergePositions(bytes32 primaryPositionId, bytes32 mergedPositionId) external {
        if (primaryPositionId == mergedPositionId) revert InvalidPosition();
        SyndicateTypes.Position storage primary = _position(primaryPositionId);
        SyndicateTypes.Position storage merged = _position(mergedPositionId);
        if (
            primary.owner != msg.sender || merged.owner != msg.sender
                || primary.trancheId != merged.trancheId
                || primary.status != SyndicateTypes.PositionStatus.ACTIVE
                || merged.status != SyndicateTypes.PositionStatus.ACTIVE
        ) {
            revert InvalidPositionState();
        }
        _settleAccrued(primary);
        _settleAccrued(merged);
        primary.shares += merged.shares;
        primary.votingPower += merged.votingPower;
        Tranche storage tranche_ = _tranches[primary.trancheId];
        if (tranche_.residualPositionId == mergedPositionId) {
            tranche_.residualPositionId = primaryPositionId;
        }
        merged.shares = 0;
        merged.votingPower = 0;
        merged.status = SyndicateTypes.PositionStatus.MERGED;
        emit PositionMerged(primaryPositionId, mergedPositionId);
    }

    function pledgePosition(bytes32 positionId, address pledgee, bytes32 evidenceHash) external {
        SyndicateTypes.Position storage position_ = _position(positionId);
        if (
            position_.owner != msg.sender || pledgee == address(0) || pledgee == msg.sender
                || evidenceHash == bytes32(0)
                || position_.status != SyndicateTypes.PositionStatus.ACTIVE
        ) {
            revert InvalidPositionState();
        }
        position_.pledgee = pledgee;
        position_.status = SyndicateTypes.PositionStatus.PLEDGED;
        emit PositionPledged(positionId, msg.sender, pledgee, evidenceHash);
    }

    function releasePledge(bytes32 positionId) external {
        SyndicateTypes.Position storage position_ = _position(positionId);
        if (
            position_.status != SyndicateTypes.PositionStatus.PLEDGED
                || position_.pledgee != msg.sender
        ) {
            revert InvalidPositionState();
        }
        address pledgee = position_.pledgee;
        position_.pledgee = address(0);
        position_.status = SyndicateTypes.PositionStatus.ACTIVE;
        emit PositionPledgeReleased(positionId, pledgee);
    }

    function setFrozen(bytes32 positionId, bool frozen, bytes32 evidenceHash) external {
        if (
            !roleManager.hasRole(ProtocolRoles.RISK_COUNCIL_ROLE, msg.sender)
                || evidenceHash == bytes32(0)
        ) {
            revert UnauthorizedPositionCaller();
        }
        SyndicateTypes.Position storage position_ = _position(positionId);
        if (
            (frozen && position_.status != SyndicateTypes.PositionStatus.ACTIVE)
                || (!frozen && position_.status != SyndicateTypes.PositionStatus.FROZEN)
        ) {
            revert InvalidPositionState();
        }
        position_.status =
            frozen ? SyndicateTypes.PositionStatus.FROZEN : SyndicateTypes.PositionStatus.ACTIVE;
        emit PositionFreezeChanged(positionId, frozen, evidenceHash);
    }

    function withdrawDistribution(bytes32 positionId) external nonReentrant {
        SyndicateTypes.Position storage position_ = _position(positionId);
        if (position_.owner != msg.sender) revert InvalidPositionState();
        _settleAccrued(position_);
        _withdrawAvailable(msg.sender);
    }

    function withdrawAvailable() external nonReentrant {
        _withdrawAvailable(msg.sender);
    }

    function redeemPosition(bytes32 positionId) external {
        SyndicateTypes.Position storage position_ = _position(positionId);
        Tranche storage tranche_ = _tranches[position_.trancheId];
        if (
            position_.owner != msg.sender
                || position_.status != SyndicateTypes.PositionStatus.ACTIVE
                || tranche_.outstandingPrincipal != 0
        ) {
            revert InvalidPositionState();
        }
        _settleAccrued(position_);
        _moveVotes(position_.owner, address(0), position_.votingPower);
        tranche_.totalShares -= position_.shares;
        position_.shares = 0;
        position_.votingPower = 0;
        position_.status = SyndicateTypes.PositionStatus.REDEEMED;
        emit PositionRedeemed(positionId, msg.sender);
    }

    function previewLoss(uint256 amount)
        external
        view
        returns (bytes32[] memory trancheIds_, uint256[] memory allocations)
    {
        if (!fundingActivated || amount > totalOutstandingPrincipal) revert InvalidTranche();
        trancheIds_ = new bytes32[](_trancheIds.length);
        allocations = new uint256[](_trancheIds.length);
        uint256 remaining = amount;
        for (uint256 cursor = _trancheIds.length; cursor != 0; --cursor) {
            uint256 index = cursor - 1;
            bytes32 trancheId = _trancheIds[index];
            trancheIds_[index] = trancheId;
            uint256 allocated = Math.min(remaining, _tranches[trancheId].outstandingPrincipal);
            allocations[index] = allocated;
            remaining -= allocated;
        }
        if (remaining != 0) revert InvalidTranche();
    }

    function position(bytes32 positionId) external view returns (SyndicateTypes.Position memory) {
        return _position(positionId);
    }

    function claimUnits(bytes32 positionId) external view returns (uint256) {
        return _claimUnits(_position(positionId));
    }

    function tranche(bytes32 trancheId) external view returns (Tranche memory) {
        return _tranche(trancheId);
    }

    function trancheIds() external view returns (bytes32[] memory) {
        return _trancheIds;
    }

    function positionIds() external view returns (bytes32[] memory) {
        return _positionIds;
    }

    function currentVotes(address owner) external view returns (uint256) {
        return _currentVotes[owner];
    }

    function getPastVotes(address owner, uint64 blockNumber) external view returns (uint256) {
        if (blockNumber >= block.number) revert InvalidPosition();
        return _checkpointValue(_voteCheckpoints[owner], blockNumber);
    }

    function getPastTotalVotes(uint64 blockNumber) external view returns (uint256) {
        if (blockNumber >= block.number) revert InvalidPosition();
        return _checkpointValue(_totalVoteCheckpoints, blockNumber);
    }

    function _settleAccrued(SyndicateTypes.Position storage position_) private {
        uint256 amount = accruedDistribution[position_.positionId];
        if (amount != 0) {
            accruedDistribution[position_.positionId] = 0;
            withdrawable[position_.owner] += amount;
        }
    }

    function _withdrawAvailable(address owner) private {
        uint256 amount = withdrawable[owner];
        if (amount == 0) revert InvalidPositionState();
        withdrawable[owner] = 0;
        _transferExact(owner, amount);
        emit DistributionWithdrawn(owner, amount);
    }

    function _moveVotes(address from, address to, uint256 amount) private {
        if (amount == 0 || from == to) return;
        if (amount > type(uint192).max) revert InvalidPosition();
        if (from != address(0)) {
            _currentVotes[from] -= amount;
            _writeCheckpoint(_voteCheckpoints[from], _currentVotes[from]);
        }
        if (to != address(0)) {
            _currentVotes[to] += amount;
            if (_currentVotes[to] > type(uint192).max) revert InvalidPosition();
            _writeCheckpoint(_voteCheckpoints[to], _currentVotes[to]);
        }
        uint256 total = _latestValue(_totalVoteCheckpoints);
        if (from == address(0)) total += amount;
        if (to == address(0)) total -= amount;
        _writeCheckpoint(_totalVoteCheckpoints, total);
    }

    function _writeCheckpoint(Checkpoint[] storage checkpoints, uint256 value) private {
        if (block.number > type(uint64).max || value > type(uint192).max) {
            revert InvalidPosition();
        }
        uint64 currentBlock = uint64(block.number);
        uint256 length = checkpoints.length;
        if (length != 0 && checkpoints[length - 1].fromBlock == currentBlock) {
            checkpoints[length - 1].value = uint192(value);
        } else {
            checkpoints.push(Checkpoint({ fromBlock: currentBlock, value: uint192(value) }));
        }
    }

    function _checkpointValue(Checkpoint[] storage checkpoints, uint64 blockNumber)
        private
        view
        returns (uint256)
    {
        uint256 low;
        uint256 high = checkpoints.length;
        while (low < high) {
            uint256 middle = (low + high) / 2;
            if (checkpoints[middle].fromBlock > blockNumber) {
                high = middle;
            } else {
                low = middle + 1;
            }
        }
        return high == 0 ? 0 : checkpoints[high - 1].value;
    }

    function _latestValue(Checkpoint[] storage checkpoints) private view returns (uint256) {
        return checkpoints.length == 0 ? 0 : checkpoints[checkpoints.length - 1].value;
    }

    function _votingPower(bytes32 trancheId, uint256 shares) private view returns (uint256) {
        return Math.mulDiv(shares, _tranches[trancheId].configuration.votingBps, BPS);
    }

    function _claimUnits(SyndicateTypes.Position storage position_) private view returns (uint256) {
        if (position_.shares == 0) return 0;
        Tranche storage tranche_ = _tranches[position_.trancheId];
        uint256 outstanding = tranche_.outstandingPrincipal;
        if (outstanding == 0) return 0;
        uint256 claim = Math.mulDiv(outstanding, position_.shares, tranche_.totalShares);
        if (position_.positionId != tranche_.residualPositionId) return claim;

        uint256 allocated;
        bytes32[] storage ids = _positionsByTranche[position_.trancheId];
        for (uint256 index = 0; index < ids.length; ++index) {
            uint256 shares = _positions[ids[index]].shares;
            if (shares != 0) {
                allocated += Math.mulDiv(outstanding, shares, tranche_.totalShares);
            }
        }
        return claim + outstanding - allocated;
    }

    function _position(bytes32 positionId)
        private
        view
        returns (SyndicateTypes.Position storage position_)
    {
        position_ = _positions[positionId];
        if (position_.status == SyndicateTypes.PositionStatus.NONE) revert InvalidPosition();
    }

    function _tranche(bytes32 trancheId) private view returns (Tranche storage tranche_) {
        tranche_ = _tranches[trancheId];
        if (tranche_.configuration.trancheId == bytes32(0)) revert InvalidTranche();
    }

    function _transferExact(address recipient, uint256 amount) private {
        uint256 senderBefore = settlementToken.balanceOf(address(this));
        uint256 recipientBefore = settlementToken.balanceOf(recipient);
        settlementToken.safeTransfer(recipient, amount);
        if (
            senderBefore - settlementToken.balanceOf(address(this)) != amount
                || settlementToken.balanceOf(recipient) - recipientBefore != amount
        ) {
            revert PositionBalanceMismatch();
        }
    }
}
