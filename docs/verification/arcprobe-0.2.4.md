# ArcProbe 0.2.4 · build 6

Added Final Fetch After Closing to Fetch Recent Play. A final request requires the original, stopped tracking generation. It can commit after stop, but fails if Arcaea has reopened or the recent account was replaced. Normal polling still rejects stopped generations. Existing leases, 60-second cooldowns, server Retry-After and account isolation remain enforced.

The installed Shortcut needs an edit: in the inactive branch, repeat twice: Wait 65 seconds, Fetch Recent Play with the original generation and Final Fetch After Closing enabled. Then stop. Keep the option off for normal polling. Follow docs/shortcuts/setup.md for result handling and longer cooldowns. Waits belong in Shortcuts; each app request retains its 20-second network budget. No implicit background retry is scheduled by the app.

Verification on 2026-10-08:
- Reproduced the missing last play: the regression returned trackingStopped and saved only the earlier play before the fix.
- 69 core tests passed, including delayed upload on the second closing poll, retained server backoff, required stopped generation, and reopening during an in-flight final request.
- 27 app tests and 2 UI tests passed on the iOS 18.6 iPad simulator. Intent tests verify propagation of the final option and rejection of a missing generation.
- Release arm64 build passed. IPA ZIP integrity, version 0.2.4/build 6 and unchanged bundle ID app.arcaeaoffline verified.

Evidence: .cache/final-fetch-red.log, .cache/final-fetch-core.log, .cache/final-fetch-tests.log, build/final-fetch-tests.xcresult, build/package/release-build.log.

Artifact: artifacts/ArcProbe-0.2.4.ipa, 2,555,903 bytes, unsigned for SideStore.
SHA-256: 81919c4b27156fb5a1d20def7ca0b0fbbacde389950c4abd446981d9705efd64.

Physical iPadOS 18.7.3 execution, Shortcut action discovery after update, and live upload propagation timing remain to be checked on the user's device. Arbitrarily delayed uploads, longer server cooldowns, and an automation terminated by iOS can still require a later fetch. The closing branch depends on the polling Shortcut still running; installing the update alone cannot edit an existing Shortcut.
