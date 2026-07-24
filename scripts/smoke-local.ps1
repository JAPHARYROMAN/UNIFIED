$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$composeFile = (Resolve-Path -LiteralPath (Join-Path $workspace 'infrastructure\local\compose.yaml')).Path
$migration = (Resolve-Path -LiteralPath (
    Join-Path $workspace 'services\foundation-ledger\migrations\000001_foundation_ledger.sql'
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

Get-Content -LiteralPath $migration -Raw |
    docker compose --project-name unified-local --file $composeFile exec -T postgres `
        psql --set ON_ERROR_STOP=1 --username unified_local --dbname unified_local | Out-Null

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
  ('journal-001', 1, '1000', 'DEBIT', 'asset:local:usd', 1000),
  ('journal-001', 2, '2000', 'CREDIT', 'asset:local:usd', 1000);
INSERT INTO event_log (
  event_id, event_type, schema_version, authority_class, aggregate_id,
  aggregate_version, correlation_id, causation_id, payload, payload_hash
) VALUES (
  'event-001', 'FoundationJournalPosted', 'v1', 'UNIFIED_LEDGER',
  'journal-001', 1, 'correlation-001', 'command-001',
  '{"contains_real_value":false}', 'local-event-hash'
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
    --command 'SELECT (SELECT count(*) FROM command_log)||'',''||(SELECT count(*) FROM event_log)||'',''||(SELECT count(*) FROM journal);'
if ($counts.Trim() -ne '1,1,1') {
    throw "Unexpected command,event,journal counts: $counts"
}

Write-Output 'Local smoke passed: command and event recorded; balanced journal persisted.'
