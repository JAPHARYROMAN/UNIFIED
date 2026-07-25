"""Canonical Phase 9 payoff-quote digest with trusted deployment context."""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Protocol

from Crypto.Hash import keccak

WORD_BYTES = 32
UINT64_LIMIT = 1 << 64
UINT256_LIMIT = 1 << 256
PAYOFF_QUOTE_DOMAIN = "UNIFIED_PAYOFF_QUOTE_V1"
_UNSIGNED_INTEGER = re.compile(r"0|[1-9][0-9]*")


class _IdentifierLike(Protocol):
    value: str


class _AssetIdLike(Protocol):
    value: str


class _MoneyLike(Protocol):
    asset_id: _AssetIdLike
    units: str


class _TimestampLike(Protocol):
    seconds: int
    nanos: int


class _PolicyReferenceLike(Protocol):
    content_hash: bytes


class _DebtSnapshotLike(Protocol):
    loan_id: _IdentifierLike
    loan_account_id: _IdentifierLike
    principal: _MoneyLike
    accrued_interest: _MoneyLike
    capitalized_interest: _MoneyLike
    fees: _MoneyLike
    penalties: _MoneyLike
    recoverable_costs: _MoneyLike
    credits: _MoneyLike
    debt_state_version: int


class _PayoffComponentLike(Protocol):
    amount: _MoneyLike


class PayoffQuoteLike(Protocol):
    quote_id: _IdentifierLike
    loan_id: _IdentifierLike
    debt: _DebtSnapshotLike
    components: list[_PayoffComponentLike]
    gross_payoff: _MoneyLike
    credits: _MoneyLike
    net_payoff: _MoneyLike
    component_beneficiary_hash: bytes
    settlement_route_hash: bytes
    issued_at: _TimestampLike
    valid_until: _TimestampLike
    quote_nonce: int
    quote_policy: _PolicyReferenceLike
    quote_digest: bytes


class TrustedPayoffQuoteContext(tuple[()]):
    """Opaque identity token; all authority remains in the codec closure."""

    __slots__ = ()

    def __new__(cls) -> TrustedPayoffQuoteContext:
        raise TypeError("TrustedPayoffQuoteContext cannot be constructed")

    def __init_subclass__(cls, **kwargs: object) -> None:
        del kwargs
        raise TypeError("TrustedPayoffQuoteContext cannot be subclassed")


@dataclass(frozen=True)
class _PayoffQuoteDigestInput:
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


def _exact_uint(value: int, bits: int, field: str) -> int:
    if value < 0 or value >= 1 << bits:
        raise ValueError(f"{field} is outside uint{bits}")
    return value


def _uint_word(value: int, field: str = "value") -> bytes:
    return _exact_uint(value, 256, field).to_bytes(WORD_BYTES, byteorder="big")


def _address_word(value: bytes, field: str) -> bytes:
    return bytes(12) + _exact_bytes(value, 20, field)


