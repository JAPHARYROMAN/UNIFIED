\set ON_ERROR_STOP on

BEGIN;

INSERT INTO payment_intent (
    payment_id,
    legal_entity_id,
    idempotency_key,
    correlation_id,
    payer_reference,
    loan_id,
    provider_id,
    rail,
    purpose,
    asset_id,
    units,
    expires_at,
    schema_version,
    created_at
) VALUES (
    'phase7c-sql-payment',
    'unified-protocol',
    'phase7c-sql-payment',
    'phase7c-sql-correlation',
    'borrower-sql',
    'loan-sql',
    'provider-sql',
    'BANK',
    'LOAN_REPAYMENT',
    'fiat-usd',
    1250,
    '2026-08-01T00:00:00Z',
    1,
    '2026-07-20T00:00:00Z'
);

INSERT INTO journal (
    journal_id,
    legal_entity_id,
    book_id,
    source_system,
    idempotency_key,
    correlation_id,
    evidence_hash,
    effective_at,
    status,
    entry_type,
    source_event_id,
    loan_id
) VALUES
    (
        'payment:phase7c-sql-payment:provisional',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-sql-payment:provisional',
        'phase7c-sql-correlation',
        'phase7c-provisional-evidence',
        '2026-07-21T00:00:00Z',
        'POSTED',
        'PAYMENT_PROVISIONAL',
        'provider-sql:provisional-event',
        'loan-sql'
    ),
    (
        'payment:phase7c-sql-payment:final',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-sql-payment:final',
        'phase7c-sql-correlation',
        'phase7c-final-evidence',
        '2026-07-22T00:00:00Z',
        'POSTED',
        'PAYMENT_FINAL',
        'provider-sql:final-event',
        'loan-sql'
    );

INSERT INTO journal_entry (
    journal_id,
    line_number,
    account_code,
    side,
    asset_id,
    units,
    party_id,
    loan_id
) VALUES
    (
        'payment:phase7c-sql-payment:provisional',
        1,
        '9140',
        'DEBIT',
        'fiat-usd',
        1250,
        'borrower-sql',
        'loan-sql'
    ),
    (
        'payment:phase7c-sql-payment:provisional',
        2,
        '9120',
        'CREDIT',
        'fiat-usd',
        1250,
        'borrower-sql',
        'loan-sql'
    ),
    (
        'payment:phase7c-sql-payment:final',
        1,
        '1100',
        'DEBIT',
        'fiat-usd',
        1250,
        'borrower-sql',
        'loan-sql'
    ),
    (
        'payment:phase7c-sql-payment:final',
        2,
        '9140',
        'CREDIT',
        'fiat-usd',
        1250,
        'borrower-sql',
        'loan-sql'
    );

INSERT INTO payment_state_event (
    event_id,
    payment_id,
    provider_id,
    provider_event_id,
    aggregate_version,
    from_status,
    to_status,
    asset_id,
    units,
    evidence_hash,
    journal_ids,
    occurred_at,
    received_at
) VALUES
    (
        'phase7c-state-processing',
        'phase7c-sql-payment',
        'provider-sql',
        'processing-event',
        2,
        'CREATED',
        'PROCESSING',
        'fiat-usd',
        1250,
        'processing-evidence',
        '{}',
        '2026-07-20T01:00:00Z',
        '2026-07-20T01:00:01Z'
    ),
    (
        'phase7c-state-provisional',
        'phase7c-sql-payment',
        'provider-sql',
        'provisional-event',
        3,
        'PROCESSING',
        'PROVISIONAL',
        'fiat-usd',
        1250,
        'provisional-evidence',
        ARRAY['payment:phase7c-sql-payment:provisional'],
        '2026-07-21T00:00:00Z',
        '2026-07-21T00:00:01Z'
    ),
    (
        'phase7c-state-final',
        'phase7c-sql-payment',
        'provider-sql',
        'final-event',
        4,
        'PROVISIONAL',
        'FINAL',
        'fiat-usd',
        1250,
        'final-evidence',
        ARRAY['payment:phase7c-sql-payment:final'],
        '2026-07-22T00:00:00Z',
        '2026-07-22T00:00:01Z'
    );

INSERT INTO payment_reconciliation_run (
    run_id,
    provider_id,
    asset_id,
    as_of,
    provider_snapshot_hash,
    ledger_snapshot_hash,
    expected_units,
    observed_units,
    difference_units,
    unmatched_items,
    status,
    owner,
    resolution_deadline
) VALUES (
    'phase7c-reconciliation',
    'provider-sql',
    'fiat-usd',
    '2026-07-23T00:00:00Z',
    'provider-snapshot',
    'ledger-snapshot',
    1250,
    1250,
    0,
    0,
    'MATCHED',
    'accounting-risk',
    '2026-07-30T00:00:00Z'
);

INSERT INTO payment_provider_statement_entry (
    run_id,
    entry_id,
    provider_id,
    provider_reference,
    payment_id,
    asset_id,
    units,
    statement_kind,
    occurred_at
) VALUES (
    'phase7c-reconciliation',
    'phase7c-statement',
    'provider-sql',
    'provider-reference-sql',
    'phase7c-sql-payment',
    'fiat-usd',
    1250,
    'SETTLED',
    '2026-07-22T00:00:00Z'
);

DO $$
BEGIN
    IF NOT create_canonical_coordinator_state(
        'phase7c-sql-payment',
        'phase7c-allocation',
        'phase7c-instruction-digest',
        4,
        'PREPARED',
        1,
        '{"state":"PREPARED","restart_fixture":true}'::jsonb,
        'phase7c-coordinator-prepared',
        '2026-07-24T00:00:00Z',
        '2026-07-24T00:00:00Z'
    ) THEN
        RAISE EXCEPTION 'initial coordinator state was not persisted';
    END IF;

    -- Exact restart replay is accepted without another history row.
    IF NOT create_canonical_coordinator_state(
        'phase7c-sql-payment',
        'phase7c-allocation',
        'phase7c-instruction-digest',
        4,
        'PREPARED',
        1,
        '{"state":"PREPARED","restart_fixture":true}'::jsonb,
        'phase7c-coordinator-prepared',
        '2026-07-24T00:00:00Z',
        '2026-07-24T00:00:00Z'
    ) THEN
        RAISE EXCEPTION 'exact coordinator restart replay was rejected';
    END IF;

    -- A stale writer cannot advance a different version.
    IF compare_and_swap_canonical_coordinator_state(
        'phase7c-sql-payment',
        'phase7c-allocation',
        'phase7c-instruction-digest',
        'PREPARED',
        0,
        'SUBMITTED',
        2,
        '{"state":"SUBMITTED","stale":true}'::jsonb,
        false,
        false,
        'phase7c-coordinator-stale',
        '2026-07-24T00:00:30Z'
    ) THEN
        RAISE EXCEPTION 'stale coordinator writer advanced durable state';
    END IF;

    IF claim_synthetic_payment_allocation(
        'phase7b-conflicting-claim',
        'phase7c-sql-payment',
        'phase7b-conflicting-allocation',
        4,
        'phase7b-conflicting-claim-digest',
        'phase7b-conflicting-evidence',
        '2026-07-24T00:00:00Z'
    ) <> 'CONFLICT' THEN
        RAISE EXCEPTION 'authoritative payment claim accepted both allocation modes';
    END IF;
END;
$$;

INSERT INTO canonicalization_eligibility (
    eligibility_id,
    claim_id,
    payment_id,
    loan_id,
    provider_id,
    provider_reference,
    payment_final_event_id,
    source_asset_id,
    source_units,
    target_asset_id,
    target_units,
    reconciliation_id,
    provider_statement_entry_id,
    original_provisional_journal_id,
    original_final_journal_id,
    finality_policy_hash,
    conversion_policy_hash,
    waterfall_policy_hash,
    policy_set_hash,
    reversal_deadline,
    eligible,
    evidence_hash,
    evaluated_at
) VALUES (
    'phase7c-eligibility',
    'phase7c:phase7c-allocation',
    'phase7c-sql-payment',
    'loan-sql',
    'provider-sql',
    'provider-reference-sql',
    'phase7c-state-final',
    'fiat-usd',
    1250,
    'usdc-mainnet',
    1250,
    'phase7c-reconciliation',
    'phase7c-statement',
    'payment:phase7c-sql-payment:provisional',
    'payment:phase7c-sql-payment:final',
    '0x1111111111111111111111111111111111111111111111111111111111111111',
    'conversion-policy',
    'waterfall-policy',
    'policy-set',
    '2026-07-23T00:00:00Z',
    true,
    'eligibility-evidence',
    '2026-07-24T00:00:00Z'
);

INSERT INTO canonicalization_plan (
    canonicalization_id,
    eligibility_id,
    claim_id,
    allocation_id,
    payment_id,
    loan_id,
    source_asset_id,
    source_units,
    target_asset_id,
    target_units,
    reconciliation_id,
    debt_before_units,
    principal_units,
    refundable_excess_units,
    debt_after_units,
    expected_state_nonce,
    finalizer_id,
    borrower_id,
    lender_id,
    target_chain_domain,
    chain_id,
    gateway_address,
    loan_account,
    target_token,
    accounting_attester_id,
    provider_id_hash,
    provider_reference_hash,
    reconciliation_commitment,
    original_journal_set_hash,
    conversion_policy_hash,
    finality_policy_hash,
    policy_set_hash,
    instruction_evidence_hash,
    journal_ref,
    provider_finalized_at,
    reversal_deadline,
    instruction_digest,
    accounting_attestation_hash,
    evidence_hash,
    prepared_at
) VALUES (
    'phase7c-canonicalization',
    'phase7c-eligibility',
    'phase7c:phase7c-allocation',
    'phase7c-allocation',
    'phase7c-sql-payment',
    'loan-sql',
    'fiat-usd',
    1250,
    'usdc-mainnet',
    1250,
    'phase7c-reconciliation',
    1000,
    1000,
    250,
    0,
    1,
    'finalizer-sql',
    'borrower-sql',
    'lender-sql',
    'evm:31337',
    31337,
    'gateway-sql',
    'loan-account-sql',
    'target-token-sql',
    'attester-sql',
    'provider-id-hash-sql',
    'provider-reference-hash-sql',
    'reconciliation-commitment-sql',
    'original-journal-set-hash-sql',
    'conversion-policy',
    '0x1111111111111111111111111111111111111111111111111111111111111111',
    'policy-set',
    'eligibility-evidence',
    'journal-ref-sql',
    extract(epoch FROM timestamptz '2026-07-22T00:00:00Z')::bigint,
    extract(epoch FROM timestamptz '2026-07-23T00:00:00Z')::bigint,
    'phase7c-instruction-digest',
    'attestation-hash',
    'plan-evidence',
    '2026-07-24T00:00:00Z'
);

INSERT INTO canonicalization_submission (
    submission_id,
    canonicalization_id,
    attempt_number,
    state,
    target_chain_domain,
    gateway_address,
    sender_id,
    sender_nonce,
    calldata_hash,
    transaction_hash,
    evidence_hash,
    submitted_at
) VALUES (
    'phase7c-submission',
    'phase7c-canonicalization',
    1,
    'SUBMITTED',
    'evm:31337',
    'gateway-sql',
    'finalizer-sql',
    1,
    'calldata-hash',
    'transaction-hash',
    'submission-evidence',
    '2026-07-24T00:01:00Z'
);

