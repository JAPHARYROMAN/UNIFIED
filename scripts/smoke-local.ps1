$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$composeFile = (Resolve-Path -LiteralPath (Join-Path $workspace 'infrastructure\local\compose.yaml')).Path
$migrationRoot = (Resolve-Path -LiteralPath (
    Join-Path $workspace 'services\foundation-ledger\migrations'
)).Path

$running = docker compose --project-name unified-local --file $composeFile ps --status running --quiet
if (($running | Measure-Object).Count -lt 5) {
    throw 'The five unified-local services are not all running.'
}

$provider = Invoke-RestMethod -Uri 'http://127.0.0.1:58080/v1/payments/mock-payment-001'
if ($provider.contains_real_value -ne $false -or $provider.finality_status -ne 'PROVISIONAL') {
    throw 'Mock provider returned unsafe or unexpected evidence.'
}

$topics = docker compose --project-name unified-local --file $composeFile exec -T redpanda `
    rpk topic list
if ($topics -notmatch 'unified\.foundation\.events') {
    docker compose --project-name unified-local --file $composeFile exec -T redpanda `
        rpk topic create unified.foundation.events | Out-Null
}
'{"event_id":"event-001","event_type":"FoundationJournalPosted"}' |
    docker compose --project-name unified-local --file $composeFile exec -T redpanda `
        rpk topic produce unified.foundation.events | Out-Null

Get-ChildItem -LiteralPath $migrationRoot -Filter '*.sql' |
    Sort-Object Name |
    ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw |
            docker compose --project-name unified-local --file $composeFile exec -T postgres `
                psql --set ON_ERROR_STOP=1 --username unified_local --dbname unified_local | Out-Null
    }

$sampleSql = @'
BEGIN;
INSERT INTO command_log (
  command_id, command_type, schema_version, idempotency_key, correlation_id, payload, payload_hash
) VALUES (
  'command-001', 'FoundationPostJournal', 'v1', 'foundation-smoke-001',
  'correlation-001', '{"contains_real_value":false}', 'local-command-hash'
);
INSERT INTO journal (
  journal_id, legal_entity_id, book_id, source_system, idempotency_key,
  correlation_id, evidence_hash, effective_at, status
) VALUES (
  'journal-001', 'entity-local', 'protocol', 'foundation-smoke',
  'foundation-smoke-001', 'correlation-001', 'local-evidence-hash',
  clock_timestamp(), 'POSTED'
);
INSERT INTO journal_entry (
  journal_id, line_number, account_code, side, asset_id, units
) VALUES
  ('journal-001', 1, '1310', 'DEBIT', 'asset:local:usd', 1000),
  ('journal-001', 2, '2310', 'CREDIT', 'asset:local:usd', 1000);
INSERT INTO event_log (
  event_id, event_type, schema_version, authority_class, aggregate_id,
  aggregate_version, correlation_id, causation_id, payload, payload_hash
) VALUES (
  'event-001', 'FoundationJournalPosted', 'v1', 'UNIFIED_LEDGER',
  'journal-001', 1, 'correlation-001', 'command-001',
  '{"contains_real_value":false}', 'local-event-hash'
);
INSERT INTO payment_intent (
  payment_id, legal_entity_id, idempotency_key, correlation_id, payer_reference,
  loan_id, provider_id, rail, purpose, asset_id, units, expires_at,
  schema_version, created_at
) VALUES (
  'payment-local-001', 'entity-local', 'payment-intent-local-001',
  'payment-correlation-local-001', 'payer-opaque-local-001', NULL,
  'mock-provider-local', 'BANK', 'UNALLOCATED_SYNTHETIC_PAYMENT',
  'asset:local:usd', 1000, clock_timestamp() + interval '1 hour',
  1, clock_timestamp()
);
INSERT INTO provider_callback_ingress (
  ingress_id, provider_id, provider_event_id, raw_payload, raw_payload_hash,
  signature_hash, received_at
) VALUES
  (
    'ingress-processing-local-001', 'mock-provider-local',
    'provider-event-processing-local-001',
    convert_to('{"contains_real_value":false,"status":"PROCESSING"}', 'UTF8'),
    'raw-processing-local-hash', 'signature-processing-local-hash', clock_timestamp()
  ),
  (
    'ingress-provisional-local-001', 'mock-provider-local',
    'provider-event-provisional-local-001',
    convert_to('{"contains_real_value":false,"status":"PROVISIONAL"}', 'UTF8'),
    'raw-provisional-local-hash', 'signature-provisional-local-hash', clock_timestamp()
  );
