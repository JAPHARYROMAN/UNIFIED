// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import {
    IMatureExternalSettlementPolicy
} from "../src/interfaces/IMatureExternalSettlementPolicy.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolTypes } from "../src/kernel/ProtocolTypes.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import {
    CanonicalExternalSettlementGateway
} from "../src/payment/CanonicalExternalSettlementGateway.sol";
import {
    FixedMatureExternalSettlementPolicy
} from "../src/payment/FixedMatureExternalSettlementPolicy.sol";

interface Phase7CDeploymentVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the local-only Phase 7C mature policy and exact-token gateway.
contract DeployPhase7C {
    Phase7CDeploymentVm private constant vm =
        Phase7CDeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        FixedMatureExternalSettlementPolicy maturePolicy;
        CanonicalExternalSettlementGateway gateway;
        ProtocolTypes.PolicyRef policyRef;
    }

    struct Configuration {
        address approvedLoanFactory;
        uint32 approvedProtocolVersion;
        bytes32 policyId;
        bytes32 configurationSchemaHash;
        bytes32 sourceAssetId;
        bytes32 targetAssetId;
        bytes32 conversionPolicyHash;
        bytes32 finalityPolicyHash;
        uint64 minimumReversalDelay;
    }

    function run(
        RoleManager roles,
        ILoanRegistry loans,
        AssetRegistry assets,
        PolicyRegistry policies,
        EmergencyController emergency,
        Configuration calldata configuration
    ) external returns (Deployment memory deployment) {
        require(
            address(roles).code.length != 0 && address(loans).code.length != 0
                && address(assets).code.length != 0 && address(policies).code.length != 0
                && address(emergency).code.length != 0
                && configuration.approvedLoanFactory.code.length != 0
                && configuration.approvedProtocolVersion != 0
                && configuration.policyId != bytes32(0)
                && configuration.configurationSchemaHash != bytes32(0),
            "invalid phase 7c attachment"
        );
        vm.startBroadcast();
        deployment.maturePolicy = new FixedMatureExternalSettlementPolicy(
            configuration.sourceAssetId,
            configuration.targetAssetId,
            configuration.conversionPolicyHash,
            configuration.finalityPolicyHash,
            configuration.minimumReversalDelay
        );
        deployment.policyRef = ProtocolTypes.PolicyRef({
            policyId: configuration.policyId,
            implementation: address(deployment.maturePolicy),
            major: 1,
            minor: 0,
            patch: 0,
            interfaceId: type(IMatureExternalSettlementPolicy).interfaceId,
            configurationSchemaHash: configuration.configurationSchemaHash
        });
        policies.registerPolicy(deployment.policyRef, _codeHash(address(deployment.maturePolicy)));
        deployment.gateway = new CanonicalExternalSettlementGateway(
            roles,
            loans,
            assets,
            policies,
            emergency,
            configuration.approvedLoanFactory,
            configuration.approvedProtocolVersion
        );
        vm.stopBroadcast();

        ProtocolTypes.PolicyRef memory registered =
            policies.resolvePolicy(configuration.policyId, 1, 0, 0);
        require(
            registered.implementation == address(deployment.maturePolicy)
                && address(deployment.gateway).code.length != 0,
            "phase 7c deployment incomplete"
        );
    }

    function _codeHash(address target) private view returns (bytes32 codeHash) {
        assembly ("memory-safe") {
            codeHash := extcodehash(target)
        }
    }
}
