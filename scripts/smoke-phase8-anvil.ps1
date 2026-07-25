param(
    [string]$HomeRpc,
    [string]$SatelliteRpc,
    [string]$ProviderAUrl,
    [string]$ProviderBUrl
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
if ([string]::IsNullOrWhiteSpace($HomeRpc)) {
    $HomeRpc = if ($env:PHASE8_HOME_RPC) {
        $env:PHASE8_HOME_RPC
    } else {
        'http://127.0.0.1:8545'
    }
}
if ([string]::IsNullOrWhiteSpace($SatelliteRpc)) {
    $SatelliteRpc = if ($env:PHASE8_SATELLITE_RPC) {
        $env:PHASE8_SATELLITE_RPC
    } else {
        'http://127.0.0.1:8546'
    }
}
if ([string]::IsNullOrWhiteSpace($ProviderAUrl)) {
    $ProviderAUrl = if ($env:UNIFIED_MOCK_BRIDGE_PROVIDER_A) {
        $env:UNIFIED_MOCK_BRIDGE_PROVIDER_A
    } else {
        'http://127.0.0.1:58081'
    }
}
if ([string]::IsNullOrWhiteSpace($ProviderBUrl)) {
    $ProviderBUrl = if ($env:UNIFIED_MOCK_BRIDGE_PROVIDER_B) {
        $env:UNIFIED_MOCK_BRIDGE_PROVIDER_B
    } else {
        'http://127.0.0.1:58082'
    }
}

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$protocol = (Resolve-Path -LiteralPath (Join-Path $workspace 'protocol')).Path
$output = Join-Path $protocol 'deployments\local'
$releaseCache = Join-Path $workspace '.cache\phase8-release'
$blueprintPath = Join-Path $output 'phase8-live-blueprint.json'
$flowPath = Join-Path $releaseCache 'phase8-authenticated-flow.json'
$releaseEvidencePath = Join-Path $output 'phase8-release-evidence.json'
$verifierSuffix = if ($IsWindows) { '.exe' } else { '' }
$verifierPath = Join-Path $releaseCache "verify-phase8-inclusion$verifierSuffix"
$observerSigner = Join-Path $workspace 'tools\sign_phase8_observer.py'
$expectedHomeObserver = '0xe84d4f1b0cf0e0217292b079bb4db43ad1416f4609b111675e720d2b1dbc0eac'
$expectedSatelliteObserver = '0xb442c9cb0eb1bce60df619505451f95701b64e32b269bda231d95a7475f5a6ac'

$homeObserver = (& uv run python $observerSigner public home).Trim()
$satelliteObserver = (& uv run python $observerSigner public satellite).Trim()
if (
    $homeObserver -cne $expectedHomeObserver -or
    $satelliteObserver -cne $expectedSatelliteObserver
) {
    throw 'Derived Phase 8 observer public keys differ from the reviewed fixtures.'
}

function Resolve-FoundryTool([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    $candidate = Join-Path $workspace ".cache\foundry-v1.7.1\$Name$suffix"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "Required Foundry tool '$Name' was not found in PATH or the workspace cache."
}

function Remove-Phase8FoundryRuns([string]$Root) {
    $expectedRoot = [IO.Path]::GetFullPath($Root)
    $protocolBoundary = $protocol.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $expectedRoot.StartsWith(
        $protocolBoundary,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Phase 8 Foundry cleanup root escaped protocol: $expectedRoot"
    }
    if (-not (Test-Path -LiteralPath $expectedRoot)) { return }
    Get-ChildItem -LiteralPath $expectedRoot -Directory -Filter 'DeployPhase8Local.s.sol-*' |
        ForEach-Object {
            $resolved = (Resolve-Path -LiteralPath $_.FullName).Path
            if (
                [IO.Path]::GetDirectoryName($resolved) -ne $expectedRoot -or
                -not [IO.Path]::GetFileName($resolved).StartsWith(
                    'DeployPhase8Local.s.sol-',
                    [StringComparison]::Ordinal
                )
            ) {
                throw "Refusing unexpected Phase 8 Foundry cleanup target: $resolved"
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
}

$anvil = Resolve-FoundryTool 'anvil'
$cast = Resolve-FoundryTool 'cast'
$forge = Resolve-FoundryTool 'forge'

function Test-AnvilEndpoint([string]$Rpc, [string]$ExpectedChainId) {
    try {
        $chainId = & $cast chain-id --rpc-url $Rpc 2>$null
        return $LASTEXITCODE -eq 0 -and $chainId -eq $ExpectedChainId
    } catch {
        return $false
    }
}

if (-not $protocol.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Protocol path escaped the workspace.'
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
New-Item -ItemType Directory -Force -Path $releaseCache | Out-Null
foreach ($staleEvidence in @($blueprintPath, $flowPath, $releaseEvidencePath, $verifierPath)) {
    if (Test-Path -LiteralPath $staleEvidence) {
        Remove-Item -LiteralPath $staleEvidence -Force
    }
}

$homeProcess = $null
$satelliteProcess = $null
$timestampsPinned = $false
try {
    $homeExisting = Test-AnvilEndpoint $HomeRpc '31337'
    $satelliteExisting = Test-AnvilEndpoint $SatelliteRpc '31338'
    if (-not $homeExisting) {
        if ($HomeRpc -ne 'http://127.0.0.1:8545') {
            throw "Home endpoint is unavailable or not chain 31337: $HomeRpc"
        }
        $startHome = @{
            FilePath = $anvil
            PassThru = $true
            ArgumentList = @('--silent', '--port', '8545', '--chain-id', '31337')
        }
        if ($IsWindows) { $startHome.WindowStyle = 'Hidden' }
        $homeProcess = Start-Process @startHome
    }
    if (-not $satelliteExisting) {
        if ($SatelliteRpc -ne 'http://127.0.0.1:8546') {
            throw "Satellite endpoint is unavailable or not chain 31338: $SatelliteRpc"
        }
        $startSatellite = @{
            FilePath = $anvil
            PassThru = $true
            ArgumentList = @('--silent', '--port', '8546', '--chain-id', '31338')
        }
        if ($IsWindows) { $startSatellite.WindowStyle = 'Hidden' }
        $satelliteProcess = Start-Process @startSatellite
    }

    foreach ($rpc in @($HomeRpc, $SatelliteRpc)) {
        $ready = $false
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            try {
                $chainId = & $cast chain-id --rpc-url $rpc
                if ($LASTEXITCODE -eq 0) {
                    $ready = $true
                    break
                }
            } catch { }
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) { throw "Anvil did not start at $rpc." }
    }

    foreach ($rpc in @($HomeRpc, $SatelliteRpc)) {
        & $cast rpc --rpc-url $rpc anvil_setBlockTimestampInterval 0 | Out-Null
    }
    $timestampsPinned = $true
    $homeTimestamp = [uint64](& $cast block latest --field timestamp --rpc-url $HomeRpc)
    $satelliteTimestamp = [uint64](
        & $cast block latest --field timestamp --rpc-url $SatelliteRpc
    )
    $commonTimestamp = if ($homeTimestamp -gt $satelliteTimestamp) {
        $homeTimestamp + 3600
    } else {
        $satelliteTimestamp + 3600
    }
    foreach ($rpc in @($HomeRpc, $SatelliteRpc)) {
        & $cast rpc --rpc-url $rpc evm_setNextBlockTimestamp $commonTimestamp | Out-Null
        & $cast rpc --rpc-url $rpc evm_mine | Out-Null
    }

    Push-Location -LiteralPath $protocol
    try {
        Remove-Phase8FoundryRuns (Join-Path $protocol 'broadcast\multi')
        Remove-Phase8FoundryRuns (Join-Path $protocol 'cache\multi')
        & $forge clean
        if ($LASTEXITCODE -ne 0) { throw 'Phase 8 Foundry clean preflight failed.' }
        & $forge script 'script/DeployPhase8Local.s.sol:DeployPhase8Local' `
            --sig 'runDeployOnly(string,string,string)' `
            $HomeRpc $SatelliteRpc $output `
            --sender '0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266' `
            --unlocked --broadcast --ffi --force --deny never
        if ($LASTEXITCODE -ne 0) { throw 'Phase 8 deploy-only script failed.' }
    } finally {
        Pop-Location
    }

    $homeManifest = Get-Content -LiteralPath (
        Join-Path $output 'phase8-home-31337.json'
    ) -Raw | ConvertFrom-Json
    $satelliteManifest = Get-Content -LiteralPath (
        Join-Path $output 'phase8-satellite-31338.json'
    ) -Raw | ConvertFrom-Json
    if (
        $homeManifest.chain_id -ne 31337 -or
        $satelliteManifest.chain_id -ne 31338 -or
        $homeManifest.contains_real_value -ne $false -or
        $satelliteManifest.contains_real_value -ne $false -or
        $homeManifest.mint_route_hash -ne $satelliteManifest.mint_route_hash
    ) {
        throw 'Phase 8 deployment manifests failed safety/parity checks.'
    }
    if (-not (Test-Path -LiteralPath $blueprintPath)) {
        throw 'Phase 8 deploy-only blueprint was not written.'
    }

    Push-Location -LiteralPath $workspace
    try {
        go build -o $verifierPath `
            ./services/chain-indexer/cmd/verify-phase8-inclusion
        if ($LASTEXITCODE -ne 0) {
            throw 'Production Phase 7C inclusion verifier build failed.'
        }
        & uv run --frozen python tools/run_phase8_authenticated_flow.py `
            --home-rpc $HomeRpc `
            --satellite-rpc $SatelliteRpc `
            --provider-a-url $ProviderAUrl `
            --provider-b-url $ProviderBUrl `
            --blueprint $blueprintPath `
            --verifier $verifierPath `
            --output $flowPath `
            --max-messages 8
        if ($LASTEXITCODE -ne 0) {
            throw 'Authenticated eight-message Phase 8 flow failed.'
        }
        & uv run --frozen python tools/assemble_phase8_release_evidence.py
        if ($LASTEXITCODE -ne 0) {
            throw 'Authenticated Phase 8 release assembly failed.'
        }

        $workerDefaults = @{
            UNIFIED_POSTGRES_DSN = `
                'postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable'
            UNIFIED_CROSSCHAIN_DATABASE_URL = `
                'postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_runtime'
            UNIFIED_CROSSCHAIN_OBSERVER_DATABASE_URL = `
                'postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_observer'
            UNIFIED_CROSSCHAIN_FINALITY_DATABASE_URL = `
                'postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_finality_attester'
            UNIFIED_CROSSCHAIN_RECOVERY_DATABASE_URL = `
                'postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_recovery_verifier'
            UNIFIED_CROSSCHAIN_REORGANIZATION_DATABASE_URL = `
                'postgres://unified_local:local-only-not-a-secret@127.0.0.1:55432/unified_local?sslmode=disable&options=-c%20role%3Dunified_crosschain_reorganization_verifier'
            UNIFIED_KAFKA_BROKERS = '127.0.0.1:19092'
            UNIFIED_OBJECT_ENDPOINT = 'http://127.0.0.1:59000'
            UNIFIED_MOCK_BRIDGE_PROVIDER_A = $ProviderAUrl
            UNIFIED_MOCK_BRIDGE_PROVIDER_B = $ProviderBUrl
        }
        $priorWorkerEnvironment = @{}
        foreach ($entry in $workerDefaults.GetEnumerator()) {
            $priorWorkerEnvironment[$entry.Key] = `
                [Environment]::GetEnvironmentVariable($entry.Key)
            if ([string]::IsNullOrWhiteSpace($priorWorkerEnvironment[$entry.Key])) {
                [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
            }
        }
        try {
            go run ./services/cross-chain-coordinator/cmd/local-worker `
                --mode smoke --timeout 90s
            if ($LASTEXITCODE -ne 0) {
                throw 'Durable Phase 8 local worker failed.'
            }
        } finally {
            foreach ($entry in $priorWorkerEnvironment.GetEnumerator()) {
                [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
            }
        }
        & (Join-Path $workspace 'scripts/check-phase8-release-evidence.ps1') `
            -Stage pre-reset -EvidencePath $releaseEvidencePath
        if ($LASTEXITCODE -ne 0) {
            throw 'Pre-reset Phase 8 release evidence validation failed.'
        }
    } finally {
        Pop-Location
    }

    $flow = Get-Content -LiteralPath $flowPath -Raw | ConvertFrom-Json
    if (
        $flow.completed_message_count -ne 8 -or
        $flow.proof_boundary -ne 'AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT' -or
        $flow.final_state.loan_state -ne 'CLOSED'
    ) {
        throw 'Authenticated flow summary is incomplete or non-terminal.'
    }
    Write-Output (
        "Phase 8 two-Anvil smoke passed: home=31337 satellite=31338 " +
        "boundary=$($flow.proof_boundary) messages=$($flow.completed_message_count) " +
        "loan_state=$($flow.final_state.loan_state)"
    )
} finally {
    if ($timestampsPinned) {
        foreach ($rpc in @($HomeRpc, $SatelliteRpc)) {
            try {
                & $cast rpc --rpc-url $rpc anvil_setBlockTimestampInterval 1 2>$null | Out-Null
            } catch { }
        }
    }
    if ($null -ne $homeProcess -and -not $homeProcess.HasExited) {
        Stop-Process -Id $homeProcess.Id -Force
    }
    if ($null -ne $satelliteProcess -and -not $satelliteProcess.HasExited) {
        Stop-Process -Id $satelliteProcess.Id -Force
    }
    foreach ($pending in @(
        (Join-Path $releaseCache '*.pending'),
        (Join-Path $output '*.pending.json')
    )) {
        Get-ChildItem -Path $pending -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}
