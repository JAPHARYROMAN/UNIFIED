// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IPhase9LoanAccount } from "../src/interfaces/phase9/IPhase9LoanAccount.sol";
import { IPhase9LoanFactory } from "../src/interfaces/phase9/IPhase9LoanFactory.sol";
import { IPositionManagerV2 } from "../src/interfaces/phase9/IPositionManagerV2.sol";
import { Phase9Types } from "../src/resolution/Phase9Types.sol";
import {
    Phase9BootstrapUnauthorizedCaller,
    Phase9RefinanceBootstrapHarness
} from "./Phase9RefinanceBootstrapHarness.sol";

/// @dev D1 evidence for P9R-BOOT-001..005, SRC-001..002, RPL-001, FAIL-001.
contract Phase9RefinanceFactoryBootstrapTest is Phase9RefinanceBootstrapHarness {
    bytes32 private constant SEED = keccak256("PHASE9_D1_FACTORY_BOOTSTRAP");
    address private constant LENDER = address(0x1E0D3);

    BootstrapSpec private _bootstrapSpec;

    function setUp() public {
        _deployBootstrapHarness();
        _bootstrapSpec = _defaultBootstrapSpec(SEED, address(this), LENDER);
    }

    function test_P9R_BOOT001_CreatesCanonicalBootstrapGraph() public {
        (address account, address manager, bytes32 creationId) = _createBootstrap(_bootstrapSpec);
        require(account.code.length != 0 && manager.code.length != 0, "clone code");
        require(creationId != bytes32(0), "canonical creation id");
        require(phase9LoanFactory.nextLoanNonce() == 2, "factory nonce");
        require(phase9LoanFactory.loanAccount(_bootstrapSpec.loanId) == account, "account map");
        require(phase9LoanFactory.positionManager(_bootstrapSpec.loanId) == manager, "manager map");
        require(loanRegistry.loanAccount(_bootstrapSpec.loanId) == account, "registry account");
        require(loanRegistry.protocolVersionOf(_bootstrapSpec.loanId) == 9, "registry version");

        Phase9Types.DebtState memory debt = IPhase9LoanAccount(account).debtState();
        require(debt.lifecycle == Phase9Types.LoanLifecycle.ACTIVE, "active lifecycle");
        require(debt.servicingState == Phase9Types.ServicingState.CURRENT, "current state");
        require(debt.termsVersion == 1, "terms version");
        require(
            IPhase9LoanAccount(account).agreementVersionHash(1) == _bootstrapSpec.agreementHash,
            "agreement binding"
        );
        require(IPhase9LoanAccount(account).agreementVersionHash(0) == bytes32(0), "version zero");

        _installBootstrapPositions(_bootstrapSpec.loanId);
        settlementToken.approve(address(collateralCustody), _bootstrapSpec.collateralQuantity);
        _recordBootstrapSecurity(_bootstrapSpec.loanId);
        require(
            collateralCustody.totalCustody(_bootstrapSpec.collateralAssetId)
                == _bootstrapSpec.collateralQuantity,
            "custody total"
        );
        require(
            lienRegistry.lien(_bootstrapSpec.collateralId).seniorLoanId == _bootstrapSpec.loanId,
            "senior lien"
        );
    }

    function test_P9R_BOOT002_ExactSetupReplayIsInertAndChangedReuseFails() public {
        (address account, address manager,) = _createBootstrap(_bootstrapSpec);
        _installBootstrapPositions(_bootstrapSpec.loanId);
        settlementToken.approve(address(collateralCustody), _bootstrapSpec.collateralQuantity);
        _recordBootstrapSecurity(_bootstrapSpec.loanId);

        uint64 nonceBefore = phase9LoanFactory.nextLoanNonce();
        (address replayAccount, address replayManager) = _replayCanonical(_bootstrapSpec.loanId);
        require(replayAccount == account && replayManager == manager, "replay pair");
        require(phase9LoanFactory.nextLoanNonce() == nonceBefore, "replay nonce");

        _installBootstrapPositions(_bootstrapSpec.loanId);
        _recordBootstrapSecurity(_bootstrapSpec.loanId);
        require(
            IPositionManagerV2(manager).trancheIds().length == 1
                && IPositionManagerV2(manager).positionIds().length == 1,
            "setup replay wrote"
        );

        Phase9Types.LoanCreationRequest memory changed = _canonicalRequest(_bootstrapSpec.loanId);
        changed.configuration.recoveryPolicyHash = keccak256("CHANGED_RECOVERY_POLICY");
        _expectFactoryError(
            abi.encodeCall(IPhase9LoanFactory.createLoan, (changed)),
            IPhase9LoanFactory.InvalidPhase9LoanConfiguration.selector
        );
    }

    function test_P9R_BOOT003_ReplacementIsDormantAndVersionZeroRemainsEmpty() public {
        _createBootstrap(_bootstrapSpec);
        ReplacementSpec memory replacement = _defaultReplacementSpec(
            keccak256("REPLACEMENT"),
            _bootstrapSpec.loanId,
            address(this),
            keccak256("REFINANCE"),
            1
        );
        (bytes32 loanId, address account, address manager, bytes32 creationId) =
            _createReplacement(replacement);
        require(loanId != bytes32(0) && creationId != bytes32(0), "replacement ids");
        require(account.code.length != 0 && manager.code.length != 0, "replacement code");
        Phase9Types.DebtState memory debt = IPhase9LoanAccount(account).debtState();
        require(debt.lifecycle == Phase9Types.LoanLifecycle.CREATED, "dormant lifecycle");
        require(debt.servicingState == Phase9Types.ServicingState.NONE, "dormant servicing");
        require(debt.termsVersion == 0 && debt.outstandingPrincipal == 0, "dormant debt");
        require(
            IPhase9LoanAccount(account).agreementVersionHash(0) == bytes32(0),
            "dormant agreement zero"
        );
    }

    function test_P9R_BOOT004_FreshIdentityAndAuthorityFailuresRollback() public {
        (Phase9Types.LoanCreationRequest memory request,) = _prepareBootstrap(_bootstrapSpec);
        Phase9Types.DebtState memory initialDebt =
        policyResolver.bootstrap(canonicalBootstrapIds[_bootstrapSpec.loanId]).initialDebt;
        (bool locked, bytes memory lockError) = address(loanAccountImplementation)
            .call(
                abi.encodeCall(IPhase9LoanAccount.initialize, (request.configuration, initialDebt))
            );
        require(!locked, "account implementation initialized");
        require(
            _selector(lockError) == IPhase9LoanAccount.UnauthorizedPhase9LoanCaller.selector,
            "account lock selector"
        );
        (locked, lockError) = address(positionManagerImplementation)
            .call(
                abi.encodeCall(
                    IPositionManagerV2.initialize,
                    (
                        request.configuration.loanId,
                        _predictLoanAccount(request.configuration.loanId),
                        address(settlementToken)
                    )
                )
            );
        require(!locked, "manager implementation initialized");
        require(
            _selector(lockError) == IPositionManagerV2.InvalidPositionOperation.selector,
            "manager lock selector"
        );

        request.creationId = keccak256("CALLER_AUTHORED_CREATION_ID");
        _expectFactoryError(
            abi.encodeCall(IPhase9LoanFactory.createLoan, (request)),
            IPhase9LoanFactory.InvalidPhase9LoanConfiguration.selector
        );
        require(phase9LoanFactory.nextLoanNonce() == 1, "invalid id moved nonce");

        request.creationId = bytes32(0);
        Phase9BootstrapUnauthorizedCaller attacker = new Phase9BootstrapUnauthorizedCaller();
        (bool success, bytes memory returned) = address(attacker)
            .call(
                abi.encodeCall(
                    Phase9BootstrapUnauthorizedCaller.createLoan, (phase9LoanFactory, request)
                )
            );
        require(!success, "unauthorized creation");
        require(
            _selector(returned) == IPhase9LoanFactory.InvalidPhase9LoanConfiguration.selector,
            "unauthorized selector"
        );
        require(phase9LoanFactory.nextLoanNonce() == 1, "unauthorized moved nonce");
        require(phase9LoanFactory.loanAccount(_bootstrapSpec.loanId) == address(0), "partial loan");
    }

    function test_P9R_BOOT005_CanonicalReplayAfterLaterCreationAndZeroRetryCollision() public {
        (address bootstrapAccount, address bootstrapManager, bytes32 bootstrapCreationId) =
            _createBootstrap(_bootstrapSpec);
        ReplacementSpec memory replacement = _defaultReplacementSpec(
            keccak256("LATER_REPLACEMENT"),
            _bootstrapSpec.loanId,
            address(this),
            keccak256("LATER_REFINANCE"),
            1
        );
        _createReplacement(replacement);
        require(phase9LoanFactory.nextLoanNonce() == 3, "later creation nonce");

        (address replayAccount, address replayManager) = _replayCanonical(_bootstrapSpec.loanId);
        require(
            replayAccount == bootstrapAccount && replayManager == bootstrapManager,
            "historical replay pair"
        );
        require(phase9LoanFactory.nextLoanNonce() == 3, "historical replay nonce");
        require(
            _canonicalRequest(_bootstrapSpec.loanId).creationId == bootstrapCreationId,
            "stored canonical id"
        );

        Phase9Types.LoanCreationRequest memory zeroRetry = _canonicalRequest(_bootstrapSpec.loanId);
        zeroRetry.creationId = bytes32(0);
        _expectFactoryError(
            abi.encodeCall(IPhase9LoanFactory.createLoan, (zeroRetry)),
            IPhase9LoanFactory.Phase9LoanAlreadyExists.selector
        );
    }

    function test_P9R_RPL001_RawOrderingReplayAndSameBlockCheckpoints() public {
        (, address manager,) = _createBootstrap(_bootstrapSpec);
        _installBootstrapPositions(_bootstrapSpec.loanId);
        IPositionManagerV2 positions = IPositionManagerV2(manager);
        bytes32 firstTrancheId = positions.trancheIds()[0];
        bytes32 firstPositionId = positions.positionIds()[0];
        require(uint256(firstTrancheId) < type(uint256).max, "tranche id boundary");
        require(uint256(firstPositionId) < type(uint256).max - 2, "position id boundary");

        Phase9Types.Tranche memory tranche_ = Phase9Types.Tranche({
            trancheId: bytes32(uint256(firstTrancheId) + 1),
            priority: 0,
            originalClaim: 20,
            outstandingClaim: 20,
            configurationHash: keccak256("SECOND_TRANCHE")
        });
        positions.registerTranche(tranche_);
        positions.registerTranche(tranche_);
        require(positions.trancheIds().length == 2, "tranche replay append");

        Phase9Types.Position memory second = Phase9Types.Position({
            positionId: bytes32(uint256(firstPositionId) + 1),
            trancheId: tranche_.trancheId,
            owner: address(0xA11CE),
            votingPower: 10,
            claim: 10,
            state: Phase9Types.PositionState.ACTIVE
        });
        Phase9Types.Position memory third = Phase9Types.Position({
            positionId: bytes32(uint256(firstPositionId) + 2),
            trancheId: tranche_.trancheId,
            owner: address(0xB0B),
            votingPower: 10,
            claim: 10,
            state: Phase9Types.PositionState.ACTIVE
        });
        positions.issuePosition(second);
        positions.issuePosition(second);
        positions.issuePosition(third);
        require(positions.positionIds().length == 3, "position replay append");
        require(positions.totalVotingPowerAt(uint64(block.number)) == 115, "coalesced total");

        Phase9Types.Position memory changed = second;
        changed.claim = 11;
        (bool success, bytes memory returned) =
            manager.call(abi.encodeCall(IPositionManagerV2.issuePosition, (changed)));
        require(!success, "changed position replay");
        require(
            _selector(returned) == IPositionManagerV2.InvalidPositionOperation.selector,
            "changed replay selector"
        );
    }

    function _expectFactoryError(bytes memory callData, bytes4 expected) private {
        (bool success, bytes memory returned) = address(phase9LoanFactory).call(callData);
        require(!success, "expected factory revert");
        require(_selector(returned) == expected, "factory error selector");
    }

    function _selector(bytes memory returned) private pure returns (bytes4 selector) {
        if (returned.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(returned, 0x20))
        }
    }
}
