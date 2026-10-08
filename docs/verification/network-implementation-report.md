# Networking, sessions, tracking and Shortcuts implementation

Implementation reviewed against the approved design and the official frontend evidence on 2026-10-07/08. This report distinguishes implemented/tested behavior from unverified website/device behavior.

## Source evidence and endpoint adapter

The cached current official frontend identifies `https://webapi.lowiro.com`, `POST /auth/login` with JSON email/password, CSRF cookie `csrf` and header `X-CSRF-TOKEN`, user/me, friend/me, all-score pages, and the five-year potential route. The profile script confirms own-account `recent_score`; friends payloads contain stable user_id and recent_score. ArcPot's read-only reference supplies all-score/history optional fields, chart metadata and the remaining-subscription-milliseconds regression. Fixtures are synthetic, contain no real account records/secrets, and are grounded in those contracts.

An unauthenticated manager probe encountered HTTP403 JSON Cloudflare error 1010. The adapter treats every 403, HTML, and redirect response as interaction-required, never an expired session. No browser credentials/cookies were extracted and no challenge was bypassed. A logged-in browser page is not proof that app URLSession login works. Actual authenticated payloads, backend credential/challenge details, unsubscribed burner permission, source retention depth, and device cookie continuity are still unverified.

`OnlineParser` validates envelopes, strict integral ranges, collection/response limits and stable account/chart identities. Missing judgments stay nil. Missing/null friend recent_score yields no visible recent plays; a malformed array fails. time_played=0, modifier=-1 and health=-1 normalize to unknown. Distinct source times retain millisecond precision. Title, artist, difficulty alias, and validated bg identifier enter chart metadata without replacing dated chart constants. Core supplies stable observation aliases/deduplication; poll time never creates an event identity. A timestamp-free identical payload has payload-only confidence, so exact attempt counts are not claimed.

## Core interfaces

- `SessionStore`: load/save/clear by AccountRole, atomic compareAndSave by revision, and withValidSession holding the operation guard during synchronous archive commit.
- `AccountRole.main` and `.burner` are separate secure records even when temporarily signed into the same account. `RecentConfiguration` binds observer, target and explicit ownAccountTesting/friendAccount mode.
- `ArcaeaWebClient`: role-scoped reads/login, cookie rotation/deletion, CSRF, identity validation, server cooldown persistence, and expected operation revision on every login/collection subrequest. Actual WK user agent and official Origin/Referer continue a legitimate role's browser session. No fallback impersonation or main-role recent fallback exists.
- `MainImportService.sync(expectedAccount:progress:)`: account/subscription check; all five difficulties and bounded pagination; five-year history; final account/subscription check; one archive apply. Requests are sequential with a default one-second pause. Duplicate/changing pages, malformed data, cancellation and failed required steps commit nothing. Main import attempts have a persisted 60-second gate; 429 Retry-After survives restart.
- `RecentSyncService.fetch(generation:now:)`: a 20-second total network budget, durable lease, 60-second minimum, server cooldown, failure backoff, one bootstrap/expired-session login maximum, attention latch and coherent recent merge. Own mode needs one healthy user/me request. Friend mode intentionally needs user/me identity verification plus friend/me target filtering. Neither checks the full-import subscription.
- `TrackingStore`: separate SQLite file with BEGIN IMMEDIATE across processes, lease expiry/recovery, generation start/stop, attempt/success/new-play timestamps and nextEligibleAt. Replacement resets target diagnostics and invalidates old generations/leases while preserving cooldown.

The tracking transaction guards the generation while the archive transaction commits. These are separate SQLite databases: a crash after archive commit but before tracking receipt write can leave an older displayed success time. Repeating the source payload safely deduplicates. This is not claimed to be a single transaction spanning both files.

## Platform and actions

`OnlineRuntime` is the app's MainActor/Observable facade. UI can inject the shared ArchiveStore, refresh profiles/status, obtain role-specific official WebViews, capture login, configure recent credentials or a browser-only session, import/cancel, fetch, start/stop tracking, and disconnect. Disconnect preserves the archive. Revision guards prevent an old response/refresh/configuration from resurrecting secrets, attaching new cookies to a replacement role, latching a newer role, or committing a disconnected import.

`KeychainSessionStore` uses device-only AfterFirstUnlock accessibility and separate service/account keys. A file lock serializes compare/save/clear and commit guards across processes. Locked/unavailable secrets produce a specific status. Credentials/cookies/UA are excluded from archive backups and Shortcut output. The two WebKit stores are distinct nonpersistent stores; only the selected role's cookies are copied through its Keychain bridge. Clear removes that role's browser storage.

Main-target App Intents: Configure Recent Account, Set Tracking Active, Fetch Recent Play, Get Tracking Status. Fetch/status return JSON with typed status/count/times; no secrets or lease token. Fetch does not open the app or perform artwork/full-import/wait-loop work. ShortcutActions is the production boundary exercised by integration tests. Friend configuration selects the connected main role's stable internal identity; a 9-digit friend code is not accepted as that identity. Setup/loop/fallback instructions are in `docs/shortcuts/setup.md`.

Optional cover downloading is deferred. Valid observed identifiers are retained for a future unauthenticated official cache; UI/export use native placeholders and state this limitation.

## Verification evidence

Latest network-owner whole-package run: 63 tests, 0 failures, `.cache/network-suite.log`, 2026-10-08. It includes parser/session/identity/cookie/CSRF policy, all-page+history import rollback, persisted 429 cooldown, role replacement at response and login boundaries, healthy/no-login recent path, one expired refresh maximum, own/friend filtering, duplicate polls, deadline cancellation, stopped generation, lease overlap/stale recovery, and target diagnostic reset, alongside the full archive/rating/backup suite.

Local-cache command (no source dependency downloads):

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/swift-module" \
swift test --package-path Packages/ArcaeaCore \
  --scratch-path .cache/swift-network --disable-sandbox
```

The managed shell sandbox remains in force; `--disable-sandbox` only disables SwiftPM's nested build sandbox. SwiftPM warns that global user caches are unwritable in this environment; source compilation and tests pass using workspace caches.

The iOS engineer's normal ad hoc signed Simulator app suite passed 15/15 including actual Keychain main/recent round-trip and one-role deletion (`build/test-logs/integrated-simulator.log`). The earlier unsigned Simulator host failed Keychain access; normal signing fixed it. Production storage policy was unchanged. Additional production ShortcutActions and rejected-configuration tests were added afterward and require the manager's final fresh app run; do not infer their pass from the earlier 15-test run.

## Unverified delivery gates

Physical SideStore installation, App Intent discovery/execution while Arcaea is in front, locked-after-reboot behavior, session renewal against the live backend, burner subscription permission, signing-refresh persistence, and a sustained 30–60 minute 70-second loop are not established by Simulator/synthetic tests. App Opened is an event trigger; iPadOS may suspend the repeated Shortcut. One-shot/open-close fetching is an explicit fallback and does not satisfy reliable continuous 60–80 second capture. Authenticated live import counts/history/source retention must be compared to the website before claiming end-to-end correctness.
