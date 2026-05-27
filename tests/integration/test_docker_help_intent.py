"""
Tests for docker-help intent-based extensions (#779).

Two additive entry points on top of #777's PWD-aware `here` recommender
(which is separately covered by tests/bats/functions/docker_help_recommend.bats):

  - docker-help i-want   goal-based lookup (intent -> alias -> raw)
  - docker-help --map    intent -> alias -> raw command table
"""

import re

import pytest

ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


def _plain(text: str) -> str:
    return ANSI_ESCAPE_RE.sub("", text)


class TestDockerHelpIntent:
    """`docker-help i-want` exposes intent -> alias -> raw command rows."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("alias_arg", ["i-want", "iwant", "intent", "want"])
    def test_intent_aliases_exit_clean(self, shell_runner, shell, alias_arg):
        result = shell_runner(shell, f"docker_help {alias_arg}")
        assert result.exit_code == 0, f"{shell}: 'docker_help {alias_arg}' failed: {result.stderr}"
        assert result.stdout.strip(), f"{shell}: 'docker_help {alias_arg}' empty output"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_intent_contains_alias_and_raw_command(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help i-want")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        assert "dcud" in plain
        assert "docker compose up -d" in plain
        assert "dcd" in plain
        assert "docker compose down" in plain

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_intent_includes_overlay_pattern(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help i-want")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        assert "-f" in plain and "overlay" in plain.lower(), (
            f"{shell}: overlay guidance missing from i-want output"
        )


class TestDockerHelpMap:
    """`docker-help --map` is the explicit three-column header view."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_map_flag_runs(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help --map")
        assert result.exit_code == 0, f"{shell}: stderr={result.stderr}"
        plain = _plain(result.stdout)
        assert "Intent" in plain
        assert "Alias" in plain
        assert "Raw command" in plain

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_map_section_keyword_runs(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help map")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        assert "dcud" in plain
        assert "docker compose up -d" in plain


class TestDockerHelpSummaryDiscoverability:
    """Default summary must mention the new entry points so they are findable.

    `--help` is used as the discriminator instead of bare `docker_help`,
    because #777 made bare `docker_help` switch to PWD-aware recommendation
    when a compose file is present in CWD. `--help` always renders the
    canonical summary.
    """

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_summary_mentions_i_want(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help --help")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        assert "i-want" in plain

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_summary_mentions_map(self, shell_runner, shell):
        result = shell_runner(shell, "docker_help --help")
        assert result.exit_code == 0
        plain = _plain(result.stdout)
        assert "--map" in plain
