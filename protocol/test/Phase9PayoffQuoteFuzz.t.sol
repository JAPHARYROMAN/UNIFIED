// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPayoffQuoteEngineV2 } from "../src/interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";
import {
    Phase9PayoffCoordinatorProxy,
    Phase9PayoffMockPositionManager,
    Phase9PayoffMockPolicySource,
    Phase9PayoffReference,
    Phase9PayoffVm,
    Phase9PayoffWrongRuntimeToken
} from "./Phase9PayoffQuoteHarness.sol";
import { Phase9PayoffQuoteFixture, Phase9PayoffQuoteIdHarness } from "./Phase9PayoffQuote.t.sol";

/// @dev Acceptance fuzz requirement map:
/// 01 => ValidEconomicsAndAllEncodersAgree + OverflowFailsBeforeEveryWrite.
/// 02 => ValidEconomicsAndAllEncodersAgree + InvalidCredit + OverflowFailsBeforeEveryWrite.
/// 03 => ValidEconomicsAndAllEncodersAgree component/beneficiary/code/route reconciliation.
/// 04 => ValidEconomicsAndAllEncodersAgree + GeneratedPolicyComponentRouteAndQuoteEncoders.
/// 05 => Policy/Component/Route/Quote mutation matrices + EveryOpaquePolicyDigestFails.
/// 06 => EveryPolicyMutationFailsForSuccessorOrFirstConsume.
/// 07 => IdenticalPositionManagerSubstitutionFailsAtIssueOrConsume.
/// 08 => invalid-credit/opaque-policy negatives + GeneralFailedIssuePreservesNonceAndOneLiveState.
/// 09 => SuccessfulNoncesAreGaplessAcrossFailures.
/// 10 => ZeroAndMaterializedIdCollisionsPreserveAllPrestate.
/// 11 => StaleQuoteRejectsEveryCallerExpectedVersion.
/// 12 => CoordinatorSelectedIntervalIsExactHalfOpenAndIssuedAtIsCanonical.
/// 13 => EveryPersistedInvalidationOrExpiryHasNonzeroSource.
/// 14 => TerminalDispositionsAreMonotonic.
/// 15 => consume/invalidation/expiry exact and changed retry matrices.
/// 16 => PinnedRuntimeInvariantAndGeneratedWrongRuntimeRejected.
/// 17 => NoQuoteActionChangesExternalValueOrCanonicalState.
contract Phase9PayoffQuoteFuzzTest is Phase9PayoffQuoteFixture {
    struct PolicyMutationFacts {
        address engineAddress;
        address source;
        bytes32 loanId;
        address loanAccount;
        bytes32 policySet;
        address beneficiary;
        bytes32 asset;
        address settlementToken;
        uint64 maximum;
    }

    struct RouteMutationFacts {
        address engineAddress;
        address coordinatorAddress;
        bytes32 loanId;
        address loanAccount;
        bytes32 asset;
        address settlementToken;
        address lender;
        address feeBeneficiary;
        bytes32 policyHash;
    }

    function testFuzz_REQ01_REQ02_REQ03_REQ04_P9Q_EQ002_ValidEconomicsAndAllEncodersAgree(
        uint128 principalSeed,
        uint128 interestSeed,
        uint64 feeSeed,
        uint64 penaltySeed,
        uint128 creditSeed,
        uint32 validitySeed
    ) public {
        uint256 principal = uint256(principalSeed) + 1;
        uint256 interest = uint256(interestSeed);
        uint256 fees = uint256(feeSeed);
        uint256 penalties = uint256(penaltySeed);
        uint256 route = fees + penalties;
        uint256 credits =
            route == type(uint128).max ? uint256(creditSeed) : uint256(creditSeed) % (route + 1);
        uint64 validity = uint64((uint256(validitySeed) % MAX_VALIDITY) + 1);
        _setCanonicalDebt(principal, interest, fees, penalties, credits, 7);
        _setPositions(address(positions), LENDER, principal + interest, 1);

        bytes32 quoteId = coordinator.issue(LOAN_ID, NOW + validity);
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        uint256 gross = principal + interest + fees + penalties;
        require(stored.grossPayoff == gross, "gross equation");
        require(stored.credits <= fees + penalties, "credit bound");
        require(stored.netPayoff == gross - credits && stored.netPayoff != 0, "net equation");
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory expected = Phase9PayoffReference.components(
            principal, interest, fees, penalties, credits, LENDER, FEE_BENEFICIARY
        );
        require(
            keccak256(abi.encode(components_)) == keccak256(abi.encode(expected)),
            "component vector"
        );
        require(
            stored.componentBeneficiaryHash == Phase9PayoffReference.componentHash(expected),
            "component encoder"
        );
        require(
            stored.policyHash
                == Phase9PayoffReference.policyHash(
                    address(engine),
                    address(policy),
                    LOAN_ID,
                    address(account),
                    POLICY_SET,
                    FEE_BENEFICIARY,
                    ASSET_ID,
                    address(token),
                    MAX_VALIDITY
                ),
            "policy encoder"
        );
        require(
            stored.settlementRouteHash
                == Phase9PayoffReference.routeHash(
                    address(engine),
                    address(coordinator),
                    LOAN_ID,
                    address(account),
                    ASSET_ID,
                    address(token),
                    LENDER,
                    FEE_BENEFICIARY,
                    stored.policyHash
                ),
            "route encoder"
        );
        require(
            quoteId == Phase9PayoffReference.quoteIdFor(address(engine), stored), "quote encoder"
        );
        uint256 lenderRoute = components_[0].amount + components_[1].amount;
        uint256 feeRouteNet = components_[2].amount + components_[3].amount - components_[4].amount;
        require(lenderRoute == principal + interest, "lender route");
        require(feeRouteNet == fees + penalties - credits, "fee route netting");
        require(stored.netPayoff == lenderRoute + feeRouteNet, "route reconciliation");
        require(stored.issuedAt == NOW && stored.validUntil == NOW + validity, "time interval");
    }

    function testFuzz_REQ01_REQ02_OverflowFailsBeforeEveryWrite(uint8 overflowKind, uint256 seed)
        public
    {
        if (overflowKind % 3 == 0) {
            _setCanonicalDebt(type(uint256).max, (seed % type(uint128).max) + 1, 0, 0, 0, 7);
        } else if (overflowKind % 3 == 1) {
            _setCanonicalDebt(1, 0, type(uint256).max, (seed % type(uint128).max) + 1, 0, 7);
            _setPositions(address(positions), LENDER, 1, 1);
        } else {
            _setCanonicalDebt(type(uint256).max - 1, 0, 2, 0, 0, 7);
            _setPositions(address(positions), LENDER, type(uint256).max - 1, 1);
        }
        bytes32 before_ = _issuanceStateHash();
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        require(_issuanceStateHash() == before_, "overflow partial state");
    }

    function testFuzz_REQ04_GeneratedPolicyComponentRouteAndQuoteEncodersEqualEngine(
        bytes32 policySetSeed,
        bytes32 assetSeed,
        address beneficiarySeed,
        address lenderSeed
    ) public {
        bytes32 policySet = _nonzero(policySetSeed, 4);
        bytes32 asset = _nonzero(assetSeed, 40);
        address beneficiary = beneficiarySeed == address(0) ? FEE_BENEFICIARY : beneficiarySeed;
        address lender = lenderSeed == address(0) ? LENDER : lenderSeed;
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        configuration.policySetHash = policySet;
        configuration.settlementAssetId = asset;
        account.setConfiguration(configuration);
        _setPositions(address(positions), lender, 95, 1);
        bytes32 expectedPolicy =
            _setCanonicalPolicy(policySet, beneficiary, asset, address(token), true);

        bytes32 quoteId = coordinator.issue(LOAN_ID, NOW + 1);
        (
            IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
        ) = engine.quote(quoteId);
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory expectedComponents =
            Phase9PayoffReference.components(90, 5, 3, 3, 1, lender, beneficiary);
        require(stored.policyHash == expectedPolicy, "generated policy encoder");
        require(
            stored.componentBeneficiaryHash
                == Phase9PayoffReference.componentHash(expectedComponents),
            "generated component encoder"
        );
        require(
            keccak256(abi.encode(components_)) == keccak256(abi.encode(expectedComponents)),
            "generated components"
        );
        require(
            stored.settlementRouteHash
                == Phase9PayoffReference.routeHash(
                    address(engine),
                    address(coordinator),
                    LOAN_ID,
                    address(account),
                    asset,
                    address(token),
                    lender,
                    beneficiary,
                    expectedPolicy
                ),
            "generated route encoder"
        );
        require(
            quoteId == Phase9PayoffReference.quoteIdFor(address(engine), stored),
            "generated quote encoder"
        );
    }

    function testFuzz_REQ02_REQ08_P9Q_EQ004_InvalidCreditNeverAdvancesNonce(
        uint128 principalSeed,
        uint64 feeSeed,
        uint64 penaltySeed,
        uint128 excessSeed
    ) public {
        uint256 principal = uint256(principalSeed) + 1;
        uint256 fees = uint256(feeSeed);
        uint256 penalties = uint256(penaltySeed);
        uint256 invalidCredit = fees + penalties + uint256(excessSeed) + 1;
        _setCanonicalDebt(principal, 0, fees, penalties, invalidCredit, 7);
        _setPositions(address(positions), LENDER, principal, 1);
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        require(vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "failed nonce");
        require(
            vm.load(address(engine), _latestStorageSlot(LOAN_ID)) == bytes32(0), "failed latest"
        );
    }

    function testFuzz_REQ05_P9Q_ID003_EveryQuotePreimageFieldMutationChangesId(
        uint8 fieldSeed,
        bytes32 mutationSeed
    ) public {
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_ = _referenceQuote();
        bytes32 original = Phase9PayoffReference.quoteIdFor(address(engine), quote_);
        uint8 field = fieldSeed % 21;
        bytes32 changed = mutationSeed == bytes32(0) ? bytes32(uint256(1)) : mutationSeed;
        if (field == 0) {
            bytes32 changedDomain = keccak256(
                abi.encode(
                    "CHANGED_PAYOFF_QUOTE_DOMAIN", address(engine), block.chainid, _identity(quote_)
                )
            );
            require(changedDomain != original, "quote domain unbound");
            return;
        } else if (field == 1) {
            require(
                Phase9PayoffReference.quoteIdFor(
                        _differentAddress(address(engine), changed), quote_
                    ) != original,
                "quote engine unbound"
            );
            return;
        } else if (field == 2) {
            vm.chainId(block.chainid + 1);
            bytes32 alternateChain = Phase9PayoffReference.quoteIdFor(address(engine), quote_);
            vm.chainId(31_337);
            require(alternateChain != original, "quote chain unbound");
            return;
        } else if (field == 3) {
            bytes32 reordered = keccak256(
                abi.encode(
                    "UNIFIED_PAYOFF_QUOTE_V1", block.chainid, address(engine), _identity(quote_)
                )
            );
            require(reordered != original, "quote order unbound");
            return;
        } else if (field == 4) {
            quote_.loanId = changed;
        } else if (field == 5) {
            quote_.loanAccount = _differentAddress(quote_.loanAccount, changed);
        } else if (field == 6) {
            quote_.policyHash = changed;
        } else if (field == 7) {
            quote_.debtStateVersion = _different64(quote_.debtStateVersion, changed);
        } else if (field == 8) {
            quote_.principal = _different256(quote_.principal, changed);
        } else if (field == 9) {
            quote_.accruedInterest = _different256(quote_.accruedInterest, changed);
        } else if (field == 10) {
            quote_.fees = _different256(quote_.fees, changed);
        } else if (field == 11) {
            quote_.penalties = _different256(quote_.penalties, changed);
        } else if (field == 12) {
            quote_.credits = _different256(quote_.credits, changed);
        } else if (field == 13) {
            quote_.componentBeneficiaryHash = changed;
        } else if (field == 14) {
            quote_.netPayoff = _different256(quote_.netPayoff, changed);
        } else if (field == 15) {
            quote_.settlementAssetId = changed;
        } else if (field == 16) {
            quote_.settlementToken = _differentAddress(quote_.settlementToken, changed);
        } else if (field == 17) {
            quote_.settlementRouteHash = changed;
        } else if (field == 18) {
            quote_.issuedAt = _different64(quote_.issuedAt, changed);
        } else if (field == 19) {
            quote_.validUntil = _different64(quote_.validUntil, changed);
        } else {
            quote_.quoteNonce = _different64(quote_.quoteNonce, changed);
        }
        require(
            Phase9PayoffReference.quoteIdFor(address(engine), quote_) != original, "field unbound"
        );
    }

    function testFuzz_REQ05_P9Q_COMP004_ComponentMutationChangesCommitment(
        uint8 fieldSeed,
        uint128 amountSeed,
        address beneficiarySeed,
        bytes32 codeSeed
    ) public pure {
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory values =
            Phase9PayoffReference.components(90, 5, 3, 3, 1, address(0x111), address(0x222));
        bytes32 original = Phase9PayoffReference.componentHash(values);
        uint8 field = fieldSeed % 8;
        if (field == 0) {
            values[2].kind = IPayoffQuoteEngineV2.ComponentKind.PENALTY;
        } else if (field == 1) {
            values[2].amount = uint256(amountSeed) + 4;
        } else if (field == 2) {
            values[2].beneficiary =
                beneficiarySeed == address(0x222) ? address(0x223) : beneficiarySeed;
        } else if (field == 3) {
            values[2].obligationCode = string(abi.encode(codeSeed, "CHANGED"));
        } else if (field == 4) {
            IPayoffQuoteEngineV2.PayoffComponentV2 memory first = values[0];
            values[0] = values[1];
            values[1] = first;
        } else if (field == 5) {
            values[1] = values[0];
        } else if (field == 6) {
            bytes32 alternateDomain = keccak256(abi.encode("CHANGED_COMPONENT_DOMAIN", values));
            require(alternateDomain != original, "component domain unbound");
            return;
        } else {
            IPayoffQuoteEngineV2.PayoffComponentV2[] memory omitted =
                new IPayoffQuoteEngineV2.PayoffComponentV2[](4);
            for (uint256 index; index < 4; ++index) {
                omitted[index] = values[index];
            }
            require(
                Phase9PayoffReference.componentHash(omitted) != original,
                "component omission unbound"
            );
            return;
        }
        require(Phase9PayoffReference.componentHash(values) != original, "component field unbound");
    }

    function testFuzz_REQ05_EveryPolicyPreimageFieldDomainAndOrderMutationChangesHash(
        uint8 fieldSeed,
        bytes32 seed
    ) public {
        bytes32 changed = seed == bytes32(0) ? bytes32(uint256(1)) : seed;
        PolicyMutationFacts memory facts = PolicyMutationFacts({
            engineAddress: address(engine),
            source: address(policy),
            loanId: LOAN_ID,
            loanAccount: address(account),
            policySet: POLICY_SET,
            beneficiary: FEE_BENEFICIARY,
            asset: ASSET_ID,
            settlementToken: address(token),
            maximum: MAX_VALIDITY
        });
        bytes32 original = _policyDigest(facts, "UNIFIED_PAYOFF_POLICY_V1", false);
        uint8 field = fieldSeed % 12;
        if (field == 0) {
            require(
                _policyDigest(facts, "CHANGED_PAYOFF_POLICY_DOMAIN", false) != original,
                "policy domain unbound"
            );
            return;
        }
        if (field == 1) {
            vm.chainId(31_338);
            bytes32 alternateChain = _policyDigest(facts, "UNIFIED_PAYOFF_POLICY_V1", false);
            vm.chainId(31_337);
            require(alternateChain != original, "policy chain unbound");
            return;
        }
        if (field == 2) {
            facts.engineAddress = _differentAddress(facts.engineAddress, changed);
        } else if (field == 3) {
            facts.source = _differentAddress(facts.source, changed);
        } else if (field == 4) {
            facts.loanId = _different32(facts.loanId, changed);
        } else if (field == 5) {
            facts.loanAccount = _differentAddress(facts.loanAccount, changed);
        } else if (field == 6) {
            facts.policySet = _different32(facts.policySet, changed);
        } else if (field == 7) {
            facts.beneficiary = _differentAddress(facts.beneficiary, changed);
        } else if (field == 8) {
            facts.asset = _different32(facts.asset, changed);
        } else if (field == 9) {
            facts.settlementToken = _differentAddress(facts.settlementToken, changed);
        } else if (field == 10) {
            facts.maximum = _different64(facts.maximum, changed);
        } else {
            require(
                _policyDigest(facts, "UNIFIED_PAYOFF_POLICY_V1", true) != original,
                "policy order unbound"
            );
            return;
        }
        require(
            _policyDigest(facts, "UNIFIED_PAYOFF_POLICY_V1", false) != original,
            "policy field unbound"
        );
    }

    function testFuzz_REQ05_EveryRoutePreimageFieldDomainAndOrderMutationChangesHash(
        uint8 fieldSeed,
        bytes32 seed
    ) public {
        bytes32 changed = seed == bytes32(0) ? bytes32(uint256(1)) : seed;
        RouteMutationFacts memory facts = RouteMutationFacts({
            engineAddress: address(engine),
            coordinatorAddress: address(coordinator),
            loanId: LOAN_ID,
            loanAccount: address(account),
            asset: ASSET_ID,
            settlementToken: address(token),
            lender: LENDER,
            feeBeneficiary: FEE_BENEFICIARY,
            policyHash: bytes32(uint256(11))
        });
        bytes32 original = _routeDigest(facts, "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1", false);
        uint8 field = fieldSeed % 12;
        if (field == 0) {
            require(
                _routeDigest(facts, "CHANGED_PAYOFF_ROUTE_DOMAIN", false) != original,
                "route domain unbound"
            );
            return;
        }
        if (field == 1) {
            vm.chainId(31_338);
            bytes32 alternateChain =
                _routeDigest(facts, "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1", false);
            vm.chainId(31_337);
            require(alternateChain != original, "route chain unbound");
            return;
        }
        if (field == 2) {
            facts.engineAddress = _differentAddress(facts.engineAddress, changed);
        } else if (field == 3) {
            facts.coordinatorAddress = _differentAddress(facts.coordinatorAddress, changed);
        } else if (field == 4) {
            facts.loanId = _different32(facts.loanId, changed);
        } else if (field == 5) {
            facts.loanAccount = _differentAddress(facts.loanAccount, changed);
        } else if (field == 6) {
            facts.asset = _different32(facts.asset, changed);
        } else if (field == 7) {
            facts.settlementToken = _differentAddress(facts.settlementToken, changed);
        } else if (field == 8) {
            facts.lender = _differentAddress(facts.lender, changed);
        } else if (field == 9) {
            facts.feeBeneficiary = _differentAddress(facts.feeBeneficiary, changed);
        } else if (field == 10) {
            facts.policyHash = _different32(facts.policyHash, changed);
        } else {
            require(
                _routeDigest(facts, "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1", true) != original,
                "route order unbound"
            );
            return;
        }
        require(
            _routeDigest(facts, "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1", false) != original,
            "route field unbound"
        );
    }

    function testFuzz_REQ15_P9Q_RPL001_RPL002_ExactConsumeRetryIsIdempotentChangedRetryConflicts(
        bytes32 changedRefinanceSeed,
        bytes32 changedSourceSeed,
        uint64 changedVersionSeed
    ) public {
        bytes32 quoteId = _issue();
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        IPayoffQuoteEngineV2.PayoffQuoteV2 memory replay =
            coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        require(replay.state == IPayoffQuoteEngineV2.QuoteState.CONSUMED, "exact replay");

        bytes32 changedRefinance = changedRefinanceSeed == REFINANCE_ID
            ? keccak256(abi.encode(changedRefinanceSeed))
            : changedRefinanceSeed;
        if (changedRefinance == bytes32(0)) changedRefinance = bytes32(uint256(1));
        bytes32 changedSource = changedSourceSeed == SOURCE_EVENT_ID
            ? keccak256(abi.encode(changedSourceSeed))
            : changedSourceSeed;
        if (changedSource == bytes32(0)) changedSource = bytes32(uint256(2));
        uint64 changedVersion = changedVersionSeed == 7 ? 8 : changedVersionSeed;
        if (changedVersion == 0) changedVersion = 1;
        _expectReplayConflict(quoteId, changedRefinance, 7, SOURCE_EVENT_ID);
        _expectReplayConflict(quoteId, REFINANCE_ID, 7, changedSource);
        _expectReplayConflict(quoteId, REFINANCE_ID, changedVersion, SOURCE_EVENT_ID);
    }

    function testFuzz_REQ05_REQ08_P9Q_POL002_EveryOpaquePolicyDigestFails(bytes32 opaqueDigest)
        public
    {
        bytes32 canonical = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            LOAN_ID,
            address(account),
            POLICY_SET,
            FEE_BENEFICIARY,
            ASSET_ID,
            address(token),
            MAX_VALIDITY
        );
        if (opaqueDigest == canonical) opaqueDigest = bytes32(uint256(canonical) + 1);
        policy.setPolicy(
            LOAN_ID,
            address(account),
            Phase9PayoffMockPolicySource.Policy({
                policyHash: opaqueDigest,
                boundPolicySetHash: POLICY_SET,
                feePenaltyBeneficiary: FEE_BENEFICIARY,
                settlementAssetId: ASSET_ID,
                settlementToken: address(token),
                maximumValidity: MAX_VALIDITY,
                active: true
            })
        );
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function testFuzz_REQ06_EveryPolicyMutationFailsForSuccessorOrFirstConsume(
        uint8 fieldSeed,
        bool firstConsume,
        bool effectiveExpiry
    ) public {
        bytes32 first = coordinator.issue(LOAN_ID, NOW + 1);
        if (!firstConsume) {
            if (effectiveExpiry) vm.warp(NOW + 1);
            else coordinator.invalidate(first, SOURCE_EVENT_ID);
        }

        uint8 field = fieldSeed % 7;
        Phase9Types.LoanConfiguration memory configuration = account.configuration();
        bytes32 policySet = POLICY_SET;
        address beneficiary = FEE_BENEFICIARY;
        bytes32 asset = ASSET_ID;
        address settlementToken = address(token);
        uint64 maximum = MAX_VALIDITY;
        bool active = true;
        if (field == 1) {
            policySet = keccak256("SUCCESSOR_POLICY_SET");
            configuration.policySetHash = policySet;
        } else if (field == 2) {
            beneficiary = address(0xBEEF);
        } else if (field == 3) {
            asset = keccak256("SUCCESSOR_ASSET");
            configuration.settlementAssetId = asset;
        } else if (field == 4) {
            Phase9LocalSyntheticToken successorToken = new Phase9LocalSyntheticToken(address(this));
            settlementToken = address(successorToken);
            configuration.settlementToken = settlementToken;
        } else if (field == 5) {
            maximum = MAX_VALIDITY - 1;
        } else if (field == 6) {
            active = false;
        }
        account.setConfiguration(configuration);

        bytes32 digest = Phase9PayoffReference.policyHash(
            address(engine),
            address(policy),
            LOAN_ID,
            address(account),
            policySet,
            beneficiary,
            asset,
            settlementToken,
            maximum
        );
        if (field == 0) digest = bytes32(uint256(digest) + 1);
        policy.setPolicy(
            LOAN_ID,
            address(account),
            Phase9PayoffMockPolicySource.Policy({
                policyHash: digest,
                boundPolicySetHash: policySet,
                feePenaltyBeneficiary: beneficiary,
                settlementAssetId: asset,
                settlementToken: settlementToken,
                maximumValidity: maximum,
                active: active
            })
        );
        (bool success, bytes memory result) = firstConsume
            ? _consumeCall(first, REFINANCE_ID, 7, SOURCE_EVENT_ID)
            : _issueCall(LOAN_ID, uint64(block.timestamp) + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        require(vm.load(address(engine), _latestStorageSlot(LOAN_ID)) == first, "latest changed");
    }

    function testFuzz_REQ07_IdenticalPositionManagerSubstitutionFailsAtIssueOrConsume(
        uint128 principalSeed,
        uint64 interestSeed,
        address ownerSeed,
        bool firstConsume
    ) public {
        uint256 principal = uint256(principalSeed) + 1;
        uint256 interest = uint256(interestSeed);
        uint256 claim = principal + interest;
        address owner = ownerSeed == address(0) ? LENDER : ownerSeed;
        _setCanonicalDebt(principal, interest, 0, 0, 0, 7);
        _setPositions(address(positions), owner, claim, 1);
        Phase9PayoffMockPositionManager substitute = new Phase9PayoffMockPositionManager();
        _setPositions(address(substitute), owner, claim, 1);

        bytes32 quoteId;
        if (firstConsume) quoteId = coordinator.issue(LOAN_ID, NOW + 1);
        factory.setLoan(LOAN_ID, address(account), address(substitute));
        (bool success, bytes memory result) = firstConsume
            ? _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID)
            : _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        if (firstConsume) {
            (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
            require(stored.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "substitution consumed");
        } else {
            require(vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(0), "nonce");
            require(vm.load(address(engine), _latestStorageSlot(LOAN_ID)) == bytes32(0), "latest");
        }
    }

    function testFuzz_REQ08_GeneralFailedIssuePreservesNonceAndOneLiveState(
        uint8 failureKind,
        bytes32 seed
    ) public {
        uint8 kind = failureKind % 8;
        uint64 validUntil = NOW + 1;
        if (kind == 0) {
            validUntil = NOW;
        } else if (kind == 1) {
            _setCanonicalDebt(90, 5, 3, 3, 7 + (uint256(seed) % 100), 7);
        } else if (kind == 2) {
            Phase9Types.DebtState memory debt = account.debtState();
            debt.lifecycle = Phase9Types.LoanLifecycle.CLOSED;
            account.setDebt(debt);
        } else if (kind == 3) {
            bytes32 canonical = Phase9PayoffReference.policyHash(
                address(engine),
                address(policy),
                LOAN_ID,
                address(account),
                POLICY_SET,
                FEE_BENEFICIARY,
                ASSET_ID,
                address(token),
                MAX_VALIDITY
            );
            Phase9PayoffMockPolicySource.Policy memory facts = Phase9PayoffMockPolicySource.Policy({
                policyHash: _different32(canonical, seed),
                boundPolicySetHash: POLICY_SET,
                feePenaltyBeneficiary: FEE_BENEFICIARY,
                settlementAssetId: ASSET_ID,
                settlementToken: address(token),
                maximumValidity: MAX_VALIDITY,
                active: true
            });
            policy.setPolicy(LOAN_ID, address(account), facts);
        } else if (kind == 4) {
            factory.setLoan(LOAN_ID, address(0xBAD), address(positions));
        } else if (kind == 5) {
            _setPositions(address(positions), LENDER, 94, 1);
        } else if (kind == 6) {
            Phase9PayoffWrongRuntimeToken wrong = new Phase9PayoffWrongRuntimeToken(address(this));
            _setCanonicalConfiguration(address(positions), address(wrong), POLICY_SET);
            _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(wrong), true);
        } else {
            coordinator.issue(LOAN_ID, NOW + 1);
        }
        bytes32 before_ = _issuanceStateHash();
        (bool success,) = _issueCall(LOAN_ID, validUntil);
        require(!success, "generated failed issue accepted");
        require(_issuanceStateHash() == before_, "failed issue changed state");
    }

    function testFuzz_REQ09_SuccessfulNoncesAreGaplessAcrossFailures(uint8 countSeed) public {
        uint256 count = uint256(countSeed % 4) + 1;
        for (uint256 index; index < count; ++index) {
            bytes32 beforeFailure = _issuanceStateHash();
            (bool success,) = _issueCall(LOAN_ID, NOW);
            require(!success && _issuanceStateHash() == beforeFailure, "failure consumed nonce");
            bytes32 quoteId = coordinator.issue(LOAN_ID, NOW + MAX_VALIDITY);
            (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
            require(stored.quoteNonce == index + 1, "nonce gap");
            coordinator.invalidate(quoteId, keccak256(abi.encode("REQ09", index)));
        }
        require(
            vm.load(address(engine), _nonceStorageSlot(LOAN_ID)) == bytes32(count + 1), "next nonce"
        );
    }

    function testFuzz_REQ10_ZeroAndMaterializedIdCollisionsPreserveAllPrestate(bytes32 idSeed)
        public
    {
        Phase9PayoffQuoteIdHarness harness = _installIdHarness();
        harness.forceQuoteId(bytes32(0));
        bytes32 zeroBefore = _collisionStateHash(bytes32(0));
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
        require(_collisionStateHash(bytes32(0)) == zeroBefore, "zero id partial write");

        setUp();
        harness = _installIdHarness();
        bytes32 collision = idSeed == bytes32(0) ? bytes32(uint256(1)) : idSeed;
        harness.forceQuoteId(collision);
        vm.store(address(engine), _quoteStorageBase(collision), collision);
        bytes32 collisionBefore = _collisionStateHash(collision);
        (success, result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
        require(_collisionStateHash(collision) == collisionBefore, "collision partial write");
    }

    function testFuzz_REQ11_StaleQuoteRejectsEveryCallerExpectedVersion(
        uint64 expectedVersion,
        uint64 liveVersionSeed
    ) public {
        bytes32 quoteId = _issue();
        uint64 liveVersion = liveVersionSeed == 7 ? 8 : liveVersionSeed;
        Phase9Types.DebtState memory debt = account.debtState();
        debt.debtStateVersion = liveVersion;
        account.setDebt(debt);
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, expectedVersion, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.StaleDebtVersion.selector);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.ISSUED, "stale consumed");
    }

    function testFuzz_REQ12_CoordinatorSelectedIntervalIsExactHalfOpenAndIssuedAtIsCanonical(
        uint32 issuedAtOffsetSeed,
        uint32 validitySeed
    ) public {
        uint64 issuedAt = NOW + uint64(uint256(issuedAtOffsetSeed) % 1_000_000);
        uint64 validity = uint64((uint256(validitySeed) % MAX_VALIDITY) + 1);
        uint64 validUntil = issuedAt + validity;
        vm.warp(issuedAt);

        bytes32 quoteId = coordinator.issue(LOAN_ID, validUntil);
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.issuedAt == issuedAt, "issuedAt was caller-replaced");
        require(stored.validUntil == validUntil, "validUntil changed");

        vm.warp(validUntil - 1);
        coordinator.consume(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        (stored,) = engine.quote(quoteId);
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.CONSUMED, "interval start/end-1");

        setUp();
        vm.warp(issuedAt);
        quoteId = coordinator.issue(LOAN_ID, validUntil);
        vm.warp(validUntil);
        (bool success, bytes memory result) =
            _consumeCall(quoteId, REFINANCE_ID, 7, SOURCE_EVENT_ID);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteExpired.selector);
        (stored,) = engine.quote(quoteId);
        require(stored.state == IPayoffQuoteEngineV2.QuoteState.EXPIRED, "interval end inclusive");
    }

    function testFuzz_REQ13_EveryPersistedInvalidationOrExpiryHasNonzeroSource(
        bytes32 sourceSeed,
        bool expiry
    ) public {
        bytes32 source = _nonzero(sourceSeed, 13);
        bytes32 quoteId = coordinator.issue(LOAN_ID, NOW + 1);
        if (expiry) vm.warp(NOW + 1);
        vm.recordLogs();
        coordinator.invalidate(quoteId, source);
        Phase9PayoffVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1 && logs[0].topics[1] == quoteId, "terminal event");
        (IPayoffQuoteEngineV2.QuoteState eventState, bytes32 eventSource,) =
            abi.decode(logs[0].data, (IPayoffQuoteEngineV2.QuoteState, bytes32, uint64));
        require(eventSource == source && eventSource != bytes32(0), "zero persisted source");
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        IPayoffQuoteEngineV2.QuoteState expected = expiry
            ? IPayoffQuoteEngineV2.QuoteState.EXPIRED
            : IPayoffQuoteEngineV2.QuoteState.INVALIDATED;
        require(eventState == expected && stored.state == expected, "terminal state");

        setUp();
        quoteId = coordinator.issue(LOAN_ID, NOW + 1);
        if (expiry) vm.warp(NOW + 1);
        (bool success, bytes memory result) = _invalidateCall(quoteId, bytes32(0));
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
    }

    function testFuzz_REQ14_TerminalDispositionsAreMonotonic(
        uint8 actionSeed,
        bytes32 sourceSeed,
        bytes32 refinanceSeed
    ) public {
        bytes32 source = _nonzero(sourceSeed, 14);
        bytes32 refinance = _nonzero(refinanceSeed, 140);
        bytes32 quoteId = coordinator.issue(LOAN_ID, NOW + 1);
        IPayoffQuoteEngineV2.QuoteState terminal;
        if (actionSeed % 3 == 0) {
            coordinator.consume(quoteId, refinance, 7, source);
            terminal = IPayoffQuoteEngineV2.QuoteState.CONSUMED;
            coordinator.consume(quoteId, refinance, 7, source);
            (bool success,) = _invalidateCall(quoteId, source);
            require(!success, "consumed invalidated");
        } else {
            if (actionSeed % 3 == 2) vm.warp(NOW + 1);
            coordinator.invalidate(quoteId, source);
            terminal = actionSeed % 3 == 2
                ? IPayoffQuoteEngineV2.QuoteState.EXPIRED
                : IPayoffQuoteEngineV2.QuoteState.INVALIDATED;
            coordinator.invalidate(quoteId, source);
            (bool success,) = _consumeCall(quoteId, refinance, 7, source);
            require(!success, "invalidated consumed");
        }
        (IPayoffQuoteEngineV2.PayoffQuoteV2 memory stored,) = engine.quote(quoteId);
        require(stored.state == terminal, "terminal regressed");
    }

    function testFuzz_REQ15_InvalidationAndExpiryRetryMatrices(
        bytes32 sourceSeed,
        bytes32 changedSeed,
        bool expiry
    ) public {
        bytes32 source = _nonzero(sourceSeed, 15);
        bytes32 changed = _different32(source, _nonzero(changedSeed, 150));
        bytes32 quoteId = coordinator.issue(LOAN_ID, NOW + 1);
        if (expiry) vm.warp(NOW + 1);
        coordinator.invalidate(quoteId, source);
        vm.recordLogs();
        coordinator.invalidate(quoteId, source);
        require(vm.getRecordedLogs().length == 0, "exact terminal replay event");
        (bool success, bytes memory result) = _invalidateCall(quoteId, changed);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
    }

    function testFuzz_REQ16_PinnedRuntimeInvariantAndGeneratedWrongRuntimeRejected(address allocatorSeed)
        public
    {
        require(address(token).codehash == TOKEN_RUNTIME_HASH, "pinned runtime drift");
        address allocator = allocatorSeed == address(0) ? address(this) : allocatorSeed;
        Phase9PayoffWrongRuntimeToken wrong = new Phase9PayoffWrongRuntimeToken(allocator);
        require(address(wrong).codehash != TOKEN_RUNTIME_HASH, "wrong runtime matched");
        _setCanonicalConfiguration(address(positions), address(wrong), POLICY_SET);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(wrong), true);
        bytes32 before_ = _issuanceStateHash();
        (bool success, bytes memory result) = _issueCall(LOAN_ID, NOW + 1);
        _assertRevert(success, result, IPayoffQuoteEngineV2.InvalidQuoteInput.selector);
        require(_issuanceStateHash() == before_, "wrong runtime partial state");
    }

    function testFuzz_REQ17_NoQuoteActionChangesExternalValueOrCanonicalState(
        uint8 actionSeed,
        bytes32 sourceSeed,
        bytes32 refinanceSeed
    ) public {
        bytes32 source = _nonzero(sourceSeed, 17);
        bytes32 refinance = _nonzero(refinanceSeed, 170);
        uint8 action = actionSeed % 8;
        bytes32 quoteId;
        if (action != 0) quoteId = coordinator.issue(LOAN_ID, NOW + 1);
        if (action == 2 || action == 7) {
            coordinator.consume(quoteId, refinance, 7, source);
        } else if (action == 6) {
            coordinator.invalidate(quoteId, source);
        } else if (action == 4) {
            vm.warp(NOW + 1);
        }
        bytes32 before_ = _trackedExternalHash();
        if (action == 0) {
            coordinator.issue(LOAN_ID, NOW + 1);
        } else if (action == 1 || action == 2) {
            coordinator.consume(quoteId, refinance, 7, source);
        } else if (action == 3 || action == 4 || action == 6) {
            coordinator.invalidate(quoteId, source);
        } else if (action == 5) {
            (bool success,) = _issueCall(LOAN_ID, NOW + 1);
            require(!success, "concurrent issue accepted");
        } else {
            (bool success,) = _consumeCall(
                quoteId, _different32(refinance, bytes32(uint256(refinance) + 1)), 7, source
            );
            require(!success, "changed consume replay accepted");
        }
        require(_trackedExternalHash() == before_, "external value/canonical state changed");
    }

    function _referenceQuote()
        private
        view
        returns (IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_)
    {
        IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_ =
            Phase9PayoffReference.components(90, 5, 3, 3, 1, LENDER, FEE_BENEFICIARY);
        quote_.loanId = LOAN_ID;
        quote_.loanAccount = address(account);
        quote_.policyHash = bytes32(uint256(11));
        quote_.debtStateVersion = 7;
        quote_.principal = 90;
        quote_.accruedInterest = 5;
        quote_.fees = 3;
        quote_.penalties = 3;
        quote_.credits = 1;
        quote_.componentBeneficiaryHash = Phase9PayoffReference.componentHash(components_);
        quote_.grossPayoff = 101;
        quote_.netPayoff = 100;
        quote_.settlementAssetId = ASSET_ID;
        quote_.settlementToken = address(token);
        quote_.settlementRouteHash = bytes32(uint256(12));
        quote_.issuedAt = NOW;
        quote_.validUntil = NOW + MAX_VALIDITY;
        quote_.quoteNonce = 1;
    }

    function _differentAddress(address original, bytes32 seed)
        private
        pure
        returns (address changed)
    {
        changed = address(uint160(uint256(seed)));
        if (changed == original) changed = address(uint160(uint256(seed) + 1));
    }

    function _different64(uint64 original, bytes32 seed) private pure returns (uint64 changed) {
        changed = uint64(uint256(seed));
        if (changed == original) changed = original + 1;
    }

    function _different256(uint256 original, bytes32 seed) private pure returns (uint256 changed) {
        changed = uint256(seed);
        if (changed == original) changed = original + 1;
    }

    function _different32(bytes32 original, bytes32 seed) private pure returns (bytes32 changed) {
        changed = seed;
        if (changed == original) changed = original ^ bytes32(uint256(1));
    }

    function _nonzero(bytes32 seed, uint256 salt) private pure returns (bytes32) {
        return seed == bytes32(0) ? bytes32(salt + 1) : seed;
    }

    function _issuanceStateHash() private view returns (bytes32) {
        bytes32 nonce = vm.load(address(engine), _nonceStorageSlot(LOAN_ID));
        bytes32 latest = vm.load(address(engine), _latestStorageSlot(LOAN_ID));
        bytes32 quoteHash;
        bytes32 componentHash;
        if (latest != bytes32(0)) {
            (
                IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_,
                IPayoffQuoteEngineV2.PayoffComponentV2[] memory components_
            ) = engine.quote(latest);
            quoteHash = keccak256(abi.encode(quote_));
            componentHash = keccak256(abi.encode(components_));
        }
        return keccak256(abi.encode(nonce, latest, quoteHash, componentHash));
    }

    function _collisionStateHash(bytes32 quoteId) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                vm.load(address(engine), _quoteStorageBase(quoteId)),
                vm.load(address(engine), keccak256(abi.encode(quoteId, uint256(6)))),
                vm.load(address(engine), keccak256(abi.encode(quoteId, uint256(7)))),
                vm.load(address(engine), _nonceStorageSlot(LOAN_ID)),
                vm.load(address(engine), _latestStorageSlot(LOAN_ID))
            )
        );
    }

    function _installIdHarness() private returns (Phase9PayoffQuoteIdHarness harness) {
        coordinator = new Phase9PayoffCoordinatorProxy();
        harness = new Phase9PayoffQuoteIdHarness(
            registry, address(policy), MAX_VALIDITY, address(factory), address(coordinator)
        );
        engine = harness;
        coordinator.bind(engine);
        _setCanonicalConfiguration(address(positions), address(token), POLICY_SET);
        _setCanonicalPolicy(POLICY_SET, FEE_BENEFICIARY, ASSET_ID, address(token), true);
    }

    function _trackedExternalHash() private view returns (bytes32) {
        bytes32 allowanceHash = keccak256(
            abi.encode(
                token.allowance(address(engine), LENDER),
                token.allowance(address(engine), FEE_BENEFICIARY),
                token.allowance(address(account), LENDER),
                token.allowance(address(account), FEE_BENEFICIARY),
                token.allowance(address(coordinator), LENDER),
                token.allowance(address(coordinator), FEE_BENEFICIARY)
            )
        );
        bytes32 recipientHash = keccak256(
            abi.encode(
                token.balanceOf(BORROWER),
                token.balanceOf(LENDER),
                token.balanceOf(FEE_BENEFICIARY),
                token.balanceOf(address(positions)),
                BORROWER.balance,
                LENDER.balance,
                FEE_BENEFICIARY.balance,
                address(coordinator).balance
            )
        );
        return keccak256(abi.encode(_externalEffectHash(), allowanceHash, recipientHash));
    }

    function _policyDigest(PolicyMutationFacts memory facts, string memory domain, bool reordered)
        private
        view
        returns (bytes32)
    {
        if (reordered) {
            return keccak256(
                abi.encode(
                    domain,
                    facts.engineAddress,
                    block.chainid,
                    facts.source,
                    facts.loanId,
                    facts.loanAccount,
                    facts.policySet,
                    facts.beneficiary,
                    facts.asset,
                    facts.settlementToken,
                    facts.maximum
                )
            );
        }
        return keccak256(
            abi.encode(
                domain,
                block.chainid,
                facts.engineAddress,
                facts.source,
                facts.loanId,
                facts.loanAccount,
                facts.policySet,
                facts.beneficiary,
                facts.asset,
                facts.settlementToken,
                facts.maximum
            )
        );
    }

    function _routeDigest(RouteMutationFacts memory facts, string memory domain, bool reordered)
        private
        view
        returns (bytes32)
    {
        if (reordered) {
            return keccak256(
                abi.encode(
                    domain,
                    facts.engineAddress,
                    block.chainid,
                    facts.coordinatorAddress,
                    facts.loanId,
                    facts.loanAccount,
                    facts.asset,
                    facts.settlementToken,
                    facts.lender,
                    facts.feeBeneficiary,
                    facts.policyHash
                )
            );
        }
        return keccak256(
            abi.encode(
                domain,
                block.chainid,
                facts.engineAddress,
                facts.coordinatorAddress,
                facts.loanId,
                facts.loanAccount,
                facts.asset,
                facts.settlementToken,
                facts.lender,
                facts.feeBeneficiary,
                facts.policyHash
            )
        );
    }

    function _identity(IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_)
        private
        pure
        returns (Phase9PayoffReference.QuoteIdentityFacts memory)
    {
        return Phase9PayoffReference.QuoteIdentityFacts({
            loanId: quote_.loanId,
            loanAccount: quote_.loanAccount,
            policyHash: quote_.policyHash,
            debtStateVersion: quote_.debtStateVersion,
            principal: quote_.principal,
            accruedInterest: quote_.accruedInterest,
            fees: quote_.fees,
            penalties: quote_.penalties,
            credits: quote_.credits,
            componentBeneficiaryHash: quote_.componentBeneficiaryHash,
            netPayoff: quote_.netPayoff,
            settlementAssetId: quote_.settlementAssetId,
            settlementToken: quote_.settlementToken,
            settlementRouteHash: quote_.settlementRouteHash,
            issuedAt: quote_.issuedAt,
            validUntil: quote_.validUntil,
            quoteNonce: quote_.quoteNonce
        });
    }

    function _expectReplayConflict(
        bytes32 quoteId,
        bytes32 refinanceId,
        uint64 version,
        bytes32 sourceEventId
    ) private {
        (bool success, bytes memory result) =
            _consumeCall(quoteId, refinanceId, version, sourceEventId);
        _assertRevert(success, result, IPayoffQuoteEngineV2.QuoteReplayConflict.selector);
    }
}