DO $$
BEGIN
    IF NOT compare_and_swap_canonical_coordinator_state(
        'phase7c-sql-payment',
        'phase7c-allocation',
        'phase7c-instruction-digest',
        'PREPARED',
        1,
        'SUBMITTED',
        2,
        '{"state":"SUBMITTED","transaction_hash":"transaction-hash"}'::jsonb,
        false,
        false,
        'phase7c-coordinator-submitted',
        '2026-07-24T00:01:00Z'
    ) THEN
        RAISE EXCEPTION 'coordinator submission CAS failed';
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT compare_and_swap_canonical_coordinator_state(
        'phase7c-sql-payment',
        'phase7c-allocation',
        'phase7c-instruction-digest',
        'SUBMITTED',
        2,
        'CONFIRMED',
        3,
        jsonb_build_object(
            'Confirmation', jsonb_build_object(
                'PaymentID', 'phase7c-sql-payment',
                'AllocationID', 'phase7c-allocation',
                'LoanID', 'loan-sql',
                'ProviderID', 'provider-sql',
                'ProviderReference', 'provider-reference-sql',
                'SourceAssetID', 'fiat-usd',
                'TargetAssetID', 'usdc-mainnet',
                'TargetToken', 'target-token-sql',
                'Denomination', 'USD',
                'Precision', 6,
                'SourceUnits', '1250',
                'TargetUnits', '1250',
                'PrincipalUnits', '1000',
                'RefundableExcessUnits', '250',
                'DebtBeforeUnits', '1000',
                'DebtAfterUnits', '0',
                'ReconciliationID', 'phase7c-reconciliation',
                'ProviderIDHash', 'provider-id-hash-sql',
                'ProviderReferenceHash', 'provider-reference-hash-sql',
                'ReconciliationCommitment', 'reconciliation-commitment-sql',
                'OriginalJournalSetHash', 'original-journal-set-hash-sql',
                'FinalityPolicyHash',
                    '0x1111111111111111111111111111111111111111111111111111111111111111',
                'ConversionPolicyHash', 'conversion-policy',
                'PolicySetHash', 'policy-set',
                'EligibilityEvidenceHash', 'eligibility-evidence',
                'JournalRef', 'journal-ref-sql',
                'ProviderFinalizedAt',
                    extract(epoch FROM timestamptz '2026-07-22T00:00:00Z')::bigint,
                'ReversalDeadlineUnix',
                    extract(epoch FROM timestamptz '2026-07-23T00:00:00Z')::bigint,
                'OriginalJournalIDs', jsonb_build_array(
                    'payment:phase7c-sql-payment:provisional',
                    'payment:phase7c-sql-payment:final'
                ),
                'CorrelationID', 'phase7c-sql-correlation',
                'InstructionDigest', 'phase7c-instruction-digest',
                'ChainID', 31337,
                'Gateway', 'gateway-sql',
                'LoanAccount', 'loan-account-sql',
                'Finalizer', 'finalizer-sql',
                'Attester', 'attester-sql',
                'TransactionHash', 'transaction-hash'
            ) || jsonb_build_object(
                'EventID', 'gateway-event-sql',
                'LogIndex', 4,
                'BlockNumber', 100,
                'BlockHash', 'block-hash-sql',
                'TransactionIndex', 0,
                'ReceiptsRoot',
                    '0x2222222222222222222222222222222222222222222222222222222222222222',
                'InclusionProofHash',
                    '0x3333333333333333333333333333333333333333333333333333333333333333',
                'HeaderAuthorityHash',
                    '0x4444444444444444444444444444444444444444444444444444444444444444',
                'ReceiptHeaderSignatureHash',
                    '0x5555555555555555555555555555555555555555555555555555555555555555',
                'HeadHeaderSignatureHash',
                    '0x6666666666666666666666666666666666666666666666666666666666666666',
                'ConfirmationDepth', 12,
                'FinalityHeadBlock', 112,
                'FinalityHeadHash', 'finality-head-hash',
                'FinalityEvidenceHash', 'finality-evidence',
                'StateNonceBefore', 1,
                'StateNonceAfter', 3,
                'LenderID', 'lender-sql',
                'BorrowerID', 'borrower-sql',
                'EventEvidenceHash',
                    '0x9999999999999999999999999999999999999999999999999999999999999999',
                'GatewayPayloadHash', 'gateway-raw-payload-hash',
                'ConfirmedAt', '2026-07-24T00:15:00Z',
                'Incident', false
            )
        ),
        false,
        false,
        'phase7c-coordinator-confirmed',
        '2026-07-24T00:15:00Z'
    ) THEN
        RAISE EXCEPTION 'coordinator confirmation CAS failed';
    END IF;
END;
$$;

DO $$
DECLARE
    temporal_order_rejected boolean := false;
BEGIN
    BEGIN
        PERFORM commit_canonical_external_settlement(
            (
                SELECT snapshot->'Confirmation'
                FROM canonical_coordinator_state
                WHERE payment_id = 'phase7c-sql-payment'
            ),
            'conversion-evidence',
            '2026-07-24T00:00:30Z',
            'loan-subledger'
        );
    EXCEPTION WHEN OTHERS THEN
        temporal_order_rejected := true;
    END;
    IF NOT temporal_order_rejected
       OR EXISTS (
           SELECT 1
           FROM canonical_settlement_confirmation
           WHERE payment_id = 'phase7c-sql-payment'
       ) THEN
        RAISE EXCEPTION
            'canonical success accepted conversion before durable submission';
    END IF;
END;
$$;

-- The production accounting entry point creates the entire success batch in
-- one transaction. This first call represents a response lost after commit.
SELECT commit_canonical_external_settlement(
    (
        SELECT snapshot->'Confirmation'
        FROM canonical_coordinator_state
        WHERE payment_id = 'phase7c-sql-payment'
    ),
    'conversion-evidence',
    '2026-07-24T00:02:00Z',
    'loan-subledger'
);

INSERT INTO canonical_settlement_conversion (
    conversion_id,
    canonicalization_id,
    payment_id,
    provider_id,
    provider_reference,
    source_asset_id,
    source_units,
    target_asset_id,
    target_units,
    rate_numerator,
    rate_denominator,
    fee_units,
    slippage_units,
    rounding_units,
    source_account_code,
    original_provisional_journal_id,
    original_final_journal_id,
    finalizer_id,
    gateway_transaction_hash,
    provider_asset_irrevocably_acquired,
    later_reversal_risk_assumed,
    evidence_hash,
    converted_at
) VALUES (
    'conversion:phase7c-canonicalization',
    'phase7c-canonicalization',
    'phase7c-sql-payment',
    'provider-sql',
    'provider-reference-sql',
    'fiat-usd',
    1250,
    'usdc-mainnet',
    1250,
    1,
    1,
    0,
    0,
    0,
    '1100',
    'payment:phase7c-sql-payment:provisional',
    'payment:phase7c-sql-payment:final',
    'finalizer-sql',
    'transaction-hash',
    true,
    true,
    'conversion-evidence',
    '2026-07-24T00:02:00Z'
)
ON CONFLICT DO NOTHING;

INSERT INTO canonical_gateway_event_projection (
    gateway_event_id,
    payment_id,
    allocation_id,
    loan_id,
    instruction_digest,
    policy_set_hash,
    loan_account,
    finalizer_id,
    accounting_attester_id,
    source_asset_id,
    target_asset_id,
    target_token,
    source_units,
    gross_units,
    provider_id_hash,
    provider_reference_hash,
    reconciliation_id,
    reconciliation_commitment,
    original_journal_set_hash,
    conversion_policy_hash,
    finality_policy_hash,
    instruction_evidence_hash,
    journal_ref,
    provider_finalized_at,
    reversal_deadline,
    debt_before_units,
    principal_units,
    refundable_excess_units,
    debt_after_units,
    state_nonce_before,
    state_nonce_after,
    lender_id,
    borrower_id,
    chain_id,
    gateway_address,
    transaction_hash,
    log_index,
    block_hash,
    block_number,
    raw_payload_hash,
    confirmation_depth,
    finality_head_block,
    finality_head_hash,
    finality_evidence_hash,
    transaction_index,
    receipts_root,
    inclusion_proof_hash,
    header_authority_hash,
    receipt_header_signature_hash,
    head_header_signature_hash,
    finality_observed_at
) VALUES (
    'gateway-event-sql',
    'phase7c-sql-payment',
    'phase7c-allocation',
    'loan-sql',
    'phase7c-instruction-digest',
    'policy-set',
    'loan-account-sql',
    'finalizer-sql',
    'attester-sql',
    'fiat-usd',
    'usdc-mainnet',
    'target-token-sql',
    1250,
    1250,
    'provider-id-hash-sql',
    'provider-reference-hash-sql',
    'phase7c-reconciliation',
    'reconciliation-commitment-sql',
    'original-journal-set-hash-sql',
    'conversion-policy',
    '0x1111111111111111111111111111111111111111111111111111111111111111',
    'eligibility-evidence',
    'journal-ref-sql',
    extract(epoch FROM timestamptz '2026-07-22T00:00:00Z')::bigint,
    extract(epoch FROM timestamptz '2026-07-23T00:00:00Z')::bigint,
    1000,
    1000,
    250,
    0,
    1,
    3,
    'lender-sql',
    'borrower-sql',
    31337,
    'gateway-sql',
    'transaction-hash',
    4,
    'block-hash-sql',
    100,
    'gateway-raw-payload-hash',
    12,
    112,
    'finality-head-hash',
    'finality-evidence',
    0,
    '0x2222222222222222222222222222222222222222222222222222222222222222',
    '0x3333333333333333333333333333333333333333333333333333333333333333',
    '0x4444444444444444444444444444444444444444444444444444444444444444',
    '0x5555555555555555555555555555555555555555555555555555555555555555',
    '0x6666666666666666666666666666666666666666666666666666666666666666',
    '2026-07-24T00:15:00Z'
)
ON CONFLICT DO NOTHING;

-- An exact retry after response loss returns the already committed identities.
SELECT commit_canonical_external_settlement(
    (
        SELECT snapshot->'Confirmation'
        FROM canonical_coordinator_state
        WHERE payment_id = 'phase7c-sql-payment'
    ),
    'conversion-evidence',
    '2026-07-24T00:02:00Z',
    'loan-subledger'
);

DO $$
DECLARE
    conflicting_retry_rejected boolean := false;
BEGIN
    IF (
        SELECT count(*)
        FROM journal
        WHERE source_system = 'canonical-settlement'
          AND source_event_id = 'gateway-event-sql'
          AND reversal_of IS NULL
    ) <> 8
       OR (
           SELECT count(*)
           FROM journal_entry
           WHERE journal_id LIKE 'canonical:phase7c-canonicalization:%'
       ) <> 17
       OR (
           SELECT count(*)
           FROM canonical_settlement_journal_link
           WHERE confirmation_id = 'confirmation:phase7c-canonicalization'
       ) <> 8
       OR (
           SELECT count(*)
           FROM canonical_settlement_confirmation
           WHERE canonicalization_id = 'phase7c-canonicalization'
       ) <> 1
       OR (
           SELECT count(*)
           FROM canonical_settlement_conversion
           WHERE canonicalization_id = 'phase7c-canonicalization'
       ) <> 1
       OR (
           SELECT count(*)
           FROM canonical_lender_payout
           WHERE canonicalization_id = 'phase7c-canonicalization'
       ) <> 1
       OR (
           SELECT count(*)
           FROM canonical_borrower_refund
           WHERE canonicalization_id = 'phase7c-canonicalization'
       ) <> 1 THEN
        RAISE EXCEPTION
            'response-loss replay duplicated or omitted settlement accounting';
    END IF;

    BEGIN
        PERFORM commit_canonical_external_settlement(
            (
                SELECT snapshot->'Confirmation'
                FROM canonical_coordinator_state
                WHERE payment_id = 'phase7c-sql-payment'
            ),
            'changed-conversion-evidence',
            '2026-07-24T00:02:00Z',
            'loan-subledger'
        );
    EXCEPTION WHEN OTHERS THEN
        conflicting_retry_rejected := true;
    END;
    IF NOT conflicting_retry_rejected THEN
        RAISE EXCEPTION
            'canonical success accepted a conflicting retry after response loss';
    END IF;
END;
$$;

INSERT INTO canonical_settlement_confirmation (
    confirmation_id,
    canonicalization_id,
    submission_id,
    conversion_id,
    allocation_id,
    payment_id,
    loan_id,
    instruction_digest,
    borrower_id,
    lender_id,
    target_asset_id,
    target_units,
    principal_units,
    refundable_excess_units,
    debt_before_units,
    debt_after_units,
    transaction_hash,
    gateway_event_id,
    block_hash,
    block_number,
    log_index,
    chain_finality_depth,
    finality_head_block,
    finality_head_hash,
    finality_evidence_hash,
    transaction_index,
    receipts_root,
    inclusion_proof_hash,
    finality_policy_hash,
    header_authority_hash,
    receipt_header_signature_hash,
    head_header_signature_hash,
    journal_count,
    raw_payload_hash,
    confirmed_at
) VALUES (
    'confirmation:phase7c-canonicalization',
    'phase7c-canonicalization',
    'phase7c-submission',
    'conversion:phase7c-canonicalization',
    'phase7c-allocation',
    'phase7c-sql-payment',
    'loan-sql',
    'phase7c-instruction-digest',
    'borrower-sql',
    'lender-sql',
    'usdc-mainnet',
    1250,
    1000,
    250,
    1000,
    0,
    'transaction-hash',
    'gateway-event-sql',
    'block-hash-sql',
    100,
    4,
    12,
    112,
    'finality-head-hash',
    'finality-evidence',
    0,
    '0x2222222222222222222222222222222222222222222222222222222222222222',
    '0x3333333333333333333333333333333333333333333333333333333333333333',
    '0x1111111111111111111111111111111111111111111111111111111111111111',
    '0x4444444444444444444444444444444444444444444444444444444444444444',
    '0x5555555555555555555555555555555555555555555555555555555555555555',
    '0x6666666666666666666666666666666666666666666666666666666666666666',
    8,
    'gateway-raw-payload-hash',
    '2026-07-24T00:15:00Z'
)
ON CONFLICT DO NOTHING;

