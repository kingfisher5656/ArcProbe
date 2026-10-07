# Arcaea Offline — proposed design

Date: 2026-10-07. Status: planning deliverable for review; no application or IPA built.

## Intended outcome and confirmed constraints

Build an iPad-first, offline score companion named **Arcaea Offline**. The user runs iPadOS 18.7.3 and approximately the September 18 LiveContainer + SideStore nightly. The user explicitly accepts direct installation through SideStore; this is the primary installation route for Shortcuts integration. LiveContainer is a secondary foreground compatibility target.

The main account has Arcaea Online and supplies the full score collection and up to five years of potential history through an in-app import. A separate burner account, already friends with the main account, supplies recent plays through a background-capable Shortcut action. The desired polling interval is 60–80 seconds while Arcaea is open. Manual add, edit, and delete must work without a subscription or network.

Only create or modify files under `/Users/familymac/Documents/Codex projects/Arcaea Offline`. Treat `/Users/familymac/Documents/Codex projects/ArcPotApk` as a read-only reference. Preserve the existing B50.jpg and ScoreData.png as references. No root integration, game-file access, game modification, or score uploads.

## Recommended approach and alternatives

1. **Recommended: native SwiftUI app installed directly through SideStore.** Swift domain logic, SQLite archive, URLSession transport, WebKit login, Swift Charts history, and App Intents in the main app target. This provides one durable archive and one networking implementation for both the UI and Shortcuts, without requiring a separate extension or App Group entitlement initially.
2. **LiveContainer guest with a Shortcut-owned downloader.** Potential fallback, but would require independently verifying cookie persistence, login-response handling, and a Files-based import inbox. Launching a guest through a URL does not establish that its background action is callable. Do not substitute this for the requested seamless workflow without reviewing the tradeoff.
3. **External always-on polling service.** Could move timing outside iPadOS but adds a server, credential custody, and ongoing operation. Outside the requested first version; revisit only if reliable unattended timing becomes essential.

## Feasibility boundaries

- A single short background App Intent and a continuously repeating Shortcut are separate capabilities. Apple's background execution guidance does not guarantee periodic execution. An App Opened automation is an event trigger, not a repeating scheduler. A Repeat/Wait loop is an experiment to validate on this iPad, not an assumed reliable service.
- LiveContainer's FAQ says guest extensions generally do not work. Its documented Launch App shortcut launches guest apps; it does not document exposing every guest app's own App Intents. Direct installation is therefore the primary route, with physical-device verification still required.
- The website's current friends page visibly presents recent activity. The authenticated response schema, login/refresh flow, exact timestamps, retention depth, and burner subscription requirements have **not** been verified in this planning session. Do not invent those endpoints or assume an unsubscribed burner works.
- “All scores” means every score record made available by the official account score listing, across all difficulties and pages. It does not mean a complete lifetime log of every attempt. Recent polling collects only plays still visible when polled; intervening plays can be missed if the source only retains one recent play.
- Five years means the returned observations for the website's five-year query, not five years of reconstructed daily values. Offline or unpublished game plays cannot be obtained from the website.

## Architecture and UI

Deployment target: iOS/iPadOS 18.0; primary acceptance device: iPadOS 18.7.3. Use iOS 18-compatible APIs even though this Mac currently has Xcode 27.0. Native light/dark layouts with iPad navigation and adaptive iPhone support; no iOS 26-only UI requirement.

Screens:

- **Overview / Best 50:** saved-score potential, separately labeled latest official potential, ranked cards, refresh state, and JPG/CSV export.
- **Scores:** all charts, search and difficulty filters, details with score, judgments, clear status, chart constant, source and date; add/edit/delete with undo.
- **Recent plays:** observed attempts including plays below a personal best; last attempted fetch, last successful fetch, last new play and interrupted tracking status.
- **Potential:** official history up to five years, date presets, selectable range, point inspection and optional separately styled local estimates.
- **Accounts & Sync:** main-account browser login and full import, burner setup/test, main-account target selection, Shortcut instructions, backups and diagnostics.

