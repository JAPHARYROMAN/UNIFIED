BEGIN;

CREATE TABLE chart_account (
    account_code text PRIMARY KEY,
    account_name text NOT NULL,
    account_class text NOT NULL,
    normal_side text NOT NULL CHECK (normal_side IN ('DEBIT', 'CREDIT')),
    specification_version text NOT NULL
);

INSERT INTO chart_account (
    account_code, account_name, account_class, normal_side, specification_version
) VALUES
    ('1220', 'Stablecoin Treasury Holdings', 'ASSET', 'DEBIT', 'v0.1'),
    ('1310', 'Principal Receivable', 'ASSET', 'DEBIT', 'v0.1'),
    ('2310', 'Lender Principal Claims', 'LIABILITY', 'CREDIT', 'v0.1'),
    ('4100', 'Loan Origination Fee Revenue', 'REVENUE', 'CREDIT', 'v0.1');

ALTER TABLE journal
    ADD COLUMN entry_type text NOT NULL DEFAULT 'FOUNDATION',
    ADD COLUMN source_event_id text NOT NULL DEFAULT 'foundation-migration',
    ADD COLUMN loan_id text,
    ADD COLUMN reversal_of text REFERENCES journal(journal_id),
    ADD COLUMN reversal_reason text,
    ADD CONSTRAINT journal_reversal_is_external CHECK (
        reversal_of IS NULL OR reversal_of <> journal_id
    );

CREATE UNIQUE INDEX one_reversal_per_journal
    ON journal (reversal_of)
    WHERE reversal_of IS NOT NULL;

ALTER TABLE journal_entry
    ADD COLUMN loan_id text,
    ADD CONSTRAINT journal_entry_account_known
        FOREIGN KEY (account_code) REFERENCES chart_account(account_code)
        NOT VALID;

CREATE VIEW loan_subledger AS
SELECT
    j.loan_id,
    j.journal_id,
    j.entry_type,
    j.source_event_id,
    j.effective_at,
    j.reversal_of,
    e.line_number,
    e.account_code,
    e.side,
    e.asset_id,
    e.units,
    e.party_id
FROM journal AS j
JOIN journal_entry AS e USING (journal_id)
WHERE j.loan_id IS NOT NULL;

CREATE FUNCTION assert_journal_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM journal_balance
        WHERE journal_id = NEW.journal_id
          AND debit_units <> credit_units
    ) THEN
        RAISE EXCEPTION 'journal % is not balanced by asset', NEW.journal_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER journal_balanced_on_commit
AFTER INSERT ON journal_entry
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_journal_balanced();

CREATE TRIGGER chart_account_immutable
BEFORE UPDATE OR DELETE ON chart_account
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;
