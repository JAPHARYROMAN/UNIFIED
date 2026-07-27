// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRefinanceCoordinator } from "../src/interfaces/phase9/IRefinanceCoordinator.sol";
import { Phase9ImplementationNotFrozen } from "../src/interfaces/phase9/Phase9Errors.sol";
import {
    Phase9RefinanceRequestModule,
    Phase9RefinanceStorageLayout
} from "../src/resolution/RefinanceCoordinator.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import {
    Phase9BootstrapAssetSource,
    Phase9BootstrapEmergencyController,
    Phase9BootstrapPolicyResolver,
    Phase9RefinanceRequestHarness
} from "./Phase9RefinanceBootstrapHarness.sol";

interface Phase9RefinanceFundingVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address caller) external;
    function warp(uint256 timestamp) external;
    function etch(address target, bytes calldata code) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
    function expectCall(address callee, bytes calldata data, uint64 count) external;
}

contract Phase9FundingOversizedReturndata {
    fallback() external {
        assembly ("memory-safe") {
            return(0, 9024)
        }
    }
}

contract Phase9FundingMalformedReturndata {
    fallback() external {
        assembly ("memory-safe") {
            mstore(0, 0x20)
            return(0, 0x20)
        }
    }
}

contract Phase9FundingRevertingDependency {
    fallback() external {
        revert("FORCED_DEPENDENCY_REVERT");
    }
}

contract Phase9FundingStaticReentryProxy {
    error ReentryUnexpectedlySucceeded();
    error ReentryDidNotReachStaticWrite();
    error UpstreamFailure();

    IRefinanceCoordinator private immutable _coordinator;
    address private immutable _upstream;
    uint8 private immutable _route;

    constructor(IRefinanceCoordinator coordinator_, address upstream_, uint8 route_) {
        _coordinator = coordinator_;
        _upstream = upstream_;
        _route = route_;
    }

    fallback() external {
        Phase9Types.RefinanceRecord memory request = probeRequest();
        (bool reentrySucceeded, bytes memory reentryResult) = address(_coordinator)
        .call{ gas: 300_000 }(
            abi.encodeCall(IRefinanceCoordinator.requestRefinance, (request))
        );
        if (reentrySucceeded) revert ReentryUnexpectedlySucceeded();
        // The request is wire-valid and has a fresh lock. An empty exceptional halt is the
        // evidence that STATICCALL reached and rejected the first SSTORE, rather than an
        // earlier typed validator rejecting the request.
        if (reentryResult.length != 0) revert ReentryDidNotReachStaticWrite();

        (bool success, bytes memory returned) = _upstream.staticcall(msg.data);
        if (!success) revert UpstreamFailure();
        assembly ("memory-safe") {
            return(add(returned, 0x20), mload(returned))
        }
    }

    function probeRequest() public view returns (Phase9Types.RefinanceRecord memory request) {
        request.oldLoanId =
            keccak256(abi.encode("PHASE9_STATIC_REENTRY_OLD", address(this), _route));
        request.newLoanId =
            keccak256(abi.encode("PHASE9_STATIC_REENTRY_NEW", address(this), _route));
        request.borrower = address(this);
        request.oldLender = address(0x1E0D3);
        request.newPositionManager = address(0xB0B);
        request.componentBeneficiaryHash = keccak256("PHASE9_STATIC_REENTRY_COMPONENTS");
        request.oldNetPayoff = 1;
        request.newPrincipal = 1;
        request.settlementAssetId =
        0x61737365743a7068617365393a7039756e697400000000000000000000000000;
        request.collateralSetHash = keccak256("PHASE9_STATIC_REENTRY_COLLATERAL");
        request.lienVersion = 1;
        request.proposedTermsHash = keccak256("PHASE9_STATIC_REENTRY_TERMS");
        request.newPolicySetHash = keccak256("PHASE9_STATIC_REENTRY_POLICY_SET");
        request.fundingAmount = 1;
        request.expiresAt = uint64(block.timestamp + 1);
        request.refinanceNonce = 1;
        request.refinancePolicyHash = keccak256("PHASE9_STATIC_REENTRY_POLICY");
        request.newLoanNonce = 1;
    }
}

contract Phase9FundingBeginDelegateProbe {
    bytes4 private constant BEGIN_SELECTOR = 0x3dc005b8;

    function invokeBegin(address module, Phase9Types.RefinanceRecord calldata request)
        external
        returns (bool success, bytes memory returned)
    {
        (success, returned) = module.delegatecall(
            abi.encodeWithSelector(BEGIN_SELECTOR, uint256(0), request)
        );
    }

    function activeLock(bytes32 oldLoanId) external view returns (uint64) {
        return _layout().nextRefinanceNonce[oldLoanId];
    }

    function _layout() private pure returns (Phase9RefinanceStorageLayout storage state) {
        assembly ("memory-safe") {
            state.slot := 0
        }
    }
}