INSERT INTO journal (
    journal_id,
    legal_entity_id,
    book_id,
    source_system,
    idempotency_key,
    correlation_id,
    evidence_hash,
    effective_at,
    status,
    entry_type,
    source_event_id,
    loan_id
) VALUES
    ('canonical:phase7c-canonicalization:source-unallocated', 'unified-protocol',
     'settlement-subledger', 'canonical-settlement', 'phase7c:source-unallocated',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_SOURCE_CLEARED', 'gateway-event-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:source-converted', 'unified-protocol',
     'settlement-subledger', 'canonical-settlement', 'phase7c:source-converted',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_SOURCE_CONVERTED', 'gateway-event-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:target-custody', 'unified-protocol',
     'loan-subledger', 'canonical-settlement', 'phase7c:target-custody',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_TARGET_CUSTODY', 'gateway-event-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:target-unallocated', 'unified-protocol',
     'loan-subledger', 'canonical-settlement', 'phase7c:target-unallocated',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_TARGET_UNALLOCATED', 'gateway-event-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:allocation', 'unified-protocol',
     'loan-subledger', 'canonical-settlement', 'phase7c:allocation',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_PAYMENT_ALLOCATED', 'gateway-event-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:lender-claim', 'unified-protocol',
     'loan-subledger', 'canonical-settlement', 'phase7c:lender-claim',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_LENDER_CLAIM_ALLOCATED', 'gateway-event-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:lender-payout', 'unified-protocol',
     'loan-subledger', 'canonical-settlement', 'phase7c:lender-payout',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_LENDER_PAID', 'gateway-event-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:borrower-refund', 'unified-protocol',
     'loan-subledger', 'canonical-settlement', 'phase7c:borrower-refund',
     'phase7c-sql-correlation',
     '0x9999999999999999999999999999999999999999999999999999999999999999',
     '2026-07-24T00:15:00Z',
     'POSTED', 'CANONICAL_BORROWER_REFUNDED', 'gateway-event-sql', 'loan-sql')
ON CONFLICT DO NOTHING;

INSERT INTO journal_entry (
    journal_id,
    line_number,
    account_code,
    side,
    asset_id,
    units,
    party_id,
    loan_id
) VALUES
    ('canonical:phase7c-canonicalization:source-unallocated', 1, '9120', 'DEBIT',
     'fiat-usd', 1250, 'borrower-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:source-unallocated', 2, '9160', 'CREDIT',
     'fiat-usd', 1250, NULL, 'loan-sql'),
    ('canonical:phase7c-canonicalization:source-converted', 1, '9160', 'DEBIT',
     'fiat-usd', 1250, NULL, 'loan-sql'),
    ('canonical:phase7c-canonicalization:source-converted', 2, '1100', 'CREDIT',
     'fiat-usd', 1250, NULL, 'loan-sql'),
    ('canonical:phase7c-canonicalization:target-custody', 1, '1260', 'DEBIT',
     'usdc-mainnet', 1250, NULL, 'loan-sql'),
    ('canonical:phase7c-canonicalization:target-custody', 2, '9160', 'CREDIT',
     'usdc-mainnet', 1250, NULL, 'loan-sql'),
    ('canonical:phase7c-canonicalization:target-unallocated', 1, '9160', 'DEBIT',
     'usdc-mainnet', 1250, NULL, 'loan-sql'),
    ('canonical:phase7c-canonicalization:target-unallocated', 2, '9120', 'CREDIT',
     'usdc-mainnet', 1250, 'borrower-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:allocation', 1, '9120', 'DEBIT',
     'usdc-mainnet', 1250, NULL, 'loan-sql'),
    ('canonical:phase7c-canonicalization:allocation', 2, '1310', 'CREDIT',
     'usdc-mainnet', 1000, 'borrower-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:allocation', 3, '2150', 'CREDIT',
     'usdc-mainnet', 250, 'borrower-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:lender-claim', 1, '2310', 'DEBIT',
     'usdc-mainnet', 1000, 'lender-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:lender-claim', 2, '2130', 'CREDIT',
     'usdc-mainnet', 1000, 'lender-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:lender-payout', 1, '2130', 'DEBIT',
     'usdc-mainnet', 1000, 'lender-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:lender-payout', 2, '1260', 'CREDIT',
     'usdc-mainnet', 1000, 'lender-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:borrower-refund', 1, '2150', 'DEBIT',
     'usdc-mainnet', 250, 'borrower-sql', 'loan-sql'),
    ('canonical:phase7c-canonicalization:borrower-refund', 2, '1260', 'CREDIT',
     'usdc-mainnet', 250, 'borrower-sql', 'loan-sql')
ON CONFLICT DO NOTHING;

INSERT INTO canonical_settlement_journal_link (
    confirmation_id, ordinal, journal_role, journal_id
) VALUES
    ('confirmation:phase7c-canonicalization', 1, 'SOURCE_UNALLOCATED',
     'canonical:phase7c-canonicalization:source-unallocated'),
    ('confirmation:phase7c-canonicalization', 2, 'SOURCE_CONVERTED',
     'canonical:phase7c-canonicalization:source-converted'),
    ('confirmation:phase7c-canonicalization', 3, 'TARGET_CUSTODY',
     'canonical:phase7c-canonicalization:target-custody'),
    ('confirmation:phase7c-canonicalization', 4, 'TARGET_UNALLOCATED',
     'canonical:phase7c-canonicalization:target-unallocated'),
    ('confirmation:phase7c-canonicalization', 5, 'ALLOCATION',
     'canonical:phase7c-canonicalization:allocation'),
    ('confirmation:phase7c-canonicalization', 6, 'LENDER_CLAIM',
     'canonical:phase7c-canonicalization:lender-claim'),
    ('confirmation:phase7c-canonicalization', 7, 'LENDER_PAYOUT',
     'canonical:phase7c-canonicalization:lender-payout'),
    ('confirmation:phase7c-canonicalization', 8, 'BORROWER_REFUND',
     'canonical:phase7c-canonicalization:borrower-refund')
ON CONFLICT DO NOTHING;

INSERT INTO canonical_lender_payout (
    payout_id,
    confirmation_id,
    canonicalization_id,
    loan_id,
    lender_id,
    target_asset_id,
    units,
    transaction_hash,
    gateway_event_id,
    journal_id,
    evidence_hash,
    paid_at
) VALUES (
    'payout:phase7c-canonicalization',
    'confirmation:phase7c-canonicalization',
    'phase7c-canonicalization',
    'loan-sql',
    'lender-sql',
    'usdc-mainnet',
    1000,
    'transaction-hash',
    'gateway-event-sql',
    'canonical:phase7c-canonicalization:lender-payout',
    'gateway-raw-payload-hash',
    '2026-07-24T00:15:00Z'
)
ON CONFLICT DO NOTHING;

INSERT INTO canonical_borrower_refund (
    refund_id,
    confirmation_id,
    canonicalization_id,
    loan_id,
    borrower_id,
    target_asset_id,
    units,
    transaction_hash,
    gateway_event_id,
    journal_id,
    evidence_hash,
    refunded_at
) VALUES (
    'refund:phase7c-canonicalization',
    'confirmation:phase7c-canonicalization',
    'phase7c-canonicalization',
    'loan-sql',
    'borrower-sql',
    'usdc-mainnet',
    250,
    'transaction-hash',
    'gateway-event-sql',
    'canonical:phase7c-canonicalization:borrower-refund',
    'gateway-raw-payload-hash',
    '2026-07-24T00:15:00Z'
)
ON CONFLICT DO NOTHING;

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $$
BEGIN
    -- The coordinator owns the reorg identity and persists the opaque indexer
    -- evidence before accounting is allowed to compensate the finalized batch.
    IF NOT compare_and_swap_canonical_coordinator_state(
        'phase7c-sql-payment',
        'phase7c-allocation',
        'phase7c-instruction-digest',
        'CONFIRMED',
        3,
        'INCIDENT',
        4,
        jsonb_build_object(
            'Plan', jsonb_build_object('State', 'INCIDENT'),
            'Reorgs', jsonb_build_array(jsonb_build_object(
                'ReorgID', 'reorg:deep-reorg-envelope-evidence',
                'PaymentID', 'phase7c-sql-payment',
                'AllocationID', 'phase7c-allocation',
                'InstructionDigest', 'phase7c-instruction-digest',
                'ChainID', 31337,
                'Gateway', 'gateway-sql',
                'OrphanedEventID', 'gateway-event-sql',
                'OrphanedTxHash', 'transaction-hash',
                'OrphanedEventEvidenceHash',
                    '0x9999999999999999999999999999999999999999999999999999999999999999',
                'RawEvidenceHash', 'gateway-raw-payload-hash',
                'TransactionIndex', 0,
                'ReceiptsRoot',
                    '0x2222222222222222222222222222222222222222222222222222222222222222',
                'InclusionProofHash',
                    '0x3333333333333333333333333333333333333333333333333333333333333333',
                'OrphanedReceiptHeaderSignatureHash',
                    '0x5555555555555555555555555555555555555555555555555555555555555555',
                'OrphanedBlockHash', 'block-hash-sql',
                'OrphanedBlock', 100,
                'ReplacementBlockHash', 'replacement-block-hash-sql',
                'ReplacementBlock', 100,
                'DepthClass', 'DEEP_FINALITY',
                'ConfirmationDepth', 12,
                'DetectedHead', 112,
                'DetectedHeadHash', 'replacement-head-hash-sql',
                'FinalityPolicyHash',
                    '0x1111111111111111111111111111111111111111111111111111111111111111',
                'HeaderAuthorityHash',
                    '0x4444444444444444444444444444444444444444444444444444444444444444',
                'ReplacementHeaderSignatureHash',
                    '0x7777777777777777777777777777777777777777777777777777777777777777',
                'DetectedHeadHeaderSignatureHash',
                    '0x8888888888888888888888888888888888888888888888888888888888888888',
                'Deep', true,
                'CompensationRequired', true,
                'EvidenceHash', 'deep-reorg-envelope-evidence',
                'SubmissionSubmittedAt', '2026-07-24T00:01:00Z',
                'DetectedAt', '2026-07-25T00:00:00Z'
            ))
        ),
        false,
        false,
        'deep-reorg-envelope-evidence',
        '2026-07-25T00:00:00Z'
    ) THEN
        RAISE EXCEPTION 'coordinator reorg CAS failed';
    END IF;
END;
$$;

DO $$
DECLARE
    candidate_event_evidence text;
    rejected boolean;
BEGIN
    FOREACH candidate_event_evidence IN ARRAY
        ARRAY[
            '',
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        ]
    LOOP
        rejected := false;
        BEGIN
            PERFORM record_deep_canonical_settlement_compensation(
                'reorg:deep-reorg-envelope-evidence',
                'phase7c-compensation',
                'confirmation:phase7c-canonicalization',
                'phase7c-canonicalization',
                'phase7c-instruction-digest',
                31337,
                'gateway-sql',
                'transaction-hash',
                'gateway-event-sql',
                0,
                '0x2222222222222222222222222222222222222222222222222222222222222222',
                '0x3333333333333333333333333333333333333333333333333333333333333333',
                '0x1111111111111111111111111111111111111111111111111111111111111111',
                '0x4444444444444444444444444444444444444444444444444444444444444444',
                '0x5555555555555555555555555555555555555555555555555555555555555555',
                '0x6666666666666666666666666666666666666666666666666666666666666666',
                '0x7777777777777777777777777777777777777777777777777777777777777777',
                '0x8888888888888888888888888888888888888888888888888888888888888888',
                'block-hash-sql',
                100,
                'replacement-block-hash-sql',
                100,
                12,
                112,
                'replacement-head-hash-sql',
                candidate_event_evidence,
                'gateway-raw-payload-hash',
                'deep-reorg-envelope-evidence',
                '2026-07-24T00:01:00Z',
                'deep-reorg-compensation-evidence',
                'chain-operations',
                '2026-07-25T00:00:00Z',
                '2026-07-26T00:00:00Z'
            );
        EXCEPTION WHEN OTHERS THEN
            rejected := true;
        END;
        IF NOT rejected THEN
            RAISE EXCEPTION
                'deep compensation accepted omitted or mutated event evidence';
        END IF;
    END LOOP;
    IF EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg
        WHERE reorg_id = 'reorg:deep-reorg-envelope-evidence'
    ) THEN
        RAISE EXCEPTION
            'rejected event evidence left partial deep compensation state';
    END IF;
