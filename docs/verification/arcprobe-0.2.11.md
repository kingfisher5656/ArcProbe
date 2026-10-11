# ArcProbe 0.2.11 · build 13

B50 export grade and clear letters now use visible CoreText glyph bounds for centering and fit within the sloping diamond edges. INS metadata selects deep blue independently of its underlying BYD difficulty. BYD is crimson, FTR reddish purple, and ETR bluish purple. Ranks 1–10 have blue card backgrounds, borders and title strips; ranks 11–50 have purple equivalents.

The header potential badge moves 6 points right and 19 points upward, alongside the partner diamond’s lower-right edge. Its number retains the smaller fractional digits and now has a heavier black outline for contrast against the white 13+ badge.

Verification on 2026-10-12:
- All 43 app tests passed on iPad Pro 11-inch (M4), iOS 18.6. Updated synthetic export fixtures exercise INS, varied grades and all six clear types.
- Visually inspected the full 50-card render for grade/clear centering and containment, difficulty colors, and the rank 10/11 frame boundary; inspected the 13.000 header preview for placement and contrast.
- Release arm64 packaging succeeded. ZIP integrity, version 0.2.11/build 13 and unchanged bundle identifier app.arcaeaoffline verified. git diff --check passed.

Evidence: build/badge-header-final-tests.xcresult, .cache/badge-header-final.log, build/package/release-build.log. Synthetic previews: artifacts/ArcProbe-0.2.11-B50-preview.png and artifacts/ArcProbe-0.2.11-potential-preview.png. B50.jpg remains an unbundled reference.

Artifact: artifacts/ArcProbe-0.2.11.ipa, 3,431,711 bytes, unsigned for SideStore re-signing.
SHA-256: c0e6c3d0fd8799e53fad1e2993cfa8d4600c15167f17321f49beb4b2486b2081.

Physical iPad installation/sharing was not tested. Core-only and UI automation suites were not rerun for this export-only change.
