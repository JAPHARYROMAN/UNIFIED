from dataclasses import fields, replace
from typing import Any, cast

import pytest
from google.protobuf.timestamp_pb2 import Timestamp  # type: ignore[import-untyped]
from unified.v1 import refinance_pb2, types_pb2  # type: ignore[import-not-found]
from unified_foundation.phase9_payoff_reference import (
    PayoffComponentReference,
    PayoffPolicyReference,
    PayoffQuoteIdentityReference,
    SettlementRouteReference,
    canonical_payoff_components,
    component_beneficiary_hash,
    encode_component_beneficiaries,
    payoff_policy_hash,
    payoff_quote_id,
    settlement_route_hash,
)
from unified_foundation.phase9_quote_codec import (
    canonical_golden_payoff_quote_context,
    payoff_quote_digest,
)

EXPECTED_POLICY_HASH = "5777a058cd8923e844c1c2e74ee82a0a8c4073084eddf4a44e860f68a3f5e718"
EXPECTED_COMPONENT_HASH = "b43d774823fee6ffb1b0aaeaa005a119300aa1e65bcea9206f434fa4c3f01189"
EXPECTED_ROUTE_HASH = "adc8f2b001860d4d37fe42ce1340628670fe587ea3401947f75d8b2c6aac3aba"
EXPECTED_QUOTE_ID = "bfb9a4e4e14118a568ad2742e9607a45dc9ed0b3bf80b1d01364003f91d16988"
EXISTING_CODEC_GOLDEN = "632cc3b4bcf2cfcddcf9699eb7f9eef6f946fa7f4ed392f4767925354f8a2058"
ASSET_VALUE = "asset:phase9:p9unit"


def _bytes(value: int, length: int) -> bytes:
    return bytes([value]) * length


def _replace_reference[ReferenceT](
    reference: ReferenceT, field: str, value: object
) -> ReferenceT:
    return cast(ReferenceT, replace(cast(Any, reference), **{field: value}))


def _policy() -> PayoffPolicyReference:
    return PayoffPolicyReference(
        chain_id=31337,
        payoff_quote_engine=_bytes(0x11, 20),
        quote_policy_registry=_bytes(0x12, 20),
        loan_id=_bytes(0x33, 32),
        loan_account=_bytes(0x44, 20),
        bound_policy_set_hash=_bytes(0x88, 32),
        fee_penalty_beneficiary=_bytes(0x77, 20),
        settlement_asset_id=_bytes(0xAA, 32),
        settlement_token=_bytes(0x22, 20),
        maximum_validity=300,
    )


def _components() -> tuple[PayoffComponentReference, ...]:
    return canonical_payoff_components(
        principal=90_000_000,
        accrued_interest=5_000_000,
        fees=3_000_000,
        penalties=3_000_000,
        credits=1_000_000,
        lender_beneficiary=_bytes(0x99, 20),
        fee_penalty_beneficiary=_bytes(0x77, 20),
    )


def _route(policy_hash: bytes) -> SettlementRouteReference:
    return SettlementRouteReference(
        chain_id=31337,
        payoff_quote_engine=_bytes(0x11, 20),
        refinance_coordinator=_bytes(0x13, 20),
        loan_id=_bytes(0x33, 32),
        loan_account=_bytes(0x44, 20),
        settlement_asset_id=_bytes(0xAA, 32),
        settlement_token=_bytes(0x22, 20),
        lender_beneficiary=_bytes(0x99, 20),
        fee_penalty_beneficiary=_bytes(0x77, 20),
        policy_hash=policy_hash,
    )


def _identity(
    policy_hash: bytes, component_hash: bytes, route_hash: bytes
) -> PayoffQuoteIdentityReference:
    return PayoffQuoteIdentityReference(
        payoff_quote_engine=_bytes(0x11, 20),
        chain_id=31337,
        loan_id=_bytes(0x33, 32),
        loan_account=_bytes(0x44, 20),
        policy_hash=policy_hash,
        debt_state_version=7,
        principal=90_000_000,
        accrued_interest=5_000_000,
        fees=3_000_000,
        penalties=3_000_000,
        credits=1_000_000,
        component_beneficiary_hash=component_hash,
        net_payoff=100_000_000,
        settlement_asset_id=_bytes(0xAA, 32),
        settlement_token=_bytes(0x22, 20),
        settlement_route_hash=route_hash,
        issued_at=1_800_000_000,
        valid_until=1_800_000_300,
        quote_nonce=1,
    )


