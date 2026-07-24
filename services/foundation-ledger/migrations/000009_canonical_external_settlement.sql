BEGIN;

INSERT INTO chart_account (
    account_code, account_name, account_class, normal_side, specification_version
) VALUES
    (
        '1260',
        'Restricted External Payment Settlement Token',
        'ASSET',
        'DEBIT',
        'v0.1'
    ),
    (
        '9160',
        'Cross-Asset Conversion Clearing',
        'SUSPENSE',
        'DEBIT',
        'v0.1'
    );

CREATE TABLE payment_allocation_mode_claim (
    claim_id text PRIMARY KEY,
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    allocation_id text NOT NULL UNIQUE,
    allocation_mode text NOT NULL CHECK (
        allocation_mode IN ('SYNTHETIC_PROJECTION', 'CANONICAL_GATEWAY')
    ),
    expected_version bigint NOT NULL CHECK (expected_version >= 0),
    claimed_version bigint NOT NULL,
    prior_allocation_absent boolean NOT NULL,
    prior_allocation_journal_count integer NOT NULL
        CHECK (prior_allocation_journal_count >= 0),
    instruction_digest text,
    claim_digest text NOT NULL,
    claim_digest_kind text NOT NULL CHECK (
        claim_digest_kind IN ('FULL_V1', 'LEGACY_NON_REPLAYABLE')
    ),
    evidence_hash text NOT NULL,
    claimed_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (payment_id, allocation_id),
    CHECK (claimed_version = expected_version + 1),
    CHECK (
        prior_allocation_absent
        AND prior_allocation_journal_count = 0
    ),
    CHECK (
        (
            allocation_mode = 'SYNTHETIC_PROJECTION'
            AND instruction_digest IS NULL
            AND claim_digest <> ''
            AND claim_digest_kind IN ('FULL_V1', 'LEGACY_NON_REPLAYABLE')
        )
        OR (
            allocation_mode = 'CANONICAL_GATEWAY'
            AND instruction_digest IS NOT NULL
            AND claim_digest = instruction_digest
            AND claim_digest_kind = 'FULL_V1'
        )
    )
);

CREATE TABLE canonical_coordinator_state (
    payment_id text PRIMARY KEY REFERENCES payment_intent(payment_id),
    allocation_id text NOT NULL UNIQUE,
    instruction_digest text NOT NULL UNIQUE,
    state text NOT NULL CHECK (
        state IN (
            'PREPARED',
            'SUBMITTED',
            'CONFIRMED',
            'FAILED',
            'QUARANTINED',
            'INCIDENT'
        )
    ),
    version bigint NOT NULL CHECK (version > 0),
    snapshot jsonb NOT NULL CHECK (jsonb_typeof(snapshot) = 'object'),
    tombstoned boolean NOT NULL DEFAULT false,
    pending_reversal boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL,
    CHECK (NOT (tombstoned AND pending_reversal)),
    CHECK (NOT tombstoned OR state = 'FAILED'),
    FOREIGN KEY (payment_id, allocation_id)
        REFERENCES payment_allocation_mode_claim(payment_id, allocation_id)
);

CREATE TABLE canonical_coordinator_state_history (
    payment_id text NOT NULL REFERENCES canonical_coordinator_state(payment_id),
    allocation_id text NOT NULL,
    instruction_digest text NOT NULL,
    version bigint NOT NULL CHECK (version > 0),
    state text NOT NULL CHECK (
        state IN (
            'PREPARED',
            'SUBMITTED',
            'CONFIRMED',
            'FAILED',
            'QUARANTINED',
            'INCIDENT'
        )
    ),
    snapshot jsonb NOT NULL CHECK (jsonb_typeof(snapshot) = 'object'),
    tombstoned boolean NOT NULL,
    pending_reversal boolean NOT NULL,
    evidence_hash text NOT NULL,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (payment_id, version),
    CHECK (NOT (tombstoned AND pending_reversal)),
    CHECK (NOT tombstoned OR state = 'FAILED')
);

CREATE TABLE canonical_allocation_tombstone (
    payment_id text PRIMARY KEY REFERENCES payment_intent(payment_id),
    allocation_id text,
    instruction_digest text,
    quarantine_id text REFERENCES payment_callback_quarantine(quarantine_id),
    reversal_event_id text NOT NULL UNIQUE REFERENCES payment_state_event(event_id),
    evidence_hash text NOT NULL,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (
        (allocation_id IS NULL AND instruction_digest IS NULL)
        OR (allocation_id IS NOT NULL AND instruction_digest IS NOT NULL)
    )
);

-- The general Phase 7A quarantine table intentionally remains rail-neutral.
-- This one-to-one extension retains the complete canonical identity and the
-- submitted transaction identity (when one exists) needed by the atomic
-- reversal resolver. A manually inserted quarantine row is therefore never
-- sufficient authority to reverse a canonical claim.
CREATE TABLE canonical_pending_reversal_quarantine (
    quarantine_id text PRIMARY KEY
        REFERENCES payment_callback_quarantine(quarantine_id),
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    allocation_id text NOT NULL,
    instruction_digest text NOT NULL,
    origin_state text NOT NULL CHECK (
        origin_state IN ('PREPARED', 'FAILED', 'SUBMITTED')
    ),
    provider_reference text NOT NULL,
    asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    callback_evidence_hash text NOT NULL,
    callback_occurred_at timestamptz NOT NULL,
    submission_chain_id bigint,
    submission_gateway text,
    submission_transaction_hash text,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    FOREIGN KEY (payment_id, allocation_id)
        REFERENCES payment_allocation_mode_claim(payment_id, allocation_id),
    CHECK (
        (
            origin_state = 'SUBMITTED'
            AND submission_chain_id > 0
            AND submission_gateway IS NOT NULL
            AND submission_transaction_hash IS NOT NULL
        )
        OR (
            origin_state IN ('PREPARED', 'FAILED')
            AND submission_chain_id IS NULL
            AND submission_gateway IS NULL
            AND submission_transaction_hash IS NULL
        )
    )
);

CREATE TABLE canonical_reverted_transaction_evidence (
    quarantine_id text PRIMARY KEY
        REFERENCES canonical_pending_reversal_quarantine(quarantine_id),
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    allocation_id text NOT NULL,
    instruction_digest text NOT NULL,
    chain_id bigint NOT NULL CHECK (chain_id > 0),
    gateway_address text NOT NULL,
    transaction_hash text NOT NULL,
    receipt_payload_hash text NOT NULL,
    receipt_status text NOT NULL CHECK (receipt_status = 'REVERTED'),
    block_number bigint NOT NULL CHECK (block_number > 0),
    block_hash text NOT NULL,
    confirmation_depth bigint NOT NULL CHECK (confirmation_depth > 0),
    head_block_number bigint NOT NULL,
    head_block_hash text NOT NULL,
    finality_policy_hash text NOT NULL CHECK (
        finality_policy_hash ~ '^0x[0-9a-f]{64}$'
    ),
    header_authority_hash text NOT NULL CHECK (
        header_authority_hash ~ '^0x[0-9a-f]{64}$'
    ),
    receipt_header_signature_hash text NOT NULL CHECK (
        receipt_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    head_header_signature_hash text NOT NULL CHECK (
        head_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    transaction_index numeric(20, 0) NOT NULL CHECK (
        transaction_index >= 0
        AND transaction_index <= 18446744073709551615
    ),
    receipts_root text NOT NULL CHECK (
        receipts_root ~ '^0x[0-9a-f]{64}$'
    ),
    inclusion_proof_hash text NOT NULL CHECK (
        inclusion_proof_hash ~ '^0x[0-9a-f]{64}$'
    ),
    evidence_hash text NOT NULL,
    observed_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    FOREIGN KEY (payment_id, allocation_id)
        REFERENCES payment_allocation_mode_claim(payment_id, allocation_id),
    CHECK (head_block_number >= block_number + confirmation_depth)
);

CREATE TABLE canonical_pending_reversal_resolution_evidence (
    resolution_id text PRIMARY KEY
        REFERENCES payment_callback_quarantine_resolution(resolution_id),
    quarantine_id text NOT NULL UNIQUE
        REFERENCES canonical_pending_reversal_quarantine(quarantine_id),
    origin_state text NOT NULL CHECK (
        origin_state IN ('PREPARED', 'FAILED', 'SUBMITTED')
    ),
    failure_evidence_hash text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE FUNCTION create_canonical_coordinator_state(
    payment_id_ text,
    allocation_id_ text,
    instruction_digest_ text,
    allocation_expected_version_ bigint,
    state_ text,
    version_ bigint,
    snapshot_ jsonb,
    evidence_hash_ text,
    claimed_at_ timestamptz,
    occurred_at_ timestamptz
) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE
    latest_payment_version bigint;
    latest_payment_status text;
BEGIN
    IF payment_id_ = '' OR allocation_id_ = '' OR instruction_digest_ = ''
       OR allocation_expected_version_ <= 0
       OR state_ <> 'PREPARED' OR version_ <> 1
       OR jsonb_typeof(snapshot_) <> 'object'
       OR evidence_hash_ = '' OR claimed_at_ IS NULL OR occurred_at_ IS NULL THEN
        RETURN false;
    END IF;
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF NOT FOUND OR EXISTS (
        SELECT 1
        FROM canonical_allocation_tombstone
        WHERE payment_id = payment_id_
    ) OR EXISTS (
        SELECT 1
        FROM final_payment_allocation
        WHERE payment_id = payment_id_
    ) OR EXISTS (
        SELECT 1
        FROM journal
        WHERE source_system = 'payment-allocation'
          AND source_event_id = payment_id_
    ) THEN
        RETURN false;
    END IF;

    SELECT aggregate_version, to_status
    INTO latest_payment_version, latest_payment_status
    FROM payment_state_event
    WHERE payment_id = payment_id_
    ORDER BY aggregate_version DESC
    LIMIT 1;
    IF latest_payment_version IS NULL
       OR latest_payment_version <> allocation_expected_version_
       OR latest_payment_status <> 'FINAL'
       OR EXISTS (
           SELECT 1
           FROM canonical_coordinator_state
           WHERE payment_id <> payment_id_
             AND (
                 allocation_id = allocation_id_
                 OR instruction_digest = instruction_digest_
             )
       ) THEN
        RETURN false;
    END IF;

    INSERT INTO payment_allocation_mode_claim (
        claim_id,
        payment_id,
        allocation_id,
        allocation_mode,
        expected_version,
        claimed_version,
        prior_allocation_absent,
        prior_allocation_journal_count,
        instruction_digest,
        claim_digest,
        claim_digest_kind,
        evidence_hash,
        claimed_at
    ) VALUES (
        'phase7c:' || allocation_id_,
        payment_id_,
        allocation_id_,
        'CANONICAL_GATEWAY',
        allocation_expected_version_,
        allocation_expected_version_ + 1,
        true,
        0,
        instruction_digest_,
        instruction_digest_,
        'FULL_V1',
        evidence_hash_,
        claimed_at_
    )
    ON CONFLICT DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim AS claim
        WHERE claim.claim_id = 'phase7c:' || allocation_id_
          AND claim.payment_id = payment_id_
          AND claim.allocation_id = allocation_id_
          AND claim.allocation_mode = 'CANONICAL_GATEWAY'
          AND claim.expected_version = allocation_expected_version_
          AND claim.claimed_version = allocation_expected_version_ + 1
          AND claim.prior_allocation_absent
           AND claim.prior_allocation_journal_count = 0
           AND claim.instruction_digest = instruction_digest_
           AND claim.claim_digest = instruction_digest_
           AND claim.claim_digest_kind = 'FULL_V1'
           AND claim.evidence_hash = evidence_hash_
          AND claim.claimed_at = claimed_at_
    ) THEN
        RETURN false;
    END IF;

    INSERT INTO canonical_coordinator_state (
        payment_id,
        allocation_id,
        instruction_digest,
        state,
        version,
        snapshot,
        tombstoned,
        pending_reversal,
        updated_at
    ) VALUES (
        payment_id_,
        allocation_id_,
        instruction_digest_,
        state_,
        version_,
        snapshot_,
        false,
        false,
        occurred_at_
    )
    ON CONFLICT (payment_id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_coordinator_state
        WHERE payment_id = payment_id_
          AND allocation_id = allocation_id_
          AND instruction_digest = instruction_digest_
          AND state = state_
          AND version = version_
          AND snapshot = snapshot_
          AND NOT tombstoned
          AND NOT pending_reversal
    ) THEN
        RETURN false;
    END IF;

    INSERT INTO canonical_coordinator_state_history (
        payment_id,
        allocation_id,
        instruction_digest,
        version,
        state,
        snapshot,
        tombstoned,
        pending_reversal,
        evidence_hash,
        occurred_at
    ) VALUES (
        payment_id_,
        allocation_id_,
        instruction_digest_,
        version_,
        state_,
        snapshot_,
        false,
        false,
        evidence_hash_,
        occurred_at_
    )
    ON CONFLICT (payment_id, version) DO NOTHING;

    RETURN EXISTS (
        SELECT 1
        FROM canonical_coordinator_state_history
        WHERE payment_id = payment_id_
          AND version = version_
          AND allocation_id = allocation_id_
          AND instruction_digest = instruction_digest_
          AND state = state_
          AND snapshot = snapshot_
          AND evidence_hash = evidence_hash_
          AND occurred_at = occurred_at_
    );
END;
$$;

CREATE FUNCTION claim_synthetic_payment_allocation(
    claim_id_ text,
    payment_id_ text,
    allocation_id_ text,
    allocation_expected_version_ bigint,
    claim_digest_ text,
    evidence_hash_ text,
    claimed_at_ timestamptz
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    latest_payment_version bigint;
    latest_payment_status text;
BEGIN
    IF claim_id_ = '' OR payment_id_ = '' OR allocation_id_ = ''
       OR allocation_expected_version_ <= 0
       OR claim_digest_ = '' OR evidence_hash_ = '' OR claimed_at_ IS NULL THEN
        RETURN 'CONFLICT';
    END IF;
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN 'CONFLICT';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim
        WHERE claim_id = claim_id_
          AND payment_id = payment_id_
          AND allocation_id = allocation_id_
          AND allocation_mode = 'SYNTHETIC_PROJECTION'
          AND expected_version = allocation_expected_version_
          AND claimed_version = allocation_expected_version_ + 1
          AND prior_allocation_absent
           AND prior_allocation_journal_count = 0
           AND instruction_digest IS NULL
           AND claim_digest = claim_digest_
           AND claim_digest_kind = 'FULL_V1'
           AND evidence_hash = evidence_hash_
          AND claimed_at = claimed_at_
    ) THEN
        RETURN 'REPLAYED';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim
        WHERE payment_id = payment_id_
           OR allocation_id = allocation_id_
           OR claim_id = claim_id_
    ) OR EXISTS (
        SELECT 1
        FROM canonical_allocation_tombstone
        WHERE payment_id = payment_id_
    ) OR EXISTS (
        SELECT 1
        FROM final_payment_allocation
        WHERE payment_id = payment_id_
    ) OR EXISTS (
        SELECT 1
        FROM journal
        WHERE source_system = 'payment-allocation'
          AND source_event_id = payment_id_
    ) THEN
        RETURN 'CONFLICT';
    END IF;

    SELECT aggregate_version, to_status
    INTO latest_payment_version, latest_payment_status
    FROM payment_state_event
    WHERE payment_id = payment_id_
    ORDER BY aggregate_version DESC
    LIMIT 1;
    IF latest_payment_version IS NULL
       OR latest_payment_version <> allocation_expected_version_
       OR latest_payment_status <> 'FINAL' THEN
        RETURN 'CONFLICT';
    END IF;

    INSERT INTO payment_allocation_mode_claim (
        claim_id,
        payment_id,
        allocation_id,
        allocation_mode,
        expected_version,
        claimed_version,
        prior_allocation_absent,
        prior_allocation_journal_count,
        instruction_digest,
        claim_digest,
        claim_digest_kind,
        evidence_hash,
        claimed_at
    ) VALUES (
        claim_id_,
        payment_id_,
        allocation_id_,
        'SYNTHETIC_PROJECTION',
        allocation_expected_version_,
        allocation_expected_version_ + 1,
        true,
        0,
        NULL,
        claim_digest_,
        'FULL_V1',
        evidence_hash_,
        claimed_at_
    )
    ON CONFLICT DO NOTHING;

    IF FOUND THEN
        RETURN 'CREATED';
    END IF;
    RETURN 'CONFLICT';
END;
$$;

CREATE FUNCTION compare_and_swap_canonical_coordinator_state(
    payment_id_ text,
    allocation_id_ text,
    instruction_digest_ text,
    expected_state_ text,
    expected_version_ bigint,
    next_state_ text,
    next_version_ bigint,
    next_snapshot_ jsonb,
    next_tombstoned_ boolean,
    next_pending_reversal_ boolean,
    evidence_hash_ text,
    occurred_at_ timestamptz
) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE
    current_state canonical_coordinator_state%ROWTYPE;
    transition_allowed boolean;
BEGIN
    SELECT *
    INTO current_state
    FROM canonical_coordinator_state
    WHERE payment_id = payment_id_
    FOR UPDATE;

    IF current_state.payment_id IS NULL
       OR current_state.allocation_id <> allocation_id_
       OR current_state.instruction_digest <> instruction_digest_
       OR current_state.state <> expected_state_
       OR current_state.version <> expected_version_
       OR next_version_ <> expected_version_ + 1
       OR jsonb_typeof(next_snapshot_) <> 'object'
       OR evidence_hash_ = '' OR occurred_at_ IS NULL
       -- Only resolve_canonical_pending_reversal may mint a tombstone and
       -- transition the saga to FAILED+tombstoned in the same transaction.
       OR next_tombstoned_
       OR (next_state_ = 'QUARANTINED' AND NOT next_pending_reversal_)
       OR current_state.tombstoned THEN
        RETURN false;
    END IF;

    transition_allowed := CASE current_state.state
        WHEN 'PREPARED' THEN next_state_ IN ('SUBMITTED', 'FAILED', 'QUARANTINED')
        WHEN 'SUBMITTED' THEN next_state_ IN ('CONFIRMED', 'FAILED', 'QUARANTINED')
        WHEN 'FAILED' THEN next_state_ IN ('PREPARED', 'QUARANTINED')
        WHEN 'QUARANTINED' THEN next_state_ IN ('FAILED', 'INCIDENT')
        WHEN 'CONFIRMED' THEN next_state_ = 'INCIDENT'
        ELSE false
    END;
    IF NOT transition_allowed
       OR (next_pending_reversal_ AND next_state_ <> 'QUARANTINED') THEN
        RETURN false;
    END IF;

    UPDATE canonical_coordinator_state
    SET state = next_state_,
        version = next_version_,
        snapshot = next_snapshot_,
        tombstoned = next_tombstoned_,
        pending_reversal = next_pending_reversal_,
        updated_at = occurred_at_
    WHERE payment_id = payment_id_
      AND version = expected_version_;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    INSERT INTO canonical_coordinator_state_history (
        payment_id,
        allocation_id,
        instruction_digest,
        version,
        state,
        snapshot,
        tombstoned,
        pending_reversal,
        evidence_hash,
        occurred_at
    ) VALUES (
        payment_id_,
        allocation_id_,
        instruction_digest_,
        next_version_,
        next_state_,
        next_snapshot_,
        next_tombstoned_,
        next_pending_reversal_,
        evidence_hash_,
        occurred_at_
    );
    RETURN true;
END;
$$;

CREATE FUNCTION create_canonical_allocation_tombstone(
    payment_id_ text,
    allocation_id_ text,
    instruction_digest_ text,
    quarantine_id_ text,
    reversal_event_id_ text,
    evidence_hash_ text,
    occurred_at_ timestamptz
) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF NOT FOUND OR reversal_event_id_ = '' OR evidence_hash_ = ''
       OR occurred_at_ IS NULL
       OR ((allocation_id_ IS NULL) <> (instruction_digest_ IS NULL)) THEN
        RETURN false;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM payment_state_event AS reversal
        WHERE reversal.event_id = reversal_event_id_
          AND reversal.payment_id = payment_id_
          AND reversal.to_status = 'REVERSED'
          AND reversal.occurred_at <= occurred_at_
          AND NOT EXISTS (
              SELECT 1
              FROM payment_state_event AS later
              WHERE later.payment_id = reversal.payment_id
                AND later.aggregate_version > reversal.aggregate_version
          )
    ) THEN
        RETURN false;
    END IF;
    IF allocation_id_ IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim AS claim
        WHERE claim.payment_id = payment_id_
          AND claim.allocation_id = allocation_id_
          AND claim.instruction_digest = instruction_digest_
          AND claim.allocation_mode = 'CANONICAL_GATEWAY'
    ) THEN
        RETURN false;
    END IF;
    IF quarantine_id_ IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM payment_callback_quarantine
        WHERE quarantine_id = quarantine_id_
          AND payment_id = payment_id_
    ) THEN
        RETURN false;
    END IF;

    INSERT INTO canonical_allocation_tombstone (
        payment_id,
        allocation_id,
        instruction_digest,
        quarantine_id,
        reversal_event_id,
        evidence_hash,
        occurred_at
    ) VALUES (
        payment_id_,
        allocation_id_,
        instruction_digest_,
        quarantine_id_,
        reversal_event_id_,
        evidence_hash_,
        occurred_at_
    )
    ON CONFLICT (payment_id) DO NOTHING;

    RETURN EXISTS (
        SELECT 1
        FROM canonical_allocation_tombstone
        WHERE payment_id = payment_id_
          AND allocation_id IS NOT DISTINCT FROM allocation_id_
          AND instruction_digest IS NOT DISTINCT FROM instruction_digest_
          AND quarantine_id IS NOT DISTINCT FROM quarantine_id_
          AND reversal_event_id = reversal_event_id_
          AND evidence_hash = evidence_hash_
          AND occurred_at = occurred_at_
    );
END;
$$;

CREATE FUNCTION reject_tombstoned_allocation_claim() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = NEW.payment_id
    FOR UPDATE;
    IF EXISTS (
        SELECT 1
        FROM canonical_allocation_tombstone
        WHERE payment_id = NEW.payment_id
    ) THEN
        RAISE EXCEPTION 'payment % has a permanent allocation tombstone', NEW.payment_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_allocation_mode_claim_tombstone_guard
BEFORE INSERT ON payment_allocation_mode_claim
FOR EACH ROW EXECUTE FUNCTION reject_tombstoned_allocation_claim();

CREATE FUNCTION quarantine_canonical_pending_reversal(
    payment_id_ text,
    allocation_id_ text,
    instruction_digest_ text,
    expected_state_ text,
    expected_version_ bigint,
    next_version_ bigint,
    next_snapshot_ jsonb,
    quarantine_id_ text,
    provider_id_ text,
    provider_event_id_ text,
    raw_payload_hash_ text,
    callback_evidence_hash_ text,
    callback_occurred_at_ timestamptz,
    received_at_ timestamptz,
    resolution_deadline_ timestamptz
) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE
    coordinator canonical_coordinator_state%ROWTYPE;
    provider_reference_ text;
    asset_id_ text;
    units_ numeric(78, 0);
    snapshot_occurred_at_ timestamptz;
    snapshot_received_at_ timestamptz;
    submission_chain_id_ bigint;
    submission_gateway_ text;
    submission_transaction_hash_ text;
