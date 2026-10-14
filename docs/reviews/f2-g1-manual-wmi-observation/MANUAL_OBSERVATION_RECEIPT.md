# F2 G1 manual WMI observation receipt

## Disposition

**Same-token WMI command-line gate: CLOSED — based on the operator-reported observation.** The operator supplied the complete JSON result and terminal exit result in the ChatGPT conversation. The earlier Codex handoff was abbreviated and omitted fields that had been supplied; this receipt now records those omitted values. The capture timestamp remains **UNKNOWN**. Codex did not execute or independently authenticate the host observation.

The unredacted command line, encoded payload, requester SID, and exception data remain withheld. The script-generated redacted command line and non-sensitive child image path are included below.

## Immutable source references

- PR #70 source HEAD: `dc9d1fbd56553598d27b9c7722bcf7ebdf17d65a`.
- PR #69 reviewed HEAD: `56a34d7899ba31b0d3fe6d3185435bc182ac453f`.
- Runtime implementation commit: `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`.
- Observation script physical Windows checkout SHA-256: `4fe30974cdab3b1ca4a87aaf26591c0192f5fa0c4423b23b155c5bab7a1abc4d`.
- Operator procedure physical Windows checkout SHA-256: `163c0d8ea5df030d83926e4a962199db146a6f1d46363801f287e19335a0757c`.

The published script and operator procedure were preserved byte-for-byte for this receipt.

## Complete operator-reported result

The following is the complete operator-reported JSON field/value set supplied in the conversation, transcribed here for independent review. It is not a Codex-captured record.

```json
{
  "Schema": "f2-g1-manual-wmi-observation-v1",
  "Outcome": "PASS",
  "Stage": "COMPLETE",
  "ErrorCode": "NONE",
  "ReviewCommit": "56a34d7899ba31b0d3fe6d3185435bc182ac453f",
  "RuntimeCommit": "8c14cf97c9446e11b8afbd64196c3f4558d4c3c9",
  "RuntimeModuleSha256": "06f117c6be29e3e150149087cb19323e83df20601b8d134f0bb02ec7335867d2",
  "PowerShellVersion": "5.1.22621.6133",
  "RequesterPid": 37092,
  "RequesterTokenClass": "STANDARD",
  "ChildPid": 24532,
  "ChildImagePath": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
  "ChildOwnerMatchesRequester": true,
  "GeneratedCommandLineLength": 3583,
  "ObservedCommandLineLength": 3583,
  "ObservedCommandLineSha256": "99b1510e432c206c0b8494a767884426cf89da29e756046d3430392fb62bd104",
  "ObservedCommandLineRedacted": "\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand <redacted;chars=3448;sha256=e8b8ca701772b6ebb3ba1e449572ef53015b2a9c66aa954849484b573f6aafc0>",
  "ObservedEncodedPayloadSha256": "e8b8ca701772b6ebb3ba1e449572ef53015b2a9c66aa954849484b573f6aafc0",
  "ExactCommandLineMatch": true,
  "EncodedPayloadMatch": true,
  "ProductionValidatorPass": true,
  "ChildExitCode": 0,
  "TimedOut": false,
  "TemporaryRootId": "abc1ff79f07144378b6aca1a6da2b04d",
  "CleanupOutcome": "COMPLETE"
}
```

The operator separately reported terminal exit code **0** for the observation script. This terminal result is reported evidence, not independently captured by Codex.

## Consistency review against the pinned script

- The schema and field names match the script's result object. `COMPLETE` is assigned only after a `PASS` result and complete cleanup.
- A reported `PASS` is consistent with the required observed PID/image/command-line checks, exact full-line and encoded-payload matches, the production validator acceptance, the same-requester-owner check, natural child exit code `0`, and cleanup. The summary reports those gates as passed.
- Both command-line lengths are equal and `3583` is below the builder's `3600`-character cap.
- The two reported PIDs are distinct positive integers. The temporary root ID is a 32-character lowercase hexadecimal GUID-N value.
- Both reported SHA-256 values have the expected 64-character lowercase hexadecimal form. The command-line digest in the script is SHA-256 over UTF-16LE command-line bytes. The encoded-payload digest is SHA-256 over bytes obtained by Base64-decoding the encoded command; it is not the hash of the Base64 text.
- The reported PowerShell version satisfies the script's Windows PowerShell 5.1 version gate.
- The restored `ChildImagePath`, `ReviewCommit`, `RuntimeCommit`, and `RuntimeModuleSha256` match the pinned script's expected image path and embedded identity constants. The restored redacted command-line value matches the script's redaction format and reported payload length/hash. These are source/value consistency checks; they do not authenticate the host execution.

The previously recorded non-elevated in-memory consistency check passed **12/12** checks over the summary fields: schema/disposition, PS 5.1 version, standard requester, distinct positive PIDs and owner match, equal bounded command lengths, SHA-256 formats, both command comparisons, production validator result, natural exit/no timeout, temporary GUID/cleanup, and operator exit. A separate review of the restored five fields (child image, review commit, runtime commit, module hash, and redacted command line) matches the pinned script constants and output construction. These checks validate reported values only; they did not run the observation script or query WMI.

## Scope and evidentiary limit

This closes only the **same-token ShellExecute/WMI command-line observation gate** on the basis of the operator's report. It supports that a harmless temporary child command line was observed and accepted by the production validator in the reported Windows PowerShell 5.1 session. It does not prove an elevated token, UAC behavior, medium-to-high integrity named-pipe connectivity, alternate-account behavior, or the historical elevated failure's cause.

The [earlier immutable host-readiness assessment](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/2c19f161740b3efb1636134cd7f62b5c58da45e4/docs/reviews/f2-g1-host-readiness/FINAL_NON_ELEVATED_HOST_READINESS.md) recorded SHA-256 values for four unsigned Git DLLs and inspected their paths, reparse status, and applicable standard-user allow ACEs. It found no trustworthy local package/catalog evidence for those DLLs. Their independently authenticated publisher/package provenance and complete effective-access assurance remain **UNKNOWN**; the earlier read-only ACE review was not a kernel effective-access evaluation. No live process, WMI query, UAC action, protected write, ACL query, VM operation, G: access, or native F2 workload was performed by Codex for this receipt.

The source-only review can compare the operator-supplied values with the pinned script contract, but cannot independently authenticate the human execution. The complete JSON and terminal result were supplied in conversation; Codex's earlier handoff, rather than the operator's submission, was abbreviated.
