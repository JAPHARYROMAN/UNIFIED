// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRefinanceCoordinator } from "../src/interfaces/phase9/IRefinanceCoordinator.sol";
import { ILienRegistry } from "../src/interfaces/phase9/ILienRegistry.sol";
import { Phase9ImplementationNotFrozen } from "../src/interfaces/phase9/Phase9Errors.sol";
import {
    Phase9RefinanceLifecycleModule,
    Phase9RefinanceRequestModule,
    Phase9RefinanceStorageLayout,
    Phase9RefinanceValidationContext,
    Phase9RefinanceValidationModule
} from "../src/resolution/RefinanceCoordinator.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import {
    Phase9BootstrapPolicyResolver,
    Phase9RefinanceRequestHarness
} from "./Phase9RefinanceBootstrapHarness.sol";

interface Phase9RefinanceModuleIsolationVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
    function prank(address caller) external;
    function expectCall(address callee, bytes calldata data, uint64 count) external;
}

contract Phase9RefinanceHostileDelegateHost {
    function configureFundingDependencies(
        address policyRegistry,
        address assetRegistry,
        address emergencyController,
        IERC20 settlementToken
    ) external {
        Phase9RefinanceStorageLayout storage state = _layout();
        state.policyRegistry = policyRegistry;
        state.assetRegistry = assetRegistry;
        state.emergencyController = emergencyController;
        state.settlementToken = settlementToken;
    }

    function installAcceptedRefinance(Phase9Types.RefinanceRecord calldata refinance_) external {
        _layout().refinances[refinance_.refinanceId] = refinance_;
    }

    function invoke(address module, bytes calldata input)
        external
        returns (bool success, bytes memory returned)
    {
        (success, returned) = module.delegatecall(input);
    }

    function activeLock(bytes32 oldLoanId) external view returns (uint64) {
        return _layout().nextRefinanceNonce[oldLoanId];
    }

    function refinance(bytes32 refinanceId)
        external
        view
        returns (Phase9Types.RefinanceRecord memory)
    {
        return _layout().refinances[refinanceId];
    }

    function fundingCommitment(bytes32 commitmentId)
        external
        view
        returns (Phase9Types.FundingCommitment memory)
    {
        return _layout().commitments[commitmentId];
    }

    function commitmentIds(bytes32 refinanceId) external view returns (bytes32[] memory) {
        return _layout().commitmentIds[refinanceId];
    }

    function escrowedUnits(bytes32 refinanceId) external view returns (uint256) {
        return _layout().escrowedUnits[refinanceId];
    }

    function operationProcessed(bytes32 operationId) external view returns (bool) {
        return _layout().processedOperationIds[operationId];
    }

    function _layout() private pure returns (Phase9RefinanceStorageLayout storage state) {
        assembly ("memory-safe") {
            state.slot := 0
        }
    }
}

