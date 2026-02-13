---
name: cleanup
description: This skill should be used when the user asks to "clean up the code", "remove unnecessary comments", "simplify docstrings", "parameterize tests", or wants to review and clean up code.
user-invocable: true
---

# Cleanup Code

Review and clean up code, removing unwanted patterns and improving test structure.

## Scope

**By default, only clean up code that was changed on the current branch** (i.e., changes not yet on `main`). Use `git diff main...HEAD` to identify which files and lines were modified.

Do NOT clean up anti-patterns in code that was already on `main` unless the user explicitly requests a broader cleanup scope.

## What This Skill Does

1. Removes unnecessary comments
2. Simplifies or removes verbose docstrings
3. Consolidates tests using parameterization
4. Removes other unwanted patterns

## Crosscheck Against CLAUDE.md

Before applying the hardcoded patterns below, also check the changed code against rules from:

1. **Project CLAUDE.md**: Read the repo's `CLAUDE.md` (if it exists) for project-specific style rules, conventions, and patterns
2. **Global CLAUDE.md**: Read `~/.claude/CLAUDE.md` (if it exists) for global coding style rules

Scan the changed code for violations of any rules in these files. Common things to catch:
- Import style violations (e.g., importing individual items instead of modules)
- Testing anti-patterns (e.g., using classes to group tests, defensive `.get()` in assertions, mocking internals)
- Python style violations (e.g., for-loop accumulators instead of comprehensions, if-else blocks instead of ternary for simple returns)
- Error handling violations (e.g., logging warnings instead of failing early)
- Any other project-specific or global conventions defined in these files

CLAUDE.md rules take **equal priority** to the hardcoded patterns below — violations of CLAUDE.md rules are just as important to fix.

## Cleanup Tasks

### 1. Remove Unnecessary Comments

Remove explanatory comments that state the obvious or describe what code does line-by-line. Remove comments that:

- Restate what the code already clearly expresses
- Explain standard library functions or well-known patterns
- Were added "for clarity" but add no value
- Describe obvious variable assignments or function calls

**Keep comments that:**
- Explain *why* something is done (business logic, workarounds, edge cases)
- Document non-obvious behavior or gotchas
- Provide context that can't be inferred from the code

**Example - Before:**
```python
# Get the user from the database
user = db.get_user(user_id)

# Check if user exists
if user is None:
    # Raise an error if user not found
    raise UserNotFoundError(user_id)

# Return the user's email address
return user.email
```

**Example - After:**
```python
user = db.get_user(user_id)
if user is None:
    raise UserNotFoundError(user_id)
return user.email
```

### 2. Simplify Docstrings

Remove verbose docstrings that repeat parameter names and types already visible in type annotations, or describe obvious behavior. Clean up docstrings by:

- Removing docstrings from simple, self-explanatory functions
- Removing Args/Returns sections when types are annotated and obvious
- Keeping only non-obvious information
- Removing filler phrases like "This function..." or "This method..."

**Example - Before:**
```python
def get_user_email(user_id: int) -> str:
    """
    Get the email address for a user.

    This function retrieves the email address associated with the given user ID
    from the database.

    Args:
        user_id: The unique identifier of the user whose email should be retrieved.

    Returns:
        The email address of the user as a string.

    Raises:
        UserNotFoundError: If no user exists with the given ID.
    """
    user = db.get_user(user_id)
    if user is None:
        raise UserNotFoundError(user_id)
    return user.email
```

**Example - After:**
```python
def get_user_email(user_id: int) -> str:
    """Raises UserNotFoundError if user doesn't exist."""
    user = db.get_user(user_id)
    if user is None:
        raise UserNotFoundError(user_id)
    return user.email
```

Or if the function name and signature are completely self-explanatory:
```python
def get_user_email(user_id: int) -> str:
    user = db.get_user(user_id)
    if user is None:
        raise UserNotFoundError(user_id)
    return user.email
```

### 3. Parameterize Tests

Consolidate separate test functions that should be parameterized. Look for:

- Multiple test functions with nearly identical structure
- Tests that differ only in input values and expected outputs
- Copy-paste test patterns with minor variations

Consolidate using `@pytest.mark.parametrize`:

**Example - Before:**
```python
def test_validate_email_valid():
    assert validate_email("user@example.com") is True

def test_validate_email_valid_with_subdomain():
    assert validate_email("user@mail.example.com") is True

def test_validate_email_invalid_no_at():
    assert validate_email("userexample.com") is False

def test_validate_email_invalid_no_domain():
    assert validate_email("user@") is False

def test_validate_email_invalid_empty():
    assert validate_email("") is False
```

**Example - After:**
```python
@pytest.mark.parametrize(
    ("email", "expected"),
    [
        ("user@example.com", True),
        ("user@mail.example.com", True),
        ("userexample.com", False),
        ("user@", False),
        ("", False),
    ],
)
def test_validate_email(email: str, expected: bool):
    assert validate_email(email) is expected
```

**When NOT to parameterize:**
- Tests with significantly different setup/teardown
- Tests that check different aspects of behavior (not just input/output variations)
- Tests where parameterization would obscure the intent

### 4. Remove Defensive Code Patterns

**HIGHEST PRIORITY**: Remove unnecessary defensive programming that hides bugs instead of failing loudly.

#### Defensive `.get()` Calls
Replace `.get()` with default values on internal data structures with direct access. Let KeyError propagate.