BEGIN
    IF payment_id_ = '' OR allocation_id_ = '' OR instruction_digest_ = ''
       OR expected_state_ NOT IN ('PREPARED', 'FAILED', 'SUBMITTED')
       OR expected_version_ <= 0 OR next_version_ <> expected_version_ + 1
       OR jsonb_typeof(next_snapshot_) <> 'object'
       OR quarantine_id_ = '' OR provider_id_ = '' OR provider_event_id_ = ''
       OR raw_payload_hash_ = '' OR callback_evidence_hash_ = ''
       OR callback_occurred_at_ IS NULL OR received_at_ IS NULL
       OR received_at_ < callback_occurred_at_
       OR resolution_deadline_ <> received_at_ + interval '24 hours' THEN
        RETURN false;
    END IF;

    PERFORM 1
    FROM payment_intent
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    SELECT *
    INTO coordinator
    FROM canonical_coordinator_state
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF coordinator.payment_id IS NULL
       OR coordinator.allocation_id <> allocation_id_
       OR coordinator.instruction_digest <> instruction_digest_
       OR coordinator.tombstoned THEN
        RETURN false;
    END IF;

    provider_reference_ :=
        next_snapshot_ #>> '{PendingReversal,ProviderReference}';
    asset_id_ := next_snapshot_ #>> '{PendingReversal,AssetID}';
    BEGIN
        units_ := (next_snapshot_ #>> '{PendingReversal,Units}')::numeric;
        snapshot_occurred_at_ :=
            (next_snapshot_ #>> '{PendingReversal,OccurredAt}')::timestamptz;
        snapshot_received_at_ :=
            (next_snapshot_ #>> '{PendingReversal,ReceivedAt}')::timestamptz;
    EXCEPTION
        WHEN invalid_text_representation OR numeric_value_out_of_range
            OR datetime_field_overflow THEN
            RETURN false;
    END;

    IF provider_reference_ IS NULL OR provider_reference_ = ''
       OR asset_id_ IS NULL OR asset_id_ = '' OR units_ <= 0
       OR snapshot_occurred_at_ <> callback_occurred_at_
       OR snapshot_received_at_ <> received_at_
       OR next_snapshot_ #>> '{Plan,PaymentID}' <> payment_id_
       OR next_snapshot_ #>> '{Plan,AllocationID}' <> allocation_id_
       OR next_snapshot_ #>> '{Plan,InstructionDigest}' <> instruction_digest_
       OR next_snapshot_ #>> '{Plan,State}' <> 'QUARANTINED'
       OR (next_snapshot_ #>> '{Plan,Version}')::bigint <> next_version_
       OR next_snapshot_ #>> '{Claim,PaymentID}' <> payment_id_
       OR next_snapshot_ #>> '{Claim,AllocationID}' <> allocation_id_
       OR next_snapshot_ #>> '{Claim,Digest}' <> instruction_digest_
       OR next_snapshot_ #>> '{Claim,Mode}' <> 'CANONICAL_GATEWAY'
       OR next_snapshot_ #>> '{Claim,State}' <> 'QUARANTINED'
       OR next_snapshot_ #>> '{PendingReversal,QuarantineID}' <> quarantine_id_
       OR next_snapshot_ #>> '{PendingReversal,ProviderID}' <> provider_id_
       OR next_snapshot_ #>> '{PendingReversal,ProviderEventID}' <> provider_event_id_
       OR next_snapshot_ #>> '{PendingReversal,RawHash}' <> raw_payload_hash_
       OR next_snapshot_ #>> '{PendingReversal,CallbackEvidenceHash}'
            <> callback_evidence_hash_
       OR NOT EXISTS (
           SELECT 1
           FROM payment_intent AS intent
           WHERE intent.payment_id = payment_id_
             AND intent.provider_id = provider_id_
             AND intent.asset_id = asset_id_
             AND intent.units = units_
       )
       OR NOT EXISTS (
           SELECT 1
           FROM payment_state_event AS final_
           WHERE final_.payment_id = payment_id_
             AND final_.to_status = 'FINAL'
             AND NOT EXISTS (
                 SELECT 1
                 FROM payment_state_event AS later
                 WHERE later.payment_id = final_.payment_id
                   AND later.aggregate_version > final_.aggregate_version
             )
       ) THEN
        RETURN false;
    END IF;

    IF expected_state_ = 'SUBMITTED' THEN
        BEGIN
            submission_chain_id_ :=
                (coordinator.snapshot #>> '{Plan,Submission,ChainID}')::bigint;
        EXCEPTION
            WHEN invalid_text_representation OR numeric_value_out_of_range THEN
                RETURN false;
        END;
        submission_gateway_ :=
            coordinator.snapshot #>> '{Plan,Submission,Gateway}';
        submission_transaction_hash_ :=
            coordinator.snapshot #>> '{Plan,Submission,TransactionHash}';
        IF submission_chain_id_ <= 0 OR submission_gateway_ IS NULL
           OR submission_gateway_ = '' OR submission_transaction_hash_ IS NULL
           OR submission_transaction_hash_ = '' THEN
            RETURN false;
        END IF;
    END IF;

    -- Exact retry after the original transaction committed.
    IF coordinator.state = 'QUARANTINED' THEN
        RETURN coordinator.version = next_version_
           AND coordinator.snapshot = next_snapshot_
           AND coordinator.pending_reversal
           AND NOT coordinator.tombstoned
           AND EXISTS (
               SELECT 1
               FROM payment_callback_quarantine AS quarantine
               JOIN canonical_pending_reversal_quarantine AS canonical
                 USING (quarantine_id)
               WHERE quarantine.quarantine_id = quarantine_id_
                 AND quarantine.provider_id = provider_id_
                 AND quarantine.provider_event_id = provider_event_id_
                 AND quarantine.payment_id = payment_id_
                 AND quarantine.raw_payload_hash = raw_payload_hash_
                 AND quarantine.evidence_hash = callback_evidence_hash_
                 AND quarantine.reason_code = 'CANONICAL_SETTLEMENT_SUBMITTED'
                 AND quarantine.owner = 'payment-operations'
                 AND quarantine.received_at = received_at_
                 AND quarantine.resolution_deadline = resolution_deadline_
                 AND canonical.payment_id = payment_id_
                 AND canonical.allocation_id = allocation_id_
                 AND canonical.instruction_digest = instruction_digest_
                 AND canonical.origin_state = expected_state_
                 AND canonical.provider_reference = provider_reference_
                 AND canonical.asset_id = asset_id_
                 AND canonical.units = units_
                 AND canonical.callback_evidence_hash = callback_evidence_hash_
                 AND canonical.callback_occurred_at = callback_occurred_at_
                 AND canonical.submission_chain_id IS NOT DISTINCT FROM
                     submission_chain_id_
                 AND canonical.submission_gateway IS NOT DISTINCT FROM
                     submission_gateway_
                 AND canonical.submission_transaction_hash IS NOT DISTINCT FROM
                     submission_transaction_hash_
           )
           AND EXISTS (
               SELECT 1
               FROM canonical_coordinator_state_history
               WHERE payment_id = payment_id_
                 AND version = next_version_
                 AND state = 'QUARANTINED'
                 AND snapshot = next_snapshot_
                 AND NOT tombstoned
                 AND pending_reversal
                 AND evidence_hash = callback_evidence_hash_
                 AND occurred_at = received_at_
           );
    END IF;

    IF coordinator.state <> expected_state_
       OR coordinator.version <> expected_version_
       OR coordinator.pending_reversal
       OR coordinator.snapshot #>> '{Plan,PaymentID}' <> payment_id_
       OR coordinator.snapshot #>> '{Plan,AllocationID}' <> allocation_id_
       OR coordinator.snapshot #>> '{Plan,InstructionDigest}' <> instruction_digest_
       OR coordinator.snapshot #>> '{Plan,State}' <> expected_state_
       OR (coordinator.snapshot #>> '{Plan,Version}')::bigint <> expected_version_ THEN
        RETURN false;
    END IF;

    INSERT INTO payment_callback_quarantine (
        quarantine_id,
        provider_id,
        provider_event_id,
        payment_id,
        raw_payload_hash,
        evidence_hash,
        reason_code,
        owner,
        received_at,
        resolution_deadline
    ) VALUES (
        quarantine_id_,
        provider_id_,
        provider_event_id_,
        payment_id_,
        raw_payload_hash_,
        callback_evidence_hash_,
        'CANONICAL_SETTLEMENT_SUBMITTED',
        'payment-operations',
        received_at_,
        resolution_deadline_
    )
    ON CONFLICT DO NOTHING;
    IF NOT EXISTS (
        SELECT 1
        FROM payment_callback_quarantine
        WHERE quarantine_id = quarantine_id_
          AND provider_id = provider_id_
          AND provider_event_id = provider_event_id_
          AND payment_id = payment_id_
          AND raw_payload_hash = raw_payload_hash_
          AND evidence_hash = callback_evidence_hash_
          AND reason_code = 'CANONICAL_SETTLEMENT_SUBMITTED'
          AND owner = 'payment-operations'
          AND received_at = received_at_
          AND resolution_deadline = resolution_deadline_
    ) THEN
        RETURN false;
    END IF;

    INSERT INTO canonical_pending_reversal_quarantine (
        quarantine_id,
        payment_id,
        allocation_id,
        instruction_digest,
        origin_state,
        provider_reference,
        asset_id,
        units,
        callback_evidence_hash,
        callback_occurred_at,
        submission_chain_id,
        submission_gateway,
        submission_transaction_hash
    ) VALUES (
        quarantine_id_,
        payment_id_,
        allocation_id_,
        instruction_digest_,
        expected_state_,
        provider_reference_,
        asset_id_,
        units_,
        callback_evidence_hash_,
        callback_occurred_at_,
        submission_chain_id_,
        submission_gateway_,
        submission_transaction_hash_
    )
    ON CONFLICT DO NOTHING;
    IF NOT EXISTS (
        SELECT 1
        FROM canonical_pending_reversal_quarantine
        WHERE quarantine_id = quarantine_id_
          AND payment_id = payment_id_
          AND allocation_id = allocation_id_
          AND instruction_digest = instruction_digest_
          AND origin_state = expected_state_
          AND provider_reference = provider_reference_
          AND asset_id = asset_id_
          AND units = units_
          AND callback_evidence_hash = callback_evidence_hash_
          AND callback_occurred_at = callback_occurred_at_
          AND submission_chain_id IS NOT DISTINCT FROM submission_chain_id_
          AND submission_gateway IS NOT DISTINCT FROM submission_gateway_
          AND submission_transaction_hash IS NOT DISTINCT FROM
              submission_transaction_hash_
    ) THEN
        RETURN false;
    END IF;

    UPDATE canonical_coordinator_state
    SET state = 'QUARANTINED',
        version = next_version_,
        snapshot = next_snapshot_,
        tombstoned = false,
        pending_reversal = true,
        updated_at = received_at_
    WHERE payment_id = payment_id_
      AND state = expected_state_
      AND version = expected_version_;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    INSERT INTO canonical_coordinator_state_history (
        payment_id,
        allocation_id,
        instruction_digest,
        version,
        state,
        snapshot,
        tombstoned,
        pending_reversal,
        evidence_hash,
        occurred_at
    ) VALUES (
        payment_id_,
        allocation_id_,
        instruction_digest_,
        next_version_,
        'QUARANTINED',
        next_snapshot_,
        false,
        true,
        callback_evidence_hash_,
        received_at_
    );
    RETURN true;
END;
$$;

CREATE FUNCTION serialize_phase7a_reversal_against_canonicalization() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    coordinator canonical_coordinator_state%ROWTYPE;
BEGIN
    IF NEW.to_status <> 'REVERSED' THEN
        RETURN NEW;
    END IF;
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = NEW.payment_id
    FOR UPDATE;

    IF NOT EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim
        WHERE payment_id = NEW.payment_id
          AND allocation_mode = 'CANONICAL_GATEWAY'
    ) THEN
        RETURN NEW;
    END IF;

    SELECT *
    INTO coordinator
    FROM canonical_coordinator_state
    WHERE payment_id = NEW.payment_id
    FOR UPDATE;
    IF coordinator.payment_id IS NULL THEN
        RAISE EXCEPTION
            'canonical payment % has no durable coordinator state',
            NEW.payment_id;
    END IF;
    IF coordinator.state IN ('CONFIRMED', 'INCIDENT') THEN
        RAISE EXCEPTION
            'confirmed canonical payment % cannot enter Phase 7A REVERSED',
            NEW.payment_id;
    END IF;
    IF coordinator.state IN ('SUBMITTED', 'QUARANTINED')
       AND NOT coordinator.pending_reversal THEN
        RAISE EXCEPTION
            'submitted canonical payment % lacks a pending reversal quarantine',
            NEW.payment_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_state_event_canonical_reversal_guard
BEFORE INSERT ON payment_state_event
FOR EACH ROW EXECUTE FUNCTION serialize_phase7a_reversal_against_canonicalization();

CREATE FUNCTION assert_phase7a_reversal_resolved() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.to_status = 'REVERSED'
       AND EXISTS (
           SELECT 1
           FROM payment_allocation_mode_claim
           WHERE payment_id = NEW.payment_id
             AND allocation_mode = 'CANONICAL_GATEWAY'
       )
       AND NOT EXISTS (
           SELECT 1
           FROM canonical_coordinator_state
           WHERE payment_id = NEW.payment_id
             AND state = 'FAILED'
             AND tombstoned
             AND NOT pending_reversal
       ) THEN
        RAISE EXCEPTION
            'canonical payment % reversal did not atomically create its tombstone',
            NEW.payment_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER payment_state_event_canonical_reversal_resolved
AFTER INSERT ON payment_state_event
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_phase7a_reversal_resolved();

CREATE FUNCTION resolve_canonical_pending_reversal(
    payment_id_ text,
    allocation_id_ text,
    instruction_digest_ text,
    expected_version_ bigint,
    next_version_ bigint,
    next_snapshot_ jsonb,
    quarantine_id_ text,
    resolution_id_ text,
    reversal_event_id_ text,
    canonical_failure_evidence_hash_ text,
    resolution_evidence_hash_ text,
    resolved_by_ text,
    resolved_at_ timestamptz,
    origin_state_ text,
    failure_chain_id_ bigint,
    failure_gateway_ text,
    failure_transaction_hash_ text,
    failure_receipt_payload_hash_ text,
    failure_status_ text,
    failure_block_number_ bigint,
    failure_block_hash_ text,
    failure_confirmation_depth_ bigint,
    failure_head_block_number_ bigint,
    failure_head_block_hash_ text,
    failure_observed_at_ timestamptz,
    failure_finality_policy_hash_ text,
    failure_header_authority_hash_ text,
    failure_receipt_header_signature_hash_ text,
    failure_head_header_signature_hash_ text,
    failure_transaction_index_ numeric(20, 0),
    failure_receipts_root_ text,
    failure_inclusion_proof_hash_ text
) RETURNS text[]
LANGUAGE plpgsql AS $$
DECLARE
    coordinator canonical_coordinator_state%ROWTYPE;
    quarantine payment_callback_quarantine%ROWTYPE;
    canonical canonical_pending_reversal_quarantine%ROWTYPE;
    intent payment_intent%ROWTYPE;
    final_event payment_state_event%ROWTYPE;
    provisional_event payment_state_event%ROWTYPE;
    final_journal journal%ROWTYPE;
    provisional_journal journal%ROWTYPE;
    final_reversal_id text;
    provisional_reversal_id text;
    reversal_journal_ids text[];
BEGIN
    IF payment_id_ = '' OR allocation_id_ = '' OR instruction_digest_ = ''
       OR expected_version_ <= 0 OR next_version_ <> expected_version_ + 1
       OR jsonb_typeof(next_snapshot_) <> 'object'
       OR quarantine_id_ = '' OR resolution_id_ = ''
       OR reversal_event_id_ = '' OR canonical_failure_evidence_hash_ = ''
       OR resolution_evidence_hash_ = '' OR resolved_by_ = ''
       OR resolved_at_ IS NULL
       OR origin_state_ NOT IN ('PREPARED', 'FAILED', 'SUBMITTED') THEN
        RETURN NULL;
    END IF;

    PERFORM 1
    FROM payment_intent
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT *
    INTO coordinator
    FROM canonical_coordinator_state
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF coordinator.payment_id IS NULL
       OR coordinator.allocation_id <> allocation_id_
       OR coordinator.instruction_digest <> instruction_digest_
       OR next_snapshot_ #>> '{Plan,PaymentID}' <> payment_id_
       OR next_snapshot_ #>> '{Plan,AllocationID}' <> allocation_id_
       OR next_snapshot_ #>> '{Plan,InstructionDigest}' <> instruction_digest_
       OR next_snapshot_ #>> '{Plan,State}' <> 'FAILED'
       OR (next_snapshot_ #>> '{Plan,Version}')::bigint <> next_version_
       OR next_snapshot_ #>> '{Claim,PaymentID}' <> payment_id_
       OR next_snapshot_ #>> '{Claim,AllocationID}' <> allocation_id_
       OR next_snapshot_ #>> '{Claim,Digest}' <> instruction_digest_
       OR next_snapshot_ #>> '{Claim,Mode}' <> 'CANONICAL_GATEWAY'
       OR next_snapshot_ #>> '{Claim,State}' <> 'FAILED'
       OR COALESCE((next_snapshot_ ->> 'Tombstoned')::boolean, false) IS NOT TRUE
       OR next_snapshot_ -> 'PendingReversal' <> 'null'::jsonb THEN
        RETURN NULL;
    END IF;

    SELECT *
    INTO quarantine
    FROM payment_callback_quarantine
    WHERE quarantine_id = quarantine_id_;
    SELECT *
    INTO canonical
    FROM canonical_pending_reversal_quarantine
    WHERE quarantine_id = quarantine_id_;
    SELECT *
    INTO intent
    FROM payment_intent
    WHERE payment_id = payment_id_;
    IF quarantine.quarantine_id IS NULL OR canonical.quarantine_id IS NULL
       OR quarantine.payment_id <> payment_id_
       OR quarantine.provider_id <> intent.provider_id
       OR quarantine.raw_payload_hash = ''
       OR quarantine.evidence_hash IS NULL OR quarantine.evidence_hash = ''
       OR quarantine.reason_code <> 'CANONICAL_SETTLEMENT_SUBMITTED'
       OR quarantine.owner <> 'payment-operations'
       OR quarantine.received_at > resolved_at_
       OR canonical.payment_id <> payment_id_
       OR canonical.allocation_id <> allocation_id_
       OR canonical.instruction_digest <> instruction_digest_
       OR canonical.origin_state <> origin_state_
       OR canonical.asset_id <> intent.asset_id
       OR canonical.units <> intent.units
       OR canonical.callback_evidence_hash <> quarantine.evidence_hash
       OR canonical.callback_occurred_at > quarantine.received_at
       OR reversal_event_id_ <>
             quarantine.provider_id || ':' || quarantine.provider_event_id
       OR EXISTS (
           SELECT 1
           FROM canonical_gateway_event_projection AS projection
           WHERE projection.payment_id = payment_id_
              OR projection.allocation_id = allocation_id_
       ) THEN
        RETURN NULL;
    END IF;

    IF origin_state_ = 'SUBMITTED' THEN
        IF num_nulls(
            failure_chain_id_,
            failure_gateway_,
            failure_transaction_hash_,
            failure_receipt_payload_hash_,
            failure_status_,
            failure_block_number_,
            failure_block_hash_,
            failure_confirmation_depth_,
            failure_head_block_number_,
            failure_head_block_hash_,
            failure_observed_at_,
            failure_finality_policy_hash_,
            failure_header_authority_hash_,
            failure_receipt_header_signature_hash_,
            failure_head_header_signature_hash_,
            failure_transaction_index_,
            failure_receipts_root_,
            failure_inclusion_proof_hash_
        ) <> 0
           OR failure_status_ <> 'REVERTED'
           OR failure_chain_id_ <> canonical.submission_chain_id
           OR failure_gateway_ <> canonical.submission_gateway
           OR failure_transaction_hash_ <> canonical.submission_transaction_hash
           OR failure_receipt_payload_hash_ = ''
           OR failure_block_number_ <= 0 OR failure_block_hash_ = ''
           OR failure_confirmation_depth_ <= 0
           OR failure_head_block_number_ <
                failure_block_number_ + failure_confirmation_depth_
            OR failure_head_block_hash_ = ''
            OR failure_observed_at_ IS NULL
            OR failure_observed_at_ > resolved_at_
            OR failure_finality_policy_hash_ !~ '^0x[0-9a-f]{64}$'
            OR failure_header_authority_hash_ !~ '^0x[0-9a-f]{64}$'
            OR failure_receipt_header_signature_hash_
                !~ '^0x[0-9a-f]{64}$'
            OR failure_head_header_signature_hash_
                !~ '^0x[0-9a-f]{64}$'
            OR failure_transaction_index_ < 0
            OR failure_transaction_index_ > 18446744073709551615
            OR failure_receipts_root_ !~ '^0x[0-9a-f]{64}$'
            OR failure_inclusion_proof_hash_ !~ '^0x[0-9a-f]{64}$'
            OR NOT EXISTS (
               SELECT 1
               FROM canonicalization_plan AS plan
               JOIN canonicalization_submission AS submission
                 ON submission.canonicalization_id = plan.canonicalization_id
               WHERE plan.payment_id = payment_id_
                 AND plan.allocation_id = allocation_id_
                 AND plan.instruction_digest = instruction_digest_
                  AND plan.chain_id = failure_chain_id_
                  AND plan.gateway_address = failure_gateway_
                  AND plan.finality_policy_hash =
                      failure_finality_policy_hash_
                  AND submission.gateway_address = failure_gateway_
                  AND submission.transaction_hash = failure_transaction_hash_
                  AND submission.state = 'SUBMITTED'
                  AND submission.submitted_at <= failure_observed_at_
            ) THEN
            RETURN NULL;
        END IF;
    ELSIF num_nonnulls(
        failure_chain_id_,
        failure_gateway_,
        failure_transaction_hash_,
        failure_receipt_payload_hash_,
        failure_status_,
        failure_block_number_,
        failure_block_hash_,
        failure_confirmation_depth_,
        failure_head_block_number_,
        failure_head_block_hash_,
        failure_observed_at_,
        failure_finality_policy_hash_,
        failure_header_authority_hash_,
        failure_receipt_header_signature_hash_,
        failure_head_header_signature_hash_,
        failure_transaction_index_,
        failure_receipts_root_,
        failure_inclusion_proof_hash_
    ) <> 0 THEN
        RETURN NULL;
    END IF;

    final_reversal_id := 'payment:' || payment_id_ || ':final-reversal';
    provisional_reversal_id := 'payment:' || payment_id_ || ':provisional-reversal';
    reversal_journal_ids := ARRAY[final_reversal_id, provisional_reversal_id];

    -- Exact retry observes the complete committed result and cannot change any
    -- receipt, resolution, journal, saga, or tombstone identity.
    IF coordinator.state = 'FAILED' AND coordinator.tombstoned
       AND NOT coordinator.pending_reversal THEN
        IF coordinator.version <> next_version_
           OR coordinator.snapshot <> next_snapshot_
           OR NOT EXISTS (
               SELECT 1
               FROM payment_callback_quarantine_resolution
               WHERE resolution_id = resolution_id_
                 AND quarantine_id = quarantine_id_
                 AND evidence_hash = resolution_evidence_hash_
                 AND resolved_by = resolved_by_
                 AND resolved_at = resolved_at_
           )
           OR NOT EXISTS (
               SELECT 1
               FROM canonical_pending_reversal_resolution_evidence
               WHERE resolution_id = resolution_id_
                 AND quarantine_id = quarantine_id_
                 AND origin_state = origin_state_
                 AND failure_evidence_hash =
                     canonical_failure_evidence_hash_
           )
           OR NOT EXISTS (
               SELECT 1
               FROM payment_state_event
               WHERE event_id = reversal_event_id_
                 AND payment_id = payment_id_
                 AND provider_id = quarantine.provider_id
                 AND provider_event_id = quarantine.provider_event_id
                 AND from_status = 'FINAL'
                 AND to_status = 'REVERSED'
                 AND asset_id = canonical.asset_id
                 AND units = canonical.units
                 AND evidence_hash = canonical.callback_evidence_hash
                 AND journal_ids = reversal_journal_ids
                 AND occurred_at = canonical.callback_occurred_at
                 AND received_at = quarantine.received_at
           )
           OR NOT EXISTS (
               SELECT 1
               FROM canonical_allocation_tombstone
               WHERE payment_id = payment_id_
                 AND allocation_id = allocation_id_
                 AND instruction_digest = instruction_digest_
                 AND quarantine_id = quarantine_id_
                 AND reversal_event_id = reversal_event_id_
                 AND evidence_hash = resolution_evidence_hash_
                 AND occurred_at = resolved_at_
           )
           OR (
               origin_state_ = 'SUBMITTED'
               AND NOT EXISTS (
                   SELECT 1
                   FROM canonical_reverted_transaction_evidence
                   WHERE quarantine_id = quarantine_id_
                     AND payment_id = payment_id_
                     AND allocation_id = allocation_id_
                     AND instruction_digest = instruction_digest_
                     AND chain_id = failure_chain_id_
                     AND gateway_address = failure_gateway_
                     AND transaction_hash = failure_transaction_hash_
                     AND receipt_payload_hash = failure_receipt_payload_hash_
                     AND receipt_status = failure_status_
                     AND block_number = failure_block_number_
                     AND block_hash = failure_block_hash_
                     AND confirmation_depth = failure_confirmation_depth_
                      AND head_block_number = failure_head_block_number_
                      AND head_block_hash = failure_head_block_hash_
                      AND finality_policy_hash =
                          failure_finality_policy_hash_
                      AND header_authority_hash =
                          failure_header_authority_hash_
                      AND receipt_header_signature_hash =
                          failure_receipt_header_signature_hash_
                      AND head_header_signature_hash =
                          failure_head_header_signature_hash_
                      AND transaction_index = failure_transaction_index_
                      AND receipts_root = failure_receipts_root_
                      AND inclusion_proof_hash =
                          failure_inclusion_proof_hash_
                      AND evidence_hash = canonical_failure_evidence_hash_
                     AND observed_at = failure_observed_at_
               )
           ) THEN
            RETURN NULL;
        END IF;
        RETURN reversal_journal_ids;
    END IF;

    IF coordinator.state <> 'QUARANTINED'
       OR coordinator.version <> expected_version_
       OR NOT coordinator.pending_reversal
       OR coordinator.tombstoned THEN
        RETURN NULL;
    END IF;

    SELECT *
    INTO final_event
    FROM payment_state_event
    WHERE payment_id = payment_id_
      AND to_status = 'FINAL'
    ORDER BY aggregate_version DESC
    LIMIT 1;
    SELECT *
    INTO provisional_event
    FROM payment_state_event
    WHERE payment_id = payment_id_
      AND to_status = 'PROVISIONAL'
      AND aggregate_version < final_event.aggregate_version
    ORDER BY aggregate_version DESC
    LIMIT 1;
    IF final_event.event_id IS NULL OR provisional_event.event_id IS NULL
       OR final_event.provider_id <> quarantine.provider_id
       OR final_event.aggregate_version + 1 <= final_event.aggregate_version
       OR final_event.asset_id <> canonical.asset_id
       OR final_event.units <> canonical.units
       OR provisional_event.asset_id <> canonical.asset_id
       OR provisional_event.units <> canonical.units
       OR cardinality(final_event.journal_ids) <> 1
       OR cardinality(provisional_event.journal_ids) <> 1
       OR EXISTS (
           SELECT 1
           FROM payment_state_event AS later
           WHERE later.payment_id = payment_id_
             AND later.aggregate_version > final_event.aggregate_version
       ) THEN
        RETURN NULL;
    END IF;

    SELECT * INTO final_journal
    FROM journal
    WHERE journal_id = final_event.journal_ids[1];
    SELECT * INTO provisional_journal
    FROM journal
    WHERE journal_id = provisional_event.journal_ids[1];
    IF final_journal.journal_id <>
            'payment:' || payment_id_ || ':final'
       OR provisional_journal.journal_id <>
            'payment:' || payment_id_ || ':provisional'
       OR final_journal.source_system <> 'payment-orchestrator'
       OR provisional_journal.source_system <> 'payment-orchestrator'
       OR final_journal.entry_type <> 'PAYMENT_FINAL'
       OR provisional_journal.entry_type <> 'PAYMENT_PROVISIONAL'
       OR final_journal.legal_entity_id <> intent.legal_entity_id
       OR provisional_journal.legal_entity_id <> intent.legal_entity_id
       OR final_journal.correlation_id <> intent.correlation_id
       OR provisional_journal.correlation_id <> intent.correlation_id
       OR final_journal.loan_id IS DISTINCT FROM intent.loan_id
       OR provisional_journal.loan_id IS DISTINCT FROM intent.loan_id
       OR EXISTS (
           SELECT 1
           FROM journal
           WHERE reversal_of IN (
               final_journal.journal_id,
               provisional_journal.journal_id
           )
       )
       OR (SELECT count(*) FROM journal_entry
           WHERE journal_id = final_journal.journal_id) <> 2
       OR (SELECT count(*) FROM journal_entry
           WHERE journal_id = provisional_journal.journal_id) <> 2 THEN
        RETURN NULL;
    END IF;

    IF origin_state_ = 'SUBMITTED' THEN
        INSERT INTO canonical_reverted_transaction_evidence (
            quarantine_id,
            payment_id,
            allocation_id,
            instruction_digest,
            chain_id,
            gateway_address,
            transaction_hash,
            receipt_payload_hash,
            receipt_status,
            block_number,
            block_hash,
            confirmation_depth,
            head_block_number,
            head_block_hash,
            finality_policy_hash,
            header_authority_hash,
            receipt_header_signature_hash,
            head_header_signature_hash,
            transaction_index,
            receipts_root,
            inclusion_proof_hash,
            evidence_hash,
            observed_at
        ) VALUES (
            quarantine_id_,
            payment_id_,
            allocation_id_,
            instruction_digest_,
            failure_chain_id_,
            failure_gateway_,
            failure_transaction_hash_,
            failure_receipt_payload_hash_,
            failure_status_,
            failure_block_number_,
            failure_block_hash_,
            failure_confirmation_depth_,
            failure_head_block_number_,
            failure_head_block_hash_,
            failure_finality_policy_hash_,
            failure_header_authority_hash_,
            failure_receipt_header_signature_hash_,
            failure_head_header_signature_hash_,
            failure_transaction_index_,
            failure_receipts_root_,
            failure_inclusion_proof_hash_,
            canonical_failure_evidence_hash_,
            failure_observed_at_
        );
    END IF;

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
            final_reversal_id,
            final_journal.legal_entity_id,
            final_journal.book_id,
            'payment-orchestrator',
            final_reversal_id,
            final_journal.correlation_id,
            canonical.callback_evidence_hash,
            canonical.callback_occurred_at,
            'POSTED',
            'PAYMENT_REVERSAL',
            reversal_event_id_,
            final_journal.loan_id,
            final_journal.journal_id,
            'authenticated provider reversal'
        ),
        (
            provisional_reversal_id,
            provisional_journal.legal_entity_id,
            provisional_journal.book_id,
            'payment-orchestrator',
            provisional_reversal_id,
            provisional_journal.correlation_id,
            canonical.callback_evidence_hash,
            canonical.callback_occurred_at,
            'POSTED',
            'PAYMENT_REVERSAL',
            reversal_event_id_,
            provisional_journal.loan_id,
            provisional_journal.journal_id,
            'authenticated provider reversal'
        );

    INSERT INTO journal_entry (
        journal_id,
        line_number,
        account_code,
        side,
        asset_id,
        units,
        party_id,
        loan_id,
        tranche_id
    )
    SELECT
        CASE original.journal_id
            WHEN final_journal.journal_id THEN final_reversal_id
            ELSE provisional_reversal_id
        END,
        original.line_number,
        original.account_code,
        CASE original.side WHEN 'DEBIT' THEN 'CREDIT' ELSE 'DEBIT' END,
        original.asset_id,
        original.units,
        original.party_id,
        original.loan_id,
        original.tranche_id
    FROM journal_entry AS original
    WHERE original.journal_id IN (
        final_journal.journal_id,
        provisional_journal.journal_id
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
    ) VALUES (
        reversal_event_id_,
        payment_id_,
        quarantine.provider_id,
        quarantine.provider_event_id,
        final_event.aggregate_version + 1,
        'FINAL',
        'REVERSED',
        canonical.asset_id,
        canonical.units,
        canonical.callback_evidence_hash,
        reversal_journal_ids,
        canonical.callback_occurred_at,
        quarantine.received_at
    );

    INSERT INTO payment_callback_quarantine_resolution (
        resolution_id,
        quarantine_id,
        evidence_hash,
        resolved_by,
        resolved_at
    ) VALUES (
        resolution_id_,
        quarantine_id_,
        resolution_evidence_hash_,
        resolved_by_,
        resolved_at_
    );

    INSERT INTO canonical_pending_reversal_resolution_evidence (
        resolution_id,
        quarantine_id,
        origin_state,
        failure_evidence_hash
    ) VALUES (
        resolution_id_,
        quarantine_id_,
        origin_state_,
        canonical_failure_evidence_hash_
    );

    UPDATE canonical_coordinator_state
    SET state = 'FAILED',
        version = next_version_,
        snapshot = next_snapshot_,
        tombstoned = true,
        pending_reversal = false,
        updated_at = resolved_at_
    WHERE payment_id = payment_id_
      AND state = 'QUARANTINED'
      AND version = expected_version_
      AND pending_reversal
      AND NOT tombstoned;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    INSERT INTO canonical_coordinator_state_history (
        payment_id,
        allocation_id,
        instruction_digest,
        version,
        state,
        snapshot,
        tombstoned,
        pending_reversal,
        evidence_hash,
        occurred_at
    ) VALUES (
        payment_id_,
        allocation_id_,
        instruction_digest_,
        next_version_,
        'FAILED',
        next_snapshot_,
        true,
        false,
        resolution_evidence_hash_,
        resolved_at_
    );

    INSERT INTO canonical_allocation_tombstone (
        payment_id,
        allocation_id,
        instruction_digest,
        quarantine_id,
        reversal_event_id,
        evidence_hash,
        occurred_at
    ) VALUES (
        payment_id_,
        allocation_id_,
        instruction_digest_,
        quarantine_id_,
        reversal_event_id_,
        resolution_evidence_hash_,
        resolved_at_
    );
    RETURN reversal_journal_ids;
END;
$$;

-- Upgrade pre-Phase-7C allocations into the same authoritative claim table used by
-- all future allocation paths. Both modes now contend on one UNIQUE payment_id row,
-- so concurrent attempts cannot pass independent cross-table visibility checks.
INSERT INTO payment_allocation_mode_claim (
    claim_id,
    payment_id,
    allocation_id,
    allocation_mode,
    expected_version,
    claimed_version,
    prior_allocation_absent,
    prior_allocation_journal_count,
    instruction_digest,
    claim_digest,
    claim_digest_kind,
    evidence_hash,
    claimed_at
)
SELECT
    'phase7b:' || allocation.allocation_id,
    allocation.payment_id,
    allocation.allocation_id,
    'SYNTHETIC_PROJECTION',
    allocation.obligation_version_before,
    allocation.obligation_version_before + 1,
    true,
    0,
    NULL,
    'legacy-lock:' || encode(
        sha256(
            convert_to('UNIFIED_PHASE7B_LEGACY_NON_REPLAYABLE_LOCK_V1', 'UTF8')
            || decode('00', 'hex')
            || convert_to(
                '{"AllocationID":' || to_json(allocation.allocation_id)::text
                || ',"PaymentID":' || to_json(allocation.payment_id)::text
                || ',"LoanID":' || to_json(allocation.loan_id)::text
                || ',"GrossUnits":' || to_json(allocation.gross_units::text)::text
                || ',"DebtBefore":' || to_json(allocation.debt_before_units::text)::text
                || ',"EvidenceHash":' || to_json(allocation.evidence_hash)::text
                || '}',
                'UTF8'
            )
        ),
        'hex'
    ),
    'LEGACY_NON_REPLAYABLE',
    allocation.evidence_hash,
    allocation.allocated_at
FROM final_payment_allocation AS allocation;

DROP TRIGGER final_payment_allocation_immutable ON final_payment_allocation;

ALTER TABLE final_payment_allocation
    ADD COLUMN claim_id text;

UPDATE final_payment_allocation
SET claim_id = 'phase7b:' || allocation_id;

ALTER TABLE final_payment_allocation
    ALTER COLUMN claim_id SET NOT NULL,
    ADD CONSTRAINT final_payment_allocation_claim_unique UNIQUE (claim_id),
    ADD CONSTRAINT final_payment_allocation_claim_fk
        FOREIGN KEY (claim_id) REFERENCES payment_allocation_mode_claim(claim_id);

CREATE FUNCTION enforce_synthetic_allocation_claim() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = NEW.payment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payment % does not exist', NEW.payment_id;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM canonical_allocation_tombstone
        WHERE payment_id = NEW.payment_id
    ) THEN
        RAISE EXCEPTION 'payment % was already reversed', NEW.payment_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim AS claim
        WHERE claim.claim_id = NEW.claim_id
          AND claim.payment_id = NEW.payment_id
          AND claim.allocation_id = NEW.allocation_id
          AND claim.allocation_mode = 'SYNTHETIC_PROJECTION'
          AND claim.instruction_digest IS NULL
          AND claim.prior_allocation_absent
          AND claim.prior_allocation_journal_count = 0
    ) THEN
        RAISE EXCEPTION
            'allocation % does not own the authoritative synthetic claim',
            NEW.allocation_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER final_payment_allocation_requires_synthetic_claim
BEFORE INSERT ON final_payment_allocation
FOR EACH ROW EXECUTE FUNCTION enforce_synthetic_allocation_claim();

CREATE TABLE canonicalization_eligibility (
    eligibility_id text PRIMARY KEY,
    claim_id text NOT NULL UNIQUE REFERENCES payment_allocation_mode_claim(claim_id),
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    loan_id text NOT NULL,
    provider_id text NOT NULL,
    provider_reference text NOT NULL,
    payment_final_event_id text NOT NULL UNIQUE
        REFERENCES payment_state_event(event_id),
    source_asset_id text NOT NULL,
    source_units numeric(78, 0) NOT NULL CHECK (source_units > 0),
    target_asset_id text NOT NULL,
    target_units numeric(78, 0) NOT NULL CHECK (target_units > 0),
    reconciliation_id text NOT NULL REFERENCES payment_reconciliation_run(run_id),
    provider_statement_entry_id text NOT NULL,
    original_provisional_journal_id text NOT NULL REFERENCES journal(journal_id),
    original_final_journal_id text NOT NULL REFERENCES journal(journal_id),
    finality_policy_hash text NOT NULL CHECK (
        finality_policy_hash ~ '^0x[0-9a-f]{64}$'
    ),
    conversion_policy_hash text NOT NULL,
    waterfall_policy_hash text NOT NULL,
    policy_set_hash text NOT NULL,
    reversal_deadline timestamptz NOT NULL,
    eligible boolean NOT NULL CHECK (eligible),
    evidence_hash text NOT NULL,
    evaluated_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (source_asset_id <> target_asset_id),
    CHECK (source_units = target_units),
    CHECK (original_provisional_journal_id <> original_final_journal_id),
    CHECK (evaluated_at >= reversal_deadline),
    FOREIGN KEY (reconciliation_id, provider_statement_entry_id)
        REFERENCES payment_provider_statement_entry(run_id, entry_id)
);

CREATE FUNCTION enforce_canonicalization_eligibility() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    expected_pending_account text;
    expected_source_account text;
BEGIN
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = NEW.payment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payment % does not exist', NEW.payment_id;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM canonical_allocation_tombstone
        WHERE payment_id = NEW.payment_id
    ) THEN
        RAISE EXCEPTION 'payment % was already reversed', NEW.payment_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM payment_allocation_mode_claim AS claim
        WHERE claim.claim_id = NEW.claim_id
          AND claim.payment_id = NEW.payment_id
          AND claim.allocation_id IS NOT NULL
          AND claim.allocation_mode = 'CANONICAL_GATEWAY'
          AND claim.instruction_digest IS NOT NULL
          AND claim.prior_allocation_absent
          AND claim.prior_allocation_journal_count = 0
    ) THEN
        RAISE EXCEPTION 'payment % lacks a canonical allocation claim', NEW.payment_id;
    END IF;

    SELECT
        CASE intent.rail WHEN 'CARD' THEN '9130' ELSE '9140' END,
        CASE intent.rail WHEN 'CARD' THEN '1120' ELSE '1100' END
    INTO expected_pending_account, expected_source_account
    FROM payment_intent AS intent
    JOIN payment_state_event AS final_event
      ON final_event.event_id = NEW.payment_final_event_id
     AND final_event.payment_id = intent.payment_id
    JOIN payment_reconciliation_run AS reconciliation
      ON reconciliation.run_id = NEW.reconciliation_id
    JOIN payment_provider_statement_entry AS statement
      ON statement.run_id = reconciliation.run_id
     AND statement.entry_id = NEW.provider_statement_entry_id
    WHERE intent.payment_id = NEW.payment_id
      AND intent.loan_id = NEW.loan_id
      AND intent.provider_id = NEW.provider_id
      AND intent.asset_id = NEW.source_asset_id
      AND intent.units = NEW.source_units
      AND final_event.provider_id = NEW.provider_id
      AND final_event.to_status = 'FINAL'
      AND final_event.asset_id = NEW.source_asset_id
      AND final_event.units = NEW.source_units
      AND final_event.journal_ids = ARRAY[NEW.original_final_journal_id]::text[]
      AND NOT EXISTS (
          SELECT 1
          FROM payment_state_event AS later
          WHERE later.payment_id = final_event.payment_id
            AND later.aggregate_version > final_event.aggregate_version
      )
      AND reconciliation.provider_id = NEW.provider_id
      AND reconciliation.asset_id = NEW.source_asset_id
      AND reconciliation.status = 'MATCHED'
      AND reconciliation.difference_units = 0
      AND reconciliation.unmatched_items = 0
      AND reconciliation.as_of >= final_event.occurred_at
      AND statement.provider_id = NEW.provider_id
      AND statement.provider_reference = NEW.provider_reference
      AND statement.payment_id = NEW.payment_id
      AND statement.asset_id = NEW.source_asset_id
      AND statement.units = NEW.source_units
      AND statement.statement_kind = 'SETTLED'
      AND statement.occurred_at <= reconciliation.as_of;

    IF expected_pending_account IS NULL OR expected_source_account IS NULL THEN
        RAISE EXCEPTION
            'payment % lacks authoritative final, reconciliation, or statement evidence',
            NEW.payment_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM payment_state_event AS provisional_event
        WHERE provisional_event.payment_id = NEW.payment_id
          AND provisional_event.provider_id = NEW.provider_id
          AND provisional_event.to_status = 'PROVISIONAL'
          AND provisional_event.asset_id = NEW.source_asset_id
          AND provisional_event.units = NEW.source_units
          AND provisional_event.journal_ids
              = ARRAY[NEW.original_provisional_journal_id]::text[]
          AND provisional_event.aggregate_version < (
              SELECT final_event.aggregate_version
              FROM payment_state_event AS final_event
              WHERE final_event.event_id = NEW.payment_final_event_id
          )
    ) THEN
        RAISE EXCEPTION 'payment % lacks its exact provisional source event', NEW.payment_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM journal AS provisional
        WHERE provisional.journal_id = NEW.original_provisional_journal_id
          AND provisional.journal_id = 'payment:' || NEW.payment_id || ':provisional'
          AND provisional.source_system = 'payment-orchestrator'
          AND provisional.entry_type = 'PAYMENT_PROVISIONAL'
          AND provisional.loan_id = NEW.loan_id
          AND (
              SELECT count(*)
              FROM journal_entry AS entry
              WHERE entry.journal_id = provisional.journal_id
          ) = 2
          AND EXISTS (
              SELECT 1
              FROM journal_entry AS entry
              JOIN payment_intent AS intent ON intent.payment_id = NEW.payment_id
              WHERE entry.journal_id = provisional.journal_id
                AND entry.account_code = expected_pending_account
                AND entry.side = 'DEBIT'
                AND entry.asset_id = NEW.source_asset_id
                AND entry.units = NEW.source_units
                AND entry.party_id = intent.payer_reference
                AND entry.loan_id = NEW.loan_id
          )
          AND EXISTS (
              SELECT 1
              FROM journal_entry AS entry
              JOIN payment_intent AS intent ON intent.payment_id = NEW.payment_id
              WHERE entry.journal_id = provisional.journal_id
                AND entry.account_code = '9120'
                AND entry.side = 'CREDIT'
                AND entry.asset_id = NEW.source_asset_id
                AND entry.units = NEW.source_units
                AND entry.party_id = intent.payer_reference
                AND entry.loan_id = NEW.loan_id
          )
    ) OR NOT EXISTS (
        SELECT 1
        FROM journal AS final
        WHERE final.journal_id = NEW.original_final_journal_id
          AND final.journal_id = 'payment:' || NEW.payment_id || ':final'
          AND final.source_system = 'payment-orchestrator'
          AND final.entry_type = 'PAYMENT_FINAL'
          AND final.loan_id = NEW.loan_id
          AND (
              SELECT count(*)
              FROM journal_entry AS entry
              WHERE entry.journal_id = final.journal_id
          ) = 2
          AND EXISTS (
              SELECT 1
              FROM journal_entry AS entry
              JOIN payment_intent AS intent ON intent.payment_id = NEW.payment_id
              WHERE entry.journal_id = final.journal_id
                AND entry.account_code = expected_source_account
                AND entry.side = 'DEBIT'
                AND entry.asset_id = NEW.source_asset_id
                AND entry.units = NEW.source_units
                AND entry.party_id = intent.payer_reference
                AND entry.loan_id = NEW.loan_id
          )
          AND EXISTS (
              SELECT 1
              FROM journal_entry AS entry
              JOIN payment_intent AS intent ON intent.payment_id = NEW.payment_id
              WHERE entry.journal_id = final.journal_id
                AND entry.account_code = expected_pending_account
                AND entry.side = 'CREDIT'
                AND entry.asset_id = NEW.source_asset_id
                AND entry.units = NEW.source_units
                AND entry.party_id = intent.payer_reference
                AND entry.loan_id = NEW.loan_id
          )
    ) OR EXISTS (
        SELECT 1
        FROM journal AS reversal
        WHERE reversal.reversal_of IN (
            NEW.original_provisional_journal_id,
            NEW.original_final_journal_id
        )
    ) THEN
        RAISE EXCEPTION
            'payment % source journals are not exact, payment-specific, and unreversed',
            NEW.payment_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonicalization_eligibility_source_guard
