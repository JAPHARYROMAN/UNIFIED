[CmdletBinding()]
param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 55432,
    [string]$UserName = "unified_local",
    [string]$Password = "local-only-not-a-secret",
    [string]$PsqlPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$migrationRoot = Join-Path $repoRoot "services/foundation-ledger/migrations"
$fixturePath = Join-Path $migrationRoot `
    "tests/000010_000012_crosschain_foundation_test.sql"
$databaseName = "unified_cancel_concurrency_$PID"

if ($databaseName -notmatch '^[a-z0-9_]+$') {
    throw "Generated disposable database name is unsafe: $databaseName"
}
if ([string]::IsNullOrWhiteSpace($PsqlPath)) {
    $psqlCommand = Get-Command psql -ErrorAction SilentlyContinue
    if ($null -ne $psqlCommand) {
        $PsqlPath = $psqlCommand.Source
    } elseif ($IsWindows) {
        $PsqlPath = "C:\Program Files\PostgreSQL\17\bin\psql.exe"
    }
}
if (-not (Test-Path -LiteralPath $PsqlPath -PathType Leaf)) {
    throw "psql was not found; pass -PsqlPath explicitly"
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "unified-phase8-cancellation-$PID"
$committedFixture = Join-Path $temporaryRoot "committed-fixture.sql"
$replaySql = Join-Path $temporaryRoot "concurrent-replay.sql"
$firstWriterSql = Join-Path $temporaryRoot "first-writer.sql"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
$jobs = @()

$env:PGPASSWORD = $Password
$commonArguments = @(
    "-h", $HostName,
    "-p", $Port.ToString(),
    "-U", $UserName,
    "-v", "ON_ERROR_STOP=1"
)

function Invoke-PsqlFile {
    param(
        [Parameter(Mandatory)]
        [string]$Database,
        [Parameter(Mandatory)]
        [string]$Path
    )
    & $PsqlPath @commonArguments "-d" $Database "-f" $Path
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed for $Path"
    }
}

function Invoke-PsqlScalar {
    param(
        [Parameter(Mandatory)]
        [string]$Database,
        [Parameter(Mandatory)]
        [string]$Query
    )
    $value = & $PsqlPath @commonArguments "-Atq" "-d" $Database "-c" $Query
    if ($LASTEXITCODE -ne 0) {
        throw "psql scalar query failed"
    }
    return (($value | Select-Object -Last 1).ToString()).Trim()
}

function Start-PsqlJob {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    return Start-Job -ArgumentList @(
        $PsqlPath, $HostName, $Port, $UserName,
        $databaseName, $Path, $Password
    ) -ScriptBlock {
        param(
            $psql, $hostName, $port, $userName,
            $database, $sqlPath, $password
        )
        $env:PGPASSWORD = $password
        & $psql `
            "-h" $hostName `
            "-p" $port.ToString() `
            "-U" $userName `
            "-v" "ON_ERROR_STOP=1" `
            "-d" $database `
            "-f" $sqlPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "concurrent psql exited $LASTEXITCODE"
        }
    }
}

try {
    & $PsqlPath @commonArguments "-d" "postgres" "-c" `
        "CREATE DATABASE $databaseName"
    if ($LASTEXITCODE -ne 0) {
        throw "failed to create disposable database $databaseName"
    }

    Get-ChildItem -LiteralPath $migrationRoot -Filter "*.sql" -File |
        Sort-Object Name |
        ForEach-Object {
            Invoke-PsqlFile -Database $databaseName -Path $_.FullName
        }

    $fixture = [System.IO.File]::ReadAllText($fixturePath)
    $rollbackIndex = $fixture.LastIndexOf(
        "ROLLBACK;",
        [System.StringComparison]::Ordinal
    )
    if ($rollbackIndex -lt 0) {
        throw "migration fixture has no terminal ROLLBACK marker"
    }
    $fixture = $fixture.Remove($rollbackIndex, "ROLLBACK;".Length).
        Insert($rollbackIndex, "COMMIT;")
    [System.IO.File]::WriteAllText($committedFixture, $fixture)
    Invoke-PsqlFile -Database $databaseName -Path $committedFixture

