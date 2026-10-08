# ArcProbe 0.2.2 · build 4

B50 play ratings now use title2 (22 pt at default text size), compared with title3 scores (20 pt). Purple emphasis and Dynamic Type remain.

Code review identified synchronous cover-file lookup in SwiftUI body and deferred full-image decoding as likely scrolling costs. CoverArtwork now requests prepared images asynchronously from a dedicated actor. ImageIO performs file reads, downsampling and immediate decoding outside the main actor. Resolution follows the rendered size and display scale, bucketed in 128-pixel increments up to 1536. Original downloaded files remain intact.

A 48 MiB decoded-image cache accounts for bitmap row bytes; missing files are cached too. Download revisions invalidate the prepared cache. Offscreen views release their image state, and cancelled requests cannot publish late results. B50 overlay badges use solid translucent fills instead of live material blur. Stable chart identities and the lazy grid are retained.

Validation, 2026-10-08:
- 26 app tests and 2 UI tests passed on the iOS 18.6 iPad simulator. The new cache test covers requested dimensions, official fallback, cache reuse after file removal, missing-file caching and refresh invalidation.
- Final B50 screenshot reviewed: `artifacts/scroll-ui/2FC5B1EA-AB4C-4AB8-836D-6C950680A99C.png`.
- Release iPhoneOS arm64 build succeeded. IPA ZIP integrity, version 0.2.2/build 4 and unchanged app identifier verified.
- No physical-device frame-rate trace was captured. The changes remove identified rendering-path work; improvement on the user's iPad remains to be checked with the same B50 scrolling gesture.

Artifact: `artifacts/ArcProbe-0.2.2.ipa`, 2,553,628 bytes; unsigned for SideStore signing.
SHA-256: `bff135c8c1fbc7c725c613704aebf026bdd1c1db54d505b538c1a3079060d02f`.
Evidence: `.cache/scroll-tests.log`, `build/scroll-tests.xcresult`, `.cache/scroll-package.log`.
