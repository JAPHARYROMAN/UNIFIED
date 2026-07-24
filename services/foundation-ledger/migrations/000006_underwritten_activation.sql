BEGIN;

ALTER TABLE identity_credit_control_event
    DROP CONSTRAINT identity_credit_control_event_record_type_check;

ALTER TABLE identity_credit_control_event
    ADD COLUMN tender_id text,
    ADD COLUMN offer_id text,
    ADD COLUMN borrower_account text,
    ADD COLUMN lender_account text,
    ADD COLUMN loan_account text,
    ADD COLUMN product_hash text,
    ADD COLUMN duration_seconds bigint CHECK (duration_seconds > 0),
    ADD COLUMN agreement_hash text,
    ADD COLUMN consent_evidence_hash text,
    ADD COLUMN journal_reference text;

ALTER TABLE identity_credit_control_event
    ADD CONSTRAINT identity_credit_control_event_record_type_check CHECK (
        record_type IN (
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
            'CREDIT_EXPOSURE_CANCELLED',
            'UNDERWRITTEN_LOAN_ACTIVATED',
            'UNDERWRITTEN_EXPOSURE_RELEASED'
        )
    ),
    ADD CONSTRAINT underwritten_activation_evidence_complete CHECK (
        record_type <> 'UNDERWRITTEN_LOAN_ACTIVATED'
        OR (
            decision_id IS NOT NULL
            AND loan_id IS NOT NULL
            AND tender_id IS NOT NULL
            AND offer_id IS NOT NULL
            AND subject_commitment IS NOT NULL
            AND borrower_account IS NOT NULL
            AND lender_account IS NOT NULL
            AND loan_account IS NOT NULL
            AND asset_id IS NOT NULL
            AND product_hash IS NOT NULL
            AND units IS NOT NULL
            AND duration_seconds IS NOT NULL
            AND agreement_hash IS NOT NULL
            AND consent_evidence_hash IS NOT NULL
            AND journal_reference IS NOT NULL
        )
    ),
    ADD CONSTRAINT underwritten_release_evidence_complete CHECK (
        record_type <> 'UNDERWRITTEN_EXPOSURE_RELEASED'
        OR (
            decision_id IS NOT NULL
            AND loan_id IS NOT NULL
            AND subject_commitment IS NOT NULL
            AND asset_id IS NOT NULL
            AND units IS NOT NULL
        )
    );

CREATE INDEX underwritten_activation_by_decision
    ON identity_credit_control_event (decision_id, occurred_at)
    WHERE record_type = 'UNDERWRITTEN_LOAN_ACTIVATED';

COMMIT;
