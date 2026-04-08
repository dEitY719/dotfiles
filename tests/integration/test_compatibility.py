"""
Test suite for bash/zsh compatibility.

Tests that dotfiles initialization works correctly in both shells,
and that help systems function consistently across environments.
"""

import pytest


class TestDotfilesInitialization:
    """Test dotfiles initialization in bash and zsh."""

    def test_bash_initialization(self, shell_runner):
        """Test bash/main.bash initialization succeeds."""
        result = shell_runner("bash", "echo initialized")
        assert result.exit_code == 0, "bash initialization failed"
        assert "initialized" in result.stdout

    def test_zsh_initialization(self, shell_runner):
        """Test zsh/main.zsh initialization succeeds."""
        result = shell_runner("zsh", "echo initialized")
        assert result.exit_code == 0, "zsh initialization failed"
        assert "initialized" in result.stdout

    def test_bash_sources_files(self, shell_runner):
        """Test that bash loads configuration files."""
        result = shell_runner("bash", "echo $SOURCED_FILES_COUNT")
        assert result.exit_code == 0
        count = result.stdout.strip()
        assert count.isdigit() and int(count) > 0, "bash: No files sourced"

    def test_zsh_sources_files(self, shell_runner):
        """Test that zsh loads configuration files."""
        result = shell_runner("zsh", "echo $SOURCED_FILES_COUNT")
        assert result.exit_code == 0
        count = result.stdout.strip()
        assert count.isdigit() and int(count) > 0, "zsh: No files sourced"


class TestFunctionAvailability:
    """Test that functions are available in both shells."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_function_available(self, shell_runner, shell):
        """Test my_help_impl function is available."""
        result = shell_runner(shell, "declare -f my_help_impl | head -1")
        assert result.exit_code == 0, f"{shell}: my_help_impl function not available"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_alias_available(self, shell_runner, shell):
        """Test my-help alias is available."""
        result = shell_runner(shell, "alias my-help")
        assert result.exit_code == 0, f"{shell}: my-help alias not available"


class TestEnvironmentVariables:
    """Test environment variable setup and availability."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_shell_common_path_set(self, shell_runner, shell):
        """Test SHELL_COMMON environment variable is set."""
        result = shell_runner(shell, 'test -n "$SHELL_COMMON" && echo ok')
        assert result.exit_code == 0, f"{shell}: SHELL_COMMON not set"
        assert "ok" in result.stdout, f"{shell}: SHELL_COMMON is empty"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_dotfiles_root_path_set(self, shell_runner, shell):
        """Test DOTFILES_ROOT environment variable is set."""
        result = shell_runner(shell, 'test -n "$DOTFILES_ROOT" && echo ok')
        assert result.exit_code == 0, f"{shell}: DOTFILES_ROOT not set"
        assert "ok" in result.stdout, f"{shell}: DOTFILES_ROOT is empty"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_sourced_files_count_integer(self, shell_runner, shell):
        """Test SOURCED_FILES_COUNT is a valid integer."""
        result = shell_runner(shell, "echo $SOURCED_FILES_COUNT")
        assert result.exit_code == 0
        count = result.stdout.strip()
        assert count.isdigit(), f"{shell}: SOURCED_FILES_COUNT is not an integer: {count}"
        assert int(count) > 0, f"{shell}: SOURCED_FILES_COUNT is 0"


class TestShellDifferences:
    """Test handling of shell-specific features."""

    def test_bash_specific_features(self, shell_runner):
        """Test bash can handle bash-specific syntax."""
        result = shell_runner("bash", '[[ -n "$BASH" ]] && echo bash')
        assert result.exit_code == 0
        assert "bash" in result.stdout

    def test_zsh_specific_features(self, shell_runner):
        """Test zsh can handle zsh-specific syntax."""
        result = shell_runner("zsh", '[[ -n "$ZSH_VERSION" ]] && echo zsh')
        assert result.exit_code == 0
        assert "zsh" in result.stdout

    def test_posix_shell_features_in_bash(self, shell_runner):
        """Test POSIX shell features work in bash."""
        result = shell_runner("bash", '[ -n "$HOME" ] && echo posix')
        assert result.exit_code == 0
        assert "posix" in result.stdout

    def test_posix_shell_features_in_zsh(self, shell_runner):
        """Test POSIX shell features work in zsh."""
        result = shell_runner("zsh", '[ -n "$HOME" ] && echo posix')
        assert result.exit_code == 0
        assert "posix" in result.stdout


class TestHelpSystemConsistency:
    """Test that help system behaves consistently across shells."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_help_descriptions_available(self, shell_runner, shell):
        """Test HELP_DESCRIPTIONS array exists."""
        result = shell_runner(shell, "declare -p HELP_DESCRIPTIONS | head -1")
        assert result.exit_code == 0, f"{shell}: HELP_DESCRIPTIONS not available"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_my_help_lists_topics(self, shell_runner, shell):
        """Test my_help_impl command lists help topics."""
        result = shell_runner(shell, "my_help_impl")
        assert result.exit_code == 0, f"{shell}: my_help_impl failed"
        lines = len([line for line in result.stdout.strip().split("\n") if line])
        assert lines > 10, f"{shell}: my_help_impl lists too few topics: {lines}"

    def test_bash_zsh_help_output_similar(self, shell_runner):
        """Test that bash and zsh produce similar help output format."""
        result_bash = shell_runner("bash", "my_help_impl")
        result_zsh = shell_runner("zsh", "my_help_impl")

        assert result_bash.exit_code == 0, "bash: my_help_impl failed"
        assert result_zsh.exit_code == 0, "zsh: my_help_impl failed"

        # Both should produce output
        assert len(result_bash.stdout.strip()) > 0, "bash: no output"
        assert len(result_zsh.stdout.strip()) > 0, "zsh: no output"

    def test_bash_zsh_mytool_output_similar(self, shell_runner):
        """Test that bash and zsh mytool_help output is similar."""
        result_bash = shell_runner("bash", "mytool_help")
        result_zsh = shell_runner("zsh", "mytool_help")

        assert result_bash.exit_code == 0, "bash: mytool_help failed"
        assert result_zsh.exit_code == 0, "zsh: mytool_help failed"

        # Both should produce output
        assert len(result_bash.stdout.strip()) > 0, "bash: no output"
        assert len(result_zsh.stdout.strip()) > 0, "zsh: no output"


class TestErrorHandling:
    """Test error handling consistency."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_undefined_function_error(self, shell_runner, shell):
        """Test that undefined function produces error."""
        result = shell_runner(shell, "undefined_nonexistent_function")
        # Should fail with non-zero exit
        assert result.exit_code != 0, f"{shell}: undefined function did not error"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_invalid_syntax_error(self, shell_runner, shell):
        """Test that invalid syntax produces error."""
        result = shell_runner(shell, "[[ ]]")  # Incomplete test
        # Should fail
        assert result.exit_code != 0, f"{shell}: invalid syntax did not error"