contract Phase9RefinanceModuleIsolationTest is Phase9RefinanceRequestHarness {
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

    struct IsolationSnapshot {
        uint256 coordinatorBalance;
        uint256 hostBalance;
        uint256 funderBalance;
        uint256 hostAllowance;
        uint256 coordinatorAllowance;
        bytes32 coordinatorRefinanceResultHash;
        bytes32 coordinatorCommitmentResultHash;
    }

    bytes4 private constant VALIDATION_SELECTOR = 0x4f9ee1ee;
    bytes4 private constant BEGIN_SELECTOR = 0x3dc005b8;
    bytes4 private constant COMPLETE_SELECTOR = 0x0be276bb;
    bytes4 private constant RECORD_SELECTOR = 0xb145df9d;
    bytes4 private constant EXECUTE_SELECTOR = 0xec32f45f;
    bytes4 private constant CANCEL_SELECTOR = 0x9521f7f9;
    bytes4 private constant REFUND_SELECTOR = 0x8e2b3054;
    bytes32 private constant SEED = keccak256("PHASE9_MODULE_ISOLATION");
    bytes32 private constant COMMITMENT_EVENT =
        keccak256("RefinanceCommitmentRecorded(bytes32,bytes32,address,uint256)");
    bytes32 private constant TRANSITION_EVENT =
        keccak256("RefinanceStateTransitioned(bytes32,uint8,uint8,uint64,bytes32,bytes32)");
    bytes32 private constant TRANSFER_EVENT = keccak256("Transfer(address,address,uint256)");
    Phase9RefinanceModuleIsolationVm private constant vm =
        Phase9RefinanceModuleIsolationVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function setUp() public {
        _deployRequestHarness(SEED);
    }

    function test_P9R_MOD001_EveryPublicModuleEntryIsDirectCallIsolated() public {
        address validation = address(Phase9RefinanceValidationModule);
        address request = address(Phase9RefinanceRequestModule);
        address lifecycle = address(Phase9RefinanceLifecycleModule);
        Phase9RefinanceValidationContext memory context = _canonicalValidationContext();
        bytes32 id = keccak256("DIRECT_MODULE_ID");

        vm.recordLogs();
        (bool validationSucceeded, bytes memory validationResult) = validation.staticcall(
            abi.encodeWithSelector(VALIDATION_SELECTOR, context, requestRecord)
        );
        require(!validationSucceeded, "direct validation path");
        require(
            _selector(validationResult) == IRefinanceCoordinator.InvalidRefinance.selector,
            "validation environment guard"
        );
        _requireDirectGuard(
            request, abi.encodeWithSelector(BEGIN_SELECTOR, uint256(0), requestRecord)
        );
        _requireDirectGuard(
            request, abi.encodeWithSelector(COMPLETE_SELECTOR, uint256(0), requestRecord, bytes(""))
        );
        _requireDirectD3Freeze(
            lifecycle, abi.encodeWithSelector(EXECUTE_SELECTOR, uint256(0), id, id)
        );
        _requireDirectD3Freeze(
            lifecycle, abi.encodeWithSelector(CANCEL_SELECTOR, uint256(0), id, id)
        );
        _requireDirectD3Freeze(
            lifecycle, abi.encodeWithSelector(REFUND_SELECTOR, uint256(0), id, id)
        );
        require(vm.getRecordedLogs().length == 0, "direct module event");

        bytes32 refinanceId = _requestRefinance();
        Phase9Types.FundingCommitment memory commitment = _commitment(
            address(requestComponents.refinanceCoordinator), refinanceId, requestRecord
        );
        requestSettlementToken.transfer(REQUEST_NEW_LENDER, REQUEST_NEW_PRINCIPAL);
        vm.prank(REQUEST_NEW_LENDER);
        requestSettlementToken.approve(
            address(requestComponents.refinanceCoordinator), REQUEST_NEW_PRINCIPAL
        );
        uint256 allowanceBefore = requestSettlementToken.allowance(
            REQUEST_NEW_LENDER, address(requestComponents.refinanceCoordinator)
        );
        vm.prank(REQUEST_NEW_LENDER);
        _requireDirectGuard(
            lifecycle, abi.encodeWithSelector(RECORD_SELECTOR, uint256(0), commitment)
        );
        require(
            requestSettlementToken.allowance(
                REQUEST_NEW_LENDER, address(requestComponents.refinanceCoordinator)
            ) == allowanceBefore,
            "direct guard allowance"
        );
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId) == 0,
            "direct guard escrow"
        );

        vm.prank(REQUEST_NEW_LENDER);
        requestComponents.refinanceCoordinator.recordFundingCommitment(commitment);
        require(
            requestComponents.refinanceCoordinator.escrowedUnits(refinanceId)
                == REQUEST_NEW_PRINCIPAL,
            "wrapper did not accept valid commitment"
        );
    }

    function test_P9R_MOD002_HostileDelegateHostOnlyMutatesItsCraftedLocalWorld() public {
        Phase9RefinanceHostileDelegateHost host = new Phase9RefinanceHostileDelegateHost();
        address lifecycle = address(Phase9RefinanceLifecycleModule);
        (bytes32 refinanceId, Phase9Types.FundingCommitment memory commitment) =
            _prepareHostFunding(host);

        IsolationSnapshot memory before_ = _hostSnapshot(host, refinanceId, commitment.commitmentId);
        _invokeHostFundingAndAssertLogs(host, lifecycle, commitment);

        _assertHostFundingResult(host, refinanceId, commitment.commitmentId, before_);
        _assertCoordinatorUnchanged(refinanceId, commitment.commitmentId, before_);
    }

    function test_P9R_MOD003_HostileRequestPathStopsAtFirstCanonicalLienBinding() public {
        Phase9RefinanceHostileDelegateHost host = new Phase9RefinanceHostileDelegateHost();
        (bool beginSucceeded, bytes memory beginResult) = host.invoke(
            address(Phase9RefinanceRequestModule),
            abi.encodeWithSelector(BEGIN_SELECTOR, uint256(0), requestRecord)
        );
        require(beginSucceeded && beginResult.length == 0, "host request begin");
        require(
            host.activeLock(requestRecord.oldLoanId)
                == (uint64(1) << 63 | requestRecord.refinanceNonce),
            "host request lock"
        );

        bytes32 witnessId = keccak256("HOSTILE_CANONICAL_BINDING_WITNESS");
        bytes32 beforeHash = _canonicalBindingFailureHash(host, witnessId);
        Phase9RefinanceValidationContext memory context = _canonicalValidationContext();
        context.coordinator = address(host);

        // The canonical lien registration is the first unavoidable coordinator binding in
        // preflight. Once it rejects the hostile host, canonical factory, custody, and quote
        // effects are unreachable; this test does not claim to exercise those later branches.
        vm.expectCall(
            address(requestComponents.lienRegistry),
            abi.encodeCall(ILienRegistry.registeredRefinanceCoordinator, ()),
            1
        );
        vm.recordLogs();
        (bool validationSucceeded, bytes memory validationResult) = host.invoke(
            address(Phase9RefinanceValidationModule),
            abi.encodeWithSelector(VALIDATION_SELECTOR, context, requestRecord)
        );
        require(!validationSucceeded, "host passed canonical lien binding");
        require(
            _selector(validationResult) == IRefinanceCoordinator.InvalidRefinance.selector,
            "canonical lien binding selector"
        );
        require(vm.getRecordedLogs().length == 0, "canonical binding event");
        require(
            _canonicalBindingFailureHash(host, witnessId) == beforeHash,
            "canonical binding durable effect"
        );
    }

    function _prepareHostFunding(Phase9RefinanceHostileDelegateHost host)
        private
        returns (bytes32 refinanceId, Phase9Types.FundingCommitment memory commitment)
    {
        Phase9Types.RefinanceRecord memory hostRequest = requestRecord;
        hostRequest.refinancePolicyHash = _hostPolicyHash(hostRequest, address(host));
        requestPolicyResolver.setRefinancePolicy(
            hostRequest.refinancePolicyHash,
            requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash)
        );
        host.configureFundingDependencies(
            address(requestPolicyResolver),
            address(requestAssetSource),
            address(requestEmergencyController),
            requestSettlementToken
        );

        (bool beginSucceeded, bytes memory beginResult) = host.invoke(
            address(Phase9RefinanceRequestModule),
            abi.encodeWithSelector(BEGIN_SELECTOR, uint256(0), hostRequest)
        );
        require(beginSucceeded && beginResult.length == 0, "host begin");
        require(
            host.activeLock(hostRequest.oldLoanId)
                == (uint64(1) << 63 | hostRequest.refinanceNonce),
            "host lock"
        );

        refinanceId = keccak256("HOSTILE_LOCAL_REFINANCE");
        Phase9Types.RefinanceRecord memory hosted = hostRequest;
        hosted.refinanceId = refinanceId;
        hosted.quoteId = keccak256("HOSTILE_LOCAL_QUOTE");
        hosted.state = Phase9Types.RefinanceState.ACCEPTED;
        hosted.stateVersion = 1;
        host.installAcceptedRefinance(hosted);
        commitment = _commitment(address(host), refinanceId, hosted);

        requestSettlementToken.transfer(REQUEST_NEW_LENDER, REQUEST_NEW_PRINCIPAL);
        vm.prank(REQUEST_NEW_LENDER);
        requestSettlementToken.approve(address(host), REQUEST_NEW_PRINCIPAL);
    }

    function _canonicalBindingFailureHash(
        Phase9RefinanceHostileDelegateHost host,
        bytes32 witnessId
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                _hostCanonicalBindingHash(host, witnessId),
                _coordinatorCanonicalBindingHash(witnessId)
            )
        );
    }

    function _hostCanonicalBindingHash(Phase9RefinanceHostileDelegateHost host, bytes32 witnessId)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                host.activeLock(requestRecord.oldLoanId),
                host.refinance(witnessId),
                host.fundingCommitment(witnessId),
                host.commitmentIds(witnessId),
                host.escrowedUnits(witnessId),
                host.operationProcessed(witnessId),
                requestSettlementToken.balanceOf(address(host)),
                requestSettlementToken.allowance(REQUEST_NEW_LENDER, address(host))
            )
        );
    }

    function _coordinatorCanonicalBindingHash(bytes32 witnessId) private view returns (bytes32) {
        (bool coordinatorRefinanceKnown, bytes memory coordinatorRefinanceResult) = address(
                requestComponents.refinanceCoordinator
            ).staticcall(abi.encodeCall(IRefinanceCoordinator.refinance, (witnessId)));
        (bool coordinatorCommitmentKnown, bytes memory coordinatorCommitmentResult) = address(
                requestComponents.refinanceCoordinator
            ).staticcall(abi.encodeCall(IRefinanceCoordinator.fundingCommitment, (witnessId)));
        return keccak256(
            abi.encode(
                requestComponents.refinanceCoordinator.operationProcessed(witnessId),
                coordinatorRefinanceKnown,
                keccak256(coordinatorRefinanceResult),
                coordinatorCommitmentKnown,
                keccak256(coordinatorCommitmentResult),
                requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator)),
                requestSettlementToken.allowance(
                    REQUEST_NEW_LENDER, address(requestComponents.refinanceCoordinator)
                )
            )
        );
    }

    function _hostSnapshot(
        Phase9RefinanceHostileDelegateHost host,
        bytes32 refinanceId,
        bytes32 commitmentId
    ) private view returns (IsolationSnapshot memory snapshot) {
        snapshot.coordinatorBalance = requestSettlementToken.balanceOf(
            address(requestComponents.refinanceCoordinator)
        );
        snapshot.hostBalance = requestSettlementToken.balanceOf(address(host));
        snapshot.funderBalance = requestSettlementToken.balanceOf(REQUEST_NEW_LENDER);
        snapshot.hostAllowance = requestSettlementToken.allowance(REQUEST_NEW_LENDER, address(host));
        snapshot.coordinatorAllowance = requestSettlementToken.allowance(
            REQUEST_NEW_LENDER, address(requestComponents.refinanceCoordinator)
        );
        (bool refinanceKnown, bytes memory refinanceResult) = address(
                requestComponents.refinanceCoordinator
            ).staticcall(abi.encodeCall(IRefinanceCoordinator.refinance, (refinanceId)));
        (bool commitmentKnown, bytes memory commitmentResult) = address(
                requestComponents.refinanceCoordinator
            ).staticcall(abi.encodeCall(IRefinanceCoordinator.fundingCommitment, (commitmentId)));
        require(!refinanceKnown, "coordinator hostile refinance fixture");
        require(!commitmentKnown, "coordinator hostile commitment fixture");
        snapshot.coordinatorRefinanceResultHash = keccak256(refinanceResult);
        snapshot.coordinatorCommitmentResultHash = keccak256(commitmentResult);
    }

    function _invokeHostFundingAndAssertLogs(
        Phase9RefinanceHostileDelegateHost host,
        address lifecycle,
        Phase9Types.FundingCommitment memory commitment
    ) private {
        vm.recordLogs();
        vm.prank(REQUEST_NEW_LENDER);
        (bool fundingSucceeded, bytes memory fundingResult) = host.invoke(
            lifecycle, abi.encodeWithSelector(RECORD_SELECTOR, uint256(0), commitment)
        );
        require(fundingSucceeded && fundingResult.length == 0, "host funding");
        Phase9RefinanceModuleIsolationVm.Log[] memory logs = vm.getRecordedLogs();
        uint256 commitmentLogs;
        uint256 transitionLogs;
        uint256 transferLogs;
        for (uint256 i = 0; i < logs.length; ++i) {
            require(
                logs[i].emitter != address(requestComponents.refinanceCoordinator),
                "coordinator log"
            );
            if (logs[i].emitter == address(host) && logs[i].topics[0] == COMMITMENT_EVENT) {
                ++commitmentLogs;
            }
            if (logs[i].emitter == address(host) && logs[i].topics[0] == TRANSITION_EVENT) {
                ++transitionLogs;
            }
            if (
                logs[i].emitter == address(requestSettlementToken)
                    && logs[i].topics[0] == TRANSFER_EVENT
            ) ++transferLogs;
        }
        require(
            logs.length == 3 && commitmentLogs == 1 && transitionLogs == 1 && transferLogs == 1,
            "host funding logs"
        );
    }

    function _assertHostFundingResult(
        Phase9RefinanceHostileDelegateHost host,
        bytes32 refinanceId,
        bytes32 commitmentId,
        IsolationSnapshot memory before_
    ) private view {
        Phase9Types.RefinanceRecord memory stored = host.refinance(refinanceId);
        Phase9Types.FundingCommitment memory storedCommitment = host.fundingCommitment(commitmentId);
        require(
            stored.state == Phase9Types.RefinanceState.FUNDING_ESCROWED && stored.stateVersion == 2
                && stored.acceptedFunding == REQUEST_NEW_PRINCIPAL,
            "host refinance result"
        );
        require(host.escrowedUnits(refinanceId) == REQUEST_NEW_PRINCIPAL, "host escrow result");
        require(
            host.commitmentIds(refinanceId).length == 1
                && storedCommitment.state == Phase9Types.FundingCommitmentState.FUNDED
                && storedCommitment.fundingResultHash != bytes32(0)
                && host.operationProcessed(commitmentId),
            "host commitment result"
        );
        require(
            requestSettlementToken.balanceOf(address(host))
                == before_.hostBalance + REQUEST_NEW_PRINCIPAL,
            "host token delta"
        );
        require(
            requestSettlementToken.balanceOf(REQUEST_NEW_LENDER)
                == before_.funderBalance - REQUEST_NEW_PRINCIPAL,
            "host funder delta"
        );
        require(before_.hostAllowance == REQUEST_NEW_PRINCIPAL, "host allowance fixture");
        require(
            requestSettlementToken.allowance(REQUEST_NEW_LENDER, address(host)) == 0,
            "host allowance delta"
        );
    }

    function _assertCoordinatorUnchanged(
        bytes32 refinanceId,
        bytes32 commitmentId,
        IsolationSnapshot memory before_
    ) private view {
        require(
            requestSettlementToken.balanceOf(address(requestComponents.refinanceCoordinator))
            == before_.coordinatorBalance,
            "host moved coordinator funds"
        );
        require(
            requestSettlementToken.allowance(
                REQUEST_NEW_LENDER, address(requestComponents.refinanceCoordinator)
            ) == before_.coordinatorAllowance,
            "host changed coordinator allowance"
        );
        require(
            !requestComponents.refinanceCoordinator.operationProcessed(commitmentId),
            "host consumed coordinator operation"
        );
        (bool refinanceKnown, bytes memory refinanceResult) = address(
                requestComponents.refinanceCoordinator
            ).staticcall(abi.encodeCall(IRefinanceCoordinator.refinance, (refinanceId)));
        (bool commitmentKnown, bytes memory commitmentResult) = address(
                requestComponents.refinanceCoordinator
            ).staticcall(abi.encodeCall(IRefinanceCoordinator.fundingCommitment, (commitmentId)));
        require(
            !refinanceKnown && keccak256(refinanceResult) == before_.coordinatorRefinanceResultHash,
            "host changed coordinator refinance"
        );
        require(
            !commitmentKnown
                && keccak256(commitmentResult) == before_.coordinatorCommitmentResultHash,
            "host changed coordinator commitment"
        );
    }

    function _requireDirectGuard(address module, bytes memory input) private {
        (bool success, bytes memory returned) = module.call(input);
        require(!success, "unguarded direct module call");
        require(returned.length == 0, "unexpected direct guard result");
    }

    function _requireDirectD3Freeze(address module, bytes memory input) private {
        (bool success, bytes memory returned) = module.call(input);
        require(!success, "direct D3 stub opened");
        require(
            _selector(returned) == Phase9ImplementationNotFrozen.selector,
            "direct D3 freeze selector"
        );
    }

    function _canonicalValidationContext()
        private
        view
        returns (Phase9RefinanceValidationContext memory context)
    {
        context.chainId = block.chainid;
        context.coordinator = address(requestComponents.refinanceCoordinator);
        context.loanRegistry = address(requestLoanRegistry);
        context.phase9LoanFactory = address(requestComponents.loanFactory);
        context.payoffQuoteEngine = address(requestComponents.payoffQuoteEngine);
        context.lienRegistry = address(requestComponents.lienRegistry);
        context.assetRegistry = address(requestAssetSource);
        context.policyRegistry = address(requestPolicyResolver);
        context.emergencyController = address(requestEmergencyController);
        context.treasuryFeeRecipient = REQUEST_TREASURY;
        context.settlementToken = address(requestSettlementToken);
        context.activeLock = uint64(1) << 63 | requestRecord.refinanceNonce;
    }

    function _commitment(
        address coordinator,
        bytes32 refinanceId,
        Phase9Types.RefinanceRecord memory refinance_
    ) private view returns (Phase9Types.FundingCommitment memory commitment) {
        commitment.refinanceId = refinanceId;
        commitment.positionId = requestReplacementPositionId;
        commitment.trancheId = requestReplacementTrancheId;
        commitment.funder = REQUEST_NEW_LENDER;
        commitment.amount = REQUEST_NEW_PRINCIPAL;
        commitment.commitmentNonce = 1;
        commitment.commitmentId = keccak256(
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
        commitment.commitmentDigest = keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_FUNDING_COMMITMENT_DIGEST_V1",
                block.chainid,
                coordinator,
                commitment.commitmentId,
                commitment.refinanceId,
                commitment.positionId,
                commitment.trancheId,
                commitment.funder,
                commitment.amount,
                commitment.commitmentNonce,
                refinance_.refinancePolicyHash,
                refinance_.expiresAt
            )
        );
    }

    function _hostPolicyHash(Phase9Types.RefinanceRecord memory refinance_, address coordinator)
        private
        view
        returns (bytes32)
    {
        Phase9BootstrapPolicyResolver.RefinancePolicyRecord memory policy =
            requestPolicyResolver.refinancePolicy(requestRecord.refinancePolicyHash);
        FundingPolicyIdentity memory identity = FundingPolicyIdentity({
            chainId: block.chainid,
            coordinator: coordinator,
            policyRegistry: address(requestPolicyResolver),
            oldLoanId: refinance_.oldLoanId,
            newLoanId: refinance_.newLoanId,
            borrower: refinance_.borrower,
            oldLender: refinance_.oldLender,
            newPositionManager: refinance_.newPositionManager,
            oldPolicySetHash: policy.boundOldPolicySetHash,
            newPolicySetHash: policy.boundNewPolicySetHash,
            proposedTermsHash: policy.proposedTermsHash,
            settlementAssetId: refinance_.settlementAssetId,
            collateralSetHash: refinance_.collateralSetHash,
            fundingAmount: refinance_.fundingAmount,
            refinanceFee: refinance_.refinanceFee,
            borrowerProceeds: refinance_.borrowerProceeds,
            expiresAt: refinance_.expiresAt,
            maximumValidity: policy.maximumValidity,
            maximumCommitments: policy.maximumCommitments,
            collateralIdsHash: keccak256(abi.encode(policy.collateralIds)),
            replacementDebtHash: keccak256(abi.encode(policy.replacementDebt)),
            replacementTranchesHash: keccak256(abi.encode(policy.replacementTranches)),
            replacementPositionsHash: keccak256(abi.encode(policy.replacementPositions))
        });
        return keccak256(abi.encode("UNIFIED_REFINANCE_POLICY_V1", identity));
    }

    function _selector(bytes memory returned) private pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
