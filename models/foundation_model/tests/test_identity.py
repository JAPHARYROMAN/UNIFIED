from dataclasses import replace

import pytest
from unified_foundation.identity import (
    ACTIVATION_STEPS,
    AtomicActivationState,
    ExposureBook,
    scoped_uniqueness_key,
    simulate_atomic_activation,
)

NOW = 1_900_000_000
SUBJECT = "commitment:randomized:subject-1"
ASSET = "asset:synthetic"


def test_same_subject_multiple_wallets_share_one_limit() -> None:
    book = ExposureBook()
    book.reserve(
        loan_id="loan-1",
        decision_id="decision-1",
        subject_commitment=SUBJECT,
        account_id="wallet-1",
        asset_id=ASSET,
        amount=60,
        decision_limit=100,
        expires_at=NOW + 900,
        now=NOW,
    )
    book.activate("loan-1", now=NOW)
    with pytest.raises(ValueError, match="limit"):
        book.reserve(
            loan_id="loan-2",
            decision_id="decision-2",
            subject_commitment=SUBJECT,
            account_id="wallet-2",
            asset_id=ASSET,
            amount=50,
            decision_limit=100,
            expires_at=NOW + 900,
            now=NOW,
        )
    assert book.totals(SUBJECT, ASSET) == (0, 60)


def test_pending_reservation_counts_and_expiry_restores_capacity() -> None:
    book = ExposureBook()
    book.reserve(
        loan_id="loan-1",
        decision_id="decision-1",
        subject_commitment=SUBJECT,
        account_id="wallet-1",
        asset_id=ASSET,
        amount=100,
        decision_limit=100,
        expires_at=NOW + 900,
        now=NOW,
    )
    assert book.recognized(SUBJECT, ASSET) == 100
    with pytest.raises(ValueError, match="activate"):
        book.activate("loan-1", now=NOW + 900)
    book.cancel_expired("loan-1", now=NOW + 900)
    assert book.recognized(SUBJECT, ASSET) == 0


def test_active_release_requires_terminal_zero_debt() -> None:
    book = ExposureBook()
    book.reserve(
        loan_id="loan-1",
        decision_id="decision-1",
        subject_commitment=SUBJECT,
        account_id="wallet-1",
        asset_id=ASSET,
        amount=70,
        decision_limit=100,
        expires_at=NOW + 900,
        now=NOW,
    )
    book.activate("loan-1", now=NOW)
    with pytest.raises(ValueError, match="release"):
        book.release("loan-1", terminal=False, outstanding=0)
    with pytest.raises(ValueError, match="release"):
        book.release("loan-1", terminal=True, outstanding=1)
    book.release("loan-1", terminal=True, outstanding=0)
    assert book.recognized(SUBJECT, ASSET) == 0


def test_uniqueness_claim_is_explicitly_scoped() -> None:
    first = scoped_uniqueness_key("provider-1", "scope-1", 1, SUBJECT)
    next_epoch = scoped_uniqueness_key("provider-1", "scope-1", 2, SUBJECT)
    another_provider = scoped_uniqueness_key("provider-2", "scope-1", 1, SUBJECT)
    assert first != next_epoch
    assert first != another_provider


def test_underwritten_activation_commits_every_step_or_none() -> None:
    initial = AtomicActivationState(
        reserved=20,
        active=30,
        loan_registered=False,
        offer_consumed=False,
        tender_fulfilled=False,
        funding_units=0,
        lender_units=2_000,
        borrower_units=100,
        fee_units=0,
    )
    for step in ACTIVATION_STEPS:
        assert (
            simulate_atomic_activation(initial, principal=1_000, fee=10, fail_at=step)
            == initial
        )

    activated = simulate_atomic_activation(initial, principal=1_000, fee=10)
    assert activated.reserved == 20
    assert activated.active == 1_030
    assert activated.loan_registered
    assert activated.offer_consumed
    assert activated.tender_fulfilled
    assert activated.funding_units == 1_000
    assert activated.lender_units == 1_000
    assert activated.borrower_units == 1_090
    assert activated.fee_units == 10
    assert (
        activated.lender_units + activated.borrower_units + activated.fee_units
        == initial.lender_units + initial.borrower_units + initial.fee_units
    )


def test_underwritten_activation_replay_and_short_funding_fail_closed() -> None:
    initial = AtomicActivationState(
        reserved=0,
        active=0,
        loan_registered=False,
        offer_consumed=False,
        tender_fulfilled=False,
        funding_units=0,
        lender_units=999,
        borrower_units=0,
        fee_units=0,
    )
    assert simulate_atomic_activation(initial, principal=1_000, fee=10) == initial
    activated = simulate_atomic_activation(
        replace(initial, lender_units=2_000), principal=1_000, fee=10
    )
    with pytest.raises(ValueError, match="invalid"):
        simulate_atomic_activation(activated, principal=1_000, fee=10)
