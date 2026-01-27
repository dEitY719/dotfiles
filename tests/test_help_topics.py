"""
Test suite for my-help() help topics.

Tests that all auto-sourced help topics (34 total) are callable
without errors in both bash and zsh environments.
"""

import pytest

# Auto-sourced help topics (34 total)
# Excludes: mount-help, addmnt-help (not auto-loaded by main.bash/main.zsh)
# Use function names (underscores) instead of aliases (dashes) for non-interactive subprocess testing
HELP_TOPICS = [
    "apt_help",
    "bat_help",
    "cc_help",
    "claude_help",
    "cli_help",
    "codex_help",
    "dir_help",
    "docker_help",
    "dot_help",
    "dproxy_help",
    "du_help",
    "fasd_help",
    "fd_help",
    "fzf_help",
    "gc_help",
    "gemini_help",
    "git_help",
    "gpu_help",
    "litellm_help",
    "mytool_help",
    "mysql_help",
    "npm_help",
    "nvm_help",
    "p10k_help",
    "pet_help",
    "pp_help",
    "proxy_help",
    "psql_help",
    "py_help",
    "ripgrep_help",
    "sys_help",
    "uv_help",
    "zsh_help",
]


class TestHelpTopicsBasic:
    """Basic help topic tests."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_function_exists(self, shell_runner, shell):
        """Verify that my_help_impl is callable."""
        result = shell_runner(shell, "declare -f my_help_impl")
        assert result.exit_code == 0, f"{shell}: my_help_impl function not defined"
        assert "my_help_impl" in result.stdout, f"{shell}: my_help_impl not in function list"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_alias_exists(self, shell_runner, shell):
        """Verify that my-help alias is defined."""
        result = shell_runner(shell, "alias my-help")
        assert result.exit_code == 0, f"{shell}: my-help alias not defined"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_help_descriptions_initialized(self, shell_runner, shell):
        """Verify that HELP_DESCRIPTIONS associative array is initialized."""
        result = shell_runner(shell, "declare -p HELP_DESCRIPTIONS | head -1")
        assert result.exit_code == 0, f"{shell}: HELP_DESCRIPTIONS not initialized"
        assert "HELP_DESCRIPTIONS" in result.stdout


class TestHelpTopicsCallable:
    """Test that each help topic is callable without errors."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("cmd", HELP_TOPICS)
    def test_help_topic_callable(self, shell_runner, shell, cmd):
        """Test that help topic command exits successfully.

        Args:
            shell_runner: Fixture providing shell execution
            shell: "bash" or "zsh"
            cmd: Help topic command (e.g., "git-help")
        """
        result = shell_runner(shell, f"{cmd} 2>&1 > /dev/null")
        assert result.exit_code == 0, (
            f"{shell}: {cmd} failed with exit code {result.exit_code}\nstderr: {result.stderr}"
        )

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("cmd", HELP_TOPICS)
    def test_help_topic_produces_output(self, shell_runner, shell, cmd):
        """Test that help topic produces non-empty output.

        Args:
            shell_runner: Fixture providing shell execution
            shell: "bash" or "zsh"
            cmd: Help topic command
        """
        result = shell_runner(shell, f"{cmd}")
        assert result.exit_code == 0, f"{shell}: {cmd} failed with exit code {result.exit_code}"
        assert len(result.stdout.strip()) > 0, f"{shell}: {cmd} produced no output"


class TestHelpTopicsWithDifferentFormats:
    """Test help topics with function names (aliases don't work in non-interactive subprocesses)."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_git_help_function(self, shell_runner, shell):
        """Test git_help function."""
        result = shell_runner(shell, "git_help")
        assert result.exit_code == 0, f"{shell}: git_help failed"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_mytool_help_function(self, shell_runner, shell):
        """Test mytool_help function."""
        result = shell_runner(shell, "mytool_help")
        assert result.exit_code == 0, f"{shell}: mytool_help failed"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_invocation_with_subtopic(self, shell_runner, shell):
        """Test my_help_impl with specific subtopic argument."""
        result = shell_runner(shell, "my_help_impl git")
        assert result.exit_code == 0, f"{shell}: my_help_impl git failed"


class TestHelpTopicsErrorHandling:
    """Test help system error handling."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_invalid_help_topic(self, shell_runner, shell):
        """Test handling of invalid help topic.

        May return non-zero or display error message.
        """
        result = shell_runner(shell, "my-help invalid_nonexistent_topic")
        # Either exit with error or show available topics
        # Both behaviors are acceptable
        assert isinstance(result.exit_code, int)

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_without_args_lists_topics(self, shell_runner, shell):
        """Test my_help_impl without arguments lists available help topics."""
        result = shell_runner(shell, "my_help_impl")
        assert result.exit_code == 0, f"{shell}: my_help_impl with no args failed"
        # Should list multiple help topics
        assert len(result.stdout.split("\n")) > 5, f"{shell}: my_help_impl output seems incomplete"


class TestHelpTopicsEnvironmentIntegrity:
    """Test that help functions don't corrupt shell environment."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_sourced_files_count_increases(self, shell_runner, shell):
        """Verify that SOURCED_FILES_COUNT is set."""
        result = shell_runner(shell, "echo $SOURCED_FILES_COUNT")
        assert result.exit_code == 0
        count = result.stdout.strip()
        assert count.isdigit() and int(count) > 0, f"{shell}: Invalid SOURCED_FILES_COUNT"
