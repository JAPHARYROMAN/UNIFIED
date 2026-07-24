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
