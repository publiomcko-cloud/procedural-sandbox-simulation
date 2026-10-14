# F2 G1 manual WMI observation receipt

## Disposition

**Same-token WMI command-line gate: CLOSED — based on human-supplied observation.** The supplied successful summary is internally consistent with the pinned PR #70 script's success path. Codex did not execute or reproduce this observation. This receipt records the human report and source comparison; it is not independent host-runtime evidence.

Capture timestamp and the original complete JSON/stdout transcript were not supplied. The original raw command line, encoded payload, requester SID, exception data, and full image path are not reproduced here.

## Immutable source references

- PR #70 source HEAD: `dc9d1fbd56553598d27b9c7722bcf7ebdf17d65a`.
- PR #69 reviewed HEAD: `56a34d7899ba31b0d3fe6d3185435bc182ac453f`.
- Runtime implementation commit: `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`.
- Observation script physical Windows checkout SHA-256: `4fe30974cdab3b1ca4a87aaf26591c0192f5fa0c4423b23b155c5bab7a1abc4d`.
- Operator procedure physical Windows checkout SHA-256: `163c0d8ea5df030d83926e4a962199db146a6f1d46363801f287e19335a0757c`.

The published script and operator procedure were preserved byte-for-byte for this receipt.

## Human-reported result

| Field | Reported value |
|---|---|
| Schema / outcome / stage / error | `f2-g1-manual-wmi-observation-v1` / `PASS` / `COMPLETE` / `NONE` |
| PowerShell | `5.1.22621.6133` |
| Requester PID / token class | `37092` / `STANDARD` |
| Child PID / same requester owner | `24532` / `true` |
| Generated / observed command-line length | `3583` / `3583` characters |
| Observed command-line SHA-256 | `99b1510e432c206c0b8494a767884426cf89da29e756046d3430392fb62bd104` |
| Observed encoded-payload SHA-256 | `e8b8ca701772b6ebb3ba1e449572ef53015b2a9c66aa954849484b573f6aafc0` |
| Exact command-line / encoded-payload match | `true` / `true` |
| Production validator | `true` |
| Child exit / timeout | `0` / `false` |
| Temporary root ID / cleanup | `abc1ff79f07144378b6aca1a6da2b04d` / `COMPLETE` |
| Operator-observed script exit | `0` |

## Consistency review against the pinned script

- The schema and field names match the script's result object. `COMPLETE` is assigned only after a `PASS` result and complete cleanup.
- A reported `PASS` is consistent with the required observed PID/image/command-line checks, exact full-line and encoded-payload matches, the production validator acceptance, the same-requester-owner check, natural child exit code `0`, and cleanup. The summary reports those gates as passed.
- Both command-line lengths are equal and `3583` is below the builder's `3600`-character cap.
- The two reported PIDs are distinct positive integers. The temporary root ID is a 32-character lowercase hexadecimal GUID-N value.
- Both reported SHA-256 values have the expected 64-character lowercase hexadecimal form. The command-line digest in the script is SHA-256 over UTF-16LE command-line bytes. The encoded-payload digest is SHA-256 over bytes obtained by Base64-decoding the encoded command; it is not the hash of the Base64 text.
- The reported PowerShell version satisfies the script's Windows PowerShell 5.1 version gate.
- The summary omits `ChildImagePath`, the script-reported review/runtime commit and module hash fields, and the redacted command-line field. The pinned script checks the image path and embeds those identities before it can report `PASS`, but the omitted values cannot be independently compared from this summary. No values have been inferred or added.

A non-elevated in-memory consistency check of the supplied summary passed **12/12** checks: schema/disposition, PS 5.1 version, standard requester, distinct positive PIDs and owner match, equal bounded command lengths, SHA-256 formats, both command comparisons, production validator result, natural exit/no timeout, temporary GUID/cleanup, and operator exit. This check validated reported values only; it did not run the observation script or query WMI.

## Scope and evidentiary limit

This closes only the **same-token ShellExecute/WMI command-line observation gate** on the basis of the operator's report. It supports that a harmless temporary child command line was observed and accepted by the production validator in the reported Windows PowerShell 5.1 session. It does not prove an elevated token, UAC behavior, medium-to-high integrity named-pipe connectivity, alternate-account behavior, or the historical elevated failure's cause.

The published Git core executable is pinned by path and SHA in PR #69. Its dependent DLL provenance and non-administrator modification exposure remain unverified. No live process, WMI query, UAC action, protected write, ACL query, VM operation, G: access, or native F2 workload was performed by Codex for this receipt.

The source-only review of this report can validate the supplied values against the script contract; it cannot authenticate the human execution or recreate the missing original transcript.