END;
$$;

SELECT record_deep_canonical_settlement_compensation(
    'reorg:deep-reorg-envelope-evidence',
    'phase7c-compensation',
    'confirmation:phase7c-canonicalization',
    'phase7c-canonicalization',
    'phase7c-instruction-digest',
    31337,
    'gateway-sql',
    'transaction-hash',
    'gateway-event-sql',
    0,
    '0x2222222222222222222222222222222222222222222222222222222222222222',
    '0x3333333333333333333333333333333333333333333333333333333333333333',
    '0x1111111111111111111111111111111111111111111111111111111111111111',
    '0x4444444444444444444444444444444444444444444444444444444444444444',
    '0x5555555555555555555555555555555555555555555555555555555555555555',
    '0x6666666666666666666666666666666666666666666666666666666666666666',
    '0x7777777777777777777777777777777777777777777777777777777777777777',
    '0x8888888888888888888888888888888888888888888888888888888888888888',
    'block-hash-sql',
    100,
    'replacement-block-hash-sql',
    100,
    12,
    112,
    'replacement-head-hash-sql',
    '0x9999999999999999999999999999999999999999999999999999999999999999',
    'gateway-raw-payload-hash',
    'deep-reorg-envelope-evidence',
    '2026-07-24T00:01:00Z',
    'deep-reorg-compensation-evidence',
    'chain-operations',
    '2026-07-25T00:00:00Z',
    '2026-07-26T00:00:00Z'
);

-- Exact retry must return the existing result without another incident or link.
SELECT record_deep_canonical_settlement_compensation(
    'reorg:deep-reorg-envelope-evidence',
    'phase7c-compensation',
    'confirmation:phase7c-canonicalization',
    'phase7c-canonicalization',
    'phase7c-instruction-digest',
    31337,
    'gateway-sql',
    'transaction-hash',
    'gateway-event-sql',
    0,
    '0x2222222222222222222222222222222222222222222222222222222222222222',
    '0x3333333333333333333333333333333333333333333333333333333333333333',
    '0x1111111111111111111111111111111111111111111111111111111111111111',
    '0x4444444444444444444444444444444444444444444444444444444444444444',
    '0x5555555555555555555555555555555555555555555555555555555555555555',
    '0x6666666666666666666666666666666666666666666666666666666666666666',
    '0x7777777777777777777777777777777777777777777777777777777777777777',
    '0x8888888888888888888888888888888888888888888888888888888888888888',
    'block-hash-sql',
    100,
    'replacement-block-hash-sql',
    100,
    12,
    112,
    'replacement-head-hash-sql',
    '0x9999999999999999999999999999999999999999999999999999999999999999',
    'gateway-raw-payload-hash',
    'deep-reorg-envelope-evidence',
    '2026-07-24T00:01:00Z',
    'deep-reorg-compensation-evidence',
    'chain-operations',
    '2026-07-25T00:00:00Z',
    '2026-07-26T00:00:00Z'
);

DO $$
DECLARE
    reversal_accepted boolean := false;
BEGIN
    IF (SELECT count(*) FROM canonical_settlement_reorg_journal_link
        WHERE compensation_id = 'phase7c-compensation') <> 8
       OR (SELECT count(*) FROM journal
           WHERE reversal_of IS NOT NULL
             AND source_event_id = 'gateway-event-sql'
             AND entry_type = 'CANONICAL_SETTLEMENT_REORG') <> 8
       OR (SELECT count(*) FROM canonical_settlement_incident
           WHERE reorg_id = 'reorg:deep-reorg-envelope-evidence'
             AND evidence_hash = 'deep-reorg-envelope-evidence') <> 1
       OR (SELECT count(*) FROM canonical_settlement_reorg_compensation
           WHERE compensation_id = 'phase7c-compensation'
             AND evidence_hash = 'deep-reorg-compensation-evidence') <> 1
       OR NOT EXISTS (
           SELECT 1
           FROM canonical_gateway_event_projection AS event
           JOIN canonical_settlement_confirmation AS confirmation
             ON confirmation.gateway_event_id = event.gateway_event_id
           JOIN canonical_settlement_reorg AS reorg
             ON reorg.confirmation_id = confirmation.confirmation_id
           WHERE event.gateway_event_id = 'gateway-event-sql'
             AND event.transaction_index = 0
             AND event.receipts_root =
                 '0x2222222222222222222222222222222222222222222222222222222222222222'
             AND event.inclusion_proof_hash =
                 '0x3333333333333333333333333333333333333333333333333333333333333333'
             AND event.finality_policy_hash =
                 '0x1111111111111111111111111111111111111111111111111111111111111111'
             AND event.header_authority_hash =
                 '0x4444444444444444444444444444444444444444444444444444444444444444'
             AND event.receipt_header_signature_hash =
                 '0x5555555555555555555555555555555555555555555555555555555555555555'
             AND event.head_header_signature_hash =
                 '0x6666666666666666666666666666666666666666666666666666666666666666'
             AND confirmation.transaction_index = event.transaction_index
             AND confirmation.receipts_root = event.receipts_root
             AND confirmation.inclusion_proof_hash =
                 event.inclusion_proof_hash
             AND confirmation.finality_policy_hash =
                 event.finality_policy_hash
             AND confirmation.header_authority_hash =
                 event.header_authority_hash
             AND confirmation.receipt_header_signature_hash =
                 event.receipt_header_signature_hash
             AND confirmation.head_header_signature_hash =
                 event.head_header_signature_hash
             AND reorg.orphaned_gateway_event_id = event.gateway_event_id
             AND reorg.transaction_index = event.transaction_index
             AND reorg.receipts_root = event.receipts_root
             AND reorg.inclusion_proof_hash = event.inclusion_proof_hash
             AND reorg.finality_policy_hash = event.finality_policy_hash
             AND reorg.header_authority_hash =
                 event.header_authority_hash
             AND reorg.orphaned_receipt_header_signature_hash =
                 event.receipt_header_signature_hash
             AND reorg.confirmation_head_header_signature_hash =
                 event.head_header_signature_hash
             AND reorg.replacement_header_signature_hash =
                 '0x7777777777777777777777777777777777777777777777777777777777777777'
             AND reorg.detected_head_header_signature_hash =
                 '0x8888888888888888888888888888888888888888888888888888888888888888'
             AND reorg.orphaned_event_evidence_hash =
                 '0x9999999999999999999999999999999999999999999999999999999999999999'
             AND reorg.orphaned_raw_payload_hash =
                 'gateway-raw-payload-hash'
             AND reorg.submission_submitted_at =
                 '2026-07-24T00:01:00Z'
       )
       OR NOT EXISTS (
           SELECT 1
           FROM canonical_coordinator_state
           WHERE payment_id = 'phase7c-sql-payment'
             AND state = 'INCIDENT'
             AND version = 4
             AND EXISTS (
                 SELECT 1
                 FROM jsonb_array_elements(snapshot->'Reorgs') AS stored_reorg
                 WHERE stored_reorg->>'ReorgID'
                     = 'reorg:deep-reorg-envelope-evidence'
                   AND stored_reorg->>'EvidenceHash'
                     = 'deep-reorg-envelope-evidence'
                   AND stored_reorg->>'OrphanedEventEvidenceHash'
                     = '0x9999999999999999999999999999999999999999999999999999999999999999'
                   AND stored_reorg->>'RawEvidenceHash'
                     = 'gateway-raw-payload-hash'
             )
       )
       OR (SELECT count(*) FROM canonical_coordinator_state_history
           WHERE payment_id = 'phase7c-sql-payment') <> 4
    THEN
        RAISE EXCEPTION 'atomic deep compensation did not persist exact durable evidence';
    END IF;

    -- Eligibility and Phase 7A reversal share the payment row lock. Once the
    -- canonical path is confirmed/incident, a concurrent reversal cannot slip in.
    BEGIN
        INSERT INTO payment_state_event (
            event_id,
            payment_id,
            provider_id,
            provider_event_id,
            aggregate_version,
            from_status,
            to_status,
            asset_id,
            units,
            evidence_hash,
            journal_ids,
            occurred_at,
            received_at
        ) VALUES (
            'phase7c-late-reversal',
            'phase7c-sql-payment',
            'provider-sql',
            'late-reversal-event',
            5,
            'FINAL',
            'REVERSED',
            'fiat-usd',
            1250,
            'late-reversal-evidence',
            '{}',
            '2026-07-25T01:00:00Z',
            '2026-07-25T01:00:01Z'
        );
        reversal_accepted := true;
    EXCEPTION
        WHEN OTHERS THEN reversal_accepted := false;
    END;
    IF reversal_accepted THEN
        RAISE EXCEPTION 'late Phase 7A reversal bypassed canonical serialization';
    END IF;
END;
$$;

-- Exercise the two reversal races that can occur before submission, plus the
-- shared synthetic/canonical claim latch used by Phase 7B and Phase 7C.
INSERT INTO payment_intent (
    payment_id,
    legal_entity_id,
    idempotency_key,
    correlation_id,
    payer_reference,
    loan_id,
    provider_id,
    rail,
    purpose,
    asset_id,
    units,
    expires_at,
    schema_version,
    created_at
) VALUES
    (
        'phase7c-synthetic-claim',
        'unified-protocol',
        'phase7c-synthetic-claim',
        'phase7c-synthetic-correlation',
        'synthetic-payer',
        'synthetic-loan',
        'provider-synthetic',
        'BANK',
        'LOAN_REPAYMENT',
        'fiat-usd',
        100,
        '2026-08-01T00:00:00Z',
        1,
        '2026-07-20T00:00:00Z'
    ),
    (
        'phase7c-prepared-reversal',
        'unified-protocol',
        'phase7c-prepared-reversal',
        'phase7c-prepared-correlation',
        'prepared-payer',
        'prepared-loan',
        'provider-prepared',
        'BANK',
        'LOAN_REPAYMENT',
        'fiat-usd',
        100,
        '2026-08-01T00:00:00Z',
        1,
        '2026-07-20T00:00:00Z'
    ),
    (
        'phase7c-failed-reversal',
        'unified-protocol',
        'phase7c-failed-reversal',
        'phase7c-failed-correlation',
        'failed-payer',
        'failed-loan',
        'provider-failed',
        'BANK',
        'LOAN_REPAYMENT',
        'fiat-usd',
        100,
        '2026-08-01T00:00:00Z',
        1,
        '2026-07-20T00:00:00Z'
    ),
    (
        'phase7c-submitted-reversal',
        'unified-protocol',
        'phase7c-submitted-reversal',
        'phase7c-submitted-correlation',
        'submitted-payer',
        'submitted-loan',
        'provider-submitted',
        'BANK',
        'LOAN_REPAYMENT',
        'fiat-usd',
        100,
        '2026-08-01T00:00:00Z',
        1,
        '2026-07-20T00:00:00Z'
    );

INSERT INTO journal (
    journal_id,
    legal_entity_id,
    book_id,
    source_system,
    idempotency_key,
    correlation_id,
    evidence_hash,
    effective_at,
    status,
    entry_type,
    source_event_id,
    loan_id,
    reversal_of,
    reversal_reason
) VALUES
    (
        'payment:phase7c-synthetic-claim:provisional',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-synthetic-claim:provisional',
        'phase7c-synthetic-correlation',
        'synthetic-provisional-evidence',
        '2026-07-21T00:00:00Z',
        'POSTED',
        'PAYMENT_PROVISIONAL',
        'synthetic-provisional-event',
        'synthetic-loan',
        NULL,
        NULL
    ),
    (
        'payment:phase7c-synthetic-claim:final',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-synthetic-claim:final',
        'phase7c-synthetic-correlation',
        'synthetic-final-evidence',
        '2026-07-22T00:00:00Z',
        'POSTED',
        'PAYMENT_FINAL',
        'synthetic-final-event',
        'synthetic-loan',
        NULL,
        NULL
    ),
    (
        'payment:phase7c-prepared-reversal:provisional',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-prepared-reversal:provisional',
        'phase7c-prepared-correlation',
        'prepared-provisional-evidence',
        '2026-07-21T00:00:00Z',
        'POSTED',
        'PAYMENT_PROVISIONAL',
        'prepared-provisional-event',
        'prepared-loan',
        NULL,
        NULL
    ),
    (
        'payment:phase7c-prepared-reversal:final',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-prepared-reversal:final',
        'phase7c-prepared-correlation',
        'prepared-final-evidence',
        '2026-07-22T00:00:00Z',
        'POSTED',
        'PAYMENT_FINAL',
        'prepared-final-event',
        'prepared-loan',
        NULL,
        NULL
    ),
    (
        'payment:phase7c-failed-reversal:provisional',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-failed-reversal:provisional',
        'phase7c-failed-correlation',
        'failed-provisional-evidence',
        '2026-07-21T00:00:00Z',
        'POSTED',
        'PAYMENT_PROVISIONAL',
        'failed-provisional-event',
        'failed-loan',
        NULL,
        NULL
    ),
    (
        'payment:phase7c-failed-reversal:final',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-failed-reversal:final',
        'phase7c-failed-correlation',
        'failed-final-evidence',
        '2026-07-22T00:00:00Z',
        'POSTED',
        'PAYMENT_FINAL',
        'failed-final-event',
        'failed-loan',
        NULL,
        NULL
    ),
    (
        'payment:phase7c-submitted-reversal:provisional',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-submitted-reversal:provisional',
        'phase7c-submitted-correlation',
        'submitted-provisional-evidence',
        '2026-07-21T00:00:00Z',
        'POSTED',
        'PAYMENT_PROVISIONAL',
        'submitted-provisional-event',
        'submitted-loan',
        NULL,
        NULL
    ),
    (
        'payment:phase7c-submitted-reversal:final',
        'unified-protocol',
        'settlement-subledger',
        'payment-orchestrator',
        'payment:phase7c-submitted-reversal:final',
        'phase7c-submitted-correlation',
        'submitted-final-evidence',
        '2026-07-22T00:00:00Z',
        'POSTED',
        'PAYMENT_FINAL',
        'submitted-final-event',
        'submitted-loan',
        NULL,
        NULL
    );

