BEGIN;

INSERT INTO chart_account (
    account_code, account_name, account_class, normal_side, specification_version
) VALUES
    ('4110', 'Liquidation Cost Recovery Revenue', 'REVENUE', 'CREDIT', 'v0.1');

CREATE TABLE liquidation_settlement (
    liquidation_id text PRIMARY KEY,
    loan_id text NOT NULL,
    source_event_id text NOT NULL UNIQUE,
    asset_id text NOT NULL,
    gross_proceeds numeric(78, 0) NOT NULL CHECK (gross_proceeds > 0),
    execution_costs numeric(78, 0) NOT NULL CHECK (execution_costs >= 0),
    liquidation_incentive numeric(78, 0) NOT NULL CHECK (liquidation_incentive >= 0),
    secured_claim_paid numeric(78, 0) NOT NULL CHECK (secured_claim_paid >= 0),
    borrower_surplus numeric(78, 0) NOT NULL CHECK (borrower_surplus >= 0),
    debt_before numeric(78, 0) NOT NULL CHECK (debt_before >= 0),
    residual_bad_debt numeric(78, 0) NOT NULL CHECK (residual_bad_debt >= 0),
    buyer_id text NOT NULL,
    executor_id text NOT NULL,
    pricing_evidence_hash text NOT NULL,
    journal_reference text NOT NULL,
    settled_at timestamptz NOT NULL,
    CONSTRAINT liquidation_proceeds_conserved CHECK (
        gross_proceeds =
            execution_costs
            + liquidation_incentive
            + secured_claim_paid
            + borrower_surplus
    ),
    CONSTRAINT liquidation_debt_reconciled CHECK (
        debt_before = secured_claim_paid + residual_bad_debt
    )
);

CREATE INDEX liquidation_settlement_by_loan
    ON liquidation_settlement (loan_id, settled_at);

CREATE TRIGGER liquidation_settlement_immutable
BEFORE UPDATE OR DELETE ON liquidation_settlement
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;
