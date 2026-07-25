// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { CrossChainTypes } from "../crosschain/CrossChainTypes.sol";

interface ICrossChainCoordinator {
    function localChainId() external view returns (uint256);
    function protocolId() external view returns (bytes32);
    function recoveryController() external view returns (address);
    function nextOutboundNonce(bytes32 laneId) external view returns (uint64);

    function sendMessage(CrossChainTypes.MessageEnvelope calldata envelope, bytes calldata payload)
        external
        returns (bytes32 messageId);

    function messageState(bytes32 messageId) external view returns (CrossChainTypes.MessageState);
    function executionResult(bytes32 messageId) external view returns (bytes32);
    function tombstoneHash(bytes32 messageId) external view returns (bytes32);
}
