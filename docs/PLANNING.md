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

Cross-repository development note:
- when `smelterl/` is developed from a `grisp_alloy` superproject checkout,
  Smelterl-owned work is still tracked here,
- if a Smelterl task also needs Alloy-side changes, create or use a linked
  `grisp_alloy` task for the follow-up submodule-pointer/docs/orchestration
  update,
- keep only one linked task `[IN_PROGRESS]` at a time,
- complete and commit the Smelterl task first, then move the linked
  `grisp_alloy` task to `[IN_PROGRESS]` so the superproject records the new
  submodule commit.
- in a standalone `smelterl` checkout, still track Smelterl-owned work here
  and call out any required downstream `grisp_alloy` synchronization
  explicitly.

Status convention:
- TODO: `- [ ] **Task ...**`
- IN_PROGRESS: `- [ ] **[IN_PROGRESS] Task ...**`
- DONE: `- [x] **Task ...**`

Backlog/process note:
- If feedback reveals a durable workflow/process improvement, record it in the
  owning repository workflow/agent/planning docs instead of relying on
  conversational memory.

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

- [x] **Task 3.3: `smelterl_tree` main+aux tree construction**
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

- [x] **Task 3.4: `smelterl_validate` target validation**
  - Scope: Category cardinality, constraints, auxiliary restrictions.
  - Tests: Unit tests for each validation family.
  - Refinement note (from Task 3.3): The pre-validation auxiliary target set is
    preserved as an ordered list rather than a map so duplicate `AuxId`
    declarations survive discovery; validation should reject duplicates before
    any later canonicalization by target id.
  - Done when: Invalid target graphs fail early with clear reasons.

- [x] **Task 3.4b: Smelterl Appendix B case-depth and `maybe` readability rule**
  - Scope: Update `docs/02_SMELTERL_DESIGN.md` Appendix B to state that
    `maybe` syntax should be used when it materially improves readability, and
    that deeply nested `case` expressions should be refactored when they exceed
    the preferred readability threshold.
  - Scope: Refactor the existing Smelterl Erlang modules that now violate the
    new readability rule, using `maybe` and/or helper-function extraction where
    it makes the control flow clearer.
  - Tests: `rebar3 as test ct`, `rebar3 dialyzer`, and focused regression tests
    for any refactored command/validator paths.
  - Refinement note (from Task 3.4): Treat more than three nested `case`
    expressions as the default refactoring threshold, but keep the rule
    readability-driven rather than mechanically enforcing `maybe` everywhere.
  - Done when: Appendix B documents the style rule clearly and the current
    Smelterl codebase no longer has obvious violations in the touched modules.

- [x] **Task 3.5: `smelterl_topology` deterministic ordering**
  - Scope: Stable topological order per target.
  - Tests: Determinism tests on repeated runs.
  - Refinement note (from Task 3.4b): New Smelterl Erlang work should follow
    the Appendix B readability rule for `maybe` and case-depth, using `maybe`
    or helper extraction when a linear flow would otherwise exceed three nested
    `case` expressions.
  - Done when: Same input yields same order every run.

- [x] **Task 3.6: `smelterl_overrides` nugget/config/aux remap**
  - Scope: Apply overrides in deterministic order with scoped semantics.
  - Tests: Unit tests for last-wins and scope rules.
  - Refinement note (from Task 3.4): After auxiliary remaps or nugget
    replacements, rerun target-set validation (not just per-tree validation) so
    duplicate `AuxId`, auxiliary-category, shared-flavor, and hook-scope
    invariants stay enforced before later pipeline stages.
  - Refinement note (from Task 3.5): Preserve the new per-target topology
    contract when remaps or replacements occur: recompute impacted target
    orders with `smelterl_topology`, keep dependency declaration order as the
    tie-break, and keep each target root last.
  - Done when: Overridden trees/motherlode/config are reproducible.

- [x] **Task 3.7: `smelterl_capabilities` discovery output**
  - Scope: Main firmware capabilities + per-target `sdk_outputs`.
  - Tests: Unit tests for variant/output/param merging and sdk output mapping.
  - Done when: Discovery map is complete for context/manifest generation.