def _money(units: int) -> types_pb2.Money:
    return types_pb2.Money(asset_id=types_pb2.AssetId(value=ASSET_VALUE), units=str(units))


def _existing_codec_quote() -> refinance_pb2.PayoffQuote:
    return refinance_pb2.PayoffQuote(
        loan_id=types_pb2.LoanId(value="0x" + "33" * 32),
        debt=refinance_pb2.CanonicalDebtSnapshot(
            loan_id=types_pb2.LoanId(value="0x" + "33" * 32),
            loan_account_id=types_pb2.Identifier(value="0x" + "44" * 20),
            principal=_money(90_000_000),
            accrued_interest=_money(5_000_000),
            capitalized_interest=_money(0),
            fees=_money(3_000_000),
            penalties=_money(3_000_000),
            recoverable_costs=_money(0),
            credits=_money(1_000_000),
            debt_state_version=7,
        ),
        components=[
            refinance_pb2.PayoffComponent(
                kind=refinance_pb2.PAYOFF_COMPONENT_KIND_PRINCIPAL,
                amount=_money(90_000_000),
                beneficiary_id=types_pb2.PartyId(value="party:old-lender"),
                obligation_code="PRINCIPAL",
            )
        ],
        gross_payoff=_money(101_000_000),
        credits=_money(1_000_000),
        net_payoff=_money(100_000_000),
        component_beneficiary_hash=_bytes(0x66, 32),
        settlement_route_hash=_bytes(0x77, 32),
        issued_at=Timestamp(seconds=1_800_000_000),
        valid_until=Timestamp(seconds=1_800_000_300),
        quote_nonce=1,
        quote_policy=types_pb2.PolicyReference(content_hash=_bytes(0x55, 32)),
    )


def test_reference_encoders_match_cross_language_golden_vectors() -> None:
    """P9Q-POL-001, P9Q-COMP-003, P9Q-ROUTE-001, and P9Q-ID-001."""

    policy_hash = payoff_policy_hash(_policy())
    component_hash = component_beneficiary_hash(_components())
    route_hash = settlement_route_hash(_route(policy_hash))
    quote_id = payoff_quote_id(_identity(policy_hash, component_hash, route_hash))

    assert policy_hash.hex() == EXPECTED_POLICY_HASH
    assert component_hash.hex() == EXPECTED_COMPONENT_HASH
    assert route_hash.hex() == EXPECTED_ROUTE_HASH
    assert quote_id.hex() == EXPECTED_QUOTE_ID


def test_reference_quote_id_preserves_existing_codec_golden() -> None:
    """P9Q-ID-001 differential: the new oracle cannot redefine the frozen codec."""

    reference = _identity(_bytes(0x55, 32), _bytes(0x66, 32), _bytes(0x77, 32))
    reference_id = payoff_quote_id(reference)
    codec_id = payoff_quote_digest(
        _existing_codec_quote(), canonical_golden_payoff_quote_context()
    )
    assert reference_id == codec_id
    assert reference_id.hex() == EXISTING_CODEC_GOLDEN


def test_quote_identity_field_set_excludes_gross_and_quote_id() -> None:
    """P9Q-ID-002: gross payoff and quote ID are not preimage inputs."""

    field_names = tuple(field.name for field in fields(PayoffQuoteIdentityReference))
    assert "gross_payoff" not in field_names
    assert "quote_id" not in field_names
    assert field_names == (
        "payoff_quote_engine",
        "chain_id",
        "loan_id",
        "loan_account",
        "policy_hash",
        "debt_state_version",
        "principal",
        "accrued_interest",
        "fees",
        "penalties",
        "credits",
        "component_beneficiary_hash",
        "net_payoff",
        "settlement_asset_id",
        "settlement_token",
        "settlement_route_hash",
        "issued_at",
        "valid_until",
        "quote_nonce",
    )