$completionCall = @'
SELECT crosschain.commit_loan_cancellation_completion(
    'cancel-zero', 'loan-cancel-zero', 'lock-cancel-zero',
    sha256(convert_to('cancel-zero-completion', 'UTF8')),
    'phase8-report',
    decode(repeat('e3', 20), 'hex'), decode(repeat('e4', 20), 'hex'),
    decode(repeat('00', 32), 'hex'), decode(repeat('00', 32), 'hex'),
    decode(repeat('a4', 32), 'hex'),
    decode(repeat('f1', 20), 'hex'), decode(repeat('a1', 20), 'hex'),
    decode(repeat('a2', 20), 'hex'), 100,
    decode(repeat('f3', 32), 'hex'),
    sha256(convert_to('cancel-zero-source-burn', 'UTF8')), 307,
    sha256(convert_to('cancel-zero-source-evidence', 'UTF8')),
    '2026-01-04 00:02:00+00',
    sha256(convert_to('cancel-zero-refund', 'UTF8')), 308,
    sha256(convert_to('cancel-zero-refund-result', 'UTF8')),
    '2026-01-04 00:02:00+00'
);
'@
    $replayContent = @"
\set ON_ERROR_STOP on
SET application_name = 'phase8-cancel-race-b';
SET ROLE unified_crosschain_runtime;
$completionCall
"@
    [System.IO.File]::WriteAllText($replaySql, $replayContent)

    $firstWriterContent = @"
\set ON_ERROR_STOP on
SET application_name = 'phase8-cancel-race-a';
BEGIN;
SET ROLE unified_crosschain_runtime;
$completionCall
RESET ROLE;
DO `$phase8_cancellation_hold`$
DECLARE
    attempts integer := 0;
BEGIN
    LOOP
        EXIT WHEN (
            SELECT released
            FROM public.phase8_cancellation_concurrency_barrier
            WHERE barrier_id = 1
        );
        attempts := attempts + 1;
        IF attempts > 300 THEN
            RAISE EXCEPTION 'concurrency barrier timed out';
        END IF;
        PERFORM pg_sleep(0.1);
    END LOOP;
END;
`$phase8_cancellation_hold`$;
COMMIT;
"@
    [System.IO.File]::WriteAllText($firstWriterSql, $firstWriterContent)

    & $PsqlPath @commonArguments "-d" $databaseName "-c" @"
CREATE TABLE public.phase8_cancellation_concurrency_barrier (
    barrier_id integer PRIMARY KEY,
    released boolean NOT NULL
);
INSERT INTO public.phase8_cancellation_concurrency_barrier
    (barrier_id, released) VALUES (1, false);