- [x] **Task 3.7a: Shared Smelterl type centralization in `smelterl.erl`**
  - Scope: Move shared plan/generate Erlang types into `smelterl.erl` as the
    canonical source of truth and replace duplicated local type declarations in
    Smelterl modules with remote type references.
  - Scope: Normalize currently duplicated shared types at least across
    `smelterl_tree`, `smelterl_validate`, `smelterl_overrides`,
    `smelterl_topology`, and `smelterl_capabilities`, including the common
    target/tree/motherlode/topology type families.
  - Scope: Update `docs/02_SMELTERL_DESIGN.md` so the design clearly states
    that cross-module shared Erlang types live in `smelterl.erl`, while
    module-private helper types stay local.
  - Scope: Update `docs/WORKFLOW.md` so future tasks explicitly check for an
    existing canonical shared type before introducing duplicate cross-module
    `-type` declarations.
  - Tests: `rebar3 as test ct`, `rebar3 dialyzer`, and documentation review of
    the updated shared-type/source-of-truth guidance.
  - Refinement note (from Task 3.7): The obvious duplicates now are
    `nugget_id`, `target_id`, `motherlode`, `nugget_tree`,
    `auxiliary_constraint_prop`, `auxiliary_target`, `target_trees`,
    `nugget_topology_order`, `topology_orders`, and `target_motherlodes`; keep
    module-local helper types local unless they are truly shared.
  - Done when: Shared cross-module types live in `smelterl.erl`, the touched
    modules use `smelterl:...()` remote types instead of copy-pasted local
    definitions, `docs/02_SMELTERL_DESIGN.md` and `docs/WORKFLOW.md` both make
    the source-of-truth rule explicit, and Common Test + Dialyzer stay clean.

- [x] **Task 3.8: `smelterl_config` consolidation**
  - Scope: Per-target config/exports with path/computed/exec handling.
  - Tests: Unit tests for substitution, script exec, path resolution.
  - Refinement note (from Task 3.2): Consume the `{Key, Value, DeclaringNugget}` config/export entries prepared by `smelterl_motherlode` instead of re-deriving the declaring nugget during consolidation.
  - Refinement note (from Task 3.6): Consume the target-local motherlode views
    emitted by `smelterl_overrides`, not the raw motherlode; nugget
    replacements rewrite nugget-id references in `depends_on`, and config
    overrides already mutate `{Key, Value, OriginNugget}` entries per target.
  - Refinement note (from Task 3.7a): Add any new cross-module configuration or
    plan payload types to `smelterl.erl` and use remote type references from
    implementation modules instead of duplicating shared `-type` declarations.
  - Done when: Consolidated config is deterministic and spec-compliant.

- [x] **Task 3.9: `smelterl_gen_defconfig` plan-stage model build**
  - Scope: Build structured defconfig model (not rendered file) at plan time.
  - Tests: Unit tests for cumulative keys and wrapper hook injection.
  - Done when: Model can be rendered later without re-resolution.

- [x] **Task 3.10: `smelterl_gen_manifest` plan-stage seed build**
  - Scope: Build deterministic manifest seed (`auxiliary_products`, firmware `capabilities`, top-level `sdk_outputs` seed).
  - Tests: Unit tests for repository dedup/id stability and seed shape.
  - Refinement note (from Task 3.7): Consume the validated
    `smelterl_capabilities` output for firmware capabilities and per-target
    `sdk_outputs` seed data instead of recomputing uniqueness and merge rules
    from nugget metadata.
  - Done when: Seed is complete and independent from runtime/legal inputs.

- [x] **Task 3.11: `smelterl_plan` serialization (`build_plan.term`)**
  - Scope: Serialize full plan structure and version markers.
  - Tests: Roundtrip read/write tests.
  - Refinement note (from Task 3.8): Persist normalized plan extra-config
    values, not raw CLI strings: `ALLOY_MOTHERLODE` is injected by
    `smelterl plan`, the user may not override it, and later stages should read
    the normalized map/key set from the serialized plan.
  - Refinement note (from Task 3.10): Consume the precomputed manifest seed
    from `smelterl_gen_manifest:prepare_seed/7` and wire in real
    build-info/motherlode repository provenance; do not synthesize placeholder
    repository records during serialization.
  - Done when: Plan can be consumed by generate without recomputation.

- [x] **Task 3.12: `build_plan.env` export writer**
  - Scope: Bash-friendly target list and loop metadata export.
  - Tests: Golden test for env file content.
  - Refinement note (from Task 3.11): Derive loop ordering from serialized
    `auxiliary_ids` rather than iterating the unordered `targets` map, and
    reuse the normalized root-level `extra_config` payload instead of
    re-parsing CLI strings.
  - Done when: Orchestrator can source it for target loops.

