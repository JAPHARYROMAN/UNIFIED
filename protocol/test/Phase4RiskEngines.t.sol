// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ProtocolRoles } from "../src/kernel/ProtocolRoles.sol";
import { RoleManager } from "../src/kernel/RoleManager.sol";
import { InterestEngine } from "../src/risk/InterestEngine.sol";
import { IOracleAdapter, OracleRouter } from "../src/risk/OracleRouter.sol";
import { RiskTypes } from "../src/risk/RiskTypes.sol";
import { ScheduleEngine } from "../src/risk/ScheduleEngine.sol";
import { ServicingEngine } from "../src/risk/ServicingEngine.sol";

interface Phase4Vm {
    function warp(uint256 timestamp) external;
}

contract TestOracleAdapter is IOracleAdapter {
    uint256 private _value;
    uint8 private _decimals;
    uint64 private _observedAt;
    uint64 private _roundId;
    bool private _fails;

    function set(uint256 value, uint8 decimals, uint64 observedAt, uint64 roundId) external {
        _value = value;
        _decimals = decimals;
        _observedAt = observedAt;
        _roundId = roundId;
    }

    function setFailure(bool fails) external {
        _fails = fails;
    }

    function latest(bytes32, bytes32)
        external
        view
        returns (uint256 value, uint8 decimals, uint64 observedAt, uint64 roundId)
    {
        require(!_fails, "adapter failure");
        return (_value, _decimals, _observedAt, _roundId);
    }
}

