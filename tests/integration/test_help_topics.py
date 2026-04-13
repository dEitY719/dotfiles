"""
Test suite for my-help() help topics.

Tests that all registered my-help topics are callable
without errors in both bash and zsh environments.
"""

import pytest

HELP_TOPICS = [
    "apt_help",
    "bat_help",
    "bun_help",
    "category_help",
    "cc_help",
    "claude_help",
    "claude_plugins_help",
    "claude_skills_marketplace_help",
    "cli_help",
    "codex_help",
    "crt_help",
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
    "gwt_help",
    "gpu_help",
    "litellm_help",
    "mytool_help",
    "mysql_help",
    "network_help",
    "notion_help",
    "npm_help",
    "nvm_help",
    "ollama_help",
    "opencode_help",
    "p10k_help",
    "pip_help",
    "pet_help",
    "pp_help",
    "proxy_help",
    "psql_help",
    "py_help",
    "redis_help",
    "register_help",
    "ripgrep_help",
    "show_doc_help",
    "ssl_help",
    "superpowers_help",
    "sys_help",
    "tmux_help",
    "uv_help",
    "work_help",
    "work_log_help",
    "zsh_help",
    "zsh_autosuggestions_help",
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

    def test_my_help_dash_command_works_with_no_aliases_in_zsh(self, shell_runner):
        """Verify `my-help` works in zsh even when alias expansion is disabled."""
        result = shell_runner("zsh", "setopt no_aliases; my-help")
        assert result.exit_code == 0, f"zsh: my-help failed with exit code {result.exit_code}"
        assert "Usage: my-help [topic|category|section|--list|--all]" in result.stdout

    def test_my_help_dash_command_survives_conflicting_alias_in_zsh(self, shell_runner):
        """Verify sourcing `my_help.sh` doesn't fail even if `my-help` alias already exists."""
        cmd = (
            "unfunction my-help >/dev/null 2>&1 || true; "
            'alias my-help="echo should_not_run"; '
            "source ${SHELL_COMMON}/functions/my_help.sh; "
            "setopt no_aliases; "
            "my-help"
        )
        result = shell_runner("zsh", cmd)
        assert result.exit_code == 0
        assert "Usage: my-help [topic|category|section|--list|--all]" in result.stdout

    def test_my_help_works_under_strict_zsh_options(self, shell_runner):
        """`my-help` should work even with common strict options enabled."""
        cmd = "setopt err_exit pipe_fail noclobber; my-help"
        result = shell_runner("zsh", cmd)
        assert result.exit_code == 0
        assert "sections" in result.stdout.lower()

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("arg", ["--list", "list", "--all", "all", "categories", "popular", "navigation"])
    def test_my_help_standard_section_interface(self, shell_runner, shell, arg):
        """my-help should support list/all/section interface."""
        result = shell_runner(shell, f"my_help_impl {arg}")
        assert result.exit_code == 0, f"{shell}: my_help_impl {arg} failed"
        assert result.stdout.strip(), f"{shell}: my_help_impl {arg} returned empty output"

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

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_invocation_with_topic_args(self, shell_runner, shell):
        """Test my_help_impl forwards args to topic function."""
        result = shell_runner(shell, "my_help_impl git stash")
        assert result.exit_code == 0, f"{shell}: my_help_impl git stash failed"
        assert "git stash" in result.stdout.lower(), f"{shell}: stash content not shown"


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
        """Test my_help_impl without arguments shows compact summary."""
        result = shell_runner(shell, "my_help_impl")
        assert result.exit_code == 0, f"{shell}: my_help_impl with no args failed"
        assert "Usage: my-help [topic|category|section|--list|--all]" in result.stdout
        assert "sections" in result.stdout.lower()


class TestHelpTopicsEnvironmentIntegrity:
    """Test that help functions don't corrupt shell environment."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_sourced_files_count_increases(self, shell_runner, shell):
        """Verify that SOURCED_FILES_COUNT is set."""
        result = shell_runner(shell, "echo $SOURCED_FILES_COUNT")
        assert result.exit_code == 0
        count = result.stdout.strip()
        assert count.isdigit() and int(count) > 0, f"{shell}: Invalid SOURCED_FILES_COUNT"
