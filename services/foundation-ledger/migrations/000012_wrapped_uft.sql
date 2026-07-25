BEGIN;

CREATE TABLE crosschain.bridge_exposure_policies (
    policy_version bigint PRIMARY KEY CHECK (policy_version > 0),
    circulating_supply_reference_units numeric(78, 0) NOT NULL CHECK (
        circulating_supply_reference_units > 0
    ),
    circulating_supply_evidence_hash bytea NOT NULL UNIQUE CHECK (
        octet_length(circulating_supply_evidence_hash) = 32
    ),
    route_absolute_cap_units numeric(78, 0) NOT NULL CHECK (route_absolute_cap_units > 0),
    chain_absolute_cap_units numeric(78, 0) NOT NULL CHECK (chain_absolute_cap_units > 0),
    adapter_absolute_cap_units numeric(78, 0) NOT NULL CHECK (adapter_absolute_cap_units > 0),
    aggregate_absolute_cap_units numeric(78, 0) NOT NULL CHECK (aggregate_absolute_cap_units > 0),
    route_percentage_basis_points integer NOT NULL CHECK (
        route_percentage_basis_points > 0 AND route_percentage_basis_points <= 500
    ),
    aggregate_percentage_basis_points integer NOT NULL CHECK (
        aggregate_percentage_basis_points > 0 AND aggregate_percentage_basis_points <= 1500
    ),
    effective_at timestamptz NOT NULL,
    status text NOT NULL CHECK (status IN ('PENDING', 'ACTIVE', 'DEPRECATED'))
);

CREATE UNIQUE INDEX one_active_bridge_exposure_policy
    ON crosschain.bridge_exposure_policies ((status))
    WHERE status = 'ACTIVE';

CREATE TABLE crosschain.bridge_locks (
    lock_id text PRIMARY KEY,
    route_id text NOT NULL,
    route_version bigint NOT NULL,
    policy_version bigint NOT NULL REFERENCES crosschain.bridge_exposure_policies(policy_version),
    chain_id numeric(78, 0) NOT NULL,
    adapter_id text NOT NULL,
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    canonical_asset_id text NOT NULL,
    wrapped_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    minted_units numeric(78, 0) NOT NULL DEFAULT 0 CHECK (minted_units >= 0),
    burned_units numeric(78, 0) NOT NULL DEFAULT 0 CHECK (burned_units >= 0),
    released_units numeric(78, 0) NOT NULL DEFAULT 0 CHECK (released_units >= 0),
    permanently_burned_units numeric(78, 0) NOT NULL DEFAULT 0 CHECK (
        permanently_burned_units >= 0
    ),
    lender_id text NOT NULL,
    loan_id text REFERENCES crosschain.loan_routes(loan_id),
    status text NOT NULL CHECK (
        status IN (
            'LOCKED', 'MINTED', 'PARTIALLY_DISPOSED', 'SETTLED',
            'COMPENSATED', 'DISPUTED'
        )
    ),
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    finalized_at timestamptz NOT NULL,
    FOREIGN KEY (route_id, route_version)
        REFERENCES crosschain.route_versions(route_id, version),
    UNIQUE (chain_id, transaction_hash, log_index),
    CHECK (minted_units <= units),
    CHECK (burned_units <= minted_units),
    CHECK (released_units + permanently_burned_units <= burned_units)
);

