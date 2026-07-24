# ADR 0003: Money and Precision

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Accounting and Economic Risk Authority

## Decision

`Money` contains an `AssetId` plus a signed integer quantity in the asset's
smallest declared unit. Floating-point money is prohibited. Asset precision is
registry metadata and is not repeated as an independently mutable amount field.

Arithmetic must use checked integer operations, explicit rounding policy, and
same-asset validation. Conversion creates a separate, evidenced valuation or
settlement record; it never mutates the original denomination.

