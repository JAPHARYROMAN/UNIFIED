BEGIN;

DO $roles$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'unified_crosschain_owner') THEN
        CREATE ROLE unified_crosschain_owner NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'unified_crosschain_runtime') THEN
        CREATE ROLE unified_crosschain_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'unified_crosschain_observer') THEN
        CREATE ROLE unified_crosschain_observer NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'unified_crosschain_finality_attester'
    ) THEN
        CREATE ROLE unified_crosschain_finality_attester
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'unified_crosschain_recovery_verifier'
    ) THEN
        CREATE ROLE unified_crosschain_recovery_verifier
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'unified_crosschain_reorganization_verifier'
    ) THEN
        CREATE ROLE unified_crosschain_reorganization_verifier
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
END;
$roles$;

DO $grant_connect$
BEGIN
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO unified_crosschain_runtime',
        current_database()
    );
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO unified_crosschain_observer',
        current_database()
    );
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO unified_crosschain_finality_attester',
        current_database()
    );
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO unified_crosschain_recovery_verifier',
        current_database()
    );
    EXECUTE format(
        'GRANT CONNECT ON DATABASE %I TO unified_crosschain_reorganization_verifier',
        current_database()
    );
END;
$grant_connect$;

CREATE SCHEMA crosschain AUTHORIZATION unified_crosschain_owner;
REVOKE ALL ON SCHEMA crosschain FROM PUBLIC;
GRANT USAGE ON SCHEMA crosschain TO unified_crosschain_runtime;
GRANT USAGE ON SCHEMA crosschain TO unified_crosschain_observer;
GRANT USAGE ON SCHEMA crosschain TO unified_crosschain_finality_attester;
GRANT USAGE ON SCHEMA crosschain TO unified_crosschain_recovery_verifier;
GRANT USAGE ON SCHEMA crosschain TO unified_crosschain_reorganization_verifier;

CREATE SCHEMA IF NOT EXISTS ledger AUTHORIZATION unified_crosschain_owner;
REVOKE ALL ON SCHEMA ledger FROM PUBLIC;
GRANT USAGE ON SCHEMA ledger TO unified_crosschain_runtime;
GRANT USAGE ON SCHEMA ledger TO unified_crosschain_observer;

-- The Phase 8 accounting helpers execute as the narrowly scoped cross-chain
-- owner and need only append/read access to the immutable base ledger.
GRANT SELECT, INSERT ON public.journal, public.journal_entry
    TO unified_crosschain_owner;
GRANT SELECT ON public.journal_balance TO unified_crosschain_owner;

-- The foundation balance constraint is deferred. Its trigger can therefore
-- fire at COMMIT after a Phase 8 SECURITY DEFINER function has restored the
-- caller role. Give only the fixed trigger predicate the accounting owner's
-- read capability instead of exposing the base ledger to the runtime role.
ALTER FUNCTION public.assert_journal_balanced()
    OWNER TO unified_crosschain_owner;
ALTER FUNCTION public.assert_journal_balanced()
    SECURITY DEFINER;
ALTER FUNCTION public.assert_journal_balanced()
    SET search_path = pg_catalog, public;
REVOKE ALL ON FUNCTION public.assert_journal_balanced()
    FROM PUBLIC, unified_crosschain_runtime;

INSERT INTO chart_account (
    account_code, account_name, account_class, normal_side, specification_version
) VALUES
    ('1410', 'Canonical Assets Locked for Bridging', 'ASSET', 'DEBIT', 'v0.1'),
    ('1420', 'Cross-Chain Settlement Receivable', 'ASSET', 'DEBIT', 'v0.1'),
    ('1430', 'Satellite Asset Receivable', 'ASSET', 'DEBIT', 'v0.1'),
    ('2230', 'Bridge Backing Liability', 'LIABILITY', 'CREDIT', 'v0.1'),
    ('5120', 'Cross-Chain Messaging Expense', 'EXPENSE', 'DEBIT', 'v0.1'),
    ('5320', 'Bridge Loss', 'EXPENSE', 'DEBIT', 'v0.1'),
    ('7150', 'UFT Locked in Bridge Escrow Control', 'CONTROL', 'DEBIT', 'v0.1'),
    ('7160', 'Wrapped UFT Outstanding Control', 'CONTROL', 'CREDIT', 'v0.1'),
    ('9150', 'Pending Cross-Chain Settlement', 'SUSPENSE', 'CREDIT', 'v0.1'),
    ('9180', 'Ledger-to-Chain Reconciliation Difference', 'SUSPENSE', 'DEBIT', 'v0.1');

