# Contributing

All changes must preserve the authority hierarchy defined by the Unified
Constitution and the specification registry.

1. Start from a work item with a stable `UNI-<WORKSTREAM>-<NUMBER>` identifier.
2. Cite governing specifications, invariants, threats, and acceptance criteria.
3. Use an ADR for material architecture choices and an RFC for cross-domain
   behavior changes.
4. Change canonical Protobuf sources before generated language bindings.
5. Run `pwsh ./scripts/check-foundation.ps1` before opening a pull request.
6. Do not commit secrets, production keys, personal data, generated credentials,
   or real financial records.

Direct pushes to `main` are prohibited. The tracked pre-push hook enforces this
locally; the remote repository must also require pull requests, successful
checks, and release-authority approval.

