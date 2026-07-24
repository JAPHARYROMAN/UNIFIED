// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
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
import { VersionedLoanAccount } from "../src/kernel/VersionedLoanAccount.sol";
import { AllocationVault } from "../src/token/AllocationVault.sol";
import { ProtocolFeeRouter } from "../src/token/ProtocolFeeRouter.sol";
import { UFTAllocations } from "../src/token/UFTAllocations.sol";
import { UFTBurner } from "../src/token/UFTBurner.sol";
import { UnifiedToken } from "../src/token/UnifiedToken.sol";
import { VestingPoolVault } from "../src/token/VestingPoolVault.sol";

interface Vm {
    function warp(uint256 timestamp) external;
}

interface ITestPolicy {
    function validate(bytes calldata configuration) external pure returns (bool);
}

contract TestPolicy is IERC165, ITestPolicy {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId || interfaceId == type(ITestPolicy).interfaceId;
    }

    function validate(bytes calldata) external pure returns (bool) {
        return true;
    }
}

contract Phase2KernelTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    RoleManager private roles;
    AllocationVault private community;
    AllocationVault private treasury;
    AllocationVault private staking;
    AllocationVault private insurance;
    AllocationVault private publicDistribution;
    AllocationVault private liquidity;
    VestingPoolVault private contributors;
    VestingPoolVault private investors;
    VestingPoolVault private partners;
    UnifiedToken private uft;

    function setUp() public {
        roles = new RoleManager(address(0xA11CE), address(this));
        _grant(ProtocolRoles.TREASURY_OPERATOR_ROLE, address(this));
        _grant(ProtocolRoles.POLICY_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.ASSET_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.LOAN_FACTORY_ROLE, address(this));
        _grant(ProtocolRoles.SERVICER_ROLE, address(this));
        _grant(ProtocolRoles.PAUSER_ROLE, address(this));
        _grant(ProtocolRoles.RISK_COUNCIL_ROLE, address(this));

        community = new AllocationVault(roles, keccak256("COMMUNITY"), UFTAllocations.COMMUNITY);
        treasury = new AllocationVault(roles, keccak256("TREASURY"), UFTAllocations.TREASURY);
        staking = new AllocationVault(
            roles, keccak256("STAKING_REWARDS"), UFTAllocations.STAKING_REWARDS
        );
        insurance = new AllocationVault(roles, keccak256("INSURANCE"), UFTAllocations.INSURANCE);
        publicDistribution = new AllocationVault(
            roles, keccak256("PUBLIC_DISTRIBUTION"), UFTAllocations.PUBLIC_DISTRIBUTION
        );
        liquidity = new AllocationVault(roles, keccak256("LIQUIDITY"), UFTAllocations.LIQUIDITY);
        contributors = new VestingPoolVault(
            roles, keccak256("CONTRIBUTORS"), UFTAllocations.CONTRIBUTORS, 12, 48
        );
        investors =
            new VestingPoolVault(roles, keccak256("INVESTORS"), UFTAllocations.INVESTORS, 12, 36);
        partners =
            new VestingPoolVault(roles, keccak256("PARTNERS"), UFTAllocations.PARTNERS, 6, 30);

        ProtocolTypes.GenesisDestinations memory destinations = ProtocolTypes.GenesisDestinations({
            community: address(community),
            treasury: address(treasury),
            stakingRewards: address(staking),
            insurance: address(insurance),
            contributors: address(contributors),
            investors: address(investors),
            publicDistribution: address(publicDistribution),
            liquidity: address(liquidity),
            partners: address(partners)
        });
        uft = new UnifiedToken(destinations);

        IUnifiedToken tokenInterface = IUnifiedToken(address(uft));
        community.bindToken(tokenInterface);
        treasury.bindToken(tokenInterface);
        staking.bindToken(tokenInterface);
        insurance.bindToken(tokenInterface);
        publicDistribution.bindToken(tokenInterface);
        liquidity.bindToken(tokenInterface);
        contributors.bindToken(tokenInterface);
        investors.bindToken(tokenInterface);
        partners.bindToken(tokenInterface);
    }

    function testGenesisSupplyAndAllocationConservation() public view {
        require(uft.totalSupply() == UFTAllocations.MAX_SUPPLY, "wrong genesis supply");
        require(uft.balanceOf(address(community)) == UFTAllocations.COMMUNITY, "community");
        require(uft.balanceOf(address(treasury)) == UFTAllocations.TREASURY, "treasury");
        require(uft.balanceOf(address(staking)) == UFTAllocations.STAKING_REWARDS, "staking");
        require(uft.balanceOf(address(insurance)) == UFTAllocations.INSURANCE, "insurance");
        require(uft.balanceOf(address(contributors)) == UFTAllocations.CONTRIBUTORS, "contributors");
        require(uft.balanceOf(address(investors)) == UFTAllocations.INVESTORS, "investors");
        require(
            uft.balanceOf(address(publicDistribution)) == UFTAllocations.PUBLIC_DISTRIBUTION,
            "public"
        );
        require(uft.balanceOf(address(liquidity)) == UFTAllocations.LIQUIDITY, "liquidity");
        require(uft.balanceOf(address(partners)) == UFTAllocations.PARTNERS, "partners");
    }

    function testGenesisDestinationsMustBeDistinct() public {
        ProtocolTypes.GenesisDestinations memory destinations = ProtocolTypes.GenesisDestinations({
            community: address(0x3001),
            treasury: address(0x3001),
            stakingRewards: address(0x3003),
            insurance: address(0x3004),
            contributors: address(0x3005),
            investors: address(0x3006),
            publicDistribution: address(0x3007),
            liquidity: address(0x3008),
            partners: address(0x3009)
        });
        try new UnifiedToken(destinations) {
            revert("duplicate destination accepted");
        } catch { }
    }

    function testBurnIsIrreversibleAndNoMintSelectorExists() public {
        community.release(address(this), 1_000 ether, keccak256("TEST_RELEASE"));
        uint256 priorSupply = uft.totalSupply();
        uft.burn(400 ether);
        require(uft.totalSupply() == priorSupply - 400 ether, "burn not reflected");

        (bool success,) =
            address(uft).call(abi.encodeWithSignature("mint(address,uint256)", this, 1));
        require(!success, "mint surface exists");
    }

    function testContributorVestingHonorsCliffAndMonthlyRelease() public {
        uint64 start = uint64(block.timestamp);
        bytes32 grantId = keccak256("CONTRIBUTOR_GRANT");
        contributors.createGrant(grantId, address(0xBEEF), 48_000 ether, start, true);
        vm.warp(uint256(start) + 11 * contributors.MONTH());
        require(contributors.vestedAmount(grantId, uint64(block.timestamp)) == 0, "early");
        vm.warp(uint256(start) + 12 * contributors.MONTH());
        require(
            contributors.vestedAmount(grantId, uint64(block.timestamp)) == 12_000 ether,
            "cliff amount"
        );
        contributors.release(grantId);
        require(uft.balanceOf(address(0xBEEF)) == 12_000 ether, "release amount");
    }

    function testEmergencyPauseIsScopedAndCannotBlockRepayment() public {
        EmergencyController emergency = new EmergencyController(roles);
        bytes32 capability = keccak256("CAPABILITY_NEW_LOANS");
        uint64 expiry = uint64(block.timestamp + 1 days);
        emergency.pauseCapability(capability, expiry, keccak256("INCIDENT"));
        (bool active,,) = emergency.emergencyState(capability);
        require(active, "pause inactive");

        (bool success,) = address(emergency)
            .call(
                abi.encodeCall(
                    emergency.pauseCapability,
                    (
                        emergency.CAPABILITY_REPAYMENT(),
                        uint64(block.timestamp + 1 hours),
                        keccak256("BAD_PAUSE")
                    )
                )
            );
        require(!success, "repayment pause allowed");
        vm.warp(expiry + 1);
        (active,,) = emergency.emergencyState(capability);
        require(!active, "pause did not expire");
        emergency.clearExpiredAction(capability);
    }

    function testAdministrativeAndGovernanceAuthoritiesMustBeSeparated() public {
        try new RoleManager(address(this), address(this)) {
            revert("same authority accepted");
        } catch { }
        require(
            roles.hasRole(ProtocolRoles.DEFAULT_ADMIN_ROLE, address(0xA11CE)), "admin role missing"
        );
        require(
            !roles.hasRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE, address(0xA11CE)),
            "admin also governs"
        );
    }

    function testPolicyVersionsAreImmutableAndDeprecationIsProspective() public {
        PolicyRegistry registry = new PolicyRegistry(roles);
        TestPolicy implementation = new TestPolicy();
        bytes32 codeHash;
        address implementationAddress = address(implementation);
        assembly ("memory-safe") {
            codeHash := extcodehash(implementationAddress)
        }
        ProtocolTypes.PolicyRef memory policy = ProtocolTypes.PolicyRef({
            policyId: keccak256("INTEREST_POLICY"),
            implementation: implementationAddress,
            major: 1,
            minor: 0,
            patch: 0,
            interfaceId: type(ITestPolicy).interfaceId,
            configurationSchemaHash: keccak256("schema:v1")
        });
        registry.registerPolicy(policy, codeHash);
        require(registry.isApproved(policy), "policy not approved");

        (bool duplicateAccepted,) =
            address(registry).call(abi.encodeCall(registry.registerPolicy, (policy, codeHash)));
        require(!duplicateAccepted, "policy version overwritten");
        registry.deprecatePolicy(policy.policyId, 1, 0, 0);
        require(!registry.isApproved(policy), "deprecated policy approved");
        require(
            registry.resolvePolicy(policy.policyId, 1, 0, 0).implementation
                == implementationAddress,
            "historical policy lost"
        );

        policy.minor = 1;
        uint64 activationTime = uint64(block.timestamp + 1 days);
        registry.registerPolicyWithActivation(policy, codeHash, activationTime);
        require(!registry.isApproved(policy), "future policy approved early");
        vm.warp(activationTime);
        require(registry.isApproved(policy), "scheduled policy did not activate");
    }

    function testLoanIdentityIsDeterministicUniqueAndTerminal() public {
        LoanRegistry registry = new LoanRegistry(roles);
        LoanFactory factory = new LoanFactory(roles, registry);
        VersionedLoanAccount implementation = new VersionedLoanAccount();
        _grant(ProtocolRoles.LOAN_FACTORY_ROLE, address(factory));
        factory.registerImplementation(1, address(implementation));

        bytes32 loanId = keccak256("LOAN-1");
        address predicted = factory.predictLoanAddress(loanId, 1);
        address account = factory.createLoan(loanId, address(0xCAFE), keccak256("AGREEMENT"), 1);
        require(account == predicted, "address not deterministic");
        require(registry.loanAccount(loanId) == account, "registry mismatch");

        (bool duplicateAccepted,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.createLoan, (loanId, address(0xCAFE), keccak256("AGREEMENT"), uint32(1))
                )
            );
        require(!duplicateAccepted, "duplicate loan accepted");
        registry.markTerminal(loanId);
        require(registry.isTerminal(loanId), "terminal flag missing");
        (bool reopened,) = address(registry).call(abi.encodeCall(registry.markTerminal, (loanId)));
        require(!reopened, "terminal transition repeated");
    }

    function testFeeRouterConservesRevenueAndSuspendsBurnOnReserveDeficiency() public {
        bytes32 assetId = keccak256("ASSET:UFT");
        AssetRegistry assets = new AssetRegistry(roles);
        assets.registerAsset(assetId, address(uft), 18, keccak256("UFT_METADATA"));
        UFTBurner burner = new UFTBurner(roles, IUnifiedToken(address(uft)), assetId);
        address[6] memory receivers = [
            address(0x1001),
            address(0x1002),
            address(0x1003),
            address(0x1004),
            address(0x1005),
            address(0x1006)
        ];
        ProtocolFeeRouter router = new ProtocolFeeRouter(
            roles,
            assets,
            IUnifiedToken(address(uft)),
            IUFTBurner(address(burner)),
            assetId,
            receivers
        );
        _grant(ProtocolRoles.TREASURY_OPERATOR_ROLE, address(router));

        community.release(address(this), 20_000 ether, keccak256("ROUTER_TEST"));
        uft.approve(address(router), 20_000 ether);
        router.collectFee(keccak256("LOAN_FEES"), assetId, 10_000 ether, keccak256("JOURNAL-1"));
        uint256 supplyBefore = uft.totalSupply();
        router.distribute(assetId, 10_000 ether);
        require(uft.balanceOf(receivers[0]) == 3_000 ether, "insurance split");
        require(uft.balanceOf(receivers[1]) == 2_500 ether, "staker split");
        require(uft.balanceOf(receivers[2]) == 2_500 ether, "treasury split");
        require(uft.balanceOf(receivers[4]) == 500 ether, "liquidity split");
        require(uft.balanceOf(receivers[5]) == 500 ether, "public goods split");
        require(uft.totalSupply() == supplyBefore - 1_000 ether, "burn split");

        router.setReserveDeficient(true, keccak256("RESERVE_EVIDENCE"));
        router.collectFee(keccak256("LOAN_FEES"), assetId, 10_000 ether, keccak256("JOURNAL-2"));
        supplyBefore = uft.totalSupply();
        router.distribute(assetId, 10_000 ether);
        require(uft.totalSupply() == supplyBefore, "burn not suspended");
        require(uft.balanceOf(receivers[3]) == 1_000 ether, "burn reserve");
    }

    function _grant(bytes32 role, address account) private {
        roles.grantRole(role, account, type(uint64).max);
    }
}
