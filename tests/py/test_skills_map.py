"""skills-map engine (claude/mods/skills-map/bin/skills_map.py, #2461).

Every test builds a throwaway CLAUDE_CONFIG_DIR + HOME + XDG dirs and a fake
'claude' CLI, so nothing touches the real account.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import stat
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "claude/mods/skills-map/bin/skills_map.py"

FAKE_CLAUDE = """#!{py}
import json, sys
db = {db!r}
plugins = json.load(open(db))
args = sys.argv[1:]
if args[:3] == ["plugin", "list", "--json"]:
    print(json.dumps(plugins))
elif args[:2] in (["plugin", "enable"], ["plugin", "disable"]):
    for p in plugins:
        if p["id"] == args[2]:
            p["enabled"] = args[1] == "enable"
    json.dump(plugins, open(db, "w"))
else:
    sys.exit(1)
"""


def iso(days_ago: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).isoformat().replace("+00:00", "Z")


def skill(d: Path, name: str, desc: str, body: str = "") -> None:
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(f"---\nname: {name}\ndescription: {desc}\n---\n{body}\n")


class Env:
    def __init__(self, tmp: Path) -> None:
        self.tmp = tmp
        self.home = tmp / "home"
        self.cfg = tmp / "acct"
        (self.home / ".claude/skills/decoy").mkdir(parents=True)
        (self.home / ".claude/skills/decoy/SKILL.md").write_text("---\nname: decoy\ndescription: x\n---\n")
        for n in ("foo", "bar", "baz"):
            skill(self.cfg / "skills" / n, n, f"{n} does things")
        skill(self.cfg / "skills/alpha", "alpha", "calls beta", "Run Skill(beta) then finish.")
        skill(self.cfg / "skills/beta", "beta", "helper")
        p1, p2 = tmp / "plugins/p1", tmp / "plugins/p2"
        skill(p1 / "skills/x", "x", "plugin skill x")
        skill(p2 / "skills/y", "y", "chains into x", "Then call p1:x.")
        self.db = tmp / "plugins.json"
        self.db.write_text(
            json.dumps(
                [
                    {"id": "p1@m", "enabled": True, "installPath": str(p1)},
                    {"id": "p2@m", "enabled": True, "installPath": str(p2)},
                ]
            )
        )
        self.claude = tmp / "claude"
        self.claude.write_text(FAKE_CLAUDE.format(py=sys.executable, db=str(self.db)))
        self.claude.chmod(self.claude.stat().st_mode | stat.S_IEXEC)
        (self.cfg / "settings.json").write_text('{"model": "opus"}\n')
        self.local = self.cfg / "settings.local.json"
        self.local.write_text('{"env": {"A": "1"}, "permissions": {"allow": ["x"]}}\n')
        proj = self.cfg / "projects/p"
        proj.mkdir(parents=True)
        recs = [
            {"uuid": "1", "timestamp": iso(1), "message": {"content": [tu("foo")]}},
            {"uuid": "2", "timestamp": iso(2), "message": {"content": [tu("foo")]}},
            {"uuid": "3", "timestamp": iso(3), "message": {"content": "<command-name>/foo</command-name>"}},
            {"uuid": "4", "timestamp": iso(1), "message": {"content": "<command-name>/clear</command-name>"}},
            {"uuid": "5", "timestamp": iso(45), "message": {"content": [tu("foo")]}},
            {"uuid": "6", "timestamp": iso(1), "message": {"content": [tu("p1:x")]}},
            {"uuid": "7", "message": {"content": [tu("bar")]}},
            # api-request-blob repeats an assistant message without a timestamp: never counted
            {"type": "api-request-blob", "message": {"content": [tu("foo")]}},
        ]
        (proj / "s.jsonl").write_text("\n".join(json.dumps(r) for r in recs) + "\n")
        # a resumed session copies record 1 into a second file: counted once
        (proj / "s2.jsonl").write_text(json.dumps(recs[0]) + "\n")

    def env(self) -> dict[str, str]:
        return {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "CLAUDE_CONFIG_DIR": str(self.cfg),
            "XDG_CONFIG_HOME": str(self.tmp / "xdg-config"),
            "XDG_CACHE_HOME": str(self.tmp / "xdg-cache"),
            "SKILLS_MAP_CLAUDE": str(self.claude),
            "SKILLS_MAP_PIN_SOURCES": str(self.tmp / "none.json"),
        }

    def run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-I", str(ENGINE), *args],
            capture_output=True,
            text=True,
            env=self.env(),
            cwd=self.tmp,
            stdin=subprocess.DEVNULL,
            check=False,
        )

    def listing(self) -> dict[str, dict[str, object]]:
        r = self.run("list", "--json", "--refresh")
        assert r.returncode == 0, r.stderr
        return {s["name"]: s for s in json.loads(r.stdout)["skills"]}


def tu(name: str) -> dict[str, object]:
    return {"type": "tool_use", "name": "Skill", "input": {"skill": name}}


@pytest.fixture
def e(tmp_path: Path) -> Env:
    return Env(tmp_path)


def digest(*paths: Path) -> str:
    return hashlib.sha256(b"".join(p.read_bytes() for p in paths)).hexdigest()


def test_list_json_fields_and_sources(e: Env) -> None:
    rows = e.listing()
    assert {"foo", "bar", "baz", "alpha", "beta", "p1:x", "p2:y"} <= set(rows)
    for r in rows.values():
        assert {"state", "source", "uses", "last_used", "tokens", "pinned_by"} <= set(r)
    assert rows["p1:x"]["source"] == "plugin:p1"
    assert rows["foo"]["source"] == "skill"


def test_claude_config_dir_is_the_only_account_read_or_written(e: Env) -> None:
    before = sorted(p.relative_to(e.home) for p in e.home.rglob("*"))
    rows = e.listing()
    assert "decoy" not in rows
    assert e.run("set", "baz", "name-only").returncode == 0
    assert sorted(p.relative_to(e.home) for p in e.home.rglob("*")) == before


def test_usage_counts_by_event_time(e: Env) -> None:
    rows = e.listing()
    assert rows["foo"]["uses"] == 3  # 2 Skill tool_use + 1 /foo; the 45-day-old record is outside the window
    assert rows["p1:x"]["uses"] == 1
    assert rows["bar"]["uses"] == 0  # record without a timestamp is skipped
    assert "clear" not in rows
    r = e.run("list", "--json", "--refresh")
    assert "without a readable timestamp" in r.stderr


def test_set_writes_local_settings_preserving_keys(e: Env) -> None:
    r = e.run("set", "foo", "user-only")
    assert r.returncode == 0, r.stderr
    obj = json.loads(e.local.read_text())
    assert obj["skillOverrides"] == {"foo": "user-invocable-only"}
    assert obj["env"] == {"A": "1"} and obj["permissions"] == {"allow": ["x"]}
    assert (e.cfg / "settings.local.json.skills-map.bak").exists()
    assert json.loads((e.cfg / "settings.json").read_text()) == {"model": "opus"}


def test_broken_json_is_never_written(e: Env) -> None:
    e.local.write_text("{broken")
    r = e.run("set", "foo", "user-only")
    assert r.returncode == 1
    assert e.local.read_text() == "{broken"


def test_pinned_skill_refuses_demotion_unless_forced(e: Env) -> None:
    assert e.listing()["beta"]["pinned_by"] == ["alpha"]
    r = e.run("set", "beta", "user-only")
    assert r.returncode == 1 and "pinned by alpha" in r.stderr
    assert e.run("set", "beta", "user-only", "--force").returncode == 0


def test_plugin_referenced_by_another_plugin_refuses_off(e: Env) -> None:
    r = e.run("plugin", "p1", "off", "--yes")
    assert r.returncode == 1 and "pinned by p2:y" in r.stderr
    assert json.loads(e.db.read_text())[0]["enabled"] is True
    r = e.run("plugin", "p2", "off", "--yes")
    assert r.returncode == 0, r.stderr
    assert json.loads(e.db.read_text())[1]["enabled"] is False


def test_plugin_off_with_usage_needs_yes_when_non_interactive(e: Env) -> None:
    r = e.run("plugin", "p1", "off", "--force")
    assert r.returncode == 1 and "--yes" in r.stderr


def test_recommend_is_read_only_and_never_off(e: Env) -> None:
    e.listing()  # first run creates the state file (import)
    state = next((e.tmp / "xdg-config/skills-map").glob("state-*.json"))
    before = digest(e.local, state)
    r = e.run("recommend", "--top", "2")
    assert r.returncode == 0, r.stderr
    assert digest(e.local, state) == before
    assert "-> off" not in r.stdout
    assert "foo: on -> on" not in r.stdout
    assert "baz: on -> user-only" in r.stdout
    assert "beta: on -> name-only" in r.stdout  # pinned stays model-invocable


def test_apply_needs_yes_then_writes(e: Env) -> None:
    assert e.run("apply").returncode == 1
    r = e.run("apply", "--yes")
    assert r.returncode == 0, r.stderr
    ov = json.loads(e.local.read_text())["skillOverrides"]
    assert ov["baz"] == "user-invocable-only" and ov["beta"] == "name-only"
    assert "foo" not in ov  # already on


def test_set_plugin_skill_points_to_plugin_command(e: Env) -> None:
    r = e.run("set", "p1:x", "off")
    assert r.returncode == 2 and "skills-map plugin p1" in r.stderr


def test_unknown_skill_suggests_names(e: Env) -> None:
    r = e.run("set", "fooo", "on")
    assert r.returncode == 2 and "foo" in r.stderr


def test_first_run_imports_and_drift_converges(e: Env) -> None:
    e.local.write_text('{"skillOverrides": {"bar": "name-only"}}\n')
    assert e.listing()["bar"]["state"] == "name-only"
    assert json.loads(e.local.read_text()) == {"skillOverrides": {"bar": "name-only"}}
    assert e.run("status").stdout.strip() == "no drift"
    # partial write: state changed, projection not (crash between the two writes)
    state = next((e.tmp / "xdg-config/skills-map").glob("state-*.json"))
    st = json.loads(state.read_text())
    st["overrides"]["baz"] = "user-invocable-only"
    state.write_text(json.dumps(st))
    assert "skillOverrides.baz" in e.run("status").stdout
    assert e.run("sync").returncode == 0
    assert e.run("status").stdout.strip() == "no drift"
    assert json.loads(e.local.read_text())["skillOverrides"]["baz"] == "user-invocable-only"


def test_deleted_settings_file_is_drift_and_sync_recreates(e: Env) -> None:
    assert e.run("set", "foo", "name-only").returncode == 0
    e.local.unlink()
    assert "skillOverrides.foo" in e.run("status").stdout
    assert e.run("sync").returncode == 0
    assert json.loads(e.local.read_text())["skillOverrides"] == {"foo": "name-only"}


def test_no_transcripts_refuses_recommend(e: Env) -> None:
    for f in (e.cfg / "projects/p").iterdir():
        f.unlink()
    (e.cfg / "projects/p").rmdir()
    (e.cfg / "projects").rmdir()
    r = e.run("recommend", "--refresh")
    assert r.returncode == 1 and "no usage evidence" in r.stderr


def test_missing_claude_cli_keeps_flat_skills(e: Env) -> None:
    e.claude.unlink()
    rows = e.listing()
    assert "foo" in rows and "p1:x" not in rows
    assert e.run("plugin", "p1", "off").returncode == 1


def test_store_merge_dedupes_and_skips_scanned_window(e: Env) -> None:
    now = time.time()
    store = e.tmp / "store.json"
    rec = {"skill": "baz", "source": "user", "ts": (now + 60) * 1000}
    store.write_text(json.dumps([rec, rec, {"skill": "baz", "source": "user", "ts": (now - 3600) * 1000}]))
    r = e.run("list", "--json", "--refresh", "--with-store", str(store))
    rows = {s["name"]: s for s in json.loads(r.stdout)["skills"]}
    assert rows["baz"]["uses"] == 1


def test_frontmatter_skips_comments_and_folds_blocks() -> None:
    sm = load_engine()
    fm = sm.frontmatter("---\nname: wave  # trailing\n# note: x\ndescription: >-\n  one\n  two\n---\nbody")
    assert fm == {"name": "wave", "description": "one two"}


def load_engine() -> ModuleType:
    spec = importlib.util.spec_from_file_location("skills_map", ENGINE)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_concurrent_writer_wins_with_exit_3(e: Env, monkeypatch: pytest.MonkeyPatch) -> None:
    for k, v in e.env().items():
        monkeypatch.setenv(k, v)
    sm = load_engine()
    n = {"i": 0}

    def other_writer(p: Path) -> None:
        n["i"] += 1
        p.write_text(json.dumps({"model": f"changed-{n['i']}"}))

    monkeypatch.setattr(sm, "before_replace", other_writer)
    with pytest.raises(sm.Refused) as exc:
        sm.write_overrides({"foo": "name-only"})
    assert exc.value.code == 3
    assert n["i"] == 3  # first try + 2 retries
    assert json.loads(e.local.read_text()) == {"model": "changed-3"}