contract Phase9FundingCallbackTokenProbe {
    error CallbackUnexpectedlySucceeded();

    IRefinanceCoordinator private immutable _coordinator;

    constructor(IRefinanceCoordinator coordinator_) {
        _coordinator = coordinator_;
    }

    function balanceOf(address) external returns (uint256) {
        Phase9Types.FundingCommitment memory emptyCommitment;
        (bool callbackSucceeded,) = address(_coordinator)
            .call(abi.encodeCall(IRefinanceCoordinator.recordFundingCommitment, (emptyCommitment)));
        if (callbackSucceeded) revert CallbackUnexpectedlySucceeded();
        return 0;
    }

    function allowance(address, address) external returns (uint256) {
        Phase9Types.RefinanceRecord memory emptyRequest;
        (bool callbackSucceeded,) = address(_coordinator)
            .call(abi.encodeCall(IRefinanceCoordinator.requestRefinance, (emptyRequest)));
        if (callbackSucceeded) revert CallbackUnexpectedlySucceeded();
        return type(uint256).max;
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        (bool callbackSucceeded,) = address(_coordinator)
            .call(
                abi.encodeCall(
                    IRefinanceCoordinator.cancelRefinance,
                    (keccak256("TOKEN_REENTRY"), keccak256("TOKEN_OPERATION"))
                )
            );
        if (callbackSucceeded) revert CallbackUnexpectedlySucceeded();
        return true;
    }
}

