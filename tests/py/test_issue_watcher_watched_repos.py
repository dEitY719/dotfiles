"""dotfiles_tools.issue_watcher.watched_repos (#2285): tracked list -> per-PC watch list."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest
from dotfiles_tools.issue_watcher.watched_repos import InputError, load_tracked, merge

ROOT = Path(__file__).resolve().parents[2]
TRACKED = ROOT / "avatar" / "watched-repos.public.json"


def run_render(*args: str) -> subprocess.CompletedProcess[str]:
    """Invoke the module the way the shell entrypoint does: -E -s, cwd = tools/py."""
    return subprocess.run(
        [sys.executable, "-E", "-s", "-m", "dotfiles_tools.issue_watcher.watched_repos", "render", *args],
        capture_output=True,
        text=True,
        cwd=ROOT / "tools/py",
        check=False,
    )


def test_merge_keeps_local_only_and_path_override() -> None:
    tracked = [
        {"repo": "a/x", "rel": "x", "host": "github.com", "verify_skill": "gh-verify:merged"},
        {"repo": "a/y", "rel": "y"},
        {"repo": "a/z", "rel": "z"},
    ]
    current = [
        {"repo": "me/private", "path": "/srv/p"},
        {"repo": "a/x", "path": "/opt/x", "verify_skill": "old", "extra": 1},
    ]
    merged, skipped = merge(tracked, current, "/h", isdir=lambda p: p == "/h/y")
    assert merged == [
        {"repo": "me/private", "path": "/srv/p"},
        {"repo": "a/x", "path": "/opt/x", "extra": 1, "host": "github.com", "verify_skill": "gh-verify:merged"},
        {"repo": "a/y", "path": "/h/y"},
    ]
    assert skipped == [("a/z", "/h/z")]


def test_merge_matches_repo_case_insensitively() -> None:
    merged, skipped = merge([{"repo": "Own/Repo", "rel": "r"}], [{"repo": "own/repo", "path": "/p"}], "/h")
    assert merged == [{"repo": "own/repo", "path": "/p"}]
    assert skipped == []


def test_merge_drops_field_the_tracked_entry_omits() -> None:
    merged, _ = merge([{"repo": "a/x", "rel": "x"}], [{"repo": "a/x", "path": "/p", "verify_skill": "v"}], "/h")
    assert merged == [{"repo": "a/x", "path": "/p"}]


@pytest.mark.parametrize(
    "raw",
    [
        "{",
        "{}",
        '[{"repo": "a/x"}]',
        '[{"repo": "a/x", "rel": "/abs"}]',
        '[{"repo": "a/x", "rel": "../up"}]',
        '[{"repo": "a/x", "rel": "x"}, {"repo": "a/x", "rel": "y"}]',
    ],
)
def test_load_tracked_rejects_bad_input(raw: str) -> None:
    with pytest.raises(InputError):
        load_tracked(raw)


def test_tracked_file_is_public_safe() -> None:
    entries = load_tracked(TRACKED.read_text(encoding="utf-8"))
    assert entries
    for e in entries:
        assert set(e) <= {"repo", "rel", "host", "verify_skill"}
        assert e.get("host", "github.com") == "github.com"
    text = TRACKED.read_text(encoding="utf-8")
    assert "/home/" not in text and "/Users/" not in text


def test_render_writes_backs_up_and_is_idempotent(tmp_path: Path) -> None:
    home = tmp_path / "home"
    (home / "x").mkdir(parents=True)
    tracked = tmp_path / "t.json"
    tracked.write_text(json.dumps([{"repo": "a/x", "rel": "x"}, {"repo": "a/y", "rel": "y"}]))
    target = home / ".avatars" / "issue-watcher" / "watched-repos.json"

    first = run_render(str(tracked), str(target), str(home))
    assert first.returncode == 0
    assert first.stdout.splitlines() == [f"skip\ta/y\t{home}/y", "written\t-"]
    assert json.loads(target.read_text()) == [{"repo": "a/x", "path": f"{home}/x"}]
    assert stat.S_IMODE(os.stat(target).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(target.parent).st_mode) == 0o700

    second = run_render(str(tracked), str(target), str(home))
    assert second.stdout.splitlines()[-1] == "unchanged"
    assert list(target.parent.glob("*.bak-*")) == []

    (home / "y").mkdir()
    third = run_render(str(tracked), str(target), str(home))
    kind, backup = third.stdout.splitlines()[-1].split("\t")
    assert kind == "written"
    assert json.loads(Path(backup).read_text()) == [{"repo": "a/x", "path": f"{home}/x"}]


def test_render_dry_run_writes_nothing(tmp_path: Path) -> None:
    (tmp_path / "x").mkdir()
    tracked = tmp_path / "t.json"
    tracked.write_text(json.dumps([{"repo": "a/x", "rel": "x"}]))
    target = tmp_path / "w" / "watched-repos.json"
    res = run_render(str(tracked), str(target), str(tmp_path), "--dry-run")
    assert res.returncode == 0
    assert res.stdout.splitlines()[-1] == "would-write"
    assert any(line.startswith('diff\t+    "repo": "a/x"') for line in res.stdout.splitlines())
    assert not target.parent.exists()


def test_render_keeps_repos_object_shape(tmp_path: Path) -> None:
    (tmp_path / "x").mkdir()
    tracked = tmp_path / "t.json"
    tracked.write_text(json.dumps([{"repo": "a/x", "rel": "x"}]))
    target = tmp_path / "w.json"
    target.write_text(json.dumps({"note": "keep", "repos": []}))
    assert run_render(str(tracked), str(target), str(tmp_path)).returncode == 0
    assert json.loads(target.read_text()) == {"note": "keep", "repos": [{"repo": "a/x", "path": f"{tmp_path}/x"}]}


@pytest.mark.parametrize("which", ["tracked", "target"])
def test_render_broken_json_exits_2_and_leaves_target(tmp_path: Path, which: str) -> None:
    tracked = tmp_path / "t.json"
    target = tmp_path / "w.json"
    tracked.write_text("[" if which == "tracked" else "[]")
    target.write_text("[]" if which == "tracked" else "{")
    before = target.read_text()
    res = run_render(str(tracked), str(target), str(tmp_path))
    assert res.returncode == 2
    assert res.stdout == ""
    assert target.read_text() == before
    assert list(tmp_path.glob("*.bak-*")) == []


def test_render_object_without_repos_and_nothing_to_add_is_unchanged(tmp_path: Path) -> None:
    tracked = tmp_path / "t.json"
    tracked.write_text(json.dumps([{"repo": "a/x", "rel": "missing"}]))
    target = tmp_path / "w.json"
    target.write_text(json.dumps({"x": 1}))
    res = run_render(str(tracked), str(target), str(tmp_path))
    assert res.stdout.splitlines()[-1] == "unchanged"
    assert json.loads(target.read_text()) == {"x": 1}
