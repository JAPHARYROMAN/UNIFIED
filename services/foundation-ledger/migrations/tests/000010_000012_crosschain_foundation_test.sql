\set ON_ERROR_STOP on

BEGIN;

SET ROLE unified_crosschain_runtime;

DO $test$
BEGIN
    IF has_table_privilege(
        'unified_crosschain_runtime',
        'public.journal',
        'SELECT'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'public.journal_entry',
        'SELECT'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'public.journal_balance',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'runtime role unexpectedly reads the foundation ledger';
    END IF;
    IF has_function_privilege(
        'unified_crosschain_runtime',
        'public.assert_journal_balanced()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'runtime role unexpectedly executes the balance trigger';
    END IF;
    IF has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.messages',
        'INSERT'
    ) THEN
        RAISE EXCEPTION 'runtime role unexpectedly has direct message INSERT';
    END IF;
    IF NOT has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_message(bytea,integer,bytea,numeric,bytea,bytea,numeric,bytea,bytea,bytea,numeric,bytea,smallint,bytea,timestamptz,timestamptz,bytea,bytea,bytea,bytea,bytea,bytea,bytea,bytea,timestamptz)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'runtime role lacks reviewed record_message capability';
    END IF;
    IF has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.outbox',
        'INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.inbox',
        'INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'runtime role unexpectedly has direct broker table writes';
    END IF;
    IF NOT has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.claim_outbox(text,timestamptz,timestamptz,integer)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.mark_outbox_published(text,text,integer,text,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.consume_inbox(text,bytea,text,text,text,bytea,timestamptz)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'runtime role lacks reviewed outbox/inbox capabilities';
    END IF;
    IF has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.source_proofs',
        'INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.finality_certificates',
        'INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'runtime role unexpectedly controls finality evidence';
    END IF;
    IF has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_source_proof(text,bytea,numeric,bytea,numeric,numeric,numeric,bytea,bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,timestamptz,bytea,bytea)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_finality_certificate(text,bytea,text,bytea,bigint,bit varying,integer,bytea,timestamptz,bytea,bytea[])',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_source_proof(text,bytea,numeric,bytea,numeric,numeric,numeric,bytea,bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,timestamptz,bytea,bytea)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_finality_certificate(text,bytea,text,bytea,bigint,bit varying,integer,bytea,timestamptz,bytea,bytea[])',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_finality_attester',
        'crosschain.record_finality_certificate(text,bytea,text,bytea,bigint,bit varying,integer,bytea,timestamptz,bytea,bytea[])',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_finality_attester',
        'crosschain.record_source_proof(text,bytea,numeric,bytea,numeric,numeric,numeric,bytea,bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,timestamptz,bytea,bytea)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'proof and finality-attester privilege boundary is invalid';
    END IF;
    IF has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_recovery_request(bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,bytea,bytea,numeric,numeric,bytea,smallint,bytea,bigint,bytea,bit varying,integer,bytea,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_recovery_verifier',
        'crosschain.record_recovery_request(bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,bytea,bytea,numeric,numeric,bytea,smallint,bytea,bigint,bytea,bit varying,integer,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_recovery_verifier',
        'crosschain.record_source_proof(text,bytea,numeric,bytea,numeric,numeric,numeric,bytea,bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,timestamptz,bytea,bytea)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_recovery_verifier',
        'crosschain.record_finality_certificate(text,bytea,text,bytea,bigint,bit varying,integer,bytea,timestamptz,bytea,bytea[])',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'recovery verifier privilege boundary is invalid';
    END IF;
    IF has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_header_observation(text,numeric,bytea,numeric,bytea,bytea,bytea,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_reorganization(text,numeric,text[],text[],text,text,bytea[],bytea,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_header_observation(text,numeric,bytea,numeric,bytea,bytea,bytea,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_reorganization(text,numeric,text[],text[],text,text,bytea[],bytea,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_reorganization_verifier',
        'crosschain.record_reorganization(text,numeric,text[],text[],text,text,bytea[],bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_reorganization_verifier',
        'crosschain.record_header_observation(text,numeric,bytea,numeric,bytea,bytea,bytea,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_reorganization_verifier',
        'crosschain.record_source_proof(text,bytea,numeric,bytea,numeric,numeric,numeric,bytea,bytea,bytea,bytea,numeric,bytea,numeric,bytea,bytea,bytea,bytea,bytea,timestamptz,bytea,bytea)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_reorganization_verifier',
        'crosschain.record_finality_certificate(text,bytea,text,bytea,bigint,bit varying,integer,bytea,timestamptz,bytea,bytea[])',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'reorganization verifier privilege boundary is invalid';
    END IF;
    IF has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_acknowledgement(bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_acknowledgement(bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_execution(bytea,numeric,bytea,numeric,bytea,bytea,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_evm_execution(bytea,numeric,bytea,numeric,bytea,bytea,text,text,jsonb,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_evm_acknowledgement(bytea,bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_evm_acknowledgement(bytea,bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_action_projection(bytea,jsonb,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_tombstone(bytea,bytea,bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_compensation(bytea,bytea,text,text,numeric,text,bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_action_projection(bytea,jsonb,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_tombstone(bytea,bytea,bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_observer',
        'crosschain.record_compensation(bytea,bytea,text,text,numeric,text,bytea,bytea,text,text,timestamptz)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'chain fact privilege boundary is invalid';
    END IF;
    IF has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.post_balanced_journal(text,text,text,text,text,bytea,timestamptz,text,numeric,text,text,text)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_direct_home_repayment_evidence(text,text,text,numeric,text,bytea,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_home_accounting_runtime',
        'crosschain.record_direct_home_repayment_evidence(text,text,text,numeric,text,bytea,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_finality_attester',
        'crosschain.record_direct_home_repayment_evidence(text,text,text,numeric,text,bytea,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_home_accounting_runtime',
        'crosschain.commit_direct_home_repayment(text,text,text,numeric,numeric,numeric,text,bytea,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_finality_attester',
        'crosschain.commit_direct_home_repayment(text,text,text,numeric,numeric,numeric,text,bytea,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.action_projections',
        'INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.direct_home_repayment_evidence',
        'INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'ledger.bridge_journal_links',
        'INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'ledger.satellite_settlement_links',
        'INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'journal',
        'INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'accounting authority or role-grant boundary is invalid';
    END IF;
    IF has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.register_chain_version(numeric,bigint,bytea,bytea,bytea,bytea,numeric,text,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.register_route_version(text,bigint,numeric,bigint,bytea,bytea,numeric,bigint,bytea,bytea,text,bytea,bytea,bytea,bytea,bigint,bytea,bigint,bytea,numeric,text,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.register_loan_route(text,text,bigint,numeric,numeric,bytea,bytea,text,text,text,numeric,text,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.activate_bridge_exposure_policy(bigint,numeric,bytea,numeric,numeric,numeric,numeric,integer,integer,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.commit_direct_home_repayment(text,text,text,numeric,numeric,numeric,text,bytea,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'runtime role unexpectedly controls trusted references or direct repayment';
    END IF;
    IF NOT has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.record_loan_cancellation_request(text,text,text,bytea,text,bytea,bytea,bytea,bytea,bytea,bytea,bytea,numeric,bytea,bytea,timestamptz)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.commit_loan_cancellation_completion(text,text,text,bytea,text,bytea,bytea,bytea,bytea,bytea,bytea,bytea,bytea,numeric,bytea,bytea,numeric,bytea,timestamptz,bytea,numeric,bytea,timestamptz)',
        'EXECUTE'
    ) OR has_function_privilege(
        'unified_crosschain_runtime',
        'crosschain.has_exact_tombstoned_disbursement(bytea,bytea,bytea,bytea,bytea,bytea)',
        'EXECUTE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.loan_cancellation_requests',
        'INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
        'unified_crosschain_runtime',
        'crosschain.loan_cancellation_completions',
        'INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'cancellation capability boundary is invalid';
    END IF;
END;
$test$;

RESET ROLE;

-- Prove the privileged trigger boundary does not weaken the invariant. A
-- deliberately one-sided journal remains rejected when the deferred
-- constraint is forced, as it would be at COMMIT.
DO $test$
BEGIN
    BEGIN
        SET CONSTRAINTS journal_balanced_on_commit DEFERRED;
        INSERT INTO public.journal (
            journal_id, legal_entity_id, book_id, source_system,
            idempotency_key, correlation_id, evidence_hash, effective_at,
            status, entry_type, source_event_id
        ) VALUES (
            'phase8-unbalanced-trigger-regression',
            'unified-protocol',
            'cross-chain-subledger',
            'phase8-test',
            'phase8-unbalanced-trigger-regression',
            'phase8-unbalanced-trigger-regression',
            repeat('00', 32),
            '2026-01-01 00:00:00+00',
            'POSTED',
            'PHASE8_TRIGGER_REGRESSION',
            'phase8-unbalanced-trigger-regression'
        );
        INSERT INTO public.journal_entry (
            journal_id, line_number, account_code, side, asset_id, units
        ) VALUES (
            'phase8-unbalanced-trigger-regression',
            1,
            '1410',
            'DEBIT',
            'uft',
            1
        );
        SET CONSTRAINTS journal_balanced_on_commit IMMEDIATE;
        RAISE EXCEPTION 'unbalanced deferred journal was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'unbalanced deferred journal was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

-- Keep the balance trigger immediate for this rollback-scoped test. The
-- balanced runtime definer writes below therefore exercise the trigger under
-- role isolation instead of postponing it until ROLLBACK discards the fixture.
SET CONSTRAINTS journal_balanced_on_commit IMMEDIATE;

SELECT crosschain.register_chain_version(
    31337, 1, decode(repeat('11', 20), 'hex'), decode(repeat('12', 20), 'hex'),
    decode(repeat('13', 32), 'hex'), decode(repeat('14', 32), 'hex'),
    1, 'ACTIVE', '2026-01-01 00:00:00+00'
);
SELECT crosschain.register_chain_version(
    31338, 1, decode(repeat('21', 20), 'hex'), decode(repeat('22', 20), 'hex'),
    decode(repeat('23', 32), 'hex'), decode(repeat('24', 32), 'hex'),
    1, 'ACTIVE', '2026-01-01 00:00:00+00'
);

INSERT INTO crosschain.signer_sets (
    signer_set_hash, version, threshold, signer_addresses,
    valid_from, valid_until, status
) VALUES
    (
        decode(repeat('60', 32), 'hex'), 1, 2,
        ARRAY[
            decode(repeat('61', 20), 'hex'),
            decode(repeat('62', 20), 'hex'),
            decode(repeat('63', 20), 'hex')
        ],
        '2025-01-01 00:00:00+00', '2027-01-01 00:00:00+00', 'ACTIVE'
    ),
    (
        decode(repeat('60', 32), 'hex'), 2, 2,
        ARRAY[
            decode(repeat('64', 20), 'hex'),
            decode(repeat('65', 20), 'hex'),
            decode(repeat('66', 20), 'hex')
        ],
        '2025-01-01 00:00:00+00', '2027-01-01 00:00:00+00', 'ACTIVE'
    ),
    (
        decode(repeat('70', 32), 'hex'), 1, 2,
        ARRAY[
            decode(repeat('71', 20), 'hex'),
            decode(repeat('72', 20), 'hex'),
            decode(repeat('73', 20), 'hex')
        ],
        '2025-01-01 00:00:00+00', '2027-01-01 00:00:00+00', 'ACTIVE'
    );

INSERT INTO crosschain.recovery_authorizer_sets (
    authorizer_set_hash, version, threshold, authorizer_addresses,
    valid_from, valid_until, status
) VALUES (
    decode(repeat('90', 32), 'hex'), 1, 2,
    ARRAY[
        decode(repeat('91', 20), 'hex'),
        decode(repeat('92', 20), 'hex'),
        decode(repeat('93', 20), 'hex')
    ],
    '2025-01-01 00:00:00+00',
    '2027-01-01 00:00:00+00',
    'ACTIVE'
);

DO $test$
BEGIN
    BEGIN
        INSERT INTO crosschain.signer_sets (
            signer_set_hash, version, threshold, signer_addresses,
            valid_from, valid_until, status
        ) VALUES (
            decode(repeat('80', 32), 'hex'), 1, 2,
            ARRAY[
                decode(repeat('81', 20), 'hex'),
                decode(repeat('81', 20), 'hex'),
                decode(repeat('82', 20), 'hex')
            ],
            '2025-01-01 00:00:00+00',
            '2027-01-01 00:00:00+00',
            'ACTIVE'
        );
        RAISE EXCEPTION 'duplicate signer set was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END;
$test$;

SELECT crosschain.register_route_version(
    'route-phase8', 1,
    31337, 1, decode(repeat('11', 20), 'hex'), decode(repeat('31', 20), 'hex'),
    31338, 1, decode(repeat('21', 20), 'hex'), decode(repeat('32', 20), 'hex'),
    'PHASE8_ALL',
    decode(repeat('41', 32), 'hex'), decode(repeat('42', 32), 'hex'),
    decode(repeat('43', 32), 'hex'),
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('44', 32), 'hex'),
    1, 'ACTIVE', '2026-01-01 00:00:00+00'
);

SELECT crosschain.register_route_version(
    'phase8-disbursement', 1,
    31337, 1, decode(repeat('11', 20), 'hex'), decode(repeat('e1', 20), 'hex'),
    31338, 1, decode(repeat('21', 20), 'hex'), decode(repeat('e2', 20), 'hex'),
    '0x' || repeat('d1', 32),
    decode(repeat('41', 32), 'hex'), decode(repeat('42', 32), 'hex'),
    decode(repeat('43', 32), 'hex'),
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('de', 32), 'hex'),
    1, 'ACTIVE', '2026-01-01 00:00:00+00'
);
SELECT crosschain.register_route_version(
    'phase8-report', 1,
    31338, 1, decode(repeat('21', 20), 'hex'), decode(repeat('e3', 20), 'hex'),
    31337, 1, decode(repeat('11', 20), 'hex'), decode(repeat('e4', 20), 'hex'),
    '0x' || repeat('d2', 32),
    decode(repeat('41', 32), 'hex'), decode(repeat('43', 32), 'hex'),
    decode(repeat('42', 32), 'hex'),
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('df', 32), 'hex'),
    1, 'ACTIVE', '2026-01-01 00:00:00+00'
);

CREATE FUNCTION pg_temp.seed_source_finality(
    message_id_ bytea,
    signer_set_hash_ bytea,
    signer_set_version_ bigint
) RETURNS bytea
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    proof_id_ text := 'source-proof-' || encode(message_id_, 'hex');
    certificate_id_ text := 'source-certificate-' || encode(message_id_, 'hex');
    certificate_hash_ bytea := sha256(
        message_id_ || convert_to('source-certificate-v1', 'UTF8')
    );
BEGIN
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        proof_hash, observed_at
    ) VALUES (
        proof_id_, message_id_, 31337,
        sha256(message_id_ || convert_to('source-transaction-v1', 'UTF8')),
        0, 0, 100, sha256(message_id_ || convert_to('source-block-v1', 'UTF8')),
        sha256(message_id_ || convert_to('source-receipts-v1', 'UTF8')),
        sha256(message_id_ || convert_to('source-inclusion-v1', 'UTF8')),
        decode(repeat('54', 32), 'hex'),
        112, sha256(message_id_ || convert_to('source-head-v1', 'UTF8')), 12,
        decode(repeat('42', 32), 'hex'), decode(repeat('14', 32), 'hex'),
        sha256(message_id_ || convert_to('source-header-v1', 'UTF8')),
        decode('010203', 'hex'),
        sha256(message_id_ || convert_to('source-proof-v1', 'UTF8')),
        '2026-01-01 00:00:10+00'
    )
    ON CONFLICT (proof_id) DO NOTHING;

    INSERT INTO crosschain.finality_certificates (
        certificate_id, message_id, proof_id, signer_set_hash,
        signer_set_version, signer_bitmap, signature_count,
        certificate_hash, certified_at
    ) VALUES (
        certificate_id_, message_id_, proof_id_,
        signer_set_hash_, signer_set_version_, B'110', 2,
        certificate_hash_, '2026-01-01 00:00:10+00'
    )
    ON CONFLICT (certificate_id) DO NOTHING;
    RETURN certificate_hash_;
END;
$function$;

CREATE FUNCTION pg_temp.seed_destination_execution_finality(
    message_id_ bytea,
    transaction_hash_ bytea,
    log_index_ numeric,
    result_hash_ bytea,
    effect_commitment_ bytea,
    executed_at_ timestamptz,
    signer_set_hash_ bytea,
    signer_set_version_ bigint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    proof_id_ text := 'destination-proof-' || encode(message_id_, 'hex');
    certificate_id_ text :=
        'destination-certificate-' || encode(message_id_, 'hex');
BEGIN
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        proof_hash, observed_at
    ) VALUES (
        proof_id_, message_id_, 31338, transaction_hash_,
        0, log_index_, 200,
        sha256(message_id_ || convert_to('destination-block-v1', 'UTF8')),
        sha256(message_id_ || convert_to('destination-receipts-v1', 'UTF8')),
        sha256(message_id_ || convert_to('destination-inclusion-v1', 'UTF8')),
        crosschain.execution_evidence_hash(
            message_id_, 31338, transaction_hash_, log_index_,
            result_hash_, effect_commitment_, executed_at_
        ),
        212, sha256(message_id_ || convert_to('destination-head-v1', 'UTF8')), 12,
        decode(repeat('43', 32), 'hex'), decode(repeat('24', 32), 'hex'),
        sha256(message_id_ || convert_to('destination-header-v1', 'UTF8')),
        decode('040506', 'hex'),
        sha256(message_id_ || convert_to('destination-proof-v1', 'UTF8')),
        executed_at_
    )
    ON CONFLICT (proof_id) DO NOTHING;

    INSERT INTO crosschain.finality_certificates (
        certificate_id, message_id, proof_id, signer_set_hash,
        signer_set_version, signer_bitmap, signature_count,
        certificate_hash, certified_at
    ) VALUES (
        certificate_id_, message_id_, proof_id_,
        signer_set_hash_, signer_set_version_, B'110', 2,
        sha256(message_id_ || convert_to('destination-certificate-v1', 'UTF8')),
        executed_at_
    )
    ON CONFLICT (certificate_id) DO NOTHING;
END;
$function$;

CREATE FUNCTION pg_temp.seed_evm_destination_finality(
    message_id_ bytea,
    transaction_hash_ bytea,
    log_index_ numeric,
    event_hash_ bytea,
    observed_at_ timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    proof_id_ text := 'evm-destination-proof-' || encode(message_id_, 'hex');
    certificate_id_ text :=
        'evm-destination-certificate-' || encode(message_id_, 'hex');
BEGIN
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        proof_hash, observed_at, raw_evidence_object_hash, proof_abi
    ) VALUES (
        proof_id_, message_id_, 31338, transaction_hash_,
        0, log_index_, 300,
        sha256(message_id_ || convert_to('evm-destination-block-v1', 'UTF8')),
        sha256(message_id_ || convert_to('evm-destination-receipts-v1', 'UTF8')),
        sha256(message_id_ || convert_to('evm-destination-inclusion-v1', 'UTF8')),
        event_hash_, 312,
        sha256(message_id_ || convert_to('evm-destination-head-v1', 'UTF8')),
        12, decode(repeat('43', 32), 'hex'), decode(repeat('24', 32), 'hex'),
        sha256(message_id_ || convert_to('evm-destination-header-v1', 'UTF8')),
        decode(repeat('04', 64), 'hex'),
        sha256(message_id_ || convert_to('evm-destination-proof-v1', 'UTF8')),
        observed_at_,
        sha256(message_id_ || convert_to('evm-raw-evidence-v1', 'UTF8')),
        convert_to('evm-proof-abi-v1', 'UTF8')
    );

    INSERT INTO crosschain.finality_certificates (
        certificate_id, message_id, proof_id, signer_set_hash,
        signer_set_version, signer_bitmap, signature_count,
        certificate_hash, certified_at, certificate_abi, signatures
    ) VALUES (
        certificate_id_, message_id_, proof_id_,
        decode(repeat('60', 32), 'hex'), 1, B'110', 2,
        sha256(message_id_ || convert_to('evm-destination-certificate-v1', 'UTF8')),
        observed_at_, convert_to('evm-certificate-abi-v1', 'UTF8'),
        ARRAY[
            decode(repeat('05', 65), 'hex'),
            decode(repeat('06', 65), 'hex')
        ]
    );
END;
$function$;

CREATE FUNCTION pg_temp.seed_acknowledgement(
    message_id_ bytea,
    execution_result_hash_ bytea,
    acknowledged_at_ timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    expected_event_hash bytea;
    diagnostic jsonb;
BEGIN
    SELECT crosschain.execution_evidence_hash(
        execution.message_id, execution.destination_chain_id,
        execution.transaction_hash, execution.log_index,
        execution.result_hash, execution.effect_commitment,
        execution.executed_at
    ) INTO expected_event_hash
    FROM crosschain.execution_results AS execution
    WHERE execution.message_id = message_id_;
    IF NOT crosschain.has_trusted_chain_evidence(
        message_id_,
        'destination-proof-' || encode(message_id_, 'hex'),
        'destination-certificate-' || encode(message_id_, 'hex'),
        expected_event_hash,
        'DESTINATION'
    ) THEN
        SELECT jsonb_build_object(
            'certificate_after_proof', certificate.certified_at >= proof.observed_at,
            'certificate_after_valid_from',
                certificate.certified_at >= signer_set.valid_from,
            'certificate_before_valid_until',
                certificate.certified_at <= signer_set.valid_until,
            'chain_coordinator', chain_version.coordinator = message.destination_coordinator,
            'chain_observer',
                chain_version.observer_authority_hash = proof.observer_authority_hash,
            'chain_status', chain_version.status,
            'event_hash', proof.event_hash = expected_event_hash,
            'policy', proof.finality_policy_hash = message.destination_finality_policy_hash,
            'proof_chain', proof.chain_id = message.destination_chain_id,
            'signature_count', certificate.signature_count,
            'signer_hash', signer_set.signer_set_hash = route.destination_signer_set_hash,
            'signer_status', signer_set.status,
            'signer_version', signer_set.version = route.destination_signer_set_version,
            'threshold', signer_set.threshold
        ) INTO diagnostic
        FROM crosschain.messages AS message
        JOIN crosschain.route_versions AS route
          ON route.route_policy_hash = message.route_policy_hash
        JOIN crosschain.source_proofs AS proof
          ON proof.proof_id = 'destination-proof-' || encode(message_id_, 'hex')
        JOIN crosschain.finality_certificates AS certificate
          ON certificate.certificate_id =
             'destination-certificate-' || encode(message_id_, 'hex')
        JOIN crosschain.signer_sets AS signer_set
          ON signer_set.signer_set_hash = certificate.signer_set_hash
         AND signer_set.version = certificate.signer_set_version
        JOIN crosschain.chain_versions AS chain_version
          ON chain_version.chain_id = proof.chain_id
        WHERE message.message_id = message_id_;
        RAISE EXCEPTION 'fixture destination evidence mismatch: %', diagnostic;
    END IF;
    PERFORM crosschain.record_acknowledgement(
        message_id_,
        execution_result_hash_,
        'destination-proof-' || encode(message_id_, 'hex'),
        'destination-certificate-' || encode(message_id_, 'hex'),
        acknowledged_at_
    );
END;
$function$;

CREATE FUNCTION pg_temp.finalize_message(
    message_id_ bytea,
    action_type_ integer,
    source_nonce_ numeric,
    transaction_hash_ bytea,
    log_index_ numeric,
    projection_ jsonb,
    occurred_ timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    evidence bytea := decode(repeat('55', 32), 'hex');
    result_hash bytea := decode(repeat('57', 32), 'hex');
    effect_commitment bytea := CASE
        WHEN projection_ IS NULL THEN decode(repeat('58', 32), 'hex')
        ELSE crosschain.action_projection_hash(
            action_type_::smallint,
            projection_
        )
    END;
    source_certificate_hash bytea;
BEGIN
    PERFORM crosschain.record_message(
        message_id_, 1, decode(repeat('51', 32), 'hex'),
        31337, decode(repeat('11', 20), 'hex'), decode(repeat('31', 20), 'hex'),
        31338, decode(repeat('21', 20), 'hex'), decode(repeat('32', 20), 'hex'),
        decode(repeat('52', 32), 'hex'), source_nonce_,
        decode(repeat('53', 32), 'hex'), action_type_::smallint,
        decode(repeat('54', 32), 'hex'),
        '2026-01-01 00:00:00+00', '2026-01-02 00:00:00+00',
        decode(repeat('44', 32), 'hex'), decode(repeat('41', 32), 'hex'),
        decode(repeat('42', 32), 'hex'), decode(repeat('43', 32), 'hex'),
        decode(repeat('56', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        decode(repeat('00', 32), 'hex'), message_id_, occurred_
    );
    PERFORM crosschain.transition_message(
        message_id_, 1, 'CREATED', 'SOURCE_FINALIZING', NULL, evidence, occurred_
    );
    source_certificate_hash := pg_temp.seed_source_finality(
        message_id_, decode(repeat('60', 32), 'hex'), 1
    );
    PERFORM crosschain.transition_message(
        message_id_, 2, 'SOURCE_FINALIZING', 'SOURCE_FINAL', NULL,
        source_certificate_hash, occurred_
    );
    PERFORM crosschain.transition_message(
        message_id_, 3, 'SOURCE_FINAL', 'SENT', NULL, evidence, occurred_
    );
    PERFORM crosschain.transition_message(
        message_id_, 4, 'SENT', 'RELAYED', NULL, evidence, occurred_
    );
    PERFORM crosschain.transition_message(
        message_id_, 5, 'RELAYED', 'VERIFIED', NULL,
        source_certificate_hash, occurred_
    );
    PERFORM pg_temp.seed_destination_execution_finality(
        message_id_, transaction_hash_, log_index_,
        result_hash, effect_commitment, occurred_,
        decode(repeat('60', 32), 'hex'), 1
    );
    BEGIN
        PERFORM crosschain.record_execution(
            message_id_, 31338, transaction_hash_, log_index_,
            decode(repeat('ff', 32), 'hex'), effect_commitment, occurred_
        );
        RAISE EXCEPTION 'trusted proof accepted altered execution evidence';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'trusted proof accepted altered execution evidence' THEN
            RAISE;
        END IF;
    END;
    PERFORM crosschain.record_execution(
        message_id_, 31338, transaction_hash_, log_index_,
        result_hash, effect_commitment, occurred_
    );
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.execution_results
        WHERE message_id = message_id_
          AND destination_proof_id =
              'destination-proof-' || encode(message_id_, 'hex')
          AND certificate_id =
              'destination-certificate-' || encode(message_id_, 'hex')
    ) THEN
        RAISE EXCEPTION 'execution did not retain exact destination finality';
    END IF;
    PERFORM crosschain.transition_message(
        message_id_, 6, 'VERIFIED', 'EXECUTED', NULL, result_hash, occurred_
    );
    PERFORM crosschain.transition_message(
        message_id_, 7, 'EXECUTED', 'ACK_PENDING', NULL, evidence, occurred_
    );
    IF NOT EXISTS (
        SELECT 1 FROM crosschain.acknowledgements
        WHERE message_id = message_id_
    ) THEN
        BEGIN
            PERFORM crosschain.transition_message(
                message_id_, 8, 'ACK_PENDING', 'ACKNOWLEDGED',
                NULL, result_hash, occurred_
            );
            RAISE EXCEPTION 'runtime fabricated ACKNOWLEDGED';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM = 'runtime fabricated ACKNOWLEDGED' THEN
                RAISE;
            END IF;
        END;
    END IF;
    PERFORM pg_temp.seed_acknowledgement(message_id_, result_hash, occurred_);
    PERFORM crosschain.transition_message(
        message_id_, 8, 'ACK_PENDING', 'ACKNOWLEDGED', NULL, result_hash, occurred_
    );
    IF projection_ IS NOT NULL THEN
        PERFORM crosschain.record_action_projection(
            message_id_,
            projection_,
            occurred_
        );
    END IF;
END;
$function$;

-- A bounded action-12/action-14 authority fixture. It inserts the same
-- immutable terminal facts that the isolated runtime/observer/finality import
-- path verifies, while allowing this migration test to focus on the
-- cancellation SECURITY DEFINER boundary and its accounting transaction.
CREATE FUNCTION pg_temp.seed_cancellation_authority(
    message_id_ bytea,
    action_type_ integer,
    source_nonce_ numeric,
    route_policy_hash_ bytea,
    causation_message_id_ bytea,
    projection_ jsonb,
    source_transaction_hash_ bytea,
    source_log_index_ numeric,
    source_raw_evidence_hash_ bytea,
    destination_transaction_hash_ bytea,
    destination_log_index_ numeric,
    destination_result_hash_ bytea,
    occurred_at_ timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    route crosschain.route_versions;
    projection_hash_ bytea := crosschain.action_projection_hash(
        action_type_::smallint,
        projection_
    );
    source_proof_id_ text :=
        'cancellation-source-' || encode(message_id_, 'hex');
    destination_proof_id_ text :=
        'cancellation-destination-' || encode(message_id_, 'hex');
    destination_certificate_id_ text :=
        'cancellation-certificate-' || encode(message_id_, 'hex');
BEGIN
    SELECT * INTO route
    FROM crosschain.route_versions
    WHERE route_policy_hash = route_policy_hash_;
    IF route.route_id IS NULL THEN
        RAISE EXCEPTION 'cancellation fixture route is missing';
    END IF;
    INSERT INTO crosschain.messages (
        message_id, schema_version, protocol_id,
        source_chain_id, source_coordinator, source_component,
        destination_chain_id, destination_coordinator,
        destination_component, lane_id, source_nonce, aggregate_id,
        action_type, payload_hash, message_created_at, expires_at,
        route_policy_hash, adapter_set_policy_hash,
        source_finality_policy_hash, destination_finality_policy_hash,
        correlation_id, causation_message_id, superseded_message_id,
        serialized_envelope, state, state_version, updated_at
    ) VALUES (
        message_id_, 1, decode(repeat('51', 32), 'hex'),
        route.source_chain_id, route.source_coordinator,
        route.source_component, route.destination_chain_id,
        route.destination_coordinator, route.destination_component,
        sha256(message_id_ || convert_to('cancellation-lane', 'UTF8')),
        source_nonce_,
        sha256(convert_to(projection_ ->> 'loan_id', 'UTF8')),
        action_type_::smallint,
        sha256(message_id_ || convert_to('cancellation-payload', 'UTF8')),
        occurred_at_ - interval '1 minute',
        occurred_at_ + interval '1 day',
        route_policy_hash_, route.adapter_set_policy_hash,
        route.source_finality_policy_hash,
        route.destination_finality_policy_hash,
        sha256(message_id_ || convert_to('cancellation-correlation', 'UTF8')),
        causation_message_id_, decode(repeat('00', 32), 'hex'),
        message_id_, 'ACKNOWLEDGED', 9, occurred_at_
    );
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        raw_evidence_object_hash, proof_abi, proof_hash, observed_at
    ) VALUES (
        source_proof_id_, message_id_, route.source_chain_id,
        source_transaction_hash_, 0, source_log_index_, 400,
        sha256(message_id_ || convert_to('cancellation-source-block', 'UTF8')),
        sha256(message_id_ || convert_to('cancellation-source-root', 'UTF8')),
        sha256(message_id_ || convert_to('cancellation-source-path', 'UTF8')),
        sha256(message_id_ || convert_to('cancellation-source-event', 'UTF8')),
        412,
        sha256(message_id_ || convert_to('cancellation-source-head', 'UTF8')),
        12, route.source_finality_policy_hash,
        CASE
            WHEN route.source_chain_id = 31337
                THEN decode(repeat('14', 32), 'hex')
            ELSE decode(repeat('24', 32), 'hex')
        END,
        sha256(message_id_ || convert_to('cancellation-source-header', 'UTF8')),
        decode('010203', 'hex'), source_raw_evidence_hash_,
        convert_to('cancellation-source-proof-v1', 'UTF8'),
        sha256(message_id_ || convert_to('cancellation-source-proof', 'UTF8')),
        occurred_at_
    );
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        raw_evidence_object_hash, proof_abi, proof_hash, observed_at
    ) VALUES (
        destination_proof_id_, message_id_, route.destination_chain_id,
        destination_transaction_hash_, 0, destination_log_index_, 500,
        sha256(message_id_ || convert_to('cancellation-destination-block', 'UTF8')),
        sha256(message_id_ || convert_to('cancellation-destination-root', 'UTF8')),
        sha256(message_id_ || convert_to('cancellation-destination-path', 'UTF8')),
        sha256(message_id_ || convert_to('cancellation-destination-event', 'UTF8')),
        512,
        sha256(message_id_ || convert_to('cancellation-destination-head', 'UTF8')),
        12, route.destination_finality_policy_hash,
        CASE
            WHEN route.destination_chain_id = 31337
                THEN decode(repeat('14', 32), 'hex')
            ELSE decode(repeat('24', 32), 'hex')
        END,
        sha256(message_id_ || convert_to('cancellation-destination-header', 'UTF8')),
        decode('040506', 'hex'),
        sha256(message_id_ || convert_to('cancellation-destination-raw', 'UTF8')),
        convert_to('cancellation-destination-proof-v1', 'UTF8'),
        sha256(message_id_ || convert_to('cancellation-destination-proof', 'UTF8')),
        occurred_at_
    );
    INSERT INTO crosschain.finality_certificates (
        certificate_id, message_id, proof_id, signer_set_hash,
        signer_set_version, signer_bitmap, signature_count,
        certificate_hash, certified_at
    ) VALUES (
        destination_certificate_id_, message_id_, destination_proof_id_,
        route.destination_signer_set_hash,
        route.destination_signer_set_version, B'110', 2,
        sha256(message_id_ || convert_to('cancellation-certificate', 'UTF8')),
        occurred_at_
    );
    INSERT INTO crosschain.execution_results (
        message_id, destination_chain_id, transaction_hash, log_index,
        result_hash, effect_commitment, action_projection,
        destination_proof_id, certificate_id, executed_at
    ) VALUES (
        message_id_, route.destination_chain_id,
        destination_transaction_hash_, destination_log_index_,
        destination_result_hash_, projection_hash_, projection_,
        destination_proof_id_, destination_certificate_id_, occurred_at_
    );
    INSERT INTO crosschain.acknowledgements (
        message_id, execution_result_hash, destination_proof_id,
        certificate_id, acknowledged_at
    ) VALUES (
        message_id_, destination_result_hash_, destination_proof_id_,
        destination_certificate_id_, occurred_at_
    );
    INSERT INTO crosschain.action_projections (
        message_id, action_type, projection, projection_hash,
        execution_result_hash, destination_proof_id, certificate_id,
        projected_at
    ) VALUES (
        message_id_, action_type_::smallint, projection_, projection_hash_,
        destination_result_hash_, destination_proof_id_,
        destination_certificate_id_, occurred_at_
    );
END;
$function$;

CREATE FUNCTION pg_temp.seed_tombstoned_disbursement(
    message_id_ bytea,
    loan_id_ text,
    source_nonce_ numeric,
    tombstone_hash_ bytea,
    occurred_at_ timestamptz,
    route_version_ bigint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
DECLARE
    route crosschain.route_versions;
    source_proof_id_ text :=
        'cancel-disbursement-source-' || encode(message_id_, 'hex');
    source_certificate_id_ text :=
        'cancel-disbursement-source-certificate-' || encode(message_id_, 'hex');
    destination_proof_id_ text :=
        'cancel-disbursement-destination-' || encode(message_id_, 'hex');
    destination_certificate_id_ text :=
        'cancel-disbursement-destination-certificate-' ||
        encode(message_id_, 'hex');
    recovery_id_ bytea := sha256(
        message_id_ || convert_to('cancel-disbursement-recovery', 'UTF8')
    );
BEGIN
    SELECT * INTO route
    FROM crosschain.route_versions
    WHERE route_id = 'phase8-disbursement' AND version = route_version_;
    INSERT INTO crosschain.messages (
        message_id, schema_version, protocol_id,
        source_chain_id, source_coordinator, source_component,
        destination_chain_id, destination_coordinator,
        destination_component, lane_id, source_nonce, aggregate_id,
        action_type, payload_hash, message_created_at, expires_at,
        route_policy_hash, adapter_set_policy_hash,
        source_finality_policy_hash, destination_finality_policy_hash,
        correlation_id, causation_message_id, superseded_message_id,
        serialized_envelope, state, state_version, updated_at
    ) VALUES (
        message_id_, 1, decode(repeat('51', 32), 'hex'),
        route.source_chain_id, route.source_coordinator,
        route.source_component, route.destination_chain_id,
        route.destination_coordinator, route.destination_component,
        sha256(message_id_ || convert_to('disbursement-lane', 'UTF8')),
        source_nonce_, sha256(convert_to(loan_id_, 'UTF8')),
        6, sha256(message_id_ || convert_to('disbursement-payload', 'UTF8')),
        occurred_at_ - interval '1 day', occurred_at_,
        route.route_policy_hash, route.adapter_set_policy_hash,
        route.source_finality_policy_hash,
        route.destination_finality_policy_hash,
        sha256(message_id_ || convert_to('disbursement-correlation', 'UTF8')),
        decode(repeat('00', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        message_id_, 'DESTINATION_TOMBSTONED', 4, occurred_at_
    );
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        raw_evidence_object_hash, proof_abi, proof_hash, observed_at
    ) VALUES (
        source_proof_id_, message_id_, route.source_chain_id,
        sha256(message_id_ || convert_to('disbursement-source-tx', 'UTF8')),
        0, 0, 600,
        sha256(message_id_ || convert_to('disbursement-source-block', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-source-root', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-source-path', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-source-event', 'UTF8')),
        612,
        sha256(message_id_ || convert_to('disbursement-source-head', 'UTF8')),
        12, route.source_finality_policy_hash,
        decode(repeat('14', 32), 'hex'),
        sha256(message_id_ || convert_to('disbursement-source-header', 'UTF8')),
        decode('010203', 'hex'),
        sha256(message_id_ || convert_to('disbursement-source-raw', 'UTF8')),
        convert_to('disbursement-source-proof-v1', 'UTF8'),
        sha256(message_id_ || convert_to('disbursement-source-proof', 'UTF8')),
        occurred_at_ - interval '1 hour'
    );
    INSERT INTO crosschain.finality_certificates (
        certificate_id, message_id, proof_id, signer_set_hash,
        signer_set_version, signer_bitmap, signature_count,
        certificate_hash, certified_at
    ) VALUES (
        source_certificate_id_, message_id_, source_proof_id_,
        route.source_signer_set_hash, route.source_signer_set_version,
        B'110', 2,
        sha256(message_id_ || convert_to('disbursement-source-certificate', 'UTF8')),
        occurred_at_ - interval '1 hour'
    );
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        raw_evidence_object_hash, proof_abi, proof_hash, observed_at
    ) VALUES (
        destination_proof_id_, message_id_, route.destination_chain_id,
        sha256(message_id_ || convert_to('disbursement-tombstone-tx', 'UTF8')),
        0, 1, 700,
        sha256(message_id_ || convert_to('disbursement-tombstone-block', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-tombstone-root', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-tombstone-path', 'UTF8')),
        tombstone_hash_, 712,
        sha256(message_id_ || convert_to('disbursement-tombstone-head', 'UTF8')),
        12, route.destination_finality_policy_hash,
        decode(repeat('24', 32), 'hex'),
        sha256(message_id_ || convert_to('disbursement-tombstone-header', 'UTF8')),
        decode('040506', 'hex'),
        sha256(message_id_ || convert_to('disbursement-tombstone-raw', 'UTF8')),
        convert_to('disbursement-tombstone-proof-v1', 'UTF8'),
        sha256(message_id_ || convert_to('disbursement-tombstone-proof', 'UTF8')),
        occurred_at_
    );
    INSERT INTO crosschain.finality_certificates (
        certificate_id, message_id, proof_id, signer_set_hash,
        signer_set_version, signer_bitmap, signature_count,
        certificate_hash, certified_at
    ) VALUES (
        destination_certificate_id_, message_id_, destination_proof_id_,
        route.destination_signer_set_hash,
        route.destination_signer_set_version, B'110', 2,
        sha256(
            message_id_ || convert_to('disbursement-tombstone-certificate', 'UTF8')
        ),
        occurred_at_
    );
    INSERT INTO crosschain.recovery_requests (
        recovery_id, original_message_id, protocol_id,
        source_chain_id, source_coordinator,
        destination_chain_id, destination_coordinator,
        immutable_envelope_hash, route_policy_hash,
        asset_amount_commitment, source_state_commitment,
        destination_state_commitment, compensation_payload_hash,
        message_expires_at, recovery_nonce, reason_code, action,
        authorizer_set_hash, authorizer_set_version, request_digest,
        signer_bitmap, signature_count, authorization_evidence_hash, verified_at
    ) VALUES (
        recovery_id_, message_id_, decode(repeat('51', 32), 'hex'),
        route.source_chain_id, route.source_coordinator,
        route.destination_chain_id, route.destination_coordinator,
        sha256(message_id_ || convert_to('disbursement-envelope', 'UTF8')),
        route.route_policy_hash,
        sha256(message_id_ || convert_to('disbursement-amount', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-source-state', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-destination-state', 'UTF8')),
        sha256(message_id_ || convert_to('disbursement-compensation', 'UTF8')),
        1767312000, source_nonce_,
        sha256(message_id_ || convert_to('disbursement-reason', 'UTF8')),
        1, decode(repeat('90', 32), 'hex'), 1,
        sha256(message_id_ || convert_to('disbursement-request-digest', 'UTF8')),
        B'110', 2,
        sha256(message_id_ || convert_to('disbursement-authorization', 'UTF8')),
        occurred_at_
    );
    INSERT INTO crosschain.tombstones (
        original_message_id, recovery_id, tombstone_hash,
        destination_state_commitment, destination_proof_id,
        certificate_id, tombstoned_at
    ) VALUES (
        message_id_, recovery_id_, tombstone_hash_,
        sha256(message_id_ || convert_to('disbursement-destination-state', 'UTF8')),
        destination_proof_id_, destination_certificate_id_, occurred_at_
    );
END;
$function$;

-- Synthetic compatibility fixtures can exercise the legacy function only
-- through this test-owned definer. No Phase 8 runtime role receives EXECUTE.
CREATE FUNCTION pg_temp.record_legacy_test_execution(
    message_id_ bytea,
    destination_chain_id_ numeric,
    transaction_hash_ bytea,
    log_index_ numeric,
    result_hash_ bytea,
    effect_hash_ bytea,
    occurred_ timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, crosschain
AS $function$
BEGIN
    PERFORM crosschain.record_execution(
        message_id_, destination_chain_id_, transaction_hash_, log_index_,
        result_hash_, effect_hash_, occurred_
    );
END;
$function$;

CREATE FUNCTION pg_temp.begin_test_message(
    message_id_ bytea,
    source_nonce_ numeric
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    evidence bytea := decode(repeat('55', 32), 'hex');
    occurred timestamptz := '2026-01-01 00:00:10+00';
BEGIN
    PERFORM crosschain.record_message(
        message_id_, 1, decode(repeat('51', 32), 'hex'),
        31337, decode(repeat('11', 20), 'hex'), decode(repeat('31', 20), 'hex'),
        31338, decode(repeat('21', 20), 'hex'), decode(repeat('32', 20), 'hex'),
        decode(repeat('52', 32), 'hex'), source_nonce_,
        decode(repeat('53', 32), 'hex'), 1::smallint,
        decode(repeat('54', 32), 'hex'),
        '2026-01-01 00:00:00+00', '2026-01-02 00:00:00+00',
        decode(repeat('44', 32), 'hex'), decode(repeat('41', 32), 'hex'),
        decode(repeat('42', 32), 'hex'), decode(repeat('43', 32), 'hex'),
        decode(repeat('56', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        decode(repeat('00', 32), 'hex'), message_id_, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 1, 'CREATED', 'SOURCE_FINALIZING',
        NULL, evidence, occurred
    );
END;
$function$;

SELECT crosschain.activate_bridge_exposure_policy(
    1, 1000000, decode(repeat('61', 32), 'hex'),
    5000, 10000, 10000, 15000, 500, 1500,
    '2026-01-01 00:00:00+00'
);

SET ROLE unified_crosschain_runtime;

DO $test$
DECLARE
    message_id_ bytea := decode(repeat('ed', 32), 'hex');
    transaction_hash_ bytea := decode(repeat('ab', 32), 'hex');
    result_hash_ bytea := decode(repeat('bc', 32), 'hex');
    event_hash_ bytea := decode(repeat('cd', 32), 'hex');
    source_certificate_hash bytea;
    occurred timestamptz := '2026-01-01 00:00:10+00';
    projection jsonb := jsonb_build_object(
        'proof_boundary', 'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT',
        'destination_result_hash', '0x' || encode(result_hash_, 'hex'),
        'evm_acknowledgement_commitment', '0x' || encode(event_hash_, 'hex')
    );
BEGIN
    PERFORM pg_temp.begin_test_message(message_id_, 249);
    source_certificate_hash := pg_temp.seed_source_finality(
        message_id_, decode(repeat('60', 32), 'hex'), 1
    );
    PERFORM crosschain.transition_message(
        message_id_, 2, 'SOURCE_FINALIZING', 'SOURCE_FINAL',
        NULL, source_certificate_hash, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 3, 'SOURCE_FINAL', 'SENT',
        NULL, source_certificate_hash, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 4, 'SENT', 'RELAYED',
        NULL, source_certificate_hash, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 5, 'RELAYED', 'VERIFIED',
        NULL, source_certificate_hash, occurred
    );
    PERFORM pg_temp.seed_evm_destination_finality(
        message_id_, transaction_hash_, 7, event_hash_, occurred
    );

    BEGIN
        PERFORM crosschain.record_evm_execution(
            message_id_, 31338, decode(repeat('aa', 32), 'hex'), 7,
            result_hash_, event_hash_,
            'evm-destination-proof-' || encode(message_id_, 'hex'),
            'evm-destination-certificate-' || encode(message_id_, 'hex'),
            projection, occurred
        );
        RAISE EXCEPTION 'authenticated execution accepted a substituted transaction';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM =
            'authenticated execution accepted a substituted transaction' THEN
            RAISE;
        END IF;
    END;

    BEGIN
        PERFORM crosschain.record_evm_execution(
            message_id_, 31338, transaction_hash_, 8,
            result_hash_, event_hash_,
            'evm-destination-proof-' || encode(message_id_, 'hex'),
            'evm-destination-certificate-' || encode(message_id_, 'hex'),
            projection, occurred
        );
        RAISE EXCEPTION 'authenticated execution accepted a substituted log index';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM =
            'authenticated execution accepted a substituted log index' THEN
            RAISE;
        END IF;
    END;

    PERFORM crosschain.record_evm_execution(
        message_id_, 31338, transaction_hash_, 7,
        result_hash_, event_hash_,
        'evm-destination-proof-' || encode(message_id_, 'hex'),
        'evm-destination-certificate-' || encode(message_id_, 'hex'),
        projection, occurred
    );
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.execution_results
        WHERE execution_results.message_id = message_id_
          AND execution_results.transaction_hash = transaction_hash_
          AND execution_results.log_index = 7
          AND execution_results.action_projection = projection
    ) THEN
        RAISE EXCEPTION 'authenticated execution lost exact receipt identity';
    END IF;
END;
$test$;

DO $test$
DECLARE
    malicious_message bytea := decode(repeat('fa', 32), 'hex');
    wrong_set_message bytea := decode(repeat('fb', 32), 'hex');
    wrong_version_message bytea := decode(repeat('fc', 32), 'hex');
    fabricated bytea := decode(repeat('ff', 32), 'hex');
    trusted_source_certificate bytea;
    wrong_certificate bytea;
    occurred timestamptz := '2026-01-01 00:00:10+00';
BEGIN
    PERFORM pg_temp.begin_test_message(malicious_message, 250);
    BEGIN
        PERFORM crosschain.transition_message(
            malicious_message, 2, 'SOURCE_FINALIZING', 'SOURCE_FINAL',
            NULL, fabricated, occurred
        );
        RAISE EXCEPTION 'runtime fabricated SOURCE_FINAL';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated SOURCE_FINAL' THEN
            RAISE;
        END IF;
    END;

    PERFORM pg_temp.begin_test_message(wrong_set_message, 251);
    wrong_certificate := pg_temp.seed_source_finality(
        wrong_set_message, decode(repeat('70', 32), 'hex'), 1
    );
    BEGIN
        PERFORM crosschain.transition_message(
            wrong_set_message, 2, 'SOURCE_FINALIZING', 'SOURCE_FINAL',
            NULL, wrong_certificate, occurred
        );
        RAISE EXCEPTION 'wrong source signer set was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'wrong source signer set was accepted' THEN
            RAISE;
        END IF;
    END;

    PERFORM pg_temp.begin_test_message(wrong_version_message, 252);
    wrong_certificate := pg_temp.seed_source_finality(
        wrong_version_message, decode(repeat('60', 32), 'hex'), 2
    );
    BEGIN
        PERFORM crosschain.transition_message(
            wrong_version_message, 2, 'SOURCE_FINALIZING', 'SOURCE_FINAL',
            NULL, wrong_certificate, occurred
        );
        RAISE EXCEPTION 'wrong source signer set version was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'wrong source signer set version was accepted' THEN
            RAISE;
        END IF;
    END;

    trusted_source_certificate :=
        pg_temp.seed_source_finality(
            malicious_message, decode(repeat('60', 32), 'hex'), 1
        );
    PERFORM crosschain.transition_message(
        malicious_message, 2, 'SOURCE_FINALIZING', 'SOURCE_FINAL',
        NULL, trusted_source_certificate, occurred
    );
    PERFORM crosschain.transition_message(
        malicious_message, 3, 'SOURCE_FINAL', 'SENT',
        NULL, fabricated, occurred
    );
    PERFORM crosschain.transition_message(
        malicious_message, 4, 'SENT', 'RELAYED',
        NULL, fabricated, occurred
    );
    BEGIN
        PERFORM crosschain.transition_message(
            malicious_message, 5, 'RELAYED', 'VERIFIED',
            NULL, fabricated, occurred
        );
        RAISE EXCEPTION 'runtime fabricated VERIFIED';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated VERIFIED' THEN
            RAISE;
        END IF;
    END;
    PERFORM crosschain.transition_message(
        malicious_message, 5, 'RELAYED', 'VERIFIED',
        NULL, trusted_source_certificate, occurred
    );
    PERFORM pg_temp.seed_destination_execution_finality(
        malicious_message, decode(repeat('ee', 32), 'hex'), 999,
        fabricated, decode(repeat('ef', 32), 'hex'), occurred,
        decode(repeat('70', 32), 'hex'), 1
    );
    BEGIN
        PERFORM crosschain.record_execution(
            malicious_message, 31338, decode(repeat('ee', 32), 'hex'), 999,
            fabricated, decode(repeat('ef', 32), 'hex'), occurred
        );
        RAISE EXCEPTION 'runtime fabricated destination execution';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated destination execution' THEN
            RAISE;
        END IF;
    END;
    IF EXISTS (
        SELECT 1 FROM crosschain.execution_results
        WHERE message_id = malicious_message
    ) THEN
        RAISE EXCEPTION 'malicious execution mutated durable state';
    END IF;
END;
$test$;

SELECT pg_temp.begin_test_message(decode(repeat('f0', 32), 'hex'), 256);
SELECT pg_temp.begin_test_message(decode(repeat('f4', 32), 'hex'), 253);

RESET ROLE;
SET ROLE unified_crosschain_observer;

SELECT crosschain.record_source_proof(
    'observer-proof-f0', decode(repeat('f0', 32), 'hex'), 31337,
    decode(repeat('e8', 32), 'hex'), 0, 89, 100,
    decode(repeat('e2', 32), 'hex'), decode(repeat('e3', 32), 'hex'),
    decode(repeat('e9', 32), 'hex'), decode(repeat('54', 32), 'hex'),
    112, decode(repeat('e5', 32), 'hex'), 12,
    decode(repeat('42', 32), 'hex'), decode(repeat('14', 32), 'hex'),
    decode(repeat('e6', 32), 'hex'), decode('070809', 'hex'),
    decode(repeat('e0', 32), 'hex'), '2026-01-01 00:00:10+00',
    decode(repeat('a1', 32), 'hex'), decode('01020304', 'hex')
);
SELECT crosschain.record_source_proof(
    'observer-proof-f4', decode(repeat('f4', 32), 'hex'), 31337,
    decode(repeat('e1', 32), 'hex'), 0, 90, 100,
    decode(repeat('e2', 32), 'hex'), decode(repeat('e3', 32), 'hex'),
    decode(repeat('e4', 32), 'hex'), decode(repeat('54', 32), 'hex'),
    112, decode(repeat('e5', 32), 'hex'), 12,
    decode(repeat('42', 32), 'hex'), decode(repeat('14', 32), 'hex'),
    decode(repeat('e6', 32), 'hex'), decode('010203', 'hex'),
    decode(repeat('e7', 32), 'hex'), '2026-01-01 00:00:10+00'
);
SELECT crosschain.record_source_proof(
    'observer-proof-f4', decode(repeat('f4', 32), 'hex'), 31337,
    decode(repeat('e1', 32), 'hex'), 0, 90, 100,
    decode(repeat('e2', 32), 'hex'), decode(repeat('e3', 32), 'hex'),
    decode(repeat('e4', 32), 'hex'), decode(repeat('54', 32), 'hex'),
    112, decode(repeat('e5', 32), 'hex'), 12,
    decode(repeat('42', 32), 'hex'), decode(repeat('14', 32), 'hex'),
    decode(repeat('e6', 32), 'hex'), decode('010203', 'hex'),
    decode(repeat('e7', 32), 'hex'), '2026-01-01 00:00:10+00'
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_source_proof(
            'observer-proof-f4', decode(repeat('f4', 32), 'hex'), 31337,
            decode(repeat('e1', 32), 'hex'), 0, 90, 100,
            decode(repeat('e2', 32), 'hex'), decode(repeat('e3', 32), 'hex'),
            decode(repeat('e4', 32), 'hex'), decode(repeat('ef', 32), 'hex'),
            112, decode(repeat('e5', 32), 'hex'), 12,
            decode(repeat('42', 32), 'hex'), decode(repeat('14', 32), 'hex'),
            decode(repeat('e6', 32), 'hex'), decode('010203', 'hex'),
            decode(repeat('e7', 32), 'hex'), '2026-01-01 00:00:10+00'
        );
        RAISE EXCEPTION 'conflicting observer proof replay was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'conflicting observer proof replay was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.load_source_proof('observer-proof-f0')
        WHERE proof_id = 'observer-proof-f0'
          AND raw_evidence_object_hash = decode(repeat('a1', 32), 'hex')
          AND proof_abi = decode('01020304', 'hex')
    ) THEN
        RAISE EXCEPTION 'exact source proof evidence was not retained';
    END IF;
    BEGIN
        PERFORM crosschain.record_source_proof(
            proof.proof_id, proof.message_id, proof.chain_id,
            proof.transaction_hash, proof.transaction_index, proof.log_index,
            proof.block_number, proof.block_hash, proof.receipts_root,
            proof.inclusion_proof_hash, proof.event_hash,
            proof.finality_head_number, proof.finality_head_hash,
            proof.confirmation_depth, proof.finality_policy_hash,
            proof.observer_authority_hash,
            proof.observer_signed_header_commitment, proof.observer_signature,
            proof.proof_hash, proof.observed_at,
            decode(repeat('a2', 32), 'hex'), proof.proof_abi
        )
        FROM crosschain.load_source_proof('observer-proof-f0') AS proof;
        RAISE EXCEPTION 'raw evidence hash substitution was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'raw evidence hash substitution was accepted' THEN
            RAISE;
        END IF;
    END;
    BEGIN
        PERFORM crosschain.record_source_proof(
            proof.proof_id, proof.message_id, proof.chain_id,
            proof.transaction_hash, proof.transaction_index, proof.log_index,
            proof.block_number, proof.block_hash, proof.receipts_root,
            proof.inclusion_proof_hash, proof.event_hash,
            proof.finality_head_number, proof.finality_head_hash,
            proof.confirmation_depth, proof.finality_policy_hash,
            proof.observer_authority_hash,
            proof.observer_signed_header_commitment, proof.observer_signature,
            proof.proof_hash, proof.observed_at,
            proof.raw_evidence_object_hash, decode('05060708', 'hex')
        )
        FROM crosschain.load_source_proof('observer-proof-f0') AS proof;
        RAISE EXCEPTION 'proof ABI substitution was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'proof ABI substitution was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;
SET ROLE unified_crosschain_finality_attester;

SELECT crosschain.record_finality_certificate(
    'observer-certificate-f0', decode(repeat('f0', 32), 'hex'),
    'observer-proof-f0', decode(repeat('60', 32), 'hex'), 1,
    B'110', 2, decode(repeat('e0', 32), 'hex'),
    '2026-01-01 00:00:10+00', decode('aabbccdd', 'hex'),
    ARRAY[
        decode(repeat('11', 65), 'hex'),
        decode(repeat('22', 65), 'hex')
    ]
);
SELECT crosschain.record_finality_certificate(
    'observer-certificate-f4', decode(repeat('f4', 32), 'hex'),
    'observer-proof-f4', decode(repeat('60', 32), 'hex'), 1,
    B'110', 2, decode(repeat('ea', 32), 'hex'),
    '2026-01-01 00:00:10+00'
);
SELECT crosschain.record_finality_certificate(
    'observer-certificate-f4', decode(repeat('f4', 32), 'hex'),
    'observer-proof-f4', decode(repeat('60', 32), 'hex'), 1,
    B'110', 2, decode(repeat('ea', 32), 'hex'),
    '2026-01-01 00:00:10+00'
);
SELECT crosschain.record_finality_certificate(
    'alternate-certificate-f4', decode(repeat('f4', 32), 'hex'),
    'observer-proof-f4', decode(repeat('60', 32), 'hex'), 1,
    B'101', 2, decode(repeat('bc', 32), 'hex'),
    '2026-01-01 00:00:10+00'
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_finality_certificate(
            'observer-certificate-f4', decode(repeat('f4', 32), 'hex'),
            'observer-proof-f4', decode(repeat('60', 32), 'hex'), 1,
            B'110', 2, decode(repeat('eb', 32), 'hex'),
            '2026-01-01 00:00:10+00'
        );
        RAISE EXCEPTION 'conflicting observer certificate replay was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'conflicting observer certificate replay was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.load_finality_certificate('observer-certificate-f0')
        WHERE certificate_id = 'observer-certificate-f0'
          AND certificate_abi = decode('aabbccdd', 'hex')
          AND signatures = ARRAY[
              decode(repeat('11', 65), 'hex'),
              decode(repeat('22', 65), 'hex')
          ]
    ) THEN
        RAISE EXCEPTION 'exact certificate evidence was not retained';
    END IF;
    BEGIN
        PERFORM crosschain.record_finality_certificate(
            certificate.certificate_id, certificate.message_id,
            certificate.proof_id, certificate.signer_set_hash,
            certificate.signer_set_version, certificate.signer_bitmap,
            certificate.signature_count, certificate.certificate_hash,
            certificate.certified_at, decode('eeff', 'hex'),
            certificate.signatures
        )
        FROM crosschain.load_finality_certificate(
            'observer-certificate-f0'
        ) AS certificate;
        RAISE EXCEPTION 'certificate ABI substitution was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'certificate ABI substitution was accepted' THEN
            RAISE;
        END IF;
    END;
    BEGIN
        PERFORM crosschain.record_finality_certificate(
            certificate.certificate_id, certificate.message_id,
            certificate.proof_id, certificate.signer_set_hash,
            certificate.signer_set_version, certificate.signer_bitmap,
            certificate.signature_count, certificate.certificate_hash,
            certificate.certified_at, certificate.certificate_abi,
            ARRAY[
                decode(repeat('11', 65), 'hex'),
                decode(repeat('33', 65), 'hex')
            ]
        )
        FROM crosschain.load_finality_certificate(
            'observer-certificate-f0'
        ) AS certificate;
        RAISE EXCEPTION 'certificate signature substitution was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'certificate signature substitution was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;

SELECT crosschain.register_chain_version(
    31337, 2, decode(repeat('11', 20), 'hex'), decode(repeat('12', 20), 'hex'),
    decode(repeat('16', 32), 'hex'), decode(repeat('15', 32), 'hex'),
    2, 'ACTIVE', '2026-01-01 00:00:01+00'
);
SELECT crosschain.register_route_version(
    'route-phase8', 2,
    31337, 2, decode(repeat('11', 20), 'hex'), decode(repeat('31', 20), 'hex'),
    31338, 1, decode(repeat('21', 20), 'hex'), decode(repeat('32', 20), 'hex'),
    'PHASE8_ALL',
    decode(repeat('41', 32), 'hex'), decode(repeat('47', 32), 'hex'),
    decode(repeat('43', 32), 'hex'),
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('45', 32), 'hex'),
    2, 'ACTIVE', '2026-01-01 00:00:01+00'
);
SELECT crosschain.register_route_version(
    'phase8-disbursement', 2,
    31337, 2, decode(repeat('11', 20), 'hex'),
    decode(repeat('e5', 20), 'hex'),
    31338, 1, decode(repeat('21', 20), 'hex'),
    decode(repeat('e6', 20), 'hex'),
    '0x' || repeat('d3', 32),
    decode(repeat('41', 32), 'hex'), decode(repeat('47', 32), 'hex'),
    decode(repeat('43', 32), 'hex'),
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('60', 32), 'hex'), 1,
    decode(repeat('dc', 32), 'hex'),
    2, 'ACTIVE', '2026-01-01 00:00:01+00'
);

SET ROLE unified_crosschain_runtime;

DO $test$
DECLARE
    mixed_block_certificate bytea;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM crosschain.messages
        WHERE message_id = decode(repeat('f4', 32), 'hex')
          AND state = 'SOURCE_FINALIZING'
    ) THEN
        RAISE EXCEPTION 'observer ingest mutated message state';
    END IF;
    PERFORM crosschain.transition_message(
        decode(repeat('f0', 32), 'hex'), 2,
        'SOURCE_FINALIZING', 'SOURCE_FINAL', NULL,
        decode(repeat('e0', 32), 'hex'), '2026-01-01 00:00:10+00'
    );
    PERFORM crosschain.transition_message(
        decode(repeat('f4', 32), 'hex'), 2,
        'SOURCE_FINALIZING', 'SOURCE_FINAL', NULL,
        decode(repeat('ea', 32), 'hex'), '2026-01-01 00:00:10+00'
    );
    PERFORM pg_temp.begin_test_message(decode(repeat('f1', 32), 'hex'), 257);
    mixed_block_certificate := pg_temp.seed_source_finality(
        decode(repeat('f1', 32), 'hex'),
        decode(repeat('60', 32), 'hex'),
        1
    );
    PERFORM crosschain.transition_message(
        decode(repeat('f1', 32), 'hex'), 2,
        'SOURCE_FINALIZING', 'SOURCE_FINAL', NULL,
        mixed_block_certificate, '2026-01-01 00:00:10+00'
    );
    PERFORM crosschain.record_message(
        decode(repeat('f2', 32), 'hex'),
        1, decode(repeat('51', 32), 'hex'),
        31337, decode(repeat('11', 20), 'hex'), decode(repeat('31', 20), 'hex'),
        31338, decode(repeat('21', 20), 'hex'), decode(repeat('32', 20), 'hex'),
        decode(repeat('52', 32), 'hex'), 258,
        decode(repeat('53', 32), 'hex'), 1::smallint,
        decode(repeat('54', 32), 'hex'),
        '2026-01-01 00:00:00+00', '2026-01-02 00:00:00+00',
        decode(repeat('45', 32), 'hex'), decode(repeat('41', 32), 'hex'),
        decode(repeat('47', 32), 'hex'), decode(repeat('43', 32), 'hex'),
        decode(repeat('56', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        decode(repeat('00', 32), 'hex'), decode(repeat('f2', 32), 'hex'),
        '2026-01-01 00:00:10+00'
    );
    PERFORM crosschain.transition_message(
        decode(repeat('f2', 32), 'hex'), 1,
        'CREATED', 'SOURCE_FINALIZING', NULL,
        decode(repeat('55', 32), 'hex'), '2026-01-01 00:00:10+00'
    );
END;
$test$;

RESET ROLE;

SET ROLE unified_crosschain_observer;

SELECT crosschain.record_source_proof(
    'observer-proof-f2', decode(repeat('f2', 32), 'hex'), 31337,
    decode(repeat('d1', 32), 'hex'), 0, 87, 100,
    decode(repeat('e2', 32), 'hex'), decode(repeat('e3', 32), 'hex'),
    decode(repeat('d2', 32), 'hex'), decode(repeat('54', 32), 'hex'),
    112, decode(repeat('e5', 32), 'hex'), 12,
    decode(repeat('47', 32), 'hex'), decode(repeat('15', 32), 'hex'),
    decode(repeat('d3', 32), 'hex'), decode('0a0b0c', 'hex'),
    decode(repeat('d4', 32), 'hex'), '2026-01-01 00:00:10+00'
);

RESET ROLE;
SET ROLE unified_crosschain_finality_attester;

SELECT crosschain.record_finality_certificate(
    'observer-certificate-f2', decode(repeat('f2', 32), 'hex'),
    'observer-proof-f2', decode(repeat('60', 32), 'hex'), 1,
    B'110', 2, decode(repeat('d5', 32), 'hex'),
    '2026-01-01 00:00:10+00'
);

RESET ROLE;

SET ROLE unified_crosschain_runtime;

DO $test$
BEGIN
    PERFORM crosschain.transition_message(
        decode(repeat('f2', 32), 'hex'), 2,
        'SOURCE_FINALIZING', 'SOURCE_FINAL', NULL,
        decode(repeat('d5', 32), 'hex'), '2026-01-01 00:00:10+00'
    );
    BEGIN
        PERFORM crosschain.transition_message(
            decode(repeat('f4', 32), 'hex'), 3,
            'SOURCE_FINAL', 'DISPUTED', 'SAFETY_CONTRADICTION',
            decode(repeat('cf', 32), 'hex'), '2026-01-01 00:00:20+00'
        );
        RAISE EXCEPTION 'runtime fabricated DISPUTED without reorganization';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated DISPUTED without reorganization' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;
SET ROLE unified_crosschain_observer;

SELECT crosschain.record_header_observation(
    'replacement-header-f4', 31337,
    decode(repeat('c1', 32), 'hex'), 100,
    decode(repeat('14', 32), 'hex'),
    decode(repeat('c2', 32), 'hex'), decode('010203', 'hex'),
    decode(repeat('42', 32), 'hex'), '2026-01-01 00:00:21+00'
);
SELECT crosschain.record_header_observation(
    'detected-head-f4', 31337,
    decode(repeat('c3', 32), 'hex'), 113,
    decode(repeat('14', 32), 'hex'),
    decode(repeat('c4', 32), 'hex'), decode('040506', 'hex'),
    decode(repeat('42', 32), 'hex'), '2026-01-01 00:00:22+00'
);
SELECT crosschain.record_header_observation(
    'detected-head-f4', 31337,
    decode(repeat('c3', 32), 'hex'), 113,
    decode(repeat('14', 32), 'hex'),
    decode(repeat('c4', 32), 'hex'), decode('040506', 'hex'),
    decode(repeat('42', 32), 'hex'), '2026-01-01 00:00:22+00'
);

RESET ROLE;
SET ROLE unified_crosschain_reorganization_verifier;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_reorganization(
            'route-phase8', 31337,
            ARRAY['observer-proof-f0', 'observer-proof-f4'],
            ARRAY['observer-certificate-f0', 'observer-certificate-f4'],
            'missing-replacement-header', 'detected-head-f4',
            ARRAY[
                decode(repeat('f0', 32), 'hex'),
                decode(repeat('f4', 32), 'hex')
            ],
            decode(repeat('c5', 32), 'hex'),
            '2026-01-01 00:00:30+00'
        );
        RAISE EXCEPTION 'unanchored replacement header was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'unanchored replacement header was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_reorganization(
            'route-phase8', 31337,
            ARRAY['observer-proof-f4', 'observer-proof-f0'],
            ARRAY['observer-certificate-f0', 'observer-certificate-f4'],
            'replacement-header-f4', 'detected-head-f4',
            ARRAY[
                decode(repeat('f0', 32), 'hex'),
                decode(repeat('f4', 32), 'hex')
            ],
            decode(repeat('c7', 32), 'hex'),
            '2026-01-01 00:00:30+00'
        );
        RAISE EXCEPTION 'misaligned orphan proof array was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'misaligned orphan proof array was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_reorganization(
            'route-phase8', 31337,
            ARRAY[
                'observer-proof-f0',
                'source-proof-' || repeat('f1', 32)
            ],
            ARRAY[
                'observer-certificate-f0',
                'source-certificate-' || repeat('f1', 32)
            ],
            'replacement-header-f4', 'detected-head-f4',
            ARRAY[
                decode(repeat('f0', 32), 'hex'),
                decode(repeat('f1', 32), 'hex')
            ],
            decode(repeat('c8', 32), 'hex'),
            '2026-01-01 00:00:30+00'
        );
        RAISE EXCEPTION 'mixed orphan block facts were accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'mixed orphan block facts were accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_reorganization(
            'route-phase8', 31337,
            ARRAY['observer-proof-f0', 'observer-proof-f2'],
            ARRAY['observer-certificate-f0', 'observer-certificate-f2'],
            'replacement-header-f4', 'detected-head-f4',
            ARRAY[
                decode(repeat('f0', 32), 'hex'),
                decode(repeat('f2', 32), 'hex')
            ],
            decode(repeat('c9', 32), 'hex'),
            '2026-01-01 00:00:30+00'
        );
        RAISE EXCEPTION 'mixed orphan authority and policy facts were accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM =
           'mixed orphan authority and policy facts were accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_reorganization(
            'route-phase8', 31337,
            ARRAY['observer-proof-f0', 'observer-proof-f4'],
            ARRAY['observer-certificate-f0', 'alternate-certificate-f4'],
            'replacement-header-f4', 'detected-head-f4',
            ARRAY[
                decode(repeat('f0', 32), 'hex'),
                decode(repeat('f4', 32), 'hex')
            ],
            decode(repeat('ca', 32), 'hex'),
            '2026-01-01 00:00:30+00'
        );
        RAISE EXCEPTION 'alternate valid finality certificate was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'alternate valid finality certificate was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

SELECT crosschain.record_reorganization(
    'route-phase8', 31337,
    ARRAY['observer-proof-f0', 'observer-proof-f4'],
    ARRAY['observer-certificate-f0', 'observer-certificate-f4'],
    'replacement-header-f4', 'detected-head-f4',
    ARRAY[
        decode(repeat('f0', 32), 'hex'),
        decode(repeat('f4', 32), 'hex')
    ],
    decode(repeat('c6', 32), 'hex'),
    '2026-01-01 00:00:30+00'
);
SELECT crosschain.record_reorganization(
    'route-phase8', 31337,
    ARRAY['observer-proof-f0', 'observer-proof-f4'],
    ARRAY['observer-certificate-f0', 'observer-certificate-f4'],
    'replacement-header-f4', 'detected-head-f4',
    ARRAY[
        decode(repeat('f0', 32), 'hex'),
        decode(repeat('f4', 32), 'hex')
    ],
    decode(repeat('c6', 32), 'hex'),
    '2026-01-01 00:00:30+00'
);

RESET ROLE;

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.messages AS message
        JOIN crosschain.reorganizations AS reorganization
          ON message.message_id = ANY(reorganization.affected_message_ids)
        JOIN crosschain.incidents AS incident
          ON incident.reorganization_id = reorganization.reorganization_id
        WHERE message.message_id = decode(repeat('f4', 32), 'hex')
          AND message.state = 'DISPUTED'
          AND message.state_version = 4
          AND reorganization.evidence_hash = decode(repeat('c6', 32), 'hex')
          AND reorganization.orphaned_proof_ids =
              ARRAY['observer-proof-f0', 'observer-proof-f4']
          AND reorganization.orphaned_certificate_ids =
              ARRAY['observer-certificate-f0', 'observer-certificate-f4']
          AND incident.owner = 'cross-chain-security'
          AND incident.status = 'OPEN'
    ) THEN
        RAISE EXCEPTION 'authenticated reorganization was not durable and atomic';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM crosschain.messages
        WHERE message_id = decode(repeat('f0', 32), 'hex')
          AND state = 'DISPUTED'
          AND state_version = 4
    ) THEN
        RAISE EXCEPTION 'aligned secondary reorganization fact was not disputed';
    END IF;
END;
$test$;

SET ROLE unified_crosschain_runtime;

SELECT pg_temp.begin_test_message(decode(repeat('f5', 32), 'hex'), 260);
SELECT crosschain.transition_message(
    decode(repeat('f5', 32), 'hex'), 2,
    'SOURCE_FINALIZING', 'EXPIRED', 'EXPIRED',
    decode(repeat('85', 32), 'hex'), '2026-01-03 00:00:00+00'
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.transition_message(
            decode(repeat('f5', 32), 'hex'), 3,
            'EXPIRED', 'RECOVERY_PENDING', NULL,
            decode(repeat('97', 32), 'hex'), '2026-01-03 00:00:05+00'
        );
        RAISE EXCEPTION 'runtime fabricated RECOVERY_PENDING';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated RECOVERY_PENDING' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;
SET ROLE unified_crosschain_recovery_verifier;

SELECT crosschain.record_recovery_request(
    decode(repeat('a5', 32), 'hex'),
    decode(repeat('f5', 32), 'hex'),
    decode(repeat('51', 32), 'hex'),
    31337::numeric, decode(repeat('11', 20), 'hex'),
    31338::numeric, decode(repeat('21', 20), 'hex'),
    decode(repeat('b5', 32), 'hex'),
    decode(repeat('44', 32), 'hex'),
    decode(repeat('c5', 32), 'hex'),
    decode(repeat('d5', 32), 'hex'),
    decode(repeat('e5', 32), 'hex'),
    decode(repeat('95', 32), 'hex'),
    1767312000::numeric, 1::numeric,
    decode(repeat('96', 32), 'hex'), 1::smallint,
    decode(repeat('90', 32), 'hex'), 1::bigint,
    decode(repeat('97', 32), 'hex'), B'110'::bit varying, 2,
    decode(repeat('98', 32), 'hex'),
    '2026-01-03 00:00:01+00'
);
SELECT crosschain.record_recovery_request(
    decode(repeat('a5', 32), 'hex'),
    decode(repeat('f5', 32), 'hex'),
    decode(repeat('51', 32), 'hex'),
    31337::numeric, decode(repeat('11', 20), 'hex'),
    31338::numeric, decode(repeat('21', 20), 'hex'),
    decode(repeat('b5', 32), 'hex'),
    decode(repeat('44', 32), 'hex'),
    decode(repeat('c5', 32), 'hex'),
    decode(repeat('d5', 32), 'hex'),
    decode(repeat('e5', 32), 'hex'),
    decode(repeat('95', 32), 'hex'),
    1767312000::numeric, 1::numeric,
    decode(repeat('96', 32), 'hex'), 1::smallint,
    decode(repeat('90', 32), 'hex'), 1::bigint,
    decode(repeat('97', 32), 'hex'), B'110'::bit varying, 2,
    decode(repeat('98', 32), 'hex'),
    '2026-01-03 00:00:01+00'
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_recovery_request(
            decode(repeat('a5', 32), 'hex'),
            decode(repeat('f5', 32), 'hex'),
            decode(repeat('51', 32), 'hex'),
            31337::numeric, decode(repeat('11', 20), 'hex'),
            31338::numeric, decode(repeat('21', 20), 'hex'),
            decode(repeat('b5', 32), 'hex'),
            decode(repeat('44', 32), 'hex'),
            decode(repeat('c5', 32), 'hex'),
            decode(repeat('d5', 32), 'hex'),
            decode(repeat('e5', 32), 'hex'),
            decode(repeat('95', 32), 'hex'),
            1767312000::numeric, 1::numeric,
            decode(repeat('96', 32), 'hex'), 1::smallint,
            decode(repeat('90', 32), 'hex'), 1::bigint,
            decode(repeat('99', 32), 'hex'), B'110'::bit varying, 2,
            decode(repeat('98', 32), 'hex'),
            '2026-01-03 00:00:01+00'
        );
        RAISE EXCEPTION 'changed signed recovery request replay was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'changed signed recovery request replay was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;
SET ROLE unified_crosschain_runtime;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.transition_message(
            decode(repeat('f5', 32), 'hex'), 3,
            'EXPIRED', 'RECOVERY_PENDING', NULL,
            decode(repeat('99', 32), 'hex'), '2026-01-03 00:00:05+00'
        );
        RAISE EXCEPTION 'wrong recovery digest was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'wrong recovery digest was accepted' THEN
            RAISE;
        END IF;
    END;
    PERFORM crosschain.transition_message(
        decode(repeat('f5', 32), 'hex'), 3,
        'EXPIRED', 'RECOVERY_PENDING', NULL,
        decode(repeat('97', 32), 'hex'), '2026-01-03 00:00:05+00'
    );
    BEGIN
        PERFORM crosschain.transition_message(
            decode(repeat('f5', 32), 'hex'), 4,
            'RECOVERY_PENDING', 'DESTINATION_TOMBSTONED', NULL,
            decode(repeat('a9', 32), 'hex'), '2026-01-03 00:00:10+00'
        );
        RAISE EXCEPTION 'runtime fabricated DESTINATION_TOMBSTONED';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated DESTINATION_TOMBSTONED' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;
SET ROLE unified_crosschain_observer;

SELECT crosschain.record_source_proof(
    'recovery-destination-proof-f5', decode(repeat('f5', 32), 'hex'), 31338,
    decode(repeat('a1', 32), 'hex'), 0, 101, 200,
    decode(repeat('a2', 32), 'hex'), decode(repeat('a3', 32), 'hex'),
    decode(repeat('a4', 32), 'hex'), decode(repeat('a9', 32), 'hex'),
    212, decode(repeat('a6', 32), 'hex'), 12,
    decode(repeat('43', 32), 'hex'), decode(repeat('24', 32), 'hex'),
    decode(repeat('a7', 32), 'hex'), decode('040506', 'hex'),
    decode(repeat('a8', 32), 'hex'), '2026-01-03 00:00:20+00'
);

RESET ROLE;
SET ROLE unified_crosschain_finality_attester;

SELECT crosschain.record_finality_certificate(
    'recovery-destination-certificate-f5',
    decode(repeat('f5', 32), 'hex'),
    'recovery-destination-proof-f5',
    decode(repeat('60', 32), 'hex'), 1, B'110', 2,
    decode(repeat('aa', 32), 'hex'), '2026-01-03 00:00:20+00'
);

RESET ROLE;
SET ROLE unified_crosschain_observer;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_tombstone(
            decode(repeat('f5', 32), 'hex'),
            decode(repeat('a5', 32), 'hex'),
            decode(repeat('a9', 32), 'hex'),
            decode(repeat('ff', 32), 'hex'),
            'recovery-destination-proof-f5',
            'recovery-destination-certificate-f5',
            '2026-01-03 00:00:10+00'
        );
        RAISE EXCEPTION 'changed destination commitment was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'changed destination commitment was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

SELECT crosschain.record_tombstone(
    decode(repeat('f5', 32), 'hex'),
    decode(repeat('a5', 32), 'hex'),
    decode(repeat('a9', 32), 'hex'),
    decode(repeat('e5', 32), 'hex'),
    'recovery-destination-proof-f5',
    'recovery-destination-certificate-f5',
    '2026-01-03 00:00:10+00'
);
SELECT crosschain.record_tombstone(
    decode(repeat('f5', 32), 'hex'),
    decode(repeat('a5', 32), 'hex'),
    decode(repeat('a9', 32), 'hex'),
    decode(repeat('e5', 32), 'hex'),
    'recovery-destination-proof-f5',
    'recovery-destination-certificate-f5',
    '2026-01-03 00:00:10+00'
);

RESET ROLE;
SET ROLE unified_crosschain_runtime;

SELECT crosschain.transition_message(
    decode(repeat('f5', 32), 'hex'), 4,
    'RECOVERY_PENDING', 'DESTINATION_TOMBSTONED', NULL,
    decode(repeat('a9', 32), 'hex'), '2026-01-03 00:00:10+00'
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.transition_message(
            decode(repeat('f5', 32), 'hex'), 5,
            'DESTINATION_TOMBSTONED', 'SOURCE_COMPENSATED', NULL,
            decode(repeat('ac', 32), 'hex'), '2026-01-03 00:00:30+00'
        );
        RAISE EXCEPTION 'runtime fabricated SOURCE_COMPENSATED';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated SOURCE_COMPENSATED' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;
SET ROLE unified_crosschain_observer;

SELECT crosschain.record_source_proof(
    'recovery-source-proof-f5', decode(repeat('f5', 32), 'hex'), 31337,
    decode(repeat('b1', 32), 'hex'), 0, 102, 300,
    decode(repeat('b2', 32), 'hex'), decode(repeat('b3', 32), 'hex'),
    decode(repeat('b4', 32), 'hex'),
    crosschain.compensation_evidence_hash(
        decode(repeat('f5', 32), 'hex'),
        decode(repeat('a5', 32), 'hex'),
        'REFUND', 'asset:local:uft', 100, 'lender-1',
        decode(repeat('95', 32), 'hex'),
        decode(repeat('ac', 32), 'hex'),
        '2026-01-03 00:00:30+00'
    ),
    312, decode(repeat('b6', 32), 'hex'), 12,
    decode(repeat('42', 32), 'hex'), decode(repeat('14', 32), 'hex'),
    decode(repeat('b7', 32), 'hex'), decode('010203', 'hex'),
    decode(repeat('b8', 32), 'hex'), '2026-01-03 00:00:40+00'
);

RESET ROLE;
SET ROLE unified_crosschain_finality_attester;

SELECT crosschain.record_finality_certificate(
    'recovery-source-certificate-f5',
    decode(repeat('f5', 32), 'hex'),
    'recovery-source-proof-f5',
    decode(repeat('60', 32), 'hex'), 1, B'110', 2,
    decode(repeat('ba', 32), 'hex'), '2026-01-03 00:00:40+00'
);

RESET ROLE;
SET ROLE unified_crosschain_runtime;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_compensation(
            decode(repeat('f5', 32), 'hex'),
            decode(repeat('a5', 32), 'hex'),
            'REFUND', 'asset:local:uft', 100, 'lender-1',
            decode(repeat('95', 32), 'hex'),
            decode(repeat('ac', 32), 'hex'),
            'recovery-source-proof-f5',
            'recovery-source-certificate-f5',
            '2026-01-03 00:00:30+00'
        );
        RAISE EXCEPTION 'runtime called observer compensation API';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
END;
$test$;

RESET ROLE;
SET ROLE unified_crosschain_observer;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.record_compensation(
            decode(repeat('f5', 32), 'hex'),
            decode(repeat('a5', 32), 'hex'),
            'REFUND', 'asset:local:uft', 101, 'attacker',
            decode(repeat('95', 32), 'hex'),
            decode(repeat('ac', 32), 'hex'),
            'recovery-source-proof-f5',
            'recovery-source-certificate-f5',
            '2026-01-03 00:00:30+00'
        );
        RAISE EXCEPTION 'arbitrary compensation units/recipient were accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'arbitrary compensation units/recipient were accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

SELECT crosschain.record_compensation(
    decode(repeat('f5', 32), 'hex'),
    decode(repeat('a5', 32), 'hex'),
    'REFUND', 'asset:local:uft', 100, 'lender-1',
    decode(repeat('95', 32), 'hex'),
    decode(repeat('ac', 32), 'hex'),
    'recovery-source-proof-f5',
    'recovery-source-certificate-f5',
    '2026-01-03 00:00:30+00'
);
SELECT crosschain.record_compensation(
    decode(repeat('f5', 32), 'hex'),
    decode(repeat('a5', 32), 'hex'),
    'REFUND', 'asset:local:uft', 100, 'lender-1',
    decode(repeat('95', 32), 'hex'),
    decode(repeat('ac', 32), 'hex'),
    'recovery-source-proof-f5',
    'recovery-source-certificate-f5',
    '2026-01-03 00:00:30+00'
);

RESET ROLE;
SELECT encode(
    crosschain.recovery_completion_evidence_hash(
        decode(repeat('f5', 32), 'hex')
    ),
    'hex'
) AS recovery_completion_hash
\gset

SET ROLE unified_crosschain_runtime;

SELECT crosschain.transition_message(
    decode(repeat('f5', 32), 'hex'), 5,
    'DESTINATION_TOMBSTONED', 'SOURCE_COMPENSATED', NULL,
    decode(repeat('ac', 32), 'hex'), '2026-01-03 00:00:30+00'
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.transition_message(
            decode(repeat('f5', 32), 'hex'), 6,
            'SOURCE_COMPENSATED', 'RECOVERED', NULL,
            decode(repeat('ff', 32), 'hex'), '2026-01-03 00:00:40+00'
        );
        RAISE EXCEPTION 'runtime fabricated RECOVERED';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime fabricated RECOVERED' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

SELECT crosschain.transition_message(
    decode(repeat('f5', 32), 'hex'), 6,
    'SOURCE_COMPENSATED', 'RECOVERED', NULL,
    decode(:'recovery_completion_hash', 'hex'), '2026-01-03 00:00:40+00'
);

RESET ROLE;

DO $test$
DECLARE
    message_id_ bytea := decode(repeat('fa', 32), 'hex');
BEGIN
    INSERT INTO crosschain.source_proofs (
        proof_id, message_id, chain_id, transaction_hash,
        transaction_index, log_index, block_number, block_hash,
        receipts_root, inclusion_proof_hash, event_hash,
        finality_head_number, finality_head_hash, confirmation_depth,
        finality_policy_hash, observer_authority_hash,
        observer_signed_header_commitment, observer_signature,
        proof_hash, observed_at
    ) VALUES (
        'false-count-proof', message_id_, 31337,
        decode(repeat('d1', 32), 'hex'), 0, 88, 100,
        decode(repeat('d2', 32), 'hex'),
        decode(repeat('d3', 32), 'hex'),
        decode(repeat('d4', 32), 'hex'),
        decode(repeat('d5', 32), 'hex'),
        112, decode(repeat('d6', 32), 'hex'), 12,
        decode(repeat('42', 32), 'hex'), decode(repeat('14', 32), 'hex'),
        decode(repeat('d7', 32), 'hex'), decode('010203', 'hex'),
        decode(repeat('d8', 32), 'hex'), '2026-01-01 00:00:10+00'
    );
    BEGIN
        INSERT INTO crosschain.finality_certificates (
            certificate_id, message_id, proof_id, signer_set_hash,
            signer_set_version, signer_bitmap, signature_count,
            certificate_hash, certified_at
        ) VALUES (
            'false-count-certificate', message_id_, 'false-count-proof',
            decode(repeat('60', 32), 'hex'), 1, B'110', 3,
            decode(repeat('d9', 32), 'hex'), '2026-01-01 00:00:10+00'
        );
        RAISE EXCEPTION 'false certificate signature count was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END;
$test$;

SET ROLE unified_crosschain_runtime;

SELECT pg_temp.finalize_message(
    decode(repeat('01', 32), 'hex'), 1, 1,
    decode(repeat('81', 32), 'hex'), 1,
    jsonb_build_object(
        'lock_id', 'lock-1', 'route_id', 'route-phase8',
        'route_version', 1, 'chain_id', 31338, 'adapter_id', 'adapter-a',
        'canonical_asset_id', 'uft', 'wrapped_asset_id', 'wuft',
        'units', 100, 'lender_id', 'lender-1', 'loan_id', NULL
    ),
    '2026-01-01 00:00:10+00'
);

-- A committed command atomically creates exactly one deterministic outbox row
-- per state version. Retrying after a lost response must not duplicate any row.
SELECT pg_temp.finalize_message(
    decode(repeat('01', 32), 'hex'), 1, 1,
    decode(repeat('81', 32), 'hex'), 1,
    jsonb_build_object(
        'lock_id', 'lock-1', 'route_id', 'route-phase8',
        'route_version', 1, 'chain_id', 31338, 'adapter_id', 'adapter-a',
        'canonical_asset_id', 'uft', 'wrapped_asset_id', 'wuft',
        'units', 100, 'lender_id', 'lender-1', 'loan_id', NULL
    ),
    '2026-01-01 00:00:10+00'
);

DO $test$
DECLARE
    first_claim crosschain.outbox;
    competing_claim crosschain.outbox;
    restart_claim crosschain.outbox;
    published crosschain.outbox;
    replayed_publication crosschain.outbox;
    consumed crosschain.inbox;
    replayed_consumption crosschain.inbox;
BEGIN
    IF (
        SELECT count(*)
        FROM crosschain.outbox
        WHERE message_id = decode(repeat('01', 32), 'hex')
    ) <> 9 OR EXISTS (
        SELECT 1
        FROM crosschain.outbox
        WHERE message_id = decode(repeat('01', 32), 'hex')
        GROUP BY message_id, state_version
        HAVING count(*) <> 1
    ) OR EXISTS (
        SELECT 1
        FROM crosschain.outbox
        WHERE message_id = decode(repeat('01', 32), 'hex')
          AND (
              outbox_id <> 'crosschain.message-state.v1:'
                  || encode(message_id, 'hex') || ':' || state_version::text
              OR partition_key <> encode(message_id, 'hex')
              OR payload_hash <> sha256(payload)
          )
    ) THEN
        RAISE EXCEPTION 'message outbox replay was not deterministic';
    END IF;

    SELECT * INTO first_claim
    FROM crosschain.claim_outbox(
        'publisher-a',
        '2026-01-01 00:01:00+00',
        '2026-01-01 00:00:20+00',
        1
    );
    IF first_claim.message_id <> decode(repeat('01', 32), 'hex')
       OR first_claim.state_version <> 1
       OR first_claim.status <> 'CLAIMED'
       OR first_claim.attempt_count <> 1 THEN
        RAISE EXCEPTION 'first deterministic outbox claim failed: %', first_claim;
    END IF;

    SELECT * INTO competing_claim
    FROM crosschain.claim_outbox(
        'publisher-b',
        '2026-01-01 00:01:00+00',
        '2026-01-01 00:00:30+00',
        1
    );
    IF competing_claim.outbox_id = first_claim.outbox_id THEN
        RAISE EXCEPTION 'active outbox lease was claimed concurrently';
    END IF;

    SELECT * INTO published
    FROM crosschain.mark_outbox_published(
        first_claim.outbox_id, 'publisher-a', 1, 'partition-0:1',
        '2026-01-01 00:00:40+00'
    );
    -- Repeating the exact request models a committed response lost to the
    -- publisher; the persisted result must be returned after restart.
    SELECT * INTO replayed_publication
    FROM crosschain.mark_outbox_published(
        first_claim.outbox_id, 'publisher-a', 1, 'partition-0:1',
        '2026-01-01 00:00:40+00'
    );
    IF replayed_publication.outbox_id <> published.outbox_id
       OR replayed_publication.status <> 'PUBLISHED'
       OR replayed_publication.broker_offset <> 'partition-0:1' THEN
        RAISE EXCEPTION 'outbox response-loss replay did not return persisted row';
    END IF;
    BEGIN
        PERFORM crosschain.mark_outbox_published(
            first_claim.outbox_id, 'publisher-a', 1, 'partition-0:conflict',
            '2026-01-01 00:00:40+00'
        );
        RAISE EXCEPTION 'conflicting publication replay was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'conflicting publication replay was accepted' THEN
            RAISE;
        END IF;
    END;

    SELECT * INTO restart_claim
    FROM crosschain.claim_outbox(
        'publisher-c',
        '2026-01-01 00:02:00+00',
        '2026-01-01 00:01:01+00',
        1
    );
    IF restart_claim.outbox_id <> competing_claim.outbox_id
       OR restart_claim.attempt_count <> 2
       OR restart_claim.publisher_id <> 'publisher-c' THEN
        RAISE EXCEPTION 'expired lease was not restart-replayable: %', restart_claim;
    END IF;

    SELECT * INTO consumed
    FROM crosschain.consume_inbox(
        'consumer-a', published.message_id, published.topic,
        published.partition_key, published.broker_offset,
        published.payload_hash, '2026-01-01 00:00:50+00'
    );
    SELECT * INTO replayed_consumption
    FROM crosschain.consume_inbox(
        'consumer-a', published.message_id, published.topic,
        published.partition_key, published.broker_offset,
        published.payload_hash, '2026-01-01 00:00:50+00'
    );
    IF replayed_consumption.consumer_id <> consumed.consumer_id
       OR replayed_consumption.payload_hash <> published.payload_hash THEN
        RAISE EXCEPTION 'inbox response-loss replay did not return persisted row';
    END IF;
    BEGIN
        PERFORM crosschain.consume_inbox(
            'consumer-a', published.message_id, published.topic,
            published.partition_key, published.broker_offset,
            decode(repeat('ff', 32), 'hex'), '2026-01-01 00:00:50+00'
        );
        RAISE EXCEPTION 'conflicting inbox payload was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'conflicting inbox payload was accepted' THEN
            RAISE;
        END IF;
    END;
    BEGIN
        PERFORM crosschain.consume_inbox(
            'consumer-a', published.message_id, published.topic,
            'changed-partition-key', published.broker_offset,
            published.payload_hash, '2026-01-01 00:00:50+00'
        );
        RAISE EXCEPTION 'broker coordinate was consumed under a changed key';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'broker coordinate was consumed under a changed key' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

SELECT crosschain.commit_bridge_lock(
    'lock-1', 'route-phase8', 1, 1, 31338, 'adapter-a',
    decode(repeat('01', 32), 'hex'), 'uft', 'wuft', 100, 'lender-1', NULL,
    decode(repeat('81', 32), 'hex'), 1,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('01', 32), 'hex')),
    '2026-01-01 00:00:10+00'
);

-- Exact command replay returns the persisted result and never duplicates the
-- atomic journal/link set.  Changed caller economics and missing canonical
-- action evidence are rejected before any business or accounting write.
SELECT crosschain.commit_bridge_lock(
    'lock-1', 'route-phase8', 1, 1, 31338, 'adapter-a',
    decode(repeat('01', 32), 'hex'), 'uft', 'wuft', 100, 'lender-1', NULL,
    decode(repeat('81', 32), 'hex'), 1,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('01', 32), 'hex')),
    '2026-01-01 00:00:10+00'
);

SELECT pg_temp.finalize_message(
    decode(repeat('07', 32), 'hex'), 1, 7,
    decode(repeat('87', 32), 'hex'), 7, NULL,
    '2026-01-01 00:00:10+00'
);

DO $test$
BEGIN
    IF (
        SELECT count(*) FROM ledger.bridge_journal_links
        WHERE message_id = decode(repeat('01', 32), 'hex')
    ) <> 2 THEN
        RAISE EXCEPTION 'bridge lock replay duplicated or omitted journal links';
    END IF;
    BEGIN
        PERFORM crosschain.commit_bridge_lock(
            'lock-1', 'route-phase8', 1, 1, 31338, 'adapter-a',
            decode(repeat('01', 32), 'hex'), 'uft', 'wuft', 101,
            'lender-1', NULL, decode(repeat('81', 32), 'hex'), 1,
            (SELECT projection_hash FROM crosschain.action_projections
             WHERE message_id = decode(repeat('01', 32), 'hex')),
            '2026-01-01 00:00:10+00'
        );
        RAISE EXCEPTION 'changed caller economics were accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'changed caller economics were accepted' THEN
            RAISE;
        END IF;
    END;
    BEGIN
        PERFORM crosschain.commit_bridge_lock(
            'lock-without-projection', 'route-phase8', 1, 1, 31338,
            'adapter-a', decode(repeat('07', 32), 'hex'), 'uft', 'wuft',
            1, 'lender-1', NULL, decode(repeat('87', 32), 'hex'), 7,
            decode(repeat('58', 32), 'hex'),
            '2026-01-01 00:00:10+00'
        );
        RAISE EXCEPTION 'commit without canonical action projection was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM =
           'commit without canonical action projection was accepted' THEN
            RAISE;
        END IF;
    END;
    IF EXISTS (
        SELECT 1 FROM crosschain.bridge_locks
        WHERE lock_id = 'lock-without-projection'
    ) THEN
        RAISE EXCEPTION 'rejected caller economics changed business or journal state';
    END IF;
END;
$test$;

SELECT pg_temp.finalize_message(
    decode(repeat('02', 32), 'hex'), 2, 2,
    decode(repeat('82', 32), 'hex'), 2,
    jsonb_build_object(
        'mint_id', 'mint-1', 'lock_id', 'lock-1',
        'wrapped_asset_id', 'wuft', 'units', 100,
        'recipient', 'recipient-1', 'supply_after_units', 100
    ),
    '2026-01-01 00:00:10+00'
);
SELECT crosschain.commit_wrapped_mint(
    'mint-1', 'lock-1', decode(repeat('02', 32), 'hex'), 'wuft', 100,
    'recipient-1', decode(repeat('82', 32), 'hex'), 2, 100,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('02', 32), 'hex')),
    '2026-01-01 00:00:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('03', 32), 'hex'), 3, 3,
    decode(repeat('83', 32), 'hex'), 3,
    jsonb_build_object(
        'burn_id', 'burn-1', 'lock_id', 'lock-1', 'payment_id', NULL,
        'wrapped_asset_id', 'wuft', 'units', 40,
        'registry_recipient', 'lender-1', 'burn_kind', 'REDEMPTION',
        'supply_after_units', 60
    ),
    '2026-01-01 00:00:10+00'
);
SELECT crosschain.commit_wrapped_burn(
    'burn-1', 'lock-1', decode(repeat('03', 32), 'hex'), NULL, 'wuft', 40,
    'lender-1', 'REDEMPTION', decode(repeat('83', 32), 'hex'), 3, 60,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('03', 32), 'hex')),
    '2026-01-01 00:00:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('04', 32), 'hex'), 4, 4,
    decode(repeat('84', 32), 'hex'), 4,
    jsonb_build_object(
        'release_id', 'release-1', 'burn_id', 'burn-1',
        'canonical_asset_id', 'uft', 'units', 40,
        'registry_recipient', 'lender-1',
        'result_hash', repeat('75', 32)
    ),
    '2026-01-01 00:00:10+00'
);
SELECT crosschain.commit_canonical_release(
    'release-1', 'burn-1', decode(repeat('04', 32), 'hex'), 'uft', 40,
    'lender-1', decode(repeat('84', 32), 'hex'), 4,
    decode(repeat('75', 32), 'hex'), '2026-01-01 00:00:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('05', 32), 'hex'), 3, 5,
    decode(repeat('85', 32), 'hex'), 5,
    jsonb_build_object(
        'burn_id', 'burn-2', 'lock_id', 'lock-1', 'payment_id', NULL,
        'wrapped_asset_id', 'wuft', 'units', 60,
        'registry_recipient', 'lender-1', 'burn_kind', 'REDEMPTION',
        'supply_after_units', 0
    ),
    '2026-01-01 00:00:10+00'
);
SELECT crosschain.commit_wrapped_burn(
    'burn-2', 'lock-1', decode(repeat('05', 32), 'hex'), NULL, 'wuft', 60,
    'lender-1', 'REDEMPTION', decode(repeat('85', 32), 'hex'), 5, 0,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('05', 32), 'hex')),
    '2026-01-01 00:00:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('06', 32), 'hex'), 4, 6,
    decode(repeat('86', 32), 'hex'), 6,
    jsonb_build_object(
        'release_id', 'release-2', 'burn_id', 'burn-2',
        'canonical_asset_id', 'uft', 'units', 60,
        'registry_recipient', 'lender-1',
        'result_hash', repeat('77', 32)
    ),
    '2026-01-01 00:00:10+00'
);
SELECT crosschain.commit_canonical_release(
    'release-2', 'burn-2', decode(repeat('06', 32), 'hex'), 'uft', 60,
    'lender-1', decode(repeat('86', 32), 'hex'), 6,
    decode(repeat('77', 32), 'hex'), '2026-01-01 00:00:10+00'
);

DO $test$
DECLARE
    lock_record crosschain.bridge_locks;
BEGIN
    SELECT * INTO lock_record FROM crosschain.bridge_locks WHERE lock_id = 'lock-1';
    IF lock_record.minted_units <> 100 OR lock_record.burned_units <> 100
       OR lock_record.released_units <> 100
       OR lock_record.permanently_burned_units <> 0
       OR lock_record.status <> 'SETTLED' THEN
        RAISE EXCEPTION 'partial burn/release conservation failed: %', lock_record;
    END IF;
    PERFORM crosschain.commit_canonical_release(
        'release-2', 'burn-2', decode(repeat('06', 32), 'hex'), 'uft', 60,
        'lender-1', decode(repeat('86', 32), 'hex'), 6,
        decode(repeat('77', 32), 'hex'), '2026-01-01 00:00:10+00'
    );
    BEGIN
        PERFORM crosschain.commit_canonical_release(
            'release-conflict', 'burn-2', decode(repeat('06', 32), 'hex'), 'uft', 60,
            'lender-1', decode(repeat('86', 32), 'hex'), 6,
            decode(repeat('77', 32), 'hex'), '2026-01-01 00:00:10+00'
        );
        RAISE EXCEPTION 'conflicting release replay was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'conflicting release replay was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;

SELECT crosschain.register_loan_route(
    'loan-direct', 'route-phase8', 1, 31337, 31338,
    decode(repeat('a1', 20), 'hex'), decode(repeat('a2', 20), 'hex'),
    'borrower-1', 'lender-1', 'uft', 100, 'collateral', 200,
    decode(repeat('a3', 32), 'hex'), '2026-01-01 00:02:00+00'
);
SELECT crosschain.register_loan_route(
    'loan-policy-reuse', 'route-phase8', 1, 31337, 31338,
    decode(repeat('b1', 20), 'hex'), decode(repeat('b2', 20), 'hex'),
    'borrower-2', 'lender-2', 'uft', 100, 'collateral', 200,
    decode(repeat('a3', 32), 'hex'), '2026-01-01 00:02:00+00'
);

SET ROLE unified_crosschain_runtime;

SELECT pg_temp.finalize_message(
    decode(repeat('0b', 32), 'hex'), 5, 11,
    decode(repeat('8b', 32), 'hex'), 11,
    jsonb_build_object(
        'position_id', 'position-1', 'loan_id', 'loan-direct',
        'satellite_chain_id', 31338, 'vault', repeat('a2', 20),
        'asset_id', 'collateral', 'remote_position_key', 'remote-position-1',
        'units', 200, 'borrower_id', 'borrower-1',
        'custody_commitment', repeat('a4', 32)
    ),
    '2026-01-01 00:02:10+00'
);
SELECT crosschain.commit_satellite_collateral_lock(
    'position-1', 'loan-direct', 31338, decode(repeat('a2', 20), 'hex'),
    'collateral', 'remote-position-1', 200, 'borrower-1',
    decode(repeat('0b', 32), 'hex'), decode(repeat('a4', 32), 'hex'),
    '2026-01-01 00:02:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('0c', 32), 'hex'), 6, 12,
    decode(repeat('8c', 32), 'hex'), 12,
    jsonb_build_object(
        'authorization_id', 'disbursement-1', 'loan_id', 'loan-direct',
        'wrapped_asset_id', 'wuft', 'units', 100,
        'borrower_id', 'borrower-1', 'settlement_vault', repeat('a5', 20)
    ),
    '2026-01-01 00:02:10+00'
);
SELECT crosschain.commit_disbursement_authorization(
    'disbursement-1', 'loan-direct', decode(repeat('0c', 32), 'hex'),
    'wuft', 100, 'borrower-1', decode(repeat('a5', 20), 'hex'),
    '2026-01-01 00:02:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('0d', 32), 'hex'), 7, 13,
    decode(repeat('8d', 32), 'hex'), 13,
    jsonb_build_object(
        'authorization_id', 'disbursement-1', 'loan_id', 'loan-direct',
        'recipient_balance_delta_hash', repeat('a6', 32), 'units', 100
    ),
    '2026-01-01 00:02:10+00'
);
SELECT crosschain.commit_disbursement_result(
    'disbursement-1', 'loan-direct', decode(repeat('0d', 32), 'hex'),
    decode(repeat('8d', 32), 'hex'), 13, decode(repeat('a6', 32), 'hex'),
    100, '2026-01-01 00:02:10+00'
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.commit_direct_home_repayment(
            'direct-payment-forged', 'loan-direct', 'uft', 100, 100, 0,
            'lender-1', decode(repeat('f1', 32), 'hex'), 999,
            decode(repeat('f2', 32), 'hex'), '2026-01-01 00:02:20+00'
        );
        RAISE EXCEPTION 'runtime forged direct home repayment';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'runtime forged direct home repayment' THEN
            RAISE;
        END IF;
    END;
    IF EXISTS (
        SELECT 1 FROM crosschain.direct_home_repayment_results
        WHERE payment_id = 'direct-payment-forged'
    ) OR EXISTS (
        SELECT 1 FROM ledger.satellite_settlement_links
        WHERE payment_id = 'direct-payment-forged'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.loan_routes
        WHERE loan_id = 'loan-direct' AND lifecycle_state = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'forged direct repayment changed debt or journal state';
    END IF;
END;
$test$;

RESET ROLE;

SET ROLE unified_crosschain_finality_attester;

SELECT crosschain.record_direct_home_repayment_evidence(
    'direct-payment-1', 'loan-direct', 'uft', 100, 'lender-1',
    decode(repeat('a7', 32), 'hex'), 1,
    crosschain.direct_home_repayment_evidence_hash(
        'direct-payment-1', 'loan-direct', 'uft', 100, 'lender-1',
        decode(repeat('a7', 32), 'hex'), 1,
        '2026-01-01 00:02:20+00'
    ),
    '2026-01-01 00:02:20+00'
);

RESET ROLE;

SET ROLE unified_home_accounting_runtime;

SELECT crosschain.commit_direct_home_repayment(
    'direct-payment-1', 'loan-direct', 'uft', 100, 100, 0, 'lender-1',
    decode(repeat('a7', 32), 'hex'), 1,
    (SELECT evidence_hash
     FROM crosschain.direct_home_repayment_evidence
     WHERE payment_id = 'direct-payment-1'),
    '2026-01-01 00:02:20+00'
);

RESET ROLE;

SET ROLE unified_crosschain_runtime;

SELECT pg_temp.finalize_message(
    decode(repeat('0e', 32), 'hex'), 9, 14,
    decode(repeat('8e', 32), 'hex'), 14,
    jsonb_build_object(
        'authorization_id', 'release-auth-1', 'loan_id', 'loan-direct',
        'position_id', 'position-1',
        'zero_debt_commitment', repeat('a9', 32),
        'borrower_id', 'borrower-1'
    ),
    '2026-01-01 00:02:30+00'
);
SELECT crosschain.commit_collateral_release_authorization(
    'release-auth-1', 'loan-direct', 'position-1',
    decode(repeat('0e', 32), 'hex'), decode(repeat('a9', 32), 'hex'),
    'borrower-1', '2026-01-01 00:02:30+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('0f', 32), 'hex'), 10, 15,
    decode(repeat('8f', 32), 'hex'), 15,
    jsonb_build_object(
        'authorization_id', 'release-auth-1', 'loan_id', 'loan-direct',
        'position_id', 'position-1', 'release_result_hash', repeat('aa', 32),
        'accounting_reconciliation_hash', repeat('ab', 32),
        'borrower_id', 'borrower-1'
    ),
    '2026-01-01 00:02:40+00'
);
SELECT crosschain.commit_collateral_release(
    'release-auth-1', 'loan-direct', 'position-1',
    decode(repeat('0f', 32), 'hex'), decode(repeat('8f', 32), 'hex'), 15,
    decode(repeat('aa', 32), 'hex'), decode(repeat('ab', 32), 'hex'),
    'borrower-1', '2026-01-01 00:02:40+00'
);

SELECT pg_temp.finalize_message(
    decode(repeat('10', 32), 'hex'), 5, 16,
    decode(repeat('90', 32), 'hex'), 16,
    jsonb_build_object(
        'position_id', 'position-conflict', 'loan_id', 'loan-policy-reuse',
        'satellite_chain_id', 31338, 'vault', repeat('a2', 20),
        'asset_id', 'collateral', 'remote_position_key', 'remote-position-1',
        'units', 200, 'borrower_id', 'borrower-2',
        'custody_commitment', repeat('ac', 32)
    ),
    '2026-01-01 00:02:50+00'
);

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM crosschain.loan_routes
        WHERE loan_id = 'loan-direct' AND lifecycle_state = 'CLOSED'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.collateral_positions
        WHERE position_id = 'position-1' AND status = 'RELEASED'
    ) THEN
        RAISE EXCEPTION 'direct-home loan lifecycle did not reach finalized CLOSED';
    END IF;
    BEGIN
        PERFORM crosschain.commit_satellite_collateral_lock(
            'position-conflict', 'loan-policy-reuse', 31338,
            decode(repeat('a2', 20), 'hex'), 'collateral', 'remote-position-1',
            200, 'borrower-2', decode(repeat('10', 32), 'hex'),
            decode(repeat('ac', 32), 'hex'), '2026-01-01 00:02:50+00'
        );
        RAISE EXCEPTION 'duplicate remote collateral was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'duplicate remote collateral was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;

INSERT INTO crosschain.loan_routes (
    loan_id, route_id, route_version, home_chain_id, satellite_chain_id,
    home_loan, satellite_component, borrower_id, lender_id,
    principal_asset_id, principal_units, collateral_asset_id, collateral_units,
    immutable_policy_hash, lifecycle_state, state_version, created_at, updated_at
) VALUES (
    'loan-remote', 'route-phase8', 1, 31337, 31338,
    decode(repeat('c1', 20), 'hex'), decode(repeat('c2', 20), 'hex'),
    'borrower-remote', 'lender-remote', 'uft', 100, 'collateral', 200,
    decode(repeat('c3', 32), 'hex'), 'ACTIVE', 2,
    '2026-01-01 00:03:00+00', '2026-01-01 00:03:00+00'
);

SET ROLE unified_crosschain_runtime;

SELECT pg_temp.finalize_message(
    decode(repeat('20', 32), 'hex'), 1, 20,
    decode(repeat('b0', 32), 'hex'), 20,
    jsonb_build_object(
        'lock_id', 'lock-remote', 'route_id', 'route-phase8',
        'route_version', 1, 'chain_id', 31338, 'adapter_id', 'adapter-a',
        'canonical_asset_id', 'uft', 'wrapped_asset_id', 'wuft',
        'units', 100, 'lender_id', 'lender-remote',
        'loan_id', 'loan-remote'
    ),
    '2026-01-01 00:03:10+00'
);
SELECT crosschain.commit_bridge_lock(
    'lock-remote', 'route-phase8', 1, 1, 31338, 'adapter-a',
    decode(repeat('20', 32), 'hex'), 'uft', 'wuft', 100, 'lender-remote',
    'loan-remote', decode(repeat('b0', 32), 'hex'), 20,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('20', 32), 'hex')),
    '2026-01-01 00:03:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('21', 32), 'hex'), 2, 21,
    decode(repeat('b1', 32), 'hex'), 21,
    jsonb_build_object(
        'mint_id', 'mint-remote', 'lock_id', 'lock-remote',
        'wrapped_asset_id', 'wuft', 'units', 100,
        'recipient', 'borrower-remote', 'supply_after_units', 100
    ),
    '2026-01-01 00:03:10+00'
);
SELECT crosschain.commit_wrapped_mint(
    'mint-remote', 'lock-remote', decode(repeat('21', 32), 'hex'), 'wuft', 100,
    'borrower-remote', decode(repeat('b1', 32), 'hex'), 21, 100,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('21', 32), 'hex')),
    '2026-01-01 00:03:10+00'
);
SELECT pg_temp.finalize_message(
    decode(repeat('22', 32), 'hex'), 8, 22,
    decode(repeat('b2', 32), 'hex'), 22,
    jsonb_build_object(
        'burn_id', 'burn-remote', 'lock_id', 'lock-remote',
        'payment_id', 'payment-remote', 'loan_id', 'loan-remote',
        'wrapped_asset_id', 'wuft', 'asset_id', 'uft', 'units', 100,
        'registry_recipient', 'lender-remote', 'lender_id', 'lender-remote',
        'burn_kind', 'LOAN_REPAYMENT', 'supply_after_units', 0,
        'release_id', 'release-remote', 'canonical_asset_id', 'uft',
        'result_hash', repeat('d3', 32)
    ),
    '2026-01-01 00:03:10+00'
);
SELECT crosschain.commit_wrapped_burn(
    'burn-remote', 'lock-remote', decode(repeat('22', 32), 'hex'),
    'payment-remote', 'wuft', 100, 'lender-remote', 'LOAN_REPAYMENT',
    decode(repeat('b2', 32), 'hex'), 22, 0,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('22', 32), 'hex')),
    '2026-01-01 00:03:10+00'
);
SELECT crosschain.commit_canonical_release(
    'release-remote', 'burn-remote', decode(repeat('22', 32), 'hex'),
    'uft', 100, 'lender-remote', decode(repeat('b2', 32), 'hex'), 22,
    decode(repeat('d3', 32), 'hex'), '2026-01-01 00:03:10+00'
);
SELECT crosschain.commit_remote_repayment(
    'payment-remote', 'loan-remote', 'burn-remote',
    decode(repeat('22', 32), 'hex'), decode(repeat('d3', 32), 'hex'),
    'uft', 100, 100, 0, 'lender-remote',
    decode(repeat('b2', 32), 'hex'), 22,
    (SELECT projection_hash FROM crosschain.action_projections
     WHERE message_id = decode(repeat('22', 32), 'hex')),
    '2026-01-01 00:03:10+00'
);

DO $test$
DECLARE
    first_repayment crosschain.repayment_results;
    replayed_repayment crosschain.repayment_results;
BEGIN
    SELECT * INTO first_repayment
    FROM crosschain.repayment_results
    WHERE payment_id = 'payment-remote';
    SELECT * INTO replayed_repayment
    FROM crosschain.commit_remote_repayment(
        'payment-remote', 'loan-remote', 'burn-remote',
        decode(repeat('22', 32), 'hex'), decode(repeat('d3', 32), 'hex'),
        'uft', 100, 100, 0, 'lender-remote',
        decode(repeat('b2', 32), 'hex'), 22,
        (SELECT projection_hash FROM crosschain.action_projections
         WHERE message_id = decode(repeat('22', 32), 'hex')),
        '2026-01-01 00:03:10+00'
    );
    IF replayed_repayment.payment_id <> first_repayment.payment_id
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.loan_routes
           WHERE loan_id = 'loan-remote' AND lifecycle_state = 'CLOSING'
       ) THEN
        RAISE EXCEPTION 'remote repayment binding/replay did not preserve canonical result';
    END IF;
END;
$test$;

RESET ROLE;

SELECT crosschain.activate_bridge_exposure_policy(
    2, 1000000, decode(repeat('62', 32), 'hex'),
    50, 10000, 10000, 15000, 500, 1500,
    '2026-01-01 00:03:30+00'
);
-- Replaying an old policy version returns the immutable old row; it must not
-- reactivate stale limits.
SELECT crosschain.activate_bridge_exposure_policy(
    1, 1000000, decode(repeat('61', 32), 'hex'),
    5000, 10000, 10000, 15000, 500, 1500,
    '2026-01-01 00:00:00+00'
);
DO $test$
BEGIN
    IF (SELECT count(*) FROM crosschain.bridge_exposure_policies
        WHERE status = 'ACTIVE') <> 1
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.bridge_exposure_policies
           WHERE policy_version = 2 AND status = 'ACTIVE'
       )
       OR NOT EXISTS (
           SELECT 1 FROM crosschain.bridge_exposure_policies
           WHERE policy_version = 1 AND status = 'DEPRECATED'
       ) THEN
        RAISE EXCEPTION 'bridge exposure policy activation is not single-current';
    END IF;
END;
$test$;

-- An unresolved partial disposal still consumes 50 units of headroom.
UPDATE crosschain.bridge_locks
SET status = 'PARTIALLY_DISPOSED', released_units = 50
WHERE lock_id = 'lock-1';

SET ROLE unified_crosschain_runtime;
SELECT pg_temp.finalize_message(
    decode(repeat('24', 32), 'hex'), 1, 24,
    decode(repeat('b4', 32), 'hex'), 24,
    jsonb_build_object(
        'lock_id', 'lock-over-partial-cap', 'route_id', 'route-phase8',
        'route_version', 1, 'chain_id', 31338, 'adapter_id', 'adapter-a',
        'canonical_asset_id', 'uft', 'wrapped_asset_id', 'wuft',
        'units', 1, 'lender_id', 'lender-cap', 'loan_id', NULL
    ),
    '2026-01-01 00:03:30+00'
);
DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.commit_bridge_lock(
            'lock-over-partial-cap', 'route-phase8', 1, 2, 31338,
            'adapter-a', decode(repeat('24', 32), 'hex'), 'uft', 'wuft',
            1, 'lender-cap', NULL, decode(repeat('b4', 32), 'hex'), 24,
            (SELECT projection_hash FROM crosschain.action_projections
             WHERE message_id = decode(repeat('24', 32), 'hex')),
            '2026-01-01 00:03:30+00'
        );
        RAISE EXCEPTION 'partially disposed exposure bypassed cap';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'partially disposed exposure bypassed cap' THEN
            RAISE;
        END IF;
    END;
END;
$test$;
RESET ROLE;

-- A disputed lock consumes the same unresolved headroom.
UPDATE crosschain.bridge_locks
SET status = 'DISPUTED'
WHERE lock_id = 'lock-1';
SET ROLE unified_crosschain_runtime;
SELECT pg_temp.finalize_message(
    decode(repeat('25', 32), 'hex'), 1, 25,
    decode(repeat('b5', 32), 'hex'), 25,
    jsonb_build_object(
        'lock_id', 'lock-over-disputed-cap', 'route_id', 'route-phase8',
        'route_version', 1, 'chain_id', 31338, 'adapter_id', 'adapter-a',
        'canonical_asset_id', 'uft', 'wrapped_asset_id', 'wuft',
        'units', 1, 'lender_id', 'lender-cap', 'loan_id', NULL
    ),
    '2026-01-01 00:03:30+00'
);
DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.commit_bridge_lock(
            'lock-over-disputed-cap', 'route-phase8', 1, 2, 31338,
            'adapter-a', decode(repeat('25', 32), 'hex'), 'uft', 'wuft',
            1, 'lender-cap', NULL, decode(repeat('b5', 32), 'hex'), 25,
            (SELECT projection_hash FROM crosschain.action_projections
             WHERE message_id = decode(repeat('25', 32), 'hex')),
            '2026-01-01 00:03:30+00'
        );
        RAISE EXCEPTION 'disputed exposure bypassed cap';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'disputed exposure bypassed cap' THEN
            RAISE;
        END IF;
    END;
END;
$test$;
RESET ROLE;

UPDATE crosschain.bridge_locks
SET status = 'SETTLED', released_units = 100
WHERE lock_id = 'lock-1';

INSERT INTO crosschain.bridge_exposure_snapshots (
    snapshot_id, route_id, route_version, policy_version, chain_id, adapter_id,
    route_escrow_units, chain_escrow_units, adapter_escrow_units,
    aggregate_escrow_units, circulating_supply_reference_units,
    circulating_supply_evidence_hash, calculated_headroom_units,
    block_number, block_hash, evidence_hash, observed_at
) VALUES (
    'exposure-snapshot-1', 'route-phase8', 1, 1, 31338, 'adapter-a',
    0, 0, 0, 0, 1000000, decode(repeat('61', 32), 'hex'), 5000,
    100, decode(repeat('91', 32), 'hex'), decode(repeat('92', 32), 'hex'),
    '2026-01-01 00:01:00+00'
);
INSERT INTO crosschain.bridge_backing_snapshots (
    snapshot_id, route_id, route_version, canonical_asset_id, wrapped_asset_id,
    canonical_escrow_units, wrapped_supply_units, pending_mint_units,
    pending_burn_units, home_block_hash, satellite_block_hash, evidence_hash, observed_at
) VALUES (
    'backing-snapshot-1', 'route-phase8', 1, 'uft', 'wuft',
    0, 0, 0, 0, decode(repeat('93', 32), 'hex'),
    decode(repeat('94', 32), 'hex'), decode(repeat('95', 32), 'hex'),
    '2026-01-01 00:01:00+00'
);

SET ROLE unified_crosschain_runtime;

SELECT crosschain.open_bridge_reconciliation(
    'recon-1', 'route-phase8', 1, decode(repeat('93', 32), 'hex'),
    decode(repeat('94', 32), 'hex'), 'backing-snapshot-1', 'exposure-snapshot-1',
    decode(repeat('96', 32), 'hex'), 'risk-owner', '2026-01-01 00:01:00+00'
);
SELECT crosschain.record_bridge_reconciliation_difference(
    'difference-1', 'recon-1', 'BACKING', 'NONZERO_DIFF', 'uft', 0, 1,
    NULL, NULL, 'CRITICAL', 'risk-owner', '2026-01-01 00:01:01+00',
    '2026-01-01 01:01:01+00', decode(repeat('97', 32), 'hex')
);
SELECT crosschain.finalize_bridge_reconciliation(
    'recon-1', '2026-01-01 00:01:02+00'
);
SELECT crosschain.record_bridge_reconciliation_difference(
    'difference-1', 'recon-1', 'BACKING', 'NONZERO_DIFF', 'uft', 0, 1,
    NULL, NULL, 'CRITICAL', 'risk-owner', '2026-01-01 00:01:01+00',
    '2026-01-01 01:01:01+00', decode(repeat('97', 32), 'hex')
);
SELECT crosschain.finalize_bridge_reconciliation(
    'recon-1', '2026-01-01 00:01:02+00'
);

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM crosschain.bridge_reconciliations
        WHERE run_id = 'recon-1' AND status = 'EXCEPTION'
          AND completed_at = '2026-01-01 00:01:02+00'
    ) THEN
        RAISE EXCEPTION 'nonzero reconciliation difference was not preserved';
    END IF;
    BEGIN
        PERFORM crosschain.record_bridge_reconciliation_difference(
            'difference-after-close', 'recon-1', 'BACKING', 'LATE_DIFF',
            'uft', 0, 1, NULL, NULL, 'CRITICAL', 'risk-owner',
            '2026-01-01 00:01:03+00', '2026-01-01 01:01:03+00',
            decode(repeat('98', 32), 'hex')
        );
        RAISE EXCEPTION 'difference was inserted after reconciliation close';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM =
           'difference was inserted after reconciliation close' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

SELECT pg_temp.begin_test_message(decode(repeat('fd', 32), 'hex'), 254);
SELECT pg_temp.seed_source_finality(
    decode(repeat('fd', 32), 'hex'), decode(repeat('60', 32), 'hex'), 1
);

RESET ROLE;

UPDATE crosschain.chain_versions
SET status = 'DEPRECATED'
WHERE (chain_id, version) IN ((31337, 1), (31338, 1));
UPDATE crosschain.signer_sets
SET status = 'DEPRECATED'
WHERE signer_set_hash = decode(repeat('60', 32), 'hex') AND version = 1;

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.register_route_version(
            'route-after-deprecation', 1,
            31337, 1, decode(repeat('11', 20), 'hex'),
            decode(repeat('31', 20), 'hex'),
            31338, 1, decode(repeat('21', 20), 'hex'),
            decode(repeat('32', 20), 'hex'),
            'PHASE8_ALL',
            decode(repeat('41', 32), 'hex'), decode(repeat('42', 32), 'hex'),
            decode(repeat('43', 32), 'hex'),
            decode(repeat('60', 32), 'hex'), 1,
            decode(repeat('60', 32), 'hex'), 1,
            decode(repeat('45', 32), 'hex'),
            1, 'ACTIVE', '2026-01-01 00:04:00+00'
        );
        RAISE EXCEPTION 'new route accepted deprecated authority';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'new route accepted deprecated authority' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

SET ROLE unified_crosschain_runtime;

DO $test$
DECLARE
    message_id_ bytea := decode(repeat('fd', 32), 'hex');
    source_certificate bytea := sha256(
        message_id_ || convert_to('source-certificate-v1', 'UTF8')
    );
    transaction_hash bytea := decode(repeat('ed', 32), 'hex');
    result_hash bytea := decode(repeat('57', 32), 'hex');
    effect_hash bytea := decode(repeat('58', 32), 'hex');
    occurred timestamptz := '2026-01-01 00:00:10+00';
BEGIN
    PERFORM crosschain.transition_message(
        message_id_, 2, 'SOURCE_FINALIZING', 'SOURCE_FINAL',
        NULL, source_certificate, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 3, 'SOURCE_FINAL', 'SENT',
        NULL, result_hash, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 4, 'SENT', 'RELAYED',
        NULL, result_hash, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 5, 'RELAYED', 'VERIFIED',
        NULL, source_certificate, occurred
    );
    PERFORM pg_temp.seed_destination_execution_finality(
        message_id_, transaction_hash, 254, result_hash, effect_hash, occurred,
        decode(repeat('60', 32), 'hex'), 1
    );
    PERFORM pg_temp.record_legacy_test_execution(
        message_id_, 31338, transaction_hash, 254,
        result_hash, effect_hash, occurred
    );
    PERFORM crosschain.transition_message(
        message_id_, 6, 'VERIFIED', 'EXECUTED',
        NULL, result_hash, occurred
    );
    IF NOT EXISTS (
        SELECT 1 FROM crosschain.messages
        WHERE message_id = message_id_ AND state = 'EXECUTED'
    ) THEN
        RAISE EXCEPTION 'deprecated pinned authority blocked safe exit';
    END IF;
END;
$test$;

RESET ROLE;

-- Separate eligible cancellation loans. These are alternate paths from the
-- happy-path loan above; neither loan is ever disbursed.
SELECT crosschain.register_loan_route(
    'loan-cancel-zero', 'route-phase8', 1, 31337, 31338,
    decode(repeat('f1', 20), 'hex'), decode(repeat('f2', 20), 'hex'),
    'borrower-cancel-zero', 'lender-cancel-zero', 'uft', 100,
    'collateral', 200, decode(repeat('f3', 32), 'hex'),
    '2026-01-04 00:00:00+00'
);
SELECT crosschain.register_loan_route(
    'loan-cancel-nonzero', 'route-phase8', 1, 31337, 31338,
    decode(repeat('f4', 20), 'hex'), decode(repeat('f5', 20), 'hex'),
    'borrower-cancel-nonzero', 'lender-cancel-nonzero', 'uft', 100,
    'collateral', 200, decode(repeat('f6', 32), 'hex'),
    '2026-01-04 00:00:00+00'
);
SELECT crosschain.activate_bridge_exposure_policy(
    3, 1000000,
    sha256(convert_to('cancellation-exposure-policy', 'UTF8')),
    5000, 10000, 10000, 15000, 500, 1500,
    '2026-01-04 00:00:00+00'
);

SET ROLE unified_crosschain_runtime;

DO $cancellation_prestate$
DECLARE
    zero_lock_message bytea := sha256(convert_to('cancel-zero-lock-message', 'UTF8'));
    zero_mint_message bytea := sha256(convert_to('cancel-zero-mint-message', 'UTF8'));
    nonzero_lock_message bytea := sha256(convert_to('cancel-nonzero-lock-message', 'UTF8'));
    nonzero_mint_message bytea := sha256(convert_to('cancel-nonzero-mint-message', 'UTF8'));
BEGIN
    PERFORM pg_temp.finalize_message(
        zero_lock_message, 1, 301,
        sha256(convert_to('cancel-zero-lock-transaction', 'UTF8')), 301,
        jsonb_build_object(
            'lock_id', 'lock-cancel-zero', 'route_id', 'route-phase8',
            'route_version', 1, 'chain_id', 31338, 'adapter_id', 'adapter-a',
            'canonical_asset_id', 'uft', 'wrapped_asset_id', 'wuft',
            'units', 100, 'lender_id', 'lender-cancel-zero',
            'loan_id', 'loan-cancel-zero'
        ),
        '2026-01-04 00:00:10+00'
    );
    PERFORM crosschain.commit_bridge_lock(
        'lock-cancel-zero', 'route-phase8', 1, 3, 31338, 'adapter-a',
        zero_lock_message, 'uft', 'wuft', 100, 'lender-cancel-zero',
        'loan-cancel-zero',
        sha256(convert_to('cancel-zero-lock-transaction', 'UTF8')), 301,
        (SELECT projection_hash FROM crosschain.action_projections
         WHERE message_id = zero_lock_message),
        '2026-01-04 00:00:10+00'
    );
    PERFORM pg_temp.finalize_message(
        zero_mint_message, 2, 302,
        sha256(convert_to('cancel-zero-mint-transaction', 'UTF8')), 302,
        jsonb_build_object(
            'mint_id', 'mint-cancel-zero', 'lock_id', 'lock-cancel-zero',
            'wrapped_asset_id', 'wuft', 'units', 100,
            'recipient', 'settlement-cancel-zero', 'supply_after_units', 100
        ),
        '2026-01-04 00:00:20+00'
    );
    PERFORM crosschain.commit_wrapped_mint(
        'mint-cancel-zero', 'lock-cancel-zero', zero_mint_message,
        'wuft', 100, 'settlement-cancel-zero',
        sha256(convert_to('cancel-zero-mint-transaction', 'UTF8')), 302, 100,
        (SELECT projection_hash FROM crosschain.action_projections
         WHERE message_id = zero_mint_message),
        '2026-01-04 00:00:20+00'
    );

    PERFORM pg_temp.finalize_message(
        nonzero_lock_message, 1, 303,
        sha256(convert_to('cancel-nonzero-lock-transaction', 'UTF8')), 303,
        jsonb_build_object(
            'lock_id', 'lock-cancel-nonzero', 'route_id', 'route-phase8',
            'route_version', 1, 'chain_id', 31338, 'adapter_id', 'adapter-a',
            'canonical_asset_id', 'uft', 'wrapped_asset_id', 'wuft',
            'units', 100, 'lender_id', 'lender-cancel-nonzero',
            'loan_id', 'loan-cancel-nonzero'
        ),
        '2026-01-04 00:00:30+00'
    );
    PERFORM crosschain.commit_bridge_lock(
        'lock-cancel-nonzero', 'route-phase8', 1, 3, 31338, 'adapter-a',
        nonzero_lock_message, 'uft', 'wuft', 100,
        'lender-cancel-nonzero', 'loan-cancel-nonzero',
        sha256(convert_to('cancel-nonzero-lock-transaction', 'UTF8')), 303,
        (SELECT projection_hash FROM crosschain.action_projections
         WHERE message_id = nonzero_lock_message),
        '2026-01-04 00:00:30+00'
    );
    PERFORM pg_temp.finalize_message(
        nonzero_mint_message, 2, 304,
        sha256(convert_to('cancel-nonzero-mint-transaction', 'UTF8')), 304,
        jsonb_build_object(
            'mint_id', 'mint-cancel-nonzero',
            'lock_id', 'lock-cancel-nonzero',
            'wrapped_asset_id', 'wuft', 'units', 100,
            'recipient', 'settlement-cancel-nonzero',
            'supply_after_units', 100
        ),
        '2026-01-04 00:00:40+00'
    );
    PERFORM crosschain.commit_wrapped_mint(
        'mint-cancel-nonzero', 'lock-cancel-nonzero',
        nonzero_mint_message, 'wuft', 100, 'settlement-cancel-nonzero',
        sha256(convert_to('cancel-nonzero-mint-transaction', 'UTF8')),
        304, 100,
        (SELECT projection_hash FROM crosschain.action_projections
         WHERE message_id = nonzero_mint_message),
        '2026-01-04 00:00:40+00'
    );
END;
$cancellation_prestate$;

RESET ROLE;

-- The nonzero branch targets a source-authenticated action 6 that was
-- tombstoned before destination execution. It has no execution, ACK, or
-- action projection and therefore preserves terminal exclusion.
SELECT pg_temp.seed_tombstoned_disbursement(
    sha256(convert_to('cancel-nonzero-disbursement-message', 'UTF8')),
    'loan-cancel-nonzero', 305,
    sha256(convert_to('cancel-nonzero-tombstone', 'UTF8')),
    '2026-01-04 00:00:47+00', 1
);
SELECT pg_temp.seed_tombstoned_disbursement(
    sha256(convert_to('cancel-substituted-route-disbursement', 'UTF8')),
    'loan-cancel-nonzero', 306,
    sha256(convert_to('cancel-substituted-route-tombstone', 'UTF8')),
    '2026-01-04 00:00:48+00', 2
);

CREATE FUNCTION pg_temp.seed_conflicting_cancellation_journal(
    message_id_ bytea
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    INSERT INTO public.journal (
        journal_id, legal_entity_id, book_id, source_system,
        idempotency_key, correlation_id, evidence_hash, effective_at,
        status, entry_type, source_event_id
    ) VALUES (
        'crosschain:' || encode(message_id_, 'hex')
            || ':loan-cancellation-burn-control',
        'unified-protocol', 'cross-chain-subledger',
        'deliberately-conflicting-test-source',
        'crosschain:' || encode(message_id_, 'hex')
            || ':loan-cancellation-burn-control',
        'rollback-regression', repeat('00', 32),
        '2026-01-04 00:01:59+00', 'POSTED',
        'ROLLBACK_REGRESSION', 'rollback-regression'
    );
$function$;

SET ROLE unified_crosschain_runtime;

DO $cancellation$
DECLARE
    zero_bad_request bytea := sha256(convert_to('cancel-zero-bad-request', 'UTF8'));
    zero_request bytea := sha256(convert_to('cancel-zero-request', 'UTF8'));
    zero_completion bytea := sha256(convert_to('cancel-zero-completion', 'UTF8'));
    zero_generic bytea := sha256(convert_to('cancel-zero-generic-action14', 'UTF8'));
    zero_wrong_cause bytea := sha256(convert_to('cancel-zero-wrong-cause', 'UTF8'));
    nonzero_mismatch_request bytea :=
        sha256(convert_to('cancel-nonzero-mismatch-request', 'UTF8'));
    nonzero_route_substitution_request bytea :=
        sha256(convert_to('cancel-route-substitution-request', 'UTF8'));
    nonzero_executed_substitution_request bytea :=
        sha256(convert_to('cancel-executed-substitution-request', 'UTF8'));
    nonzero_wrong_cause_request bytea :=
        sha256(convert_to('cancel-nonzero-wrong-cause-request', 'UTF8'));
    nonzero_request bytea := sha256(convert_to('cancel-nonzero-request', 'UTF8'));
    nonzero_completion bytea := sha256(convert_to('cancel-nonzero-completion', 'UTF8'));
    zero_request_projection jsonb;
    zero_completion_projection jsonb;
    nonzero_request_projection jsonb;
    nonzero_completion_projection jsonb;
    nonzero_mismatch_projection jsonb;
    nonzero_route_substitution_projection jsonb;
    nonzero_executed_substitution_projection jsonb;
    nonzero_disbursement_message bytea :=
        sha256(convert_to('cancel-nonzero-disbursement-message', 'UTF8'));
    nonzero_tombstone bytea :=
        sha256(convert_to('cancel-nonzero-tombstone', 'UTF8'));
    substituted_route_disbursement bytea :=
        sha256(convert_to('cancel-substituted-route-disbursement', 'UTF8'));
    substituted_route_tombstone bytea :=
        sha256(convert_to('cancel-substituted-route-tombstone', 'UTF8'));
    executed_disbursement bytea :=
        sha256(convert_to('cancel-executed-disbursement', 'UTF8'));
    executed_substitution_tombstone bytea :=
        sha256(convert_to('cancel-executed-substitution-tombstone', 'UTF8'));
    zero_mint_message bytea :=
        sha256(convert_to('cancel-zero-mint-message', 'UTF8'));
    journals_before bigint;
    zero_source_transaction bytea :=
        sha256(convert_to('cancel-zero-source-burn', 'UTF8'));
    zero_source_evidence bytea :=
        sha256(convert_to('cancel-zero-source-evidence', 'UTF8'));
    zero_refund_transaction bytea :=
        sha256(convert_to('cancel-zero-refund', 'UTF8'));
    zero_refund_result bytea :=
        sha256(convert_to('cancel-zero-refund-result', 'UTF8'));
    nonzero_source_transaction bytea :=
        sha256(convert_to('cancel-nonzero-source-burn', 'UTF8'));
    nonzero_source_evidence bytea :=
        sha256(convert_to('cancel-nonzero-source-evidence', 'UTF8'));
    nonzero_refund_transaction bytea :=
        sha256(convert_to('cancel-nonzero-refund', 'UTF8'));
    nonzero_refund_result bytea :=
        sha256(convert_to('cancel-nonzero-refund-result', 'UTF8'));
BEGIN
    zero_request_projection := jsonb_build_object(
        'typed_action', 'LOAN_CANCELLATION_REQUESTED',
        'route_id', 'phase8-disbursement',
        'action_family_hash', '0x' || repeat('d1', 32),
        'source_component', repeat('e1', 20),
        'destination_component', repeat('e2', 20),
        'cancellation_id', 'cancel-zero',
        'loan_id', 'loan-cancel-zero',
        'funding_lock_id', 'lock-cancel-zero',
        'disbursement_message_id', repeat('00', 32),
        'disbursement_tombstone_hash', repeat('00', 32),
        'home_loan_account', repeat('f1', 20),
        'lender_address', repeat('a1', 20),
        'wrapped_token', repeat('a2', 20),
        'units', 100, 'policy_hash', repeat('f3', 32),
        'reason_code', repeat('a3', 32)
    );
    BEGIN
        PERFORM pg_temp.seed_cancellation_authority(
            zero_bad_request, 12, 305, decode(repeat('de', 32), 'hex'),
            decode(repeat('00', 32), 'hex'), zero_request_projection,
            sha256(convert_to('cancel-zero-bad-request-source', 'UTF8')), 305,
            sha256(convert_to('cancel-zero-bad-request-evidence', 'UTF8')),
            sha256(convert_to('cancel-zero-bad-request-destination', 'UTF8')),
            306,
            sha256(convert_to('cancel-zero-bad-request-result', 'UTF8')),
            '2026-01-04 00:00:55+00'
        );
        PERFORM crosschain.record_loan_cancellation_request(
            'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
            zero_bad_request, 'phase8-disbursement',
            decode(repeat('e1', 20), 'hex'),
            decode(repeat('e2', 20), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('f1', 20), 'hex'),
            decode(repeat('a1', 20), 'hex'),
            decode(repeat('a2', 20), 'hex'), 100,
            decode(repeat('f3', 32), 'hex'),
            decode(repeat('a3', 32), 'hex'),
            '2026-01-04 00:00:55+00'
        );
        RAISE EXCEPTION 'zero cancellation accepted wrong mint causation';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'zero cancellation accepted wrong mint causation' THEN
            RAISE;
        END IF;
    END;
    PERFORM pg_temp.seed_cancellation_authority(
        zero_request, 12, 305, decode(repeat('de', 32), 'hex'),
        zero_mint_message, zero_request_projection,
        sha256(convert_to('cancel-zero-request-source', 'UTF8')), 305,
        sha256(convert_to('cancel-zero-request-evidence', 'UTF8')),
        sha256(convert_to('cancel-zero-request-destination', 'UTF8')), 306,
        sha256(convert_to('cancel-zero-request-result', 'UTF8')),
        '2026-01-04 00:01:00+00'
    );
    SELECT count(*) INTO journals_before
    FROM ledger.bridge_journal_links;
    PERFORM crosschain.record_loan_cancellation_request(
        'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
        zero_request, 'phase8-disbursement',
        decode(repeat('e1', 20), 'hex'), decode(repeat('e2', 20), 'hex'),
        decode(repeat('00', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        decode(repeat('f1', 20), 'hex'), decode(repeat('a1', 20), 'hex'),
        decode(repeat('a2', 20), 'hex'), 100,
        decode(repeat('f3', 32), 'hex'), decode(repeat('a3', 32), 'hex'),
        '2026-01-04 00:01:00+00'
    );
    IF (SELECT count(*) FROM ledger.bridge_journal_links) <> journals_before THEN
        RAISE EXCEPTION 'action 12 posted economic journals';
    END IF;

    zero_completion_projection := jsonb_build_object(
        'typed_action', 'SATELLITE_FUNDING_CANCELLED',
        'route_id', 'phase8-report',
        'action_family_hash', '0x' || repeat('d2', 32),
        'source_component', repeat('e3', 20),
        'destination_component', repeat('e4', 20),
        'cancellation_id', 'cancel-zero',
        'loan_id', 'loan-cancel-zero',
        'funding_lock_id', 'lock-cancel-zero',
        'disbursement_message_id', repeat('00', 32),
        'disbursement_tombstone_hash', repeat('00', 32),
        'escrow_burn_result_hash', repeat('a4', 32),
        'home_loan_account', repeat('f1', 20),
        'lender_address', repeat('a1', 20),
        'wrapped_token', repeat('a2', 20),
        'units', 100, 'policy_hash', repeat('f3', 32),
        'source_burn_transaction_hash', encode(zero_source_transaction, 'hex'),
        'source_burn_log_index', 307,
        'source_burn_evidence_hash', encode(zero_source_evidence, 'hex'),
        'source_burn_finalized_at', '2026-01-04T00:02:00Z',
        'destination_refund_transaction_hash',
            encode(zero_refund_transaction, 'hex'),
        'destination_refund_log_index', 308,
        'destination_refund_result_hash', encode(zero_refund_result, 'hex'),
        'destination_refund_finalized_at', '2026-01-04T00:02:00Z'
    );
    -- This authority has production-shaped payload JSON but the wrong
    -- causation. Keep its seed and rejected call in one subtransaction so
    -- the globally unique projection hash remains available to the valid
    -- action-14 authority below.
    BEGIN
        PERFORM pg_temp.seed_cancellation_authority(
            zero_wrong_cause, 14, 308, decode(repeat('df', 32), 'hex'),
            decode(repeat('00', 32), 'hex'),
            zero_completion_projection,
            sha256(convert_to('cancel-wrong-cause-source', 'UTF8')), 311,
            sha256(convert_to('cancel-wrong-cause-evidence', 'UTF8')),
            sha256(convert_to('cancel-wrong-cause-destination', 'UTF8')),
            312,
            sha256(convert_to('cancel-wrong-cause-result', 'UTF8')),
            '2026-01-04 00:04:00+00'
        );
        PERFORM crosschain.commit_loan_cancellation_completion(
            'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
            zero_wrong_cause, 'phase8-report',
            decode(repeat('e3', 20), 'hex'),
            decode(repeat('e4', 20), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('a4', 32), 'hex'),
            decode(repeat('f1', 20), 'hex'),
            decode(repeat('a1', 20), 'hex'),
            decode(repeat('a2', 20), 'hex'), 100,
            decode(repeat('f3', 32), 'hex'),
            sha256(convert_to('cancel-wrong-cause-source', 'UTF8')), 311,
            sha256(convert_to('cancel-wrong-cause-evidence', 'UTF8')),
            '2026-01-04 00:04:00+00',
            sha256(convert_to('cancel-wrong-cause-destination', 'UTF8')),
            312,
            sha256(convert_to('cancel-wrong-cause-result', 'UTF8')),
            '2026-01-04 00:04:00+00'
        );
        RAISE EXCEPTION 'wrong causation authorized cancellation';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'wrong causation authorized cancellation' THEN
            RAISE;
        END IF;
    END;
    PERFORM pg_temp.seed_cancellation_authority(
        zero_completion, 14, 306, decode(repeat('df', 32), 'hex'),
        zero_request, zero_completion_projection,
        zero_source_transaction, 307, zero_source_evidence,
        zero_refund_transaction, 308, zero_refund_result,
        '2026-01-04 00:02:00+00'
    );
    -- Force a failure in the first journal after the completion row and both
    -- mutable states have changed. The nested subtransaction must restore
    -- every effect before the valid completion is attempted.
    BEGIN
        PERFORM pg_temp.seed_conflicting_cancellation_journal(zero_completion);
        PERFORM crosschain.commit_loan_cancellation_completion(
            'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
            zero_completion, 'phase8-report',
            decode(repeat('e3', 20), 'hex'),
            decode(repeat('e4', 20), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('a4', 32), 'hex'),
            decode(repeat('f1', 20), 'hex'),
            decode(repeat('a1', 20), 'hex'),
            decode(repeat('a2', 20), 'hex'), 100,
            decode(repeat('f3', 32), 'hex'),
            zero_source_transaction, 307, zero_source_evidence,
            '2026-01-04 00:02:00+00',
            zero_refund_transaction, 308, zero_refund_result,
            '2026-01-04 00:02:00+00'
        );
        RAISE EXCEPTION 'late journal conflict did not fail completion';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'late journal conflict did not fail completion' THEN
            RAISE;
        END IF;
    END;
    IF EXISTS (
        SELECT 1 FROM crosschain.loan_cancellation_completions
        WHERE cancellation_id = 'cancel-zero'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.loan_routes
        WHERE loan_id = 'loan-cancel-zero' AND lifecycle_state = 'RECOVERY'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.bridge_locks
        WHERE lock_id = 'lock-cancel-zero'
          AND status = 'MINTED' AND burned_units = 0 AND released_units = 0
    ) OR EXISTS (
        SELECT 1 FROM ledger.bridge_journal_links
        WHERE message_id = zero_completion
    ) THEN
        RAISE EXCEPTION 'failed cancellation completion was not atomic';
    END IF;
    -- Exercise the full zero-disbursement success and post-terminal replay
    -- path, then deliberately roll it back. This leaves a committed pending
    -- authority when the concurrency harness changes the outer ROLLBACK to
    -- COMMIT, allowing two sessions to race the first completion.
    BEGIN
        PERFORM crosschain.commit_loan_cancellation_completion(
        'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
        zero_completion, 'phase8-report',
        decode(repeat('e3', 20), 'hex'), decode(repeat('e4', 20), 'hex'),
        decode(repeat('00', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        decode(repeat('a4', 32), 'hex'),
        decode(repeat('f1', 20), 'hex'), decode(repeat('a1', 20), 'hex'),
        decode(repeat('a2', 20), 'hex'), 100,
        decode(repeat('f3', 32), 'hex'),
        zero_source_transaction, 307, zero_source_evidence,
        '2026-01-04 00:02:00+00',
        zero_refund_transaction, 308, zero_refund_result,
        '2026-01-04 00:02:00+00'
        );
        -- Exact request/completion replay occurs after terminal mutation.
        PERFORM crosschain.record_loan_cancellation_request(
        'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
        zero_request, 'phase8-disbursement',
        decode(repeat('e1', 20), 'hex'), decode(repeat('e2', 20), 'hex'),
        decode(repeat('00', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        decode(repeat('f1', 20), 'hex'), decode(repeat('a1', 20), 'hex'),
        decode(repeat('a2', 20), 'hex'), 100,
        decode(repeat('f3', 32), 'hex'), decode(repeat('a3', 32), 'hex'),
        '2026-01-04 00:01:00+00'
        );
        PERFORM crosschain.commit_loan_cancellation_completion(
        'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
        zero_completion, 'phase8-report',
        decode(repeat('e3', 20), 'hex'), decode(repeat('e4', 20), 'hex'),
        decode(repeat('00', 32), 'hex'), decode(repeat('00', 32), 'hex'),
        decode(repeat('a4', 32), 'hex'),
        decode(repeat('f1', 20), 'hex'), decode(repeat('a1', 20), 'hex'),
        decode(repeat('a2', 20), 'hex'), 100,
        decode(repeat('f3', 32), 'hex'),
        zero_source_transaction, 307, zero_source_evidence,
        '2026-01-04 00:02:00+00',
        zero_refund_transaction, 308, zero_refund_result,
        '2026-01-04 00:02:00+00'
        );
        BEGIN
            PERFORM crosschain.commit_loan_cancellation_completion(
            'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
            zero_completion, 'phase8-report',
            decode(repeat('e3', 20), 'hex'), decode(repeat('e4', 20), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('00', 32), 'hex'), decode(repeat('a4', 32), 'hex'),
            decode(repeat('f1', 20), 'hex'), decode(repeat('a1', 20), 'hex'),
            decode(repeat('a2', 20), 'hex'), 99,
            decode(repeat('f3', 32), 'hex'),
            zero_source_transaction, 307, zero_source_evidence,
            '2026-01-04 00:02:00+00',
            zero_refund_transaction, 308, zero_refund_result,
            '2026-01-04 00:02:00+00'
            );
            RAISE EXCEPTION 'changed cancellation completion was accepted';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM = 'changed cancellation completion was accepted' THEN
                RAISE;
            END IF;
        END;
        IF NOT EXISTS (
            SELECT 1 FROM crosschain.loan_cancellation_completions
            WHERE cancellation_id = 'cancel-zero'
        ) OR (
            SELECT count(*) FROM ledger.bridge_journal_links
            WHERE message_id = zero_completion
        ) <> 3 OR NOT EXISTS (
            SELECT 1 FROM crosschain.loan_routes
            WHERE loan_id = 'loan-cancel-zero'
              AND lifecycle_state = 'CANCELLED'
        ) THEN
            RAISE EXCEPTION
                'zero cancellation success/replay path is incomplete';
        END IF;
        RAISE EXCEPTION 'rollback zero completion after verification';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'rollback zero completion after verification' THEN
            RAISE;
        END IF;
    END;
    IF EXISTS (
        SELECT 1 FROM crosschain.loan_cancellation_completions
        WHERE cancellation_id = 'cancel-zero'
    ) OR EXISTS (
        SELECT 1 FROM ledger.bridge_journal_links
        WHERE message_id = zero_completion
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.loan_routes
        WHERE loan_id = 'loan-cancel-zero' AND lifecycle_state = 'RECOVERY'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.bridge_locks
        WHERE lock_id = 'lock-cancel-zero'
          AND status = 'MINTED' AND burned_units = 0 AND released_units = 0
    ) THEN
        RAISE EXCEPTION
            'zero cancellation fixture did not return to pending state';
    END IF;

    -- A generic action-14 projection and a wrong-causation action-14
    -- projection must both fail the SQL authority boundary.
    PERFORM pg_temp.seed_cancellation_authority(
        zero_generic, 14, 307, decode(repeat('df', 32), 'hex'),
        zero_request,
        zero_completion_projection ||
            jsonb_build_object('typed_action', 'SOURCE_COMPENSATED'),
        sha256(convert_to('cancel-generic-source', 'UTF8')), 309,
        sha256(convert_to('cancel-generic-evidence', 'UTF8')),
        sha256(convert_to('cancel-generic-destination', 'UTF8')), 310,
        sha256(convert_to('cancel-generic-result', 'UTF8')),
        '2026-01-04 00:03:00+00'
    );
    BEGIN
        PERFORM crosschain.commit_loan_cancellation_completion(
            'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
            zero_generic, 'phase8-report',
            decode(repeat('e3', 20), 'hex'), decode(repeat('e4', 20), 'hex'),
            decode(repeat('00', 32), 'hex'),
            decode(repeat('00', 32), 'hex'), decode(repeat('a4', 32), 'hex'),
            decode(repeat('f1', 20), 'hex'), decode(repeat('a1', 20), 'hex'),
            decode(repeat('a2', 20), 'hex'), 100,
            decode(repeat('f3', 32), 'hex'),
            sha256(convert_to('cancel-generic-source', 'UTF8')), 309,
            sha256(convert_to('cancel-generic-evidence', 'UTF8')),
            '2026-01-04 00:03:00+00',
            sha256(convert_to('cancel-generic-destination', 'UTF8')), 310,
            sha256(convert_to('cancel-generic-result', 'UTF8')),
            '2026-01-04 00:03:00+00'
        );
        RAISE EXCEPTION 'generic action 14 authorized cancellation';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'generic action 14 authorized cancellation' THEN
            RAISE;
        END IF;
    END;
    nonzero_request_projection := jsonb_build_object(
        'typed_action', 'LOAN_CANCELLATION_REQUESTED',
        'route_id', 'phase8-disbursement',
        'action_family_hash', '0x' || repeat('d1', 32),
        'source_component', repeat('e1', 20),
        'destination_component', repeat('e2', 20),
        'cancellation_id', 'cancel-nonzero',
        'loan_id', 'loan-cancel-nonzero',
        'funding_lock_id', 'lock-cancel-nonzero',
        'disbursement_message_id', encode(nonzero_disbursement_message, 'hex'),
        'disbursement_tombstone_hash', encode(nonzero_tombstone, 'hex'),
        'home_loan_account', repeat('f4', 20),
        'lender_address', repeat('a5', 20),
        'wrapped_token', repeat('a6', 20),
        'units', 100, 'policy_hash', repeat('f6', 32),
        'reason_code', repeat('a7', 32)
    );
    nonzero_mismatch_projection := jsonb_set(
        jsonb_set(
            nonzero_request_projection,
            '{disbursement_message_id}',
            to_jsonb(repeat('f5', 32))
        ),
        '{disbursement_tombstone_hash}',
        to_jsonb(repeat('a9', 32))
    );
    nonzero_route_substitution_projection := jsonb_set(
        jsonb_set(
            nonzero_request_projection,
            '{disbursement_message_id}',
            to_jsonb(encode(substituted_route_disbursement, 'hex'))
        ),
        '{disbursement_tombstone_hash}',
        to_jsonb(encode(substituted_route_tombstone, 'hex'))
    );
    BEGIN
        PERFORM pg_temp.seed_cancellation_authority(
            nonzero_route_substitution_request, 12, 308,
            decode(repeat('de', 32), 'hex'),
            substituted_route_disbursement,
            nonzero_route_substitution_projection,
            sha256(convert_to('cancel-route-substitution-source', 'UTF8')),
            313,
            sha256(convert_to('cancel-route-substitution-evidence', 'UTF8')),
            sha256(
                convert_to('cancel-route-substitution-destination', 'UTF8')
            ),
            314,
            sha256(convert_to('cancel-route-substitution-result', 'UTF8')),
            '2026-01-04 00:04:15+00'
        );
        PERFORM crosschain.record_loan_cancellation_request(
            'cancel-nonzero', 'loan-cancel-nonzero',
            'lock-cancel-nonzero', nonzero_route_substitution_request,
            'phase8-disbursement',
            decode(repeat('e1', 20), 'hex'),
            decode(repeat('e2', 20), 'hex'),
            substituted_route_disbursement, substituted_route_tombstone,
            decode(repeat('f4', 20), 'hex'),
            decode(repeat('a5', 20), 'hex'),
            decode(repeat('a6', 20), 'hex'), 100,
            decode(repeat('f6', 32), 'hex'),
            decode(repeat('a7', 32), 'hex'),
            '2026-01-04 00:04:15+00'
        );
        RAISE EXCEPTION 'substituted disbursement route was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'substituted disbursement route was accepted' THEN
            RAISE;
        END IF;
    END;
    nonzero_executed_substitution_projection := jsonb_set(
        jsonb_set(
            nonzero_request_projection,
            '{disbursement_message_id}',
            to_jsonb(encode(executed_disbursement, 'hex'))
        ),
        '{disbursement_tombstone_hash}',
        to_jsonb(encode(executed_substitution_tombstone, 'hex'))
    );
    BEGIN
        PERFORM pg_temp.seed_cancellation_authority(
            executed_disbursement, 6, 307,
            decode(repeat('de', 32), 'hex'),
            decode(repeat('00', 32), 'hex'),
            jsonb_build_object(
                'typed_action', 'DISBURSEMENT_EXECUTED',
                'loan_id', 'loan-cancel-nonzero'
            ),
            sha256(convert_to('cancel-executed-source', 'UTF8')), 313,
            sha256(convert_to('cancel-executed-evidence', 'UTF8')),
            sha256(convert_to('cancel-executed-destination', 'UTF8')), 314,
            sha256(convert_to('cancel-executed-result', 'UTF8')),
            '2026-01-04 00:04:20+00'
        );
        PERFORM pg_temp.seed_cancellation_authority(
            nonzero_executed_substitution_request, 12, 308,
            decode(repeat('de', 32), 'hex'),
            executed_disbursement,
            nonzero_executed_substitution_projection,
            sha256(convert_to('cancel-executed-request-source', 'UTF8')),
            315,
            sha256(convert_to('cancel-executed-request-evidence', 'UTF8')),
            sha256(
                convert_to('cancel-executed-request-destination', 'UTF8')
            ),
            316,
            sha256(convert_to('cancel-executed-request-result', 'UTF8')),
            '2026-01-04 00:04:25+00'
        );
        PERFORM crosschain.record_loan_cancellation_request(
            'cancel-nonzero', 'loan-cancel-nonzero',
            'lock-cancel-nonzero',
            nonzero_executed_substitution_request,
            'phase8-disbursement',
            decode(repeat('e1', 20), 'hex'),
            decode(repeat('e2', 20), 'hex'),
            executed_disbursement, executed_substitution_tombstone,
            decode(repeat('f4', 20), 'hex'),
            decode(repeat('a5', 20), 'hex'),
            decode(repeat('a6', 20), 'hex'), 100,
            decode(repeat('f6', 32), 'hex'),
            decode(repeat('a7', 32), 'hex'),
            '2026-01-04 00:04:25+00'
        );
        RAISE EXCEPTION 'executed action 6 substituted for tombstone';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'executed action 6 substituted for tombstone' THEN
            RAISE;
        END IF;
    END;
    PERFORM pg_temp.seed_cancellation_authority(
        nonzero_mismatch_request, 12, 309,
        decode(repeat('de', 32), 'hex'),
        decode(repeat('f5', 32), 'hex'), nonzero_mismatch_projection,
        sha256(convert_to('cancel-nonzero-mismatch-source', 'UTF8')), 313,
        sha256(convert_to('cancel-nonzero-mismatch-evidence', 'UTF8')),
        sha256(convert_to('cancel-nonzero-mismatch-destination', 'UTF8')),
        314, sha256(convert_to('cancel-nonzero-mismatch-result', 'UTF8')),
        '2026-01-04 00:04:30+00'
    );
    BEGIN
        PERFORM crosschain.record_loan_cancellation_request(
            'cancel-nonzero', 'loan-cancel-nonzero', 'lock-cancel-nonzero',
            nonzero_mismatch_request, 'phase8-disbursement',
            decode(repeat('e1', 20), 'hex'),
            decode(repeat('e2', 20), 'hex'),
            decode(repeat('f5', 32), 'hex'),
            decode(repeat('a9', 32), 'hex'),
            decode(repeat('f4', 20), 'hex'),
            decode(repeat('a5', 20), 'hex'),
            decode(repeat('a6', 20), 'hex'), 100,
            decode(repeat('f6', 32), 'hex'),
            decode(repeat('a7', 32), 'hex'),
            '2026-01-04 00:04:30+00'
        );
        RAISE EXCEPTION 'unrelated authorization and tombstone were paired';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'unrelated authorization and tombstone were paired' THEN
            RAISE;
        END IF;
    END;
    BEGIN
        PERFORM pg_temp.seed_cancellation_authority(
            nonzero_wrong_cause_request, 12, 310,
            decode(repeat('de', 32), 'hex'),
            decode(repeat('00', 32), 'hex'), nonzero_request_projection,
            sha256(convert_to('cancel-nonzero-wrong-cause-source', 'UTF8')),
            315,
            sha256(convert_to('cancel-nonzero-wrong-cause-evidence', 'UTF8')),
            sha256(
                convert_to('cancel-nonzero-wrong-cause-destination', 'UTF8')
            ),
            316,
            sha256(convert_to('cancel-nonzero-wrong-cause-result', 'UTF8')),
            '2026-01-04 00:04:45+00'
        );
        PERFORM crosschain.record_loan_cancellation_request(
            'cancel-nonzero', 'loan-cancel-nonzero',
            'lock-cancel-nonzero', nonzero_wrong_cause_request,
            'phase8-disbursement',
            decode(repeat('e1', 20), 'hex'),
            decode(repeat('e2', 20), 'hex'),
            nonzero_disbursement_message, nonzero_tombstone,
            decode(repeat('f4', 20), 'hex'),
            decode(repeat('a5', 20), 'hex'),
            decode(repeat('a6', 20), 'hex'), 100,
            decode(repeat('f6', 32), 'hex'),
            decode(repeat('a7', 32), 'hex'),
            '2026-01-04 00:04:45+00'
        );
        RAISE EXCEPTION 'nonzero cancellation accepted wrong causation';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'nonzero cancellation accepted wrong causation' THEN
            RAISE;
        END IF;
    END;
    PERFORM pg_temp.seed_cancellation_authority(
        nonzero_request, 12, 310, decode(repeat('de', 32), 'hex'),
        nonzero_disbursement_message, nonzero_request_projection,
        sha256(convert_to('cancel-nonzero-request-source', 'UTF8')), 313,
        sha256(convert_to('cancel-nonzero-request-evidence', 'UTF8')),
        sha256(convert_to('cancel-nonzero-request-destination', 'UTF8')), 314,
        sha256(convert_to('cancel-nonzero-request-result', 'UTF8')),
        '2026-01-04 00:05:00+00'
    );
    PERFORM crosschain.record_loan_cancellation_request(
        'cancel-nonzero', 'loan-cancel-nonzero', 'lock-cancel-nonzero',
        nonzero_request, 'phase8-disbursement',
        decode(repeat('e1', 20), 'hex'), decode(repeat('e2', 20), 'hex'),
        nonzero_disbursement_message, nonzero_tombstone,
        decode(repeat('f4', 20), 'hex'), decode(repeat('a5', 20), 'hex'),
        decode(repeat('a6', 20), 'hex'), 100,
        decode(repeat('f6', 32), 'hex'), decode(repeat('a7', 32), 'hex'),
        '2026-01-04 00:05:00+00'
    );
    nonzero_completion_projection := jsonb_build_object(
        'typed_action', 'SATELLITE_FUNDING_CANCELLED',
        'route_id', 'phase8-report',
        'action_family_hash', '0x' || repeat('d2', 32),
        'source_component', repeat('e3', 20),
        'destination_component', repeat('e4', 20),
        'cancellation_id', 'cancel-nonzero',
        'loan_id', 'loan-cancel-nonzero',
        'funding_lock_id', 'lock-cancel-nonzero',
        'disbursement_message_id', encode(nonzero_disbursement_message, 'hex'),
        'disbursement_tombstone_hash', encode(nonzero_tombstone, 'hex'),
        'escrow_burn_result_hash', repeat('a8', 32),
        'home_loan_account', repeat('f4', 20),
        'lender_address', repeat('a5', 20),
        'wrapped_token', repeat('a6', 20),
        'units', 100, 'policy_hash', repeat('f6', 32),
        'source_burn_transaction_hash',
            encode(nonzero_source_transaction, 'hex'),
        'source_burn_log_index', 315,
        'source_burn_evidence_hash', encode(nonzero_source_evidence, 'hex'),
        'source_burn_finalized_at', '2026-01-04T00:06:00Z',
        'destination_refund_transaction_hash',
            encode(nonzero_refund_transaction, 'hex'),
        'destination_refund_log_index', 316,
        'destination_refund_result_hash',
            encode(nonzero_refund_result, 'hex'),
        'destination_refund_finalized_at', '2026-01-04T00:06:00Z'
    );
    PERFORM pg_temp.seed_cancellation_authority(
        nonzero_completion, 14, 311, decode(repeat('df', 32), 'hex'),
        nonzero_request, nonzero_completion_projection,
        nonzero_source_transaction, 315, nonzero_source_evidence,
        nonzero_refund_transaction, 316, nonzero_refund_result,
        '2026-01-04 00:06:00+00'
    );
    PERFORM crosschain.commit_loan_cancellation_completion(
        'cancel-nonzero', 'loan-cancel-nonzero', 'lock-cancel-nonzero',
        nonzero_completion, 'phase8-report',
        decode(repeat('e3', 20), 'hex'), decode(repeat('e4', 20), 'hex'),
        nonzero_disbursement_message, nonzero_tombstone,
        decode(repeat('a8', 32), 'hex'),
        decode(repeat('f4', 20), 'hex'), decode(repeat('a5', 20), 'hex'),
        decode(repeat('a6', 20), 'hex'), 100,
        decode(repeat('f6', 32), 'hex'),
        nonzero_source_transaction, 315, nonzero_source_evidence,
        '2026-01-04 00:06:00+00',
        nonzero_refund_transaction, 316, nonzero_refund_result,
        '2026-01-04 00:06:00+00'
    );

    IF (
        SELECT count(*) FROM crosschain.loan_cancellation_requests
        WHERE cancellation_id IN ('cancel-zero', 'cancel-nonzero')
    ) <> 2 OR (
        SELECT count(*) FROM crosschain.loan_cancellation_completions
        WHERE cancellation_id IN ('cancel-zero', 'cancel-nonzero')
    ) <> 1 OR NOT EXISTS (
        SELECT 1 FROM crosschain.loan_routes
        WHERE loan_id = 'loan-cancel-zero' AND lifecycle_state = 'RECOVERY'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.loan_routes
        WHERE loan_id = 'loan-cancel-nonzero'
          AND lifecycle_state = 'CANCELLED'
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.bridge_locks
        WHERE lock_id = 'lock-cancel-zero' AND status = 'MINTED'
          AND burned_units = 0 AND released_units = 0
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.bridge_locks
        WHERE lock_id = 'lock-cancel-nonzero' AND status = 'COMPENSATED'
          AND burned_units = 100 AND released_units = 100
    ) THEN
        RAISE EXCEPTION 'cancellation terminal state is incomplete';
    END IF;
    IF EXISTS (
        SELECT message_id
        FROM ledger.bridge_journal_links
        WHERE message_id = nonzero_completion
        GROUP BY message_id
        HAVING count(*) <> 3
    ) OR (
        SELECT count(*) FROM ledger.bridge_journal_links
        WHERE message_id = nonzero_completion
    ) <> 3 OR EXISTS (
        SELECT 1 FROM ledger.bridge_journal_links
        WHERE message_id = zero_completion
    ) THEN
        RAISE EXCEPTION 'cancellation did not post exactly three reviewed pairs';
    END IF;
END;
$cancellation$;

RESET ROLE;

DO $cancellation_owner_assertions$
BEGIN
    IF EXISTS (
        SELECT link.message_id
        FROM ledger.bridge_journal_links AS link
        JOIN public.journal_entry AS debit
          ON debit.journal_id = link.journal_id AND debit.side = 'DEBIT'
        JOIN public.journal_entry AS credit
          ON credit.journal_id = link.journal_id AND credit.side = 'CREDIT'
        WHERE link.message_id =
            sha256(convert_to('cancel-nonzero-completion', 'UTF8'))
        GROUP BY link.message_id
        HAVING array_agg(
            debit.account_code || ':' || credit.account_code
            ORDER BY debit.account_code, credit.account_code
        ) <> ARRAY['2230:1410', '7160:9150', '9150:7150']::text[]
    ) THEN
        RAISE EXCEPTION 'cancellation journal account pairs are not exact';
    END IF;
    BEGIN
        UPDATE crosschain.loan_cancellation_completions
        SET lender_id = 'substituted-lender'
        WHERE cancellation_id = 'cancel-nonzero';
        RAISE EXCEPTION 'stored cancellation identity was mutable';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'stored cancellation identity was mutable'
           OR SQLERRM <> 'crosschain evidence is append-only' THEN
            RAISE;
        END IF;
    END;
END;
$cancellation_owner_assertions$;

UPDATE crosschain.signer_sets
SET status = 'COMPROMISED'
WHERE signer_set_hash = decode(repeat('60', 32), 'hex') AND version = 1;

SET ROLE unified_crosschain_runtime;
SELECT pg_temp.begin_test_message(decode(repeat('f3', 32), 'hex'), 255);
SELECT pg_temp.seed_source_finality(
    decode(repeat('f3', 32), 'hex'), decode(repeat('60', 32), 'hex'), 1
);

DO $test$
BEGIN
    BEGIN
        PERFORM crosschain.transition_message(
            decode(repeat('f3', 32), 'hex'), 2,
            'SOURCE_FINALIZING', 'SOURCE_FINAL', NULL,
            sha256(
                decode(repeat('f3', 32), 'hex')
                || convert_to('source-certificate-v1', 'UTF8')
            ),
            '2026-01-01 00:00:10+00'
        );
        RAISE EXCEPTION 'compromised pinned signer set was accepted';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'compromised pinned signer set was accepted' THEN
            RAISE;
        END IF;
    END;
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    expected_bridge_journals bigint;
BEGIN
    SELECT
        2 * (SELECT count(*) FROM crosschain.bridge_locks)
        + (SELECT count(*) FROM crosschain.wrapped_mints)
        + (SELECT count(*) FROM crosschain.wrapped_burns)
        + 2 * (SELECT count(*) FROM crosschain.canonical_releases)
        + 2 * (SELECT count(*) FROM crosschain.canonical_burns)
        + 3 * (SELECT count(*) FROM crosschain.loan_cancellation_completions)
    INTO expected_bridge_journals;
    IF (SELECT count(*) FROM ledger.bridge_journal_links) <>
       expected_bridge_journals THEN
        RAISE EXCEPTION 'bridge economic facts are not fully journal-linked';
    END IF;
    IF (SELECT count(*) FROM ledger.satellite_custody_links) <> 1
       OR (SELECT count(*) FROM ledger.satellite_settlement_links) <> 4
       OR (
           SELECT count(*)
           FROM ledger.crosschain_recovery_journal_links
           WHERE recovery_id = decode(repeat('a5', 32), 'hex')
       ) <> 2 THEN
        RAISE EXCEPTION 'satellite or compensation journal links are incomplete';
    END IF;
    IF (
        SELECT count(*)
        FROM public.journal
        WHERE source_system = 'cross-chain-coordinator'
    ) <> expected_bridge_journals + 7 THEN
        RAISE EXCEPTION 'unexpected Phase 8 journal cardinality';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM public.journal AS journal
        JOIN public.journal_balance AS balance
          ON balance.journal_id = journal.journal_id
        WHERE journal.source_system = 'cross-chain-coordinator'
          AND balance.debit_units <> balance.credit_units
    ) OR EXISTS (
        SELECT 1
        FROM public.journal AS journal
        WHERE journal.source_system = 'cross-chain-coordinator'
          AND (
              SELECT count(*)
              FROM public.journal_entry AS entry
              WHERE entry.journal_id = journal.journal_id
          ) <> 2
    ) THEN
        RAISE EXCEPTION 'Phase 8 journal is missing its exact balanced pair';
    END IF;
    IF EXISTS (
        SELECT journal_id FROM ledger.bridge_journal_links
        UNION ALL
        SELECT journal_id FROM ledger.satellite_custody_links
        UNION ALL
        SELECT journal_id FROM ledger.satellite_settlement_links
        UNION ALL
        SELECT journal_id FROM ledger.crosschain_recovery_journal_links
        EXCEPT
        SELECT journal_id FROM public.journal
    ) THEN
        RAISE EXCEPTION 'Phase 8 accounting link points to no posted journal';
    END IF;
END;
$test$;

ROLLBACK;
