"""
Compact help policy tests.

Validates help UX rules from docs/standards/command-guidelines.md:
- canonical *-help entrypoints
- default help outputs are compact (<= 15 lines)
- standardized summary/list/all interface
"""

import re

import pytest

ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")

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


def _non_empty_line_count(shell_runner, shell, cmd):
    result = shell_runner(shell, f"{cmd} | wc -l")
    assert result.exit_code == 0, f"{shell}: failed to count lines for: {cmd}"
    return int(result.stdout.strip())


def _normalized_lines(text):
    stripped = ANSI_ESCAPE_RE.sub("", text)
    return [line.strip() for line in stripped.splitlines() if line.strip()]


def _func_to_alias(func_name):
    topic = func_name.removesuffix("_help")
    return f"{topic.replace('_', '-')}-help"


def _first_section_token(list_output):
    stopwords = {"usage", "try", "sections", "section", "help", "and", "or"}
    stripped = ANSI_ESCAPE_RE.sub("", list_output.lower())
    tokens = re.findall(r"[a-z0-9_-]+", stripped)
    for token in tokens:
        if token in stopwords:
            continue
        if token.endswith("-help"):
            continue
        return token
    return "overview"


class TestHelpStandardInterface:
    """All my-help topics should expose the standard help interface."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("func_name", HELP_TOPICS)
    def test_default_help_within_15_lines(self, shell_runner, shell, func_name):
        lines = _non_empty_line_count(shell_runner, shell, func_name)
        assert lines <= 15, f"{shell}: '{func_name}' exceeded 15 lines ({lines})"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize(
        "func_name",
        HELP_TOPICS,
    )
    def test_default_help_uses_standard_template(self, shell_runner, shell, func_name):
        result = shell_runner(shell, func_name)
        assert result.exit_code == 0, f"{shell}: '{func_name}' failed"
        lines = _normalized_lines(result.stdout)

        assert any("[section|--list|--all]" in line for line in lines), (
            f"{shell}: '{func_name}' missing standard usage template"
        )
        assert any("sections" in line.lower() for line in lines), f"{shell}: '{func_name}' missing sections summary"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("func_name", HELP_TOPICS)
    def test_supports_list_and_all(self, shell_runner, shell, func_name):
        for arg in ("--list", "list", "--all", "all"):
            result = shell_runner(shell, f"{func_name} {arg}")
            assert result.exit_code == 0, f"{shell}: '{func_name} {arg}' failed"
            assert result.stdout.strip(), f"{shell}: '{func_name} {arg}' returned empty output"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("func_name", HELP_TOPICS)
    def test_section_lookup_is_available(self, shell_runner, shell, func_name):
        list_result = shell_runner(shell, f"{func_name} --list")
        assert list_result.exit_code == 0, f"{shell}: '{func_name} --list' failed"

        section = _first_section_token(list_result.stdout)
        section_result = shell_runner(shell, f"{func_name} {section}")
        assert section_result.exit_code == 0, f"{shell}: '{func_name} {section}' failed"
        assert section_result.stdout.strip(), f"{shell}: '{func_name} {section}' returned empty output"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("func_name", HELP_TOPICS)
    def test_canonical_alias_exists(self, shell_runner, shell, func_name):
        alias_name = _func_to_alias(func_name)
        result = shell_runner(shell, f"alias {alias_name}")
        assert result.exit_code == 0, f"{shell}: '{alias_name}' alias not defined"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("func_name", HELP_TOPICS)
    def test_canonical_alias_invocation_works(self, shell_runner, shell, func_name):
        alias_name = _func_to_alias(func_name)
        cmd = f"{alias_name} --list"
        if shell == "bash":
            # bash non-interactive mode disables alias expansion by default.
            result = shell_runner(shell, f"shopt -s expand_aliases; eval '{cmd}'")
        else:
            result = shell_runner(shell, cmd)
        assert result.exit_code == 0, f"{shell}: '{cmd}' failed"


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
        assert any("details: gwt-help <section>" in line for line in lines), f"{shell}: details guide missing"

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
