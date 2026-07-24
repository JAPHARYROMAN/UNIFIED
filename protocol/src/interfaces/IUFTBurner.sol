// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

interface IUFTBurner {
    function burnFromRevenue(uint256 amount, bytes32 revenueEpoch, bytes32 journalRef) external;
    function cumulativeBurned() external view returns (uint256);
}
