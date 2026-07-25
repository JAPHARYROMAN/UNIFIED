BEGIN;

DO $roles$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'unified_home_accounting_runtime'
    ) THEN
        CREATE ROLE unified_home_accounting_runtime
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
END;
$roles$;

DO $grant_connect$
BEGIN
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO unified_home_accounting_runtime',
        current_database()
    );
END;
$grant_connect$;

CREATE SCHEMA IF NOT EXISTS ledger AUTHORIZATION unified_crosschain_owner;
REVOKE ALL ON SCHEMA ledger FROM PUBLIC;
GRANT USAGE ON SCHEMA ledger TO unified_crosschain_runtime;
GRANT USAGE ON SCHEMA crosschain, ledger
    TO unified_home_accounting_runtime;

CREATE TABLE crosschain.loan_routes (
    loan_id text PRIMARY KEY,
    route_id text NOT NULL,
    route_version bigint NOT NULL,
    home_chain_id numeric(78, 0) NOT NULL,
    satellite_chain_id numeric(78, 0) NOT NULL,
    home_loan bytea NOT NULL CHECK (octet_length(home_loan) = 20),
    satellite_component bytea NOT NULL CHECK (octet_length(satellite_component) = 20),
    borrower_id text NOT NULL,
    lender_id text NOT NULL,
    principal_asset_id text NOT NULL,
    principal_units numeric(78, 0) NOT NULL CHECK (principal_units > 0),
    collateral_asset_id text NOT NULL,
    collateral_units numeric(78, 0) NOT NULL CHECK (collateral_units > 0),
    immutable_policy_hash bytea NOT NULL CHECK (octet_length(immutable_policy_hash) = 32),
    lifecycle_state text NOT NULL CHECK (
        lifecycle_state IN (
            'ACTIVATING', 'ACTIVE', 'CLOSING', 'CLOSED',
            'RECOVERY', 'CANCELLED', 'DISPUTED'
        )
    ),
    state_version bigint NOT NULL CHECK (state_version > 0),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    FOREIGN KEY (route_id, route_version)
        REFERENCES crosschain.route_versions(route_id, version),
    CHECK (home_chain_id <> satellite_chain_id)
);

CREATE TABLE crosschain.collateral_positions (
    position_id text PRIMARY KEY,
    loan_id text NOT NULL UNIQUE REFERENCES crosschain.loan_routes(loan_id),
    satellite_chain_id numeric(78, 0) NOT NULL,
    vault bytea NOT NULL CHECK (octet_length(vault) = 20),
    asset_id text NOT NULL,
    remote_position_key text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    borrower_id text NOT NULL,
    lock_message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    custody_commitment bytea NOT NULL UNIQUE CHECK (octet_length(custody_commitment) = 32),
    status text NOT NULL CHECK (status IN ('LOCKED', 'RELEASE_AUTHORIZED', 'RELEASED', 'DISPUTED')),
    locked_at timestamptz NOT NULL,
    UNIQUE (satellite_chain_id, vault, asset_id, remote_position_key)
);

