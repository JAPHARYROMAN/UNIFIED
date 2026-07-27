// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Normalized UNI-REFI-001/UNI-REFI-002 acceptance-to-evidence map.
/// @dev D1 rows name their Solidity evidence. Later-state rows remain explicitly
/// assigned to D2-D4 suites and cannot be treated as passing D1 evidence.
library Phase9RefinanceBootstrapAcceptanceMap {
    // P9R-COMPAT-001 => external historical ABI/storage compatibility gate
    // P9R-COMPAT-002 => external additive ABI allowlist gate
    // P9R-COMPAT-003 => external frozen-source and storage-layout gate
    // P9R-CHECK-001 => external method-level activation checkpoint gate
    // P9R-CHECK-002 => external bundled backlog/evidence closure gate
    // P9R-RISK-001 => external risk and assumption register gate
    // P9R-DEPLOY-001 => D4 local deployment evidence suite
    // P9R-DEPLOY-002 => D4 reciprocal deployment binding suite
    // P9R-DEPLOY-003 => D4 deployment receipt/runtime/storage suite
    // P9R-DEPLOY-004 => D4 prohibited deployment and reset suite
    // P9R-BOOT-001 => Phase9RefinanceFactoryBootstrapTest.BOOT001
    // P9R-BOOT-002 => Phase9RefinanceFactoryBootstrapTest.BOOT002
    // P9R-BOOT-003 => Phase9RefinanceFactoryBootstrapTest.BOOT003
    // P9R-BOOT-004 => Phase9RefinanceFactoryBootstrapTest.BOOT004
    // P9R-BOOT-005 => Phase9RefinanceFactoryBootstrapTest.BOOT005
    // P9R-AUTH-001 => Phase9RefinanceRequestTest.AUTH001
    // P9R-AUTH-002 => D2 funding authorization suite
    // P9R-AUTH-003 => D3 execution authorization suite
    // P9R-AUTH-004 => D3 cancellation authorization suite
    // P9R-AUTH-005 => D3 expiry authorization suite
    // P9R-AUTH-006 => D3 refund authorization suite
    // P9R-AUTH-007 => D2-D3 capability isolation suite
    // P9R-AUTH-008 => Phase9RefinanceRequestTest.AUTH008
    // P9R-ID-001 => Phase9RefinanceRequestGoldenTest.ID001
    // P9R-ID-002 => Phase9RefinanceRequestGoldenTest.ID002
    // P9R-ID-003 => Phase9RefinanceRequestTest.ID003
    // P9R-ID-004 => external Protobuf boundary suite
    // P9R-ID-005 => Phase9RefinanceRequestTest.ID005
    // P9R-ID-006 => Phase9RefinanceRequestTest.ID006
    // P9R-SRC-001 => Phase9RefinanceFactoryBootstrapTest.SRC001
    // P9R-SRC-002 => Phase9RefinanceFactoryBootstrapTest.SRC002
    // P9R-SRC-003 => Phase9RefinanceCustodyLienBootstrapTest.SRC003
    // P9R-SRC-004 => Phase9RefinanceRequestTest.SRC004
    // P9R-SRC-005 => Phase9RefinanceCustodyLienBootstrapTest.SRC005
    // P9R-SRC-006 => D3 execution canonical-source suite
    // P9R-STATE-001 => Phase9RefinanceRequestTest.STATE001
    // P9R-STATE-002 => D2-D3 state and tagged-lock suite
    // P9R-STATE-003 => D2-D3 unreachable-state suite
    // P9R-STATE-004 => D3 execution rollback suite
    // P9R-VIEW-001 => D2-D3 typed unknown/view suite
    // P9R-FUND-001 => D2 funding derived-field suite
    // P9R-FUND-002 => D2 exact partial-funding suite
    // P9R-FUND-003 => D2 funding identity/replay suite
    // P9R-FUND-004 => D2 exact token-delta suite
    // P9R-FUND-005 => D2 commitment allocation suite
    // P9R-EXEC-001 => D3 execution readiness suite
    // P9R-EXEC-002 => D3 execution equation suite
    // P9R-EXEC-003 => D3 atomic call-order suite
    // P9R-EXEC-004 => D3 recipient balance-delta suite
    // P9R-EXEC-005 => D3 old-debt terminality suite
    // P9R-EXEC-006 => D3 sorted lien-handoff suite
    // P9R-EXEC-007 => D3 replacement activation suite
    // P9R-EXEC-008 => D3 dependency rollback suite
    // P9R-EXEC-009 => D3 terminal execution replay suite
    // P9R-EXIT-001 => D3 cancel/expiry invalidation suite
    // P9R-EXIT-002 => D3 refundable lock-retention suite
    // P9R-EXIT-003 => D3 ordered refund suite
    // P9R-EXIT-004 => D3 final refund completion suite
    // P9R-EXIT-005 => D3 incompatible terminal edge suite
    // P9R-RPL-001 => Phase9RefinanceFactoryBootstrapTest.RPL001
    // P9R-RPL-002 => D3 replacement activation suite
    // P9R-RPL-003 => D3 replacement zero-component suite
    // P9R-RPL-004 => D2-D3 commitment-position bijection suite
    // P9R-TIME-001 => D1 request plus D2-D3 deadline boundary suites
    // P9R-FAIL-001 => Phase9RefinanceFactoryBootstrapTest.FAIL001
    // P9R-FAIL-002 => Phase9RefinanceRequestTest.FAIL002
    // P9R-FAIL-003 => Phase9RefinanceRequestFuzzTest.FAIL003
    // P9R-FAIL-004 => Phase9RefinanceRequestInvariants.FAIL004
    // P9R-DON-001 => D2 donation isolation suite
    // P9R-DON-002 => D3 execution/refund donation isolation suite
    // P9R-DON-003 => external authority/sweep scan
    // P9R-DON-004 => D4 bounded reset evidence
    // P9R-EVT-001 => Phase9RefinanceRequestGoldenTest.EVT001 plus D2-D3 events
    // P9R-EVT-002 => Phase9RefinanceRequestTest.EVT002 plus D2-D3 replay
    // P9R-EVT-003 => D2-D3 cross-language event reconstruction
    // P9R-INV-001 => Phase9RefinanceRequestInvariants.INV001 plus D2-D3 handler
    // P9R-FZ-001 => external ABI/storage/compiler/source checkpoint gate
    // P9R-LOCAL-001 => external dependency/key/provider boundary scan
    // P9R-LOCAL-002 => D4 clean-checkout local flow and reset
    // P9R-LOCAL-003 => external non-production evidence boundary gate
}