CREATE TABLE crosschain.wrapped_mints (
    mint_id text PRIMARY KEY,
    lock_id text NOT NULL UNIQUE REFERENCES crosschain.bridge_locks(lock_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    wrapped_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    recipient text NOT NULL,
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    supply_after_units numeric(78, 0) NOT NULL CHECK (supply_after_units >= units),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    finalized_at timestamptz NOT NULL,
    UNIQUE (transaction_hash, log_index)
);

CREATE TABLE crosschain.wrapped_burns (
    burn_id text PRIMARY KEY,
    lock_id text NOT NULL REFERENCES crosschain.bridge_locks(lock_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    payment_id text,
    wrapped_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    registry_recipient text NOT NULL,
    burn_kind text NOT NULL CHECK (burn_kind IN ('REDEMPTION', 'LOAN_REPAYMENT', 'PERMANENT')),
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    supply_after_units numeric(78, 0) NOT NULL CHECK (supply_after_units >= 0),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    finalized_at timestamptz NOT NULL,
    UNIQUE (transaction_hash, log_index),
    UNIQUE (lock_id, burn_id)
);

CREATE TABLE crosschain.canonical_releases (
    release_id text PRIMARY KEY,
    burn_id text NOT NULL UNIQUE REFERENCES crosschain.wrapped_burns(burn_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    canonical_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    registry_recipient text NOT NULL,
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    result_hash bytea NOT NULL UNIQUE CHECK (octet_length(result_hash) = 32),
    finalized_at timestamptz NOT NULL,
    UNIQUE (transaction_hash, log_index)
);

CREATE TABLE crosschain.canonical_burns (
    canonical_burn_id text PRIMARY KEY,
    burn_id text NOT NULL UNIQUE REFERENCES crosschain.wrapped_burns(burn_id),
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    canonical_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    result_hash bytea NOT NULL UNIQUE CHECK (octet_length(result_hash) = 32),
    finalized_at timestamptz NOT NULL,
    UNIQUE (transaction_hash, log_index)
);

-- Action 12 is durable cancellation intent only and has no accounting effect.
CREATE TABLE crosschain.loan_cancellation_requests (
    cancellation_id text PRIMARY KEY,
    loan_id text NOT NULL UNIQUE REFERENCES crosschain.loan_routes(loan_id),
    funding_lock_id text NOT NULL,
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    route_id text NOT NULL,
    source_component bytea NOT NULL CHECK (octet_length(source_component) = 20),
    destination_component bytea NOT NULL CHECK (octet_length(destination_component) = 20),
    disbursement_message_id bytea NOT NULL CHECK (
        octet_length(disbursement_message_id) = 32
    ),
    disbursement_tombstone_hash bytea NOT NULL CHECK (
        octet_length(disbursement_tombstone_hash) = 32
    ),
    home_loan_account bytea NOT NULL CHECK (octet_length(home_loan_account) = 20),
    lender_address bytea NOT NULL CHECK (octet_length(lender_address) = 20),
    wrapped_token bytea NOT NULL CHECK (octet_length(wrapped_token) = 20),
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    policy_hash bytea NOT NULL CHECK (octet_length(policy_hash) = 32),
    reason_code bytea NOT NULL CHECK (octet_length(reason_code) = 32),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    requested_at timestamptz NOT NULL,
    FOREIGN KEY (route_id) REFERENCES crosschain.routes(route_id)
);

-- Action 14 is a typed satellite funding-cancellation completion. It is
-- separate from generic recovery compensation and binds both the satellite
-- escrow burn receipt and the home refund execution receipt.
CREATE TABLE crosschain.loan_cancellation_completions (
    cancellation_id text PRIMARY KEY
        REFERENCES crosschain.loan_cancellation_requests(cancellation_id),
    loan_id text NOT NULL UNIQUE REFERENCES crosschain.loan_routes(loan_id),
    funding_lock_id text NOT NULL,
    message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    route_id text NOT NULL,
    source_component bytea NOT NULL CHECK (octet_length(source_component) = 20),
    destination_component bytea NOT NULL CHECK (octet_length(destination_component) = 20),
    disbursement_message_id bytea NOT NULL CHECK (
        octet_length(disbursement_message_id) = 32
    ),
    disbursement_tombstone_hash bytea NOT NULL CHECK (
        octet_length(disbursement_tombstone_hash) = 32
    ),
    escrow_burn_result_hash bytea NOT NULL CHECK (
        octet_length(escrow_burn_result_hash) = 32
    ),
    home_loan_account bytea NOT NULL CHECK (octet_length(home_loan_account) = 20),
    lender_address bytea NOT NULL CHECK (octet_length(lender_address) = 20),
    lender_id text NOT NULL,
    wrapped_token bytea NOT NULL CHECK (octet_length(wrapped_token) = 20),
    wrapped_asset_id text NOT NULL,
    canonical_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    policy_hash bytea NOT NULL CHECK (octet_length(policy_hash) = 32),
    source_burn_transaction_hash bytea NOT NULL CHECK (
        octet_length(source_burn_transaction_hash) = 32
    ),
    source_burn_log_index numeric(20, 0) NOT NULL CHECK (source_burn_log_index >= 0),
    source_burn_evidence_hash bytea NOT NULL CHECK (
        octet_length(source_burn_evidence_hash) = 32
    ),
    source_burn_finalized_at timestamptz NOT NULL,
    destination_refund_transaction_hash bytea NOT NULL CHECK (
        octet_length(destination_refund_transaction_hash) = 32
    ),
    destination_refund_log_index numeric(20, 0) NOT NULL CHECK (
        destination_refund_log_index >= 0
    ),
    destination_refund_result_hash bytea NOT NULL CHECK (
        octet_length(destination_refund_result_hash) = 32
    ),
    destination_refund_finalized_at timestamptz NOT NULL,
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    FOREIGN KEY (route_id) REFERENCES crosschain.routes(route_id),
    UNIQUE (source_burn_transaction_hash, source_burn_log_index),
    UNIQUE (destination_refund_transaction_hash, destination_refund_log_index)
);

CREATE TABLE crosschain.bridge_exposure_snapshots (
    snapshot_id text PRIMARY KEY,
    route_id text NOT NULL,
    route_version bigint NOT NULL,
    policy_version bigint NOT NULL REFERENCES crosschain.bridge_exposure_policies(policy_version),
    chain_id numeric(78, 0) NOT NULL,
    adapter_id text NOT NULL,
    route_escrow_units numeric(78, 0) NOT NULL CHECK (route_escrow_units >= 0),
    chain_escrow_units numeric(78, 0) NOT NULL CHECK (chain_escrow_units >= 0),
    adapter_escrow_units numeric(78, 0) NOT NULL CHECK (adapter_escrow_units >= 0),
    aggregate_escrow_units numeric(78, 0) NOT NULL CHECK (aggregate_escrow_units >= 0),
    circulating_supply_reference_units numeric(78, 0) NOT NULL CHECK (
        circulating_supply_reference_units > 0
    ),
    circulating_supply_evidence_hash bytea NOT NULL CHECK (
        octet_length(circulating_supply_evidence_hash) = 32
    ),
    calculated_headroom_units numeric(78, 0) NOT NULL CHECK (calculated_headroom_units >= 0),
    block_number numeric(78, 0) NOT NULL CHECK (block_number >= 0),
    block_hash bytea NOT NULL CHECK (octet_length(block_hash) = 32),
    evidence_hash bytea NOT NULL UNIQUE CHECK (octet_length(evidence_hash) = 32),
    observed_at timestamptz NOT NULL,
    FOREIGN KEY (route_id, route_version)
        REFERENCES crosschain.route_versions(route_id, version),
    UNIQUE (route_id, route_version, block_number)
);

CREATE TABLE crosschain.bridge_backing_snapshots (
    snapshot_id text PRIMARY KEY,
    route_id text NOT NULL,
    route_version bigint NOT NULL,
    canonical_asset_id text NOT NULL,
    wrapped_asset_id text NOT NULL,
    canonical_escrow_units numeric(78, 0) NOT NULL CHECK (canonical_escrow_units >= 0),
    wrapped_supply_units numeric(78, 0) NOT NULL CHECK (wrapped_supply_units >= 0),
    pending_mint_units numeric(78, 0) NOT NULL CHECK (pending_mint_units >= 0),
    pending_burn_units numeric(78, 0) NOT NULL CHECK (pending_burn_units >= 0),
    home_block_hash bytea NOT NULL CHECK (octet_length(home_block_hash) = 32),
    satellite_block_hash bytea NOT NULL CHECK (octet_length(satellite_block_hash) = 32),
    evidence_hash bytea NOT NULL UNIQUE CHECK (octet_length(evidence_hash) = 32),
    observed_at timestamptz NOT NULL,
    FOREIGN KEY (route_id, route_version)
        REFERENCES crosschain.route_versions(route_id, version),
    CHECK (wrapped_supply_units <= canonical_escrow_units)
);

CREATE TABLE crosschain.bridge_reconciliations (
    run_id text PRIMARY KEY,
    route_id text NOT NULL,
    route_version bigint NOT NULL,
    home_head_hash bytea NOT NULL CHECK (octet_length(home_head_hash) = 32),
    satellite_head_hash bytea NOT NULL CHECK (octet_length(satellite_head_hash) = 32),
    backing_snapshot_id text NOT NULL UNIQUE
        REFERENCES crosschain.bridge_backing_snapshots(snapshot_id),
    exposure_snapshot_id text NOT NULL UNIQUE
        REFERENCES crosschain.bridge_exposure_snapshots(snapshot_id),
    ledger_snapshot_hash bytea NOT NULL CHECK (octet_length(ledger_snapshot_hash) = 32),
    status text NOT NULL CHECK (status IN ('OPEN', 'MATCHED', 'EXCEPTION', 'RESOLVED')),
    owner text NOT NULL,
    started_at timestamptz NOT NULL,
    completed_at timestamptz,
    FOREIGN KEY (route_id, route_version)
        REFERENCES crosschain.route_versions(route_id, version),
    CHECK ((status = 'OPEN') = (completed_at IS NULL))
);

CREATE TABLE crosschain.bridge_reconciliation_differences (
    difference_id text PRIMARY KEY,
    run_id text NOT NULL REFERENCES crosschain.bridge_reconciliations(run_id),
    dimension text NOT NULL,
    reason_code text NOT NULL,
    asset_id text NOT NULL,
    expected_units numeric(78, 0) NOT NULL,
    observed_units numeric(78, 0) NOT NULL,
    message_id bytea REFERENCES crosschain.messages(message_id),
    loan_id text REFERENCES crosschain.loan_routes(loan_id),
    severity text NOT NULL CHECK (severity IN ('MEDIUM', 'HIGH', 'CRITICAL', 'EXISTENTIAL')),
    owner text NOT NULL,
    detected_at timestamptz NOT NULL,
    resolution_deadline timestamptz NOT NULL,
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    status text NOT NULL CHECK (status IN ('OPEN', 'INVESTIGATING', 'RESOLVED')),
    resolution_reference text,
    CHECK (resolution_deadline > detected_at),
    CHECK ((status = 'RESOLVED') = (resolution_reference IS NOT NULL))
);

CREATE TABLE ledger.bridge_journal_links (
    link_id text PRIMARY KEY,
    message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    route_id text NOT NULL,
    bridge_effect text NOT NULL CHECK (
        bridge_effect IN (
            'LOCK', 'MINT', 'BURN', 'RELEASE', 'PERMANENT_BURN',
            'COMPENSATION', 'LOAN_CANCELLATION_BURN',
            'LOAN_CANCELLATION_REFUND', 'RECONCILIATION_DIFFERENCE'
        )
    ),
    journal_id text NOT NULL UNIQUE REFERENCES public.journal(journal_id),
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    UNIQUE (message_id, bridge_effect, journal_id)
);

CREATE FUNCTION crosschain.link_bridge_journal(
    link_id_ text,
    message_id_ bytea,
    route_id_ text,
    bridge_effect_ text,
    journal_id_ text,
    asset_id_ text,
    units_ numeric,
    evidence_hash_ bytea
) RETURNS ledger.bridge_journal_links
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain, ledger
AS $function$
DECLARE
    result ledger.bridge_journal_links;
BEGIN
    INSERT INTO ledger.bridge_journal_links (
        link_id, message_id, route_id, bridge_effect,
        journal_id, asset_id, units, evidence_hash
    ) VALUES (
        link_id_, message_id_, route_id_, bridge_effect_,
        journal_id_, asset_id_, units_, evidence_hash_
    )
    ON CONFLICT (link_id) DO NOTHING
    RETURNING * INTO result;
    IF result.link_id IS NULL THEN
        SELECT * INTO result
        FROM ledger.bridge_journal_links
        WHERE link_id = link_id_;
    END IF;
    IF result.link_id IS NULL OR result.message_id <> message_id_
       OR result.route_id <> route_id_
       OR result.bridge_effect <> bridge_effect_
       OR result.journal_id <> journal_id_
       OR result.asset_id <> asset_id_ OR result.units <> units_
       OR result.evidence_hash <> evidence_hash_ THEN
        RAISE EXCEPTION 'conflicting bridge journal link replay';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.post_bridge_journal(
    message_id_ bytea,
    route_id_ text,
    bridge_effect_ text,
    suffix_ text,
    entry_type_ text,
    loan_id_ text,
    asset_id_ text,
    units_ numeric,
    debit_account_ text,
    credit_account_ text,
    party_id_ text
) RETURNS ledger.bridge_journal_links
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain, ledger
AS $function$
DECLARE
    posted public.journal;
    projection crosschain.action_projections;
    link_id_ text;
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
    link_id_ := encode(message_id_, 'hex') || ':' || suffix_;
    RETURN crosschain.link_bridge_journal(
        link_id_, message_id_, route_id_, bridge_effect_,
        posted.journal_id, asset_id_, units_, projection.projection_hash
    );
END;
$function$;

CREATE FUNCTION crosschain.activate_bridge_exposure_policy(
    policy_version_ bigint,
    circulating_supply_reference_units_ numeric,
    circulating_supply_evidence_hash_ bytea,
    route_absolute_cap_units_ numeric,
    chain_absolute_cap_units_ numeric,
    adapter_absolute_cap_units_ numeric,
    aggregate_absolute_cap_units_ numeric,
    route_percentage_basis_points_ integer,
    aggregate_percentage_basis_points_ integer,
    effective_at_ timestamptz
) RETURNS crosschain.bridge_exposure_policies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.bridge_exposure_policies;
BEGIN
    LOCK TABLE crosschain.bridge_exposure_policies IN SHARE ROW EXCLUSIVE MODE;
    SELECT * INTO result
    FROM crosschain.bridge_exposure_policies
    WHERE policy_version = policy_version_;
    IF result.policy_version IS NOT NULL THEN
        IF result.circulating_supply_reference_units <>
               circulating_supply_reference_units_
           OR result.circulating_supply_evidence_hash <>
               circulating_supply_evidence_hash_
           OR result.route_absolute_cap_units <> route_absolute_cap_units_
           OR result.chain_absolute_cap_units <> chain_absolute_cap_units_
           OR result.adapter_absolute_cap_units <> adapter_absolute_cap_units_
           OR result.aggregate_absolute_cap_units <> aggregate_absolute_cap_units_
           OR result.route_percentage_basis_points <> route_percentage_basis_points_
           OR result.aggregate_percentage_basis_points <>
               aggregate_percentage_basis_points_
           OR result.effective_at <> effective_at_ THEN
            RAISE EXCEPTION 'conflicting bridge exposure policy replay';
        END IF;
        RETURN result;
    END IF;
    UPDATE crosschain.bridge_exposure_policies
    SET status = 'DEPRECATED'
    WHERE status = 'ACTIVE';
    INSERT INTO crosschain.bridge_exposure_policies (
        policy_version, circulating_supply_reference_units,
        circulating_supply_evidence_hash, route_absolute_cap_units,
        chain_absolute_cap_units, adapter_absolute_cap_units,
        aggregate_absolute_cap_units, route_percentage_basis_points,
        aggregate_percentage_basis_points, effective_at, status
    ) VALUES (
        policy_version_, circulating_supply_reference_units_,
        circulating_supply_evidence_hash_, route_absolute_cap_units_,
        chain_absolute_cap_units_, adapter_absolute_cap_units_,
        aggregate_absolute_cap_units_, route_percentage_basis_points_,
        aggregate_percentage_basis_points_, effective_at_, 'ACTIVE'
    )
    ON CONFLICT (policy_version) DO NOTHING
    RETURNING * INTO result;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_remote_repayment(
    payment_id_ text,
    loan_id_ text,
    burn_id_ text,
    burn_message_id_ bytea,
    canonical_release_result_hash_ bytea,
    asset_id_ text,
    units_ numeric,
    debt_before_units_ numeric,
    debt_after_units_ numeric,
    lender_id_ text,
    home_transaction_hash_ bytea,
    home_log_index_ numeric,
    evidence_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.repayment_results
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    loan crosschain.loan_routes;
    burn crosschain.wrapped_burns;
    release crosschain.canonical_releases;
    projection crosschain.action_projections;
    result crosschain.repayment_results;
    repaid numeric;
BEGIN
    PERFORM crosschain.require_finalized_message(
        burn_message_id_,
        8::smallint
    );
    projection := crosschain.require_action_projection(
        burn_message_id_,
        8::smallint
    );
    SELECT * INTO burn
    FROM crosschain.wrapped_burns
    WHERE burn_id = burn_id_;
    SELECT * INTO release
    FROM crosschain.canonical_releases
    WHERE burn_id = burn_id_;
    SELECT * INTO loan
    FROM crosschain.loan_routes
    WHERE loan_id = loan_id_
    FOR UPDATE;

    IF projection.projection ->> 'payment_id' <> payment_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR projection.projection ->> 'burn_id' <> burn_id_
       OR projection.projection ->> 'asset_id' <> asset_id_
       OR projection.projection ->> 'wrapped_asset_id' <>
          burn.wrapped_asset_id
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projection ->> 'lender_id' <> lender_id_
       OR projection.projection_hash <> evidence_hash_
       OR projection.projected_at <> finalized_at_
       OR burn.burn_id IS NULL
       OR burn.payment_id <> payment_id_
       OR burn.message_id <> burn_message_id_
       OR burn.burn_kind <> 'LOAN_REPAYMENT'
       OR burn.units <> units_
       OR burn.registry_recipient <> lender_id_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               (projection.projection ->> 'burn_finalized_at')::timestamptz
                   <> burn.finalized_at
               OR (projection.projection ->> 'release_finalized_at')::timestamptz
                   <> finalized_at_
               OR NOT EXISTS (
                   SELECT 1
                   FROM crosschain.source_proofs
                   WHERE message_id = burn_message_id_
                     AND transaction_hash = burn.transaction_hash
                     AND log_index = burn.log_index
               )
           )
       )
       OR (
           projection.projection ->> 'proof_boundary' IS DISTINCT FROM
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND NOT EXISTS (
               SELECT 1
               FROM crosschain.execution_results
               WHERE message_id = burn_message_id_
                 AND transaction_hash = burn.transaction_hash
                 AND log_index = burn.log_index
           )
       ) THEN
        RAISE EXCEPTION
            'remote repayment disagrees with authenticated action projection';
    END IF;
    IF loan.loan_id IS NULL
       OR loan.principal_asset_id <> asset_id_
       OR loan.lender_id <> lender_id_
       OR release.release_id IS NULL
       OR release.result_hash <> canonical_release_result_hash_
       OR release.canonical_asset_id <> asset_id_
       OR release.units <> units_
       OR release.registry_recipient <> lender_id_
       OR release.transaction_hash <> home_transaction_hash_
       OR release.log_index <> home_log_index_
       OR release.finalized_at <> finalized_at_ THEN
        RAISE EXCEPTION
            'remote repayment disagrees with immutable canonical release';
    END IF;

    SELECT * INTO result
    FROM crosschain.repayment_results
    WHERE payment_id = payment_id_;
    IF result.payment_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_ OR result.burn_id <> burn_id_
           OR result.burn_message_id <> burn_message_id_
           OR result.canonical_release_result_hash <>
              canonical_release_result_hash_
           OR result.asset_id <> asset_id_ OR result.units <> units_
           OR result.debt_before_units <> debt_before_units_
           OR result.debt_after_units <> debt_after_units_
           OR result.lender_id <> lender_id_
           OR result.home_transaction_hash <> home_transaction_hash_
           OR result.home_log_index <> home_log_index_
           OR result.evidence_hash <> evidence_hash_
           OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting remote repayment replay';
        END IF;
        PERFORM crosschain.post_satellite_settlement_journal(
            burn_message_id_, payment_id_, 'REMOTE_REPAYMENT', payment_id_,
            loan_id_, 'repayment-debt', 'REMOTE_REPAYMENT',
            asset_id_, units_, '2310', '1310', lender_id_
        );
        RETURN result;
    END IF;
    IF loan.lifecycle_state <> 'ACTIVE' THEN
        RAISE EXCEPTION 'repayment does not match immutable active loan';
    END IF;
    SELECT
        COALESCE((
            SELECT SUM(units)
            FROM crosschain.repayment_results
            WHERE loan_id = loan_id_
        ), 0)
        + COALESCE((
            SELECT SUM(units)
            FROM crosschain.direct_home_repayment_results
            WHERE loan_id = loan_id_
        ), 0)
    INTO repaid;
    IF repaid + units_ > loan.principal_units
       OR debt_before_units_ <> loan.principal_units - repaid
       OR debt_after_units_ <> loan.principal_units - repaid - units_ THEN
        RAISE EXCEPTION
            'repayment exceeds or disagrees with canonical debt';
    END IF;
    INSERT INTO crosschain.repayment_results (
        payment_id, loan_id, burn_id, burn_message_id,
        canonical_release_result_hash, asset_id, units,
        debt_before_units, debt_after_units, lender_id,
        home_transaction_hash, home_log_index, evidence_hash, finalized_at
    ) VALUES (
        payment_id_, loan_id_, burn_id_, burn_message_id_,
        canonical_release_result_hash_, asset_id_, units_,
        debt_before_units_, debt_after_units_, lender_id_,
        home_transaction_hash_, home_log_index_, evidence_hash_, finalized_at_
    )
    RETURNING * INTO result;
    IF debt_after_units_ = 0 THEN
        UPDATE crosschain.loan_routes
        SET lifecycle_state = 'CLOSING',
            state_version = state_version + 1,
            updated_at = finalized_at_
        WHERE loan_id = loan_id_ AND lifecycle_state = 'ACTIVE';
    END IF;
    PERFORM crosschain.post_satellite_settlement_journal(
        burn_message_id_, payment_id_, 'REMOTE_REPAYMENT', payment_id_,
        loan_id_, 'repayment-debt', 'REMOTE_REPAYMENT',
        asset_id_, units_, '2310', '1310', lender_id_
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_bridge_lock(
    lock_id_ text,
    route_id_ text,
    route_version_ bigint,
    policy_version_ bigint,
    chain_id_ numeric,
    adapter_id_ text,
    message_id_ bytea,
    canonical_asset_id_ text,
    wrapped_asset_id_ text,
    units_ numeric,
    lender_id_ text,
    loan_id_ text,
    transaction_hash_ bytea,
    log_index_ numeric,
    evidence_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.bridge_locks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    policy crosschain.bridge_exposure_policies;
    route_units numeric;
    chain_units numeric;
    adapter_units numeric;
    aggregate_units numeric;
    result crosschain.bridge_locks;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(message_id_, 1::smallint);
    projection := crosschain.require_action_projection(message_id_, 1::smallint);
    IF projection.projection ->> 'lock_id' <> lock_id_
       OR projection.projection ->> 'route_id' <> route_id_
       OR (projection.projection ->> 'route_version')::bigint <>
          route_version_
       OR (projection.projection ->> 'chain_id')::numeric <> chain_id_
       OR projection.projection ->> 'adapter_id' <> adapter_id_
       OR projection.projection ->> 'canonical_asset_id' <>
          canonical_asset_id_
       OR projection.projection ->> 'wrapped_asset_id' <> wrapped_asset_id_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projection ->> 'lender_id' <> lender_id_
       OR projection.projection ->> 'loan_id' IS DISTINCT FROM loan_id_
       OR projection.projection_hash <> evidence_hash_
       OR projection.projected_at <> finalized_at_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'effect_message_id',
                   'hex'
               ) <> message_id_
               OR decode(
                   projection.projection ->> 'effect_transaction_hash',
                   'hex'
               ) <> transaction_hash_
               OR (projection.projection ->> 'effect_log_index')::numeric <>
                  log_index_
               OR NOT EXISTS (
                   SELECT 1
                   FROM crosschain.source_proofs AS proof
                   WHERE proof.message_id = message_id_
                     AND proof.transaction_hash = transaction_hash_
                     AND proof.log_index = log_index_
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
           FROM crosschain.messages AS message
           JOIN crosschain.route_versions AS route
             ON route.route_policy_hash = message.route_policy_hash
           JOIN crosschain.execution_results AS execution
             ON execution.message_id = message.message_id
           WHERE message.message_id = message_id_
             AND route.route_id = route_id_
             AND route.version = route_version_
             AND execution.transaction_hash = transaction_hash_
             AND execution.log_index = log_index_
           )
       ) THEN
        RAISE EXCEPTION 'bridge lock disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.bridge_locks WHERE lock_id = lock_id_;
    IF result.lock_id IS NOT NULL THEN
        IF result.route_id <> route_id_ OR result.route_version <> route_version_
           OR result.policy_version <> policy_version_ OR result.chain_id <> chain_id_
           OR result.adapter_id <> adapter_id_ OR result.message_id <> message_id_
           OR result.canonical_asset_id <> canonical_asset_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.lender_id <> lender_id_
           OR result.loan_id IS DISTINCT FROM loan_id_
           OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_ OR result.evidence_hash <> evidence_hash_
           OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting bridge lock replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, route_id_, 'LOCK', 'bridge-lock-financial',
            'CANONICAL_LOCK', loan_id_, canonical_asset_id_, units_,
            '1410', '2230', lender_id_
        );
        PERFORM crosschain.post_bridge_journal(
            message_id_, route_id_, 'LOCK', 'bridge-lock-control',
            'CANONICAL_LOCK', loan_id_, canonical_asset_id_, units_,
            '7150', '9150', lender_id_
        );
        RETURN result;
    END IF;
    SELECT * INTO policy FROM crosschain.bridge_exposure_policies
    WHERE policy_version = policy_version_
      AND status = 'ACTIVE' AND effective_at <= finalized_at_
    FOR UPDATE;
    IF policy.policy_version IS NULL THEN
        RAISE EXCEPTION 'active bridge exposure policy required';
    END IF;
    SELECT COALESCE(SUM(units - released_units - permanently_burned_units), 0)
    INTO route_units
    FROM crosschain.bridge_locks
    WHERE route_id = route_id_ AND status NOT IN ('SETTLED', 'COMPENSATED');
    SELECT COALESCE(SUM(units - released_units - permanently_burned_units), 0)
    INTO chain_units
    FROM crosschain.bridge_locks
    WHERE chain_id = chain_id_ AND status NOT IN ('SETTLED', 'COMPENSATED');
    SELECT COALESCE(SUM(units - released_units - permanently_burned_units), 0)
    INTO adapter_units
    FROM crosschain.bridge_locks
    WHERE adapter_id = adapter_id_ AND status NOT IN ('SETTLED', 'COMPENSATED');
    SELECT COALESCE(SUM(units - released_units - permanently_burned_units), 0)
    INTO aggregate_units
    FROM crosschain.bridge_locks
    WHERE status NOT IN ('SETTLED', 'COMPENSATED');
    IF route_units + units_ > policy.route_absolute_cap_units
       OR route_units + units_ >
          policy.circulating_supply_reference_units * policy.route_percentage_basis_points / 10000
       OR chain_units + units_ > policy.chain_absolute_cap_units
       OR adapter_units + units_ > policy.adapter_absolute_cap_units
       OR aggregate_units + units_ > policy.aggregate_absolute_cap_units
       OR aggregate_units + units_ >
          policy.circulating_supply_reference_units * policy.aggregate_percentage_basis_points / 10000 THEN
        RAISE EXCEPTION 'bridge exposure cap exceeded';
    END IF;
    INSERT INTO crosschain.bridge_locks (
        lock_id, route_id, route_version, policy_version, chain_id, adapter_id,
        message_id, canonical_asset_id, wrapped_asset_id, units, lender_id, loan_id,
        status, transaction_hash, log_index, evidence_hash, finalized_at
    ) VALUES (
        lock_id_, route_id_, route_version_, policy.policy_version, chain_id_, adapter_id_,
        message_id_, canonical_asset_id_, wrapped_asset_id_, units_, lender_id_, loan_id_,
        'LOCKED', transaction_hash_, log_index_, evidence_hash_, finalized_at_
    )
    ON CONFLICT (lock_id) DO NOTHING
    RETURNING * INTO result;
    IF result.lock_id IS NULL THEN
        SELECT * INTO result FROM crosschain.bridge_locks WHERE lock_id = lock_id_;
        IF result.route_id <> route_id_ OR result.route_version <> route_version_
           OR result.policy_version <> policy_version_ OR result.chain_id <> chain_id_
           OR result.adapter_id <> adapter_id_ OR result.message_id <> message_id_
           OR result.canonical_asset_id <> canonical_asset_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.lender_id <> lender_id_
           OR result.loan_id IS DISTINCT FROM loan_id_
           OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_ OR result.evidence_hash <> evidence_hash_
           OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting bridge lock replay';
        END IF;
    END IF;
    PERFORM crosschain.post_bridge_journal(
        message_id_, route_id_, 'LOCK', 'bridge-lock-financial',
        'CANONICAL_LOCK', loan_id_, canonical_asset_id_, units_,
        '1410', '2230', lender_id_
    );
    PERFORM crosschain.post_bridge_journal(
        message_id_, route_id_, 'LOCK', 'bridge-lock-control',
        'CANONICAL_LOCK', loan_id_, canonical_asset_id_, units_,
        '7150', '9150', lender_id_
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_wrapped_mint(
    mint_id_ text,
    lock_id_ text,
    message_id_ bytea,
    wrapped_asset_id_ text,
    units_ numeric,
    recipient_ text,
    transaction_hash_ bytea,
    log_index_ numeric,
    supply_after_units_ numeric,
    evidence_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.wrapped_mints
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    lock_record crosschain.bridge_locks;
    result crosschain.wrapped_mints;
    inserted_count bigint;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(message_id_, 2::smallint);
    projection := crosschain.require_action_projection(message_id_, 2::smallint);
    SELECT * INTO lock_record
    FROM crosschain.bridge_locks
    WHERE lock_id = lock_id_;
    IF projection.projection ->> 'mint_id' <> mint_id_
       OR projection.projection ->> 'lock_id' <> lock_id_
       OR projection.projection ->> 'wrapped_asset_id' <> wrapped_asset_id_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projection ->> 'recipient' <> recipient_
       OR (projection.projection ->> 'supply_after_units')::numeric <>
          supply_after_units_
       OR projection.projection_hash <> evidence_hash_
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
                   SELECT 1 FROM crosschain.execution_results
                   WHERE message_id = decode(
                             projection.projection ->> 'effect_message_id',
                             'hex'
                         )
                     AND transaction_hash = transaction_hash_
                     AND log_index = log_index_
               )
               OR (projection.projection ->> 'effect_finalized_at')::timestamptz
                  <> finalized_at_
           )
       )
       OR (
           projection.projection ->> 'proof_boundary' IS DISTINCT FROM
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND NOT EXISTS (
               SELECT 1 FROM crosschain.execution_results
               WHERE message_id = message_id_
                 AND transaction_hash = transaction_hash_
                 AND log_index = log_index_
           )
       ) THEN
        RAISE EXCEPTION 'wrapped mint disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.wrapped_mints WHERE mint_id = mint_id_;
    IF result.mint_id IS NOT NULL THEN
        IF result.lock_id <> lock_id_ OR result.message_id <> message_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.recipient <> recipient_ OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_
           OR result.supply_after_units <> supply_after_units_
           OR result.evidence_hash <> evidence_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting wrapped mint replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'MINT',
            'wrapped-mint-control', 'WRAPPED_MINT', lock_record.loan_id,
            wrapped_asset_id_, units_, '9150', '7160', recipient_
        );
        RETURN result;
    END IF;
    SELECT * INTO lock_record FROM crosschain.bridge_locks
    WHERE lock_id = lock_id_ FOR UPDATE;
    IF lock_record.lock_id IS NULL
       OR lock_record.wrapped_asset_id <> wrapped_asset_id_
       OR lock_record.units <> units_ THEN
        RAISE EXCEPTION 'wrapped mint lacks exact finalized lock';
    END IF;
    INSERT INTO crosschain.wrapped_mints (
        mint_id, lock_id, message_id, wrapped_asset_id, units, recipient,
        transaction_hash, log_index, supply_after_units, evidence_hash, finalized_at
    ) VALUES (
        mint_id_, lock_id_, message_id_, wrapped_asset_id_, units_, recipient_,
        transaction_hash_, log_index_, supply_after_units_, evidence_hash_, finalized_at_
    )
    ON CONFLICT (mint_id) DO NOTHING
    RETURNING * INTO result;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 0 THEN
        SELECT * INTO result FROM crosschain.wrapped_mints WHERE mint_id = mint_id_;
        IF result.lock_id <> lock_id_ OR result.message_id <> message_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.recipient <> recipient_ OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_
           OR result.supply_after_units <> supply_after_units_
           OR result.evidence_hash <> evidence_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting wrapped mint replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'MINT',
            'wrapped-mint-control', 'WRAPPED_MINT', lock_record.loan_id,
            wrapped_asset_id_, units_, '9150', '7160', recipient_
        );
        RETURN result;
    END IF;
    IF lock_record.status <> 'LOCKED' OR lock_record.minted_units <> 0 THEN
        RAISE EXCEPTION 'bridge lock already minted';
    END IF;
    UPDATE crosschain.bridge_locks
    SET minted_units = units_, status = 'MINTED'
    WHERE lock_id = lock_id_;
    PERFORM crosschain.post_bridge_journal(
        message_id_, lock_record.route_id, 'MINT',
        'wrapped-mint-control', 'WRAPPED_MINT', lock_record.loan_id,
        wrapped_asset_id_, units_, '9150', '7160', recipient_
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_wrapped_burn(
    burn_id_ text,
    lock_id_ text,
    message_id_ bytea,
    payment_id_ text,
    wrapped_asset_id_ text,
    units_ numeric,
    registry_recipient_ text,
    burn_kind_ text,
    transaction_hash_ bytea,
    log_index_ numeric,
    supply_after_units_ numeric,
    evidence_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.wrapped_burns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    lock_record crosschain.bridge_locks;
    result crosschain.wrapped_burns;
    inserted_count bigint;
    total_burned numeric;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(
        message_id_,
        (CASE burn_kind_
            WHEN 'LOAN_REPAYMENT' THEN 8
            WHEN 'PERMANENT' THEN 15
            ELSE 3
        END)::smallint
    );
    projection := crosschain.require_action_projection(
        message_id_,
        (CASE burn_kind_
            WHEN 'LOAN_REPAYMENT' THEN 8
            WHEN 'PERMANENT' THEN 15
            ELSE 3
        END)::smallint
    );
    SELECT * INTO lock_record
    FROM crosschain.bridge_locks
    WHERE lock_id = lock_id_;
    IF projection.projection ->> 'burn_id' <> burn_id_
       OR projection.projection ->> 'lock_id' <> lock_id_
       OR projection.projection ->> 'payment_id' IS DISTINCT FROM payment_id_
       OR projection.projection ->> 'wrapped_asset_id' <> wrapped_asset_id_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projection ->> 'registry_recipient' <>
          registry_recipient_
       OR projection.projection ->> 'burn_kind' <> burn_kind_
       OR (projection.projection ->> 'supply_after_units')::numeric <>
          supply_after_units_
       OR projection.projection_hash <> evidence_hash_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'burn_transaction_hash',
                   'hex'
               ) <> transaction_hash_
               OR (projection.projection ->> 'burn_log_index')::numeric <>
                  log_index_
               OR NOT EXISTS (
                   SELECT 1 FROM crosschain.source_proofs
                   WHERE message_id = message_id_
                     AND transaction_hash = transaction_hash_
                     AND log_index = log_index_
               )
               OR (projection.projection ->> 'burn_finalized_at')::timestamptz
                  <> finalized_at_
           )
       )
       OR (
           projection.projection ->> 'proof_boundary' IS DISTINCT FROM
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               projection.projected_at <> finalized_at_
               OR NOT EXISTS (
                   SELECT 1 FROM crosschain.execution_results
                   WHERE message_id = message_id_
                     AND transaction_hash = transaction_hash_
                     AND log_index = log_index_
               )
           )
       ) THEN
        RAISE EXCEPTION 'wrapped burn disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.wrapped_burns WHERE burn_id = burn_id_;
    IF result.burn_id IS NOT NULL THEN
        IF result.lock_id <> lock_id_ OR result.message_id <> message_id_
           OR result.payment_id IS DISTINCT FROM payment_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.registry_recipient <> registry_recipient_
           OR result.burn_kind <> burn_kind_ OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_ OR result.supply_after_units <> supply_after_units_
           OR result.evidence_hash <> evidence_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting wrapped burn replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'BURN',
            'wrapped-burn-control', 'WRAPPED_BURN', lock_record.loan_id,
            wrapped_asset_id_, units_, '7160', '9150',
            registry_recipient_
        );
        RETURN result;
    END IF;
    SELECT * INTO lock_record FROM crosschain.bridge_locks
    WHERE lock_id = lock_id_ FOR UPDATE;
    IF lock_record.lock_id IS NULL
       OR lock_record.status NOT IN ('MINTED', 'PARTIALLY_DISPOSED')
       OR lock_record.wrapped_asset_id <> wrapped_asset_id_
       OR units_ > lock_record.minted_units - lock_record.burned_units THEN
        RAISE EXCEPTION 'wrapped burn exceeds exact finalized mint backing';
    END IF;
    INSERT INTO crosschain.wrapped_burns (
        burn_id, lock_id, message_id, payment_id, wrapped_asset_id, units,
        registry_recipient, burn_kind, transaction_hash, log_index,
        supply_after_units, evidence_hash, finalized_at
    ) VALUES (
        burn_id_, lock_id_, message_id_, payment_id_, wrapped_asset_id_, units_,
        registry_recipient_, burn_kind_, transaction_hash_, log_index_,
        supply_after_units_, evidence_hash_, finalized_at_
    )
    ON CONFLICT (burn_id) DO NOTHING
    RETURNING * INTO result;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 0 THEN
        SELECT * INTO result FROM crosschain.wrapped_burns WHERE burn_id = burn_id_;
        IF result.lock_id <> lock_id_ OR result.message_id <> message_id_
           OR result.payment_id IS DISTINCT FROM payment_id_
           OR result.wrapped_asset_id <> wrapped_asset_id_ OR result.units <> units_
           OR result.registry_recipient <> registry_recipient_
           OR result.burn_kind <> burn_kind_ OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_ OR result.supply_after_units <> supply_after_units_
           OR result.evidence_hash <> evidence_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting wrapped burn replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'BURN',
            'wrapped-burn-control', 'WRAPPED_BURN', lock_record.loan_id,
            wrapped_asset_id_, units_, '7160', '9150',
            registry_recipient_
        );
        RETURN result;
    END IF;
    total_burned := lock_record.burned_units + units_;
    UPDATE crosschain.bridge_locks
    SET burned_units = total_burned,
        status = CASE
            WHEN total_burned = minted_units
                 AND released_units + permanently_burned_units = total_burned
                THEN 'SETTLED'
            WHEN total_burned > 0 THEN 'PARTIALLY_DISPOSED'
            ELSE status
        END
    WHERE lock_id = lock_id_;
    PERFORM crosschain.post_bridge_journal(
        message_id_, lock_record.route_id, 'BURN',
        'wrapped-burn-control', 'WRAPPED_BURN', lock_record.loan_id,
        wrapped_asset_id_, units_, '7160', '9150',
        registry_recipient_
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_canonical_release(
    release_id_ text,
    burn_id_ text,
    message_id_ bytea,
    canonical_asset_id_ text,
    units_ numeric,
    registry_recipient_ text,
    transaction_hash_ bytea,
    log_index_ numeric,
    result_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.canonical_releases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    burn_record crosschain.wrapped_burns;
    lock_record crosschain.bridge_locks;
    result crosschain.canonical_releases;
    inserted_count bigint;
    total_released numeric;
    projection crosschain.action_projections;
    action_type_ smallint;
BEGIN
    SELECT action_type INTO action_type_
    FROM crosschain.messages
    WHERE message_id = message_id_;
    IF action_type_ NOT IN (4, 8) THEN
        RAISE EXCEPTION 'canonical release requires release or repayment action';
    END IF;
    PERFORM crosschain.require_finalized_message(message_id_, action_type_);
    projection := crosschain.require_action_projection(message_id_, action_type_);
    SELECT * INTO burn_record
    FROM crosschain.wrapped_burns
    WHERE burn_id = burn_id_;
    SELECT * INTO lock_record
    FROM crosschain.bridge_locks
    WHERE lock_id = burn_record.lock_id;
    IF projection.projection ->> 'release_id' <> release_id_
       OR projection.projection ->> 'burn_id' <> burn_id_
       OR projection.projection ->> 'canonical_asset_id' <>
          canonical_asset_id_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR projection.projection ->> 'registry_recipient' <>
          registry_recipient_
       OR decode(projection.projection ->> 'result_hash', 'hex') <>
          result_hash_
       OR (
           projection.projection ->> 'proof_boundary' =
               'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
           AND (
               decode(
                   projection.projection ->> 'release_transaction_hash',
                   'hex'
               ) <> transaction_hash_
               OR (projection.projection ->> 'release_log_index')::numeric <>
                  log_index_
               OR (projection.projection ->> 'release_finalized_at')::timestamptz
                  <> finalized_at_
           )
       )
       OR projection.projected_at <> finalized_at_
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.execution_results
           WHERE message_id = message_id_
             AND transaction_hash = transaction_hash_
             AND log_index = log_index_
       ) THEN
        RAISE EXCEPTION 'canonical release disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.canonical_releases WHERE burn_id = burn_id_;
    IF result.burn_id IS NOT NULL THEN
        IF result.release_id <> release_id_ OR result.message_id <> message_id_
           OR result.canonical_asset_id <> canonical_asset_id_ OR result.units <> units_
           OR result.registry_recipient <> registry_recipient_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.result_hash <> result_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting canonical release replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'RELEASE',
            'bridge-disposition-financial', 'CANONICAL_RELEASE',
            lock_record.loan_id, canonical_asset_id_, units_,
            '2230', '1410', registry_recipient_
        );
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'RELEASE',
            'bridge-disposition-control', 'CANONICAL_RELEASE',
            lock_record.loan_id, canonical_asset_id_, units_,
            '9150', '7150', registry_recipient_
        );
        RETURN result;
    END IF;
    SELECT burn.* INTO burn_record
    FROM crosschain.wrapped_burns AS burn
    WHERE burn.burn_id = burn_id_ FOR UPDATE;
    SELECT * INTO lock_record FROM crosschain.bridge_locks
    WHERE lock_id = burn_record.lock_id FOR UPDATE;
    IF burn_record.burn_id IS NULL OR lock_record.lock_id IS NULL
       OR EXISTS (SELECT 1 FROM crosschain.canonical_burns WHERE burn_id = burn_id_)
       OR lock_record.canonical_asset_id <> canonical_asset_id_
       OR burn_record.units <> units_
       OR burn_record.registry_recipient <> registry_recipient_ THEN
        RAISE EXCEPTION 'canonical release lacks exact burn or conflicts with permanent burn';
    END IF;
    INSERT INTO crosschain.canonical_releases (
        release_id, burn_id, message_id, canonical_asset_id, units,
        registry_recipient, transaction_hash, log_index, result_hash, finalized_at
    ) VALUES (
        release_id_, burn_id_, message_id_, canonical_asset_id_, units_,
        registry_recipient_, transaction_hash_, log_index_, result_hash_, finalized_at_
    )
    ON CONFLICT (burn_id) DO NOTHING
    RETURNING * INTO result;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 0 THEN
        SELECT * INTO result FROM crosschain.canonical_releases WHERE burn_id = burn_id_;
        IF result.release_id <> release_id_ OR result.message_id <> message_id_
           OR result.canonical_asset_id <> canonical_asset_id_ OR result.units <> units_
           OR result.registry_recipient <> registry_recipient_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.result_hash <> result_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting canonical release replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'RELEASE',
            'bridge-disposition-financial', 'CANONICAL_RELEASE',
            lock_record.loan_id, canonical_asset_id_, units_,
            '2230', '1410', registry_recipient_
        );
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'RELEASE',
            'bridge-disposition-control', 'CANONICAL_RELEASE',
            lock_record.loan_id, canonical_asset_id_, units_,
            '9150', '7150', registry_recipient_
        );
        RETURN result;
    END IF;
    total_released := lock_record.released_units + units_;
    IF total_released + lock_record.permanently_burned_units > lock_record.burned_units THEN
        RAISE EXCEPTION 'canonical disposition exceeds finalized burns';
    END IF;
    UPDATE crosschain.bridge_locks
    SET released_units = total_released,
        status = CASE
            WHEN burned_units = minted_units
                 AND total_released + permanently_burned_units = burned_units
                THEN 'SETTLED'
            ELSE 'PARTIALLY_DISPOSED'
        END
    WHERE lock_id = burn_record.lock_id;
    PERFORM crosschain.post_bridge_journal(
        message_id_, lock_record.route_id, 'RELEASE',
        'bridge-disposition-financial', 'CANONICAL_RELEASE',
        lock_record.loan_id, canonical_asset_id_, units_,
        '2230', '1410', registry_recipient_
    );
    PERFORM crosschain.post_bridge_journal(
        message_id_, lock_record.route_id, 'RELEASE',
        'bridge-disposition-control', 'CANONICAL_RELEASE',
        lock_record.loan_id, canonical_asset_id_, units_,
        '9150', '7150', registry_recipient_
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_canonical_permanent_burn(
    canonical_burn_id_ text,
    burn_id_ text,
    message_id_ bytea,
    canonical_asset_id_ text,
    units_ numeric,
    transaction_hash_ bytea,
    log_index_ numeric,
    result_hash_ bytea,
    finalized_at_ timestamptz
) RETURNS crosschain.canonical_burns
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    burn_record crosschain.wrapped_burns;
    lock_record crosschain.bridge_locks;
    result crosschain.canonical_burns;
    inserted_count bigint;
    total_permanent numeric;
    projection crosschain.action_projections;
BEGIN
    PERFORM crosschain.require_finalized_message(message_id_, 15::smallint);
    projection := crosschain.require_action_projection(message_id_, 15::smallint);
    SELECT * INTO burn_record
    FROM crosschain.wrapped_burns
    WHERE burn_id = burn_id_;
    SELECT * INTO lock_record
    FROM crosschain.bridge_locks
    WHERE lock_id = burn_record.lock_id;
    IF projection.projection ->> 'canonical_burn_id' <>
          canonical_burn_id_
       OR projection.projection ->> 'burn_id' <> burn_id_
       OR projection.projection ->> 'canonical_asset_id' <>
          canonical_asset_id_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR decode(projection.projection ->> 'result_hash', 'hex') <>
          result_hash_
       OR projection.projected_at <> finalized_at_
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.execution_results
           WHERE message_id = message_id_
             AND transaction_hash = transaction_hash_
             AND log_index = log_index_
       ) THEN
        RAISE EXCEPTION 'permanent burn disagrees with authenticated action projection';
    END IF;
    SELECT * INTO result FROM crosschain.canonical_burns WHERE burn_id = burn_id_;
    IF result.burn_id IS NOT NULL THEN
        IF result.canonical_burn_id <> canonical_burn_id_
           OR result.message_id <> message_id_
           OR result.canonical_asset_id <> canonical_asset_id_ OR result.units <> units_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.result_hash <> result_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting permanent burn replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'PERMANENT_BURN',
            'bridge-disposition-financial', 'PERMANENT_CANONICAL_BURN',
            lock_record.loan_id, canonical_asset_id_, units_,
            '2230', '1410', lock_record.lender_id
        );
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'PERMANENT_BURN',
            'bridge-disposition-control', 'PERMANENT_CANONICAL_BURN',
            lock_record.loan_id, canonical_asset_id_, units_,
            '9150', '7150', lock_record.lender_id
        );
        RETURN result;
    END IF;
    SELECT * INTO burn_record
    FROM crosschain.wrapped_burns
    WHERE burn_id = burn_id_ FOR UPDATE;
    SELECT * INTO lock_record
    FROM crosschain.bridge_locks
    WHERE lock_id = burn_record.lock_id FOR UPDATE;
    IF burn_record.burn_id IS NULL OR burn_record.burn_kind <> 'PERMANENT'
       OR lock_record.lock_id IS NULL
       OR EXISTS (SELECT 1 FROM crosschain.canonical_releases WHERE burn_id = burn_id_)
       OR lock_record.canonical_asset_id <> canonical_asset_id_
       OR burn_record.units <> units_ THEN
        RAISE EXCEPTION 'permanent burn lacks exact burn or conflicts with release';
    END IF;
    INSERT INTO crosschain.canonical_burns (
        canonical_burn_id, burn_id, message_id, canonical_asset_id, units,
        transaction_hash, log_index, result_hash, finalized_at
    ) VALUES (
        canonical_burn_id_, burn_id_, message_id_, canonical_asset_id_, units_,
        transaction_hash_, log_index_, result_hash_, finalized_at_
    )
    ON CONFLICT (burn_id) DO NOTHING
    RETURNING * INTO result;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    IF inserted_count = 0 THEN
        SELECT * INTO result FROM crosschain.canonical_burns WHERE burn_id = burn_id_;
        IF result.canonical_burn_id <> canonical_burn_id_
           OR result.message_id <> message_id_
           OR result.canonical_asset_id <> canonical_asset_id_ OR result.units <> units_
           OR result.transaction_hash <> transaction_hash_ OR result.log_index <> log_index_
           OR result.result_hash <> result_hash_ OR result.finalized_at <> finalized_at_ THEN
            RAISE EXCEPTION 'conflicting permanent burn replay';
        END IF;
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'PERMANENT_BURN',
            'bridge-disposition-financial', 'PERMANENT_CANONICAL_BURN',
            lock_record.loan_id, canonical_asset_id_, units_,
            '2230', '1410', lock_record.lender_id
        );
        PERFORM crosschain.post_bridge_journal(
            message_id_, lock_record.route_id, 'PERMANENT_BURN',
            'bridge-disposition-control', 'PERMANENT_CANONICAL_BURN',
            lock_record.loan_id, canonical_asset_id_, units_,
            '9150', '7150', lock_record.lender_id
        );
        RETURN result;
    END IF;
    total_permanent := lock_record.permanently_burned_units + units_;
    IF total_permanent + lock_record.released_units > lock_record.burned_units THEN
        RAISE EXCEPTION 'canonical disposition exceeds finalized burns';
    END IF;
    UPDATE crosschain.bridge_locks
    SET permanently_burned_units = total_permanent,
        status = CASE
            WHEN burned_units = minted_units
                 AND released_units + total_permanent = burned_units
                THEN 'SETTLED'
            ELSE 'PARTIALLY_DISPOSED'
        END
    WHERE lock_id = burn_record.lock_id;
    PERFORM crosschain.post_bridge_journal(
        message_id_, lock_record.route_id, 'PERMANENT_BURN',
        'bridge-disposition-financial', 'PERMANENT_CANONICAL_BURN',
        lock_record.loan_id, canonical_asset_id_, units_,
        '2230', '1410', lock_record.lender_id
    );
    PERFORM crosschain.post_bridge_journal(
        message_id_, lock_record.route_id, 'PERMANENT_BURN',
        'bridge-disposition-control', 'PERMANENT_CANONICAL_BURN',
        lock_record.loan_id, canonical_asset_id_, units_,
        '9150', '7150', lock_record.lender_id
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.has_exact_tombstoned_disbursement(
    message_id_ bytea,
    aggregate_id_ bytea,
    tombstone_hash_ bytea,
    route_policy_hash_ bytea,
    source_component_ bytea,
    destination_component_ bytea
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
         AND route.route_policy_hash = route_policy_hash_
         AND route.route_id = 'phase8-disbursement'
         AND route.source_component = message.source_component
         AND route.destination_component = message.destination_component
         AND route.source_coordinator = message.source_coordinator
         AND route.destination_coordinator = message.destination_coordinator
        JOIN crosschain.tombstones AS tombstone
          ON tombstone.original_message_id = message.message_id
         AND tombstone.tombstone_hash = tombstone_hash_
        WHERE message.message_id = message_id_
          AND message.action_type = 6
          AND message.state = 'DESTINATION_TOMBSTONED'
          AND message.aggregate_id = aggregate_id_
          AND message.source_component = source_component_
          AND message.destination_component = destination_component_
          AND route.source_component = source_component_
          AND route.destination_component = destination_component_
          AND route.action_family ~ '^0x[0-9a-f]{64}$'
          AND NOT EXISTS (
              SELECT 1 FROM crosschain.execution_results AS execution
              WHERE execution.message_id = message.message_id
          )
          AND NOT EXISTS (
              SELECT 1 FROM crosschain.acknowledgements AS acknowledgement
              WHERE acknowledgement.message_id = message.message_id
          )
          AND EXISTS (
              SELECT 1
              FROM crosschain.source_proofs AS proof
              JOIN crosschain.finality_certificates AS certificate
                ON certificate.message_id = message.message_id
               AND certificate.proof_id = proof.proof_id
              WHERE proof.message_id = message.message_id
                AND proof.chain_id = message.source_chain_id
          )
    );
$function$;

CREATE FUNCTION crosschain.record_loan_cancellation_request(
    cancellation_id_ text,
    loan_id_ text,
    funding_lock_id_ text,
    message_id_ bytea,
    route_id_ text,
    source_component_ bytea,
    destination_component_ bytea,
    disbursement_message_id_ bytea,
    disbursement_tombstone_hash_ bytea,
    home_loan_account_ bytea,
    lender_address_ bytea,
    wrapped_token_ bytea,
    units_ numeric,
    policy_hash_ bytea,
    reason_code_ bytea,
    requested_at_ timestamptz
) RETURNS crosschain.loan_cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    projection crosschain.action_projections;
    message crosschain.messages;
    route crosschain.route_versions;
    loan crosschain.loan_routes;
    result crosschain.loan_cancellation_requests;
BEGIN
    projection := crosschain.require_action_projection(message_id_, 12::smallint);
    SELECT * INTO message FROM crosschain.messages WHERE message_id = message_id_;
    SELECT * INTO route
    FROM crosschain.route_versions
    WHERE route_policy_hash = message.route_policy_hash;
    SELECT * INTO loan FROM crosschain.loan_routes WHERE loan_id = loan_id_ FOR UPDATE;
    SELECT * INTO result
    FROM crosschain.loan_cancellation_requests
    WHERE cancellation_id = cancellation_id_;
    IF route.route_id <> route_id_ OR route_id_ <> 'phase8-disbursement'
       OR message.source_component <> source_component_
       OR message.destination_component <> destination_component_
       OR route.source_component <> source_component_
       OR route.destination_component <> destination_component_
       OR projection.projection ->> 'typed_action' <>
          'LOAN_CANCELLATION_REQUESTED'
       OR projection.projection ->> 'route_id' <> route_id_
       OR projection.projection ->> 'action_family_hash' <>
          route.action_family
       OR decode(projection.projection ->> 'source_component', 'hex') <>
          source_component_
       OR decode(projection.projection ->> 'destination_component', 'hex') <>
          destination_component_
       OR projection.projection ->> 'cancellation_id' <> cancellation_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR projection.projection ->> 'funding_lock_id' <> funding_lock_id_
       OR decode(projection.projection ->> 'disbursement_message_id', 'hex') <>
          disbursement_message_id_
       OR decode(
           projection.projection ->> 'disbursement_tombstone_hash', 'hex'
       ) <> disbursement_tombstone_hash_
       OR decode(projection.projection ->> 'home_loan_account', 'hex') <>
          home_loan_account_
       OR decode(projection.projection ->> 'lender_address', 'hex') <>
          lender_address_
       OR decode(projection.projection ->> 'wrapped_token', 'hex') <>
          wrapped_token_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR decode(projection.projection ->> 'policy_hash', 'hex') <> policy_hash_
       OR decode(projection.projection ->> 'reason_code', 'hex') <> reason_code_
       OR projection.projected_at <> requested_at_
       OR message.aggregate_id <> (CASE
           WHEN loan_id_ ~ '^0x[0-9a-fA-F]{64}$'
               THEN decode(substring(loan_id_ FROM 3), 'hex')
           ELSE sha256(convert_to(loan_id_, 'UTF8'))
       END)
       OR loan.loan_id IS NULL OR loan.home_loan <> home_loan_account_
       OR loan.principal_units <> units_
       OR loan.immutable_policy_hash <> policy_hash_ THEN
        RAISE EXCEPTION
            'cancellation request disagrees with typed action-12 authority';
    END IF;
    IF result.cancellation_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_
           OR result.funding_lock_id <> funding_lock_id_
           OR result.message_id <> message_id_ OR result.route_id <> route_id_
           OR result.source_component <> source_component_
           OR result.destination_component <> destination_component_
           OR result.disbursement_message_id <> disbursement_message_id_
           OR result.disbursement_tombstone_hash <>
              disbursement_tombstone_hash_
           OR result.home_loan_account <> home_loan_account_
           OR result.lender_address <> lender_address_
           OR result.wrapped_token <> wrapped_token_ OR result.units <> units_
           OR result.policy_hash <> policy_hash_
           OR result.reason_code <> reason_code_
           OR result.evidence_hash <> projection.projection_hash
           OR result.requested_at <> requested_at_ THEN
            RAISE EXCEPTION 'conflicting cancellation request replay';
        END IF;
        RETURN result;
    END IF;
    IF loan.lifecycle_state NOT IN ('ACTIVATING', 'RECOVERY')
       OR (
           (disbursement_message_id_ = decode(repeat('00', 32), 'hex'))
           <> (
               disbursement_tombstone_hash_ =
                   decode(repeat('00', 32), 'hex')
           )
       )
       OR (
           disbursement_message_id_ <> decode(repeat('00', 32), 'hex')
           AND (
               message.causation_message_id <> disbursement_message_id_
               OR NOT crosschain.has_exact_tombstoned_disbursement(
                   disbursement_message_id_,
                   message.aggregate_id,
                   disbursement_tombstone_hash_,
                   message.route_policy_hash,
                   source_component_,
                   destination_component_
               )
           )
       )
       OR (
           disbursement_message_id_ = decode(repeat('00', 32), 'hex')
           AND NOT EXISTS (
               SELECT 1
               FROM crosschain.wrapped_mints AS mint
               WHERE mint.lock_id = funding_lock_id_
                 AND mint.message_id = message.causation_message_id
           )
       )
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.bridge_locks AS lock
           WHERE lock.lock_id = funding_lock_id_
             AND lock.loan_id = loan_id_
             AND lock.units = units_
       ) THEN
        RAISE EXCEPTION
            'cancellation request lacks exact eligible pre-state';
    END IF;
    INSERT INTO crosschain.loan_cancellation_requests (
        cancellation_id, loan_id, funding_lock_id, message_id, route_id,
        source_component, destination_component, disbursement_message_id,
        disbursement_tombstone_hash, home_loan_account, lender_address,
        wrapped_token, units, policy_hash, reason_code, evidence_hash,
        requested_at
    ) VALUES (
        cancellation_id_, loan_id_, funding_lock_id_, message_id_, route_id_,
        source_component_, destination_component_, disbursement_message_id_,
        disbursement_tombstone_hash_, home_loan_account_, lender_address_,
        wrapped_token_, units_, policy_hash_, reason_code_,
        projection.projection_hash, requested_at_
    )
    ON CONFLICT (cancellation_id) DO NOTHING
    RETURNING * INTO result;
    IF result.cancellation_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.loan_cancellation_requests
        WHERE cancellation_id = cancellation_id_;
        IF result.loan_id <> loan_id_
           OR result.funding_lock_id <> funding_lock_id_
           OR result.message_id <> message_id_ OR result.route_id <> route_id_
           OR result.source_component <> source_component_
           OR result.destination_component <> destination_component_
           OR result.disbursement_message_id <> disbursement_message_id_
           OR result.disbursement_tombstone_hash <>
              disbursement_tombstone_hash_
           OR result.home_loan_account <> home_loan_account_
           OR result.lender_address <> lender_address_
           OR result.wrapped_token <> wrapped_token_ OR result.units <> units_
           OR result.policy_hash <> policy_hash_
           OR result.reason_code <> reason_code_
           OR result.evidence_hash <> projection.projection_hash
           OR result.requested_at <> requested_at_ THEN
            RAISE EXCEPTION 'conflicting cancellation request replay';
        END IF;
        RETURN result;
    END IF;
    UPDATE crosschain.loan_routes
    SET lifecycle_state = 'RECOVERY', state_version = state_version + 1,
        updated_at = requested_at_
    WHERE loan_id = loan_id_ AND lifecycle_state = 'ACTIVATING';
    -- Deliberately no journal: action 12 is intent, not economic completion.
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.commit_loan_cancellation_completion(
    cancellation_id_ text,
    loan_id_ text,
    funding_lock_id_ text,
    message_id_ bytea,
    route_id_ text,
    source_component_ bytea,
    destination_component_ bytea,
    disbursement_message_id_ bytea,
    disbursement_tombstone_hash_ bytea,
    escrow_burn_result_hash_ bytea,
    home_loan_account_ bytea,
    lender_address_ bytea,
    wrapped_token_ bytea,
    units_ numeric,
    policy_hash_ bytea,
    source_burn_transaction_hash_ bytea,
    source_burn_log_index_ numeric,
    source_burn_evidence_hash_ bytea,
    source_burn_finalized_at_ timestamptz,
    destination_refund_transaction_hash_ bytea,
    destination_refund_log_index_ numeric,
    destination_refund_result_hash_ bytea,
    destination_refund_finalized_at_ timestamptz
) RETURNS crosschain.loan_cancellation_completions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    projection crosschain.action_projections;
    message crosschain.messages;
    route crosschain.route_versions;
    loan crosschain.loan_routes;
    request crosschain.loan_cancellation_requests;
    request_message crosschain.messages;
    lock_record crosschain.bridge_locks;
    result crosschain.loan_cancellation_completions;
