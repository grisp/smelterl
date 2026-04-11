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
- write history in `smelterl/history/`, following the shared rule that
  history files record only durable, future-useful task context and not normal
  process confirmations or local session-state reminders,
  including routine successful validation-command lists when those commands
  were only the expected workflow and produced no task-specific insight,
- codify durable workflow/process improvements in the owning repository docs
  rather than leaving them only in conversational feedback,
- update `smelterl/CHANGELOG.md`,
- prepare the Smelterl commit message via the Smelterl repository git dir
  (for example from the superproject root:
  `git -C smelterl rev-parse --git-dir`),
- commit Smelterl changes in the `smelterl/` repository first,
- create or move a `grisp_alloy` follow-up task to `[IN_PROGRESS]` only when
  the superproject is actually being changed:
  - immediately, when Alloy-side code/docs/tests also change as part of the
    same overall feature/fix,
  - later, when development returns to `grisp_alloy` and a batched submodule
    sync commit is being prepared.

When working from a standalone `smelterl` checkout:
- follow the same Smelterl-local planning/history/changelog/commit rules,
- use the local planning file for task ownership,
- if the change would require a later `grisp_alloy` submodule bump, shared-doc
  update, or orchestration change, record that downstream follow-up explicitly
  in planning/history/completion reporting instead of implying the overall
  cross-repository job is already complete.
- that downstream follow-up does not require an immediate `grisp_alloy`
  planning task if the superproject will be synchronized later in one batched
  commit.

Use one of these:

- [Local superproject documentation](../../docs/WORKFLOW.md)
- [Web documentation](https://github.com/grisp/grisp_alloy/blob/grisp-alloy-ng/docs/WORKFLOW.md)
