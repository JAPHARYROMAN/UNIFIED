$ErrorActionPreference = 'Stop'

# This hash-critical dependency preparer is stored with repository-canonical LF endings.

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $workspace 'node_modules\@openzeppelin\contracts'
$targetRoot = Join-Path $workspace 'protocol\lib\openzeppelin-contracts'
$target = Join-Path $targetRoot 'contracts'

if (-not (Test-Path -LiteralPath $source)) {
    throw 'OpenZeppelin Contracts is missing. Run pnpm install first.'
}

if (Test-Path -LiteralPath $targetRoot) {
    $resolvedTarget = (Resolve-Path -LiteralPath $targetRoot).Path
    $expectedParent = (Resolve-Path -LiteralPath (Join-Path $workspace 'protocol\lib')).Path
    if (-not $resolvedTarget.StartsWith($expectedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace unexpected Foundry dependency path: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
Copy-Item -LiteralPath $source -Destination $target -Recurse
Write-Output 'Prepared pinned OpenZeppelin sources for Foundry.'