/// @dev D2 funding/escrow evidence. D3 execution, cancellation, and refund stay frozen.
contract Phase9RefinanceFundingTest is Phase9RefinanceRequestHarness {
    struct FundingPolicyIdentity {
        uint256 chainId;
        address coordinator;
        address policyRegistry;
        bytes32 oldLoanId;
        bytes32 newLoanId;
        address borrower;
        address oldLender;
        address newPositionManager;
        bytes32 oldPolicySetHash;
        bytes32 newPolicySetHash;
        bytes32 proposedTermsHash;
        bytes32 settlementAssetId;
        bytes32 collateralSetHash;
        uint256 fundingAmount;
        uint256 refinanceFee;
        uint256 borrowerProceeds;
        uint64 expiresAt;
        uint64 maximumValidity;
        uint32 maximumCommitments;
        bytes32 collateralIdsHash;
        bytes32 replacementDebtHash;
        bytes32 replacementTranchesHash;
        bytes32 replacementPositionsHash;
    }

    bytes32 private constant SEED = keccak256("PHASE9_D2_FUNDING");
    bytes32 private constant REQUEST_CAPABILITY = keccak256("CAPABILITY_PHASE9_REFINANCE_REQUEST");
    bytes32 private constant FUNDING_CAPABILITY = keccak256("CAPABILITY_PHASE9_REFINANCE_FUNDING");
    bytes32 private constant COMMITMENT_EVENT =
        keccak256("RefinanceCommitmentRecorded(bytes32,bytes32,address,uint256)");
    bytes32 private constant TRANSITION_EVENT =
        keccak256("RefinanceStateTransitioned(bytes32,uint8,uint8,uint64,bytes32,bytes32)");
    bytes32 private constant TRANSFER_EVENT = keccak256("Transfer(address,address,uint256)");
    Phase9RefinanceFundingVm private constant vm =
        Phase9RefinanceFundingVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private fundingTrancheId;

    function setUp() public {
        _deployRequestHarness(SEED);
        _configureFundingPositions(2);
    }

    function test_P9R_FUND001_FUND002_AUTH002_STATE002_EVT001_ExactPartialAndFullFunding() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9Types.FundingCommitment memory first = _commitment(refinanceId, 0, 90, 1);

        uint256 coordinatorBefore =
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator));
        uint256 funderBefore = requestSettlementToken.balanceOf(REQUEST_NEW_LENDER);
        vm.recordLogs();
        _recordAs(REQUEST_NEW_LENDER, first);
        Phase9RefinanceFundingVm.Log[] memory logs = vm.getRecordedLogs();

        _assertFundingState(refinanceId, first, 90, 90, 1, 2);
        require(
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator))
                == coordinatorBefore + 90,
            "first coordinator delta"
        );
        require(
            requestSettlementToken.balanceOf(REQUEST_NEW_LENDER) == funderBefore - 90,
            "first funder delta"
        );
        _assertFundingEvents(logs, refinanceId, first, 90, 90, 1, 2, true);

        Phase9Types.FundingCommitment memory second = _commitment(refinanceId, 1, 30, 2);
        vm.recordLogs();
        _recordAs(REQUEST_NEW_LENDER, second);
        logs = vm.getRecordedLogs();
        _assertFundingState(refinanceId, second, 120, 120, 2, 3);
        _assertFundingEvents(logs, refinanceId, second, 120, 120, 2, 3, false);

        Phase9Types.RefinanceRecord memory stored =
            requestComponents.refinanceCoordinator.refinance(refinanceId);
        require(stored.state == Phase9Types.RefinanceState.FUNDING_ESCROWED, "full state");
        require(stored.acceptedFunding == stored.fundingAmount, "full readiness");
        require(
            requestComponents.refinanceCoordinator.terminalResult(refinanceId).resultHash
                == bytes32(0),
            "premature terminal result"
        );
    }

    function test_P9R_FUND003_AUTH007_EVT002_ReplayAndConflictPrecedePauseAndAuthority() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9Types.FundingCommitment memory first = _commitment(refinanceId, 0, 90, 1);
        _recordAs(REQUEST_NEW_LENDER, first);
        bytes32 stateHashBefore = _fundingStateHash(refinanceId, first.commitmentId);
        uint256 coordinatorBefore =
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator));

        requestEmergencyController.setEmergencyState(
            FUNDING_CAPABILITY, true, uint64(block.timestamp + 100), keccak256("PAUSED")
        );
        vm.recordLogs();
        _recordAs(address(0xBAD), first);
        require(vm.getRecordedLogs().length == 0, "replay event");
        require(
            _fundingStateHash(refinanceId, first.commitmentId) == stateHashBefore, "replay mutation"
        );
        require(
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator))
                == coordinatorBefore,
            "replay transfer"
        );

        Phase9Types.FundingCommitment memory changed = first;
        changed.commitmentNonce = 99;
        _expectFundingFailure(
            address(0xBAD), changed, IRefinanceCoordinator.RefinanceReplayConflict.selector
        );

        Phase9Types.FundingCommitment memory second = _commitment(refinanceId, 1, 30, 2);
        _expectFundingFailure(
            REQUEST_NEW_LENDER, second, IRefinanceCoordinator.InvalidRefinance.selector
        );
        requestEmergencyController.setEmergencyState(FUNDING_CAPABILITY, false, 0, bytes32(0));
        _recordAs(REQUEST_NEW_LENDER, second);
    }

    function test_P9R_FUND001_FUND003_FUND005_AUTH002_InvalidInputsAndAllocationAreAtomic() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9Types.FundingCommitment memory canonical = _commitment(refinanceId, 0, 90, 1);

        Phase9Types.FundingCommitment memory changed = canonical;
        changed.state = Phase9Types.FundingCommitmentState.FUNDED;
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.fundingResultHash = keccak256("CALLER_RESULT");
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.commitmentId = keccak256("WRONG_COMMITMENT_ID");
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.commitmentDigest = keccak256("WRONG_COMMITMENT_DIGEST");
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.positionId = bytes32(uint256(2));
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.amount = 89;
        changed = _rewireCommitment(changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.trancheId = keccak256("WRONG_TRANCHE");
        changed = _rewireCommitment(changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.funder = address(0xBAD);
        changed = _rewireCommitment(changed);
        _expectInvalidNoFunding(refinanceId, address(0xBAD), changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.commitmentNonce = 0;
        changed = _rewireCommitment(changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.positionId = bytes32(0);
        changed = _rewireCommitment(changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.amount = 0;
        changed = _rewireCommitment(changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.commitmentId = bytes32(0);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, changed);
        canonical = _commitment(refinanceId, 0, 90, 1);
        _expectInvalidNoFunding(refinanceId, address(0xBAD), canonical);

        _recordAs(REQUEST_NEW_LENDER, canonical);
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.state = Phase9Types.FundingCommitmentState.FUNDED;
        _expectFundingFailure(
            REQUEST_NEW_LENDER, changed, IRefinanceCoordinator.RefinanceReplayConflict.selector
        );
        changed = _commitment(refinanceId, 0, 90, 1);
        changed.fundingResultHash = keccak256("CHANGED_REPLAY_RESULT");
        _expectFundingFailure(
            REQUEST_NEW_LENDER, changed, IRefinanceCoordinator.RefinanceReplayConflict.selector
        );
        Phase9Types.FundingCommitment memory duplicatePosition = _commitment(refinanceId, 0, 90, 7);
        _expectFundingFailure(
            REQUEST_NEW_LENDER, duplicatePosition, IRefinanceCoordinator.InvalidRefinance.selector
        );
    }

    function test_P9R_FUND004_DON001_AllowanceFailureAndDonationDoNotCreateEscrow() public {
        bytes32 refinanceId = _requestRefinance();
        requestSettlementToken.transfer(address(requestComponents.refinanceCoordinator), 17);
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == 0,
            "donation escrow"
        );
        require(
            requestComponents.refinanceCoordinator.commitmentIds(refinanceId).length == 0,
            "donation commitment"
        );

        requestSettlementToken.transfer(REQUEST_NEW_LENDER, REQUEST_NEW_PRINCIPAL);
        Phase9Types.FundingCommitment memory first = _commitment(refinanceId, 0, 90, 1);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, first);

        vm.prank(REQUEST_NEW_LENDER);
        requestSettlementToken.approve(
            address(requestComponents.refinanceCoordinator), REQUEST_NEW_PRINCIPAL
        );
        uint256 globalBefore =
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator));
        _recordAs(REQUEST_NEW_LENDER, first);
        require(
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator))
                == globalBefore + 90,
            "donation changed operation delta"
        );
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == 90,
            "attributed escrow"
        );

        requestSettlementToken.transfer(address(requestComponents.refinanceCoordinator), 11);
        uint256 partialBalance =
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator));
        Phase9Types.FundingCommitment memory second = _commitment(refinanceId, 1, 30, 2);
        _recordAs(REQUEST_NEW_LENDER, second);
        require(
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator))
                == partialBalance + 30,
            "full donation changed operation delta"
        );
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId)
                == REQUEST_NEW_PRINCIPAL,
            "full attributed escrow"
        );
        require(
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator))
                    - requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == 28,
            "donation surplus drift"
        );
    }

    function test_P9R_AUTH007_TIME001_RequestPauseDoesNotBlockFundingAndExpiryIsHalfOpen() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        requestEmergencyController.setEmergencyState(
            REQUEST_CAPABILITY, true, uint64(block.timestamp + 100), keccak256("REQUEST_ONLY")
        );
        Phase9Types.FundingCommitment memory first = _commitment(refinanceId, 0, 90, 1);
        _recordAs(REQUEST_NEW_LENDER, first);

        vm.warp(requestRecord.expiresAt);
        _recordAs(address(0xBAD), first);
        Phase9Types.FundingCommitment memory second = _commitment(refinanceId, 1, 30, 2);
        _expectFundingFailure(
            REQUEST_NEW_LENDER, second, IRefinanceCoordinator.InvalidRefinance.selector
        );
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == 90,
            "expiry escrow mutation"
        );
    }

    function test_P9R_FUND005_MaximumThirtyTwoCommitmentsAndNoThirtyThird() public {
        _configureFundingPositions(32);
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        uint256 funded;
        for (uint256 i = 0; i < 32; ++i) {
            uint256 amount = i == 31 ? 89 : 1;
            _recordAs(REQUEST_NEW_LENDER, _commitment(refinanceId, i, amount, uint64(i + 1)));
            funded += amount;
        }
        require(funded == REQUEST_NEW_PRINCIPAL, "fixture funding");
        require(
            requestComponents.refinanceCoordinator.commitmentIds(refinanceId).length == 32,
            "commitment cap"
        );
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId)
                == REQUEST_NEW_PRINCIPAL,
            "cap escrow"
        );

        Phase9Types.FundingCommitment memory thirtyThird = Phase9Types.FundingCommitment({
            commitmentId: bytes32(0),
            refinanceId: refinanceId,
            positionId: bytes32(uint256(33)),
            trancheId: fundingTrancheId,
            funder: REQUEST_NEW_LENDER,
            amount: 1,
            commitmentNonce: 33,
            commitmentDigest: bytes32(0),
            state: Phase9Types.FundingCommitmentState.NONE,
            fundingResultHash: bytes32(0)
        });
        thirtyThird.commitmentId = _commitmentId(thirtyThird);
        thirtyThird.commitmentDigest = _commitmentDigest(thirtyThird);
        _expectFundingFailure(
            REQUEST_NEW_LENDER, thirtyThird, IRefinanceCoordinator.InvalidRefinance.selector
        );
    }

    function test_P9R_VIEW001_UnknownViewsUseTypedErrorsAndKnownNonterminalIsZero() public {
        bytes32 unknown = keccak256("UNKNOWN");
        _expectViewFailure(
            abi.encodeCall(IRefinanceCoordinator.refinance, (unknown)),
            IRefinanceCoordinator.UnknownRefinance.selector
        );
        _expectViewFailure(
            abi.encodeCall(IRefinanceCoordinator.commitmentIds, (unknown)),
            IRefinanceCoordinator.UnknownRefinance.selector
        );
        _expectViewFailure(
            abi.encodeCall(IRefinanceCoordinator.escrowedUnits, (unknown)),
            IRefinanceCoordinator.UnknownRefinance.selector
        );
        _expectViewFailure(
            abi.encodeCall(IRefinanceCoordinator.terminalResult, (unknown)),
            IRefinanceCoordinator.UnknownRefinance.selector
        );
        _expectViewFailure(
            abi.encodeCall(IRefinanceCoordinator.fundingCommitment, (unknown)),
            IRefinanceCoordinator.UnknownFundingCommitment.selector
        );

        bytes32 refinanceId = _requestRefinance();
        require(
            requestComponents.refinanceCoordinator.commitmentIds(refinanceId).length == 0,
            "known empty commitments"
        );
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == 0,
            "known empty escrow"
        );
        Phase9Types.RefinanceTerminalResult memory terminal =
            requestComponents.refinanceCoordinator.terminalResult(refinanceId);
        require(terminal.resultHash == bytes32(0), "known nonterminal result");
        require(
            !requestComponents.refinanceCoordinator.operationProcessed(unknown),
            "unknown operation membership"
        );
    }

    function test_P9R_FAIL001_OversizedMalformedAndRevertingDependenciesFailAtomically() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9Types.FundingCommitment memory commitment = _commitment(refinanceId, 0, 90, 1);

        address[3] memory targets = [
            address(requestPolicyResolver),
            address(requestEmergencyController),
            address(requestAssetSource)
        ];
        bytes[3] memory hostileCode = [
            address(new Phase9FundingOversizedReturndata()).code,
            address(new Phase9FundingMalformedReturndata()).code,
            address(new Phase9FundingRevertingDependency()).code
        ];
        for (uint256 targetIndex = 0; targetIndex < targets.length; ++targetIndex) {
            bytes memory originalCode = targets[targetIndex].code;
            for (uint256 codeIndex = 0; codeIndex < hostileCode.length; ++codeIndex) {
                vm.etch(targets[targetIndex], hostileCode[codeIndex]);
                _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, commitment);
            }
            vm.etch(targets[targetIndex], originalCode);
        }
    }

    function test_P9R_FAIL004_SufficientAllowanceInsufficientBalanceRollsBackProvisionalFunding()
        public
    {
        bytes32 refinanceId = _requestRefinance();
        requestSettlementToken.transfer(REQUEST_NEW_LENDER, 89);
        vm.prank(REQUEST_NEW_LENDER);
        requestSettlementToken.approve(address(requestComponents.refinanceCoordinator), 90);
        Phase9Types.FundingCommitment memory commitment = _commitment(refinanceId, 0, 90, 1);

        require(
            requestSettlementToken.allowance(
                REQUEST_NEW_LENDER, address(requestComponents.refinanceCoordinator)
            ) == 90,
            "failure allowance fixture"
        );
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, commitment);
    }

    function test_P9R_FUND002_ComposedAllocationInvariantRejectsWouldBeOverfund() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL + 1);
        _recordAs(REQUEST_NEW_LENDER, _commitment(refinanceId, 0, 90, 1));

        // A commitment above the remaining 30 units cannot also match its canonical
        // position's exact 30-unit claim. The allocation bijection therefore rejects this
        // composed overfund attempt before the defensive arithmetic ceiling is reachable.
        Phase9Types.FundingCommitment memory aboveRemaining = _commitment(refinanceId, 1, 31, 2);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, aboveRemaining);
    }

    function test_P9R_FUND005_AcceptedPolicyIdentityDriftFailsBeforeDeeperValidators() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9Types.FundingCommitment memory commitment = _commitment(refinanceId, 0, 90, 1);
        // Each mutation changes the accepted policy preimage. These cases prove the outer
        // policy-identity seal, not reachability of the deeper per-position validators.
        Phase9BootstrapPolicyResolver.RefinancePolicyRecord memory changed =
            requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash);
        changed.replacementPositions[1].positionId = changed.replacementPositions[0].positionId;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, commitment);
        changed.replacementPositions[1].positionId = bytes32(uint256(2));
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, changed);

        changed = requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash);
        changed.replacementPositions[1].state = Phase9Types.PositionState.NONE;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, commitment);
        changed.replacementPositions[1].state = Phase9Types.PositionState.ACTIVE;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, changed);

        changed = requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash);
        changed.replacementPositions[1].claim = 29;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, commitment);
        changed.replacementPositions[1].claim = 30;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, changed);

        changed = requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash);
        changed.replacementTranches[0].outstandingClaim = 119;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, changed);
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, commitment);
    }

    function test_P9R_FAIL002_PolicyResolverStaticReentryCannotCompleteStateChange() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9BootstrapPolicyResolver mirror = new Phase9BootstrapPolicyResolver();
        mirror.setRefinancePolicy(
            requestRecord.refinancePolicyHash,
            requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash)
        );
        _fundThroughStaticReentryProxy(
            refinanceId, address(requestPolicyResolver), address(mirror), 0
        );
    }

    function test_P9R_FAIL002_EmergencyControllerStaticReentryCannotCompleteStateChange() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9BootstrapEmergencyController mirror = new Phase9BootstrapEmergencyController();
        _fundThroughStaticReentryProxy(
            refinanceId, address(requestEmergencyController), address(mirror), 1
        );
    }

    function test_P9R_FAIL002_AssetResolverStaticReentryCannotCompleteStateChange() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9BootstrapAssetSource mirror = new Phase9BootstrapAssetSource();
        mirror.setAsset(
            requestRecord.settlementAssetId,
            Phase9BootstrapAssetSource.AssetRecord({
                token: address(requestSettlementToken),
                decimals: 6,
                runtimeCodeHash: address(requestSettlementToken).codehash,
                exactBalanceDelta: true,
                active: true
            })
        );
        _fundThroughStaticReentryProxy(refinanceId, address(requestAssetSource), address(mirror), 2);
    }

    function test_P9R_FAIL002_SubstitutedCallbackTokenRejectedBeforeAnyCallToSubstitute() public {
        bytes32 refinanceId = _requestRefinance();
        _fundLenderAndApprove(REQUEST_NEW_PRINCIPAL);
        Phase9FundingCallbackTokenProbe callbackToken =
            new Phase9FundingCallbackTokenProbe(requestComponents.refinanceCoordinator);
        require(
            address(callbackToken).codehash != address(requestSettlementToken).codehash,
            "callback runtime unexpectedly canonical"
        );
        requestAssetSource.setAsset(
            requestRecord.settlementAssetId,
            Phase9BootstrapAssetSource.AssetRecord({
                token: address(callbackToken),
                decimals: 6,
                runtimeCodeHash: address(callbackToken).codehash,
                exactBalanceDelta: true,
                active: true
            })
        );
        vm.expectCall(
            address(callbackToken),
            abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)"))),
            0
        );
        vm.expectCall(
            address(callbackToken),
            abi.encodeWithSelector(bytes4(keccak256("allowance(address,address)"))),
            0
        );
        vm.expectCall(
            address(callbackToken),
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)"))),
            0
        );
        _expectInvalidNoFunding(refinanceId, REQUEST_NEW_LENDER, _commitment(refinanceId, 0, 90, 1));
    }

    function test_D3MutatorsRemainExactFreezeStubs() public {
        bytes32 id = keccak256("D3_STUB");
        _expectD3Freeze(abi.encodeCall(IRefinanceCoordinator.executeRefinance, (id, id)));
        _expectD3Freeze(abi.encodeCall(IRefinanceCoordinator.cancelRefinance, (id, id)));
        _expectD3Freeze(abi.encodeCall(IRefinanceCoordinator.refundCommitment, (id, id)));
    }

    function _configureFundingPositions(uint32 count) private {
        Phase9BootstrapPolicyResolver.RefinancePolicyRecord memory policy =
            requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash);
        fundingTrancheId = policy.replacementTranches[0].trancheId;
        policy.maximumCommitments = count;
        policy.replacementPositions = new Phase9Types.Position[](count);
        for (uint256 i = 0; i < count; ++i) {
            uint256 claim;
            if (count == 2) claim = i == 0 ? 90 : 30;
            else if (count == 32) claim = i == 31 ? 89 : 1;
            else claim = REQUEST_NEW_PRINCIPAL;
            policy.replacementPositions[i] = Phase9Types.Position({
                positionId: bytes32(i + 1),
                trancheId: fundingTrancheId,
                owner: REQUEST_NEW_LENDER,
                votingPower: claim,
                claim: claim,
                state: Phase9Types.PositionState.ACTIVE
            });
        }

        FundingPolicyIdentity memory identity = FundingPolicyIdentity({
            chainId: block.chainid,
            coordinator: address(requestComponents.refinanceCoordinator),
            policyRegistry: address(requestPolicyResolver),
            oldLoanId: requestRecord.oldLoanId,
            newLoanId: requestRecord.newLoanId,
            borrower: requestRecord.borrower,
            oldLender: requestRecord.oldLender,
            newPositionManager: requestRecord.newPositionManager,
            oldPolicySetHash: policy.boundOldPolicySetHash,
            newPolicySetHash: policy.boundNewPolicySetHash,
            proposedTermsHash: policy.proposedTermsHash,
            settlementAssetId: requestRecord.settlementAssetId,
            collateralSetHash: requestRecord.collateralSetHash,
            fundingAmount: requestRecord.fundingAmount,
            refinanceFee: requestRecord.refinanceFee,
            borrowerProceeds: requestRecord.borrowerProceeds,
            expiresAt: requestRecord.expiresAt,
            maximumValidity: policy.maximumValidity,
            maximumCommitments: policy.maximumCommitments,
            collateralIdsHash: keccak256(abi.encode(policy.collateralIds)),
            replacementDebtHash: keccak256(abi.encode(policy.replacementDebt)),
            replacementTranchesHash: keccak256(abi.encode(policy.replacementTranches)),
            replacementPositionsHash: keccak256(abi.encode(policy.replacementPositions))
        });
        bytes32 policyHash = keccak256(abi.encode("UNIFIED_REFINANCE_POLICY_V1", identity));
        requestRecord.refinancePolicyHash = policyHash;
        requestPolicyResolver.setRefinancePolicy(policyHash, policy);
    }

    function _commitment(bytes32 refinanceId, uint256 positionIndex, uint256 amount, uint64 nonce)
        private
        view
        returns (Phase9Types.FundingCommitment memory commitment)
    {
        commitment.refinanceId = refinanceId;
        commitment.positionId = bytes32(positionIndex + 1);
        commitment.trancheId = fundingTrancheId;
        commitment.funder = REQUEST_NEW_LENDER;
        commitment.amount = amount;
        commitment.commitmentNonce = nonce;
        commitment.commitmentId = _commitmentId(commitment);
        commitment.commitmentDigest = _commitmentDigest(commitment);
    }

    function _commitmentId(Phase9Types.FundingCommitment memory commitment)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_FUNDING_COMMITMENT_V1",
                commitment.refinanceId,
                commitment.positionId,
                commitment.trancheId,
                commitment.funder,
                commitment.amount,
                commitment.commitmentNonce
            )
        );
    }

    function _commitmentDigest(Phase9Types.FundingCommitment memory commitment)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_FUNDING_COMMITMENT_DIGEST_V1",
                block.chainid,
                address(requestComponents.refinanceCoordinator),
                commitment.commitmentId,
                commitment.refinanceId,
                commitment.positionId,
                commitment.trancheId,
                commitment.funder,
                commitment.amount,
                commitment.commitmentNonce,
                requestRecord.refinancePolicyHash,
                requestRecord.expiresAt
            )
        );
    }

    function _rewireCommitment(Phase9Types.FundingCommitment memory commitment)
        private
        view
        returns (Phase9Types.FundingCommitment memory)
    {
        commitment.commitmentId = _commitmentId(commitment);
        commitment.commitmentDigest = _commitmentDigest(commitment);
        return commitment;
    }

    function _fundLenderAndApprove(uint256 amount) private {
        requestSettlementToken.transfer(REQUEST_NEW_LENDER, amount);
        vm.prank(REQUEST_NEW_LENDER);
        requestSettlementToken.approve(address(requestComponents.refinanceCoordinator), amount);
    }

    function _recordAs(address caller, Phase9Types.FundingCommitment memory commitment) private {
        vm.prank(caller);
        requestComponents.refinanceCoordinator.recordFundingCommitment(commitment);
    }

    function _fundThroughStaticReentryProxy(
        bytes32 refinanceId,
        address target,
        address upstream,
        uint8 route
    ) private {
        bytes memory originalCode = target.code;
        Phase9FundingStaticReentryProxy proxy = new Phase9FundingStaticReentryProxy(
            requestComponents.refinanceCoordinator, upstream, route
        );
        vm.etch(target, address(proxy).code);
        Phase9Types.RefinanceRecord memory probeRequest =
            Phase9FundingStaticReentryProxy(target).probeRequest();
        Phase9FundingBeginDelegateProbe beginProbe = new Phase9FundingBeginDelegateProbe();
        vm.prank(target);
        (bool beginSucceeded, bytes memory beginResult) =
            beginProbe.invokeBegin(address(Phase9RefinanceRequestModule), probeRequest);
        require(beginSucceeded && beginResult.length == 0, "wire-valid reentry probe");
        require(
            beginProbe.activeLock(probeRequest.oldLoanId) == (uint64(1) << 63 | uint64(1)),
            "reentry probe did not write"
        );
        vm.expectCall(
            address(requestComponents.refinanceCoordinator),
            abi.encodeCall(IRefinanceCoordinator.requestRefinance, (probeRequest)),
            1
        );
        _recordAs(REQUEST_NEW_LENDER, _commitment(refinanceId, 0, 90, 1));
        vm.etch(target, originalCode);
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == 90,
            "reentry funding failed"
        );
    }

    function _expectInvalidNoFunding(
        bytes32 refinanceId,
        address caller,
        Phase9Types.FundingCommitment memory commitment
    ) private {
        bytes32 beforeHash = _fundingFailureHash(refinanceId, commitment);
        vm.recordLogs();
        _expectFundingFailure(caller, commitment, IRefinanceCoordinator.InvalidRefinance.selector);
        require(vm.getRecordedLogs().length == 0, "failed funding event");
        require(
            _fundingFailureHash(refinanceId, commitment) == beforeHash, "invalid funding effect"
        );
    }

    function _expectFundingFailure(
        address caller,
        Phase9Types.FundingCommitment memory commitment,
        bytes4 expectedSelector
    ) private {
        vm.prank(caller);
        (bool success, bytes memory returned) = address(requestComponents.refinanceCoordinator)
            .call(abi.encodeCall(IRefinanceCoordinator.recordFundingCommitment, (commitment)));
        require(!success, "expected funding failure");
        require(_selector(returned) == expectedSelector, "funding failure selector");
    }

    function _assertFundingState(
        bytes32 refinanceId,
        Phase9Types.FundingCommitment memory commitment,
        uint256 acceptedFunding,
        uint256 escrow,
        uint256 count,
        uint64 stateVersion
    ) private view {
        Phase9Types.RefinanceRecord memory stored =
            requestComponents.refinanceCoordinator.refinance(refinanceId);
        require(stored.state == Phase9Types.RefinanceState.FUNDING_ESCROWED, "funding state");
        require(stored.stateVersion == stateVersion, "funding version");
        require(stored.acceptedFunding == acceptedFunding, "accepted funding");
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == escrow, "escrow"
        );
        require(
            requestComponents.refinanceCoordinator.commitmentIds(refinanceId).length == count,
            "commitment count"
        );
        Phase9Types.FundingCommitment memory storedCommitment =
            requestComponents.refinanceCoordinator.fundingCommitment(commitment.commitmentId);
        require(
            storedCommitment.state == Phase9Types.FundingCommitmentState.FUNDED, "commitment state"
        );
        require(storedCommitment.fundingResultHash != bytes32(0), "funding result");
        require(
            requestComponents.refinanceCoordinator.operationProcessed(commitment.commitmentId),
            "funding operation"
        );
    }

    function _assertFundingEvents(
        Phase9RefinanceFundingVm.Log[] memory logs,
        bytes32 refinanceId,
        Phase9Types.FundingCommitment memory commitment,
        uint256 acceptedFunding,
        uint256 escrow,
        uint256 count,
        uint64 stateVersion,
        bool first
    ) private view {
        bytes32 expectedFundingResult = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_FUNDING_RESULT_V1",
                block.chainid,
                address(requestComponents.refinanceCoordinator),
                refinanceId,
                commitment.commitmentId,
                commitment.funder,
                commitment.amount,
                commitment.commitmentNonce,
                acceptedFunding,
                escrow,
                count,
                Phase9Types.RefinanceState.FUNDING_ESCROWED,
                stateVersion
            )
        );
        Phase9Types.RefinanceState previous = first
            ? Phase9Types.RefinanceState.ACCEPTED
            : Phase9Types.RefinanceState.FUNDING_ESCROWED;
        bytes32 expectedTransition = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_STATE_TRANSITION_V1",
                block.chainid,
                address(requestComponents.refinanceCoordinator),
                refinanceId,
                previous,
                Phase9Types.RefinanceState.FUNDING_ESCROWED,
                stateVersion,
                commitment.commitmentId,
                expectedFundingResult
            )
        );

        require(logs.length == 3, "funding event inventory");
        require(
            logs[0].emitter == address(requestSettlementToken)
                && logs[0].topics[0] == TRANSFER_EVENT,
            "funding transfer order"
        );
        require(
            logs[1].emitter == address(requestComponents.refinanceCoordinator)
                && logs[1].topics[0] == COMMITMENT_EVENT,
            "commitment event order"
        );
        require(
            logs[2].emitter == address(requestComponents.refinanceCoordinator)
                && logs[2].topics[0] == TRANSITION_EVENT,
            "transition event order"
        );

        uint256 coordinatorLogs;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(requestComponents.refinanceCoordinator)) continue;
            ++coordinatorLogs;
            if (logs[i].topics[0] == COMMITMENT_EVENT) {
                require(logs[i].topics[1] == refinanceId, "commitment event refinance");
                require(logs[i].topics[2] == commitment.commitmentId, "commitment event id");
                require(
                    address(uint160(uint256(logs[i].topics[3]))) == commitment.funder,
                    "commitment event funder"
                );
                require(abi.decode(logs[i].data, (uint256)) == commitment.amount, "event amount");
            } else {
                require(logs[i].topics[0] == TRANSITION_EVENT, "unexpected event");
                require(logs[i].topics[1] == refinanceId, "transition refinance");
                require(uint256(logs[i].topics[2]) == uint256(previous), "previous state");
                require(
                    uint256(logs[i].topics[3])
                        == uint256(Phase9Types.RefinanceState.FUNDING_ESCROWED),
                    "next state"
                );
                (uint64 version, bytes32 operationId, bytes32 evidenceHash) =
                    abi.decode(logs[i].data, (uint64, bytes32, bytes32));
                require(version == stateVersion, "transition version");
                require(operationId == commitment.commitmentId, "transition operation");
                require(evidenceHash == expectedTransition, "transition evidence");
            }
        }
        require(coordinatorLogs == 2, "coordinator event count");
        require(
            requestComponents.refinanceCoordinator
            .fundingCommitment(commitment.commitmentId)
            .fundingResultHash == expectedFundingResult,
            "stored funding result"
        );
    }

    function _refinanceFundingHash(bytes32 refinanceId) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                requestComponents.refinanceCoordinator.refinance(refinanceId),
                requestComponents.refinanceCoordinator.commitmentIds(refinanceId),
                requestComponents.refinanceCoordinator.escrowedUnits(refinanceId),
                requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator)),
                requestSettlementToken.balanceOf(REQUEST_NEW_LENDER)
            )
        );
    }

    function _fundingFailureHash(
        bytes32 refinanceId,
        Phase9Types.FundingCommitment memory commitment
    ) private view returns (bytes32) {
        (bool commitmentKnown, bytes memory commitmentResult) = address(
                requestComponents.refinanceCoordinator
            )
            .staticcall(
                abi.encodeCall(IRefinanceCoordinator.fundingCommitment, (commitment.commitmentId))
            );
        return keccak256(
            abi.encode(
                _refinanceFundingHash(refinanceId),
                commitmentKnown,
                keccak256(commitmentResult),
                requestComponents.refinanceCoordinator.operationProcessed(commitment.commitmentId),
                requestSettlementToken.balanceOf(commitment.funder),
                requestSettlementToken.allowance(
                    commitment.funder, address(requestComponents.refinanceCoordinator)
                )
            )
        );
    }

    function _fundingStateHash(bytes32 refinanceId, bytes32 commitmentId)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _refinanceFundingHash(refinanceId),
                requestComponents.refinanceCoordinator.fundingCommitment(commitmentId),
                requestComponents.refinanceCoordinator.operationProcessed(commitmentId)
            )
        );
    }

    function _expectViewFailure(bytes memory callData, bytes4 expectedSelector) private view {
        (bool success, bytes memory returned) =
            address(requestComponents.refinanceCoordinator).staticcall(callData);
        require(!success, "expected view failure");
        require(_selector(returned) == expectedSelector, "view selector");
    }

    function _expectD3Freeze(bytes memory callData) private {
        (bool success, bytes memory returned) =
            address(requestComponents.refinanceCoordinator).call(callData);
        require(!success, "D3 mutator opened");
        require(_selector(returned) == Phase9ImplementationNotFrozen.selector, "D3 freeze selector");
    }

    function _selector(bytes memory returned) private pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
