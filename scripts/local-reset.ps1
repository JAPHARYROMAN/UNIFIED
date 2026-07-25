param(
    [switch]$SkipCompose
)

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
if (-not $SkipCompose) {
    docker compose --project-name unified-local --file $composeFile down --volumes --remove-orphans
}

$protocolRoot = (Resolve-Path -LiteralPath (
    Join-Path $workspace 'protocol'
)).Path
$expectedManifestDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $protocolRoot 'deployments\local')
)
$workspaceBoundary = $workspace.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar
if (
    -not $expectedManifestDirectory.StartsWith(
        $workspaceBoundary,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -or
    $expectedManifestDirectory -ne [System.IO.Path]::GetFullPath(
        (Join-Path $workspace 'protocol\deployments\local')
    )
) {
    throw "Refusing reset for unexpected manifest target: $expectedManifestDirectory"
}
if (Test-Path -LiteralPath $expectedManifestDirectory) {
    $resolvedManifestDirectory = (
        Resolve-Path -LiteralPath $expectedManifestDirectory
    ).Path
    if (
        $resolvedManifestDirectory -ne $expectedManifestDirectory -or
        -not $resolvedManifestDirectory.StartsWith(
            $workspaceBoundary,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Refusing reset for escaped manifest target: $resolvedManifestDirectory"
    }
    Remove-Item -LiteralPath $resolvedManifestDirectory -Recurse -Force
    Write-Output "Removed generated local manifests: $resolvedManifestDirectory"
}

$validationDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $workspace '.cache\phase8-release')
)
if (-not $validationDirectory.StartsWith(
    $workspaceBoundary,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing reset for escaped validation target: $validationDirectory"
}
if (Test-Path -LiteralPath $validationDirectory) {
    $resolvedValidationDirectory = (
        Resolve-Path -LiteralPath $validationDirectory
    ).Path
    if ($resolvedValidationDirectory -ne $validationDirectory) {
        throw "Refusing reset for unexpected validation target: $resolvedValidationDirectory"
    }
    Remove-Item -LiteralPath $resolvedValidationDirectory -Recurse -Force
    Write-Output "Removed Phase 8 ephemeral validation: $resolvedValidationDirectory"
}
if (
    (Test-Path -LiteralPath $expectedManifestDirectory) -or
    (Test-Path -LiteralPath $validationDirectory)
) {
    throw 'Local reset left Phase 8 generated topology or validation artifacts.'
}