"@
    if ($LASTEXITCODE -ne 0) {
        throw "failed to create concurrency barrier"
    }

    $jobs = @(Start-PsqlJob -Path $firstWriterSql)
    $deadline = (Get-Date).AddSeconds(10)
    do {
        $atBarrier = Invoke-PsqlScalar -Database $databaseName -Query @"
SELECT count(*)
FROM pg_stat_activity
WHERE datname = '$databaseName'
  AND application_name = 'phase8-cancel-race-a'
  AND state = 'active'
  AND query LIKE '%phase8_cancellation_hold%';
"@
        if ($atBarrier -eq "1") {
            break
        }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    if ($atBarrier -ne "1") {
        throw "first writer did not reach the controlled transaction barrier"
    }

    $jobs += Start-PsqlJob -Path $replaySql
    $deadline = (Get-Date).AddSeconds(10)
    do {
        $waiting = Invoke-PsqlScalar -Database $databaseName -Query @"
SELECT count(*)
FROM pg_stat_activity
WHERE datname = '$databaseName'
  AND application_name = 'phase8-cancel-race-b'
  AND state = 'active'
  AND wait_event_type = 'Lock';
"@
        if ($waiting -eq "1") {
            break
        }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    if ($waiting -ne "1") {
        throw "second writer never contended on the first completion"
    }
    Write-Output (
        "Observed second first-completion writer waiting on a PostgreSQL Lock."
    )

    & $PsqlPath @commonArguments "-d" $databaseName "-c" `
        "UPDATE public.phase8_cancellation_concurrency_barrier SET released = true WHERE barrier_id = 1" |
        Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "failed to release first writer barrier"
    }

    $jobs | Wait-Job | Out-Null
    $jobFailures = $jobs | Where-Object State -ne "Completed"
    $jobOutput = $jobs | Receive-Job
    $jobs | Remove-Job -Force
    if ($jobFailures.Count -ne 0) {
        $jobOutput | Out-String | Write-Error
        throw "one or more concurrent replay sessions failed"
    }
    # A third session proves the exact post-terminal replay remains a no-op
    # after the two first-completion contenders settle.
    Invoke-PsqlFile -Database $databaseName -Path $replaySql

    $verification = @"
DO `$verify`$
BEGIN
    IF (
        SELECT count(*) FROM crosschain.loan_cancellation_completions
        WHERE cancellation_id = 'cancel-zero'
    ) <> 1 OR (
        SELECT count(*) FROM ledger.bridge_journal_links
        WHERE message_id =
            sha256(convert_to('cancel-zero-completion', 'UTF8'))
    ) <> 3 OR NOT EXISTS (
        SELECT 1 FROM crosschain.loan_routes
        WHERE loan_id = 'loan-cancel-zero'
          AND lifecycle_state = 'CANCELLED'
          AND state_version = 3
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.bridge_locks
        WHERE lock_id = 'lock-cancel-zero'
          AND status = 'COMPENSATED'
          AND burned_units = 100
          AND released_units = 100
    ) OR NOT EXISTS (
        SELECT 1 FROM crosschain.loan_cancellation_completions
        WHERE cancellation_id = 'cancel-zero'
          AND loan_id = 'loan-cancel-zero'
          AND funding_lock_id = 'lock-cancel-zero'
          AND lender_id = 'lender-cancel-zero'
          AND wrapped_asset_id = 'wuft'
          AND canonical_asset_id = 'uft'
          AND units = 100
    ) OR EXISTS (
        SELECT link.message_id
        FROM ledger.bridge_journal_links AS link
        JOIN public.journal_entry AS debit
          ON debit.journal_id = link.journal_id AND debit.side = 'DEBIT'
        JOIN public.journal_entry AS credit
          ON credit.journal_id = link.journal_id AND credit.side = 'CREDIT'
        WHERE link.message_id =
            sha256(convert_to('cancel-zero-completion', 'UTF8'))
        GROUP BY link.message_id
        HAVING array_agg(
            debit.account_code || ':' || credit.account_code
            ORDER BY debit.account_code, credit.account_code
        ) <> ARRAY['2230:1410', '7160:9150', '9150:7150']::text[]
    ) OR EXISTS (
        SELECT 1
        FROM ledger.bridge_journal_links AS link
        JOIN public.journal_balance AS balance
          ON balance.journal_id = link.journal_id
        WHERE link.message_id =
            sha256(convert_to('cancel-zero-completion', 'UTF8'))
          AND balance.debit_units <> balance.credit_units
    ) THEN
        RAISE EXCEPTION
            'concurrent exact replay changed cancellation cardinality';
    END IF;
END;
`$verify`$;
"@
    & $PsqlPath @commonArguments "-d" $databaseName "-c" $verification
    if ($LASTEXITCODE -ne 0) {
        throw "concurrent cancellation replay verification failed"
    }
    & $PsqlPath @commonArguments "-d" $databaseName "-c" `
        "DROP TABLE public.phase8_cancellation_concurrency_barrier" |
        Out-Null
    Write-Output "Phase 8 cancellation first-completion contention: PASS"
} finally {
    if ($jobs.Count -gt 0) {
        $jobs | Where-Object State -eq "Running" | Stop-Job
        $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    }
    & $PsqlPath @commonArguments "-d" "postgres" "-c" `
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$databaseName' AND pid <> pg_backend_pid()" |
        Out-Null
    & $PsqlPath @commonArguments "-d" "postgres" "-c" `
        "DROP DATABASE IF EXISTS $databaseName" |
        Out-Null
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
