.PHONY: generate check local-up local-smoke local-reset

generate:
	pwsh ./scripts/generate.ps1

check:
	pwsh ./scripts/check-foundation.ps1

local-up:
	pwsh ./scripts/local-up.ps1

local-smoke:
	pwsh ./scripts/smoke-local.ps1

local-reset:
	pwsh ./scripts/local-reset.ps1

