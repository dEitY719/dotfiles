"""
Compact help policy tests.

Validates the new help UX rules:
- canonical gwt help entrypoint is gwt-help
- default help outputs are compact (<= 15 lines)
"""

import pytest


def _non_empty_line_count(shell_runner, shell, cmd):
    result = shell_runner(shell, f"{cmd} | wc -l")
    assert result.exit_code == 0, f"{shell}: failed to count lines for: {cmd}"
    return int(result.stdout.strip())


class TestCompactHelpLineLimit:
    """Default help outputs must stay within 15 non-empty lines."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize(
        "cmd",
        [
            "git_help",
            "git_help stash",
            "gwt_help",
            "gwt_help spawn",
        ],
    )
    def test_compact_help_within_15_lines(self, shell_runner, shell, cmd):
        lines = _non_empty_line_count(shell_runner, shell, cmd)
        assert lines <= 15, f"{shell}: '{cmd}' exceeded 15 lines ({lines})"


class TestGwtHelpCanonicalEntrypoint:
    """gwt help should be accessed via gwt-help."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_gwt_help_alias_exists(self, shell_runner, shell):
        result = shell_runner(shell, "alias gwt-help")
        assert result.exit_code == 0, f"{shell}: gwt-help alias not defined"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("cmd", ["gwt-help", "gwt-help spawn", "gwt-help teardown"])
    def test_gwt_help_canonical_commands_work(self, shell_runner, shell, cmd):
        if shell == "bash":
            # bash non-interactive mode disables alias expansion by default.
            result = shell_runner(shell, f"shopt -s expand_aliases; eval '{cmd}'")
        else:
            result = shell_runner(shell, cmd)
        assert result.exit_code == 0, f"{shell}: '{cmd}' failed"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("cmd", ["gwt help", "gwt spawn help", "gwt teardown help"])
    def test_legacy_gwt_help_forms_rejected(self, shell_runner, shell, cmd):
        result = shell_runner(shell, cmd)
        assert result.exit_code != 0, f"{shell}: legacy command should fail: {cmd}"