BEFORE INSERT ON canonicalization_eligibility
FOR EACH ROW EXECUTE FUNCTION enforce_canonicalization_eligibility();

CREATE TABLE canonicalization_plan (
    canonicalization_id text PRIMARY KEY,
    eligibility_id text NOT NULL UNIQUE
        REFERENCES canonicalization_eligibility(eligibility_id),
    claim_id text NOT NULL UNIQUE REFERENCES payment_allocation_mode_claim(claim_id),
    allocation_id text NOT NULL UNIQUE,
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    loan_id text NOT NULL,
    source_asset_id text NOT NULL,
    source_units numeric(78, 0) NOT NULL CHECK (source_units > 0),
    target_asset_id text NOT NULL,
    target_units numeric(78, 0) NOT NULL CHECK (target_units > 0),
    reconciliation_id text NOT NULL REFERENCES payment_reconciliation_run(run_id),
    debt_before_units numeric(78, 0) NOT NULL CHECK (debt_before_units > 0),
    principal_units numeric(78, 0) NOT NULL CHECK (principal_units > 0),
    refundable_excess_units numeric(78, 0) NOT NULL
        CHECK (refundable_excess_units >= 0),
    debt_after_units numeric(78, 0) NOT NULL CHECK (debt_after_units >= 0),
    expected_state_nonce bigint NOT NULL CHECK (expected_state_nonce > 0),
    finalizer_id text NOT NULL,
    borrower_id text NOT NULL,
    lender_id text NOT NULL,
    target_chain_domain text NOT NULL,
    chain_id bigint NOT NULL CHECK (chain_id > 0),
    gateway_address text NOT NULL,
    loan_account text NOT NULL,
    target_token text NOT NULL,
    accounting_attester_id text NOT NULL,
    provider_id_hash text NOT NULL,
    provider_reference_hash text NOT NULL,
    reconciliation_commitment text NOT NULL,
    original_journal_set_hash text NOT NULL,
    conversion_policy_hash text NOT NULL,
    finality_policy_hash text NOT NULL,
    policy_set_hash text NOT NULL,
    instruction_evidence_hash text NOT NULL,
    journal_ref text NOT NULL,
    provider_finalized_at bigint NOT NULL CHECK (provider_finalized_at > 0),
    reversal_deadline bigint NOT NULL CHECK (reversal_deadline > provider_finalized_at),
    instruction_digest text NOT NULL UNIQUE,
    accounting_attestation_hash text NOT NULL,
    evidence_hash text NOT NULL,
    prepared_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (source_asset_id <> target_asset_id),
    CHECK (source_units = target_units),
    CHECK (target_units = principal_units + refundable_excess_units),
    CHECK (debt_before_units = principal_units + debt_after_units),
    CHECK (borrower_id <> lender_id),
    CHECK (finalizer_id <> borrower_id),
    CHECK (finalizer_id <> lender_id),
    CHECK (accounting_attester_id <> finalizer_id)
);

CREATE FUNCTION enforce_eligible_canonicalization_plan() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM canonicalization_eligibility AS eligibility
        JOIN payment_allocation_mode_claim AS claim
          ON claim.claim_id = eligibility.claim_id
        JOIN canonical_coordinator_state AS coordinator
          ON coordinator.payment_id = claim.payment_id
        WHERE eligibility.eligibility_id = NEW.eligibility_id
          AND eligibility.claim_id = NEW.claim_id
          AND eligibility.payment_id = NEW.payment_id
          AND eligibility.loan_id = NEW.loan_id
          AND eligibility.source_asset_id = NEW.source_asset_id
          AND eligibility.source_units = NEW.source_units
          AND eligibility.target_asset_id = NEW.target_asset_id
          AND eligibility.target_units = NEW.target_units
          AND eligibility.reconciliation_id = NEW.reconciliation_id
          AND eligibility.provider_id = (
              SELECT intent.provider_id
              FROM payment_intent AS intent
              WHERE intent.payment_id = NEW.payment_id
          )
          AND eligibility.finality_policy_hash = NEW.finality_policy_hash
          AND eligibility.conversion_policy_hash = NEW.conversion_policy_hash
          AND eligibility.policy_set_hash = NEW.policy_set_hash
          AND eligibility.evidence_hash = NEW.instruction_evidence_hash
          AND eligibility.reversal_deadline = to_timestamp(NEW.reversal_deadline)
          AND NEW.provider_finalized_at < NEW.reversal_deadline
          AND eligibility.eligible
          AND claim.payment_id = NEW.payment_id
          AND claim.allocation_id = NEW.allocation_id
          AND claim.allocation_mode = 'CANONICAL_GATEWAY'
          AND claim.instruction_digest = NEW.instruction_digest
          AND coordinator.allocation_id = NEW.allocation_id
          AND coordinator.instruction_digest = NEW.instruction_digest
          AND coordinator.state = 'PREPARED'
          AND NOT coordinator.tombstoned
          AND NOT coordinator.pending_reversal
    ) THEN
        RAISE EXCEPTION 'canonicalization plan is not backed by exact eligible evidence';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonicalization_plan_eligibility_guard
BEFORE INSERT ON canonicalization_plan
FOR EACH ROW EXECUTE FUNCTION enforce_eligible_canonicalization_plan();

CREATE TABLE canonicalization_submission (
    submission_id text PRIMARY KEY,
    canonicalization_id text NOT NULL REFERENCES canonicalization_plan(canonicalization_id),
    attempt_number integer NOT NULL CHECK (attempt_number > 0),
    state text NOT NULL CHECK (
        state IN ('SUBMITTED', 'FAILED', 'QUARANTINED')
    ),
    target_chain_domain text NOT NULL,
    gateway_address text NOT NULL,
    sender_id text NOT NULL,
    sender_nonce numeric(78, 0) NOT NULL CHECK (sender_nonce >= 0),
    calldata_hash text NOT NULL,
    transaction_hash text NOT NULL UNIQUE,
    evidence_hash text NOT NULL,
    submitted_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (canonicalization_id, attempt_number)
);

CREATE TABLE canonical_settlement_conversion (
    conversion_id text PRIMARY KEY,
    canonicalization_id text NOT NULL UNIQUE
        REFERENCES canonicalization_plan(canonicalization_id),
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    provider_id text NOT NULL,
    provider_reference text NOT NULL,
    source_asset_id text NOT NULL,
    source_units numeric(78, 0) NOT NULL CHECK (source_units > 0),
    target_asset_id text NOT NULL,
    target_units numeric(78, 0) NOT NULL CHECK (target_units > 0),
    rate_numerator numeric(78, 0) NOT NULL CHECK (rate_numerator = 1),
    rate_denominator numeric(78, 0) NOT NULL CHECK (rate_denominator = 1),
    fee_units numeric(78, 0) NOT NULL CHECK (fee_units = 0),
    slippage_units numeric(78, 0) NOT NULL CHECK (slippage_units = 0),
    rounding_units numeric(78, 0) NOT NULL CHECK (rounding_units = 0),
    source_account_code text NOT NULL CHECK (source_account_code IN ('1100', '1120')),
    original_provisional_journal_id text NOT NULL REFERENCES journal(journal_id),
    original_final_journal_id text NOT NULL REFERENCES journal(journal_id),
    finalizer_id text NOT NULL,
    gateway_transaction_hash text NOT NULL,
    provider_asset_irrevocably_acquired boolean NOT NULL CHECK (
        provider_asset_irrevocably_acquired
    ),
    later_reversal_risk_assumed boolean NOT NULL CHECK (
        later_reversal_risk_assumed
    ),
    evidence_hash text NOT NULL,
    converted_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (source_asset_id <> target_asset_id),
    CHECK (source_units = target_units),
    CHECK (original_provisional_journal_id <> original_final_journal_id)
);

