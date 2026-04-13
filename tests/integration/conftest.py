"""
Test configuration and fixtures for dotfiles test suite.

Provides shell runner fixture that sets up isolated test environment
with temporary HOME/ZDOTDIR and environment variables.
"""

import os
import subprocess
import tempfile
from pathlib import Path

import pytest

# Repository root detection
REPO_ROOT = Path(__file__).parent.parent.parent
SHELL_COMMON = REPO_ROOT / "shell-common"
BASH_DIR = REPO_ROOT / "bash"
ZSH_DIR = REPO_ROOT / "zsh"


# pytest-xdist support: provide worker_id fixture for all test modes
@pytest.fixture
def worker_id(request):
    """Get pytest-xdist worker ID.

    Returns:
        - "master" when running sequentially (no xdist)
        - "gw0", "gw1", etc. when running with pytest-xdist
    """
    if hasattr(request.config, "workerinput"):
        # Running with pytest-xdist
        return request.config.workerinput["workerid"]
    else:
        # Running without pytest-xdist
        return "master"


class ShellRunnerResult:
    """Result from executing shell command."""

    def __init__(self, exit_code: int, stdout: str, stderr: str):
        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr

    def __repr__(self) -> str:
        return f"ShellRunnerResult(exit_code={self.exit_code})"


def run_command(
    cmd: str,
    shell: str = "bash",
    env: dict = None,
    cwd: str = None,
) -> ShellRunnerResult:
    """
    Execute command in specified shell with custom environment.

    Args:
        cmd: Command to execute
        shell: Shell type ("bash" or "zsh")
        env: Environment variables (merged with current env)
        cwd: Working directory

    Returns:
        ShellRunnerResult with exit_code, stdout, stderr
    """
    # Prepare environment
    run_env = os.environ.copy()
    if env:
        run_env.update(env)

    # Construct shell invocation
    if shell == "bash":
        # bash: non-interactive, no profile/rc, login shell
        full_cmd = f"bash --noprofile --norc -lc '{cmd}'"
    elif shell == "zsh":
        # zsh: force user rc off, login shell
        full_cmd = f"zsh -f -lc '{cmd}'"
    else:
        raise ValueError(f"Unknown shell: {shell}")

    try:
        result = subprocess.run(
            full_cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=60,
            cwd=cwd,
            env=run_env,
        )
        return ShellRunnerResult(
            exit_code=result.returncode,
            stdout=result.stdout,
            stderr=result.stderr,
        )
    except subprocess.TimeoutExpired:
        return ShellRunnerResult(
            exit_code=124,
            stdout="",
            stderr="Command timed out after 60 seconds",
        )
    except Exception as e:
        return ShellRunnerResult(
            exit_code=255,
            stdout="",
            stderr=f"Error executing command: {str(e)}",
        )


@pytest.fixture
def temp_home(worker_id):
    """Create and cleanup temporary HOME directory (xdist-aware).

    Each pytest-xdist worker gets a unique temporary directory
    to avoid conflicts during parallel execution.
    """
    # worker_id is "master" for non-parallel or "gw0", "gw1", etc. for parallel
    with tempfile.TemporaryDirectory(prefix=f"dotfiles_test_{worker_id}_") as tmpdir:
        yield tmpdir


@pytest.fixture
def shell_runner(temp_home):
    """
    Fixture providing shell_runner function for executing commands.

    Sets up isolated test environment with:
    - Temporary HOME and ZDOTDIR (prevents user config interference)
    - DOTFILES_FORCE_INIT=1 (forces bash initialization in non-interactive mode)
    - DOTFILES_TEST_MODE=1 (signals test mode to custom tools)
    - DOTFILES_ROOT and SHELL_COMMON paths
    - Disabled XDG directories (further isolation)

    Returns:
        Function: runner(shell, cmd, env_overrides=None) -> ShellRunnerResult
    """

    def runner(shell: str, cmd: str, env_overrides: dict = None) -> ShellRunnerResult:
        """
        Run command in isolated test environment.

        Args:
            shell: "bash" or "zsh"
            cmd: Command to execute
            env_overrides: Optional dict of additional environment variables

        Returns:
            ShellRunnerResult with exit_code, stdout, stderr
        """
        # Base environment for tests
        test_env = {
            "DOTFILES_FORCE_INIT": "1",  # Bypass bash interactive check
            "DOTFILES_TEST_MODE": "1",  # Signal test mode to tools
            "DOTFILES_ROOT": str(REPO_ROOT),
            "SHELL_COMMON": str(SHELL_COMMON),
            "HOME": temp_home,  # Temporary home
            "ZDOTDIR": temp_home,  # Prevent zsh user rc loading
            "XDG_CONFIG_HOME": temp_home,  # Further isolation
            "XDG_CACHE_HOME": temp_home,
            "XDG_DATA_HOME": temp_home,
            # Clear interactive indicators
            "TERM": "dumb",
        }

        # Apply overrides if provided
        if env_overrides:
            test_env.update(env_overrides)

        # Build initialization command
        if shell == "bash":
            init_cmd = f"source {BASH_DIR}/main.bash; {cmd}"
        elif shell == "zsh":
            init_cmd = f"source {ZSH_DIR}/main.zsh; {cmd}"
        else:
            raise ValueError(f"Unknown shell: {shell}")

        return run_command(init_cmd, shell=shell, env=test_env)

    return runner


@pytest.fixture
def dotfiles_state(shell_runner):
    """
    Fixture providing function to check dotfiles initialization state.

    Useful for verifying that environment variables and sourced files
    are correctly initialized.

    Returns:
        Function: check_state(shell) -> dict with state info
    """

    def check_state(shell: str) -> dict:
        """Check dotfiles initialization state."""
        checks = {}

        # Check SOURCED_FILES_COUNT
        result = shell_runner(shell, "echo $SOURCED_FILES_COUNT")
        checks["sourced_files_count"] = result.stdout.strip()
        checks["sourced_files_count_exit"] = result.exit_code

        # Check SHELL_COMMON variable
        result = shell_runner(shell, "echo $SHELL_COMMON")
        checks["shell_common_path"] = result.stdout.strip()
        checks["shell_common_path_exit"] = result.exit_code

        # Check if my_help_impl function exists
        result = shell_runner(shell, "declare -f my_help_impl | head -1")
        checks["my_help_impl_exists"] = result.exit_code == 0

        # Check if my-help alias exists
        result = shell_runner(shell, "alias my-help")
        checks["my_help_alias_exists"] = result.exit_code == 0

        return checks

    return check_state


# Pytest hooks for better output


def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers",
        "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    )
    config.addinivalue_line(
        "markers",
        "bash: marks tests that run in bash shell",
    )
    config.addinivalue_line(
        "markers",
        "zsh: marks tests that run in zsh shell",
    )


def pytest_collection_modifyitems(config, items):
    """Add markers to tests based on name."""
    for item in items:
        # Mark bash/zsh tests
        if "bash" in item.nodeid:
            item.add_marker(pytest.mark.bash)
        if "zsh" in item.nodeid:
            item.add_marker(pytest.mark.zsh)