contract Phase4RiskEnginesTest {
    Phase4Vm private constant vm =
        Phase4Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant ASSET = keccak256("ASSET:UFT");
    bytes32 private constant QUOTE = keccak256("ASSET:USD");
    uint64 private constant NOW = 1_800_000_000;

    RoleManager private roles;
    OracleRouter private oracle;
    InterestEngine private interest;
    ScheduleEngine private schedule;
    ServicingEngine private servicing;
    TestOracleAdapter[3] private adapters;

    function setUp() public {
        vm.warp(NOW);
        roles = new RoleManager(address(0xA11CE), address(this));
        roles.grantRole(ProtocolRoles.ORACLE_MANAGER_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.SERVICER_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.PAYMENT_FINALIZER_ROLE, address(this), type(uint64).max);
        roles.grantRole(ProtocolRoles.RISK_COUNCIL_ROLE, address(this), type(uint64).max);
        oracle = new OracleRouter(roles);
        interest = new InterestEngine();
        schedule = new ScheduleEngine();
        servicing = new ServicingEngine(roles);

        oracle.configurePair(ASSET, QUOTE, 30 minutes, 750, 3);
        for (uint256 index = 0; index < adapters.length; ++index) {
            adapters[index] = new TestOracleAdapter();
            oracle.configureSource(
                ASSET, QUOTE, keccak256(abi.encode("SOURCE", index)), address(adapters[index]), true
            );
        }
        _setPrices(99e8, 100e8, 101e8, NOW);
    }

    function testOracleMedianNormalizationEvidenceAndSafeMode() public {
        require(oracle.updatePrice(ASSET, QUOTE), "valid price rejected");
        RiskTypes.OracleObservation memory observation = oracle.price(ASSET, QUOTE);
        require(observation.value == 100e18, "median mismatch");
        require(observation.decimals == 18, "normalization mismatch");
        require(observation.observedAt == NOW, "observation time mismatch");
        require(observation.sourceEvidenceHash != bytes32(0), "evidence missing");
        require(
            oracle.validateObservation(observation, keccak256("LIQUIDATION")),
            "canonical observation rejected"
        );
        observation.retrievedAt += 1;
        require(
            !oracle.validateObservation(observation, keccak256("LIQUIDATION")),
            "altered observation metadata accepted"
        );
        observation.retrievedAt -= 1;

        vm.warp(NOW + 30 minutes + 1);
        require(!oracle.updatePrice(ASSET, QUOTE), "stale sources accepted");
        require(oracle.isCircuitBroken(ASSET), "safe mode not entered");
        (bool staleRead,) = address(oracle).call(abi.encodeCall(oracle.price, (ASSET, QUOTE)));
        require(!staleRead, "stale price remained actionable");

        _setPrices(100e8, 100e8, 100e8, uint64(block.timestamp));
        require(oracle.updatePrice(ASSET, QUOTE), "fresh quorum did not recover");
        require(!oracle.isCircuitBroken(ASSET), "safe mode did not clear");

        _setPrices(50e8, 100e8, 101e8, uint64(block.timestamp));
        require(!oracle.updatePrice(ASSET, QUOTE), "deviating source set accepted");
        require(oracle.isPairCircuitBroken(ASSET, QUOTE), "deviation did not break pair");
    }

    function testFixedAndVariableInterestAreBoundedAndDeterministic() public view {
        RiskTypes.InterestTerms memory fixedTerms = RiskTypes.InterestTerms({
            annualRateRay: 1e26,
            spreadRay: 0,
            floorRateRay: 0,
            capRateRay: 10e27,
            maximumBenchmarkAge: 0
        });
        uint256 fixedAccrual = interest.accrueFixed(1_000 ether, NOW, NOW + 365 days, fixedTerms);
        require(fixedAccrual == 100 ether, "fixed accrual mismatch");

        RiskTypes.InterestTerms memory variableTerms = RiskTypes.InterestTerms({
            annualRateRay: 0,
            spreadRay: 2e25,
            floorRateRay: 4e25,
            capRateRay: 6e25,
            maximumBenchmarkAge: 1 hours
        });
        (uint256 variableAccrual, uint256 appliedRate) = interest.accrueVariable(
            1_000 ether, NOW, NOW + 365 days, 5e25, NOW + 365 days - 1 hours, variableTerms
        );
        require(appliedRate == 6e25, "rate cap not applied");
        require(variableAccrual == 60 ether, "variable accrual mismatch");
    }

    function testStaleBenchmarkCannotAccrueVariableInterest() public {
        RiskTypes.InterestTerms memory terms = RiskTypes.InterestTerms({
            annualRateRay: 0,
            spreadRay: 1e25,
            floorRateRay: 1e25,
            capRateRay: 5e25,
            maximumBenchmarkAge: 1 hours
        });
        (bool accepted,) = address(interest)
            .call(
                abi.encodeCall(
                    interest.accrueVariable, (1_000 ether, NOW, NOW + 2 hours, 2e25, NOW, terms)
                )
            );
        require(!accepted, "stale benchmark accrued interest");
    }

    function testScheduleFamiliesConservePrincipalAndRemainder() public view {
        RiskTypes.SchedulePlan memory equalPrincipal = RiskTypes.SchedulePlan({
            kind: RiskTypes.ScheduleKind.EQUAL_PRINCIPAL,
            principal: 1_000,
            totalInterest: 101,
            periodicRateRay: 0,
            balloonPrincipal: 0,
            startTime: NOW,
            periodSeconds: 30 days,
            installmentCount: 3,
            paymentHolidayCount: 1
        });
        RiskTypes.Installment[] memory installments = schedule.generate(equalPrincipal);
        require(
            installments[0].principalDue == 333 && installments[1].principalDue == 333
                && installments[2].principalDue == 334,
            "principal remainder mismatch"
        );
        require(
            installments[0].interestDue == 33 && installments[2].interestDue == 35,
            "interest remainder mismatch"
        );
        require(installments[0].dueTime == NOW + 60 days, "payment holiday not deterministic");

        RiskTypes.SchedulePlan memory annuity = RiskTypes.SchedulePlan({
            kind: RiskTypes.ScheduleKind.ANNUITY,
            principal: 1_000_000,
            totalInterest: 0,
            periodicRateRay: 1e25,
            balloonPrincipal: 0,
            startTime: NOW,
            periodSeconds: 30 days,
            installmentCount: 12,
            paymentHolidayCount: 0
        });
        RiskTypes.Installment[] memory annuityItems = schedule.generate(annuity);
        uint256 totalPrincipal;
        for (uint256 index = 0; index < annuityItems.length; ++index) {
            totalPrincipal += annuityItems[index].principalDue;
        }
        require(totalPrincipal == annuity.principal, "annuity principal not conserved");
    }

    function testServicingCureAndDefaultAreObjective() public {
        bytes32 curedLoan = keccak256("CURED_LOAN");
        servicing.configure(curedLoan, 1_000, NOW + 10, NOW + 20, NOW + 30);
        vm.warp(NOW + 21);
        require(
            servicing.evaluate(curedLoan) == RiskTypes.ServicingStatus.DELINQUENT,
            "delinquency not detected"
        );
        servicing.recordCure(curedLoan, keccak256("TOP_UP_EVIDENCE"));
        vm.warp(NOW + 31);
        require(
            servicing.evaluate(curedLoan) == RiskTypes.ServicingStatus.CURED,
            "valid cure did not prevent default"
        );
        (bool curedDefaulted,) = address(servicing)
            .call(
                abi.encodeCall(servicing.confirmDefault, (curedLoan, keccak256("INVALID_DEFAULT")))
            );
        require(!curedDefaulted, "cured loan defaulted");

        bytes32 defaultedLoan = keccak256("DEFAULTED_LOAN");
        servicing.configure(
            defaultedLoan,
            2_000,
            uint64(block.timestamp + 10),
            uint64(block.timestamp + 20),
            uint64(block.timestamp + 30)
        );
        vm.warp(block.timestamp + 21);
        servicing.evaluate(defaultedLoan);
        vm.warp(block.timestamp + 10);
        servicing.confirmDefault(defaultedLoan, keccak256("DEFAULT_EVIDENCE"));
        require(servicing.liquidationEligible(defaultedLoan), "default is not actionable");
    }

    function testFinalPaymentMarksObligationRepaid() public {
        bytes32 loanId = keccak256("REPAID_LOAN");
        servicing.configure(loanId, 500, NOW + 10, NOW + 20, NOW + 30);
        servicing.applyFinalPayment(loanId, keccak256("FINAL_PAYMENT"), 500);
        require(
            servicing.servicingRecord(loanId).status == RiskTypes.ServicingStatus.REPAID,
            "final payment did not repay obligation"
        );
        require(!servicing.liquidationEligible(loanId), "repaid obligation is liquidatable");
    }

    function _setPrices(uint256 first, uint256 second, uint256 third, uint64 observedAt) private {
        adapters[0].set(first, 8, observedAt, 1);
        adapters[1].set(second, 8, observedAt, 2);
        adapters[2].set(third, 8, observedAt, 3);
    }
}
