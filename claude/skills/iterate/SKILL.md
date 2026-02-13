---
name: iterate
description: This skill should be used when the user asks to "iterate", "plan and implement", "implement with review", or wants an autonomous plan → implement → review loop.
user-invocable: true
---

# Iterate: Plan, Implement, Review

Interactive planning session with the user, followed by an autonomous loop of implement → commit/push → review until the code is clean.

## Phase 1: Planning (Interactive)

Work with the user to create a detailed implementation plan. This is the only phase where you interact with the user — after planning, everything is autonomous.

### Planning Requirements

The plan must be detailed enough that **no further human input is needed**. Push for specifics:

- Exactly which files to create/modify
- Function signatures, data structures, key logic
- How to handle edge cases
- What tests to write
- Acceptance criteria: how to verify the implementation is correct

Ask clarifying questions until the plan is unambiguous. Tell the user: "I'm going to make this plan very detailed because once I start implementing, I won't ask for any more input."

### Plan Output

Write the finalized plan as a numbered list of concrete implementation steps. Each step should be small enough for a single subagent to execute. Group related changes that must be consistent (e.g., updating a function signature and all its callers) into the same step.

## Phase 2: Autonomous Loop

Once the user approves the plan, execute this loop with no further user interaction. Continue looping until the review says "done" or you hit 5 iterations.

### Step 1: Implement

Spawn one or more Task subagents (subagent_type: "general-purpose") to implement the next set of changes. Give each subagent:

- The relevant portion of the plan
- The cumulative context from previous iterations (what was implemented, what the reviewer flagged, what was fixed)
- Clear instructions to make the changes and run any available validation (tests, linter, typechecker)

If the plan has independent steps, run multiple subagents in parallel. If steps depend on each other, run them sequentially.

For the first iteration, implement the plan. For subsequent iterations, address the review findings.

### Step 2: Validate, Commit, Push

Run lightweight validation and push. Do NOT use the commit-push skill here — save that for the end.

1. Run the project's linter (e.g., `ruff check`), typechecker (e.g., `basedpyright`), and formatter (e.g., `ruff format --check`). Fix any issues.
2. Run fast tests (e.g., `pytest -m "not slow"` or `pytest` if no slow markers). Fix any failures.
3. Stage and commit with a descriptive message ending with `Co-Authored-By: Claude <noreply@anthropic.com>`
4. Push to remote.

If validation fails, fix and retry — don't move on to the review step with broken code.

### Step 3: Review

Spawn a Task subagent (subagent_type: "general-purpose") to review the changes. Give the review subagent:

- The original plan
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

### Step 4: Decide

Based on the review subagent's response:

- **If "continue"**: Append the review findings to the cumulative context. Go back to Step 1, but this time the implementation subagent addresses the review findings instead of the original plan.
- **If "done" or 5 iterations reached**: Proceed to Step 5 (Cleanup) before finalizing.

### Step 5: Cleanup

Before finalizing, run the `/cleanup` skill to remove anti-patterns and enforce CLAUDE.md conventions on the changed code:

1. **Spawn cleanup subagent**: Launch a Task subagent (subagent_type: "general-purpose") and instruct it to run the cleanup skill (invoke `/cleanup`)
2. **Give it context**: Provide the cumulative context. Instruct it to:
   - Read the project's `CLAUDE.md` and `~/.claude/CLAUDE.md` to check changed code against all style rules and conventions
   - Apply both the hardcoded cleanup patterns and any CLAUDE.md rule violations
   - Only clean up code changed on this branch (not pre-existing code on main)
3. **Validate and commit**: After cleanup, the subagent should validate (linter/typechecker/tests), commit changes with message "Clean up code before PR", and push
4. **Append to context**: Add a cleanup summary to the cumulative context, noting which changes came from CLAUDE.md rules vs hardcoded patterns

### Step 6: Finalize

After cleanup is complete:

- Run the full commit-push skill (`/commit-push`) to open/update the PR, wait for CI, and handle PR comments
- Report the final summary to the user, including the cumulative context and cleanup summary

### Cumulative Context

Maintain a running summary across iterations. After each iteration, append:

```
--- Iteration N ---
Implemented: <what was done>
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
- If a review finding is a false positive, the implementation subagent should skip it and note why in the cumulative context
- If the project has no tests or linters, the review subagent should note this but not block on it
- The full commit-push skill (PR creation, CI waiting, PR comments) only runs once at the very end — during the loop, just validate locally, commit, and push
