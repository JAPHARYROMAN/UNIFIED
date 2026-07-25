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
import { UnderwrittenLoanFactory } from "./loan/UnderwrittenLoanFactory.sol";
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
import { IdentityProviderRegistry } from "./identity/IdentityProviderRegistry.sol";
import { CredentialRegistry } from "./identity/CredentialRegistry.sol";
import { CreditDecisionRegistry } from "./identity/CreditDecisionRegistry.sol";
import { ExposureManager } from "./identity/ExposureManager.sol";
import {
    CanonicalExternalSettlementGateway
} from "./payment/CanonicalExternalSettlementGateway.sol";
import {
    FixedMatureExternalSettlementPolicy
} from "./payment/FixedMatureExternalSettlementPolicy.sol";
import { BridgeExposurePolicy } from "./crosschain/BridgeExposurePolicy.sol";
import { ChainRegistry } from "./crosschain/ChainRegistry.sol";
import { CrossChainCoordinator } from "./crosschain/CrossChainCoordinator.sol";
import { CrossChainLoanAccount } from "./crosschain/CrossChainLoanAccount.sol";
import { CrossChainLoanAccountDeployer } from "./crosschain/CrossChainLoanAccountDeployer.sol";
import { CrossChainLoanFactory } from "./crosschain/CrossChainLoanFactory.sol";
import { CrossChainLoanPolicy } from "./crosschain/CrossChainLoanPolicy.sol";
import { CrossChainRecoveryController } from "./crosschain/CrossChainRecoveryController.sol";
import { Phase8LocalSyntheticToken } from "./crosschain/Phase8LocalSyntheticToken.sol";
import { RouteRegistry } from "./crosschain/RouteRegistry.sol";
import { SatelliteCollateralVault } from "./crosschain/SatelliteCollateralVault.sol";
import { SatelliteLoanComponent } from "./crosschain/SatelliteLoanComponent.sol";
import { SatelliteSettlementVault } from "./crosschain/SatelliteSettlementVault.sol";
import { SyntheticFinalityVerifier } from "./crosschain/SyntheticFinalityVerifier.sol";
import { UFTBridgeHub } from "./crosschain/UFTBridgeHub.sol";
import { WrappedUFT } from "./crosschain/WrappedUFT.sol";
import { Phase9LoanFactory } from "./resolution/Phase9LoanFactory.sol";
import { Phase9LoanAccount } from "./resolution/Phase9LoanAccount.sol";
import { PayoffQuoteEngine } from "./resolution/PayoffQuoteEngine.sol";
import { CollateralCustodyV2 } from "./resolution/CollateralCustodyV2.sol";
import { LienRegistry } from "./resolution/LienRegistry.sol";
import { RefinanceCoordinator } from "./resolution/RefinanceCoordinator.sol";
import { PositionManagerV2 } from "./resolution/PositionManagerV2.sol";
import { RestructuringController } from "./resolution/RestructuringController.sol";
import { InsuranceReserveVault } from "./protection/InsuranceReserveVault.sol";
import { ReservePolicy } from "./protection/ReservePolicy.sol";
import { InsuranceManager } from "./protection/InsuranceManager.sol";
import { GuaranteeVault } from "./recovery/GuaranteeVault.sol";
import { RecoveryManager } from "./recovery/RecoveryManager.sol";
import { Phase9LocalSyntheticToken } from "./token/Phase9LocalSyntheticToken.sol";
