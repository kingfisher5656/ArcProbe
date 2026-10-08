# Native iOS implementation report

Updated: 2026-10-08. Scope: native project, app/UI, offline state integration, backup review, sharing, and simulator acceptance. Networking/platform session and App Intent implementations are owned by the networking engineer; domain/storage/rating are owned by the core engineer.

## Implemented

- `ArcaeaOffline.xcodeproj` with a shared `ArcaeaOffline` scheme, native SwiftUI app target, app-unit and UI-test targets, local ArcaeaCore package reference, Swift 6 strict concurrency, iOS/iPadOS 18 deployment, phone/iPad support, display name Arcaea Offline, and an independently drawn purple waveform app icon.
- Deterministic `scripts/generate-project.py` builds the project without xcodegen or external project-generation dependencies. Regenerate after adding Swift source files.
- Adaptive native tabs/sidebar with Best 50, Scores, Recent, Potential, and Accounts & Sync. Light/dark system materials and native chart-cover placeholders are used; no personal reference screenshot or private artwork is bundled.
- Offline chart search/difficulty filtering, known chart chooser and explicit custom-chart entry, optional dates/judgments/clear lamps, add/edit/delete, persistent undo, override reset, and a separate downward chart-best correction/reset.
- Score-only editing retains imported modifier/health and unchanged server timestamp provenance. Gauge bitmasks follow the core's 0...65535 bounds; health is 0...100. Remote -1 sentinels normalize to unknown upstream. Blank fields remain unknown.
- Recent attempt ratings use the supplied attempt's score and play clear. Recent-only filtering uses bulk capture provenance, so a recent fetch remains visible when the same attempt later gets richer canonical details through full import.
- Official potential history remains separate from local ranking estimates. Calendar five-year range, custom whole-day bounds, and nearest-point inspection are available. Display sampling caps chart marks to approximately 1500 points while retaining endpoints and each bucket's extrema; inspection searches the full saved series.
- Scene activation reloads the archive and runtime status after background Shortcut writes.
- Separate main/recent login browsers and role disconnects. Own-account testing and friend-target modes are explicit. Friend mode defaults to the connected main account's stable identity. Full-import progress/cancellation, recent fetch, tracking timestamps, and Shortcut guidance are wired to OnlineRuntime.
- Versioned JSON backup sharing. Selected restore files are validated in an isolated temporary archive before presenting counts and an explicit Replace saved archive confirmation. Live restore uses the core's transactional replacement semantics. No credentials or session cookies are in backups.
- B50 CSV and 1800×3100 JPG exports always use the full top 50, independently of UI filters. JPG has five columns and ten rows, rank/difficulty/score/grade/rating/clear/source/date labels, with unknown values labeled. CSV quotes commas/quotes/newlines, mitigates formula-prefixed labels, and does not invent timestamps or judgments.
- `scripts/package-ipa.sh` regenerates the project, builds Release iphoneos arm64 with signing disabled, assembles a fresh Payload ZIP, and writes a SHA-256. The manager runs the final package step. Output is an unsigned device build intended for SideStore re-signing, not a signed/device-verified installation.

## Verification completed by the iOS engineer

Toolchain: Xcode 27.0 (27A266a). Simulator: iPad Pro 11-inch (M4), iOS 18.6, `835FA26D-9808-45E7-8A59-AC0389B95DDE`.

- Initial offline/export test run deliberately failed five behavior tests against unsupported mutation/export stubs, establishing the expected missing behavior (`build/test-logs/offline-red.log`).
- The integrated app-unit run passed 15/15 tests, including real Keychain role round-trip/role-specific clearing, using normal Simulator ad hoc signing (`build/test-logs/integrated-simulator.log`). The earlier unsigned-host run had one Keychain storage failure; production security policy was not weakened.
- The initial UI run caught two real interaction bugs: validation below the visible editor area and automatic List row button aggregation invoking Edit when Delete was tapped. Validation moved to an immediately visible row, and per-play buttons now use borderless behavior.
- Both repaired UI tests passed on the real bundled chart catalog: invalid input leaves the editor open, and offline add → edit → relaunch → delete → undo works (`build/test-logs/provenance-red-ui-repair.log`). That mixed run's overall failure was solely the deliberately failing new recent-provenance regression, 0 visible recent plays instead of 1, before its fix.
- After wiring `captureSources`, the recent-provenance regression and shared production ShortcutActions runtime test passed 2/2 (`build/test-logs/provenance-green-intents.log`).
- Standalone red/green sampling checks verify the 100,000-point series remains bounded, keeps a positive spike and negative trough, and nearest inspection returns an original observation rather than a sampled neighbor (`build/history-check`). Equivalent app-unit tests are included.
- Synthetic full B50 JPG and CSV were copied from the Simulator and visually inspected. The 5×10 JPG has no clipping. App dashboard/detail screenshots from passing UI tests were exported and inspected.

The complete current suite consists of 17 app-unit tests and 2 UI tests. The manager will perform one final fresh integrated run after the networking engineer's final session-race fix and record its results in release verification. No iOS-engineer Simulator run remains active at handoff.

## Review artifacts

- `artifacts/synthetic-b50.jpg`
- `artifacts/synthetic-b50.csv`
- `artifacts/simulator-best50.png`
- `artifacts/simulator-score-details.png`
- `artifacts/ui-verification/manifest.json`

The dashboard screenshot predates the small nil-rank/count text correction: unknown charts now display Unrated rather than #0, and single-item counts use singular labels. The final manager run can refresh that screenshot.

## Limits

No physical SideStore signing/install, LiveContainer foreground run, Shortcut discovery on the user's device, locked-device Keychain access, signing refresh, or sustained 60–80-second polling has been verified by this engineer. Website transport fixtures, own-account recent testing, and background intent helper tests do not establish unsubscribed burner access or sustained iPadOS scheduling. Official artwork fetching/rendering is not implemented in this build; native placeholders are explicit. Those limits remain visible in the app and release documentation.
