# Arcaea Offline Implementation Plan

> **For agentic workers:** User approved implementation on 2026-10-07 and selected GPT-6.1 Sol, Extra High reasoning, for coding with parent engineering review. Use superpowers:subagent-driven-development. Steps use checkbox syntax for tracking.

**Goal:** Deliver a native offline Arcaea score archive with full main-account import, manual corrections, and cookie-reusing recent-play Shortcuts for a separate burner account.

**Architecture:** SwiftUI app with a shared Swift core, transactional SQLite storage, isolated authenticated clients and thin App Intents in the main target. Direct SideStore installation is primary; prove background execution and source access before building the complete app.

**Tech Stack:** Swift, SwiftUI, Swift Charts, Foundation/URLSession, WebKit, Security/Keychain, SQLite3, XCTest, Xcode; use system frameworks initially.

**Spec:** `../specs/2026-10-07-arcaea-offline-design.md` (read together with this plan).

## Implementation status — 2026-10-08

The user approved implementation and delegated coding to Sol Extra High engineers. The native app and shared core are implemented, integrated and independently verified with 63 core, 18 app and 2 UI tests. A Release arm64 IPA is packaged for SideStore re-signing. See `../../verification/release.md` for exact evidence and checksum.

The original checklists below retain the complete acceptance scope: mixed implementation/device-test items are not marked fully complete merely because their code exists. Physical installation, live authenticated import/recent access and sustained polling remain pending. Optional official artwork download/cache was deferred; the delivered UI and exports use disclosed placeholders. No feasibility-probe IPA was delivered separately; the integrated test IPA is the concrete device-validation artifact.

## Global constraints

- Product/display name: **Arcaea Offline**.
- Deployment target: iOS/iPadOS 18.0; primary acceptance device: iPadOS 18.7.3.
- All new files and outputs under `/Users/familymac/Documents/Codex projects/Arcaea Offline`; ArcPotApk remains read-only.
- No root integration, game-file access, game modification, or score uploads.
- Main-account import is in-app. Recurring Shortcuts use an isolated recent-fetch login role; user authorizes the main account in this role for temporary own-account testing before obtaining a burner.
- Target 70-second polling; minimum 60 seconds between attempts; never override server cooldowns. Sustained timing is conditional on physical-device evidence.
- Plan reviewed and implementation authorized. Physical iPad/SideStore and actual burner-account verification must remain labeled pending until performed.

## Review focus

1. iPadOS suspension or force-quit: preserve data, expose stale state, do not claim complete capture (Tasks 1, 6, 8).
2. Account identity or subscription changes midway through import: no partial commit or cross-account data (Tasks 3, 4).
3. A corrected/deleted record returns in a later poll/import: correction remains effective, a genuinely new play still imports (Tasks 2, 5).
4. Cookie expiry plus concurrent polls: exactly one refresh attempt and no repeated login on challenge/429 (Tasks 3, 6).
5. Identical scores on distinct plays, missing timestamps, or missing judgments: preserve coherent records and uncertainty without fabricated fields (Tasks 1, 2, 6).

## File and module map

Create `ArcaeaOffline.xcodeproj`, `ArcaeaOffline/App/`, `ArcaeaOffline/Features/`, `ArcaeaOffline/Intents/`, `ArcaeaOffline/Resources/`, `Packages/ArcaeaCore/`, `ArcaeaOfflineTests/`, `ArcaeaOfflineUITests/`, `docs/verification/`, `docs/shortcuts/` and `artifacts/` only when implementation begins.

`Packages/ArcaeaCore/Sources/ArcaeaCore/` owns Domain, Storage, Rating, Online, and Tracking folders. Its tests use sanitized synthetic or redacted fixtures. The app owns SwiftUI/WebKit/platform credential wiring and intent declarations. Never include real credentials, private score dumps, or browser cookies in test fixtures.

## Task 1: Prove the installation, background action, and website contracts

**Create:** `ArcaeaOffline/App/ArcaeaOfflineApp.swift`, `ArcaeaOffline/Intents/ProbeFetchIntent.swift`, `ArcaeaOfflineTests/ProbeTests.swift`, `docs/verification/feasibility.md`, project configuration.

**Interfaces:** Establish a prototype `ProbeResult` with timestamps, network status and a persisted counter. Before Task 3, document the observed login, session-expiry, friends-list and recent-detail contracts, including fields and required account subscription.

