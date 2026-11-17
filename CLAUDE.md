# ArcProbe

iPadOS/iOS app (SwiftUI, iOS 18+, English and Korean) that keeps a local archive of Arcaea scores: Best 50 with JPG export, all scores, potential graph, import/export with the Arcaea consultant Google Sheet, and automatic recording of each play while Arcaea is open. Distributed as an unsigned IPA through SideStore. Owner plays on an M1 iPad Pro 12.9" (iPadOS 18).

## Commands

```sh
swift test --package-path Packages/ArcaeaCore            # core logic, ~1 s, run this first
swift test --package-path Packages/ConsultantProbeCore   # Google Sheets client
python3 scripts/generate-project.py                      # after adding/moving/deleting any Swift file
xcodebuild test -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' -derivedDataPath build/DerivedData
zsh scripts/sync-strings.sh                              # after adding or changing any user-facing text (see Languages)
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
- Four tabs at most (Best 50, Scores, Recent, Potential). A fifth scrolls out of the iPad's top tab bar in portrait. Settings is one sheet over the tabs (`SettingsSheet` in `RootView.swift`), opened by the gear button that `settingsButton()` adds to each tab's root screen; the consultant sheet lives inside Settings.
- `AppNavigation` (in the environment) opens Settings: `openSettings()` for the list, `openSettings(.mainAccount)` to land on a screen with the list behind it. Each row of Settings is a `SettingsRoute`; add a screen by adding a case and its line in `SettingsSheet`.
- The message bar (with Undo) and the error alert are drawn by whichever layer is in front: `feedback(active:)` is on the tabs and on the Settings sheet. A sheet covers the tabs, so a message raised from inside it would otherwise be hidden.
- An empty screen offers buttons that go to the fix (`EmptyArchiveView`, the tracker card's `showsActions`), not a sentence that says where to go.
- On iPad, give sheets that hold a web page `.presentationSizing(.page)`.

## Look of the score screens

- Difficulty colours (`Difficulty.color`, and the INS blue in `ChartBadge`) are the game's own. The owner wants them kept: do not restyle them, and do not reuse them for anything that is not a difficulty.
- A difficulty is a filled capsule (`ChartBadge`); a clear lamp is a coloured dot with a name (`ClearLamp`), so the two never look alike. The dot takes the hue of the game's badge for that clear (`ClearType.color`). An unknown clear shows nothing.
- Scores, grades and ratings are plain text colour, not the accent. The accent is for things you can tap.
- Best 50 is a one-line summary over a grid of cards: four across on an iPad in portrait, five in landscape (the count is chosen from the screen width in `OverviewView.columnCount`). Card text is sized for the landscape card and shrinks by the same ratio on a narrower card (`cardScale`), so portrait and landscape have the same proportions. Song names stay on one line. It is a plain `Grid`, not a lazy one, so that every card in a row is as tall as the tallest.
- Scores has a filter bar pinned above the list (`safeAreaInset`): sort menu, difficulty toggles, then Pack / Level / Clear menus. A row leaves out an unknown date instead of printing "Date unknown" on every line.
- Score detail: song and best result in the header, then figures and `JudgmentBar`, then one compact row per play with its actions in a menu (`playActions`) and as swipe actions.
- Recent groups plays like a browser history (`RecentGroup`): Today and Yesterday, then one group per day for the rest of the week, then one per month, then "Date unknown". Today and Yesterday start open, the rest closed; tapping a group's header row toggles it (kept only while the app runs). The disclosure chevron is on the leading side so it does not read as a row that opens a screen.
- A play's change against the chart's earlier best ("New best +38,766", "−76,300", "Same as best", "First saved play") comes from `PlayHistory.changes` in ArcaeaCore. It says nothing when the order of plays is not known (a play without a date that was first seen later). A new best is bold, not coloured: green and red already mean a difficulty.
- Potential: preset ranges (30D … All) over a chart that scrolls by dragging and zooms by pinching; touch and hold reads a point. `PotentialViewport` holds what is on screen and fits the value axis to it shortly after movement stops. It is an `@Observable` object rather than view state so that scrolling redraws the header only, not the chart.

## Languages

English (source) and Korean, in one string catalog: `ArcaeaOffline/Resources/Localizable.xcstrings`.

- After adding or changing text, run `zsh scripts/sync-strings.sh`. It builds, adds the new keys to the catalog, drops unused ones and lists every key without Korean. Then write the Korean into the catalog (`localizations.ko.stringUnit`, state `translated`). The script exits with 1 while anything is missing.
- `Text("…")`, `Button("…")`, `Label`, `Section`, `navigationTitle` and the like are picked up by themselves. A plain `String` is not: wrap it as `String(localized: "…")`, or give a helper's parameter the type `LocalizedStringKey`. Use `Text(verbatim:)` for text that is only data (`"#\(rank)"`).
- Counted phrases ("3 plays") are one key; English gets its singular from plural variations in the catalog, Korean has one form. Do not build plurals with `count == 1 ? … : …`.
- The Swift packages have no catalog. They word things with `localized("…")`, which looks the string up in the app's catalog; `scripts/check-strings.py` collects those keys.
- Kept in English everywhere, on purpose: the game's own terms as the game shows them (clear names, PURE/FAR/LOST, difficulty labels, grades), what goes into exported files (CSV columns and values, the B50 image), the notification title `NotificationTracking.title` (the user's automation matches on it), and the sheet diagnostics report.
- Shortcut action titles are translated, so the Shortcuts app shows Korean names on a Korean device. The setup guide uses the same keys, so the two always agree. `README.md` and `docs/shortcuts.md` name both.
- Korean wording used so far: 주 계정 (main account), 추적 계정 (tracker account), 보면 (chart), 보면 상수, 최고 기록 (chart best), 신기록 (new best), 재킷 (cover art), 포텐셜, 플레이 레이팅, 컨설턴트 시트, 스프레드시트 (workbook), 단축어, 자동화, 가져오기 / 보내기 / 내보내기 (import / send to sheet / export), 날짜 없음.
- To look at the app in Korean in the simulator: `xcrun simctl launch <device> app.arcaeaoffline -AppleLanguages "(ko)" -AppleLocale ko_KR`. Tests match on English text, so they force English: the scheme's test action sets the language (unit tests), and UI tests start the app through `englishApp()`. The owner's simulator is set to Korean, so a test that launches `XCUIApplication()` directly will see Korean.

## Wiki data (Settings → Charts & cover art)

- "Update constants and levels" reads `Data:ChartConstant.json` (constants), then `Data:Songlist.json` (level, INS label, pack, and title/artist for charts that have none) and `Data:Packlist.json` (pack names) from arcaea.miraheze.org. `SongListSnapshot` skips entries it cannot read; a song-list failure never undoes the constants.
- Wiki covers: `WikiSongArticle.jacket(for:)` picks a jacket by (1) a tab naming the difficulty, (2) a single unlabelled jacket, (3) the file name (`Songs_<id>_byd`, or `Songs_<id>` when its tab is not a difficulty: "Moment", "Day", "English"). A page can list several song IDs ("Last" also holds `lasteternity`).
- Charts whose page was read without a match are remembered (`wikiUnmatchedCharts`, per app version) so their pages are not reopened on every run.
- Packs: each song's `set` in the song list names its pack; `Data:Packlist.json` gives pack names, sections and append parents. `PackCatalog` (ArcaeaCore) is bundled as `Resources/pack-catalog.json` (rebuild with `python3 scripts/update-bundled-packs.py` before a release), refreshed by the same update button and by a game folder import, and saved by `LibraryResources` as `pack-catalog.json` beside the archive. It is not in the SQLite archive or in backups. A song from an append pack counts as its parent pack; the set `single` is shown as "Memory Archive". The Scores tab filters by pack and offers only packs that hold a saved score.

## Game folder import (Settings → Arcaea game folder)

Reads Arcaea's own data container (the copy the owner runs inside LiveContainer); `GameDataFolder` in ArcaeaCore, screen and file work in `Features/GameData`.

- Files read, nothing else: `Documents/st3` (SQLite: `scores` + `cleartypes`, one best per chart), `Library/Application Support/cb/active/songs/songlist` (same format as the wiki song list) and the jackets beside it (`dl_<id>/1080_base.jpg`, `1080_<difficulty>.jpg` for a chart with its own art), `cb/meta.cb` (version), and the player name from `Library/Preferences/moe.low.arc.plist`. That plist also holds login tokens: never read other keys, never log it.
- `st3` is copied to a temporary folder before it is opened. The game's folder is never written to.
- Not authoritative: a score becomes a `.gameData` play only when it beats the chart's current best. Its identity is account + chart + score, so repeating the import adds nothing. A main-account import does not delete these plays (the play may never have been uploaded).
- The `date` column in `st3` is unreliable (0, 1, or thousands of seconds). It is not read; play dates stay unknown. Chart constants are not in the folder either; they still come from the wiki.
- Only charts known to the app or to the folder's song list are imported, which leaves out custom charts (`arcpx…`).
- Covers are copied byte for byte under the keys `game:<song>` and `game:<song>:<difficulty>`. Lookup order everywhere is `LibraryResources.coverIdentifiers`: game chart, game song, wiki, official.
- The chosen folder is remembered as a bookmark; `GameDataFolder.locate` accepts the container or a folder up to three levels above it. `ARCAEA_TEST_GAME_FOLDER` (debug builds) stands in for the picker in UI tests.

## Releasing

GitHub repo `kingfisher5656/ArcProbe`, default branch `implementation`. Commit, push, merge and publish only when the owner asks for that step.

1. Bump `MARKETING_VERSION` and `BUILD_NUMBER` in `scripts/generate-project.py`, regenerate the project, run all tests.
2. Work on a branch, open a PR into `implementation`, merge when asked.
3. `zsh scripts/package-ipa.sh`, then
   `gh release create vX.Y.Z artifacts/ArcProbe-X.Y.Z.ipa --title "ArcProbe X.Y.Z" --target <full commit SHA> --notes-file <file>`.
   `--target` rejects a short SHA. The IPA is the only asset.
4. Release notes: Korean first, then English (as in the README). Lead with anything the user must redo after updating (for example rebuilding the Shortcut) and include the IPA's SHA-256.

`B50.jpg`, `WhenArcaea*.PNG` and `LiveContainer_Arcaea_Installation_Data_folder/` in the repo root are the owner's personal files (ignored by git). The folder holds login data and game assets: never commit or upload any of it.

## Open items (as of 2026-11-17, version 0.4.0)

- 0.4.0 is released (build 43, GitHub release v0.4.0). Only the game folder import was tried on the physical iPad (2026-11-16 test build); everything else was seen only in the iPad simulator: the redesigned Best 50 / Scores / score detail, Settings as a sheet, empty states with buttons, Recent grouped by day, the draggable and pinchable Potential graph, and Korean.
- Shortcut automation, SideStore install and real logins have not been checked on the physical iPad since 0.3.1. If recording misbehaves, first check that the "Arcaea opens" automation starts the new shortcut.
- Nobody who reads Korean natively has reviewed the translation yet; the owner does.
- Whether the remembered game folder still opens after the iPad restarts was not reported.
- Chart data is refreshed only by the "Update constants and levels" button (and by a game folder import). Nothing refreshes it automatically when a new song appears.
- A full wiki cover download was not run end to end after the jacket-matching change; the rules were checked against saved copies of the Last, Wandering Melody of Love and Solitary Dream pages.
- The App Shortcut voice phrase ("Fetch recent play with ArcProbe") is English only; a Korean phrase needs an `AppShortcuts.xcstrings`.
- Design follow-up proposed on 2026-11-16 and not built: one accent colour that is not the Future purple.

Remove an item here once it is done.

## Conventions

- User-facing words: "Main account", "Tracker account", "check" (not poll/fetch), "play", "Consultant sheet". Their Korean counterparts are listed under Languages.
- Unknown stays unknown: no invented dates, clears or potential values. Official potential history and the local estimate are separate series.
- No analytics, no servers of our own. Requests go only to lowiro, the Arcaea wiki (constants, covers) and Google (the user's chosen workbook). The game folder import is local file reading only.
- Secrets (cookies, passwords, Google tokens) live in the Keychain only and never in backups, logs or diagnostics.
- `refs/backup/pre-claude-rework` is a snapshot of the tree before the 0.3.0 rework (including the old verification reports and plans).
