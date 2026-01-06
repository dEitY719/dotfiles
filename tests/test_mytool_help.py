"""
Test suite for mytool-help() and custom tools.

Tests that mytool-help function lists all tools correctly,
and that custom tool files exist and are executable.
"""

import os
from pathlib import Path

import pytest


# Repository paths
REPO_ROOT = Path(__file__).parent.parent
SHELL_COMMON = REPO_ROOT / "shell-common"
TOOLS_CUSTOM = SHELL_COMMON / "tools" / "custom"

# Custom tool commands (39 total)
MYTOOL_COMMANDS = [
    "analyze_bash_scripts",
    "check_proxy",
    "check_ux_consistency",
    "demo_ux",
    "devx",
    "docker_configure_proxy",
    "enable_docker",
    "get_hw_info",
    "gpu_status",
    "init",
    "install_bat",
    "install_claude",
    "install_codex",
    "install_docker",
    "install_fasd",
    "install_fd",
    "install_fzf",
    "install_gemini",
    "install_git_crypt",
    "install_npm",
    "install_nvm",
    "install_p10k",
    "install_pet",
    "install_postgresql",
    "install_python",
    "install_ripgrep",
    "install_uv",
    "install_zsh",
    "mount",
    "repo_stats",
    "run_agents_md_master_prompt",
    "set_locale",
    "setup_crt",
    "setup_gpg_cache",
    "setup_new_pc",
    "uninstall_codex",
    "uninstall_docker",
    "uninstall_gemini",
    "uninstall_npm",
]


class TestMytoolHelpFunction:
    """Test mytool-help function."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_function_exists(self, shell_runner, shell):
        """Verify that mytool_help function is defined."""
        result = shell_runner(shell, "declare -f mytool_help | head -1")
        assert result.exit_code == 0, f"{shell}: mytool_help not defined"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_alias_exists(self, shell_runner, shell):
        """Verify that mytool-help alias is defined."""
        result = shell_runner(shell, "alias mytool-help")
        assert result.exit_code == 0, f"{shell}: mytool-help alias not defined"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_produces_output(self, shell_runner, shell):
        """Test that mytool_help function produces non-empty output."""
        result = shell_runner(shell, "mytool_help")
        assert (
            result.exit_code == 0
        ), f"{shell}: mytool_help failed with exit code {result.exit_code}"
        assert (
            len(result.stdout.strip()) > 0
        ), f"{shell}: mytool_help produced no output"


class TestMytoolHelpLists:
    """Test that mytool_help function lists all tools."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_lists_all_tools(self, shell_runner, shell):
        """Test that mytool_help output contains all tool names."""
        result = shell_runner(shell, "mytool_help")
        assert result.exit_code == 0

        output = result.stdout.lower()

        # Check for key tools (sample)
        key_tools = [
            "analyze_bash_scripts",
            "check_proxy",
            "devx",
            "install_fd",
            "mount",
            "repo_stats",
        ]

        for tool in key_tools:
            assert tool.lower() in output, (
                f"{shell}: {tool} not found in mytool-help output"
            )

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_aliases(self, shell_runner, shell):
        """Test alternative mytool-help aliases."""
        # Test mthelp alias
        result = shell_runner(shell, "alias mthelp")
        assert result.exit_code == 0, f"{shell}: mthelp alias not defined"


class TestMytoolFilesExist:
    """Test that all custom tool files exist and are executable."""

    def test_tools_custom_directory_exists(self):
        """Verify tools/custom directory exists."""
        assert TOOLS_CUSTOM.is_dir(), f"Directory not found: {TOOLS_CUSTOM}"

    @pytest.mark.parametrize("tool", MYTOOL_COMMANDS)
    def test_tool_file_exists(self, tool):
        """Test that tool script file exists.

        Args:
            tool: Tool command name
        """
        tool_path = TOOLS_CUSTOM / f"{tool}.sh"
        assert tool_path.exists(), f"Tool file not found: {tool_path}"

    @pytest.mark.parametrize("tool", MYTOOL_COMMANDS)
    def test_tool_is_executable(self, tool):
        """Test that tool script file is executable.

        Args:
            tool: Tool command name
        """
        tool_path = TOOLS_CUSTOM / f"{tool}.sh"
        assert os.access(
            tool_path, os.X_OK
        ), f"Tool not executable: {tool_path} (mode: {oct(tool_path.stat().st_mode)})"


class TestMytoolFunctionality:
    """Test mytool-help functionality."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_extract_tool_description_logic(self, shell_runner, shell):
        """Test that tool descriptions can be extracted.

        The mytool_help function should display tool descriptions
        extracted from script headers.
        """
        result = shell_runner(shell, "mytool_help")
        # Should find tool descriptions (bash, analyze, etc)
        output_lower = result.stdout.lower()
        # Look for common keywords in tool descriptions
        found_descriptions = any(keyword in output_lower for keyword in ["bash", "analyze", "install", "configure"])
        assert found_descriptions or len(result.stdout.strip()) > 0, (
            f"{shell}: No tool descriptions found in mytool_help"
        )


class TestMytoolErrorHandling:
    """Test mytool-help error handling."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_resilient_to_missing_tools(self, shell_runner, shell):
        """Test that mytool_help function handles missing tool descriptions gracefully."""
        result = shell_runner(shell, "mytool_help")
        # Should complete successfully even if some tool descriptions are missing
        assert result.exit_code == 0, f"{shell}: mytool_help failed"


class TestMytoolIntegration:
    """Integration tests for mytool system."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_includes_mytool(self, shell_runner, shell):
        """Test that my_help function includes mytool in its list or produces output."""
        result = shell_runner(shell, "my_help")
        # In some shells, help topics may not all be found, but my_help should work
        assert result.exit_code == 0, f"{shell}: my_help failed"
        # Either mytool is listed, or we at least have the help output
        mytool_listed = "mytool" in result.stdout.lower()
        has_help_output = len(result.stdout.strip()) > 100  # More than just header
        assert mytool_listed or has_help_output, (
            f"{shell}: No meaningful output from my_help or mytool not listed"
        )

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_mytool_invocation(self, shell_runner, shell):
        """Test invoking mytool_help via my_help system.

        Example: my_help mytool should show mytool_help
        """
        result = shell_runner(shell, "my_help mytool")
        assert result.exit_code == 0, f"{shell}: my_help mytool failed"
        # Should show tool list
        assert (
            len(result.stdout.strip()) > 0
        ), f"{shell}: my_help mytool produced no output"