INSERT INTO payment_state_event (
  event_id, payment_id, provider_id, provider_event_id, aggregate_version,
  from_status, to_status, asset_id, units, evidence_hash, journal_ids,
  occurred_at, received_at
) VALUES (
  'payment-event-processing-local-001', 'payment-local-001', 'mock-provider-local',
  'provider-event-processing-local-001', 2, 'CREATED', 'PROCESSING',
  'asset:local:usd', 1000, 'processing-evidence-local', '{}',
  clock_timestamp(), clock_timestamp()
);
INSERT INTO journal (
  journal_id, legal_entity_id, book_id, source_system, idempotency_key,
  correlation_id, evidence_hash, effective_at, status
) VALUES (
  'journal-payment-provisional-local-001', 'entity-local', 'protocol',
  'payment-orchestrator', 'payment-provisional-local-001',
  'payment-correlation-local-001', 'provisional-evidence-local',
  clock_timestamp(), 'POSTED'
);
INSERT INTO journal_entry (
  journal_id, line_number, account_code, side, asset_id, units
) VALUES
  ('journal-payment-provisional-local-001', 1, '9140', 'DEBIT', 'asset:local:usd', 1000),
  ('journal-payment-provisional-local-001', 2, '9120', 'CREDIT', 'asset:local:usd', 1000);
INSERT INTO payment_state_event (
  event_id, payment_id, provider_id, provider_event_id, aggregate_version,
  from_status, to_status, asset_id, units, evidence_hash, journal_ids,
  occurred_at, received_at
) VALUES (
  'payment-event-provisional-local-001', 'payment-local-001', 'mock-provider-local',
  'provider-event-provisional-local-001', 3, 'PROCESSING', 'PROVISIONAL',
  'asset:local:usd', 1000, 'provisional-evidence-local',
  ARRAY['journal-payment-provisional-local-001'],
  clock_timestamp(), clock_timestamp()
);
INSERT INTO payment_reconciliation_run (
  run_id, provider_id, asset_id, as_of, provider_snapshot_hash,
  ledger_snapshot_hash, expected_units, observed_units, difference_units,
  unmatched_items, status, owner, resolution_deadline
) VALUES (
  'reconciliation-local-001', 'mock-provider-local', 'asset:local:usd',
  clock_timestamp(), 'provider-snapshot-local-hash', 'ledger-snapshot-local-hash',
  0, 0, 0, 0, 'MATCHED', 'payment-operations', clock_timestamp() + interval '1 day'
);
COMMIT;
'@
$sampleSql |
    docker compose --project-name unified-local --file $composeFile exec -T postgres `
        psql --set ON_ERROR_STOP=1 --username unified_local --dbname unified_local | Out-Null

$imbalance = docker compose --project-name unified-local --file $composeFile exec -T postgres `
    psql --tuples-only --no-align --username unified_local --dbname unified_local `
    --command 'SELECT COALESCE(SUM(ABS(debit_units-credit_units)),0) FROM journal_balance;'
if ($imbalance.Trim() -ne '0') {
    throw "Foundation journal is unbalanced: $imbalance"
}

$counts = docker compose --project-name unified-local --file $composeFile exec -T postgres `
    psql --tuples-only --no-align --username unified_local --dbname unified_local `
    --command 'SELECT (SELECT count(*) FROM command_log)||'',''||(SELECT count(*) FROM event_log)||'',''||(SELECT count(*) FROM journal)||'',''||(SELECT count(*) FROM payment_intent)||'',''||(SELECT count(*) FROM payment_state_event)||'',''||(SELECT count(*) FROM payment_reconciliation_run);'
if ($counts.Trim() -ne '1,1,2,1,2,1') {
    throw "Unexpected foundation and payment evidence counts: $counts"
}

Write-Output 'Local smoke passed: command, event, payment lifecycle, balanced journals, and reconciliation persisted.'