BEGIN
    projection := crosschain.require_action_projection(message_id_, 14::smallint);
    SELECT * INTO message FROM crosschain.messages WHERE message_id = message_id_;
    SELECT * INTO route
    FROM crosschain.route_versions
    WHERE route_policy_hash = message.route_policy_hash;
    SELECT * INTO loan FROM crosschain.loan_routes WHERE loan_id = loan_id_;
    SELECT * INTO request
    FROM crosschain.loan_cancellation_requests
    WHERE cancellation_id = cancellation_id_;
    SELECT * INTO request_message
    FROM crosschain.messages
    WHERE message_id = request.message_id;
    SELECT * INTO lock_record
    FROM crosschain.bridge_locks
    WHERE lock_id = funding_lock_id_;
    SELECT * INTO result
    FROM crosschain.loan_cancellation_completions
    WHERE cancellation_id = cancellation_id_;
    IF route.route_id <> route_id_ OR route_id_ <> 'phase8-report'
       OR message.source_component <> source_component_
       OR message.destination_component <> destination_component_
       OR route.source_component <> source_component_
       OR route.destination_component <> destination_component_
       OR projection.projection ->> 'typed_action' <>
          'SATELLITE_FUNDING_CANCELLED'
       OR projection.projection ->> 'route_id' <> route_id_
       OR projection.projection ->> 'action_family_hash' <>
          route.action_family
       OR decode(projection.projection ->> 'source_component', 'hex') <>
          source_component_
       OR decode(projection.projection ->> 'destination_component', 'hex') <>
          destination_component_
       OR projection.projection ->> 'cancellation_id' <> cancellation_id_
       OR projection.projection ->> 'loan_id' <> loan_id_
       OR projection.projection ->> 'funding_lock_id' <> funding_lock_id_
       OR decode(projection.projection ->> 'disbursement_message_id', 'hex') <>
          disbursement_message_id_
       OR decode(
           projection.projection ->> 'disbursement_tombstone_hash', 'hex'
       ) <> disbursement_tombstone_hash_
       OR decode(projection.projection ->> 'escrow_burn_result_hash', 'hex') <>
          escrow_burn_result_hash_
       OR decode(projection.projection ->> 'home_loan_account', 'hex') <>
          home_loan_account_
       OR decode(projection.projection ->> 'lender_address', 'hex') <>
          lender_address_
       OR decode(projection.projection ->> 'wrapped_token', 'hex') <>
          wrapped_token_
       OR (projection.projection ->> 'units')::numeric <> units_
       OR decode(projection.projection ->> 'policy_hash', 'hex') <> policy_hash_
       OR decode(
           projection.projection ->> 'source_burn_transaction_hash', 'hex'
       ) <> source_burn_transaction_hash_
       OR (projection.projection ->> 'source_burn_log_index')::numeric <>
          source_burn_log_index_
       OR decode(
           projection.projection ->> 'source_burn_evidence_hash', 'hex'
       ) <> source_burn_evidence_hash_
       OR (projection.projection ->> 'source_burn_finalized_at')::timestamptz
          <> source_burn_finalized_at_
       OR decode(
           projection.projection ->> 'destination_refund_transaction_hash',
           'hex'
       ) <> destination_refund_transaction_hash_
       OR (projection.projection ->> 'destination_refund_log_index')::numeric
          <> destination_refund_log_index_
       OR decode(
           projection.projection ->> 'destination_refund_result_hash', 'hex'
       ) <> destination_refund_result_hash_
       OR (
           projection.projection ->> 'destination_refund_finalized_at'
       )::timestamptz <> destination_refund_finalized_at_
       OR projection.projected_at <> destination_refund_finalized_at_
       OR message.aggregate_id <> (CASE
           WHEN loan_id_ ~ '^0x[0-9a-fA-F]{64}$'
               THEN decode(substring(loan_id_ FROM 3), 'hex')
           ELSE sha256(convert_to(loan_id_, 'UTF8'))
       END)
       OR request.cancellation_id IS NULL OR request.loan_id <> loan_id_
       OR message.causation_message_id <> request.message_id
       OR message.aggregate_id <> request_message.aggregate_id
       OR request.funding_lock_id <> funding_lock_id_
       OR request.disbursement_message_id <> disbursement_message_id_
       OR request.disbursement_tombstone_hash <>
          disbursement_tombstone_hash_
       OR request.home_loan_account <> home_loan_account_
       OR request.lender_address <> lender_address_
       OR request.wrapped_token <> wrapped_token_ OR request.units <> units_
       OR request.policy_hash <> policy_hash_
       OR loan.loan_id IS NULL
       OR loan.home_loan <> home_loan_account_ OR loan.principal_units <> units_
       OR loan.immutable_policy_hash <> policy_hash_
       OR lock_record.lock_id IS NULL OR lock_record.loan_id <> loan_id_
       OR lock_record.units <> units_ OR lock_record.minted_units <> units_
       OR (
           disbursement_message_id_ = decode(repeat('00', 32), 'hex')
           AND disbursement_tombstone_hash_ <>
               decode(repeat('00', 32), 'hex')
       )
       OR (
           disbursement_message_id_ <> decode(repeat('00', 32), 'hex')
           AND (
               disbursement_tombstone_hash_ =
                   decode(repeat('00', 32), 'hex')
               OR NOT crosschain.has_exact_tombstoned_disbursement(
                   disbursement_message_id_,
                   message.aggregate_id,
                   disbursement_tombstone_hash_,
                   request_message.route_policy_hash,
                   request.source_component,
                   request.destination_component
               )
           )
       )
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.source_proofs AS proof
           WHERE proof.message_id = message_id_
             AND proof.transaction_hash = source_burn_transaction_hash_
             AND proof.log_index = source_burn_log_index_
             AND proof.raw_evidence_object_hash = source_burn_evidence_hash_
       )
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.execution_results AS execution
           WHERE execution.message_id = message_id_
             AND execution.transaction_hash =
                 destination_refund_transaction_hash_
             AND execution.log_index = destination_refund_log_index_
             AND execution.result_hash = destination_refund_result_hash_
             AND execution.executed_at = destination_refund_finalized_at_
       ) THEN
        RAISE EXCEPTION
            'cancellation completion disagrees with typed action-14 authority';
    END IF;
    IF result.cancellation_id IS NOT NULL THEN
        IF result.loan_id <> loan_id_
           OR result.funding_lock_id <> funding_lock_id_
           OR result.message_id <> message_id_ OR result.route_id <> route_id_
           OR result.source_component <> source_component_
           OR result.destination_component <> destination_component_
           OR result.disbursement_message_id <> disbursement_message_id_
           OR result.disbursement_tombstone_hash <>
              disbursement_tombstone_hash_
           OR result.escrow_burn_result_hash <> escrow_burn_result_hash_
           OR result.home_loan_account <> home_loan_account_
           OR result.lender_address <> lender_address_
           OR result.lender_id <> loan.lender_id
           OR result.wrapped_token <> wrapped_token_ OR result.units <> units_
           OR result.wrapped_asset_id <> lock_record.wrapped_asset_id
           OR result.canonical_asset_id <> loan.principal_asset_id
           OR result.policy_hash <> policy_hash_
           OR result.source_burn_transaction_hash <>
              source_burn_transaction_hash_
           OR result.source_burn_log_index <> source_burn_log_index_
           OR result.source_burn_evidence_hash <> source_burn_evidence_hash_
           OR result.source_burn_finalized_at <> source_burn_finalized_at_
           OR result.destination_refund_transaction_hash <>
              destination_refund_transaction_hash_
           OR result.destination_refund_log_index <>
              destination_refund_log_index_
           OR result.destination_refund_result_hash <>
              destination_refund_result_hash_
           OR result.destination_refund_finalized_at <>
              destination_refund_finalized_at_
           OR result.evidence_hash <> projection.projection_hash THEN
            RAISE EXCEPTION 'conflicting cancellation completion replay';
        END IF;
    ELSE
        IF loan.lifecycle_state <> 'RECOVERY'
           OR lock_record.status NOT IN ('MINTED', 'LOCKED')
           OR lock_record.burned_units <> 0
           OR lock_record.released_units <> 0
           OR lock_record.permanently_burned_units <> 0 THEN
            RAISE EXCEPTION
                'cancellation completion conflicts with mutable pre-state';
        END IF;
        INSERT INTO crosschain.loan_cancellation_completions (
            cancellation_id, loan_id, funding_lock_id, message_id, route_id,
            source_component, destination_component, disbursement_message_id,
            disbursement_tombstone_hash, escrow_burn_result_hash,
            home_loan_account, lender_address, lender_id, wrapped_token,
            wrapped_asset_id, canonical_asset_id, units, policy_hash,
            source_burn_transaction_hash, source_burn_log_index,
            source_burn_evidence_hash, source_burn_finalized_at,
            destination_refund_transaction_hash,
            destination_refund_log_index, destination_refund_result_hash,
            destination_refund_finalized_at, evidence_hash
        ) VALUES (
            cancellation_id_, loan_id_, funding_lock_id_, message_id_, route_id_,
            source_component_, destination_component_,
            disbursement_message_id_, disbursement_tombstone_hash_,
            escrow_burn_result_hash_, home_loan_account_, lender_address_,
            loan.lender_id, wrapped_token_, lock_record.wrapped_asset_id,
            loan.principal_asset_id, units_, policy_hash_,
            source_burn_transaction_hash_, source_burn_log_index_,
            source_burn_evidence_hash_, source_burn_finalized_at_,
            destination_refund_transaction_hash_,
            destination_refund_log_index_, destination_refund_result_hash_,
            destination_refund_finalized_at_, projection.projection_hash
        )
        ON CONFLICT (cancellation_id) DO NOTHING
        RETURNING * INTO result;
        IF result.cancellation_id IS NULL THEN
            SELECT * INTO result
            FROM crosschain.loan_cancellation_completions
            WHERE cancellation_id = cancellation_id_;
            IF result.loan_id <> loan_id_
               OR result.funding_lock_id <> funding_lock_id_
               OR result.message_id <> message_id_
               OR result.route_id <> route_id_
               OR result.source_component <> source_component_
               OR result.destination_component <> destination_component_
               OR result.disbursement_message_id <>
                  disbursement_message_id_
               OR result.disbursement_tombstone_hash <>
                  disbursement_tombstone_hash_
               OR result.escrow_burn_result_hash <>
                  escrow_burn_result_hash_
               OR result.home_loan_account <> home_loan_account_
               OR result.lender_address <> lender_address_
               OR result.lender_id <> loan.lender_id
               OR result.wrapped_token <> wrapped_token_
               OR result.wrapped_asset_id <> lock_record.wrapped_asset_id
               OR result.canonical_asset_id <> loan.principal_asset_id
               OR result.units <> units_
               OR result.policy_hash <> policy_hash_
               OR result.source_burn_transaction_hash <>
                  source_burn_transaction_hash_
               OR result.source_burn_log_index <> source_burn_log_index_
               OR result.source_burn_evidence_hash <>
                  source_burn_evidence_hash_
               OR result.source_burn_finalized_at <>
                  source_burn_finalized_at_
               OR result.destination_refund_transaction_hash <>
                  destination_refund_transaction_hash_
               OR result.destination_refund_log_index <>
                  destination_refund_log_index_
               OR result.destination_refund_result_hash <>
                  destination_refund_result_hash_
               OR result.destination_refund_finalized_at <>
                  destination_refund_finalized_at_
               OR result.evidence_hash <> projection.projection_hash THEN
                RAISE EXCEPTION
                    'conflicting cancellation completion replay';
            END IF;
        ELSE
            UPDATE crosschain.bridge_locks
            SET burned_units = units_, released_units = units_,
                status = 'COMPENSATED'
            WHERE lock_id = funding_lock_id_
              AND burned_units = 0 AND released_units = 0
              AND permanently_burned_units = 0;
            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'cancellation completion conflicts with prior disposition';
            END IF;
            UPDATE crosschain.loan_routes
            SET lifecycle_state = 'CANCELLED',
                state_version = state_version + 1,
                updated_at = destination_refund_finalized_at_
            WHERE loan_id = loan_id_ AND lifecycle_state = 'RECOVERY';
            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'cancellation completion lacks recovery-state loan';
            END IF;
        END IF;
    END IF;
    PERFORM crosschain.post_bridge_journal(
        message_id_, route_id_, 'LOAN_CANCELLATION_BURN',
        'loan-cancellation-burn-control', 'LOAN_CANCELLATION_COMPLETE',
        loan_id_, lock_record.wrapped_asset_id, units_,
        '7160', '9150', loan.lender_id
    );
    PERFORM crosschain.post_bridge_journal(
        message_id_, route_id_, 'LOAN_CANCELLATION_REFUND',
        'loan-cancellation-refund-financial', 'LOAN_CANCELLATION_COMPLETE',
        loan_id_, loan.principal_asset_id, units_,
        '2230', '1410', loan.lender_id
    );
    PERFORM crosschain.post_bridge_journal(
        message_id_, route_id_, 'LOAN_CANCELLATION_REFUND',
        'loan-cancellation-refund-control', 'LOAN_CANCELLATION_COMPLETE',
        loan_id_, loan.principal_asset_id, units_,
        '9150', '7150', loan.lender_id
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.open_bridge_reconciliation(
    run_id_ text,
    route_id_ text,
    route_version_ bigint,
    home_head_hash_ bytea,
    satellite_head_hash_ bytea,
    backing_snapshot_id_ text,
    exposure_snapshot_id_ text,
    ledger_snapshot_hash_ bytea,
    owner_ text,
    started_at_ timestamptz
) RETURNS crosschain.bridge_reconciliations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.bridge_reconciliations;
BEGIN
    INSERT INTO crosschain.bridge_reconciliations (
        run_id, route_id, route_version, home_head_hash, satellite_head_hash,
        backing_snapshot_id, exposure_snapshot_id, ledger_snapshot_hash,
        status, owner, started_at, completed_at
    ) VALUES (
        run_id_, route_id_, route_version_, home_head_hash_, satellite_head_hash_,
        backing_snapshot_id_, exposure_snapshot_id_, ledger_snapshot_hash_,
        'OPEN', owner_, started_at_, NULL
    )
    ON CONFLICT (run_id) DO NOTHING
    RETURNING * INTO result;
    IF result.run_id IS NULL THEN
        SELECT * INTO result FROM crosschain.bridge_reconciliations WHERE run_id = run_id_;
        IF result.route_id <> route_id_ OR result.route_version <> route_version_
           OR result.home_head_hash <> home_head_hash_
           OR result.satellite_head_hash <> satellite_head_hash_
           OR result.backing_snapshot_id <> backing_snapshot_id_
           OR result.exposure_snapshot_id <> exposure_snapshot_id_
           OR result.ledger_snapshot_hash <> ledger_snapshot_hash_
           OR result.owner <> owner_ OR result.started_at <> started_at_ THEN
            RAISE EXCEPTION 'conflicting reconciliation run replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_bridge_reconciliation_difference(
    difference_id_ text,
    run_id_ text,
    dimension_ text,
    reason_code_ text,
    asset_id_ text,
    expected_units_ numeric,
    observed_units_ numeric,
    message_id_ bytea,
    loan_id_ text,
    severity_ text,
    owner_ text,
    detected_at_ timestamptz,
    resolution_deadline_ timestamptz,
    evidence_hash_ bytea
) RETURNS crosschain.bridge_reconciliation_differences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.bridge_reconciliation_differences;
    run_status text;
