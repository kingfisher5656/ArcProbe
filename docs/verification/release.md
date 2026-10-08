# Arcaea Offline 0.1.0 — verification

Status: locally verified test build, packaged 2026-10-08. Ready for direct SideStore signing and physical-device acceptance. Live authenticated account collection and sustained background timing remain unverified.

## Final independent verification

| Check | Result |
| --- | --- |
| Actual shared core package | 63 tests, 0 failures, exit 0 |
| Fresh signed iPad Simulator app tests | 18 tests, 0 failures |
| Fresh iPad Simulator UI tests | 2 tests, 0 failures |
| Release iphoneos arm64 build | Succeeded, exit 0; no compiler warnings/errors in the build log |
| IPA ZIP integrity and bundle metadata | Passed |
| Binary platform | Mach-O arm64, IOS platform, minimum OS 18.0 |
| App Intent metadata | All four actions present |
| Package privacy checks | No archive databases, logs, private reference screenshots or debug archive selector bundled |
| Visual review | Final iPad dashboard/details and full synthetic B50 JPG inspected |

Final core run completed at 10:08:31 KST; app/UI test run completed at 10:09:28 KST. The newer rejected-configuration and concurrent-login regression tests are included. Tests use source-grounded synthetic website responses; they are not live-account integration tests.

```sh
swift test --package-path Packages/ArcaeaCore --scratch-path .cache/manager-core
xcodebuild test -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
  -destination 'platform=iOS Simulator,id=835FA26D-9808-45E7-8A59-AC0389B95DDE' \
  -derivedDataPath build/ManagerDerivedData \
  -resultBundlePath build/manager-final-tests.xcresult -parallel-testing-enabled NO
zsh scripts/package-ipa.sh
```

Local logs: `.cache/manager-core-final.log`, `.cache/manager-app-final.log`, `build/package/release-build.log`. Test bundle: `build/manager-final-tests.xcresult`. Final UI attachments: `artifacts/final-ui-verification/`.

## Package

- File: `artifacts/Arcaea-Offline-0.1.0.ipa`
- Size: 2,367,349 bytes.
- SHA-256: `55aae19a7243726e7df241db815f0cabafa59860afb5e1e13de1ae2ad9d8f3db`
- Unsigned device package; `codesign` confirms no signature. SideStore must sign it. No provisioning identity was added or changed.
- Payload includes the app executable, icon assets, App Intents metadata, public chart constants/levels and attribution. Test targets and private reference images are excluded.

## Environment

- Xcode 27.0, build 27A266a; Swift 6 project.
- Minimum iOS/iPadOS 18.0; intended physical device iPadOS 18.7.3.
- Local test device: iPad Pro 11-inch (M4), iPadOS 18.6 Simulator, ID `835FA26D-9808-45E7-8A59-AC0389B95DDE`.
- Bundle identity `app.arcaeaoffline`, display name **Arcaea Offline**, version 0.1.0, build 1.
- Simulator tests use normal ad hoc signing. An earlier unsigned simulator test failed Keychain access; normal signing resolved it without changing secure storage.
- Physical iPad is paired, but its Xcode developer disk could not mount. No physical installation or live-account app test is claimed.

## Review scope

The lead engineer inspected the implementation, including transactional archive/backup handling, manual-change persistence, cross-source identity, isolated role storage, session revision guards, request policy, tracking leases/generations, App Intents, UI state refresh, graph sampling and exports.

Review fixes include preserving gauge fields during score edits, keeping recent capture provenance after deduplication, using each attempt's rating in recent rows, cancelling stale role operations, preserving server cooldowns, making validation visible and separating Edit/Delete actions in list rows.

The synthetic Best 50 JPG was visually inspected: five columns by ten rows, with source/date labels and no observed clipping. No private account data was used in tests or examples.

## Physical-device acceptance still required

These items cannot be established by synthetic network tests or a Simulator build:

- SideStore installation, first launch, Shortcut action discovery and re-sign/update persistence on iPadOS 18.7.3.
- Real main-account login, cookie transfer from official login to API requests, full score counts and returned five-year history compared with the website.
- Real own-account recent fetch; later, burner friend access and whether that burner requires a subscription.
- Actual expiry/renewal and website challenge handling with that account and device.
- A 30–60-minute 70-second Shortcut-loop trial while Arcaea is in front, including close/reopen, suspension, lock/unlock and network loss. Continuous 60–80-second collection is **not verified or guaranteed**.
- LiveContainer guest-app Shortcut discovery/background execution. Direct SideStore installation remains primary.

The website contract report distinguishes inspected official frontend routes from unverified authenticated raw responses. Cover downloading is deferred; this build uses placeholders and preserves returned artwork identifiers. The local rating uses dated reference constants and remains an estimate.

## Reproduction

Core tests and app tests must both pass; do not disable Simulator signing for Keychain verification. Build commands are in the README. `scripts/package-ipa.sh` produces a device arm64 Release app and an unsigned IPA for SideStore to re-sign. A Simulator `.app` is never substituted for the device package.
