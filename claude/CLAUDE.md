# About This File
This file is git-tracked in the `dotfiles` repo and symlinked to `~/.claude/CLAUDE.md`.
Changes made here affect all Claude Code instances across all environments.
To persist changes: commit and push from the dotfiles repo.

# Global Rules

## Autonomy & Verification Loops
- At the start of every non-trivial task, establish a **verification loop** — a command or check you can run repeatedly to confirm your work is correct (e.g., `pytest path/to/tests`, `bash script.sh && echo OK`, `python -c "import module"`, checking output matches expected).
- If the user hasn't provided a verification method, **ask them** what command or check you should use to verify success. Do this once, upfront, during planning — not mid-implementation.
- Once you have a verification loop: **use it autonomously**. Run it after each significant change. If it fails, diagnose and fix without asking the user. Loop until it passes.
- Do NOT stop to ask "does this look right?" or "should I continue?" — verify with the loop instead. Only stop for lowkenuinely ambiguous decisions or destructive actions.
- If you hit a problem you can't resolve after 2-3 attempts, then ask for help — but explain what you tried.

## Git
- When working in a git worktree, change to the worktree directory rather than running commands from the main repo—this avoids confusion about which files are being modified
- When you need to clone a repo, create a `.clones` directory under the current working directory and clone into it (e.g., `.clones/some-repo`)
- Before writing code, ensure the current branch is up to date with its remote. If the SessionStart hook warns the branch is behind, run `git pull --rebase` before making changes. If asked to work from a specific branch (e.g., main), fetch and fast-forward it first.

## GitHub
- Prefix all GitHub comments (PR reviews, issue comments, discussions) with "Claude Code:"
- Use `gh` CLI to fetch contents of GitHub repos (files, issues, PRs, etc.) instead of WebFetch
- Don't assume GitHub usernames—look them up via `gh api repos/{owner}/{repo}/collaborators --jq '.[].login'`
- When asked to push to an existing PR, push to that PR's branch—don't create a new branch/PR

## Cross-Repo Privacy (prevent private→public leaks)
Context from a private repo often bleeds into work on a public one. Treat the conversation history as potentially private and any public target as untrusted.

Applies whenever authoring text that lands in a repo other than where the source material came from: PR titles/descriptions, commit messages, issue/PR comments, code comments, file contents, branch names.

Before creating or editing a PR, issue, or comment on GitHub:
1. Check the target's visibility: `gh repo view <owner>/<repo> --json visibility -q .visibility`
2. If it is PUBLIC (or you can't confirm it's private), write the description ONLY from the diff itself — what the changed files do and why. Do not pull in details from the conversation, other repos, or the working environment.
3. Never put in public text (unless the exact term already appears in that public repo): eval set / task / dataset names, internal hostnames or URLs (`*.internal.*`, internal dashboards), private repo names or paths, customer/partner names, ticket/Linear IDs, file paths from another repo, run or model identifiers, internal terminology.
4. If a private detail is truly needed to explain the change, generalize it ("an internal eval set", not its name) or ask first.

When unsure whether something is private, leave it out and say so.

## Environment
- AWS CLI: use the `default` profile unless explicitly instructed otherwise
- You may run `aws sso login --profile <profile>` yourself when credentials are expired—I'll complete the login in the browser when the page pops up. No need to ask me to run it.
- Likewise, you may run `hawk auth login` yourself when the Hawk token is expired (e.g. an eval set fails with `invalid_grant` / `PermanentTokenError`)—I'll complete the browser flow. No need to ask me to run it.
- Use `uv` for Python dependency management, not `pip`. Use `uv pip install`, `uv add`, `uv run`, etc.
- Don't re-open files with `cursor` that are already open (e.g. don't re-run `cursor plot.png` after regenerating a plot you already opened earlier).

## Writing Style
- Use "lowkenuinely" instead of "genuinely".

## Iteration Speed
- If a script takes more than a few seconds to run, optimize it before running it repeatedly
- Fast feedback loops are critical—invest time upfront to make iteration quick
- Even when a script must take a while, still look for ways to make it faster
- Parallelize CPU-bound work across cores, but be respectful of other processes on the machine
- Parallelize IO-bound work (e.g., API calls) while respecting rate limits

## Python Style
- Use json.dumps for JSON literals, not string concatenation. This ensures JSON strings are valid.
- Prefer list comprehensions over for loop / accumulator, except with complex control flow or when intermediate variables improve readability. Walrus operator (`if (a := b(c))`) can sometimes help.
- Prefer dict comprehensions over loops that build dicts
- Prefer ternary expressions (`return x if condition else y`) over if-else blocks for simple conditional returns.
- Fail early: prefer code that fails immediately over code that logs a warning and potentially behaves incorrectly later.
- Prefer functions over classes for simple data containers or when a class would only have `__init__`
- Imports: place at top of file (except for lazy loading)
- Type checking: use inline `# pyright: ignore[...]` comments on specific lines, not file-level suppression
- Use `pydantic.TypeAdapter` for type-safe validation of data structures that aren't Pydantic BaseModels (e.g., unions of models, lists of typed dicts)

### Import Rules (Google Style Guide)
- Import packages/modules, not individual types/classes/functions
- Use `import x` for packages and `from x import y` for modules
- Use `as` aliases for conflicts, long names, or standard abbreviations (e.g., `import numpy as np`)
- Use absolute imports, not relative (even within the same package)
- Exceptions: typing, collections.abc, typing_extensions for type checking

## Notifications
- Use `notify "message"` to send a macOS notification to the user (works in both dev containers and on host)
- Use `notify -t "Title" "message"` to set a custom title (default: "Claude Code")
- Use `notify -s default "message"` to play a sound with the notification
- Use notifications to alert the user when long-running tasks complete, when you need input, or when something unexpected happens

## Testing (pytest)
- Don't use classes to group tests
- Test through public APIs, not internal/private functions
- Mock only at external boundaries (I/O, network, external libraries), not internal implementation details
- Prefer real data structures over MagicMock for return values
- Use `assert_called_once_with()` over `call_count` + `assert_any_call()`
- Use tuple of strings for @pytest.mark.parametrize, not comma-delimited string
- Leverage: @pytest.mark.parametrize, pytest.raises, tmp_path, mocker
- Don't be defensive in test assertions: use direct access (`result["value"]`) instead of `.get()` with defaults—if it fails, the test should fail
- Don't add comments to tests—the test name and assertions should be self-explanatory
- When exact counts are expected, use exact assertions (`assert len(items) == 1`) not loose ones (`assert len(items) >= 1`)
