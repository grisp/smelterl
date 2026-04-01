# Project Plan

This file tracks the standalone Smelterl backlog and execution status.

Related documents:

- [Design](DESIGN.md)
- [Alloy Workflow Redirect](WORKFLOW.md)
- [Alloy Data Design Redirect](01_DATA_DESIGN.md)

Task ID note:
- phase numbering below is standalone-Smelterl-local,
- task IDs intentionally keep the original shared-planning numbering so
  migrated history and replayed commits remain traceable to their source tasks.

Status convention:
- TODO: `- [ ] **Task ...**`
- IN_PROGRESS: `- [ ] **[IN_PROGRESS] Task ...**`
- DONE: `- [x] **Task ...**`

## Phase 1: Smelterl Plan Pipeline (original Alloy Phase 3)


- [x] **Task 3.1: `smelterl_cmd_plan` skeleton and option validation**
  - Scope: Command handler with strict required option checks.
  - Tests: Command-option unit tests, stderr/status behavior.
  - Done when: `plan` entry behavior is stable and test-covered.

- [x] **Task 3.2: `smelterl_motherlode` load + schema checks**
  - Scope: `.nuggets` and `.nugget` parsing with defaults merge.
  - Tests: Parsing/unit tests for malformed and valid registries.
  - Refinement note (from Task 3.1): Implement loading behind the new `smelterl` / `smelterl_cli` / `smelterl_cmd_plan` skeleton so `plan` can transition from validated stub to real pipeline without changing the public CLI shape again.
  - Done when: Motherlode map is complete and validated.

- [x] **Task 3.2b: Smelterl Appendix B formatting and documentation conformance**
  - Scope: Bring the Smelterl Erlang source modules into conformance with
    `docs/02_SMELTERL_DESIGN.md` Appendix B formatting and inline
    documentation rules.
  - Scope: Add any missing SPDX/REUSE headers, `-moduledoc`, `-doc`,
    documented exported types/callbacks, section headers/order, export layout,
    and line-wrapping cleanups required by the current Smelterl source set.
  - Tests: `rebar3 as test ct`, `rebar3 dialyzer`, and Appendix B review of
    touched Erlang modules.
  - Done when: The Smelterl Erlang source files follow Appendix B structure and
    inline documentation requirements.

- [x] **Task 3.2c: Smelterl warning/reporting surface**
  - Scope: Introduce a proper non-fatal Smelterl warning/reporting surface for
    command-visible warnings that should not abort execution.
  - Scope: Use that warning/reporting surface for motherlode repositories that
    are missing `.nuggets`, instead of continuing silently.
  - Tests: `rebar3 as test ct`, `rebar3 dialyzer`, and focused tests for
    warning emission/collection behavior.
  - Done when: Smelterl can report non-fatal warnings deterministically and the
    missing-`.nuggets` motherlode case uses that path.

- [ ] **Task 3.3: `smelterl_tree` main+aux tree construction**
  - Scope: Main tree, auxiliary discovery, effective auxiliary trees.
  - Tests: Unit tests for dependency resolution and cycle detection.
  - Refinement note (from Task 3.2b): New Smelterl Erlang modules should start
    from the Appendix B-compliant source skeleton (SPDX/REUSE headers,
    `-moduledoc`, section headers, documented exported APIs) so style/docs do
    not drift until the end of the pipeline work.
  - Refinement note (from Task 3.2c): Route new non-fatal planner diagnostics
    through `smelterl_log` and cover command-visible warning cases with
    deterministic tests instead of reintroducing silent skips or ad-hoc
    `io:format/3` reporting.
  - Done when: All target trees are built deterministically.

- [ ] **Task 3.4: `smelterl_validate` target validation**
  - Scope: Category cardinality, constraints, auxiliary restrictions.
  - Tests: Unit tests for each validation family.
  - Done when: Invalid target graphs fail early with clear reasons.

- [ ] **Task 3.5: `smelterl_topology` deterministic ordering**
  - Scope: Stable topological order per target.
  - Tests: Determinism tests on repeated runs.
  - Done when: Same input yields same order every run.

- [ ] **Task 3.6: `smelterl_overrides` nugget/config/aux remap**
  - Scope: Apply overrides in deterministic order with scoped semantics.
  - Tests: Unit tests for last-wins and scope rules.
  - Done when: Overridden trees/motherlode/config are reproducible.

- [ ] **Task 3.7: `smelterl_capabilities` discovery output**
  - Scope: Main firmware capabilities + per-target `sdk_outputs`.
  - Tests: Unit tests for variant/output/param merging and sdk output mapping.
  - Done when: Discovery map is complete for context/manifest generation.