Keep the UI, calculations, persistence, authenticated transport, source parsers, and App Intents separate. Do not reuse the Android shell or copy its whole assets/dump folder. Port selected behavior from Rating.java, OnlineProtocol.java, OnlineSync.java, ScoreProjection.java, ScoreDates.java and HistorySeries.java. Copy only needed chart metadata snapshots with provenance and attribution from NOTICE.md. Those snapshots are dated reference data, not assumed current constants. Validate the inherited rating rules against current official data before labeling estimates accurate.

## Archive and reconciliation

SQLite transactions and migrations store profiles, chart metadata, immutable source observations, personal-best projections, manual overrides, deletion markers, potential points, sync receipts and tracking state. An observation records source, owner account, chart identity, original play time when supplied, first-seen time, score, optional judgments, play clear and best clear. Unknown values remain null.

- Keep main and burner identities distinct. The archive belongs to the main account even when the authenticated observer is the burner. Select by a stable account identifier, not display name. Never import other friends' records.
- Use a source event ID when available; otherwise a stable key combining target account, chart, exact play timestamp and payload identity. Never include poll time in a duplicate key. If the source supplies no adequate identity, preserve uncertainty and do not claim exact attempt counts.
- Keep every distinct observed attempt. Lower recent scores do not replace a higher best. Separate best clear lamp from the high-score attempt, and keep judgment counts from one coherent play.
- Manual editing creates an override over the affected record; deletion creates a restorable suppression marker. Re-importing that same remote record must not restore it or remove a correction. Distinct later plays remain eligible. Chart details also offer an explicit best-score correction so the user can lower an incorrectly imported personal best without accidentally exposing the same bad source record again. Show an override badge and a Reset to imported data action.
- Score edits recompute local rankings and estimates only. They never rewrite the official potential series or send data to lowiro. Permit an unknown timestamp and missing judgments; distinguish a manually recorded date from a server-provided one.
- Retain verified official history beyond the moving five-year window once imported. Merge by account and source identity, preserve original precision, and keep local estimates as a separate series. Do not fabricate gaps or interpolate a missing current value as an observation.
- Provide versioned JSON backup/restore for the full archive plus CSV/JPG sharing. Exclude credentials and session cookies. Restore validates the entire payload before replacing or merging anything.

## Main-account import

Login occurs on the official site inside the app. Bind the confirmed account before import, and use an isolated main-account session. No main-account password in a Shortcut.

Existing ArcPot code provides these reference read routes at `https://webapi.lowiro.com`:

- `/webapi/user/me`
- `/webapi/score/song/me/all?difficulty={0..4}&page={n}&sort=date&term=`
- `/webapi/score/rating_progression/me?duration=5y`
- `/webapi/score/rating/me` for optional B50 comparison.

Revalidate these contracts in implementation. In the existing code, `arcaea_online_expire_ts` is **milliseconds remaining**, not an epoch timestamp. Carry that regression test into Swift and confirm it against current responses.

Sequence: account/subscription check → all difficulty pages → five-year history → account/subscription recheck → one atomic archive commit. Use sequential requests with a default one-second pause after each response; display progress and support cancellation. Bound page counts, response sizes and collection sizes. An incomplete page sequence, account switch, cancellation, malformed response or required-step failure leaves the previous archive intact. An empty successful source result must not erase existing history or manual records.

Artwork is an independent optional cache fill after score commit. Fetch only observed official asset identifiers, without authentication cookies; retain successful images and use placeholders on failure. A missing cover must not roll back scores.

## Burner authentication and recent fetch

Provide a one-time **Configure Burner Account** Shortcut action accepting credentials entered by the user in Shortcuts, plus the intended main-account identifier. Store credentials in the device Keychain; the recurring action references the configured account and has no password parameter. Tell the user to remove literal password values from saved setup actions after configuration, since Shortcuts content is not the app's Keychain. Also allow setup/replacement from the app.

Persist the burner cookie jar across invocations and app restarts, including cookie attributes and rotated Set-Cookie values. Isolate it from the main login and from Safari/global shared cookie storage. Use Keychain for session secrets; never write raw authentication values to diagnostics or exports. Support access after first device unlock for background requests; return a locked status before secrets are available. Verify storage behavior after re-signing/updating the app.

