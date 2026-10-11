# ArcProbe 0.2.10 · build 12

B50 export now uses bundled open-source Exo, Exo 2, Titillium Web and Open Sans, replacing system fonts for Latin text and numbers. Font roles, weights, sizes and baseline placement were tuned against B50.jpg. The header potential uses a larger whole number and smaller fractional portion (including the decimal point) at the official frontend’s 16/22 size ratio, on a shared baseline. It retains all three decimal digits and no estimate label inside the portrait diamond. Source and license details are in ../export-fonts.md.

The server-generated official JPG’s exact fonts/settings are not exposed; these are the close open-source matches approved by the user. System fallback remains for scripts outside these fonts’ coverage. Fonts and their original SIL OFL license files are included in the app and require no network requests.

Verification on 2026-10-11:
- Observed the font-resource test fail before the Fonts folder was added to the app’s resource build phase.
- All 43 app tests passed on iPad Pro 11-inch (M4), iOS 18.6, including font loading without system fallback, fractional font-size ratio and preserved value, JPEG export/cover/partner regression tests and existing archive/network tests.
- Inspected the rendered header and first card rows at full size, including long and non-Latin titles. Score digits remain clear of the clear badge; smaller potential decimals share the baseline and leave stars visible.
- Release arm64 IPA build succeeded. ZIP integrity, version 0.2.10/build 12, unchanged bundle identifier app.arcaeaoffline, all 6 font binaries and all 4 license files verified. git diff --check passed.

Evidence: .cache/font-red.log, .cache/font-final.log, build/font-preview-tests.xcresult, build/font-final-tests.xcresult, build/package/release-build.log. Preview images under artifacts use synthetic scores and placeholder artwork.

Artifact: artifacts/ArcProbe-0.2.10.ipa, 3,430,874 bytes, unsigned for SideStore re-signing.
SHA-256: 7e72d475e23fe1eb561525ba29bbfde7d4c9536e3d3a5f3b6a8f349183ba41de.

Physical iPad installation/sharing was not tested. UI automation and core-only suites were not rerun for this export-only typography change.
