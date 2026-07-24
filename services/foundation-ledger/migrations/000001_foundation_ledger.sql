BEGIN;

CREATE TABLE command_log (
    command_id text PRIMARY KEY,
    command_type text NOT NULL,
    schema_version text NOT NULL,
    idempotency_key text NOT NULL,
    correlation_id text NOT NULL,
    payload jsonb NOT NULL,
    payload_hash text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (command_type, idempotency_key)
);

CREATE TABLE event_log (
    event_id text PRIMARY KEY,
    event_type text NOT NULL,
    schema_version text NOT NULL,
    authority_class text NOT NULL,
    aggregate_id text NOT NULL,
    aggregate_version bigint NOT NULL CHECK (aggregate_version > 0),
    correlation_id text NOT NULL,
    causation_id text NOT NULL,
    payload jsonb NOT NULL,
    payload_hash text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (aggregate_id, aggregate_version)
);

CREATE TABLE journal (
    journal_id text PRIMARY KEY,
    legal_entity_id text NOT NULL,
    book_id text NOT NULL,
    source_system text NOT NULL,
    idempotency_key text NOT NULL,
    correlation_id text NOT NULL,
    evidence_hash text NOT NULL,
    effective_at timestamptz NOT NULL,
    posted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    status text NOT NULL CHECK (status = 'POSTED'),
    UNIQUE (legal_entity_id, source_system, idempotency_key)
);

CREATE TABLE journal_entry (
    journal_id text NOT NULL REFERENCES journal(journal_id),
    line_number integer NOT NULL CHECK (line_number > 0),
    account_code text NOT NULL,
    side text NOT NULL CHECK (side IN ('DEBIT', 'CREDIT')),
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    party_id text,
    PRIMARY KEY (journal_id, line_number)
);

CREATE VIEW journal_balance AS
SELECT
    journal_id,
    asset_id,
    SUM(CASE WHEN side = 'DEBIT' THEN units ELSE 0 END) AS debit_units,
    SUM(CASE WHEN side = 'CREDIT' THEN units ELSE 0 END) AS credit_units
FROM journal_entry
GROUP BY journal_id, asset_id;

CREATE FUNCTION reject_posted_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'posted foundation ledger history is immutable';
END;
$$;

CREATE TRIGGER journal_immutable
BEFORE UPDATE OR DELETE ON journal
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER journal_entry_immutable
BEFORE UPDATE OR DELETE ON journal_entry
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;

