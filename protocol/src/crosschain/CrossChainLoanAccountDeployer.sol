// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { IUFTBridgeHub } from "../interfaces/IUFTBridgeHub.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CrossChainLoanAccount } from "./CrossChainLoanAccount.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";

/// @notice Isolates account creation bytecode from the fixed home message router.
contract CrossChainLoanAccountDeployer is RoleControlled {
    error InvalidAccountDeployment();
    error UnauthorizedAccountDeployment(address caller);

    address public factory;

    event FactoryBound(address indexed factory);
    event AccountDeployed(bytes32 indexed loanId, address indexed account);

    constructor(IRoleManager roleManager_) RoleControlled(roleManager_) { }

    function bindFactory(address factory_)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (factory != address(0) || factory_.code.length == 0) {
            revert InvalidAccountDeployment();
        }
        factory = factory_;
        emit FactoryBound(factory_);
    }

    function deployAccount(
        CrossChainTypes.CrossChainLoanTerms calldata terms,
        ILoanRegistry loanRegistry,
        IUFTBridgeHub bridgeHub,
        IERC20 canonicalUFT,
        address wrappedUFT,
        bytes32 policyConfigurationHash
    ) external returns (CrossChainLoanAccount account) {
        if (msg.sender != factory) {
            revert UnauthorizedAccountDeployment(msg.sender);
        }
        account = new CrossChainLoanAccount(
            terms,
            factory,
            loanRegistry,
            bridgeHub,
            canonicalUFT,
            wrappedUFT,
            policyConfigurationHash
        );
        emit AccountDeployed(terms.loanId, address(account));
    }
}