@pytest.mark.parametrize(
    ("field", "value"),
    (
        ("chain_id", 31338),
        ("payoff_quote_engine", _bytes(0x10, 20)),
        ("quote_policy_registry", _bytes(0x14, 20)),
        ("loan_id", _bytes(0x34, 32)),
        ("loan_account", _bytes(0x45, 20)),
        ("bound_policy_set_hash", _bytes(0x89, 32)),
        ("fee_penalty_beneficiary", _bytes(0x78, 20)),
        ("settlement_asset_id", _bytes(0xAB, 32)),
        ("settlement_token", _bytes(0x23, 20)),
        ("maximum_validity", 301),
    ),
)
def test_every_policy_field_mutation_changes_hash(field: str, value: object) -> None:
    """P9Q-POL-002 and P9Q-POL-003."""

    baseline = _policy()
    assert payoff_policy_hash(_replace_reference(baseline, field, value)) != payoff_policy_hash(
        baseline
    )


def test_component_mutations_change_hash_and_omission_fails_closed() -> None:
    """P9Q-COMP-001 through P9Q-COMP-004, including zero retention."""

    baseline = _components()
    baseline_hash = component_beneficiary_hash(baseline)
    mutations = (
        (replace(baseline[0], kind=4), *baseline[1:]),
        (replace(baseline[0], amount=0), *baseline[1:]),
        (replace(baseline[0], beneficiary=_bytes(0x98, 20)), *baseline[1:]),
        (replace(baseline[0], obligation_code="PRINCIPAL_CHANGED"), *baseline[1:]),
        (baseline[1], baseline[0], *baseline[2:]),
    )
    assert all(component_beneficiary_hash(mutation) != baseline_hash for mutation in mutations)
    with pytest.raises(ValueError, match="exactly five"):
        encode_component_beneficiaries(baseline[:-1])

    zero_vector = canonical_payoff_components(
        principal=90_000_000,
        accrued_interest=0,
        fees=0,
        penalties=0,
        credits=0,
        lender_beneficiary=_bytes(0x99, 20),
        fee_penalty_beneficiary=_bytes(0x77, 20),
    )
    assert len(zero_vector) == 5
    assert tuple(component.amount for component in zero_vector) == (90_000_000, 0, 0, 0, 0)


@pytest.mark.parametrize(
    ("field", "value"),
    (
        ("chain_id", 31338),
        ("payoff_quote_engine", _bytes(0x10, 20)),
        ("refinance_coordinator", _bytes(0x14, 20)),
        ("loan_id", _bytes(0x34, 32)),
        ("loan_account", _bytes(0x45, 20)),
        ("settlement_asset_id", _bytes(0xAB, 32)),
        ("settlement_token", _bytes(0x23, 20)),
        ("lender_beneficiary", _bytes(0x98, 20)),
        ("fee_penalty_beneficiary", _bytes(0x78, 20)),
        ("policy_hash", _bytes(0x57, 32)),
    ),
)
def test_every_route_field_mutation_changes_hash(field: str, value: object) -> None:
    """P9Q-ROUTE-002."""

    policy_hash = payoff_policy_hash(_policy())
    baseline = _route(policy_hash)
    assert settlement_route_hash(
        _replace_reference(baseline, field, value)
    ) != settlement_route_hash(baseline)


@pytest.mark.parametrize(
    ("field", "value"),
    (
        ("payoff_quote_engine", _bytes(0x10, 20)),
        ("chain_id", 31338),
        ("loan_id", _bytes(0x34, 32)),
        ("loan_account", _bytes(0x45, 20)),
        ("policy_hash", _bytes(0x57, 32)),
        ("debt_state_version", 8),
        ("principal", 90_000_001),
        ("accrued_interest", 5_000_001),
        ("fees", 3_000_001),
        ("penalties", 3_000_001),
        ("credits", 1_000_001),
        ("component_beneficiary_hash", _bytes(0xB5, 32)),
        ("net_payoff", 100_000_001),
        ("settlement_asset_id", _bytes(0xAB, 32)),
        ("settlement_token", _bytes(0x23, 20)),
        ("settlement_route_hash", _bytes(0xAE, 32)),
        ("issued_at", 1_800_000_001),
        ("valid_until", 1_800_000_301),
        ("quote_nonce", 2),
    ),
)
def test_every_quote_preimage_field_mutation_changes_id(field: str, value: object) -> None:
    """P9Q-ID-003 and P9Q-ID-004."""

    policy_hash = payoff_policy_hash(_policy())
    component_hash = component_beneficiary_hash(_components())
    route_hash = settlement_route_hash(_route(policy_hash))
    baseline = _identity(policy_hash, component_hash, route_hash)
    assert payoff_quote_id(_replace_reference(baseline, field, value)) != payoff_quote_id(baseline)