CREATE TABLE crosschain.chains (
    chain_id numeric(78, 0) PRIMARY KEY CHECK (chain_id > 0),
    active_version bigint NOT NULL CHECK (active_version > 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE crosschain.chain_versions (
    chain_id numeric(78, 0) NOT NULL REFERENCES crosschain.chains(chain_id),
    version bigint NOT NULL CHECK (version > 0),
    coordinator bytea NOT NULL CHECK (octet_length(coordinator) = 20),
    finality_verifier bytea NOT NULL CHECK (octet_length(finality_verifier) = 20),
    configuration_hash bytea NOT NULL CHECK (octet_length(configuration_hash) = 32),
    observer_authority_hash bytea NOT NULL CHECK (octet_length(observer_authority_hash) = 32),
    activated_at_block numeric(78, 0) NOT NULL CHECK (activated_at_block >= 0),
    deprecated_at_block numeric(78, 0),
    status text NOT NULL CHECK (status IN ('ACTIVE', 'DEPRECATED', 'PAUSED')),
    PRIMARY KEY (chain_id, version),
    CHECK (deprecated_at_block IS NULL OR deprecated_at_block >= activated_at_block)
);

CREATE TABLE crosschain.routes (
    route_id text PRIMARY KEY,
    active_version bigint NOT NULL CHECK (active_version > 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE crosschain.route_versions (
    route_id text NOT NULL REFERENCES crosschain.routes(route_id),
    version bigint NOT NULL CHECK (version > 0),
    source_chain_id numeric(78, 0) NOT NULL REFERENCES crosschain.chains(chain_id),
    source_chain_version bigint NOT NULL CHECK (source_chain_version > 0),
    source_coordinator bytea NOT NULL CHECK (octet_length(source_coordinator) = 20),
    source_component bytea NOT NULL CHECK (octet_length(source_component) = 20),
    destination_chain_id numeric(78, 0) NOT NULL REFERENCES crosschain.chains(chain_id),
    destination_chain_version bigint NOT NULL CHECK (destination_chain_version > 0),
    destination_coordinator bytea NOT NULL CHECK (octet_length(destination_coordinator) = 20),
    destination_component bytea NOT NULL CHECK (octet_length(destination_component) = 20),
    action_family text NOT NULL,
    adapter_set_policy_hash bytea NOT NULL CHECK (octet_length(adapter_set_policy_hash) = 32),
    source_finality_policy_hash bytea NOT NULL CHECK (octet_length(source_finality_policy_hash) = 32),
    destination_finality_policy_hash bytea NOT NULL CHECK (octet_length(destination_finality_policy_hash) = 32),
    source_signer_set_hash bytea NOT NULL CHECK (octet_length(source_signer_set_hash) = 32),
    source_signer_set_version bigint NOT NULL CHECK (
        source_signer_set_version BETWEEN 1 AND 4294967295
    ),
    destination_signer_set_hash bytea NOT NULL CHECK (
        octet_length(destination_signer_set_hash) = 32
    ),
    destination_signer_set_version bigint NOT NULL CHECK (
        destination_signer_set_version BETWEEN 1 AND 4294967295
    ),
    route_policy_hash bytea NOT NULL UNIQUE CHECK (octet_length(route_policy_hash) = 32),
    activated_at_block numeric(78, 0) NOT NULL CHECK (activated_at_block >= 0),
    deprecated_at_block numeric(78, 0),
    status text NOT NULL CHECK (status IN ('ACTIVE', 'DEPRECATED', 'PAUSED')),
    PRIMARY KEY (route_id, version),
    CHECK (source_chain_id <> destination_chain_id),
    CHECK (deprecated_at_block IS NULL OR deprecated_at_block >= activated_at_block)
);

CREATE TABLE crosschain.signer_sets (
    signer_set_hash bytea NOT NULL CHECK (octet_length(signer_set_hash) = 32),
    version bigint NOT NULL CHECK (version BETWEEN 1 AND 4294967295),
    threshold integer NOT NULL CHECK (threshold = 2),
    signer_addresses bytea[] NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_until timestamptz NOT NULL,
    status text NOT NULL CHECK (status IN ('ACTIVE', 'DEPRECATED', 'COMPROMISED')),
    PRIMARY KEY (signer_set_hash, version),
    CHECK (
        cardinality(signer_addresses) = 3
        AND array_lower(signer_addresses, 1) = 1
        AND array_upper(signer_addresses, 1) = 3
        AND octet_length(signer_addresses[1]) = 20
        AND octet_length(signer_addresses[2]) = 20
        AND octet_length(signer_addresses[3]) = 20
        AND signer_addresses[1] < signer_addresses[2]
        AND signer_addresses[2] < signer_addresses[3]
    ),
    CHECK (valid_until > valid_from)
);

ALTER TABLE crosschain.route_versions
    ADD FOREIGN KEY (source_chain_id, source_chain_version)
        REFERENCES crosschain.chain_versions(chain_id, version),
    ADD FOREIGN KEY (destination_chain_id, destination_chain_version)
        REFERENCES crosschain.chain_versions(chain_id, version),
    ADD FOREIGN KEY (source_signer_set_hash, source_signer_set_version)
        REFERENCES crosschain.signer_sets(signer_set_hash, version),
    ADD FOREIGN KEY (
        destination_signer_set_hash, destination_signer_set_version
    ) REFERENCES crosschain.signer_sets(signer_set_hash, version);

CREATE TABLE crosschain.messages (
    message_id bytea PRIMARY KEY CHECK (octet_length(message_id) = 32),
    schema_version integer NOT NULL CHECK (schema_version > 0),
    protocol_id bytea NOT NULL CHECK (octet_length(protocol_id) = 32),
    source_chain_id numeric(78, 0) NOT NULL,
    source_coordinator bytea NOT NULL CHECK (octet_length(source_coordinator) = 20),
    source_component bytea NOT NULL CHECK (octet_length(source_component) = 20),
    destination_chain_id numeric(78, 0) NOT NULL,
    destination_coordinator bytea NOT NULL CHECK (octet_length(destination_coordinator) = 20),
    destination_component bytea NOT NULL CHECK (octet_length(destination_component) = 20),
    lane_id bytea NOT NULL CHECK (octet_length(lane_id) = 32),
    source_nonce numeric(20, 0) NOT NULL CHECK (
        source_nonce > 0 AND source_nonce <= 18446744073709551615
    ),
    aggregate_id bytea NOT NULL CHECK (octet_length(aggregate_id) = 32),
    action_type smallint NOT NULL CHECK (action_type BETWEEN 1 AND 16),
    payload_hash bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    message_created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    route_policy_hash bytea NOT NULL REFERENCES crosschain.route_versions(route_policy_hash),
    adapter_set_policy_hash bytea NOT NULL CHECK (octet_length(adapter_set_policy_hash) = 32),
    source_finality_policy_hash bytea NOT NULL CHECK (octet_length(source_finality_policy_hash) = 32),
    destination_finality_policy_hash bytea NOT NULL CHECK (octet_length(destination_finality_policy_hash) = 32),
    correlation_id bytea NOT NULL CHECK (octet_length(correlation_id) = 32),
    causation_message_id bytea NOT NULL CHECK (octet_length(causation_message_id) = 32),
    superseded_message_id bytea NOT NULL CHECK (octet_length(superseded_message_id) = 32),
    serialized_envelope bytea NOT NULL CHECK (octet_length(serialized_envelope) > 0),
    state text NOT NULL CHECK (
        state IN (
            'CREATED', 'SOURCE_FINALIZING', 'SOURCE_FINAL', 'SENT', 'RELAYED',
            'VERIFIED', 'EXECUTED', 'ACK_PENDING', 'ACKNOWLEDGED', 'REJECTED',
            'FAILED', 'EXPIRED', 'RECOVERY_PENDING', 'DESTINATION_TOMBSTONED',
            'SOURCE_COMPENSATED', 'RECOVERED', 'DISPUTED'
        )
    ),
    state_version bigint NOT NULL CHECK (state_version > 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL,
    UNIQUE (source_chain_id, source_coordinator, lane_id, source_nonce),
    UNIQUE (destination_chain_id, destination_coordinator, message_id),
    UNIQUE (destination_chain_id, destination_coordinator, lane_id, source_nonce),
    CHECK (source_chain_id <> destination_chain_id),
    CHECK (expires_at > message_created_at),
    CHECK (
        causation_message_id = decode(repeat('00', 32), 'hex')
        OR causation_message_id <> message_id
    ),
    CHECK (
        superseded_message_id = decode(repeat('00', 32), 'hex')
        OR superseded_message_id <> message_id
    )
);

CREATE TABLE crosschain.message_transitions (
    message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    state_version bigint NOT NULL CHECK (state_version > 0),
    from_state text NOT NULL,
    to_state text NOT NULL,
    failure_class text,
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (message_id, state_version)
);

CREATE TABLE crosschain.source_proofs (
    proof_id text PRIMARY KEY,
    message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    chain_id numeric(78, 0) NOT NULL REFERENCES crosschain.chains(chain_id),
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    transaction_index numeric(20, 0) NOT NULL CHECK (transaction_index >= 0),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    block_number numeric(78, 0) NOT NULL CHECK (block_number >= 0),
    block_hash bytea NOT NULL CHECK (octet_length(block_hash) = 32),
    receipts_root bytea NOT NULL CHECK (octet_length(receipts_root) = 32),
    inclusion_proof_hash bytea NOT NULL CHECK (octet_length(inclusion_proof_hash) = 32),
    event_hash bytea NOT NULL CHECK (octet_length(event_hash) = 32),
    finality_head_number numeric(78, 0) NOT NULL,
    finality_head_hash bytea NOT NULL CHECK (octet_length(finality_head_hash) = 32),
    confirmation_depth numeric(78, 0) NOT NULL CHECK (confirmation_depth > 0),
    finality_policy_hash bytea NOT NULL CHECK (octet_length(finality_policy_hash) = 32),
    observer_authority_hash bytea NOT NULL CHECK (octet_length(observer_authority_hash) = 32),
    observer_signed_header_commitment bytea NOT NULL CHECK (
        octet_length(observer_signed_header_commitment) = 32
    ),
    observer_signature bytea NOT NULL CHECK (octet_length(observer_signature) > 0),
    raw_evidence_object_hash bytea,
    proof_abi bytea,
    proof_hash bytea NOT NULL UNIQUE CHECK (octet_length(proof_hash) = 32),
    observed_at timestamptz NOT NULL,
    UNIQUE (chain_id, transaction_hash, log_index),
    CHECK (finality_head_number >= block_number + confirmation_depth),
    CHECK (
        (raw_evidence_object_hash IS NULL AND proof_abi IS NULL)
        OR (
            octet_length(raw_evidence_object_hash) = 32
            AND octet_length(proof_abi) > 0
        )
    )
);

CREATE TABLE crosschain.finality_certificates (
    certificate_id text PRIMARY KEY,
    message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    proof_id text NOT NULL REFERENCES crosschain.source_proofs(proof_id),
    signer_set_hash bytea NOT NULL CHECK (octet_length(signer_set_hash) = 32),
    signer_set_version bigint NOT NULL CHECK (
        signer_set_version BETWEEN 1 AND 4294967295
    ),
    signer_bitmap bit varying NOT NULL,
    signature_count integer NOT NULL CHECK (signature_count BETWEEN 2 AND 3),
    signatures bytea[],
    certificate_abi bytea,
    certificate_hash bytea NOT NULL UNIQUE CHECK (octet_length(certificate_hash) = 32),
    certified_at timestamptz NOT NULL,
    FOREIGN KEY (signer_set_hash, signer_set_version)
        REFERENCES crosschain.signer_sets(signer_set_hash, version),
    CHECK (bit_length(signer_bitmap) = 3),
    CHECK (
        signature_count =
            length(replace(signer_bitmap::text, '0', ''))
    ),
    CHECK (
        (signatures IS NULL AND certificate_abi IS NULL)
        OR (
            cardinality(signatures) = signature_count
            AND octet_length(certificate_abi) > 0
            AND array_lower(signatures, 1) = 1
            AND octet_length(signatures[1]) = 65
            AND octet_length(signatures[2]) = 65
            AND (
                signature_count = 2
                OR octet_length(signatures[3]) = 65
            )
        )
    )
);

CREATE TABLE crosschain.provider_attempts (
    message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    provider_id text NOT NULL,
    attempt_number integer NOT NULL CHECK (attempt_number > 0),
    serialized_envelope_hash bytea NOT NULL CHECK (octet_length(serialized_envelope_hash) = 32),
    source_proof_hash bytea NOT NULL CHECK (octet_length(source_proof_hash) = 32),
    status text NOT NULL CHECK (status IN ('REQUESTED', 'DELIVERED', 'FAILED')),
    provider_receipt_hash bytea,
    attempted_at timestamptz NOT NULL,
    PRIMARY KEY (message_id, provider_id, attempt_number),
    CHECK (
        (status = 'DELIVERED' AND octet_length(provider_receipt_hash) = 32)
        OR (status <> 'DELIVERED' AND provider_receipt_hash IS NULL)
    )
);

CREATE TABLE crosschain.execution_results (
    message_id bytea PRIMARY KEY REFERENCES crosschain.messages(message_id),
    destination_chain_id numeric(78, 0) NOT NULL,
    transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash) = 32),
    log_index numeric(20, 0) NOT NULL CHECK (log_index >= 0),
    result_hash bytea NOT NULL CHECK (octet_length(result_hash) = 32),
    effect_commitment bytea NOT NULL CHECK (octet_length(effect_commitment) = 32),
    -- The authenticated EVM path retains the exact parsed action projection
    -- beside the outer live receipt identity. Legacy synthetic fixtures remain
    -- nullable and cannot enter the Phase 7C manifest path.
    action_projection jsonb CHECK (
        action_projection IS NULL OR (
            jsonb_typeof(action_projection) = 'object'
            AND action_projection <> '{}'::jsonb
        )
    ),
    destination_proof_id text NOT NULL
        REFERENCES crosschain.source_proofs(proof_id),
    certificate_id text NOT NULL
        REFERENCES crosschain.finality_certificates(certificate_id),
    executed_at timestamptz NOT NULL,
    UNIQUE (destination_chain_id, transaction_hash, log_index),
    UNIQUE (destination_proof_id, certificate_id)
);

CREATE TABLE crosschain.acknowledgements (
    message_id bytea PRIMARY KEY REFERENCES crosschain.execution_results(message_id),
    execution_result_hash bytea NOT NULL CHECK (octet_length(execution_result_hash) = 32),
    destination_proof_id text NOT NULL UNIQUE REFERENCES crosschain.source_proofs(proof_id),
    certificate_id text NOT NULL UNIQUE REFERENCES crosschain.finality_certificates(certificate_id),
    acknowledged_at timestamptz NOT NULL
);

-- Canonical typed-action economics are retained only after the exact
-- destination execution and acknowledgement have been authenticated. Runtime
-- business functions read this immutable projection; they never treat caller
-- JSON or caller-selected economic fields as authority.
CREATE TABLE crosschain.action_projections (
    message_id bytea PRIMARY KEY REFERENCES crosschain.acknowledgements(message_id),
    action_type smallint NOT NULL CHECK (action_type BETWEEN 1 AND 16),
    projection jsonb NOT NULL CHECK (jsonb_typeof(projection) = 'object'),
    projection_hash bytea NOT NULL UNIQUE CHECK (octet_length(projection_hash) = 32),
    execution_result_hash bytea NOT NULL CHECK (
        octet_length(execution_result_hash) = 32
    ),
    destination_proof_id text NOT NULL REFERENCES crosschain.source_proofs(proof_id),
    certificate_id text NOT NULL REFERENCES crosschain.finality_certificates(certificate_id),
    projected_at timestamptz NOT NULL
);

CREATE TABLE crosschain.recovery_authorizer_sets (
    authorizer_set_hash bytea NOT NULL CHECK (octet_length(authorizer_set_hash) = 32),
    version bigint NOT NULL CHECK (version > 0),
    threshold integer NOT NULL CHECK (threshold = 2),
    authorizer_addresses bytea[] NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_until timestamptz NOT NULL,
    status text NOT NULL CHECK (status IN ('ACTIVE', 'DEPRECATED', 'COMPROMISED')),
    PRIMARY KEY (authorizer_set_hash, version),
    CHECK (
        cardinality(authorizer_addresses) = 3
        AND array_lower(authorizer_addresses, 1) = 1
        AND array_upper(authorizer_addresses, 1) = 3
        AND octet_length(authorizer_addresses[1]) = 20
        AND octet_length(authorizer_addresses[2]) = 20
        AND octet_length(authorizer_addresses[3]) = 20
        AND authorizer_addresses[1] < authorizer_addresses[2]
        AND authorizer_addresses[2] < authorizer_addresses[3]
    ),
    CHECK (valid_until > valid_from)
);

CREATE TABLE crosschain.recovery_requests (
    recovery_id bytea PRIMARY KEY CHECK (octet_length(recovery_id) = 32),
    original_message_id bytea NOT NULL UNIQUE REFERENCES crosschain.messages(message_id),
    protocol_id bytea NOT NULL CHECK (octet_length(protocol_id) = 32),
    source_chain_id numeric(78, 0) NOT NULL CHECK (source_chain_id > 0),
    source_coordinator bytea NOT NULL CHECK (octet_length(source_coordinator) = 20),
    destination_chain_id numeric(78, 0) NOT NULL CHECK (destination_chain_id > 0),
    destination_coordinator bytea NOT NULL CHECK (
        octet_length(destination_coordinator) = 20
    ),
    immutable_envelope_hash bytea NOT NULL CHECK (octet_length(immutable_envelope_hash) = 32),
    route_policy_hash bytea NOT NULL CHECK (octet_length(route_policy_hash) = 32),
    asset_amount_commitment bytea NOT NULL CHECK (
        octet_length(asset_amount_commitment) = 32
    ),
    source_state_commitment bytea NOT NULL CHECK (octet_length(source_state_commitment) = 32),
    destination_state_commitment bytea NOT NULL CHECK (octet_length(destination_state_commitment) = 32),
    compensation_payload_hash bytea NOT NULL CHECK (octet_length(compensation_payload_hash) = 32),
    message_expires_at numeric(20, 0) NOT NULL CHECK (
        message_expires_at > 0
        AND message_expires_at <= 18446744073709551615
    ),
    recovery_nonce numeric(20, 0) NOT NULL CHECK (
        recovery_nonce > 0
        AND recovery_nonce <= 18446744073709551615
    ),
    reason_code bytea NOT NULL CHECK (octet_length(reason_code) = 32),
    action smallint NOT NULL CHECK (action = 1),
    authorizer_set_hash bytea NOT NULL CHECK (octet_length(authorizer_set_hash) = 32),
    authorizer_set_version bigint NOT NULL CHECK (authorizer_set_version > 0),
    request_digest bytea NOT NULL UNIQUE CHECK (octet_length(request_digest) = 32),
    signer_bitmap bit varying NOT NULL,
    signature_count integer NOT NULL CHECK (signature_count BETWEEN 2 AND 3),
    authorization_evidence_hash bytea NOT NULL UNIQUE CHECK (
        octet_length(authorization_evidence_hash) = 32
    ),
    verified_at timestamptz NOT NULL,
    FOREIGN KEY (authorizer_set_hash, authorizer_set_version)
        REFERENCES crosschain.recovery_authorizer_sets(authorizer_set_hash, version),
    CHECK (bit_length(signer_bitmap) = 3),
    CHECK (
        signature_count =
            length(replace(signer_bitmap::text, '0', ''))
    )
);

CREATE TABLE crosschain.tombstones (
    original_message_id bytea PRIMARY KEY REFERENCES crosschain.messages(message_id),
    recovery_id bytea NOT NULL UNIQUE REFERENCES crosschain.recovery_requests(recovery_id),
    tombstone_hash bytea NOT NULL UNIQUE CHECK (octet_length(tombstone_hash) = 32),
    destination_state_commitment bytea NOT NULL CHECK (octet_length(destination_state_commitment) = 32),
    destination_proof_id text NOT NULL UNIQUE REFERENCES crosschain.source_proofs(proof_id),
    certificate_id text NOT NULL UNIQUE REFERENCES crosschain.finality_certificates(certificate_id),
    tombstoned_at timestamptz NOT NULL
);

CREATE TABLE crosschain.compensations (
    original_message_id bytea PRIMARY KEY REFERENCES crosschain.tombstones(original_message_id),
    recovery_id bytea NOT NULL UNIQUE REFERENCES crosschain.recovery_requests(recovery_id),
    compensation_type text NOT NULL,
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    recipient text NOT NULL,
    compensation_payload_hash bytea NOT NULL CHECK (
        octet_length(compensation_payload_hash) = 32
    ),
    result_hash bytea NOT NULL UNIQUE CHECK (octet_length(result_hash) = 32),
    source_proof_id text NOT NULL UNIQUE REFERENCES crosschain.source_proofs(proof_id),
    certificate_id text NOT NULL UNIQUE REFERENCES crosschain.finality_certificates(certificate_id),
    compensated_at timestamptz NOT NULL
);

CREATE TABLE ledger.crosschain_recovery_journal_links (
    recovery_id bytea NOT NULL REFERENCES crosschain.recovery_requests(recovery_id),
    journal_role text NOT NULL CHECK (
        journal_role IN ('FINANCIAL_REVERSAL', 'CONTROL_REVERSAL')
    ),
    original_message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    journal_id text NOT NULL UNIQUE REFERENCES public.journal(journal_id),
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    PRIMARY KEY (recovery_id, journal_role)
);

CREATE TABLE crosschain.header_observations (
    observation_id text PRIMARY KEY,
    chain_id numeric(78, 0) NOT NULL REFERENCES crosschain.chains(chain_id),
    block_hash bytea NOT NULL CHECK (octet_length(block_hash) = 32),
    block_number numeric(78, 0) NOT NULL CHECK (block_number > 0),
    header_authority_hash bytea NOT NULL CHECK (
        octet_length(header_authority_hash) = 32
    ),
    observer_signed_header_commitment bytea NOT NULL CHECK (
        octet_length(observer_signed_header_commitment) = 32
    ),
    observer_signature bytea NOT NULL CHECK (octet_length(observer_signature) > 0),
    finality_policy_hash bytea NOT NULL CHECK (octet_length(finality_policy_hash) = 32),
    observed_at timestamptz NOT NULL,
    UNIQUE (chain_id, block_hash),
    UNIQUE (chain_id, block_number, observer_signed_header_commitment)
);

CREATE TABLE crosschain.reorganizations (
    reorganization_id text PRIMARY KEY,
    route_id text NOT NULL REFERENCES crosschain.routes(route_id),
    chain_id numeric(78, 0) NOT NULL REFERENCES crosschain.chains(chain_id),
    orphaned_block_hash bytea NOT NULL CHECK (octet_length(orphaned_block_hash) = 32),
    orphaned_block_number numeric(78, 0) NOT NULL CHECK (orphaned_block_number > 0),
    orphaned_proof_id text NOT NULL REFERENCES crosschain.source_proofs(proof_id),
    orphaned_certificate_id text NOT NULL
        REFERENCES crosschain.finality_certificates(certificate_id),
    orphaned_proof_ids text[] NOT NULL CHECK (
        cardinality(orphaned_proof_ids) BETWEEN 1 AND 256
    ),
    orphaned_certificate_ids text[] NOT NULL CHECK (
        cardinality(orphaned_certificate_ids) BETWEEN 1 AND 256
    ),
    replacement_block_hash bytea NOT NULL CHECK (octet_length(replacement_block_hash) = 32),
    replacement_block_number numeric(78, 0) NOT NULL CHECK (
        replacement_block_number > 0
    ),
    replacement_observation_id text NOT NULL
        REFERENCES crosschain.header_observations(observation_id),
    detected_head_hash bytea NOT NULL CHECK (octet_length(detected_head_hash) = 32),
    detected_head_number numeric(78, 0) NOT NULL CHECK (detected_head_number > 0),
    detected_head_observation_id text NOT NULL
        REFERENCES crosschain.header_observations(observation_id),
    depth_class text NOT NULL CHECK (depth_class = 'DEEP_FINALITY'),
    affected_message_ids bytea[] NOT NULL CHECK (
        cardinality(affected_message_ids) BETWEEN 1 AND 256
    ),
    evidence_hash bytea NOT NULL UNIQUE CHECK (octet_length(evidence_hash) = 32),
    detected_at timestamptz NOT NULL,
    CHECK (cardinality(orphaned_proof_ids) = cardinality(affected_message_ids)),
    CHECK (
        cardinality(orphaned_certificate_ids) =
        cardinality(affected_message_ids)
    ),
    CHECK (orphaned_proof_id = orphaned_proof_ids[1]),
    CHECK (orphaned_certificate_id = orphaned_certificate_ids[1]),
    CHECK (orphaned_block_hash <> replacement_block_hash),
    CHECK (replacement_block_number <= detected_head_number)
);

CREATE TABLE crosschain.incidents (
    incident_id text PRIMARY KEY,
    reorganization_id text NOT NULL UNIQUE
        REFERENCES crosschain.reorganizations(reorganization_id),
    route_id text NOT NULL REFERENCES crosschain.routes(route_id),
    reason_code text NOT NULL,
    severity text NOT NULL CHECK (severity IN ('HIGH', 'CRITICAL', 'EXISTENTIAL')),
    owner text NOT NULL,
    evidence_hash bytea NOT NULL CHECK (octet_length(evidence_hash) = 32),
    affected_message_ids bytea[] NOT NULL,
    status text NOT NULL CHECK (status IN ('OPEN', 'MITIGATING', 'RESOLVED')),
    opened_at timestamptz NOT NULL,
    resolved_at timestamptz,
    CHECK ((status = 'RESOLVED') = (resolved_at IS NOT NULL))
);

CREATE TABLE crosschain.outbox (
    outbox_id text PRIMARY KEY,
    message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    state_version bigint NOT NULL CHECK (state_version > 0),
    topic text NOT NULL,
    partition_key text NOT NULL,
    payload bytea NOT NULL CHECK (octet_length(payload) > 0),
    payload_hash bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    status text NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'CLAIMED', 'PUBLISHED')),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    publisher_id text,
    lease_until timestamptz,
    broker_offset text,
    created_at timestamptz NOT NULL,
    published_at timestamptz,
    UNIQUE (message_id, state_version),
    CHECK (
        (status = 'PENDING' AND attempt_count = 0 AND publisher_id IS NULL
            AND lease_until IS NULL AND broker_offset IS NULL
            AND published_at IS NULL)
        OR
        (status = 'CLAIMED' AND attempt_count > 0 AND publisher_id IS NOT NULL
            AND lease_until IS NOT NULL AND broker_offset IS NULL
            AND published_at IS NULL)
        OR
        (status = 'PUBLISHED' AND attempt_count > 0 AND publisher_id IS NOT NULL
            AND lease_until IS NULL AND broker_offset IS NOT NULL
            AND published_at IS NOT NULL)
    )
);

CREATE TABLE crosschain.inbox (
    consumer_id text NOT NULL,
    message_id bytea NOT NULL REFERENCES crosschain.messages(message_id),
    topic text NOT NULL,
    partition_key text NOT NULL,
    broker_offset text NOT NULL,
    payload_hash bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    consumed_at timestamptz NOT NULL,
    PRIMARY KEY (consumer_id, topic, broker_offset)
);

CREATE FUNCTION crosschain.reject_append_only_mutation() RETURNS trigger
LANGUAGE plpgsql AS $function$
BEGIN
    RAISE EXCEPTION 'crosschain evidence is append-only';
END;
$function$;

CREATE FUNCTION crosschain.guard_terminal_exclusion() RETURNS trigger
LANGUAGE plpgsql AS $function$
BEGIN
    IF TG_TABLE_NAME = 'execution_results' THEN
        IF EXISTS (
            SELECT 1 FROM crosschain.tombstones
            WHERE original_message_id = NEW.message_id
        ) THEN
            RAISE EXCEPTION 'tombstoned message cannot execute';
        END IF;
    ELSIF TG_TABLE_NAME = 'tombstones' THEN
        IF EXISTS (
            SELECT 1 FROM crosschain.execution_results
            WHERE message_id = NEW.original_message_id
        ) THEN
            RAISE EXCEPTION 'executed message cannot be tombstoned';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER execution_result_excludes_tombstone
BEFORE INSERT ON crosschain.execution_results
FOR EACH ROW EXECUTE FUNCTION crosschain.guard_terminal_exclusion();

CREATE TRIGGER tombstone_excludes_execution
BEFORE INSERT ON crosschain.tombstones
FOR EACH ROW EXECUTE FUNCTION crosschain.guard_terminal_exclusion();

CREATE TRIGGER message_transition_immutable
BEFORE UPDATE OR DELETE ON crosschain.message_transitions
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER source_proof_immutable
BEFORE UPDATE OR DELETE ON crosschain.source_proofs
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER finality_certificate_immutable
BEFORE UPDATE OR DELETE ON crosschain.finality_certificates
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER header_observation_immutable
BEFORE UPDATE OR DELETE ON crosschain.header_observations
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER reorganization_immutable
BEFORE UPDATE OR DELETE ON crosschain.reorganizations
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER provider_attempt_immutable
BEFORE UPDATE OR DELETE ON crosschain.provider_attempts
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER execution_result_immutable
BEFORE UPDATE OR DELETE ON crosschain.execution_results
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER tombstone_immutable
BEFORE UPDATE OR DELETE ON crosschain.tombstones
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER compensation_immutable
BEFORE UPDATE OR DELETE ON crosschain.compensations
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER recovery_journal_link_immutable
BEFORE UPDATE OR DELETE ON ledger.crosschain_recovery_journal_links
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE TRIGGER action_projection_immutable
BEFORE UPDATE OR DELETE ON crosschain.action_projections
FOR EACH ROW EXECUTE FUNCTION crosschain.reject_append_only_mutation();

CREATE FUNCTION crosschain.enqueue_message_state_event(
    message_id_ bytea,
    state_version_ bigint,
    state_ text,
    evidence_hash_ bytea,
    occurred_at_ timestamptz
) RETURNS crosschain.outbox
LANGUAGE plpgsql
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.outbox;
    event_payload bytea;
    event_id text;
BEGIN
    IF message_id_ IS NULL OR octet_length(message_id_) <> 32
       OR state_version_ IS NULL OR state_version_ <= 0
       OR state_ IS NULL OR state_ = ''
       OR evidence_hash_ IS NULL OR octet_length(evidence_hash_) <> 32
       OR occurred_at_ IS NULL THEN
        RAISE EXCEPTION 'invalid message state outbox event';
    END IF;

    event_id := 'crosschain.message-state.v1:'
        || encode(message_id_, 'hex') || ':' || state_version_::text;
    event_payload := convert_to(
        jsonb_build_object(
            'evidence_hash', encode(evidence_hash_, 'hex'),
            'message_id', encode(message_id_, 'hex'),
            'occurred_at_epoch_microseconds',
                floor(extract(epoch FROM occurred_at_) * 1000000)::numeric(78, 0),
            'serialized_envelope',
                encode((
                    SELECT serialized_envelope
                    FROM crosschain.messages
                    WHERE message_id = message_id_
                ), 'hex'),
            'state', state_,
            'state_version', state_version_
        )::text,
        'UTF8'
    );

    INSERT INTO crosschain.outbox (
        outbox_id, message_id, state_version, topic, partition_key,
        payload, payload_hash, created_at
    ) VALUES (
        event_id, message_id_, state_version_,
        'unified.crosschain.message-state.v1',
        encode(message_id_, 'hex'),
        event_payload, sha256(event_payload), occurred_at_
    )
    ON CONFLICT (message_id, state_version) DO NOTHING
    RETURNING * INTO result;

    IF result.outbox_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.outbox
        WHERE message_id = message_id_ AND state_version = state_version_;
        IF result.outbox_id <> event_id
           OR result.topic <> 'unified.crosschain.message-state.v1'
           OR result.partition_key <> encode(message_id_, 'hex')
           OR result.payload <> event_payload
           OR result.payload_hash <> sha256(event_payload)
           OR result.created_at <> occurred_at_ THEN
            RAISE EXCEPTION 'conflicting message state outbox replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.has_trusted_finality_evidence(
    message_id_ bytea,
    certificate_hash_ bytea
) RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, crosschain
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
        JOIN crosschain.finality_certificates AS certificate
          ON certificate.message_id = message.message_id
        JOIN crosschain.source_proofs AS proof
          ON proof.proof_id = certificate.proof_id
         AND proof.message_id = certificate.message_id
        JOIN crosschain.signer_sets AS signer_set
          ON signer_set.signer_set_hash = certificate.signer_set_hash
         AND signer_set.version = certificate.signer_set_version
         AND signer_set.signer_set_hash = route.source_signer_set_hash
         AND signer_set.version = route.source_signer_set_version
        JOIN crosschain.chain_versions AS chain_version
          ON chain_version.chain_id = proof.chain_id
         AND chain_version.version = route.source_chain_version
         AND chain_version.observer_authority_hash =
             proof.observer_authority_hash
        WHERE message.message_id = message_id_
          AND certificate.certificate_hash = certificate_hash_
          AND proof.chain_id = message.source_chain_id
          AND proof.finality_policy_hash = message.source_finality_policy_hash
          AND chain_version.coordinator = message.source_coordinator
          AND chain_version.status IN ('ACTIVE', 'DEPRECATED')
          AND signer_set.status IN ('ACTIVE', 'DEPRECATED')
          AND certificate.signature_count >= signer_set.threshold
          AND certificate.certified_at >= proof.observed_at
          AND certificate.certified_at >= signer_set.valid_from
          AND certificate.certified_at <= signer_set.valid_until
    );