INSERT INTO journal_entry (
    journal_id,
    line_number,
    account_code,
    side,
    asset_id,
    units,
    party_id,
    loan_id
)
SELECT
    journal_id,
    line_number,
    account_code,
    side,
    'fiat-usd',
    100,
    party_id,
    loan_id
FROM (
    VALUES
        ('payment:phase7c-synthetic-claim:provisional', 1, '9140', 'DEBIT', 'synthetic-payer', 'synthetic-loan'),
        ('payment:phase7c-synthetic-claim:provisional', 2, '9120', 'CREDIT', 'synthetic-payer', 'synthetic-loan'),
        ('payment:phase7c-synthetic-claim:final', 1, '1100', 'DEBIT', 'synthetic-payer', 'synthetic-loan'),
        ('payment:phase7c-synthetic-claim:final', 2, '9140', 'CREDIT', 'synthetic-payer', 'synthetic-loan'),
        ('payment:phase7c-prepared-reversal:provisional', 1, '9140', 'DEBIT', 'prepared-payer', 'prepared-loan'),
        ('payment:phase7c-prepared-reversal:provisional', 2, '9120', 'CREDIT', 'prepared-payer', 'prepared-loan'),
        ('payment:phase7c-prepared-reversal:final', 1, '1100', 'DEBIT', 'prepared-payer', 'prepared-loan'),
        ('payment:phase7c-prepared-reversal:final', 2, '9140', 'CREDIT', 'prepared-payer', 'prepared-loan'),
        ('payment:phase7c-failed-reversal:provisional', 1, '9140', 'DEBIT', 'failed-payer', 'failed-loan'),
        ('payment:phase7c-failed-reversal:provisional', 2, '9120', 'CREDIT', 'failed-payer', 'failed-loan'),
        ('payment:phase7c-failed-reversal:final', 1, '1100', 'DEBIT', 'failed-payer', 'failed-loan'),
        ('payment:phase7c-failed-reversal:final', 2, '9140', 'CREDIT', 'failed-payer', 'failed-loan'),
        ('payment:phase7c-submitted-reversal:provisional', 1, '9140', 'DEBIT', 'submitted-payer', 'submitted-loan'),
        ('payment:phase7c-submitted-reversal:provisional', 2, '9120', 'CREDIT', 'submitted-payer', 'submitted-loan'),
        ('payment:phase7c-submitted-reversal:final', 1, '1100', 'DEBIT', 'submitted-payer', 'submitted-loan'),
        ('payment:phase7c-submitted-reversal:final', 2, '9140', 'CREDIT', 'submitted-payer', 'submitted-loan')
) AS lines(journal_id, line_number, account_code, side, party_id, loan_id);

INSERT INTO payment_state_event (
    event_id,
    payment_id,
    provider_id,
    provider_event_id,
    aggregate_version,
    from_status,
    to_status,
    asset_id,
    units,
    evidence_hash,
    journal_ids,
    occurred_at,
    received_at
) VALUES
    ('synthetic-processing', 'phase7c-synthetic-claim', 'provider-synthetic',
     'synthetic-processing-event', 2, 'CREATED', 'PROCESSING', 'fiat-usd', 100,
     'synthetic-processing-evidence', '{}', '2026-07-20T01:00:00Z', '2026-07-20T01:00:01Z'),
    ('synthetic-provisional', 'phase7c-synthetic-claim', 'provider-synthetic',
     'synthetic-provisional-event', 3, 'PROCESSING', 'PROVISIONAL', 'fiat-usd', 100,
     'synthetic-provisional-evidence', ARRAY['payment:phase7c-synthetic-claim:provisional'],
     '2026-07-21T00:00:00Z', '2026-07-21T00:00:01Z'),
    ('synthetic-final', 'phase7c-synthetic-claim', 'provider-synthetic',
     'synthetic-final-event', 4, 'PROVISIONAL', 'FINAL', 'fiat-usd', 100,
     'synthetic-final-evidence', ARRAY['payment:phase7c-synthetic-claim:final'],
     '2026-07-22T00:00:00Z', '2026-07-22T00:00:01Z'),
    ('prepared-processing', 'phase7c-prepared-reversal', 'provider-prepared',
     'prepared-processing-event', 2, 'CREATED', 'PROCESSING', 'fiat-usd', 100,
     'prepared-processing-evidence', '{}', '2026-07-20T01:00:00Z', '2026-07-20T01:00:01Z'),
    ('prepared-provisional', 'phase7c-prepared-reversal', 'provider-prepared',
     'prepared-provisional-event', 3, 'PROCESSING', 'PROVISIONAL', 'fiat-usd', 100,
     'prepared-provisional-evidence', ARRAY['payment:phase7c-prepared-reversal:provisional'],
     '2026-07-21T00:00:00Z', '2026-07-21T00:00:01Z'),
    ('prepared-final', 'phase7c-prepared-reversal', 'provider-prepared',
     'prepared-final-event', 4, 'PROVISIONAL', 'FINAL', 'fiat-usd', 100,
     'prepared-final-evidence', ARRAY['payment:phase7c-prepared-reversal:final'],
     '2026-07-22T00:00:00Z', '2026-07-22T00:00:01Z'),
    ('failed-processing', 'phase7c-failed-reversal', 'provider-failed',
     'failed-processing-event', 2, 'CREATED', 'PROCESSING', 'fiat-usd', 100,
     'failed-processing-evidence', '{}', '2026-07-20T01:00:00Z', '2026-07-20T01:00:01Z'),
    ('failed-provisional', 'phase7c-failed-reversal', 'provider-failed',
     'failed-provisional-event', 3, 'PROCESSING', 'PROVISIONAL', 'fiat-usd', 100,
     'failed-provisional-evidence', ARRAY['payment:phase7c-failed-reversal:provisional'],
     '2026-07-21T00:00:00Z', '2026-07-21T00:00:01Z'),
    ('failed-final', 'phase7c-failed-reversal', 'provider-failed',
     'failed-final-event', 4, 'PROVISIONAL', 'FINAL', 'fiat-usd', 100,
     'failed-final-evidence', ARRAY['payment:phase7c-failed-reversal:final'],
     '2026-07-22T00:00:00Z', '2026-07-22T00:00:01Z'),
    ('submitted-processing', 'phase7c-submitted-reversal', 'provider-submitted',
     'submitted-processing-event', 2, 'CREATED', 'PROCESSING', 'fiat-usd', 100,
     'submitted-processing-evidence', '{}', '2026-07-20T01:00:00Z', '2026-07-20T01:00:01Z'),
    ('submitted-provisional', 'phase7c-submitted-reversal', 'provider-submitted',
     'submitted-provisional-event', 3, 'PROCESSING', 'PROVISIONAL', 'fiat-usd', 100,
     'submitted-provisional-evidence', ARRAY['payment:phase7c-submitted-reversal:provisional'],
     '2026-07-21T00:00:00Z', '2026-07-21T00:00:01Z'),
    ('submitted-final', 'phase7c-submitted-reversal', 'provider-submitted',
     'submitted-final-event', 4, 'PROVISIONAL', 'FINAL', 'fiat-usd', 100,
     'submitted-final-evidence', ARRAY['payment:phase7c-submitted-reversal:final'],
     '2026-07-22T00:00:00Z', '2026-07-22T00:00:01Z');

DO $$
BEGIN
    IF claim_synthetic_payment_allocation(
        'phase7b:synthetic-allocation',
        'phase7c-synthetic-claim',
        'synthetic-allocation',
        4,
        'synthetic-full-claim-digest',
        'synthetic-claim-evidence',
        '2026-07-24T00:00:00Z'
    ) <> 'CREATED' OR claim_synthetic_payment_allocation(
        'phase7b:synthetic-allocation',
        'phase7c-synthetic-claim',
        'synthetic-allocation',
        4,
        'synthetic-full-claim-digest',
        'synthetic-claim-evidence',
        '2026-07-24T00:00:00Z'
    ) <> 'REPLAYED' THEN
        RAISE EXCEPTION 'synthetic allocation claim or exact replay failed';
    END IF;
    IF claim_synthetic_payment_allocation(
        'phase7b:synthetic-allocation',
        'phase7c-synthetic-claim',
        'synthetic-allocation',
        4,
        'changed-full-claim-digest',
        'synthetic-claim-evidence',
        '2026-07-24T00:00:00Z'
    ) <> 'CONFLICT' THEN
        RAISE EXCEPTION 'synthetic claim replay ignored changed allocation content';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim
        WHERE claim_id = 'phase7b:synthetic-allocation'
          AND claim_digest = 'synthetic-full-claim-digest'
          AND claim_digest_kind = 'FULL_V1'
    ) THEN
        RAISE EXCEPTION 'synthetic full claim digest was not durably classified';
    END IF;
    IF create_canonical_coordinator_state(
        'phase7c-synthetic-claim',
        'canonical-after-synthetic',
        'canonical-after-synthetic-digest',
        4,
        'PREPARED',
        1,
        '{"state":"PREPARED"}'::jsonb,
        'canonical-after-synthetic-evidence',
        '2026-07-24T00:00:00Z',
        '2026-07-24T00:00:00Z'
    ) THEN
        RAISE EXCEPTION 'canonical claim bypassed the synthetic claim latch';
    END IF;

END;
$$;

DO $$
DECLARE
    submitted_initial jsonb;
BEGIN
    submitted_initial := jsonb_build_object(
        'Plan', jsonb_build_object(
            'PaymentID', 'phase7c-submitted-reversal',
            'AllocationID', 'submitted-reversal-allocation',
            'InstructionDigest', 'submitted-reversal-digest',
            'State', 'PREPARED',
            'Version', 1,
            'Submission', jsonb_build_object(
                'ChainID', 0, 'Gateway', '', 'TransactionHash', ''
            )
        ),
        'Claim', jsonb_build_object(
            'PaymentID', 'phase7c-submitted-reversal',
            'AllocationID', 'submitted-reversal-allocation',
            'Digest', 'submitted-reversal-digest',
            'Mode', 'CANONICAL_GATEWAY',
            'State', 'PREPARED'
        ),
        'Tombstoned', false,
        'PendingReversal', NULL
    );
    IF NOT create_canonical_coordinator_state(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        4, 'PREPARED', 1, submitted_initial,
        'submitted-claim-evidence',
        '2026-07-24T00:00:00Z',
        '2026-07-24T00:00:00Z'
    ) THEN
        RAISE EXCEPTION 'submitted reversal fixture could not enter PREPARED';
    END IF;
END;
$$;

INSERT INTO payment_reconciliation_run (
    run_id, provider_id, asset_id, as_of, provider_snapshot_hash,
    ledger_snapshot_hash, expected_units, observed_units, difference_units,
    unmatched_items, status, owner, resolution_deadline
) VALUES (
    'submitted-reversal-reconciliation', 'provider-submitted', 'fiat-usd',
    '2026-07-24T00:00:00Z', 'submitted-provider-snapshot',
    'submitted-ledger-snapshot', 100, 100, 0, 0, 'MATCHED',
    'accounting-risk', '2026-07-30T00:00:00Z'
);

