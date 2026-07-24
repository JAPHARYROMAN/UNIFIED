# Payment Orchestrator

This directory contains the synthetic Phase 7A payment-ingress domain package.

It has no HTTP listener, provider SDK, outbound network client, production credential,
loan-allocation hook, collateral hook, refund path, or fund-moving capability. Provider
configuration is injected by tests, callbacks use synthetic canonical payloads and
Ed25519 keys, and accepted accounting transitions cross a narrow interface implemented
by the foundation ledger.

The package is intentionally importable by the ledger adapter so the payment state
authority and journal-posting authority can be tested together without merging them.
See `adr/0015-phase-7a-payment-ingress-and-reconciliation-boundary.md`.