CREATE TABLE crosschain.disbursement_authorizations (
    authorization_id text PRIMARY KEY,
    loan_id text NOT NULL UNIQUE REFERENCES crosschain.loan_routes(loan_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    wrapped_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    borrower_id text NOT NULL,
    settlement_vault bytea NOT NULL CHECK (octet_length(settlement_vault) = 20),
    authorized_at timestamptz NOT NULL
);

CREATE TABLE crosschain.disbursement_results (
    authorization_id text PRIMARY KEY
        REFERENCES crosschain.disbursement_authorizations(authorization_id),
    loan_id text NOT NULL UNIQUE REFERENCES crosschain.loan_routes(loan_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    recipient_balance_delta_hash bytea NOT NULL CHECK (octet_length(recipient_balance_delta_hash) = 32),
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    finalized_at timestamptz NOT NULL,
    UNIQUE (transaction_hash, log_index)
);

CREATE TABLE crosschain.repayment_results (
    payment_id text PRIMARY KEY,
    loan_id text NOT NULL REFERENCES crosschain.loan_routes(loan_id),
    burn_id text NOT NULL UNIQUE,
    burn_message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    canonical_release_result_hash bytea NOT NULL UNIQUE CHECK (
        octet_length(canonical_release_result_hash) = 32
    ),
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    debt_before_units numeric(78, 0) NOT NULL CHECK (debt_before_units > 0),
    debt_after_units numeric(78, 0) NOT NULL CHECK (debt_after_units >= 0),
    lender_id text NOT NULL,
    home_transaction_hash bytea NOT NULL CHECK (octet_length(home_transaction_hash) = 32),
    home_log_index numeric(20, 0) NOT NULL CHECK (home_log_index >= 0),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    finalized_at timestamptz NOT NULL,
    UNIQUE (home_transaction_hash, home_log_index),
    CHECK (debt_before_units = units + debt_after_units)
);

-- Direct-home repayments do not have a cross-chain message.  Their economic
-- fields therefore enter the commit path only through this immutable,
-- finality-attested authority record; the commit function merely verifies its
-- arguments against the record and derives debt from the locked loan row.
CREATE TABLE crosschain.direct_home_repayment_evidence (
    payment_id text PRIMARY KEY,
    loan_id text NOT NULL REFERENCES crosschain.loan_routes(loan_id),
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    lender_id text NOT NULL,
    home_transaction_hash bytea NOT NULL CHECK (
        octet_length(home_transaction_hash) = 32
    ),
    home_log_index numeric(20, 0) NOT NULL CHECK (home_log_index >= 0),
    evidence_hash bytea NOT NULL UNIQUE CHECK (octet_length(evidence_hash) = 32),
    finalized_at timestamptz NOT NULL,
    UNIQUE (home_transaction_hash, home_log_index)
);

CREATE TABLE crosschain.direct_home_repayment_results (
    payment_id text PRIMARY KEY,
    loan_id text NOT NULL REFERENCES crosschain.loan_routes(loan_id),
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    debt_before_units numeric(78, 0) NOT NULL CHECK (debt_before_units > 0),
    debt_after_units numeric(78, 0) NOT NULL CHECK (debt_after_units >= 0),
    lender_id text NOT NULL,
    home_transaction_hash bytea NOT NULL CHECK (octet_length(home_transaction_hash) = 32),
    home_log_index numeric(20, 0) NOT NULL CHECK (home_log_index >= 0),
    bridge_backing_changed boolean NOT NULL CHECK (NOT bridge_backing_changed),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    finalized_at timestamptz NOT NULL,
    UNIQUE (home_transaction_hash, home_log_index),
    CHECK (debt_before_units = units + debt_after_units)
);

CREATE TABLE crosschain.collateral_release_authorizations (
    authorization_id text PRIMARY KEY,
    loan_id text NOT NULL UNIQUE REFERENCES crosschain.loan_routes(loan_id),
    position_id text NOT NULL UNIQUE REFERENCES crosschain.collateral_positions(position_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    zero_debt_commitment bytea NOT NULL UNIQUE CHECK (octet_length(zero_debt_commitment) = 32),
    borrower_id text NOT NULL,
    authorized_at timestamptz NOT NULL
);

CREATE TABLE crosschain.collateral_release_results (
    authorization_id text PRIMARY KEY
        REFERENCES crosschain.collateral_release_authorizations(authorization_id),
    loan_id text NOT NULL UNIQUE REFERENCES crosschain.loan_routes(loan_id),
    position_id text NOT NULL UNIQUE REFERENCES crosschain.collateral_positions(position_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    release_result_hash bytea NOT NULL UNIQUE CHECK (octet_length(release_result_hash) = 32),
    accounting_reconciliation_hash bytea NOT NULL CHECK (
        octet_length(accounting_reconciliation_hash) = 32
    ),
    borrower_id text NOT NULL,
    finalized_at timestamptz NOT NULL,
    UNIQUE (transaction_hash, log_index)
);

CREATE TABLE ledger.satellite_custody_links (
    position_id text PRIMARY KEY REFERENCES crosschain.collateral_positions(position_id),
    journal_id text NOT NULL UNIQUE REFERENCES public.journal(journal_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32)
);

CREATE TABLE ledger.satellite_settlement_links (
    settlement_id text PRIMARY KEY,
    loan_id text NOT NULL REFERENCES crosschain.loan_routes(loan_id),
    settlement_kind text NOT NULL CHECK (
        settlement_kind IN (
            'DISBURSEMENT', 'REMOTE_REPAYMENT', 'DIRECT_HOME_REPAYMENT',
            'COLLATERAL_RELEASE'
        )
    ),
    journal_id text NOT NULL UNIQUE REFERENCES public.journal(journal_id),
    message_id bytea REFERENCES crosschain.messages(message_id),
    payment_id text,
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    CHECK (
        (settlement_kind = 'DIRECT_HOME_REPAYMENT' AND message_id IS NULL)
        OR (settlement_kind <> 'DIRECT_HOME_REPAYMENT' AND message_id IS NOT NULL)
    )
);

CREATE FUNCTION crosschain.require_finalized_message(
    message_id_ bytea,
    expected_action_type_ smallint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.execution_results AS execution
          ON execution.message_id = message.message_id
        WHERE message.message_id = message_id_
          AND message.action_type = expected_action_type_
          AND message.state = 'ACKNOWLEDGED'
    ) THEN
        RAISE EXCEPTION 'message lacks expected action and finalized execution evidence';
    END IF;
END;
$function$;

CREATE FUNCTION crosschain.require_action_projection(
    message_id_ bytea,
    expected_action_type_ smallint
) RETURNS crosschain.action_projections
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.action_projections;
BEGIN
    SELECT projection.* INTO result
    FROM crosschain.action_projections AS projection
    JOIN crosschain.messages AS message
      ON message.message_id = projection.message_id
     AND message.action_type = projection.action_type
     AND message.state = 'ACKNOWLEDGED'
    JOIN crosschain.execution_results AS execution
      ON execution.message_id = projection.message_id
     AND execution.result_hash = projection.execution_result_hash
     AND execution.effect_commitment = projection.projection_hash
     AND execution.destination_proof_id = projection.destination_proof_id
     AND execution.certificate_id = projection.certificate_id
    JOIN crosschain.acknowledgements AS acknowledgement
      ON acknowledgement.message_id = projection.message_id
     AND acknowledgement.execution_result_hash =
         projection.execution_result_hash
     AND acknowledgement.destination_proof_id =
         projection.destination_proof_id
     AND acknowledgement.certificate_id = projection.certificate_id
    WHERE projection.message_id = message_id_
      AND projection.action_type = expected_action_type_;
    IF result.message_id IS NULL THEN
        RAISE EXCEPTION 'message lacks canonical authenticated action projection';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.direct_home_repayment_evidence_hash(
    payment_id_ text,
    loan_id_ text,
    asset_id_ text,
    units_ numeric,
    lender_id_ text,
    home_transaction_hash_ bytea,
    home_log_index_ numeric,
    finalized_at_ timestamptz
) RETURNS bytea
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog, crosschain
AS $function$
SELECT sha256(
    convert_to(
        jsonb_build_object(
            'asset_id', asset_id_,
            'finalized_at', to_char(
                finalized_at_ AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'home_log_index', home_log_index_,
            'home_transaction_hash', encode(home_transaction_hash_, 'hex'),
            'lender_id', lender_id_,
            'loan_id', loan_id_,
            'payment_id', payment_id_,
            'units', units_
        )::text,
        'UTF8'
    )
);
$function$;

CREATE FUNCTION crosschain.record_direct_home_repayment_evidence(
    payment_id_ text,
    loan_id_ text,
    asset_id_ text,
    units_ numeric,
    lender_id_ text,
    home_transaction_hash_ bytea,
    home_log_index_ numeric,
    evidence_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.direct_home_repayment_evidence
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.direct_home_repayment_evidence;
BEGIN
    IF evidence_hash_ <> crosschain.direct_home_repayment_evidence_hash(
        payment_id_, loan_id_, asset_id_, units_, lender_id_,
        home_transaction_hash_, home_log_index_, finalized_at_
    ) THEN
        RAISE EXCEPTION 'direct-home repayment evidence hash mismatch';
    END IF;
    INSERT INTO crosschain.direct_home_repayment_evidence (
        payment_id, loan_id, asset_id, units, lender_id,
        home_transaction_hash, home_log_index, evidence_hash, finalized_at
    ) VALUES (
        payment_id_, loan_id_, asset_id_, units_, lender_id_,
        home_transaction_hash_, home_log_index_, evidence_hash_, finalized_at_
    )
    ON CONFLICT (payment_id) DO NOTHING
    RETURNING * INTO result;
    IF result.payment_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.direct_home_repayment_evidence
        WHERE payment_id = payment_id_;
        IF result.loan_id <> loan_id_ OR result.asset_id <> asset_id_
           OR result.units <> units_ OR result.lender_id <> lender_id_
           OR result.home_transaction_hash <> home_transaction_hash_
           OR result.home_log_index <> home_log_index_
           OR result.evidence_hash <> evidence_hash_
           OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting direct-home repayment evidence replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.link_satellite_settlement_journal(
    settlement_id_ text,
    loan_id_ text,
    settlement_kind_ text,
    journal_id_ text,
    message_id_ bytea,
    payment_id_ text,
    evidence_hash_ bytea
) RETURNS ledger.satellite_settlement_links
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain, ledger
AS $function$
DECLARE
    result ledger.satellite_settlement_links;
BEGIN
    INSERT INTO ledger.satellite_settlement_links (
        settlement_id, loan_id, settlement_kind, journal_id,
        message_id, payment_id, evidence_hash
    ) VALUES (
        settlement_id_, loan_id_, settlement_kind_, journal_id_,
        message_id_, payment_id_, evidence_hash_
    )
    ON CONFLICT (settlement_id) DO NOTHING
    RETURNING * INTO result;
    IF result.settlement_id IS NULL THEN
        SELECT * INTO result
        FROM ledger.satellite_settlement_links
        WHERE settlement_id = settlement_id_;
    END IF;
    IF result.settlement_id IS NULL OR result.loan_id <> loan_id_
       OR result.settlement_kind <> settlement_kind_
       OR result.journal_id <> journal_id_
       OR result.message_id IS DISTINCT FROM message_id_
       OR result.payment_id IS DISTINCT FROM payment_id_
       OR result.evidence_hash <> evidence_hash_ THEN
        RAISE EXCEPTION 'conflicting satellite settlement journal replay';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.post_satellite_settlement_journal(
    message_id_ bytea,
    settlement_id_ text,
    settlement_kind_ text,
    payment_id_ text,
    loan_id_ text,
    suffix_ text,
    entry_type_ text,
    asset_id_ text,
    units_ numeric,
    debit_account_ text,
    credit_account_ text,
    party_id_ text
) RETURNS ledger.satellite_settlement_links
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain, ledger
AS $function$
DECLARE
    posted public.journal;
    projection crosschain.action_projections;
BEGIN
    projection := crosschain.require_action_projection(
        message_id_,
        (
            SELECT action_type
            FROM crosschain.messages
            WHERE message_id = message_id_
        )
    );
    posted := crosschain.post_message_journal(
        message_id_, suffix_, entry_type_, loan_id_, asset_id_, units_,
        debit_account_, credit_account_, party_id_
    );
    RETURN crosschain.link_satellite_settlement_journal(
        settlement_id_, loan_id_, settlement_kind_, posted.journal_id,
        message_id_, payment_id_, projection.projection_hash
    );
END;
$function$;

CREATE FUNCTION crosschain.register_loan_route(
    loan_id_ text,
    route_id_ text,
    route_version_ bigint,
    home_chain_id_ numeric,
    satellite_chain_id_ numeric,
    home_loan_ bytea,
    satellite_component_ bytea,
    borrower_id_ text,
    lender_id_ text,
    principal_asset_id_ text,
    principal_units_ numeric,
    collateral_asset_id_ text,
    collateral_units_ numeric,
    immutable_policy_hash_ bytea,
    created_at_ timestamptz
) RETURNS crosschain.loan_routes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.loan_routes;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.route_versions
        WHERE route_id = route_id_
          AND version = route_version_
          AND source_chain_id = home_chain_id_
          AND destination_chain_id = satellite_chain_id_
          AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'loan route does not match trusted route version';
    END IF;
    INSERT INTO crosschain.loan_routes (
        loan_id, route_id, route_version, home_chain_id, satellite_chain_id,
        home_loan, satellite_component, borrower_id, lender_id,
        principal_asset_id, principal_units, collateral_asset_id, collateral_units,
        immutable_policy_hash, lifecycle_state, state_version, created_at, updated_at
    ) VALUES (
        loan_id_, route_id_, route_version_, home_chain_id_, satellite_chain_id_,
        home_loan_, satellite_component_, borrower_id_, lender_id_,
        principal_asset_id_, principal_units_, collateral_asset_id_, collateral_units_,
        immutable_policy_hash_, 'ACTIVATING', 1, created_at_, created_at_
    )
    ON CONFLICT (loan_id) DO NOTHING
    RETURNING * INTO result;
    IF result.loan_id IS NULL THEN
        SELECT * INTO result FROM crosschain.loan_routes WHERE loan_id = loan_id_;
        IF result.route_id <> route_id_ OR result.route_version <> route_version_
           OR result.home_chain_id <> home_chain_id_
           OR result.satellite_chain_id <> satellite_chain_id_
           OR result.home_loan <> home_loan_
           OR result.satellite_component <> satellite_component_
           OR result.borrower_id <> borrower_id_ OR result.lender_id <> lender_id_
           OR result.principal_asset_id <> principal_asset_id_
           OR result.principal_units <> principal_units_
           OR result.collateral_asset_id <> collateral_asset_id_
           OR result.collateral_units <> collateral_units_
           OR result.immutable_policy_hash <> immutable_policy_hash_
           OR result.created_at <> created_at_ THEN
            RAISE EXCEPTION 'conflicting loan route replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_satellite_collateral_lock(
    position_id_ text,
    loan_id_ text,
    satellite_chain_id_ numeric,
    vault_ bytea,
    asset_id_ text,
    remote_position_key_ text,
    units_ numeric,
    borrower_id_ text,
    lock_message_id_ bytea,
    custody_commitment_ bytea,
    locked_at_ timestamptz
) RETURNS crosschain.collateral_positions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.collateral_positions;
    projection crosschain.action_projections;
    posted public.journal;
    link ledger.satellite_custody_links;
BEGIN
    PERFORM crosschain.require_finalized_message(lock_message_id_, 5::smallint);
    projection := crosschain.require_action_projection(
        lock_message_id_,
        5::smallint
    );
    IF projection.projection ->> 'position_id' <> position_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR (projection.projection ->> 'satellite_chain_id')::numeric <>
          satellite_chain_id_
       OR decode(projection.projection ->> 'vault', 'hex') <> vault_
       OR projection.projection ->> 'asset_id' <> asset_id_
       OR projection.projection ->> 'remote_position_key' <>
          remote_position_key_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projection ->> 'borrower_id' <> borrower_id_
       OR decode(
           projection.projection ->> 'custody_commitment',
           'hex'
       ) <> custody_commitment_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'effect_message_id',
                   'hex'
               ) <> lock_message_id_
               OR NOT EXISTS (
                   SELECT 1
                   FROM crosschain.source_proofs
                   WHERE message_id = lock_message_id_
                     AND transaction_hash = decode(
                         projection.projection ->> 'effect_transaction_hash',
                         'hex'
                     )
                     AND log_index =
                         (projection.projection ->> 'effect_log_index')::numeric
                     AND event_hash = custody_commitment_
               )
               OR (projection.projection ->> 'effect_finalized_at')::timestamptz
                  <> locked_at_
           )
       )
       OR projection.projected_at <> locked_at_ THEN
        RAISE EXCEPTION 'collateral lock disagrees with authenticated action projection';
    END IF;
    INSERT INTO crosschain.collateral_positions (
        position_id, loan_id, satellite_chain_id, vault, asset_id, remote_position_key, units,
        borrower_id, lock_message_id, custody_commitment, status, locked_at
    )
    SELECT
        position_id_, loan_id_, satellite_chain_id_, vault_, asset_id_, remote_position_key_, units_,
        borrower_id_, lock_message_id_, custody_commitment_, 'LOCKED', locked_at_
    FROM crosschain.loan_routes AS loan
    WHERE loan.loan_id = loan_id_
      AND loan.satellite_chain_id = satellite_chain_id_
      AND loan.collateral_asset_id = asset_id_
      AND loan.collateral_units = units_
      AND loan.borrower_id = borrower_id_
    ON CONFLICT (position_id) DO NOTHING
    RETURNING * INTO result;
    IF result.position_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.collateral_positions
        WHERE position_id = position_id_;
        IF result.loan_id <> loan_id_ OR result.satellite_chain_id <> satellite_chain_id_
           OR result.vault <> vault_ OR result.asset_id <> asset_id_
           OR result.remote_position_key <> remote_position_key_ OR result.units <> units_
           OR result.borrower_id <> borrower_id_
           OR result.lock_message_id <> lock_message_id_
           OR result.custody_commitment <> custody_commitment_
           OR result.locked_at <> locked_at_ THEN
            RAISE EXCEPTION 'conflicting collateral lock replay';
        END IF;
    END IF;
    posted := crosschain.post_message_journal(
        lock_message_id_, 'satellite-custody', 'SATELLITE_CUSTODY',
        loan_id_, asset_id_, units_, '1430', '1420', borrower_id_
    );
    INSERT INTO ledger.satellite_custody_links (
        position_id, journal_id, message_id, evidence_hash
    ) VALUES (
        position_id_, posted.journal_id, lock_message_id_,
        projection.projection_hash
    )
    ON CONFLICT (position_id) DO NOTHING
    RETURNING * INTO link;
    IF link.position_id IS NULL THEN
        SELECT * INTO link
        FROM ledger.satellite_custody_links
        WHERE position_id = position_id_;
    END IF;
    IF link.position_id IS NULL OR link.journal_id <> posted.journal_id
       OR link.message_id <> lock_message_id_
       OR link.evidence_hash <> projection.projection_hash THEN
        RAISE EXCEPTION 'conflicting satellite custody journal replay';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_disbursement_authorization(
    authorization_id_ text,
    loan_id_ text,
    message_id_ bytea,
    wrapped_asset_id_ text,
    units_ numeric,
    borrower_id_ text,
    settlement_vault_ bytea,
    authorized_at_ timestamptz
) RETURNS crosschain.disbursement_authorizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    loan crosschain.loan_routes;
    result crosschain.disbursement_authorizations;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(message_id_, 6::smallint);
    projection := crosschain.require_action_projection(message_id_, 6::smallint);
    IF projection.projection ->> 'authorization_id' <> authorization_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR projection.projection ->> 'wrapped_asset_id' <> wrapped_asset_id_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projection ->> 'borrower_id' <> borrower_id_
       OR decode(
           projection.projection ->> 'settlement_vault',
           'hex'
       ) <> settlement_vault_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'effect_message_id',
                   'hex'
               ) <> message_id_
               OR NOT EXISTS (
                   SELECT 1
                   FROM crosschain.source_proofs
                   WHERE message_id = message_id_
                     AND transaction_hash = decode(
                         projection.projection ->> 'effect_transaction_hash',
                         'hex'
                     )
                     AND log_index =
                         (projection.projection ->> 'effect_log_index')::numeric
               )
               OR (projection.projection ->> 'effect_finalized_at')::timestamptz
                  <> authorized_at_
           )
       )
       OR projection.projected_at <> authorized_at_ THEN
        RAISE EXCEPTION 'disbursement authorization disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.disbursement_authorizations
    WHERE authorization_id = authorization_id_;
    IF result.authorization_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_ OR result.message_id <> message_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.borrower_id <> borrower_id_
           OR result.settlement_vault <> settlement_vault_
           OR result.authorized_at <> authorized_at_ THEN
            RAISE EXCEPTION 'conflicting disbursement authorization replay';
        END IF;
        RETURN result;
    END IF;
    SELECT * INTO loan FROM crosschain.loan_routes WHERE loan_id = loan_id_ FOR UPDATE;
    IF loan.loan_id IS NULL OR loan.lifecycle_state <> 'ACTIVATING'
       OR loan.borrower_id <> borrower_id_ OR loan.principal_units <> units_
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.collateral_positions
           WHERE loan_id = loan_id_ AND status = 'LOCKED'
       ) THEN
        RAISE EXCEPTION 'disbursement authorization requires finalized collateral lock';
    END IF;
    INSERT INTO crosschain.disbursement_authorizations (
        authorization_id, loan_id, message_id, wrapped_asset_id, units,
        borrower_id, settlement_vault, authorized_at
    ) VALUES (
        authorization_id_, loan_id_, message_id_, wrapped_asset_id_, units_,
        borrower_id_, settlement_vault_, authorized_at_
    )
    ON CONFLICT (authorization_id) DO NOTHING
    RETURNING * INTO result;
    IF result.authorization_id IS NULL THEN
        SELECT * INTO result FROM crosschain.disbursement_authorizations
        WHERE authorization_id = authorization_id_;
        IF result.loan_id <> loan_id_ OR result.message_id <> message_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.borrower_id <> borrower_id_
           OR result.settlement_vault <> settlement_vault_
           OR result.authorized_at <> authorized_at_ THEN
            RAISE EXCEPTION 'conflicting disbursement authorization replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_disbursement_result(
    authorization_id_ text,
    loan_id_ text,
    message_id_ bytea,
    transaction_hash_ bytea,
    log_index_ numeric,
    recipient_balance_delta_hash_ bytea,
    units_ numeric,
    finalized_at_ timestamptz
) RETURNS crosschain.disbursement_results
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    loan crosschain.loan_routes;
    authorization_record crosschain.disbursement_authorizations;
    result crosschain.disbursement_results;
    inserted_count bigint;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(message_id_, 7::smallint);
    projection := crosschain.require_action_projection(message_id_, 7::smallint);
    IF projection.projection ->> 'authorization_id' <> authorization_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR decode(
           projection.projection ->> 'recipient_balance_delta_hash',
           'hex'
       ) <> recipient_balance_delta_hash_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projected_at <> finalized_at_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'effect_transaction_hash',
                   'hex'
               ) <> transaction_hash_
               OR (projection.projection ->> 'effect_log_index')::numeric <>
                  log_index_
               OR NOT EXISTS (
                   SELECT 1
                   FROM crosschain.execution_results
                   WHERE message_id = decode(
                             projection.projection ->> 'effect_message_id',
                             'hex'
                         )
                     AND transaction_hash = transaction_hash_
                     AND log_index = log_index_
                     AND result_hash = recipient_balance_delta_hash_
               )
               OR (projection.projection ->> 'effect_finalized_at')::timestamptz
                  <> finalized_at_
           )
       )
       OR (
           projection.projection ->> 'proof_boundary' IS DISTINCT FROM
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND NOT EXISTS (
               SELECT 1
               FROM crosschain.execution_results
               WHERE message_id = message_id_
                 AND transaction_hash = transaction_hash_
                 AND log_index = log_index_
           )
       ) THEN
        RAISE EXCEPTION 'disbursement result disagrees with authenticated action projection';
    END IF;
    SELECT * INTO loan
    FROM crosschain.loan_routes
    WHERE loan_id = loan_id_;
    SELECT * INTO authorization_record
    FROM crosschain.disbursement_authorizations
    WHERE authorization_id = authorization_id_;
    SELECT * INTO result FROM crosschain.disbursement_results
    WHERE authorization_id = authorization_id_;
    IF result.authorization_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_ OR result.message_id <> message_id_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.recipient_balance_delta_hash <> recipient_balance_delta_hash_
           OR result.units <> units_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting disbursement result replay';
        END IF;
        PERFORM crosschain.post_satellite_settlement_journal(
            message_id_, authorization_id_, 'DISBURSEMENT', NULL,
            loan_id_, 'loan-activation', 'LOAN_ACTIVATION',
            loan.principal_asset_id, units_, '1310', '2310',
            authorization_record.borrower_id
        );
        RETURN result;
    END IF;
    SELECT * INTO loan FROM crosschain.loan_routes WHERE loan_id = loan_id_ FOR UPDATE;
    SELECT * INTO authorization_record FROM crosschain.disbursement_authorizations
    WHERE authorization_id = authorization_id_;
    IF loan.loan_id IS NULL OR loan.lifecycle_state <> 'ACTIVATING'
       OR authorization_record.authorization_id IS NULL
       OR authorization_record.loan_id <> loan_id_
       OR authorization_record.units <> units_
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.execution_results
           WHERE message_id = CASE
                   WHEN projection.projection ->> 'proof_boundary' =
                       'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
                   THEN decode(
                       projection.projection ->> 'effect_message_id',
                       'hex'
                   )
                   ELSE message_id_
               END
             AND transaction_hash = transaction_hash_
             AND log_index = log_index_
             AND (
                 projection.projection ->> 'proof_boundary' IS DISTINCT FROM
                     'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
                 OR result_hash = recipient_balance_delta_hash_
             )
       ) THEN
        RAISE EXCEPTION 'disbursement result lacks exact authorization or final execution';
    END IF;
    INSERT INTO crosschain.disbursement_results (
        authorization_id, loan_id, message_id, transaction_hash, log_index,
        recipient_balance_delta_hash, units, finalized_at
    ) VALUES (
        authorization_id_, loan_id_, message_id_, transaction_hash_, log_index_,
        recipient_balance_delta_hash_, units_, finalized_at_
    )
    ON CONFLICT (authorization_id) DO NOTHING
    RETURNING * INTO result;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 0 THEN
        SELECT * INTO result FROM crosschain.disbursement_results
        WHERE authorization_id = authorization_id_;
        IF result.loan_id <> loan_id_ OR result.message_id <> message_id_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.recipient_balance_delta_hash <> recipient_balance_delta_hash_
           OR result.units <> units_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting disbursement result replay';
        END IF;
        PERFORM crosschain.post_satellite_settlement_journal(
            message_id_, authorization_id_, 'DISBURSEMENT', NULL,
            loan_id_, 'loan-activation', 'LOAN_ACTIVATION',
            loan.principal_asset_id, units_, '1310', '2310',
            authorization_record.borrower_id
        );
        RETURN result;
    END IF;
    UPDATE crosschain.loan_routes
    SET lifecycle_state = 'ACTIVE', state_version = state_version + 1,
        updated_at = finalized_at_
    WHERE loan_id = loan_id_ AND lifecycle_state = 'ACTIVATING';
    PERFORM crosschain.post_satellite_settlement_journal(
        message_id_, authorization_id_, 'DISBURSEMENT', NULL,
        loan_id_, 'loan-activation', 'LOAN_ACTIVATION',
        loan.principal_asset_id, units_, '1310', '2310',
        authorization_record.borrower_id
    );
    RETURN result;