BEGIN
    SELECT * INTO result
    FROM crosschain.bridge_reconciliation_differences
    WHERE difference_id = difference_id_;
    IF result.difference_id IS NOT NULL THEN
        IF result.run_id <> run_id_ OR result.dimension <> dimension_
           OR result.reason_code <> reason_code_ OR result.asset_id <> asset_id_
           OR result.expected_units <> expected_units_
           OR result.observed_units <> observed_units_
           OR result.message_id IS DISTINCT FROM message_id_
           OR result.loan_id IS DISTINCT FROM loan_id_
           OR result.severity <> severity_ OR result.owner <> owner_
           OR result.detected_at <> detected_at_
           OR result.resolution_deadline <> resolution_deadline_
           OR result.evidence_hash <> evidence_hash_ THEN
            RAISE EXCEPTION 'conflicting reconciliation difference replay';
        END IF;
        RETURN result;
    END IF;
    SELECT status INTO run_status
    FROM crosschain.bridge_reconciliations
    WHERE run_id = run_id_
    FOR UPDATE;
    IF run_status IS DISTINCT FROM 'OPEN' THEN
        RAISE EXCEPTION 'reconciliation run is not open';
    END IF;
    INSERT INTO crosschain.bridge_reconciliation_differences (
        difference_id, run_id, dimension, reason_code, asset_id,
        expected_units, observed_units, message_id, loan_id, severity,
        owner, detected_at, resolution_deadline, evidence_hash, status
    ) VALUES (
        difference_id_, run_id_, dimension_, reason_code_, asset_id_,
        expected_units_, observed_units_, message_id_, loan_id_, severity_,
        owner_, detected_at_, resolution_deadline_, evidence_hash_, 'OPEN'
    )
    ON CONFLICT (difference_id) DO NOTHING
    RETURNING * INTO result;
    IF result.difference_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.bridge_reconciliation_differences
        WHERE difference_id = difference_id_;
        IF result.run_id <> run_id_ OR result.dimension <> dimension_
           OR result.reason_code <> reason_code_ OR result.asset_id <> asset_id_
           OR result.expected_units <> expected_units_
           OR result.observed_units <> observed_units_
           OR result.message_id IS DISTINCT FROM message_id_
           OR result.loan_id IS DISTINCT FROM loan_id_
           OR result.severity <> severity_ OR result.owner <> owner_
           OR result.detected_at <> detected_at_
           OR result.resolution_deadline <> resolution_deadline_
           OR result.evidence_hash <> evidence_hash_ THEN
            RAISE EXCEPTION 'conflicting reconciliation difference replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.finalize_bridge_reconciliation(
    run_id_ text,
    completed_at_ timestamptz
) RETURNS crosschain.bridge_reconciliations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.bridge_reconciliations;
    difference_count bigint;
    expected_status text;
    current_run crosschain.bridge_reconciliations;
