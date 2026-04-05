# Alloy Workflow Redirect

The authoritative workflow document remains in `grisp_alloy`.

Primary development model:
- daily development normally starts from the `grisp_alloy` superproject root,
- Smelterl-owned tasks still use Smelterl-local planning/history/changelog and
  the Smelterl repository git dir for commit-message preparation,
- if `smelterl/` changes need Alloy-side updates, the Smelterl commit comes
  first and the linked `grisp_alloy` follow-up commit records the submodule
  pointer plus any Alloy-side code/docs/test changes.

When working from a `grisp_alloy` superproject checkout:
- track Smelterl-owned work in `smelterl/docs/PLANNING.md`,
- write history in `smelterl/history/`,
- update `smelterl/CHANGELOG.md`,
- prepare the Smelterl commit message via the Smelterl repository git dir
  (for example from the superproject root:
  `git -C smelterl rev-parse --git-dir`),
- commit Smelterl changes in the `smelterl/` repository first,
- then complete the linked `grisp_alloy` follow-up task that records the new
  submodule commit and any Alloy-side updates.

When working from a standalone `smelterl` checkout:
- follow the same Smelterl-local planning/history/changelog/commit rules,
- use the local planning file for task ownership,
- if the change would require a later `grisp_alloy` submodule bump, shared-doc
  update, or orchestration change, record that downstream follow-up explicitly
  in planning/history/completion reporting instead of implying the overall
  cross-repository job is already complete.

Use one of these:

- [Local superproject documentation](../../docs/WORKFLOW.md)
- [Web documentation](https://github.com/grisp/grisp_alloy/blob/grisp-alloy-ng/docs/WORKFLOW.md)