- [ ] Create a minimal iOS 18 app with one non-opening intent, local counter, and a bounded benign network request; no full feature implementation.
- [ ] Build and test the probe in Simulator; verify persistence across separate invocations.
- [ ] Package a clearly labeled feasibility IPA and validate installation and intent discovery through the user's direct SideStore setup. Real-device testing requires access to the iPad or the user's recorded results; do not infer it from Simulator.
- [ ] Verify one-shot execution with Arcaea in front, then test the requested 70-second loop for 30–60 minutes, stopping on close and avoiding duplicate loops after reopen. Record missed intervals and interruption behavior.
- [ ] Verify the website's current authenticated main-account routes and the burner login/friends contract through ordinary account access. Record stable identity, exact score fields, timestamp units, pagination, retention and whether the burner needs a subscription. Keep secrets out of the report.
- [ ] Test whether a persisted session can be reused by URLSession without a live WebView; verify one expired-session refresh or mark interaction required. If unattended login or required recent fields are unavailable, document the unmet requirement before expanding implementation.
- [ ] Record pass/fail/untested for each capability. Remove the prototype action from production once replaced. Commit the probe and report if a Git repository has been initialized.

**Gate:** A failing continuous-loop test does not block developing the offline archive, but does block claiming the requested continuous capture works. Resolve that product tradeoff with the user before final release.

## Task 2: Build the archive, ranking model, and reconciliation rules

**Create in core:** `Domain/ScoreModels.swift`, `Domain/SyncModels.swift`, `Storage/ArchiveStore.swift`, `Storage/Migrations.swift`, `Storage/ScoreReconciler.swift`, `Rating/RatingCalculator.swift`, `Rating/ChartCatalog.swift`.
**Tests:** `Packages/ArcaeaCore/Tests/ArcaeaCoreTests/ArchiveTests.swift`, `ReconciliationTests.swift`, `RatingTests.swift`.

**Interfaces:** Define `AccountID`, `ChartID`, `ObservationID`, `ScoreObservation`, `PotentialPoint`, `ImportBatch`, `ManualChange`, `ImportReceipt` and `FetchResult`. `ArchiveStore.apply(batch: ImportBatch) throws -> ImportReceipt`; `applyManual(change: ManualChange) throws`; `RatingCalculator.rank(observations: [ScoreObservation]) -> RankingSnapshot`. `FetchResult` contains status, addedCount, lastPlayAt, lastSuccessAt and nextEligibleAt.

- [ ] Add failing tests for rollback on malformed batches, cross-account isolation, lower-score recent plays, repeated fetch deduplication, distinct plays sharing a score, tied-score judgment coherence, manual overrides and deletion/reimport.
- [ ] Add boundary fixtures ported from ArcPot's rating tests: 9,500,000, 9,800,000 and 10,000,000; clear-bonus cases; fewer than 50 charts; unknown/outdated constants; difficulty aliases. Treat the inherited calculation as an estimate until validated against current website results.
- [ ] Implement SQLite migrations and transactions, immutable observations and derived best-score views. Use exact integer/rational rating arithmetic matching the verified rule version.
- [ ] Test history merge with empty responses, timestamps in different units, older retained points and separate local estimates. Test missing optional fields stay unknown.
- [ ] Run `swift test --package-path Packages/ArcaeaCore`; require all core tests passing. Save the tested metadata version/provenance and commit this unit.

## Task 3: Implement isolated sessions and the verified website adapter

**Create in core:** `Online/ArcaeaWebClient.swift`, `Online/OnlineParser.swift`, `Online/RequestPolicy.swift`, `Online/SessionTypes.swift`.
**Create in app:** `App/KeychainSessionStore.swift`, `Features/Accounts/OfficialLoginView.swift`.
**Tests:** `OnlineParserTests.swift`, `SessionTests.swift`, `ArcaeaOfflineTests/KeychainSessionTests.swift`.

**Interfaces:** `AccountRole.main` and `.burner`; `SessionStore.load(role:)`, `save(session:role:)`, `clear(role:)`; `ArcaeaWebClient.readAccount(role:)`, `collectAllScores()`, `collectPotentialHistory()`, `fetchRecent(target:)`, `refreshBurnerSession()`. Return typed values defined in Task 2. Endpoint paths and login encoding come from Task 1's verified contract.