BEGIN
    SELECT * INTO current_run
    FROM crosschain.bridge_reconciliations
    WHERE run_id = run_id_
    FOR UPDATE;
    IF current_run.run_id IS NULL THEN
        RAISE EXCEPTION 'reconciliation run not found';
    END IF;
    SELECT COUNT(*) INTO difference_count
    FROM crosschain.bridge_reconciliation_differences
    WHERE run_id = run_id_ AND status <> 'RESOLVED';
    expected_status := CASE
        WHEN difference_count = 0 THEN 'MATCHED' ELSE 'EXCEPTION'
    END;
    IF current_run.status <> 'OPEN' THEN
        IF current_run.completed_at <> completed_at_
           OR current_run.status <> expected_status THEN
            RAISE EXCEPTION 'reconciliation run cannot be finalized';
        END IF;
        RETURN current_run;
    END IF;
    UPDATE crosschain.bridge_reconciliations
    SET status = expected_status,
        completed_at = completed_at_
    WHERE run_id = run_id_ AND status = 'OPEN'
    RETURNING * INTO result;
    IF result.run_id IS NULL THEN
        SELECT * INTO result FROM crosschain.bridge_reconciliations WHERE run_id = run_id_;
        IF result.run_id IS NULL OR result.completed_at <> completed_at_
           OR result.status <> expected_status THEN
            RAISE EXCEPTION 'reconciliation run cannot be finalized';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.guard_burn_disposition() RETURNS trigger
