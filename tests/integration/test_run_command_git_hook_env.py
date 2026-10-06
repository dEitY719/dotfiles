"""run_command must not inherit git's hook-time exec-path (#2031).

Inside a git hook (pre-push -> mise run test), git prepends its exec-path
(e.g. /usr/lib/git-core) to PATH and exports GIT_EXEC_PATH. A dashed name such
as `git-help` then resolves to git's own binary instead of the dotfiles
function, so tests pass in a terminal but fail only inside the hook.
"""

from __future__ import annotations

import os

from .conftest import run_command


def test_run_command_drops_git_exec_path(tmp_path, monkeypatch) -> None:
    exec_dir = tmp_path / "git-core"
    exec_dir.mkdir()
    fake = exec_dir / "git-help"
    fake.write_text("#!/bin/sh\nexit 129\n")
    fake.chmod(0o755)
    monkeypatch.setenv("GIT_EXEC_PATH", str(exec_dir))
    monkeypatch.setenv("PATH", f"{exec_dir}{os.pathsep}{os.environ['PATH']}")

    result = run_command('echo "[${GIT_EXEC_PATH-}]"; command -v git-help || echo none')

    assert result.exit_code == 0, result.stderr
    assert result.stdout.splitlines() == ["[]", "none"]