def _dynamic_string_tail(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return _uint_word(len(encoded), "string length") + encoded + bytes((-len(encoded)) % 32)


def _keccak256(value: bytes) -> bytes:
    digest = keccak.new(digest_bits=256)
    digest.update(value)
    return digest.digest()


def _decode_hex(value: str, length: int, field: str) -> bytes:
    if not value.startswith("0x") or len(value) != 2 + length * 2:
        raise ValueError(f"{field} must be canonical 0x-prefixed {length}-byte hex")
    try:
        decoded = bytes.fromhex(value[2:])
    except ValueError as error:
        raise ValueError(f"{field} is not hexadecimal") from error
    return _exact_bytes(decoded, length, field)


_TrustedAuthority = tuple[bytes, int, str, bytes, bytes]


def _money_units(value: _MoneyLike, settlement_asset_value: str, field: str) -> int:
    if value.asset_id.value != settlement_asset_value:
        raise ValueError(f"{field} uses an untrusted settlement asset")
    if _UNSIGNED_INTEGER.fullmatch(value.units) is None:
        raise ValueError(f"{field}.units must be a canonical unsigned integer")
    return _exact_uint(int(value.units), 256, field)


def _timestamp_seconds(value: _TimestampLike, field: str) -> int:
    if value.nanos != 0:
        raise ValueError(f"{field} must have zero nanoseconds")
    return _exact_uint(value.seconds, 64, field)


def _resolve_payoff_quote_digest_input(
    quote: PayoffQuoteLike,
    authority: _TrustedAuthority,
) -> _PayoffQuoteDigestInput:
    """Resolve wire fields using only the closure-held authority tuple."""

    engine, chain_id, settlement_asset_value, settlement_asset_id, settlement_token = authority
    if quote.loan_id.value != quote.debt.loan_id.value:
        raise ValueError("quote and debt snapshot loan IDs differ")

    principal = _money_units(quote.debt.principal, settlement_asset_value, "principal")
    accrued_interest = _money_units(
        quote.debt.accrued_interest, settlement_asset_value, "accrued_interest"
    )
    capitalized_interest = _money_units(
        quote.debt.capitalized_interest, settlement_asset_value, "capitalized_interest"
    )
    fees = _money_units(quote.debt.fees, settlement_asset_value, "fees")
    penalties = _money_units(quote.debt.penalties, settlement_asset_value, "penalties")
    recoverable_costs = _money_units(
        quote.debt.recoverable_costs, settlement_asset_value, "recoverable_costs"
    )
    credits = _money_units(quote.debt.credits, settlement_asset_value, "debt.credits")
    if capitalized_interest != 0 or recoverable_costs != 0:
        raise ValueError(
            "Phase 9 quote V1 requires zero capitalized interest and recoverable costs"
        )

    gross_payoff = _money_units(quote.gross_payoff, settlement_asset_value, "gross_payoff")
    quote_credits = _money_units(quote.credits, settlement_asset_value, "quote.credits")
    net_payoff = _money_units(quote.net_payoff, settlement_asset_value, "net_payoff")
    expected_gross = principal + accrued_interest + fees + penalties
    if gross_payoff != expected_gross or quote_credits != credits:
        raise ValueError("quote gross payoff or credits do not match canonical debt")
    if credits > gross_payoff or net_payoff != gross_payoff - credits:
        raise ValueError("quote net payoff equation is invalid")
    for index, component in enumerate(quote.components):
        _money_units(
            component.amount,
            settlement_asset_value,
            f"components[{index}].amount",
        )

    issued_at = _timestamp_seconds(quote.issued_at, "issued_at")
    valid_until = _timestamp_seconds(quote.valid_until, "valid_until")
    if valid_until <= issued_at:
        raise ValueError("quote validity interval is empty")

    return _PayoffQuoteDigestInput(
        payoff_quote_engine=engine,
        chain_id=chain_id,
        loan_id=_decode_hex(quote.loan_id.value, 32, "loan_id"),
        loan_account=_decode_hex(quote.debt.loan_account_id.value, 20, "loan_account_id"),
        policy_hash=_exact_bytes(quote.quote_policy.content_hash, 32, "quote policy hash"),
        debt_state_version=_exact_uint(
            quote.debt.debt_state_version, 64, "debt_state_version"
        ),
        principal=principal,
        accrued_interest=accrued_interest,
        fees=fees,
        penalties=penalties,
        credits=credits,
        component_beneficiary_hash=_exact_bytes(
            quote.component_beneficiary_hash, 32, "component_beneficiary_hash"
        ),
        net_payoff=net_payoff,
        settlement_asset_id=settlement_asset_id,
        settlement_token=settlement_token,
        settlement_route_hash=_exact_bytes(
            quote.settlement_route_hash, 32, "settlement_route_hash"
        ),
        issued_at=issued_at,
        valid_until=valid_until,
        quote_nonce=_exact_uint(quote.quote_nonce, 64, "quote_nonce"),
    )


def _encode_payoff_quote_preimage(value: _PayoffQuoteDigestInput) -> bytes:
    static_words = (
        _address_word(value.payoff_quote_engine, "payoff_quote_engine"),
        _uint_word(value.chain_id, "chain_id"),
        _exact_bytes(value.loan_id, 32, "loan_id"),
        _address_word(value.loan_account, "loan_account"),
        _exact_bytes(value.policy_hash, 32, "policy_hash"),
        _uint_word(_exact_uint(value.debt_state_version, 64, "debt_state_version")),
        _uint_word(value.principal, "principal"),
        _uint_word(value.accrued_interest, "accrued_interest"),
        _uint_word(value.fees, "fees"),
        _uint_word(value.penalties, "penalties"),
        _uint_word(value.credits, "credits"),
        _exact_bytes(value.component_beneficiary_hash, 32, "component_beneficiary_hash"),
        _uint_word(value.net_payoff, "net_payoff"),
        _exact_bytes(value.settlement_asset_id, 32, "settlement_asset_id"),
        _address_word(value.settlement_token, "settlement_token"),
        _exact_bytes(value.settlement_route_hash, 32, "settlement_route_hash"),
        _uint_word(_exact_uint(value.issued_at, 64, "issued_at")),
        _uint_word(_exact_uint(value.valid_until, 64, "valid_until")),
        _uint_word(_exact_uint(value.quote_nonce, 64, "quote_nonce")),
    )
    head_size = (len(static_words) + 1) * WORD_BYTES
    return _uint_word(head_size, "domain offset") + b"".join(static_words) + _dynamic_string_tail(
        PAYOFF_QUOTE_DOMAIN
    )


_ContextGetter = Callable[[], TrustedPayoffQuoteContext]
_DigestFunction = Callable[[PayoffQuoteLike, TrustedPayoffQuoteContext], bytes]


def _build_trusted_payoff_quote_codec() -> tuple[
    _ContextGetter,
    _DigestFunction,
    _DigestFunction,
]:
    singleton = tuple.__new__(TrustedPayoffQuoteContext, ())
    authority: _TrustedAuthority = (
        bytes([0x11]) * 20,
        31337,
        "asset:phase9:p9unit",
        bytes([0xAA]) * 32,
        bytes([0x22]) * 20,
    )

    def canonical_context() -> TrustedPayoffQuoteContext:
        """Return the fixed cross-language test fixture; this is not a value factory."""

        return singleton

    def resolve_authority(context: TrustedPayoffQuoteContext) -> _TrustedAuthority:
        if context is not singleton or type(context) is not TrustedPayoffQuoteContext:
            raise TypeError("payoff quote context is not the canonical opaque singleton")
        return authority

    def digest(
        quote: PayoffQuoteLike,
        context: TrustedPayoffQuoteContext,
    ) -> bytes:
        resolved = _resolve_payoff_quote_digest_input(quote, resolve_authority(context))
        return _keccak256(_encode_payoff_quote_preimage(resolved))

    def validate(
        quote: PayoffQuoteLike,
        context: TrustedPayoffQuoteContext,
    ) -> bytes:
        quote_digest = digest(quote, context)
        if quote.quote_digest != quote_digest:
            raise ValueError("quote_digest does not match the trusted-context preimage")
        if _decode_hex(quote.quote_id.value, 32, "quote_id") != quote_digest:
            raise ValueError("quote_id does not match the trusted-context preimage")
        return quote_digest

    return canonical_context, digest, validate


(
    canonical_golden_payoff_quote_context,
    payoff_quote_digest,
    validate_payoff_quote_digest,
) = _build_trusted_payoff_quote_codec()
del _build_trusted_payoff_quote_codec