CREATE FUNCTION enforce_canonical_settlement_conversion() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM canonicalization_plan AS plan
        JOIN canonicalization_eligibility AS eligibility
          ON eligibility.eligibility_id = plan.eligibility_id
        JOIN canonicalization_submission AS submission
          ON submission.canonicalization_id = plan.canonicalization_id
        WHERE plan.canonicalization_id = NEW.canonicalization_id
          AND plan.payment_id = NEW.payment_id
          AND plan.finalizer_id = NEW.finalizer_id
          AND plan.source_asset_id = NEW.source_asset_id
          AND plan.source_units = NEW.source_units
          AND plan.target_asset_id = NEW.target_asset_id
          AND plan.target_units = NEW.target_units
          AND eligibility.provider_id = NEW.provider_id
          AND eligibility.provider_reference = NEW.provider_reference
          AND eligibility.original_provisional_journal_id
              = NEW.original_provisional_journal_id
          AND eligibility.original_final_journal_id
              = NEW.original_final_journal_id
          AND submission.state = 'SUBMITTED'
          AND submission.transaction_hash = NEW.gateway_transaction_hash
          AND submission.submitted_at <= NEW.converted_at
    ) THEN
        RAISE EXCEPTION 'conversion does not match its canonicalization plan';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM journal_entry AS entry
        WHERE entry.journal_id = NEW.original_provisional_journal_id
          AND entry.account_code = '9120'
          AND entry.side = 'CREDIT'
          AND entry.asset_id = NEW.source_asset_id
          AND entry.units = NEW.source_units
    ) OR NOT EXISTS (
        SELECT 1
        FROM journal_entry AS entry
        WHERE entry.journal_id = NEW.original_final_journal_id
          AND entry.account_code = NEW.source_account_code
          AND entry.side = 'DEBIT'
          AND entry.asset_id = NEW.source_asset_id
          AND entry.units = NEW.source_units
    ) OR EXISTS (
        SELECT 1
        FROM journal AS reversal
        WHERE reversal.reversal_of IN (
            NEW.original_provisional_journal_id,
            NEW.original_final_journal_id
        )
    ) THEN
        RAISE EXCEPTION 'conversion source journals are not exact and unreversed';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_settlement_conversion_source_guard
BEFORE INSERT ON canonical_settlement_conversion
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_settlement_conversion();

