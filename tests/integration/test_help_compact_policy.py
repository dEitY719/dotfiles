"""
Compact help policy tests.

Validates the new help UX rules:
- canonical gwt help entrypoint is gwt-help
- default help outputs are compact (<= 15 lines)
"""

import re

import pytest

ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


def _non_empty_line_count(shell_runner, shell, cmd):
    result = shell_runner(shell, f"{cmd} | wc -l")
    assert result.exit_code == 0, f"{shell}: failed to count lines for: {cmd}"
    return int(result.stdout.strip())


def _normalized_lines(text):
    stripped = ANSI_ESCAPE_RE.sub("", text)
    return [line.strip() for line in stripped.splitlines() if line.strip()]


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
    @pytest.mark.parametrize(
        "cmd",
        ["gwt-help", "gwt-help spawn", "gwt-help teardown", "gwt-help --list", "gwt-help --all"],
    )
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


class TestGwtHelpSotInterface:
    """gwt-help supports list/all forms and reuses section rows in --all output."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("cmd", ["gwt_help --list", "gwt_help list", "gwt_help --all", "gwt_help all"])
    def test_gwt_help_supports_list_and_all_forms(self, shell_runner, shell, cmd):
        result = shell_runner(shell, cmd)
        assert result.exit_code == 0, f"{shell}: '{cmd}' failed"
        assert result.stdout.strip(), f"{shell}: '{cmd}' returned empty output"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_gwt_help_summary_uses_standard_template(self, shell_runner, shell):
        result = shell_runner(shell, "gwt_help")
        assert result.exit_code == 0, f"{shell}: 'gwt_help' failed"

        lines = _normalized_lines(result.stdout)
        assert any("Usage: gwt-help [section|--list|--all]" in line for line in lines), (
            f"{shell}: usage template missing"
        )
        assert not any("sections: add | list | remove | prune | spawn | teardown" in line for line in lines), (
            f"{shell}: legacy flat section summary detected"
        )
        assert any("details: gwt-help <section>" in line for line in lines), (
            f"{shell}: details guide missing"
        )

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize(
        ("section_arg", "section_name"),
        [
            ("add", "add"),
            ("ls", "list"),
            ("remove", "remove"),
            ("prune", "prune"),
            ("spawn", "spawn"),
            ("teardown", "teardown"),
        ],
    )
    def test_gwt_help_section_rows_match_all_output(self, shell_runner, shell, section_arg, section_name):
        section_result = shell_runner(shell, f"gwt_help {section_arg}")
        assert section_result.exit_code == 0, f"{shell}: 'gwt_help {section_arg}' failed"

        all_result = shell_runner(shell, "gwt_help --all")
        assert all_result.exit_code == 0, f"{shell}: 'gwt_help --all' failed"

        section_lines = _normalized_lines(section_result.stdout)
        all_lines = _normalized_lines(all_result.stdout)
        assert section_lines, f"{shell}: no rows found for section '{section_name}'"

        for line in section_lines:
            assert line in all_lines, f"{shell}: section '{section_name}' row not found in --all output: '{line}'"
