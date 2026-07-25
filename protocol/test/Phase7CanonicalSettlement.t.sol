// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { ProtocolTypes } from "../src/kernel/ProtocolTypes.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { CoreLoanAccount } from "../src/loan/CoreLoanAccount.sol";
import { LoanTypes } from "../src/loan/LoanTypes.sol";
import {
    CanonicalExternalSettlementGateway
} from "../src/payment/CanonicalExternalSettlementGateway.sol";
import {
    FixedMatureExternalSettlementPolicy
} from "../src/payment/FixedMatureExternalSettlementPolicy.sol";
import {
    IMatureExternalSettlementPolicy
} from "../src/interfaces/IMatureExternalSettlementPolicy.sol";

interface Phase7SettlementVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function addr(uint256 privateKey) external returns (address);
    function prank(address sender) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function sign(uint256 privateKey, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 timestamp) external;
}

contract Phase7SettlementToken is ERC20 {
    bool public feeEnabled;

    constructor() ERC20("Phase 7C Synthetic Settlement", "P7C") { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function setFeeEnabled(bool enabled) external {
        feeEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (feeEnabled && from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
            return;
        }
        super._update(from, to, value);
    }
}

contract Phase7CanonicalSettlementTest {
    Phase7SettlementVm private constant vm =
        Phase7SettlementVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 private constant NOW = 1_900_000_000;
    uint32 private constant PROTOCOL_VERSION = 77;
    uint256 private constant FINALIZER_KEY = 0xF17A11;
    uint256 private constant ATTESTER_KEY = 0xA77E57;
    uint256 private constant WRONG_ATTESTER_KEY = 0xBAD777;
    bytes32 private constant LOAN_ID = keccak256("PHASE7C:LOAN");
    bytes32 private constant SOURCE_ASSET = keccak256("PHASE7C:PROVIDER:USD");
    bytes32 private constant TARGET_ASSET = keccak256("PHASE7C:TOKEN:USD");
    bytes32 private constant OTHER_ASSET = keccak256("PHASE7C:OTHER");
    bytes32 private constant POLICY_ID = keccak256("PHASE7C:MATURE_POLICY");
    bytes32 private constant POLICY_SCHEMA = keccak256("PHASE7C:MATURE_POLICY_SCHEMA");
    bytes32 private constant CONVERSION_POLICY = keccak256("PHASE7C:CONVERSION:ONE_TO_ONE");
    bytes32 private constant FINALITY_POLICY = keccak256("PHASE7C:FINALITY:MATURE");
    bytes32 private constant GOLDEN_DIGEST =
        0x21e842e55f3dce5613f44771b5299608ea7154e8fc7fdb0fa709539373610c06;
    bytes32 private constant SETTLEMENT_EVENT_TOPIC = keccak256(
        "CanonicalSettlementExecuted(bytes32,bytes32,bytes32,(bytes32,bytes32,address,address,address,bytes32,bytes32,address,uint256,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint256,uint256,uint256,uint64,uint64,address,address))"
    );

    address private administrator = address(0xA71A);
    address private borrower = address(0xB0770);
    address private lender = address(0x1EAD7);
    address private outsider = address(0xBAD7);
    address private finalizer;
    address private attester;

    RoleManager private roles;
    LoanRegistry private loans;
    AssetRegistry private assets;
    PolicyRegistry private policies;
    EmergencyController private emergency;
    Phase7SettlementToken private token;
    FixedMatureExternalSettlementPolicy private maturePolicy;
    CoreLoanAccount private account;
    CanonicalExternalSettlementGateway private gateway;
    ProtocolTypes.PolicyRef private maturePolicyRef;

    function setUp() public {
        vm.warp(NOW);
        finalizer = vm.addr(FINALIZER_KEY);
        attester = vm.addr(ATTESTER_KEY);

        roles = new RoleManager(administrator, address(this));
        loans = new LoanRegistry(roles);
        assets = new AssetRegistry(roles);
        policies = new PolicyRegistry(roles);
        emergency = new EmergencyController(roles);
        token = new Phase7SettlementToken();
        maturePolicy = new FixedMatureExternalSettlementPolicy(
            SOURCE_ASSET, TARGET_ASSET, CONVERSION_POLICY, FINALITY_POLICY, 1 days
        );
        maturePolicyRef = ProtocolTypes.PolicyRef({
            policyId: POLICY_ID,
            implementation: address(maturePolicy),
            major: 1,
            minor: 0,
            patch: 0,
            interfaceId: type(IMatureExternalSettlementPolicy).interfaceId,
            configurationSchemaHash: POLICY_SCHEMA
        });

        _grant(ProtocolRoles.LOAN_FACTORY_ROLE, address(this));
        _grant(ProtocolRoles.ASSET_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.POLICY_REGISTRAR_ROLE, address(this));
        _grant(ProtocolRoles.PAUSER_ROLE, address(this));
        _grant(ProtocolRoles.PAYMENT_FINALIZER_ROLE, finalizer);
        _grant(ProtocolRoles.ACCOUNTING_ATTESTER_ROLE, attester);

        assets.registerAsset(TARGET_ASSET, address(token), 18, keccak256("PHASE7C:TOKEN:METADATA"));
        policies.registerPolicy(maturePolicyRef, _codeHash(address(maturePolicy)));

        ProtocolTypes.PolicyRef[] memory policySet = _policySet();
        LoanTypes.UniversalLoanTerms memory terms = LoanTypes.UniversalLoanTerms({
            loanId: LOAN_ID,
            tenderId: keccak256("PHASE7C:TENDER"),
            acceptedOfferId: keccak256("PHASE7C:OFFER"),
            agreementHash: keccak256("PHASE7C:AGREEMENT"),
            parties: LoanTypes.AgreementParties({
                borrower: borrower,
                arranger: address(0),
                servicer: address(this),
                collateralAgent: address(0),
                paymentAgent: address(0)
            }),
            principal: LoanTypes.MonetaryAmount({ assetId: TARGET_ASSET, amount: 1_000 ether }),
            fundingDeadline: NOW + 1 days,
            activationDeadline: NOW + 2 days,
            commencementTime: NOW,
            finalMaturityTime: NOW + 30 days,
            gracePeriod: 3 days,
            protocolVersion: PROTOCOL_VERSION,
            policySetHash: keccak256(abi.encode(policySet)),
            metadataHash: keccak256("PHASE7C:LOAN:METADATA")
        });
        account = new CoreLoanAccount();
        account.initialize(terms, lender, address(token), loans);
        loans.registerLoan(
            LOAN_ID, address(account), borrower, terms.agreementHash, PROTOCOL_VERSION
        );
        account.activate(keccak256("PHASE7C:ACTIVATION:JOURNAL"));

        gateway = new CanonicalExternalSettlementGateway(
            roles, loans, assets, policies, emergency, address(this), PROTOCOL_VERSION
        );
        token.mint(finalizer, 10_000 ether);
        vm.prank(finalizer);
        token.approve(address(gateway), type(uint256).max);
    }

    function testPartialSettlementMovesExactTokensAndDebt() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("PARTIAL", 400 ether);
        CanonicalExternalSettlementGateway.SettlementResult memory result =
            _settle(instruction, gateway, finalizer);

        require(result.principalUnits == 400 ether && result.excessUnits == 0, "allocation");
        require(result.debtAfter == 600 ether, "result debt");
        require(account.outstandingPrincipal() == 600 ether, "canonical debt");
        require(token.balanceOf(lender) == 400 ether, "lender payout");
        require(token.balanceOf(address(gateway)) == 0, "gateway retained value");
        require(!loans.isTerminal(LOAN_ID), "partial settlement terminal");
    }

    function testCanonicalSettlementEventCommitsCompleteInstructionAndOutcome() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("EVENT", 1_200 ether);
        ProtocolTypes.PolicyRef[] memory policySet = _policySet();
        bytes32 policySetHash = keccak256(abi.encode(policySet));
        bytes32 digest = gateway.eligibilityDigest(instruction, policySetHash, finalizer);

        vm.recordLogs();
        CanonicalExternalSettlementGateway.SettlementResult memory result =
            _settle(instruction, gateway, finalizer);
        Phase7SettlementVm.Log[] memory entries = vm.getRecordedLogs();

        CanonicalExternalSettlementGateway.CanonicalSettlementEventData memory expected =
            CanonicalExternalSettlementGateway.CanonicalSettlementEventData({
                instructionDigest: digest,
                policySetHash: policySetHash,
                loanAccount: address(account),
                finalizer: finalizer,
                attester: attester,
                sourceAssetId: instruction.sourceAssetId,
                targetAssetId: instruction.targetAssetId,
                targetToken: address(token),
                sourceUnits: instruction.sourceUnits,
                grossUnits: instruction.targetUnits,
                providerIdHash: instruction.providerIdHash,
                providerReferenceHash: instruction.providerReferenceHash,
                reconciliationId: instruction.reconciliationId,
                reconciliationCommitment: instruction.reconciliationCommitment,
                originalJournalSetHash: instruction.originalJournalSetHash,
                conversionPolicyHash: instruction.conversionPolicyHash,
                finalityPolicyHash: instruction.finalityPolicyHash,
                evidenceHash: instruction.evidenceHash,
                journalRef: instruction.journalRef,
                finalizedAt: instruction.finalizedAt,
                reversalDeadline: instruction.reversalDeadline,
                debtBefore: result.debtBefore,
                principalUnits: result.principalUnits,
                excessUnits: result.excessUnits,
                debtAfter: result.debtAfter,
                stateNonceBefore: result.stateNonceBefore,
                stateNonceAfter: result.stateNonceAfter,
                lender: lender,
                borrower: borrower
            });

        bool found;
        for (uint256 index = 0; index < entries.length; ++index) {
            Phase7SettlementVm.Log memory entry_ = entries[index];
            if (entry_.emitter != address(gateway)) continue;
            require(!found, "duplicate gateway event");
            require(entry_.topics.length == 4, "gateway event topics");
            require(entry_.topics[0] == SETTLEMENT_EVENT_TOPIC, "gateway event signature");
            require(entry_.topics[1] == instruction.paymentId, "event payment");
            require(entry_.topics[2] == instruction.allocationId, "event allocation");
            require(entry_.topics[3] == instruction.loanId, "event loan");
            require(
                keccak256(entry_.data) == keccak256(abi.encode(expected)), "gateway event payload"
            );
            found = true;
        }
        require(found, "gateway event missing");
    }

    function testFullSettlementMarksTerminal() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("FULL", 1_000 ether);
        CanonicalExternalSettlementGateway.SettlementResult memory result =
            _settle(instruction, gateway, finalizer);

        require(result.debtAfter == 0 && result.excessUnits == 0, "full result");
        require(account.outstandingPrincipal() == 0, "principal remains");
        require(loans.isTerminal(LOAN_ID), "registry not terminal");
        require(
            account.stateVector().lifecycle == LoanTypes.LoanLifecycle.CLOSED, "loan not closed"
        );
        require(token.balanceOf(lender) == 1_000 ether, "lender not paid");
    }

    function testFullSettlementReplayReturnsStoredTerminalResult() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("FULL_REPLAY", 1_000 ether);
        CanonicalExternalSettlementGateway.SettlementResult memory first =
            _settle(instruction, gateway, finalizer);
        uint256 finalizerAfterFirst = token.balanceOf(finalizer);
        uint256 lenderAfterFirst = token.balanceOf(lender);

        CanonicalExternalSettlementGateway.SettlementResult memory replay =
            _settle(instruction, gateway, finalizer);
        require(loans.isTerminal(LOAN_ID), "terminal state lost");
        require(replay.instructionDigest == first.instructionDigest, "terminal replay result");
        require(replay.debtAfter == 0, "terminal replay debt");
        require(token.balanceOf(finalizer) == finalizerAfterFirst, "terminal replay pull");
        require(token.balanceOf(lender) == lenderAfterFirst, "terminal replay payout");
    }

    function testExcessSettlementRefundsRegistryBorrowerAtomically() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("EXCESS", 1_200 ether);
        CanonicalExternalSettlementGateway.SettlementResult memory result =
            _settle(instruction, gateway, finalizer);

        require(result.principalUnits == 1_000 ether, "principal");
        require(result.excessUnits == 200 ether, "excess");
        require(token.balanceOf(lender) == 1_000 ether, "lender payout");
        require(token.balanceOf(borrower) == 200 ether, "borrower refund");
        require(token.balanceOf(address(gateway)) == 0, "gateway retained");
        require(loans.isTerminal(LOAN_ID), "loan not terminal");
    }

    function testReplayReturnsStoredResultAndConflictFails() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("REPLAY", 400 ether);
        CanonicalExternalSettlementGateway.SettlementResult memory first =
            _settle(instruction, gateway, finalizer);
        uint256 finalizerAfterFirst = token.balanceOf(finalizer);
        uint256 lenderAfterFirst = token.balanceOf(lender);

        CanonicalExternalSettlementGateway.SettlementResult memory replay =
            _settle(instruction, gateway, finalizer);
        require(replay.instructionDigest == first.instructionDigest, "replay result");
        require(token.balanceOf(finalizer) == finalizerAfterFirst, "replay pulled token");
        require(token.balanceOf(lender) == lenderAfterFirst, "replay paid lender");

        CanonicalExternalSettlementGateway.SettlementInstruction memory conflict = instruction;
        conflict.allocationId = keccak256("PHASE7C:CONFLICTING_ALLOCATION");
        bytes memory signature = _signature(gateway, conflict, _policySet(), finalizer);
        require(
            !_trySettle(gateway, conflict, _policySet(), signature, finalizer),
            "conflicting identity accepted"
        );
        require(account.outstandingPrincipal() == 600 ether, "conflict changed debt");
    }

    function testExactReplaySurvivesAdapterDisableAndRoleRevocation() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("REPLAY_MUTABLE_GATES", 400 ether);
        CanonicalExternalSettlementGateway.SettlementResult memory first =
            _settle(instruction, gateway, finalizer);
        uint256 finalizerAfterFirst = token.balanceOf(finalizer);
        uint256 lenderAfterFirst = token.balanceOf(lender);

        emergency.disableAdapter(gateway.ADAPTER_ID(), NOW + 1 days, keccak256("REPLAY"));
        roles.revokeRole(ProtocolRoles.PAYMENT_FINALIZER_ROLE, finalizer);
        roles.revokeRole(ProtocolRoles.ACCOUNTING_ATTESTER_ROLE, attester);

        vm.prank(finalizer);
        CanonicalExternalSettlementGateway.SettlementResult memory replay =
            gateway.settle(instruction, _policySet(), hex"");
        require(replay.instructionDigest == first.instructionDigest, "revoked replay digest");
        require(replay.debtAfter == first.debtAfter, "revoked replay result");
        require(token.balanceOf(finalizer) == finalizerAfterFirst, "revoked replay pull");
        require(token.balanceOf(lender) == lenderAfterFirst, "revoked replay payout");

        CanonicalExternalSettlementGateway.SettlementInstruction memory conflict = instruction;
        conflict.evidenceHash = keccak256("REPLAY:CONFLICT");
        require(
            !_trySettle(gateway, conflict, _policySet(), hex"", finalizer),
            "conflict bypassed mutable gates"
        );
    }

    function testExactReplaySurvivesRoleExpiry() public {
        roles.revokeRole(ProtocolRoles.PAYMENT_FINALIZER_ROLE, finalizer);
        roles.revokeRole(ProtocolRoles.ACCOUNTING_ATTESTER_ROLE, attester);
        roles.grantRole(ProtocolRoles.PAYMENT_FINALIZER_ROLE, finalizer, NOW + 1);
        roles.grantRole(ProtocolRoles.ACCOUNTING_ATTESTER_ROLE, attester, NOW + 1);

        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("REPLAY_EXPIRED_ROLES", 400 ether);
        CanonicalExternalSettlementGateway.SettlementResult memory first =
            _settle(instruction, gateway, finalizer);
        vm.warp(NOW + 2);

        vm.prank(finalizer);
        CanonicalExternalSettlementGateway.SettlementResult memory replay =
            gateway.settle(instruction, _policySet(), hex"");
        require(replay.instructionDigest == first.instructionDigest, "expired replay digest");
        require(replay.debtAfter == first.debtAfter, "expired replay result");
    }

    function testEligibilityDigestGoldenVector() public view {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            CanonicalExternalSettlementGateway.SettlementInstruction({
                paymentId: bytes32(uint256(1)),
                allocationId: bytes32(uint256(2)),
                loanId: bytes32(uint256(3)),
                sourceAssetId: bytes32(uint256(4)),
                targetAssetId: bytes32(uint256(5)),
                sourceUnits: 1_000,
                targetUnits: 1_000,
                providerIdHash: bytes32(uint256(6)),
                providerReferenceHash: bytes32(uint256(7)),
                reconciliationId: bytes32(uint256(8)),
                reconciliationCommitment: bytes32(uint256(9)),
                originalJournalSetHash: bytes32(uint256(10)),
                conversionPolicyHash: bytes32(uint256(11)),
                finalityPolicyHash: bytes32(uint256(12)),
                evidenceHash: bytes32(uint256(13)),
                journalRef: bytes32(uint256(14)),
                finalizedAt: 1_700_000_000,
                reversalDeadline: 1_700_086_400,
                expectedDebt: 1_200,
                expectedStateNonce: 7,
                attester: address(0x4444444444444444444444444444444444444444)
            });
        bytes32 digest = gateway.eligibilityDigestFor(
            31_337,
            address(0x1111111111111111111111111111111111111111),
            address(0x2222222222222222222222222222222222222222),
            bytes32(uint256(0x33)),
            instruction
        );
        require(digest == GOLDEN_DIGEST, "eligibility digest golden vector");
    }

    function testAuthorizationAndIndependentAttestationAreRequired() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory unauthorized =
            _instruction("UNAUTHORIZED", 100 ether);
        bytes memory outsiderSignature = _signature(gateway, unauthorized, _policySet(), outsider);
        require(
            !_trySettle(gateway, unauthorized, _policySet(), outsiderSignature, outsider),
            "unauthorized finalizer accepted"
        );

        CanonicalExternalSettlementGateway.SettlementInstruction memory forged =
            _instruction("FORGED", 100 ether);
        bytes32 digest =
            gateway.eligibilityDigest(forged, keccak256(abi.encode(_policySet())), finalizer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(WRONG_ATTESTER_KEY, digest);
        bytes memory forgedSignature = abi.encodePacked(r, s, v);
        require(
            !_trySettle(gateway, forged, _policySet(), forgedSignature, finalizer),
            "forged attestation accepted"
        );

        roles.revokeRole(ProtocolRoles.ACCOUNTING_ATTESTER_ROLE, attester);
        CanonicalExternalSettlementGateway.SettlementInstruction memory revoked =
            _instruction("REVOKED", 100 ether);
        bytes memory revokedSignature = _signature(gateway, revoked, _policySet(), finalizer);
        require(
            !_trySettle(gateway, revoked, _policySet(), revokedSignature, finalizer),
            "revoked attester accepted"
        );
        require(account.outstandingPrincipal() == 1_000 ether, "authority failure changed debt");
    }

    function testPrematureDeadlineFailsClosed() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("PREMATURE", 100 ether);
        instruction.reversalDeadline = NOW + 1;
        bytes memory signature = _signature(gateway, instruction, _policySet(), finalizer);
        uint256 finalizerBefore = token.balanceOf(finalizer);
        require(
            !_trySettle(gateway, instruction, _policySet(), signature, finalizer),
            "premature settlement accepted"
        );
        require(token.balanceOf(finalizer) == finalizerBefore, "premature token movement");
        require(account.outstandingPrincipal() == 1_000 ether, "premature debt movement");
    }

    function testWrongPolicyAssetDebtAndNonceFailClosed() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory wrongAsset =
            _instruction("WRONG_ASSET", 100 ether);
        wrongAsset.targetAssetId = OTHER_ASSET;
        require(!_signedAttempt(wrongAsset, _policySet()), "wrong asset accepted");

        CanonicalExternalSettlementGateway.SettlementInstruction memory wrongDebt =
            _instruction("WRONG_DEBT", 100 ether);
        wrongDebt.expectedDebt -= 1;
        require(!_signedAttempt(wrongDebt, _policySet()), "wrong debt accepted");

        CanonicalExternalSettlementGateway.SettlementInstruction memory wrongNonce =
            _instruction("WRONG_NONCE", 100 ether);
        ++wrongNonce.expectedStateNonce;
        require(!_signedAttempt(wrongNonce, _policySet()), "wrong nonce accepted");

        ProtocolTypes.PolicyRef[] memory wrongPolicies = _policySet();
        wrongPolicies[0].configurationSchemaHash = keccak256("WRONG_SCHEMA");
        CanonicalExternalSettlementGateway.SettlementInstruction memory wrongPolicy =
            _instruction("WRONG_POLICY", 100 ether);
        require(!_signedAttempt(wrongPolicy, wrongPolicies), "wrong policy accepted");
        require(account.outstandingPrincipal() == 1_000 ether, "invalid request changed debt");
    }

    function testPolicyDeprecationDoesNotRemoveBoundRepaymentRoute() public {
        policies.deprecatePolicy(POLICY_ID, 1, 0, 0);
        require(!policies.isApproved(maturePolicyRef), "policy still origination-active");
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("DEPRECATED", 100 ether);
        _settle(instruction, gateway, finalizer);
        require(account.outstandingPrincipal() == 900 ether, "bound route removed");
    }

    function testDirectRepaymentRaceInvalidatesSignedDebtAndNonce() public {
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("RACE", 400 ether);
        bytes memory signature = _signature(gateway, instruction, _policySet(), finalizer);

        token.mint(borrower, 100 ether);
        vm.prank(borrower);
        token.approve(address(account), 100 ether);
        vm.prank(borrower);
        account.repay(
            keccak256("PHASE7C:DIRECT:RACE"), 100 ether, keccak256("PHASE7C:DIRECT:JOURNAL")
        );

        uint256 finalizerBefore = token.balanceOf(finalizer);
        require(
            !_trySettle(gateway, instruction, _policySet(), signature, finalizer),
            "stale canonicalization accepted"
        );
        require(account.outstandingPrincipal() == 900 ether, "race changed twice");
        require(token.balanceOf(finalizer) == finalizerBefore, "race pulled finalizer");
    }

    function testEmergencyAdapterDisableBlocksOnlyGatewayRoute() public {
        emergency.disableAdapter(gateway.ADAPTER_ID(), NOW + 1 days, keccak256("PHASE7C:INCIDENT"));
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("DISABLED", 100 ether);
        require(!_signedAttempt(instruction, _policySet()), "disabled adapter accepted");

        token.mint(borrower, 100 ether);
        vm.prank(borrower);
        token.approve(address(account), 100 ether);
        vm.prank(borrower);
        account.repay(
            keccak256("PHASE7C:DIRECT:SAFE"), 100 ether, keccak256("PHASE7C:DIRECT:SAFE:JOURNAL")
        );
        require(account.outstandingPrincipal() == 900 ether, "direct repayment blocked");
    }

    function testFeeTokenDeltaFailureRollsBackEveryEffect() public {
        token.setFeeEnabled(true);
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction =
            _instruction("FEE_TOKEN", 400 ether);
        uint256 finalizerBefore = token.balanceOf(finalizer);
        bytes memory signature = _signature(gateway, instruction, _policySet(), finalizer);
        require(
            !_trySettle(gateway, instruction, _policySet(), signature, finalizer),
            "fee token accepted"
        );
        require(token.balanceOf(finalizer) == finalizerBefore, "fee rollback finalizer");
        require(token.balanceOf(address(gateway)) == 0, "fee rollback gateway");
        require(token.balanceOf(lender) == 0, "fee rollback lender");
        require(account.outstandingPrincipal() == 1_000 ether, "fee rollback debt");
        require(
            gateway.paymentInstructionDigest(instruction.paymentId) == bytes32(0),
            "fee rollback identity"
        );
    }

    function testFactoryVersionAndParticipantSeparationAreEnforced() public {
        CanonicalExternalSettlementGateway wrongFactoryGateway = new CanonicalExternalSettlementGateway(
            roles, loans, assets, policies, emergency, address(token), PROTOCOL_VERSION
        );
        vm.prank(finalizer);
        token.approve(address(wrongFactoryGateway), type(uint256).max);
        CanonicalExternalSettlementGateway.SettlementInstruction memory provenance =
            _instruction("PROVENANCE", 100 ether);
        bytes memory provenanceSignature =
            _signature(wrongFactoryGateway, provenance, _policySet(), finalizer);
        require(
            !_trySettle(
                wrongFactoryGateway, provenance, _policySet(), provenanceSignature, finalizer
            ),
            "wrong factory accepted"
        );

        _grant(ProtocolRoles.PAYMENT_FINALIZER_ROLE, lender);
        token.mint(lender, 100 ether);
        vm.prank(lender);
        token.approve(address(gateway), 100 ether);
        CanonicalExternalSettlementGateway.SettlementInstruction memory aliased =
            _instruction("ALIASED", 100 ether);
        bytes memory aliasedSignature = _signature(gateway, aliased, _policySet(), lender);
        require(
            !_trySettle(gateway, aliased, _policySet(), aliasedSignature, lender),
            "lender finalizer accepted"
        );
        require(account.outstandingPrincipal() == 1_000 ether, "separation changed debt");
    }

    function _instruction(string memory salt, uint256 gross)
        private
        view
        returns (CanonicalExternalSettlementGateway.SettlementInstruction memory instruction)
    {
        instruction = CanonicalExternalSettlementGateway.SettlementInstruction({
            paymentId: keccak256(abi.encode("PHASE7C:PAYMENT", salt)),
            allocationId: keccak256(abi.encode("PHASE7C:ALLOCATION", salt)),
            loanId: LOAN_ID,
            sourceAssetId: SOURCE_ASSET,
            targetAssetId: TARGET_ASSET,
            sourceUnits: gross,
            targetUnits: gross,
            providerIdHash: keccak256("PHASE7C:SYNTHETIC_PROVIDER"),
            providerReferenceHash: keccak256(abi.encode("PHASE7C:PROVIDER_REFERENCE", salt)),
            reconciliationId: keccak256(abi.encode("PHASE7C:RECONCILIATION", salt)),
            reconciliationCommitment: keccak256(
                abi.encode("PHASE7C:MATCHED_RECONCILIATION", salt, gross)
            ),
            originalJournalSetHash: keccak256(abi.encode("PHASE7C:ORIGINAL_JOURNALS", salt)),
            conversionPolicyHash: CONVERSION_POLICY,
            finalityPolicyHash: FINALITY_POLICY,
            evidenceHash: keccak256(abi.encode("PHASE7C:EVIDENCE", salt)),
            journalRef: keccak256(abi.encode("PHASE7C:CANONICAL_JOURNAL", salt)),
            finalizedAt: NOW - 2 days,
            reversalDeadline: NOW - 1,
            expectedDebt: account.outstandingPrincipal(),
            expectedStateNonce: account.stateVector().stateNonce,
            attester: attester
        });
    }

    function _settle(
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction,
        CanonicalExternalSettlementGateway targetGateway,
        address caller
    ) private returns (CanonicalExternalSettlementGateway.SettlementResult memory result) {
        ProtocolTypes.PolicyRef[] memory policySet = _policySet();
        bytes memory signature = _signature(targetGateway, instruction, policySet, caller);
        vm.prank(caller);
        return targetGateway.settle(instruction, policySet, signature);
    }

    function _signedAttempt(
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction,
        ProtocolTypes.PolicyRef[] memory policySet
    ) private returns (bool) {
        bytes memory signature = _signature(gateway, instruction, policySet, finalizer);
        return _trySettle(gateway, instruction, policySet, signature, finalizer);
    }

    function _trySettle(
        CanonicalExternalSettlementGateway targetGateway,
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction,
        ProtocolTypes.PolicyRef[] memory policySet,
        bytes memory signature,
        address caller
    ) private returns (bool success) {
        vm.prank(caller);
        (success,) = address(targetGateway)
            .call(abi.encodeCall(targetGateway.settle, (instruction, policySet, signature)));
    }

    function _signature(
        CanonicalExternalSettlementGateway targetGateway,
        CanonicalExternalSettlementGateway.SettlementInstruction memory instruction,
        ProtocolTypes.PolicyRef[] memory policySet,
        address caller
    ) private returns (bytes memory) {
        require(caller != address(0), "invalid signature caller");
        bytes32 digest = targetGateway.eligibilityDigest(
            instruction, keccak256(abi.encode(policySet)), caller
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _policySet() private view returns (ProtocolTypes.PolicyRef[] memory policySet) {
        policySet = new ProtocolTypes.PolicyRef[](1);
        policySet[0] = maturePolicyRef;
    }

    function _grant(bytes32 role, address account_) private {
        roles.grantRole(role, account_, type(uint64).max);
    }

    function _codeHash(address target) private view returns (bytes32 codeHash) {
        assembly ("memory-safe") {
            codeHash := extcodehash(target)
        }
    }
}
