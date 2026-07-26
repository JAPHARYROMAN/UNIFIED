// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ILoanRegistry } from "../src/interfaces/ILoanRegistry.sol";
import { IPayoffQuoteEngineV2 } from "../src/interfaces/phase9/IPayoffQuoteEngineV2.sol";
import { IPhase9LoanAccount } from "../src/interfaces/phase9/IPhase9LoanAccount.sol";
import { IPhase9LoanFactory } from "../src/interfaces/phase9/IPhase9LoanFactory.sol";
import { IPositionManagerV2 } from "../src/interfaces/phase9/IPositionManagerV2.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";

interface Phase9PayoffVm {
    enum AccountAccessKind {
        Call,
        DelegateCall,
        CallCode,
        StaticCall,
        Create,
        SelfDestruct,
        Resume,
        Balance,
        Extcodesize,
        Extcodehash,
        Extcodecopy
    }

    struct ChainInfo {
        uint256 forkId;
        uint256 chainId;
    }

    struct StorageAccess {
        address account;
        bytes32 slot;
        bool isWrite;
        bytes32 previousValue;
        bytes32 newValue;
        bool reverted;
    }

    struct AccountAccess {
        ChainInfo chainInfo;
        AccountAccessKind kind;
        address account;
        address accessor;
        bool initialized;
        uint256 oldBalance;
        uint256 newBalance;
        bytes deployedCode;
        uint256 value;
        bytes data;
        bool reverted;
        StorageAccess[] storageAccesses;
        uint64 depth;
        uint64 oldNonce;
        uint64 newNonce;
    }

    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function chainId(uint256 chainId) external;
    function deal(address account, uint256 balance) external;
    function getRecordedLogs() external returns (Log[] memory logs);
    function load(address target, bytes32 slot) external view returns (bytes32 value);
    function prank(address sender) external;
    function recordLogs() external;
    function startStateDiffRecording() external;
    function stopAndReturnStateDiff() external returns (AccountAccess[] memory accesses);
    function store(address target, bytes32 slot, bytes32 value) external;
    function warp(uint256 timestamp) external;
}

interface IPhase9PayoffQuotePolicySource {
    function resolvePayoffQuotePolicy(bytes32 loanId, address loanAccount)
        external
        view
        returns (
            bytes32 policyHash,
            bytes32 boundPolicySetHash,
            address feePenaltyBeneficiary,
            bytes32 settlementAssetId,
            address settlementToken,
            uint64 maximumValidity,
            bool active
        );
}

