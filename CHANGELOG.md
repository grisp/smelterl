# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to Semantic Versioning.

## [Unreleased]

### Added
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
