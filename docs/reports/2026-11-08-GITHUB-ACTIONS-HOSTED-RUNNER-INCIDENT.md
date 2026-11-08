# 2026-11-08 — GitHub Actions hosted-runner pre-start failure

## Verdict

`ACTIONS_HOSTED_RUNNER_BLOCKED_BEFORE_STEPS / BILLING_OR_USAGE_BUDGET_HIGH_CONFIDENCE / REPO_TRIGGER_AMPLIFICATION_CONFIRMED`

This report records the investigation of repository workflows that began completing with `conclusion=failure`, `steps=null`, and no job logs.

## Scope

Repository:

`publiomcko-cloud/procedural-sandbox-simulation`

The repository is private and uses GitHub-hosted runners.

## Evidence

### Jobs stop before runner setup

A successful Starter checks run immediately before the incident contained:

1. `Set up job`;
2. `actions/checkout@v4`;
3. `Validate expected files`;
4. `Complete job`.

After the transition, equivalent jobs report:

- status: `completed`;
- conclusion: `failure`;
- `steps=null`;
- no job logs.

This proves the failure occurs before workflow steps, checkout, Godot download, or project code.

### Transition window

Observed repository evidence:

- PR #240, updated 2026-11-06 17:15 UTC: Starter checks and P2 benchmark still executed successfully.
- PR #241, updated 2026-11-06 17:58 UTC: Starter checks, P2 benchmark, pre-D, D1, D2, D3 and mod-first workflows all completed as failures before steps.

Therefore the repository-wide runner block began between approximately 17:15 and 17:58 UTC on 2026-11-06.

### Not an OS image issue

Isolated diagnostic PR #259 created a workflow whose jobs only print one line.

The three independent hosted runner labels all failed before their first step:

- `ubuntu-latest`: `steps=null`;
- `windows-latest`: `steps=null`;
- `macos-latest`: `steps=null`.

No checkout, third-party action or Godot command was involved.

### Not the current public GitHub Actions incident state

GitHub Status reports Actions operational on 2026-11-08. Historical Actions incidents occurred on 2026-11-04 through 2026-11-06, but the repository block persists after those incidents were resolved.

### Billing/usage context

The repository is private. GitHub-hosted runner usage for private repositories consumes the owner's included/billable Actions compute.

GitHub documentation states that exhausted hard Actions budgets can block use of all GitHub-hosted runners until the budget is increased or the next billing cycle starts.

The GitHub connector available to this project does not expose personal billing/usage/budget APIs, so the exact billing ledger cannot be read or changed programmatically here.

## Trigger amplification

The repository accumulated many phase-specific workflows. Several remained automatic after their phase was complete.

Before mitigation, one PR could trigger:

- Starter checks;
- P2 GDScript allocation benchmark;
- mod-first hardening;
- multiple Issue #108 phase/performance workflows;
- the current phase workflow.

Each heavy workflow independently downloaded Godot 4.7.2 and imported the project.

The P2 benchmark had an unrestricted `pull_request -> main` trigger, so every PR to main launched that expensive benchmark.

Starter checks used `on: [push, pull_request]`, causing duplicate branch-push and PR execution for normal feature work.

This trigger amplification is a credible mechanism for exhausting a private-repository Actions allowance/budget.

## Repository mitigation

Branch `fix/actions-quota-hardening` changes CI policy without deleting historical workflows.

### Historical Issue #108 workflows

Automatic `pull_request` triggers are removed from completed Issue #108 workflows.

Their original branch-specific `push` trigger is retained and `workflow_dispatch` is available, so the historical qualification remains reproducible on demand.

### M4/mod-first workflows

Automatic PR triggers are retired after M4 integration. Historical branch/manual execution remains available.

### P2 benchmark

The unrestricted automatic PR trigger is removed. The exact benchmark remains available through its historical branch and manual dispatch.

### Starter checks

Starter checks now run:

- on pull requests targeting `main`;
- on pushes to `main`.

They no longer run on every feature-branch push in addition to the PR event.

A concurrency group cancels superseded runs for the same PR/ref.

### Current P4 workflow

P4.0A remains the current automatic qualification workflow for relevant simulation/runtime paths.

It now:

- runs automatically only for PRs to `main`;
- supports manual dispatch;
- cancels superseded runs for the same PR/ref.

## Required account-side action

Repository changes cannot unblock an already exhausted or hard-stopped Actions budget.

The account owner must inspect GitHub billing:

`Settings -> Billing & licensing -> Budgets and alerts / Usage`

For Actions, verify:

- included usage remaining;
- any Actions/product/repository budget at 100%;
- whether `Stop usage when budget limit is reached` is enabled;
- payment method / usage-based billing availability.

If the limit is exhausted, increase/soften the applicable Actions budget or wait for the billing-cycle reset.

After account-side unblocking, rerun the minimal diagnostic or current P4 workflow. Successful appearance of `Set up job` is the first proof that runner allocation is restored.

## Expected post-mitigation CI shape

A normal P4 PR should ordinarily launch:

1. Starter checks;
2. current P4 qualification when relevant paths change.

Historical Issue #108/M4/P2 benchmark workflows should not launch automatically.

This reduces hosted-runner fan-out from as many as 7–11 jobs on one PR to approximately 1–2 current jobs.
