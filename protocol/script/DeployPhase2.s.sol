// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IUnifiedToken } from "../src/interfaces/IUnifiedToken.sol";
import { IUFTBurner } from "../src/interfaces/IUFTBurner.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { LoanFactory } from "../src/kernel/LoanFactory.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { ProtocolTypes } from "../src/kernel/ProtocolTypes.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { UnifiedProtocol } from "../src/kernel/UnifiedProtocol.sol";
import { VersionedLoanAccount } from "../src/kernel/VersionedLoanAccount.sol";
import { AllocationVault } from "../src/token/AllocationVault.sol";
import { ProtocolFeeRouter } from "../src/token/ProtocolFeeRouter.sol";
import { UFTAllocations } from "../src/token/UFTAllocations.sol";
import { UFTBurner } from "../src/token/UFTBurner.sol";
import { UnifiedToken } from "../src/token/UnifiedToken.sol";
import { VestingPoolVault } from "../src/token/VestingPoolVault.sol";

interface DeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Reproducible local/testnet deployment. Never embed or accept private keys here.
contract DeployPhase2 {
    DeploymentVm private constant vm =
        DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        RoleManager roles;
        UnifiedToken uft;
        AssetRegistry assets;
        PolicyRegistry policies;
        LoanRegistry loans;
        LoanFactory loanFactory;
        EmergencyController emergency;
        UFTBurner burner;
        ProtocolFeeRouter feeRouter;
        UnifiedProtocol protocol;
    }

    bytes32 public constant UFT_ASSET_ID = keccak256("ASSET:UFT");
    uint64 public constant OPERATOR_ROLE_DURATION = 30 days;

    function run(
        address administrator,
        address governance,
        address[7] calldata operators,
        address[6] calldata receivers
    ) external returns (Deployment memory deployment) {
        require(administrator != address(0) && governance != address(0), "invalid authority");
        require(administrator != governance, "authority separation required");
        _validateOperators(administrator, governance, operators);
        _validateReceivers(receivers);
        vm.startBroadcast();

        deployment.roles = new RoleManager(administrator, governance);

        ProtocolTypes.GenesisDestinations memory destinations =
            _deployGenesisVaults(deployment.roles);
        deployment.uft = new UnifiedToken(destinations);
        _bindGenesisVaults(destinations, IUnifiedToken(address(deployment.uft)));

        deployment.assets = new AssetRegistry(deployment.roles);
        deployment.policies = new PolicyRegistry(deployment.roles);
        deployment.loans = new LoanRegistry(deployment.roles);
        deployment.loanFactory = new LoanFactory(deployment.roles, deployment.loans);
        deployment.emergency = new EmergencyController(deployment.roles);

        deployment.roles
            .grantRole(
                ProtocolRoles.LOAN_FACTORY_ROLE, address(deployment.loanFactory), type(uint64).max
            );
        VersionedLoanAccount loanImplementation = new VersionedLoanAccount();
        deployment.loanFactory.registerImplementation(1, address(loanImplementation));
        deployment.roles.grantRole(ProtocolRoles.ASSET_REGISTRAR_ROLE, governance, type(uint64).max);
        deployment.assets
            .registerAsset(UFT_ASSET_ID, address(deployment.uft), 18, keccak256("UFT_METADATA_V1"));
        deployment.roles.revokeRole(ProtocolRoles.ASSET_REGISTRAR_ROLE, governance);

        deployment.burner =
            new UFTBurner(deployment.roles, IUnifiedToken(address(deployment.uft)), UFT_ASSET_ID);
        deployment.feeRouter = new ProtocolFeeRouter(
            deployment.roles,
            deployment.assets,
            IUnifiedToken(address(deployment.uft)),
            IUFTBurner(address(deployment.burner)),
            UFT_ASSET_ID,
            receivers
        );
        deployment.roles
            .grantRole(
                ProtocolRoles.TREASURY_OPERATOR_ROLE,
                address(deployment.feeRouter),
                type(uint64).max
            );
        deployment.protocol = new UnifiedProtocol(
            1,
            address(deployment.loans),
            address(deployment.policies),
            address(deployment.assets),
            address(deployment.roles),
            address(deployment.emergency),
            address(deployment.feeRouter),
            receivers[2],
            keccak256(abi.encode("LOCAL_EVM", block.chainid))
        );
        _grantOperationalRoles(deployment.roles, operators);
        _assertAuthoritySeparation(deployment.roles, administrator, governance);

        vm.stopBroadcast();
    }

    function _grantOperationalRoles(RoleManager roles, address[7] calldata operators) private {
        uint64 expiry = uint64(block.timestamp + OPERATOR_ROLE_DURATION);
        roles.grantRole(ProtocolRoles.POLICY_REGISTRAR_ROLE, operators[0], expiry);
        roles.grantRole(ProtocolRoles.ASSET_REGISTRAR_ROLE, operators[1], expiry);
        roles.grantRole(ProtocolRoles.LOAN_FACTORY_ROLE, operators[2], expiry);
        roles.grantRole(ProtocolRoles.SERVICER_ROLE, operators[3], expiry);
        roles.grantRole(ProtocolRoles.TREASURY_OPERATOR_ROLE, operators[4], expiry);
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, operators[5], expiry);
        roles.grantRole(ProtocolRoles.PAUSER_ROLE, operators[6], expiry);
    }

    function _validateOperators(
        address administrator,
        address governance,
        address[7] calldata operators
    ) private pure {
        for (uint256 index = 0; index < operators.length; ++index) {
            require(
                operators[index] != address(0) && operators[index] != administrator
                    && operators[index] != governance,
                "operator conflicts with authority"
            );
            for (uint256 prior = 0; prior < index; ++prior) {
                require(operators[index] != operators[prior], "operators must be distinct");
            }
        }
    }

    function _validateReceivers(address[6] calldata receivers) private pure {
        for (uint256 index = 0; index < receivers.length; ++index) {
            require(receivers[index] != address(0), "receiver is zero");
            for (uint256 prior = 0; prior < index; ++prior) {
                require(receivers[index] != receivers[prior], "receivers must be distinct");
            }
        }
    }

    function _assertAuthoritySeparation(
        RoleManager roles,
        address administrator,
        address governance
    ) private view {
        bytes32[7] memory operationalRoles = [
            ProtocolRoles.POLICY_REGISTRAR_ROLE,
            ProtocolRoles.ASSET_REGISTRAR_ROLE,
            ProtocolRoles.LOAN_FACTORY_ROLE,
            ProtocolRoles.SERVICER_ROLE,
            ProtocolRoles.TREASURY_OPERATOR_ROLE,
            ProtocolRoles.RISK_COUNCIL_ROLE,
            ProtocolRoles.PAUSER_ROLE
        ];
        for (uint256 index = 0; index < operationalRoles.length; ++index) {
            require(!roles.hasRole(operationalRoles[index], administrator), "admin is operator");
            require(!roles.hasRole(operationalRoles[index], governance), "governance is operator");
        }
    }

    function _deployGenesisVaults(RoleManager roles)
        private
        returns (ProtocolTypes.GenesisDestinations memory destinations)
    {
        destinations.community = address(
            new AllocationVault(roles, keccak256("COMMUNITY"), UFTAllocations.COMMUNITY)
        );
        destinations.treasury =
            address(new AllocationVault(roles, keccak256("TREASURY"), UFTAllocations.TREASURY));
        destinations.stakingRewards = address(
            new AllocationVault(roles, keccak256("STAKING_REWARDS"), UFTAllocations.STAKING_REWARDS)
        );
        destinations.insurance =
            address(new AllocationVault(roles, keccak256("INSURANCE"), UFTAllocations.INSURANCE));
        destinations.contributors = address(
            new VestingPoolVault(
                roles, keccak256("CONTRIBUTORS"), UFTAllocations.CONTRIBUTORS, 12, 48
            )
        );
        destinations.investors = address(
            new VestingPoolVault(roles, keccak256("INVESTORS"), UFTAllocations.INVESTORS, 12, 36)
        );
        destinations.publicDistribution = address(
            new AllocationVault(
                roles, keccak256("PUBLIC_DISTRIBUTION"), UFTAllocations.PUBLIC_DISTRIBUTION
            )
        );
        destinations.liquidity =
            address(new AllocationVault(roles, keccak256("LIQUIDITY"), UFTAllocations.LIQUIDITY));
        destinations.partners = address(
            new VestingPoolVault(roles, keccak256("PARTNERS"), UFTAllocations.PARTNERS, 6, 30)
        );
    }

    function _bindGenesisVaults(
        ProtocolTypes.GenesisDestinations memory destinations,
        IUnifiedToken token
    ) private {
        AllocationVault(destinations.community).bindToken(token);
        AllocationVault(destinations.treasury).bindToken(token);
        AllocationVault(destinations.stakingRewards).bindToken(token);
        AllocationVault(destinations.insurance).bindToken(token);
        VestingPoolVault(destinations.contributors).bindToken(token);
        VestingPoolVault(destinations.investors).bindToken(token);
        AllocationVault(destinations.publicDistribution).bindToken(token);
        AllocationVault(destinations.liquidity).bindToken(token);
        VestingPoolVault(destinations.partners).bindToken(token);
    }
}