LANGUAGE plpgsql AS $function$
BEGIN
    IF TG_TABLE_NAME = 'canonical_releases' AND EXISTS (
        SELECT 1 FROM crosschain.canonical_burns WHERE burn_id = NEW.burn_id
    ) THEN
        RAISE EXCEPTION 'burn already has permanent canonical disposition';
    END IF;
    IF TG_TABLE_NAME = 'canonical_burns' AND EXISTS (
        SELECT 1 FROM crosschain.canonical_releases WHERE burn_id = NEW.burn_id
    ) THEN
        RAISE EXCEPTION 'burn already has canonical release disposition';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER release_excludes_permanent_burn
BEFORE INSERT ON crosschain.canonical_releases
FOR EACH ROW EXECUTE FUNCTION crosschain.guard_burn_disposition();

CREATE TRIGGER permanent_burn_excludes_release
BEFORE INSERT ON crosschain.canonical_burns
FOR EACH ROW EXECUTE FUNCTION crosschain.guard_burn_disposition();

CREATE TRIGGER bridge_lock_immutable_delete
BEFORE DELETE ON crosschain.bridge_locks
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER wrapped_mint_immutable
BEFORE UPDATE OR DELETE ON crosschain.wrapped_mints
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER wrapped_burn_immutable
BEFORE UPDATE OR DELETE ON crosschain.wrapped_burns
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER canonical_release_immutable
BEFORE UPDATE OR DELETE ON crosschain.canonical_releases
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER canonical_burn_immutable
BEFORE UPDATE OR DELETE ON crosschain.canonical_burns
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER loan_cancellation_request_immutable
BEFORE UPDATE OR DELETE ON crosschain.loan_cancellation_requests
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER loan_cancellation_completion_immutable
BEFORE UPDATE OR DELETE ON crosschain.loan_cancellation_completions
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER backing_snapshot_immutable
BEFORE UPDATE OR DELETE ON crosschain.bridge_backing_snapshots
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER exposure_snapshot_immutable
BEFORE UPDATE OR DELETE ON crosschain.bridge_exposure_snapshots
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER reconciliation_difference_immutable_delete
BEFORE DELETE ON crosschain.bridge_reconciliation_differences
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
        WHERE c.relkind = 'r'
          AND (
              n.nspname = 'crosschain'
              OR (n.nspname = 'ledger' AND c.relname = 'bridge_journal_links')
          )
          AND pg_get_userbyid(c.relowner) <> 'unified_crosschain_owner'
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
               'link_bridge_journal', 'post_bridge_journal',
               'activate_bridge_exposure_policy',
               'commit_remote_repayment', 'commit_bridge_lock',
              'commit_wrapped_mint', 'commit_wrapped_burn',
              'commit_canonical_release', 'commit_canonical_permanent_burn',
              'has_exact_tombstoned_disbursement',
              'record_loan_cancellation_request',
              'commit_loan_cancellation_completion',
              'open_bridge_reconciliation',
              'record_bridge_reconciliation_difference',
              'finalize_bridge_reconciliation',
              'guard_burn_disposition'
          )
    LOOP
        EXECUTE format('ALTER FUNCTION %s OWNER TO unified_crosschain_owner', function_name);
    END LOOP;
