# Shortcuts setup — experimental background tracking

Install **ArcProbe directly through SideStore** and open the app once. Offline records and own-account recent testing work independently of a full import. For friend mode, connect the main account in the app so setup can select it; run a full import if desired and if it has Arcaea Online. LiveContainer foreground use does not prove that the guest app's actions are available in Shortcuts.

This build exposes Configure Recent Account, Set Tracking Active, Fetch Recent Play, and Get Tracking Status in the main app target. Fetch is one bounded invocation; it does not open the app, download artwork, import all scores, or run a waiting loop. Device discovery and background execution still require testing on the user's iPadOS 18.7.3 installation.

## Configure once

Choose a source in Accounts & Sync:

- **Own account (testing)** signs into the main account independently in the recent role. It reads that role's `/webapi/user/me` recent scores without applying the full-import subscription requirement. It shares no login, cookies, or credentials with the main role.
- **Friend account** signs into the intended burner. The main account must already be its friend. Connect the main account in the app first; setup selects its stable internal account identity automatically. A 9-digit friend code is a different value and is not an internal API identifier.

The app supports the official browser login separately for each role. If the server demands interaction, complete it there and select the recent source afterward. Browser-only configuration can reuse the persisted cookies; after they expire, automatic renewal needs explicitly saved credentials or another browser login.

For credential setup in Shortcuts, add **Configure Recent Account**, provide email/password using Ask for Input (or the action's prompts), and choose Source. Credentials are stored in the device-only Keychain, accessible after the first unlock. The recurring Fetch action has no password parameter. Remove literal passwords from the saved setup action after configuring; Shortcuts text is outside the app's Keychain. Do not put credentials into a dictionary exported by the recurring loop.

## Fetch once

Add Fetch Recent Play with Tracking Generation omitted. Its output is JSON. Use Get Dictionary from Input to read:

```json
{"status":"success","addedCount":1,"lastSuccessAt":"2026-10-08T00:00:00Z","nextEligibleAt":"2026-10-08T00:01:00Z"}
```

`lastPlayAt` is present only when the source supplies a usable play time. Omitted dates remain unknown. `success` means new observations were saved; `unchanged` means no new source event was visible. Repeated payloads deduplicate. A source retaining only its latest play can miss intervening attempts.

`cooldown`, `rateLimited`, and `alreadyFetching` perform no catch-up work. Honor `nextEligibleAt`. `attentionRequired`, `authenticationRequired`, `wrongAccount`, or `unsupportedSchema` require repairing setup in the app; automatic login stops rather than repeating indefinitely. `locked` means unlock the device once. `offline`, `deadlineExceeded`, or `cancelled` preserve saved data. Fetch uses a 20-second total request budget and a persisted minimum 60-second interval; network failures back off, and a server's longer Retry-After wins.

## App Opened automation

Create a personal automation for **Arcaea Is Opened**:

1. Run Set Tracking Active with Active=true. Save its returned UUID string as `This Generation`.
2. Use a bounded Repeat count (for example 30 iterations).
3. In each iteration, get Tracking Status and turn its JSON into a dictionary. Stop the Shortcut if `isActive` is false or `generation` differs from `This Generation`.
4. Run Fetch Recent Play with Tracking Generation=`This Generation`.
5. If its status requires account attention, stop the loop. If cooldown applies, honor `nextEligibleAt`; do not fetch repeatedly while waiting.
6. Wait 70 seconds before the next normal iteration. Keep routine `unchanged` results silent. Show a notification only for new plays, completion, failure, or required account action if desired.

The persisted interval prevents earlier calls; server delays can make the interval longer than 70 seconds. Each new open creates a generation, so an old suspended loop cannot commit a play after a newer session starts. Overlapping UI and Shortcut calls use the same durable lease.

## App Closed automation

For **Arcaea Is Closed**, run Set Tracking Active with Active=false. Optionally perform one final Fetch Recent Play with its generation omitted; it still honors minimum intervals and server cooldown. Do not run a second repeated loop.

## Required device check

The loop is experimental. iPadOS can suspend Shortcuts; an App Opened trigger is not a repeating scheduler. Test a 30–60 minute play session, rapid close/reopen, lock/unlock, airplane mode, expired cookies, force-quit, and a SideStore signing refresh. Record actual invocation timestamps, missed intervals, and visible recent plays. Simulator tests do not establish reliable 60–80 second capture while Arcaea is in front.

One-shot fetch and fetch-on-open/close are explicit fallbacks. They do not satisfy continuous 60–80 second collection if the loop is suspended. Disconnecting or replacing either login retains archived scores; replacing the recent account resets its displayed tracking dates/generation while preserving any server cooldown.


## iOS 27 notification method (experimental)

Keep the original iOS 18 Repeat/Wait recipe above for the current iPad. Do not run both methods concurrently: they share the tracking generation and request cooldown.

1. In ArcProbe Settings, configure the recent account, choose the minimum/maximum notification interval (default 65–80 seconds), save it, then enable notifications.
2. Create an **Arcaea Is Opened** automation that runs **Start Notification Tracking** once.
3. Create an iOS 27 **Notification** automation for **ArcProbe**, filtering Title to **ArcProbe tracking pulse**. Choose immediate execution when available. Add **Process Tracking Notification** and set **Notification Message** to the received notification's Message/body variable. Do not type a generation or token manually and do not use the notification title. No Repeat or Wait is needed.
4. Create an **Arcaea Is Closed** automation running **Stop Notification Tracking**. A suitable Focus-off automation is an optional experiment; Game Mode and Focus are different controls.
5. Allow immediate ArcProbe notification delivery during gaming. Verify the next pulse and a fresh recent fetch on the device.

Each pulse contains a single-use token. Processing it schedules one successor, then runs the existing bounded recent fetch. Duplicate, old-session and stopped-session pulses cannot renew the chain. Stop cancels the pending pulse. Authentication or schema failures end the chain so the account can be repaired in-app. Rate limits still apply.

The chain can renew indefinitely while iOS runs each notification automation. It does not keep the app running forever, and it cannot renew itself if the automation is not invoked. Restart notification tracking after interrupted delivery. The four-minute automation limit motivating this method is user-reported; physical iOS 27 validation remains outstanding.

Apple documents the [iOS 27 Notification automation trigger](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/10.0/ios/27) and [local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
