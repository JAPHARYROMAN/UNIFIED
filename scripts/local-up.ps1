$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$composeFile = (Resolve-Path -LiteralPath (Join-Path $workspace 'infrastructure\local\compose.yaml')).Path
if (-not $composeFile.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Compose file escaped the workspace.'
}
if ($env:UNIFIED_ENVIRONMENT -and $env:UNIFIED_ENVIRONMENT -ne 'local') {
    throw 'Refusing to start foundation infrastructure outside UNIFIED_ENVIRONMENT=local.'
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker engine is not available. Start Docker Desktop and retry.'
}

docker compose --project-name unified-local --file $composeFile up --detach --wait
docker compose --project-name unified-local --file $composeFile ps

$domainConfig = Get-Content -LiteralPath (
    Join-Path $workspace 'infrastructure\local\cross-chain\domains.json'
) -Raw | ConvertFrom-Json
if (
    $domainConfig.environment -ne 'local' -or
    $domainConfig.contains_real_value -ne $false -or
    $domainConfig.home.chain_id -ne 31337 -or
    $domainConfig.satellite.chain_id -ne 31338
) {
    throw 'Unsafe or unexpected Phase 8 local domain configuration.'
}
$supplyEvidence = (Resolve-Path -LiteralPath (
    Join-Path $workspace $domainConfig.exposure.evidence_path
)).Path
if (-not $supplyEvidence.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Phase 8 supply evidence escaped the workspace.'
}
$supplyEvidenceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $supplyEvidence).Hash
if ($supplyEvidenceHash -ne $domainConfig.exposure.evidence_sha256) {
    throw 'Phase 8 frozen circulating-supply evidence hash mismatch.'
}
