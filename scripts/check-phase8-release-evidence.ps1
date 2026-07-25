param(
    [ValidateSet('pre-reset', 'post-reset')]
    [string]$Stage = 'pre-reset',
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace

$arguments = @(
    'run',
    '--frozen',
    'python',
    'tools/check_phase8_release_evidence.py',
    '--stage',
    $Stage
)
if ($Stage -eq 'pre-reset') {
    if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
        $EvidencePath = Join-Path $workspace `
            'protocol\deployments\local\phase8-release-evidence.json'
    } elseif (-not [IO.Path]::IsPathRooted($EvidencePath)) {
        $EvidencePath = Join-Path $workspace $EvidencePath
    }
    $EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
    if (-not $EvidencePath.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Phase 8 release evidence must remain inside the workspace.'
    }
    $arguments += @('--evidence', $EvidencePath)
}
uv @arguments
