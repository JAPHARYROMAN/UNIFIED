param(
    [string]$RpcUrl = 'http://127.0.0.1:18545'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$protocol = (Resolve-Path -LiteralPath (Join-Path $workspace 'protocol')).Path
$foundry = Join-Path $workspace '.cache\foundry-v1.7.1'
$suffix = if ($IsWindows) { '.exe' } else { '' }
$forge = Join-Path $foundry "forge$suffix"
$cast = Join-Path $foundry "cast$suffix"
$anvil = Join-Path $foundry "anvil$suffix"
$pythonVerifier = Join-Path $workspace 'tools\verify_phase9_refinance_deployment.py'

$setupBroadcaster = '0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'
$candidateBroadcaster = '0x70997970c51812dc3a010c7d01b50e0d17dc79c8'
$governanceExecutor = '0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc'
$fixtureAllocator = '0x90f79bf6eb2c4f870365e785982e1f101e93b906'

$configurationRelative = 'deployments/local/phase9-refinance-smoke-configuration.json'
$candidateRelative = 'deployments/local/phase9-refinance-deployment-candidate.json'
$configurationPath = Join-Path $protocol $configurationRelative
$planPath = Join-Path $protocol 'deployments\local\phase9-refinance-deployment-plan.json'
$candidatePath = Join-Path $protocol $candidateRelative
$evidencePath = Join-Path $protocol 'deployments\local\phase9-refinance-deployment-evidence.json'
$setupBroadcastRoot = Join-Path $protocol 'broadcast\PreparePhase9RefinanceLocal.s.sol'
$candidateBroadcastRoot = Join-Path $protocol 'broadcast\DeployPhase9RefinanceLocal.s.sol'
$setupCacheRoot = Join-Path $protocol 'cache\PreparePhase9RefinanceLocal.s.sol'
$candidateCacheRoot = Join-Path $protocol 'cache\DeployPhase9RefinanceLocal.s.sol'
$broadcastPath = Join-Path $candidateBroadcastRoot '31337\run-latest.json'
$smokeCache = Join-Path $workspace '.cache\phase9-refinance-smoke'
$anvilStdout = Join-Path $smokeCache 'anvil.stdout.log'
$anvilStderr = Join-Path $smokeCache 'anvil.stderr.log'

function Assert-ExactTool([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Pinned Foundry tool is missing: $Path"
    }
    $version = (& $Path --version | Out-String)
    if (
        $LASTEXITCODE -ne 0 -or
        $version -notmatch [regex]::Escape("$Name Version: 1.7.1") -or
        $version -notmatch '4072e48705af9d93e3c0f6e29e93b5e9a40caed8'
    ) {
        throw "Unexpected pinned Foundry identity for $Name."
    }
}

function Assert-BoundedGeneratedPath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $protocolBoundary = $protocol.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    $cacheBoundary = $smokeCache.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (
        -not $absolute.StartsWith($protocolBoundary, [StringComparison]::OrdinalIgnoreCase) -and
        $absolute -ne $smokeCache -and
        -not $absolute.StartsWith($cacheBoundary, [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "Generated path escaped the bounded Phase 9 smoke roots: $absolute"
    }
}

function Remove-BoundedGeneratedPath([string]$Path) {
    Assert-BoundedGeneratedPath $Path
    if (Test-Path -LiteralPath $Path) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        Assert-BoundedGeneratedPath $resolved
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

function Invoke-Rpc([string]$Method, [object[]]$Parameters = @()) {
    $arguments = @('rpc', '--rpc-url', $RpcUrl, $Method) + $Parameters
    $raw = (& $cast @arguments | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "JSON-RPC call failed: $Method"
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

function Read-Nonce([string]$BlockTag) {
    return [string](Invoke-Rpc 'eth_getTransactionCount' @($candidateBroadcaster, $BlockTag))
}

function Assert-EmptyCode([string[]]$Addresses) {
    foreach ($address in $Addresses) {
        $code = [string](Invoke-Rpc 'eth_getCode' @($address, 'latest'))
        if ($code -ne '0x') {
            throw "Reset left deployed code at $address."
        }
    }
}

function Test-RpcOccupied() {
    try {
        $null = & $cast chain-id --rpc-url $RpcUrl 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Write-BroadcastDiagnostics() {
    if (-not (Test-Path -LiteralPath $broadcastPath -PathType Leaf)) { return }
    try {
        $broadcast = Get-Content -LiteralPath $broadcastPath -Raw | ConvertFrom-Json
        $transactions = @($broadcast.transactions)
        $receipts = @($broadcast.receipts)
        for ($index = 0; $index -lt $transactions.Count; $index++) {
            $row = $transactions[$index]
            $receipt = if ($index -lt $receipts.Count) { $receipts[$index] } else { $null }
            $rpcTransaction = Invoke-Rpc 'eth_getTransactionByHash' @([string]$row.hash)
            [ordered]@{
                ordinal = $index + 1
                deployment = [string]$row.contractName
                broadcast_hash = [string]$row.hash
                broadcast_nonce = $row.transaction.nonce
                broadcast_address = [string]$row.contractAddress
                receipt_hash = if ($null -ne $receipt) {
                    [string]$receipt.transactionHash
                } else { $null }
                receipt_address = if ($null -ne $receipt) {
                    [string]$receipt.contractAddress
                } else { $null }
                rpc_hash = [string]$rpcTransaction.hash
                rpc_nonce = [string]$rpcTransaction.nonce
                rpc_to = $rpcTransaction.to
            } | ConvertTo-Json -Compress | Write-Output
        }
    } catch {
        Write-Warning "Unable to emit in-memory rejected-broadcast diagnostics: $_"
    }
}

function Resolve-CreateAddress([int]$Nonce) {
    $output = (& $cast compute-address $candidateBroadcaster --nonce $Nonce | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $output -notmatch '0x[0-9a-fA-F]{40}') {
        throw "Pinned CREATE address derivation failed for nonce $Nonce."
    }
    return $Matches[0].ToLowerInvariant()
}

$rpc = [Uri]$RpcUrl
if ($RpcUrl -cne 'http://127.0.0.1:18545') {
    throw 'The reset-bound topology harness is pinned to http://127.0.0.1:18545.'
}
if (
    $rpc.Scheme -cne 'http' -or $rpc.Host -cne '127.0.0.1' -or $rpc.Port -ne 18545 -or
    $rpc.AbsolutePath -ne '/' -or -not [string]::IsNullOrEmpty($rpc.Query) -or
    -not [string]::IsNullOrEmpty($rpc.Fragment) -or -not [string]::IsNullOrEmpty($rpc.UserInfo)
) {
    throw 'RPC URL must be the credential-free canonical http://127.0.0.1:18545 endpoint.'
}
if ((git -C $workspace status --porcelain --untracked-files=all | Out-String).Trim()) {
    throw 'Phase 9 topology evidence requires a clean tracked and untracked source worktree.'
}
if ($LASTEXITCODE -ne 0) { throw 'Git worktree status is unavailable.' }

Assert-ExactTool $forge 'forge'
Assert-ExactTool $cast 'cast'
Assert-ExactTool $anvil 'anvil'
if (-not (Test-Path -LiteralPath $pythonVerifier -PathType Leaf)) {
    throw "Phase 9 refinance verifier is missing: $pythonVerifier"
}
if (Test-RpcOccupied) {
    throw "Refusing to reuse an existing RPC endpoint: $RpcUrl"
}

$refinanceSource = 'src/resolution/RefinanceCoordinator.sol'
$preparationLibrarySpecifications = @(
    "${refinanceSource}:Phase9RefinanceValidationModule:$(Resolve-CreateAddress 6)",
    "${refinanceSource}:Phase9RefinanceRequestModule:$(Resolve-CreateAddress 7)",
    "${refinanceSource}:Phase9RefinanceLifecycleModule:$(Resolve-CreateAddress 8)"
)
$preparationLibraryArguments = @()
foreach ($specification in $preparationLibrarySpecifications) {
    $preparationLibraryArguments += @('--libraries', $specification)
}

foreach ($stalePath in @(
    $configurationPath,
    $planPath,
    $candidatePath,
    $evidencePath,
    $setupBroadcastRoot,
    $candidateBroadcastRoot,
    $setupCacheRoot,
    $candidateCacheRoot,
    $smokeCache
)) {
    Remove-BoundedGeneratedPath $stalePath
}
New-Item -ItemType Directory -Force -Path $smokeCache | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configurationPath) | Out-Null

$anvilProcess = $null
$configuration = $null
$plan = $null
$resetIdentity = $null
$resetSnapshot = $null
$succeeded = $false
$resetProved = $false
try {
    $start = @{
        FilePath = $anvil
        ArgumentList = @(
            '--silent', '--host', '127.0.0.1', '--port', [string]$rpc.Port,
            '--chain-id', '31337'
        )
        PassThru = $true
        RedirectStandardOutput = $anvilStdout
        RedirectStandardError = $anvilStderr
    }
    if ($IsWindows) { $start.WindowStyle = 'Hidden' }
    $anvilProcess = Start-Process @start

    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($anvilProcess.HasExited) {
            throw "Anvil exited before readiness; see $anvilStderr"
        }
        if (Test-RpcOccupied) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw "Anvil did not become ready at $RpcUrl." }
    if ([string](Invoke-Rpc 'eth_chainId') -ne '0x7a69') {
        throw 'Disposable Anvil chain ID is not canonical 0x7a69.'
    }
    if ([string](Invoke-Rpc 'web3_clientVersion') -notmatch 'anvil/v1\.7\.1') {
        throw 'Disposable RPC does not report pinned Anvil v1.7.1.'
    }
    $accounts = @(Invoke-Rpc 'eth_accounts') | ForEach-Object { ([string]$_).ToLowerInvariant() }
    foreach ($requiredAccount in @(
        $setupBroadcaster,
        $candidateBroadcaster,
        $governanceExecutor,
        $fixtureAllocator
    )) {
        if ($accounts -notcontains $requiredAccount) {
            throw "Disposable Anvil is missing required fixture account $requiredAccount."
        }
    }
    $genesis = Invoke-Rpc 'eth_getBlockByNumber' @('latest', 'false')
    if ([string]$genesis.number -ne '0x0' -or [string]$genesis.hash -notmatch '^0x[0-9a-f]{64}$') {
        throw 'Fresh Anvil reset identity is malformed.'
    }
    $resetIdentity = [string]$genesis.hash
    $resetSnapshot = [string](Invoke-Rpc 'evm_snapshot')
    if ($resetSnapshot -notmatch '^0x(?:0|[1-9a-f][0-9a-f]*)$') {
        throw 'Fresh Anvil snapshot identity is malformed.'
    }

    Push-Location -LiteralPath $protocol
    try {
        & $forge script `
            'script/PreparePhase9RefinanceLocal.s.sol:PreparePhase9RefinanceLocal' `
            --sig 'run(address,address,address,address,string)' `
            $setupBroadcaster $candidateBroadcaster $governanceExecutor $fixtureAllocator `
            $configurationRelative `
            --sender $setupBroadcaster --unlocked --broadcast --rpc-url $RpcUrl `
            @preparationLibraryArguments --force --deny never
        if ($LASTEXITCODE -ne 0) { throw 'Synthetic prerequisite deployment failed.' }
    } finally {
        Pop-Location
    }
    $configuration = Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json

    $latestBefore = Read-Nonce 'latest'
    $pendingBefore = Read-Nonce 'pending'
    if ($latestBefore -ne '0x0' -or $pendingBefore -ne '0x0') {
        throw 'Candidate broadcaster is not fresh at nonce zero.'
    }

    Push-Location -LiteralPath $workspace
    try {
        & uv run --frozen python $pythonVerifier `
            --prepare --config $configurationPath --broadcaster $candidateBroadcaster `
            --reset-identity $resetIdentity --plan $planPath --rpc-url $RpcUrl
        if ($LASTEXITCODE -ne 0) { throw 'Phase 9 topology plan preparation failed.' }
    } finally {
        Pop-Location
    }
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (
        [string]$plan.nonce_transcript.latest_before -ne $latestBefore -or
        [string]$plan.nonce_transcript.pending_before -ne $pendingBefore -or
        [string]$plan.nonce_transcript.preparation_method -ne 'anvil_setNonce' -or
        [string]$plan.nonce_transcript.preparation_value -ne '0x1' -or
        $null -ne $plan.nonce_transcript.preparation_result -or
        [string]$plan.nonce_transcript.latest_prepared -ne '0x1' -or
        [string]$plan.nonce_transcript.pending_prepared -ne '0x1' -or
        [string]$plan.pre_broadcast_block.hash -notmatch '^0x[0-9a-f]{64}$' -or
        [string]$plan.broadcaster -ne $candidateBroadcaster -or
        [string]$plan.broadcaster_provenance.provider -ne 'anvil' -or
        [string]$plan.broadcaster_provenance.account_profile -ne 'foundry-default-account-1' -or
        [int]$plan.broadcaster_provenance.account_index -ne 1 -or
        [string]$plan.broadcaster_provenance.address -ne $candidateBroadcaster -or
        [string]$plan.broadcaster_provenance.account_set_sha256 -ne `
            'sha256:19901d67310664f0f09541131dbc6669f2aa9ce4ffdb1cf497d8a7da8d1ba307' -or
        $plan.broadcaster_provenance.unlocked -ne $true -or
        $plan.broadcaster_provenance.private_key_input -ne $false -or
        [string]$plan.reset_command -ne 'pwsh ./scripts/smoke-phase9-refinance-anvil.ps1'
    ) {
        throw 'Prepared plan did not bind the verifier-owned raw nonce transcript.'
    }
    if ((Read-Nonce 'latest') -ne '0x1' -or (Read-Nonce 'pending') -ne '0x1') {
        throw 'Verifier-owned broadcaster nonce preconditioning did not settle at one.'
    }
    $libraryArguments = @()
    $librarySpecifications = @()
    foreach ($library in @($plan.forge_libraries)) {
        $specification = '{0}:{1}:{2}' -f @(
            [string]$library.source,
            [string]$library.library,
            [string]$library.address
        )
        $librarySpecifications += $specification
        $libraryArguments += @('--libraries', $specification)
    }
    $plannedLibraryArguments = @(
        $plan.forge_libraries_arguments | ForEach-Object { [string]$_ }
    )
    if ($librarySpecifications.Count -ne 3 -or $plannedLibraryArguments.Count -ne 3) {
        throw 'Prepared plan must contain exactly three Forge library arguments.'
    }
    for ($index = 0; $index -lt 3; $index++) {
        if (
            $librarySpecifications[$index] -cne $plannedLibraryArguments[$index] -or
            $librarySpecifications[$index] -cne $preparationLibrarySpecifications[$index]
        ) {
            throw 'Prepared plan library entries do not reproduce the prerequisite arguments.'
        }
    }
    $sourceCommit = [string]$plan.source_commit
    $planSha256 = [string]$plan.plan_sha256
    $configurationArgument = '({0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12})' -f @(
        $candidateBroadcaster,
        [string]$configuration.role_manager,
        [string]$configuration.loan_registry,
        [string]$configuration.settlement_token,
        [string]$configuration.quote_policy_registry,
        [string]$configuration.refinance_policy_registry,
        [string]$configuration.amendment_policy_registry,
        [string]$configuration.protection_policy_registry,
        [string]$configuration.recovery_policy_registry,
        [string]$configuration.asset_registry,
        [string]$configuration.emergency_controller,
        [string]$configuration.treasury_fee_recipient,
        [string]$configuration.maximum_quote_validity
    )

    Push-Location -LiteralPath $protocol
    try {
        & $forge script `
            'script/DeployPhase9RefinanceLocal.s.sol:DeployPhase9RefinanceLocal' `
            --sig 'run((address,address,address,address,address,address,address,address,address,address,address,address,uint64),string,bytes32,string,string)' `
            $configurationArgument $planSha256 $resetIdentity $sourceCommit $candidateRelative `
            --sender $candidateBroadcaster --unlocked --broadcast --slow --rpc-url $RpcUrl `
            @libraryArguments --force --deny never
        if ($LASTEXITCODE -ne 0) { throw 'Exact ten-CREATE topology broadcast failed.' }
    } finally {
        Pop-Location
    }

    $latestFinal = Read-Nonce 'latest'
    $pendingFinal = Read-Nonce 'pending'
    if ($latestFinal -ne '0xb' -or $pendingFinal -ne '0xb') {
        throw 'Candidate broadcaster did not stop after ten CREATE transactions at nonce 0xb.'
    }
    Push-Location -LiteralPath $workspace
    try {
        $nativeExitPreference = $PSNativeCommandUseErrorActionPreference
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            & uv run --frozen python $pythonVerifier `
                --verify --plan $planPath --candidate $candidatePath --broadcast $broadcastPath `
                --rpc-url $RpcUrl --output $evidencePath
            $verifierExit = $LASTEXITCODE
        } finally {
            $PSNativeCommandUseErrorActionPreference = $nativeExitPreference
        }
        if ($verifierExit -ne 0) {
            Write-BroadcastDiagnostics
            throw 'Independent topology verification failed.'
        }
    } finally {
        Pop-Location
    }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if (
        $evidence.topology_only -ne $true -or $evidence.topology_verified -ne $true -or
        $evidence.activation_accepted -ne $false -or
        $evidence.role_grant_performed -ne $false -or
        $evidence.contains_real_value -ne $false -or
        [string]$evidence.broadcaster -ne $candidateBroadcaster -or
        [string]$evidence.broadcaster_provenance.provider -ne 'anvil' -or
        [string]$evidence.broadcaster_provenance.account_profile -ne 'foundry-default-account-1' -or
        [int]$evidence.broadcaster_provenance.account_index -ne 1 -or
        [string]$evidence.broadcaster_provenance.address -ne $candidateBroadcaster -or
        [string]$evidence.broadcaster_provenance.account_set_sha256 -ne `
            'sha256:19901d67310664f0f09541131dbc6669f2aa9ce4ffdb1cf497d8a7da8d1ba307' -or
        $evidence.broadcaster_provenance.unlocked -ne $true -or
        $evidence.broadcaster_provenance.private_key_input -ne $false -or
        [string]$evidence.reset_command -ne 'pwsh ./scripts/smoke-phase9-refinance-anvil.ps1'
    ) {
        throw 'Verified evidence escaped the non-activating topology boundary.'
    }
    $succeeded = $true
} finally {
    $cleanupError = $null
    if ($null -ne $anvilProcess -and -not $anvilProcess.HasExited) {
        try {
            if ($null -ne $resetSnapshot) {
                $revertResult = Invoke-Rpc 'evm_revert' @($resetSnapshot)
                if ($revertResult -ne $true) {
                    throw 'evm_revert did not accept the bounded genesis snapshot.'
                }
            } else {
                $resetResult = Invoke-Rpc 'anvil_reset'
                if ($null -ne $resetResult) {
                    throw 'anvil_reset returned a non-null success result.'
                }
            }
            if ((Read-Nonce 'latest') -ne '0x0' -or (Read-Nonce 'pending') -ne '0x0') {
                throw 'Candidate broadcaster nonce survived reset.'
            }
            $candidateAddresses = if ($null -ne $plan) {
                @($plan.addresses.PSObject.Properties.Value | ForEach-Object { [string]$_ })
            } else { @() }
            $prerequisiteAddresses = if ($null -ne $configuration) {
                @(
                    [string]$configuration.role_manager,
                    [string]$configuration.loan_registry,
                    [string]$configuration.settlement_token,
                    [string]$configuration.quote_policy_registry,
                    [string]$configuration.asset_registry,
                    [string]$configuration.emergency_controller
                )
            } else { @() }
            Assert-EmptyCode @($candidateAddresses + $prerequisiteAddresses)
            $resetGenesis = Invoke-Rpc 'eth_getBlockByNumber' @('latest', 'false')
            if (
                [string]$resetGenesis.number -ne '0x0' -or
                [string]$resetGenesis.hash -ne $resetIdentity
            ) {
                throw 'Disposable chain did not return to genesis after reset.'
            }
            $resetProved = $true
        } catch {
            $cleanupError = $_
        }
        Stop-Process -Id $anvilProcess.Id -Force -ErrorAction SilentlyContinue
        if (-not $anvilProcess.WaitForExit(5000) -and $null -eq $cleanupError) {
            $cleanupError = 'Disposable Anvil process did not exit within five seconds.'
        }
    }
    foreach ($ephemeralPath in @(
        $configurationPath,
        $setupBroadcastRoot,
        $setupCacheRoot,
        $candidateCacheRoot,
        $smokeCache
    )) {
        try { Remove-BoundedGeneratedPath $ephemeralPath } catch {
            if ($null -eq $cleanupError) { $cleanupError = $_ }
        }
    }
    if ($null -ne $cleanupError -or ($null -ne $anvilProcess -and -not $resetProved)) {
        $succeeded = $false
    }
    if (-not $succeeded) {
        foreach ($rejectedPath in @($planPath, $candidatePath, $evidencePath, $candidateBroadcastRoot)) {
            try { Remove-BoundedGeneratedPath $rejectedPath } catch {
                if ($null -eq $cleanupError) { $cleanupError = $_ }
            }
        }
    }
    if ($null -ne $cleanupError) { throw $cleanupError }
    if ($null -ne $anvilProcess -and -not $resetProved) {
        throw 'Disposable topology chain was stopped without a proved reset.'
    }
}

Write-Output (
    'Phase 9 refinance ten-CREATE topology passed and reset: ' +
    "chain=31337 sender=$candidateBroadcaster nonces=1..10 final=0xb " +
    'role_grant=false activation=false reset=true'
)
