// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUnifiedToken } from "../interfaces/IUnifiedToken.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";

/// @notice Grant pool with a fixed, publicly inspectable monthly vesting schedule.
contract VestingPoolVault is RoleControlled {
    using SafeERC20 for IERC20;

    error InvalidBinding();
    error TokenAlreadyBound();
    error InvalidGrant();
    error UnknownGrant(bytes32 grantId);
    error NothingToRelease();

    uint64 public constant MONTH = 30 days;

    struct Grant {
        address beneficiary;
        uint128 total;
        uint128 released;
        uint64 start;
        bool cancellable;
        bool cancelled;
    }

    bytes32 public immutable allocationId;
    uint256 public immutable allocationCapacity;
    uint32 public immutable cliffMonths;
    uint32 public immutable durationMonths;
    IERC20 public token;
    uint256 public committed;
    mapping(bytes32 grantId => Grant grant) private _grants;

    event TokenBound(address indexed token, uint256 verifiedBalance);
    event GrantCreated(
        bytes32 indexed grantId,
        address indexed beneficiary,
        uint256 amount,
        uint64 start,
        bool cancellable
    );
    event GrantReleased(bytes32 indexed grantId, address indexed beneficiary, uint256 amount);
    event GrantCancelled(bytes32 indexed grantId, uint256 unvestedReturned);
    event BeneficiaryChanged(
        bytes32 indexed grantId, address indexed priorBeneficiary, address indexed newBeneficiary
    );

    constructor(
        IRoleManager roleManager_,
        bytes32 allocationId_,
        uint256 allocationCapacity_,
        uint32 cliffMonths_,
        uint32 durationMonths_
    ) RoleControlled(roleManager_) {
        require(
            allocationId_ != bytes32(0) && allocationCapacity_ != 0
                && durationMonths_ > cliffMonths_ && durationMonths_ != 0,
            "invalid vesting pool"
        );
        allocationId = allocationId_;
        allocationCapacity = allocationCapacity_;
        cliffMonths = cliffMonths_;
        durationMonths = durationMonths_;
    }

    function bindToken(IUnifiedToken token_)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (address(token) != address(0)) revert TokenAlreadyBound();
        if (
            address(token_) == address(0) || token_.MAX_SUPPLY() != 1_000_000_000 ether
                || token_.balanceOf(address(this)) != allocationCapacity
        ) {
            revert InvalidBinding();
        }
        token = IERC20(address(token_));
        emit TokenBound(address(token_), allocationCapacity);
    }

    function createGrant(
        bytes32 grantId,
        address beneficiary,
        uint128 amount,
        uint64 start,
        bool cancellable
    ) external onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE) {
        if (
            address(token) == address(0) || grantId == bytes32(0)
                || _grants[grantId].beneficiary != address(0) || beneficiary == address(0)
                || amount == 0 || start < block.timestamp || committed + amount > allocationCapacity
        ) {
            revert InvalidGrant();
        }
        committed += amount;
        _grants[grantId] = Grant({
            beneficiary: beneficiary,
            total: amount,
            released: 0,
            start: start,
            cancellable: cancellable,
            cancelled: false
        });
        emit GrantCreated(grantId, beneficiary, amount, start, cancellable);
    }

    function release(bytes32 grantId) external returns (uint256 amount) {
        Grant storage grantRecord = _grant(grantId);
        uint256 vested = vestedAmount(grantId, uint64(block.timestamp));
        amount = vested - grantRecord.released;
        if (amount == 0) revert NothingToRelease();
        grantRecord.released += uint128(amount);
        token.safeTransfer(grantRecord.beneficiary, amount);
        emit GrantReleased(grantId, grantRecord.beneficiary, amount);
    }

    function cancelGrant(bytes32 grantId)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        Grant storage grantRecord = _grant(grantId);
        if (!grantRecord.cancellable || grantRecord.cancelled) revert InvalidGrant();
        uint256 vested = vestedAmount(grantId, uint64(block.timestamp));
        uint256 unvested = uint256(grantRecord.total) - vested;
        grantRecord.total = uint128(vested);
        grantRecord.cancelled = true;
        committed -= unvested;
        emit GrantCancelled(grantId, unvested);
    }

    function changeBeneficiary(bytes32 grantId, address newBeneficiary)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (newBeneficiary == address(0)) revert InvalidGrant();
        Grant storage grantRecord = _grant(grantId);
        address prior = grantRecord.beneficiary;
        grantRecord.beneficiary = newBeneficiary;
        emit BeneficiaryChanged(grantId, prior, newBeneficiary);
    }

    function vestedAmount(bytes32 grantId, uint64 timestamp) public view returns (uint256) {
        Grant storage grantRecord = _grant(grantId);
        if (grantRecord.cancelled) return grantRecord.total;
        uint256 elapsedMonths =
            timestamp <= grantRecord.start ? 0 : (timestamp - grantRecord.start) / MONTH;
        if (elapsedMonths < cliffMonths) return 0;
        if (elapsedMonths >= durationMonths) return grantRecord.total;
        return uint256(grantRecord.total) * elapsedMonths / durationMonths;
    }

    function grant(bytes32 grantId) external view returns (Grant memory) {
        return _grant(grantId);
    }

    function _grant(bytes32 grantId) private view returns (Grant storage result) {
        result = _grants[grantId];
        if (result.beneficiary == address(0)) revert UnknownGrant(grantId);
    }
}
