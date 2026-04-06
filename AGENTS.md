# AGENTS.md

This repository contains the standalone `smelterl` history and working tree,
but the authoritative multi-repository workflow still lives in `grisp_alloy`.

Start here:

1. Read `README.md`.
2. Read `docs/DESIGN.md`.
3. Read `docs/PLANNING.md`.
4. Read `docs/WORKFLOW.md` in a superproject checkout, or use the redirect stub
   at [docs/WORKFLOW.md](docs/WORKFLOW.md) to reach the Alloy workflow
   document in standalone/web view.
5. If this checkout lives inside `grisp_alloy/`, also read the superproject
   `AGENTS.md` because the primary day-to-day development model starts there.

Working model:

- primary development normally starts from the `grisp_alloy` root, even when
  the active implementation task is Smelterl-owned,
- when `smelterl/` is checked out inside `grisp_alloy`, daily development still
  starts from the `grisp_alloy` root,
- Smelterl-owned work is tracked in `smelterl/docs/PLANNING.md`,
- if a Smelterl task also requires substantive Alloy-side changes, keep a
  linked `grisp_alloy` follow-up task and commit the Smelterl repository first,
- if the only later Alloy-side change is a submodule-pointer sync, that sync
  may be deferred and batched until development returns to `grisp_alloy`,
- when `smelterl` is checked out on its own, the same Smelterl-local planning,
  history, changelog, and commit-message rules still apply here, but the agent
  must explicitly call out any later `grisp_alloy` follow-up that would be
  required to synchronize the larger system.

Rules:

- keep Smelterl-specific implementation, tests, planning, and history here,
- keep Alloy orchestration, shared workflow, and Alloy-owned design docs in the
  `grisp_alloy` repository,
- when a task depends on Alloy-owned design documents, follow the local/external
  links provided by the redirect stubs under `docs/`.
- do not treat a cross-repository request as one unowned task; use linked
  repo-local tasks for substantive changes in both repositories and keep only
  the currently edited repository task `[IN_PROGRESS]`.
- do not create an immediate `grisp_alloy` task when the only later Alloy-side
  work is a batched submodule-pointer sync; record that deferred sync in
  completion reporting/history instead.
- use Smelterl-local workflow artifacts for Smelterl tasks:
  - `smelterl/docs/PLANNING.md`,
  - `smelterl/history/`,
  - `smelterl/CHANGELOG.md`,
  - `$(git rev-parse --git-dir)/ALLOY_COMMIT_MSG` when run in the Smelterl
    repository root.
