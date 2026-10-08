# ArcProbe 0.2.0 · build 2

Verified 2026-10-08 with Xcode 27.0 and an iPad Pro 11-inch M4 simulator running iOS 18.6.

## Results

- 66 core tests passed, including constant snapshot validation, atomic replacement and preservation on reopening; notification token persistence, duplicate rejection, stale generation, stop and interval limits.
- 21 app tests passed, including notification renewal, stop during scheduling, failed scheduling cleanup and official artwork URL/image validation.
- 2 UI tests passed: manual entry/edit/relaunch/delete/undo and invalid entry validation. Exported simulator screenshots were reviewed; the B50 card now uses a large artwork area and ArcProbe heading.
- Release iPhoneOS arm64 build passed. IPA ZIP integrity, iOS 18 minimum, display name, version and all seven App Intent records verified. No cached account databases or downloaded covers are packaged.
- Existing bundle identifier `app.arcaeaoffline`, internal target, storage paths and Keychain namespaces retained. Original four Shortcut actions retained.
- Only Arcaea Offline project files were changed; ArcPotApk was a read-only reference.

Artifact: `artifacts/ArcProbe-0.2.0.ipa` (2,476,911 bytes), unsigned for SideStore signing.

SHA-256: `40392e3144a00ad2d8975177f12032fec2e31674cefa419f57338e8c1b5c4f89`

Test evidence: `.cache/arcprobe-core.log`, `.cache/arcprobe-verified-ios.log`, `build/arcprobe-verified-tests.xcresult`. Release log: `build/package/release-build.log`. Reviewed screenshot: `artifacts/arcprobe-ui/BEE9227C-F799-4822-B9C2-308FF8C0528F.png`.

## Device acceptance still needed

- Install/update through SideStore and verify archive, Keychain and existing Shortcut references survive the same signing identity. Export a backup before changing signing identity or reinstalling.
- Main-account full import followed by Download missing official covers. The existing Codex profile view was cached; opening the score page redirected to login, preventing a live account cover check during this update. Public artwork mapping follows lowiro's asset URL contract; no login cookies are sent to asset or wiki servers.
- Test Start Notification Tracking → notification-triggered Process Tracking Notification with Message/body → Stop Notification Tracking on physical iOS 27. Delivery while gaming, Focus behavior and repeated automation execution cannot be proven by simulator unit tests. This is an indefinitely renewable one-notification chain, not a continuously running background process. If automation is not invoked, restart the chain.
- The user reports the original iOS 18.7.3 Shortcut automation works; this update retains that method. The iOS 27 four-minute limit is user-reported.

Miraheze returned a valid JSON-shaped table at the provided raw endpoint. Fandom returned HTTP 403; the user authorized official account artwork instead. No Fandom bypass was added.