## Phase 2: Smelterl Generate Pipeline (original Alloy Phase 4)


- [x] **Task 4.1: `smelterl_cmd_generate` skeleton and option validation**
  - Scope: Selected-target generation, main-only option enforcement.
  - Tests: Command-option matrix tests (`--auxiliary` vs main-only options).
  - Done when: Invalid combos fail early and predictably.

- [x] **Task 4.2: `smelterl_gen_external_desc` render/write**
  - Scope: Generate `external.desc` from selected target plan data.
  - Tests: Golden output test.
  - Refinement note (from Task 4.1): Reuse `smelterl_cmd_generate`'s
    plan-loading and selected-target validation path so render tasks keep one
    command-layer source of truth for main-vs-auxiliary option gating and plan
    selection errors.
  - Done when: Output is deterministic and valid.

- [x] **Task 4.3: `smelterl_gen_config_in` render/write**
  - Scope: Generate `Config.in` from selected target + plan-carried extra-config.
  - Tests: Golden output test including `ALLOY_MOTHERLODE` behavior.
  - Refinement note (from Task 3.8): Use the normalized plan-carried
    extra-config key set produced by `smelterl plan`, with injected
    `ALLOY_MOTHERLODE` first and no user-provided override path.
  - Refinement note (from Task 4.2): Reuse `smelterl_template` and
    `priv/templates/` for Config.in rendering so template lookup, placeholder
    expansion, and file writes stay out of `smelterl_cmd_generate`.
  - Done when: Output matches design and Buildroot expectations.

- [x] **Task 4.4: `smelterl_gen_external_mk` render/write**
  - Scope: Generate `external.mk`.
  - Tests: Golden output test.
  - Refinement note (from Task 4.3): Reuse the same package-tree discovery
    rules as `smelterl_gen_config_in`: accept a root-level packages-path
    aggregator file when present and keep per-package directory traversal
    deterministic (alphabetical within each nugget).
  - Done when: Include order and content are deterministic.

- [x] **Task 4.4a: `smelterl_gen_config_in` template-owned formatting refactor**
  - Scope: Replace the current pre-rendered `extra_config_blocks` and
    `source_blocks` strings with structured template data so `Config.in`
    comments, blank lines, `config`, and `source` line layout live in the
    Mustache template instead of Erlang.
  - Tests: Update `smelterl_gen_config_in` Common Tests to assert the same
    output through section-driven template rendering.
  - Refinement note (from Task 4.4): Reuse the section-capable
    `smelterl_template` path introduced for `external.mk`; Erlang should keep
    deterministic ordering and path resolution, but not assemble formatted
    text blocks.
  - Done when: `smelterl_gen_config_in` passes structured data only and the
    template fully defines output formatting.

- [x] **Task 4.4b: `smelterl_gen_external_desc` template-owned formatting refactor**
  - Scope: Replace the current preformatted description/version concatenation
    in Erlang with structured template data so `external.desc` layout and
    optional version text are defined in the Mustache template.
  - Tests: Update `smelterl_gen_external_desc` Common Tests to cover the
    template-driven version/description cases.
  - Refinement note (from Task 4.4): Keep product-name normalization in Erlang,
    but move the final text-shape decisions into the template using the shared
    section-capable renderer.
  - Done when: `smelterl_gen_external_desc` provides structured fields only and
    the template defines the emitted text format.

- [x] **Task 4.5: `smelterl_gen_defconfig` generate-stage render**
  - Scope: Render selected target defconfig from plan model.
  - Tests: Golden output test.
  - Refinement note (from Task 3.9): Consume the precomputed
    `smelterl:defconfig_model()` directly; cumulative entries already carry
    resolved paths, injected wrapper hooks, and final quoted value strings, so
    the render stage must not re-split or re-resolve them.
  - Refinement note (from Task 4.5a): Treat `priv/defconfig-keys.spec` as a
    committed generated input maintained by the self-contained helper escript;
    generate-stage defconfig rendering must consume the precomputed model only
    and must not reintroduce ad-hoc cumulative-key inference.
  - Done when: Generate stage does render only (no resolution).

