import pytest
from unified_foundation.identity import ExposureBook, scoped_uniqueness_key

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
