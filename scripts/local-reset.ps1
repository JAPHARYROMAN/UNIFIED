$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$composeFile = (Resolve-Path -LiteralPath (Join-Path $workspace 'infrastructure\local\compose.yaml')).Path
$expected = Join-Path $workspace 'infrastructure\local\compose.yaml'
if ($composeFile -ne $expected) {
    throw "Refusing reset for unexpected compose target: $composeFile"
}
if ($env:UNIFIED_ENVIRONMENT -and $env:UNIFIED_ENVIRONMENT -ne 'local') {
    throw 'Refusing reset outside UNIFIED_ENVIRONMENT=local.'
}

$resources = docker ps --all --filter 'label=com.unified.environment=local' --format '{{.Names}}'
if ($resources) {
    Write-Output 'Removing only unified-local containers, networks, and labeled volumes:'
    $resources | ForEach-Object { Write-Output "  $_" }
}
docker compose --project-name unified-local --file $composeFile down --volumes --remove-orphans
