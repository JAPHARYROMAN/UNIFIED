# ADR 0002: Canonical Schema and Evolution

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Protocol Architecture Authority

## Decision

Protobuf under `schemas/proto` is the canonical source for internal messages and
domain events. Packages use explicit `unified.v1` versioning. Field numbers are
never reused; removal reserves both number and name. Compatible additions are
preferred. Breaking changes require a new package version and migration RFC.

Go, TypeScript, and Python wire bindings are generated with pinned Protobuf
plugins. Solidity receives a deterministic type projection because Solidity is
not a Protobuf transport runtime. OpenAPI, ABI, and JSON Schema are derivatives,
never competing sources.

