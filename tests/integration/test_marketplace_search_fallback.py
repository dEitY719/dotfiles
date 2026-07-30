"""
`claude_skills_marketplace search` (alias `find`) non-interactive fallback tests.

The harness runs non-interactive subprocesses with no TTY, so fzf can never be
launched here — every run must take the jq substring fallback path instead of
hanging or erroring. `$MARKETPLACE_BASE_DIR` lives under the isolated temp HOME
and holds no marketplaces, so the generated manifest is empty; assertions here
target the code path (exit status, absence of errors), not skill names.
"""

import json
import os
import stat
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent

MANIFEST = {
    "version": "1.0",
    "total_skills": 2,
    "skills": [
        {
            "name": "zed-skill",
            "description": "desc one",
            "license": "MIT",
            "path": "/p/SKILL.md",
            "category": "pl",
            "marketplace": "m",
            "plugin": "pl",
        },
        {
            "name": "alpha-skill",
            "description": "desc two",
            "license": "MIT",
            "path": "/q/SKILL.md",
            "category": "pl",
            "marketplace": "m",
            "plugin": "pl",
        },
    ],
}


@pytest.mark.parametrize("shell", ["bash", "zsh"])
@pytest.mark.parametrize("subcmd", ["search", "find"])
def test_search_and_find_take_the_same_fallback(shell_runner, shell, subcmd):
    result = shell_runner(shell, f"claude_skills_marketplace {subcmd} python")
    assert result.exit_code == 0, (
        f"{shell}: csm {subcmd} python failed\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert "Unknown command" not in result.stdout, f"{shell}: '{subcmd}' not routed to search"
    assert "No skills found matching query" in result.stdout, (
        f"{shell}: csm {subcmd} did not render the substring-search result\nstdout: {result.stdout}"
    )


@pytest.mark.parametrize("shell", ["bash", "zsh"])
@pytest.mark.parametrize("subcmd", ["search", "find"])
def test_missing_query_still_errors_in_fallback(shell_runner, shell, subcmd):
    """Regression guard: making the query optional must only relax the fzf path."""
    result = shell_runner(shell, f"claude_skills_marketplace {subcmd}")
    assert result.exit_code != 0, f"{shell}: csm {subcmd} with no query should fail"
    assert "Query required" in result.stdout + result.stderr, (
        f"{shell}: csm {subcmd} lost its 'Query required' error\nstdout: {result.stdout}"
    )


class TestMarketplaceSearchInteractive:
    """`csm search`/`csm find` on the real fzf path, driven through a pty.

    The fallback tests above can only reach the no-TTY branch, so the fzf branch
    — where zsh stray-output (#1248) and strict-shell cancel aborts (#1247) have
    bitten before — would otherwise go untested. pexpect gives us a pty so
    `[ -t 0 ] && [ -t 1 ]` holds, and a stub `fzf` on PATH captures the
    candidate stream and picks a skill.
    """

    @staticmethod
    def _spawn(shell, tmp_path, stub_body, cmd, prelude="", manifest_text=None):
        """Run `claude_skills_marketplace <cmd>` under a pty with a stubbed fzf.

        `manifest_text` overrides the cached manifest contents (default: the
        valid MANIFEST fixture) — used to simulate a corrupt cache.

        Returns (exit_code, output, captured_candidates_or_None, fzf_args).
        """
        pexpect = pytest.importorskip("pexpect")

        bindir = tmp_path / "bin"
        bindir.mkdir()
        capture = tmp_path / "candidates.txt"
        argsfile = tmp_path / "fzf_args.txt"
        stub = bindir / "fzf"
        stub.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$FZF_STUB_ARGS"\ncat > "$FZF_STUB_CAPTURE"\n' + stub_body)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

        home = tmp_path / "home"
        marketplaces = home / ".claude/plugins/marketplaces"
        marketplaces.mkdir(parents=True)
        (marketplaces / ".skills-manifest.json").write_text(
            manifest_text if manifest_text is not None else json.dumps(MANIFEST)
        )

        env = {
            "PATH": f"{bindir}:{os.environ['PATH']}",
            "FZF_STUB_CAPTURE": str(capture),
            "FZF_STUB_ARGS": str(argsfile),
            "DOTFILES_FORCE_INIT": "1",
            "DOTFILES_TEST_MODE": "1",
            "DOTFILES_ROOT": str(REPO_ROOT),
            "SHELL_COMMON": str(REPO_ROOT / "shell-common"),
            "DOTFILES_ROOT_NO_CANONICALIZE": "1",
            "HOME": str(home),
            "ZDOTDIR": str(home),
            "XDG_CONFIG_HOME": str(home),
            "XDG_CACHE_HOME": str(home),
            "XDG_DATA_HOME": str(home),
            "TERM": "dumb",
        }
        if shell == "zsh":
            entry, args = REPO_ROOT / "zsh/main.zsh", ["-f", "-lc"]
        else:
            entry, args = REPO_ROOT / "bash/main.bash", ["--noprofile", "--norc", "-lc"]
        args.append(f"source {entry}; {prelude}claude_skills_marketplace {cmd}")

        child = pexpect.spawn(shell, args, env=env, encoding="utf-8", timeout=60, dimensions=(40, 200))
        child.expect(pexpect.EOF)
        output = child.before
        child.close()
        captured = capture.read_text() if capture.exists() else None
        fzf_args = argsfile.read_text().splitlines() if argsfile.exists() else []
        return child.exitstatus, output, captured, fzf_args

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("subcmd", ["search", "find"])
    def test_selection_dispatches_to_info(self, shell, tmp_path, subcmd):
        """The candidate stream carries only `name<TAB>desc<TAB>plugin` lines, and
        the selected line dispatches to that skill's `info` output."""
        exit_code, output, captured, fzf_args = self._spawn(
            shell, tmp_path, stub_body='head -n1 "$FZF_STUB_CAPTURE"\n', cmd=f"{subcmd} myquery"
        )
        assert exit_code == 0, f"{shell}: csm {subcmd} failed\n{output}"
        assert captured, f"{shell}: fzf stub received no candidates"
        assert captured.splitlines() == ["alpha-skill\tdesc two\tpl", "zed-skill\tdesc one\tpl"], (
            f"{shell}: unexpected candidate stream: {captured!r}"
        )
        assert "--query=myquery" in fzf_args, f"{shell}: query arg not forwarded to fzf: {fzf_args}"
        assert "Skill: alpha-skill" in output, f"{shell}: selection did not reach info\n{output}"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_cancel_is_not_an_error_under_strict_shell(self, shell, tmp_path):
        """Esc (fzf exit 130, empty selection) must return 0 without aborting a
        strict shell (`set -e` / `setopt err_exit`)."""
        prelude = "setopt err_exit; " if shell == "zsh" else "set -e; "
        exit_code, output, _, _ = self._spawn(shell, tmp_path, stub_body="exit 130\n", cmd="find", prelude=prelude)
        assert exit_code == 0, f"{shell}: cancel aborted the shell\n{output}"
        assert "Skill:" not in output, f"{shell}: cancel still rendered a skill\n{output}"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("subcmd", ["search", "find"])
    def test_zero_arg_picker_dispatches_to_info(self, shell, tmp_path, subcmd):
        """The main user-facing flow — `csm search`/`csm find` with NO keyword —
        must launch the full picker (all skills, no --query prefill) and dispatch
        the selection to `info`, same as the query-prefilled case."""
        exit_code, output, captured, fzf_args = self._spawn(
            shell, tmp_path, stub_body='head -n1 "$FZF_STUB_CAPTURE"\n', cmd=subcmd
        )
        assert exit_code == 0, f"{shell}: csm {subcmd} (no args) failed\n{output}"
        assert captured, f"{shell}: fzf stub received no candidates"
        assert captured.splitlines() == ["alpha-skill\tdesc two\tpl", "zed-skill\tdesc one\tpl"], (
            f"{shell}: unexpected candidate stream: {captured!r}"
        )
        assert "--query=" in fzf_args, f"{shell}: no-keyword picker must pass an empty --query: {fzf_args}"
        assert "Skill: alpha-skill" in output, f"{shell}: selection did not reach info\n{output}"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_corrupt_manifest_surfaces_error_instead_of_silent_success(self, shell, tmp_path):
        """A jq parse failure (corrupt manifest) must be reported, not swallowed
        as if the user had simply cancelled the picker (PR #1252 review)."""
        exit_code, output, captured, _ = self._spawn(
            shell,
            tmp_path,
            stub_body="exit 1\n",  # fzf must never be reached — jq fails first.
            cmd="search",
            manifest_text="{not valid json",
        )
        assert exit_code != 0, f"{shell}: corrupt manifest silently succeeded\n{output}"
        assert "Failed to parse marketplace manifest" in output, (
            f"{shell}: no parse-error message surfaced\n{output}"
        )
        assert not captured, f"{shell}: fzf ran despite the manifest failing to parse: {captured!r}"