**Before:**
```python
user_id = data.get("user_id", None)
if user_id is None:
    return
```

**After:**
```python
user_id = data["user_id"]  # Let KeyError propagate if missing
```

#### Unnecessary Try-Except Blocks
Remove try-except blocks that catch exceptions without specific handling logic.

**Before:**
```python
try:
    result = parse_data(input)
except Exception as e:
    logger.warning(f"Parse failed: {e}")
    result = None
```

**After:**
```python
result = parse_data(input)  # Let exceptions propagate
```

#### Unnecessary None Checks
Remove None checks on fields that should always exist in internal data structures.

**Before:**
```python
if score.metadata is not None and "error" in score.metadata:
    error = score.metadata.get("error", "unknown")
```

**After:**
```python
if "error" in score.metadata:
    error = score.metadata["error"]
```

#### Validating Internal Invariants
Remove validation that checks internal invariants. Trust internal code.

**Before:**
```python
def process_user(user: User) -> str:
    if not isinstance(user, User):
        raise TypeError("Expected User instance")
    if user.email is None:
        raise ValueError("User email is required")
    return user.email
```

**After:**
```python
def process_user(user: User) -> str:
    return user.email
```

### 5. Fix Type Checking Issues

Replace `type: ignore` comments with proper type narrowing.

**Before:**
```python
result = some_function()  # type: ignore
```

**After (Option 1 - Assert isinstance):**
```python
result = some_function()
assert isinstance(result, ExpectedType)
```

**After (Option 2 - Assert not None):**
```python
result = some_optional_function()
assert result is not None
```

**Keep type: ignore only for legitimate library limitations:**
```python
# pandas groupby has incomplete type stubs
grouped = df.groupby("column")  # pyright: ignore[reportUnknownMemberType]
```

### 6. Improve Error Handling

Make code fail early and loudly instead of continuing with invalid state.

**Before:**
```python
try:
    data = json.loads(raw_data)
except json.JSONDecodeError:
    logger.warning("Invalid JSON, using empty dict")
    data = {}
```

**After:**
```python
data = json.loads(raw_data)  # Let JSONDecodeError propagate
```

**Add newlines after raise statements:**
```python
# Before
if value < 0:
    raise ValueError("Value must be positive")
return value * 2

# After
if value < 0:
    raise ValueError("Value must be positive")

return value * 2
```

### 7. Fix Import Style (Google Style Guide)

**Import modules, not individual items:**
```python
# Before
from mypackage.module import FunctionA, FunctionB, ClassC

# After
from mypackage import module
# Use as: module.FunctionA(), module.ClassC()
```

**Move imports to top level:**
```python
# Before
def some_function():
    import expensive_module
    return expensive_module.do_work()

# After
import expensive_module

def some_function():
    return expensive_module.do_work()
```

**Exception: TYPE_CHECKING guard for type-only imports:**
```python
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from mypackage import SomeType
```

### 8. Improve Test Structure

Beyond parameterization, also look for:

**Using real instances instead of MagicMock:**
```python
# Before
mock_target = MagicMock(spec=Target)
mock_target.name = "test"

# After
target = Target(name="test")  # Use real instance of simple class
```

**Direct assertions instead of defensive ones:**
```python
# Before (defensive)
result = some_function()
assert result.get("value") == expected

# After (direct)
result = some_function()
assert result["value"] == expected  # Let KeyError fail the test
```

**Mock only at boundaries:**
```python
# Mock external APIs, not internal code
mocker.patch("requests.get")  # Good - external boundary
mocker.patch("myapp.internal_helper")  # Bad - internal code
```

### 9. Other Patterns to Remove

- Overly verbose error messages that duplicate context
- Redundant validation that duplicates framework behavior
- Empty except blocks or overly broad exception handling
- Unused imports added "just in case"
- Unnecessary intermediate variables that don't improve clarity

## Workflow

1. **Load rules**: Read the project's `CLAUDE.md` and `~/.claude/CLAUDE.md` (if they exist) to understand all applicable style rules and conventions
2. **Identify files to clean**: Run `git diff main...HEAD --name-only` to find files changed on this branch, then focus cleanup on only the changed portions of those files (not pre-existing code)
3. **Review systematically**: Check changed code against both CLAUDE.md rules and the hardcoded patterns above, in priority order:
   - **Priority 1 (CRITICAL)**: Defensive code patterns (sections 4-6) and CLAUDE.md "fail early" rules
   - **Priority 2 (HIGH)**: Test structure and parameterization (sections 3, 8) and CLAUDE.md testing rules
   - **Priority 3 (MEDIUM)**: Type checking issues (section 5) and CLAUDE.md type checking rules
   - **Priority 4 (LOW)**: Comments, docstrings, imports (sections 1, 2, 7) and CLAUDE.md import/style rules
4. **Make changes**: Edit files to fix violations in the new/changed code
5. **Run tests**: Ensure changes don't break anything
6. **Summarize**: Tell the user what was cleaned up, organized by category, noting which changes came from CLAUDE.md rules vs hardcoded patterns

## Notes

- When in doubt, less is more—remove rather than keep
- If a comment or docstring makes you think "obviously", remove it
- Parameterization should make tests more readable, not less—if a test matrix is confusing, keep separate tests
- Always run tests after cleanup to catch any accidental removals
