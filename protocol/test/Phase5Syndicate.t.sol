// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { AssetRegistry } from "../src/kernel/AssetRegistry.sol";
import { EmergencyController } from "../src/kernel/EmergencyController.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { PolicyRegistry } from "../src/kernel/PolicyRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { ProtocolTypes } from "../src/kernel/ProtocolTypes.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { PositionManager } from "../src/syndicate/PositionManager.sol";
import { SyndicateFactory } from "../src/syndicate/SyndicateFactory.sol";
import { SyndicateTypes } from "../src/syndicate/SyndicateTypes.sol";
import { SyndicateVault } from "../src/syndicate/SyndicateVault.sol";

interface SyndicateVm {
    function prank(address sender) external;
    function roll(uint256 blockNumber) external;
    function warp(uint256 timestamp) external;
}

contract SyndicateTestToken is ERC20 {
    constructor() ERC20("Syndicate Settlement", "SSET") { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract SyndicateTestPolicy is IERC165 {
    bytes4 private immutable _interfaceId;

    constructor(bytes4 interfaceId_) {
        _interfaceId = interfaceId_;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == _interfaceId;
    }
}

contract Phase5SyndicateTest {
    SyndicateVm private constant vm =
        SyndicateVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 private constant NOW = 1_800_000_000;
    bytes32 private constant SETTLEMENT_ID = keccak256("ASSET:SYNDICATE");
    bytes32 private constant SENIOR = keccak256("TRANCHE:SENIOR");
    bytes32 private constant JUNIOR = keccak256("TRANCHE:JUNIOR");
    bytes4 private constant POLICY_INTERFACE = 0x51f5a001;

    address private borrower = address(0xB0B);
    address private seniorLender = address(0x5E01);
    address private juniorLender = address(0x5E02);
    address private buyer = address(0xB0A7);
    address private pledgee = address(0xC011);

    RoleManager private roles;
    AssetRegistry private assets;
    PolicyRegistry private policies;
    EmergencyController private emergency;
    LoanRegistry private loans;
    SyndicateTestToken private token;
    SyndicateFactory private factory;
    ProtocolTypes.PolicyRef[] private policySet;

    function setUp() public {
        vm.warp(NOW);
        roles = new RoleManager(address(0xA11CE), address(this));
        roles.grantRole(ProtocolRoles.ASSET_REGISTRAR_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.POLICY_REGISTRAR_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.PAUSER_ROLE, address(this), type(uint64).max);
        assets = new AssetRegistry(roles);
        policies = new PolicyRegistry(roles);
        emergency = new EmergencyController(roles);
        loans = new LoanRegistry(roles);
        token = new SyndicateTestToken();
        assets.registerAsset(SETTLEMENT_ID, address(token), 18, keccak256("SSET"));

        SyndicateTestPolicy policy = new SyndicateTestPolicy(POLICY_INTERFACE);
        ProtocolTypes.PolicyRef memory policyRef = ProtocolTypes.PolicyRef({
            policyId: keccak256("SYNDICATE_POLICY"),
            implementation: address(policy),
            major: 1,
            minor: 0,
            patch: 0,
            interfaceId: POLICY_INTERFACE,
            configurationSchemaHash: keccak256("SYNDICATE_POLICY_SCHEMA")
        });
        policies.registerPolicy(policyRef, _codeHash(address(policy)));
        policySet.push(policyRef);

        PositionManager positionImplementation = new PositionManager();
        SyndicateVault vaultImplementation = new SyndicateVault();
        factory = new SyndicateFactory(
            IRoleManager(address(roles)),
            loans,
            assets,
            policies,
            emergency,
            address(vaultImplementation),
            address(positionImplementation)
        );
        roles.grantRole(ProtocolRoles.LOAN_FACTORY_ROLE, address(factory), type(uint64).max);
        token.mint(seniorLender, 1_000 ether);
        token.mint(juniorLender, 1_000 ether);
    }

    function testFundingActivationAndSeniorFirstDistribution() public {
        (SyndicateVault vault, PositionManager manager, bytes32 loanId) =
            _createRound(keccak256("ROUND:SUCCESS"), 60 ether, 100 ether);
        require(factory.predictVault(loanId) == address(vault), "vault prediction mismatch");
        require(
            factory.predictPositionManager(loanId) == address(manager),
            "manager prediction mismatch"
        );
        require(loans.loanAccount(loanId) == address(vault), "canonical loan mismatch");
        (bytes32 seniorPosition, bytes32 juniorPosition) = _fund(vault, 60 ether, 40 ether);
        vault.finalize(keccak256("ACTIVATION_JOURNAL"));

        require(token.balanceOf(borrower) == 100 ether, "borrower disbursement mismatch");
        require(vault.outstandingPrincipal() == 100 ether, "vault debt mismatch");
        require(manager.totalIssuedShares() == 100 ether, "issued rights mismatch");
        require(manager.totalOutstandingPrincipal() == 100 ether, "tranche debt mismatch");
        require(manager.currentVotes(seniorLender) == 60 ether, "senior votes mismatch");
        require(manager.currentVotes(juniorLender) == 20 ether, "junior votes mismatch");

        vm.prank(borrower);
        token.approve(address(vault), type(uint256).max);
        vm.prank(borrower);
        vault.repay(keccak256("PAYMENT:70"), 70 ether, keccak256("JOURNAL:70"));
        require(manager.accruedDistribution(seniorPosition) == 60 ether, "senior unpaid");
        require(manager.accruedDistribution(juniorPosition) == 10 ether, "junior waterfall");
        require(manager.tranche(SENIOR).outstandingPrincipal == 0, "senior not retired");
        require(manager.tranche(JUNIOR).outstandingPrincipal == 30 ether, "junior mismatch");

        vm.prank(seniorLender);
        manager.withdrawDistribution(seniorPosition);
        vm.prank(juniorLender);
        manager.withdrawDistribution(juniorPosition);
        require(token.balanceOf(seniorLender) == 1_000 ether, "senior receipt mismatch");
        require(token.balanceOf(juniorLender) == 970 ether, "junior receipt mismatch");
    }

    function testFuzzPaymentWaterfallConservesPrincipal(uint96 rawAmount) public {
        (SyndicateVault vault, PositionManager manager,) =
            _createRound(keccak256("ROUND:FUZZ"), 60 ether, 100 ether);
        (bytes32 seniorPosition, bytes32 juniorPosition) = _fund(vault, 60 ether, 40 ether);
        vault.finalize(keccak256("ACTIVATION_JOURNAL"));
        uint256 amount = (uint256(rawAmount) % (100 ether)) + 1;

        vm.prank(borrower);
        token.approve(address(vault), type(uint256).max);
        vm.prank(borrower);
        vault.repay(
            keccak256(abi.encode("PAYMENT:FUZZ", amount)), amount, keccak256("JOURNAL:FUZZ")
        );

        uint256 seniorAllocation = amount > 60 ether ? 60 ether : amount;
        uint256 juniorAllocation = amount - seniorAllocation;
        require(
            manager.accruedDistribution(seniorPosition) == seniorAllocation, "fuzz senior mismatch"
        );
        require(
            manager.accruedDistribution(juniorPosition) == juniorAllocation, "fuzz junior mismatch"
        );
        require(
            manager.totalOutstandingPrincipal() + amount == 100 ether,
            "fuzz principal not conserved"
        );
    }

    function testTransferCutsOffAccruedRightsAndVotingAtOneBlock() public {
        (SyndicateVault vault, PositionManager manager,) =
            _createRound(keccak256("ROUND:TRANSFER"), 60 ether, 100 ether);
        (bytes32 seniorPosition, bytes32 juniorPosition) = _fund(vault, 60 ether, 40 ether);
        vault.finalize(keccak256("ACTIVATION_JOURNAL"));
        uint64 activationBlock = uint64(block.number);

        vm.prank(borrower);
        token.approve(address(vault), type(uint256).max);
        vm.prank(borrower);
        vault.repay(keccak256("PAYMENT:20"), 20 ether, keccak256("JOURNAL:20"));
        require(manager.claimUnits(seniorPosition) == 40 ether, "claim snapshot mismatch");

        vm.roll(block.number + 1);
        uint64 transferBlock = uint64(block.number);
        vm.prank(seniorLender);
        manager.transferPosition(seniorPosition, buyer, keccak256("TRANSFER_FINALITY"));
        require(manager.withdrawable(seniorLender) == 20 ether, "seller accrual moved");
        require(manager.currentVotes(seniorLender) == 0, "seller retained votes");
        require(manager.currentVotes(buyer) == 60 ether, "buyer votes missing");

        vm.roll(block.number + 1);
        require(
            manager.getPastVotes(seniorLender, activationBlock) == 60 ether,
            "historical seller votes lost"
        );
        require(
            manager.getPastVotes(seniorLender, transferBlock) == 0, "post-transfer votes duplicated"
        );

        vm.prank(borrower);
        vault.repay(keccak256("PAYMENT:80"), 80 ether, keccak256("JOURNAL:80"));
        require(manager.accruedDistribution(seniorPosition) == 40 ether, "buyer accrual mismatch");
        require(manager.accruedDistribution(juniorPosition) == 40 ether, "junior accrual mismatch");
        vm.prank(buyer);
        manager.withdrawDistribution(seniorPosition);
        vm.prank(seniorLender);
        manager.withdrawAvailable();
        require(token.balanceOf(buyer) == 40 ether, "buyer did not receive future rights");
        require(token.balanceOf(seniorLender) == 960 ether, "seller cutoff mismatch");
    }

    function testFundingBelowThresholdRefundsExactCommitment() public {
        (SyndicateVault vault,, bytes32 loanId) =
            _createRound(keccak256("ROUND:FAILED"), 80 ether, 100 ether);
        vm.prank(seniorLender);
        token.approve(address(vault), type(uint256).max);
        vm.prank(seniorLender);
        vault.commit(keccak256("COMMITMENT:FAILED"), SENIOR, 50 ether);
        vm.warp(NOW + 1 days + 1);
        vault.finalize(keccak256("FAILED_JOURNAL"));
        require(
            vault.roundStatus() == SyndicateTypes.RoundStatus.FAILED, "failed threshold activated"
        );
        require(loans.isTerminal(loanId), "failed loan not terminal");
        vault.refund(keccak256("COMMITMENT:FAILED"));
        require(token.balanceOf(seniorLender) == 1_000 ether, "refund not exact");
    }

    function testEmergencyPauseBlocksCreationWithoutRegistryState() public {
        bytes32 roundId = keccak256("ROUND:PAUSED");
        (
            SyndicateTypes.FundingRoundTerms memory terms,
            SyndicateTypes.TrancheConfiguration[] memory tranches
        ) = _roundConfiguration(roundId, 60 ether, 100 ether);
        emergency.pauseCapability(
            factory.CAPABILITY_NEW_LOANS(),
            uint64(block.timestamp + 1 days),
            keccak256("SYNDICATE_INCIDENT")
        );
        vm.prank(borrower);
        (bool created,) = address(factory)
            .call(abi.encodeCall(factory.createSyndicate, (terms, tranches, policySet)));
        require(!created, "paused syndicate creation succeeded");
        require(!loans.exists(terms.loanId), "paused creation registered a loan");
    }

    function testSplitMergePledgeAndTransferConserveShares() public {
        (SyndicateVault vault, PositionManager manager,) =
            _createRound(keccak256("ROUND:POSITIONS"), 60 ether, 100 ether);
        (bytes32 seniorPosition, bytes32 juniorPosition) = _fund(vault, 60 ether, 40 ether);
        vault.finalize(keccak256("ACTIVATION_JOURNAL"));
        uint256 votesBefore = manager.currentVotes(seniorLender);
        bytes32 splitPosition = keccak256("POSITION:SPLIT");
        vm.prank(seniorLender);
        (bool splitTransferred,) = address(manager)
            .call(
                abi.encodeCall(
                    manager.splitPosition, (seniorPosition, splitPosition, 20 ether, buyer)
                )
            );
        require(!splitTransferred, "split bypassed transfer evidence");
        vm.prank(seniorLender);
        manager.splitPosition(seniorPosition, splitPosition, 20 ether, seniorLender);
        require(manager.position(seniorPosition).shares == 40 ether, "split source mismatch");
        require(manager.position(splitPosition).shares == 20 ether, "split target mismatch");
        require(manager.totalIssuedShares() == 100 ether, "split created rights");
        require(
            manager.currentVotes(seniorLender) + manager.currentVotes(buyer) == votesBefore,
            "split changed voting power"
        );

        vm.prank(seniorLender);
        manager.pledgePosition(splitPosition, pledgee, keccak256("PLEDGE"));
        vm.prank(seniorLender);
        (bool transferred,) = address(manager)
            .call(
                abi.encodeCall(
                    manager.transferPosition, (splitPosition, buyer, keccak256("INVALID_TRANSFER"))
                )
            );
        require(!transferred, "pledged position transferred");
        vm.prank(pledgee);
        manager.releasePledge(splitPosition);
        vm.prank(seniorLender);
        manager.transferPosition(splitPosition, buyer, keccak256("TRANSFER:OUT"));
        vm.prank(buyer);
        manager.transferPosition(splitPosition, seniorLender, keccak256("TRANSFER:BACK"));
        vm.prank(seniorLender);
        manager.mergePositions(seniorPosition, splitPosition);
        require(manager.position(seniorPosition).shares == 60 ether, "merge mismatch");
        require(manager.totalIssuedShares() == 100 ether, "merge changed total rights");
        require(manager.currentVotes(seniorLender) == votesBefore, "merge changed voting power");

        vm.prank(juniorLender);
        (bool juniorTransferred,) = address(manager)
            .call(
                abi.encodeCall(
                    manager.transferPosition, (juniorPosition, buyer, keccak256("NON_TRANSFERABLE"))
                )
            );
        require(!juniorTransferred, "restricted tranche transferred");
    }

    function testProRataRemainderUsesFixedResidualPosition() public {
        (SyndicateVault vault, PositionManager manager,) =
            _createRound(keccak256("ROUND:RESIDUAL"), 60 ether, 100 ether);
        token.mint(buyer, 30 ether);
        vm.prank(seniorLender);
        token.approve(address(vault), type(uint256).max);
        vm.prank(buyer);
        token.approve(address(vault), type(uint256).max);
        vm.prank(juniorLender);
        token.approve(address(vault), type(uint256).max);

        vm.prank(seniorLender);
        bytes32 residualPosition =
            vault.commit(keccak256("COMMITMENT:SENIOR:FIRST"), SENIOR, 30 ether);
        vm.prank(buyer);
        bytes32 secondSenior = vault.commit(keccak256("COMMITMENT:SENIOR:SECOND"), SENIOR, 30 ether);
        vm.prank(juniorLender);
        vault.commit(keccak256("COMMITMENT:JUNIOR:RESIDUAL"), JUNIOR, 40 ether);
        vault.finalize(keccak256("ACTIVATION_JOURNAL"));

        vm.prank(borrower);
        token.approve(address(vault), type(uint256).max);
        vm.prank(borrower);
        vault.repay(keccak256("PAYMENT:ONE_WEI"), 1, keccak256("JOURNAL:ONE_WEI"));
        require(manager.accruedDistribution(residualPosition) == 1, "residual not allocated");
        require(manager.accruedDistribution(secondSenior) == 0, "residual changed owner");
        require(manager.claimUnits(residualPosition) == 30 ether, "residual claim mismatch");
        require(
            manager.claimUnits(secondSenior) == 30 ether - 1, "secondary claim rounding mismatch"
        );
    }

    function testJuniorFirstLossPreviewIsDeterministic() public {
        (SyndicateVault vault, PositionManager manager,) =
            _createRound(keccak256("ROUND:LOSS"), 60 ether, 100 ether);
        _fund(vault, 60 ether, 40 ether);
        vault.finalize(keccak256("ACTIVATION_JOURNAL"));
        (bytes32[] memory ids, uint256[] memory losses) = manager.previewLoss(70 ether);
        require(ids[0] == SENIOR && ids[1] == JUNIOR, "tranche order changed");
        require(losses[0] == 30 ether, "senior loss mismatch");
        require(losses[1] == 40 ether, "junior loss mismatch");
    }

    function testFreezeRepaymentAndRedemptionPreserveRights() public {
        (SyndicateVault vault, PositionManager manager,) =
            _createRound(keccak256("ROUND:FREEZE"), 60 ether, 100 ether);
        (bytes32 seniorPosition, bytes32 juniorPosition) = _fund(vault, 60 ether, 40 ether);
        vault.finalize(keccak256("ACTIVATION_JOURNAL"));
        manager.setFrozen(seniorPosition, true, keccak256("RISK_FREEZE"));
        vm.prank(seniorLender);
        (bool transferred,) = address(manager)
            .call(
                abi.encodeCall(
                    manager.transferPosition, (seniorPosition, buyer, keccak256("FROZEN_TRANSFER"))
                )
            );
        require(!transferred, "frozen position transferred");
        manager.setFrozen(seniorPosition, false, keccak256("RISK_CLEAR"));

        vm.prank(borrower);
        token.approve(address(vault), type(uint256).max);
        vm.prank(borrower);
        vault.repay(keccak256("PAYMENT:FINAL"), 100 ether, keccak256("JOURNAL:FINAL"));
        vm.prank(seniorLender);
        manager.redeemPosition(seniorPosition);
        vm.prank(juniorLender);
        manager.redeemPosition(juniorPosition);
        require(
            manager.position(seniorPosition).status == SyndicateTypes.PositionStatus.REDEEMED,
            "senior not redeemed"
        );
        require(manager.currentVotes(seniorLender) == 0, "redeemed votes remained");
        require(manager.currentVotes(juniorLender) == 0, "junior votes remained");
        vm.prank(seniorLender);
        manager.withdrawAvailable();
        vm.prank(juniorLender);
        manager.withdrawAvailable();
        require(token.balanceOf(seniorLender) == 1_000 ether, "senior redemption mismatch");
        require(token.balanceOf(juniorLender) == 1_000 ether, "junior redemption mismatch");
    }

    function testRoundCancellationRefundAndCapacityCannotOverfund() public {
        (SyndicateVault vault, PositionManager manager,) =
            _createRound(keccak256("ROUND:WITHDRAW"), 60 ether, 100 ether);
        vm.prank(seniorLender);
        token.approve(address(vault), type(uint256).max);
        vm.prank(seniorLender);
        (bool overfunded,) = address(vault)
            .call(abi.encodeCall(vault.commit, (keccak256("TOO_LARGE"), SENIOR, 61 ether)));
        require(!overfunded, "tranche capacity exceeded");

        bytes32 commitmentId = keccak256("COMMITMENT:WITHDRAW");
        vm.prank(seniorLender);
        vault.commit(commitmentId, SENIOR, 60 ether);
        vm.prank(borrower);
        vault.cancelRound(keccak256("BORROWER_CANCELLED"));
        vault.refund(commitmentId);
        (bool duplicateRefund,) = address(vault).call(abi.encodeCall(vault.refund, (commitmentId)));
        require(!duplicateRefund, "commitment refunded twice");
        require(manager.totalIssuedShares() == 0, "refunded position rights remained");
        require(token.balanceOf(seniorLender) == 1_000 ether, "cancellation refund not exact");
    }

    function _createRound(bytes32 roundId, uint256 minimum, uint256 target)
        private
        returns (SyndicateVault vault, PositionManager manager, bytes32 loanId)
    {
        (
            SyndicateTypes.FundingRoundTerms memory terms,
            SyndicateTypes.TrancheConfiguration[] memory tranches
        ) = _roundConfiguration(roundId, minimum, target);
        loanId = terms.loanId;
        vm.prank(borrower);
        (address vaultAddress, address managerAddress) =
            factory.createSyndicate(terms, tranches, policySet);
        vault = SyndicateVault(vaultAddress);
        manager = PositionManager(managerAddress);
    }

    function _roundConfiguration(bytes32 roundId, uint256 minimum, uint256 target)
        private
        view
        returns (
            SyndicateTypes.FundingRoundTerms memory terms,
            SyndicateTypes.TrancheConfiguration[] memory tranches
        )
    {
        terms = SyndicateTypes.FundingRoundTerms({
            loanId: factory.calculateLoanId(roundId, borrower),
            roundId: roundId,
            agreementHash: keccak256(abi.encode("AGREEMENT", roundId)),
            policySetHash: factory.policySetHash(policySet),
            metadataHash: keccak256(abi.encode("METADATA", roundId)),
            borrower: borrower,
            settlementAssetId: SETTLEMENT_ID,
            minimumFunding: minimum,
            targetFunding: target,
            maximumFunding: 120 ether,
            opensAt: uint64(block.timestamp),
            closesAt: uint64(block.timestamp + 1 days),
            finalMaturityTime: uint64(block.timestamp + 365 days),
            gracePeriod: 7 days,
            protocolVersion: factory.IMPLEMENTATION_VERSION()
        });
        tranches = new SyndicateTypes.TrancheConfiguration[](2);
        tranches[0] = SyndicateTypes.TrancheConfiguration({
            trancheId: SENIOR,
            nameHash: keccak256("Senior"),
            seniorityRank: 1,
            targetSize: 60 ether,
            couponBps: 0,
            votingBps: 10_000,
            transferPolicy: SyndicateTypes.TransferPolicy.FREELY_TRANSFERABLE
        });
        tranches[1] = SyndicateTypes.TrancheConfiguration({
            trancheId: JUNIOR,
            nameHash: keccak256("Junior"),
            seniorityRank: 2,
            targetSize: 60 ether,
            couponBps: 0,
            votingBps: 5_000,
            transferPolicy: SyndicateTypes.TransferPolicy.NON_TRANSFERABLE
        });
    }

    function _fund(SyndicateVault vault, uint256 seniorAmount, uint256 juniorAmount)
        private
        returns (bytes32 seniorPosition, bytes32 juniorPosition)
    {
        bytes32 seniorCommitment = keccak256("COMMITMENT:SENIOR");
        bytes32 juniorCommitment = keccak256("COMMITMENT:JUNIOR");
        vm.prank(seniorLender);
        token.approve(address(vault), type(uint256).max);
        vm.prank(juniorLender);
        token.approve(address(vault), type(uint256).max);
        vm.prank(seniorLender);
        seniorPosition = vault.commit(seniorCommitment, SENIOR, seniorAmount);
        vm.prank(juniorLender);
        juniorPosition = vault.commit(juniorCommitment, JUNIOR, juniorAmount);
    }

    function _codeHash(address account) private view returns (bytes32 hash) {
        assembly ("memory-safe") {
            hash := extcodehash(account)
        }
    }
}
