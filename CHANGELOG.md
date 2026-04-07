# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to Semantic Versioning.

## [Unreleased]

### Added
- Added `smelterl_cmd_generate` as the initial `smelterl generate` command
  handler, including plan loading, selected-target resolution, strict
  main-target-only option validation, and dedicated Common Test coverage for
  the command-option matrix.
- Added `smelterl_plan`, `smelterl_file`, and `smelterl_vcs` to serialize
  versioned `build_plan.term` files, read them back for later generate-stage
  consumption, emit UTF-8 Erlang term files consistently, and attach
  repository provenance from `.alloy_repo_info` or git.
- Added `smelterl_gen_manifest` with plan-stage manifest seed preparation,
  including deterministic repository deduplication and repo-id assignment,
  firmware-capability and `sdk_outputs` seed shaping, external-component seed
  collection, and dedicated Common Test coverage for manifest-seed shape and
  target-arch validation.

- Added `smelterl_gen_defconfig` with plan-stage defconfig model building,
  cumulative-key specification under `priv/defconfig-keys.spec`, target-local
  wrapper-hook injection, and dedicated Common Test coverage for cumulative
  merging and flavor-mapped fragment selection.

- Added `smelterl_config` with plan-stage target-local config consolidation
  for overridden inputs, including export-conflict validation, flavor-aware
  value selection, relocatable path resolution, deferred `computed`/`exec`
  handling, and Common Test coverage for both happy-path and conflict cases.

- Added `smelterl_capabilities` with plan-stage firmware variant discovery,
  bootflow coverage validation, selectable firmware output collection, merged
  firmware parameter discovery, target-local `sdk_outputs` mapping, and Common
  Test coverage for both happy-path and validation-failure cases.

- Added `smelterl_overrides` with deterministic override collection,
  auxiliary-remap handling, nugget replacement application, target-local
  motherlode rewriting, scoped config override support, and Common Test
  coverage for replacement, scope handling, and auxiliary-remap revalidation.

- Added `smelterl_topology` with deterministic DFS-based topological ordering,
  cycle detection, and Common Test coverage for dependency ordering,
  declaration-order tie-breaking, stability across runs, and cycle reporting.

- Added `smelterl_validate` with target-tree and target-set validation for
  category cardinality, dependency constraints, conflicts, version/flavor
  checks, auxiliary restrictions, and hook-scope enforcement, plus a dedicated
  Common Test suite covering each validation family.

- Added `smelterl_tree` with nugget-only dependency subtree construction,
  auxiliary target discovery, effective auxiliary-tree composition, and Common
  Test coverage for dependency order, cycle detection, and backbone merging.
- Added `smelterl_log` as the shared stderr reporting surface for Smelterl
  command diagnostics, with warning emission used by motherlode loading when a
  repository is missing `.nuggets`.
- Added `smelterl_motherlode` with motherlode repository loading, `.nuggets`
  and `.nugget` root/schema validation, SBOM-default merging, `license_files`
  path resolution, duplicate nugget-id detection, and Common Test coverage for
  valid and malformed motherlodes.
- Added an initial standalone `smelterl` OTP project skeleton with a real
  escript entrypoint, CLI dispatch, `plan` command handler, and Common Test
  coverage for `plan` option validation and stderr/status behavior.

### Changed
- Updated the shared Smelterl CLI parser so command-argument errors are
  reported with the actual command name, allowing `generate` and later
  commands to reuse one parsing path without inheriting `plan`-specific
  diagnostics.
- Updated `smelterl plan` to write the optional `build_plan.env` summary when
  `--output-plan-env` is provided, exposing deterministic bash loop metadata
  (`ALLOY_PLAN_AUXILIARY_IDS`, `ALLOY_PLAN_TARGET_IDS`,
  `ALLOY_PLAN_TARGET_KIND`, `ALLOY_PLAN_TARGET_ROOT`) and the normalized
  root-level `ALLOY_PLAN_EXTRA_CONFIG` map from the serialized plan.
- Updated Smelterl plan coverage and docs with sourceable `build_plan.env`
  examples plus Common Test checks that the generated file preserves auxiliary
  order, keeps normalized `extra_config` values literal, and can be sourced by
  bash successfully.
