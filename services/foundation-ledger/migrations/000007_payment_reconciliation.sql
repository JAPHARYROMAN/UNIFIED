BEGIN;

INSERT INTO chart_account (
    account_code, account_name, account_class, normal_side, specification_version
) VALUES
    ('1100', 'Cash and Fiat at Banks', 'ASSET', 'DEBIT', 'v0.1'),
    ('1120', 'Card Processor Receivable', 'ASSET', 'DEBIT', 'v0.1'),
    ('9120', 'Unallocated Loan Payment', 'SUSPENSE', 'CREDIT', 'v0.1'),
    ('9130', 'Pending Card Settlement', 'SUSPENSE', 'DEBIT', 'v0.1'),
    ('9140', 'Pending Bank Settlement', 'SUSPENSE', 'DEBIT', 'v0.1');

CREATE TABLE payment_intent (
    payment_id text PRIMARY KEY,
    legal_entity_id text NOT NULL,
    idempotency_key text NOT NULL,
    correlation_id text NOT NULL,
    payer_reference text NOT NULL,
    loan_id text,
    provider_id text NOT NULL,
    rail text NOT NULL CHECK (rail IN ('BANK', 'CARD')),
    purpose text NOT NULL,
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    expires_at timestamptz NOT NULL,
    schema_version integer NOT NULL CHECK (schema_version > 0),
    created_at timestamptz NOT NULL,
    UNIQUE (legal_entity_id, idempotency_key),
    UNIQUE (payment_id, provider_id, asset_id, units),
    CHECK (expires_at > created_at)
);

-- Phase 7A stores only bounded synthetic raw payloads. A production raw-provider
-- store requires a separately approved restricted-data design.
CREATE TABLE provider_callback_ingress (
    ingress_id text PRIMARY KEY,
    provider_id text NOT NULL,
    provider_event_id text NOT NULL,
    raw_payload bytea NOT NULL CHECK (
        octet_length(raw_payload) > 0
        AND octet_length(raw_payload) <= 65536
    ),
    raw_payload_hash text NOT NULL,
    signature_hash text NOT NULL,
    received_at timestamptz NOT NULL,
    UNIQUE (provider_id, provider_event_id, raw_payload_hash, signature_hash, received_at)
);

CREATE TABLE payment_state_event (
    event_id text PRIMARY KEY,
    payment_id text NOT NULL REFERENCES payment_intent(payment_id),
    provider_id text NOT NULL,
    provider_event_id text NOT NULL,
    aggregate_version bigint NOT NULL CHECK (aggregate_version > 1),
    from_status text NOT NULL CHECK (
        from_status IN ('CREATED', 'PROCESSING', 'PROVISIONAL', 'FINAL')
    ),
    to_status text NOT NULL CHECK (
        to_status IN ('PROCESSING', 'PROVISIONAL', 'FINAL', 'FAILED', 'REVERSED')
    ),
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    evidence_hash text NOT NULL,
    journal_ids text[] NOT NULL DEFAULT '{}',
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    FOREIGN KEY (payment_id, provider_id, asset_id, units)
        REFERENCES payment_intent(payment_id, provider_id, asset_id, units),
    UNIQUE (provider_id, provider_event_id),
    UNIQUE (payment_id, aggregate_version),
    CHECK (
        (from_status = 'CREATED' AND to_status IN ('PROCESSING', 'FAILED'))
        OR (from_status = 'PROCESSING' AND to_status IN ('PROVISIONAL', 'FAILED'))
        OR (from_status = 'PROVISIONAL' AND to_status IN ('FINAL', 'REVERSED'))
        OR (from_status = 'FINAL' AND to_status = 'REVERSED')
    ),
    CHECK (
        (to_status IN ('PROCESSING', 'FAILED') AND cardinality(journal_ids) = 0)
        OR (to_status IN ('PROVISIONAL', 'FINAL') AND cardinality(journal_ids) = 1)
        OR (to_status = 'REVERSED' AND cardinality(journal_ids) BETWEEN 1 AND 2)
    )
);

CREATE TABLE payment_callback_quarantine (
    quarantine_id text PRIMARY KEY,
    provider_id text NOT NULL,
    provider_event_id text NOT NULL,
    payment_id text,
    raw_payload_hash text NOT NULL,
    evidence_hash text,
    reason_code text NOT NULL,
    owner text NOT NULL,
    received_at timestamptz NOT NULL,
    resolution_deadline timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (resolution_deadline > received_at)
);

