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
- Quota interruption preserved partial code; user replenished quota and requested continuation. Same three Sol Extra High engineers resumed from their existing files (core, iOS UI/project, networking/tracking). No task is marked complete yet.
- Browser login restored by user. Current public website code confirms login/friends/main-score/own-recent routes. Browser API navigation was blocked; no cookie extraction or bypass attempted. Authenticated app network tests await app login.
- iPadOS 18.6 iPad Simulator booted for local verification. Paired physical iPad confirmed as iPadOS 18.7.3, but Xcode developer disk mounting failed; SideStore install and sustained automation remain separate acceptance checks.

## Manager review findings in progress

- Core: checked timestamp conversion must not overflow on malformed import/backup; metadata merge must preserve existing constants when official fields are absent; cross-source same-play identity must retain corrections and suppression despite optional enrichment/best-lamp changes. Engineer implementing regression tests.
- Networking: JSON access challenges must not trigger re-login; disconnect/reconfigure must invalidate late responses; changing recent target must invalidate tracking generation without evading cooldown; preserve actual login WebView UA/session context. Engineer implementing role revision and tests.
- UI: preserve optional health/modifier when editing other fields; use INS alias consistently; reload after background writes; bound graph rendering while retaining full history; calendar-correct range selection. Engineer implementing regressions.
- Intermediate iOS shell compilation reported successful by engineer. Final integrated build and actual test totals remain pending.

## Resumption and integration review — 2026-10-08

- Same three engineers resumed again after quota refresh. Do not recreate their work.
- Agent's latest complete core run: 46 XCTest tests passed (`.build/core-alias-green.log`), including event-ID/fallback aliases and backup round-trip. Manager's independent final run is still pending final source changes.
- Intermediate platform run: 14 tests, one Keychain failure (`build/test-logs/offline-green.log`). Network/iOS engineers are diagnosing it; do not report a passing app suite yet.
- Manager reviewed actual network/session/backup/tracking/UI code. Additional fixes requested: stale refresh must not replace a newer role configuration; transport initialization must be concurrency-safe; recent rows must show the attempt's rating and include recent capture provenance after dedup; source -1 health/modifier semantics must agree with archive validation.
- Manager visually inspected `artifacts/synthetic-b50.jpg`: all 50 cards fit, text is legible, source/date uncertainty is visible. Synthetic export only, no private account data.
- README and top-level notices drafted. Shortcut recipes and final verification report remain pending. No IPA exists yet.
- Xcode 27 has no launchable Simulator.app at usual locations; CUA cannot attach it. The iPad simulator is booted and test tooling works. Capture final UI evidence through simulator development tooling.

## Delivered local build — 2026-10-08

- All three implementation tracks frozen and reviewed; reports saved beside this ledger.
- Manager independent final verification: 63 core tests, 18 app tests and 2 UI tests, all passing. UI flow verifies add/edit/relaunch/delete/undo and visible validation. Real Simulator Keychain tests pass with normal signing.
- Manager built Release iphoneos arm64, packaged unsigned SideStore IPA, checked ZIP integrity, iOS platform/minimum version, all four App Intent metadata entries, resource attribution, exclusion of test/private archive data and debug selector.
- `artifacts/Arcaea-Offline-0.1.0.ipa`, SHA-256 `55aae19a7243726e7df241db815f0cabafa59860afb5e1e13de1ae2ad9d8f3db`.
- Final screenshots and synthetic B50 export reviewed. Source/runtime verification is complete locally; physical SideStore install, real authenticated account imports/recent fetching and sustained 60–80-second execution remain pending as detailed in `release.md`.
