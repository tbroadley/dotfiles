---
name: iterate-review
description: Review, clean up, and finalize changes after implementation. Run this after implementing a plan from /iterate to review code, fix issues, run cleanup, and open/update a PR.
user-invocable: true
---

# Iterate Review: Review → Fix → Cleanup → Finalize

Autonomous review loop that runs after implementation. Continue looping until the review says "done" or you hit 5 iterations.

## Step 1: Understand Context

Before starting the review loop:

1. Determine the base branch by checking what the current branch was created from (e.g., `git log --oneline main..HEAD` or `git merge-base main HEAD`)
2. Read the full diff: `git diff origin/<base>...HEAD`
3. Read the plan file if one exists in plan mode — this tells you what was supposed to be implemented
4. Initialize the cumulative context (empty for the first iteration)

## Step 2: Validate

Run lightweight validation. Fix any issues before proceeding.

1. Run the project's linter (e.g., `ruff check`), typechecker (e.g., `basedpyright`), and formatter (e.g., `ruff format --check`). Fix any issues.
2. Run fast tests (e.g., `pytest -m "not slow"` or `pytest` if no slow markers). Fix any failures.
3. If you fixed anything, stage, commit, and push.

If validation fails, fix and retry — don't move on to the review step with broken code.

## Step 3: Review

Spawn a Task subagent (subagent_type: "general-purpose") to review the changes. Give the review subagent:

- The original plan (if available)
- The cumulative context from all iterations
- The diff of all changes on the branch vs the base branch: `git diff origin/<base>...HEAD`

The review subagent should:

1. Read the diff and any relevant source files
2. Check for: bugs, logic errors, missing error handling, deviations from the plan, style violations, missing tests, code smells
3. Run the project's linter, typechecker, and tests if available
4. Return a structured assessment:
   - **Verdict**: "continue" (has actionable findings) or "done" (ready to merge)
   - **Findings**: list of issues with severity (error/warning/nit), file, and description
   - **Summary**: one-line summary of the review

Tell the review subagent:
- Nits alone are NOT sufficient to return "continue" — only errors and warnings justify another iteration
- Read the cumulative context carefully — do NOT re-report issues that were already fixed
- If the same issue is being fixed and re-introduced across iterations, flag oscillation and return "done"
- Bias toward "done"

## Step 4: Decide

Based on the review subagent's response:

- **If "continue"**: Append the review findings to the cumulative context. Go back to Step 2, but this time fix the review findings before re-validating.
- **If "done" or 5 iterations reached**: Proceed to Step 5 (Cleanup).

## Step 5: Cleanup

Before finalizing, run the `/cleanup` skill to remove anti-patterns and enforce CLAUDE.md conventions on the changed code:

1. **Spawn cleanup subagent**: Launch a Task subagent (subagent_type: "general-purpose") and instruct it to run the cleanup skill (invoke `/cleanup`)
2. **Give it context**: Provide the cumulative context. Instruct it to:
   - Read the project's `CLAUDE.md` and `~/.claude/CLAUDE.md` to check changed code against all style rules and conventions
   - Apply both the hardcoded cleanup patterns and any CLAUDE.md rule violations
   - Only clean up code changed on this branch (not pre-existing code on main)
3. **Validate and commit**: After cleanup, the subagent should validate (linter/typechecker/tests), commit changes with message "Clean up code before PR", and push
4. **Append to context**: Add a cleanup summary to the cumulative context

## Step 6: Finalize

After cleanup is complete:

- Run the full commit-push skill (`/commit-push`) to open/update the PR, wait for CI, and handle PR comments
- Report the final summary to the user, including the cumulative context and cleanup summary

## Cumulative Context

Maintain a running summary across iterations. After each iteration, append:

```
--- Iteration N ---
Fixed: <what was done>
Review: <verdict> — <summary>
Findings: <list of findings, if any>
```

After cleanup, append:
```
--- Cleanup ---
Changes: <what was cleaned up>
```

Pass this full context to every subagent so they understand the history and avoid re-introducing old issues.

## Notes

- The implementation and review subagents should be given the project's CLAUDE.md content if it exists, so they follow project conventions
- If a review finding is a false positive, skip it and note why in the cumulative context
- If the project has no tests or linters, the review subagent should note this but not block on it
- The full commit-push skill (PR creation, CI waiting, PR comments) only runs once at the very end — during the loop, just validate locally, commit, and push
