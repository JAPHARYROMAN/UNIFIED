from unified_foundation.payment import (
    Callback,
    PaymentStatus,
    simulate_callback_delivery,
)


def test_duplicate_delivery_creates_one_final_effect() -> None:
    provisional = Callback("event-provisional", PaymentStatus.PROVISIONAL, 1_000)
    result = simulate_callback_delivery(
        payment_units=1_000,
        callbacks=(
            Callback("event-processing", PaymentStatus.PROCESSING, 1_000),
            provisional,
            provisional,
            Callback("event-final", PaymentStatus.FINAL, 1_000),
        ),
        statement_units=1_000,
    )
    assert result.status == PaymentStatus.FINAL
    assert result.raw_ingress_count == 4
    assert result.economic_effect_count == 2
    assert result.replay_count == 1
    assert result.final_units == 1_000
    assert result.reconciliation_difference == 0


def test_forged_stale_mismatched_and_reordered_callbacks_are_quarantined() -> None:
    result = simulate_callback_delivery(
        payment_units=1_000,
        callbacks=(
            Callback(
                "event-forged",
                PaymentStatus.PROCESSING,
                1_000,
                authenticated=False,
            ),
            Callback(
                "event-stale",
                PaymentStatus.PROCESSING,
                1_000,
                unexpired=False,
            ),
            Callback("event-mismatch", PaymentStatus.PROCESSING, 999),
            Callback("event-final-too-early", PaymentStatus.FINAL, 1_000),
        ),
        statement_units=0,
    )
    assert result.status == PaymentStatus.CREATED
    assert result.economic_effect_count == 0
    assert result.quarantine_count == 4


def test_accounting_outage_retry_has_no_partial_state() -> None:
    provisional = Callback("event-provisional", PaymentStatus.PROVISIONAL, 1_000)
    result = simulate_callback_delivery(
        payment_units=1_000,
        callbacks=(
            Callback("event-processing", PaymentStatus.PROCESSING, 1_000),
            provisional,
            provisional,
        ),
        statement_units=0,
        fail_once_event_ids=frozenset({"event-provisional"}),
    )
    assert result.status == PaymentStatus.PROVISIONAL
    assert result.outage_count == 1
    assert result.economic_effect_count == 1
    assert result.provisional_units == 1_000
    assert result.final_units == 0


def test_final_reversal_offsets_both_accounting_stages() -> None:
    result = simulate_callback_delivery(
        payment_units=1_000,
        callbacks=(
            Callback("event-processing", PaymentStatus.PROCESSING, 1_000),
            Callback("event-provisional", PaymentStatus.PROVISIONAL, 1_000),
            Callback("event-final", PaymentStatus.FINAL, 1_000),
            Callback("event-reversal", PaymentStatus.REVERSED, 1_000),
        ),
        statement_units=0,
    )
    assert result.status == PaymentStatus.REVERSED
    assert result.economic_effect_count == 4
    assert result.provisional_units == 0
    assert result.final_units == 0
    assert result.reconciliation_difference == 0


def test_reconciliation_difference_remains_explicit() -> None:
    result = simulate_callback_delivery(
        payment_units=1_000,
        callbacks=(
            Callback("event-processing", PaymentStatus.PROCESSING, 1_000),
            Callback("event-provisional", PaymentStatus.PROVISIONAL, 1_000),
            Callback("event-final", PaymentStatus.FINAL, 1_000),
        ),
        statement_units=900,
    )
    assert result.final_units == 1_000
    assert result.reconciliation_difference == -100