INSERT INTO payment_provider_statement_entry (
    run_id, entry_id, provider_id, provider_reference, payment_id,
    asset_id, units, statement_kind, occurred_at
) VALUES (
    'submitted-reversal-reconciliation', 'submitted-reversal-statement',
    'provider-submitted', 'submitted-provider-reference',
    'phase7c-submitted-reversal', 'fiat-usd', 100, 'SETTLED',
    '2026-07-22T00:00:00Z'
);

INSERT INTO canonicalization_eligibility (
    eligibility_id, claim_id, payment_id, loan_id, provider_id,
    provider_reference, payment_final_event_id, source_asset_id, source_units,
    target_asset_id, target_units, reconciliation_id,
    provider_statement_entry_id, original_provisional_journal_id,
    original_final_journal_id, finality_policy_hash, conversion_policy_hash,
    waterfall_policy_hash, policy_set_hash, reversal_deadline, eligible,
    evidence_hash, evaluated_at
) VALUES (
    'submitted-reversal-eligibility', 'phase7c:submitted-reversal-allocation',
    'phase7c-submitted-reversal', 'submitted-loan', 'provider-submitted',
    'submitted-provider-reference', 'submitted-final', 'fiat-usd', 100,
    'usdc-mainnet', 100, 'submitted-reversal-reconciliation',
    'submitted-reversal-statement',
    'payment:phase7c-submitted-reversal:provisional',
    'payment:phase7c-submitted-reversal:final',
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'submitted-conversion-policy',
    'submitted-waterfall-policy', 'submitted-policy-set',
    '2026-07-23T00:00:00Z', true, 'submitted-eligibility-evidence',
    '2026-07-24T00:00:00Z'
);

INSERT INTO canonicalization_plan (
    canonicalization_id, eligibility_id, claim_id, allocation_id, payment_id,
    loan_id, source_asset_id, source_units, target_asset_id, target_units,
    reconciliation_id, debt_before_units, principal_units,
    refundable_excess_units, debt_after_units, expected_state_nonce,
    finalizer_id, borrower_id, lender_id, target_chain_domain, chain_id,
    gateway_address, loan_account, target_token, accounting_attester_id,
    provider_id_hash, provider_reference_hash, reconciliation_commitment,
    original_journal_set_hash, conversion_policy_hash, finality_policy_hash,
    policy_set_hash, instruction_evidence_hash, journal_ref,
    provider_finalized_at, reversal_deadline, instruction_digest,
    accounting_attestation_hash, evidence_hash, prepared_at
) VALUES (
    'submitted-reversal-canonicalization', 'submitted-reversal-eligibility',
    'phase7c:submitted-reversal-allocation', 'submitted-reversal-allocation',
    'phase7c-submitted-reversal', 'submitted-loan', 'fiat-usd', 100,
    'usdc-mainnet', 100, 'submitted-reversal-reconciliation', 100, 100, 0, 0,
    1, 'finalizer-submitted', 'submitted-payer', 'submitted-lender',
    'evm:31337', 31337, 'gateway-submitted', 'submitted-loan-account',
    'submitted-target-token', 'submitted-attester', 'submitted-provider-hash',
    'submitted-provider-reference-hash', 'submitted-reconciliation-commitment',
    'submitted-original-journal-set', 'submitted-conversion-policy',
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'submitted-policy-set',
    'submitted-eligibility-evidence', 'submitted-journal-ref',
    extract(epoch FROM timestamptz '2026-07-22T00:00:00Z')::bigint,
    extract(epoch FROM timestamptz '2026-07-23T00:00:00Z')::bigint,
    'submitted-reversal-digest', 'submitted-attestation',
    'submitted-plan-evidence', '2026-07-24T00:00:00Z'
);

DO $$
DECLARE
    submitted_initial jsonb;
    submitted_state jsonb;
BEGIN
    SELECT snapshot
    INTO STRICT submitted_initial
    FROM canonical_coordinator_state
    WHERE payment_id = 'phase7c-submitted-reversal';

    submitted_state := jsonb_set(
        jsonb_set(
            jsonb_set(submitted_initial, '{Plan,State}', '"SUBMITTED"'),
            '{Plan,Version}', '2'
        ),
        '{Claim,State}', '"SUBMITTED"'
    );
    submitted_state := jsonb_set(
        submitted_state,
        '{Plan,Submission}',
        jsonb_build_object(
            'ChainID', 31337,
            'Gateway', 'gateway-submitted',
            'Sender', 'finalizer-submitted',
            'SenderNonce', 1,
            'TransactionHash', 'submitted-transaction-hash',
            'CalldataHash', 'submitted-calldata-hash',
            'SubmittedAt', '2026-07-24T00:10:00Z'
        )
    );
    IF NOT compare_and_swap_canonical_coordinator_state(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        'PREPARED', 1, 'SUBMITTED', 2, submitted_state,
        false, false, 'submitted-calldata-hash',
        '2026-07-24T00:10:00Z'
    ) THEN
        RAISE EXCEPTION 'submitted reversal fixture could not enter SUBMITTED';
    END IF;
END;
$$;

INSERT INTO canonicalization_submission (
    submission_id, canonicalization_id, attempt_number, state,
    target_chain_domain, gateway_address, sender_id, sender_nonce,
    calldata_hash, transaction_hash, evidence_hash, submitted_at
) VALUES (
    'submitted-reversal-submission', 'submitted-reversal-canonicalization',
    1, 'SUBMITTED', 'evm:31337', 'gateway-submitted', 'finalizer-submitted', 1,
    'submitted-calldata-hash', 'submitted-transaction-hash',
    'submitted-submission-evidence', '2026-07-24T00:10:00Z'
);

DO $$
DECLARE
    prepared_initial jsonb;
    prepared_pending jsonb;
    prepared_done jsonb;
    failed_initial jsonb;
    failed_state jsonb;
    failed_pending jsonb;
    failed_done jsonb;
    submitted_state jsonb;
    submitted_pending jsonb;
    submitted_done jsonb;
    ids text[];
    projection_accepted boolean := false;
    resolver_blocked boolean := false;
    invalid_origin_rejected boolean := false;
    mismatched_submission_rejected boolean := false;
    reversal_winner_rejected boolean := false;
    unauthorized_success_projection jsonb;
    submitted_success_rejected boolean := false;
    quarantined_success_rejected boolean := false;
