// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IUnifiedToken } from "../src/interfaces/IUnifiedToken.sol";
import { BridgeExposurePolicy } from "../src/crosschain/BridgeExposurePolicy.sol";
import { CrossChainTypes } from "../src/crosschain/CrossChainTypes.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";

interface Phase8FuzzVm {
    function warp(uint256 timestamp) external;
}

contract Phase8FuzzUFT is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000 ether;

    constructor() ERC20("Phase 8 Fuzz UFT", "P8FUFT") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract Phase8CrossChainFuzzTest {
    Phase8FuzzVm private constant vm =
        Phase8FuzzVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 private constant NOW = 1_900_000_000;
    RoleManager private roles;
    BridgeExposurePolicy private exposure;
    bytes32 private routePolicyHash;

    function setUp() public {
        vm.warp(NOW);
        roles = new RoleManager(address(0xA11), address(this));
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
        Phase8FuzzUFT token = new Phase8FuzzUFT();
        exposure = new BridgeExposurePolicy(roles, IUnifiedToken(address(token)));
        routePolicyHash = keccak256("FUZZ_ROUTE");
        bytes32 policyHash = exposure.registerPolicy(
            BridgeExposurePolicy.ExposureConfig({
                circulatingSupplyReference: token.MAX_SUPPLY(),
                circulatingSupplyEvidenceHash: keccak256("FUZZ_SUPPLY_EVIDENCE"),
                routeAbsoluteCap: 50 ether,
                chainAbsoluteCap: 60 ether,
                adapterAbsoluteCap: 70 ether,
                aggregateAbsoluteCap: 80 ether,
                routePercentageCeilingBps: 500,
                aggregatePercentageCeilingBps: 1_500,
                activationDelay: 0,
                activeFrom: NOW
            })
        );
        exposure.activateForRoute(routePolicyHash, policyHash);
    }

    function testFuzz_CanonicalLockPayloadRoundTrips(
        bytes32 lockId,
        bytes32 loanId,
        address recipient,
        uint128 rawAmount
    ) public pure {
        CrossChainTypes.CanonicalUftLockPayload memory original =
            CrossChainTypes.CanonicalUftLockPayload({
                lockId: lockId,
                loanId: loanId,
                canonicalToken: address(0x1111),
                homeBridgeHub: address(0x2222),
                wrappedToken: address(0x3333),
                destinationRecipient: recipient,
                amount: uint256(rawAmount)
            });
        bytes memory encoded = abi.encode(original);
        CrossChainTypes.CanonicalUftLockPayload memory decoded =
            abi.decode(encoded, (CrossChainTypes.CanonicalUftLockPayload));

        require(encoded.length == 224, "non-canonical ABI length");
        require(decoded.lockId == original.lockId, "lock id");
        require(decoded.loanId == original.loanId, "loan id");
        require(decoded.canonicalToken == original.canonicalToken, "canonical token");
        require(decoded.homeBridgeHub == original.homeBridgeHub, "hub");
        require(decoded.wrappedToken == original.wrappedToken, "wrapped token");
        require(decoded.destinationRecipient == original.destinationRecipient, "recipient");
        require(decoded.amount == original.amount, "amount");
    }

    function testFuzz_MessageIdCommitsToSecurityFields(bytes32 changed, uint8 fieldSeed)
        public
        pure
    {
        CrossChainTypes.MessageEnvelope memory original = _envelope();
        bytes32 originalId = CrossChainTypes.messageId(original);
        CrossChainTypes.MessageEnvelope memory mutated = _envelope();
        bytes32 replacement = changed == bytes32(uint256(1)) ? bytes32(uint256(2)) : changed;

        uint8 field = fieldSeed % 9;
        if (field == 0) mutated.protocolId = replacement;
        else if (field == 1) mutated.laneId = replacement;
        else if (field == 2) mutated.aggregateId = replacement;
        else if (field == 3) mutated.payloadHash = replacement;
        else if (field == 4) mutated.routePolicyHash = replacement;
        else if (field == 5) mutated.adapterSetPolicyHash = replacement;
        else if (field == 6) mutated.sourceFinalityPolicyHash = replacement;
        else if (field == 7) mutated.destinationFinalityPolicyHash = replacement;
        else mutated.correlationId = replacement;

        require(CrossChainTypes.messageId(mutated) != originalId, "field omitted from id");
    }

    function testFuzz_ObserverCommitmentBindsHeaderEvidence(
        bytes32 changedBlockHash,
        uint64 changedHead
    ) public pure {
        CrossChainTypes.SourceEventProof memory original = _proof();
        bytes32 originalCommitment = CrossChainTypes.observerHeaderCommitment(original);
        CrossChainTypes.SourceEventProof memory mutated = _proof();
        mutated.sourceBlockHash = changedBlockHash == original.sourceBlockHash
            ? bytes32(uint256(original.sourceBlockHash) + 1)
            : changedBlockHash;
        mutated.finalityHeadNumber =
            changedHead == original.finalityHeadNumber ? changedHead + 1 : changedHead;
        require(
            CrossChainTypes.observerHeaderCommitment(mutated) != originalCommitment,
            "observer evidence not bound"
        );
    }

    function testFuzz_ExposureRejectsEveryExceededDimension(
        uint96 rawRoute,
        uint96 rawChain,
        uint96 rawAdapter,
        uint96 rawAggregate
    ) public view {
        uint256 routeExposure = uint256(rawRoute) % (101 ether);
        uint256 chainExposure = uint256(rawChain) % (101 ether);
        uint256 adapterExposure = uint256(rawAdapter) % (101 ether);
        uint256 aggregateExposure = uint256(rawAggregate) % (101 ether);
        bool expected = routeExposure <= 50 ether && chainExposure <= 60 ether
            && adapterExposure <= 70 ether && aggregateExposure <= 80 ether;
        (bool accepted,) = address(exposure)
            .staticcall(
                abi.encodeCall(
                    BridgeExposurePolicy.validateLock,
                    (
                        routePolicyHash,
                        routeExposure,
                        chainExposure,
                        adapterExposure,
                        aggregateExposure
                    )
                )
            );
        require(accepted == expected, "cap dimension mismatch");
    }

    function testFuzz_ActionBitsAreOrdinalAndDisjoint(uint8 firstSeed, uint8 secondSeed)
        public
        pure
    {
        uint8 first = (firstSeed % 16) + 1;
        uint8 second = (secondSeed % 16) + 1;
        CrossChainTypes.CrossChainActionType firstAction =
            CrossChainTypes.CrossChainActionType(first);
        CrossChainTypes.CrossChainActionType secondAction =
            CrossChainTypes.CrossChainActionType(second);
        uint32 firstBit = CrossChainTypes.actionBit(firstAction);
        uint32 secondBit = CrossChainTypes.actionBit(secondAction);
        require(firstBit == uint32(1) << first, "ordinal bit mismatch");
        if (first == second) require(firstBit == secondBit, "same action bit");
        else require(firstBit & secondBit == 0, "action bits overlap");
    }

    function _envelope() private pure returns (CrossChainTypes.MessageEnvelope memory envelope) {
        envelope = CrossChainTypes.MessageEnvelope({
            schemaVersion: 1,
            messageId: bytes32(0),
            protocolId: bytes32(uint256(1)),
            sourceChainId: 31_337,
            sourceCoordinator: address(0x1111),
            sourceComponent: address(0x2222),
            destinationChainId: 31_338,
            destinationCoordinator: address(0x3333),
            destinationComponent: address(0x4444),
            laneId: bytes32(uint256(1)),
            sourceNonce: 1,
            aggregateId: bytes32(uint256(1)),
            actionType: CrossChainTypes.CrossChainActionType.CANONICAL_UFT_LOCKED_V1,
            payloadHash: bytes32(uint256(1)),
            createdAt: NOW,
            expiresAt: NOW + 1 hours,
            routePolicyHash: bytes32(uint256(1)),
            adapterSetPolicyHash: bytes32(uint256(1)),
            sourceFinalityPolicyHash: bytes32(uint256(1)),
            destinationFinalityPolicyHash: bytes32(uint256(1)),
            correlationId: bytes32(uint256(1)),
            causationMessageId: bytes32(0),
            supersededMessageId: bytes32(0)
        });
    }

    function _proof() private pure returns (CrossChainTypes.SourceEventProof memory proof) {
        proof = CrossChainTypes.SourceEventProof({
            sourceBlockHash: bytes32(uint256(1)),
            sourceBlockNumber: 10,
            sourceBlockTimestamp: NOW,
            transactionHash: bytes32(uint256(2)),
            transactionIndex: 3,
            receiptRoot: bytes32(uint256(4)),
            receiptProofHash: bytes32(uint256(5)),
            logIndex: 6,
            eventHash: bytes32(uint256(7)),
            finalityHeadHash: bytes32(uint256(8)),
            finalityHeadNumber: 20,
            requiredDepth: 10,
            headerAuthorityHash: bytes32(uint256(9)),
            observerSignedHeaderCommitment: bytes32(0),
            observerSignature: hex"0102",
            finalityPolicyHash: bytes32(uint256(10))
        });
    }
}