END;
$function$;

-- Remote repayment commit is defined by migration 000012 after bridge
-- burn and canonical-release authority tables exist.

CREATE FUNCTION crosschain.commit_direct_home_repayment(
    payment_id_ text,
    loan_id_ text,
    asset_id_ text,
    units_ numeric,
    debt_before_units_ numeric,
    debt_after_units_ numeric,
    lender_id_ text,
    home_transaction_hash_ bytea,
    home_log_index_ numeric,
    evidence_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.direct_home_repayment_results
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    loan crosschain.loan_routes;
    authority crosschain.direct_home_repayment_evidence;
    repaid numeric;
    result crosschain.direct_home_repayment_results;
    inserted_count bigint;
    posted public.journal;
BEGIN
    SELECT * INTO authority
    FROM crosschain.direct_home_repayment_evidence
    WHERE payment_id = payment_id_;
    IF authority.payment_id IS NULL
       OR authority.loan_id <> loan_id_
       OR authority.asset_id <> asset_id_
       OR authority.units <> units_
       OR authority.lender_id <> lender_id_
       OR authority.home_transaction_hash <> home_transaction_hash_
       OR authority.home_log_index <> home_log_index_
       OR authority.evidence_hash <> evidence_hash_
       OR authority.finalized_at <> finalized_at_ THEN
        RAISE EXCEPTION 'direct repayment lacks immutable authenticated home evidence';
    END IF;
    SELECT * INTO result FROM crosschain.direct_home_repayment_results
    WHERE payment_id = payment_id_;
    IF result.payment_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_ OR result.asset_id <> asset_id_
           OR result.units <> units_ OR result.debt_before_units <> debt_before_units_
           OR result.debt_after_units <> debt_after_units_
           OR result.lender_id <> lender_id_
           OR result.home_transaction_hash <> home_transaction_hash_
           OR result.home_log_index <> home_log_index_
           OR result.bridge_backing_changed
           OR result.evidence_hash <> evidence_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting direct repayment replay';
        END IF;
        posted := crosschain.post_balanced_journal(
            'crosschain:home:' || payment_id_ || ':repayment-debt',
            'DIRECT_HOME_REPAYMENT', payment_id_, loan_id_,
            'loan:' || loan_id_, evidence_hash_, finalized_at_,
            asset_id_, units_, '2310', '1310', lender_id_
        );
        PERFORM crosschain.link_satellite_settlement_journal(
            payment_id_, loan_id_, 'DIRECT_HOME_REPAYMENT',
            posted.journal_id, NULL, payment_id_, evidence_hash_
        );
        RETURN result;
    END IF;
    SELECT * INTO loan FROM crosschain.loan_routes
    WHERE loan_id = loan_id_ FOR UPDATE;
    IF loan.loan_id IS NULL OR loan.lifecycle_state <> 'ACTIVE'
       OR loan.principal_asset_id <> asset_id_ OR loan.lender_id <> lender_id_ THEN
        RAISE EXCEPTION 'direct repayment does not match immutable loan';
    END IF;
    SELECT
        COALESCE((SELECT SUM(units) FROM crosschain.repayment_results WHERE loan_id = loan_id_), 0)
        + COALESCE((SELECT SUM(units) FROM crosschain.direct_home_repayment_results WHERE loan_id = loan_id_), 0)
    INTO repaid;
    IF repaid + units_ > loan.principal_units
       OR debt_before_units_ <> loan.principal_units - repaid
       OR debt_after_units_ <> debt_before_units_ - units_ THEN
        RAISE EXCEPTION 'direct repayment exceeds or disagrees with canonical debt';
    END IF;
    INSERT INTO crosschain.direct_home_repayment_results (
        payment_id, loan_id, asset_id, units, debt_before_units, debt_after_units,
        lender_id, home_transaction_hash, home_log_index, bridge_backing_changed,
        evidence_hash, finalized_at
    ) VALUES (
        payment_id_, loan_id_, asset_id_, units_, debt_before_units_, debt_after_units_,
        lender_id_, home_transaction_hash_, home_log_index_, false,
        evidence_hash_, finalized_at_
    )
    ON CONFLICT (payment_id) DO NOTHING
    RETURNING * INTO result;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 0 THEN
        SELECT * INTO result FROM crosschain.direct_home_repayment_results
        WHERE payment_id = payment_id_;
        IF result.loan_id <> loan_id_ OR result.asset_id <> asset_id_
           OR result.units <> units_ OR result.debt_before_units <> debt_before_units_
           OR result.debt_after_units <> debt_after_units_
           OR result.lender_id <> lender_id_
           OR result.home_transaction_hash <> home_transaction_hash_
           OR result.home_log_index <> home_log_index_
           OR result.bridge_backing_changed
           OR result.evidence_hash <> evidence_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting direct repayment replay';
        END IF;
        posted := crosschain.post_balanced_journal(
            'crosschain:home:' || payment_id_ || ':repayment-debt',
            'DIRECT_HOME_REPAYMENT', payment_id_, loan_id_,
            'loan:' || loan_id_, evidence_hash_, finalized_at_,
            asset_id_, units_, '2310', '1310', lender_id_
        );
        PERFORM crosschain.link_satellite_settlement_journal(
            payment_id_, loan_id_, 'DIRECT_HOME_REPAYMENT',
            posted.journal_id, NULL, payment_id_, evidence_hash_
        );
        RETURN result;
    END IF;
    IF debt_after_units_ = 0 THEN
        UPDATE crosschain.loan_routes
        SET lifecycle_state = 'CLOSING',
            state_version = state_version + 1,
            updated_at = finalized_at_
        WHERE loan_id = loan_id_ AND lifecycle_state <> 'CLOSING';
    END IF;
    posted := crosschain.post_balanced_journal(
        'crosschain:home:' || payment_id_ || ':repayment-debt',
        'DIRECT_HOME_REPAYMENT', payment_id_, loan_id_,
        'loan:' || loan_id_, evidence_hash_, finalized_at_,
        asset_id_, units_, '2310', '1310', lender_id_
    );
    PERFORM crosschain.link_satellite_settlement_journal(
        payment_id_, loan_id_, 'DIRECT_HOME_REPAYMENT',
        posted.journal_id, NULL, payment_id_, evidence_hash_
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_collateral_release_authorization(
    authorization_id_ text,
    loan_id_ text,
    position_id_ text,
    message_id_ bytea,
    zero_debt_commitment_ bytea,
    borrower_id_ text,
    authorized_at_ timestamptz
) RETURNS crosschain.collateral_release_authorizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    loan crosschain.loan_routes;
    repaid numeric;
    result crosschain.collateral_release_authorizations;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(message_id_, 9::smallint);
    projection := crosschain.require_action_projection(message_id_, 9::smallint);
    IF projection.projection ->> 'authorization_id' <> authorization_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR projection.projection ->> 'position_id' <> position_id_
       OR decode(
           projection.projection ->> 'zero_debt_commitment',
           'hex'
       ) <> zero_debt_commitment_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'effect_message_id',
                   'hex'
               ) <> message_id_
               OR NOT EXISTS (
                   SELECT 1
                   FROM crosschain.source_proofs
                   WHERE message_id = message_id_
                     AND transaction_hash = decode(
                         projection.projection ->> 'effect_transaction_hash',
                         'hex'
                     )
                     AND log_index =
                         (projection.projection ->> 'effect_log_index')::numeric
                     AND event_hash = zero_debt_commitment_
               )
               OR (projection.projection ->> 'effect_finalized_at')::timestamptz
                  <> authorized_at_
           )
       )
       OR projection.projection ->> 'borrower_id' <> borrower_id_
       OR projection.projected_at <> authorized_at_ THEN
        RAISE EXCEPTION 'collateral release authorization disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.collateral_release_authorizations
    WHERE authorization_id = authorization_id_;
    IF result.authorization_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_ OR result.position_id <> position_id_
           OR result.message_id <> message_id_
           OR result.zero_debt_commitment <> zero_debt_commitment_
           OR result.borrower_id <> borrower_id_ OR result.authorized_at <> authorized_at_ THEN
            RAISE EXCEPTION 'conflicting collateral release authorization replay';
        END IF;
        RETURN result;
    END IF;
    SELECT * INTO loan FROM crosschain.loan_routes WHERE loan_id = loan_id_ FOR UPDATE;
    SELECT
        COALESCE((SELECT SUM(units) FROM crosschain.repayment_results WHERE loan_id = loan_id_), 0)
        + COALESCE((SELECT SUM(units) FROM crosschain.direct_home_repayment_results WHERE loan_id = loan_id_), 0)
    INTO repaid;
    IF loan.loan_id IS NULL OR loan.lifecycle_state <> 'CLOSING'
       OR repaid <> loan.principal_units OR loan.borrower_id <> borrower_id_
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.collateral_positions
           WHERE position_id = position_id_ AND loan_id = loan_id_
             AND status = 'LOCKED'
       ) THEN
        RAISE EXCEPTION 'collateral release authorization requires canonical zero debt';
    END IF;
    INSERT INTO crosschain.collateral_release_authorizations (
        authorization_id, loan_id, position_id, message_id,
        zero_debt_commitment, borrower_id, authorized_at
    ) VALUES (
        authorization_id_, loan_id_, position_id_, message_id_,
        zero_debt_commitment_, borrower_id_, authorized_at_
    )
    ON CONFLICT (authorization_id) DO NOTHING
    RETURNING * INTO result;
    IF result.authorization_id IS NULL THEN
        SELECT * INTO result FROM crosschain.collateral_release_authorizations
        WHERE authorization_id = authorization_id_;
        IF result.loan_id <> loan_id_ OR result.position_id <> position_id_
           OR result.message_id <> message_id_
           OR result.zero_debt_commitment <> zero_debt_commitment_
           OR result.borrower_id <> borrower_id_ OR result.authorized_at <> authorized_at_ THEN
            RAISE EXCEPTION 'conflicting collateral release authorization replay';
        END IF;
        RETURN result;
    END IF;
    UPDATE crosschain.collateral_positions
    SET status = 'RELEASE_AUTHORIZED'
    WHERE position_id = position_id_ AND status = 'LOCKED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'collateral position cannot be release-authorized';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_collateral_release(
    authorization_id_ text,
    loan_id_ text,
    position_id_ text,
    message_id_ bytea,
    transaction_hash_ bytea,
    log_index_ numeric,
    release_result_hash_ bytea,
    accounting_reconciliation_hash_ bytea,
    borrower_id_ text,
    finalized_at_ timestamptz
) RETURNS crosschain.collateral_release_results
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    loan crosschain.loan_routes;
    result crosschain.collateral_release_results;
    repaid numeric;
    inserted_count bigint;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(message_id_, 10::smallint);
    projection := crosschain.require_action_projection(message_id_, 10::smallint);
    SELECT * INTO loan
    FROM crosschain.loan_routes
    WHERE loan_id = loan_id_;
    IF projection.projection ->> 'authorization_id' <> authorization_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR projection.projection ->> 'position_id' <> position_id_
       OR decode(
           projection.projection ->> 'release_result_hash',
           'hex'
       ) <> release_result_hash_
       OR decode(
           projection.projection ->> 'accounting_reconciliation_hash',
           'hex'
       ) <> accounting_reconciliation_hash_
       OR projection.projection ->> 'borrower_id' <> borrower_id_
       OR projection.projected_at <> finalized_at_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'effect_transaction_hash',
                   'hex'
               ) <> transaction_hash_
               OR (projection.projection ->> 'effect_log_index')::numeric <>
                  log_index_
               OR NOT EXISTS (
                   SELECT 1
                   FROM crosschain.execution_results
                   WHERE message_id = decode(
                             projection.projection ->> 'effect_message_id',
                             'hex'
                         )
                     AND transaction_hash = transaction_hash_
                     AND log_index = log_index_
                     AND result_hash = release_result_hash_
               )
               OR (projection.projection ->> 'effect_finalized_at')::timestamptz
                  <> finalized_at_
           )
       )
       OR (
           projection.projection ->> 'proof_boundary' IS DISTINCT FROM
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND NOT EXISTS (
               SELECT 1
               FROM crosschain.execution_results
               WHERE message_id = message_id_
                 AND transaction_hash = transaction_hash_
                 AND log_index = log_index_
           )
       ) THEN
        RAISE EXCEPTION 'collateral release disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.collateral_release_results
    WHERE authorization_id = authorization_id_;
    IF result.authorization_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_ OR result.position_id <> position_id_
           OR result.message_id <> message_id_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.release_result_hash <> release_result_hash_
           OR result.accounting_reconciliation_hash <> accounting_reconciliation_hash_
           OR result.borrower_id <> borrower_id_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting collateral release replay';
        END IF;
        PERFORM crosschain.post_satellite_settlement_journal(
            message_id_, authorization_id_, 'COLLATERAL_RELEASE', NULL,
            loan_id_, 'satellite-custody-release', 'COLLATERAL_RELEASE',
            loan.collateral_asset_id, loan.collateral_units,
            '1420', '1430', borrower_id_
        );
        RETURN result;
    END IF;
    SELECT * INTO loan FROM crosschain.loan_routes
    WHERE loan_id = loan_id_ FOR UPDATE;
    SELECT
        COALESCE((SELECT SUM(units) FROM crosschain.repayment_results WHERE loan_id = loan_id_), 0)
        + COALESCE((SELECT SUM(units) FROM crosschain.direct_home_repayment_results WHERE loan_id = loan_id_), 0)
    INTO repaid;
    IF loan.loan_id IS NULL OR loan.lifecycle_state <> 'CLOSING'
       OR repaid <> loan.principal_units OR loan.borrower_id <> borrower_id_
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.collateral_release_authorizations
           WHERE authorization_id = authorization_id_
             AND loan_id = loan_id_
             AND position_id = position_id_
             AND borrower_id = borrower_id_
       )
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.execution_results
           WHERE message_id = CASE
                   WHEN projection.projection ->> 'proof_boundary' =
                       'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
                   THEN decode(
                       projection.projection ->> 'effect_message_id',
                       'hex'
                   )
                   ELSE message_id_
               END
             AND transaction_hash = transaction_hash_
             AND log_index = log_index_
             AND (
                 projection.projection ->> 'proof_boundary' IS DISTINCT FROM
                     'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
                 OR result_hash = release_result_hash_
             )
       ) THEN
        RAISE EXCEPTION 'collateral release lacks zero-debt home authorization';
    END IF;
    INSERT INTO crosschain.collateral_release_results (
        authorization_id, loan_id, position_id, message_id, transaction_hash,
        log_index, release_result_hash, accounting_reconciliation_hash,
        borrower_id, finalized_at
    ) VALUES (
        authorization_id_, loan_id_, position_id_, message_id_, transaction_hash_,
        log_index_, release_result_hash_, accounting_reconciliation_hash_,
        borrower_id_, finalized_at_
    )
    ON CONFLICT (authorization_id) DO NOTHING
    RETURNING * INTO result;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 0 THEN
        SELECT * INTO result FROM crosschain.collateral_release_results
        WHERE authorization_id = authorization_id_;
        IF result.loan_id <> loan_id_ OR result.position_id <> position_id_
           OR result.message_id <> message_id_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.release_result_hash <> release_result_hash_
           OR result.accounting_reconciliation_hash <> accounting_reconciliation_hash_
           OR result.borrower_id <> borrower_id_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting collateral release replay';
        END IF;
        PERFORM crosschain.post_satellite_settlement_journal(
            message_id_, authorization_id_, 'COLLATERAL_RELEASE', NULL,
            loan_id_, 'satellite-custody-release', 'COLLATERAL_RELEASE',
            loan.collateral_asset_id, loan.collateral_units,
            '1420', '1430', borrower_id_
        );
        RETURN result;
    END IF;
    UPDATE crosschain.collateral_positions
    SET status = 'RELEASED'
    WHERE position_id = position_id_ AND status = 'RELEASE_AUTHORIZED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'collateral position was not release-authorized';
    END IF;
    UPDATE crosschain.loan_routes
    SET lifecycle_state = 'CLOSED', state_version = state_version + 1,
        updated_at = finalized_at_
    WHERE loan_id = loan_id_ AND lifecycle_state = 'CLOSING';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'loan could not close after collateral release';
    END IF;
    PERFORM crosschain.post_satellite_settlement_journal(
        message_id_, authorization_id_, 'COLLATERAL_RELEASE', NULL,
        loan_id_, 'satellite-custody-release', 'COLLATERAL_RELEASE',
        loan.collateral_asset_id, loan.collateral_units,
        '1420', '1430', borrower_id_
    );
    RETURN result;