BEGIN
    unauthorized_success_projection := jsonb_build_object(
        'PaymentID', 'phase7c-submitted-reversal',
        'AllocationID', 'submitted-reversal-allocation',
        'InstructionDigest', 'submitted-reversal-digest',
        'EventID', 'unauthorized-gateway-event',
        'TransactionHash', 'submitted-transaction-hash',
        'GatewayPayloadHash', 'unauthorized-payload',
        'FinalityEvidenceHash', 'unauthorized-finality',
        'TargetUnits', '100',
        'PrincipalUnits', '100',
        'RefundableExcessUnits', '0',
        'DebtBeforeUnits', '100',
        'DebtAfterUnits', '0',
        'BlockNumber', 100,
        'LogIndex', 1,
        'TransactionIndex', 0,
        'ConfirmationDepth', 12,
        'FinalityHeadBlock', 112,
        'StateNonceBefore', 1,
        'StateNonceAfter', 3,
        'ConfirmedAt', '2026-07-24T00:15:00Z',
        'Incident', false
    );
    BEGIN
        PERFORM commit_canonical_external_settlement(
            unauthorized_success_projection,
            'unauthorized-conversion-evidence',
            '2026-07-24T00:12:00Z',
            'loan-subledger'
        );
    EXCEPTION WHEN OTHERS THEN
        submitted_success_rejected := true;
    END;
    IF NOT submitted_success_rejected THEN
        RAISE EXCEPTION
            'canonical success accepted a durable SUBMITTED coordinator';
    END IF;

    prepared_initial := jsonb_build_object(
        'Plan', jsonb_build_object(
            'PaymentID', 'phase7c-prepared-reversal',
            'AllocationID', 'prepared-reversal-allocation',
            'InstructionDigest', 'prepared-reversal-digest',
            'State', 'PREPARED',
            'Version', 1,
            'Submission', jsonb_build_object(
                'ChainID', 0, 'Gateway', '', 'TransactionHash', ''
            )
        ),
        'Claim', jsonb_build_object(
            'PaymentID', 'phase7c-prepared-reversal',
            'AllocationID', 'prepared-reversal-allocation',
            'Digest', 'prepared-reversal-digest',
            'Mode', 'CANONICAL_GATEWAY',
            'State', 'PREPARED'
        ),
        'Tombstoned', false,
        'PendingReversal', NULL
    );
    prepared_pending := jsonb_set(
        jsonb_set(
            jsonb_set(prepared_initial, '{Plan,State}', '"QUARANTINED"'),
            '{Plan,Version}', '2'
        ),
        '{Claim,State}', '"QUARANTINED"'
    ) || jsonb_build_object(
        'PendingReversal', jsonb_build_object(
            'QuarantineID', 'prepared-reversal-quarantine',
            'ProviderID', 'provider-prepared',
            'ProviderEventID', 'prepared-reversal-event',
            'ProviderReference', 'prepared-provider-reference',
            'AssetID', 'fiat-usd',
            'Units', '100',
            'RawHash', 'prepared-raw-hash',
            'PaymentID', 'phase7c-prepared-reversal',
            'AllocationID', 'prepared-reversal-allocation',
            'InstructionDigest', 'prepared-reversal-digest',
            'CallbackEvidenceHash', 'prepared-reversal-evidence',
            'OccurredAt', '2026-07-24T00:29:00Z',
            'ReceivedAt', '2026-07-24T00:30:00Z'
        )
    );
    prepared_done := jsonb_set(
        jsonb_set(
            jsonb_set(prepared_pending, '{Plan,State}', '"FAILED"'),
            '{Plan,Version}', '3'
        ),
        '{Claim,State}', '"FAILED"'
    ) || jsonb_build_object('Tombstoned', true, 'PendingReversal', NULL);

    failed_initial := jsonb_build_object(
        'Plan', jsonb_build_object(
            'PaymentID', 'phase7c-failed-reversal',
            'AllocationID', 'failed-reversal-allocation',
            'InstructionDigest', 'failed-reversal-digest',
            'State', 'PREPARED',
            'Version', 1,
            'Submission', jsonb_build_object(
                'ChainID', 0, 'Gateway', '', 'TransactionHash', ''
            )
        ),
        'Claim', jsonb_build_object(
            'PaymentID', 'phase7c-failed-reversal',
            'AllocationID', 'failed-reversal-allocation',
            'Digest', 'failed-reversal-digest',
            'Mode', 'CANONICAL_GATEWAY',
            'State', 'PREPARED'
        ),
        'Tombstoned', false,
        'PendingReversal', NULL
    );
    failed_state := jsonb_set(
        jsonb_set(
            jsonb_set(failed_initial, '{Plan,State}', '"FAILED"'),
            '{Plan,Version}', '2'
        ),
        '{Claim,State}', '"FAILED"'
    );
    failed_pending := jsonb_set(
        jsonb_set(
            jsonb_set(failed_state, '{Plan,State}', '"QUARANTINED"'),
            '{Plan,Version}', '3'
        ),
        '{Claim,State}', '"QUARANTINED"'
    ) || jsonb_build_object(
        'PendingReversal', jsonb_build_object(
            'QuarantineID', 'failed-reversal-quarantine',
            'ProviderID', 'provider-failed',
            'ProviderEventID', 'failed-reversal-event',
            'ProviderReference', 'failed-provider-reference',
            'AssetID', 'fiat-usd',
            'Units', '100',
            'RawHash', 'failed-raw-hash',
            'PaymentID', 'phase7c-failed-reversal',
            'AllocationID', 'failed-reversal-allocation',
            'InstructionDigest', 'failed-reversal-digest',
            'CallbackEvidenceHash', 'failed-reversal-evidence',
            'OccurredAt', '2026-07-24T00:29:00Z',
            'ReceivedAt', '2026-07-24T00:30:00Z'
        )
    );
    failed_done := jsonb_set(
        jsonb_set(
            jsonb_set(failed_pending, '{Plan,State}', '"FAILED"'),
            '{Plan,Version}', '4'
        ),
        '{Claim,State}', '"FAILED"'
    ) || jsonb_build_object('Tombstoned', true, 'PendingReversal', NULL);

    SELECT snapshot
    INTO submitted_state
    FROM canonical_coordinator_state
    WHERE payment_id = 'phase7c-submitted-reversal';
    submitted_pending := jsonb_set(
        jsonb_set(
            jsonb_set(submitted_state, '{Plan,State}', '"QUARANTINED"'),
            '{Plan,Version}', '3'
        ),
        '{Claim,State}', '"QUARANTINED"'
    ) || jsonb_build_object(
        'PendingReversal', jsonb_build_object(
            'QuarantineID', 'submitted-reversal-quarantine',
            'ProviderID', 'provider-submitted',
            'ProviderEventID', 'submitted-reversal-event',
            'ProviderReference', 'submitted-provider-reference',
            'AssetID', 'fiat-usd',
            'Units', '100',
            'RawHash', 'submitted-raw-hash',
            'PaymentID', 'phase7c-submitted-reversal',
            'AllocationID', 'submitted-reversal-allocation',
            'InstructionDigest', 'submitted-reversal-digest',
            'CallbackEvidenceHash', 'submitted-reversal-evidence',
            'OriginState', 'SUBMITTED',
            'SubmissionChainID', 31337,
            'SubmissionGateway', 'gateway-submitted',
            'SubmissionTxHash', 'submitted-transaction-hash',
            'SubmissionSubmittedAt', '2026-07-24T00:10:00Z',
            'OccurredAt', '2026-07-24T00:29:00Z',
            'ReceivedAt', '2026-07-24T00:30:00Z'
        )
    );
    submitted_done := jsonb_set(
        jsonb_set(
            jsonb_set(submitted_pending, '{Plan,State}', '"FAILED"'),
            '{Plan,Version}', '4'
        ),
        '{Claim,State}', '"FAILED"'
    ) || jsonb_build_object('Tombstoned', true, 'PendingReversal', NULL);

    IF NOT create_canonical_coordinator_state(
        'phase7c-prepared-reversal',
        'prepared-reversal-allocation',
        'prepared-reversal-digest',
        4, 'PREPARED', 1, prepared_initial,
        'prepared-claim-evidence',
        '2026-07-24T00:00:00Z',
        '2026-07-24T00:00:00Z'
    ) OR NOT create_canonical_coordinator_state(
        'phase7c-failed-reversal',
        'failed-reversal-allocation',
        'failed-reversal-digest',
        4, 'PREPARED', 1, failed_initial,
        'failed-claim-evidence',
        '2026-07-24T00:00:00Z',
        '2026-07-24T00:00:00Z'
    ) THEN
        RAISE EXCEPTION 'canonical reversal fixture could not create claim and saga atomically';
    END IF;
    IF NOT compare_and_swap_canonical_coordinator_state(
        'phase7c-failed-reversal',
        'failed-reversal-allocation',
        'failed-reversal-digest',
        'PREPARED', 1, 'FAILED', 2, failed_state,
        false, false, 'canonical-failure-evidence',
        '2026-07-24T00:15:00Z'
    ) THEN
        RAISE EXCEPTION 'failed reversal fixture did not enter FAILED';
    END IF;

    IF EXISTS (SELECT 1 FROM payment_callback_quarantine
               WHERE payment_id IN (
                   'phase7c-prepared-reversal',
                   'phase7c-failed-reversal'
               ))
       OR EXISTS (SELECT 1 FROM payment_state_event
                  WHERE payment_id IN (
                      'phase7c-prepared-reversal',
                      'phase7c-failed-reversal'
                  ) AND to_status = 'REVERSED') THEN
        RAISE EXCEPTION 'reversal fixture relied on prerequisite manual rows';
    END IF;

    IF NOT quarantine_canonical_pending_reversal(
        'phase7c-prepared-reversal',
        'prepared-reversal-allocation',
        'prepared-reversal-digest',
        'PREPARED', 1, 2, prepared_pending,
        'prepared-reversal-quarantine',
        'provider-prepared', 'prepared-reversal-event',
        'prepared-raw-hash', 'prepared-reversal-evidence',
        '2026-07-24T00:29:00Z',
        '2026-07-24T00:30:00Z',
        '2026-07-25T00:30:00Z'
    ) OR NOT quarantine_canonical_pending_reversal(
        'phase7c-failed-reversal',
        'failed-reversal-allocation',
        'failed-reversal-digest',
        'FAILED', 2, 3, failed_pending,
        'failed-reversal-quarantine',
        'provider-failed', 'failed-reversal-event',
        'failed-raw-hash', 'failed-reversal-evidence',
        '2026-07-24T00:29:00Z',
        '2026-07-24T00:30:00Z',
        '2026-07-25T00:30:00Z'
    ) OR NOT quarantine_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        'SUBMITTED', 2, 3, submitted_pending,
        'submitted-reversal-quarantine',
        'provider-submitted', 'submitted-reversal-event',
        'submitted-raw-hash', 'submitted-reversal-evidence',
        '2026-07-24T00:29:00Z',
        '2026-07-24T00:30:00Z',
        '2026-07-25T00:30:00Z'
    ) THEN
        RAISE EXCEPTION 'atomic canonical reversal quarantine failed';
    END IF;

    BEGIN
        PERFORM commit_canonical_external_settlement(
            unauthorized_success_projection,
            'unauthorized-conversion-evidence',
            '2026-07-24T00:12:00Z',
            'loan-subledger'
        );
    EXCEPTION WHEN OTHERS THEN
        quarantined_success_rejected := true;
    END;
    IF NOT quarantined_success_rejected THEN
        RAISE EXCEPTION
            'canonical success accepted a durable QUARANTINED coordinator';
    END IF;

    -- Projection-first wins deterministically. The nested block deliberately
    -- rolls the accepted projection back so the same fixture can then exercise
    -- the reversal-first ordering.
    BEGIN
        INSERT INTO canonical_gateway_event_projection (
            gateway_event_id, payment_id, allocation_id, loan_id,
            instruction_digest, policy_set_hash, loan_account, finalizer_id,
            accounting_attester_id, source_asset_id, target_asset_id,
            target_token, source_units, gross_units, provider_id_hash,
            provider_reference_hash, reconciliation_id,
            reconciliation_commitment, original_journal_set_hash,
            conversion_policy_hash, finality_policy_hash,
            instruction_evidence_hash, journal_ref, provider_finalized_at,
            reversal_deadline, debt_before_units, principal_units,
            refundable_excess_units, debt_after_units, state_nonce_before,
            state_nonce_after, lender_id, borrower_id, chain_id,
            gateway_address, transaction_hash, log_index, block_hash,
            block_number, raw_payload_hash, confirmation_depth,
            finality_head_block, finality_head_hash, finality_evidence_hash,
            transaction_index, receipts_root, inclusion_proof_hash,
            header_authority_hash, receipt_header_signature_hash,
            head_header_signature_hash,
            finality_observed_at
        )
        SELECT
            'submitted-late-success-event', plan.payment_id,
            plan.allocation_id, plan.loan_id, plan.instruction_digest,
            plan.policy_set_hash, plan.loan_account, plan.finalizer_id,
            plan.accounting_attester_id, plan.source_asset_id,
            plan.target_asset_id, plan.target_token, plan.source_units,
            plan.target_units, plan.provider_id_hash,
            plan.provider_reference_hash, plan.reconciliation_id,
            plan.reconciliation_commitment, plan.original_journal_set_hash,
            plan.conversion_policy_hash, plan.finality_policy_hash,
            plan.instruction_evidence_hash, plan.journal_ref,
            plan.provider_finalized_at, plan.reversal_deadline,
            plan.debt_before_units, plan.principal_units,
            plan.refundable_excess_units, plan.debt_after_units,
            plan.expected_state_nonce, plan.expected_state_nonce + 1,
            plan.lender_id, plan.borrower_id, plan.chain_id,
            plan.gateway_address, 'submitted-transaction-hash', 0,
            'submitted-success-block-100', 100, 'submitted-success-raw',
            2, 102, 'submitted-success-head-102',
            'submitted-success-finality',
            0,
            '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
            '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            '2026-07-24T00:20:00Z'
        FROM canonicalization_plan AS plan
        WHERE plan.canonicalization_id = 'submitted-reversal-canonicalization';
        projection_accepted := true;
        resolver_blocked := resolve_canonical_pending_reversal(
            'phase7c-submitted-reversal',
            'submitted-reversal-allocation',
            'submitted-reversal-digest',
            3, 4, submitted_done,
            'submitted-reversal-quarantine',
            'submitted-reversal-resolution',
            'provider-submitted:submitted-reversal-event',
            'submitted-failure-evidence',
            'submitted-resolution-evidence',
            'payment-operations',
            '2026-07-24T01:15:00Z',
            'SUBMITTED',
            31337, 'gateway-submitted', 'submitted-transaction-hash',
            'submitted-receipt-payload', 'REVERTED', 100,
            'submitted-block-100', 2, 102, 'submitted-block-102',
            '2026-07-24T00:20:00Z',
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            0,
            '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        ) IS NULL;
        RAISE EXCEPTION 'ROLLBACK_ACCEPTED_PROJECTION_PROBE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'ROLLBACK_ACCEPTED_PROJECTION_PROBE' THEN
                RAISE;
            END IF;
    END;
    IF NOT projection_accepted OR NOT resolver_blocked THEN
        RAISE EXCEPTION 'projection-first winner semantics failed';
    END IF;

    BEGIN
        UPDATE canonical_coordinator_state
        SET snapshot = jsonb_set(
            snapshot,
            '{PendingReversal,OriginState}',
            '"PREPARED"'
        )
        WHERE payment_id = 'phase7c-submitted-reversal';
        INSERT INTO canonical_gateway_event_projection
        SELECT
            'submitted-invalid-origin-event', payment_id, allocation_id, loan_id,
            instruction_digest, policy_set_hash, loan_account, finalizer_id,
            accounting_attester_id, source_asset_id, target_asset_id,
            target_token, source_units, target_units, provider_id_hash,
            provider_reference_hash, reconciliation_id,
            reconciliation_commitment, original_journal_set_hash,
            conversion_policy_hash, finality_policy_hash,
            instruction_evidence_hash, journal_ref, provider_finalized_at,
            reversal_deadline, debt_before_units, principal_units,
            refundable_excess_units, debt_after_units, expected_state_nonce,
            expected_state_nonce + 1, lender_id, borrower_id, chain_id,
            gateway_address, 'submitted-transaction-hash', 0,
            'invalid-origin-block', 100, 'invalid-origin-raw', 2, 102,
            'invalid-origin-head', 'invalid-origin-finality',
            0,
            '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
            '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            '2026-07-24T00:20:00Z', clock_timestamp()
        FROM canonicalization_plan
        WHERE canonicalization_id = 'submitted-reversal-canonicalization';
        RAISE EXCEPTION 'INVALID_ORIGIN_WAS_ACCEPTED';
    EXCEPTION
        WHEN OTHERS THEN
            invalid_origin_rejected := SQLERRM <>
                'INVALID_ORIGIN_WAS_ACCEPTED';
    END;
    IF NOT invalid_origin_rejected THEN
        RAISE EXCEPTION 'PREPARED-origin quarantine accepted late success';
    END IF;

    BEGIN
        UPDATE canonical_coordinator_state
        SET snapshot = jsonb_set(
            snapshot,
            '{PendingReversal,SubmissionTxHash}',
            '"mismatched-stored-transaction"'
        )
        WHERE payment_id = 'phase7c-submitted-reversal';
        INSERT INTO canonical_gateway_event_projection
        SELECT
            'submitted-mismatch-event', payment_id, allocation_id, loan_id,
            instruction_digest, policy_set_hash, loan_account, finalizer_id,
            accounting_attester_id, source_asset_id, target_asset_id,
            target_token, source_units, target_units, provider_id_hash,
            provider_reference_hash, reconciliation_id,
            reconciliation_commitment, original_journal_set_hash,
            conversion_policy_hash, finality_policy_hash,
            instruction_evidence_hash, journal_ref, provider_finalized_at,
            reversal_deadline, debt_before_units, principal_units,
            refundable_excess_units, debt_after_units, expected_state_nonce,
            expected_state_nonce + 1, lender_id, borrower_id, chain_id,
            gateway_address, 'submitted-transaction-hash', 0,
            'mismatch-block', 100, 'mismatch-raw', 2, 102,
            'mismatch-head', 'mismatch-finality',
            0,
            '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
            '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            '2026-07-24T00:20:00Z', clock_timestamp()
        FROM canonicalization_plan
        WHERE canonicalization_id = 'submitted-reversal-canonicalization';
        RAISE EXCEPTION 'MISMATCHED_SUBMISSION_WAS_ACCEPTED';
    EXCEPTION
        WHEN OTHERS THEN
            mismatched_submission_rejected := SQLERRM <>
                'MISMATCHED_SUBMISSION_WAS_ACCEPTED';
    END;
    IF NOT mismatched_submission_rejected THEN
        RAISE EXCEPTION 'mismatched pending submission accepted late success';
    END IF;

    IF resolve_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        3, 4, submitted_done,
        'submitted-reversal-quarantine',
        'submitted-reversal-resolution',
        'provider-submitted:submitted-reversal-event',
        'submitted-failure-evidence',
        'submitted-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'SUBMITTED',
        31337, 'gateway-submitted', 'wrong-submitted-transaction',
        'submitted-receipt-payload', 'REVERTED', 100, 'submitted-block-100',
        2, 102, 'submitted-block-102', '2026-07-24T00:20:00Z',
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        0,
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'submitted resolver accepted mismatched transaction';
    END IF;
    IF resolve_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        3, 4, submitted_done,
        'submitted-reversal-quarantine',
        'submitted-reversal-resolution',
        'provider-submitted:submitted-reversal-event',
        'submitted-failure-evidence',
        'submitted-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'SUBMITTED',
        31337, 'gateway-submitted', 'submitted-transaction-hash',
        'submitted-receipt-payload', 'REVERTED', 100, 'submitted-block-100',
        2, 102, 'submitted-block-102', '2026-07-24T00:05:00Z',
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        0,
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'submitted resolver accepted proof observed before submission';
    END IF;
    IF resolve_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        3, 4, submitted_done,
        'submitted-reversal-quarantine',
        'submitted-reversal-resolution',
        'provider-submitted:submitted-reversal-event',
        'submitted-failure-evidence',
        'submitted-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'SUBMITTED',
        31337, 'gateway-submitted', 'submitted-transaction-hash',
        'submitted-receipt-payload', 'REVERTED', 100, 'submitted-block-100',
        2, 101, 'submitted-block-101', '2026-07-24T00:20:00Z',
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        0,
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'submitted resolver accepted insufficient finality';
    END IF;
    IF resolve_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        3, 4, submitted_done,
        'submitted-reversal-quarantine',
        'submitted-reversal-resolution',
        'provider-submitted:submitted-reversal-event',
        'submitted-failure-evidence',
        'submitted-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'SUBMITTED',
        31337, 'gateway-submitted', 'submitted-transaction-hash',
        'submitted-receipt-payload', 'REVERTED', 100, 'submitted-block-100',
        2, 102, 'submitted-block-102', '2026-07-24T00:20:00Z',
        '0x1111111111111111111111111111111111111111111111111111111111111111',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        0,
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'submitted resolver accepted mismatched finality policy';
    END IF;

    ids := resolve_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        3, 4, submitted_done,
        'submitted-reversal-quarantine',
        'submitted-reversal-resolution',
        'provider-submitted:submitted-reversal-event',
        'submitted-failure-evidence',
        'submitted-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'SUBMITTED',
        31337, 'gateway-submitted', 'submitted-transaction-hash',
        'submitted-receipt-payload', 'REVERTED', 100, 'submitted-block-100',
        2, 102, 'submitted-block-102', '2026-07-24T00:20:00Z',
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        0,
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    );
    IF ids <> ARRAY[
        'payment:phase7c-submitted-reversal:final-reversal',
        'payment:phase7c-submitted-reversal:provisional-reversal'
    ] THEN
        RAISE EXCEPTION 'submitted atomic resolver returned wrong journals: %', ids;
    END IF;
    IF resolve_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        3, 4, submitted_done,
        'submitted-reversal-quarantine',
        'submitted-reversal-resolution',
        'provider-submitted:submitted-reversal-event',
        'submitted-failure-evidence',
        'submitted-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'SUBMITTED',
        31337, 'gateway-submitted', 'submitted-transaction-hash',
        'submitted-receipt-payload', 'REVERTED', 100, 'submitted-block-100',
        2, 102, 'submitted-block-102', '2026-07-24T00:20:00Z',
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        0,
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    ) <> ARRAY[
        'payment:phase7c-submitted-reversal:final-reversal',
        'payment:phase7c-submitted-reversal:provisional-reversal'
    ] THEN
        RAISE EXCEPTION 'submitted exact resolver replay failed';
    END IF;
    IF resolve_canonical_pending_reversal(
        'phase7c-submitted-reversal',
        'submitted-reversal-allocation',
        'submitted-reversal-digest',
        3, 4, submitted_done,
        'submitted-reversal-quarantine',
        'submitted-reversal-resolution',
        'provider-submitted:submitted-reversal-event',
        'submitted-failure-evidence',
        'submitted-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'SUBMITTED',
        31337, 'gateway-submitted', 'submitted-transaction-hash',
        'submitted-receipt-payload', 'REVERTED', 100, 'submitted-block-100',
        2, 102, 'submitted-block-102', '2026-07-24T00:20:00Z',
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        0,
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        '0x1111111111111111111111111111111111111111111111111111111111111111'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'submitted exact replay ignored changed inclusion proof';
    END IF;
    BEGIN
        INSERT INTO canonical_gateway_event_projection
        SELECT
            'submitted-after-reversal-event', payment_id, allocation_id, loan_id,
            instruction_digest, policy_set_hash, loan_account, finalizer_id,
            accounting_attester_id, source_asset_id, target_asset_id,
            target_token, source_units, target_units, provider_id_hash,
            provider_reference_hash, reconciliation_id,
            reconciliation_commitment, original_journal_set_hash,
            conversion_policy_hash, finality_policy_hash,
            instruction_evidence_hash, journal_ref, provider_finalized_at,
            reversal_deadline, debt_before_units, principal_units,
            refundable_excess_units, debt_after_units, expected_state_nonce,
            expected_state_nonce + 1, lender_id, borrower_id, chain_id,
            gateway_address, 'submitted-transaction-hash', 0,
            'post-reversal-block', 100, 'post-reversal-raw', 2, 102,
            'post-reversal-head', 'post-reversal-finality',
            0,
            '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
            '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
            '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            '2026-07-24T00:20:00Z', clock_timestamp()
        FROM canonicalization_plan
        WHERE canonicalization_id = 'submitted-reversal-canonicalization';
    EXCEPTION
        WHEN OTHERS THEN reversal_winner_rejected := true;
    END;
    IF NOT reversal_winner_rejected THEN
        RAISE EXCEPTION 'reversal winner allowed late canonical projection';
    END IF;

    ids := resolve_canonical_pending_reversal(
        'phase7c-prepared-reversal',
        'prepared-reversal-allocation',
        'prepared-reversal-digest',
        2, 3, prepared_done,
        'prepared-reversal-quarantine',
        'prepared-reversal-resolution',
        'provider-prepared:prepared-reversal-event',
        'prepared-canonical-failure',
        'prepared-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'PREPARED',
        NULL, NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL
    );
    IF ids <> ARRAY[
        'payment:phase7c-prepared-reversal:final-reversal',
        'payment:phase7c-prepared-reversal:provisional-reversal'
    ] THEN
        RAISE EXCEPTION 'prepared atomic resolver returned wrong journals: %', ids;
    END IF;

    ids := resolve_canonical_pending_reversal(
        'phase7c-prepared-reversal',
        'prepared-reversal-allocation',
        'prepared-reversal-digest',
        2, 3, prepared_done,
        'prepared-reversal-quarantine',
        'prepared-reversal-resolution',
        'provider-prepared:prepared-reversal-event',
        'prepared-canonical-failure',
        'prepared-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'PREPARED',
        NULL, NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL
    );
    IF ids <> ARRAY[
        'payment:phase7c-prepared-reversal:final-reversal',
        'payment:phase7c-prepared-reversal:provisional-reversal'
    ] THEN
        RAISE EXCEPTION 'exact resolver replay did not return original journals: %', ids;
    END IF;
    IF resolve_canonical_pending_reversal(
        'phase7c-prepared-reversal',
        'prepared-reversal-allocation',
        'prepared-reversal-digest',
        2, 3, prepared_done,
        'prepared-reversal-quarantine',
        'prepared-reversal-resolution',
        'provider-prepared:prepared-reversal-event',
        'changed-prepared-canonical-failure',
        'prepared-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'PREPARED',
        NULL, NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'pre-submit exact replay ignored changed failure evidence';
    END IF;

    ids := resolve_canonical_pending_reversal(
        'phase7c-failed-reversal',
        'failed-reversal-allocation',
        'failed-reversal-digest',
        3, 4, failed_done,
        'failed-reversal-quarantine',
        'failed-reversal-resolution',
        'provider-failed:failed-reversal-event',
        'failed-canonical-failure',
        'failed-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'FAILED',
        NULL, NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL
    );
    IF ids <> ARRAY[
        'payment:phase7c-failed-reversal:final-reversal',
        'payment:phase7c-failed-reversal:provisional-reversal'
    ] THEN
        RAISE EXCEPTION 'failed atomic resolver returned wrong journals: %', ids;
    END IF;

    -- Exact retry returns the original journals; adding any receipt proof to a
    -- pre-submit origin conflicts.
    IF resolve_canonical_pending_reversal(
        'phase7c-prepared-reversal',
        'prepared-reversal-allocation',
        'prepared-reversal-digest',
        2, 3, prepared_done,
        'prepared-reversal-quarantine',
        'prepared-reversal-resolution',
        'provider-prepared:prepared-reversal-event',
        'prepared-canonical-failure',
        'prepared-resolution-evidence',
        'payment-operations',
        '2026-07-24T01:15:00Z',
        'PREPARED',
        31337, NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'pre-submit resolver accepted caller receipt fields';
    END IF;

    IF (SELECT count(*) FROM canonical_allocation_tombstone
        WHERE payment_id IN (
            'phase7c-prepared-reversal',
            'phase7c-failed-reversal',
            'phase7c-submitted-reversal'
        )) <> 3
       OR NOT EXISTS (
           SELECT 1 FROM canonical_coordinator_state
           WHERE payment_id = 'phase7c-prepared-reversal'
             AND state = 'FAILED'
             AND version = 3
             AND tombstoned
             AND NOT pending_reversal
       )
       OR NOT EXISTS (
           SELECT 1 FROM canonical_coordinator_state
           WHERE payment_id = 'phase7c-failed-reversal'
             AND state = 'FAILED'
             AND version = 4
             AND tombstoned
             AND NOT pending_reversal
       )
       OR NOT EXISTS (
           SELECT 1 FROM canonical_coordinator_state
           WHERE payment_id = 'phase7c-submitted-reversal'
             AND state = 'FAILED'
             AND version = 4
             AND tombstoned
             AND NOT pending_reversal
       )
       OR (SELECT count(*) FROM canonical_coordinator_state_history
           WHERE payment_id = 'phase7c-prepared-reversal') <> 3
       OR (SELECT count(*) FROM canonical_coordinator_state_history
           WHERE payment_id = 'phase7c-failed-reversal') <> 4
       OR (SELECT count(*) FROM canonical_coordinator_state_history
           WHERE payment_id = 'phase7c-submitted-reversal') <> 4
       OR (SELECT count(*) FROM payment_state_event
           WHERE payment_id IN (
               'phase7c-prepared-reversal',
               'phase7c-failed-reversal',
               'phase7c-submitted-reversal'
           ) AND to_status = 'REVERSED') <> 3
       OR (SELECT count(*) FROM canonical_pending_reversal_resolution_evidence
           WHERE quarantine_id IN (
               'prepared-reversal-quarantine',
               'failed-reversal-quarantine',
               'submitted-reversal-quarantine'
           )) <> 3
       OR NOT EXISTS (
           SELECT 1
           FROM canonical_reverted_transaction_evidence
           WHERE quarantine_id = 'submitted-reversal-quarantine'
             AND transaction_hash = 'submitted-transaction-hash'
             AND receipt_status = 'REVERTED'
             AND confirmation_depth = 2
             AND head_block_number = 102
             AND finality_policy_hash =
                 '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
             AND header_authority_hash =
                 '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
             AND receipt_header_signature_hash =
                 '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
             AND head_header_signature_hash =
                 '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
             AND transaction_index = 0
             AND receipts_root =
                 '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
             AND inclusion_proof_hash =
                 '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
             AND evidence_hash = 'submitted-failure-evidence'
       )
       OR (SELECT count(*) FROM journal
           WHERE reversal_of IN (
               'payment:phase7c-prepared-reversal:final',
               'payment:phase7c-prepared-reversal:provisional',
               'payment:phase7c-failed-reversal:final',
               'payment:phase7c-failed-reversal:provisional',
               'payment:phase7c-submitted-reversal:final',
               'payment:phase7c-submitted-reversal:provisional'
           )) <> 6
    THEN
        RAISE EXCEPTION 'reversal quarantine lifecycle lost durable state';
    END IF;
END;
$$;

SET CONSTRAINTS ALL IMMEDIATE;

ROLLBACK;