$function$;

CREATE FUNCTION crosschain.has_trusted_chain_evidence(
    message_id_ bytea,
    proof_id_ text,
    certificate_id_ text,
    event_hash_ bytea,
    evidence_side_ text
) RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, crosschain
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
        JOIN crosschain.source_proofs AS proof
          ON proof.proof_id = proof_id_
         AND proof.message_id = message.message_id
         AND proof.event_hash = event_hash_
        JOIN crosschain.finality_certificates AS certificate
          ON certificate.certificate_id = certificate_id_
         AND certificate.message_id = message.message_id
         AND certificate.proof_id = proof.proof_id
         AND certificate.certified_at >= proof.observed_at
        JOIN crosschain.signer_sets AS signer_set
          ON signer_set.signer_set_hash = certificate.signer_set_hash
         AND signer_set.version = certificate.signer_set_version
         AND signer_set.signer_set_hash = CASE evidence_side_
             WHEN 'SOURCE' THEN route.source_signer_set_hash
             WHEN 'DESTINATION' THEN route.destination_signer_set_hash
         END
         AND signer_set.version = CASE evidence_side_
             WHEN 'SOURCE' THEN route.source_signer_set_version
             WHEN 'DESTINATION' THEN route.destination_signer_set_version
         END
         AND signer_set.status IN ('ACTIVE', 'DEPRECATED')
         AND certificate.signature_count >= signer_set.threshold
         AND certificate.certified_at >= signer_set.valid_from
         AND certificate.certified_at <= signer_set.valid_until
        JOIN crosschain.chain_versions AS chain_version
          ON chain_version.chain_id = proof.chain_id
         AND chain_version.version = CASE evidence_side_
             WHEN 'SOURCE' THEN route.source_chain_version
             WHEN 'DESTINATION' THEN route.destination_chain_version
         END
         AND chain_version.coordinator = CASE evidence_side_
             WHEN 'SOURCE' THEN message.source_coordinator
             WHEN 'DESTINATION' THEN message.destination_coordinator
         END
         AND chain_version.observer_authority_hash = proof.observer_authority_hash
         AND chain_version.status IN ('ACTIVE', 'DEPRECATED')
        WHERE message.message_id = message_id_
          AND evidence_side_ IN ('SOURCE', 'DESTINATION')
          AND proof.chain_id = CASE evidence_side_
              WHEN 'SOURCE' THEN message.source_chain_id
              WHEN 'DESTINATION' THEN message.destination_chain_id
          END
          AND proof.finality_policy_hash = CASE evidence_side_
              WHEN 'SOURCE' THEN message.source_finality_policy_hash
              WHEN 'DESTINATION' THEN message.destination_finality_policy_hash
          END
    );
$function$;

CREATE FUNCTION crosschain.execution_evidence_hash(
    message_id_ bytea,
    destination_chain_id_ numeric,
    transaction_hash_ bytea,
    log_index_ numeric,
    result_hash_ bytea,
    effect_commitment_ bytea,
    executed_at_ timestamptz
) RETURNS bytea
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $function$
    SELECT sha256(convert_to(
        jsonb_build_object(
            'destination_chain_id', destination_chain_id_::text,
            'effect_commitment', encode(effect_commitment_, 'hex'),
            'executed_at_epoch_microseconds',
                floor(extract(epoch FROM executed_at_) * 1000000)::numeric(78, 0),
            'log_index', log_index_::text,
            'message_id', encode(message_id_, 'hex'),
            'result_hash', encode(result_hash_, 'hex'),
            'transaction_hash', encode(transaction_hash_, 'hex')
        )::text,
        'UTF8'
    ));
$function$;

CREATE FUNCTION crosschain.action_projection_hash(
    action_type_ smallint,
    projection_ jsonb
) RETURNS bytea
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $function$
    SELECT sha256(convert_to(
        jsonb_build_object(
            'action_type', action_type_,
            'projection', projection_
        )::text,
        'UTF8'
    ));
$function$;

CREATE FUNCTION crosschain.compensation_evidence_hash(
    original_message_id_ bytea,
    recovery_id_ bytea,
    compensation_type_ text,
    asset_id_ text,
    units_ numeric,
    recipient_ text,
    compensation_payload_hash_ bytea,
    result_hash_ bytea,
    compensated_at_ timestamptz
) RETURNS bytea
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog
AS $function$
    SELECT sha256(convert_to(
        jsonb_build_object(
            'asset_id', asset_id_,
            'compensated_at_epoch_microseconds',
                floor(extract(epoch FROM compensated_at_) * 1000000)::numeric(78, 0),
            'compensation_payload_hash', encode(compensation_payload_hash_, 'hex'),
            'compensation_type', compensation_type_,
            'original_message_id', encode(original_message_id_, 'hex'),
            'recipient', recipient_,
            'recovery_id', encode(recovery_id_, 'hex'),
            'result_hash', encode(result_hash_, 'hex'),
            'units', units_::text
        )::text,
        'UTF8'
    ));
$function$;

CREATE FUNCTION crosschain.recovery_completion_evidence_hash(
    message_id_ bytea
) RETURNS bytea
LANGUAGE sql
STABLE
STRICT
SET search_path = pg_catalog, crosschain
AS $function$
    SELECT sha256(convert_to(
        jsonb_build_object(
            'compensation_payload_hash', encode(compensation.compensation_payload_hash, 'hex'),
            'compensation_result', encode(compensation.result_hash, 'hex'),
            'message_id', encode(request.original_message_id, 'hex'),
            'recovery_id', encode(request.recovery_id, 'hex'),
            'request_digest', encode(request.request_digest, 'hex'),
            'tombstone_event_hash', encode(tombstone.tombstone_hash, 'hex')
        )::text,
        'UTF8'
    ))
    FROM crosschain.recovery_requests AS request
    JOIN crosschain.tombstones AS tombstone
      ON tombstone.original_message_id = request.original_message_id
     AND tombstone.recovery_id = request.recovery_id
    JOIN crosschain.compensations AS compensation
      ON compensation.original_message_id = request.original_message_id
     AND compensation.recovery_id = request.recovery_id
    WHERE request.original_message_id = message_id_;
$function$;

CREATE FUNCTION crosschain.register_chain_version(
    chain_id_ numeric,
    version_ bigint,
    coordinator_ bytea,
    finality_verifier_ bytea,
    configuration_hash_ bytea,
    observer_authority_hash_ bytea,
    activated_at_block_ numeric,
    status_ text,
    created_at_ timestamptz
) RETURNS crosschain.chain_versions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.chain_versions;
BEGIN
    INSERT INTO crosschain.chains (chain_id, active_version, created_at)
    VALUES (chain_id_, version_, created_at_)
    ON CONFLICT (chain_id) DO NOTHING;
    INSERT INTO crosschain.chain_versions (
        chain_id, version, coordinator, finality_verifier, configuration_hash,
        observer_authority_hash, activated_at_block, status
    ) VALUES (
        chain_id_, version_, coordinator_, finality_verifier_, configuration_hash_,
        observer_authority_hash_, activated_at_block_, status_
    )
    ON CONFLICT (chain_id, version) DO NOTHING
    RETURNING * INTO result;
    IF result.chain_id IS NULL THEN
        SELECT * INTO result FROM crosschain.chain_versions
        WHERE chain_id = chain_id_ AND version = version_;
        IF result.coordinator <> coordinator_
           OR result.finality_verifier <> finality_verifier_
           OR result.configuration_hash <> configuration_hash_
           OR result.observer_authority_hash <> observer_authority_hash_
           OR result.activated_at_block <> activated_at_block_
           OR result.status <> status_ THEN
            RAISE EXCEPTION 'conflicting chain version replay';
        END IF;
        RETURN result;
    END IF;
    UPDATE crosschain.chains
    SET active_version = version_
    WHERE chain_id = chain_id_ AND active_version <= version_;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'chain version cannot move backwards';
    END IF;
    RETURN result;
END;
$function$;

