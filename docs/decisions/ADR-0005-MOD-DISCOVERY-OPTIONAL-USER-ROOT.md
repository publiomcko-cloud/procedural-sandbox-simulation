# ADR-0005 — Optional user package root classification

- Status: **PROPOSED — pending independent review and owner GUI retest**
- Date: 2026-10-25
- Issue: [#118](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/118)
- Candidate implementation: `f8edbff0a7bab3ea733b4903611a9e6a5904613c`

## Context

Package discovery previously interpreted every immediate directory in every authorized root as a package. A harmless residual folder in `user://mods` without a manifest prevented required packages and procedural objects from initializing.

## Decision proposed

Treat only the exact `user://mods` root as optional. Within that root, an immediate child directory with no `manifest.json` is reported as an ignored undeclared folder and discovery continues. Required roots remain strict. A present but invalid manifest or content, dependency/identity failure, missing required root, or path safety failure remains fatal. Discovery stays deterministic, bounded and non-recursive.

The loader reports counts and structured diagnostics. The HUD presents a brief sanitized warning, without exposing absolute user paths. The loader does not create package manifests or mutate user folders.

## Consequences

This prevents unrelated folders and test residue from disabling installed packages, while preserving fail-closed treatment for directories that declare themselves as packages and for all safety violations. A user-created directory without a manifest is deliberately not treated as a package; adding a package requires a valid manifest.

## Alternatives considered

1. Treat every child folder as a required package: rejected because harmless residue blocks all objects.
2. Ignore every package discovery error: rejected because it would hide malformed declared packages and security/integrity failures.
3. Recursively search for manifests: rejected because it expands discovery scope and makes identity/order behavior less clear.

## Acceptance boundary

This ADR remains proposed until independent source review and owner GUI retest. It does not authorize a merge, migration, inspection of owner saves, or changes to F2-G1. See the [Issue #118 discovery contract](../specs/ISSUE-118-MOD-DISCOVERY.md).