- Updated `smelterl plan` to complete Task 3.11 end to end: it now loads real
  Smelterl build provenance, carries target-local motherlode/config/defconfig
  data plus normalized `extra_config` into a serialized build plan, builds the
  main manifest seed during planning, and writes a successful `build_plan.term`
  instead of stopping at the previous not-implemented stub.
- Updated the motherlode loader to preserve per-repository provenance in the
  in-memory motherlode so manifest-seed generation can reuse actual staged
  repository metadata rather than placeholder records.
- Updated Common Test coverage with plan roundtrip tests and an end-to-end
  `smelterl plan` success case that verifies normalized extra-config
  persistence and `.alloy_repo_info` provenance flowing into the serialized
  plan.
- Extended `smelterl.erl` with canonical manifest/build-info shared types so
  later plan/generate stages can reuse one manifest-seed source of truth.

- Updated `smelterl plan` to build per-target defconfig models after config
  consolidation, merging normalized extra-config values into the substitution
  environment while keeping plan serialization/rendering for later tasks.
- Updated Smelterl Common Test temp-directory helpers in the defconfig and
  config suites to retry on `eexist`, keeping repeated local/full-gate reruns
  deterministic without manual `/tmp` cleanup.

- Updated `smelterl plan` to parse and normalize `--extra-config`, reject
  user-specified `ALLOY_MOTHERLODE`, inject the reserved motherlode template
  value for later stages, execute config consolidation after capability
  discovery, and surface config-stage failures at command level before the
  remaining stubbed stages.
- Updated `smelterl_validate` with `resolved_flavors/2` so later plan stages
  can reuse validated flavor resolution without duplicating dependency-flavor
  logic, and extended `smelterl.erl` with canonical consolidated-config types.

- Centralized shared Smelterl plan-pipeline Erlang types in `smelterl.erl` and
  updated `smelterl_tree`, `smelterl_topology`, `smelterl_overrides`, and
  `smelterl_validate` to consume those canonical types via remote type
  references instead of repeating local declarations.
- Clarified `docs/DESIGN.md` so cross-module shared Smelterl types are
  explicitly sourced from `smelterl.erl` and future tasks are expected to
  reuse those canonical types.

- Updated `smelterl plan` to run capability discovery after override
  application, report capability-validation failures at command level, and keep
  the remaining not-implemented stub only for plans whose capabilities are
  valid.

- Updated `smelterl_validate` with `validate_replacement/4` so nugget
  replacements are checked against a candidate tree plus rewritten nugget-id
  references before they are applied.
- Updated `smelterl plan` to execute the override stage after topology
  calculation, surface override failures at command level, and keep the
  existing not-implemented stub only for plans that pass override processing.

- Updated `smelterl plan` to compute per-target topology orders after
  validation so the plan pipeline now exercises deterministic ordering for main
  and auxiliary targets before the remaining stubbed stages.

- Updated Smelterl Appendix B to document a readability rule for Erlang
  `maybe` usage and to treat more than three nested `case` expressions as the
  default refactoring threshold.
- Refactored the current linear error-propagation paths in `smelterl_validate`
  and `smelterl_cmd_plan` to use `maybe` and small helper extraction where that
  reduces nesting without changing behavior.

- Updated `smelterl plan` to run target validation after target-tree
  construction, report validation failures with command-level diagnostics, and
  keep the stubbed not-implemented path only for validated plans.
- Updated Smelterl Common Test temp-directory helpers to use collision-resistant
  `/tmp` directory creation so repeated reruns do not require manual cleanup.

- Updated `smelterl plan` to run target-tree construction before the later
  pipeline stub and to report circular-dependency and missing-dependency tree
  failures at command level.
- Updated `smelterl plan` and the shared CLI path to route stderr diagnostics
  through `smelterl_log`, and added Common Test coverage for visible,
  deterministic missing-registry warnings.
- Brought the current Smelterl source modules into Appendix B conformance with
  REUSE/SPDX headers, `-moduledoc` text, documented callbacks/types, required
  section headers, one-export-per-line layout, and explicit two-space wrapped
  guard indentation, including preferred vs not-preferred Appendix B examples,
  without changing runtime behavior.
- Updated `smelterl plan` so it now runs motherlode loading before the later
  pipeline stub and reports loader errors with command-level stderr messages.
- Simplified the initial `smelterl` first-pass CLI handling so Dialyzer passes
  without impossible-branch warnings.
