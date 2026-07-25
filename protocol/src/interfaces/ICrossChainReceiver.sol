// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { CrossChainTypes } from "../crosschain/CrossChainTypes.sol";

interface ICrossChainReceiver {
    function handleCrossChainMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external returns (bytes32 resultHash);
}

interface ICrossChainCompensable {
    function compensateMessage(
        bytes32 messageId,
        CrossChainTypes.CrossChainActionType actionType,
        bytes calldata payload
    ) external returns (bytes32 resultHash);
}

interface IWrappedMintReceiver {
    function onWrappedMint(bytes32 lockId, bytes32 loanId, uint256 amount) external;
}
