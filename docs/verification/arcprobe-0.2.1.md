# ArcProbe 0.2.1 · build 3

Verified 2026-10-08, Xcode 27.0, iPad Pro 11-inch M4 simulator on iOS 18.6.

- 66 core, 25 app and 2 UI tests passed. New app tests cover separate Beyond jackets, duplicate/ambiguous labels, original-image URL validation, original resolution preservation and chart-specific cache separation.
- A separate live simulator probe followed Song_list → Vexaria → original file pages and downloaded both Future and Beyond jackets. Both cached images measured 768×768. Result: “Saved 2 chart covers. 0 unmatched charts retain their existing artwork.” Evidence: `.cache/wiki-live-probe.log`, `build/wiki-live-probe.xcresult`. The temporary network-dependent probe was removed from the normal offline test suite; its source is retained in `.cache/wiki-live-probe.swift`.
- The official score-page jacket inspected in the browser was 200×200. Vexaria's wiki lists separate normal and Beyond originals: https://arcaea.miraheze.org/wiki/Vexaria . Direct HTTP wiki requests returned 403, while normal browser navigation and the implemented in-app WebKit download both succeeded.
- The B50 rating now has a PLAY RATING label and a bold purple title-sized value. Final simulator screenshot reviewed: `artifacts/wiki-ui/CD9AC575-8E38-4879-8CA8-7839E8C85F0D.png`.
- Release arm64 iPhoneOS IPA built successfully; ZIP integrity, ArcProbe display name, version 0.2.1/build 3, unchanged `app.arcaeaoffline` identity, and exclusion of account databases/cached artwork checked.

Artifact: `artifacts/ArcProbe-0.2.1.ipa`, 2,542,823 bytes. Unsigned; SideStore performs signing.

SHA-256: `a16a43de82a930a229fa65fa0def4bf47e6e461ed2893984972f1791d531ddd5`

Use Settings → Chart data & cover art → Download sharper wiki covers → Download missing wiki covers. Import official score metadata first and leave this screen open. The downloader matches exact titles to song-list links, verifies the article's Song ID, reads explicit difficulty labels and follows original-file links. Ambiguous matches are skipped; existing official artwork remains available. Original files are stored without recompression, keyed by song and difficulty. Completed downloads survive stopping. Network or website changes can interrupt a run; reopening and restarting skips already cached chart covers.

Live verification covered Vexaria's two variants, not every song in the wiki. Songs with ambiguous titles or unsupported article layouts retain official artwork. No new guarantee about iOS 27 background notification delivery is made in this update. ArcPotApk remains unchanged.
