import unified_foundation.phase9_quote_codec as quote_codec
from google.protobuf.timestamp_pb2 import Timestamp  # type: ignore[import-untyped]
from unified.v1 import refinance_pb2, types_pb2  # type: ignore[import-not-found]
from unified_foundation.phase9_quote_codec import (
    TrustedPayoffQuoteContext,
    canonical_golden_payoff_quote_context,
    payoff_quote_digest,
    validate_payoff_quote_digest,
)

EXPECTED_DIGEST = "632cc3b4bcf2cfcddcf9699eb7f9eef6f946fa7f4ed392f4767925354f8a2058"
ASSET_VALUE = "asset:phase9:p9unit"


def _bytes(value: int, length: int) -> bytes:
    return bytes([value]) * length


def _money(units: int) -> types_pb2.Money:
    return types_pb2.Money(asset_id=types_pb2.AssetId(value=ASSET_VALUE), units=str(units))


def _quote() -> refinance_pb2.PayoffQuote:
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


def _context() -> TrustedPayoffQuoteContext:
    return canonical_golden_payoff_quote_context()


def test_python_payoff_quote_digest_matches_cross_language_golden() -> None:
    quote = _quote()
    digest = payoff_quote_digest(quote, _context())
    assert digest.hex() == EXPECTED_DIGEST
    quote.quote_id.value = "0x" + digest.hex()
    quote.quote_digest = digest
    assert validate_payoff_quote_digest(quote, _context()) == digest


def test_payoff_quote_rejects_wire_asset_substitution() -> None:
    quote = _quote()
    quote.net_payoff.asset_id.value = "asset:caller:substitute"
    try:
        payoff_quote_digest(quote, _context())
    except ValueError as error:
        assert "untrusted settlement asset" in str(error)
    else:
        raise AssertionError("wire asset substitution was accepted")


def test_payoff_quote_context_is_one_empty_slot_singleton() -> None:
    context = _context()
    assert context is canonical_golden_payoff_quote_context()
    assert TrustedPayoffQuoteContext.__slots__ == ()
    assert not hasattr(context, "__dict__")

    try:
        TrustedPayoffQuoteContext()
    except TypeError as error:
        assert "cannot be constructed" in str(error)
    else:
        raise AssertionError("direct trusted-context construction was accepted")

    try:
        object.__setattr__(context, "payoff_quote_engine", _bytes(0x12, 20))
    except AttributeError as error:
        assert "attribute" in str(error)
    else:
        raise AssertionError("object.__setattr__ mutated the opaque context")

    class EmptyContext:
        __slots__ = ()

    try:
        object.__setattr__(context, "__class__", EmptyContext)
    except TypeError as error:
        assert "layout differs" in str(error) or "mutable types" in str(error)
    else:
        raise AssertionError("object.__setattr__ replaced the opaque context class")

    assert payoff_quote_digest(_quote(), context).hex() == EXPECTED_DIGEST


def test_payoff_quote_rejects_alternate_source_and_object_new_forgery() -> None:
    class CallerRegistrySnapshot:
        payoff_quote_engine = _bytes(0x12, 20)
        chain_id = 31338
        settlement_asset_value = "asset:caller:substitute"
        settlement_asset_id = _bytes(0xBB, 32)
        settlement_token = _bytes(0x23, 20)

    try:
        object.__new__(TrustedPayoffQuoteContext)
    except TypeError as error:
        assert "not safe" in str(error)
    else:
        raise AssertionError("object.__new__ forged an opaque context")

    forged = tuple.__new__(TrustedPayoffQuoteContext, ())
    try:
        payoff_quote_digest(_quote(), forged)
    except TypeError as error:
        assert "canonical opaque singleton" in str(error)
    else:
        raise AssertionError("object.__new__ context forgery was accepted")

    try:
        payoff_quote_digest(
            _quote(),
            CallerRegistrySnapshot(),  # type: ignore[arg-type]
        )
    except TypeError as error:
        assert "canonical opaque singleton" in str(error)
    else:
        raise AssertionError("caller engine/chain/asset/token source was accepted")


def test_payoff_quote_rejects_subclass_and_private_mint_lookup() -> None:
    try:
        class ForgedPayoffQuoteContext(TrustedPayoffQuoteContext):
            pass
    except TypeError as error:
        assert "cannot be subclassed" in str(error)
    else:
        raise AssertionError("TrustedPayoffQuoteContext was subclassable")

    forbidden_names = (
        "_AUTHENTICATED_REGISTRY_CAPABILITY",
        "_AuthenticatedRegistrySnapshot",
        "_context_from_authenticated_registry",
        "_MINTED_CONTEXTS",
        "_build_trusted_payoff_quote_codec",
    )
    assert all(not hasattr(quote_codec, name) for name in forbidden_names)
    assert not any(
        token in name.casefold()
        for name in vars(quote_codec)
        for token in ("capability", "minted", "_mint")
    )
