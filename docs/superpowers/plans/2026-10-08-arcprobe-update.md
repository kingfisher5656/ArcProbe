# ArcProbe update

User scope: rename the app, retain the proven iOS 18 Shortcut loop, add experimental notification-triggered short cycles for iOS 27, refresh public chart constants and cover art, use graph range sliders, enlarge B50 artwork, and add play-rating sorting. Implementation is direct in the existing project, without the earlier mandatory Sol delegation. ArcPotApk remains read-only.

## Decisions

- Display/export/package name becomes ArcProbe 0.2.0. Retain bundle ID, internal module and storage/Keychain paths for update compatibility.
- Existing four Shortcut actions and generation behavior remain available.
- Add Start Notification Tracking, Stop Notification Tracking, and Process Tracking Notification. One pending notification carries a random token and tracking generation. Processing a current token consumes it once, schedules a successor using the configured interval, then performs the existing bounded fetch. Old/duplicate/stopped notifications cannot schedule another cycle. This is an indefinitely renewable chain, not an app process running forever. Notification permission is requested in the app. Delivery and automation scheduling require physical iOS 27 validation.
- Interval defaults 65–80 seconds, adjustable with a 60-second minimum. Persist range and chain state; honor fetch cooldowns. Stop removes pending requests and invalidates the generation. No guaranteed delivery timing claimed.
- Chart constants are fetched explicitly from the provided Miraheze raw JSON endpoint. Validate a complete snapshot before atomic replacement; preserve existing scores/descriptions. Bundled metadata must not overwrite downloaded constants on reopening. Invalid or failed downloads retain the previous table.
- Fandom Songs_by_Date returns HTTP 403 on direct HTTP access. User authorized the official account source instead: imported artwork identifiers map to lowiro’s public asset server. Download/cache those covers without account credentials; unavailable images retain placeholders.
- Custom potential range uses two accessible start/end sliders over the saved history, with date labels and presets retained. All-score sort offers Name and Play rating, with unrated charts last and deterministic ties.

## Verification

Core tests: constant validation/rollback/reopen, pulse token consumption/stopping/restart, interval bounds. App tests: sorting/range and notification adapter behavior where feasible. Preserve existing full test suite, then run signed iPad Simulator app/UI tests and Release arm64 build. Device tests remain necessary for iOS 27 notification-triggered automation and upgraded SideStore persistence.

## Source evidence

Apple iOS 27 Shortcuts event-trigger documentation lists Notification with app/title/subtitle/message filters. Apple notification documentation describes system delivery while the app is suspended; delivery alone does not run the app's scheduler. Miraheze raw endpoint returned HTTP 200 with the expected JSON schema on 2026-10-08. Fandom returned HTTP 403.
