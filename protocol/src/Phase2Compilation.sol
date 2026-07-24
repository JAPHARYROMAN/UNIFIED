// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

// solcjs compiles this import graph as the deterministic Phase 2 compilation target.
import { FoundationProbe } from "./FoundationProbe.sol";
import { AssetRegistry } from "./kernel/AssetRegistry.sol";
import { EmergencyController } from "./kernel/EmergencyController.sol";
import { LoanFactory } from "./kernel/LoanFactory.sol";
import { LoanRegistry } from "./kernel/LoanRegistry.sol";
import { PolicyRegistry } from "./kernel/PolicyRegistry.sol";
import { RoleManager } from "./kernel/RoleManager.sol";
import { UnifiedProtocol } from "./kernel/UnifiedProtocol.sol";
import { VersionedLoanAccount } from "./kernel/VersionedLoanAccount.sol";
import { AllocationVault } from "./token/AllocationVault.sol";
import { ProtocolFeeRouter } from "./token/ProtocolFeeRouter.sol";
import { UFTBurner } from "./token/UFTBurner.sol";
import { UnifiedToken } from "./token/UnifiedToken.sol";
import { VestingPoolVault } from "./token/VestingPoolVault.sol";
