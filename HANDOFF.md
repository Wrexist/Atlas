# Atlas — handoff

> The previous contents of this file were a point-in-time snapshot from
> an old branch (`claude/add-review-prompt-onboarding-H4SD6`) and had
> gone badly stale — wrong product framing, references to tabs that no
> longer exist (Track, Lifestyle), and a claim that the SwiftData
> migration was deferred when it has long since shipped. It was
> replaced to stop misleading contributors.

## Current in-flight state

The authoritative in-flight work and remediation plan now lives in
[`docs/ATLAS_AUDIT_AND_POLISH_PLAN.md`](docs/ATLAS_AUDIT_AND_POLISH_PLAN.md)
— a phased, checkbox-tracked plan covering data-integrity fixes,
security hardening, error handling, the Liquid Glass design pass, and
code cleanup.

A second-wave hardening audit lives in
[`docs/ATLAS_DEEP_AUDIT_II.md`](docs/ATLAS_DEEP_AUDIT_II.md) — six
parallel deep-audits (App Store / medical-safety compliance,
accessibility, performance, Swift 6 concurrency, StoreKit, HealthKit)
with ten Critical ship-blockers. The two existential ones for a
peptide app: the medical disclaimer is never enforced, and the
reconstitution calculator computes an injection dose volume — both
App Store rejection risks. Read Section A before submission.

## Project basics

- Product: **Atlas** (iOS health & fitness). Repo / Xcode targets are
  named `Peptide` for legacy reasons — see the "Naming" section of
  [`README.md`](README.md).
- iOS 18+, Swift 6.0, SwiftUI, SwiftData (CloudKit-backed). Companion
  Watch app, two widget targets, Live Activities.
- Persistence runs through `SwiftDataRepository` (the JSON
  `PersistenceService` is retained only for custom peptides and
  widget snapshots).
- The Anthropic key lives in the Vercel proxy under `server/`; the iOS
  binary never ships one.

## Before merging branch work

1. `xcodegen generate`, then a clean build for an iOS 18+ simulator.
2. Run the `PeptideTests` suite.
3. Verify Liquid Glass surfaces on an iOS 26 simulator/device — the
   design work cannot be validated on older OSes.
