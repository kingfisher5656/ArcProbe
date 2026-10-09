# ArcProbe 0.2.6 · build 8

Potential now defaults to Local · Best 50, reconstructed from effective saved plays with the same ranking formula and display precision as Best 50. Recent improvements and manual score, clear, and achieved-date changes rebuild the curve. Deletion, undo, corrections, and constant refreshes also recalculate it. An improvement outside Best 50 does not move the curve unless it changes the calculated potential. Official history remains separately selectable and unmodified.

The local curve is an estimate based on available plays and current constants, not exact official historical potential. Undated plays use their first recorded time. New undated best corrections store their creation time; legacy corrections use baseline timestamps, including suppressed baseline records, so unrelated newer imports cannot move them. Corrections replace their baseline plays consistently with current Best 50 reconciliation.

JSON backup already contains official history, source plays, edits, best corrections, and constants. The local curve rebuilds after restore. Tests confirm official and edited local histories survive a round trip; no additional graph-backup action is needed.

Chart data & cover art now includes Export cover backup and Restore cover backup. The separate .arcprobe-covers file streams original image bytes and hashed cache keys, preserving official and difficulty-specific wiki covers. Restore validates checksums, image sizes, filenames and all records before merging, keeps existing images of equal/higher resolution, and invalidates both cover caches. Disk errors during installation can leave a partial merge with completed images usable. Save both the JSON and cover backup outside the app before uninstalling.

Verification on 2026-10-09:
- 78 core tests passed, including graph updates, the Best 50 cutoff, date edits, deletion/undo, correction dates and JSON round trips. The legacy suppressed-baseline date regression was observed failing before its fix.
- 33 app tests passed, including the ArchiveModel refresh path, exact artwork round trips, difficulty variants, quality-preserving merges, cache invalidation, malformed/truncated archives, checksum failures, traversal, size limits and symlinks.
- All 3 simulator UI tests passed, exercising local/official graph switching and settings persistence. Earlier runs exposed test-only navigation mistakes (iPad overflow and sidebar button/cell selection); the selector was corrected. An overlapping run was cancelled and excluded from final verification.
- Release arm64 build and IPA ZIP integrity, version/build and unchanged app identifier verified.

Evidence: .cache/history-legacy-red.log, .cache/history-final-core.log, .cache/history-final-ios-tests.log, build/history-final-ios-tests.xcresult, build/package/release-build.log. A graph screenshot from the passing graph UI flow is in .cache/history-attachments.

Artifact: artifacts/ArcProbe-0.2.6.ipa, 2,608,735 bytes, unsigned for SideStore.
SHA-256: 53be8754083c455809e7ecade2c000dee1e37052cfe2e99885dcdff872fe0983.

Physical-device installation, live website propagation, and export/import through a user's external Files provider were not performed here.
