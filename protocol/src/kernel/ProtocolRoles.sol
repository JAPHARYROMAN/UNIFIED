// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library ProtocolRoles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant GOVERNANCE_EXECUTOR_ROLE = keccak256("GOVERNANCE_EXECUTOR_ROLE");
    bytes32 internal constant POLICY_REGISTRAR_ROLE = keccak256("POLICY_REGISTRAR_ROLE");
    bytes32 internal constant ASSET_REGISTRAR_ROLE = keccak256("ASSET_REGISTRAR_ROLE");
    bytes32 internal constant LOAN_FACTORY_ROLE = keccak256("LOAN_FACTORY_ROLE");
    bytes32 internal constant SERVICER_ROLE = keccak256("SERVICER_ROLE");
    bytes32 internal constant PAYMENT_FINALIZER_ROLE = keccak256("PAYMENT_FINALIZER_ROLE");
    bytes32 internal constant ACCOUNTING_ATTESTER_ROLE = keccak256("ACCOUNTING_ATTESTER_ROLE");
    bytes32 internal constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 internal constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");
    bytes32 internal constant TREASURY_OPERATOR_ROLE = keccak256("TREASURY_OPERATOR_ROLE");
    bytes32 internal constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE");
    bytes32 internal constant EMERGENCY_COUNCIL_ROLE = keccak256("EMERGENCY_COUNCIL_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
}
