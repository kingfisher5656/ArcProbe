# ArcProbe 0.2.8 · build 10

Best 50 JPG export now follows the supplied B50.jpg composition: 1800 × 3208 portrait, five columns and ten rows, pale lavender geometric background, centered player/potential banner, square song covers, left-hand potential and grade, gold top-ten ratings, score overlays, title strips, difficulty diamonds and chart-best clear badges. ArcProbe branding and explicit estimate wording remain. Decorative artwork is drawn locally; the official wallpaper, logo, partner image and typeface are not replicated exactly.

The export freezes its score/catalog/profile snapshot before asynchronously loading cached, downsampled artwork. Difficulty-specific wiki artwork takes priority over official artwork, with a visible fallback for unavailable covers. Export does not perform authenticated requests or fetch new covers. Unknown clear/level/rating data remains unknown. The JPG button prevents duplicate exports while preparing. CSV source/date fields and the B50 screen layout are unchanged.

Verification on 2026-10-11:
- Observed the portrait-dimension regression fail against the former 1800 × 3100 renderer before implementation.
- All 36 app tests and 3 simulator UI tests passed on iPad Pro 11-inch (M4), iOS 18.6. Five export tests cover CSV, full-size JPEG, difficulty-specific artwork priority and official fallback using decoded pixel checks, score formatting/unknown clear status, and a 50-card visual fixture.
- Inspected exported full-size and detail preview attachments. Fixed clear-badge overlap with score digits and strengthened outlined text. Long titles truncate within their cards; all ten rows and the footer remain in bounds.
- Release arm64 build succeeded; IPA archive integrity, version/build and unchanged bundle identifier app.arcaeaoffline verified. The user's B50.jpg is not bundled. git diff --check passed.

Evidence: .cache/b50-export-red.log, .cache/b50-export-final-tests.log, build/b50-export-final-tests.xcresult, build/package/release-build.log. Preview files under artifacts use synthetic player data and illustrative artwork, not the user's archive.

Artifact: artifacts/ArcProbe-0.2.8.ipa, 2,642,504 bytes, unsigned for SideStore re-signing.
SHA-256: af6a96dd1970172474ff71df4e4a9e10f180007f8db429fc0ad0f2845c1b3897.

Physical-device installation and sharing through external iOS apps were not verified here.