- [ ] Add failing parser/session tests for expired authentication, rotated cookies, 403/HTML challenge, 429 with both Retry-After formats, offline errors, oversized payload, wrong account, missing optional fields and unsupported schemas.
- [ ] Implement strict known-origin requests and cookie isolation, including domain/path/secure/expiry matching. Do not forward credentials on cross-origin redirects or attach cookies to artwork downloads.
- [ ] Implement official in-app main login and burner credential configuration. Persist session secrets in Keychain with after-first-unlock device-only access, bounded refresh and credential invalidation state.
- [ ] Add the ArcPot regression for remaining subscription milliseconds. Verify account identity independently of subscription so burner access is not incorrectly blocked by main-account rules.
- [ ] Run parser tests with injected transport, then platform Keychain tests in Simulator. Verify no secrets appear in diagnostics or backup payloads. Commit.

## Task 4: Deliver full in-app import and potential history

**Create in core:** `Online/MainImportService.swift`, `Online/ArtworkCache.swift`.
**Create in app:** `Features/Accounts/SyncView.swift`, `Features/History/PotentialHistoryView.swift`.
**Tests:** `MainImportTests.swift`, `ArcaeaOfflineUITests/ImportHistoryTests.swift`.

**Interfaces:** `MainImportService.sync(expectedAccount: AccountID) async throws -> ImportReceipt`; progress callback publishes completed pages and current stage. Consumes Task 3 client and Task 2 archive.

- [ ] Write failing tests for all difficulty pages, duplicate/changing pages, cancellation, empty history, subscription ending or account switching at final verification, and a failed graph request after successful score pages.
- [ ] Implement sequential paced collection and a single final transaction. Show count/date coverage only for verified collected data; cancellation preserves the old archive.
- [ ] Implement the five-year chart with date range controls, source labels, empty states and latest official value kept distinct from saved-score estimates.
- [ ] Fill artwork cache after commit with unauthenticated bounded image requests; test missing/bad images do not invalidate score imports.
- [ ] Run core tests plus import/history UI tests. Compare a real import's counts and sample points against the website, keeping private data local. Commit.

## Task 5: Deliver manual editing and the offline dashboard

**Create in app:** `Features/Overview/Best50View.swift`, `Features/Scores/ScoreListView.swift`, `ScoreDetailView.swift`, `ScoreEditorView.swift`, `Features/Recent/RecentPlaysView.swift`.
**Tests:** `ManualChangesTests.swift`, `ArcaeaOfflineUITests/OfflineEditingTests.swift`.

**Interfaces:** UI uses Task 2 archive queries and `applyManual(change:)`; source records remain immutable. Define changes for add, override, suppress, restore and resetOverride.

- [ ] Add tests for add/edit/delete/undo offline; downward best-score correction; re-import after correction; new distinct plays after a deletion; unknown date/judgments; invalid scores and inconsistent provided judgment counts.
- [ ] Implement score selection, details, edits and provenance badges. Score range validation follows the verified chart/note bounds when available; unknown catalog entries must remain editable and visibly unrated.
- [ ] Implement B50/all-score views, recent attempts and filters using the archive. Use the supplied image references and ArcPot interaction patterns without copying private assets or root features.
- [ ] Test first launch without subscription, airplane-mode editing, persistence after relaunch and recomputed local rankings. Confirm edits never alter the official graph.
- [ ] Run core and targeted UI tests; commit.

## Task 6: Deliver burner fetching and background Shortcuts

**Create in core:** `Tracking/RecentSyncService.swift`, `Tracking/TrackingStore.swift`.
**Create in app:** `Intents/ConfigureBurnerIntent.swift`, `SetTrackingActiveIntent.swift`, `FetchRecentPlayIntent.swift`, `GetTrackingStatusIntent.swift`, `ArcaeaOfflineShortcuts.swift`.
**Create:** `docs/shortcuts/setup.md`.
**Tests:** `RecentSyncTests.swift`, `TrackingTests.swift`, `ArcaeaOfflineTests/IntentTests.swift`.

**Interfaces:** `RecentSyncService.fetch(target: AccountID, generation: UUID?) async -> FetchResult`; `TrackingStore.start() throws -> UUID`; `stop() throws`; `status() throws -> TrackingStatus`. Persist a transactional lease, attempt/success timestamps, tracking generation and nextEligibleAt in SQLite; an actor alone is insufficient if executions occur in separate processes.