-- Signer sets are privileged deployment authorities. This append-only
-- function exists so a local manifest bootstrap never needs a direct table
-- write; it is intentionally not granted to any runtime/evidence role.
CREATE FUNCTION crosschain.register_signer_set(
    signer_set_hash_ bytea,
    version_ bigint,
    threshold_ integer,
    signer_addresses_ bytea[],
    valid_from_ timestamptz,
    valid_until_ timestamptz,
    status_ text,
    created_at_ timestamptz
) RETURNS crosschain.signer_sets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.signer_sets;
BEGIN
    IF signer_set_hash_ IS NULL OR octet_length(signer_set_hash_) <> 32
       OR version_ NOT BETWEEN 1 AND 4294967295
       OR threshold_ <> 2
       OR cardinality(signer_addresses_) <> 3
       OR array_lower(signer_addresses_, 1) <> 1
       OR array_upper(signer_addresses_, 1) <> 3
       OR octet_length(signer_addresses_[1]) <> 20
       OR octet_length(signer_addresses_[2]) <> 20
       OR octet_length(signer_addresses_[3]) <> 20
       OR signer_addresses_[1] >= signer_addresses_[2]
       OR signer_addresses_[2] >= signer_addresses_[3]
       OR valid_from_ IS NULL OR valid_until_ <= valid_from_
       OR status_ <> 'ACTIVE'
       OR created_at_ IS NULL OR created_at_ > valid_from_ THEN
        RAISE EXCEPTION 'invalid signer-set registration';
    END IF;
    INSERT INTO crosschain.signer_sets (
        signer_set_hash, version, threshold, signer_addresses,
        valid_from, valid_until, status
    ) VALUES (
        signer_set_hash_, version_, threshold_, signer_addresses_,
        valid_from_, valid_until_, status_
    )
    ON CONFLICT (signer_set_hash, version) DO NOTHING
    RETURNING * INTO result;
    IF result.signer_set_hash IS NULL THEN
        SELECT * INTO result
        FROM crosschain.signer_sets
        WHERE signer_set_hash = signer_set_hash_ AND version = version_;
        IF result.threshold <> threshold_
           OR result.signer_addresses <> signer_addresses_
           OR result.valid_from <> valid_from_
           OR result.valid_until <> valid_until_
           OR result.status <> status_ THEN
            RAISE EXCEPTION 'conflicting signer-set replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.register_route_version(
    route_id_ text,
    version_ bigint,
    source_chain_id_ numeric,
    source_chain_version_ bigint,
    source_coordinator_ bytea,
    source_component_ bytea,
    destination_chain_id_ numeric,
    destination_chain_version_ bigint,
    destination_coordinator_ bytea,
    destination_component_ bytea,
    action_family_ text,
    adapter_set_policy_hash_ bytea,
    source_finality_policy_hash_ bytea,
    destination_finality_policy_hash_ bytea,
    source_signer_set_hash_ bytea,
    source_signer_set_version_ bigint,
    destination_signer_set_hash_ bytea,
    destination_signer_set_version_ bigint,
    route_policy_hash_ bytea,
    activated_at_block_ numeric,
    status_ text,
    created_at_ timestamptz
) RETURNS crosschain.route_versions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.route_versions;
BEGIN
    IF status_ <> 'ACTIVE' THEN
        RAISE EXCEPTION 'new route version must be active';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM crosschain.chain_versions
        WHERE chain_id = source_chain_id_ AND version = source_chain_version_
          AND coordinator = source_coordinator_
          AND status = 'ACTIVE'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.chain_versions
        WHERE chain_id = destination_chain_id_
          AND version = destination_chain_version_
          AND coordinator = destination_coordinator_
          AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'route endpoints require registered active chain versions';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM crosschain.signer_sets
        WHERE signer_set_hash = source_signer_set_hash_
          AND version = source_signer_set_version_
          AND status = 'ACTIVE'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.signer_sets
        WHERE signer_set_hash = destination_signer_set_hash_
          AND version = destination_signer_set_version_
          AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'route endpoints require registered active signer sets';
    END IF;
    INSERT INTO crosschain.routes (route_id, active_version, created_at)
    VALUES (route_id_, version_, created_at_)
    ON CONFLICT (route_id) DO NOTHING;
    INSERT INTO crosschain.route_versions (
        route_id, version, source_chain_id, source_chain_version,
        source_coordinator, source_component,
        destination_chain_id, destination_chain_version,
        destination_coordinator, destination_component,
        action_family, adapter_set_policy_hash, source_finality_policy_hash,
        destination_finality_policy_hash,
        source_signer_set_hash, source_signer_set_version,
        destination_signer_set_hash, destination_signer_set_version,
        route_policy_hash, activated_at_block, status
    ) VALUES (
        route_id_, version_, source_chain_id_, source_chain_version_,
        source_coordinator_, source_component_,
        destination_chain_id_, destination_chain_version_,
        destination_coordinator_, destination_component_,
        action_family_, adapter_set_policy_hash_, source_finality_policy_hash_,
        destination_finality_policy_hash_,
        source_signer_set_hash_, source_signer_set_version_,
        destination_signer_set_hash_, destination_signer_set_version_,
        route_policy_hash_, activated_at_block_, status_
    )
    ON CONFLICT (route_id, version) DO NOTHING
    RETURNING * INTO result;
    IF result.route_id IS NULL THEN
        SELECT * INTO result FROM crosschain.route_versions
        WHERE route_id = route_id_ AND version = version_;
        IF result.source_chain_id <> source_chain_id_
           OR result.source_chain_version <> source_chain_version_
           OR result.source_coordinator <> source_coordinator_
           OR result.source_component <> source_component_
           OR result.destination_chain_id <> destination_chain_id_
           OR result.destination_chain_version <> destination_chain_version_
           OR result.destination_coordinator <> destination_coordinator_
           OR result.destination_component <> destination_component_
           OR result.action_family <> action_family_
           OR result.adapter_set_policy_hash <> adapter_set_policy_hash_
           OR result.source_finality_policy_hash <> source_finality_policy_hash_
           OR result.destination_finality_policy_hash <>
               destination_finality_policy_hash_
           OR result.source_signer_set_hash <> source_signer_set_hash_
           OR result.source_signer_set_version <> source_signer_set_version_
           OR result.destination_signer_set_hash <> destination_signer_set_hash_
           OR result.destination_signer_set_version <>
               destination_signer_set_version_
           OR result.route_policy_hash <> route_policy_hash_
           OR result.activated_at_block <> activated_at_block_
           OR result.status <> status_ THEN
            RAISE EXCEPTION 'conflicting route version replay';
        END IF;
        RETURN result;
    END IF;
    UPDATE crosschain.routes
    SET active_version = version_
    WHERE route_id = route_id_ AND active_version <= version_;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'route version cannot move backwards';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_message(
    message_id_ bytea,
    schema_version_ integer,
    protocol_id_ bytea,
    source_chain_id_ numeric,
    source_coordinator_ bytea,
    source_component_ bytea,
    destination_chain_id_ numeric,
    destination_coordinator_ bytea,
    destination_component_ bytea,
    lane_id_ bytea,
    source_nonce_ numeric,
    aggregate_id_ bytea,
    action_type_ smallint,
    payload_hash_ bytea,
    message_created_at_ timestamptz,
    expires_at_ timestamptz,
    route_policy_hash_ bytea,
    adapter_set_policy_hash_ bytea,
    source_finality_policy_hash_ bytea,
    destination_finality_policy_hash_ bytea,
    correlation_id_ bytea,
    causation_message_id_ bytea,
    superseded_message_id_ bytea,
    serialized_envelope_ bytea,
    updated_at_ timestamptz
) RETURNS crosschain.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.messages;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.route_versions AS route
        WHERE route.route_policy_hash = route_policy_hash_
          AND route.status = 'ACTIVE'
          AND route.source_chain_id = source_chain_id_
          AND route.source_coordinator = source_coordinator_
          AND route.source_component = source_component_
          AND route.destination_chain_id = destination_chain_id_
          AND route.destination_coordinator = destination_coordinator_
          AND route.destination_component = destination_component_
          AND route.adapter_set_policy_hash = adapter_set_policy_hash_
          AND route.source_finality_policy_hash = source_finality_policy_hash_
          AND route.destination_finality_policy_hash =
              destination_finality_policy_hash_
    ) THEN
        RAISE EXCEPTION 'message does not match its pinned active route version';
    END IF;
    INSERT INTO crosschain.messages (
        message_id, schema_version, protocol_id,
        source_chain_id, source_coordinator, source_component,
        destination_chain_id, destination_coordinator, destination_component,
        lane_id, source_nonce, aggregate_id, action_type, payload_hash,
        message_created_at, expires_at, route_policy_hash, adapter_set_policy_hash,
        source_finality_policy_hash, destination_finality_policy_hash,
        correlation_id, causation_message_id, superseded_message_id,
        serialized_envelope, state, state_version, updated_at
    ) VALUES (
        message_id_, schema_version_, protocol_id_,
        source_chain_id_, source_coordinator_, source_component_,
        destination_chain_id_, destination_coordinator_, destination_component_,
        lane_id_, source_nonce_, aggregate_id_, action_type_, payload_hash_,
        message_created_at_, expires_at_, route_policy_hash_, adapter_set_policy_hash_,
        source_finality_policy_hash_, destination_finality_policy_hash_,
        correlation_id_, causation_message_id_, superseded_message_id_,
        serialized_envelope_, 'CREATED', 1, updated_at_
    )
    ON CONFLICT (message_id) DO NOTHING
    RETURNING * INTO result;

    IF result.message_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.messages
        WHERE message_id = message_id_;
        IF result.serialized_envelope <> serialized_envelope_
           OR result.lane_id <> lane_id_
           OR result.source_nonce <> source_nonce_
           OR result.route_policy_hash <> route_policy_hash_ THEN
            RAISE EXCEPTION 'message identity conflict';
        END IF;
    ELSE
        INSERT INTO crosschain.message_transitions (
            message_id, state_version, from_state, to_state,
            evidence_hash, occurred_at
        ) VALUES (
            message_id_, 1, 'CREATED', 'CREATED', payload_hash_, updated_at_
        );
        PERFORM crosschain.enqueue_message_state_event(
            message_id_, 1, 'CREATED', payload_hash_, updated_at_
        );
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_source_proof(
    proof_id_ text,
    message_id_ bytea,
    chain_id_ numeric,
    transaction_hash_ bytea,
    transaction_index_ numeric,
    log_index_ numeric,
    block_number_ numeric,
    block_hash_ bytea,
    receipts_root_ bytea,
    inclusion_proof_hash_ bytea,
    event_hash_ bytea,
    finality_head_number_ numeric,
    finality_head_hash_ bytea,
    confirmation_depth_ numeric,
    finality_policy_hash_ bytea,
    observer_authority_hash_ bytea,
    observer_signed_header_commitment_ bytea,
    observer_signature_ bytea,
    proof_hash_ bytea,
    observed_at_ timestamptz,
    raw_evidence_object_hash_ bytea DEFAULT NULL,
    proof_abi_ bytea DEFAULT NULL
) RETURNS crosschain.source_proofs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.source_proofs;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
        WHERE message.message_id = message_id_
          AND (
              (
                  chain_id_ = message.source_chain_id
                  AND chain_id_ = route.source_chain_id
                  AND finality_policy_hash_ =
                      message.source_finality_policy_hash
                  AND EXISTS (
                      SELECT 1
                      FROM crosschain.chain_versions AS chain_version
                      WHERE chain_version.chain_id = chain_id_
                        AND chain_version.version =
                            route.source_chain_version
                        AND chain_version.coordinator =
                            message.source_coordinator
                        AND chain_version.observer_authority_hash =
                            observer_authority_hash_
                        AND chain_version.status IN ('ACTIVE', 'DEPRECATED')
                  )
              )
              OR
              (
                  chain_id_ = message.destination_chain_id
                  AND chain_id_ = route.destination_chain_id
                  AND finality_policy_hash_ =
                      message.destination_finality_policy_hash
                  AND EXISTS (
                      SELECT 1
                      FROM crosschain.chain_versions AS chain_version
                      WHERE chain_version.chain_id = chain_id_
                        AND chain_version.version =
                            route.destination_chain_version
                        AND chain_version.coordinator =
                            message.destination_coordinator
                        AND chain_version.observer_authority_hash =
                            observer_authority_hash_
                        AND chain_version.status IN ('ACTIVE', 'DEPRECATED')
                  )
              )
          )
    ) THEN
        RAISE EXCEPTION 'proof does not match pinned route authority';
    END IF;

    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        raw_evidence_object_hash, proof_abi,
        proof_hash, observed_at
    ) VALUES (
        proof_id_, message_id_, chain_id_, transaction_hash_,
        transaction_index_, log_index_, block_number_, block_hash_,
        receipts_root_, inclusion_proof_hash_, event_hash_,
        finality_head_number_, finality_head_hash_, confirmation_depth_,
        finality_policy_hash_, observer_authority_hash_,
        observer_signed_header_commitment_, observer_signature_,
        raw_evidence_object_hash_, proof_abi_,
        proof_hash_, observed_at_
    )
    ON CONFLICT (proof_id) DO NOTHING
    RETURNING * INTO result;

    IF result.proof_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.source_proofs
        WHERE proof_id = proof_id_;
        IF result.message_id <> message_id_
           OR result.chain_id <> chain_id_
           OR result.transaction_hash <> transaction_hash_
           OR result.transaction_index <> transaction_index_
           OR result.log_index <> log_index_
           OR result.block_number <> block_number_
           OR result.block_hash <> block_hash_
           OR result.receipts_root <> receipts_root_
           OR result.inclusion_proof_hash <> inclusion_proof_hash_
           OR result.event_hash <> event_hash_
           OR result.finality_head_number <> finality_head_number_
           OR result.finality_head_hash <> finality_head_hash_
           OR result.confirmation_depth <> confirmation_depth_
           OR result.finality_policy_hash <> finality_policy_hash_
           OR result.observer_authority_hash <> observer_authority_hash_
           OR result.observer_signed_header_commitment <>
               observer_signed_header_commitment_
           OR result.observer_signature <> observer_signature_
           OR result.raw_evidence_object_hash IS DISTINCT FROM
               raw_evidence_object_hash_
           OR result.proof_abi IS DISTINCT FROM proof_abi_
           OR result.proof_hash <> proof_hash_
           OR result.observed_at <> observed_at_ THEN
            RAISE EXCEPTION 'conflicting source proof replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_header_observation(
    observation_id_ text,
    chain_id_ numeric,
    block_hash_ bytea,
    block_number_ numeric,
    header_authority_hash_ bytea,
    observer_signed_header_commitment_ bytea,
    observer_signature_ bytea,
    finality_policy_hash_ bytea,
    observed_at_ timestamptz
) RETURNS crosschain.header_observations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.header_observations;
BEGIN
    SELECT * INTO result
    FROM crosschain.header_observations
    WHERE observation_id = observation_id_;
    IF result.observation_id IS NOT NULL THEN
        IF result.chain_id <> chain_id_
           OR result.block_hash <> block_hash_
           OR result.block_number <> block_number_
           OR result.header_authority_hash <> header_authority_hash_
           OR result.observer_signed_header_commitment <>
               observer_signed_header_commitment_
           OR result.observer_signature <> observer_signature_
           OR result.finality_policy_hash <> finality_policy_hash_
           OR result.observed_at <> observed_at_ THEN
            RAISE EXCEPTION 'conflicting header observation replay';
        END IF;
        RETURN result;
    END IF;
    IF observation_id_ IS NULL OR observation_id_ = ''
       OR chain_id_ IS NULL OR block_number_ IS NULL
       OR observed_at_ IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM crosschain.chain_versions AS chain_version
           WHERE chain_version.chain_id = chain_id_
             AND chain_version.observer_authority_hash =
                 header_authority_hash_
             AND chain_version.status IN ('ACTIVE', 'DEPRECATED')
       ) THEN
        RAISE EXCEPTION 'header observation lacks pinned observer authority';
    END IF;
    INSERT INTO crosschain.header_observations (
        observation_id, chain_id, block_hash, block_number,
        header_authority_hash, observer_signed_header_commitment,
        observer_signature, finality_policy_hash, observed_at
    ) VALUES (
        observation_id_, chain_id_, block_hash_, block_number_,
        header_authority_hash_, observer_signed_header_commitment_,
        observer_signature_, finality_policy_hash_, observed_at_
    )
    RETURNING * INTO result;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_finality_certificate(
    certificate_id_ text,
    message_id_ bytea,
    proof_id_ text,
    signer_set_hash_ bytea,
    signer_set_version_ bigint,
    signer_bitmap_ bit varying,
    signature_count_ integer,
    certificate_hash_ bytea,
    certified_at_ timestamptz,
    certificate_abi_ bytea DEFAULT NULL,
    signatures_ bytea[] DEFAULT NULL
) RETURNS crosschain.finality_certificates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.finality_certificates;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.source_proofs AS proof
        JOIN crosschain.messages AS message
          ON message.message_id = proof.message_id
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
        JOIN crosschain.signer_sets AS signer_set
          ON signer_set.signer_set_hash = signer_set_hash_
         AND signer_set.version = signer_set_version_
         AND signer_set.status IN ('ACTIVE', 'DEPRECATED')
         AND certified_at_ >= signer_set.valid_from
         AND certified_at_ <= signer_set.valid_until
        WHERE proof.proof_id = proof_id_
          AND proof.message_id = message_id_
          AND certified_at_ >= proof.observed_at
          AND (
              (
                  proof.chain_id = message.source_chain_id
                  AND signer_set_hash_ = route.source_signer_set_hash
                  AND signer_set_version_ = route.source_signer_set_version
              )
              OR
              (
                  proof.chain_id = message.destination_chain_id
                  AND signer_set_hash_ =
                      route.destination_signer_set_hash
                  AND signer_set_version_ =
                      route.destination_signer_set_version
              )
          )
    ) THEN
        RAISE EXCEPTION 'certificate does not match pinned route signer set';
    END IF;

    INSERT INTO crosschain.finality_certificates (
        certificate_id, message_id, proof_id, signer_set_hash,
        signer_set_version, signer_bitmap, signature_count,
        signatures, certificate_abi,
        certificate_hash, certified_at
    ) VALUES (
        certificate_id_, message_id_, proof_id_, signer_set_hash_,
        signer_set_version_, signer_bitmap_, signature_count_,
        signatures_, certificate_abi_,
        certificate_hash_, certified_at_
    )
    ON CONFLICT (certificate_id) DO NOTHING
    RETURNING * INTO result;

    IF result.certificate_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.finality_certificates
        WHERE certificate_id = certificate_id_;
        IF result.message_id <> message_id_
           OR result.proof_id <> proof_id_
           OR result.signer_set_hash <> signer_set_hash_
           OR result.signer_set_version <> signer_set_version_
           OR result.signer_bitmap <> signer_bitmap_
           OR result.signature_count <> signature_count_
           OR result.signatures IS DISTINCT FROM signatures_
           OR result.certificate_abi IS DISTINCT FROM certificate_abi_
           OR result.certificate_hash <> certificate_hash_
           OR result.certified_at <> certified_at_ THEN
            RAISE EXCEPTION 'conflicting finality certificate replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.load_source_proof(
    proof_id_ text
) RETURNS crosschain.source_proofs
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.source_proofs;
BEGIN
    SELECT * INTO result
    FROM crosschain.source_proofs
    WHERE proof_id = proof_id_;
    IF result.proof_id IS NULL THEN
        RAISE EXCEPTION 'source proof not found';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.load_finality_certificate(
    certificate_id_ text
) RETURNS crosschain.finality_certificates
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.finality_certificates;
BEGIN
    SELECT * INTO result
    FROM crosschain.finality_certificates
    WHERE certificate_id = certificate_id_;
    IF result.certificate_id IS NULL THEN
        RAISE EXCEPTION 'finality certificate not found';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_recovery_request(
    recovery_id_ bytea,
    original_message_id_ bytea,
    protocol_id_ bytea,
    source_chain_id_ numeric,
    source_coordinator_ bytea,
    destination_chain_id_ numeric,
    destination_coordinator_ bytea,
    immutable_envelope_hash_ bytea,
    route_policy_hash_ bytea,
    asset_amount_commitment_ bytea,
    source_state_commitment_ bytea,
    destination_state_commitment_ bytea,
    compensation_payload_hash_ bytea,
    message_expires_at_ numeric,
    recovery_nonce_ numeric,
    reason_code_ bytea,
    action_ smallint,
    authorizer_set_hash_ bytea,
    authorizer_set_version_ bigint,
    request_digest_ bytea,
    signer_bitmap_ bit varying,
    signature_count_ integer,
    authorization_evidence_hash_ bytea,
    verified_at_ timestamptz
) RETURNS crosschain.recovery_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.recovery_requests;
BEGIN
    SELECT * INTO result
    FROM crosschain.recovery_requests
    WHERE recovery_id = recovery_id_;
    IF result.recovery_id IS NOT NULL THEN
        IF result.original_message_id <> original_message_id_
           OR result.protocol_id <> protocol_id_
           OR result.source_chain_id <> source_chain_id_
           OR result.source_coordinator <> source_coordinator_
           OR result.destination_chain_id <> destination_chain_id_
           OR result.destination_coordinator <> destination_coordinator_
           OR result.immutable_envelope_hash <> immutable_envelope_hash_
           OR result.route_policy_hash <> route_policy_hash_
           OR result.asset_amount_commitment <> asset_amount_commitment_
           OR result.source_state_commitment <> source_state_commitment_
           OR result.destination_state_commitment <> destination_state_commitment_
           OR result.compensation_payload_hash <> compensation_payload_hash_
           OR result.message_expires_at <> message_expires_at_
           OR result.recovery_nonce <> recovery_nonce_
           OR result.reason_code <> reason_code_
           OR result.action <> action_
           OR result.authorizer_set_hash <> authorizer_set_hash_
           OR result.authorizer_set_version <> authorizer_set_version_
           OR result.request_digest <> request_digest_
           OR result.signer_bitmap <> signer_bitmap_
           OR result.signature_count <> signature_count_
           OR result.authorization_evidence_hash <> authorization_evidence_hash_
           OR result.verified_at <> verified_at_ THEN
            RAISE EXCEPTION 'conflicting recovery request replay';
        END IF;
        RETURN result;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
        JOIN crosschain.recovery_authorizer_sets AS authorizer_set
          ON authorizer_set.authorizer_set_hash = authorizer_set_hash_
         AND authorizer_set.version = authorizer_set_version_
         AND authorizer_set.status IN ('ACTIVE', 'DEPRECATED')
         AND signature_count_ >= authorizer_set.threshold
         AND verified_at_ >= authorizer_set.valid_from
         AND verified_at_ <= authorizer_set.valid_until
        WHERE message.message_id = original_message_id_
          AND message.state IN ('REJECTED', 'FAILED', 'EXPIRED', 'RECOVERY_PENDING')
          AND message.protocol_id = protocol_id_
          AND message.source_chain_id = source_chain_id_
          AND message.source_coordinator = source_coordinator_
          AND message.destination_chain_id = destination_chain_id_
          AND message.destination_coordinator = destination_coordinator_
          AND message.route_policy_hash = route_policy_hash_
          AND floor(extract(epoch FROM message.expires_at))::numeric(20, 0) =
              message_expires_at_
          AND verified_at_ >= message.expires_at
          AND action_ = 1
          AND octet_length(recovery_id_) = 32
          AND octet_length(immutable_envelope_hash_) = 32
          AND octet_length(asset_amount_commitment_) = 32
          AND octet_length(source_state_commitment_) = 32
          AND octet_length(destination_state_commitment_) = 32
          AND octet_length(compensation_payload_hash_) = 32
          AND octet_length(reason_code_) = 32
          AND octet_length(request_digest_) = 32
          AND octet_length(authorization_evidence_hash_) = 32
          AND bit_length(signer_bitmap_) = 3
          AND signature_count_ =
              length(replace(signer_bitmap_::text, '0', ''))
    ) THEN
        RAISE EXCEPTION 'recovery request requires exact signed V2 authorization';
    END IF;

    INSERT INTO crosschain.recovery_requests (
        recovery_id, original_message_id, protocol_id, source_chain_id,
        source_coordinator, destination_chain_id, destination_coordinator,
        immutable_envelope_hash, route_policy_hash, asset_amount_commitment,
        source_state_commitment, destination_state_commitment,
        compensation_payload_hash, message_expires_at, recovery_nonce,
        reason_code, action, authorizer_set_hash, authorizer_set_version,
        request_digest, signer_bitmap, signature_count,
        authorization_evidence_hash, verified_at
    ) VALUES (
        recovery_id_, original_message_id_, protocol_id_, source_chain_id_,
        source_coordinator_, destination_chain_id_, destination_coordinator_,
        immutable_envelope_hash_, route_policy_hash_, asset_amount_commitment_,
        source_state_commitment_, destination_state_commitment_,
        compensation_payload_hash_, message_expires_at_, recovery_nonce_,
        reason_code_, action_, authorizer_set_hash_, authorizer_set_version_,
        request_digest_, signer_bitmap_, signature_count_,
        authorization_evidence_hash_, verified_at_
    )
    ON CONFLICT (recovery_id) DO NOTHING
    RETURNING * INTO result;

    IF result.recovery_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.recovery_requests
        WHERE recovery_id = recovery_id_;
        IF result.original_message_id <> original_message_id_
           OR result.protocol_id <> protocol_id_
           OR result.source_chain_id <> source_chain_id_
           OR result.source_coordinator <> source_coordinator_
           OR result.destination_chain_id <> destination_chain_id_
           OR result.destination_coordinator <> destination_coordinator_
           OR result.immutable_envelope_hash <> immutable_envelope_hash_
           OR result.route_policy_hash <> route_policy_hash_
           OR result.asset_amount_commitment <> asset_amount_commitment_
           OR result.source_state_commitment <> source_state_commitment_
           OR result.destination_state_commitment <> destination_state_commitment_
           OR result.compensation_payload_hash <> compensation_payload_hash_
           OR result.message_expires_at <> message_expires_at_
           OR result.recovery_nonce <> recovery_nonce_
           OR result.reason_code <> reason_code_
           OR result.action <> action_
           OR result.authorizer_set_hash <> authorizer_set_hash_
           OR result.authorizer_set_version <> authorizer_set_version_
           OR result.request_digest <> request_digest_
           OR result.signer_bitmap <> signer_bitmap_
           OR result.signature_count <> signature_count_
           OR result.authorization_evidence_hash <> authorization_evidence_hash_
           OR result.verified_at <> verified_at_ THEN
            RAISE EXCEPTION 'conflicting recovery request replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_acknowledgement(
    message_id_ bytea,
    execution_result_hash_ bytea,
    destination_proof_id_ text,
    certificate_id_ text,
    acknowledged_at_ timestamptz
) RETURNS crosschain.acknowledgements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.acknowledgements;
    expected_event_hash bytea;
