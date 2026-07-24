// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { ProtocolRoles } from "./ProtocolRoles.sol";
import { RoleControlled } from "./RoleControlled.sol";
import { VersionedLoanAccount } from "./VersionedLoanAccount.sol";

/// @notice Deterministic loan identity factory with append-only implementation versions.
contract LoanFactory is RoleControlled {
    error InvalidImplementation();
    error ImplementationVersionAlreadyRegistered(uint32 version);
    error UnknownImplementationVersion(uint32 version);
    error InvalidLoan();

    ILoanRegistry public immutable loanRegistry;
    mapping(uint32 version => address implementation) public implementationForVersion;

    event ImplementationVersionRegistered(
        uint32 indexed version, address indexed implementation, bytes32 indexed codeHash
    );
    event LoanCreated(
        bytes32 indexed loanId,
        address indexed loanAccount,
        address indexed borrower,
        bytes32 agreementHash,
        uint32 implementationVersion
    );

    constructor(IRoleManager roleManager_, ILoanRegistry loanRegistry_)
        RoleControlled(roleManager_)
    {
        require(address(loanRegistry_) != address(0), "loan registry is zero");
        loanRegistry = loanRegistry_;
    }

    function registerImplementation(uint32 version, address implementation)
        external
        onlyRole(ProtocolRoles.GOVERNANCE_EXECUTOR_ROLE)
    {
        if (version == 0 || implementation.code.length == 0) {
            revert InvalidImplementation();
        }
        if (implementationForVersion[version] != address(0)) {
            revert ImplementationVersionAlreadyRegistered(version);
        }
        implementationForVersion[version] = implementation;
        bytes32 codeHash;
        assembly ("memory-safe") {
            codeHash := extcodehash(implementation)
        }
        emit ImplementationVersionRegistered(version, implementation, codeHash);
    }

    function createLoan(
        bytes32 loanId,
        address borrower,
        bytes32 agreementHash,
        uint32 implementationVersion
    ) external onlyRole(ProtocolRoles.LOAN_FACTORY_ROLE) returns (address loanAccount) {
        if (
            loanId == bytes32(0) || borrower == address(0) || agreementHash == bytes32(0)
                || loanRegistry.exists(loanId)
        ) {
            revert InvalidLoan();
        }
        address implementation = implementationForVersion[implementationVersion];
        if (implementation == address(0)) {
            revert UnknownImplementationVersion(implementationVersion);
        }
        loanAccount = Clones.cloneDeterministic(implementation, loanId);
        VersionedLoanAccount(loanAccount)
            .initialize(loanId, borrower, agreementHash, implementationVersion);
        loanRegistry.registerLoan(
            loanId, loanAccount, borrower, agreementHash, implementationVersion
        );
        emit LoanCreated(loanId, loanAccount, borrower, agreementHash, implementationVersion);
    }

    function predictLoanAddress(bytes32 loanId, uint32 implementationVersion)
        external
        view
        returns (address)
    {
        address implementation = implementationForVersion[implementationVersion];
        if (implementation == address(0)) {
            revert UnknownImplementationVersion(implementationVersion);
        }
        return Clones.predictDeterministicAddress(implementation, loanId, address(this));
    }
}
