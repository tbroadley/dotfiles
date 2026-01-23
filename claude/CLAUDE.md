# Global Rules

## Git
- When working in a git worktree, change to the worktree directory rather than running commands from the main repo—this avoids confusion about which files are being modified

## GitHub
- Prefix all GitHub comments (PR reviews, issue comments, discussions) with "Claude Code:"
- Use `gh` CLI to fetch contents of GitHub repos (files, issues, PRs, etc.) instead of WebFetch

## Environment
- AWS CLI: explicitly use production or staging profile

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

## DVC (Data Version Control)
- Track large generated/processed data files with DVC (`dvc add`), not git
- After modifying `dvc.yaml`: `dvc repro` then `dvc push` before committing

## Research Engineering

### Validate Before Scaling
- ALWAYS run on a tiny sample first (N=5-10) and inspect the outputs yourself before scaling up
- If a script will take >30 seconds, first run a 5-second version and verify results look reasonable
- Add `--limit N` or `--dry-run` flags to scripts that process large datasets
- Check sample outputs for obvious problems: repeated text, empty values, wrong format, garbled content
- Only proceed to full-scale runs after confirming the small sample looks correct

### Be Skeptical (Null Hypothesis: Your Code Is Wrong)
- Assume generated data is garbage until you've inspected samples and confirmed otherwise
- When results look "too good" or "too clean", investigate—they're probably wrong
- Print descriptive statistics (min, max, mean, distribution) and check for anomalies
- Before reporting results, actively try to find bugs that would invalidate them
- Don't trust that code works just because it runs without errors—verify the outputs make sense
