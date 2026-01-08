# Test Suite Documentation

Comprehensive pytest-based test suite for the dotfiles project, validating bash/zsh compatibility, help system consistency, and custom tool functionality.

## Quick Start

Run all tests:
```bash
./tests/test
```

With verbose output:
```bash
./tests/test -v
```

Or use the dtests alias:
```bash
dtests -v
```

## Test Structure

### conftest.py (Pytest Configuration)

Central pytest configuration providing the `shell_runner` fixture for executing bash/zsh commands in isolated environments.

**Key Features:**

- **Isolated environment**: Each test gets a temporary HOME and ZDOTDIR to prevent config interference
- **Shell agnostic**: Single fixture supports both bash and zsh testing
- **Result capture**: Returns `ShellRunnerResult` with exit_code, stdout, stderr
- **Test-mode enabled**: Sets DOTFILES_TEST_MODE=1 to prevent side effects
- **Force initialization**: Uses DOTFILES_FORCE_INIT=1 for non-interactive shells

**Fixture Usage:**

```python
def test_example(shell_runner):
    result = shell_runner("bash", "echo $SHELL_COMMON")
    assert result.exit_code == 0
    assert "shell-common" in result.stdout
```

### test_help_topics.py (Help System Tests)

Tests 34 auto-sourced help topics for callable status and output validity.

**Excluded Help Topics:**

- `mount-help`: Requires /etc/mtab (filesystem-specific)
- `addmnt-help`: Requires /etc/mtab (filesystem-specific)

**Test Coverage:**

- Function/alias existence for each help topic
- Function callability in bash and zsh (68 parametrized tests)
- Output validation (non-empty, contains expected sections)
- Error handling (undefined topics report errors)

**Example:**

```bash
# Topics tested: aliasimp, ansiexpl, ansitest, bash, buildhelp, ...
declare -f mount_help > /dev/null && echo ok  # Validates function exists
```

### test_mytool_help.py (Custom Tools Tests)

Tests 39 custom tool implementations in `shell-common/tools/custom/`.

**Test Coverage:**

- File existence and +x executable permission
- Function callable in bash and zsh
- Integration with help system
- Environment variable setup (DOTFILES_ROOT, SHELL_COMMON)

**Example Tool Files:**

- devx.sh: Project development commands
- init.sh: Centralized initialization
- repo_stats.sh: Repository statistics
- mount.sh: Mount point management

### test_compatibility.py (Bash/Zsh Parity)

32 tests validating feature parity between bash and zsh.

**Test Categories:**

1. **Initialization Tests (4):**

   - Dotfiles initialization succeeds in both shells
   - Configuration files are sourced in both shells

2. **Function Availability Tests (4):**

   - `my_help` function available
   - `mytool_help` function available
   - Aliases registered correctly

3. **Environment Variables Tests (3):**

   - SHELL_COMMON, DOTFILES_ROOT, SOURCED_FILES_COUNT set correctly
   - Values non-empty and valid

4. **Shell-Specific Features Tests (4):**

   - Bash handles [[ ]] syntax
   - Zsh handles [[ ]] syntax
   - Both handle POSIX [ ] syntax

5. **Help System Consistency Tests (4):**

   - HELP_DESCRIPTIONS array exists
   - my_help function produces output
   - mytool_help function produces output
   - Both shells produce similar help output

6. **Error Handling Tests (2):**

   - Undefined functions produce errors
   - Invalid syntax produces errors

## Environment Variables

### DOTFILES_TEST_MODE=1

Prevents side effects during test execution:

- **devx.sh**: Skips symlink creation in ~/.local/bin
- **init.sh**: Early returns, prevents install_*.sh execution
- **Custom tools**: Can check this to skip external operations

### DOTFILES_FORCE_INIT=1

Forces full initialization in non-interactive shells:

- Bypasses DOTFILES_SUPPRESS_MESSAGE checks
- Enables function/alias loading in subprocesses
- Required for pytest subprocess testing

### DOTFILES_ROOT, SHELL_COMMON

Auto-detected by conftest.py based on current working directory. Available in all test environments.

## Running Tests

### All Tests

```bash
./tests/test
```

### Verbose Output

```bash
./tests/test -v
```

### Specific Test File

```bash
pytest tests/test_help_topics.py
```

### Specific Test Class

```bash
pytest tests/test_help_topics.py::TestHelpTopics
```

### Specific Test

```bash
pytest tests/test_compatibility.py::TestDotfilesInitialization::test_bash_initialization
```

### With Coverage

```bash
python3 -m pytest tests/ --cov=. --cov-report=html
```

## Adding New Tests

### Adding Help Topic Tests

1. Add your help topic function to `shell-common/functions/`
2. Register in `HELP_DESCRIPTIONS` array in appropriate shell-common file
3. If the topic requires special handling, add to excludes in test_help_topics.py
4. Run tests to verify: `pytest tests/test_help_topics.py -v`

### Adding Custom Tool Tests

1. Create your tool in `shell-common/tools/custom/yourname.sh`
2. Ensure it sources `init.sh` for DOTFILES_ROOT detection
3. Make it executable: `chmod +x shell-common/tools/custom/yourname.sh`
4. Add function/alias tests to test_mytool_help.py if needed
5. Run: `pytest tests/test_mytool_help.py -v`

### Adding Compatibility Tests

For new features that should work in both bash and zsh:

```python
@pytest.mark.parametrize("shell", ["bash", "zsh"])
def test_my_feature(self, shell_runner, shell):
    """Test my feature works in both shells."""
    result = shell_runner(shell, "my_command")
    assert result.exit_code == 0
    assert "expected_output" in result.stdout
```

## Test Mode Behavior

When running tests, DOTFILES_TEST_MODE=1 prevents:

1. **Package Installation**: install_python.sh, install_node.sh, etc. won't run
2. **Symlink Creation**: devx self-heal skipped
3. **External Calls**: Tools can check and skip expensive operations
4. **Side Effects**: File system modifications minimized

To implement test-mode detection in custom tools:

```bash
if [ "${DOTFILES_TEST_MODE:-0}" = "1" ]; then
    # Skip external operations
    return 0
fi
```

## Requirements

- Python 3.10+
- pytest
- pexpect (for shell interaction)

Install with:
```bash
pip install pytest pexpect
```

Or use tox:
```bash
tox -e test
```

## Troubleshooting

### Tests timeout
Increase timeout in pytest.ini or use:
```bash
pytest --timeout=30
```

### Shell not found
Ensure bash and zsh are installed:
```bash
which bash zsh
```

### Import errors
Install test dependencies:
```bash
pip install -e .[dev]
```

### Test mode not working
Verify DOTFILES_TEST_MODE is set:
```bash
DOTFILES_TEST_MODE=1 bash -c 'echo $DOTFILES_TEST_MODE'
```

## CI/CD Integration

Tests run automatically on GitHub Actions for:
- Python 3.10, 3.11, 3.12, 3.13
- All commits to main and pull requests

View results in Actions tab on GitHub.

## Test Statistics

- **Total tests**: 279 collected
- **Help topic tests**: 68 (34 topics × 2 shells)
- **Custom tool tests**: 76
- **Compatibility tests**: 32
- **Execution time**: ~15-30 seconds

## See Also

- docs/abc-review-C.md: Test plan and architecture
- tests/test: Test runner with dependency checking
- .github/workflows/test.yml: GitHub Actions CI configuration