-- Lossless, finalized projection of the canonical gateway log. This is the durable
-- recipient and chain authority used by confirmation; pre-chain plan parties are never
-- sufficient to establish payout or refund provenance.
CREATE TABLE canonical_gateway_event_projection (
    gateway_event_id text PRIMARY KEY,
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    allocation_id text NOT NULL UNIQUE,
    loan_id text NOT NULL,
    instruction_digest text NOT NULL UNIQUE,
    policy_set_hash text NOT NULL,
    loan_account text NOT NULL,
    finalizer_id text NOT NULL,
    accounting_attester_id text NOT NULL,
    source_asset_id text NOT NULL,
    target_asset_id text NOT NULL,
    target_token text NOT NULL,
    source_units numeric(78, 0) NOT NULL CHECK (source_units > 0),
    gross_units numeric(78, 0) NOT NULL CHECK (gross_units > 0),
    provider_id_hash text NOT NULL,
    provider_reference_hash text NOT NULL,
    reconciliation_id text NOT NULL,
    reconciliation_commitment text NOT NULL,
    original_journal_set_hash text NOT NULL,
    conversion_policy_hash text NOT NULL,
    finality_policy_hash text NOT NULL,
    instruction_evidence_hash text NOT NULL,
    journal_ref text NOT NULL,
    provider_finalized_at bigint NOT NULL CHECK (provider_finalized_at > 0),
    reversal_deadline bigint NOT NULL CHECK (reversal_deadline > provider_finalized_at),
    debt_before_units numeric(78, 0) NOT NULL CHECK (debt_before_units > 0),
    principal_units numeric(78, 0) NOT NULL CHECK (principal_units > 0),
    refundable_excess_units numeric(78, 0) NOT NULL
        CHECK (refundable_excess_units >= 0),
    debt_after_units numeric(78, 0) NOT NULL CHECK (debt_after_units >= 0),
    state_nonce_before bigint NOT NULL CHECK (state_nonce_before > 0),
    state_nonce_after bigint NOT NULL CHECK (state_nonce_after > state_nonce_before),
    lender_id text NOT NULL,
    borrower_id text NOT NULL,
    chain_id bigint NOT NULL CHECK (chain_id > 0),
    gateway_address text NOT NULL,
    transaction_hash text NOT NULL,
    log_index integer NOT NULL CHECK (log_index >= 0),
    block_hash text NOT NULL,
    block_number bigint NOT NULL CHECK (block_number > 0),
    raw_payload_hash text NOT NULL,
    confirmation_depth bigint NOT NULL CHECK (confirmation_depth > 0),
    finality_head_block bigint NOT NULL CHECK (finality_head_block > 0),
    finality_head_hash text NOT NULL,
    finality_evidence_hash text NOT NULL,
    transaction_index numeric(20, 0) NOT NULL CHECK (
        transaction_index >= 0
        AND transaction_index <= 18446744073709551615
    ),
    receipts_root text NOT NULL CHECK (
        receipts_root ~ '^0x[0-9a-f]{64}$'
    ),
    inclusion_proof_hash text NOT NULL CHECK (
        inclusion_proof_hash ~ '^0x[0-9a-f]{64}$'
    ),
    header_authority_hash text NOT NULL CHECK (
        header_authority_hash ~ '^0x[0-9a-f]{64}$'
    ),
    receipt_header_signature_hash text NOT NULL CHECK (
        receipt_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    head_header_signature_hash text NOT NULL CHECK (
        head_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    finality_observed_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (transaction_hash, log_index),
    CHECK (source_asset_id <> target_asset_id),
    CHECK (source_units = gross_units),
    CHECK (gross_units = principal_units + refundable_excess_units),
    CHECK (debt_before_units = principal_units + debt_after_units),
    CHECK (borrower_id <> lender_id),
    CHECK (finalizer_id <> borrower_id),
    CHECK (finalizer_id <> lender_id),
    CHECK (accounting_attester_id <> finalizer_id),
    CHECK (finality_head_block >= block_number + confirmation_depth)
);

CREATE FUNCTION enforce_canonical_gateway_event_projection() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    coordinator canonical_coordinator_state%ROWTYPE;
BEGIN
    PERFORM 1
    FROM payment_intent
    WHERE payment_id = NEW.payment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'gateway event payment does not exist';
    END IF;
    SELECT *
    INTO coordinator
    FROM canonical_coordinator_state
    WHERE payment_id = NEW.payment_id
    FOR UPDATE;

    IF NOT EXISTS (
        SELECT 1
        FROM canonicalization_plan AS plan
        JOIN canonicalization_submission AS submission
          ON submission.canonicalization_id = plan.canonicalization_id
        WHERE plan.payment_id = NEW.payment_id
          AND plan.allocation_id = NEW.allocation_id
          AND plan.loan_id = NEW.loan_id
          AND plan.instruction_digest = NEW.instruction_digest
          AND plan.policy_set_hash = NEW.policy_set_hash
          AND plan.loan_account = NEW.loan_account
          AND plan.finalizer_id = NEW.finalizer_id
          AND plan.accounting_attester_id = NEW.accounting_attester_id
          AND plan.source_asset_id = NEW.source_asset_id
          AND plan.target_asset_id = NEW.target_asset_id
          AND plan.target_token = NEW.target_token
          AND plan.source_units = NEW.source_units
          AND plan.target_units = NEW.gross_units
          AND plan.provider_id_hash = NEW.provider_id_hash
          AND plan.provider_reference_hash = NEW.provider_reference_hash
          AND plan.reconciliation_id = NEW.reconciliation_id
          AND plan.reconciliation_commitment = NEW.reconciliation_commitment
          AND plan.original_journal_set_hash = NEW.original_journal_set_hash
          AND plan.conversion_policy_hash = NEW.conversion_policy_hash
          AND plan.finality_policy_hash = NEW.finality_policy_hash
          AND plan.instruction_evidence_hash = NEW.instruction_evidence_hash
          AND plan.journal_ref = NEW.journal_ref
          AND plan.provider_finalized_at = NEW.provider_finalized_at
          AND plan.reversal_deadline = NEW.reversal_deadline
          AND plan.debt_before_units = NEW.debt_before_units
          AND plan.principal_units = NEW.principal_units
          AND plan.refundable_excess_units = NEW.refundable_excess_units
          AND plan.debt_after_units = NEW.debt_after_units
          AND plan.expected_state_nonce = NEW.state_nonce_before
          AND plan.chain_id = NEW.chain_id
          AND plan.gateway_address = NEW.gateway_address
          AND submission.canonicalization_id = plan.canonicalization_id
          AND submission.state = 'SUBMITTED'
          AND submission.target_chain_domain = plan.target_chain_domain
          AND submission.gateway_address = plan.gateway_address
           AND submission.sender_id = plan.finalizer_id
           AND submission.transaction_hash = NEW.transaction_hash
           AND submission.submitted_at <= NEW.finality_observed_at
           AND coordinator.payment_id = plan.payment_id
           AND coordinator.allocation_id = NEW.allocation_id
           AND coordinator.instruction_digest = NEW.instruction_digest
          AND NOT coordinator.tombstoned
          AND (
              (
                  coordinator.state = 'SUBMITTED'
                  AND NOT coordinator.pending_reversal
              )
              OR (
                  coordinator.state = 'QUARANTINED'
                  AND coordinator.pending_reversal
                  AND coordinator.snapshot #>> '{PendingReversal,OriginState}'
                      = 'SUBMITTED'
                  AND (
                      coordinator.snapshot
                          #>> '{PendingReversal,SubmissionChainID}'
                  )::bigint = NEW.chain_id
                  AND coordinator.snapshot
                          #>> '{PendingReversal,SubmissionGateway}'
                      = NEW.gateway_address
                   AND coordinator.snapshot
                           #>> '{PendingReversal,SubmissionTxHash}'
                       = NEW.transaction_hash
               )
              OR (
                  coordinator.state = 'CONFIRMED'
                  AND NOT coordinator.pending_reversal
                  AND coordinator.snapshot #>> '{Confirmation,PaymentID}'
                      = NEW.payment_id
                  AND coordinator.snapshot #>> '{Confirmation,AllocationID}'
                      = NEW.allocation_id
                  AND coordinator.snapshot #>> '{Confirmation,InstructionDigest}'
                      = NEW.instruction_digest
                  AND coordinator.snapshot #>> '{Confirmation,EventID}'
                      = NEW.gateway_event_id
                  AND coordinator.snapshot #>> '{Confirmation,TransactionHash}'
                      = NEW.transaction_hash
                  AND coordinator.snapshot #>> '{Confirmation,GatewayPayloadHash}'
                      = NEW.raw_payload_hash
                  AND coordinator.snapshot #>> '{Confirmation,FinalityEvidenceHash}'
                      = NEW.finality_evidence_hash
                  AND COALESCE(
                      (coordinator.snapshot #>> '{Confirmation,Incident}')::boolean,
                      false
                  ) IS FALSE
              )
              OR (
                  coordinator.state = 'INCIDENT'
                  AND NOT coordinator.pending_reversal
                  AND coordinator.snapshot #>> '{Confirmation,PaymentID}'
                      = NEW.payment_id
                  AND coordinator.snapshot #>> '{Confirmation,AllocationID}'
                      = NEW.allocation_id
                  AND coordinator.snapshot #>> '{Confirmation,InstructionDigest}'
                      = NEW.instruction_digest
                  AND coordinator.snapshot #>> '{Confirmation,EventID}'
                      = NEW.gateway_event_id
                  AND coordinator.snapshot #>> '{Confirmation,TransactionHash}'
                      = NEW.transaction_hash
                  AND coordinator.snapshot #>> '{Confirmation,GatewayPayloadHash}'
                      = NEW.raw_payload_hash
                  AND coordinator.snapshot #>> '{Confirmation,FinalityEvidenceHash}'
                      = NEW.finality_evidence_hash
                  AND COALESCE(
                      (coordinator.snapshot #>> '{Confirmation,Incident}')::boolean,
                      false
                  ) IS TRUE
                  AND coordinator.snapshot
                          #>> '{ConsumedPendingReversal,Pending,OriginState}'
                      = 'SUBMITTED'
              )
           )
    ) THEN
        RAISE EXCEPTION
            'gateway event is not bound to its exact plan, submission, and authority';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_gateway_event_projection_guard
BEFORE INSERT ON canonical_gateway_event_projection
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_gateway_event_projection();

CREATE TABLE canonical_settlement_confirmation (
    confirmation_id text PRIMARY KEY,
    canonicalization_id text NOT NULL UNIQUE
        REFERENCES canonicalization_plan(canonicalization_id),
    submission_id text NOT NULL UNIQUE
        REFERENCES canonicalization_submission(submission_id),
    conversion_id text NOT NULL UNIQUE
        REFERENCES canonical_settlement_conversion(conversion_id),
    allocation_id text NOT NULL UNIQUE,
    payment_id text NOT NULL UNIQUE REFERENCES payment_intent(payment_id),
    loan_id text NOT NULL,
    instruction_digest text NOT NULL UNIQUE,
    borrower_id text NOT NULL,
    lender_id text NOT NULL,
    target_asset_id text NOT NULL,
    target_units numeric(78, 0) NOT NULL CHECK (target_units > 0),
    principal_units numeric(78, 0) NOT NULL CHECK (principal_units > 0),
    refundable_excess_units numeric(78, 0) NOT NULL
        CHECK (refundable_excess_units >= 0),
    debt_before_units numeric(78, 0) NOT NULL CHECK (debt_before_units > 0),
    debt_after_units numeric(78, 0) NOT NULL CHECK (debt_after_units >= 0),
    transaction_hash text NOT NULL UNIQUE,
    gateway_event_id text NOT NULL UNIQUE
        REFERENCES canonical_gateway_event_projection(gateway_event_id),
    block_hash text NOT NULL,
    block_number bigint NOT NULL CHECK (block_number > 0),
    log_index integer NOT NULL CHECK (log_index >= 0),
    chain_finality_depth bigint NOT NULL CHECK (chain_finality_depth > 0),
    finality_head_block bigint NOT NULL CHECK (finality_head_block > 0),
    finality_head_hash text NOT NULL,
    finality_evidence_hash text NOT NULL,
    transaction_index numeric(20, 0) NOT NULL CHECK (
        transaction_index >= 0
        AND transaction_index <= 18446744073709551615
    ),
    receipts_root text NOT NULL CHECK (
        receipts_root ~ '^0x[0-9a-f]{64}$'
    ),
    inclusion_proof_hash text NOT NULL CHECK (
        inclusion_proof_hash ~ '^0x[0-9a-f]{64}$'
    ),
    finality_policy_hash text NOT NULL CHECK (
        finality_policy_hash ~ '^0x[0-9a-f]{64}$'
    ),
    header_authority_hash text NOT NULL CHECK (
        header_authority_hash ~ '^0x[0-9a-f]{64}$'
    ),
    receipt_header_signature_hash text NOT NULL CHECK (
        receipt_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    head_header_signature_hash text NOT NULL CHECK (
        head_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    journal_count integer NOT NULL CHECK (journal_count BETWEEN 7 AND 8),
    raw_payload_hash text NOT NULL,
    confirmed_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (transaction_hash, log_index),
    CHECK (target_units = principal_units + refundable_excess_units),
    CHECK (debt_before_units = principal_units + debt_after_units),
    CHECK (borrower_id <> lender_id),
    CHECK (finality_head_block >= block_number + chain_finality_depth),
    CHECK (
        (refundable_excess_units = 0 AND journal_count = 7)
        OR (refundable_excess_units > 0 AND journal_count = 8)
    )
);

CREATE FUNCTION enforce_canonical_settlement_confirmation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM canonicalization_plan AS plan
        JOIN canonicalization_submission AS submission
          ON submission.submission_id = NEW.submission_id
        JOIN canonical_settlement_conversion AS conversion
          ON conversion.conversion_id = NEW.conversion_id
        JOIN canonical_gateway_event_projection AS event
          ON event.gateway_event_id = NEW.gateway_event_id
        JOIN canonical_coordinator_state AS coordinator
          ON coordinator.payment_id = NEW.payment_id
        WHERE plan.canonicalization_id = NEW.canonicalization_id
          AND plan.allocation_id = NEW.allocation_id
          AND plan.payment_id = NEW.payment_id
          AND plan.loan_id = NEW.loan_id
          AND plan.instruction_digest = NEW.instruction_digest
          AND plan.target_asset_id = NEW.target_asset_id
          AND plan.target_units = NEW.target_units
          AND plan.principal_units = NEW.principal_units
          AND plan.refundable_excess_units = NEW.refundable_excess_units
          AND plan.debt_before_units = NEW.debt_before_units
          AND plan.debt_after_units = NEW.debt_after_units
          AND submission.canonicalization_id = NEW.canonicalization_id
          AND submission.state = 'SUBMITTED'
          AND submission.transaction_hash = NEW.transaction_hash
          AND submission.target_chain_domain = plan.target_chain_domain
          AND submission.gateway_address = plan.gateway_address
          AND submission.sender_id = plan.finalizer_id
          AND conversion.canonicalization_id = NEW.canonicalization_id
          AND conversion.payment_id = NEW.payment_id
          AND conversion.target_asset_id = NEW.target_asset_id
          AND conversion.target_units = NEW.target_units
          AND conversion.gateway_transaction_hash = NEW.transaction_hash
          AND event.payment_id = NEW.payment_id
          AND event.allocation_id = NEW.allocation_id
          AND event.loan_id = NEW.loan_id
          AND event.instruction_digest = NEW.instruction_digest
          AND event.borrower_id = NEW.borrower_id
          AND event.lender_id = NEW.lender_id
          AND event.target_asset_id = NEW.target_asset_id
          AND event.gross_units = NEW.target_units
          AND event.principal_units = NEW.principal_units
          AND event.refundable_excess_units = NEW.refundable_excess_units
          AND event.debt_before_units = NEW.debt_before_units
          AND event.debt_after_units = NEW.debt_after_units
          AND event.transaction_hash = NEW.transaction_hash
          AND event.block_hash = NEW.block_hash
          AND event.block_number = NEW.block_number
          AND event.log_index = NEW.log_index
          AND event.confirmation_depth = NEW.chain_finality_depth
           AND event.finality_head_block = NEW.finality_head_block
           AND event.finality_head_hash = NEW.finality_head_hash
           AND event.finality_evidence_hash = NEW.finality_evidence_hash
           AND event.transaction_index = NEW.transaction_index
           AND event.receipts_root = NEW.receipts_root
           AND event.inclusion_proof_hash = NEW.inclusion_proof_hash
           AND event.finality_policy_hash = NEW.finality_policy_hash
           AND event.header_authority_hash = NEW.header_authority_hash
           AND event.receipt_header_signature_hash =
               NEW.receipt_header_signature_hash
           AND event.head_header_signature_hash =
               NEW.head_header_signature_hash
           AND plan.finality_policy_hash = NEW.finality_policy_hash
           AND event.raw_payload_hash = NEW.raw_payload_hash
           AND event.finality_observed_at = NEW.confirmed_at
           AND submission.submitted_at <= conversion.converted_at
           AND conversion.converted_at <= NEW.confirmed_at
           AND submission.submitted_at <= NEW.confirmed_at
           AND coordinator.allocation_id = NEW.allocation_id
           AND coordinator.instruction_digest = NEW.instruction_digest
           AND NOT coordinator.tombstoned
           AND NOT coordinator.pending_reversal
           AND coordinator.snapshot #>> '{Confirmation,PaymentID}' =
               NEW.payment_id
           AND coordinator.snapshot #>> '{Confirmation,AllocationID}' =
               NEW.allocation_id
           AND coordinator.snapshot #>> '{Confirmation,InstructionDigest}' =
               NEW.instruction_digest
           AND coordinator.snapshot #>> '{Confirmation,EventID}' =
               NEW.gateway_event_id
           AND coordinator.snapshot #>> '{Confirmation,TransactionHash}' =
               NEW.transaction_hash
           AND coordinator.snapshot #>> '{Confirmation,GatewayPayloadHash}' =
               NEW.raw_payload_hash
           AND coordinator.snapshot #>> '{Confirmation,FinalityEvidenceHash}' =
               NEW.finality_evidence_hash
           AND (
               (
                   coordinator.state = 'CONFIRMED'
                   AND COALESCE(
                       (coordinator.snapshot
                           #>> '{Confirmation,Incident}')::boolean,
                       false
                   ) IS FALSE
               )
               OR (
                   coordinator.state = 'INCIDENT'
                   AND COALESCE(
                       (coordinator.snapshot
                           #>> '{Confirmation,Incident}')::boolean,
                       false
                   ) IS TRUE
                   AND coordinator.snapshot
                           #>> '{ConsumedPendingReversal,Pending,OriginState}'
                       = 'SUBMITTED'
               )
           )
    ) THEN
        RAISE EXCEPTION 'confirmation does not match plan submission and conversion';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_settlement_confirmation_execution_guard
BEFORE INSERT ON canonical_settlement_confirmation
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_settlement_confirmation();

CREATE TABLE canonical_settlement_journal_link (
    confirmation_id text NOT NULL
        REFERENCES canonical_settlement_confirmation(confirmation_id),
    ordinal integer NOT NULL CHECK (ordinal BETWEEN 1 AND 8),
    journal_role text NOT NULL CHECK (
        journal_role IN (
            'SOURCE_UNALLOCATED',
            'SOURCE_CONVERTED',
            'TARGET_CUSTODY',
            'TARGET_UNALLOCATED',
            'ALLOCATION',
            'LENDER_CLAIM',
            'LENDER_PAYOUT',
            'BORROWER_REFUND'
        )
    ),
    journal_id text NOT NULL UNIQUE REFERENCES journal(journal_id),
    PRIMARY KEY (confirmation_id, ordinal),
    UNIQUE (confirmation_id, journal_role)
);

CREATE FUNCTION enforce_canonical_settlement_journal_role() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    confirmation canonical_settlement_confirmation%ROWTYPE;
BEGIN
    SELECT *
    INTO confirmation
    FROM canonical_settlement_confirmation AS stored
    WHERE stored.confirmation_id = NEW.confirmation_id;

    IF NOT FOUND OR NOT EXISTS (
        SELECT 1
        FROM journal AS posted
        WHERE posted.journal_id = NEW.journal_id
          AND posted.source_system = 'canonical-settlement'
          AND posted.source_event_id = confirmation.gateway_event_id
          AND posted.loan_id = confirmation.loan_id
    ) THEN
        RAISE EXCEPTION 'canonical journal role is not linked to its gateway confirmation';
    END IF;

    IF NEW.journal_role = 'LENDER_PAYOUT' AND (
        (
            SELECT count(*)
            FROM journal_entry AS entry
            WHERE entry.journal_id = NEW.journal_id
        ) <> 2
        OR NOT EXISTS (
            SELECT 1
            FROM journal_entry AS entry
            WHERE entry.journal_id = NEW.journal_id
              AND entry.account_code = '2130'
              AND entry.side = 'DEBIT'
              AND entry.asset_id = confirmation.target_asset_id
              AND entry.units = confirmation.principal_units
              AND entry.party_id = confirmation.lender_id
              AND entry.loan_id = confirmation.loan_id
        )
        OR NOT EXISTS (
            SELECT 1
            FROM journal_entry AS entry
            WHERE entry.journal_id = NEW.journal_id
              AND entry.account_code = '1260'
              AND entry.side = 'CREDIT'
              AND entry.asset_id = confirmation.target_asset_id
              AND entry.units = confirmation.principal_units
              AND entry.party_id = confirmation.lender_id
              AND entry.loan_id = confirmation.loan_id
        )
    ) THEN
        RAISE EXCEPTION 'lender payout journal role has invalid amount or party provenance';
    END IF;

    IF NEW.journal_role = 'BORROWER_REFUND' AND (
        confirmation.refundable_excess_units = 0
        OR (
            SELECT count(*)
            FROM journal_entry AS entry
            WHERE entry.journal_id = NEW.journal_id
        ) <> 2
        OR NOT EXISTS (
            SELECT 1
            FROM journal_entry AS entry
            WHERE entry.journal_id = NEW.journal_id
              AND entry.account_code = '2150'
              AND entry.side = 'DEBIT'
              AND entry.asset_id = confirmation.target_asset_id
              AND entry.units = confirmation.refundable_excess_units
              AND entry.party_id = confirmation.borrower_id
              AND entry.loan_id = confirmation.loan_id
        )
        OR NOT EXISTS (
            SELECT 1
            FROM journal_entry AS entry
            WHERE entry.journal_id = NEW.journal_id
              AND entry.account_code = '1260'
              AND entry.side = 'CREDIT'
              AND entry.asset_id = confirmation.target_asset_id
              AND entry.units = confirmation.refundable_excess_units
              AND entry.party_id = confirmation.borrower_id
              AND entry.loan_id = confirmation.loan_id
        )
    ) THEN
        RAISE EXCEPTION 'borrower refund journal role has invalid amount or party provenance';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_settlement_journal_role_guard
BEFORE INSERT ON canonical_settlement_journal_link
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_settlement_journal_role();

CREATE TABLE canonical_lender_payout (
    payout_id text PRIMARY KEY,
    confirmation_id text NOT NULL UNIQUE
        REFERENCES canonical_settlement_confirmation(confirmation_id),
    canonicalization_id text NOT NULL UNIQUE
        REFERENCES canonicalization_plan(canonicalization_id),
    loan_id text NOT NULL,
    lender_id text NOT NULL,
    target_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    transaction_hash text NOT NULL,
    gateway_event_id text NOT NULL,
    journal_id text NOT NULL UNIQUE REFERENCES journal(journal_id),
    evidence_hash text NOT NULL,
    paid_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE canonical_borrower_refund (
    refund_id text PRIMARY KEY,
    confirmation_id text NOT NULL UNIQUE
        REFERENCES canonical_settlement_confirmation(confirmation_id),
    canonicalization_id text NOT NULL UNIQUE
        REFERENCES canonicalization_plan(canonicalization_id),
    loan_id text NOT NULL,
    borrower_id text NOT NULL,
    target_asset_id text NOT NULL,
    units numeric(78, 0) NOT NULL CHECK (units > 0),
    transaction_hash text NOT NULL,
    gateway_event_id text NOT NULL,
    journal_id text NOT NULL UNIQUE REFERENCES journal(journal_id),
    evidence_hash text NOT NULL,
    refunded_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE FUNCTION enforce_canonical_payout_or_refund() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    confirmation canonical_settlement_confirmation%ROWTYPE;
BEGIN
    SELECT *
    INTO confirmation
    FROM canonical_settlement_confirmation AS stored
    WHERE stored.confirmation_id = NEW.confirmation_id;
    IF NOT FOUND
       OR confirmation.canonicalization_id <> NEW.canonicalization_id
       OR confirmation.loan_id <> NEW.loan_id
       OR confirmation.target_asset_id <> NEW.target_asset_id
       OR confirmation.transaction_hash <> NEW.transaction_hash
       OR confirmation.gateway_event_id <> NEW.gateway_event_id THEN
        RAISE EXCEPTION 'payout or refund does not match confirmation';
    END IF;
    IF TG_TABLE_NAME = 'canonical_lender_payout' THEN
        IF confirmation.principal_units <> NEW.units
           OR confirmation.lender_id <> NEW.lender_id
           OR NOT EXISTS (
               SELECT 1
               FROM canonical_settlement_journal_link AS link
               WHERE link.confirmation_id = NEW.confirmation_id
                 AND link.journal_role = 'LENDER_PAYOUT'
                 AND link.journal_id = NEW.journal_id
           ) THEN
            RAISE EXCEPTION 'lender payout differs from confirmed principal';
        END IF;
    ELSIF TG_TABLE_NAME = 'canonical_borrower_refund' THEN
        IF confirmation.refundable_excess_units <> NEW.units
           OR confirmation.borrower_id <> NEW.borrower_id
           OR NOT EXISTS (
               SELECT 1
               FROM canonical_settlement_journal_link AS link
               WHERE link.confirmation_id = NEW.confirmation_id
                 AND link.journal_role = 'BORROWER_REFUND'
                 AND link.journal_id = NEW.journal_id
           ) THEN
            RAISE EXCEPTION 'borrower refund differs from confirmed excess';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_lender_payout_confirmation_guard
BEFORE INSERT ON canonical_lender_payout
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_payout_or_refund();

CREATE TRIGGER canonical_borrower_refund_confirmation_guard
BEFORE INSERT ON canonical_borrower_refund
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_payout_or_refund();

CREATE FUNCTION assert_canonical_settlement_complete() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    linked_count integer;
    minimum_ordinal integer;
    maximum_ordinal integer;
    required_role_count integer;
BEGIN
    SELECT count(*), min(ordinal), max(ordinal)
    INTO linked_count, minimum_ordinal, maximum_ordinal
    FROM canonical_settlement_journal_link
    WHERE confirmation_id = NEW.confirmation_id;

    SELECT count(*)
    INTO required_role_count
    FROM canonical_settlement_journal_link
    WHERE confirmation_id = NEW.confirmation_id
      AND journal_role IN (
          'SOURCE_UNALLOCATED',
          'SOURCE_CONVERTED',
          'TARGET_CUSTODY',
          'TARGET_UNALLOCATED',
          'ALLOCATION',
          'LENDER_CLAIM',
          'LENDER_PAYOUT'
      );

    IF linked_count <> NEW.journal_count
       OR minimum_ordinal <> 1
       OR maximum_ordinal <> NEW.journal_count
       OR required_role_count <> 7
       OR NOT EXISTS (
           SELECT 1
           FROM canonical_lender_payout AS payout
           WHERE payout.confirmation_id = NEW.confirmation_id
             AND payout.canonicalization_id = NEW.canonicalization_id
             AND payout.lender_id = NEW.lender_id
             AND payout.units = NEW.principal_units
       )
       OR (
           NEW.refundable_excess_units = 0
           AND (
               EXISTS (
                   SELECT 1
                   FROM canonical_settlement_journal_link AS link
                   WHERE link.confirmation_id = NEW.confirmation_id
                     AND link.journal_role = 'BORROWER_REFUND'
               )
               OR EXISTS (
                   SELECT 1
                   FROM canonical_borrower_refund AS refund
                   WHERE refund.confirmation_id = NEW.confirmation_id
               )
           )
       )
       OR (
           NEW.refundable_excess_units > 0
           AND (
               NOT EXISTS (
                   SELECT 1
                   FROM canonical_settlement_journal_link AS link
                   WHERE link.confirmation_id = NEW.confirmation_id
                     AND link.journal_role = 'BORROWER_REFUND'
               )
               OR NOT EXISTS (
                   SELECT 1
                   FROM canonical_borrower_refund AS refund
                   WHERE refund.confirmation_id = NEW.confirmation_id
                     AND refund.canonicalization_id = NEW.canonicalization_id
                     AND refund.borrower_id = NEW.borrower_id
                     AND refund.units = NEW.refundable_excess_units
               )
           )
       ) THEN
        RAISE EXCEPTION
            'canonical confirmation % lacks its complete journal, payout, or refund evidence',
            NEW.confirmation_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER canonical_settlement_complete_on_commit
AFTER INSERT ON canonical_settlement_confirmation
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_canonical_settlement_complete();

-- Commits the complete canonical-success accounting batch from the exact opaque
-- coordinator confirmation already stored by the payment orchestrator. Every
-- identity other than the conversion evidence and configured target book is
-- derived from immutable database authority. A committed exact retry returns the
-- same result; every conflicting retry raises and rolls back the whole statement.
CREATE FUNCTION commit_canonical_external_settlement(
    confirmation_projection_ jsonb,
    conversion_evidence_hash_ text,
    converted_at_ timestamptz,
    target_book_id_ text
) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    coordinator canonical_coordinator_state%ROWTYPE;
    plan canonicalization_plan%ROWTYPE;
    eligibility canonicalization_eligibility%ROWTYPE;
    submission canonicalization_submission%ROWTYPE;
    intent payment_intent%ROWTYPE;
    original_final journal%ROWTYPE;
    payment_id_ text;
    allocation_id_ text;
    instruction_digest_ text;
    gateway_event_id_ text;
    transaction_hash_ text;
    canonicalization_id_ text;
    conversion_id_ text;
    confirmation_id_ text;
    payout_id_ text;
    refund_id_ text;
    source_book_id_ text;
    source_account_code_ text;
    confirmed_at_ timestamptz;
    transaction_index_ numeric(20, 0);
    log_index_ integer;
    block_number_ bigint;
    finality_head_block_ bigint;
    confirmation_depth_ bigint;
    state_nonce_before_ bigint;
    state_nonce_after_ bigint;
    provider_finalized_at_ bigint;
    reversal_deadline_ bigint;
    source_units_ numeric(78, 0);
    target_units_ numeric(78, 0);
    principal_units_ numeric(78, 0);
    refundable_excess_units_ numeric(78, 0);
    debt_before_units_ numeric(78, 0);
    debt_after_units_ numeric(78, 0);
    journal_count_ integer;
    journal_ids_ text[];
BEGIN
    IF jsonb_typeof(confirmation_projection_) <> 'object'
       OR conversion_evidence_hash_ = ''
       OR converted_at_ IS NULL
       OR target_book_id_ = '' THEN
        RAISE EXCEPTION 'invalid canonical settlement commit envelope';
    END IF;

    payment_id_ := confirmation_projection_ ->> 'PaymentID';
    allocation_id_ := confirmation_projection_ ->> 'AllocationID';
    instruction_digest_ := confirmation_projection_ ->> 'InstructionDigest';
    gateway_event_id_ := confirmation_projection_ ->> 'EventID';
    transaction_hash_ := confirmation_projection_ ->> 'TransactionHash';
    BEGIN
        confirmed_at_ :=
            (confirmation_projection_ ->> 'ConfirmedAt')::timestamptz;
        transaction_index_ :=
            (confirmation_projection_ ->> 'TransactionIndex')::numeric;
        log_index_ := (confirmation_projection_ ->> 'LogIndex')::integer;
        block_number_ := (confirmation_projection_ ->> 'BlockNumber')::bigint;
        finality_head_block_ :=
            (confirmation_projection_ ->> 'FinalityHeadBlock')::bigint;
        confirmation_depth_ :=
            (confirmation_projection_ ->> 'ConfirmationDepth')::bigint;
        state_nonce_before_ :=
            (confirmation_projection_ ->> 'StateNonceBefore')::bigint;
        state_nonce_after_ :=
            (confirmation_projection_ ->> 'StateNonceAfter')::bigint;
        provider_finalized_at_ :=
            (confirmation_projection_ ->> 'ProviderFinalizedAt')::bigint;
        reversal_deadline_ :=
            (confirmation_projection_ ->> 'ReversalDeadlineUnix')::bigint;
        source_units_ :=
            (confirmation_projection_ ->> 'SourceUnits')::numeric;
        target_units_ :=
            (confirmation_projection_ ->> 'TargetUnits')::numeric;
        principal_units_ :=
            (confirmation_projection_ ->> 'PrincipalUnits')::numeric;
        refundable_excess_units_ :=
            (confirmation_projection_ ->> 'RefundableExcessUnits')::numeric;
        debt_before_units_ :=
            (confirmation_projection_ ->> 'DebtBeforeUnits')::numeric;
        debt_after_units_ :=
            (confirmation_projection_ ->> 'DebtAfterUnits')::numeric;
    EXCEPTION
        WHEN invalid_text_representation OR numeric_value_out_of_range
            OR datetime_field_overflow THEN
            RAISE EXCEPTION 'canonical settlement projection has invalid scalar encoding';
    END;

    IF payment_id_ IS NULL OR payment_id_ = ''
       OR allocation_id_ IS NULL OR allocation_id_ = ''
       OR instruction_digest_ IS NULL OR instruction_digest_ = ''
       OR gateway_event_id_ IS NULL OR gateway_event_id_ = ''
       OR transaction_hash_ IS NULL OR transaction_hash_ = ''
       OR confirmed_at_ IS NULL
       OR transaction_index_ IS NULL
       OR log_index_ IS NULL OR block_number_ IS NULL
       OR finality_head_block_ IS NULL OR confirmation_depth_ IS NULL
       OR state_nonce_before_ IS NULL OR state_nonce_after_ IS NULL
       OR provider_finalized_at_ IS NULL OR reversal_deadline_ IS NULL
       OR source_units_ IS NULL OR target_units_ IS NULL
       OR principal_units_ IS NULL OR refundable_excess_units_ IS NULL
       OR debt_before_units_ IS NULL OR debt_after_units_ IS NULL
       OR transaction_index_ < 0
       OR transaction_index_ > 18446744073709551615
       OR log_index_ < 0 OR block_number_ <= 0
       OR confirmation_depth_ <= 0
       OR finality_head_block_ < block_number_ + confirmation_depth_
       OR state_nonce_before_ <= 0
       OR state_nonce_after_ <= state_nonce_before_
       OR provider_finalized_at_ <= 0
       OR reversal_deadline_ <= provider_finalized_at_
       OR source_units_ <= 0 OR target_units_ <= 0
       OR source_units_ <> target_units_
       OR principal_units_ <= 0 OR refundable_excess_units_ < 0
       OR target_units_ <> principal_units_ + refundable_excess_units_
       OR debt_before_units_ <> principal_units_ + debt_after_units_
       OR debt_after_units_ < 0 THEN
        RAISE EXCEPTION 'canonical settlement projection violates scalar invariants';
    END IF;

    PERFORM 1
    FROM payment_intent
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'canonical settlement payment does not exist';
    END IF;

    SELECT *
    INTO coordinator
    FROM canonical_coordinator_state
    WHERE payment_id = payment_id_
    FOR UPDATE;
    IF coordinator.payment_id IS NULL
       OR coordinator.allocation_id <> allocation_id_
       OR coordinator.instruction_digest <> instruction_digest_
       OR coordinator.tombstoned
       OR coordinator.pending_reversal
       OR coordinator.snapshot -> 'Confirmation' IS NULL
       OR coordinator.snapshot -> 'Confirmation' <> confirmation_projection_
       OR NOT (
           (
               coordinator.state = 'CONFIRMED'
               AND COALESCE(
                   (confirmation_projection_ ->> 'Incident')::boolean,
                   false
               ) IS FALSE
           )
           OR (
               coordinator.state = 'INCIDENT'
               AND COALESCE(
                   (confirmation_projection_ ->> 'Incident')::boolean,
                   false
               ) IS TRUE
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,OriginState}'
                   = 'SUBMITTED'
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,PaymentID}'
                   = payment_id_
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,AllocationID}'
                   = allocation_id_
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,InstructionDigest}'
                   = instruction_digest_
               AND (
                   coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,SubmissionChainID}'
               )::bigint =
                   (confirmation_projection_ ->> 'ChainID')::bigint
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,SubmissionGateway}'
                   = confirmation_projection_ ->> 'Gateway'
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,SubmissionTxHash}'
                   = transaction_hash_
               AND (
                   coordinator.snapshot
                       #>> '{ConsumedPendingReversal,Pending,SubmissionSubmittedAt}'
               )::timestamptz <= confirmed_at_
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,ResolutionID}'
                   = 'canonical-success:' || gateway_event_id_
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,ResolutionEvidenceHash}'
                   = confirmation_projection_ ->> 'FinalityEvidenceHash'
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,ResolvedBy}'
                   = 'canonical-chain-indexer'
               AND (
                   coordinator.snapshot
                       #>> '{ConsumedPendingReversal,ResolvedAt}'
               )::timestamptz = confirmed_at_
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,GatewayEventID}'
                   = gateway_event_id_
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,GatewayTransactionHash}'
                   = transaction_hash_
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,GatewayRawPayloadHash}'
                   = confirmation_projection_ ->> 'GatewayPayloadHash'
               AND coordinator.snapshot
                       #>> '{ConsumedPendingReversal,FinalityEvidenceHash}'
                   = confirmation_projection_ ->> 'FinalityEvidenceHash'
           )
       ) THEN
        RAISE EXCEPTION
            'canonical success lacks exact durable coordinator confirmation authority';
    END IF;

    SELECT stored.*
    INTO plan
    FROM canonicalization_plan AS stored
    WHERE stored.payment_id = payment_id_
      AND stored.allocation_id = allocation_id_
      AND stored.instruction_digest = instruction_digest_;
    IF plan.canonicalization_id IS NULL THEN
        RAISE EXCEPTION 'canonical settlement plan does not exist';
    END IF;
    canonicalization_id_ := plan.canonicalization_id;
    conversion_id_ := 'conversion:' || canonicalization_id_;
    confirmation_id_ := 'confirmation:' || canonicalization_id_;
    payout_id_ := 'payout:' || canonicalization_id_;
    refund_id_ := 'refund:' || canonicalization_id_;

    SELECT stored.*
    INTO eligibility
    FROM canonicalization_eligibility AS stored
    WHERE stored.eligibility_id = plan.eligibility_id;
    SELECT stored.*
    INTO submission
    FROM canonicalization_submission AS stored
    WHERE stored.canonicalization_id = canonicalization_id_
      AND stored.state = 'SUBMITTED'
      AND stored.transaction_hash = transaction_hash_;
    SELECT stored.*
    INTO intent
    FROM payment_intent AS stored
    WHERE stored.payment_id = payment_id_;
    SELECT stored.*
    INTO original_final
    FROM journal AS stored
    WHERE stored.journal_id = eligibility.original_final_journal_id;
    SELECT entry.account_code
    INTO source_account_code_
    FROM journal_entry AS entry
    WHERE entry.journal_id = eligibility.original_final_journal_id
      AND entry.side = 'DEBIT'
      AND entry.asset_id = plan.source_asset_id
      AND entry.units = plan.source_units;
    source_book_id_ := original_final.book_id;

    IF eligibility.eligibility_id IS NULL
       OR submission.submission_id IS NULL
       OR intent.payment_id IS NULL
       OR original_final.journal_id IS NULL
       OR source_book_id_ IS NULL OR source_book_id_ = ''
       OR source_account_code_ NOT IN ('1100', '1120')
       OR converted_at_ < submission.submitted_at
       OR converted_at_ > confirmed_at_
       OR confirmed_at_ < submission.submitted_at
       OR confirmation_projection_ ->> 'PaymentID' <> plan.payment_id
       OR confirmation_projection_ ->> 'AllocationID' <> plan.allocation_id
       OR confirmation_projection_ ->> 'LoanID' <> plan.loan_id
       OR confirmation_projection_ ->> 'InstructionDigest' <>
           plan.instruction_digest
       OR confirmation_projection_ ->> 'ProviderID' <> eligibility.provider_id
       OR confirmation_projection_ ->> 'ProviderReference' <>
           eligibility.provider_reference
       OR confirmation_projection_ ->> 'SourceAssetID' <> plan.source_asset_id
       OR source_units_ <> plan.source_units
       OR confirmation_projection_ ->> 'TargetAssetID' <> plan.target_asset_id
       OR target_units_ <> plan.target_units
       OR principal_units_ <> plan.principal_units
       OR refundable_excess_units_ <> plan.refundable_excess_units
       OR debt_before_units_ <> plan.debt_before_units
       OR debt_after_units_ <> plan.debt_after_units
       OR confirmation_projection_ ->> 'FinalityPolicyHash' <>
           plan.finality_policy_hash
       OR confirmation_projection_ ->> 'Gateway' <> plan.gateway_address
       OR confirmation_projection_ ->> 'Finalizer' <> plan.finalizer_id
       OR confirmation_projection_ ->> 'Attester' <>
           plan.accounting_attester_id
       OR confirmation_projection_ ->> 'BorrowerID' <> plan.borrower_id
       OR confirmation_projection_ ->> 'LenderID' <> plan.lender_id
       OR confirmation_projection_ ->> 'CorrelationID' <> intent.correlation_id
       OR (confirmation_projection_ -> 'OriginalJournalIDs') <>
           to_jsonb(ARRAY[
               eligibility.original_provisional_journal_id,
               eligibility.original_final_journal_id
           ]) THEN
        RAISE EXCEPTION
            'canonical coordinator confirmation differs from durable plan authority';
    END IF;

    INSERT INTO canonical_settlement_conversion (
        conversion_id, canonicalization_id, payment_id, provider_id,
        provider_reference, source_asset_id, source_units, target_asset_id,
        target_units, rate_numerator, rate_denominator, fee_units,
        slippage_units, rounding_units, source_account_code,
        original_provisional_journal_id, original_final_journal_id,
        finalizer_id, gateway_transaction_hash,
        provider_asset_irrevocably_acquired, later_reversal_risk_assumed,
        evidence_hash, converted_at
    ) VALUES (
        conversion_id_, canonicalization_id_, payment_id_,
        eligibility.provider_id, eligibility.provider_reference,
        plan.source_asset_id, plan.source_units, plan.target_asset_id,
        plan.target_units, 1, 1, 0, 0, 0, source_account_code_,
        eligibility.original_provisional_journal_id,
        eligibility.original_final_journal_id, plan.finalizer_id,
        transaction_hash_, true, true, conversion_evidence_hash_, converted_at_
    )
    ON CONFLICT DO NOTHING;
    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_conversion AS conversion
        WHERE conversion.conversion_id = conversion_id_
          AND conversion.canonicalization_id = canonicalization_id_
          AND conversion.payment_id = payment_id_
          AND conversion.provider_id = eligibility.provider_id
          AND conversion.provider_reference = eligibility.provider_reference
          AND conversion.source_asset_id = plan.source_asset_id
          AND conversion.source_units = plan.source_units
          AND conversion.target_asset_id = plan.target_asset_id
          AND conversion.target_units = plan.target_units
          AND conversion.rate_numerator = 1
          AND conversion.rate_denominator = 1
          AND conversion.fee_units = 0
          AND conversion.slippage_units = 0
          AND conversion.rounding_units = 0
          AND conversion.original_provisional_journal_id =
              eligibility.original_provisional_journal_id
          AND conversion.original_final_journal_id =
              eligibility.original_final_journal_id
          AND conversion.finalizer_id = plan.finalizer_id
          AND conversion.gateway_transaction_hash = transaction_hash_
          AND conversion.provider_asset_irrevocably_acquired
          AND conversion.later_reversal_risk_assumed
          AND conversion.evidence_hash = conversion_evidence_hash_
          AND conversion.converted_at = converted_at_
          AND conversion.source_account_code = source_account_code_
    ) THEN
        RAISE EXCEPTION 'canonical conversion conflicts with committed evidence';
    END IF;

    INSERT INTO canonical_gateway_event_projection (
        gateway_event_id, payment_id, allocation_id, loan_id,
        instruction_digest, policy_set_hash, loan_account, finalizer_id,
        accounting_attester_id, source_asset_id, target_asset_id, target_token,
        source_units, gross_units, provider_id_hash, provider_reference_hash,
        reconciliation_id, reconciliation_commitment, original_journal_set_hash,
        conversion_policy_hash, finality_policy_hash, instruction_evidence_hash,
        journal_ref, provider_finalized_at, reversal_deadline,
        debt_before_units, principal_units, refundable_excess_units,
        debt_after_units, state_nonce_before, state_nonce_after, lender_id,
        borrower_id, chain_id, gateway_address, transaction_hash, log_index,
        block_hash, block_number, raw_payload_hash, confirmation_depth,
        finality_head_block, finality_head_hash, finality_evidence_hash,
        transaction_index, receipts_root, inclusion_proof_hash,
        header_authority_hash, receipt_header_signature_hash,
        head_header_signature_hash, finality_observed_at
    ) VALUES (
        gateway_event_id_, payment_id_, allocation_id_, plan.loan_id,
        instruction_digest_, plan.policy_set_hash,
        confirmation_projection_ ->> 'LoanAccount', plan.finalizer_id,
        plan.accounting_attester_id, plan.source_asset_id, plan.target_asset_id,
        plan.target_token, source_units_, target_units_,
        plan.provider_id_hash, plan.provider_reference_hash,
        plan.reconciliation_id, plan.reconciliation_commitment,
        plan.original_journal_set_hash, plan.conversion_policy_hash,
        plan.finality_policy_hash, plan.instruction_evidence_hash,
        plan.journal_ref, provider_finalized_at_, reversal_deadline_,
        debt_before_units_, principal_units_, refundable_excess_units_,
        debt_after_units_, state_nonce_before_, state_nonce_after_,
        plan.lender_id, plan.borrower_id,
        (confirmation_projection_ ->> 'ChainID')::bigint,
        plan.gateway_address, transaction_hash_, log_index_,
        confirmation_projection_ ->> 'BlockHash', block_number_,
        confirmation_projection_ ->> 'GatewayPayloadHash',
        confirmation_depth_, finality_head_block_,
        confirmation_projection_ ->> 'FinalityHeadHash',
        confirmation_projection_ ->> 'FinalityEvidenceHash',
        transaction_index_, confirmation_projection_ ->> 'ReceiptsRoot',
        confirmation_projection_ ->> 'InclusionProofHash',
        confirmation_projection_ ->> 'HeaderAuthorityHash',
        confirmation_projection_ ->> 'ReceiptHeaderSignatureHash',
        confirmation_projection_ ->> 'HeadHeaderSignatureHash',
        confirmed_at_
    )
    ON CONFLICT DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_gateway_event_projection AS event
        WHERE event.gateway_event_id = gateway_event_id_
          AND event.payment_id = payment_id_
          AND event.allocation_id = allocation_id_
          AND event.loan_id = plan.loan_id
          AND event.instruction_digest = instruction_digest_
          AND event.policy_set_hash = plan.policy_set_hash
          AND event.loan_account =
              confirmation_projection_ ->> 'LoanAccount'
          AND event.finalizer_id = plan.finalizer_id
          AND event.accounting_attester_id = plan.accounting_attester_id
          AND event.source_asset_id = plan.source_asset_id
          AND event.target_asset_id = plan.target_asset_id
          AND event.target_token = plan.target_token
          AND event.source_units = source_units_
          AND event.gross_units = target_units_
          AND event.provider_id_hash = plan.provider_id_hash
          AND event.provider_reference_hash = plan.provider_reference_hash
          AND event.reconciliation_id = plan.reconciliation_id
          AND event.reconciliation_commitment =
              plan.reconciliation_commitment
          AND event.original_journal_set_hash =
              plan.original_journal_set_hash
          AND event.conversion_policy_hash = plan.conversion_policy_hash
          AND event.finality_policy_hash = plan.finality_policy_hash
          AND event.instruction_evidence_hash =
              plan.instruction_evidence_hash
          AND event.journal_ref = plan.journal_ref
          AND event.provider_finalized_at = provider_finalized_at_
          AND event.reversal_deadline = reversal_deadline_
          AND event.debt_before_units = debt_before_units_
          AND event.principal_units = principal_units_
          AND event.refundable_excess_units = refundable_excess_units_
          AND event.debt_after_units = debt_after_units_
          AND event.state_nonce_before = state_nonce_before_
          AND event.state_nonce_after = state_nonce_after_
          AND event.lender_id = plan.lender_id
          AND event.borrower_id = plan.borrower_id
          AND event.chain_id =
              (confirmation_projection_ ->> 'ChainID')::bigint
          AND event.gateway_address = plan.gateway_address
          AND event.transaction_hash = transaction_hash_
          AND event.log_index = log_index_
          AND event.block_hash =
              confirmation_projection_ ->> 'BlockHash'
          AND event.block_number = block_number_
          AND event.raw_payload_hash =
              confirmation_projection_ ->> 'GatewayPayloadHash'
          AND event.confirmation_depth = confirmation_depth_
          AND event.finality_head_block = finality_head_block_
          AND event.finality_head_hash =
              confirmation_projection_ ->> 'FinalityHeadHash'
          AND event.finality_evidence_hash =
              confirmation_projection_ ->> 'FinalityEvidenceHash'
          AND event.transaction_index = transaction_index_
          AND event.receipts_root =
              confirmation_projection_ ->> 'ReceiptsRoot'
          AND event.inclusion_proof_hash =
              confirmation_projection_ ->> 'InclusionProofHash'
          AND event.header_authority_hash =
              confirmation_projection_ ->> 'HeaderAuthorityHash'
          AND event.receipt_header_signature_hash =
              confirmation_projection_ ->> 'ReceiptHeaderSignatureHash'
          AND event.head_header_signature_hash =
              confirmation_projection_ ->> 'HeadHeaderSignatureHash'
          AND event.finality_observed_at = confirmed_at_
    ) THEN
        RAISE EXCEPTION 'canonical gateway event conflicts with committed evidence';
    END IF;

    journal_count_ := CASE
        WHEN refundable_excess_units_ = 0 THEN 7
        ELSE 8
    END;
    journal_ids_ := ARRAY[
        'canonical:' || canonicalization_id_ || ':source-unallocated',
        'canonical:' || canonicalization_id_ || ':source-converted',
        'canonical:' || canonicalization_id_ || ':target-custody',
        'canonical:' || canonicalization_id_ || ':target-unallocated',
        'canonical:' || canonicalization_id_ || ':allocation',
        'canonical:' || canonicalization_id_ || ':lender-claim',
        'canonical:' || canonicalization_id_ || ':lender-payout'
    ];
    IF refundable_excess_units_ > 0 THEN
        journal_ids_ := journal_ids_ ||
            ('canonical:' || canonicalization_id_ || ':borrower-refund');
    END IF;

    INSERT INTO canonical_settlement_confirmation (
        confirmation_id, canonicalization_id, submission_id, conversion_id,
        allocation_id, payment_id, loan_id, instruction_digest, borrower_id,
        lender_id, target_asset_id, target_units, principal_units,
        refundable_excess_units, debt_before_units, debt_after_units,
        transaction_hash, gateway_event_id, block_hash, block_number, log_index,
        chain_finality_depth, finality_head_block, finality_head_hash,
        finality_evidence_hash, transaction_index, receipts_root,
        inclusion_proof_hash, finality_policy_hash, header_authority_hash,
        receipt_header_signature_hash, head_header_signature_hash,
        journal_count, raw_payload_hash, confirmed_at
    ) VALUES (
        confirmation_id_, canonicalization_id_, submission.submission_id,
        conversion_id_, allocation_id_, payment_id_, plan.loan_id,
        instruction_digest_, plan.borrower_id, plan.lender_id,
        plan.target_asset_id, target_units_, principal_units_,
        refundable_excess_units_, debt_before_units_, debt_after_units_,
        transaction_hash_, gateway_event_id_,
        confirmation_projection_ ->> 'BlockHash', block_number_, log_index_,
        confirmation_depth_, finality_head_block_,
        confirmation_projection_ ->> 'FinalityHeadHash',
        confirmation_projection_ ->> 'FinalityEvidenceHash',
        transaction_index_, confirmation_projection_ ->> 'ReceiptsRoot',
        confirmation_projection_ ->> 'InclusionProofHash',
        plan.finality_policy_hash,
        confirmation_projection_ ->> 'HeaderAuthorityHash',
        confirmation_projection_ ->> 'ReceiptHeaderSignatureHash',
        confirmation_projection_ ->> 'HeadHeaderSignatureHash',
        journal_count_, confirmation_projection_ ->> 'GatewayPayloadHash',
        confirmed_at_
    )
    ON CONFLICT DO NOTHING;

    INSERT INTO journal (
        journal_id, legal_entity_id, book_id, source_system, idempotency_key,
        correlation_id, evidence_hash, effective_at, status, entry_type,
        source_event_id, loan_id
    ) VALUES
        (journal_ids_[1], original_final.legal_entity_id, source_book_id_,
         'canonical-settlement',
         'payment:' || payment_id_ || ':canonical:' || canonicalization_id_ ||
             ':source-unallocated',
         intent.correlation_id, confirmation_projection_ ->> 'GatewayPayloadHash',
         confirmed_at_, 'POSTED', 'CANONICAL_SOURCE_CLEARED',
         gateway_event_id_, plan.loan_id),
        (journal_ids_[2], original_final.legal_entity_id, source_book_id_,
         'canonical-settlement',
         'payment:' || payment_id_ || ':canonical:' || canonicalization_id_ ||
             ':source-converted',
         intent.correlation_id, confirmation_projection_ ->> 'GatewayPayloadHash',
         confirmed_at_, 'POSTED', 'CANONICAL_SOURCE_CONVERTED',
         gateway_event_id_, plan.loan_id),
        (journal_ids_[3], original_final.legal_entity_id, target_book_id_,
         'canonical-settlement',
         'payment:' || payment_id_ || ':canonical:' || canonicalization_id_ ||
             ':target-custody',
         intent.correlation_id, confirmation_projection_ ->> 'GatewayPayloadHash',
         confirmed_at_, 'POSTED', 'CANONICAL_TARGET_CUSTODY',
         gateway_event_id_, plan.loan_id),
        (journal_ids_[4], original_final.legal_entity_id, target_book_id_,
         'canonical-settlement',
         'payment:' || payment_id_ || ':canonical:' || canonicalization_id_ ||
             ':target-unallocated',
         intent.correlation_id, confirmation_projection_ ->> 'GatewayPayloadHash',
         confirmed_at_, 'POSTED', 'CANONICAL_TARGET_UNALLOCATED',
         gateway_event_id_, plan.loan_id),
        (journal_ids_[5], original_final.legal_entity_id, target_book_id_,
         'canonical-settlement',
         'payment:' || payment_id_ || ':canonical:' || canonicalization_id_ ||
             ':allocation',
         intent.correlation_id, confirmation_projection_ ->> 'GatewayPayloadHash',
         confirmed_at_, 'POSTED', 'CANONICAL_PAYMENT_ALLOCATED',
         gateway_event_id_, plan.loan_id),
        (journal_ids_[6], original_final.legal_entity_id, target_book_id_,
         'canonical-settlement',
         'payment:' || payment_id_ || ':canonical:' || canonicalization_id_ ||
             ':lender-claim',
         intent.correlation_id, confirmation_projection_ ->> 'GatewayPayloadHash',
         confirmed_at_, 'POSTED', 'CANONICAL_LENDER_CLAIM_ALLOCATED',
         gateway_event_id_, plan.loan_id),
        (journal_ids_[7], original_final.legal_entity_id, target_book_id_,
         'canonical-settlement',
         'payment:' || payment_id_ || ':canonical:' || canonicalization_id_ ||
             ':lender-payout',
         intent.correlation_id, confirmation_projection_ ->> 'GatewayPayloadHash',
         confirmed_at_, 'POSTED', 'CANONICAL_LENDER_PAID',
         gateway_event_id_, plan.loan_id)
    ON CONFLICT DO NOTHING;
    IF refundable_excess_units_ > 0 THEN
        INSERT INTO journal (
            journal_id, legal_entity_id, book_id, source_system,
            idempotency_key, correlation_id, evidence_hash, effective_at,
            status, entry_type, source_event_id, loan_id
        ) VALUES (
            journal_ids_[8], original_final.legal_entity_id, target_book_id_,
            'canonical-settlement',
            'payment:' || payment_id_ || ':canonical:' ||
                canonicalization_id_ || ':borrower-refund',
            intent.correlation_id,
            confirmation_projection_ ->> 'GatewayPayloadHash',
            confirmed_at_, 'POSTED', 'CANONICAL_BORROWER_REFUNDED',
            gateway_event_id_, plan.loan_id
        )
        ON CONFLICT DO NOTHING;
    END IF;

    INSERT INTO journal_entry (
        journal_id, line_number, account_code, side, asset_id, units,
        party_id, loan_id
    ) VALUES
        (journal_ids_[1], 1, '9120', 'DEBIT', plan.source_asset_id,
         source_units_, plan.borrower_id, plan.loan_id),
        (journal_ids_[1], 2, '9160', 'CREDIT', plan.source_asset_id,
         source_units_, NULL, plan.loan_id),
        (journal_ids_[2], 1, '9160', 'DEBIT', plan.source_asset_id,
         source_units_, NULL, plan.loan_id),
        (journal_ids_[2], 2, source_account_code_, 'CREDIT',
         plan.source_asset_id, source_units_, NULL, plan.loan_id),
        (journal_ids_[3], 1, '1260', 'DEBIT', plan.target_asset_id,
         target_units_, NULL, plan.loan_id),
        (journal_ids_[3], 2, '9160', 'CREDIT', plan.target_asset_id,
         target_units_, NULL, plan.loan_id),
        (journal_ids_[4], 1, '9160', 'DEBIT', plan.target_asset_id,
         target_units_, NULL, plan.loan_id),
        (journal_ids_[4], 2, '9120', 'CREDIT', plan.target_asset_id,
         target_units_, plan.borrower_id, plan.loan_id),
        (journal_ids_[5], 1, '9120', 'DEBIT', plan.target_asset_id,
         target_units_, NULL, plan.loan_id),
        (journal_ids_[5], 2, '1310', 'CREDIT', plan.target_asset_id,
         principal_units_, plan.borrower_id, plan.loan_id),
        (journal_ids_[6], 1, '2310', 'DEBIT', plan.target_asset_id,
         principal_units_, plan.lender_id, plan.loan_id),
        (journal_ids_[6], 2, '2130', 'CREDIT', plan.target_asset_id,
         principal_units_, plan.lender_id, plan.loan_id),
        (journal_ids_[7], 1, '2130', 'DEBIT', plan.target_asset_id,
         principal_units_, plan.lender_id, plan.loan_id),
        (journal_ids_[7], 2, '1260', 'CREDIT', plan.target_asset_id,
         principal_units_, plan.lender_id, plan.loan_id)
    ON CONFLICT DO NOTHING;
    IF refundable_excess_units_ > 0 THEN
        INSERT INTO journal_entry (
            journal_id, line_number, account_code, side, asset_id, units,
            party_id, loan_id
        ) VALUES
            (journal_ids_[5], 3, '2150', 'CREDIT', plan.target_asset_id,
             refundable_excess_units_, plan.borrower_id, plan.loan_id),
            (journal_ids_[8], 1, '2150', 'DEBIT', plan.target_asset_id,
             refundable_excess_units_, plan.borrower_id, plan.loan_id),
            (journal_ids_[8], 2, '1260', 'CREDIT', plan.target_asset_id,
             refundable_excess_units_, plan.borrower_id, plan.loan_id)
        ON CONFLICT DO NOTHING;
    END IF;

    IF (
        SELECT count(*)
        FROM journal AS posted
        WHERE posted.journal_id = ANY(journal_ids_)
          AND posted.legal_entity_id = original_final.legal_entity_id
          AND posted.source_system = 'canonical-settlement'
          AND posted.correlation_id = intent.correlation_id
          AND posted.evidence_hash =
              confirmation_projection_ ->> 'GatewayPayloadHash'
          AND posted.effective_at = confirmed_at_
          AND posted.status = 'POSTED'
          AND posted.source_event_id = gateway_event_id_
          AND posted.loan_id = plan.loan_id
    ) <> journal_count_
       OR EXISTS (
           SELECT 1
           FROM journal_balance AS balance
           WHERE balance.journal_id = ANY(journal_ids_)
             AND balance.debit_units <> balance.credit_units
       )
       OR (
           SELECT count(*)
           FROM journal_entry
           WHERE journal_id = ANY(journal_ids_)
       ) <> (CASE
           WHEN refundable_excess_units_ = 0 THEN 14
           ELSE 17
       END)
       OR EXISTS (
           SELECT 1
           FROM (
               VALUES
                   (journal_ids_[1], source_book_id_,
                    'payment:' || payment_id_ || ':canonical:' ||
                        canonicalization_id_ || ':source-unallocated',
                    'CANONICAL_SOURCE_CLEARED'),
                   (journal_ids_[2], source_book_id_,
                    'payment:' || payment_id_ || ':canonical:' ||
                        canonicalization_id_ || ':source-converted',
                    'CANONICAL_SOURCE_CONVERTED'),
                   (journal_ids_[3], target_book_id_,
                    'payment:' || payment_id_ || ':canonical:' ||
                        canonicalization_id_ || ':target-custody',
                    'CANONICAL_TARGET_CUSTODY'),
                   (journal_ids_[4], target_book_id_,
                    'payment:' || payment_id_ || ':canonical:' ||
                        canonicalization_id_ || ':target-unallocated',
                    'CANONICAL_TARGET_UNALLOCATED'),
                   (journal_ids_[5], target_book_id_,
                    'payment:' || payment_id_ || ':canonical:' ||
                        canonicalization_id_ || ':allocation',
                    'CANONICAL_PAYMENT_ALLOCATED'),
                   (journal_ids_[6], target_book_id_,
                    'payment:' || payment_id_ || ':canonical:' ||
                        canonicalization_id_ || ':lender-claim',
                    'CANONICAL_LENDER_CLAIM_ALLOCATED'),
                   (journal_ids_[7], target_book_id_,
                    'payment:' || payment_id_ || ':canonical:' ||
                        canonicalization_id_ || ':lender-payout',
                    'CANONICAL_LENDER_PAID')
           ) AS expected(journal_id, book_id, idempotency_key, entry_type)
           LEFT JOIN journal AS actual
             ON actual.journal_id = expected.journal_id
           WHERE actual.journal_id IS NULL
              OR actual.book_id IS DISTINCT FROM expected.book_id
              OR actual.idempotency_key IS DISTINCT FROM
                  expected.idempotency_key
              OR actual.entry_type IS DISTINCT FROM expected.entry_type
              OR actual.reversal_of IS NOT NULL
              OR actual.reversal_reason IS NOT NULL
       )
       OR EXISTS (
           SELECT 1
           FROM (
               VALUES
                   (journal_ids_[1], 1, '9120', 'DEBIT',
                    plan.source_asset_id, source_units_,
                    plan.borrower_id, plan.loan_id),
                   (journal_ids_[1], 2, '9160', 'CREDIT',
                    plan.source_asset_id, source_units_,
                    NULL::text, plan.loan_id),
                   (journal_ids_[2], 1, '9160', 'DEBIT',
                    plan.source_asset_id, source_units_,
                    NULL::text, plan.loan_id),
                   (journal_ids_[2], 2, source_account_code_, 'CREDIT',
                    plan.source_asset_id, source_units_,
                    NULL::text, plan.loan_id),
                   (journal_ids_[3], 1, '1260', 'DEBIT',
                    plan.target_asset_id, target_units_,
                    NULL::text, plan.loan_id),
                   (journal_ids_[3], 2, '9160', 'CREDIT',
                    plan.target_asset_id, target_units_,
                    NULL::text, plan.loan_id),
                   (journal_ids_[4], 1, '9160', 'DEBIT',
                    plan.target_asset_id, target_units_,
                    NULL::text, plan.loan_id),
                   (journal_ids_[4], 2, '9120', 'CREDIT',
                    plan.target_asset_id, target_units_,
                    plan.borrower_id, plan.loan_id),
                   (journal_ids_[5], 1, '9120', 'DEBIT',
                    plan.target_asset_id, target_units_,
                    NULL::text, plan.loan_id),
                   (journal_ids_[5], 2, '1310', 'CREDIT',
                    plan.target_asset_id, principal_units_,
                    plan.borrower_id, plan.loan_id),
                   (journal_ids_[6], 1, '2310', 'DEBIT',
                    plan.target_asset_id, principal_units_,
                    plan.lender_id, plan.loan_id),
                   (journal_ids_[6], 2, '2130', 'CREDIT',
                    plan.target_asset_id, principal_units_,
                    plan.lender_id, plan.loan_id),
                   (journal_ids_[7], 1, '2130', 'DEBIT',
                    plan.target_asset_id, principal_units_,
                    plan.lender_id, plan.loan_id),
                   (journal_ids_[7], 2, '1260', 'CREDIT',
                    plan.target_asset_id, principal_units_,
                    plan.lender_id, plan.loan_id)
           ) AS expected(
               journal_id, line_number, account_code, side, asset_id,
               units, party_id, loan_id
           )
           LEFT JOIN journal_entry AS actual
             ON actual.journal_id = expected.journal_id
            AND actual.line_number = expected.line_number
           WHERE actual.journal_id IS NULL
              OR actual.account_code IS DISTINCT FROM expected.account_code
              OR actual.side IS DISTINCT FROM expected.side
              OR actual.asset_id IS DISTINCT FROM expected.asset_id
              OR actual.units IS DISTINCT FROM expected.units
              OR actual.party_id IS DISTINCT FROM expected.party_id
              OR actual.loan_id IS DISTINCT FROM expected.loan_id
       ) THEN
        RAISE EXCEPTION
            'canonical settlement journal batch conflicts or is unbalanced';
    END IF;
    IF refundable_excess_units_ > 0 AND (
        NOT EXISTS (
            SELECT 1
            FROM journal_entry
            WHERE journal_id = journal_ids_[5]
              AND line_number = 3
              AND account_code = '2150'
              AND side = 'CREDIT'
              AND asset_id = plan.target_asset_id
              AND units = refundable_excess_units_
              AND party_id = plan.borrower_id
              AND loan_id = plan.loan_id
        )
        OR NOT EXISTS (
            SELECT 1
            FROM journal_entry
            WHERE journal_id = journal_ids_[8]
              AND line_number = 1
              AND account_code = '2150'
              AND side = 'DEBIT'
              AND asset_id = plan.target_asset_id
              AND units = refundable_excess_units_
              AND party_id = plan.borrower_id
              AND loan_id = plan.loan_id
        )
        OR NOT EXISTS (
            SELECT 1
            FROM journal_entry
            WHERE journal_id = journal_ids_[8]
              AND line_number = 2
              AND account_code = '1260'
              AND side = 'CREDIT'
              AND asset_id = plan.target_asset_id
              AND units = refundable_excess_units_
              AND party_id = plan.borrower_id
              AND loan_id = plan.loan_id
        )
        OR NOT EXISTS (
            SELECT 1
            FROM journal
            WHERE journal_id = journal_ids_[8]
              AND book_id = target_book_id_
              AND idempotency_key =
                  'payment:' || payment_id_ || ':canonical:' ||
                      canonicalization_id_ || ':borrower-refund'
              AND entry_type = 'CANONICAL_BORROWER_REFUNDED'
              AND reversal_of IS NULL
              AND reversal_reason IS NULL
        )
    ) THEN
        RAISE EXCEPTION
            'canonical settlement refund journal conflicts with prior content';
    END IF;

    INSERT INTO canonical_settlement_journal_link (
        confirmation_id, ordinal, journal_role, journal_id
    ) VALUES
        (confirmation_id_, 1, 'SOURCE_UNALLOCATED', journal_ids_[1]),
        (confirmation_id_, 2, 'SOURCE_CONVERTED', journal_ids_[2]),
        (confirmation_id_, 3, 'TARGET_CUSTODY', journal_ids_[3]),
        (confirmation_id_, 4, 'TARGET_UNALLOCATED', journal_ids_[4]),
        (confirmation_id_, 5, 'ALLOCATION', journal_ids_[5]),
        (confirmation_id_, 6, 'LENDER_CLAIM', journal_ids_[6]),
        (confirmation_id_, 7, 'LENDER_PAYOUT', journal_ids_[7])
    ON CONFLICT DO NOTHING;
    IF refundable_excess_units_ > 0 THEN
        INSERT INTO canonical_settlement_journal_link (
            confirmation_id, ordinal, journal_role, journal_id
        ) VALUES (
            confirmation_id_, 8, 'BORROWER_REFUND', journal_ids_[8]
        )
        ON CONFLICT DO NOTHING;
    END IF;

    INSERT INTO canonical_lender_payout (
        payout_id, confirmation_id, canonicalization_id, loan_id, lender_id,
        target_asset_id, units, transaction_hash, gateway_event_id, journal_id,
        evidence_hash, paid_at
    ) VALUES (
        payout_id_, confirmation_id_, canonicalization_id_, plan.loan_id,
        plan.lender_id, plan.target_asset_id, principal_units_,
        transaction_hash_, gateway_event_id_, journal_ids_[7],
        confirmation_projection_ ->> 'GatewayPayloadHash', confirmed_at_
    )
    ON CONFLICT DO NOTHING;
    IF refundable_excess_units_ > 0 THEN
        INSERT INTO canonical_borrower_refund (
            refund_id, confirmation_id, canonicalization_id, loan_id,
            borrower_id, target_asset_id, units, transaction_hash,
            gateway_event_id, journal_id, evidence_hash, refunded_at
        ) VALUES (
            refund_id_, confirmation_id_, canonicalization_id_, plan.loan_id,
            plan.borrower_id, plan.target_asset_id, refundable_excess_units_,
            transaction_hash_, gateway_event_id_, journal_ids_[8],
            confirmation_projection_ ->> 'GatewayPayloadHash', confirmed_at_
        )
        ON CONFLICT DO NOTHING;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_confirmation AS confirmation
        WHERE confirmation.confirmation_id = confirmation_id_
          AND confirmation.canonicalization_id = canonicalization_id_
          AND confirmation.submission_id = submission.submission_id
          AND confirmation.conversion_id = conversion_id_
          AND confirmation.payment_id = payment_id_
          AND confirmation.allocation_id = allocation_id_
          AND confirmation.loan_id = plan.loan_id
          AND confirmation.instruction_digest = instruction_digest_
          AND confirmation.borrower_id = plan.borrower_id
          AND confirmation.lender_id = plan.lender_id
          AND confirmation.target_asset_id = plan.target_asset_id
          AND confirmation.target_units = target_units_
          AND confirmation.principal_units = principal_units_
          AND confirmation.refundable_excess_units =
              refundable_excess_units_
          AND confirmation.debt_before_units = debt_before_units_
          AND confirmation.debt_after_units = debt_after_units_
          AND confirmation.gateway_event_id = gateway_event_id_
          AND confirmation.transaction_hash = transaction_hash_
          AND confirmation.block_hash =
              confirmation_projection_ ->> 'BlockHash'
          AND confirmation.block_number = block_number_
          AND confirmation.log_index = log_index_
          AND confirmation.chain_finality_depth = confirmation_depth_
          AND confirmation.finality_head_block = finality_head_block_
          AND confirmation.finality_head_hash =
              confirmation_projection_ ->> 'FinalityHeadHash'
          AND confirmation.finality_evidence_hash =
              confirmation_projection_ ->> 'FinalityEvidenceHash'
          AND confirmation.transaction_index = transaction_index_
          AND confirmation.receipts_root =
              confirmation_projection_ ->> 'ReceiptsRoot'
          AND confirmation.inclusion_proof_hash =
              confirmation_projection_ ->> 'InclusionProofHash'
          AND confirmation.finality_policy_hash = plan.finality_policy_hash
          AND confirmation.header_authority_hash =
              confirmation_projection_ ->> 'HeaderAuthorityHash'
          AND confirmation.receipt_header_signature_hash =
              confirmation_projection_ ->> 'ReceiptHeaderSignatureHash'
          AND confirmation.head_header_signature_hash =
              confirmation_projection_ ->> 'HeadHeaderSignatureHash'
          AND confirmation.journal_count = journal_count_
          AND confirmation.raw_payload_hash =
              confirmation_projection_ ->> 'GatewayPayloadHash'
          AND confirmation.confirmed_at = confirmed_at_
    ) OR (
        SELECT count(*)
        FROM canonical_settlement_journal_link
        WHERE confirmation_id = confirmation_id_
    ) <> journal_count_
       OR EXISTS (
           SELECT 1
           FROM (
               VALUES
                   (1, 'SOURCE_UNALLOCATED', journal_ids_[1]),
                   (2, 'SOURCE_CONVERTED', journal_ids_[2]),
                   (3, 'TARGET_CUSTODY', journal_ids_[3]),
                   (4, 'TARGET_UNALLOCATED', journal_ids_[4]),
                   (5, 'ALLOCATION', journal_ids_[5]),
                   (6, 'LENDER_CLAIM', journal_ids_[6]),
                   (7, 'LENDER_PAYOUT', journal_ids_[7])
           ) AS expected(ordinal, journal_role, journal_id)
           LEFT JOIN canonical_settlement_journal_link AS actual
             ON actual.confirmation_id = confirmation_id_
            AND actual.ordinal = expected.ordinal
           WHERE actual.confirmation_id IS NULL
              OR actual.journal_role IS DISTINCT FROM expected.journal_role
              OR actual.journal_id IS DISTINCT FROM expected.journal_id
       )
       OR NOT EXISTS (
           SELECT 1
           FROM canonical_lender_payout
           WHERE confirmation_id = confirmation_id_
             AND payout_id = payout_id_
             AND canonicalization_id = canonicalization_id_
             AND loan_id = plan.loan_id
             AND lender_id = plan.lender_id
             AND target_asset_id = plan.target_asset_id
             AND journal_id = journal_ids_[7]
             AND units = principal_units_
             AND transaction_hash = transaction_hash_
             AND gateway_event_id = gateway_event_id_
             AND evidence_hash =
                 confirmation_projection_ ->> 'GatewayPayloadHash'
             AND paid_at = confirmed_at_
       )
       OR (
           refundable_excess_units_ > 0
           AND NOT EXISTS (
               SELECT 1
               FROM canonical_borrower_refund
               WHERE confirmation_id = confirmation_id_
                 AND refund_id = refund_id_
                 AND canonicalization_id = canonicalization_id_
                 AND loan_id = plan.loan_id
                 AND borrower_id = plan.borrower_id
                 AND target_asset_id = plan.target_asset_id
                 AND journal_id = journal_ids_[8]
                 AND units = refundable_excess_units_
                 AND transaction_hash = transaction_hash_
                 AND gateway_event_id = gateway_event_id_
                 AND evidence_hash =
                     confirmation_projection_ ->> 'GatewayPayloadHash'
                 AND refunded_at = confirmed_at_
           )
       )
       OR (
           refundable_excess_units_ > 0
           AND NOT EXISTS (
               SELECT 1
               FROM canonical_settlement_journal_link
               WHERE confirmation_id = confirmation_id_
                 AND ordinal = 8
                 AND journal_role = 'BORROWER_REFUND'
                 AND journal_id = journal_ids_[8]
           )
       )
       OR (
           refundable_excess_units_ = 0
           AND EXISTS (
               SELECT 1
               FROM canonical_borrower_refund
               WHERE confirmation_id = confirmation_id_
           )
       ) THEN
        RAISE EXCEPTION
            'canonical settlement commit is incomplete or conflicts with prior content';
    END IF;

    RETURN jsonb_build_object(
        'confirmation_id', confirmation_id_,
        'conversion_id', conversion_id_,
        'gateway_event_id', gateway_event_id_,
        'journal_ids', to_jsonb(journal_ids_)
    );
