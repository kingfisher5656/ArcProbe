# Implementation ledger — Arcaea Offline

Plan: ../superpowers/plans/2026-10-07-arcaea-offline.md

## User authorization, 2026-10-07

Build approved. User requests GPT-6.1 Sol at Extra High for most coding, with parent engineer managing architecture, reviewing changes and running final checks. Main account already signed into the browser may be used temporarily for recent-source tests. Keep separate login/session roles for subscribed imports and recent fetching; actual burner testing is deferred until the user obtains that account.

## Execution decisions

- Work in the requested new Arcaea Offline directory; no existing application or repository was present, and no files in ArcPotApk will be changed.
- Implement archive core while the manager verifies website contracts. The user explicitly permits deferring actual burner errors; do not block offline implementation on that future account.
- Direct SideStore is primary. A continuous 70-second Shortcut loop remains subject to physical iPad testing, not a guaranteed background scheduler.

## Work

- Core engineer dispatched: Swift package, SQLite archive, ranking, reconciliation, manual changes, backup, tests.
- Manager: website contract inspection, project/device environment, plan update, integration and review.
