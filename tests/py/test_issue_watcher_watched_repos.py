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
        {
            "repo": "a/x",
            "rel": "x",
            "host": "github.com",
            "post_merge_verify": True,
            "post_merge_verify_skill": "gh-verify:merged",
        },
        {"repo": "a/y", "rel": "y"},
        {"repo": "a/z", "rel": "z"},
    ]
    current = [
        {"repo": "me/private", "path": "/srv/p"},
        {"repo": "a/x", "path": "/opt/x", "post_merge_verify": False, "verify_skill": "gh-verify:live", "extra": 1},
    ]
    merged, skipped, _ = merge(tracked, current, "/h", isdir=lambda p: p == "/h/y")
    assert merged == [
        {"repo": "me/private", "path": "/srv/p"},
        {
            "repo": "a/x",
            "path": "/opt/x",
            "extra": 1,
            "host": "github.com",
            "post_merge_verify": True,
            "post_merge_verify_skill": "gh-verify:merged",
        },
        {"repo": "a/y", "path": "/h/y"},
    ]
    assert skipped == [("a/z", "/h/z")]


def test_merge_matches_repo_case_insensitively() -> None:
    merged, skipped, _ = merge([{"repo": "Own/Repo", "rel": "r"}], [{"repo": "own/repo", "path": "/p"}], "/h")
    assert merged == [{"repo": "own/repo", "path": "/p"}]
    assert skipped == []


def test_merge_keeps_entry_on_another_host() -> None:
    local = {"repo": "a/x", "path": "/p", "host": "ghes.example", "post_merge_verify": True}
    merged, skipped, _ = merge([{"repo": "a/x", "rel": "x", "host": "github.com"}], [local], "/h", isdir=lambda _: True)
    assert merged == [local]
    assert skipped == []


def test_merge_drops_field_the_tracked_entry_omits() -> None:
    local = {"repo": "a/x", "path": "/p", "post_merge_verify": True, "verify_skill": "gh-verify:live"}
    merged, _, _ = merge([{"repo": "a/x", "rel": "x"}], [local], "/h")
    assert merged == [{"repo": "a/x", "path": "/p"}]


# #2296: a local entry the tracked file does not own still carries the old
# `verify_skill` key; the render migrates it to the two-key schema.
@pytest.mark.parametrize(
    ("local", "want"),
    [
        (
            {"repo": "me/p", "path": "/p", "verify_skill": "gh-verify:live", "x": 1},
            {
                "repo": "me/p",
                "path": "/p",
                "x": 1,
                "post_merge_verify": True,
                "post_merge_verify_skill": "gh-verify:live",
            },
        ),
        (
            {"repo": "me/p", "path": "/p", "verify_skill": "gh-verify:merged"},
            {"repo": "me/p", "path": "/p", "post_merge_verify": True, "post_merge_verify_skill": "gh-verify:merged"},
        ),
        # new keys already there win; the old key is only removed
        (
            {"repo": "me/p", "path": "/p", "post_merge_verify": False, "verify_skill": "gh-verify:live"},
            {"repo": "me/p", "path": "/p", "post_merge_verify": False},
        ),
        # no old key: no post_merge_verify is invented
        ({"repo": "me/p", "path": "/p"}, {"repo": "me/p", "path": "/p"}),
    ],
)
def test_merge_migrates_old_verify_skill(local: dict[str, object], want: dict[str, object]) -> None:
    merged, _, warnings = merge([], [local], "/h")
    assert merged == [want]
    assert warnings == []
    again, _, _ = merge([], merged, "/h")
    assert again == merged


def test_merge_migrates_entry_on_another_host() -> None:
    local = {"repo": "a/x", "path": "/p", "host": "ghes.example", "verify_skill": "gh-verify:merged"}
    merged, _, _ = merge([{"repo": "a/x", "rel": "x"}], [local], "/h", isdir=lambda _: True)
    assert merged == [
        {
            "repo": "a/x",
            "path": "/p",
            "host": "ghes.example",
            "post_merge_verify": True,
            "post_merge_verify_skill": "gh-verify:merged",
        }
    ]


def test_merge_keeps_unknown_verify_skill_and_warns() -> None:
    local = {"repo": "me/p", "path": "/p", "verify_skill": "gh-pr:custom"}
    merged, _, warnings = merge([], [local], "/h")
    assert merged == [local]
    assert warnings == [("me/p", "gh-pr:custom")]


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
        assert set(e) <= {"repo", "rel", "host", "post_merge_verify", "post_merge_verify_skill"}
        assert e.get("post_merge_verify", False) in (True, False)
        assert e.get("post_merge_verify_skill", "gh-verify:merged") in ("gh-verify:merged", "gh-verify:live")
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


def test_render_migrates_local_file_and_reports_unknown_value(tmp_path: Path) -> None:
    tracked = tmp_path / "t.json"
    tracked.write_text("[]")
    target = tmp_path / "w.json"
    target.write_text(
        json.dumps(
            [
                {"repo": "me/a", "path": "/a", "verify_skill": "gh-verify:live"},
                {"repo": "me/b", "path": "/b", "verify_skill": "bogus"},
            ]
        )
    )
    res = run_render(str(tracked), str(target), str(tmp_path))
    assert res.returncode == 0
    assert res.stdout.splitlines()[0] == "warn\tme/b\tbogus"
    assert json.loads(target.read_text()) == [
        {"repo": "me/a", "path": "/a", "post_merge_verify": True, "post_merge_verify_skill": "gh-verify:live"},
        {"repo": "me/b", "path": "/b", "verify_skill": "bogus"},
    ]
    assert run_render(str(tracked), str(target), str(tmp_path)).stdout.splitlines()[-1] == "unchanged"


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


def test_render_same_second_backups_do_not_collide(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    from dotfiles_tools.issue_watcher import watched_repos

    monkeypatch.setattr(watched_repos.time, "strftime", lambda _fmt: "20260101-000000")
    (tmp_path / "x").mkdir()
    (tmp_path / "y").mkdir()
    tracked = tmp_path / "t.json"
    target = tmp_path / "w.json"
    target.write_text("[]")
    tracked.write_text(json.dumps([{"repo": "a/x", "rel": "x"}]))
    watched_repos.render(str(tracked), str(target), str(tmp_path), False)
    tracked.write_text(json.dumps([{"repo": "a/x", "rel": "x"}, {"repo": "a/y", "rel": "y"}]))
    watched_repos.render(str(tracked), str(target), str(tmp_path), False)
    assert sorted(p.name for p in tmp_path.glob("w.json.bak-*")) == [
        "w.json.bak-20260101-000000",
        "w.json.bak-20260101-000000.1",
    ]