END;
$$;

CREATE TABLE canonical_settlement_reorg (
    reorg_id text PRIMARY KEY,
    canonicalization_id text NOT NULL
        REFERENCES canonicalization_plan(canonicalization_id),
    confirmation_id text UNIQUE
        REFERENCES canonical_settlement_confirmation(confirmation_id),
    instruction_digest text NOT NULL,
    chain_id bigint NOT NULL CHECK (chain_id > 0),
    gateway_address text NOT NULL,
    orphaned_transaction_hash text NOT NULL,
    orphaned_gateway_event_id text NOT NULL UNIQUE,
    transaction_index numeric(20, 0) NOT NULL CHECK (
        transaction_index >= 0
        AND transaction_index <= 18446744073709551615
    ),
    receipts_root text NOT NULL CHECK (
        receipts_root ~ '^0x[0-9a-f]{64}$'
    ),
    inclusion_proof_hash text NOT NULL CHECK (
        inclusion_proof_hash ~ '^0x[0-9a-f]{64}$'
    ),
    finality_policy_hash text NOT NULL CHECK (
        finality_policy_hash ~ '^0x[0-9a-f]{64}$'
    ),
    header_authority_hash text NOT NULL CHECK (
        header_authority_hash ~ '^0x[0-9a-f]{64}$'
    ),
    orphaned_receipt_header_signature_hash text NOT NULL CHECK (
        orphaned_receipt_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    confirmation_head_header_signature_hash text NOT NULL CHECK (
        confirmation_head_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    replacement_header_signature_hash text NOT NULL CHECK (
        replacement_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    detected_head_header_signature_hash text NOT NULL CHECK (
        detected_head_header_signature_hash ~ '^0x[0-9a-f]{64}$'
    ),
    orphaned_block_hash text NOT NULL,
    orphaned_block_number bigint NOT NULL CHECK (orphaned_block_number > 0),
    replacement_block_hash text NOT NULL,
    replacement_block_number bigint NOT NULL CHECK (replacement_block_number > 0),
    confirmation_depth bigint NOT NULL CHECK (confirmation_depth > 0),
    detected_head_block bigint NOT NULL CHECK (detected_head_block >= orphaned_block_number),
    detected_head_hash text NOT NULL,
    reorg_kind text NOT NULL CHECK (reorg_kind IN ('SHALLOW', 'DEEP')),
    compensation_required boolean NOT NULL,
    orphaned_event_evidence_hash text NOT NULL CHECK (
        orphaned_event_evidence_hash ~ '^0x[0-9a-f]{64}$'
        AND orphaned_event_evidence_hash <>
            '0x0000000000000000000000000000000000000000000000000000000000000000'
    ),
    orphaned_raw_payload_hash text NOT NULL,
    evidence_hash text NOT NULL,
    submission_submitted_at timestamptz NOT NULL,
    detected_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (compensation_required = (reorg_kind = 'DEEP')),
    CHECK (submission_submitted_at <= detected_at),
    CHECK (
        (reorg_kind = 'SHALLOW' AND confirmation_id IS NULL)
        OR (reorg_kind = 'DEEP' AND confirmation_id IS NOT NULL)
    )
);

CREATE FUNCTION enforce_canonical_settlement_reorg() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.reorg_kind = 'SHALLOW' AND NOT EXISTS (
        SELECT 1
        FROM canonicalization_plan AS plan
        JOIN canonicalization_submission AS submission
          ON submission.canonicalization_id = plan.canonicalization_id
        WHERE plan.canonicalization_id = NEW.canonicalization_id
          AND plan.instruction_digest = NEW.instruction_digest
          AND submission.transaction_hash = NEW.orphaned_transaction_hash
          AND submission.state = 'SUBMITTED'
    ) THEN
        RAISE EXCEPTION 'shallow reorg does not match a submitted canonicalization';
    END IF;

    IF NEW.reorg_kind = 'DEEP' AND NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_confirmation AS confirmation
        WHERE confirmation.confirmation_id = NEW.confirmation_id
          AND confirmation.canonicalization_id = NEW.canonicalization_id
          AND confirmation.instruction_digest = NEW.instruction_digest
          AND confirmation.transaction_hash = NEW.orphaned_transaction_hash
          AND confirmation.gateway_event_id = NEW.orphaned_gateway_event_id
          AND confirmation.block_hash = NEW.orphaned_block_hash
          AND confirmation.block_number = NEW.orphaned_block_number
           AND confirmation.chain_finality_depth = NEW.confirmation_depth
           AND confirmation.raw_payload_hash = NEW.orphaned_raw_payload_hash
           AND confirmation.confirmed_at <= NEW.detected_at
           AND EXISTS (
              SELECT 1
              FROM canonical_gateway_event_projection AS event
              WHERE event.gateway_event_id = confirmation.gateway_event_id
                 AND event.chain_id = NEW.chain_id
                 AND event.gateway_address = NEW.gateway_address
                 AND event.transaction_index =
                     confirmation.transaction_index
                 AND event.transaction_index = NEW.transaction_index
                 AND event.receipts_root = confirmation.receipts_root
                 AND event.receipts_root = NEW.receipts_root
                 AND event.inclusion_proof_hash =
                     confirmation.inclusion_proof_hash
                 AND event.inclusion_proof_hash = NEW.inclusion_proof_hash
                 AND event.finality_policy_hash =
                     confirmation.finality_policy_hash
                 AND event.finality_policy_hash = NEW.finality_policy_hash
                 AND event.header_authority_hash =
                     confirmation.header_authority_hash
                 AND event.header_authority_hash = NEW.header_authority_hash
                 AND event.receipt_header_signature_hash =
                     confirmation.receipt_header_signature_hash
                 AND event.receipt_header_signature_hash =
                     NEW.orphaned_receipt_header_signature_hash
                 AND event.head_header_signature_hash =
                     confirmation.head_header_signature_hash
                 AND event.head_header_signature_hash =
                     NEW.confirmation_head_header_signature_hash
                 AND event.raw_payload_hash = NEW.orphaned_raw_payload_hash
          )
          AND EXISTS (
              SELECT 1
              FROM canonical_coordinator_state AS coordinator
              CROSS JOIN LATERAL jsonb_array_elements(
                  COALESCE(coordinator.snapshot->'Reorgs', '[]'::jsonb)
              ) AS stored_reorg
              WHERE coordinator.payment_id = confirmation.payment_id
                AND coordinator.instruction_digest = NEW.instruction_digest
                AND coordinator.state = 'INCIDENT'
                AND NOT coordinator.tombstoned
                AND NOT coordinator.pending_reversal
                AND stored_reorg->>'ReorgID' = NEW.reorg_id
                AND stored_reorg->>'OrphanedEventEvidenceHash' =
                    NEW.orphaned_event_evidence_hash
                AND stored_reorg->>'RawEvidenceHash' =
                    NEW.orphaned_raw_payload_hash
          )
          AND EXISTS (
              SELECT 1
              FROM canonical_coordinator_state_history AS confirmed_state
              WHERE confirmed_state.payment_id = confirmation.payment_id
                AND confirmed_state.instruction_digest =
                    NEW.instruction_digest
                AND confirmed_state.state = 'CONFIRMED'
                AND confirmed_state.snapshot
                        #>> '{Confirmation,EventID}' =
                    NEW.orphaned_gateway_event_id
                AND confirmed_state.snapshot
                        #>> '{Confirmation,EventEvidenceHash}' =
                    NEW.orphaned_event_evidence_hash
                AND confirmed_state.snapshot
                        #>> '{Confirmation,GatewayPayloadHash}' =
                    NEW.orphaned_raw_payload_hash
          )
          AND EXISTS (
              SELECT 1
              FROM canonicalization_submission AS submission
              WHERE submission.canonicalization_id = NEW.canonicalization_id
                AND submission.submitted_at = NEW.submission_submitted_at
                AND submission.submitted_at <= confirmation.confirmed_at
          )
    ) THEN
        RAISE EXCEPTION 'deep reorg does not match its finalized gateway confirmation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_settlement_reorg_guard
BEFORE INSERT ON canonical_settlement_reorg
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_settlement_reorg();

CREATE TABLE canonical_settlement_incident (
    incident_id text PRIMARY KEY,
    incident_kind text NOT NULL CHECK (
        incident_kind IN ('PROVIDER_CONTRADICTION', 'DEEP_CHAIN_REORG')
    ),
    reorg_id text UNIQUE REFERENCES canonical_settlement_reorg(reorg_id),
    canonicalization_id text NOT NULL
        REFERENCES canonicalization_plan(canonicalization_id),
    payment_id text NOT NULL REFERENCES payment_intent(payment_id),
    instruction_digest text NOT NULL,
    provider_id text NOT NULL,
    provider_event_id text NOT NULL,
    reported_status text NOT NULL,
    canonicalization_state text NOT NULL CHECK (
        canonicalization_state IN ('SUBMITTED', 'CONFIRMED')
    ),
    reason_code text NOT NULL,
    owner text NOT NULL,
    payment_state_unchanged boolean NOT NULL,
    economic_journals_suppressed boolean NOT NULL,
    raw_payload_hash text NOT NULL,
    evidence_hash text NOT NULL,
    observed_at timestamptz NOT NULL,
    resolution_deadline timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (provider_id, provider_event_id),
    CHECK (resolution_deadline > observed_at),
    CHECK (
        (
            incident_kind = 'PROVIDER_CONTRADICTION'
            AND reorg_id IS NULL
            AND payment_state_unchanged
            AND economic_journals_suppressed
        )
        OR (
            incident_kind = 'DEEP_CHAIN_REORG'
            AND reorg_id IS NOT NULL
            AND reported_status = 'ORPHANED'
            AND NOT economic_journals_suppressed
        )
    )
);

CREATE TABLE canonical_settlement_reorg_compensation (
    compensation_id text PRIMARY KEY,
    reorg_id text NOT NULL UNIQUE REFERENCES canonical_settlement_reorg(reorg_id),
    confirmation_id text NOT NULL UNIQUE
        REFERENCES canonical_settlement_confirmation(confirmation_id),
    canonicalization_id text NOT NULL UNIQUE
        REFERENCES canonicalization_plan(canonicalization_id),
    incident_id text NOT NULL UNIQUE
        REFERENCES canonical_settlement_incident(incident_id),
    instruction_digest text NOT NULL,
    orphaned_transaction_hash text NOT NULL,
    orphaned_gateway_event_id text NOT NULL,
    orphaned_block_hash text NOT NULL,
    original_journal_count integer NOT NULL CHECK (
        original_journal_count BETWEEN 7 AND 8
    ),
    reversal_journal_count integer NOT NULL CHECK (
        reversal_journal_count = original_journal_count
    ),
    evidence_hash text NOT NULL,
    detected_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE canonical_settlement_reorg_journal_link (
    compensation_id text NOT NULL
        REFERENCES canonical_settlement_reorg_compensation(compensation_id),
    ordinal integer NOT NULL CHECK (ordinal BETWEEN 1 AND 8),
    original_journal_id text NOT NULL UNIQUE REFERENCES journal(journal_id),
    reversal_journal_id text NOT NULL UNIQUE REFERENCES journal(journal_id),
    PRIMARY KEY (compensation_id, ordinal),
    CHECK (original_journal_id <> reversal_journal_id)
);

CREATE FUNCTION enforce_canonical_settlement_incident() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM canonicalization_plan AS plan
        JOIN canonicalization_eligibility AS eligibility
          ON eligibility.eligibility_id = plan.eligibility_id
        WHERE plan.canonicalization_id = NEW.canonicalization_id
          AND plan.payment_id = NEW.payment_id
          AND plan.instruction_digest = NEW.instruction_digest
          AND eligibility.provider_id = NEW.provider_id
    ) THEN
        RAISE EXCEPTION 'incident does not match canonicalization provenance';
    END IF;
    IF NEW.incident_kind = 'DEEP_CHAIN_REORG' AND NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg AS reorg
        WHERE reorg.reorg_id = NEW.reorg_id
          AND reorg.canonicalization_id = NEW.canonicalization_id
          AND reorg.instruction_digest = NEW.instruction_digest
          AND reorg.reorg_kind = 'DEEP'
          AND reorg.orphaned_gateway_event_id = NEW.provider_event_id
    ) THEN
        RAISE EXCEPTION 'deep reorg incident does not match its reorg envelope';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_settlement_incident_guard
BEFORE INSERT ON canonical_settlement_incident
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_settlement_incident();

CREATE FUNCTION enforce_canonical_reorg_compensation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg AS reorg
        JOIN canonical_settlement_confirmation AS confirmation
          ON confirmation.confirmation_id = reorg.confirmation_id
        JOIN canonical_settlement_incident AS incident
          ON incident.incident_id = NEW.incident_id
        WHERE reorg.reorg_id = NEW.reorg_id
          AND reorg.reorg_kind = 'DEEP'
          AND reorg.compensation_required
          AND reorg.confirmation_id = NEW.confirmation_id
          AND reorg.canonicalization_id = NEW.canonicalization_id
          AND reorg.instruction_digest = NEW.instruction_digest
          AND reorg.orphaned_transaction_hash = NEW.orphaned_transaction_hash
          AND reorg.orphaned_gateway_event_id = NEW.orphaned_gateway_event_id
          AND reorg.orphaned_block_hash = NEW.orphaned_block_hash
          AND confirmation.canonicalization_id = NEW.canonicalization_id
          AND incident.reorg_id = NEW.reorg_id
          AND incident.canonicalization_id = NEW.canonicalization_id
          AND incident.instruction_digest = NEW.instruction_digest
          AND incident.incident_kind = 'DEEP_CHAIN_REORG'
    ) THEN
        RAISE EXCEPTION 'compensation lacks matching deep reorg and incident evidence';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_reorg_compensation_guard
