# ArcProbe

iPadOS/iOS app (SwiftUI, iOS 18+) that keeps a local archive of Arcaea scores: Best 50 with JPG export, all scores, potential graph, import/export with the Arcaea consultant Google Sheet, and automatic recording of each play while Arcaea is open. Distributed as an unsigned IPA through SideStore. Owner plays on an M1 iPad Pro 12.9" (iPadOS 18).

## Commands

```sh
swift test --package-path Packages/ArcaeaCore            # core logic, ~1 s, run this first
swift test --package-path Packages/ConsultantProbeCore   # Google Sheets client
python3 scripts/generate-project.py                      # after adding/moving/deleting any Swift file
xcodebuild test -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' -derivedDataPath build/DerivedData
zsh scripts/package-ipa.sh                               # artifacts/ArcProbe-<version>.ipa
```

- `ArcaeaOffline.xcodeproj` is generated. Never edit it; edit `scripts/generate-project.py` (version and build number live there).
- Add `-only-testing:ArcaeaOfflineTests` to skip the slow UI tests (several minutes).
- Do not build simulator tests with `CODE_SIGNING_ALLOWED=NO`: the Keychain then fails with -34018.
- `xcrun simctl` and `xcodebuild test` need to run outside the command sandbox.

## Layout

- `Packages/ArcaeaCore` — everything that is not UI: SQLite archive (`Storage/`), rating math (`Rating/`), Arcaea Online client and parsers (`Online/`), tracking state machine (`Tracking/`), consultant-sheet mapping (`Consultant/`). Pure Swift, tested on macOS.
- `Packages/ConsultantProbeCore` — Google Sheets REST client.
- `ArcaeaOffline/App` — `AppContainer` (the one shared store/model/runtime), root tab view, `ArchiveModel` (observable view of the archive).
- `ArcaeaOffline/Networking` — `OnlineRuntime` (logins, import, tracking; the app-side façade over ArcaeaCore), login web view bridge, cover art.
- `ArcaeaOffline/Intents` — Shortcut actions. Thin: they call `TrackingActions` / `OnlineRuntime`.
- `ArcaeaOffline/Features/*` — one folder per screen area.

The folder, target and bundle ID are still called ArcaeaOffline / `app.arcaeaoffline`. Do not rename the bundle ID: installed data, Keychain logins and the Google client depend on it.

## Tracking (the part that must not break)

Two account roles, isolated from each other: `main` (subscribed; full import) and `burner` (shown as "Tracker account"; reads the main account's newest play through the friends list).

The Shortcut is dumb, the app is smart (`docs/shortcuts.md`):
`Start Arcaea Tracking` → session UUID → loop { `Check Recent Play(session)` → seconds; stop if 0; wait seconds }. `Stop Arcaea Tracking` on close.

`TrackingStore` (one SQLite row, `BEGIN IMMEDIATE`) holds all state. Rules encoded there and in `RecentSyncService`, each with a test:
- Newest session wins; an older loop gets `.stop(.superseded)`. The schedule (`nextPollAt`) is global, not per session, so close/reopen never restarts the wait.
- Fetched data is always saved, whichever loop asked. Only a lease (one request at a time) and the login's revision guard the write.
- After close: two more checks that really reached the server, then `.stop(.finished)`; hard limit 10 minutes.
- Manual "check now" ignores the poll schedule but respects server cooldowns.
- A 403/HTML/odd response to a read is retried with backoff; the login is only marked `requiresAttention` after three in a row, or immediately when a sign-in itself is rejected or the session expired with no saved password. Once marked, nothing is requested until the user signs in again.
- Offline adds no backoff. Other failures: 60 s, 120 s, 240 s, then 300 s.

Shortcut actions run in the app process in the background, with ~30 s per action. Never sleep inside an action; return the wait to the Shortcut.

## SwiftUI rules learned the hard way

- Never attach `.sheet`, `.fileImporter`, `.confirmationDialog` or `.task` to a `Section` (or `Group`/`ForEach`) inside a `Form`/`List`. SwiftUI copies the modifier onto every row; the duplicate sheets dismiss each other, which showed up as "the browser opens and closes on the first tap". Attach them to the `List` itself. `OfflineFlowTests.testSettingsSheetsOpenOnFirstTap` guards this.
- One `.fileImporter` per view; drive it with an enum when a screen imports two kinds of file (`BackupView`).
- Settings is a short list of links; each area is its own screen. Keep explanatory text to one short footer per section.
- Four tabs at most (Best 50, Scores, Recent, Potential). A fifth scrolls out of the iPad's top tab bar in portrait. Settings is pushed from the gear button that `settingsButton()` adds to each tab's root screen; the consultant sheet lives inside Settings.
- On iPad, give sheets that hold a web page `.presentationSizing(.page)`.

## Wiki data (Settings → Charts & cover art)

- "Update constants and levels" reads `Data:ChartConstant.json` (constants) and then `Data:Songlist.json` (level, INS label, and title/artist for charts that have none) from arcaea.miraheze.org. `SongListSnapshot` skips entries it cannot read; a song-list failure never undoes the constants.
- Wiki covers: `WikiSongArticle.jacket(for:)` picks a jacket by (1) a tab naming the difficulty, (2) a single unlabelled jacket, (3) the file name (`Songs_<id>_byd`, or `Songs_<id>` when its tab is not a difficulty: "Moment", "Day", "English"). A page can list several song IDs ("Last" also holds `lasteternity`).
- Charts whose page was read without a match are remembered (`wikiUnmatchedCharts`, per app version) so their pages are not reopened on every run.

## Conventions

- User-facing words: "Main account", "Tracker account", "check" (not poll/fetch), "play", "Consultant sheet".
- Unknown stays unknown: no invented dates, clears or potential values. Official potential history and the local estimate are separate series.
- No analytics, no servers of our own. Requests go only to lowiro, the Arcaea wiki (constants, covers) and Google (the user's chosen workbook).
- Secrets (cookies, passwords, Google tokens) live in the Keychain only and never in backups, logs or diagnostics.
- `refs/backup/pre-claude-rework` is a snapshot of the tree before the 0.3.0 rework (including the old verification reports and plans).
