# F2 G1 blocked preflight evidence manifes

Base reviewed commit: 9e9915e6eb15bcb20cc2f5a1c990791e2a822b90
Production SourceRoot commit: 8b70a70934445bee660c1e53e71b2e7b20a6191f
Report scope: read-only preflight; upgrade not launched; UAC attempts 0.

| Path | SHA-256 | Purpose |
|---|---|---|
| UPGRADE_PREFLIGHT_BLOCKED.md | 4ceb3c420c8194a6f5b92545275708a725f8db6ff790ac09f748448c9c20f231 | Sanitized gate results, blocker, and non-consumption status |
| results.json | f53f2ebf44511022cf19a1ca65869a20ef8893546d188028f9f6f3d186f9c69f | Machine-readable preflight and execution disposition |

Validation: results.json parses; sensitive-pattern scan found no SIDs or raw SDDL; no code, ACL, VM, G:, installation or transaction changes were made. The final Git commit independently anchors both files. This manifest intentionally does not include its own hash; retrieve and hash it at the immutable commit.