BEGIN
    SELECT * INTO result
    FROM crosschain.acknowledgements
    WHERE message_id = message_id_;
    IF result.message_id IS NOT NULL THEN
        IF result.execution_result_hash <> execution_result_hash_
           OR result.destination_proof_id <> destination_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.acknowledged_at <> acknowledged_at_ THEN
            RAISE EXCEPTION 'conflicting acknowledgement replay';
        END IF;
        RETURN result;
    END IF;
    SELECT crosschain.execution_evidence_hash(
        execution.message_id,
        execution.destination_chain_id,
        execution.transaction_hash,
        execution.log_index,
        execution.result_hash,
        execution.effect_commitment,
        execution.executed_at
    ) INTO expected_event_hash
    FROM crosschain.execution_results AS execution
    JOIN crosschain.messages AS message
      ON message.message_id = execution.message_id
    WHERE execution.message_id = message_id_
      AND execution.result_hash = execution_result_hash_
      AND message.state = 'ACK_PENDING'
      AND acknowledged_at_ >= execution.executed_at;

    IF expected_event_hash IS NULL
       OR NOT crosschain.has_trusted_chain_evidence(
           message_id_, destination_proof_id_, certificate_id_,
           expected_event_hash, 'DESTINATION'
       ) THEN
        RAISE EXCEPTION 'acknowledgement requires trusted exact destination execution';
    END IF;

    INSERT INTO crosschain.acknowledgements (
        message_id, execution_result_hash, destination_proof_id,
        certificate_id, acknowledged_at
    ) VALUES (
        message_id_, execution_result_hash_, destination_proof_id_,
        certificate_id_, acknowledged_at_
    )
    ON CONFLICT (message_id) DO NOTHING
    RETURNING * INTO result;
    IF result.message_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.acknowledgements
        WHERE message_id = message_id_;
        IF result.execution_result_hash <> execution_result_hash_
           OR result.destination_proof_id <> destination_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.acknowledged_at <> acknowledged_at_ THEN
            RAISE EXCEPTION 'conflicting acknowledgement replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_action_projection(
    message_id_ bytea,
    projection_ jsonb,
    projected_at_ timestamptz
) RETURNS crosschain.action_projections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.action_projections;
    action_type_ smallint;
    projection_hash_ bytea;
BEGIN
    SELECT * INTO result
    FROM crosschain.action_projections
    WHERE message_id = message_id_;
    IF result.message_id IS NOT NULL THEN
        IF result.projection IS DISTINCT FROM projection_
           OR result.projected_at <> projected_at_ THEN
            RAISE EXCEPTION 'conflicting action projection replay';
        END IF;
        RETURN result;
    END IF;
    IF message_id_ IS NULL OR octet_length(message_id_) <> 32
       OR projection_ IS NULL OR jsonb_typeof(projection_) <> 'object'
       OR projection_ = '{}'::jsonb OR projected_at_ IS NULL THEN
        RAISE EXCEPTION 'invalid canonical action projection';
    END IF;
    SELECT message.action_type
    INTO action_type_
    FROM crosschain.messages AS message
    JOIN crosschain.execution_results AS execution
      ON execution.message_id = message.message_id
    JOIN crosschain.acknowledgements AS acknowledgement
      ON acknowledgement.message_id = execution.message_id
     AND acknowledgement.execution_result_hash = execution.result_hash
     AND acknowledgement.destination_proof_id = execution.destination_proof_id
     AND acknowledgement.certificate_id = execution.certificate_id
    WHERE message.message_id = message_id_
      AND message.state = 'ACKNOWLEDGED'
      -- Legacy reviewed fixtures predate exact JSON retention and bind the
      -- same projection through effect_commitment. The EVM path always stores
      -- a non-null projection and therefore must match it byte-for-byte.
      AND (
          execution.action_projection IS NULL
          OR execution.action_projection = projection_
      )
      AND projected_at_ >= acknowledgement.acknowledged_at;
    IF action_type_ IS NULL THEN
        RAISE EXCEPTION 'action projection requires exact acknowledged execution';
    END IF;
    projection_hash_ := crosschain.action_projection_hash(
        action_type_,
        projection_
    );
    INSERT INTO crosschain.action_projections (
        message_id, action_type, projection, projection_hash,
        execution_result_hash, destination_proof_id, certificate_id,
        projected_at
    )
    SELECT
        execution.message_id, action_type_, projection_, projection_hash_,
        execution.result_hash, execution.destination_proof_id,
        execution.certificate_id, projected_at_
    FROM crosschain.execution_results AS execution
    WHERE execution.message_id = message_id_
      AND (
          execution.action_projection IS NULL
          OR execution.action_projection = projection_
      )
      AND execution.effect_commitment = projection_hash_
    ON CONFLICT (message_id) DO NOTHING
    RETURNING * INTO result;
    IF result.message_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.action_projections
        WHERE message_id = message_id_;
        IF result.message_id IS NULL THEN
            RAISE EXCEPTION 'action projection does not match finalized effect commitment';
        END IF;
        IF result.action_type <> action_type_
           OR result.projection IS DISTINCT FROM projection_
           OR result.projection_hash <> projection_hash_
           OR result.projected_at <> projected_at_ THEN
            RAISE EXCEPTION 'conflicting action projection replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

-- All Phase 8 accounting functions use this single exact-replay primitive.
-- The outer business function, its authoritative record, both journal lines,
-- and the corresponding link row commit or roll back as one transaction.
CREATE FUNCTION crosschain.post_balanced_journal(
    journal_id_ text,
    entry_type_ text,
    source_event_id_ text,
    loan_id_ text,
    correlation_id_ text,
    evidence_hash_ bytea,
    effective_at_ timestamptz,
    asset_id_ text,
    units_ numeric,
    debit_account_ text,
    credit_account_ text,
    party_id_ text
) RETURNS public.journal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result public.journal;
BEGIN
    IF journal_id_ IS NULL OR journal_id_ = ''
       OR entry_type_ IS NULL OR entry_type_ = ''
       OR source_event_id_ IS NULL OR source_event_id_ = ''
       OR correlation_id_ IS NULL OR correlation_id_ = ''
       OR evidence_hash_ IS NULL OR octet_length(evidence_hash_) <> 32
       OR effective_at_ IS NULL OR asset_id_ IS NULL OR asset_id_ = ''
       OR units_ IS NULL OR units_ <= 0
       OR debit_account_ IS NULL OR debit_account_ = ''
       OR credit_account_ IS NULL OR credit_account_ = ''
       OR debit_account_ = credit_account_ THEN
        RAISE EXCEPTION 'invalid Phase 8 journal';
    END IF;
    INSERT INTO public.journal (
        journal_id, legal_entity_id, book_id, source_system,
        idempotency_key, correlation_id, evidence_hash, effective_at,
        status, entry_type, source_event_id, loan_id
    ) VALUES (
        journal_id_, 'unified-protocol', 'cross-chain-subledger',
        'cross-chain-coordinator', journal_id_, correlation_id_,
        encode(evidence_hash_, 'hex'), effective_at_, 'POSTED',
        entry_type_, source_event_id_, loan_id_
    )
    ON CONFLICT DO NOTHING;
    INSERT INTO public.journal_entry (
        journal_id, line_number, account_code, side, asset_id,
        units, party_id, loan_id
    ) VALUES
        (
            journal_id_, 1, debit_account_, 'DEBIT', asset_id_,
            units_, party_id_, loan_id_
        ),
        (
            journal_id_, 2, credit_account_, 'CREDIT', asset_id_,
            units_, party_id_, loan_id_
        )
    ON CONFLICT DO NOTHING;
    SELECT * INTO result
    FROM public.journal
    WHERE journal_id = journal_id_;
    IF result.journal_id IS NULL
       OR result.legal_entity_id <> 'unified-protocol'
       OR result.book_id <> 'cross-chain-subledger'
       OR result.source_system <> 'cross-chain-coordinator'
       OR result.idempotency_key <> journal_id_
       OR result.correlation_id <> correlation_id_
       OR result.evidence_hash <> encode(evidence_hash_, 'hex')
       OR result.effective_at <> effective_at_
       OR result.status <> 'POSTED'
       OR result.entry_type <> entry_type_
       OR result.source_event_id <> source_event_id_
       OR result.loan_id IS DISTINCT FROM loan_id_
       OR (
           SELECT count(*)
           FROM public.journal_entry
           WHERE journal_id = journal_id_
       ) <> 2
       OR NOT EXISTS (
           SELECT 1
           FROM public.journal_entry
           WHERE journal_id = journal_id_ AND line_number = 1
             AND account_code = debit_account_ AND side = 'DEBIT'
             AND asset_id = asset_id_ AND units = units_
             AND party_id IS NOT DISTINCT FROM party_id_
             AND loan_id IS NOT DISTINCT FROM loan_id_
       )
       OR NOT EXISTS (
           SELECT 1
           FROM public.journal_entry
           WHERE journal_id = journal_id_ AND line_number = 2
             AND account_code = credit_account_ AND side = 'CREDIT'
             AND asset_id = asset_id_ AND units = units_
             AND party_id IS NOT DISTINCT FROM party_id_
             AND loan_id IS NOT DISTINCT FROM loan_id_
       )
       OR EXISTS (
           SELECT 1
           FROM public.journal_balance
           WHERE journal_id = journal_id_
             AND debit_units <> credit_units
       ) THEN
        RAISE EXCEPTION 'Phase 8 journal replay conflicts or is unbalanced';
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.post_message_journal(
    message_id_ bytea,
    suffix_ text,
    entry_type_ text,
    loan_id_ text,
    asset_id_ text,
    units_ numeric,
    debit_account_ text,
    credit_account_ text,
    party_id_ text
) RETURNS public.journal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    message crosschain.messages;
    projection crosschain.action_projections;
BEGIN
    SELECT * INTO message
    FROM crosschain.messages
    WHERE message_id = message_id_;
    SELECT * INTO projection
    FROM crosschain.action_projections
    WHERE message_id = message_id_;
    IF message.message_id IS NULL OR projection.message_id IS NULL
       OR suffix_ IS NULL OR suffix_ = '' THEN
        RAISE EXCEPTION 'journal requires canonical action projection';
    END IF;
    RETURN crosschain.post_balanced_journal(
        'crosschain:' || encode(message_id_, 'hex') || ':' || suffix_,
        entry_type_,
        encode(message_id_, 'hex'),
        loan_id_,
        encode(message.correlation_id, 'hex'),
        projection.projection_hash,
        projection.projected_at,
        asset_id_,
        units_,
        debit_account_,
        credit_account_,
        party_id_
    );
END;
$function$;