- [x] **Task 4.5a: Buildroot-driven `defconfig-keys.spec` generator**
  - Scope: Add an Smelterl escript that scans a Buildroot source tree and
    generates `priv/defconfig-keys.spec` using conservative heuristics for
    cumulative key detection and path-vs-plain classification.
  - Scope: Support explicit include and override options so known keys can be
    forced into the generated spec or have their kind corrected when heuristics
    are insufficient.
  - Scope: Make the generated file self-describing with traceability comments
    that record the Buildroot version/revision, generator command (without
    leaking host-specific absolute paths), and any explicit include/override
    options used for regeneration.
  - Scope: Commit the first generated version of `priv/defconfig-keys.spec`
    using the new generator and update the Smelterl design document to define
    this workflow.
  - Tests: Focused generator tests covering conservative detection, explicit
    includes/overrides, and generated header content.
  - Done when: Smelterl can regenerate `priv/defconfig-keys.spec` from a
    Buildroot tree reproducibly, the initial generated spec is committed, and
    the design/doc workflow reflects the new source of truth.

- [x] **Task 4.6: `smelterl_gen_context` selected-target context**
  - Scope: Generate target context with strict main-vs-aux boundaries.
  - Tests: Golden tests for one main and one auxiliary context.
  - Refinement note (from Task 3.7): Reuse the plan-carried capability data
    (`firmware_variants`, `variant_nuggets`, merged firmware parameters, and
    target-local `sdk_outputs`) rather than reparsing nugget metadata during
    generate.
  - Refinement note (from Task 3.7): The current capability payload carries the
    documented selectable firmware outputs; if main-context generation needs
    metadata for non-selectable firmware outputs too, clarify that design edge
    before extending the plan payload.
  - Done when:
    - Auxiliary context omits firmware/embed/fs-priority control arrays.
    - Main context includes firmware arrays and sdk-output consumption support.

- [x] **Task 4.7: `smelterl_legal` parse single legal tree**
  - Scope: Parse one Buildroot legal-info input.
  - Tests: Unit tests for parse failures and package extraction.
  - Done when: Parsed legal structure is reusable for merge/export.

- [x] **Task 4.8: `smelterl_legal` merge/export multi-target legal trees**
  - Scope: Merge main+aux legal data and emit one legal-info export.
  - Tests: Golden export tree test including merged README blocks.
  - Refinement note (from Task 4.7): Consume `smelterl_legal:parse_legal/1`
    as the source of truth for Buildroot package lists; the special
    `buildroot` host-manifest row is already folded into `br_version` and
    excluded from `host_packages`, and the parser is header-driven so merge
    logic should rely on required column names rather than fixed CSV ordering.
  - Done when: Final export has one merged tree with preserved target README content.

- [x] **Task 4.9: `smelterl_gen_manifest` generate-stage finalize**
  - Scope: Finalize manifest from seed (runtime fields, legal sections, integrity).
  - Tests: Golden manifest test with and without Buildroot legal data.
  - Refinement note (from Task 4.8): Reuse the merged Buildroot legal package
    data emitted by `smelterl_legal` instead of reparsing exported
    `manifest.csv` files; the legal exporter already reconstructs deterministic
    target and host manifests, preserves per-input README ordering, and
    normalizes the special `buildroot` row through `br_version`.
  - Done when:
    - `capabilities` is firmware-only.
    - `sdk_outputs` is a separate top-level section.

- [x] **Task 4.10: Plan/generate integration regression tests**
  - Scope: End-to-end smelterl tests for one main + one auxiliary sample.
  - Tests: Integration tests asserting no dependency resolution in generate.
  - Refinement note (from Task 4.9): End-to-end generate fixtures that request
    `--output-manifest` must carry a valid plan-stage `manifest_seed`; the
    generate path now validates and finalizes that seed instead of tolerating
    placeholder manifest metadata.
  - Refinement note (from Task 4.6): Static `alloy_context.sh` generation can
    emit declared `sdk_outputs` metadata and helper lookups, but the
    main-context `ALLOY_SDK_OUTPUT_<AUX_ID>_<OUTPUT_ID>` path variables remain
    Alloy-orchestrator injections after auxiliary builds and should be covered
    by later integration tests rather than Smelterl-only unit tests.
  - Refinement note (from Task 4.6): Main-context firmware output metadata
    still needs the selected target motherlode for non-selectable
    `firmware_outputs`; the current capability payload only carries selectable
    outputs plus firmware variants/parameters and target-local `sdk_outputs`.
  - Done when: Pipeline determinism and option gating are verified.
