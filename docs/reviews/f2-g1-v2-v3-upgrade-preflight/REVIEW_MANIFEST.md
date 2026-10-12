# F2 G1 blocked preflight evidence manifest

Base reviewed commit: 9e9915e6eb15bcb20cc2f5a1c990791e2a822b90
Production SourceRoot commit: 8b70a70934445bee660c1e53e71b2e7b20a6191f
Report scope: read-only preflight; upgrade not launched; UAC attempts 0.

| Path | SHA-256 | Purpose |
|---|---|---|
| UPGRADE_PREFLIGHT_BLOCKED.md | 294013296f9f28066569c304aa305ead96844d58f03b06cb604bc264b6c4d21b | Sanitized gate results, blocker, and non-consumption status |
| results.json | e474b4151f4deedb8abc65100d7b7b4a069726689e284d53b3a3acd9ced043a3 | Machine-readable preflight and execution disposition |

Validation: results.json parses; sensitive-pattern scan found no SIDs or raw SDDL; no code, ACL, VM, G:, installation or transaction changes were made. The final Git commit independently anchors both files. This manifest intentionally does not include its own hash; retrieve and hash it at the immutable commit.
