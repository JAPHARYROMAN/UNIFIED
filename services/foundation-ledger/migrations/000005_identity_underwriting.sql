BEGIN;

CREATE TABLE identity_credit_control_event (
    event_id text PRIMARY KEY,
    record_type text NOT NULL CHECK (record_type IN (
        'IDENTITY_PROVIDER_REGISTERED',
        'IDENTITY_PROVIDER_STATUS_CHANGED',
        'IDENTITY_CREDENTIAL_SCHEMA_REGISTERED',
        'IDENTITY_CREDENTIAL_SCHEMA_STATUS_CHANGED',
        'IDENTITY_CREDENTIAL_ISSUED',
        'IDENTITY_CREDENTIAL_REVOKED',
        'CREDIT_DECISION_ISSUED',
        'CREDIT_DECISION_REVOKED',
        'CREDIT_EXPOSURE_RESERVED',
        'CREDIT_EXPOSURE_ACTIVATED',
        'CREDIT_EXPOSURE_RELEASED',
        'CREDIT_EXPOSURE_CANCELLED'
    )),
    record_id text NOT NULL,
    sequence bigint NOT NULL CHECK (sequence > 0),
    provider_id text,
    schema_id text,
    credential_id text,
    decision_id text,
    loan_id text,
    subject_commitment text,
    asset_id text,
    units numeric(78, 0) CHECK (units > 0),
    evidence_hash text NOT NULL,
    finality text NOT NULL CHECK (finality = 'FINAL'),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (record_type, record_id, sequence),
    CONSTRAINT no_obvious_raw_identity_columns CHECK (
        subject_commitment IS NULL OR length(subject_commitment) >= 32
    ),
    CONSTRAINT identity_evidence_complete CHECK (
        (record_type NOT LIKE 'IDENTITY_PROVIDER_%' OR provider_id IS NOT NULL)
        AND (
            record_type NOT LIKE 'IDENTITY_CREDENTIAL_SCHEMA_%'
            OR (provider_id IS NOT NULL AND schema_id IS NOT NULL)
        )
        AND (
            record_type NOT LIKE 'IDENTITY_CREDENTIAL_%'
            OR record_type LIKE 'IDENTITY_CREDENTIAL_SCHEMA_%'
            OR (credential_id IS NOT NULL AND subject_commitment IS NOT NULL)
        )
    ),
    CONSTRAINT decision_evidence_complete CHECK (
        record_type NOT LIKE 'CREDIT_DECISION_%'
        OR (
            decision_id IS NOT NULL
            AND credential_id IS NOT NULL
            AND subject_commitment IS NOT NULL
        )
    ),
    CONSTRAINT exposure_evidence_complete CHECK (
        record_type NOT LIKE 'CREDIT_EXPOSURE_%'
        OR (
            decision_id IS NOT NULL
            AND loan_id IS NOT NULL
            AND subject_commitment IS NOT NULL
            AND asset_id IS NOT NULL
            AND units IS NOT NULL
        )
    )
);

CREATE INDEX identity_control_by_credential
    ON identity_credit_control_event (credential_id, sequence)
    WHERE credential_id IS NOT NULL;

CREATE INDEX credit_control_by_decision
    ON identity_credit_control_event (decision_id, sequence)
    WHERE decision_id IS NOT NULL;

CREATE INDEX exposure_control_by_subject_asset
    ON identity_credit_control_event (subject_commitment, asset_id, occurred_at)
    WHERE record_type LIKE 'CREDIT_EXPOSURE_%';

CREATE TRIGGER identity_credit_control_immutable
BEFORE UPDATE OR DELETE ON identity_credit_control_event
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;
