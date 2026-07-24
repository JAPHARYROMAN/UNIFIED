// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { IRoleManager } from "../src/interfaces/IRoleManager.sol";
import { LoanRegistry } from "../src/kernel/LoanRegistry.sol";
import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { LoanTypes } from "../src/loan/LoanTypes.sol";
import { CredentialRegistry } from "../src/identity/CredentialRegistry.sol";
import { CreditDecisionRegistry } from "../src/identity/CreditDecisionRegistry.sol";
import { ExposureManager } from "../src/identity/ExposureManager.sol";
import { IdentityProviderRegistry } from "../src/identity/IdentityProviderRegistry.sol";
import { IdentityTypes } from "../src/identity/IdentityTypes.sol";

interface IdentityVm {
    function prank(address sender) external;
    function warp(uint256 timestamp) external;
}

contract ExposureTestLoan {
    LoanRegistry private immutable _loans;
    bytes32 private immutable _loanId;
    uint256 private _outstandingPrincipal;

    constructor(LoanRegistry loans_, bytes32 loanId_, uint256 principal_) {
        _loans = loans_;
        _loanId = loanId_;
        _outstandingPrincipal = principal_;
    }

    function debtSnapshot(uint64 asOf) external view returns (LoanTypes.DebtSnapshot memory) {
        return LoanTypes.DebtSnapshot({
            outstandingPrincipal: _outstandingPrincipal,
            accruedInterest: 0,
            capitalizedInterest: 0,
            accruedFees: 0,
            accruedPenalties: 0,
            recoverableCosts: 0,
            unappliedCredit: 0,
            asOf: asOf
        });
    }

    function close() external {
        _outstandingPrincipal = 0;
        _loans.markTerminal(_loanId);
    }
}

contract ExposureFactoryHarness {
    ExposureManager private immutable _exposure;
    LoanRegistry private immutable _loans;

    constructor(ExposureManager exposure_, LoanRegistry loans_) {
        _exposure = exposure_;
        _loans = loans_;
    }

    function reserveOnly(
        bytes32 decisionId,
        bytes32 loanId,
        address borrower,
        uint256 amount,
        uint64 duration,
        bytes32 productHash
    ) public {
        _exposure.reserve(
            decisionId,
            loanId,
            borrower,
            amount,
            duration,
            productHash,
            keccak256(abi.encode("RESERVE", loanId))
        );
    }

    function createAndActivate(
        bytes32 decisionId,
        bytes32 loanId,
        address borrower,
        uint256 amount,
        uint64 duration,
        bytes32 productHash
    ) external returns (ExposureTestLoan loan) {
        reserveOnly(decisionId, loanId, borrower, amount, duration, productHash);
        loan = _registerAndActivate(loanId, borrower, amount);
    }

    function activateReserved(bytes32 loanId, address borrower, uint256 amount)
        external
        returns (ExposureTestLoan loan)
    {
        return _registerAndActivate(loanId, borrower, amount);
    }

    function cancel(bytes32 loanId) external {
        _exposure.cancelReservation(loanId, keccak256(abi.encode("CANCEL", loanId)));
    }

    function _registerAndActivate(bytes32 loanId, address borrower, uint256 amount)
        private
        returns (ExposureTestLoan loan)
    {
        loan = new ExposureTestLoan(_loans, loanId, amount);
        _loans.registerLoan(loanId, address(loan), borrower, keccak256("AGREEMENT"), 6);
        _exposure.activate(loanId, keccak256(abi.encode("ACTIVATE", loanId)));
    }
}