END;
$function$;

CREATE TRIGGER collateral_position_immutable_delete
BEFORE DELETE ON crosschain.collateral_positions
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER disbursement_result_immutable
BEFORE UPDATE OR DELETE ON crosschain.disbursement_results
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER repayment_result_immutable
BEFORE UPDATE OR DELETE ON crosschain.repayment_results
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER direct_home_repayment_result_immutable
BEFORE UPDATE OR DELETE ON crosschain.direct_home_repayment_results
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER direct_home_repayment_evidence_immutable
BEFORE UPDATE OR DELETE ON crosschain.direct_home_repayment_evidence
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER collateral_release_result_immutable
BEFORE UPDATE OR DELETE ON crosschain.collateral_release_results
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

DO $ownership$
DECLARE
    owned_object record;
    function_name text;
BEGIN
    FOR owned_object IN
        SELECT n.nspname AS schema_name, c.relname AS relation_name
        FROM pg_class AS c
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('crosschain', 'ledger')
          AND c.relkind = 'r'
          AND pg_get_userbyid(c.relowner) <> 'unified_crosschain_owner'
          AND (
              n.nspname = 'crosschain'
              OR c.relname IN ('satellite_custody_links', 'satellite_settlement_links')
          )
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I OWNER TO unified_crosschain_owner',
            owned_object.schema_name,
            owned_object.relation_name
        );
    END LOOP;
    FOR function_name IN
        SELECT p.oid::regprocedure::text
        FROM pg_proc AS p
        JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'crosschain'
           AND p.proname IN (
               'register_loan_route', 'commit_satellite_collateral_lock',
               'require_finalized_message', 'require_action_projection',
               'direct_home_repayment_evidence_hash',
               'record_direct_home_repayment_evidence',
               'link_satellite_settlement_journal',
               'post_satellite_settlement_journal',
               'commit_disbursement_authorization', 'commit_disbursement_result',
              'commit_direct_home_repayment',
              'commit_collateral_release_authorization',
              'commit_collateral_release'
          )
    LOOP
        EXECUTE format('ALTER FUNCTION %s OWNER TO unified_crosschain_owner', function_name);
    END LOOP;
