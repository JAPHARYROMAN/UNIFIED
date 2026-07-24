BEGIN;

INSERT INTO chart_account (
    account_code, account_name, account_class, normal_side, specification_version
) VALUES
    ('2320', 'Funding Commitment Liabilities', 'LIABILITY', 'CREDIT', 'v0.1');

ALTER TABLE journal_entry
    ADD COLUMN tranche_id text;

CREATE TABLE syndicate_commitment (
    commitment_id text PRIMARY KEY,
    loan_id text NOT NULL,
    tranche_id text NOT NULL,
    lender_id text NOT NULL,
    asset_id text NOT NULL,
    funded_units numeric(78, 0) NOT NULL CHECK (funded_units > 0),
    position_id text NOT NULL UNIQUE,
    status text NOT NULL CHECK (status IN ('FUNDED', 'POSITION_ACTIVE', 'REFUNDED')),
    source_event_id text NOT NULL UNIQUE,
    evidence_hash text NOT NULL,
    effective_at timestamptz NOT NULL
);

CREATE TABLE lender_position_transfer (
    transfer_id text PRIMARY KEY,
    position_id text NOT NULL,
    loan_id text NOT NULL,
    seller_id text NOT NULL,
    buyer_id text NOT NULL,
    share_units numeric(78, 0) NOT NULL CHECK (share_units > 0),
    outstanding_claim_units numeric(78, 0) NOT NULL CHECK (outstanding_claim_units > 0),
    cutoff_block numeric(78, 0) NOT NULL CHECK (cutoff_block > 0),
    source_event_id text NOT NULL UNIQUE,
    evidence_hash text NOT NULL,
    settled_at timestamptz NOT NULL,
    CONSTRAINT position_transfer_changes_owner CHECK (seller_id <> buyer_id)
);

CREATE INDEX syndicate_commitment_by_loan
    ON syndicate_commitment (loan_id, tranche_id, lender_id);

CREATE INDEX position_transfer_history
    ON lender_position_transfer (position_id, cutoff_block);

CREATE TRIGGER syndicate_commitment_immutable
BEFORE UPDATE OR DELETE ON syndicate_commitment
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER lender_position_transfer_immutable
BEFORE UPDATE OR DELETE ON lender_position_transfer
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;
