// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

// solcjs compiles this import graph as the deterministic protocol compilation target.
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
import { CoreLoanAccount } from "./loan/CoreLoanAccount.sol";
import { CoreLoanFactory } from "./loan/CoreLoanFactory.sol";
import { FundingManager } from "./loan/FundingManager.sol";
import { OfferManager } from "./loan/OfferManager.sol";
import { TenderRegistry } from "./loan/TenderRegistry.sol";
import { InterestEngine } from "./risk/InterestEngine.sol";
import { OracleRouter } from "./risk/OracleRouter.sol";
import { ScheduleEngine } from "./risk/ScheduleEngine.sol";
import { ServicingEngine } from "./risk/ServicingEngine.sol";
import { CollateralManager } from "./collateral/CollateralManager.sol";
import { CollateralVault } from "./collateral/CollateralVault.sol";
import { LiquidationEngine } from "./collateral/LiquidationEngine.sol";
import { PositionManager } from "./syndicate/PositionManager.sol";
import { SyndicateFactory } from "./syndicate/SyndicateFactory.sol";
import { SyndicateVault } from "./syndicate/SyndicateVault.sol";
