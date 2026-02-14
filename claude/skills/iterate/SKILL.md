---
name: iterate
description: This skill should be used when the user asks to "iterate", "plan and implement", "implement with review", or wants an autonomous plan → implement → review loop.
user-invocable: true
---

# Iterate: Plan and Implement

Interactive planning session with the user, followed by autonomous implementation. After implementation, the `/iterate-review` skill handles the review → fix → cleanup → finalize loop.

## Planning (Interactive)

Work with the user to create a detailed implementation plan. Tell the user: "I'm going to make this plan very detailed because once I start implementing, I won't ask for any more input."

### Planning Requirements

The plan must be detailed enough that **no further human input is needed**. Push for specifics:

- Exactly which files to create/modify
- Function signatures, data structures, key logic
- How to handle edge cases
- What tests to write
- Acceptance criteria: how to verify the implementation is correct

Ask clarifying questions until the plan is unambiguous.

### Plan Output

Enter plan mode and write the finalized plan as a numbered list of concrete implementation steps. Each step should be small enough for a single subagent to execute. Group related changes that must be consistent (e.g., updating a function signature and all its callers) into the same step.

**At the end of the plan, add this section:**

```
## Post-Implementation

After all implementation steps are complete and validation passes:
1. Stage and commit all changes with a descriptive message ending with `Co-Authored-By: Claude <noreply@anthropic.com>`
2. Push to remote
3. Invoke the `/iterate-review` skill to review, clean up, and finalize the changes
```

This ensures the next agent (after context clearing) knows to invoke the review skill.
