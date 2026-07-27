// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPhase9LoanAccount } from "../src/interfaces/phase9/IPhase9LoanAccount.sol";
import { IPositionManagerV2 } from "../src/interfaces/phase9/IPositionManagerV2.sol";
import { IRefinanceCoordinator } from "../src/interfaces/phase9/IRefinanceCoordinator.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import {
    Phase9BootstrapPolicyResolver,
    Phase9BootstrapUnauthorizedCaller,
    Phase9RefinanceRequestHarness
} from "./Phase9RefinanceBootstrapHarness.sol";

/// @dev D1 evidence for borrower authority, canonical sources, accepted state, and rollback.
contract Phase9RefinanceRequestTest is Phase9RefinanceRequestHarness {
    bytes32 private constant SEED = keccak256("PHASE9_D1_REQUEST");

    function setUp() public {
        _deployRequestHarness(SEED);
    }

    function test_P9R_AUTH001_STATE001_RequestCreatesExactAcceptedGraph() public {
        uint256 borrowerBefore = requestSettlementToken.balanceOf(address(this));
        bytes32 refinanceId = _requestRefinance();
        require(refinanceId != bytes32(0), "refinance id");

        Phase9Types.RefinanceRecord memory stored =
            requestComponents.refinanceCoordinator.refinance(refinanceId);
        require(stored.refinanceId == refinanceId, "stored id");
        require(stored.quoteId != bytes32(0), "quote id");
        require(stored.state == Phase9Types.RefinanceState.ACCEPTED, "accepted state");
        require(stored.stateVersion == 1, "accepted version");
        require(stored.acceptedFunding == 0, "premature funding");
        require(
            stored.oldLoanId == requestRecord.oldLoanId
                && stored.newLoanId == requestRecord.newLoanId,
            "loan bindings"
        );

        address oldAccount = requestComponents.loanFactory.loanAccount(requestRecord.oldLoanId);
        address oldManager =
            requestComponents.loanFactory.positionManager(requestRecord.oldLoanId);
        require(oldAccount == _requestPredictAccount(requestRecord.oldLoanId), "old account");
        require(oldManager.code.length != 0, "old manager");
        require(
            requestLoanRegistry.loanAccount(requestRecord.oldLoanId) == oldAccount,
            "old registry"
        );
        Phase9Types.DebtState memory oldDebt = IPhase9LoanAccount(oldAccount).debtState();
        require(oldDebt.lifecycle == Phase9Types.LoanLifecycle.ACTIVE, "old active");
        require(
            oldDebt.outstandingPrincipal == REQUEST_OLD_PRINCIPAL
                && oldDebt.accruedInterest == REQUEST_OLD_INTEREST,
            "old debt"
        );
        require(IPositionManagerV2(oldManager).positionIds().length == 1, "old positions");
        require(
            requestComponents.collateralCustody.totalCustody(requestCollateralAssetId)
                == REQUEST_COLLATERAL_QUANTITY,
            "custody attribution"
        );
        require(
            requestSettlementToken.balanceOf(address(this))
                == borrowerBefore - REQUEST_COLLATERAL_QUANTITY,
            "borrower collateral delta"
        );
        require(
            requestComponents.lienRegistry.lien(requestCollateralId).seniorLoanId
                == requestRecord.oldLoanId,
            "old senior lien"
        );

        address newAccount = requestComponents.loanFactory.loanAccount(requestRecord.newLoanId);
        address newManager =
            requestComponents.loanFactory.positionManager(requestRecord.newLoanId);
        require(newAccount == _requestPredictAccount(requestRecord.newLoanId), "new account");
        require(newManager == requestRecord.newPositionManager, "new manager");
        Phase9Types.DebtState memory newDebt = IPhase9LoanAccount(newAccount).debtState();
        require(newDebt.lifecycle == Phase9Types.LoanLifecycle.CREATED, "new dormant");
        require(newDebt.servicingState == Phase9Types.ServicingState.NONE, "new servicing");
        require(newDebt.termsVersion == 0 && newDebt.outstandingPrincipal == 0, "new debt");
        require(IPositionManagerV2(newManager).positionIds().length == 0, "new positions");

        bytes32 operationId = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_REQUEST_OPERATION_V1",
                block.chainid,
                address(requestComponents.refinanceCoordinator),
                refinanceId
            )
        );
        require(
            requestComponents.refinanceCoordinator.operationProcessed(operationId),
            "request operation"
        );
    }

    function test_P9R_AUTH001_SubstitutedCallerCannotAccept() public {
        Phase9BootstrapUnauthorizedCaller attacker = new Phase9BootstrapUnauthorizedCaller();
        (bool success, bytes memory returned) = address(attacker).call(
            abi.encodeCall(
                Phase9BootstrapUnauthorizedCaller.requestRefinance,
                (requestComponents.refinanceCoordinator, requestRecord)
            )
        );
        require(!success, "substituted borrower");
        require(
            _requestSelector(returned) == IRefinanceCoordinator.InvalidRefinance.selector,
            "authority selector"
        );
        _assertNoRequestEffects();
    }

    function test_P9R_ID003_EVT002_OuterReplayRejectsBeforeSecondQuote() public {
        bytes32 refinanceId = _requestRefinance();
        Phase9Types.RefinanceRecord memory accepted =
            requestComponents.refinanceCoordinator.refinance(refinanceId);
        uint64 factoryNonce = requestComponents.loanFactory.nextLoanNonce();

        (bool success, bytes memory returned) =
            address(requestComponents.refinanceCoordinator).call(
                abi.encodeCall(IRefinanceCoordinator.requestRefinance, (requestRecord))
            );
        require(!success, "outer replay");
        require(
            _requestSelector(returned) == IRefinanceCoordinator.InvalidRefinance.selector,
            "replay selector"
        );
        require(
            requestComponents.loanFactory.nextLoanNonce() == factoryNonce,
            "replay factory nonce"
        );
        require(
            keccak256(
                abi.encode(requestComponents.refinanceCoordinator.refinance(refinanceId))
            ) == keccak256(abi.encode(accepted)),
            "accepted mutation"
        );
    }

    function test_P9R_STATE001_ID005_ID006_RejectsCallerDerivedAndManagerSubstitution() public {
        Phase9Types.RefinanceRecord memory changed = requestRecord;
        changed.refinanceId = keccak256("CALLER_REFINANCE_ID");
        _expectInvalidRequest(changed);
        changed = requestRecord;
        changed.quoteId = keccak256("CALLER_QUOTE_ID");
        _expectInvalidRequest(changed);
        changed = requestRecord;
        changed.state = Phase9Types.RefinanceState.ACCEPTED;
        _expectInvalidRequest(changed);
        changed = requestRecord;
        changed.newPositionManager = address(0xBAD);
        _expectInvalidRequest(changed);
        _assertNoRequestEffects();
    }

    function test_P9R_SRC004_FAIL002_DependencyFailureRollsBackThenRetrySucceeds() public {
        Phase9BootstrapPolicyResolver.RefinancePolicyRecord memory policy =
            requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash);
        policy.active = false;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, policy);
        _expectInvalidRequest(requestRecord);
        _assertNoRequestEffects();

        policy.active = true;
        requestPolicyResolver.setRefinancePolicy(requestRecord.refinancePolicyHash, policy);
        bytes32 refinanceId = _requestRefinance();
        require(refinanceId != bytes32(0), "retry did not acquire lock");
        require(requestComponents.loanFactory.nextLoanNonce() == 3, "retry graph nonce");
    }

    function test_P9R_TIME001_DeadlineIsHalfOpenAtRequestBoundary() public {
        Phase9Types.RefinanceRecord memory changed = requestRecord;
        changed.expiresAt = uint64(block.timestamp);
        _expectInvalidRequest(changed);
        _assertNoRequestEffects();
    }

    function _expectInvalidRequest(Phase9Types.RefinanceRecord memory supplied) private {
        (bool success, bytes memory returned) =
            address(requestComponents.refinanceCoordinator).call(
                abi.encodeCall(IRefinanceCoordinator.requestRefinance, (supplied))
            );
        require(!success, "expected invalid refinance");
        require(
            _requestSelector(returned) == IRefinanceCoordinator.InvalidRefinance.selector,
            "invalid selector"
        );
    }

    function _assertNoRequestEffects() private view {
        require(requestComponents.loanFactory.nextLoanNonce() == 1, "factory nonce moved");
        require(
            requestComponents.loanFactory.loanAccount(requestRecord.oldLoanId) == address(0),
            "old clone persisted"
        );
        require(
            requestComponents.loanFactory.loanAccount(requestRecord.newLoanId) == address(0),
            "new clone persisted"
        );
        require(
            requestComponents.collateralCustody.totalCustody(requestCollateralAssetId) == 0,
            "custody persisted"
        );
    }
}
