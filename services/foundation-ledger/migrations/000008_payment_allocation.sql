BEGIN;

INSERT INTO chart_account (
    account_code, account_name, account_class, normal_side, specification_version
) VALUES
    ('2130', 'Lender Repayment Payable', 'LIABILITY', 'CREDIT', 'v0.1'),
    ('2150', 'Refund Payable', 'LIABILITY', 'CREDIT', 'v0.1');

CREATE TABLE synthetic_loan_obligation_projection (
    loan_id text NOT NULL,
    aggregate_version bigint NOT NULL CHECK (aggregate_version > 0),
    borrower_id text NOT NULL,
    lender_id text NOT NULL,
    asset_id text NOT NULL,
    outstanding_principal numeric(78, 0) NOT NULL CHECK (outstanding_principal >= 0),
    source_authority text NOT NULL,
    source_evidence_hash text NOT NULL,
    as_of timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (loan_id, aggregate_version)
);

CREATE TABLE final_payment_allocation (
    allocation_id text PRIMARY KEY,
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    loan_id text NOT NULL,
    provider_id text NOT NULL,
    provider_reference text NOT NULL,
    asset_id text NOT NULL,
    gross_units numeric(78, 0) NOT NULL CHECK (gross_units > 0),
    principal_units numeric(78, 0) NOT NULL CHECK (principal_units > 0),
    refundable_excess_units numeric(78, 0) NOT NULL CHECK (refundable_excess_units >= 0),
    debt_before_units numeric(78, 0) NOT NULL CHECK (debt_before_units > 0),
    debt_after_units numeric(78, 0) NOT NULL CHECK (debt_after_units >= 0),
    obligation_version_before bigint NOT NULL,
    obligation_version_after bigint NOT NULL,
    waterfall_policy_hash text NOT NULL,
    finality_policy_hash text NOT NULL,
    reconciliation_id text NOT NULL REFERENCES payment_reconciliation_run(run_id),
    reversal_deadline timestamptz NOT NULL,
    correlation_id text NOT NULL,
    evidence_hash text NOT NULL,
    journal_ids text[] NOT NULL CHECK (cardinality(journal_ids) = 2),
    allocated_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (gross_units = principal_units + refundable_excess_units),
    CHECK (debt_before_units = principal_units + debt_after_units),
    CHECK (obligation_version_after = obligation_version_before + 1),
    CHECK (reversal_deadline > allocated_at)
);

CREATE TABLE payment_allocation_reversal (
    reversal_id text PRIMARY KEY,
    allocation_id text NOT NULL UNIQUE
        REFERENCES final_payment_allocation(allocation_id),
    payment_id text NOT NULL,
    loan_id text NOT NULL,
    restored_principal_units numeric(78, 0) NOT NULL CHECK (restored_principal_units > 0),
    removed_excess_units numeric(78, 0) NOT NULL CHECK (removed_excess_units >= 0),
    debt_before_units numeric(78, 0) NOT NULL CHECK (debt_before_units >= 0),
    debt_after_units numeric(78, 0) NOT NULL CHECK (debt_after_units > 0),
    obligation_version_before bigint NOT NULL,
    obligation_version_after bigint NOT NULL,
    reason_code text NOT NULL,
    evidence_hash text NOT NULL,
    journal_ids text[] NOT NULL CHECK (cardinality(journal_ids) = 2),
    reversed_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (debt_after_units = debt_before_units + restored_principal_units),
    CHECK (obligation_version_after = obligation_version_before + 1)
);

CREATE TABLE collateral_release_eligibility_evidence (
    evidence_id text PRIMARY KEY,
    allocation_id text NOT NULL REFERENCES final_payment_allocation(allocation_id),
    loan_id text NOT NULL,
    projected_outstanding_principal numeric(78, 0) NOT NULL
        CHECK (projected_outstanding_principal >= 0),
    payment_final boolean NOT NULL,
    reconciliation_matched boolean NOT NULL,
    reversal_deadline_elapsed boolean NOT NULL,
    allocation_reversed boolean NOT NULL,
    eligible boolean NOT NULL,
    evidence_hash text NOT NULL,
    evaluated_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (
        eligible = (
            projected_outstanding_principal = 0
            AND payment_final
            AND reconciliation_matched
            AND reversal_deadline_elapsed
            AND NOT allocation_reversed
        )
    )
);

CREATE TRIGGER synthetic_loan_obligation_projection_immutable
BEFORE UPDATE OR DELETE ON synthetic_loan_obligation_projection
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER final_payment_allocation_immutable
BEFORE UPDATE OR DELETE ON final_payment_allocation
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER payment_allocation_reversal_immutable
BEFORE UPDATE OR DELETE ON payment_allocation_reversal
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER collateral_release_eligibility_evidence_immutable
BEFORE UPDATE OR DELETE ON collateral_release_eligibility_evidence
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;
