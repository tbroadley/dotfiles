# About This File
This file is git-tracked in the `dotfiles` repo and symlinked to `~/.claude/CLAUDE.md`.
Changes made here affect all Claude Code instances across all environments.
To persist changes: commit and push from the dotfiles repo.

# Global Rules

## Autonomy & Verification Loops
- At the start of every non-trivial task, establish a **verification loop** — a command or check you can run repeatedly to confirm your work is correct (e.g., `pytest path/to/tests`, `bash script.sh && echo OK`, `python -c "import module"`, checking output matches expected).
- If the user hasn't provided a verification method, **ask them** what command or check you should use to verify success. Do this once, upfront, during planning — not mid-implementation.
- Once you have a verification loop: **use it autonomously**. Run it after each significant change. If it fails, diagnose and fix without asking the user. Loop until it passes.
- Do NOT stop to ask "does this look right?" or "should I continue?" — verify with the loop instead. Only stop for genuinely ambiguous decisions or destructive actions.
- If you hit a problem you can't resolve after 2-3 attempts, then ask for help — but explain what you tried.

## Git
- When working in a git worktree, change to the worktree directory rather than running commands from the main repo—this avoids confusion about which files are being modified
- When you need to clone a repo, create a `.clones` directory under the current working directory and clone into it (e.g., `.clones/some-repo`)

## GitHub
- Prefix all GitHub comments (PR reviews, issue comments, discussions) with "Claude Code:"
- Use `gh` CLI to fetch contents of GitHub repos (files, issues, PRs, etc.) instead of WebFetch
- Don't assume GitHub usernames—look them up via `gh api repos/{owner}/{repo}/collaborators --jq '.[].login'`
- When asked to push to an existing PR, push to that PR's branch—don't create a new branch/PR

## Environment
- AWS CLI: explicitly use production or staging profile
- Use `uv` for Python dependency management, not `pip`. Use `uv pip install`, `uv add`, `uv run`, etc.

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