Each **Fetch Recent Play** invocation:

1. Acquire the persisted fetch lease and check the minimum interval and server cooldown. Overlapping UI/Shortcut calls cannot create duplicate requests or competing logins.
2. Reuse the burner session and request only the website data needed for the selected main account. Validate the authenticated observer and target binding; do not use the subscribed main session as a fallback.
3. On a documented expired/invalid-session response, log in once using the saved burner credentials, validate identity, persist replacement cookies and retry the read once. Bootstrap login is also allowed when no session exists. Do not classify every 403, HTML response or network failure as session expiry.
4. If login needs CAPTCHA/MFA/browser interaction, credentials are rejected, or the schema changes, return a specific status and stop automatic attempts until repaired. Respect Retry-After on 429; back off network failures. Never enter an unbounded re-login loop.
5. Atomically save new observations and refreshed sync state, returning a structured result containing status, added count, last play time, last success time and next eligible request time. Never return secrets.

Target one recent-data request on the healthy path if the verified source permits it; identity checks or pagination may require more. Keep artwork downloads, full imports, charts, and waiting loops out of the intent. Bound an invocation to a short deadline (initial budget 20 seconds, measured and adjusted downward if the OS requires); preserve data and return retryable status on expiration.

## Shortcut automation

Actions: Configure Burner Account, Set Tracking Active, Fetch Recent Play, and Get Tracking Status. Keep the fetch action non-opening (`openAppWhenRun = false`). Use the main app target initially to avoid a separate extension/container requirement; prove discovery and background execution after SideStore signing.

Requested recipe: Arcaea Opened → start a new tracking generation → fetch → bounded Repeat/Wait loop targeting 70 seconds between attempts; Arcaea Closed → deactivate tracking, optionally make one final permitted fetch. Each iteration checks its generation so a previous loop cannot resume after a new game session starts. Respect the persisted 60-second minimum between attempts and longer server cooldowns. Do not accumulate catch-up requests after suspension. The app cannot independently inspect arbitrary foreground apps; the automation signals are the source of tracking state.

Real-device proof must measure sustained runs, rapid app switching, lock/unlock, force-quit, network loss, an expired cookie, and signing refresh. Test an ordinary 30–60 minute play session. If the loop is suspended, label continuous tracking experimental/unreliable and offer one-shot fetch plus fetch-on-open/close as explicit fallbacks. Never claim those fallbacks meet the continuous 60–80-second requirement. If that requirement is non-negotiable and fails, return to architecture review before a production release.

## Delivery gates

1. Approve this proposed design and implementation plan.
2. Build a small device feasibility IPA after approval: prove Shortcut discovery, background request/write, cookie reuse, renewal, and timing on iPadOS 18.7.3; verify the actual burner source contract and subscription requirements.
3. Implement the archive and feature set, with automated parser/reconciliation tests and simulator UI checks.
4. Validate the finished app through direct SideStore installation; optionally smoke-test the foreground app in LiveContainer. Record exact versions and limits.
5. Deliver versioned IPA, source, installation/Shortcut instructions, backup guidance, and a verification report. An IPA package alone is not proof that it installs or that background automation works. No product code, dependencies, signing or IPA generation is part of this planning-only delivery.

## Sources and evidence

- Local ArcPotApk README, Rating.java, OnlineProtocol.java, OnlineSync.java, existing tests and NOTICE.md inspected read-only on 2026-10-07.
- Current friends page inspected through the existing browser tab; recent-activity summaries were visible. This was not a verified burner-session network capture.
- [Apple: iOS background execution limits](https://developer.apple.com/forums/thread/685525).
- [Apple: App automation triggers](https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios).
- [Apple: AppIntent](https://developer.apple.com/documentation/appintents/appintent).
- [LiveContainer: guest extension limitations](https://livecontainer.github.io/docs/faq).
- [LiveContainer: Launch App Shortcut](https://livecontainer.github.io/docs/guides/add-to-home-screen).
