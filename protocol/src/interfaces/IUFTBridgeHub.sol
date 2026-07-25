// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

interface IUFTBridgeHub {
    function lockForLoan(
        bytes32 lockId,
        bytes32 loanId,
        address loanAccount,
        address lender,
        address destinationRecipient,
        uint256 amount,
        bytes32 routePolicyHash,
        uint64 expiresAt
    ) external returns (bytes32 messageId);

    function releaseLoanBacking(bytes32 loanId, bytes32 burnId, address lender, uint256 amount)
        external;

    function refundCancelledLoan(
        bytes32 loanId,
        bytes32 cancellationId,
        address lender,
        uint256 amount
    ) external;

    function reclassifyLoanBacking(bytes32 loanId, uint256 amount) external;

    function loanBacking(bytes32 loanId) external view returns (uint256);
    function backingForChain(uint256 chainId) external view returns (uint256);
    function totalBridgeBacking() external view returns (uint256);
}
