"""Integration tests for `devx_help` (issue #726 / #722 PR 2).

Covers Acceptance Criteria from #726 that are best exercised through the
shell_runner fixture (cross-shell bash + zsh): five-entrypoint equivalence,
SSOT byte-for-byte row matching, devx-help-alias-absent regression guard,
and basic command-guidelines policy (Usage line + sections + 15-line cap).

Every test uses `devx_runner`, a thin wrapper around `shell_runner` that
forces `DOTFILES_ROOT_NO_CANONICALIZE=1` for this file only. Without it,
a developer running pytest from a worktree on a machine that also has
`~/dotfiles` installed would silently exercise the main-repo copy of
`devx.sh` (issue #589 worktree canonicalization) instead of the worktree's
freshly-edited file. The bats helper sets the same flag globally; here we
opt-in per-file so the broader pytest suite's behavior is unchanged.
"""

import pytest


ENTRY_POINTS = [
    "devx",
    "devx -h",
    "devx --help",
    "devx help",
    "my_help_impl devx",
]

SECTIONS = ["lint", "fix", "lint-helpfunc", "lint-deadcode", "stat"]


@pytest.fixture
def devx_runner(shell_runner):
    """Wrap shell_runner with DOTFILES_ROOT_NO_CANONICALIZE=1 so the worktree's
    own `shell-common/functions/devx.sh` is what gets sourced — not whatever
    the main install in `~/dotfiles` happens to have."""

    def runner(shell, cmd):
        return shell_runner(
            shell, cmd, env_overrides={"DOTFILES_ROOT_NO_CANONICALIZE": "1"}
        )

    return runner


class TestDevxEntryPoints:
    """All five entry points must produce equivalent summary output."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_devx_function_exists(self, devx_runner, shell):
        result = devx_runner(shell, "declare -f devx >/dev/null && echo ok")
        assert result.exit_code == 0, f"{shell}: devx not defined ({result.stderr})"
        assert "ok" in result.stdout

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_devx_help_function_exists(self, devx_runner, shell):
        result = devx_runner(shell, "declare -f devx_help >/dev/null && echo ok")
        assert result.exit_code == 0, f"{shell}: devx_help not defined ({result.stderr})"
        assert "ok" in result.stdout

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("entry", ENTRY_POINTS)
    def test_entry_point_succeeds(self, devx_runner, shell, entry):
        result = devx_runner(shell, entry)
        assert result.exit_code == 0, f"{shell}: '{entry}' failed ({result.stderr})"
        assert result.stdout.strip(), f"{shell}: '{entry}' produced no output"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_five_entry_points_equivalent(self, devx_runner, shell):
        """All five entry points should produce byte-for-byte identical output."""
        outputs = []
        for entry in ENTRY_POINTS:
            result = devx_runner(shell, entry)
            assert result.exit_code == 0, f"{shell}: '{entry}' failed"
            outputs.append(result.stdout)

        # Use the first as the reference; all others must equal it.
        ref = outputs[0]
        for entry, out in zip(ENTRY_POINTS[1:], outputs[1:], strict=False):
            assert out == ref, (
                f"{shell}: entry-point output mismatch.\n"
                f"  reference ('{ENTRY_POINTS[0]}'):\n{ref!r}\n"
                f"  this one  ('{entry}'):\n{out!r}"
            )


class TestDevxHelpAliasAbsent:
    """§7.6.1 deviation — the `devx-help` dash-form alias must NOT exist."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_devx_help_alias_not_defined(self, devx_runner, shell):
        result = devx_runner(shell, "type devx-help 2>&1; echo rc=$?")
        # `type devx-help` should fail (no alias, no function, no binary).
        # The `rc=` suffix is our success-detect marker regardless of shell.
        assert "rc=0" not in result.stdout, (
            f"{shell}: devx-help unexpectedly resolved — §7.6.1 regression."
        )


class TestDevxSsotRowConsistency:
    """SSOT §1 — `devx help <section>` rows ≡ `devx help --all` same section."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("section", SECTIONS)
    def test_section_rows_in_all(self, devx_runner, shell, section):
        section_result = devx_runner(shell, f"devx help {section}")
        all_result = devx_runner(shell, "devx help --all")

        assert section_result.exit_code == 0, f"{shell}: devx help {section} failed"
        assert all_result.exit_code == 0, f"{shell}: devx help --all failed"

        # Every non-empty line of the per-section view must appear verbatim in
        # the --all dump. The --all view also adds the `ux_section` header; we
        # only require the rows to match.
        for line in section_result.stdout.splitlines():
            if not line.strip():
                continue
            assert line in all_result.stdout, (
                f"{shell}: row missing from --all view for section '{section}': {line!r}"
            )


class TestDevxHelpFormatPolicy:
    """`devx help` (default) must follow command-guidelines.md §출력 정책."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_default_summary_line_budget(self, devx_runner, shell):
        result = devx_runner(shell, "devx help")
        assert result.exit_code == 0
        # ≤ 15 lines per command-guidelines.md §출력 정책 / §2.
        lines = result.stdout.splitlines()
        assert len(lines) <= 15, (
            f"{shell}: devx help summary is {len(lines)} lines (>15):\n{result.stdout}"
        )

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_default_summary_uses_template(self, devx_runner, shell):
        result = devx_runner(shell, "devx help")
        assert result.exit_code == 0
        # Template: `Usage: devx help [section|--list|--all]` + `sections` bullet
        assert "Usage: devx help" in result.stdout
        assert "sections" in result.stdout.lower()

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_default_summary_mentions_all_sections(self, devx_runner, shell):
        result = devx_runner(shell, "devx help")
        assert result.exit_code == 0
        for section in SECTIONS:
            assert section in result.stdout, (
                f"{shell}: section '{section}' missing from summary"
            )


class TestDevxHelpRegistration:
    """my_help.sh must register devx_help so my-help discovers it."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_help_descriptions_contains_devx_help(self, devx_runner, shell):
        # Trigger lazy default-registration by running my_help_impl first.
        result = devx_runner(
            shell,
            'my_help_impl >/dev/null 2>&1; echo "${HELP_DESCRIPTIONS[devx_help]}"',
        )
        assert result.exit_code == 0, f"{shell}: HELP_DESCRIPTIONS lookup failed"
        assert "[Development]" in result.stdout

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_category_members_contains_devx(self, devx_runner, shell):
        result = devx_runner(
            shell,
            'my_help_impl >/dev/null 2>&1; echo "${HELP_CATEGORY_MEMBERS[development]}"',
        )
        assert result.exit_code == 0
        assert "devx" in result.stdout.split()


class TestDevxLintHelpfuncSelfCheck:
    """`devx lint-helpfunc` must pass on the repo itself (AC self-check)."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_lint_helpfunc_exits_zero(self, devx_runner, shell):
        result = devx_runner(shell, "devx lint-helpfunc")
        assert result.exit_code == 0, (
            f"{shell}: devx lint-helpfunc returned {result.exit_code}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