CREATE TABLE payment_callback_quarantine_resolution (
    resolution_id text PRIMARY KEY,
    quarantine_id text NOT NULL UNIQUE
        REFERENCES payment_callback_quarantine(quarantine_id),
    evidence_hash text NOT NULL,
    resolved_by text NOT NULL,
    resolved_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE payment_reconciliation_run (
    run_id text PRIMARY KEY,
    provider_id text NOT NULL,
    asset_id text NOT NULL,
    as_of timestamptz NOT NULL,
    provider_snapshot_hash text NOT NULL,
    ledger_snapshot_hash text NOT NULL,
    expected_units numeric(78, 0) NOT NULL CHECK (expected_units >= 0),
    observed_units numeric(78, 0) NOT NULL CHECK (observed_units >= 0),
    difference_units numeric(78, 0) NOT NULL,
    unmatched_items integer NOT NULL CHECK (unmatched_items >= 0),
    status text NOT NULL CHECK (status IN ('MATCHED', 'EXCEPTION')),
    owner text NOT NULL,
    resolution_deadline timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (run_id, provider_id, asset_id),
    CHECK (resolution_deadline > as_of),
    CHECK (
        (difference_units = 0 AND unmatched_items = 0 AND status = 'MATCHED')
        OR (
            (difference_units <> 0 OR unmatched_items > 0)
            AND status = 'EXCEPTION'
        )
    )
);

CREATE TABLE payment_provider_statement_entry (
    run_id text NOT NULL,
    entry_id text NOT NULL,
    provider_id text NOT NULL,
    provider_reference text NOT NULL,
    payment_id text NOT NULL,
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    statement_kind text NOT NULL CHECK (statement_kind IN ('SETTLED', 'REVERSED')),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (run_id, entry_id),
    FOREIGN KEY (run_id, provider_id, asset_id)
        REFERENCES payment_reconciliation_run(run_id, provider_id, asset_id)
);

CREATE TABLE payment_reconciliation_exception (
    exception_id text PRIMARY KEY,
    run_id text NOT NULL UNIQUE REFERENCES payment_reconciliation_run(run_id),
    provider_id text NOT NULL,
    asset_id text NOT NULL,
    difference_units numeric(78, 0) NOT NULL,
    unmatched_items integer NOT NULL CHECK (unmatched_items >= 0),
    reason_code text NOT NULL,
    owner text NOT NULL,
    detected_at timestamptz NOT NULL,
    resolution_deadline timestamptz NOT NULL,
    FOREIGN KEY (run_id, provider_id, asset_id)
        REFERENCES payment_reconciliation_run(run_id, provider_id, asset_id),
    CHECK (resolution_deadline > detected_at),
    CHECK (difference_units <> 0 OR unmatched_items > 0)
);

CREATE TABLE payment_reconciliation_resolution (
    resolution_id text PRIMARY KEY,
    exception_id text NOT NULL UNIQUE
        REFERENCES payment_reconciliation_exception(exception_id),
    evidence_hash text NOT NULL,
    resolution_journal_id text REFERENCES journal(journal_id),
    resolved_by text NOT NULL,
    resolved_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX payment_state_by_payment
    ON payment_state_event (payment_id, aggregate_version);

CREATE INDEX payment_quarantine_by_deadline
    ON payment_callback_quarantine (resolution_deadline, owner);

CREATE INDEX payment_reconciliation_by_provider_asset
    ON payment_reconciliation_run (provider_id, asset_id, as_of);

CREATE TRIGGER payment_intent_immutable
BEFORE UPDATE OR DELETE ON payment_intent
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER provider_callback_ingress_immutable
BEFORE UPDATE OR DELETE ON provider_callback_ingress
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_state_event_immutable
BEFORE UPDATE OR DELETE ON payment_state_event
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_callback_quarantine_immutable
BEFORE UPDATE OR DELETE ON payment_callback_quarantine
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_callback_quarantine_resolution_immutable
BEFORE UPDATE OR DELETE ON payment_callback_quarantine_resolution
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_reconciliation_run_immutable
BEFORE UPDATE OR DELETE ON payment_reconciliation_run
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_provider_statement_entry_immutable
BEFORE UPDATE OR DELETE ON payment_provider_statement_entry
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_reconciliation_exception_immutable
BEFORE UPDATE OR DELETE ON payment_reconciliation_exception
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_reconciliation_resolution_immutable
BEFORE UPDATE OR DELETE ON payment_reconciliation_resolution
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;
