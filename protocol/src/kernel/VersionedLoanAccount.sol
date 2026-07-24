// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Phase 2 immutable identity shell. Servicing behavior is deliberately absent.
contract VersionedLoanAccount {
    error AlreadyInitialized();
    error InvalidLoan();

    bytes32 public loanId;
    address public borrower;
    bytes32 public agreementHash;
    uint32 public protocolVersion;
    address public factory;
    bool private _initialized;

    event LoanAccountInitialized(
        bytes32 indexed loanId,
        address indexed borrower,
        bytes32 indexed agreementHash,
        uint32 protocolVersion
    );

    function initialize(
        bytes32 loanId_,
        address borrower_,
        bytes32 agreementHash_,
        uint32 protocolVersion_
    ) external {
        if (_initialized) revert AlreadyInitialized();
        if (
            loanId_ == bytes32(0) || borrower_ == address(0) || agreementHash_ == bytes32(0)
                || protocolVersion_ == 0
        ) {
            revert InvalidLoan();
        }
        _initialized = true;
        factory = msg.sender;
        loanId = loanId_;
        borrower = borrower_;
        agreementHash = agreementHash_;
        protocolVersion = protocolVersion_;
        emit LoanAccountInitialized(loanId_, borrower_, agreementHash_, protocolVersion_);
    }

    function initialized() external view returns (bool) {
        return _initialized;
    }
}
