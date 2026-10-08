# ArcaeaCore implementation report

Verified: 2026-10-08, 10:04 KST. Scope: plan Task 2 and the domain/storage portions of Tasks 5 and 7. The app, authenticated transport, tracking service, App Intents, signing and device verification are owned by the other implementation tracks.

## Delivered behavior

- SQLite archive with foreign keys, WAL, full synchronization, serialized access and transactional schema migrations through database version 3. Account IDs scope all archive queries; display names are never identities. Malformed imports and source identity collisions roll back profiles, metadata, observations, history and receipts together.
- Immutable canonical observations and immutable source captures. Repeated polls exclude poll time from identity. Source event IDs take precedence; timestamp/score identities have durable aliases when a later route supplies an event ID. Distinct verified event IDs remain distinct even when scores and timestamps match.
- One coherent source capture supplies a play's score, judgments, gauge and modifier. Optional enrichment chooses a complete captured payload; it does not splice judgment fields from different attempts. Best clear is a separate chart lamp. Contradictory shared optional values reject the batch.
- Manual add, whole-record override, suppression/restoration, reset to imported data, explicit downward chart best correction, and durable chronological undo. A first offline manual add creates its profile only after validation. Corrections and suppression survive repeated and cross-source imports; later distinct plays remain eligible. A chart best correction remembers every baseline observation it replaces.
- Exact 600,000-unit inherited rating arithmetic, B10 double weighting, B50 truncation with zero-filled missing slots, unrated unknown/outdated constants, and deterministic ordering. All snapshots explicitly mark these results as estimates.
- Separate official and local-estimate potential series. Raw timestamp units and decimal precision remain stored. Empty imports do not erase older points; manual changes never rewrite official history. Potential equality uses integer decimal normalization.
- Versioned JSON backup of profiles, charts, canonical observations, captures, ID aliases, overrides, suppression markers, best corrections, both potential series, import receipts and undo state. Restore validates the complete payload and all references before a transactional replacement. Cancellation after deletion starts rolls back. Credentials, cookies and session stores are outside this archive and are never consulted.

## Public interfaces for consumers

`ArchiveStore` is a synchronous, serialized `@unchecked Sendable` class. Call it from a service actor or a background task where large operations could affect responsiveness.

```swift
try ArchiveStore(url: URL, catalog: ChartCatalog? = nil)
try store.profiles() -> [AccountProfile]
try store.apply(batch: ImportBatch) -> ImportReceipt
try store.observations(accountID: AccountID,
                       includeSuppressed: Bool = false) -> [EffectiveObservation]
try store.sourceObservations(accountID: AccountID) -> [ScoreObservation]
try store.sourceCaptures(observationID: ObservationID) -> [ScoreObservation]
try store.captureSources(accountID: AccountID) -> [ObservationID: Set<ObservationSource>]
try store.bestScores(accountID: AccountID) -> [BestScore]
try store.potentialHistory(accountID: AccountID,
                          series: PotentialSeries = .official) -> [PotentialPoint]
try store.chartCatalog() -> ChartCatalog
try store.receipts(accountID: AccountID? = nil) -> [ImportReceipt]
try store.applyManual(change: ManualChange) -> UndoToken
try store.latestUndoToken() -> UndoToken?
try store.undo(UndoToken)
```

`EffectiveObservation.original.id` is the canonical attempt ID. Use `captureSources` to identify recent captures after a full import chooses a richer official-import payload. `sourceObservations` returns the immutable first payload for each canonical attempt; `sourceCaptures` returns the immutable evidence, including later enrichment. Aliases are accepted by manual observation operations and `sourceCaptures`.

`ImportBatch(profile:observations:potentialPoints:charts:importedAt:kind:)` is the sole import commit boundary. All observations and potential points must belong to `profile.id`. Incoming metadata preserves existing constants, level, note count, aliases and descriptions when corresponding fields are omitted.

`ScoreObservation.remote(accountID:chartID:source:values:firstSeenAt:eventID:)` validates and creates stable official identities. For manual records use a unique `ObservationID`, source `.manual`, and identity confidence `.manual`. `ScoreValues` permits missing date, judgments, play clear, best clear, modifier and health. Modifier supports unsigned 16-bit values, health supports 0–100, and parser sentinel `-1` is normalized to nil by the online track.

`SourceTimestamp(value:unit:origin:)` preserves integer seconds/milliseconds and server/manual origin. Its `milliseconds` and `date` properties are optional checked conversions. Negative, overflowing or out-of-range dates remain safe to inspect and are rejected before archive commit/restore. `PotentialValue(rawValue:decimalPlaces:)` stores exact source decimals; `doubleValue` exists only for display/charting.

`ManualChange` cases are add, override, suppress, restore, resetOverride, correctBest and resetBestCorrection. Override/edit commands identify both account and observation; best corrections identify account and chart. Undo follows a global chronological stack and rejects stale tokens rather than overwriting newer edits.

