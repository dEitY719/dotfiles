"""
Tests for docker-help raw-command-first learning surfaces (#899).

Three additive surfaces on top of the existing alias-first help:

  - docker-help raw [section]   raw-first, copy-paste-ready full commands (F-1)
  - docker-help <alias>         reverse lookup: alias -> raw command (F-2)
  - intent map / resources      full-prune raw command surfaced + dprune
                                scope clarified (F-3)
  - summary mentions raw/lookup so they are discoverable (F-4)
"""

import re

import pytest

ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


def _plain(text: str) -> str:
    return ANSI_ESCAPE_RE.sub("", text)


@pytest.fixture
def shell_runner(shell_runner):
    """Force DOTFILES_ROOT_NO_CANONICALIZE=1 so the worktree's own
    `shell-common/functions/devops_help.sh` is sourced — not whatever the
    main install in `~/dotfiles` happens to have (issue #589 worktree
    canonicalization). Mirrors test_devx_help.py's `devx_runner`."""
    base = shell_runner

    def runner(shell, cmd, env_overrides=None):
        merged = {"DOTFILES_ROOT_NO_CANONICALIZE": "1"}
        if env_overrides:
            merged.update(env_overrides)
        return base(shell, cmd, env_overrides=merged)

    return runner


class TestDockerHelpRaw:
    """`docker-help raw [section]` renders portable raw commands."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_raw_all_runs(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help raw")
        assert result.exit_code == 0, f"{shell}: stderr={result.stderr}"
        plain = _plain(result.stdout)
        assert "docker compose up -d" in plain
        assert "docker system prune -f" in plain

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("section_arg", ["resources", "prune"])
    def test_raw_resources_has_full_prune(self, shell_runner, shell, section_arg):
        result = shell_runner(shell, f"docker_help raw {section_arg}")
        assert result.exit_code == 0, f"{shell}: stderr={result.stderr}"
        plain = _plain(result.stdout)
        # The canonical deep-prune command the user wants to learn.
        assert "docker system prune -a --volumes" in plain

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_raw_flag_form(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help --raw resources")
        assert result.exit_code == 0
        assert "docker system prune -a --volumes" in _plain(result.stdout)

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_raw_unknown_section_fails(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help raw nope")
        assert result.exit_code != 0, f"{shell}: unknown raw section should fail"


class TestDockerHelpReverseLookup:
    """`docker-help <alias>` teaches the raw command behind an alias."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_dprune_reverse(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help dprune")
        assert result.exit_code == 0, f"{shell}: stderr={result.stderr}"
        plain = _plain(result.stdout)
        assert "docker system prune -f" in plain
        assert "->" in plain
        # dprune is the basic form — must NOT be confused with the deep one.
        assert "-a --volumes" not in plain

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_dprune_full_reverse(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help dprune_full")
        assert result.exit_code == 0
        assert "docker system prune -a --volumes" in _plain(result.stdout)

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_unknown_section_still_errors(self, shell_runner, shell):
        # A token that is neither a section nor a known alias preserves the
        # original unknown-section error path (regression guard).
        result = shell_runner(shell, "docker_help totally-bogus")
        assert result.exit_code != 0


class TestDockerHelpDataFixes:
    """F-3: full-prune raw command surfaced; dprune scope clarified."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_intent_map_has_full_prune(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help --map")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        assert "reclaim everything" in plain
        assert "docker system prune -a --volumes" in plain

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_resources_section_distinguishes_prune_scope(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help resources")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        # dprune_full now shows its real flags inline so it can't be mistaken
        # for the lighter dprune.
        assert "system prune -a --volumes" in plain


class TestDockerHelpDiscoverability:
    """F-4: summary advertises the new learning surfaces."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_summary_mentions_raw_and_lookup(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help --help")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        assert "raw" in plain
        assert "lookup" in plain