BEFORE INSERT ON canonical_settlement_reorg_compensation
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_reorg_compensation();

CREATE FUNCTION enforce_canonical_reorg_journal_link() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg_compensation AS compensation
        JOIN canonical_settlement_journal_link AS original_link
          ON original_link.confirmation_id = compensation.confirmation_id
         AND original_link.journal_id = NEW.original_journal_id
        JOIN journal AS reversal
          ON reversal.journal_id = NEW.reversal_journal_id
        WHERE compensation.compensation_id = NEW.compensation_id
          AND reversal.reversal_of = NEW.original_journal_id
          AND reversal.source_system = 'canonical-settlement'
          AND reversal.entry_type = 'CANONICAL_SETTLEMENT_REORG'
          AND reversal.source_event_id = compensation.orphaned_gateway_event_id
    ) THEN
        RAISE EXCEPTION 'reorg journal link is not an exact opposite of the confirmed batch';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER canonical_reorg_journal_link_guard
BEFORE INSERT ON canonical_settlement_reorg_journal_link
FOR EACH ROW EXECUTE FUNCTION enforce_canonical_reorg_journal_link();

CREATE FUNCTION assert_canonical_reorg_compensation_complete() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    linked_count integer;
    minimum_ordinal integer;
    maximum_ordinal integer;
BEGIN
    SELECT count(*), min(ordinal), max(ordinal)
    INTO linked_count, minimum_ordinal, maximum_ordinal
    FROM canonical_settlement_reorg_journal_link
    WHERE compensation_id = NEW.compensation_id;
    IF linked_count <> NEW.original_journal_count
       OR linked_count <> NEW.reversal_journal_count
       OR minimum_ordinal <> 1
       OR maximum_ordinal <> NEW.original_journal_count THEN
        RAISE EXCEPTION
            'deep reorg compensation % does not link the complete journal batch',
            NEW.compensation_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER canonical_reorg_compensation_complete_on_commit
AFTER INSERT ON canonical_settlement_reorg_compensation
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_canonical_reorg_compensation_complete();

