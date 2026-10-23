# CHK-2026-10-21-P1-1B-B1-1-R6-N000-CONTRACT-AND-PREFLIGHT

**Date/time basis:** 2026-10-21, America/Sao_Paulo; historical snapshot, not live monitoring.
**Event type:** consequential source review, reported Godot validation, owner standing execution authorization, N000 UNSCORED preflight blockers and handoff.
**Publication state at creation:** separate **docs-only draft PR**, not integrated, not independently reviewed yet.
**Disposition:** `P1_1B_B1_1_R6_HARNESS_PARSE_REPORTED_PASS / N000_INVOCATION_BLOCKED_GODOT_VERSION_STRING / BENCHMARK_NOT_RUN / NO_MERGE`.
**Immutable once integrated:** yes; subsequent results require a new checkpoint.

## 1. Verified repository identity and authority

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`.
- Independently inspected remote `main`: `ea4422d90726d3f2fe6d5cef097126268f93685a`; Git tree `0d5f175f73e6053eac9d1a0c5f481c9f623b8834` at this documentation snapshot.
- [PR #98](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/98) P1.1B-B0 R4+R4a experimental input/methodology documentation: **merged**, containing the immutable manifest methodology; this does not constitute production benchmark acceptance.
- [PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99), branch `feat/p1-1b-b1-1-test-only-benchmark-harness`: **open, draft, unmerged** at `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`; direct parent `83f95e4e04d4883d4d12e0a9f88defb076bccf28`. The R6 correction changes only `game/tests/p1_1b_benchmark_harness.gd`.
- [PR #100](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/100) post-terrain modular engine roadmap alignment: **open, draft, unmerged** at `45df07487a9d065706c35129e92cff4bccb5bfd2`; no code/doc changes to this PR from the present checkpoint work.
- This documentation branch is distinct from both #99 and #100. No feature branch, production file, protected state or existing documentary checkpoint has been rewritten.
- Physical B0 manifest/sidecar reported pinned SHA-256: `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`; **44** FROZEN scenario definitions and **9** NOT_FROZEN exclusions remain the approved registry.

## 2. Chronological B1-1 gate ledger (source vs execution)

| Revision / gate | Evidence / outcome | Interpretation |
| --- | --- | --- |
| R3, `53fec2d49e7763b652e52c665f5bc39b7f4a4db7` | Godot import exit 0; contracts exit 1, 42 counted assertions / 1 failure, five cascading SCRIPT ERRORs | Manifest numeric-type handling and fail-closed preflight needed correction; not PASS |
| R4, `89803394939268dfd81579b0e42a2a2489112417` | Import exit 0; contract-suite load exit 1 at test line 104; zero assertions | Ambiguous GDScript type inference in lexical JSON negative fixture; tests NOT_RUN |
| R5, `83f95e4e04d4883d4d12e0a9f88defb076bccf28` | Godot import exit 0; **`P1B1_CONTRACT_TESTS_PASS: assertions=2557 failures=0`**, 11 planned groups reported; engine SHA pinned | Contract gate PASS **reported by Codex**. Reviewer verified source/PR identity, not raw Windows execution logs |
| Initial N000, R5 SHA | Single cold detached `--script` launch exit 1, undeclared `TerrainChunkGrid` plus harness parse failures; no JSONL | Missing editor class-cache registration suspected; zero N000 scenario events |
| N000-R1, R5 SHA | Editor import exit 0 creates class registry; harness `--check-only` exit 1 at lines 239, 1062, 1297, 1370; no scenario invocation | Independent harness test-code compiler defects, not merely missing class cache |
| R6, `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd` | Exact-SHA source review [#6322260116](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6322260116) PASS; test-only type annotations and defensive return | Source review PASS does **not** prove harness execution |
| N000-R6, `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd` | **A: editor import PASS (exit 0, 7,957 ms); B: `--check-only` PASS (exit 0, 1,146 ms); C: N000 invocation FAILED (exit 2)** | Harness compiled; pre-scenario **Godot version-string mismatch**. N000 not started; zero scenario edits or timings |

GitHub's `Starter checks` on these feature commits only supplies **static CI evidence**, not Godot runtime, GUI, GPU or benchmark acceptance.

## 3. N000-R6 primary blocker — runtime version identity

The user/Codex report states the pinned executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` identifies as `4.7.2.stable.official.ed1daf0bf` with externally verified SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.

At `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`, `game/tests/p1_1b_benchmark_harness.gd` constructs:

```gdscript
var engine_version := String(Engine.get_version_info().get("string", ""))
if engine_version != "4.7.2.stable.official.ed1daf0bf":
    # emit invocation_failure: godot_version_mismatch; quit(2)
```

