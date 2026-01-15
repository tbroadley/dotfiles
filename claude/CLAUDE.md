# Global Rules

## GitHub Comments
- Prefix all GitHub comments (PR reviews, issue comments, discussions) with "Claude Code:"

## Environment
- AWS CLI: explicitly use production or staging profile

## Python Style
- Use json.dumps for JSON literals, not string concatenation. This ensures JSON strings are valid.
- Prefer list comprehensions over for loop / accumulator, except with complex control flow or when intermediate variables improve readability. Walrus operator (`if (a := b(c))`) can sometimes help.
- Prefer ternary expressions (`return x if condition else y`) over if-else blocks for simple conditional returns.
- Fail early: prefer code that fails immediately over code that logs a warning and potentially behaves incorrectly later.
- Imports: place at top of file (except for lazy loading)

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

## DVC (Data Version Control)
- If you encounter a failing `check-dvc` CI check, run `dvc repro`, then `dvc push`, then rerun the check

## Final Steps (before finishing any task)
- Remove try-except blocks that suppress errors. Code should fail early rather than log a warning and potentially behave incorrectly. Exception: when aggregating results from multiple operations to report at the end.
- Remove comments and docstrings you added
- Move imports to top of file
