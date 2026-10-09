# ArcProbe 0.2.5 · build 7

Added **Enforce 60-second minimum** under Accounts & sync → Tracking and Shortcuts. It defaults to on and is persisted in the shared tracking database so manual requests and Shortcut processes use the same choice. Disabling it clears the normal local deadline immediately. Re-enabling it applies the minimum from the last attempt.

Server rate-limit deadlines, network-failure backoff, generation validation, and concurrent-request leases remain enforced. Account replacement retains the preference and protected cooldowns. Existing Shortcut Wait actions are not edited. Older versions stored all cooldowns in one field, so an outstanding legacy deadline is conservatively preserved once during upgrade.

Verification on 2026-10-09:
- 72 core tests passed, including preference changes across database connections, re-enabling, preserved server/failure backoff and legacy-payload migration.
- 27 app tests and both existing UI flows passed in the full run. The new setting UI test initially failed because the test tapped an offscreen tab, then the labeled row instead of its child switch. After correcting those selectors, the focused test passed: default on, off, relaunch still off, and back on. No application changes were needed for these test issues.
- App intent regression checks verify a closing fetch can run immediately after disabling the minimum.
- Release arm64 build passed; ZIP integrity, version/build and unchanged app identifier verified.

Evidence: .cache/minimum-core.log, .cache/minimum-fixed-tests.log, build/minimum-fixed-tests.xcresult, .cache/minimum-toggle-tests.log, build/minimum-toggle-tests.xcresult, build/package/release-build.log.

Artifact: artifacts/ArcProbe-0.2.5.ipa, 2,560,489 bytes, unsigned for SideStore signing.
SHA-256: b648faa9ab327c746d9e2866e99ef4a6752611006c509204f0ef1dbadeee698d.

Physical-device installation and background automation timing have not been verified here. Shorter intervals cannot guarantee that a newly uploaded play is already visible at the server.
