# Source and incident provenance

## Immutable lineage

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- PR #67 approved base HEAD: `d9a0ffa18e54716dbc8dac577ce2c2979e961a9a`
- PR #67 parent: `bb888d0755ebd3cfc358ad3f7ccdbbcbb4b65913`
- Probe implementation commit: `31103765aa494faadf38d67d0dec34dbc5f94d30`
- Probe canonical-byte pin correction: `fcea89928d3c24b0714c274ca6007522cee02fa2`
- Correction parent: `31103765aa494faadf38d67d0dec34dbc5f94d30`
- SID-free synthetic fixture correction: `dfc715b7a758a49876c5d27d2e7339c2b8ac5313`
- Fixture correction parent: `fcea89928d3c24b0714c274ca6007522cee02fa2`
- Historical production commit: `396c44965c90c08292ad2835f8317e81b6b9daaf`
- Historical production parent: `f58b7fdfaf71e212213d559480e1913ae6c210f8`
- Historical candidate checkout: `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`
- New probe branch: `feat/f2-g1-accelerated-diagnostic-probe-issue48`

Verified lineage: historical production commit is an ancestor of the candidate checkout; the candidate checkout is an ancestor of PR #67's base. The historical production source tree and candidate review checkout are distinct. The probe reads the candidate only from the latter fixed checkout.

## Windows checkout byte pins

| File at pinned commit | Raw SHA-256 | Byte count |
| --- | --- | ---: |
| `396:scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1` | `d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2` | 64379 |
| `396:scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1` | `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9` | 21843 |
| `396:scripts/f2-acl/F2ProtectedRelease.Diagnostics.ps1` | `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7` | 25136 |
| `7f99:docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json` | `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022` | 1431 |

New probe implementation Git-blob-byte SHA-256 (the PS1 Git blobs are LF; their Windows checkout bytes are listed below):

- `scripts/f2-acl/F2HistoricalManifestDiagnostic.psm1`: `4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee` (LF by `.gitattributes`).
- `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1`: `63222f868351e1275681bd992f1b5219e960e736699572a6e05a79842296ad95` (Git blob bytes; Windows checkout is CRLF).
- `scripts/f2-acl/Test-F2HistoricalManifestDiagnostic.ps1`: `2368ffab16f774af9a6858253725d56bffe4f5fc34713adc1aaa51a6d664e4de` (Git blob bytes; Windows checkout is CRLF).

Expected Windows checkout SHA-256 after repository filters:

- `scripts/f2-acl/F2HistoricalManifestDiagnostic.psm1`: `4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee` (15645 bytes; LF).
- `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1`: `a7767f3db327569651577c2f0f2b3271f7dc7301105a614e49dd4d4be99bcf76` (7006 bytes; CRLF).
- `scripts/f2-acl/Test-F2HistoricalManifestDiagnostic.ps1`: `471e747eac32e5c262bb692743f59d55f96b5be102b740581af5065c4443591a` (17896 bytes; CRLF).

Git bytes were materialized with the repository's Windows checkout filter (`core.autocrlf=true`) before SHA-256. Local historical checkout files were independently hashed to the same values. These pins are historical inputs; the new diagnostic module's own hash is listed in `FILE_SHA256_MANIFEST.txt`.

The historical seven-file production package pins and source-pin-manifest pin reproduced by the module are:

| Historical file | SHA-256 |
| --- | --- |
| `F2AclCapture.Protocol.psm1` | `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` |
| `F2AclIcacls.Corroboration.psm1` | `a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b` |
| `F2AclIcacls.Runtime.psm1` | `950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5` |
| `Invoke-F2IcaclsCapture.ps1` | `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0` |
| `Invoke-F2IcaclsProtectedCoordinator.ps1` | `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2` |
| `F2_ICACLS_SOURCE_PINS.json` | `bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7` |
| `Invoke-F2AclReadOnlyCapture.ps1` | `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` |

These are historical source pins embedded in the pinned updater. The probe verifies the updater/launcher/protocol/candidate bytes and parses the candidate; it does not execute the updater or validate any current installed package.

## Incident evidence

Issue #48 [incident comment `6145144520`](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6145144520) records historical elevated PID `43072`, actual child exit `1`, diagnostic stage `CandidateManifestValidation`, and stable code `UPDATE_UNCLASSIFIED_FAILURE`. The internal Stage/ErrorCode was not further localized at the time; the exact root cause is unknown. The original comment's correlation/request values are intentionally not repeated here.

The approved historical child builder contains a call to `Get-F2UpdateManifestObject` followed by a comparison of `ParsedCandidate.ReviewedCommitSha` against the expected production commit. The new test verifies those exact statements from the historical builder. The actual candidate parser/comparison passed locally under standard-token Windows PowerShell 5.1. A synthetic missing-field candidate reproduces a StrictMode property lookup exception, but that malformed fixture is not evidence about the bytes consumed by PID 43072.
