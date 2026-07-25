// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IMatureExternalSettlementPolicy } from "../interfaces/IMatureExternalSettlementPolicy.sol";
import { ILoanRegistry } from "../interfaces/ILoanRegistry.sol";
import { IRoleManager } from "../interfaces/IRoleManager.sol";
import { AssetRegistry } from "../kernel/AssetRegistry.sol";
import { EmergencyController } from "../kernel/EmergencyController.sol";
import { PolicyRegistry } from "../kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../kernel/ProtocolRoles.sol";
import { ProtocolTypes } from "../kernel/ProtocolTypes.sol";
import { RoleControlled } from "../kernel/RoleControlled.sol";
import { CoreLoanAccount } from "../loan/CoreLoanAccount.sol";
import { LoanTypes } from "../loan/LoanTypes.sol";

/// @notice Converts attested mature external settlement into exact canonical loan tokens.
/// @dev Synthetic/local Phase 7C only. No provider callback, FX, reserve, or collateral call.
contract CanonicalExternalSettlementGateway is RoleControlled, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidGatewayConfiguration();
    error InvalidSettlementInstruction();
    error InvalidSettlementAuthority();
    error InvalidSettlementAttestation();
    error InvalidSettlementPolicy();
    error InvalidCanonicalLoan();
    error InvalidSettlementAsset();
    error SettlementAdapterDisabled();
    error SettlementIdentityConflict();
    error SettlementBalanceMismatch();

    bytes32 public constant ADAPTER_ID = keccak256("UNIFIED_PHASE7C_CANONICAL_EXTERNAL_SETTLEMENT");
    bytes32 public constant ELIGIBILITY_DOMAIN = keccak256("UNIFIED_PHASE7C_ELIGIBILITY_V1");

    struct SettlementInstruction {
        bytes32 paymentId;
        bytes32 allocationId;
        bytes32 loanId;
        bytes32 sourceAssetId;
        bytes32 targetAssetId;
        uint256 sourceUnits;
        uint256 targetUnits;
        bytes32 providerIdHash;
        bytes32 providerReferenceHash;
        bytes32 reconciliationId;
        bytes32 reconciliationCommitment;
        bytes32 originalJournalSetHash;
        bytes32 conversionPolicyHash;
        bytes32 finalityPolicyHash;
        bytes32 evidenceHash;
        bytes32 journalRef;
        uint64 finalizedAt;
        uint64 reversalDeadline;
        uint256 expectedDebt;
        uint64 expectedStateNonce;
        address attester;
    }

    struct SettlementResult {
        bytes32 instructionDigest;
        address loanAccount;
        address finalizer;
        address attester;
        uint256 grossUnits;
        uint256 principalUnits;
        uint256 excessUnits;
        uint256 debtBefore;
        uint256 debtAfter;
        uint64 stateNonceBefore;
        uint64 stateNonceAfter;
    }

    /// @dev Complete, self-contained event payload for deterministic off-chain decoding.
    /// Chain ID and gateway address are supplied by the EVM log envelope.
    struct CanonicalSettlementEventData {
        bytes32 instructionDigest;
        bytes32 policySetHash;
        address loanAccount;
        address finalizer;
        address attester;
        bytes32 sourceAssetId;
        bytes32 targetAssetId;
        address targetToken;
        uint256 sourceUnits;
        uint256 grossUnits;
        bytes32 providerIdHash;
        bytes32 providerReferenceHash;
        bytes32 reconciliationId;
        bytes32 reconciliationCommitment;
        bytes32 originalJournalSetHash;
        bytes32 conversionPolicyHash;
        bytes32 finalityPolicyHash;
        bytes32 evidenceHash;
        bytes32 journalRef;
        uint64 finalizedAt;
        uint64 reversalDeadline;
        uint256 debtBefore;
        uint256 principalUnits;
        uint256 excessUnits;
        uint256 debtAfter;
        uint64 stateNonceBefore;
        uint64 stateNonceAfter;
        address lender;
        address borrower;
    }

    struct LoanContext {
        CoreLoanAccount account;
        LoanTypes.UniversalLoanTerms terms;
        LoanTypes.LoanStateVector state;
        address borrower;
        address lender;
    }

    struct BalanceSnapshot {
        uint256 finalizer;
        uint256 gateway;
        uint256 lender;
        uint256 borrower;
    }

    ILoanRegistry public immutable loanRegistry;
    AssetRegistry public immutable assetRegistry;
    PolicyRegistry public immutable policyRegistry;
    EmergencyController public immutable emergencyController;
    address public immutable approvedLoanFactory;
    uint32 public immutable approvedProtocolVersion;

    mapping(bytes32 paymentId => bytes32 digest) public paymentInstructionDigest;
    mapping(bytes32 allocationId => bytes32 digest) public allocationInstructionDigest;
    mapping(bytes32 paymentId => SettlementResult result) private _results;

    event CanonicalSettlementExecuted(
        bytes32 indexed paymentId,
        bytes32 indexed allocationId,
        bytes32 indexed loanId,
        CanonicalSettlementEventData settlement
    );

    constructor(
        IRoleManager roleManager_,
        ILoanRegistry loanRegistry_,
        AssetRegistry assetRegistry_,
        PolicyRegistry policyRegistry_,
        EmergencyController emergencyController_,
        address approvedLoanFactory_,
        uint32 approvedProtocolVersion_
    ) RoleControlled(roleManager_) {
        if (
            address(loanRegistry_).code.length == 0 || address(assetRegistry_).code.length == 0
                || address(policyRegistry_).code.length == 0
                || address(emergencyController_).code.length == 0
                || approvedLoanFactory_.code.length == 0 || approvedProtocolVersion_ == 0
        ) {
            revert InvalidGatewayConfiguration();
        }
        loanRegistry = loanRegistry_;
        assetRegistry = assetRegistry_;
        policyRegistry = policyRegistry_;
        emergencyController = emergencyController_;
        approvedLoanFactory = approvedLoanFactory_;
        approvedProtocolVersion = approvedProtocolVersion_;
    }

    function settle(
        SettlementInstruction calldata instruction,
        ProtocolTypes.PolicyRef[] calldata policies,
        bytes calldata attestation
    ) external nonReentrant returns (SettlementResult memory result) {
        _requireInstruction(instruction);
        bytes32 policySetHash = hashPolicySet(policies);
        bytes32 digest = eligibilityDigest(instruction, policySetHash, msg.sender);
        // A committed identity is immutable historical state. Resolve exact replay or
        // conflicting reuse before consulting mutable pause, role, policy, or signature gates.
        result = _replayOrConflict(instruction, digest);
        if (result.instructionDigest != bytes32(0)) return result;

        _requireAdapterAvailable();
        LoanContext memory loan = _loanContext(instruction.loanId);
        _requireAuthorities(loan, instruction.attester);
        if (policySetHash != loan.terms.policySetHash) revert InvalidSettlementPolicy();
        if (!SignatureChecker.isValidSignatureNow(instruction.attester, digest, attestation)) {
            revert InvalidSettlementAttestation();
        }

        _requireCanonicalLoan(loan, instruction);
        IERC20 token = _requireAssetAndPolicy(loan, instruction, policies);
        result = _execute(loan, token, instruction, digest);
    }

    function eligibilityDigest(
        SettlementInstruction calldata instruction,
        bytes32 policySetHash,
        address finalizer
    ) public view returns (bytes32) {
        return eligibilityDigestFor(
            block.chainid, address(this), finalizer, policySetHash, instruction
        );
    }

    /// @notice Pure form used by off-chain encoders and the cross-language golden vector.
    function eligibilityDigestFor(
        uint256 chainId,
        address gateway,
        address finalizer,
        bytes32 policySetHash,
        SettlementInstruction calldata instruction
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(ELIGIBILITY_DOMAIN, chainId, gateway, finalizer, policySetHash, instruction)
        );
    }

    function hashPolicySet(ProtocolTypes.PolicyRef[] calldata policies)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(policies));
    }

    function settlementResult(bytes32 paymentId) external view returns (SettlementResult memory) {
        return _results[paymentId];
    }

    function _requireInstruction(SettlementInstruction calldata instruction) private view {
        if (
            instruction.paymentId == bytes32(0) || instruction.allocationId == bytes32(0)
                || instruction.loanId == bytes32(0) || instruction.sourceAssetId == bytes32(0)
                || instruction.targetAssetId == bytes32(0)
                || instruction.sourceAssetId == instruction.targetAssetId
                || instruction.sourceUnits == 0
                || instruction.sourceUnits != instruction.targetUnits
                || instruction.providerIdHash == bytes32(0)
                || instruction.providerReferenceHash == bytes32(0)
                || instruction.reconciliationId == bytes32(0)
                || instruction.reconciliationCommitment == bytes32(0)
                || instruction.originalJournalSetHash == bytes32(0)
                || instruction.conversionPolicyHash == bytes32(0)
                || instruction.finalityPolicyHash == bytes32(0)
                || instruction.evidenceHash == bytes32(0) || instruction.journalRef == bytes32(0)
                || instruction.finalizedAt == 0
                || instruction.reversalDeadline <= instruction.finalizedAt
                || block.timestamp < instruction.reversalDeadline || instruction.expectedDebt == 0
                || instruction.expectedStateNonce == 0 || instruction.attester == address(0)
        ) {
            revert InvalidSettlementInstruction();
        }
    }

    function _requireAdapterAvailable() private view {
        bytes32 actionId = emergencyController.adapterActionId(ADAPTER_ID);
        (bool disabled,,) = emergencyController.emergencyState(actionId);
        if (disabled) revert SettlementAdapterDisabled();
    }

    function _loanContext(bytes32 loanId) private view returns (LoanContext memory loan) {
        address accountAddress = loanRegistry.loanAccount(loanId);
        if (!loanRegistry.exists(loanId) || accountAddress.code.length == 0) {
            revert InvalidCanonicalLoan();
        }
        loan.account = CoreLoanAccount(accountAddress);
        loan.terms = loan.account.terms();
        loan.state = loan.account.stateVector();
        loan.borrower = loanRegistry.borrowerOf(loanId);
        loan.lender = loan.account.lender();
        if (
            loan.account.loanId() != loanId || loan.terms.loanId != loanId
                || loan.account.borrower() != loan.borrower
                || loan.terms.parties.borrower != loan.borrower || loan.borrower == address(0)
                || loan.lender == address(0)
                || address(loan.account.loanRegistry()) != address(loanRegistry)
        ) {
            revert InvalidCanonicalLoan();
        }
    }

    function _requireAuthorities(LoanContext memory loan, address attester) private view {
        bool finalizerAuthorized =
            roleManager.hasRole(ProtocolRoles.PAYMENT_FINALIZER_ROLE, msg.sender);
        bool attesterAuthorized =
            roleManager.hasRole(ProtocolRoles.ACCOUNTING_ATTESTER_ROLE, attester);
        if (
            !finalizerAuthorized || !attesterAuthorized || msg.sender == address(this)
                || msg.sender == address(loan.account) || msg.sender == loan.lender
                || msg.sender == loan.borrower || msg.sender == attester
                || attester == address(this) || attester == address(loan.account)
                || attester == loan.lender || attester == loan.borrower
        ) {
            revert InvalidSettlementAuthority();
        }
    }

    function _replayOrConflict(SettlementInstruction calldata instruction, bytes32 digest)
        private
        view
        returns (SettlementResult memory result)
    {
        bytes32 paymentDigest = paymentInstructionDigest[instruction.paymentId];
        bytes32 allocationDigest = allocationInstructionDigest[instruction.allocationId];
        if (paymentDigest == bytes32(0) && allocationDigest == bytes32(0)) return result;
        if (paymentDigest != digest || allocationDigest != digest) {
            revert SettlementIdentityConflict();
        }
        result = _results[instruction.paymentId];
        if (result.instructionDigest != digest) revert SettlementIdentityConflict();
    }

    function _requireCanonicalLoan(
        LoanContext memory loan,
        SettlementInstruction calldata instruction
    ) private view {
        if (
            loan.account.factory() != approvedLoanFactory
                || loanRegistry.protocolVersionOf(instruction.loanId) != approvedProtocolVersion
                || loan.terms.protocolVersion != approvedProtocolVersion
                || loanRegistry.isTerminal(instruction.loanId)
                || loan.state.lifecycle != LoanTypes.LoanLifecycle.ACTIVE
                || !loan.account.isRepaymentAllowed()
                || loan.state.stateNonce != instruction.expectedStateNonce
                || loan.account.outstandingPrincipal() != instruction.expectedDebt
        ) {
            revert InvalidCanonicalLoan();
        }
    }

    function _requireAssetAndPolicy(
        LoanContext memory loan,
        SettlementInstruction calldata instruction,
        ProtocolTypes.PolicyRef[] calldata policies
    ) private view returns (IERC20 token) {
        if (instruction.targetAssetId != loan.terms.principal.assetId) {
            revert InvalidSettlementAsset();
        }
        AssetRegistry.AssetRecord memory asset = assetRegistry.resolve(instruction.targetAssetId);
        if (
            !asset.active || asset.token.code.length == 0
                || asset.token != loan.account.settlementToken()
        ) {
            revert InvalidSettlementAsset();
        }
        uint256 maturePolicies;
        for (uint256 index = 0; index < policies.length; ++index) {
            ProtocolTypes.PolicyRef calldata policy = policies[index];
            if (policy.interfaceId != type(IMatureExternalSettlementPolicy).interfaceId) continue;
            ++maturePolicies;
            _requireHistoricalMaturePolicy(policy, instruction);
        }
        if (maturePolicies != 1) revert InvalidSettlementPolicy();
        token = IERC20(asset.token);
    }

    function _requireHistoricalMaturePolicy(
        ProtocolTypes.PolicyRef calldata policy,
        SettlementInstruction calldata instruction
    ) private view {
        ProtocolTypes.PolicyRef memory registered =
            policyRegistry.resolvePolicy(policy.policyId, policy.major, policy.minor, policy.patch);
        bytes32 registeredCodeHash = policyRegistry.codeHashOf(policy.implementation);
        if (
            keccak256(abi.encode(registered)) != keccak256(abi.encode(policy))
                || registeredCodeHash == bytes32(0)
                || policy.implementation.codehash != registeredCodeHash
        ) {
            revert InvalidSettlementPolicy();
        }
        bool permitted = IMatureExternalSettlementPolicy(policy.implementation)
            .permitsMatureSettlement(
                instruction.sourceAssetId,
                instruction.targetAssetId,
                instruction.conversionPolicyHash,
                instruction.finalityPolicyHash,
                instruction.finalizedAt,
                instruction.reversalDeadline
            );
        if (!permitted) revert InvalidSettlementPolicy();
    }

    function _execute(
        LoanContext memory loan,
        IERC20 token,
        SettlementInstruction calldata instruction,
        bytes32 digest
    ) private returns (SettlementResult memory result) {
        uint256 principal = instruction.targetUnits;
        if (principal > instruction.expectedDebt) principal = instruction.expectedDebt;
        uint256 excess = instruction.targetUnits - principal;
        BalanceSnapshot memory before_ = BalanceSnapshot({
            finalizer: token.balanceOf(msg.sender),
            gateway: token.balanceOf(address(this)),
            lender: token.balanceOf(loan.lender),
            borrower: token.balanceOf(loan.borrower)
        });

        paymentInstructionDigest[instruction.paymentId] = digest;
        allocationInstructionDigest[instruction.allocationId] = digest;

        token.safeTransferFrom(msg.sender, address(this), instruction.targetUnits);
        _requirePullBalance(token, before_, instruction.targetUnits);

        token.forceApprove(address(loan.account), principal);
        loan.account.repay(instruction.paymentId, principal, instruction.journalRef);
        token.forceApprove(address(loan.account), 0);
        if (excess != 0) token.safeTransfer(loan.borrower, excess);

        LoanTypes.LoanStateVector memory afterState = loan.account.stateVector();
        uint256 debtAfter = loan.account.outstandingPrincipal();
        if (
            debtAfter != instruction.expectedDebt - principal
                || token.allowance(address(this), address(loan.account)) != 0
        ) {
            revert SettlementBalanceMismatch();
        }
        _requireFinalBalances(token, before_, instruction.targetUnits, principal, excess, loan);

        result = SettlementResult({
            instructionDigest: digest,
            loanAccount: address(loan.account),
            finalizer: msg.sender,
            attester: instruction.attester,
            grossUnits: instruction.targetUnits,
            principalUnits: principal,
            excessUnits: excess,
            debtBefore: instruction.expectedDebt,
            debtAfter: debtAfter,
            stateNonceBefore: instruction.expectedStateNonce,
            stateNonceAfter: afterState.stateNonce
        });
        _results[instruction.paymentId] = result;
        emit CanonicalSettlementExecuted(
            instruction.paymentId,
            instruction.allocationId,
            instruction.loanId,
            CanonicalSettlementEventData({
                instructionDigest: digest,
                policySetHash: loan.terms.policySetHash,
                loanAccount: address(loan.account),
                finalizer: msg.sender,
                attester: instruction.attester,
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
                debtBefore: instruction.expectedDebt,
                principalUnits: principal,
                excessUnits: excess,
                debtAfter: debtAfter,
                stateNonceBefore: instruction.expectedStateNonce,
                stateNonceAfter: afterState.stateNonce,
                lender: loan.lender,
                borrower: loan.borrower
            })
        );
    }

    function _requirePullBalance(IERC20 token, BalanceSnapshot memory before_, uint256 gross)
        private
        view
    {
        uint256 finalizerAfter = token.balanceOf(msg.sender);
        uint256 gatewayAfter = token.balanceOf(address(this));
        if (
            finalizerAfter > before_.finalizer || before_.finalizer - finalizerAfter != gross
                || gatewayAfter < before_.gateway || gatewayAfter - before_.gateway != gross
        ) {
            revert SettlementBalanceMismatch();
        }
    }

    function _requireFinalBalances(
        IERC20 token,
        BalanceSnapshot memory before_,
        uint256 gross,
        uint256 principal,
        uint256 excess,
        LoanContext memory loan
    ) private view {
        uint256 finalizerAfter = token.balanceOf(msg.sender);
        uint256 lenderAfter = token.balanceOf(loan.lender);
        uint256 borrowerAfter = token.balanceOf(loan.borrower);
        if (
            finalizerAfter > before_.finalizer || before_.finalizer - finalizerAfter != gross
                || token.balanceOf(address(this)) != before_.gateway || lenderAfter < before_.lender
                || lenderAfter - before_.lender != principal || borrowerAfter < before_.borrower
                || borrowerAfter - before_.borrower != excess
        ) {
            revert SettlementBalanceMismatch();
        }
    }
}