contract Phase9PayoffMockRegistry is ILoanRegistry {
    struct Record {
        address account;
        address borrower;
        bytes32 agreementHash;
        uint32 version;
        bool exists_;
        bool terminal;
    }

    mapping(bytes32 loanId => Record record) private _records;
    bool public shouldRevert;

    function setRecord(bytes32 loanId, Record memory record) external {
        _records[loanId] = record;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function registerLoan(
        bytes32 loanId,
        address account,
        address borrower,
        bytes32 agreementHash,
        uint32 protocolVersion
    ) external {
        _records[loanId] = Record(account, borrower, agreementHash, protocolVersion, true, false);
    }

    function loanAccount(bytes32 loanId) external view returns (address) {
        _reject();
        return _records[loanId].account;
    }

    function borrowerOf(bytes32 loanId) external view returns (address) {
        _reject();
        return _records[loanId].borrower;
    }

    function agreementHashOf(bytes32 loanId) external view returns (bytes32) {
        _reject();
        return _records[loanId].agreementHash;
    }

    function protocolVersionOf(bytes32 loanId) external view returns (uint32) {
        _reject();
        return _records[loanId].version;
    }

    function exists(bytes32 loanId) external view returns (bool) {
        _reject();
        return _records[loanId].exists_;
    }

    function isTerminal(bytes32 loanId) external view returns (bool) {
        _reject();
        return _records[loanId].terminal;
    }

    function markTerminal(bytes32 loanId) external {
        _records[loanId].terminal = true;
    }

    function _reject() private view {
        if (shouldRevert) revert("REGISTRY_READ_REVERTED");
    }
}

contract Phase9PayoffMockFactory is IPhase9LoanFactory {
    mapping(bytes32 loanId => address account) private _accounts;
    mapping(bytes32 loanId => address manager) private _managers;
    bool public shouldRevert;

    function setLoan(bytes32 loanId, address account, address manager) external {
        _accounts[loanId] = account;
        _managers[loanId] = manager;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function createLoan(Phase9Types.LoanCreationRequest calldata)
        external
        pure
        returns (address, address)
    {
        revert InvalidPhase9LoanConfiguration();
    }

    function loanAccount(bytes32 loanId) external view returns (address) {
        _reject();
        return _accounts[loanId];
    }

    function positionManager(bytes32 loanId) external view returns (address) {
        _reject();
        return _managers[loanId];
    }

    function creationRequest(bytes32)
        external
        pure
        returns (Phase9Types.LoanCreationRequest memory request)
    {
        return request;
    }

    function nextLoanNonce() external pure returns (uint64) {
        return 1;
    }

    function _reject() private view {
        if (shouldRevert) revert("FACTORY_READ_REVERTED");
    }
}

contract Phase9PayoffMockAccount is IPhase9LoanAccount {
    Phase9Types.LoanConfiguration private _configuration;
    Phase9Types.DebtState private _debt;
    bool public configurationReverts;
    bool public debtReverts;

    function setConfiguration(Phase9Types.LoanConfiguration memory configuration_) external {
        _configuration = configuration_;
    }

    function setDebt(Phase9Types.DebtState memory debt_) external {
        _debt = debt_;
    }

    function setReadReverts(bool configuration_, bool debt_) external {
        configurationReverts = configuration_;
        debtReverts = debt_;
    }

    function initialize(
        Phase9Types.LoanConfiguration calldata configuration_,
        Phase9Types.DebtState calldata debt_
    ) external {
        _configuration = configuration_;
        _debt = debt_;
    }

    function configuration() external view returns (Phase9Types.LoanConfiguration memory) {
        if (configurationReverts) revert("CONFIGURATION_READ_REVERTED");
        return _configuration;
    }

    function debtState() external view returns (Phase9Types.DebtState memory) {
        if (debtReverts) revert("DEBT_READ_REVERTED");
        return _debt;
    }

    function agreementVersionHash(uint64) external pure returns (bytes32) {
        return bytes32(0);
    }

    function operationProcessed(bytes32) external pure returns (bool) {
        return false;
    }

    function recordRefinancePayoff(bytes32, uint256, bytes32) external pure { }
    function activateReplacementLoan(bytes32, Phase9Types.DebtState calldata, bytes32)
        external
        pure { }
    function applyRestructuring(Phase9Types.LoanAmendment calldata, bytes32) external pure { }
    function recordCoveredLoss(bytes32, uint256, bytes32) external pure { }
    function recordRealizedLoss(bytes32, uint256, bytes32) external pure { }
    function recordWriteOff(bytes32, uint256, bytes32) external pure { }
    function recordPostWriteOffRecovery(bytes32, uint256, bytes32) external pure { }
    function closeLoan(bytes32) external pure { }
}

contract Phase9PayoffMockPositionManager is IPositionManagerV2 {
    mapping(bytes32 positionId => Phase9Types.Position position_) private _positions;
    bytes32[] private _ids;
    bool public shouldRevert;

    function setPositions(Phase9Types.Position[] memory positions_) external {
        for (uint256 i; i < _ids.length; ++i) {
            delete _positions[_ids[i]];
        }
        delete _ids;
        for (uint256 i; i < positions_.length; ++i) {
            _positions[positions_[i].positionId] = positions_[i];
            _ids.push(positions_[i].positionId);
        }
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function initialize(bytes32, address, address) external pure { }
    function registerTranche(Phase9Types.Tranche calldata) external pure { }
    function issuePosition(Phase9Types.Position calldata) external pure { }
    function transferPosition(bytes32, address) external pure { }
    function createSnapshot(Phase9Types.PositionRightSnapshot calldata) external pure { }
    function consumeVotingRight(bytes32, bytes32) external pure { }

    function tranche(bytes32) external pure returns (Phase9Types.Tranche memory tranche_) {
        return tranche_;
    }

    function trancheIds() external pure returns (bytes32[] memory ids) {
        return ids;
    }

    function position(bytes32 positionId)
        external
        view
        returns (Phase9Types.Position memory position_)
    {
        _reject();
        return _positions[positionId];
    }

    function positionIds() external view returns (bytes32[] memory) {
        _reject();
        return _ids;
    }

    function snapshot(bytes32)
        external
        pure
        returns (Phase9Types.PositionRightSnapshot memory snapshot_)
    {
        return snapshot_;
    }

    function votingRightConsumed(bytes32, bytes32) external pure returns (bool) {
        return false;
    }

    function positionOwnerAt(bytes32 positionId, uint64) external view returns (address) {
        _reject();
        return _positions[positionId].owner;
    }

    function positionVotingPowerAt(bytes32 positionId, uint64) external view returns (uint256) {
        _reject();
        return _positions[positionId].votingPower;
    }

    function positionClaimAt(bytes32 positionId, uint64) external view returns (uint256) {
        _reject();
        return _positions[positionId].claim;
    }

    function totalVotingPowerAt(uint64) external view returns (uint256 total) {
        _reject();
        for (uint256 i; i < _ids.length; ++i) {
            total += _positions[_ids[i]].votingPower;
        }
    }

    function _reject() private view {
        if (shouldRevert) revert("POSITION_READ_REVERTED");
    }
}

contract Phase9PayoffMockPolicySource is IPhase9PayoffQuotePolicySource {
    struct Policy {
        bytes32 policyHash;
        bytes32 boundPolicySetHash;
        address feePenaltyBeneficiary;
        bytes32 settlementAssetId;
        address settlementToken;
        uint64 maximumValidity;
        bool active;
    }

    mapping(bytes32 loanId => mapping(address account => Policy policy)) private _policies;
    bool public shouldRevert;

    function setPolicy(bytes32 loanId, address account, Policy memory policy) external {
        _policies[loanId][account] = policy;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function resolvePayoffQuotePolicy(bytes32 loanId, address loanAccount)
        external
        view
        returns (bytes32, bytes32, address, bytes32, address, uint64, bool)
    {
        if (shouldRevert) revert("POLICY_READ_REVERTED");
        Policy memory policy = _policies[loanId][loanAccount];
        return (
            policy.policyHash,
            policy.boundPolicySetHash,
            policy.feePenaltyBeneficiary,
            policy.settlementAssetId,
            policy.settlementToken,
            policy.maximumValidity,
            policy.active
        );
    }
}

contract Phase9PayoffMalformedPolicySource {
    uint8 public mode;

    function setMode(uint8 mode_) external {
        mode = mode_;
    }

    fallback() external {
        uint8 mode_ = mode;
        if (mode_ != 0) {
            bytes32[7] memory words;
            words[0] = bytes32(uint256(1));
            words[1] = bytes32(uint256(2));
            words[2] = bytes32(uint256(uint160(address(0xFEE))));
            words[3] = bytes32(uint256(3));
            words[4] = bytes32(uint256(uint160(address(0xCAFE))));
            words[5] = bytes32(uint256(3_600));
            words[6] = bytes32(uint256(1));
            if (mode_ == 1) words[2] = bytes32(uint256(1) << 160);
            else if (mode_ == 2) words[4] = bytes32(uint256(1) << 160);
            else if (mode_ == 3) words[5] = bytes32(uint256(type(uint64).max) + 1);
            else if (mode_ == 4) words[6] = bytes32(uint256(2));
            assembly ("memory-safe") {
                return(words, 0xe0)
            }
        }
        assembly ("memory-safe") {
            mstore(0, 1)
            return(0, 1)
        }
    }
}

contract Phase9PayoffCoordinatorProxy {
    IPayoffQuoteEngineV2 public engine;

    function bind(IPayoffQuoteEngineV2 engine_) external {
        require(address(engine) == address(0), "already bound");
        engine = engine_;
    }

    function issue(bytes32 loanId, uint64 validUntil) external payable returns (bytes32) {
        bytes memory result =
            _invoke(abi.encodeCall(IPayoffQuoteEngineV2.issueQuote, (loanId, validUntil)));
        return abi.decode(result, (bytes32));
    }

    function consume(
        bytes32 quoteId,
        bytes32 refinanceId,
        uint64 expectedDebtStateVersion,
        bytes32 sourceEventId
    ) external payable returns (IPayoffQuoteEngineV2.PayoffQuoteV2 memory) {
        bytes memory result = _invoke(
            abi.encodeCall(
                IPayoffQuoteEngineV2.consumeQuote,
                (quoteId, refinanceId, expectedDebtStateVersion, sourceEventId)
            )
        );
        return abi.decode(result, (IPayoffQuoteEngineV2.PayoffQuoteV2));
    }

    function invalidate(bytes32 quoteId, bytes32 sourceEventId) external payable {
        _invoke(abi.encodeCall(IPayoffQuoteEngineV2.invalidateQuote, (quoteId, sourceEventId)));
    }

    function _invoke(bytes memory data) private returns (bytes memory result) {
        bool success;
        (success, result) = address(engine).call{ value: msg.value }(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }
}

contract Phase9PayoffUnauthorizedCaller {
    function invoke(address target, bytes calldata data) external payable returns (bytes memory) {
        (bool success, bytes memory result) = target.call{ value: msg.value }(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
        return result;
    }
}

contract Phase9PayoffWrongRuntimeToken is ERC20 {
    uint256 public calls;

    constructor(address allocator) ERC20("Unified Phase 9 Local Synthetic Unit", "P9UNIT") {
        _mint(allocator, 1_000_000_000_000_000);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    fallback() external {
        ++calls;
    }
}

library Phase9PayoffReference {
    struct QuoteIdentityFacts {
        bytes32 loanId;
        address loanAccount;
        bytes32 policyHash;
        uint64 debtStateVersion;
        uint256 principal;
        uint256 accruedInterest;
        uint256 fees;
        uint256 penalties;
        uint256 credits;
        bytes32 componentBeneficiaryHash;
        uint256 netPayoff;
        bytes32 settlementAssetId;
        address settlementToken;
        bytes32 settlementRouteHash;
        uint64 issuedAt;
        uint64 validUntil;
        uint64 quoteNonce;
    }

    function policyHash(
        address engine,
        address policySource,
        bytes32 loanId,
        address loanAccount,
        bytes32 policySetHash,
        address feePenaltyBeneficiary,
        bytes32 settlementAssetId,
        address settlementToken,
        uint64 maximumValidity
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_POLICY_V1",
                block.chainid,
                engine,
                policySource,
                loanId,
                loanAccount,
                policySetHash,
                feePenaltyBeneficiary,
                settlementAssetId,
                settlementToken,
                maximumValidity
            )
        );
    }

    function components(
        uint256 principal,
        uint256 interest,
        uint256 fees,
        uint256 penalties,
        uint256 credits,
        address lender,
        address feeBeneficiary
    ) internal pure returns (IPayoffQuoteEngineV2.PayoffComponentV2[] memory values) {
        values = new IPayoffQuoteEngineV2.PayoffComponentV2[](5);
        values[0] = IPayoffQuoteEngineV2.PayoffComponentV2(
            IPayoffQuoteEngineV2.ComponentKind.PRINCIPAL, principal, lender, "PRINCIPAL"
        );
        values[1] = IPayoffQuoteEngineV2.PayoffComponentV2(
            IPayoffQuoteEngineV2.ComponentKind.ACCRUED_INTEREST,
            interest,
            lender,
            "ACCRUED_INTEREST"
        );
        values[2] = IPayoffQuoteEngineV2.PayoffComponentV2(
            IPayoffQuoteEngineV2.ComponentKind.FEE, fees, feeBeneficiary, "FEE"
        );
        values[3] = IPayoffQuoteEngineV2.PayoffComponentV2(
            IPayoffQuoteEngineV2.ComponentKind.PENALTY, penalties, feeBeneficiary, "PENALTY"
        );
        values[4] = IPayoffQuoteEngineV2.PayoffComponentV2(
            IPayoffQuoteEngineV2.ComponentKind.CREDIT, credits, feeBeneficiary, "FEE_PENALTY_CREDIT"
        );
    }

    function componentHash(IPayoffQuoteEngineV2.PayoffComponentV2[] memory values)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode("UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1", values));
    }

    function routeHash(
        address engine,
        address coordinator,
        bytes32 loanId,
        address loanAccount,
        bytes32 settlementAssetId,
        address settlementToken,
        address lender,
        address feeBeneficiary,
        bytes32 policyHash_
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1",
                block.chainid,
                engine,
                coordinator,
                loanId,
                loanAccount,
                settlementAssetId,
                settlementToken,
                lender,
                feeBeneficiary,
                policyHash_
            )
        );
    }

    function quoteId(IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_)
        internal
        view
        returns (bytes32)
    {
        QuoteIdentityFacts memory identity = _identity(quote_);
        return
            keccak256(abi.encode("UNIFIED_PAYOFF_QUOTE_V1", address(this), block.chainid, identity));
    }

    function quoteIdFor(address engine, IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_)
        internal
        view
        returns (bytes32)
    {
        QuoteIdentityFacts memory identity = _identity(quote_);
        return keccak256(abi.encode("UNIFIED_PAYOFF_QUOTE_V1", engine, block.chainid, identity));
    }

    function _identity(IPayoffQuoteEngineV2.PayoffQuoteV2 memory quote_)
        private
        pure
        returns (QuoteIdentityFacts memory)
    {
        return QuoteIdentityFacts({
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
}
