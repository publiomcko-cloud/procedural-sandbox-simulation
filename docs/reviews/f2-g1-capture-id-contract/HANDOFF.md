# Developer handoff

Status: READY_FOR_INDEPENDENT_REVIEW
Ticket / acceptance criteria: Issue #48 capture identity correction; independent finding `5483606279` / `6109879757`.
Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `origin`.
Worktree / branch: `C:\Dev\f2-g1-capture-id-contract` / `fix/f2-baseline-capture-identity-issue48`.
Base SHA: `2c967661163fc157b638fa4f76da86c48aa57ff2` (reviewed PR #50 source).
Candidate production source SHA: `54b1d0c7a9865d710c19b59cd38c0da670a12536`; final review-package HEAD is the immutable PR #53 HEAD.
Parent SHA: `a0edf58a75c4ff947defc05acf723a1be0f1c34c` for the production correction.
Changed paths: see `REVIEW_MANIFEST.md` at the candidate commit.
Implementation summary: Preserve and separately validate mailbox directory ID `ecb6deeb424e40feb5354d18908986df` and payload CaptureId `489e7fec-0300-467c-bfbd-a46fb8cf7211` in the corroboration loader, runtime release contract, protected installer and synthetic tests. Bump the runtime release schema to v2 so the two-ID contract is explicit. Propagate source-package and installer/bootstrap pins.
Architectural impact: Consumer-side identity correction only. Mailbox directory and exact four-ACE verification remain keyed by mailbox ID. Baseline bytes and producer are unchanged.
Dependencies added / licenses: None.
Tests executed (exact commands): See `TEST_EVIDENCE.md` and complete captured output logs. Windows PowerShell 5.1 suites: Corroboration 118 assertions, Runtime 29, Installer 31; all zero failures and exit 0. Parser: 12 files, 0 errors. Windows CI passed on the source-bearing PR commit; run `38147352219` is linked in TEST_EVIDENCE.md.
Results / assertion counts: See above; `git diff --check` passed locally and in Windows GitHub CI.
Tests not executed: No UAC, protected install, live icacls/ACL/token/VM/Hyper-V operations, VM start, G: write, or native workload.
Failure/recovery cases: Wrong mailbox ID, wrong payload ID, wrong embedded CaptureId with recomputed inner digests, changed evidence hashes, missing/malformed/duplicate baseline data all fail closed. Legacy runtime manifest schema is rejected.
Benchmark machine and metrics: Not applicable.
Known limitations: This source review does not establish live ACL acceptance. Protected install authorization must be fresh because executable bytes changed. The actual live icacls corroboration remains a separate owner-authorized step after review.
Visual reproduction steps: Not applicable.
Rollback instructions: Keep PR draft/unmerged; revert only the dedicated correction commit(s) after review if rejected. No live state was changed.
Reviewer focus / open questions: Verify that independent IDs are each pinned and consumed consistently through baseline loader, installer, runtime release manifest and source-package pins; review v2 schema transition and exact installation package hashes.
