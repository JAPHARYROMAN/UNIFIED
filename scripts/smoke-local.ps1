$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$composeFile = (Resolve-Path -LiteralPath (Join-Path $workspace 'infrastructure\local\compose.yaml')).Path
$migrationRoot = (Resolve-Path -LiteralPath (
    Join-Path $workspace 'services\foundation-ledger\migrations'
)).Path

$running = docker compose --project-name unified-local --file $composeFile ps --status running --quiet
if (($running | Measure-Object).Count -lt 8) {
    throw 'The eight unified-local services are not all running.'
}

$provider = Invoke-RestMethod -Uri 'http://127.0.0.1:58080/v1/payments/mock-payment-001'
if ($provider.contains_real_value -ne $false -or $provider.finality_status -ne 'PROVISIONAL') {
    throw 'Mock provider returned unsafe or unexpected evidence.'
}

$homeChain = docker compose --project-name unified-local --file $composeFile exec -T `
    home-anvil cast chain-id --rpc-url http://127.0.0.1:8545
$satelliteChain = docker compose --project-name unified-local --file $composeFile exec -T `
    satellite-anvil cast chain-id --rpc-url http://127.0.0.1:8545
if ($homeChain.Trim() -ne '31337' -or $satelliteChain.Trim() -ne '31338') {
    throw "Unexpected local chain domains: home=$homeChain, satellite=$satelliteChain"
}

$transportBody = @{
    message_id = '0xphase8localsynthetic'
    contains_real_value = $false
} | ConvertTo-Json -Compress
$providerA = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:58081/v1/messages' `
    -ContentType 'application/json' -Body $transportBody
$providerB = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:58082/v1/messages' `
    -ContentType 'application/json' -Body $transportBody
if (
    $providerA.authority -ne 'TRANSPORT_ONLY' -or
    $providerB.authority -ne 'TRANSPORT_ONLY' -or
    $providerA.contains_real_value -ne $false -or
    $providerB.contains_real_value -ne $false
) {
    throw 'Mock cross-chain providers asserted authority or real value.'
}
$retryable = Invoke-WebRequest -Method Post `
    -Uri 'http://127.0.0.1:58081/v1/faults/retryable' `
    -ContentType 'application/json' -Body $transportBody -SkipHttpErrorCheck
if ($retryable.StatusCode -ne 503) {
    throw 'Provider A did not expose the bounded retryable-failure fixture.'
}
$failover = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:58082/v1/messages' `
    -ContentType 'application/json' -Body $transportBody
$duplicate = Invoke-RestMethod -Method Post `
    -Uri 'http://127.0.0.1:58082/v1/faults/duplicate' `
    -ContentType 'application/json' -Body $transportBody
$fabricated = Invoke-RestMethod -Method Post `
    -Uri 'http://127.0.0.1:58082/v1/faults/fabricated-authority' `
    -ContentType 'application/json' -Body $transportBody
if (
    $failover.provider -ne 'mock-bridge-provider-b' -or
    $duplicate.delivery_status -ne 'DUPLICATE' -or
    $duplicate.authority -ne 'TRANSPORT_ONLY' -or
    $fabricated.authority -ne 'FABRICATED_FINALITY'
) {
    throw 'Cross-chain failover, duplicate, or fabricated-authority fixtures drifted.'
}

$topics = (
    docker compose --project-name unified-local --file $composeFile exec -T redpanda `
        rpk topic list
) -join "`n"
if ($topics -notmatch 'unified\.foundation\.events') {
    docker compose --project-name unified-local --file $composeFile exec -T redpanda `
        rpk topic create unified.foundation.events | Out-Null
}
if ($topics -notmatch 'unified\.crosschain\.messages') {
    docker compose --project-name unified-local --file $composeFile exec -T redpanda `
        rpk topic create unified.crosschain.messages | Out-Null
}
'{"event_id":"event-001","event_type":"FoundationJournalPosted"}' |
    docker compose --project-name unified-local --file $composeFile exec -T redpanda `
        rpk topic produce unified.foundation.events | Out-Null
'{"message_id":"0xphase8localsynthetic","state":"SENT","contains_real_value":false}' |
    docker compose --project-name unified-local --file $composeFile exec -T redpanda `
        rpk topic produce unified.crosschain.messages | Out-Null

Get-ChildItem -LiteralPath $migrationRoot -Filter '*.sql' |
    Sort-Object Name |
    ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw |
            docker compose --project-name unified-local --file $composeFile exec -T postgres `
                psql --set ON_ERROR_STOP=1 --username unified_local --dbname unified_local | Out-Null
    }

$phase8MigrationTest = Join-Path $migrationRoot `
    'tests\000010_000012_crosschain_foundation_test.sql'
Get-Content -LiteralPath $phase8MigrationTest -Raw |
    docker compose --project-name unified-local --file $composeFile exec -T postgres `
        psql --set ON_ERROR_STOP=1 --username unified_local --dbname unified_local | Out-Null

$priorCoordinatorDatabaseUrl = $env:UNIFIED_CROSSCHAIN_DATABASE_URL
try {
    $env:UNIFIED_CROSSCHAIN_DATABASE_URL = `
        'postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable'
    $coordinatorStatus = go run ./services/cross-chain-coordinator/cmd/server `
        --mode smoke --timeout 10s
    if ($coordinatorStatus -notmatch '"repository":"crosschain"' -or `
        $coordinatorStatus -notmatch '"status":"ok"') {
        throw "Cross-chain coordinator did not rehydrate its SQL surface: $coordinatorStatus"
    }
} finally {
    if ($null -eq $priorCoordinatorDatabaseUrl) {
        Remove-Item Env:UNIFIED_CROSSCHAIN_DATABASE_URL -ErrorAction SilentlyContinue
    } else {
        $env:UNIFIED_CROSSCHAIN_DATABASE_URL = $priorCoordinatorDatabaseUrl
    }
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

Write-Output 'Local smoke passed: two chains, providers, cross-chain SQL/runtime, command, event, payment lifecycle, balanced journals, and reconciliation.'
