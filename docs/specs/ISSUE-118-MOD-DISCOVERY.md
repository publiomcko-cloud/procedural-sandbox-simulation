# Issue #118 — Optional User Mod Discovery Contract

Status: implementation candidate on `fix/issue-118-mod-discovery-initialization`; independent source review and owner GUI retest are pending. This document records the proposed behavior, not an accepted product-wide policy.

## Problem

The runtime discovers declarative packages in `res://mods/first-party` and `user://mods`. Discovery previously treated every immediate child directory as a package. A residual or user-created folder without `manifest.json` therefore returned `missing_manifest` and blocked registry creation and procedural-object initialization, even when required first-party packages were valid.

The defect was reproduced before the correction using an isolated Godot user-data profile and a synthetic child folder. The actual owner profile and saved worlds were not accessed.

## Contract

- Package roots remain explicit and allowlisted. Normal runtime uses the required repository first-party root and the optional exact `user://mods` root.
- The loader itself validates optional-root eligibility; callers cannot broaden the policy by passing another otherwise-authorized root in `optional_roots`. After slash/case/path normalization appropriate to the platform, the only eligible optional root must equal the exact `user://mods` root. A descendant, neighboring string prefix, required first-party root or example-package root is rejected before package enumeration. The optional root must also occur in the supplied `roots` array.
- Discovery inspects immediate child directories only. It does not recurse into folders.
- Only a child directory in the exact optional `user://mods` root that has no `manifest.json` is classified as `IGNORED_NOT_A_PACKAGE`. It is counted and appears in a deterministic diagnostic; its contents are not loaded.
- A `manifest.json` that exists but is malformed, a package with invalid content/schema/pins/dependencies, a duplicate package ID, an unavailable required root, or a path/reparse safety violation remains fatal. No catch-all suppression is used.
- Missing manifests in required roots remain fatal. Optionality is not inferred for arbitrary roots; only the exact `user://mods` path is recognized by the runtime helper.
- Enumeration is deterministic and non-recursive. Root authorization and existing package content/path validation remain in force.
- No manifest is generated. No user directory is deleted, moved, renamed, or rewritten. No package scripts are executed.
- Successful discovery returns accepted package and ignored-folder counts plus diagnostics. The HUD shows a short warning without absolute personal paths when optional folders are ignored. Failure summaries are actionable and sanitized.
- Fallback to the repository example package occurs only after configured package discovery succeeds and the optional example package is absent. A declared but invalid user package blocks before fallback.

## Validation evidence and limits

Issue #118 initial correction source: `f8edbff0a7bab3ea733b4903611a9e6a5904613c`. Bounded optional-root hardening source: `f0164b140009bb797951aa4085bb36001889bc57`, parent `6280fac4b7554ba24b880790c3991c01aaa43851`. Tests cover canonical root eligibility, attempted downgrade of first-party/example/authorized descendant roots, prefix/descendant rejection, empty/residual folders, nested package non-discovery, deterministic root ordering, malformed manifest/content, missing dependency, required-root manifest failure, duplicate/unsafe paths, reparse rejection, optional-folder warning, initialization, object publication and existing F6–F9 regressions.

Godot 4.7.2 full headless validation for the hardened source reported 18,047 assertions, 0 failures. Headless tests do not establish visual quality or the owner's real GUI/save behavior. Three `Target and up vectors are colinear` warnings occurred in test camera setup; no parser, script, or test errors were reported. Exact logs and isolated-profile details are in [R1 addendum checkpoint](../checkpoints/2026-10-25-ISSUE-118-OPTIONAL-ROOT-API-HARDENING.md).

The implementation does not inspect or repair arbitrary user-folder contents, prove that a folder was intentionally abandoned, migrate persisted entity state, or establish GUI acceptance. Ignoring a folder without a manifest is the explicit classification rule; the warning is the user's notice. Independent review must verify canonical root eligibility, diagnostics, fallback behavior and preservation of strict validation.
