param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$manifestDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $workspace 'protocol\deployments\local')
)
$workspaceBoundary = $workspace.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar
if (-not $manifestDirectory.StartsWith(
    $workspaceBoundary,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Reset test target escaped the workspace: $manifestDirectory"
}

New-Item -ItemType Directory -Force -Path $manifestDirectory | Out-Null
$sentinel = Join-Path $manifestDirectory 'phase8-release-evidence.json'
Set-Content -LiteralPath $sentinel -Encoding utf8 -NoNewline -Value (
    '{"schema_version":1,"environment":"local","contains_real_value":false,"run_id":"reset-test"}'
)
if (-not (Test-Path -LiteralPath $sentinel)) {
    throw 'Reset test could not create the generated-manifest sentinel.'
}
$validationDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $workspace '.cache\phase8-release')
)
New-Item -ItemType Directory -Force -Path $validationDirectory | Out-Null
Set-Content -LiteralPath (
    Join-Path $validationDirectory 'ephemeral-validation.json'
) -Encoding utf8 -NoNewline -Value '{"stage":"pre-reset"}'

& (Join-Path $PSScriptRoot 'local-reset.ps1') -SkipCompose
if (
    (Test-Path -LiteralPath $manifestDirectory) -or
    (Test-Path -LiteralPath $validationDirectory)
) {
    throw 'Local reset retained generated Phase 8 topology or validation evidence.'
}

Write-Output (
    'Local reset test passed: generated Phase 8 topology and ephemeral ' +
    'validation directories removed.'
)