-- Records a deep reorg, its owned incident, compensation header, and every journal
-- opposite as one idempotent database operation. Any mismatch raises and rolls back
-- the entire call; an exact retry returns the existing compensation identity.
CREATE FUNCTION disabled_legacy_deep_compensation(
    reorg_id_ text,
    compensation_id_ text,
    confirmation_id_ text,
    canonicalization_id_ text,
    instruction_digest_ text,
    orphaned_transaction_hash_ text,
    orphaned_gateway_event_id_ text,
    orphaned_block_hash_ text,
    orphaned_block_number_ bigint,
    replacement_block_number_ bigint,
    orphaned_event_evidence_hash_ text,
    reorg_evidence_hash_ text,
    compensation_evidence_hash_ text,
    original_journal_ids_ text[],
    reversal_journal_ids_ text[],
    owner_ text,
    detected_at_ timestamptz,
    resolution_deadline_ timestamptz
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    incident_id_ text := 'reorg:' || reorg_id_;
    payment_id_ text;
    provider_id_ text;
    ordinal_ integer;
BEGIN
    RAISE EXCEPTION
        'legacy deep compensation interface is disabled; use the atomic derived-journal operation';

    IF cardinality(original_journal_ids_) NOT BETWEEN 7 AND 8
       OR cardinality(reversal_journal_ids_) <> cardinality(original_journal_ids_)
       OR owner_ = ''
       OR resolution_deadline_ <= detected_at_ THEN
        RAISE EXCEPTION 'invalid complete deep-reorg compensation envelope';
    END IF;

    INSERT INTO canonical_settlement_reorg (
        reorg_id,
        canonicalization_id,
        confirmation_id,
        instruction_digest,
        orphaned_transaction_hash,
        orphaned_gateway_event_id,
        orphaned_block_hash,
        orphaned_block_number,
        replacement_block_number,
        reorg_kind,
        compensation_required,
        orphaned_event_evidence_hash,
        evidence_hash,
        detected_at
    ) VALUES (
        reorg_id_,
        canonicalization_id_,
        confirmation_id_,
        instruction_digest_,
        orphaned_transaction_hash_,
        orphaned_gateway_event_id_,
        orphaned_block_hash_,
        orphaned_block_number_,
        replacement_block_number_,
        'DEEP',
        true,
        orphaned_event_evidence_hash_,
        reorg_evidence_hash_,
        detected_at_
    )
    ON CONFLICT (reorg_id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg AS reorg
        WHERE reorg.reorg_id = reorg_id_
          AND reorg.canonicalization_id = canonicalization_id_
          AND reorg.confirmation_id = confirmation_id_
          AND reorg.instruction_digest = instruction_digest_
          AND reorg.orphaned_transaction_hash = orphaned_transaction_hash_
          AND reorg.orphaned_gateway_event_id = orphaned_gateway_event_id_
          AND reorg.orphaned_block_hash = orphaned_block_hash_
          AND reorg.orphaned_block_number = orphaned_block_number_
          AND reorg.replacement_block_number = replacement_block_number_
          AND reorg.reorg_kind = 'DEEP'
          AND reorg.compensation_required
          AND reorg.orphaned_event_evidence_hash = orphaned_event_evidence_hash_
          AND reorg.evidence_hash = reorg_evidence_hash_
          AND reorg.detected_at = detected_at_
    ) THEN
        RAISE EXCEPTION 'deep reorg id was reused with conflicting evidence';
    END IF;

    SELECT plan.payment_id, eligibility.provider_id
    INTO payment_id_, provider_id_
    FROM canonicalization_plan AS plan
    JOIN canonicalization_eligibility AS eligibility
      ON eligibility.eligibility_id = plan.eligibility_id
    WHERE plan.canonicalization_id = canonicalization_id_
      AND plan.instruction_digest = instruction_digest_;
    IF payment_id_ IS NULL OR provider_id_ IS NULL THEN
        RAISE EXCEPTION 'deep reorg cannot resolve canonicalization provenance';
    END IF;

    INSERT INTO canonical_settlement_incident (
        incident_id,
        incident_kind,
        reorg_id,
        canonicalization_id,
        payment_id,
        instruction_digest,
        provider_id,
        provider_event_id,
        reported_status,
        canonicalization_state,
        reason_code,
        owner,
        payment_state_unchanged,
        economic_journals_suppressed,
        raw_payload_hash,
        evidence_hash,
        observed_at,
        resolution_deadline
    ) VALUES (
        incident_id_,
        'DEEP_CHAIN_REORG',
        reorg_id_,
        canonicalization_id_,
        payment_id_,
        instruction_digest_,
        provider_id_,
        orphaned_gateway_event_id_,
        'ORPHANED',
        'CONFIRMED',
        'FINALIZED_GATEWAY_EVENT_ORPHANED',
        owner_,
        true,
        false,
        orphaned_event_evidence_hash_,
        reorg_evidence_hash_,
        detected_at_,
        resolution_deadline_
    )
    ON CONFLICT (incident_id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_incident AS incident
        WHERE incident.incident_id = incident_id_
          AND incident.incident_kind = 'DEEP_CHAIN_REORG'
          AND incident.reorg_id = reorg_id_
          AND incident.canonicalization_id = canonicalization_id_
          AND incident.payment_id = payment_id_
          AND incident.instruction_digest = instruction_digest_
          AND incident.provider_id = provider_id_
          AND incident.provider_event_id = orphaned_gateway_event_id_
          AND incident.owner = owner_
          AND incident.evidence_hash = reorg_evidence_hash_
          AND incident.observed_at = detected_at_
          AND incident.resolution_deadline = resolution_deadline_
    ) THEN
        RAISE EXCEPTION 'deep reorg incident id was reused with conflicting evidence';
    END IF;

    INSERT INTO canonical_settlement_reorg_compensation (
        compensation_id,
        reorg_id,
        confirmation_id,
        canonicalization_id,
        incident_id,
        instruction_digest,
        orphaned_transaction_hash,
        orphaned_gateway_event_id,
        orphaned_block_hash,
        original_journal_count,
        reversal_journal_count,
        evidence_hash,
        detected_at
    ) VALUES (
        compensation_id_,
        reorg_id_,
        confirmation_id_,
        canonicalization_id_,
        incident_id_,
        instruction_digest_,
        orphaned_transaction_hash_,
        orphaned_gateway_event_id_,
        orphaned_block_hash_,
        cardinality(original_journal_ids_),
        cardinality(reversal_journal_ids_),
        compensation_evidence_hash_,
        detected_at_
    )
    ON CONFLICT (compensation_id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg_compensation AS compensation
        WHERE compensation.compensation_id = compensation_id_
          AND compensation.reorg_id = reorg_id_
          AND compensation.confirmation_id = confirmation_id_
          AND compensation.canonicalization_id = canonicalization_id_
          AND compensation.incident_id = incident_id_
          AND compensation.instruction_digest = instruction_digest_
          AND compensation.orphaned_transaction_hash = orphaned_transaction_hash_
          AND compensation.orphaned_gateway_event_id = orphaned_gateway_event_id_
          AND compensation.orphaned_block_hash = orphaned_block_hash_
          AND compensation.original_journal_count = cardinality(original_journal_ids_)
          AND compensation.reversal_journal_count = cardinality(reversal_journal_ids_)
          AND compensation.evidence_hash = compensation_evidence_hash_
          AND compensation.detected_at = detected_at_
    ) THEN
        RAISE EXCEPTION 'compensation id was reused with conflicting evidence';
    END IF;

    FOR ordinal_ IN 1..cardinality(original_journal_ids_) LOOP
        INSERT INTO canonical_settlement_reorg_journal_link (
            compensation_id,
            ordinal,
            original_journal_id,
            reversal_journal_id
        ) VALUES (
            compensation_id_,
            ordinal_,
            original_journal_ids_[ordinal_],
            reversal_journal_ids_[ordinal_]
        )
        ON CONFLICT (compensation_id, ordinal) DO NOTHING;

        IF NOT EXISTS (
            SELECT 1
            FROM canonical_settlement_reorg_journal_link AS link
            WHERE link.compensation_id = compensation_id_
              AND link.ordinal = ordinal_
              AND link.original_journal_id = original_journal_ids_[ordinal_]
              AND link.reversal_journal_id = reversal_journal_ids_[ordinal_]
        ) THEN
            RAISE EXCEPTION 'reorg journal ordinal was reused with conflicting evidence';
        END IF;
    END LOOP;
    RETURN compensation_id_;
END;
$$;

DROP FUNCTION disabled_legacy_deep_compensation(
    text,
    text,
    text,
    text,
    text,
    text,
    text,
    text,
    bigint,
    bigint,
    text,
    text,
    text,
    text[],
    text[],
    text,
    timestamptz,
    timestamptz
);

-- The only supported deep-compensation operation. It derives the complete original
-- batch from the finalized confirmation, creates exact opposite journals and entries,
-- and records reorg/incident/compensation evidence in the same database transaction.
CREATE FUNCTION record_deep_canonical_settlement_compensation(
    reorg_id_ text,
    compensation_id_ text,
    confirmation_id_ text,
    canonicalization_id_ text,
    instruction_digest_ text,
    chain_id_ bigint,
    gateway_address_ text,
    orphaned_transaction_hash_ text,
    orphaned_gateway_event_id_ text,
    transaction_index_ numeric(20, 0),
    receipts_root_ text,
    inclusion_proof_hash_ text,
    finality_policy_hash_ text,
    header_authority_hash_ text,
    orphaned_receipt_header_signature_hash_ text,
    confirmation_head_header_signature_hash_ text,
    replacement_header_signature_hash_ text,
    detected_head_header_signature_hash_ text,
    orphaned_block_hash_ text,
    orphaned_block_number_ bigint,
    replacement_block_hash_ text,
    replacement_block_number_ bigint,
    confirmation_depth_ bigint,
    detected_head_block_ bigint,
    detected_head_hash_ text,
    orphaned_event_evidence_hash_ text,
    orphaned_raw_payload_hash_ text,
    reorg_evidence_hash_ text,
    submission_submitted_at_ timestamptz,
    compensation_evidence_hash_ text,
    owner_ text,
    detected_at_ timestamptz,
    resolution_deadline_ timestamptz
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    incident_id_ text := 'reorg:' || reorg_id_;
    payment_id_ text;
    provider_id_ text;
    journal_count_ integer;
    link_ record;
    reversal_id_ text;
BEGIN
    IF reorg_id_ = '' OR compensation_id_ = '' OR confirmation_id_ = ''
       OR canonicalization_id_ = '' OR instruction_digest_ = ''
       OR chain_id_ <= 0 OR gateway_address_ = ''
       OR orphaned_transaction_hash_ = '' OR orphaned_gateway_event_id_ = ''
       OR transaction_index_ < 0
       OR transaction_index_ > 18446744073709551615
       OR receipts_root_ !~ '^0x[0-9a-f]{64}$'
       OR inclusion_proof_hash_ !~ '^0x[0-9a-f]{64}$'
       OR finality_policy_hash_ !~ '^0x[0-9a-f]{64}$'
       OR header_authority_hash_ !~ '^0x[0-9a-f]{64}$'
       OR orphaned_receipt_header_signature_hash_ !~ '^0x[0-9a-f]{64}$'
       OR confirmation_head_header_signature_hash_ !~ '^0x[0-9a-f]{64}$'
       OR replacement_header_signature_hash_ !~ '^0x[0-9a-f]{64}$'
       OR detected_head_header_signature_hash_ !~ '^0x[0-9a-f]{64}$'
       OR orphaned_block_hash_ = '' OR orphaned_block_number_ <= 0
       OR replacement_block_hash_ = '' OR replacement_block_number_ <= 0
       OR confirmation_depth_ <= 0
       OR detected_head_block_ < orphaned_block_number_
       OR detected_head_hash_ = ''
       OR orphaned_event_evidence_hash_
            !~ '^0x[0-9a-f]{64}$'
       OR orphaned_event_evidence_hash_ =
            '0x0000000000000000000000000000000000000000000000000000000000000000'
       OR orphaned_raw_payload_hash_ = ''
       OR reorg_evidence_hash_ = '' OR compensation_evidence_hash_ = ''
       OR owner_ = '' OR submission_submitted_at_ IS NULL
       OR detected_at_ IS NULL
       OR submission_submitted_at_ > detected_at_
       OR resolution_deadline_ <= detected_at_ THEN
        RAISE EXCEPTION 'invalid complete deep-reorg compensation envelope';
    END IF;

    SELECT plan.payment_id, eligibility.provider_id, confirmation.journal_count
    INTO payment_id_, provider_id_, journal_count_
    FROM canonical_settlement_confirmation AS confirmation
    JOIN canonicalization_plan AS plan
      ON plan.canonicalization_id = confirmation.canonicalization_id
    JOIN canonicalization_eligibility AS eligibility
      ON eligibility.eligibility_id = plan.eligibility_id
    JOIN canonical_gateway_event_projection AS event
      ON event.gateway_event_id = confirmation.gateway_event_id
    WHERE confirmation.confirmation_id = confirmation_id_
      AND confirmation.canonicalization_id = canonicalization_id_
      AND confirmation.instruction_digest = instruction_digest_
      AND confirmation.transaction_hash = orphaned_transaction_hash_
      AND confirmation.gateway_event_id = orphaned_gateway_event_id_
      AND confirmation.block_hash = orphaned_block_hash_
      AND confirmation.block_number = orphaned_block_number_
      AND confirmation.chain_finality_depth = confirmation_depth_
      AND confirmation.raw_payload_hash = orphaned_raw_payload_hash_
      AND confirmation.confirmed_at <= detected_at_
      AND event.chain_id = chain_id_
      AND event.gateway_address = gateway_address_
      AND event.transaction_index = confirmation.transaction_index
      AND event.transaction_index = transaction_index_
      AND event.receipts_root = confirmation.receipts_root
      AND event.receipts_root = receipts_root_
      AND event.inclusion_proof_hash = confirmation.inclusion_proof_hash
      AND event.inclusion_proof_hash = inclusion_proof_hash_
      AND event.finality_policy_hash = confirmation.finality_policy_hash
      AND event.finality_policy_hash = finality_policy_hash_
      AND event.header_authority_hash = confirmation.header_authority_hash
      AND event.header_authority_hash = header_authority_hash_
      AND event.receipt_header_signature_hash =
          confirmation.receipt_header_signature_hash
      AND event.receipt_header_signature_hash =
          orphaned_receipt_header_signature_hash_
      AND event.head_header_signature_hash =
          confirmation.head_header_signature_hash
      AND event.head_header_signature_hash =
          confirmation_head_header_signature_hash_
      AND event.raw_payload_hash = orphaned_raw_payload_hash_
      AND EXISTS (
          SELECT 1
          FROM canonicalization_submission AS submission
          WHERE submission.canonicalization_id = canonicalization_id_
            AND submission.submitted_at = submission_submitted_at_
            AND submission.submitted_at <= confirmation.confirmed_at
      );
    IF payment_id_ IS NULL OR provider_id_ IS NULL OR journal_count_ NOT BETWEEN 7 AND 8 THEN
        RAISE EXCEPTION 'deep reorg does not match its finalized gateway confirmation';
    END IF;
    IF (
        SELECT count(*)
        FROM canonical_settlement_journal_link
        WHERE confirmation_id = confirmation_id_
    ) <> journal_count_ THEN
        RAISE EXCEPTION 'finalized confirmation journal batch is incomplete';
    END IF;

    PERFORM 1
    FROM canonical_coordinator_state AS coordinator
    CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(coordinator.snapshot->'Reorgs', '[]'::jsonb)
    ) AS stored_reorg
    WHERE coordinator.payment_id = payment_id_
      AND coordinator.instruction_digest = instruction_digest_
      AND coordinator.state = 'INCIDENT'
      AND NOT coordinator.tombstoned
      AND NOT coordinator.pending_reversal
      AND stored_reorg->>'ReorgID' = reorg_id_
      AND stored_reorg->>'PaymentID' = payment_id_
      AND stored_reorg->>'AllocationID' = (
          SELECT allocation_id
          FROM canonicalization_plan
          WHERE canonicalization_id = canonicalization_id_
      )
      AND stored_reorg->>'InstructionDigest' = instruction_digest_
      AND stored_reorg->>'ChainID' = chain_id_::text
      AND stored_reorg->>'Gateway' = gateway_address_
      AND stored_reorg->>'OrphanedEventID' = orphaned_gateway_event_id_
      AND stored_reorg->>'OrphanedTxHash' = orphaned_transaction_hash_
      AND stored_reorg->>'OrphanedEventEvidenceHash' =
          orphaned_event_evidence_hash_
      AND stored_reorg->>'RawEvidenceHash' = orphaned_raw_payload_hash_
      AND stored_reorg->>'TransactionIndex' = transaction_index_::text
      AND stored_reorg->>'ReceiptsRoot' = receipts_root_
      AND stored_reorg->>'InclusionProofHash' = inclusion_proof_hash_
      AND stored_reorg->>'OrphanedReceiptHeaderSignatureHash' =
          orphaned_receipt_header_signature_hash_
      AND stored_reorg->>'OrphanedBlockHash' = orphaned_block_hash_
      AND stored_reorg->>'OrphanedBlock' = orphaned_block_number_::text
      AND stored_reorg->>'ReplacementBlockHash' = replacement_block_hash_
      AND stored_reorg->>'ReplacementBlock' = replacement_block_number_::text
      AND stored_reorg->>'ConfirmationDepth' = confirmation_depth_::text
      AND stored_reorg->>'DetectedHead' = detected_head_block_::text
      AND stored_reorg->>'DetectedHeadHash' = detected_head_hash_
      AND stored_reorg->>'FinalityPolicyHash' = finality_policy_hash_
      AND stored_reorg->>'HeaderAuthorityHash' = header_authority_hash_
      AND stored_reorg->>'ReplacementHeaderSignatureHash' =
          replacement_header_signature_hash_
      AND stored_reorg->>'DetectedHeadHeaderSignatureHash' =
          detected_head_header_signature_hash_
      AND stored_reorg->>'DepthClass' = 'DEEP_FINALITY'
      AND stored_reorg->>'Deep' = 'true'
      AND stored_reorg->>'CompensationRequired' = 'true'
      AND stored_reorg->>'EvidenceHash' = reorg_evidence_hash_
      AND (stored_reorg->>'SubmissionSubmittedAt')::timestamptz =
          submission_submitted_at_
      AND (stored_reorg->>'DetectedAt')::timestamptz = detected_at_
    FOR UPDATE OF coordinator;
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'deep reorg lacks matching coordinator-issued incident authority';
    END IF;

    INSERT INTO canonical_settlement_reorg (
        reorg_id,
        canonicalization_id,
        confirmation_id,
        instruction_digest,
        chain_id,
        gateway_address,
        orphaned_transaction_hash,
        orphaned_gateway_event_id,
        transaction_index,
        receipts_root,
        inclusion_proof_hash,
        finality_policy_hash,
        header_authority_hash,
        orphaned_receipt_header_signature_hash,
        confirmation_head_header_signature_hash,
        replacement_header_signature_hash,
        detected_head_header_signature_hash,
        orphaned_block_hash,
        orphaned_block_number,
        replacement_block_hash,
        replacement_block_number,
        confirmation_depth,
        detected_head_block,
        detected_head_hash,
        reorg_kind,
        compensation_required,
        orphaned_event_evidence_hash,
        orphaned_raw_payload_hash,
        evidence_hash,
        submission_submitted_at,
        detected_at
    ) VALUES (
        reorg_id_,
        canonicalization_id_,
        confirmation_id_,
        instruction_digest_,
        chain_id_,
        gateway_address_,
        orphaned_transaction_hash_,
        orphaned_gateway_event_id_,
        transaction_index_,
        receipts_root_,
        inclusion_proof_hash_,
        finality_policy_hash_,
        header_authority_hash_,
        orphaned_receipt_header_signature_hash_,
        confirmation_head_header_signature_hash_,
        replacement_header_signature_hash_,
        detected_head_header_signature_hash_,
        orphaned_block_hash_,
        orphaned_block_number_,
        replacement_block_hash_,
        replacement_block_number_,
        confirmation_depth_,
        detected_head_block_,
        detected_head_hash_,
        'DEEP',
        true,
        orphaned_event_evidence_hash_,
        orphaned_raw_payload_hash_,
        reorg_evidence_hash_,
        submission_submitted_at_,
        detected_at_
    )
    ON CONFLICT (reorg_id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg AS reorg
        WHERE reorg.reorg_id = reorg_id_
          AND reorg.canonicalization_id = canonicalization_id_
          AND reorg.confirmation_id = confirmation_id_
          AND reorg.instruction_digest = instruction_digest_
          AND reorg.chain_id = chain_id_
          AND reorg.gateway_address = gateway_address_
          AND reorg.orphaned_transaction_hash = orphaned_transaction_hash_
          AND reorg.orphaned_gateway_event_id = orphaned_gateway_event_id_
          AND reorg.transaction_index = transaction_index_
          AND reorg.receipts_root = receipts_root_
          AND reorg.inclusion_proof_hash = inclusion_proof_hash_
          AND reorg.finality_policy_hash = finality_policy_hash_
          AND reorg.header_authority_hash = header_authority_hash_
          AND reorg.orphaned_receipt_header_signature_hash =
              orphaned_receipt_header_signature_hash_
          AND reorg.confirmation_head_header_signature_hash =
              confirmation_head_header_signature_hash_
          AND reorg.replacement_header_signature_hash =
              replacement_header_signature_hash_
          AND reorg.detected_head_header_signature_hash =
              detected_head_header_signature_hash_
          AND reorg.orphaned_block_hash = orphaned_block_hash_
          AND reorg.orphaned_block_number = orphaned_block_number_
          AND reorg.replacement_block_hash = replacement_block_hash_
          AND reorg.replacement_block_number = replacement_block_number_
          AND reorg.confirmation_depth = confirmation_depth_
          AND reorg.detected_head_block = detected_head_block_
          AND reorg.detected_head_hash = detected_head_hash_
          AND reorg.reorg_kind = 'DEEP'
          AND reorg.compensation_required
          AND reorg.orphaned_event_evidence_hash =
              orphaned_event_evidence_hash_
          AND reorg.orphaned_raw_payload_hash = orphaned_raw_payload_hash_
          AND reorg.evidence_hash = reorg_evidence_hash_
          AND reorg.submission_submitted_at = submission_submitted_at_
          AND reorg.detected_at = detected_at_
    ) THEN
        RAISE EXCEPTION 'deep reorg id was reused with conflicting evidence';
    END IF;

    INSERT INTO canonical_settlement_incident (
        incident_id,
        incident_kind,
        reorg_id,
        canonicalization_id,
        payment_id,
        instruction_digest,
        provider_id,
        provider_event_id,
        reported_status,
        canonicalization_state,
        reason_code,
        owner,
        payment_state_unchanged,
        economic_journals_suppressed,
        raw_payload_hash,
        evidence_hash,
        observed_at,
        resolution_deadline
    ) VALUES (
        incident_id_,
        'DEEP_CHAIN_REORG',
        reorg_id_,
        canonicalization_id_,
        payment_id_,
        instruction_digest_,
        provider_id_,
        orphaned_gateway_event_id_,
        'ORPHANED',
        'CONFIRMED',
        'FINALIZED_GATEWAY_EVENT_ORPHANED',
        owner_,
        true,
        false,
        orphaned_raw_payload_hash_,
        reorg_evidence_hash_,
        detected_at_,
        resolution_deadline_
    )
    ON CONFLICT (incident_id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_incident AS incident
        WHERE incident.incident_id = incident_id_
          AND incident.incident_kind = 'DEEP_CHAIN_REORG'
          AND incident.reorg_id = reorg_id_
          AND incident.canonicalization_id = canonicalization_id_
          AND incident.payment_id = payment_id_
          AND incident.instruction_digest = instruction_digest_
          AND incident.provider_id = provider_id_
          AND incident.provider_event_id = orphaned_gateway_event_id_
          AND incident.owner = owner_
          AND incident.raw_payload_hash = orphaned_raw_payload_hash_
          AND incident.evidence_hash = reorg_evidence_hash_
          AND incident.observed_at = detected_at_
          AND incident.resolution_deadline = resolution_deadline_
    ) THEN
        RAISE EXCEPTION 'deep reorg incident id was reused with conflicting evidence';
    END IF;

    FOR link_ IN
        SELECT
            link.ordinal,
            link.journal_id AS original_journal_id,
            original.legal_entity_id,
            original.book_id,
            original.correlation_id,
            original.loan_id
        FROM canonical_settlement_journal_link AS link
        JOIN journal AS original ON original.journal_id = link.journal_id
        WHERE link.confirmation_id = confirmation_id_
        ORDER BY link.ordinal
    LOOP
        reversal_id_ := link_.original_journal_id || ':reorg:' || reorg_id_;
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
        ) VALUES (
            reversal_id_,
            link_.legal_entity_id,
            link_.book_id,
            'canonical-settlement',
            reorg_id_ || ':' || link_.original_journal_id,
            link_.correlation_id,
            reorg_evidence_hash_,
            detected_at_,
            'POSTED',
            'CANONICAL_SETTLEMENT_REORG',
            orphaned_gateway_event_id_,
            link_.loan_id,
            link_.original_journal_id,
            'deep reorganization removed finalized gateway event'
        )
        ON CONFLICT (journal_id) DO NOTHING;

        IF NOT EXISTS (
            SELECT 1
            FROM journal AS reversal
            WHERE reversal.journal_id = reversal_id_
              AND reversal.legal_entity_id = link_.legal_entity_id
              AND reversal.book_id = link_.book_id
              AND reversal.source_system = 'canonical-settlement'
              AND reversal.idempotency_key = reorg_id_ || ':' || link_.original_journal_id
              AND reversal.correlation_id = link_.correlation_id
              AND reversal.evidence_hash = reorg_evidence_hash_
              AND reversal.effective_at = detected_at_
              AND reversal.status = 'POSTED'
              AND reversal.entry_type = 'CANONICAL_SETTLEMENT_REORG'
              AND reversal.source_event_id = orphaned_gateway_event_id_
              AND reversal.loan_id IS NOT DISTINCT FROM link_.loan_id
              AND reversal.reversal_of = link_.original_journal_id
        ) THEN
            RAISE EXCEPTION 'reversal journal id was reused with conflicting evidence';
        END IF;

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
            reversal_id_,
            original_entry.line_number,
            original_entry.account_code,
            CASE original_entry.side WHEN 'DEBIT' THEN 'CREDIT' ELSE 'DEBIT' END,
            original_entry.asset_id,
            original_entry.units,
            original_entry.party_id,
            original_entry.loan_id
        FROM journal_entry AS original_entry
        WHERE original_entry.journal_id = link_.original_journal_id
        ON CONFLICT (journal_id, line_number) DO NOTHING;

        IF EXISTS (
            SELECT 1
            FROM journal_entry AS original_entry
            FULL JOIN journal_entry AS reversal_entry
              ON reversal_entry.journal_id = reversal_id_
             AND reversal_entry.line_number = original_entry.line_number
            WHERE original_entry.journal_id = link_.original_journal_id
              AND (
                  reversal_entry.journal_id IS NULL
                  OR reversal_entry.account_code <> original_entry.account_code
                  OR reversal_entry.side <>
                      CASE original_entry.side WHEN 'DEBIT' THEN 'CREDIT' ELSE 'DEBIT' END
                  OR reversal_entry.asset_id <> original_entry.asset_id
                  OR reversal_entry.units <> original_entry.units
                  OR reversal_entry.party_id IS DISTINCT FROM original_entry.party_id
                  OR reversal_entry.loan_id IS DISTINCT FROM original_entry.loan_id
              )
        ) OR (
            SELECT count(*)
            FROM journal_entry
            WHERE journal_id = reversal_id_
        ) <> (
            SELECT count(*)
            FROM journal_entry
            WHERE journal_id = link_.original_journal_id
        ) THEN
            RAISE EXCEPTION 'derived reorg journal is not the exact opposite';
        END IF;
    END LOOP;

    INSERT INTO canonical_settlement_reorg_compensation (
        compensation_id,
        reorg_id,
        confirmation_id,
        canonicalization_id,
        incident_id,
        instruction_digest,
        orphaned_transaction_hash,
        orphaned_gateway_event_id,
        orphaned_block_hash,
        original_journal_count,
        reversal_journal_count,
        evidence_hash,
        detected_at
    ) VALUES (
        compensation_id_,
        reorg_id_,
        confirmation_id_,
        canonicalization_id_,
        incident_id_,
        instruction_digest_,
        orphaned_transaction_hash_,
        orphaned_gateway_event_id_,
        orphaned_block_hash_,
        journal_count_,
        journal_count_,
        compensation_evidence_hash_,
        detected_at_
    )
    ON CONFLICT (compensation_id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM canonical_settlement_reorg_compensation AS compensation
        WHERE compensation.compensation_id = compensation_id_
          AND compensation.reorg_id = reorg_id_
          AND compensation.confirmation_id = confirmation_id_
          AND compensation.canonicalization_id = canonicalization_id_
          AND compensation.incident_id = incident_id_
          AND compensation.instruction_digest = instruction_digest_
          AND compensation.orphaned_transaction_hash = orphaned_transaction_hash_
          AND compensation.orphaned_gateway_event_id = orphaned_gateway_event_id_
          AND compensation.orphaned_block_hash = orphaned_block_hash_
          AND compensation.original_journal_count = journal_count_
          AND compensation.reversal_journal_count = journal_count_
          AND compensation.evidence_hash = compensation_evidence_hash_
          AND compensation.detected_at = detected_at_
    ) THEN
        RAISE EXCEPTION 'compensation id was reused with conflicting evidence';
    END IF;

    FOR link_ IN
        SELECT ordinal, journal_id
        FROM canonical_settlement_journal_link
        WHERE confirmation_id = confirmation_id_
        ORDER BY ordinal
    LOOP
        reversal_id_ := link_.journal_id || ':reorg:' || reorg_id_;
        INSERT INTO canonical_settlement_reorg_journal_link (
            compensation_id,
            ordinal,
            original_journal_id,
            reversal_journal_id
        ) VALUES (
            compensation_id_,
            link_.ordinal,
            link_.journal_id,
            reversal_id_
        )
        ON CONFLICT (compensation_id, ordinal) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1
            FROM canonical_settlement_reorg_journal_link AS stored
            WHERE stored.compensation_id = compensation_id_
              AND stored.ordinal = link_.ordinal
              AND stored.original_journal_id = link_.journal_id
              AND stored.reversal_journal_id = reversal_id_
        ) THEN
            RAISE EXCEPTION 'reorg journal ordinal was reused with conflicting evidence';
        END IF;
    END LOOP;
    RETURN compensation_id_;
END;
$$;

CREATE INDEX canonical_submission_by_operation
    ON canonicalization_submission (canonicalization_id, attempt_number);

CREATE INDEX canonical_incident_by_owner_deadline
    ON canonical_settlement_incident (owner, resolution_deadline);

CREATE TRIGGER payment_allocation_mode_claim_immutable
BEFORE UPDATE OR DELETE ON payment_allocation_mode_claim
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_coordinator_state_history_immutable
BEFORE UPDATE OR DELETE ON canonical_coordinator_state_history
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_allocation_tombstone_immutable
BEFORE UPDATE OR DELETE ON canonical_allocation_tombstone
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_pending_reversal_quarantine_immutable
BEFORE UPDATE OR DELETE ON canonical_pending_reversal_quarantine
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_reverted_transaction_evidence_immutable
BEFORE UPDATE OR DELETE ON canonical_reverted_transaction_evidence
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_pending_reversal_resolution_evidence_immutable
BEFORE UPDATE OR DELETE ON canonical_pending_reversal_resolution_evidence
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER final_payment_allocation_immutable
BEFORE UPDATE OR DELETE ON final_payment_allocation
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonicalization_eligibility_immutable
BEFORE UPDATE OR DELETE ON canonicalization_eligibility
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonicalization_plan_immutable
BEFORE UPDATE OR DELETE ON canonicalization_plan
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonicalization_submission_immutable
BEFORE UPDATE OR DELETE ON canonicalization_submission
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_settlement_conversion_immutable
BEFORE UPDATE OR DELETE ON canonical_settlement_conversion
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_gateway_event_projection_immutable
BEFORE UPDATE OR DELETE ON canonical_gateway_event_projection
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_settlement_confirmation_immutable
BEFORE UPDATE OR DELETE ON canonical_settlement_confirmation
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_settlement_journal_link_immutable
BEFORE UPDATE OR DELETE ON canonical_settlement_journal_link
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_lender_payout_immutable
BEFORE UPDATE OR DELETE ON canonical_lender_payout
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_borrower_refund_immutable
BEFORE UPDATE OR DELETE ON canonical_borrower_refund
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_settlement_reorg_immutable
BEFORE UPDATE OR DELETE ON canonical_settlement_reorg
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_settlement_incident_immutable
BEFORE UPDATE OR DELETE ON canonical_settlement_incident
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_settlement_reorg_compensation_immutable
BEFORE UPDATE OR DELETE ON canonical_settlement_reorg_compensation
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

CREATE TRIGGER canonical_settlement_reorg_journal_link_immutable
BEFORE UPDATE OR DELETE ON canonical_settlement_reorg_journal_link
FOR EACH ROW EXECUTE FUNCTION reject_posted_mutation();

COMMIT;
