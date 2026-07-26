// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { ICollateralCustodyV2 } from "../src/interfaces/phase9/ICollateralCustodyV2.sol";
import { IGuaranteeVault } from "../src/interfaces/phase9/IGuaranteeVault.sol";
import { IInsuranceManager } from "../src/interfaces/phase9/IInsuranceManager.sol";
import { IInsuranceReserveVault } from "../src/interfaces/phase9/IInsuranceReserveVault.sol";
import { ILienRegistry } from "../src/interfaces/phase9/ILienRegistry.sol";
import { IPhase9LoanAccount } from "../src/interfaces/phase9/IPhase9LoanAccount.sol";
import { IPhase9LoanFactory } from "../src/interfaces/phase9/IPhase9LoanFactory.sol";
import { IPositionManagerV2 } from "../src/interfaces/phase9/IPositionManagerV2.sol";
import { IRecoveryManager } from "../src/interfaces/phase9/IRecoveryManager.sol";
import { IRefinanceCoordinator } from "../src/interfaces/phase9/IRefinanceCoordinator.sol";
import { IReservePolicy } from "../src/interfaces/phase9/IReservePolicy.sol";
import { IRestructuringController } from "../src/interfaces/phase9/IRestructuringController.sol";
import { Phase9ProtectionTypes } from "../src/protection/Phase9ProtectionTypes.sol";
import { InsuranceManager } from "../src/protection/InsuranceManager.sol";
import { InsuranceReserveVault } from "../src/protection/InsuranceReserveVault.sol";
import { ReservePolicy } from "../src/protection/ReservePolicy.sol";
import { Phase9RecoveryTypes } from "../src/recovery/Phase9RecoveryTypes.sol";
import { GuaranteeVault } from "../src/recovery/GuaranteeVault.sol";
import { RecoveryManager } from "../src/recovery/RecoveryManager.sol";
import { CollateralCustodyV2 } from "../src/resolution/CollateralCustodyV2.sol";
import { LienRegistry } from "../src/resolution/LienRegistry.sol";
import { Phase9LoanAccount } from "../src/resolution/Phase9LoanAccount.sol";
import { Phase9LoanFactory } from "../src/resolution/Phase9LoanFactory.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import { PositionManagerV2 } from "../src/resolution/PositionManagerV2.sol";
import { RefinanceCoordinator } from "../src/resolution/RefinanceCoordinator.sol";
import { RestructuringController } from "../src/resolution/RestructuringController.sol";

contract Phase9InterfaceFreezeTest {
    bytes4 private constant FROZEN = bytes4(keccak256("Phase9ImplementationNotFrozen()"));

    function testEveryStillUnopenedNonTokenComponentRejectsItsRepresentativeMutator() public {
        Phase9Types.LoanCreationRequest memory loanCreationRequest;
        _requireFrozen(
            address(
                new Phase9LoanFactory(
                    ILoanRegistry(address(0)),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0)
                )
            ),
            abi.encodeCall(IPhase9LoanFactory.createLoan, (loanCreationRequest))
        );
        _requireFrozen(
            address(new Phase9LoanAccount()),
            abi.encodeCall(IPhase9LoanAccount.closeLoan, (bytes32(uint256(1))))
        );
        _requireFrozen(
            address(new CollateralCustodyV2(address(0), address(0), address(0))),
            abi.encodeCall(
                ICollateralCustodyV2.updateCustody,
                (bytes32(uint256(1)), 1, Phase9Types.CustodyStatus.HELD, bytes32(uint256(2)))
            )
        );
        _requireFrozen(
            address(new LienRegistry(address(0))),
            abi.encodeCall(
                ILienRegistry.beginHandoff,
                (bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)), uint64(1))
            )
        );
        _requireFrozen(
            address(
                new RefinanceCoordinator(
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    IERC20(address(0))
                )
            ),
            abi.encodeCall(
                IRefinanceCoordinator.cancelRefinance, (bytes32(uint256(1)), bytes32(uint256(2)))
            )
        );
        _requireFrozen(
            address(new PositionManagerV2()),
            abi.encodeCall(
                IPositionManagerV2.initialize, (bytes32(uint256(1)), address(1), address(2))
            )
        );
        _requireFrozen(
            address(new RestructuringController(address(0), address(0), address(0))),
            abi.encodeCall(
                IRestructuringController.execute, (bytes32(uint256(1)), bytes32(uint256(2)))
            )
        );

        Phase9ProtectionTypes.ReserveFundingResult memory funding;
        _requireFrozen(
            address(new InsuranceReserveVault(address(0), address(0))),
            abi.encodeCall(IInsuranceReserveVault.fundReserve, (funding))
        );
        _requireFrozen(
            address(new ReservePolicy(address(0))),
            abi.encodeCall(
                IReservePolicy.activatePolicy,
                (bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)))
            )
        );
        _requireFrozen(
            address(new InsuranceManager(address(0), address(0), address(0), address(0))),
            abi.encodeCall(
                IInsuranceManager.setActivePolicy,
                (bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3)))
            )
        );
        _requireFrozen(
            address(new GuaranteeVault(address(0), address(0), address(0))),
            abi.encodeCall(
                IGuaranteeVault.recordGuaranteeReceipt,
                (bytes32(uint256(1)), bytes32(uint256(2)), 1, bytes32(uint256(3)))
            )
        );

        Phase9RecoveryTypes.LossRecord memory loss;
        _requireFrozen(
            address(new RecoveryManager(address(0), address(0), address(0))),
            abi.encodeCall(IRecoveryManager.openLoss, (bytes32(uint256(1)), loss))
        );
    }

    function testPerInstanceAccountInitializerIsFrozen() public {
        Phase9Types.LoanConfiguration memory configuration;
        Phase9Types.DebtState memory initialDebt;
        _requireFrozen(
            address(new Phase9LoanAccount()),
            abi.encodeCall(IPhase9LoanAccount.initialize, (configuration, initialDebt))
        );
    }

    function testReceiptAndHandoffAuthoritiesAreConstructorBound() public {
        address assetRegistry = address(0xA55E7);
        address settlementToken = address(0x70CE1);
        address authorizedManager = address(0xA07);

        LienRegistry liens = new LienRegistry(authorizedManager);
        require(liens.registeredRefinanceCoordinator() == authorizedManager, "lien coordinator");

        GuaranteeVault guarantees =
            new GuaranteeVault(assetRegistry, settlementToken, authorizedManager);
        require(guarantees.assetRegistry() == assetRegistry, "guarantee asset registry");
        require(guarantees.settlementToken() == settlementToken, "guarantee token");
        require(guarantees.authorizedRecoveryManager() == authorizedManager, "guarantee manager");

        RecoveryManager recovery =
            new RecoveryManager(assetRegistry, settlementToken, authorizedManager);
        require(recovery.assetRegistry() == assetRegistry, "recovery asset registry");
        require(recovery.settlementToken() == settlementToken, "recovery token");
        require(recovery.authorizedReceiptManager() == authorizedManager, "recovery manager");
    }

    function _requireFrozen(address target, bytes memory callData) private {
        (bool success, bytes memory result) = target.call(callData);
        require(!success, "mutator succeeded");
        require(result.length == 4 && bytes4(result) == FROZEN, "wrong freeze error");
    }
}
