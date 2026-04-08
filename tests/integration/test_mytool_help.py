"""
Test suite for mytool-help() function behavior.

Tests that mytool-help function works correctly and lists tools.
Custom tool file existence/executability is tested in bats/tools/custom_tools.bats.
"""

import pytest


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
        assert result.exit_code == 0, f"{shell}: mytool_help failed with exit code {result.exit_code}"
        assert len(result.stdout.strip()) > 0, f"{shell}: mytool_help produced no output"


class TestMytoolHelpLists:
    """Test that mytool_help function lists all tools."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_lists_all_tools(self, shell_runner, shell):
        """Test that mytool_help output contains key tool names."""
        result = shell_runner(shell, "mytool_help")
        assert result.exit_code == 0

        output = result.stdout.lower()

        key_tools = [
            "analyze_bash_scripts",
            "check_proxy",
            "install_fd",
            "repo_stats",
        ]

        for tool in key_tools:
            assert tool.lower() in output, f"{shell}: {tool} not found in mytool-help output"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_aliases(self, shell_runner, shell):
        """Test alternative mytool-help aliases."""
        result = shell_runner(shell, "alias mthelp")
        assert result.exit_code == 0, f"{shell}: mthelp alias not defined"


class TestMytoolErrorHandling:
    """Test mytool-help error handling."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_resilient_to_missing_tools(self, shell_runner, shell):
        """Test that mytool_help function handles missing tool descriptions gracefully."""
        result = shell_runner(shell, "mytool_help")
        assert result.exit_code == 0, f"{shell}: mytool_help failed"
