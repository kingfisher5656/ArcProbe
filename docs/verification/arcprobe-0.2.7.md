# ArcProbe 0.2.7 · build 9

Potential now uses one graph. Imported official history remains purple and unchanged. Orange points and a connecting line show only estimated changes after a real full-sync baseline. The former reconstructed historical Best 50 graph and its series picker have been removed.

A successful full import freezes the imported scores, latest official potential point, and sync time together. Subsequent eligible plays and manual changes are replayed after that boundary; the change in calculated Best 50 potential is added to the official anchor. Changes dated at or before the sync time cannot rewrite official history. Deletion, undo, score edits, and achieved-date edits rebuild the continuation. Another full import advances the baseline and replaces covered estimates with official history.

Existing installations need one full Arcaea Online import after upgrading to establish this baseline. Earlier versions did not save a trustworthy full-sync score snapshot, so the app deliberately does not fabricate one. The orange section is an estimate, not recovered official history. JSON backups include the baseline and source changes; older JSON backups still restore their official history but require a full sync before estimates can resume. Cover backup and existing tracking controls remain available.

Verification on 2026-10-09:
- 79 core tests passed, including exact sync-boundary behavior, ignored pre-sync edits, post-sync score/date changes, deletion/undo, baseline advancement, repeated official points, legacy backup compatibility, malformed baseline rejection, account isolation, migration, and JSON round trips.
- 33 app tests passed, including model refresh and restored continuation, plus cover backup and tracking regressions.
- 3 iOS simulator UI tests passed. Manual scores without an official baseline do not fabricate historical potential; the merged graph legend and tracking setting persistence were checked.
- Release arm64 packaging succeeded. IPA ZIP integrity, display name ArcProbe, version 0.2.7, build 9, and unchanged bundle identifier app.arcaeaoffline were verified. git diff --check passed.

Evidence: .cache/continuation-final-core.log, .cache/continuation-final-ios-tests.log, build/continuation-final-ios-tests.xcresult, .cache/continuation-package.log, build/package/release-build.log.

Artifact: artifacts/ArcProbe-0.2.7.ipa, 2,620,766 bytes, unsigned for SideStore re-signing.
SHA-256: 4872a9836c1e24ef3a6db7da124574505c9f2fa87def21adf6e13876e39d2e9b.

Physical-device installation and live website propagation were not verified here.
