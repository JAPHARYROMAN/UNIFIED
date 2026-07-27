// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IPhase9LoanAccount } from "../src/interfaces/phase9/IPhase9LoanAccount.sol";
import { Phase9ImplementationNotFrozen } from "../src/interfaces/phase9/Phase9Errors.sol";
import { Phase9LoanAccount } from "../src/resolution/Phase9LoanAccount.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import { Phase9LocalSyntheticToken } from "../src/token/Phase9LocalSyntheticToken.sol";

interface Phase9AccountRefinanceVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
    function load(address target, bytes32 slot) external view returns (bytes32 value);
    function store(address target, bytes32 slot, bytes32 value) external;
}

contract Phase9AccountTestDependency { }

contract Phase9AccountTestFactory {
    function createAccount(
        address implementation,
        Phase9Types.LoanConfiguration calldata configuration,
        Phase9Types.DebtState calldata debt
    ) external returns (address account) {
        account = Clones.clone(implementation);
        IPhase9LoanAccount(account).initialize(configuration, debt);
    }
}

contract Phase9AccountTestCoordinator {
    Phase9Types.RefinanceRecord private _record;

    function setRecord(Phase9Types.RefinanceRecord calldata record) external {
        _record = record;
    }

    function refinance(bytes32) external view returns (Phase9Types.RefinanceRecord memory) {
        return _record;
    }

    function recordPayoff(
        IPhase9LoanAccount account,
        bytes32 refinanceId,
        uint256 amount,
        bytes32 operationId
    ) external {
        account.recordRefinancePayoff(refinanceId, amount, operationId);
    }

    function activate(
        IPhase9LoanAccount account,
        bytes32 refinanceId,
        Phase9Types.DebtState calldata debt,
        bytes32 operationId
    ) external {
        account.activateReplacementLoan(refinanceId, debt, operationId);
    }
}

contract Phase9AccountTestRegistry {
    error MarkFailed();

    struct Loan {
        address account;
        address borrower;
        bytes32 agreementHash;
        uint32 protocolVersion;
        bool terminal;
    }

    Phase9AccountTestCoordinator private immutable _coordinator;
    mapping(bytes32 loanId => Loan loan) private _loans;
    bool private _failMark;
    bool private _suppressTerminal;
    bool private _reenter;
    bytes32 private _reentryRefinanceId;
    uint256 private _reentryAmount;
    bytes32 private _reentryOperationId;
    uint256 public markCalls;

    constructor(Phase9AccountTestCoordinator coordinator) {
        _coordinator = coordinator;
    }

    function register(
        bytes32 loanId,
        address account,
        address borrower,
        bytes32 agreementHash,
        uint32 protocolVersion
    ) external {
        _loans[loanId] = Loan(account, borrower, agreementHash, protocolVersion, false);
    }

    function setLoan(
        bytes32 loanId,
        address account,
        address borrower,
        bytes32 agreementHash,
        uint32 protocolVersion,
        bool terminal
    ) external {
        _loans[loanId] = Loan(account, borrower, agreementHash, protocolVersion, terminal);
    }

    function setMarkBehavior(
        bool failMark,
        bool suppressTerminal,
        bool reenter,
        bytes32 refinanceId,
        uint256 amount,
        bytes32 operationId
    ) external {
        _failMark = failMark;
        _suppressTerminal = suppressTerminal;
        _reenter = reenter;
        _reentryRefinanceId = refinanceId;
        _reentryAmount = amount;
        _reentryOperationId = operationId;
    }

    function markTerminal(bytes32 loanId) external {
        Loan storage loan = _loans[loanId];
        require(msg.sender == loan.account, "account authority");
        ++markCalls;
        if (_failMark) revert MarkFailed();
        if (_reenter) {
            _coordinator.recordPayoff(
                IPhase9LoanAccount(msg.sender),
                _reentryRefinanceId,
                _reentryAmount,
                _reentryOperationId
            );
        }
        if (!_suppressTerminal) loan.terminal = true;
    }

    function loanAccount(bytes32 loanId) external view returns (address) {
        return _loans[loanId].account;
    }

    function borrowerOf(bytes32 loanId) external view returns (address) {
        return _loans[loanId].borrower;
    }

    function agreementHashOf(bytes32 loanId) external view returns (bytes32) {
        return _loans[loanId].agreementHash;
    }

    function protocolVersionOf(bytes32 loanId) external view returns (uint32) {
        return _loans[loanId].protocolVersion;
    }

    function exists(bytes32 loanId) external view returns (bool) {
        return _loans[loanId].account != address(0);
    }

    function isTerminal(bytes32 loanId) external view returns (bool) {
        return _loans[loanId].terminal;
    }
}

