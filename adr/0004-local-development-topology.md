# ADR 0004: Local Development Topology

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Release Authority

## Decision

The reproducible local environment uses an isolated EVM development chain with
chain id `31337`, PostgreSQL, Redpanda-compatible event streaming, S3-compatible
object storage, and a deterministic HTTP mock provider.

All resources carry `com.unified.environment=local`. Credentials are fixed,
obviously non-production values. Reset scripts may delete only resources with
that label and project name. Production topology and providers require separate
ADRs and are not inferred from this environment.

