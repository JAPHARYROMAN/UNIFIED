# ADR 0005: Ledger Topology and Reporting

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Accounting and Economic Risk Authority

## Decision

The foundation uses one logical double-entry ledger partitioned by legal entity,
book, and asset. Journals retain their original denomination. USD is the initial
presentation currency only; valuation evidence and rates are stored separately.

Posted journals are immutable. Corrections use linked reversing and replacement
journals. Idempotency keys are unique within source system and legal entity.
Every journal must balance independently by asset.

