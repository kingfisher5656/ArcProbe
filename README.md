# ArcProbe

An unofficial native iPhone/iPad score archive for iOS 18 or later. The primary installation target is a direct SideStore installation on iPadOS 18.7.3.

## Included

- Local score browsing, manual entry, corrections, deletion and undo without a subscription.
- A separate main-account login for importing the website's exposed score pages and returned five-year potential history.
- An independent recent-account login, with explicit own-account testing and friend-target modes.
- One-shot background Shortcuts actions, saved cookies, bounded session renewal and persisted request cooldowns.
- Large artwork Best 50 cards, history range sliders, play-rating sorting, JSON archive backup/restore, and Best 50 JPG/CSV export.
- On-demand Miraheze chart-constant refresh and official lowiro cover downloads.
- Experimental iOS 27 notification automation actions, alongside the existing iOS 18 tracking method.

Official history and local estimates stay separate. Constants are a dated snapshot; estimates are not a guarantee of the current official rating. Missing fields and dates remain unknown. Website imports capture the data exposed by the website; they cannot recover every historical play. Official cover artwork can be downloaded after importing scores and stays cached offline.

## Install and configure

The generated `artifacts/ArcProbe-0.2.1.ipa` is an unsigned iPhoneOS arm64 package. Import it into SideStore for signing and installation. It is not a pre-signed IPA. Direct installation is the intended path for Shortcuts; LiveContainer background-action discovery has not been verified.

1. Open **Accounts & sync** and sign into the main account using the official login page. Confirm **Use signed-in account**, then run the full import. This account needs an active Arcaea Online subscription.
2. Set up the **Recent account** independently. For now choose **Own account (testing)** and sign in with the same main account identity. The two sessions remain isolated.
3. Later, connect a burner account that is already friends with the main account, select **Friend target (burner)**, and configure it again. The connected main account supplies the target identity.
4. Configure automatic renewal in the app or using the setup Shortcut action. Credentials are held in the device Keychain; remove literal passwords from the saved setup Shortcut afterward. Recurring fetches do not take passwords.
5. In **Chart data & cover art**, refresh constants and download missing official covers after importing scores. For larger originals, choose **Download sharper wiki covers**, then start the download in the wiki screen. The app follows song articles and original-file links, checks song IDs and difficulty labels, and keeps Beyond artwork separate. Keep that screen open. Unmatched charts retain official covers. Artwork requests use separate sessions without account login cookies. Keep the app open while downloading; completed covers survive cancellation.
6. Follow the in-app **Shortcut setup instructions** and [detailed recipes](docs/shortcuts/setup.md).

The app does not schedule a guaranteed minute-by-minute background task. A bounded Shortcut loop can request a fetch about every 70 seconds, but iPadOS may suspend it. Each request respects a 60-second minimum and server cooldowns. Sustained timing, SideStore action discovery and burner access require testing on the physical iPad. If a website challenge appears, open the role's official login in the app; repeated automated login is not attempted.

## Recovery and privacy

Export a JSON backup before reinstalling or changing signing identity. Restore validates the file and asks before replacing the saved archive. Backups include scores, corrections, deletion markers and history, but not session cookies or credentials. Disconnecting a login preserves the archive. A new signing identity may require account reconfiguration; update/re-sign persistence remains a device acceptance check.

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

Use an installed iOS 18+ simulator and a current Xcode supporting the deployment target. Packaging writes its build log under `build/package` and IPA/checksum under `artifacts`. See [release verification](docs/verification/arcprobe-0.2.1.md) for actual checks and untested device requirements. The website adapter is based on inspected official frontend contracts and synthetic regression fixtures; real authenticated app import is a separate acceptance test.

See [notices](NOTICE.md) for metadata attribution. The sibling ArcPotApk project is a read-only reference and is not a build dependency.