- [ ] Add failing tests for overlapping calls, stale lease recovery, a stopped/old generation, a 60-second minimum interval, network backoff, persisted 429 cooldown, and cancellation before commit.
- [ ] Add authentication tests: healthy polls perform no login; expiration refreshes once; the retry never refreshes again; bad credentials/challenges latch attention-required state; locked Keychain returns a specific status.
- [ ] Implement short one-shot fetches, identity validation, durable cookie reuse and coherent merges. Use a 20-second initial total deadline including refresh; do not wait out long cooldowns inside an intent.
- [ ] Expose Shortcuts actions in the main target with non-opening fetch behavior and structured results. Configuration accepts user-entered credentials once and recurring actions reference the saved account.
- [ ] Document Configure, Fetch Once, Arcaea Opened and Arcaea Closed recipes; generation checks and a bounded 70-second loop; show “next eligible” handling and silence unchanged results. Explain credential removal from setup actions and experimental timing honestly.
- [ ] Repeat Task 1's device test with the actual service, including stale/expired cookies and restart. Record invocation timings, identity, deduplication counts and any missed events without recording secrets. Commit.

## Task 7: Deliver backup, export, and account recovery

**Create in core:** `Storage/ArchiveBackup.swift`.
**Create in app:** `Features/Export/ScoreExportService.swift`, `Features/Settings/BackupView.swift`, `Features/Settings/DiagnosticsView.swift`.
**Tests:** `BackupTests.swift`, `ArcaeaOfflineTests/ExportTests.swift`.

**Interfaces:** `ArchiveBackup.export() throws -> Data`; `validateAndRestore(data: Data) throws -> ImportReceipt`; exports read `RankingSnapshot` and never credential stores.

- [ ] Add tests for full archive round-trip including edits/deletion markers, unsupported schema, corrupt data, cross-account collisions, interrupted restore and secret exclusion.
- [ ] Implement versioned JSON backup and transactional validated restore, B50 JPG and CSV with source/date labels. Export full B50 independently of UI filters, with placeholders for absent artwork.
- [ ] Implement explicit disconnect/replace-account flows that clear the chosen role's secrets while preserving archives. Show last attempt/success/new play and actionable statuses.
- [ ] Run tests and visually inspect exports on iPad layouts. Verify no saved credentials/cookies are included; commit.

## Task 8: Validate and package the release

**Create:** `README.md`, `NOTICE.md`, `docs/verification/release.md`, `artifacts/Arcaea-Offline-<version>.ipa` after approval and implementation.

- [ ] Run the core suite and app/UI tests. Select an installed Simulator using `xcodebuild -showdestinations -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline`, then use `xcodebuild test` with that concrete destination; report exact counts/failures.
- [ ] Test the signed app on iPadOS 18.7.3 through SideStore: login, import, graph, offline edits, undo, backup/restore, JPG/CSV sharing, Shortcut discovery, healthy/expired session, suspension and loop interruption.
- [ ] Test updating/re-signing with the same app identity preserves archive and credential access, or document recovery using backup and reconfiguration. Optional LiveContainer smoke test covers foreground features only unless more is proven.
- [ ] Produce an iPhoneOS arm64 Release archive and IPA using the verified SideStore-compatible signing/re-signing workflow; distinguish unsigned/re-signable output from a device-verified signed installation. Do not claim Simulator output is an installable device IPA.
- [ ] Record build tools, bundle identity, supported OS, SideStore version, tested device, checksum, privacy/source notices and every failed/untested acceptance item. No secrets in artifacts.
- [ ] Deliver the IPA and instructions only with an accurate capability statement. If sustained polling failed, explicitly state the unmet continuous-capture requirement and the user-approved fallback.

## Acceptance checklist

- [ ] Main-account import covers all exposed score pages and returned five-year history, entirely inside the app.
- [ ] Manual add/edit/delete and offline browsing work with no subscription; corrections survive imports.
- [ ] Background Fetch Recent Play uses only the burner account, reuses cookies and refreshes only when needed.
- [ ] Distinct observed plays are retained, repeated polls deduplicate, unknown data is labeled, and failures preserve the archive.
- [ ] Actual 60–80-second behavior is measured on the user's iPad and honestly labeled; any deviation is an explicit accepted limitation.
- [ ] UI and package name are Arcaea Offline; ArcPotApk has not been modified.

## Execution method

Following approval, three Sol Extra High engineers implemented bounded core, networking/tracking, and native iOS tasks in this chat. The lead engineer reviewed their source, delegated corrections, ran the final independent suites, reviewed visual outputs and packaged the device IPA. Physical-device feasibility remains an explicit acceptance boundary rather than an inferred Simulator result.
