// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ILienRegistry } from "../src/interfaces/phase9/ILienRegistry.sol";
import { LienRegistry } from "../src/resolution/LienRegistry.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";

interface Phase9LienHandoffVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address sender) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
}

contract Phase9LienCoordinatorProbe {
    error UnexpectedRegistryCallback();

    fallback() external payable {
        revert UnexpectedRegistryCallback();
    }

    receive() external payable {
        revert UnexpectedRegistryCallback();
    }

    function registerLien(ILienRegistry registry, Phase9Types.Lien calldata lien_) external {
        registry.registerLien(lien_);
    }

    function beginHandoff(
        ILienRegistry registry,
        bytes32 collateralId,
        bytes32 refinanceId,
        bytes32 targetLoanId,
        uint64 expectedLienVersion
    ) external returns (bytes32) {
        return registry.beginHandoff(collateralId, refinanceId, targetLoanId, expectedLienVersion);
    }

    function completeHandoff(ILienRegistry registry, bytes32 handoffId, bytes32 evidenceHash)
        external
        returns (Phase9Types.LienHandoffResult memory)
    {
        return registry.completeHandoff(handoffId, evidenceHash);
    }

    function rawCall(address target, bytes calldata callData)
        external
        returns (bool success, bytes memory returned)
    {
        return target.call(callData);
    }

    function beginThenInvalidComplete(
        ILienRegistry registry,
        bytes32 collateralId,
        bytes32 refinanceId,
        bytes32 targetLoanId,
        uint64 expectedLienVersion
    ) external {
        bytes32 handoffId = registry.beginHandoff(
            collateralId, refinanceId, targetLoanId, expectedLienVersion
        );
        registry.completeHandoff(handoffId, bytes32(0));
    }
}

