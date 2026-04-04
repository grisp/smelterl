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

Rules:

- keep Smelterl-specific implementation, tests, planning, and history here,
- keep Alloy orchestration, shared workflow, and Alloy-owned design docs in the
  `grisp_alloy` repository,
- when a task depends on Alloy-owned design documents, follow the local/external
  links provided by the redirect stubs under `docs/`.
