// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library UnderwrittenTypes {
    struct ActivationAuthorization {
        bytes32 decisionId;
        bytes32 productHash;
        bytes32 consentEvidenceHash;
        bytes32 journalRef;
    }
}
