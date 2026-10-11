# ArcProbe 0.2.9 · build 11

The B50 export now places the equipped partner portrait in the header diamond, with potential overlapping its lower-right edge. The estimate label is removed from the diamond; the footer retains the explanation. Official rank backgrounds provide the exact star/ring artwork: one star at 12.000, two at 12.500, three at 13.000. All lower ranks and hidden/unknown fallback are covered too. The displayed local potential drives badge selection.

The friends endpoint supplies the selected target’s icon. The main-account endpoint can also supply the equipped character via character_stats. The optional validated identifier is persisted with the profile, survives sparse imports and JSON backup/restore, and updates even when a recent fetch contains no new score. Older JSON archives decode without the field. Existing installs need a recent fetch or a full import to capture the partner once.

Portraits are loaded from the official public asset server with no cookies or credentials, size/dimension validation and redirect blocking, then cached separately on disk. Exports can reuse that portrait offline. Unknown or unavailable portraits use a neutral placeholder; a cached portrait for a different partner is never substituted. The profile identifier is backed up in JSON; the small portrait image can download again after reinstalling. Official badge assets and inspected frontend rules are documented in ../official-profile-artwork.md.

Verification on 2026-10-11:
- 82 core tests passed, including target-partner extraction, main-account equipped-character selection, unsafe and numeric identifiers, sparse-import preservation, partner changes, legacy profiles and JSON round trips.
- 40 app tests passed, including every rank threshold, all bundled badges, cookie-free portrait URL construction, persistent/offline cache, invalid identifiers/images, and an end-to-end decoded-pixel check that the selected profile’s portrait reaches the export diamond.
- 3 simulator UI regressions passed on iPad Pro 11-inch (M4), iOS 18.6.
- Inspected header previews at 12.499, 12.500 and 13.000; the number, star count and portrait frame remain legible without the estimate label. Preview art is synthetic, not the user's partner.
- Release arm64 build and IPA ZIP integrity passed. Version 0.2.9, build 11, unchanged bundle app.arcaeaoffline verified. git diff --check passed.

Evidence: .cache/partner-core.log, .cache/partner-app.log, .cache/partner-red.log, build/partner-final-tests.xcresult, build/package/release-build.log.

Artifact: artifacts/ArcProbe-0.2.9.ipa, 2,746,394 bytes, unsigned for SideStore re-signing.
SHA-256: 479a7a173d77591715700277715c6734020fa92a1c4acebe0e3f0a1b310a5299.

Live authenticated friend data and installation/sharing on a physical iPad were not verified here. The integration uses the current official public frontend contract and synthetic regression tests.
