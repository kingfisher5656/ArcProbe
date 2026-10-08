# ArcProbe 0.2.3 · build 5

Fixed a reproducible original-cover validation bug: Lost Civilization's base jacket is 500×500, below the previous 512-pixel minimum. The app now accepts originals from 256 through 4096 pixels without upscaling. Existing size, format, chart identity and difficulty checks remain. An invalid or undersized image is counted as unsupported and skipped instead of aborting the remaining chart downloads. Transport failures still stop the run and retain completed covers.

Verification on 2026-10-08:
- Added a 500×500 regression test and observed it fail with invalidImage before the fix, then pass after the change.
- 27 app tests and 2 UI tests passed on the iOS 18.6 iPad simulator.
- Separate live simulator probe downloaded Lost Civilization's Future original at 500×500 and Beyond original at 768×768. Both assertions passed. Result: “Saved 2 chart covers. 0 unmatched or unsupported charts retain their existing artwork.”
- Release arm64 IPA built; ZIP integrity, version/build and unchanged app identifier verified.

Evidence: `.cache/lost-red.log`, `.cache/lost-fixed-tests.log`, `build/lost-fixed-tests.xcresult`, `.cache/lost-live-probe.log`, `build/lost-live-probe.xcresult`. The temporary live test was removed from the offline regression suite; its source is in `.cache/lost-live-probe.swift`.

Artifact: `artifacts/ArcProbe-0.2.3.ipa`, 2,553,766 bytes, unsigned for SideStore signing.
SHA-256: `2f966ecd9d1845a4bb0fed636cedb280905068fce806f9e9cb3c70f63d631e83`.

After updating, restart Download sharper wiki covers. Already cached chart covers are skipped. Physical-device installation was not performed here.
