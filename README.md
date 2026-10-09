# ArcProbe

An unofficial native iPhone/iPad score archive for iOS 18 or later. The primary installation target is a direct SideStore installation on iPadOS 18.7.3.

## Included

- Local score browsing, manual entry, corrections, deletion and undo without a subscription.
- A separate main-account login for importing the website's exposed score pages and returned five-year potential history.
- An independent recent-account login, with explicit own-account testing and friend-target modes.
- One-shot background Shortcuts actions, saved cookies, bounded session renewal and persisted request cooldowns.
- Large artwork Best 50 cards, official potential history with a post-sync estimated continuation, history range sliders, play-rating sorting, JSON archive backup/restore, and Best 50 JPG/CSV export.
- On-demand Miraheze chart-constant refresh, cover downloads, and portable cover-art backup/restore.
- Experimental iOS 27 notification automation actions, alongside the existing iOS 18 tracking method.

Official history and local estimates stay separate. Constants are a dated snapshot; estimates are not a guarantee of the current official rating. Missing fields and dates remain unknown. Website imports capture the data exposed by the website; they cannot recover every historical play. Official cover artwork can be downloaded after importing scores and stays cached offline.

## Install and configure

The generated `artifacts/ArcProbe-0.2.7.ipa` is an unsigned iPhoneOS arm64 package. Import it into SideStore for signing and installation. It is not a pre-signed IPA. Direct installation is the intended path for Shortcuts; LiveContainer background-action discovery has not been verified.

1. Open **Accounts & sync** and sign into the main account using the official login page. Confirm **Use signed-in account**, then run the full import. This account needs an active Arcaea Online subscription.
2. Set up the **Recent account** independently. For now choose **Own account (testing)** and sign in with the same main account identity. The two sessions remain isolated.
3. Later, connect a burner account that is already friends with the main account, select **Friend target (burner)**, and configure it again. The connected main account supplies the target identity.
4. Configure automatic renewal in the app or using the setup Shortcut action. Credentials are held in the device Keychain; remove literal passwords from the saved setup Shortcut afterward. Recurring fetches do not take passwords.
5. In **Chart data & cover art**, refresh constants and download missing official covers after importing scores. For larger originals, choose **Download sharper wiki covers**, then start the download in the wiki screen. The app follows song articles and original-file links, checks song IDs and difficulty labels, and keeps Beyond artwork separate. Keep that screen open. Unmatched charts retain official covers. Artwork requests use separate sessions without account login cookies. Keep the app open while downloading; completed covers survive cancellation.
6. Follow the in-app **Shortcut setup instructions** and [detailed recipes](docs/shortcuts/setup.md).

The app does not schedule a guaranteed minute-by-minute background task. A bounded Shortcut loop can request a fetch about every 70 seconds, but iPadOS may suspend it. Each request respects an optional 60-second minimum (enabled by default) and server cooldowns. Disable the app minimum in Settings → Tracking and Shortcuts; existing Shortcut Wait actions remain unchanged. Sustained timing, SideStore action discovery and burner access require testing on the physical iPad. If a website challenge appears, open the role's official login in the app; repeated automated login is not attempted.

## Potential graph

One graph shows **official history in purple** and an **estimated continuation in orange**. Imported official values are never reconstructed or changed by score edits. A full score/history sync stores an immutable score baseline and the last official point. Later plays and edits with achieved dates after that sync adjust only the orange continuation, using the change in saved-score potential relative to the baseline and adding that change to the official anchor value. Undated new plays use their first recorded time. A new full sync advances the baseline; covered estimates are replaced by official observations.

The old Local · Best 50 history view has been removed. Existing installations need one full Arcaea Online import after this update to establish a trustworthy baseline; old official history remains available before then. No earlier potential is inferred from current chart bests. Plays/edits dated at or before the sync do not affect the continuation. Orange values remain estimates and can differ from the server.

JSON backup/restore includes official history, the frozen sync baseline, source plays and edits. The orange continuation rebuilds from the restored data. Older JSON backups remain importable but need a new full sync to establish a baseline.

## Recovery and privacy

Export a JSON backup before reinstalling or changing signing identity. Also use **Chart data & cover art → Export cover backup**, then save the `.arcprobe-covers` file outside the app (for example, iCloud Drive). After reinstalling, restore the JSON archive and use **Restore cover backup** to import the image file. Cover backups preserve original image bytes, official cache identifiers, and difficulty-specific wiki keys; restoring merges covers and retains equal/higher-resolution existing images. Validation happens before installation; a disk-write failure can leave a partial merge with completed covers usable. Cover backups are limited to 12,000 images, 8 MiB per image, and 2 GiB total. Restore validates the file and asks before replacing the saved archive. Backups include scores, corrections, deletion markers and history, but not session cookies or credentials. Disconnecting a login preserves the archive. A new signing identity may require account reconfiguration; update/re-sign persistence remains a device acceptance check.

Account requests go to lowiro's official website API. The app neither uploads scores nor accesses or modifies Arcaea's game files. No analytics service or developer relay is used. Exported files contain your selected archive data; share them intentionally.

## Build and verification

See the versioned release report for test/build evidence. Simulator checks do not establish sustained notification automation on physical iOS 27 devices. The user reports that the original iOS 18 loop works on their iPad.

The app uses SwiftUI, App Intents, WebKit, Keychain and a local Swift package backed by SQLite. No third-party package manager is required.

```sh
swift test --package-path Packages/ArcaeaCore
python3 scripts/generate-project.py
xcodebuild test -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID'
zsh scripts/package-ipa.sh
```

Use an installed iOS 18+ simulator and a current Xcode supporting the deployment target. Packaging writes its build log under `build/package` and IPA/checksum under `artifacts`. See [release verification](docs/verification/arcprobe-0.2.7.md) for actual checks and untested device requirements. The website adapter is based on inspected official frontend contracts and synthetic regression fixtures; real authenticated app import is a separate acceptance test.

See [notices](NOTICE.md) for metadata attribution. The sibling ArcPotApk project is a read-only reference and is not a build dependency.
