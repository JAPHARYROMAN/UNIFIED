"""Independent ABI reference encoders for the Phase 9 payoff commitments."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from Crypto.Hash import keccak

WORD_BYTES = 32
UINT64_LIMIT = 1 << 64
UINT256_LIMIT = 1 << 256

PAYOFF_POLICY_DOMAIN = "UNIFIED_PAYOFF_POLICY_V1"
PAYOFF_COMPONENTS_DOMAIN = "UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1"
PAYOFF_ROUTE_DOMAIN = "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1"
PAYOFF_QUOTE_DOMAIN = "UNIFIED_PAYOFF_QUOTE_V1"


@dataclass(frozen=True)
class PayoffPolicyReference:
    chain_id: int
    payoff_quote_engine: bytes
    quote_policy_registry: bytes
    loan_id: bytes
    loan_account: bytes
    bound_policy_set_hash: bytes
    fee_penalty_beneficiary: bytes
    settlement_asset_id: bytes
    settlement_token: bytes
    maximum_validity: int


@dataclass(frozen=True)
class PayoffComponentReference:
    kind: int
    amount: int
    beneficiary: bytes
    obligation_code: str


@dataclass(frozen=True)
class SettlementRouteReference:
    chain_id: int
    payoff_quote_engine: bytes
    refinance_coordinator: bytes
    loan_id: bytes
    loan_account: bytes
    settlement_asset_id: bytes
    settlement_token: bytes
    lender_beneficiary: bytes
    fee_penalty_beneficiary: bytes
    policy_hash: bytes


@dataclass(frozen=True)
class PayoffQuoteIdentityReference:
    payoff_quote_engine: bytes
    chain_id: int
    loan_id: bytes
    loan_account: bytes
    policy_hash: bytes
    debt_state_version: int
    principal: int
    accrued_interest: int
    fees: int
    penalties: int
    credits: int
    component_beneficiary_hash: bytes
    net_payoff: int
    settlement_asset_id: bytes
    settlement_token: bytes
    settlement_route_hash: bytes
    issued_at: int
    valid_until: int
    quote_nonce: int


def _exact_bytes(value: bytes, length: int, field: str) -> bytes:
    if len(value) != length:
        raise ValueError(f"{field} must contain {length} bytes")
    return value


def _uint_word(value: int, bits: int, field: str) -> bytes:
    if value < 0 or value >= 1 << bits:
        raise ValueError(f"{field} is outside uint{bits}")
    return value.to_bytes(WORD_BYTES, byteorder="big")


def _address_word(value: bytes, field: str) -> bytes:
    return bytes(12) + _exact_bytes(value, 20, field)


def _string_tail(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return _uint_word(len(encoded), 256, "string length") + encoded + bytes((-len(encoded)) % 32)


def _keccak256(value: bytes) -> bytes:
    digest = keccak.new(digest_bits=256)
    digest.update(value)
    return digest.digest()


def _domain_and_static_words(domain: str, static_words: Sequence[bytes]) -> bytes:
    head_words = len(static_words) + 1
    return (
        _uint_word(head_words * WORD_BYTES, 256, "domain offset")
        + b"".join(_exact_bytes(word, WORD_BYTES, "static ABI word") for word in static_words)
        + _string_tail(domain)
    )


def encode_payoff_policy(reference: PayoffPolicyReference) -> bytes:
    """Encode the exact ``UNIFIED_PAYOFF_POLICY_V1`` Solidity preimage."""

    return _domain_and_static_words(
        PAYOFF_POLICY_DOMAIN,
        (
            _uint_word(reference.chain_id, 256, "chain_id"),
            _address_word(reference.payoff_quote_engine, "payoff_quote_engine"),
            _address_word(reference.quote_policy_registry, "quote_policy_registry"),
            _exact_bytes(reference.loan_id, 32, "loan_id"),
            _address_word(reference.loan_account, "loan_account"),
            _exact_bytes(reference.bound_policy_set_hash, 32, "bound_policy_set_hash"),
            _address_word(reference.fee_penalty_beneficiary, "fee_penalty_beneficiary"),
            _exact_bytes(reference.settlement_asset_id, 32, "settlement_asset_id"),
            _address_word(reference.settlement_token, "settlement_token"),
            _uint_word(reference.maximum_validity, 64, "maximum_validity"),
        ),
    )


def payoff_policy_hash(reference: PayoffPolicyReference) -> bytes:
    return _keccak256(encode_payoff_policy(reference))


def canonical_payoff_components(
    *,
    principal: int,
    accrued_interest: int,
    fees: int,
    penalties: int,
    credits: int,
    lender_beneficiary: bytes,
    fee_penalty_beneficiary: bytes,
) -> tuple[PayoffComponentReference, ...]:
    """Build the mandatory five-component V1 vector, retaining zero amounts."""

    return (
        PayoffComponentReference(1, principal, lender_beneficiary, "PRINCIPAL"),
        PayoffComponentReference(
            2, accrued_interest, lender_beneficiary, "ACCRUED_INTEREST"
        ),
        PayoffComponentReference(4, fees, fee_penalty_beneficiary, "FEE"),
        PayoffComponentReference(5, penalties, fee_penalty_beneficiary, "PENALTY"),
        PayoffComponentReference(
            7, credits, fee_penalty_beneficiary, "FEE_PENALTY_CREDIT"
        ),
    )


def _encode_component(component: PayoffComponentReference) -> bytes:
    string_tail = _string_tail(component.obligation_code)
    return b"".join(
        (
            _uint_word(component.kind, 8, "component.kind"),
            _uint_word(component.amount, 256, "component.amount"),
            _address_word(component.beneficiary, "component.beneficiary"),
            _uint_word(4 * WORD_BYTES, 256, "component obligation-code offset"),
            string_tail,
        )
    )


def encode_component_beneficiaries(
    components: Sequence[PayoffComponentReference],
) -> bytes:
    """Encode ``abi.encode(domain, PayoffComponentV2[])`` for exactly five entries."""

    if len(components) != 5:
        raise ValueError("the V1 payoff component vector must contain exactly five entries")
    encoded_components = tuple(_encode_component(component) for component in components)
    component_head_size = len(components) * WORD_BYTES
    offsets: list[bytes] = []
    next_offset = component_head_size
    for encoded_component in encoded_components:
        offsets.append(_uint_word(next_offset, 256, "component offset"))
        next_offset += len(encoded_component)
    array_tail = (
        _uint_word(len(components), 256, "component count")
        + b"".join(offsets)
        + b"".join(encoded_components)
    )
    domain_tail = _string_tail(PAYOFF_COMPONENTS_DOMAIN)
    return b"".join(
        (
            _uint_word(2 * WORD_BYTES, 256, "component domain offset"),
            _uint_word(2 * WORD_BYTES + len(domain_tail), 256, "component array offset"),
            domain_tail,
            array_tail,
        )
    )


def component_beneficiary_hash(components: Sequence[PayoffComponentReference]) -> bytes:
    return _keccak256(encode_component_beneficiaries(components))


def encode_settlement_route(reference: SettlementRouteReference) -> bytes:
    """Encode the exact ``UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1`` preimage."""

    return _domain_and_static_words(
        PAYOFF_ROUTE_DOMAIN,
        (
            _uint_word(reference.chain_id, 256, "chain_id"),
            _address_word(reference.payoff_quote_engine, "payoff_quote_engine"),
            _address_word(reference.refinance_coordinator, "refinance_coordinator"),
            _exact_bytes(reference.loan_id, 32, "loan_id"),
            _address_word(reference.loan_account, "loan_account"),
            _exact_bytes(reference.settlement_asset_id, 32, "settlement_asset_id"),
            _address_word(reference.settlement_token, "settlement_token"),
            _address_word(reference.lender_beneficiary, "lender_beneficiary"),
            _address_word(reference.fee_penalty_beneficiary, "fee_penalty_beneficiary"),
            _exact_bytes(reference.policy_hash, 32, "policy_hash"),
        ),
    )


def settlement_route_hash(reference: SettlementRouteReference) -> bytes:
    return _keccak256(encode_settlement_route(reference))


def encode_payoff_quote_identity(reference: PayoffQuoteIdentityReference) -> bytes:
    """Encode the exact ADR 0019 ``UNIFIED_PAYOFF_QUOTE_V1`` preimage."""

    return _domain_and_static_words(
        PAYOFF_QUOTE_DOMAIN,
        (
            _address_word(reference.payoff_quote_engine, "payoff_quote_engine"),
            _uint_word(reference.chain_id, 256, "chain_id"),
            _exact_bytes(reference.loan_id, 32, "loan_id"),
            _address_word(reference.loan_account, "loan_account"),
            _exact_bytes(reference.policy_hash, 32, "policy_hash"),
            _uint_word(reference.debt_state_version, 64, "debt_state_version"),
            _uint_word(reference.principal, 256, "principal"),
            _uint_word(reference.accrued_interest, 256, "accrued_interest"),
            _uint_word(reference.fees, 256, "fees"),
            _uint_word(reference.penalties, 256, "penalties"),
            _uint_word(reference.credits, 256, "credits"),
            _exact_bytes(
                reference.component_beneficiary_hash, 32, "component_beneficiary_hash"
            ),
            _uint_word(reference.net_payoff, 256, "net_payoff"),
            _exact_bytes(reference.settlement_asset_id, 32, "settlement_asset_id"),
            _address_word(reference.settlement_token, "settlement_token"),
            _exact_bytes(reference.settlement_route_hash, 32, "settlement_route_hash"),
            _uint_word(reference.issued_at, 64, "issued_at"),
            _uint_word(reference.valid_until, 64, "valid_until"),
            _uint_word(reference.quote_nonce, 64, "quote_nonce"),
        ),
    )


def payoff_quote_id(reference: PayoffQuoteIdentityReference) -> bytes:
    return _keccak256(encode_payoff_quote_identity(reference))