CREATE FUNCTION crosschain.post_compensation_journals(
    original_message_id_ bytea
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    message crosschain.messages;
    compensation crosschain.compensations;
    evidence_hash_ bytea;
    posted public.journal;
    journal_id_ text;
BEGIN
    SELECT * INTO message
    FROM crosschain.messages
    WHERE message_id = original_message_id_;
    SELECT * INTO compensation
    FROM crosschain.compensations
    WHERE original_message_id = original_message_id_;
    IF message.message_id IS NULL OR compensation.original_message_id IS NULL THEN
        RAISE EXCEPTION 'compensation journal requires immutable recovery facts';
    END IF;
    evidence_hash_ := crosschain.compensation_evidence_hash(
        compensation.original_message_id,
        compensation.recovery_id,
        compensation.compensation_type,
        compensation.asset_id,
        compensation.units,
        compensation.recipient,
        compensation.compensation_payload_hash,
        compensation.result_hash,
        compensation.compensated_at
    );
    IF message.action_type = 1 THEN
        journal_id_ :=
            'crosschain:recovery:' || encode(compensation.recovery_id, 'hex')
            || ':financial-reversal';
        posted := crosschain.post_balanced_journal(
            journal_id_, 'BRIDGE_COMPENSATION',
            encode(original_message_id_, 'hex'), NULL,
            encode(message.correlation_id, 'hex'), evidence_hash_,
            compensation.compensated_at, compensation.asset_id,
            compensation.units, '2230', '1410', compensation.recipient
        );
        INSERT INTO ledger.crosschain_recovery_journal_links (
            recovery_id, journal_role, original_message_id, journal_id,
            evidence_hash
        ) VALUES (
            compensation.recovery_id, 'FINANCIAL_REVERSAL',
            original_message_id_, posted.journal_id, evidence_hash_
        )
        ON CONFLICT DO NOTHING;
        IF NOT EXISTS (
            SELECT 1
            FROM ledger.crosschain_recovery_journal_links
            WHERE recovery_id = compensation.recovery_id
              AND journal_role = 'FINANCIAL_REVERSAL'
              AND original_message_id = original_message_id_
              AND journal_id = posted.journal_id
              AND evidence_hash = evidence_hash_
        ) THEN
            RAISE EXCEPTION 'conflicting compensation financial journal replay';
        END IF;
    ELSIF message.action_type NOT IN (3, 8, 15) THEN
        RAISE EXCEPTION 'unsupported compensated action type';
    END IF;

    journal_id_ :=
        'crosschain:recovery:' || encode(compensation.recovery_id, 'hex')
        || ':control-reversal';
    posted := crosschain.post_balanced_journal(
        journal_id_, 'BRIDGE_COMPENSATION',
        encode(original_message_id_, 'hex'), NULL,
        encode(message.correlation_id, 'hex'), evidence_hash_,
        compensation.compensated_at, compensation.asset_id,
        compensation.units,
        '9150',
        CASE WHEN message.action_type = 1 THEN '7150' ELSE '7160' END,
        compensation.recipient
    );
    INSERT INTO ledger.crosschain_recovery_journal_links (
        recovery_id, journal_role, original_message_id, journal_id,
        evidence_hash
    ) VALUES (
        compensation.recovery_id, 'CONTROL_REVERSAL',
        original_message_id_, posted.journal_id, evidence_hash_
    )
    ON CONFLICT DO NOTHING;
    IF NOT EXISTS (
        SELECT 1
        FROM ledger.crosschain_recovery_journal_links
        WHERE recovery_id = compensation.recovery_id
          AND journal_role = 'CONTROL_REVERSAL'
          AND original_message_id = original_message_id_
          AND journal_id = posted.journal_id
          AND evidence_hash = evidence_hash_
    ) THEN
        RAISE EXCEPTION 'conflicting compensation control journal replay';
    END IF;
END;
$function$;

CREATE FUNCTION crosschain.transition_message(
    message_id_ bytea,
    expected_version_ bigint,
    expected_state_ text,
    next_state_ text,
    failure_class_ text,
    evidence_hash_ bytea,
    occurred_at_ timestamptz
) RETURNS crosschain.messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.messages;
    existing_transition crosschain.message_transitions;
    allowed boolean;
BEGIN
    SELECT * INTO existing_transition
    FROM crosschain.message_transitions
    WHERE message_id = message_id_ AND state_version = expected_version_ + 1;
    IF existing_transition.message_id IS NOT NULL THEN
        IF existing_transition.from_state <> expected_state_
           OR existing_transition.to_state <> next_state_
           OR existing_transition.failure_class IS DISTINCT FROM failure_class_
           OR existing_transition.evidence_hash <> evidence_hash_
           OR existing_transition.occurred_at <> occurred_at_ THEN
            RAISE EXCEPTION 'conflicting message transition replay';
        END IF;
        SELECT * INTO result FROM crosschain.messages WHERE message_id = message_id_;
        RETURN result;
    END IF;
    allowed := CASE expected_state_
        WHEN 'CREATED' THEN next_state_ = 'SOURCE_FINALIZING'
        WHEN 'SOURCE_FINALIZING' THEN next_state_ IN ('SOURCE_FINAL', 'EXPIRED', 'DISPUTED')
        WHEN 'SOURCE_FINAL' THEN next_state_ IN ('SENT', 'DISPUTED')
        WHEN 'SENT' THEN next_state_ IN ('RELAYED', 'FAILED', 'REJECTED', 'EXPIRED', 'DISPUTED')
        WHEN 'RELAYED' THEN next_state_ IN ('VERIFIED', 'FAILED', 'REJECTED', 'EXPIRED', 'DISPUTED')
        WHEN 'VERIFIED' THEN next_state_ IN ('EXECUTED', 'FAILED', 'REJECTED', 'DISPUTED')
        WHEN 'EXECUTED' THEN next_state_ IN ('ACK_PENDING', 'DISPUTED')
        WHEN 'ACK_PENDING' THEN next_state_ IN ('ACKNOWLEDGED', 'DISPUTED')
        WHEN 'REJECTED' THEN next_state_ IN ('RECOVERY_PENDING', 'DISPUTED')
        WHEN 'FAILED' THEN
            next_state_ IN ('RECOVERY_PENDING', 'DISPUTED')
            OR (
                next_state_ = 'SENT'
                AND failure_class_ IN ('RETRYABLE_TRANSPORT', 'RETRYABLE_TARGET')
            )
        WHEN 'EXPIRED' THEN next_state_ IN ('RECOVERY_PENDING', 'DISPUTED')
        WHEN 'RECOVERY_PENDING' THEN next_state_ IN ('DESTINATION_TOMBSTONED', 'DISPUTED')
        WHEN 'DESTINATION_TOMBSTONED' THEN next_state_ IN ('SOURCE_COMPENSATED', 'DISPUTED')
        WHEN 'SOURCE_COMPENSATED' THEN next_state_ IN ('RECOVERED', 'DISPUTED')
        WHEN 'ACKNOWLEDGED' THEN next_state_ = 'DISPUTED'
        WHEN 'RECOVERED' THEN next_state_ = 'DISPUTED'
        ELSE false
    END;
    IF NOT allowed THEN
        RAISE EXCEPTION 'invalid message state transition';
    END IF;
    IF next_state_ IN ('SOURCE_FINAL', 'VERIFIED')
       AND NOT EXISTS (
           SELECT 1
           FROM crosschain.messages AS message
           WHERE message.message_id = message_id_
             AND crosschain.has_trusted_finality_evidence(
                 message.message_id,
                 evidence_hash_
             )
       ) THEN
        RAISE EXCEPTION 'finality transition requires trusted source evidence';
    END IF;
    IF next_state_ = 'EXECUTED'
       AND NOT EXISTS (
           SELECT 1
           FROM crosschain.execution_results
           WHERE message_id = message_id_
             AND result_hash = evidence_hash_
       ) THEN
        RAISE EXCEPTION 'executed transition requires exact execution result';
    END IF;
    IF next_state_ = 'ACKNOWLEDGED'
       AND NOT EXISTS (
           SELECT 1
           FROM crosschain.acknowledgements
           WHERE message_id = message_id_
             AND execution_result_hash = evidence_hash_
       ) THEN
        RAISE EXCEPTION 'acknowledged transition requires exact authoritative acknowledgement';
    END IF;
    IF next_state_ = 'RECOVERY_PENDING'
       AND NOT EXISTS (
           SELECT 1
           FROM crosschain.recovery_requests
           WHERE original_message_id = message_id_
             AND request_digest = evidence_hash_
       ) THEN
        RAISE EXCEPTION 'recovery pending requires exact signed V2 request';
    END IF;
    IF next_state_ = 'DESTINATION_TOMBSTONED'
       AND NOT EXISTS (
           SELECT 1
           FROM crosschain.tombstones
           WHERE original_message_id = message_id_
             AND tombstone_hash = evidence_hash_
       ) THEN
        RAISE EXCEPTION 'destination tombstone requires exact authoritative chain fact';
    END IF;
    IF next_state_ = 'SOURCE_COMPENSATED'
       AND NOT EXISTS (
           SELECT 1
           FROM crosschain.compensations
           WHERE original_message_id = message_id_
             AND result_hash = evidence_hash_
       ) THEN
        RAISE EXCEPTION 'source compensation requires exact authoritative chain fact';
    END IF;
    IF next_state_ = 'RECOVERED'
       AND crosschain.recovery_completion_evidence_hash(message_id_)
           IS DISTINCT FROM evidence_hash_ THEN
        RAISE EXCEPTION 'recovered transition requires exact completion evidence';
    END IF;
    IF next_state_ = 'DISPUTED'
       AND NOT EXISTS (
           SELECT 1
           FROM crosschain.reorganizations AS reorganization
           WHERE reorganization.evidence_hash = evidence_hash_
             AND message_id_ = ANY(reorganization.affected_message_ids)
       ) THEN
        RAISE EXCEPTION 'disputed transition requires exact authenticated reorganization';
    END IF;
    UPDATE crosschain.messages
    SET state = next_state_,
        state_version = state_version + 1,
        updated_at = occurred_at_
    WHERE message_id = message_id_
      AND state_version = expected_version_
      AND state = expected_state_
      AND occurred_at_ >= updated_at
    RETURNING * INTO result;
    IF result.message_id IS NULL THEN
        RAISE EXCEPTION 'message compare-and-set conflict';
    END IF;
    INSERT INTO crosschain.message_transitions (
        message_id, state_version, from_state, to_state,
        failure_class, evidence_hash, occurred_at
    ) VALUES (
        message_id_, result.state_version, expected_state_, next_state_,
        failure_class_, evidence_hash_, occurred_at_
    );
    PERFORM crosschain.enqueue_message_state_event(
        message_id_, result.state_version, next_state_, evidence_hash_, occurred_at_
    );
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_reorganization(
    route_id_ text,
    chain_id_ numeric,
    orphaned_proof_ids_ text[],
    orphaned_certificate_ids_ text[],
    replacement_observation_id_ text,
    detected_head_observation_id_ text,
    affected_message_ids_ bytea[],
    evidence_hash_ bytea,
    detected_at_ timestamptz
) RETURNS crosschain.reorganizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.reorganizations;
    incident crosschain.incidents;
    orphaned_proof crosschain.source_proofs;
    orphaned_certificate crosschain.finality_certificates;
    replacement_observation crosschain.header_observations;
    detected_head_observation crosschain.header_observations;
    affected_message crosschain.messages;
    reorganization_id_ text;
    incident_id_ text;
    orphaned_proof_id_ text;
    orphaned_certificate_id_ text;
BEGIN
    reorganization_id_ := 'crosschain-reorg:' || encode(evidence_hash_, 'hex');
    incident_id_ := 'crosschain-incident:' || encode(evidence_hash_, 'hex');
    orphaned_proof_id_ := orphaned_proof_ids_[1];
    orphaned_certificate_id_ := orphaned_certificate_ids_[1];
    SELECT * INTO result
    FROM crosschain.reorganizations
    WHERE evidence_hash = evidence_hash_;
    IF result.reorganization_id IS NOT NULL THEN
        SELECT * INTO incident
        FROM crosschain.incidents
        WHERE reorganization_id = result.reorganization_id;
        IF result.reorganization_id <> reorganization_id_
           OR result.route_id <> route_id_
           OR result.chain_id <> chain_id_
           OR result.orphaned_proof_id <> orphaned_proof_id_
           OR result.orphaned_certificate_id <> orphaned_certificate_id_
           OR result.orphaned_proof_ids <> orphaned_proof_ids_
           OR result.orphaned_certificate_ids <>
               orphaned_certificate_ids_
           OR result.replacement_observation_id <> replacement_observation_id_
           OR result.detected_head_observation_id <>
               detected_head_observation_id_
           OR result.affected_message_ids <> affected_message_ids_
           OR result.detected_at <> detected_at_
           OR incident.incident_id IS NULL
           OR incident.incident_id <> incident_id_
           OR incident.route_id <> route_id_
           OR incident.reason_code <> 'POST_FINALITY_REORGANIZATION'
           OR incident.severity <> 'CRITICAL'
           OR incident.owner <> 'cross-chain-security'
           OR incident.evidence_hash <> evidence_hash_
           OR incident.affected_message_ids <> affected_message_ids_
           OR incident.status <> 'OPEN'
           OR incident.opened_at <> detected_at_
           OR EXISTS (
               SELECT 1
               FROM unnest(affected_message_ids_) AS affected(message_id)
               LEFT JOIN crosschain.messages AS message
                 ON message.message_id = affected.message_id
               WHERE message.message_id IS NULL
                  OR message.state <> 'DISPUTED'
                  OR NOT EXISTS (
                      SELECT 1
                      FROM crosschain.message_transitions AS transition
                      WHERE transition.message_id = affected.message_id
                        AND transition.to_state = 'DISPUTED'
                        AND transition.evidence_hash = evidence_hash_
                  )
           ) THEN
            RAISE EXCEPTION 'conflicting reorganization replay';
        END IF;
        RETURN result;
    END IF;
    IF route_id_ IS NULL OR route_id_ = ''
       OR chain_id_ IS NULL
       OR evidence_hash_ IS NULL OR octet_length(evidence_hash_) <> 32
       OR detected_at_ IS NULL
       OR affected_message_ids_ IS NULL
       OR cardinality(affected_message_ids_) NOT BETWEEN 1 AND 256
       OR orphaned_proof_ids_ IS NULL
       OR cardinality(orphaned_proof_ids_) <>
          cardinality(affected_message_ids_)
       OR orphaned_certificate_ids_ IS NULL
       OR cardinality(orphaned_certificate_ids_) <>
          cardinality(affected_message_ids_)
       OR EXISTS (
           SELECT 1
           FROM unnest(
               affected_message_ids_,
               orphaned_proof_ids_,
               orphaned_certificate_ids_
           ) AS affected(message_id, proof_id, certificate_id)
           WHERE affected.message_id IS NULL
              OR octet_length(affected.message_id) <> 32
              OR affected.proof_id IS NULL OR affected.proof_id = ''
              OR affected.certificate_id IS NULL
              OR affected.certificate_id = ''
       )
       OR EXISTS (
           SELECT 1
           FROM unnest(affected_message_ids_) WITH ORDINALITY
               AS left_item(message_id, item_order)
           JOIN unnest(affected_message_ids_) WITH ORDINALITY
               AS right_item(message_id, item_order)
             ON right_item.item_order = left_item.item_order + 1
           WHERE left_item.message_id >= right_item.message_id
       ) THEN
        RAISE EXCEPTION 'invalid canonical reorganization identity';
    END IF;
    SELECT * INTO orphaned_proof
    FROM crosschain.source_proofs
    WHERE proof_id = orphaned_proof_id_;
    SELECT * INTO orphaned_certificate
    FROM crosschain.finality_certificates
    WHERE certificate_id = orphaned_certificate_id_;
    SELECT * INTO replacement_observation
    FROM crosschain.header_observations
    WHERE observation_id = replacement_observation_id_;
    SELECT * INTO detected_head_observation
    FROM crosschain.header_observations
    WHERE observation_id = detected_head_observation_id_;
    IF orphaned_proof.proof_id IS NULL
       OR orphaned_certificate.certificate_id IS NULL
       OR replacement_observation.observation_id IS NULL
       OR detected_head_observation.observation_id IS NULL
       OR orphaned_certificate.proof_id <> orphaned_proof.proof_id
       OR orphaned_certificate.message_id <> orphaned_proof.message_id
       OR NOT (orphaned_proof.message_id = ANY(affected_message_ids_))
       OR orphaned_proof.chain_id <> chain_id_
       OR replacement_observation.chain_id <> chain_id_
       OR detected_head_observation.chain_id <> chain_id_
       OR replacement_observation.block_hash = orphaned_proof.block_hash
       OR replacement_observation.block_number >
          detected_head_observation.block_number
       OR detected_head_observation.block_number <
          orphaned_proof.finality_head_number
       OR replacement_observation.header_authority_hash <>
          orphaned_proof.observer_authority_hash
       OR detected_head_observation.header_authority_hash <>
          orphaned_proof.observer_authority_hash
       OR replacement_observation.finality_policy_hash <>
          orphaned_proof.finality_policy_hash
       OR detected_head_observation.finality_policy_hash <>
          orphaned_proof.finality_policy_hash
       OR replacement_observation.observed_at > detected_at_
       OR detected_head_observation.observed_at > detected_at_ THEN
        RAISE EXCEPTION 'reorganization lacks authenticated header continuity';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
         AND route.route_id = route_id_
        WHERE message.message_id = orphaned_proof.message_id
          AND (
              (
                  chain_id_ = message.source_chain_id
                  AND crosschain.has_trusted_chain_evidence(
                      message.message_id,
                      orphaned_proof_id_,
                      orphaned_certificate_id_,
                      orphaned_proof.event_hash,
                      'SOURCE'
                  )
              )
              OR
              (
                  chain_id_ = message.destination_chain_id
                  AND crosschain.has_trusted_chain_evidence(
                      message.message_id,
                      orphaned_proof_id_,
                      orphaned_certificate_id_,
                      orphaned_proof.event_hash,
                      'DESTINATION'
                  )
              )
          )
    ) THEN
        RAISE EXCEPTION 'reorganization orphan lacks trusted threshold finality';
    END IF;
    IF (
        SELECT count(*)
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
         AND route.route_id = route_id_
        WHERE message.message_id = ANY(affected_message_ids_)
          AND chain_id_ IN (
              message.source_chain_id,
              message.destination_chain_id
          )
    ) <> cardinality(affected_message_ids_)
       OR EXISTS (
           SELECT 1
           FROM unnest(
               affected_message_ids_,
               orphaned_proof_ids_,
               orphaned_certificate_ids_
           ) AS affected(message_id, proof_id, certificate_id)
           WHERE NOT EXISTS (
               SELECT 1
               FROM crosschain.messages AS message
               JOIN crosschain.source_proofs AS proof
                 ON proof.message_id = message.message_id
                AND proof.chain_id = chain_id_
                AND proof.block_hash = orphaned_proof.block_hash
                AND proof.block_number = orphaned_proof.block_number
                AND proof.observer_authority_hash =
                    orphaned_proof.observer_authority_hash
                AND proof.finality_policy_hash =
                    orphaned_proof.finality_policy_hash
                AND proof.proof_id = affected.proof_id
               JOIN crosschain.finality_certificates AS certificate
                 ON certificate.message_id = message.message_id
                AND certificate.proof_id = proof.proof_id
                AND certificate.certificate_id = affected.certificate_id
               WHERE message.message_id = affected.message_id
                 AND (
                     (
                         chain_id_ = message.source_chain_id
                         AND crosschain.has_trusted_chain_evidence(
                             message.message_id,
                             proof.proof_id,
                             certificate.certificate_id,
                             proof.event_hash,
                             'SOURCE'
                         )
                     )
                     OR
                     (
                         chain_id_ = message.destination_chain_id
                         AND crosschain.has_trusted_chain_evidence(
                             message.message_id,
                             proof.proof_id,
                             certificate.certificate_id,
                             proof.event_hash,
                             'DESTINATION'
                         )
                     )
                 )
                 AND (
                     (
                         chain_id_ = message.source_chain_id
                         AND EXISTS (
                             SELECT 1
                             FROM crosschain.message_transitions AS transition
                             WHERE transition.message_id = message.message_id
                               AND transition.to_state = 'SOURCE_FINAL'
                               AND transition.evidence_hash =
                                   certificate.certificate_hash
                         )
                     )
                     OR
                     (
                         chain_id_ = message.destination_chain_id
                         AND EXISTS (
                             SELECT 1
                             FROM crosschain.execution_results AS execution
                             WHERE execution.message_id = message.message_id
                               AND execution.destination_proof_id =
                                   proof.proof_id
                               AND execution.certificate_id =
                                   certificate.certificate_id
                         )
                     )
                 )
           )
       ) THEN
        RAISE EXCEPTION 'affected messages lack exact orphaned finalized facts';
    END IF;
    INSERT INTO crosschain.reorganizations (
        reorganization_id, route_id, chain_id,
        orphaned_block_hash, orphaned_block_number,
        orphaned_proof_id, orphaned_certificate_id,
        orphaned_proof_ids, orphaned_certificate_ids,
        replacement_block_hash, replacement_block_number,
        replacement_observation_id,
        detected_head_hash, detected_head_number,
        detected_head_observation_id, depth_class,
        affected_message_ids, evidence_hash, detected_at
    ) VALUES (
        reorganization_id_, route_id_, chain_id_,
        orphaned_proof.block_hash, orphaned_proof.block_number,
        orphaned_proof_id_, orphaned_certificate_id_,
        orphaned_proof_ids_, orphaned_certificate_ids_,
        replacement_observation.block_hash,
        replacement_observation.block_number,
        replacement_observation_id_,
        detected_head_observation.block_hash,
        detected_head_observation.block_number,
        detected_head_observation_id_, 'DEEP_FINALITY',
        affected_message_ids_, evidence_hash_, detected_at_
    )
    RETURNING * INTO result;
    INSERT INTO crosschain.incidents (
        incident_id, reorganization_id, route_id, reason_code,
        severity, owner, evidence_hash, affected_message_ids,
        status, opened_at
    ) VALUES (
        incident_id_, reorganization_id_, route_id_,
        'POST_FINALITY_REORGANIZATION',
        'CRITICAL', 'cross-chain-security', evidence_hash_,
        affected_message_ids_, 'OPEN', detected_at_
    );
    FOR affected_message IN
        SELECT message.*
        FROM crosschain.messages AS message
        WHERE message.message_id = ANY(affected_message_ids_)
        ORDER BY message.message_id
        FOR UPDATE
    LOOP
        IF affected_message.state = 'DISPUTED' THEN
            IF NOT EXISTS (
                SELECT 1
                FROM crosschain.message_transitions AS transition
                WHERE transition.message_id = affected_message.message_id
                  AND transition.to_state = 'DISPUTED'
                  AND transition.evidence_hash = evidence_hash_
            ) THEN
                RAISE EXCEPTION 'message was disputed by different evidence';
            END IF;
        ELSE
            PERFORM crosschain.transition_message(
                affected_message.message_id,
                affected_message.state_version,
                affected_message.state,
                'DISPUTED',
                'SAFETY_CONTRADICTION',
                evidence_hash_,
                detected_at_
            );
        END IF;
    END LOOP;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.claim_outbox(
    publisher_id_ text,
    lease_until_ timestamptz,
    claimed_at_ timestamptz,
    batch_size_ integer
) RETURNS SETOF crosschain.outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
BEGIN
    IF publisher_id_ IS NULL OR publisher_id_ = ''
       OR claimed_at_ IS NULL OR lease_until_ IS NULL
       OR lease_until_ <= claimed_at_
       OR batch_size_ IS NULL OR batch_size_ < 1 OR batch_size_ > 1000 THEN
        RAISE EXCEPTION 'invalid outbox claim';
    END IF;

    RETURN QUERY
    WITH candidates AS (
        SELECT pending.outbox_id
        FROM crosschain.outbox AS pending
        WHERE pending.status = 'PENDING'
           OR (
                pending.status = 'CLAIMED'
                AND pending.lease_until <= claimed_at_
           )
        ORDER BY pending.created_at, pending.outbox_id
        FOR UPDATE SKIP LOCKED
        LIMIT batch_size_
    ),
    updated AS (
        UPDATE crosschain.outbox AS claimed
        SET status = 'CLAIMED',
            attempt_count = claimed.attempt_count + 1,
            publisher_id = publisher_id_,
            lease_until = lease_until_
        FROM candidates
        WHERE claimed.outbox_id = candidates.outbox_id
        RETURNING claimed.*
    )
    SELECT updated.*
    FROM updated
    ORDER BY updated.created_at, updated.outbox_id;