END;
$ownership$;

REVOKE ALL ON ALL TABLES IN SCHEMA crosschain FROM PUBLIC, unified_crosschain_runtime;
REVOKE ALL ON ledger.bridge_journal_links FROM PUBLIC, unified_crosschain_runtime;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crosschain FROM PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA crosschain TO unified_crosschain_runtime;
GRANT SELECT ON ledger.bridge_journal_links TO unified_crosschain_runtime;
REVOKE ALL ON FUNCTION crosschain.activate_bridge_exposure_policy(
    bigint, numeric, bytea, numeric, numeric, numeric, numeric,
    integer, integer, timestamptz
) FROM PUBLIC, unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_bridge_lock(
    text, text, bigint, bigint, numeric, text, bytea, text, text, numeric, text,
    text, bytea, numeric, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_remote_repayment(
    text, text, text, bytea, bytea, text, numeric, numeric, numeric,
    text, bytea, numeric, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_wrapped_mint(
    text, text, bytea, text, numeric, text, bytea, numeric, numeric,
    bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_wrapped_burn(
    text, text, bytea, text, text, numeric, text, text, bytea, numeric,
    numeric, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_canonical_release(
    text, text, bytea, text, numeric, text, bytea, numeric, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_canonical_permanent_burn(
    text, text, bytea, text, numeric, bytea, numeric, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.record_loan_cancellation_request(
    text, text, text, bytea, text, bytea, bytea, bytea, bytea, bytea,
    bytea, bytea, numeric, bytea, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.commit_loan_cancellation_completion(
    text, text, text, bytea, text, bytea, bytea, bytea, bytea, bytea,
    bytea, bytea, bytea, numeric, bytea, bytea, numeric, bytea, timestamptz,
    bytea, numeric, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.open_bridge_reconciliation(
    text, text, bigint, bytea, bytea, text, text, bytea, text, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.record_bridge_reconciliation_difference(
    text, text, text, text, text, numeric, numeric, bytea, text, text, text,
    timestamptz, timestamptz, bytea
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.finalize_bridge_reconciliation(
    text, timestamptz
) TO unified_crosschain_runtime;

COMMIT;
