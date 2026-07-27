// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";

interface Phase9RefinancePrerequisiteVm {
    function serializeAddress(string calldata objectKey, string calldata valueKey, address value)
        external
        returns (string memory json);
    function serializeUint(string calldata objectKey, string calldata valueKey, uint256 value)
        external
        returns (string memory json);
    function startBroadcast(address broadcaster) external;
    function stopBroadcast() external;
    function writeJson(string calldata json, string calldata path) external;
}

/// @notice Deploys synthetic prerequisites from an account distinct from the topology broadcaster.
/// @dev RoleManager grants only its setup administrator and governance executor in construction.
///      The script grants no role to the candidate and performs no post-construction role, setup,
///      or business call.
contract PreparePhase9RefinanceLocal {
    error InvalidLocalChain(uint256 chainId);
    error InvalidFixtureConfiguration();

    Phase9RefinancePrerequisiteVm private constant vm =
        Phase9RefinancePrerequisiteVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(
        address setupBroadcaster,
        address candidateBroadcaster,
        address governanceExecutor,
        address fixtureAllocator,
        string calldata configurationPath
    ) external {
        if (block.chainid != 31_337) {
            revert InvalidLocalChain(block.chainid);
        }
        if (
            setupBroadcaster == address(0) || candidateBroadcaster == address(0)
                || governanceExecutor == address(0) || fixtureAllocator == address(0)
                || setupBroadcaster == candidateBroadcaster
                || candidateBroadcaster == governanceExecutor
                || candidateBroadcaster == fixtureAllocator
                || setupBroadcaster == governanceExecutor || bytes(configurationPath).length == 0
        ) revert InvalidFixtureConfiguration();

        vm.startBroadcast(setupBroadcaster);
        RoleManager roleManager = new RoleManager(setupBroadcaster, governanceExecutor);
        LoanRegistry loanRegistry = new LoanRegistry(roleManager);
        PolicyRegistry policyRegistry = new PolicyRegistry(roleManager);
        AssetRegistry assetRegistry = new AssetRegistry(roleManager);
        EmergencyController emergencyController = new EmergencyController(roleManager);
        Phase9LocalSyntheticToken settlementToken = new Phase9LocalSyntheticToken(fixtureAllocator);
        vm.stopBroadcast();

        string memory key = "phase9_refinance_local_configuration";
        vm.serializeAddress(key, "loan_registry", address(loanRegistry));
        vm.serializeAddress(key, "role_manager", address(roleManager));
        vm.serializeAddress(key, "settlement_token", address(settlementToken));
        vm.serializeAddress(key, "quote_policy_registry", address(policyRegistry));
        vm.serializeAddress(key, "refinance_policy_registry", address(policyRegistry));
        vm.serializeAddress(key, "amendment_policy_registry", address(policyRegistry));
        vm.serializeAddress(key, "protection_policy_registry", address(policyRegistry));
        vm.serializeAddress(key, "recovery_policy_registry", address(policyRegistry));
        vm.serializeAddress(key, "asset_registry", address(assetRegistry));
        vm.serializeAddress(key, "emergency_controller", address(emergencyController));
        vm.serializeAddress(key, "treasury_fee_recipient", fixtureAllocator);
        string memory json = vm.serializeUint(key, "maximum_quote_validity", 1 hours);
        vm.writeJson(json, configurationPath);
    }
}
