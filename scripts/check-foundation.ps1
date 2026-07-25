$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace

buf lint
buf build --output '.cache/unified-schema.binpb'
buf breaking --against 'schemas/baseline/v0.1'

go test ./...
pnpm run check
uv run python -m compileall -q models packages/generated/python tools scripts
uv run pytest -q
uv run pytest -q tests
uv run mypy --strict models/foundation_model/src tools scripts tests
uv run ruff check models tools scripts tests
uv run python tools/check_foundation.py
uv run python tools/check_privileged_surface.py
uv run python tools/check_privacy_surface.py
uv run python tools/check_payment_privacy_surface.py
uv run python tools/check_phase8.py

$solcTarget = Join-Path $workspace '.cache\solc'
if (Test-Path -LiteralPath $solcTarget) {
    Remove-Item -LiteralPath $solcTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $solcTarget | Out-Null
pnpm run solidity:compile
uv run python tools/check_abi.py

if (Get-Command forge -ErrorAction SilentlyContinue) {
    pwsh ./scripts/prepare-foundry.ps1
    Push-Location protocol
    try {
        forge fmt --check src/FoundationProbe.sol src/ProtocolCompilation.sol `
            src/collateral src/crosschain src/identity src/interfaces src/kernel src/loan src/risk `
            src/payment src/token test script
        forge test
        uv run python ../scripts/check-contract-sizes.py
    } finally {
        Pop-Location
    }
} else {
    Write-Warning 'forge not installed locally; solc compilation passed. CI installs pinned Foundry.'
}

if (Test-Path -LiteralPath '.git') {
    pwsh ./scripts/generate.ps1
    git diff --exit-code -- packages/generated protocol/src/generated `
        docs/specifications/registry.yaml security/invariant-catalog.csv
}

Write-Output 'All foundation checks passed.'