END;
$ownership$;

ALTER TABLE ledger.satellite_custody_links OWNER TO unified_crosschain_owner;
ALTER TABLE ledger.satellite_settlement_links OWNER TO unified_crosschain_owner;

REVOKE ALL ON ALL TABLES IN SCHEMA crosschain FROM PUBLIC, unified_crosschain_runtime;
REVOKE ALL ON ledger.satellite_custody_links, ledger.satellite_settlement_links
    FROM PUBLIC, unified_crosschain_runtime;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crosschain FROM PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA crosschain TO unified_crosschain_runtime;
GRANT SELECT ON crosschain.direct_home_repayment_evidence
    TO unified_home_accounting_runtime;
GRANT SELECT ON ledger.satellite_custody_links, ledger.satellite_settlement_links
    TO unified_crosschain_runtime;
REVOKE ALL ON FUNCTION crosschain.register_loan_route(
    text, text, bigint, numeric, numeric, bytea, bytea, text, text, text,
    numeric, text, numeric, bytea, timestamptz
) FROM PUBLIC, unified_crosschain_runtime;
REVOKE ALL ON FUNCTION crosschain.commit_direct_home_repayment(
    text, text, text, numeric, numeric, numeric, text, bytea, numeric,
    bytea, timestamptz
) FROM PUBLIC, unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_direct_home_repayment(
    text, text, text, numeric, numeric, numeric, text, bytea, numeric,
    bytea, timestamptz
) TO unified_home_accounting_runtime;
GRANT EXECUTE ON FUNCTION crosschain.record_direct_home_repayment_evidence(
    text, text, text, numeric, text, bytea, numeric, bytea, timestamptz
) TO unified_crosschain_finality_attester;
GRANT EXECUTE ON FUNCTION crosschain.direct_home_repayment_evidence_hash(
    text, text, text, numeric, text, bytea, numeric, timestamptz
) TO unified_crosschain_finality_attester;
GRANT EXECUTE ON FUNCTION crosschain.commit_satellite_collateral_lock(
    text, text, numeric, bytea, text, text, numeric, text, bytea, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_disbursement_authorization(
    text, text, bytea, text, numeric, text, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_disbursement_result(
    text, text, bytea, bytea, numeric, bytea, numeric, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_collateral_release_authorization(
    text, text, text, bytea, bytea, text, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_collateral_release(
    text, text, text, bytea, bytea, numeric, bytea, bytea, text, timestamptz
) TO unified_crosschain_runtime;

COMMIT;
