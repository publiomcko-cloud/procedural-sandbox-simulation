# P3.1 R10-A Raw Archive Hash Erratum

Date: 2026-10-29
Event: corrected a transcribed SHA-256 value; no experiment or archive bytes changed.
Repository: publiomcko-cloud/procedural-sandbox-simulation
Draft PR: https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/207
PR head when checked: 5cddb9410614c46d9cdb5d904f5e620ea523178c

## Correction

The previously published RESULTS.md and PR publication receipt contain a transcription error in the raw ZIP SHA-256: one c was omitted from the ...e8fdcf8bc7ac... sequence. The correct physical SHA-256 of docs/reports/P3-1-R10-A-CAMPAIGN/evidence/R10-A-raw-evidence.zip is:

ac630bd3b6b8be3494b33367e1896030de541a88ae16e8fdcf8bc7ac83ac58e6

The verified archive size is 7,305,964 bytes. The raw-file inventory SHA-256 remains 28102a70c69b2a6e098a857d49896e3e8a44d2ba007f91e8a30abfdb3bd65ba4; the source inventory SHA-256 remains c8a38f5d3bf08063d014d839a74729c64d7dc3d4f80f9d9e5e437537a435491e.

The archive was not rebuilt or modified. The prior report/checkpoint wording is retained as historical publication text; this erratum supersedes only the ZIP hash value. No geometry result, campaign classification, or validation boundary changes. All five F2-G1 holds remain.
