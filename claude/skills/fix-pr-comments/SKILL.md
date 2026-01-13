---
name: fix-pr-comments
description: This skill should be used when the user asks to "fix PR comments", "address PR feedback", "resolve PR threads", mentions "PR review", or discusses GitHub pull request comments.
version: 1.0.0
---

# Fix PR Comments

Handle PR review comments by choosing the appropriate response for each comment.

## Response Types

For each PR comment, choose one of these responses:

1. **Address and resolve**: Fix the issue, push the changes, and resolve the thread
2. **Explain**: If the comment doesn't make sense, leave a comment explaining why. Only resolve the thread if the comment is from a bot user.
3. **Ask for clarification**: If unclear, leave a question asking for clarification

## Comment Prefix

When leaving comments on PRs, always prefix with "Claude Code: " to make it clear the comment came from Claude.

## Workflow

1. Read all PR comments to understand the feedback
2. For each comment, determine the appropriate response type
3. Make code changes where needed
4. Push all changes
5. Resolve threads that have been addressed
6. Leave explanatory comments or clarification questions as needed