/// @dev Focused Stage-A coverage for the two activated account refinance methods.
contract Phase9LoanAccountRefinanceTest {
    bytes32 private constant SETTLEMENT_ASSET_ID =
        0x61737365743a7068617365393a7039756e697400000000000000000000000000;
    address private constant BORROWER = address(0xB0770);
    bytes32 private constant PAYOFF_EVENT_TOPIC =
        keccak256("RefinancePayoffRecorded(bytes32,uint256,uint64)");
    bytes32 private constant ACTIVATION_EVENT_TOPIC =
        keccak256("ReplacementLoanActivated(bytes32,uint64)");
    uint256 private constant PACKED_DEBT_SLOT = 19;
    uint256 private constant TIME_SLOT = 20;
    uint256 private constant SCHEDULE_SLOT = 21;
    uint256 private constant AGREEMENT_VERSIONS_SLOT = 35;
    uint256 private constant INITIALIZED_SLOT = 37;

    Phase9AccountRefinanceVm private constant vm =
        Phase9AccountRefinanceVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Phase9LoanAccount private _implementation;
    Phase9AccountTestFactory private _factory;
    Phase9AccountTestCoordinator private _coordinator;
    Phase9AccountTestRegistry private _registry;
    Phase9AccountTestDependency private _dependency;
    Phase9LocalSyntheticToken private _token;

    function setUp() public {
        require(block.chainid == 31337, "local chain");
        _implementation = new Phase9LoanAccount();
        _factory = new Phase9AccountTestFactory();
        _coordinator = new Phase9AccountTestCoordinator();
        _registry = new Phase9AccountTestRegistry(_coordinator);
        _dependency = new Phase9AccountTestDependency();
        _token = new Phase9LocalSyntheticToken(address(this));
    }

    function test_RecordRefinancePayoffClosesExactDebtAndRegistry() public {
        bytes32 loanId = keccak256("ACCOUNT_PAYOFF_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_PAYOFF_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_PAYOFF_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _activeDebt(loanId));
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));

        Phase9Types.DebtState memory beforeDebt = account.debtState();
        vm.recordLogs();
        _coordinator.recordPayoff(account, refinanceId, 114, operationId);
        Phase9AccountRefinanceVm.Log[] memory logs = vm.getRecordedLogs();
        Phase9Types.DebtState memory afterDebt = account.debtState();

        require(afterDebt.lifecycle == Phase9Types.LoanLifecycle.CLOSED, "closed lifecycle");
        require(
            afterDebt.servicingState == Phase9Types.ServicingState.TERMINAL, "terminal servicing"
        );
        require(afterDebt.termsVersion == beforeDebt.termsVersion, "terms changed");
        require(afterDebt.debtStateVersion == beforeDebt.debtStateVersion + 1, "debt version");
        require(afterDebt.stateNonce == beforeDebt.stateNonce + 1, "state nonce");
        require(afterDebt.commencementTime == beforeDebt.commencementTime, "commencement");
        require(afterDebt.maturityTime == beforeDebt.maturityTime, "maturity");
        require(afterDebt.scheduleHash == beforeDebt.scheduleHash, "schedule");
        require(_allEconomicAmountsZero(afterDebt), "terminal amounts");
        require(afterDebt.activeRefinanceId == refinanceId, "active refinance");
        require(afterDebt.activeRestructureId == bytes32(0), "active restructure");
        require(account.operationProcessed(operationId), "operation marker");
        require(_registry.isTerminal(loanId), "registry terminal");
        require(_registry.markCalls() == 1, "mark count");
        _requireAccountEvent(
            logs,
            address(account),
            PAYOFF_EVENT_TOPIC,
            refinanceId,
            abi.encode(uint256(114), uint64(beforeDebt.debtStateVersion + 1))
        );
    }

    function test_RecordRefinancePayoffAuthorityAndReplayClassification() public {
        bytes32 loanId = keccak256("ACCOUNT_PAYOFF_REPLAY_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_PAYOFF_REPLAY_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_PAYOFF_REPLAY_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _activeDebt(loanId));
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));

        (bool success, bytes memory returned) = address(account)
            .call(
                abi.encodeCall(
                    IPhase9LoanAccount.recordRefinancePayoff,
                    (refinanceId, uint256(114), operationId)
                )
            );
        _requireError(
            success, returned, IPhase9LoanAccount.UnauthorizedPhase9LoanCaller.selector, "authority"
        );

        _expectPayoffInvalid(account, refinanceId, 114, bytes32(0));
        _coordinator.recordPayoff(account, refinanceId, 114, operationId);
        (success, returned) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.recordPayoff,
                    (account, refinanceId, uint256(114), operationId)
                )
            );
        _requireError(
            success, returned, IPhase9LoanAccount.Phase9LoanOperationReplay.selector, "replay"
        );

        bytes32 changedOperation = keccak256("CHANGED_PAYOFF_OPERATION");
        (success, returned) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.recordPayoff,
                    (account, refinanceId, uint256(114), changedOperation)
                )
            );
        _requireError(
            success, returned, IPhase9LoanAccount.InvalidPhase9LoanOperation.selector, "changed"
        );
        require(!account.operationProcessed(changedOperation), "changed operation consumed");
    }

    function test_RecordRefinancePayoffRejectsAmountVersionNonceAndBinding() public {
        bytes32 refinanceId = keccak256("ACCOUNT_PAYOFF_INVALID_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_PAYOFF_INVALID_OPERATION");
        bytes32 loanId = keccak256("ACCOUNT_PAYOFF_INVALID_AMOUNT");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _activeDebt(loanId));
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));
        _expectPayoffInvalid(account, refinanceId, 113, operationId);

        loanId = keccak256("ACCOUNT_PAYOFF_INVALID_VERSION");
        Phase9Types.DebtState memory maxVersionDebt = _activeDebt(loanId);
        maxVersionDebt.debtStateVersion = type(uint64).max;
        (account, configuration) = _createAccount(loanId, maxVersionDebt);
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));
        _expectPayoffInvalid(account, refinanceId, 114, operationId);

        loanId = keccak256("ACCOUNT_PAYOFF_INVALID_NONCE");
        Phase9Types.DebtState memory maxNonceDebt = _activeDebt(loanId);
        maxNonceDebt.stateNonce = type(uint64).max;
        (account, configuration) = _createAccount(loanId, maxNonceDebt);
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));
        _expectPayoffInvalid(account, refinanceId, 114, operationId);

        loanId = keccak256("ACCOUNT_PAYOFF_INVALID_BINDING");
        (account, configuration) = _createAccount(loanId, _activeDebt(loanId));
        Phase9Types.RefinanceRecord memory changed = _oldRefinance(configuration, refinanceId, 114);
        changed.oldLoanId = keccak256("OTHER_OLD_LOAN");
        _coordinator.setRecord(changed);
        _expectPayoffInvalid(account, refinanceId, 114, operationId);
    }

    function test_RecordRefinancePayoffRejectsRegistryIdentityMutationMatrix() public {
        bytes32 loanId = keccak256("ACCOUNT_PAYOFF_REGISTRY_MATRIX_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_PAYOFF_REGISTRY_MATRIX_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_PAYOFF_REGISTRY_MATRIX_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _activeDebt(loanId));
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));
        bytes32 debtHash = keccak256(abi.encode(account.debtState()));

        for (uint256 mutation = 0; mutation < 6; ++mutation) {
            _registry.setLoan(
                loanId,
                mutation == 0
                    ? address(0)
                    : mutation == 1 ? address(_dependency) : address(account),
                mutation == 2 ? address(0xBADB0B) : configuration.borrower,
                mutation == 3 ? keccak256("OTHER_AGREEMENT") : configuration.agreementHash,
                mutation == 4 ? uint32(8) : uint32(9),
                mutation == 5
            );
            _expectPayoffInvalid(account, refinanceId, 114, operationId);
            require(!account.operationProcessed(operationId), "registry mutation consumed");
            require(_registry.markCalls() == 0, "registry mutation marked");
        }
        require(keccak256(abi.encode(account.debtState())) == debtHash, "registry mutation debt");
    }

    function test_RecordRefinancePayoffRejectsExecutingRecordMutationMatrix() public {
        bytes32 loanId = keccak256("ACCOUNT_PAYOFF_RECORD_MATRIX_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_PAYOFF_RECORD_MATRIX_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_PAYOFF_RECORD_MATRIX_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _activeDebt(loanId));

        _expectPayoffInvalid(account, bytes32(0), 114, operationId);
        for (uint256 mutation = 0; mutation < 6; ++mutation) {
            Phase9Types.RefinanceRecord memory changed =
                _mutatedOldRecord(_oldRefinance(configuration, refinanceId, 114), mutation);
            _coordinator.setRecord(changed);
            _expectPayoffInvalid(account, refinanceId, 114, operationId);
            require(!account.operationProcessed(operationId), "record mutation consumed");
        }
    }

    function test_RecordRefinancePayoffRejectsDebtStateMutationMatrix() public {
        bytes32 loanId = keccak256("ACCOUNT_PAYOFF_DEBT_MATRIX_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_PAYOFF_DEBT_MATRIX_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_PAYOFF_DEBT_MATRIX_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _activeDebt(loanId));
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));
        bytes32 debtHash = keccak256(abi.encode(account.debtState()));

        for (uint256 mutation = 0; mutation < 24; ++mutation) {
            (bytes32 slot, bytes32 original) = _mutatePayoffState(address(account), mutation);
            _expectPayoffInvalid(account, refinanceId, 114, operationId);
            require(!account.operationProcessed(operationId), "debt mutation consumed");
            vm.store(address(account), slot, original);
        }
        require(keccak256(abi.encode(account.debtState())) == debtHash, "debt mutation restore");

        bytes32 zeroClaimLoanId = keccak256("ACCOUNT_PAYOFF_ZERO_CLAIM_LOAN");
        Phase9Types.DebtState memory zeroClaimDebt = _activeDebt(zeroClaimLoanId);
        zeroClaimDebt.outstandingPrincipal = 0;
        zeroClaimDebt.accruedInterest = 0;
        (account, configuration) = _createAccount(zeroClaimLoanId, zeroClaimDebt);
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 4));
        _expectPayoffInvalid(account, refinanceId, 4, operationId);
    }

    function test_RecordRefinancePayoffRegistryFailureRollsBackEverything() public {
        bytes32 loanId = keccak256("ACCOUNT_PAYOFF_ROLLBACK_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_PAYOFF_ROLLBACK_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_PAYOFF_ROLLBACK_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _activeDebt(loanId));
        _coordinator.setRecord(_oldRefinance(configuration, refinanceId, 114));
        bytes32 debtHashBefore = keccak256(abi.encode(account.debtState()));

        _registry.setMarkBehavior(true, false, false, bytes32(0), 0, bytes32(0));
        _expectPayoffFailure(account, refinanceId, 114, operationId);
        _requirePayoffRollback(account, loanId, operationId, debtHashBefore);

        _registry.setMarkBehavior(false, true, false, bytes32(0), 0, bytes32(0));
        _expectPayoffFailure(account, refinanceId, 114, operationId);
        _requirePayoffRollback(account, loanId, operationId, debtHashBefore);

        _registry.setMarkBehavior(false, false, true, refinanceId, 114, operationId);
        _expectPayoffError(
            account,
            refinanceId,
            114,
            operationId,
            IPhase9LoanAccount.Phase9LoanOperationReplay.selector
        );
        _requirePayoffRollback(account, loanId, operationId, debtHashBefore);

        bytes32 freshReentryOperationId = keccak256("ACCOUNT_PAYOFF_FRESH_REENTRY_OPERATION");
        _registry.setMarkBehavior(false, false, true, refinanceId, 114, freshReentryOperationId);
        _expectPayoffError(
            account,
            refinanceId,
            114,
            operationId,
            IPhase9LoanAccount.InvalidPhase9LoanOperation.selector
        );
        _requirePayoffRollback(account, loanId, operationId, debtHashBefore);
        require(
            !account.operationProcessed(freshReentryOperationId),
            "fresh reentry operation not rolled back"
        );
    }

    function test_ActivateReplacementLoanBindsPolicyConfigurationAndAgreementVersion() public {
        bytes32 loanId = keccak256("ACCOUNT_ACTIVATION_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_ACTIVATION_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_ACTIVATION_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _dormantDebt());
        Phase9Types.DebtState memory activationDebt = _activationDebt(refinanceId);
        _coordinator.setRecord(_newRefinance(configuration, refinanceId, activationDebt));

        vm.recordLogs();
        _coordinator.activate(account, refinanceId, activationDebt, operationId);
        Phase9AccountRefinanceVm.Log[] memory logs = vm.getRecordedLogs();

        require(
            keccak256(abi.encode(account.debtState())) == keccak256(abi.encode(activationDebt)),
            "activation debt"
        );
        require(account.agreementVersionHash(0) == bytes32(0), "version zero");
        require(
            account.agreementVersionHash(activationDebt.termsVersion)
                == configuration.agreementHash,
            "agreement version"
        );
        require(account.operationProcessed(operationId), "activation operation");
        require(!_registry.isTerminal(loanId), "replacement terminal");
        _requireAccountEvent(
            logs,
            address(account),
            ACTIVATION_EVENT_TOPIC,
            refinanceId,
            abi.encode(activationDebt.debtStateVersion)
        );

        (bool success, bytes memory returned) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.activate,
                    (account, refinanceId, activationDebt, operationId)
                )
            );
        _requireError(
            success,
            returned,
            IPhase9LoanAccount.Phase9LoanOperationReplay.selector,
            "activation replay"
        );

        bytes32 changedOperation = keccak256("CHANGED_ACTIVATION_OPERATION");
        (success, returned) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.activate,
                    (account, refinanceId, activationDebt, changedOperation)
                )
            );
        _requireError(
            success,
            returned,
            IPhase9LoanAccount.InvalidPhase9LoanOperation.selector,
            "second activation"
        );
    }

    function test_ActivateReplacementLoanRejectsAuthorityStatePolicyAndDebtDrift() public {
        bytes32 loanId = keccak256("ACCOUNT_ACTIVATION_INVALID_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_ACTIVATION_INVALID_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_ACTIVATION_INVALID_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _dormantDebt());
        Phase9Types.DebtState memory activationDebt = _activationDebt(refinanceId);
        Phase9Types.RefinanceRecord memory record =
            _newRefinance(configuration, refinanceId, activationDebt);
        _coordinator.setRecord(record);

        (bool success, bytes memory returned) = address(account)
            .call(
                abi.encodeCall(
                    IPhase9LoanAccount.activateReplacementLoan,
                    (refinanceId, activationDebt, operationId)
                )
            );
        _requireError(
            success, returned, IPhase9LoanAccount.UnauthorizedPhase9LoanCaller.selector, "authority"
        );

        _expectActivationInvalid(account, refinanceId, activationDebt, bytes32(0));
        record.state = Phase9Types.RefinanceState.FUNDING_ESCROWED;
        _coordinator.setRecord(record);
        _expectActivationInvalid(account, refinanceId, activationDebt, operationId);

        record = _newRefinance(configuration, refinanceId, activationDebt);
        record.newPolicySetHash = keccak256("OTHER_POLICY_SET");
        _coordinator.setRecord(record);
        _expectActivationInvalid(account, refinanceId, activationDebt, operationId);

        record = _newRefinance(configuration, refinanceId, activationDebt);
        record.newPositionManager = address(0xBADD1E);
        _coordinator.setRecord(record);
        _expectActivationInvalid(account, refinanceId, activationDebt, operationId);

        record = _newRefinance(configuration, refinanceId, activationDebt);
        _coordinator.setRecord(record);
        activationDebt.activeRefinanceId = keccak256("OTHER_REFINANCE");
        _expectActivationInvalid(account, refinanceId, activationDebt, operationId);
        activationDebt = _activationDebt(refinanceId);
        activationDebt.termsVersion = 0;
        _expectActivationInvalid(account, refinanceId, activationDebt, operationId);
        require(
            keccak256(abi.encode(account.debtState())) == keccak256(abi.encode(_dormantDebt())),
            "invalid activation wrote debt"
        );
        require(!account.operationProcessed(operationId), "invalid operation consumed");
    }

    function test_ActivateReplacementLoanRejectsRecordBindingMutationMatrix() public {
        bytes32 loanId = keccak256("ACCOUNT_ACTIVATION_RECORD_MATRIX_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_ACTIVATION_RECORD_MATRIX_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_ACTIVATION_RECORD_MATRIX_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _dormantDebt());
        Phase9Types.DebtState memory activationDebt = _activationDebt(refinanceId);

        _expectActivationInvalid(account, bytes32(0), activationDebt, operationId);
        for (uint256 mutation = 0; mutation < 11; ++mutation) {
            Phase9Types.RefinanceRecord memory changed = _mutatedReplacementRecord(
                _newRefinance(configuration, refinanceId, activationDebt), mutation
            );
            _coordinator.setRecord(changed);
            _expectActivationInvalid(account, refinanceId, activationDebt, operationId);
            require(!account.operationProcessed(operationId), "activation record consumed");
        }
        require(
            keccak256(abi.encode(account.debtState())) == keccak256(abi.encode(_dormantDebt())),
            "activation record debt"
        );
    }

    function test_ActivateReplacementLoanRejectsRegistryIdentityMutationMatrix() public {
        bytes32 loanId = keccak256("ACCOUNT_ACTIVATION_REGISTRY_MATRIX_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_ACTIVATION_REGISTRY_MATRIX_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_ACTIVATION_REGISTRY_MATRIX_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _dormantDebt());
        Phase9Types.DebtState memory activationDebt = _activationDebt(refinanceId);
        _coordinator.setRecord(_newRefinance(configuration, refinanceId, activationDebt));

        for (uint256 mutation = 0; mutation < 6; ++mutation) {
            _registry.setLoan(
                loanId,
                mutation == 0
                    ? address(0)
                    : mutation == 1 ? address(_dependency) : address(account),
                mutation == 2 ? address(0xBADB0B) : configuration.borrower,
                mutation == 3 ? keccak256("OTHER_AGREEMENT") : configuration.agreementHash,
                mutation == 4 ? uint32(8) : uint32(9),
                mutation == 5
            );
            _expectActivationInvalid(account, refinanceId, activationDebt, operationId);
            require(!account.operationProcessed(operationId), "activation registry consumed");
            require(
                keccak256(abi.encode(account.debtState())) == keccak256(abi.encode(_dormantDebt())),
                "activation registry debt"
            );
            require(
                account.agreementVersionHash(activationDebt.termsVersion) == bytes32(0),
                "activation registry agreement"
            );
        }
    }

    function test_ActivateReplacementLoanRejectsDebtMutationMatrix() public {
        bytes32 loanId = keccak256("ACCOUNT_ACTIVATION_DEBT_MATRIX_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_ACTIVATION_DEBT_MATRIX_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_ACTIVATION_DEBT_MATRIX_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _dormantDebt());
        Phase9Types.DebtState memory activationDebt = _activationDebt(refinanceId);
        _coordinator.setRecord(_newRefinance(configuration, refinanceId, activationDebt));

        for (uint256 mutation = 0; mutation < 21; ++mutation) {
            Phase9Types.DebtState memory changed = _mutatedActivationDebt(activationDebt, mutation);
            _expectActivationInvalid(account, refinanceId, changed, operationId);
            require(!account.operationProcessed(operationId), "activation debt consumed");
        }
        require(
            keccak256(abi.encode(account.debtState())) == keccak256(abi.encode(_dormantDebt())),
            "activation debt mutation"
        );
    }

    function test_ActivateReplacementLoanRejectsDormantAndAgreementMutationMatrix() public {
        bytes32 loanId = keccak256("ACCOUNT_ACTIVATION_DORMANT_MATRIX_LOAN");
        bytes32 refinanceId = keccak256("ACCOUNT_ACTIVATION_DORMANT_MATRIX_REFINANCE");
        bytes32 operationId = keccak256("ACCOUNT_ACTIVATION_DORMANT_MATRIX_OPERATION");
        (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration) =
            _createAccount(loanId, _dormantDebt());
        Phase9Types.DebtState memory activationDebt = _activationDebt(refinanceId);
        _coordinator.setRecord(_newRefinance(configuration, refinanceId, activationDebt));

        for (uint256 mutation = 0; mutation < 25; ++mutation) {
            (bytes32 slot, bytes32 original) = _mutateDormantState(address(account), mutation);
            _expectActivationInvalid(account, refinanceId, activationDebt, operationId);
            require(!account.operationProcessed(operationId), "dormant mutation consumed");
            vm.store(address(account), slot, original);
        }
        require(account.agreementVersionHash(0) == bytes32(0), "version zero restore");
        require(
            account.agreementVersionHash(activationDebt.termsVersion) == bytes32(0),
            "collision restore"
        );
        require(
            keccak256(abi.encode(account.debtState())) == keccak256(abi.encode(_dormantDebt())),
            "dormant mutation restore"
        );
    }

    function test_OtherAccountMutatorsRemainFrozen() public {
        bytes32 loanId = keccak256("ACCOUNT_FROZEN_LOAN");
        (IPhase9LoanAccount account,) = _createAccount(loanId, _activeDebt(loanId));
        Phase9Types.LoanAmendment memory amendment;
        _expectFrozen(
            address(account),
            abi.encodeCall(IPhase9LoanAccount.applyRestructuring, (amendment, bytes32(uint256(1))))
        );
        _expectFrozen(
            address(account),
            abi.encodeCall(
                IPhase9LoanAccount.recordCoveredLoss,
                (bytes32(uint256(1)), uint256(1), bytes32(uint256(2)))
            )
        );
        _expectFrozen(
            address(account),
            abi.encodeCall(
                IPhase9LoanAccount.recordRealizedLoss,
                (bytes32(uint256(1)), uint256(1), bytes32(uint256(2)))
            )
        );
        _expectFrozen(
            address(account),
            abi.encodeCall(
                IPhase9LoanAccount.recordWriteOff,
                (bytes32(uint256(1)), uint256(1), bytes32(uint256(2)))
            )
        );
        _expectFrozen(
            address(account),
            abi.encodeCall(
                IPhase9LoanAccount.recordPostWriteOffRecovery,
                (bytes32(uint256(1)), uint256(1), bytes32(uint256(2)))
            )
        );
        _expectFrozen(
            address(account), abi.encodeCall(IPhase9LoanAccount.closeLoan, (bytes32(uint256(1))))
        );
    }

    function _createAccount(bytes32 loanId, Phase9Types.DebtState memory initialDebt)
        private
        returns (IPhase9LoanAccount account, Phase9Types.LoanConfiguration memory configuration)
    {
        configuration = _configuration(loanId);
        account = IPhase9LoanAccount(
            _factory.createAccount(address(_implementation), configuration, initialDebt)
        );
        _registry.register(
            loanId, address(account), configuration.borrower, configuration.agreementHash, 9
        );
    }

    function _configuration(bytes32 loanId)
        private
        view
        returns (Phase9Types.LoanConfiguration memory configuration)
    {
        configuration = Phase9Types.LoanConfiguration({
            factory: address(_factory),
            loanRegistry: address(_registry),
            settlementToken: address(_token),
            settlementAssetId: SETTLEMENT_ASSET_ID,
            borrower: BORROWER,
            positionManager: address(_dependency),
            collateralCustody: address(_dependency),
            lienRegistry: address(_dependency),
            payoffQuoteEngine: address(_dependency),
            refinanceCoordinator: address(_coordinator),
            restructuringController: address(_dependency),
            insuranceManager: address(_dependency),
            recoveryManager: address(_dependency),
            loanId: loanId,
            agreementHash: keccak256(abi.encode("AGREEMENT", loanId)),
            policySetHash: keccak256(abi.encode("POLICY", loanId)),
            amendmentPolicyHash: keccak256(abi.encode("AMENDMENT", loanId)),
            protectionPolicyHash: keccak256(abi.encode("PROTECTION", loanId)),
            recoveryPolicyHash: keccak256(abi.encode("RECOVERY", loanId))
        });
    }

    function _activeDebt(bytes32 loanId) private pure returns (Phase9Types.DebtState memory debt) {
        debt = Phase9Types.DebtState({
            lifecycle: Phase9Types.LoanLifecycle.ACTIVE,
            servicingState: Phase9Types.ServicingState.CURRENT,
            termsVersion: 3,
            debtStateVersion: 7,
            stateNonce: 9,
            commencementTime: 10,
            maturityTime: 20,
            scheduleHash: keccak256(abi.encode("OLD_SCHEDULE", loanId)),
            outstandingPrincipal: 100,
            accruedInterest: 10,
            capitalizedInterest: 0,
            accruedFees: 5,
            accruedPenalties: 2,
            recoverableCosts: 0,
            unappliedCredit: 3,
            coveredLossExposure: 0,
            realizedLoss: 0,
            writtenOffAmount: 0,
            recoveredAfterWriteoff: 0,
            activeRefinanceId: bytes32(0),
            activeRestructureId: bytes32(0)
        });
    }

    function _dormantDebt() private pure returns (Phase9Types.DebtState memory debt) {
        debt.lifecycle = Phase9Types.LoanLifecycle.CREATED;
        debt.servicingState = Phase9Types.ServicingState.NONE;
    }

    function _activationDebt(bytes32 refinanceId)
        private
        pure
        returns (Phase9Types.DebtState memory debt)
    {
        debt = Phase9Types.DebtState({
            lifecycle: Phase9Types.LoanLifecycle.ACTIVE,
            servicingState: Phase9Types.ServicingState.CURRENT,
            termsVersion: 4,
            debtStateVersion: 1,
            stateNonce: 1,
            commencementTime: 100,
            maturityTime: 200,
            scheduleHash: keccak256("NEW_SCHEDULE"),
            outstandingPrincipal: 120,
            accruedInterest: 0,
            capitalizedInterest: 0,
            accruedFees: 0,
            accruedPenalties: 0,
            recoverableCosts: 0,
            unappliedCredit: 0,
            coveredLossExposure: 0,
            realizedLoss: 0,
            writtenOffAmount: 0,
            recoveredAfterWriteoff: 0,
            activeRefinanceId: refinanceId,
            activeRestructureId: bytes32(0)
        });
    }

    function _oldRefinance(
        Phase9Types.LoanConfiguration memory configuration,
        bytes32 refinanceId,
        uint256 amount
    ) private view returns (Phase9Types.RefinanceRecord memory record) {
        record = _baseRefinance(configuration, refinanceId);
        record.oldLoanId = configuration.loanId;
        record.oldNetPayoff = amount;
    }

    function _newRefinance(
        Phase9Types.LoanConfiguration memory configuration,
        bytes32 refinanceId,
        Phase9Types.DebtState memory activationDebt
    ) private view returns (Phase9Types.RefinanceRecord memory record) {
        record = _baseRefinance(configuration, refinanceId);
        record.newLoanId = configuration.loanId;
        record.newPositionManager = configuration.positionManager;
        record.newPolicySetHash = configuration.policySetHash;
        record.newPrincipal = activationDebt.outstandingPrincipal;
        record.fundingAmount = activationDebt.outstandingPrincipal;
    }

    function _baseRefinance(Phase9Types.LoanConfiguration memory configuration, bytes32 refinanceId)
        private
        view
        returns (Phase9Types.RefinanceRecord memory record)
    {
        record.refinanceId = refinanceId;
        record.oldLoanId = keccak256("OLD_LOAN");
        record.newLoanId = keccak256("NEW_LOAN");
        record.borrower = configuration.borrower;
        record.oldLender = address(0x1E0D3);
        record.newPositionManager = configuration.positionManager;
        record.quoteId = keccak256("QUOTE");
        record.componentBeneficiaryHash = keccak256("COMPONENTS");
        record.oldNetPayoff = 114;
        record.newPrincipal = 120;
        record.settlementAssetId = configuration.settlementAssetId;
        record.collateralSetHash = keccak256("COLLATERAL");
        record.lienVersion = 1;
        record.proposedTermsHash = keccak256("PROPOSED_TERMS");
        record.newPolicySetHash = configuration.policySetHash;
        record.fundingAmount = 120;
        record.refinanceFee = 2;
        record.borrowerProceeds = 4;
        record.expiresAt = uint64(block.timestamp + 100);
        record.refinanceNonce = 1;
        record.refinancePolicyHash = keccak256("REFINANCE_POLICY");
        record.newLoanNonce = 1;
        record.state = Phase9Types.RefinanceState.EXECUTING;
        record.stateVersion = 3;
        record.acceptedFunding = 120;
    }

    function _mutatedOldRecord(Phase9Types.RefinanceRecord memory record, uint256 mutation)
        private
        pure
        returns (Phase9Types.RefinanceRecord memory)
    {
        if (mutation == 0) record.refinanceId = keccak256("OTHER_REFINANCE_ID");
        else if (mutation == 1) record.state = Phase9Types.RefinanceState.FUNDING_ESCROWED;
        else if (mutation == 2) record.oldLoanId = keccak256("OTHER_OLD_LOAN_ID");
        else if (mutation == 3) record.borrower = address(0xBADB0B);
        else if (mutation == 4) record.settlementAssetId = keccak256("OTHER_ASSET_ID");
        else if (mutation == 5) record.oldNetPayoff -= 1;
        else revert("unknown old record mutation");
        return record;
    }

    function _mutatedReplacementRecord(Phase9Types.RefinanceRecord memory record, uint256 mutation)
        private
        pure
        returns (Phase9Types.RefinanceRecord memory)
    {
        if (mutation == 0) {
            record.refinanceId = keccak256("OTHER_REPLACEMENT_REFINANCE_ID");
        } else if (mutation == 1) {
            record.state = Phase9Types.RefinanceState.FUNDING_ESCROWED;
        } else if (mutation == 2) {
            record.newLoanId = keccak256("OTHER_NEW_LOAN_ID");
        } else if (mutation == 3) {
            record.borrower = address(0xBADB0B);
        } else if (mutation == 4) {
            record.newPositionManager = address(0xBADF00D);
        } else if (mutation == 5) {
            record.settlementAssetId = keccak256("OTHER_ASSET_ID");
        } else if (mutation == 6) {
            record.newPolicySetHash = keccak256("OTHER_POLICY_SET");
        } else if (mutation == 7) {
            record.newPrincipal += 1;
            record.fundingAmount += 1;
        } else if (mutation == 8) {
            record.fundingAmount += 1;
        } else if (mutation == 9) {
            record.proposedTermsHash = bytes32(0);
        } else if (mutation == 10) {
            record.refinancePolicyHash = bytes32(0);
        } else {
            revert("unknown replacement record mutation");
        }
        return record;
    }

    function _mutatedActivationDebt(Phase9Types.DebtState memory debt, uint256 mutation)
        private
        pure
        returns (Phase9Types.DebtState memory)
    {
        if (mutation == 0) debt.lifecycle = Phase9Types.LoanLifecycle.CREATED;
        else if (mutation == 1) debt.servicingState = Phase9Types.ServicingState.DELINQUENT;
        else if (mutation == 2) debt.termsVersion = 0;
        else if (mutation == 3) debt.debtStateVersion = 0;
        else if (mutation == 4) debt.stateNonce = 0;
        else if (mutation == 5) debt.commencementTime = 0;
        else if (mutation == 6) debt.maturityTime = debt.commencementTime;
        else if (mutation == 7) debt.scheduleHash = bytes32(0);
        else if (mutation == 8) debt.outstandingPrincipal = 0;
        else if (mutation == 9) debt.accruedInterest = 1;
        else if (mutation == 10) debt.capitalizedInterest = 1;
        else if (mutation == 11) debt.accruedFees = 1;
        else if (mutation == 12) debt.accruedPenalties = 1;
        else if (mutation == 13) debt.recoverableCosts = 1;
        else if (mutation == 14) debt.unappliedCredit = 1;
        else if (mutation == 15) debt.coveredLossExposure = 1;
        else if (mutation == 16) debt.realizedLoss = 1;
        else if (mutation == 17) debt.writtenOffAmount = 1;
        else if (mutation == 18) debt.recoveredAfterWriteoff = 1;
        else if (mutation == 19) debt.activeRefinanceId = keccak256("OTHER_ACTIVE_REFINANCE");
        else if (mutation == 20) debt.activeRestructureId = bytes32(uint256(1));
        else revert("unknown activation debt mutation");
        return debt;
    }

    function _mutatePayoffState(address account, uint256 mutation)
        private
        returns (bytes32 slot, bytes32 original)
    {
        bytes32 changed;
        if (mutation == 0) {
            slot = bytes32(INITIALIZED_SLOT);
            original = vm.load(account, slot);
            changed = bytes32(0);
        } else if (mutation <= 8) {
            slot = bytes32(PACKED_DEBT_SLOT);
            original = vm.load(account, slot);
            uint256 word = uint256(original);
            if (mutation == 1) word = _replaceBits(word, 0, 32, 0);
            else if (mutation == 2) word = _replaceBits(word, 32, 8, 1);
            else if (mutation == 3) word = _replaceBits(word, 40, 8, 0);
            else if (mutation == 4) word = _replaceBits(word, 48, 64, 0);
            else if (mutation == 5) word = _replaceBits(word, 112, 64, 0);
            else if (mutation == 6) word = _replaceBits(word, 112, 64, type(uint64).max);
            else if (mutation == 7) word = _replaceBits(word, 176, 64, 0);
            else word = _replaceBits(word, 176, 64, type(uint64).max);
            changed = bytes32(word);
        } else if (mutation <= 10) {
            slot = bytes32(TIME_SLOT);
            original = vm.load(account, slot);
            uint256 word = uint256(original);
            changed = bytes32(
                mutation == 9 ? _replaceBits(word, 0, 64, 0) : _replaceBits(word, 64, 64, 10)
            );
        } else {
            uint256 numericSlot;
            uint256 value = 1;
            if (mutation == 11) {
                numericSlot = SCHEDULE_SLOT;
                value = 0;
            } else if (mutation == 12) {
                numericSlot = 24;
            } else if (mutation == 13) {
                numericSlot = 27;
            } else if (mutation == 14) {
                numericSlot = 29;
            } else if (mutation == 15) {
                numericSlot = 30;
            } else if (mutation == 16) {
                numericSlot = 31;
            } else if (mutation == 17) {
                numericSlot = 32;
            } else if (mutation == 18) {
                numericSlot = 33;
            } else if (mutation == 19) {
                numericSlot = 34;
            } else if (mutation == 20) {
                numericSlot = 28;
                value = 8;
            } else if (mutation == 21) {
                numericSlot = 22;
                value = type(uint256).max;
            } else if (mutation == 22) {
                numericSlot = 25;
                value = type(uint256).max;
            } else if (mutation == 23) {
                numericSlot = 22;
                value = type(uint256).max - 10;
            } else {
                revert("unknown payoff state mutation");
            }
            slot = bytes32(numericSlot);
            original = vm.load(account, slot);
            changed = bytes32(value);
        }
        vm.store(account, slot, changed);
    }

    function _mutateDormantState(address account, uint256 mutation)
        private
        returns (bytes32 slot, bytes32 original)
    {
        bytes32 changed;
        if (mutation == 0) {
            slot = bytes32(INITIALIZED_SLOT);
            original = vm.load(account, slot);
            changed = bytes32(0);
        } else if (mutation <= 6) {
            slot = bytes32(PACKED_DEBT_SLOT);
            original = vm.load(account, slot);
            uint256 word = uint256(original);
            if (mutation == 1) word = _replaceBits(word, 0, 32, 0);
            else if (mutation == 2) word = _replaceBits(word, 32, 8, 2);
            else if (mutation == 3) word = _replaceBits(word, 40, 8, 1);
            else if (mutation == 4) word = _replaceBits(word, 48, 64, 1);
            else if (mutation == 5) word = _replaceBits(word, 112, 64, 1);
            else word = _replaceBits(word, 176, 64, 1);
            changed = bytes32(word);
        } else if (mutation <= 8) {
            slot = bytes32(TIME_SLOT);
            original = vm.load(account, slot);
            changed = bytes32(mutation == 7 ? uint256(1) : uint256(1) << 64);
        } else if (mutation == 9) {
            slot = bytes32(SCHEDULE_SLOT);
            original = vm.load(account, slot);
            changed = bytes32(uint256(1));
        } else if (mutation <= 20) {
            slot = bytes32(uint256(22 + mutation - 10));
            original = vm.load(account, slot);
            changed = bytes32(uint256(1));
        } else if (mutation <= 22) {
            slot = bytes32(uint256(mutation == 21 ? 33 : 34));
            original = vm.load(account, slot);
            changed = bytes32(uint256(1));
        } else if (mutation <= 24) {
            uint256 agreementVersion = mutation == 23 ? 0 : 4;
            slot = keccak256(abi.encode(agreementVersion, AGREEMENT_VERSIONS_SLOT));
            original = vm.load(account, slot);
            changed = bytes32(uint256(1));
        } else {
            revert("unknown dormant mutation");
        }
        vm.store(account, slot, changed);
    }

    function _replaceBits(uint256 word, uint256 shift, uint256 width, uint256 value)
        private
        pure
        returns (uint256)
    {
        uint256 mask = ((uint256(1) << width) - 1) << shift;
        return (word & ~mask) | ((value << shift) & mask);
    }

    function _expectPayoffInvalid(
        IPhase9LoanAccount account,
        bytes32 refinanceId,
        uint256 amount,
        bytes32 operationId
    ) private {
        (bool success, bytes memory returned) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.recordPayoff,
                    (account, refinanceId, amount, operationId)
                )
            );
        _requireError(
            success, returned, IPhase9LoanAccount.InvalidPhase9LoanOperation.selector, "payoff"
        );
    }

    function _expectPayoffFailure(
        IPhase9LoanAccount account,
        bytes32 refinanceId,
        uint256 amount,
        bytes32 operationId
    ) private {
        (bool success,) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.recordPayoff,
                    (account, refinanceId, amount, operationId)
                )
            );
        require(!success, "payoff succeeded");
    }

    function _expectPayoffError(
        IPhase9LoanAccount account,
        bytes32 refinanceId,
        uint256 amount,
        bytes32 operationId,
        bytes4 expectedSelector
    ) private {
        (bool success, bytes memory returned) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.recordPayoff,
                    (account, refinanceId, amount, operationId)
                )
            );
        _requireError(success, returned, expectedSelector, "payoff error");
    }

    function _requirePayoffRollback(
        IPhase9LoanAccount account,
        bytes32 loanId,
        bytes32 operationId,
        bytes32 debtHashBefore
    ) private view {
        require(
            keccak256(abi.encode(account.debtState())) == debtHashBefore,
            "payoff debt not rolled back"
        );
        require(!account.operationProcessed(operationId), "payoff operation not rolled back");
        require(!_registry.isTerminal(loanId), "registry terminal not rolled back");
        require(_registry.markCalls() == 0, "mark count not rolled back");
    }

    function _expectActivationInvalid(
        IPhase9LoanAccount account,
        bytes32 refinanceId,
        Phase9Types.DebtState memory debt,
        bytes32 operationId
    ) private {
        (bool success, bytes memory returned) = address(_coordinator)
            .call(
                abi.encodeCall(
                    Phase9AccountTestCoordinator.activate, (account, refinanceId, debt, operationId)
                )
            );
        _requireError(
            success, returned, IPhase9LoanAccount.InvalidPhase9LoanOperation.selector, "activation"
        );
    }

    function _expectFrozen(address account, bytes memory callData) private {
        (bool success, bytes memory returned) = account.call(callData);
        _requireError(success, returned, Phase9ImplementationNotFrozen.selector, "frozen");
    }

    function _requireAccountEvent(
        Phase9AccountRefinanceVm.Log[] memory logs,
        address emitter,
        bytes32 signature,
        bytes32 indexedRefinanceId,
        bytes memory data
    ) private pure {
        require(logs.length == 1, "account event count");
        require(logs[0].emitter == emitter, "account event emitter");
        require(logs[0].topics.length == 2, "account event topics");
        require(logs[0].topics[0] == signature, "account event signature");
        require(logs[0].topics[1] == indexedRefinanceId, "account event refinance");
        require(keccak256(logs[0].data) == keccak256(data), "account event data");
    }

    function _allEconomicAmountsZero(Phase9Types.DebtState memory debt)
        private
        pure
        returns (bool)
    {
        return debt.outstandingPrincipal == 0 && debt.accruedInterest == 0
            && debt.capitalizedInterest == 0 && debt.accruedFees == 0 && debt.accruedPenalties == 0
            && debt.recoverableCosts == 0 && debt.unappliedCredit == 0
            && debt.coveredLossExposure == 0 && debt.realizedLoss == 0 && debt.writtenOffAmount == 0
            && debt.recoveredAfterWriteoff == 0;
    }

    function _requireError(
        bool success,
        bytes memory returned,
        bytes4 expected,
        string memory label
    ) private pure {
        require(!success, label);
        require(_selector(returned) == expected, label);
    }

    function _selector(bytes memory returned) private pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
