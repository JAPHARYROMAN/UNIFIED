$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# This deterministic schema-generation entry point is bound by the Phase 9 control bundle.
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace

buf lint
New-Item -ItemType Directory -Force -Path '.cache' | Out-Null
buf build --output '.cache/unified-schema.binpb'
buf generate

Get-ChildItem -LiteralPath 'packages/generated/typescript/unified/v1' -Filter '*.ts' |
    ForEach-Object {
        $generated = [IO.File]::ReadAllText($_.FullName).TrimEnd() + "`n"
        [IO.File]::WriteAllText($_.FullName, $generated, [Text.UTF8Encoding]::new($false))
    }

$pythonTarget = Join-Path $workspace 'packages\generated\python'
if (-not $pythonTarget.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Generated Python target escaped the workspace.'
}
if (Test-Path -LiteralPath $pythonTarget) {
    Remove-Item -LiteralPath $pythonTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $pythonTarget | Out-Null

$protoRoot = Join-Path $workspace 'schemas\proto'
$protoFiles = Get-ChildItem -LiteralPath (Join-Path $protoRoot 'unified\v1') -Filter '*.proto' |
    Sort-Object Name |
    ForEach-Object { $_.FullName }
uv run python -m grpc_tools.protoc `
    "-I$protoRoot" `
    '--python_out=packages/generated/python' `
    $protoFiles

New-Item -ItemType File -Force -Path `
    'packages/generated/python/unified/__init__.py', `
    'packages/generated/python/unified/v1/__init__.py' | Out-Null

uv run python tools/generate_solidity_types.py
uv run python tools/build_generated_manifest.py
uv run python tools/build_spec_registry.py
uv run python tools/sync_invariants.py

Write-Output 'Generated schema bindings, manifests, registry, and invariant catalog.'