- [ ] **Task 3.8: `smelterl_config` consolidation**
  - Scope: Per-target config/exports with path/computed/exec handling.
  - Tests: Unit tests for substitution, script exec, path resolution.
  - Refinement note (from Task 3.2): Consume the `{Key, Value, DeclaringNugget}` config/export entries prepared by `smelterl_motherlode` instead of re-deriving the declaring nugget during consolidation.
  - Done when: Consolidated config is deterministic and spec-compliant.

- [ ] **Task 3.9: `smelterl_gen_defconfig` plan-stage model build**
  - Scope: Build structured defconfig model (not rendered file) at plan time.
  - Tests: Unit tests for cumulative keys and wrapper hook injection.
  - Done when: Model can be rendered later without re-resolution.

- [ ] **Task 3.10: `smelterl_gen_manifest` plan-stage seed build**
  - Scope: Build deterministic manifest seed (`auxiliary_products`, firmware `capabilities`, top-level `sdk_outputs` seed).
  - Tests: Unit tests for repository dedup/id stability and seed shape.
  - Done when: Seed is complete and independent from runtime/legal inputs.

- [ ] **Task 3.11: `smelterl_plan` serialization (`build_plan.term`)**
  - Scope: Serialize full plan structure and version markers.
  - Tests: Roundtrip read/write tests.
  - Done when: Plan can be consumed by generate without recomputation.

- [ ] **Task 3.12: `build_plan.env` export writer**
  - Scope: Bash-friendly target list and loop metadata export.
  - Tests: Golden test for env file content.
  - Done when: Orchestrator can source it for target loops.


## Phase 2: Smelterl Generate Pipeline (original Alloy Phase 4)


- [ ] **Task 4.1: `smelterl_cmd_generate` skeleton and option validation**
  - Scope: Selected-target generation, main-only option enforcement.
  - Tests: Command-option matrix tests (`--auxiliary` vs main-only options).
  - Done when: Invalid combos fail early and predictably.

- [ ] **Task 4.2: `smelterl_gen_external_desc` render/write**
  - Scope: Generate `external.desc` from selected target plan data.
  - Tests: Golden output test.
  - Done when: Output is deterministic and valid.

- [ ] **Task 4.3: `smelterl_gen_config_in` render/write**
  - Scope: Generate `Config.in` from selected target + plan-carried extra-config.
  - Tests: Golden output test including `ALLOY_MOTHERLODE` behavior.
  - Done when: Output matches design and Buildroot expectations.

- [ ] **Task 4.4: `smelterl_gen_external_mk` render/write**
  - Scope: Generate `external.mk`.
  - Tests: Golden output test.
  - Done when: Include order and content are deterministic.

- [ ] **Task 4.5: `smelterl_gen_defconfig` generate-stage render**
  - Scope: Render selected target defconfig from plan model.
  - Tests: Golden output test.
  - Done when: Generate stage does render only (no resolution).

- [ ] **Task 4.6: `smelterl_gen_context` selected-target context**
  - Scope: Generate target context with strict main-vs-aux boundaries.
  - Tests: Golden tests for one main and one auxiliary context.
  - Done when:
    - Auxiliary context omits firmware/embed/fs-priority control arrays.
    - Main context includes firmware arrays and sdk-output consumption support.

- [ ] **Task 4.7: `smelterl_legal` parse single legal tree**
  - Scope: Parse one Buildroot legal-info input.
  - Tests: Unit tests for parse failures and package extraction.
  - Done when: Parsed legal structure is reusable for merge/export.

- [ ] **Task 4.8: `smelterl_legal` merge/export multi-target legal trees**
  - Scope: Merge main+aux legal data and emit one legal-info export.
  - Tests: Golden export tree test including merged README blocks.
  - Done when: Final export has one merged tree with preserved target README content.

- [ ] **Task 4.9: `smelterl_gen_manifest` generate-stage finalize**
  - Scope: Finalize manifest from seed (runtime fields, legal sections, integrity).
  - Tests: Golden manifest test with and without Buildroot legal data.
  - Done when:
    - `capabilities` is firmware-only.
    - `sdk_outputs` is a separate top-level section.

- [ ] **Task 4.10: Plan/generate integration regression tests**
  - Scope: End-to-end smelterl tests for one main + one auxiliary sample.
  - Tests: Integration tests asserting no dependency resolution in generate.
  - Done when: Pipeline determinism and option gating are verified.

