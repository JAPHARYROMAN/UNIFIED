// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Normalized UNI-PAYOFF-001 acceptance-to-evidence map.
/// @dev Exactly one entry is retained for every mandatory ADR 0020 acceptance ID.
/// `external` means the gate is intentionally owned by deployment/tooling/model evidence,
/// not that a Solidity test silently claims it.
library Phase9PayoffQuoteAcceptanceMap {
    // P9Q-CFG-001 => Phase9PayoffQuoteAuthorizationAndInputTest.CFG001
    // P9Q-CFG-002 => Phase9PayoffQuoteAuthorizationAndInputTest.CFG002_POL002
    // P9Q-DEPLOY-001 => Phase9PayoffQuoteDeploymentTest.DEPLOY001
    // P9Q-DEPLOY-002 => Phase9PayoffQuoteDeploymentTest.DEPLOY002
    // P9Q-DEPLOY-003 => Phase9PayoffQuoteDeploymentTest.DEPLOY003
    // P9Q-DEPLOY-004 => Phase9PayoffQuoteDeploymentTest.DEPLOY004
    // P9Q-DEPLOY-005 => external DeployPhase9Local evidence rejection/reset gate
    // P9Q-AUTH-001 => Phase9PayoffQuoteAuthorizationAndInputTest.AUTH001_AUTH002
    // P9Q-AUTH-002 => Phase9PayoffQuoteAuthorizationAndInputTest.AUTH002_AllNamed
    // P9Q-SRC-001 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC001_SRC002
    // P9Q-SRC-002 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC001_SRC002
    // P9Q-SRC-003 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC003_SRC004_SRC005
    // P9Q-SRC-004 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC004_EveryField
    // P9Q-SRC-005 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC005_UninitializedTerminalCodeLess
    // P9Q-SRC-006 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC006_SRC007
    // P9Q-SRC-007 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC006_SRC007
    // P9Q-SRC-008 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC008 tests
    // P9Q-SRC-009 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC008_SRC009_SRC010
    // P9Q-SRC-010 => Phase9PayoffQuoteAuthorizationAndInputTest.CFG001 + SRC013
    // P9Q-SRC-011 => Phase9PayoffQuoteLifecycleTest.SRC011_Consume + issue negative
    // P9Q-SRC-012 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC011_SRC012
    // P9Q-SRC-013 => Phase9PayoffQuoteAuthorizationAndInputTest.SRC013 + lifecycle consume
    // P9Q-SRC-014 => Phase9PayoffQuoteCanonicalTest canonical runtime + token golden suite
    // P9Q-POL-001 => Phase9PayoffQuoteCanonicalTest.POL001
    // P9Q-POL-002 => Phase9PayoffQuoteFuzzTest.POL002
    // P9Q-POL-003 => Phase9PayoffQuoteFuzzTest.POL003 successor field fuzz
    // P9Q-POL-004 => Phase9PayoffQuoteLifecycleTest.POL003_POL004
    // P9Q-EQ-001 => Phase9PayoffQuoteCanonicalTest.EQ001
    // P9Q-EQ-002 => Phase9PayoffQuoteFuzzTest.EQ002
    // P9Q-EQ-003 => Phase9PayoffQuoteCanonicalTest.EQ003_FullNonzeroFeeAndPenaltyCredit
    // P9Q-EQ-004 => Phase9PayoffQuoteFuzzTest.EQ004 + unit invalid equations
    // P9Q-EQ-005 => Phase9PayoffQuoteAuthorizationAndInputTest.EQ004_EQ005_EQ006_EQ007
    // P9Q-EQ-006 => Phase9PayoffQuoteAuthorizationAndInputTest.EQ004_EQ005_EQ006_EQ007
    // P9Q-EQ-007 => Phase9PayoffQuoteAuthorizationAndInputTest.EQ004_EQ005_EQ006_EQ007
    // P9Q-COMP-001 => Phase9PayoffQuoteCanonicalTest.EQ001_COMP001
    // P9Q-COMP-002 => Phase9PayoffQuoteCanonicalTest.COMP002_ZeroComponentsRemain
    // P9Q-COMP-003 => Phase9PayoffQuoteCanonicalTest.EQ001_COMP003
    // P9Q-COMP-004 => Phase9PayoffQuoteFuzzTest.COMP004
    // P9Q-ROUTE-001 => Phase9PayoffQuoteCanonicalTest.ROUTE001
    // P9Q-ROUTE-002 => Phase9PayoffQuoteCanonicalTest.ROUTE002 + lifecycle substitution
    // P9Q-TIME-001 => Phase9PayoffQuoteAuthorizationAndInputTest.TIME001_TIME002_TIME003_TIME008
    // P9Q-TIME-002 => Phase9PayoffQuoteAuthorizationAndInputTest.TIME001_TIME002_TIME003_TIME008
    // P9Q-TIME-003 => Phase9PayoffQuoteAuthorizationAndInputTest.TIME001_TIME002_TIME003_TIME008
    // P9Q-TIME-004 => Phase9PayoffQuoteLifecycleTest.TIME004_TIME005_TIME006_TIME007
    // P9Q-TIME-005 => Phase9PayoffQuoteLifecycleTest.TIME004_TIME005_TIME006_TIME007
    // P9Q-TIME-006 => Phase9PayoffQuoteLifecycleTest.TIME004_TIME005_TIME006_TIME007
    // P9Q-TIME-007 => Phase9PayoffQuoteLifecycleTest.TIME004_TIME005_TIME006_TIME007
    // P9Q-TIME-008 => Phase9PayoffQuoteFuzzTest.EQ002 validity fuzz
    // P9Q-NONCE-001 => Phase9PayoffQuoteLifecycleTest.NONCE001_NONCE002
    // P9Q-NONCE-002 => Phase9PayoffQuoteLifecycleTest.NONCE001_NONCE002
    // P9Q-NONCE-003 => Phase9PayoffQuoteLifecycleTest.NONCE003_DifferentLoans
    // P9Q-NONCE-004 => Phase9PayoffQuoteLifecycleTest.NONCE004 exact payload
    // P9Q-NONCE-005 => Phase9PayoffQuoteLifecycleTest.NONCE005 hook harness
    // P9Q-NONCE-006 => Phase9PayoffQuoteLifecycleTest.NONCE006 storage collision
    // P9Q-LIVE-001 => Phase9PayoffQuoteLifecycleTest.NONCE001_LIVE001
    // P9Q-LIVE-002 => Phase9PayoffQuoteLifecycleTest.LIVE002_EffectiveExpiry
    // P9Q-ID-001 => Phase9PayoffQuoteCanonicalTest.ID001 + existing golden vectors
    // P9Q-ID-002 => Phase9PayoffQuoteCanonicalTest.ID002
    // P9Q-ID-003 => Phase9PayoffQuoteFuzzTest.ID003 every field
    // P9Q-ID-004 => Phase9PayoffQuoteCanonicalTest engine-domain + external cross-language vectors
    // P9Q-EVT-001 => Phase9PayoffQuoteCanonicalTest.EVT001 exact indexed/data decode
    // P9Q-VIEW-001 => Phase9PayoffQuoteAuthorizationAndInputTest.VIEW001
    // P9Q-VIEW-002 => Phase9PayoffQuoteLifecycleTest.VIEW002
    // P9Q-CONS-001 => Phase9PayoffQuoteLifecycleTest.CONS001
    // P9Q-CONS-002 => Phase9PayoffQuoteLifecycleTest.CONS002
    // P9Q-CONS-003 => Phase9PayoffQuoteLifecycleTest.CONS003 both expected-version branches
    // P9Q-CONS-004 => Phase9PayoffQuoteLifecycleTest.CONS004
    // P9Q-CONS-005 => Phase9PayoffQuoteLifecycleTest.CONS005 route/recipient substitutions
    // P9Q-CONS-006 => Phase9PayoffQuoteLifecycleTest.CONS006 zero IDs
    // P9Q-CONS-007 => Phase9PayoffQuoteLifecycleTest.CONS007 stored corruption
    // P9Q-TERM-001 => Phase9PayoffQuoteLifecycleTest.TERM001
    // P9Q-TERM-002 => Phase9PayoffQuoteLifecycleTest.TERM002
    // P9Q-TERM-003 => Phase9PayoffQuoteLifecycleTest.TERM003
    // P9Q-TERM-004 => Phase9PayoffQuoteLifecycleTest.TERM004
    // P9Q-TERM-005 => Phase9PayoffQuoteLifecycleTest.TERM005 precedence
    // P9Q-RPL-001 => Phase9PayoffQuoteLifecycleTest.RPL001 replay matrix
    // P9Q-RPL-002 => Phase9PayoffQuoteFuzzTest.RPL002 changed fields
    // P9Q-RPL-003 => Phase9PayoffQuoteLifecycleTest.RPL003 consume/invalidate/expiry
    // P9Q-RPL-004 => Phase9PayoffQuoteLifecycleTest.RPL004 changed invalidation/expiry
    // P9Q-RPL-005 => Phase9PayoffQuoteLifecycleTest.RPL005 changed live debt
    // P9Q-RPL-006 => Phase9PayoffQuoteLifecycleTest.RPL006 changed live debt
    // P9Q-NOVAL-001 => Phase9PayoffQuoteLifecycleTest.NOVAL001 + stateful invariant
    // P9Q-NOVAL-002 => Phase9PayoffQuoteLifecycleTest.NOVAL002 all mutators
    // P9Q-NOVAL-003 => Phase9PayoffQuoteLifecycleTest canonical-token access recording + invariant
    // P9Q-NOVAL-004 => Phase9PayoffQuoteLifecycleTest.NOVAL004 forced ETH
    // P9Q-LOCAL-001 => external Phase 9 dependency/bytecode/release-boundary tooling
    // P9Q-LOCAL-002 => every Solidity fixture uses Phase9LocalSyntheticToken on chain 31337
    // P9Q-LOCAL-003 => Phase9PayoffQuoteLifecycleTest issue + first-consume wrong-chain negatives
}