contract Phase6IdentityTest {
    IdentityVm private constant vm =
        IdentityVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint64 private constant NOW = 1_900_000_000;
    bytes32 private constant PROVIDER = keccak256("PROVIDER:SYNTHETIC");
    bytes32 private constant SCHEMA = keccak256("SCHEMA:ELIGIBILITY:V1");
    bytes32 private constant SUBJECT = keccak256("SALTED:SUBJECT:SYNTHETIC");
    bytes32 private constant SCOPE = keccak256("SCOPE:UNSECURED:LOCAL");
    bytes32 private constant ASSET = keccak256("ASSET:SYNTHETIC");
    bytes32 private constant PRODUCT = keccak256("PRODUCT:UNSECURED:LOCAL");

    address private issuer = address(0x1550);
    address private underwriter = address(0xA11D);
    address private riskCouncil = address(0x715C);
    address private borrower = address(0xB0B);
    address private secondWallet = address(0xB0C);
    address private outsider = address(0xBAD);

    RoleManager private roles;
    LoanRegistry private loans;
    IdentityProviderRegistry private providers;
    CredentialRegistry private credentials;
    CreditDecisionRegistry private decisions;
    ExposureManager private exposure;
    ExposureFactoryHarness private factory;

    function setUp() public {
        vm.warp(NOW);
        roles = new RoleManager(address(0xA11CE), address(this));
        roles.grantRole(ProtocolRoles.IDENTITY_REGISTRAR_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.CREDENTIAL_ISSUER_ROLE, issuer, type(uint64).max);
        roles.grantRole(ProtocolRoles.UNDERWRITER_ROLE, underwriter, type(uint64).max);
        roles.grantRole(ProtocolRoles.IDENTITY_REVOCATION_ROLE, riskCouncil, type(uint64).max);
        loans = new LoanRegistry(IRoleManager(address(roles)));
        providers = new IdentityProviderRegistry(IRoleManager(address(roles)));
        credentials = new CredentialRegistry(IRoleManager(address(roles)), providers);
        decisions = new CreditDecisionRegistry(IRoleManager(address(roles)), credentials);
        exposure = new ExposureManager(IRoleManager(address(roles)), decisions, loans);
        factory = new ExposureFactoryHarness(exposure, loans);
        roles.grantRole(ProtocolRoles.EXPOSURE_FACTORY_ROLE, address(factory), type(uint64).max);
        roles.grantRole(ProtocolRoles.LOAN_FACTORY_ROLE, address(factory), type(uint64).max);
        providers.registerProvider(PROVIDER, issuer, keccak256("PROVIDER_METADATA"), 5);
        providers.registerSchema(SCHEMA, PROVIDER, keccak256("SCHEMA_DEFINITION"), 4);
    }

    function testCredentialBindingValidityAndScopedSemantics() public {
        bytes32 credentialId = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:PRIMARY"), NOW + 1 hours, NOW + 30 days
        );
        require(
            !credentials.isUsable(credentialId, borrower, SUBJECT, SCOPE, 1, 3),
            "not-yet-valid credential accepted"
        );
        vm.warp(NOW + 1 hours);
        require(
            credentials.isUsable(credentialId, borrower, SUBJECT, SCOPE, 1, 3),
            "valid credential rejected"
        );
        require(
            !credentials.isUsable(credentialId, secondWallet, SUBJECT, SCOPE, 1, 3),
            "wrong account accepted"
        );
        require(
            !credentials.isUsable(credentialId, borrower, keccak256("OTHER_SUBJECT"), SCOPE, 1, 3),
            "wrong subject accepted"
        );
        require(
            !credentials.isUsable(credentialId, borrower, SUBJECT, keccak256("OTHER_SCOPE"), 1, 3),
            "wrong scope accepted"
        );
        require(
            !credentials.isUsable(credentialId, borrower, SUBJECT, SCOPE, 2, 3),
            "wrong epoch accepted"
        );
    }

    function testCredentialAndProviderRevocationPropagateProspectively() public {
        bytes32 credentialId = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:REVOKE"), NOW, NOW + 30 days
        );
        bytes32 decisionId = _issueDecision(
            credentialId, borrower, SUBJECT, keccak256("DECISION:REVOKE"), 100 ether
        );
        require(_decisionUsable(decisionId, borrower, SUBJECT, 1 ether), "decision not usable");

        vm.prank(riskCouncil);
        credentials.revokeCredential(credentialId, keccak256("REVOCATION_EVIDENCE"));
        require(
            !_decisionUsable(decisionId, borrower, SUBJECT, 1 ether),
            "revoked credential authorized exposure"
        );

        bytes32 secondCredential = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:PROVIDER"), NOW, NOW + 30 days
        );
        vm.prank(riskCouncil);
        providers.setProviderStatus(
            PROVIDER, IdentityTypes.ProviderStatus.SUSPENDED, keccak256("PROVIDER_INCIDENT")
        );
        require(
            !credentials.isUsable(secondCredential, borrower, SUBJECT, SCOPE, 1, 3),
            "suspended provider credential accepted"
        );
        vm.prank(riskCouncil);
        providers.setSchemaActive(SCHEMA, false, keccak256("SCHEMA_INCIDENT"));
        (bool restoredWhileSuspended,) = address(providers)
            .call(
                abi.encodeCall(
                    providers.setSchemaActive, (SCHEMA, true, keccak256("PREMATURE_SCHEMA_RESTORE"))
                )
            );
        require(!restoredWhileSuspended, "schema restored under suspended provider");
        providers.setProviderStatus(
            PROVIDER, IdentityTypes.ProviderStatus.ACTIVE, keccak256("PROVIDER_REVIEWED")
        );
        providers.setSchemaActive(SCHEMA, true, keccak256("SCHEMA_REVIEWED"));
        require(
            credentials.isUsable(secondCredential, borrower, SUBJECT, SCOPE, 1, 3),
            "reviewed provider did not recover"
        );
    }

    function testDecisionBindsProductAssetDurationAndExpiry() public {
        bytes32 credentialId = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:DECISION"), NOW, NOW + 30 days
        );
        bytes32 decisionId = _issueDecision(
            credentialId, borrower, SUBJECT, keccak256("DECISION:BOUND"), 100 ether
        );
        require(_decisionUsable(decisionId, borrower, SUBJECT, 100 ether), "limit rejected");
        require(
            !decisions.isUsable(
                decisionId, borrower, SUBJECT, keccak256("OTHER_ASSET"), PRODUCT, 1, 30 days
            ),
            "wrong asset accepted"
        );
        require(
            !decisions.isUsable(
                decisionId, borrower, SUBJECT, ASSET, keccak256("OTHER_PRODUCT"), 1, 30 days
            ),
            "wrong product accepted"
        );
        require(
            !decisions.isUsable(decisionId, borrower, SUBJECT, ASSET, PRODUCT, 1, 366 days),
            "excess duration accepted"
        );
        vm.warp(NOW + 31 days);
        require(
            !_decisionUsable(decisionId, borrower, SUBJECT, 1 ether), "expired decision accepted"
        );
    }

    function testSubjectExposureAggregatesAcrossWalletsAndDecisions() public {
        bytes32 firstCredential = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:WALLET:1"), NOW, NOW + 30 days
        );
        bytes32 firstDecision = _issueDecision(
            firstCredential, borrower, SUBJECT, keccak256("DECISION:WALLET:1"), 100 ether
        );
        ExposureTestLoan loan = factory.createAndActivate(
            firstDecision, keccak256("LOAN:WALLET:1"), borrower, 60 ether, 30 days, PRODUCT
        );
        require(address(loan) != address(0), "first exposure not activated");

        bytes32 secondCredential = _issueCredential(
            secondWallet, SUBJECT, keccak256("CREDENTIAL:WALLET:2"), NOW, NOW + 30 days
        );
        bytes32 secondDecision = _issueDecision(
            secondCredential, secondWallet, SUBJECT, keccak256("DECISION:WALLET:2"), 100 ether
        );
        require(
            !_decisionUsable(firstDecision, borrower, SUBJECT, 1 ether),
            "superseded decision remained usable"
        );
        (bool reserved,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.reserveOnly,
                    (
                        secondDecision,
                        keccak256("LOAN:WALLET:2"),
                        secondWallet,
                        50 ether,
                        30 days,
                        PRODUCT
                    )
                )
            );
        require(!reserved, "second wallet bypassed subject limit");
        IdentityTypes.ExposureTotals memory totals = exposure.exposure(SUBJECT, ASSET);
        require(totals.active == 60 ether && totals.reserved == 0, "exposure drift");
    }

    function testFuzzRecognizedExposureNeverExceedsCurrentLimit(uint96 firstRaw, uint96 secondRaw)
        public
    {
        uint256 firstAmount = (uint256(firstRaw) % (100 ether)) + 1;
        uint256 secondAmount = (uint256(secondRaw) % (100 ether)) + 1;
        bytes32 firstCredential = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:FUZZ:1"), NOW, NOW + 30 days
        );
        bytes32 firstDecision = _issueDecision(
            firstCredential, borrower, SUBJECT, keccak256("DECISION:FUZZ:1"), 100 ether
        );
        factory.createAndActivate(
            firstDecision,
            keccak256(abi.encode("LOAN:FUZZ:1", firstAmount)),
            borrower,
            firstAmount,
            30 days,
            PRODUCT
        );

        bytes32 secondCredential = _issueCredential(
            secondWallet, SUBJECT, keccak256("CREDENTIAL:FUZZ:2"), NOW, NOW + 30 days
        );
        bytes32 secondDecision = _issueDecision(
            secondCredential, secondWallet, SUBJECT, keccak256("DECISION:FUZZ:2"), 100 ether
        );
        (bool reserved,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.reserveOnly,
                    (
                        secondDecision,
                        keccak256(abi.encode("LOAN:FUZZ:2", secondAmount)),
                        secondWallet,
                        secondAmount,
                        30 days,
                        PRODUCT
                    )
                )
            );
        IdentityTypes.ExposureTotals memory totals = exposure.exposure(SUBJECT, ASSET);
        require(totals.active + totals.reserved <= 100 ether, "fuzz exposure exceeded limit");
        if (firstAmount + secondAmount <= 100 ether) {
            require(reserved && totals.reserved == secondAmount, "valid capacity rejected");
        } else {
            require(!reserved && totals.reserved == 0, "excess capacity accepted");
        }
    }

    function testReservationActivationTerminalReleaseAndReplaySafety() public {
        bytes32 credentialId = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:LIFECYCLE"), NOW, NOW + 30 days
        );
        bytes32 decisionId = _issueDecision(
            credentialId, borrower, SUBJECT, keccak256("DECISION:LIFECYCLE"), 100 ether
        );
        bytes32 loanId = keccak256("LOAN:LIFECYCLE");
        ExposureTestLoan loan =
            factory.createAndActivate(decisionId, loanId, borrower, 70 ether, 30 days, PRODUCT);
        IdentityTypes.ExposureTotals memory active = exposure.exposure(SUBJECT, ASSET);
        require(active.active == 70 ether && active.reserved == 0, "activation mismatch");

        loan.close();
        vm.prank(outsider);
        exposure.release(loanId, keccak256("TERMINAL_RELEASE"));
        IdentityTypes.ExposureTotals memory released = exposure.exposure(SUBJECT, ASSET);
        require(released.active == 0 && released.reserved == 0, "release mismatch");
        vm.prank(outsider);
        (bool replayed,) =
            address(exposure).call(abi.encodeCall(exposure.release, (loanId, keccak256("REPLAY"))));
        require(!replayed, "exposure released twice");
    }

    function testPendingReservationsCountAndExpireSafely() public {
        bytes32 credentialId = _issueCredential(
            borrower, SUBJECT, keccak256("CREDENTIAL:PENDING"), NOW, NOW + 30 days
        );
        bytes32 decisionId = _issueDecision(
            credentialId, borrower, SUBJECT, keccak256("DECISION:PENDING"), 100 ether
        );
        bytes32 firstLoan = keccak256("LOAN:PENDING:1");
        factory.reserveOnly(decisionId, firstLoan, borrower, 70 ether, 30 days, PRODUCT);
        (bool secondReserved,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.reserveOnly,
                    (decisionId, keccak256("LOAN:PENDING:2"), borrower, 31 ether, 30 days, PRODUCT)
                )
            );
        require(!secondReserved, "pending reservation did not count");
        vm.warp(NOW + exposure.RESERVATION_TTL());
        vm.prank(outsider);
        exposure.cancelReservation(firstLoan, keccak256("EXPIRED_RESERVATION"));
        IdentityTypes.ExposureTotals memory totals = exposure.exposure(SUBJECT, ASSET);
        require(totals.active == 0 && totals.reserved == 0, "expired capacity not released");
    }

    function testRevocationBetweenReservationAndActivationFailsClosed() public {
        bytes32 credentialId =
            _issueCredential(borrower, SUBJECT, keccak256("CREDENTIAL:RACE"), NOW, NOW + 30 days);
        bytes32 decisionId = _issueDecision(
            credentialId, borrower, SUBJECT, keccak256("DECISION:RACE"), 100 ether
        );
        bytes32 loanId = keccak256("LOAN:RACE");
        factory.reserveOnly(decisionId, loanId, borrower, 80 ether, 30 days, PRODUCT);
        vm.prank(riskCouncil);
        credentials.revokeCredential(credentialId, keccak256("RACE_REVOCATION"));
        (bool activated,) = address(factory)
            .call(abi.encodeCall(factory.activateReserved, (loanId, borrower, 80 ether)));
        require(!activated, "revoked credential activated reservation");
        require(!loans.exists(loanId), "failed activation left registered loan");
        factory.cancel(loanId);
        require(
            exposure.exposure(SUBJECT, ASSET).reserved == 0, "failed activation trapped capacity"
        );
    }

    function _issueCredential(
        address account,
        bytes32 subject,
        bytes32 credentialId,
        uint64 validFrom,
        uint64 validUntil
    ) private returns (bytes32) {
        IdentityTypes.CredentialInput memory input =
            IdentityTypes.CredentialInput({
                credentialId: credentialId,
                subjectCommitment: subject,
                boundAccount: account,
                providerId: PROVIDER,
                schemaId: SCHEMA,
                claimsCommitment: keccak256(abi.encode("SALTED_SYNTHETIC_CLAIMS", credentialId)),
                scopeHash: SCOPE,
                epoch: 1,
                assurance: 4,
                validFrom: validFrom,
                validUntil: validUntil
            });
        vm.prank(issuer);
        credentials.issueCredential(input);
        return credentialId;
    }

    function _issueDecision(
        bytes32 credentialId,
        address account,
        bytes32 subject,
        bytes32 decisionId,
        uint256 maximumExposure
    ) private returns (bytes32) {
        bytes32 previousDecisionId = decisions.currentDecisionId(subject, ASSET, PRODUCT);
        uint64 sequence = previousDecisionId == bytes32(0)
            ? 1
            : decisions.decision(previousDecisionId).sequence + 1;
        IdentityTypes.CreditDecisionInput memory input = IdentityTypes.CreditDecisionInput({
            decisionId: decisionId,
            previousDecisionId: previousDecisionId,
            credentialId: credentialId,
            subjectCommitment: subject,
            borrower: account,
            credentialScopeHash: SCOPE,
            credentialEpoch: 1,
            minimumAssurance: 3,
            policyId: keccak256("POLICY:UNSECURED:LOCAL"),
            policyMajor: 1,
            policyMinor: 0,
            policyPatch: 0,
            ruleSetHash: keccak256("RULES:UNSECURED:LOCAL:V1"),
            modelSetHash: keccak256("MODELS:RULES_ONLY:V1"),
            featureEvidenceRoot: keccak256(abi.encode("SYNTHETIC_FEATURES", decisionId)),
            featureSchemaHash: keccak256("FEATURE_SCHEMA:V1"),
            featuresAsOf: uint64(block.timestamp),
            settlementAssetId: ASSET,
            productHash: PRODUCT,
            maximumExposure: maximumExposure,
            maximumDuration: 365 days,
            expiresAt: uint64(block.timestamp + 30 days),
            sequence: sequence,
            reasonCodesHash: keccak256("REASON:APPROVED_SYNTHETIC")
        });
        vm.prank(underwriter);
        decisions.issueDecision(input);
        return decisionId;
    }

    function _decisionUsable(bytes32 decisionId, address account, bytes32 subject, uint256 amount)
        private
        view
        returns (bool)
    {
        return decisions.isUsable(decisionId, account, subject, ASSET, PRODUCT, amount, 30 days);
    }
}
