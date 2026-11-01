# 2026-11-01 — P3.1 R12-CXR R6 evidence byte-preservation correction

## Finding and correction

After checkpoint `2026-11-01-P3-1-R12-CXR-R6-D0-BLOCKER.md` was committed at `64ace4e9de3b8dbd65b62205cd5cab7f07fc5896`, a post-commit audit streamed each archived D0 evidence blob directly from Git and compared its SHA-256 to `docs/reports/P3-1-R12-CXR-R6/evidence/d0/SHA256SUMS.txt`. Seventeen of 25 files differed because the repository-wide `text=auto` attribute normalized line endings while staging. The 2,487,941-byte scientific result JSON itself matched its pinned SHA. The working-tree evidence and original process captures remained intact.

The correction adds a path-specific `-text` rule for the R6 raw evidence tree and restages those same evidence bytes. The 25 Git index blobs now match all 25 entries in the existing SHA-256 manifest; manifest SHA-256 is `a150f8634fd0d2e96232fc43a720356b2e416127df2531057d6a1a8090d56fc2`. The commit's blob audit remains the final check. No scientific result, source code, target count or D0 interpretation changes.

## State and limits

The active issue remains [#218](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/218), on `exp/p3-1-r12-cxr-r6-realization-map-cavity`. The original D0 checkpoint and its report remain immutable. The R6 procedure remains active with zero of five target attempts consumed; R6-A–F and geometry gates are still pending. Evidence class is archival integrity verification around the previously recorded L4 local runtime evidence; this is not an independent source review or owner GUI result. No production adoption, merge, release or F2-G1 change is claimed.