END;
$function$;

CREATE FUNCTION crosschain.mark_outbox_published(
    outbox_id_ text,
    publisher_id_ text,
    expected_attempt_count_ integer,
    broker_offset_ text,
    published_at_ timestamptz
) RETURNS crosschain.outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.outbox;
BEGIN
    IF outbox_id_ IS NULL OR outbox_id_ = ''
       OR publisher_id_ IS NULL OR publisher_id_ = ''
       OR expected_attempt_count_ IS NULL OR expected_attempt_count_ <= 0
       OR broker_offset_ IS NULL OR broker_offset_ = ''
       OR published_at_ IS NULL THEN
        RAISE EXCEPTION 'invalid outbox publication';
    END IF;

    SELECT * INTO result
    FROM crosschain.outbox
    WHERE outbox_id = outbox_id_
    FOR UPDATE;
    IF result.outbox_id IS NULL THEN
        RAISE EXCEPTION 'outbox record not found';
    END IF;

    IF result.status = 'PUBLISHED' THEN
        IF result.publisher_id <> publisher_id_
           OR result.attempt_count <> expected_attempt_count_
           OR result.broker_offset <> broker_offset_
           OR result.published_at <> published_at_ THEN
            RAISE EXCEPTION 'conflicting outbox publication replay';
        END IF;
        RETURN result;
    END IF;

    IF result.status <> 'CLAIMED'
       OR result.publisher_id <> publisher_id_
       OR result.attempt_count <> expected_attempt_count_
       OR published_at_ > result.lease_until THEN
        RAISE EXCEPTION 'outbox publication lease conflict';
    END IF;

    UPDATE crosschain.outbox
    SET status = 'PUBLISHED',
        lease_until = NULL,
        broker_offset = broker_offset_,
        published_at = published_at_
    WHERE outbox_id = outbox_id_
    RETURNING * INTO result;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.consume_inbox(
    consumer_id_ text,
    message_id_ bytea,
    topic_ text,
    partition_key_ text,
    broker_offset_ text,
    payload_hash_ bytea,
    consumed_at_ timestamptz
) RETURNS crosschain.inbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.inbox;
BEGIN
    IF consumer_id_ IS NULL OR consumer_id_ = ''
       OR message_id_ IS NULL OR octet_length(message_id_) <> 32
       OR topic_ IS NULL OR topic_ = ''
       OR partition_key_ IS NULL OR partition_key_ = ''
       OR broker_offset_ IS NULL OR broker_offset_ = ''
       OR payload_hash_ IS NULL OR octet_length(payload_hash_) <> 32
       OR consumed_at_ IS NULL THEN
        RAISE EXCEPTION 'invalid inbox consumption';
    END IF;

    INSERT INTO crosschain.inbox (
        consumer_id, message_id, topic, partition_key, broker_offset,
        payload_hash, consumed_at
    ) VALUES (
        consumer_id_, message_id_, topic_, partition_key_, broker_offset_,
        payload_hash_, consumed_at_
    )
    ON CONFLICT (consumer_id, topic, broker_offset) DO NOTHING
    RETURNING * INTO result;

    IF result.consumer_id IS NULL THEN
        SELECT * INTO result
        FROM crosschain.inbox
        WHERE consumer_id = consumer_id_
          AND topic = topic_
          AND broker_offset = broker_offset_;
        IF result.message_id <> message_id_
           OR result.partition_key <> partition_key_
           OR result.payload_hash <> payload_hash_
           OR result.consumed_at <> consumed_at_ THEN
            RAISE EXCEPTION 'conflicting inbox consumption replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_provider_attempt(
    message_id_ bytea,
    provider_id_ text,
    attempt_number_ integer,
    serialized_envelope_hash_ bytea,
    source_proof_hash_ bytea,
    status_ text,
    provider_receipt_hash_ bytea,
    attempted_at_ timestamptz
) RETURNS crosschain.provider_attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.provider_attempts;
BEGIN
    INSERT INTO crosschain.provider_attempts (
        message_id, provider_id, attempt_number, serialized_envelope_hash,
        source_proof_hash, status, provider_receipt_hash, attempted_at
    ) VALUES (
        message_id_, provider_id_, attempt_number_, serialized_envelope_hash_,
        source_proof_hash_, status_, provider_receipt_hash_, attempted_at_
    )
    ON CONFLICT (message_id, provider_id, attempt_number) DO NOTHING
    RETURNING * INTO result;
    IF result.message_id IS NULL THEN
        SELECT * INTO result FROM crosschain.provider_attempts
        WHERE message_id = message_id_ AND provider_id = provider_id_
          AND attempt_number = attempt_number_;
        IF result.serialized_envelope_hash <> serialized_envelope_hash_
           OR result.source_proof_hash <> source_proof_hash_
           OR result.status <> status_
           OR result.provider_receipt_hash IS DISTINCT FROM provider_receipt_hash_
           OR result.attempted_at <> attempted_at_ THEN
            RAISE EXCEPTION 'conflicting provider attempt replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_execution(
    message_id_ bytea,
    destination_chain_id_ numeric,
    transaction_hash_ bytea,
    log_index_ numeric,
    result_hash_ bytea,
    effect_commitment_ bytea,
    executed_at_ timestamptz
) RETURNS crosschain.execution_results
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.execution_results;
    destination_proof_id_ text;
    certificate_id_ text;
BEGIN
    -- Execution ingestion and recovery tombstoning are mutually exclusive
    -- terminal facts. Serialize both functions on the authoritative message
    -- row so a stale VERIFIED observation cannot race a RECOVERY_PENDING
    -- tombstone through the cross-table exclusion triggers.
    PERFORM 1
    FROM crosschain.messages
    WHERE message_id = message_id_
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'execution message not found';
    END IF;
    SELECT * INTO result FROM crosschain.execution_results WHERE message_id = message_id_;
    IF result.message_id IS NOT NULL THEN
        IF result.destination_chain_id <> destination_chain_id_
           OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_ OR result.result_hash <> result_hash_
           OR result.effect_commitment <> effect_commitment_
           OR result.executed_at <> executed_at_ THEN
            RAISE EXCEPTION 'conflicting execution replay';
        END IF;
        RETURN result;
    END IF;
    SELECT proof.proof_id, certificate.certificate_id
    INTO destination_proof_id_, certificate_id_
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
        JOIN crosschain.source_proofs AS proof
          ON proof.message_id = message.message_id
         AND proof.chain_id = message.destination_chain_id
         AND proof.transaction_hash = transaction_hash_
         AND proof.log_index = log_index_
         AND proof.finality_policy_hash =
             message.destination_finality_policy_hash
         AND proof.event_hash = crosschain.execution_evidence_hash(
             message_id_, destination_chain_id_, transaction_hash_, log_index_,
             result_hash_, effect_commitment_, executed_at_
         )
         AND proof.observed_at >= executed_at_
        JOIN crosschain.finality_certificates AS certificate
          ON certificate.message_id = message.message_id
         AND certificate.proof_id = proof.proof_id
         AND certificate.certified_at >= proof.observed_at
        JOIN crosschain.signer_sets AS signer_set
          ON signer_set.signer_set_hash = certificate.signer_set_hash
         AND signer_set.version = certificate.signer_set_version
         AND signer_set.signer_set_hash =
             route.destination_signer_set_hash
         AND signer_set.version = route.destination_signer_set_version
         AND signer_set.status IN ('ACTIVE', 'DEPRECATED')
         AND certificate.signature_count >= signer_set.threshold
         AND certificate.certified_at >= signer_set.valid_from
         AND certificate.certified_at <= signer_set.valid_until
        JOIN crosschain.chain_versions AS chain_version
          ON chain_version.chain_id = proof.chain_id
         AND chain_version.version = route.destination_chain_version
         AND chain_version.coordinator = message.destination_coordinator
         AND chain_version.observer_authority_hash =
             proof.observer_authority_hash
         AND chain_version.status IN ('ACTIVE', 'DEPRECATED')
        WHERE message.message_id = message_id_
          AND message.state = 'VERIFIED'
          AND message.destination_chain_id = destination_chain_id_
        ORDER BY proof.proof_id, certificate.certificate_id
        LIMIT 1;
    IF destination_proof_id_ IS NULL OR certificate_id_ IS NULL THEN
        RAISE EXCEPTION 'execution requires trusted exact destination evidence';
    END IF;
    INSERT INTO crosschain.execution_results (
        message_id, destination_chain_id, transaction_hash, log_index,
        result_hash, effect_commitment, destination_proof_id,
        certificate_id, executed_at
    ) VALUES (
        message_id_, destination_chain_id_, transaction_hash_, log_index_,
        result_hash_, effect_commitment_, destination_proof_id_,
        certificate_id_, executed_at_
    )
    ON CONFLICT (message_id) DO NOTHING
    RETURNING * INTO result;
    IF result.message_id IS NULL THEN
        SELECT * INTO result FROM crosschain.execution_results WHERE message_id = message_id_;
        IF result.destination_chain_id <> destination_chain_id_
           OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_ OR result.result_hash <> result_hash_
           OR result.effect_commitment <> effect_commitment_
           OR result.executed_at <> executed_at_ THEN
            RAISE EXCEPTION 'conflicting execution replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

-- Manifest-driven local ingestion preserves the exact Solidity
-- acknowledgement-event commitment instead of substituting the SQL-specific
-- execution_evidence_hash used by the legacy synthetic worker.
CREATE FUNCTION crosschain.record_evm_execution(
    message_id_ bytea,
    destination_chain_id_ numeric,
    transaction_hash_ bytea,
    log_index_ numeric,
    result_hash_ bytea,
    destination_event_hash_ bytea,
    destination_proof_id_ text,
    certificate_id_ text,
    action_projection_ jsonb,
    executed_at_ timestamptz
) RETURNS crosschain.execution_results
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.execution_results;
    effect_commitment_ bytea;
    action_type_ smallint;