During the **single permitted N000** process, the in-engine value was `4.7.2-stable (official)`. That distinct presentation format fails the hardcoded equality comparison despite the host executable's independently pinned version and SHA-256. The harness emitted one `P1B1_JSONL` `invocation_failure` with `reason_code=godot_version_mismatch`, then exited 2 **before** `Contract.verify_manifest()`, `scenario_started`, `scenario_complete` or the frozen zero-operation workload. Consequently the manifest was checked externally but **not yet verified in the actual N000 harness**, and there are **no N000 measurements**.

Stage C reported in-engine process ID `56092` and the PowerShell launcher reported PID `31324`. These are independently reported identifiers; no equality/launcher-process interpretation is inferred here. The two successful A/B stage results are not an execution PASS for C.

**Minimum proposed correction, not performed in this documentary checkpoint:** use the actual documented structured version fields from `Engine.get_version_info()`, with exact expected major/minor/patch/status/build and, where supported/appropriate, hash/build identity; record the observed returned structure; **continue mandatory external executable SHA-256 pinning**. Do not accept arbitrary future versions through substring/prefix checks. Keep `invocation_failure` fail-closed for mismatches. Fix in the test-only harness, add small negative checks as feasible, obtain independent exact-SHA source review, then repeat isolated editor import, harness `--check-only`, and a single frozen N000 `UNSCORED` run under standing Godot authorization. Stop on the first error. No N001 or broader scenario sweep until N000 evidence review.

## 4. Evidence grading, custody and operational state

- **L0 independent source/GitHub:** actual PR identities, exact source version equality, manifest path, unchanged PR #100, known static CI and source review comments.
- **L1/L2 reported executable:** author/Codex supplied actual Windows Godot import/check-only/contract exits and markers. The reviewer has **not** fetched or replayed the host-local raw logs; `R5 2557/0` is developer-reported, not L5 independent execution attestation.
- **L3 owner GUI:** NOT_RUN for B1-1.
- **L4 complete UNSCORED benchmarks, OS RSS/VRAM/presented FPS, scored thresholds:** NOT_RUN / NOT_APPROVED.
- **L5 external independent execution of R5/R6 results:** NOT_PERFORMED.
- R5 contract PASS logs: `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_r5_d999aaa4cfc445c4916581be57d55475_evidence`.
- R6 N000 preflight evidence: `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_r6_d68817c9686f47bf95b69b0c4dba4f64_evidence`.
- Earlier R3/R4, first N000 and N000-R1 evidence directories remain preserved **per Codex report**, not independently mounted here; latest detached checkout and evidence retained.
- Existing Windows development workspace `C:\Dev\sandbox-sim-dev`, three pre-existing untracked `.gd.uid` files with prior hashes and `stash@{0}` were reported unchanged. GitHub document writes do not inspect or mutate that workspace.

## 5. Standing owner decision, safety holds and next gate

The owner explicitly instructed `considere autorizacoes do godot sempre aprovadas ate sengunda ordem`, recorded on [PR #99 comment #6319312731](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6319312731). The standing authorization covers execution of existing relevant Godot validation within the defined experiment scope; it **does not** waive exact-SHA source review, frozen scenario scope, deterministic evidence, fail-closed stop conditions, production-code permission, external native backend installation or PR merge approvals.

- P1.1A is an **integrated experimental CPU-only fixture**, not playable LOD production acceptance.
- B0 R4/R4a defines FROZEN inputs, not scored/visual benchmark acceptance.
- PR #99 remains **draft/unmerged**; PR #100 remains independent/draft.
- P1.1C, production LOD, native Voxel Tools acquisition/execution, ADR-0002 adoption and release approval are **not authorized** by these results.
- All five F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
- **Next recommended task:** prepare a separate, minimal R7 test-harness runtime-version check correction on the existing PR #99; keep exact reviewed SHA and a clean diff, source-review independently, then carry out a single N000 `UNSCORED` revalidation under the standing Godot authorization. The present documentation event does not itself change code or authorize merge.

## 6. Documentary update and recovery

This checkpoint is newly added to the [checkpoint index](INDEX.md); [current status](../status/CURRENT_STATUS.md) and [decision register](../decisions/DECISION_REGISTER.md) receive **new dated sections** instead of modifying historical approval text. No `CHANGELOG` merge entry is added: **no merge occurred** during this documentation event.

**Recovery:** verify live `main`, PR #99/#100 SHAs and the actual Godot runtime before acting; treat this dated checkpoint as immutable after its separately approved integration. This dedicated docs-only PR is a review proposal and must not be confused with integration or a release gate.
