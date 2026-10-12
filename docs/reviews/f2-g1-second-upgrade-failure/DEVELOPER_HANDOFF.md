# Developer handoff — second F2 G1 upgrade failure

- Branch: docs/f2-g1-second-upgrade-failure-review-20261012
- Base / parent: 3dc05f98831924160474bfb5b554b2963d9a137b (PR #63 HEAD)
- Production source reviewed: 03882eedf3104fc33aa0cf503ddef9c9a6bec702
- PR #62: 923c7d39d7fbfe106dea404c386efd4b5844654e, draft/open
- PR #63: 3dc05f98831924160474bfb5b554b2963d9a137b, draft/open
- Paths changed: docs/reviews/f2-g1-second-upgrade-failure/ only

## Rationale

The second elevated attempt returned a validated but non-authoritative CandidateAndSourceValidation / UPDATE_UNCLASSIFIED_FAILURE result and child exit 1. Standard-token execution of the reviewed production read-only functions passed, including source/candidate, parent ACL, installed v2 and retained-baseline checks. The exact elevated failure is not reproducible from the available evidence. This handoff records that finding and proposes a small finite allowlisted diagnostic substage update; it does not modify production code.

## Validation commands and results

- Windows PowerShell 5.1, standard token:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File docs/reviews/f2-g1-second-upgrade-failure/evidence/Test-F2G1SecondFailureReadOnly.ps1
  - Exit code: 0
  - Candidate/source/parent/installed-v2/transaction absence/baseline checks: all PASS.
  - UpdaterEntryPointInvoked=NO, TransactionEntryPointInvoked=NO, UAC=NONE, ProtectedWrites=NONE, LiveIcacls=NOT_RUN, VMHyperVAndG=NOT_QUERIED.
- The first run of the review helper stopped at its own malformed volume-GUID regex and exited 1; it did not change or evaluate protected data past that check. The exact failure log is retained; after a local helper-only correction, the full run exited 0.
- The successful PS5.1 execution parsed the helper and exact-hash-pinned updater. A separate parser sweep is included in the evidence directory.
- git diff --check: recorded after packaging.
- No full product suite or Windows GitHub CI is claimed: production source is unchanged and this PR contains a read-only incident report/helper only.

## Limitations and risks

- Elevated exception type and exact failing statement remain unknown.
- Standard-token success does not prove elevated environment equivalence.
- No UAC, updater transaction, protected mutation, recovery, icacls, VM/Hyper-V/G: query, or native workload occurred.
- Independent source review remains required. No new UAC is authorized by this handoff.

**READY_FOR_INDEPENDENT_REVIEW**