```swift
let catalog = try ChartCatalog.bundled()
let calculator = RatingCalculator(catalog: catalog)
try calculator.rank(bestScores: [BestScore]) -> RankingSnapshot
try calculator.rank(observations: [ScoreObservation]) -> RankingSnapshot
RatingCalculator.display(Int64, rounded: Bool = false) -> String

let backup = ArchiveBackup(store: store)
try backup.export() -> Data
try backup.validateAndRestore(data: Data,
    cancellationCheck: () throws -> Void = /* Task cancellation guard */) -> ImportReceipt
```

Restore replaces the score archive; it does not merge. The app should stage and review a selected backup in a temporary archive before asking for explicit replacement. JSON backup schema is version 1, distinct from SQLite database version 3. The maximum backup is 64 MiB. Import batches and backup collections are bounded; at most 256 distinct payload variants may be retained for one canonical attempt.

## Metadata and provenance

Only ArcPotApk's public chart constants and level/alias indices were copied. No private dump, player score export or artwork was copied. The sibling project was treated as read-only. Full provenance and attribution are bundled in `Sources/ArcaeaCore/Resources/NOTICE.md`.

| Resource | Provenance | Entries | SHA-256 |
| --- | --- | ---: | --- |
| `chart-constants.json` | Arcaea Wiki contributors, snapshot retrieved 2026-09-09, CC BY-SA 4.0 | 1,830 non-null constants | `5b1035fcb1faf6fad25da49b1e6e7222813aa3284e2587dd0c63311af4bff1a5` |
| `chart-levels.json` | ArcPotApk public game7.0.255 level/difficulty index | 1,830 rows | `e1429c5bddb8c9f1d0fcdccdfe2aaf526a307630a85fd95f4841aba9b72a092e` |

The inherited arithmetic is ported from ArcPotApk `Rating.java`, inspected 2026-10-07, with rule version `arcpot-2026-09`. No current official rating validation has been claimed.

## Verification

The final run executed the real shared package, including the online/tracking tests written by the other engineer:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --package-path Packages/ArcaeaCore \
  --scratch-path .build/core \
  --cache-path .build/swift-cache \
  --config-path .build/swift-config \
  --security-path .build/swift-security \
  --disable-sandbox \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
```

Result: **61 XCTest tests, zero failures, exit 0**. This run finished at 2026-10-08 10:04:21 KST. The detailed local log is `.build/core-final-suite.log`. Tools: Apple Swift 6.4, Xcode 27.0, arm64 macOS. Caches, test archives and logs remain in ignored project paths.

The owned portion contains 33 tests across ArchiveTests, ReconciliationTests, RatingTests, ManualChangesTests, IdentityTests, HistoryTests and BackupTests, plus shared test fixtures. Coverage includes malformed-batch rollback, reopening durability, cross-account isolation, repeated-poll deduplication, lower/identical-score attempts, coherent tied judgments, nil fields, cross-source enrichment, alias transitions, downward corrections, reimport after deletion, undo, known note bounds, invalid judgments, modifier bitmasks, timestamp overflow, decimal precision, retained older history, empty imports, top-50 rating limits, metadata omission, version-one migration, full backup round trip, corrupt/unsupported/cross-account backups, interruption rollback and secret exclusion.

Initial substantive rating, archive, identity, manual, backup and final interface tests were observed failing against stubs before implementation. During parallel edits, some shared-suite runs failed compilation because the other engineer's pending types were not yet declared; interim owned-core snapshots provided independent verification without modifying their files. The final suite above ran against the actual package and includes all converged tests.

## Files owned by this implementation

- `Packages/ArcaeaCore/Package.swift` and `Sources/CSQLite/{module.modulemap,shim.h}`.
- `Sources/ArcaeaCore/Domain/{ArchiveError,ManualChange,ScoreModels,SyncModels}.swift`.
- `Sources/ArcaeaCore/Rating/{ChartCatalog,RatingCalculator}.swift`.
- `Sources/ArcaeaCore/Storage/{ArchiveBackup,ArchiveDatabase,ArchiveStore,ArchiveValidation,ManualChanges,Migrations,ObservationIdentity,ScoreReconciler}.swift`.
- `Sources/ArcaeaCore/Resources/{NOTICE.md,chart-constants.json,chart-levels.json}`.
- `Tests/ArcaeaCoreTests/{ArchiveTests,BackupTests,HistoryTests,IdentityTests,ManualChangesTests,RatingTests,ReconciliationTests,TestSupport}.swift`.
- This report. No app/Online/Tracking source or project-wide design/plan documents were edited by this implementation track. Git commits are left to the manager.

## Limits and remaining integration verification

- With no event ID or usable timestamp, repeated equal account/chart/score payloads share an explicitly uncertain identity. Exact attempt counts cannot be reconstructed. Multiple verified events that make an untagged timestamped payload ambiguous are rejected rather than guessed.
- All rating output uses dated metadata and an inherited rule. Accuracy against the current official website remains to be verified.
- Backup covers the full score archive, not the separate credential stores or transient tracking coordination database. Restore does not restore an active polling generation or lease.
- Restore supports validated replacement only. Merge restore is not implemented.
- Core behavior is verified on the Mac. Simulator app behavior, physical-device storage/Keychain access, SideStore re-signing, actual account/burner access, Shortcut timing, large-archive UI responsiveness, exports and IPA installation require the manager's app/device validation.