/// @dev D3 Stage A evidence for P9R-EXEC-006, P9R-EXEC-008, and P9R-VIEW-001.
contract Phase9LienHandoffTest {
    bytes32 private constant COLLATERAL_ID = keccak256("PHASE9_LIEN_COLLATERAL");
    bytes32 private constant SECOND_COLLATERAL_ID = keccak256("PHASE9_LIEN_COLLATERAL_TWO");
    bytes32 private constant ASSET_ID = keccak256("PHASE9_LIEN_ASSET");
    bytes32 private constant OLD_LOAN_ID = keccak256("PHASE9_LIEN_OLD_LOAN");
    bytes32 private constant NEW_LOAN_ID = keccak256("PHASE9_LIEN_NEW_LOAN");
    bytes32 private constant REFINANCE_ID = keccak256("PHASE9_LIEN_REFINANCE");
    bytes32 private constant WRONG_EVIDENCE_HASH = keccak256("PHASE9_LIEN_WRONG_EVIDENCE");
    uint64 private constant LIEN_VERSION = 7;

    bytes32 private constant PENDING_EVENT_TOPIC =
        keccak256("LienHandoffPending(bytes32,bytes32,bytes32)");
    bytes32 private constant COMPLETED_EVENT_TOPIC =
        keccak256("LienHandoffCompleted(bytes32,bytes32,bytes32,uint64)");

    Phase9LienHandoffVm private constant vm =
        Phase9LienHandoffVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Phase9LienCoordinatorProbe private coordinator;
    LienRegistry private registry;
    Phase9Types.Lien private initialLien;

    function setUp() public {
        require(block.chainid == 31337, "local chain");
        coordinator = new Phase9LienCoordinatorProbe();
        registry = new LienRegistry(address(coordinator));
        require(
            registry.registeredRefinanceCoordinator() == address(coordinator), "coordinator binding"
        );

        initialLien = _activeLien(COLLATERAL_ID, OLD_LOAN_ID, LIEN_VERSION);
        coordinator.registerLien(registry, initialLien);
    }

    function test_P9R_EXEC006_BeginStoresCanonicalPendingTupleAndEmits() public {
        vm.recordLogs();
        bytes32 handoffId = coordinator.beginHandoff(
            registry, COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION
        );
        Phase9LienHandoffVm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 expectedHandoffId = _handoffId(
            REFINANCE_ID, COLLATERAL_ID, OLD_LOAN_ID, NEW_LOAN_ID, LIEN_VERSION, LIEN_VERSION + 1
        );
        require(handoffId == expectedHandoffId, "canonical handoff id");

        Phase9Types.Lien memory pending = registry.lien(COLLATERAL_ID);
        _requirePreservedCollateral(initialLien, pending);
        require(pending.seniorLoanId == OLD_LOAN_ID, "old senior remains");
        require(pending.lienVersion == LIEN_VERSION, "prior version remains");
        require(pending.status == Phase9Types.LienStatus.HANDOFF_PENDING, "pending status");
        require(pending.pendingRefinanceId == REFINANCE_ID, "pending refinance");
        require(pending.pendingTargetLoanId == NEW_LOAN_ID, "pending target");

        Phase9Types.LienHandoffResult memory result = registry.handoff(handoffId);
        _requireExecutingResult(result, handoffId);

        require(logs.length == 1, "one pending event");
        require(logs[0].emitter == address(registry), "pending emitter");
        require(logs[0].topics.length == 4, "pending topics");
        require(logs[0].topics[0] == PENDING_EVENT_TOPIC, "pending signature");
        require(logs[0].topics[1] == COLLATERAL_ID, "pending collateral topic");
        require(logs[0].topics[2] == REFINANCE_ID, "pending refinance topic");
        require(logs[0].topics[3] == NEW_LOAN_ID, "pending target topic");
        require(logs[0].data.length == 0, "pending event data");
    }

    function test_P9R_EXEC006_ExactBeginReplayIsInertAndChangedReplayConflicts() public {
        bytes32 handoffId = coordinator.beginHandoff(
            registry, COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION
        );
        bytes32 pendingLienHash = keccak256(abi.encode(registry.lien(COLLATERAL_ID)));
        bytes32 pendingResultHash = keccak256(abi.encode(registry.handoff(handoffId)));

        vm.recordLogs();
        bytes32 replayed = coordinator.beginHandoff(
            registry, COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION
        );
        Phase9LienHandoffVm.Log[] memory logs = vm.getRecordedLogs();
        require(replayed == handoffId, "exact begin replay");
        require(logs.length == 0, "begin replay event");

        _expectCoordinatorError(
            abi.encodeCall(
                ILienRegistry.beginHandoff,
                (COLLATERAL_ID, keccak256("CHANGED_REFINANCE"), NEW_LOAN_ID, LIEN_VERSION)
            ),
            ILienRegistry.InvalidLienHandoff.selector
        );
        _expectCoordinatorError(
            abi.encodeCall(
                ILienRegistry.beginHandoff,
                (COLLATERAL_ID, REFINANCE_ID, keccak256("CHANGED_TARGET"), LIEN_VERSION)
            ),
            ILienRegistry.InvalidLienHandoff.selector
        );
        require(
            keccak256(abi.encode(registry.lien(COLLATERAL_ID))) == pendingLienHash,
            "changed begin lien mutation"
        );
        require(
            keccak256(abi.encode(registry.handoff(handoffId))) == pendingResultHash,
            "changed begin result mutation"
        );
    }

    function test_P9R_EXEC006_BeginRejectsAuthorityInputsAndVersionOverflow() public {
        bytes memory beginCall = abi.encodeCall(
            ILienRegistry.beginHandoff, (COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION)
        );
        _expectDirectError(address(registry), beginCall, ILienRegistry.InvalidLien.selector);

        LienRegistry eoaCoordinatorRegistry = new LienRegistry(address(0xBEEF));
        vm.prank(address(0xBEEF));
        _expectDirectError(
            address(eoaCoordinatorRegistry), beginCall, ILienRegistry.InvalidLien.selector
        );

        bytes32 activeLienHash = keccak256(abi.encode(registry.lien(COLLATERAL_ID)));
        _expectInvalidBegin(COLLATERAL_ID, bytes32(0), NEW_LOAN_ID, LIEN_VERSION);
        _expectInvalidBegin(COLLATERAL_ID, REFINANCE_ID, bytes32(0), LIEN_VERSION);
        _expectInvalidBegin(COLLATERAL_ID, REFINANCE_ID, OLD_LOAN_ID, LIEN_VERSION);
        _expectInvalidBegin(COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION + 1);
        _expectInvalidBegin(
            keccak256("UNKNOWN_COLLATERAL"), REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION
        );
        require(
            keccak256(abi.encode(registry.lien(COLLATERAL_ID))) == activeLienHash,
            "invalid begin mutation"
        );

        Phase9Types.Lien memory maximumVersionLien =
            _activeLien(SECOND_COLLATERAL_ID, OLD_LOAN_ID, type(uint64).max);
        coordinator.registerLien(registry, maximumVersionLien);
        _expectInvalidBegin(SECOND_COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, type(uint64).max);
        require(
            keccak256(abi.encode(registry.lien(SECOND_COLLATERAL_ID)))
                == keccak256(abi.encode(maximumVersionLien)),
            "overflow lien mutation"
        );
    }

    function test_P9R_EXEC006_CompleteStoresExactActiveTupleAndReplayIsInert() public {
        bytes32 handoffId = coordinator.beginHandoff(
            registry, COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION
        );
        bytes32 evidenceHash = _evidenceHash(handoffId);
        bytes32 pendingLienHash = keccak256(abi.encode(registry.lien(COLLATERAL_ID)));
        bytes32 pendingResultHash = keccak256(abi.encode(registry.handoff(handoffId)));

        _expectCoordinatorError(
            abi.encodeCall(ILienRegistry.completeHandoff, (handoffId, WRONG_EVIDENCE_HASH)),
            ILienRegistry.InvalidLienHandoff.selector
        );
        require(
            keccak256(abi.encode(registry.lien(COLLATERAL_ID))) == pendingLienHash,
            "wrong evidence lien mutation"
        );
        require(
            keccak256(abi.encode(registry.handoff(handoffId))) == pendingResultHash,
            "wrong evidence result mutation"
        );

        vm.recordLogs();
        Phase9Types.LienHandoffResult memory returned =
            coordinator.completeHandoff(registry, handoffId, evidenceHash);
        Phase9LienHandoffVm.Log[] memory logs = vm.getRecordedLogs();

        require(returned.handoffId == handoffId, "completed handoff id");
        require(returned.refinanceId == REFINANCE_ID, "completed refinance");
        require(returned.collateralId == COLLATERAL_ID, "completed collateral");
        require(returned.oldLoanId == OLD_LOAN_ID, "completed old loan");
        require(returned.newLoanId == NEW_LOAN_ID, "completed new loan");
        require(returned.priorLienVersion == LIEN_VERSION, "completed prior version");
        require(returned.nextLienVersion == LIEN_VERSION + 1, "completed next version");
        require(returned.state == Phase9Types.LienHandoffState.ACTIVE_NEW, "completed state");
        require(returned.evidenceHash == evidenceHash, "completed evidence");

        Phase9Types.LienHandoffResult memory stored = registry.handoff(handoffId);
        require(keccak256(abi.encode(stored)) == keccak256(abi.encode(returned)), "stored result");
        Phase9Types.Lien memory active = registry.lien(COLLATERAL_ID);
        _requirePreservedCollateral(initialLien, active);
        require(active.seniorLoanId == NEW_LOAN_ID, "new senior");
        require(active.lienVersion == LIEN_VERSION + 1, "new lien version");
        require(active.status == Phase9Types.LienStatus.ACTIVE, "active status");
        require(active.pendingRefinanceId == bytes32(0), "cleared refinance");
        require(active.pendingTargetLoanId == bytes32(0), "cleared target");

        require(logs.length == 1, "one completion event");
        require(logs[0].emitter == address(registry), "completion emitter");
        require(logs[0].topics.length == 4, "completion topics");
        require(logs[0].topics[0] == COMPLETED_EVENT_TOPIC, "completion signature");
        require(logs[0].topics[1] == COLLATERAL_ID, "completion collateral topic");
        require(logs[0].topics[2] == OLD_LOAN_ID, "completion old topic");
        require(logs[0].topics[3] == NEW_LOAN_ID, "completion new topic");
        require(
            keccak256(logs[0].data) == keccak256(abi.encode(uint64(LIEN_VERSION + 1))),
            "completion event data"
        );

        vm.recordLogs();
        Phase9Types.LienHandoffResult memory replayed =
            coordinator.completeHandoff(registry, handoffId, evidenceHash);
        logs = vm.getRecordedLogs();
        require(
            keccak256(abi.encode(replayed)) == keccak256(abi.encode(returned)), "complete replay"
        );
        require(logs.length == 0, "complete replay event");

        bytes32 activeHash = keccak256(abi.encode(active));
        _expectCoordinatorError(
            abi.encodeCall(ILienRegistry.completeHandoff, (handoffId, WRONG_EVIDENCE_HASH)),
            ILienRegistry.InvalidLienHandoff.selector
        );
        require(
            keccak256(abi.encode(registry.lien(COLLATERAL_ID))) == activeHash,
            "changed evidence mutation"
        );
    }

    function test_P9R_EXEC008_FailedCompletionRollsBackEarlierBeginWithoutCallbacks() public {
        bytes32 expectedHandoffId = _handoffId(
            REFINANCE_ID, COLLATERAL_ID, OLD_LOAN_ID, NEW_LOAN_ID, LIEN_VERSION, LIEN_VERSION + 1
        );
        bytes32 activeLienHash = keccak256(abi.encode(registry.lien(COLLATERAL_ID)));

        (bool success, bytes memory returned) = address(coordinator)
            .call(
                abi.encodeCall(
                    Phase9LienCoordinatorProbe.beginThenInvalidComplete,
                    (registry, COLLATERAL_ID, REFINANCE_ID, NEW_LOAN_ID, LIEN_VERSION)
                )
            );
        require(!success, "invalid completion succeeded");
        require(
            _selector(returned) == ILienRegistry.InvalidLienHandoff.selector,
            "invalid completion selector"
        );
        require(
            keccak256(abi.encode(registry.lien(COLLATERAL_ID))) == activeLienHash,
            "begin did not roll back"
        );
        _expectViewError(
            abi.encodeCall(ILienRegistry.handoff, (expectedHandoffId)),
            ILienRegistry.UnknownLienHandoff.selector
        );
    }

    function test_P9R_VIEW001_UnknownLienAndHandoffUseTypedErrors() public {
        bytes32 unknownCollateral = keccak256("UNKNOWN_LIEN");
        bytes32 unknownHandoff = keccak256("UNKNOWN_HANDOFF");
        _expectViewError(
            abi.encodeCall(ILienRegistry.lien, (unknownCollateral)),
            ILienRegistry.UnknownLien.selector
        );
        _expectViewError(
            abi.encodeCall(ILienRegistry.handoff, (unknownHandoff)),
            ILienRegistry.UnknownLienHandoff.selector
        );
        _expectCoordinatorError(
            abi.encodeCall(ILienRegistry.completeHandoff, (unknownHandoff, WRONG_EVIDENCE_HASH)),
            ILienRegistry.UnknownLienHandoff.selector
        );
    }

    function _activeLien(bytes32 collateralId, bytes32 seniorLoanId, uint64 lienVersion)
        private
        pure
        returns (Phase9Types.Lien memory)
    {
        return Phase9Types.Lien({
            collateralId: collateralId,
            collateralManager: address(0xC011A7),
            vault: address(0xA11CE),
            assetId: ASSET_ID,
            quantity: 500_000000,
            borrower: address(0xB0B),
            seniorLoanId: seniorLoanId,
            lienVersion: lienVersion,
            status: Phase9Types.LienStatus.ACTIVE,
            pendingRefinanceId: bytes32(0),
            pendingTargetLoanId: bytes32(0)
        });
    }

    function _handoffId(
        bytes32 refinanceId,
        bytes32 collateralId,
        bytes32 oldLoanId,
        bytes32 newLoanId,
        uint64 priorLienVersion,
        uint64 nextLienVersion
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_LIEN_HANDOFF_V1",
                block.chainid,
                address(registry),
                refinanceId,
                collateralId,
                oldLoanId,
                newLoanId,
                priorLienVersion,
                nextLienVersion
            )
        );
    }

    function _evidenceHash(bytes32 handoffId) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_REFINANCE_LIEN_HANDOFF_RESULT_V1",
                block.chainid,
                address(registry),
                handoffId,
                REFINANCE_ID,
                COLLATERAL_ID,
                OLD_LOAN_ID,
                NEW_LOAN_ID,
                LIEN_VERSION,
                LIEN_VERSION + 1,
                Phase9Types.LienHandoffState.ACTIVE_NEW
            )
        );
    }

    function _requirePreservedCollateral(
        Phase9Types.Lien memory expected,
        Phase9Types.Lien memory actual
    ) private pure {
        require(actual.collateralId == expected.collateralId, "preserved collateral");
        require(actual.collateralManager == expected.collateralManager, "preserved manager");
        require(actual.vault == expected.vault, "preserved vault");
        require(actual.assetId == expected.assetId, "preserved asset");
        require(actual.quantity == expected.quantity, "preserved quantity");
        require(actual.borrower == expected.borrower, "preserved borrower");
    }

    function _requireExecutingResult(Phase9Types.LienHandoffResult memory result, bytes32 handoffId)
        private
        pure
    {
        require(result.handoffId == handoffId, "pending handoff id");
        require(result.refinanceId == REFINANCE_ID, "pending result refinance");
        require(result.collateralId == COLLATERAL_ID, "pending result collateral");
        require(result.oldLoanId == OLD_LOAN_ID, "pending result old loan");
        require(result.newLoanId == NEW_LOAN_ID, "pending result new loan");
        require(result.priorLienVersion == LIEN_VERSION, "pending result prior version");
        require(result.nextLienVersion == LIEN_VERSION + 1, "pending result next version");
        require(result.state == Phase9Types.LienHandoffState.EXECUTING, "pending result state");
        require(result.evidenceHash == bytes32(0), "pending result evidence");
    }

    function _expectInvalidBegin(
        bytes32 collateralId,
        bytes32 refinanceId,
        bytes32 targetLoanId,
        uint64 expectedLienVersion
    ) private {
        _expectCoordinatorError(
            abi.encodeCall(
                ILienRegistry.beginHandoff,
                (collateralId, refinanceId, targetLoanId, expectedLienVersion)
            ),
            ILienRegistry.InvalidLienHandoff.selector
        );
    }

    function _expectCoordinatorError(bytes memory callData, bytes4 expectedSelector) private {
        (bool success, bytes memory returned) = coordinator.rawCall(address(registry), callData);
        require(!success, "expected coordinator error");
        require(_selector(returned) == expectedSelector, "coordinator error selector");
    }

    function _expectDirectError(address target, bytes memory callData, bytes4 expectedSelector)
        private
    {
        (bool success, bytes memory returned) = target.call(callData);
        require(!success, "expected direct error");
        require(_selector(returned) == expectedSelector, "direct error selector");
    }

    function _expectViewError(bytes memory callData, bytes4 expectedSelector) private view {
        (bool success, bytes memory returned) = address(registry).staticcall(callData);
        require(!success, "expected view error");
        require(_selector(returned) == expectedSelector, "view error selector");
    }

    function _selector(bytes memory returned) private pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