BEGIN
    PERFORM 1 FROM crosschain.messages
    WHERE message_id = message_id_
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'execution message not found';
    END IF;
    SELECT action_type INTO action_type_
    FROM crosschain.messages
    WHERE message_id = message_id_;
    IF action_projection_ IS NULL
       OR jsonb_typeof(action_projection_) <> 'object'
       OR action_projection_ = '{}'::jsonb THEN
        RAISE EXCEPTION 'execution action projection is required';
    END IF;
    IF action_projection_->>'proof_boundary'
            <> 'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT'
       OR action_projection_->>'destination_result_hash'
            <> '0x' || encode(result_hash_, 'hex')
       OR action_projection_->>'evm_acknowledgement_commitment'
            <> '0x' || encode(destination_event_hash_, 'hex') THEN
        RAISE EXCEPTION 'execution projection differs from authenticated EVM result';
    END IF;
    effect_commitment_ := crosschain.action_projection_hash(
        action_type_,
        action_projection_
    );
    SELECT * INTO result
    FROM crosschain.execution_results
    WHERE message_id = message_id_;
    IF result.message_id IS NOT NULL THEN
        IF result.destination_chain_id <> destination_chain_id_
           OR result.transaction_hash <> transaction_hash_
           OR result.log_index <> log_index_
           OR result.result_hash <> result_hash_
           OR result.effect_commitment <> effect_commitment_
           OR result.action_projection IS DISTINCT FROM action_projection_
           OR result.destination_proof_id <> destination_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.executed_at <> executed_at_ THEN
            RAISE EXCEPTION 'conflicting execution replay';
        END IF;
        RETURN result;
    END IF;
    IF destination_event_hash_ IS NULL
       OR octet_length(destination_event_hash_) <> 32
       OR NOT EXISTS (
           SELECT 1
           FROM crosschain.messages AS message
           JOIN crosschain.source_proofs AS proof
             ON proof.proof_id = destination_proof_id_
             AND proof.message_id = message.message_id
             AND proof.chain_id = message.destination_chain_id
             AND proof.transaction_hash = transaction_hash_
             AND proof.log_index = log_index_
             AND proof.event_hash = destination_event_hash_
            AND proof.finality_policy_hash =
                message.destination_finality_policy_hash
            AND proof.observed_at >= executed_at_
           JOIN crosschain.finality_certificates AS certificate
             ON certificate.certificate_id = certificate_id_
            AND certificate.message_id = message.message_id
            AND certificate.proof_id = proof.proof_id
            AND certificate.certified_at >= proof.observed_at
           JOIN crosschain.route_versions AS route
             ON route.route_policy_hash = message.route_policy_hash
           JOIN crosschain.signer_sets AS signer_set
             ON signer_set.signer_set_hash = certificate.signer_set_hash
            AND signer_set.version = certificate.signer_set_version
            AND signer_set.signer_set_hash =
                route.destination_signer_set_hash
            AND signer_set.version =
                route.destination_signer_set_version
            AND signer_set.status IN ('ACTIVE', 'DEPRECATED')
            AND certificate.signature_count >= signer_set.threshold
            AND certificate.certified_at >= signer_set.valid_from
            AND certificate.certified_at <= signer_set.valid_until
           JOIN crosschain.chain_versions AS chain_version
             ON chain_version.chain_id = proof.chain_id
            AND chain_version.version = route.destination_chain_version
            AND chain_version.coordinator =
                message.destination_coordinator
            AND chain_version.observer_authority_hash =
                proof.observer_authority_hash
            AND chain_version.status IN ('ACTIVE', 'DEPRECATED')
           WHERE message.message_id = message_id_
             AND message.state = 'VERIFIED'
             AND message.destination_chain_id = destination_chain_id_
       ) THEN
        RAISE EXCEPTION 'execution requires exact trusted EVM destination evidence';
    END IF;
    INSERT INTO crosschain.execution_results (
        message_id, destination_chain_id, transaction_hash, log_index,
        result_hash, effect_commitment, action_projection, destination_proof_id,
        certificate_id, executed_at
    ) VALUES (
        message_id_, destination_chain_id_, transaction_hash_, log_index_,
        result_hash_, effect_commitment_, action_projection_, destination_proof_id_,
        certificate_id_, executed_at_
    )
    RETURNING * INTO result;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_evm_acknowledgement(
    message_id_ bytea,
    execution_result_hash_ bytea,
    destination_event_hash_ bytea,
    destination_proof_id_ text,
    certificate_id_ text,
    acknowledged_at_ timestamptz
) RETURNS crosschain.acknowledgements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.acknowledgements;
BEGIN
    SELECT * INTO result
    FROM crosschain.acknowledgements
    WHERE message_id = message_id_;
    IF result.message_id IS NOT NULL THEN
        IF result.execution_result_hash <> execution_result_hash_
           OR result.destination_proof_id <> destination_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.acknowledged_at <> acknowledged_at_ THEN
            RAISE EXCEPTION 'conflicting acknowledgement replay';
        END IF;
        RETURN result;
    END IF;
    IF destination_event_hash_ IS NULL
       OR octet_length(destination_event_hash_) <> 32
       OR NOT EXISTS (
           SELECT 1
           FROM crosschain.execution_results AS execution
           JOIN crosschain.messages AS message
             ON message.message_id = execution.message_id
           JOIN crosschain.source_proofs AS proof
             ON proof.proof_id = destination_proof_id_
            AND proof.message_id = message.message_id
            AND proof.event_hash = destination_event_hash_
            AND proof.proof_id = execution.destination_proof_id
           JOIN crosschain.finality_certificates AS certificate
             ON certificate.certificate_id = certificate_id_
            AND certificate.message_id = message.message_id
            AND certificate.proof_id = proof.proof_id
            AND certificate.certificate_id = execution.certificate_id
           WHERE execution.message_id = message_id_
             AND execution.result_hash = execution_result_hash_
             AND message.state = 'ACK_PENDING'
             AND acknowledged_at_ >= execution.executed_at
             AND crosschain.has_trusted_chain_evidence(
                 message_id_, destination_proof_id_, certificate_id_,
                 destination_event_hash_, 'DESTINATION'
             )
       ) THEN
        RAISE EXCEPTION 'acknowledgement requires exact trusted EVM destination evidence';
    END IF;
    INSERT INTO crosschain.acknowledgements (
        message_id, execution_result_hash, destination_proof_id,
        certificate_id, acknowledged_at
    ) VALUES (
        message_id_, execution_result_hash_, destination_proof_id_,
        certificate_id_, acknowledged_at_
    )
    RETURNING * INTO result;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_tombstone(
    original_message_id_ bytea,
    recovery_id_ bytea,
    tombstone_hash_ bytea,
    destination_state_commitment_ bytea,
    destination_proof_id_ text,
    certificate_id_ text,
    tombstoned_at_ timestamptz
) RETURNS crosschain.tombstones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.tombstones;
BEGIN
    -- See record_execution: both terminal-fact writers take this same row
    -- lock before checking state or inserting their mutually exclusive fact.
    PERFORM 1
    FROM crosschain.messages
    WHERE message_id = original_message_id_
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'tombstone message not found';
    END IF;
    SELECT * INTO result
    FROM crosschain.tombstones
    WHERE original_message_id = original_message_id_;
    IF result.original_message_id IS NOT NULL THEN
        IF result.recovery_id <> recovery_id_
           OR result.tombstone_hash <> tombstone_hash_
           OR result.destination_state_commitment <> destination_state_commitment_
           OR result.destination_proof_id <> destination_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.tombstoned_at <> tombstoned_at_ THEN
            RAISE EXCEPTION 'conflicting tombstone replay';
        END IF;
        RETURN result;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.recovery_requests AS request
        JOIN crosschain.messages AS message
          ON message.message_id = request.original_message_id
        JOIN crosschain.source_proofs AS proof
          ON proof.proof_id = destination_proof_id_
         AND proof.message_id = request.original_message_id
        WHERE request.recovery_id = recovery_id_
          AND request.original_message_id = original_message_id_
          AND request.destination_state_commitment = destination_state_commitment_
          AND message.state = 'RECOVERY_PENDING'
          AND tombstoned_at_ >= message.updated_at
          AND tombstoned_at_ <= proof.observed_at
    )
       OR NOT crosschain.has_trusted_chain_evidence(
           original_message_id_, destination_proof_id_, certificate_id_,
           tombstone_hash_, 'DESTINATION'
       ) THEN
        RAISE EXCEPTION 'tombstone requires exact signed request and finalized destination fact';
    END IF;

    INSERT INTO crosschain.tombstones (
        original_message_id, recovery_id, tombstone_hash,
        destination_state_commitment, destination_proof_id,
        certificate_id, tombstoned_at
    ) VALUES (
        original_message_id_, recovery_id_, tombstone_hash_,
        destination_state_commitment_, destination_proof_id_,
        certificate_id_, tombstoned_at_
    )
    ON CONFLICT (original_message_id) DO NOTHING
    RETURNING * INTO result;
    IF result.original_message_id IS NULL THEN
        SELECT * INTO result FROM crosschain.tombstones
        WHERE original_message_id = original_message_id_;
        IF result.recovery_id <> recovery_id_ OR result.tombstone_hash <> tombstone_hash_
           OR result.destination_state_commitment <> destination_state_commitment_
           OR result.destination_proof_id <> destination_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.tombstoned_at <> tombstoned_at_ THEN
            RAISE EXCEPTION 'conflicting tombstone replay';
        END IF;
    END IF;
    RETURN result;
END;
$function$;

CREATE FUNCTION crosschain.record_compensation(
    original_message_id_ bytea,
    recovery_id_ bytea,
    compensation_type_ text,
    asset_id_ text,
    units_ numeric,
    recipient_ text,
    compensation_payload_hash_ bytea,
    result_hash_ bytea,
    source_proof_id_ text,
    certificate_id_ text,
    compensated_at_ timestamptz
) RETURNS crosschain.compensations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    result crosschain.compensations;
    expected_event_hash bytea;
BEGIN
    SELECT * INTO result
    FROM crosschain.compensations
    WHERE original_message_id = original_message_id_;
    IF result.original_message_id IS NOT NULL THEN
        IF result.recovery_id <> recovery_id_
           OR result.compensation_type <> compensation_type_
           OR result.asset_id <> asset_id_ OR result.units <> units_
           OR result.recipient <> recipient_
           OR result.compensation_payload_hash <> compensation_payload_hash_
           OR result.result_hash <> result_hash_
           OR result.source_proof_id <> source_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.compensated_at <> compensated_at_ THEN
            RAISE EXCEPTION 'conflicting compensation replay';
        END IF;
        PERFORM crosschain.post_compensation_journals(
            original_message_id_
        );
        RETURN result;
    END IF;
    expected_event_hash := crosschain.compensation_evidence_hash(
        original_message_id_, recovery_id_, compensation_type_, asset_id_,
        units_, recipient_, compensation_payload_hash_, result_hash_,
        compensated_at_
    );
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.recovery_requests AS request
        JOIN crosschain.tombstones AS tombstone
          ON tombstone.original_message_id = request.original_message_id
         AND tombstone.recovery_id = request.recovery_id
        JOIN crosschain.messages AS message
          ON message.message_id = request.original_message_id
        JOIN crosschain.source_proofs AS proof
          ON proof.proof_id = source_proof_id_
         AND proof.message_id = request.original_message_id
        WHERE request.recovery_id = recovery_id_
          AND request.original_message_id = original_message_id_
          AND request.compensation_payload_hash = compensation_payload_hash_
          AND message.state = 'DESTINATION_TOMBSTONED'
          AND compensated_at_ >= message.updated_at
          AND compensated_at_ <= proof.observed_at
    )
       OR NOT crosschain.has_trusted_chain_evidence(
           original_message_id_, source_proof_id_, certificate_id_,
           expected_event_hash, 'SOURCE'
       ) THEN
        RAISE EXCEPTION 'compensation requires exact request payload and finalized source fact';
    END IF;

    INSERT INTO crosschain.compensations (
        original_message_id, recovery_id, compensation_type, asset_id,
        units, recipient, compensation_payload_hash, result_hash,
        source_proof_id, certificate_id, compensated_at
    ) VALUES (
        original_message_id_, recovery_id_, compensation_type_, asset_id_,
        units_, recipient_, compensation_payload_hash_, result_hash_,
        source_proof_id_, certificate_id_, compensated_at_
    )
    ON CONFLICT (original_message_id) DO NOTHING
    RETURNING * INTO result;
    IF result.original_message_id IS NULL THEN
        SELECT * INTO result FROM crosschain.compensations
        WHERE original_message_id = original_message_id_;
        IF result.recovery_id <> recovery_id_
           OR result.compensation_type <> compensation_type_
           OR result.asset_id <> asset_id_ OR result.units <> units_
           OR result.recipient <> recipient_
           OR result.compensation_payload_hash <> compensation_payload_hash_
           OR result.result_hash <> result_hash_
           OR result.source_proof_id <> source_proof_id_
           OR result.certificate_id <> certificate_id_
           OR result.compensated_at <> compensated_at_ THEN
            RAISE EXCEPTION 'conflicting compensation replay';
        END IF;
    END IF;
    PERFORM crosschain.post_compensation_journals(
        original_message_id_
    );
    RETURN result;
END;
$function$;

DO $ownership$
DECLARE
    object_name text;
    function_name text;
BEGIN
    FOR object_name IN
        SELECT quote_ident(c.relname)
        FROM pg_class AS c
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname = 'crosschain'
          AND c.relkind IN ('r', 'p', 'S', 'v', 'm')
    LOOP
        EXECUTE format('ALTER TABLE crosschain.%s OWNER TO unified_crosschain_owner', object_name);
    END LOOP;
    FOR function_name IN
        SELECT p.oid::regprocedure::text
        FROM pg_proc AS p
        JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'crosschain'
    LOOP
        EXECUTE format('ALTER FUNCTION %s OWNER TO unified_crosschain_owner', function_name);
    END LOOP;
END;
$ownership$;

ALTER TABLE ledger.crosschain_recovery_journal_links
    OWNER TO unified_crosschain_owner;

REVOKE ALL ON ALL TABLES IN SCHEMA crosschain
    FROM PUBLIC, unified_crosschain_runtime, unified_crosschain_observer,
         unified_crosschain_finality_attester,
         unified_crosschain_recovery_verifier,
         unified_crosschain_reorganization_verifier;
REVOKE ALL ON ledger.crosschain_recovery_journal_links
    FROM PUBLIC, unified_crosschain_runtime, unified_crosschain_observer,
         unified_crosschain_finality_attester,
         unified_crosschain_recovery_verifier,
         unified_crosschain_reorganization_verifier;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crosschain
    FROM PUBLIC, unified_crosschain_runtime, unified_crosschain_observer,
         unified_crosschain_finality_attester,
         unified_crosschain_recovery_verifier,
         unified_crosschain_reorganization_verifier;
GRANT SELECT ON ALL TABLES IN SCHEMA crosschain TO unified_crosschain_runtime;
GRANT SELECT ON ledger.crosschain_recovery_journal_links
    TO unified_crosschain_runtime, unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.record_message(
    bytea, integer, bytea, numeric, bytea, bytea, numeric, bytea, bytea,
    bytea, numeric, bytea, smallint, bytea, timestamptz, timestamptz, bytea,
    bytea, bytea, bytea, bytea, bytea, bytea, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.record_source_proof(
    text, bytea, numeric, bytea, numeric, numeric, numeric, bytea, bytea,
    bytea, bytea, numeric, bytea, numeric, bytea, bytea, bytea, bytea,
    bytea, timestamptz, bytea, bytea
) TO unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.record_header_observation(
    text, numeric, bytea, numeric, bytea, bytea, bytea, bytea, timestamptz
) TO unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.record_finality_certificate(
    text, bytea, text, bytea, bigint, bit varying, integer, bytea, timestamptz,
    bytea, bytea[]
) TO unified_crosschain_finality_attester;
GRANT EXECUTE ON FUNCTION crosschain.load_source_proof(
    text
) TO unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.load_finality_certificate(
    text
) TO unified_crosschain_finality_attester;
GRANT EXECUTE ON FUNCTION crosschain.record_recovery_request(
    bytea, bytea, bytea, numeric, bytea, numeric, bytea, bytea, bytea,
    bytea, bytea, bytea, bytea, numeric, numeric, bytea, smallint,
    bytea, bigint, bytea, bit varying, integer, bytea, timestamptz
) TO unified_crosschain_recovery_verifier;
GRANT EXECUTE ON FUNCTION crosschain.record_reorganization(
    text, numeric, text[], text[], text, text, bytea[], bytea, timestamptz
) TO unified_crosschain_reorganization_verifier;
GRANT EXECUTE ON FUNCTION crosschain.record_evm_acknowledgement(
    bytea, bytea, bytea, text, text, timestamptz
) TO unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.record_action_projection(
    bytea, jsonb, timestamptz
) TO unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.compensation_evidence_hash(
    bytea, bytea, text, text, numeric, text, bytea, bytea, timestamptz
) TO unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.transition_message(
    bytea, bigint, text, text, text, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.claim_outbox(
    text, timestamptz, timestamptz, integer
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.mark_outbox_published(
    text, text, integer, text, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.consume_inbox(
    text, bytea, text, text, text, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.record_provider_attempt(
    bytea, text, integer, bytea, bytea, text, bytea, timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.record_evm_execution(
    bytea, numeric, bytea, numeric, bytea, bytea, text, text, jsonb,
    timestamptz
) TO unified_crosschain_runtime;
GRANT EXECUTE ON FUNCTION crosschain.record_tombstone(
    bytea, bytea, bytea, bytea, text, text, timestamptz
) TO unified_crosschain_observer;
GRANT EXECUTE ON FUNCTION crosschain.record_compensation(
    bytea, bytea, text, text, numeric, text, bytea, bytea, text, text,
    timestamptz
) TO unified_crosschain_observer;

ALTER DEFAULT PRIVILEGES FOR ROLE unified_crosschain_owner IN SCHEMA crosschain
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE unified_crosschain_owner IN SCHEMA crosschain
    REVOKE ALL ON FUNCTIONS FROM PUBLIC;

COMMIT;
