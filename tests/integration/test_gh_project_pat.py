"""Tests for shell-common/tools/custom/lib/gh_project_pat.py (issue #2064).

Every gh call goes to a stub on PATH that logs argv / GH_HOST / stdin, so no
test touches a real remote. The PAT prompt is replaced via monkeypatch of
`read_pat`; the TTY probe via `require_tty`.
"""

import importlib.util
import json
import os
import stat
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
HELPER = REPO_ROOT / "shell-common" / "tools" / "custom" / "lib" / "gh_project_pat.py"
PAT = "ghp_FAKEtoken1234567890SECRET"

# Stub gh: logs one JSON line per call (argv, GH_HOST, stdin, whether the PAT
# leaked into the environment) and answers from fixture files in $STUB_DIR.
STUB = r"""#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
stdin = "" if sys.stdin.isatty() else sys.stdin.read()
with open(os.path.join(d, "calls.jsonl"), "a") as f:
    f.write(json.dumps({"argv": args, "host": os.environ.get("GH_HOST"),
                        "stdin": stdin, "env": sorted(os.environ.values())}) + "\n")
def fixture(name):
    p = os.path.join(d, name)
    if os.path.exists(p):
        sys.stdout.write(open(p).read()); sys.exit(0)
    sys.stderr.write("HTTP 404: Not Found (" + name + ")\n"); sys.exit(1)
if args[:2] == ["api", "--hostname"]:
    path = args[3]
    fixture("api_" + path.replace("/", "_").replace("?", "_").replace("&", "_").replace("=", "_"))
if args[:2] == ["secret", "set"]:
    repo = args[args.index("--repo") + 1]
    if repo in os.environ.get("STUB_FAIL_REPOS", "").split(","):
        sys.stderr.write("HTTP 403: Resource not accessible\n"); sys.exit(1)
    sys.exit(0)
if args[:2] == ["secret", "list"]:
    repo = args[args.index("--repo") + 1]
    fixture("secrets_" + repo.replace("/", "_"))
sys.exit(3)
"""


def _load_module():
    spec = importlib.util.spec_from_file_location("gh_project_pat", HELPER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def mod():
    return _load_module()


@pytest.fixture
def stub(tmp_path, monkeypatch):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    gh = bindir / "gh"
    gh.write_text(STUB)
    gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("STUB_DIR", str(tmp_path))
    monkeypatch.delenv("STUB_FAIL_REPOS", raising=False)
    return tmp_path


def api_fixture(stub_dir: Path, path: str, data) -> None:
    name = "api_" + path.replace("/", "_").replace("?", "_").replace("&", "_").replace("=", "_")
    (stub_dir / name).write_text(json.dumps(data))


def calls(stub_dir: Path):
    log = stub_dir / "calls.jsonl"
    if not log.exists():
        return []
    return [json.loads(line) for line in log.read_text().splitlines()]


def secret_set_calls(stub_dir: Path):
    return [c for c in calls(stub_dir) if c["argv"][:2] == ["secret", "set"]]


def repo(name, owner="me", private=False):
    return {"name": name, "full_name": f"{owner}/{name}", "private": private}


def user_repos_path(page):
    return f"user/repos?affiliation=owner&visibility=all&per_page=100&page={page}"


def records(out: str):
    return [line.split("\t") for line in out.splitlines() if line]


@pytest.fixture
def me(stub):
    api_fixture(stub, "user", {"login": "me"})
    return stub


def no_pat_prompt():
    raise AssertionError("read_pat must not be called")


class TestPlan:
    def test_dry_run_lists_multi_page_including_private(self, mod, me, capsys, monkeypatch):
        page1 = [repo(f"r{i}-skills", private=(i % 2 == 0)) for i in range(99)] + [repo("other")]
        page2 = [repo("last-skills", private=True)]
        api_fixture(me, user_repos_path(1), page1)
        api_fixture(me, user_repos_path(2), page2)
        monkeypatch.setattr(mod, "read_pat", no_pat_prompt)

        rc = mod.main(["set", "--host", "ghe.example.com"])

        out = capsys.readouterr().out
        recs = records(out)
        targets = [r[1] for r in recs if r[0] == "target"]
        assert rc == 0
        assert len(targets) == 100
        assert "me/last-skills" in targets
        assert "me/other" not in targets
        assert ["count", "100"] in recs
        assert ["mode", "dry-run"] in recs
        assert ["owner", "me"] in recs
        assert ["secret", "PROJECT_BOARD_PAT"] in recs
        assert secret_set_calls(me) == []
        assert all(c["host"] == "ghe.example.com" for c in calls(me))
        assert all(c["argv"][2] == "ghe.example.com" for c in calls(me))

    def test_explicit_repos_skip_listing(self, mod, me, capsys):
        rc = mod.main(["set", "--host", "github.com", "--repo", "me/a", "--repo", "me/b", "--repo", "me/a"])
        recs = records(capsys.readouterr().out)
        assert rc == 0
        assert [r[1] for r in recs if r[0] == "target"] == ["me/a", "me/b"]
        assert not any("repos" in c["argv"][-1] for c in calls(me))

    def test_org_owner_includes_private(self, mod, me, capsys):
        api_fixture(
            me,
            "orgs/acme/repos?type=all&per_page=100&page=1",
            [repo("x-skills", "acme", private=True), repo("y", "acme")],
        )
        rc = mod.main(["set", "--host", "github.com", "--owner", "acme"])
        recs = records(capsys.readouterr().out)
        assert rc == 0
        assert [r[1] for r in recs if r[0] == "target"] == ["acme/x-skills"]

    def test_custom_pattern(self, mod, me, capsys):
        api_fixture(me, user_repos_path(1), [repo("a-skills"), repo("tool-x")])
        rc = mod.main(["set", "--host", "github.com", "--repo-pattern", "tool-*"])
        recs = records(capsys.readouterr().out)
        assert rc == 0
        assert [r[1] for r in recs if r[0] == "target"] == ["me/tool-x"]

    def test_apply_mode_reported(self, mod, me, capsys):
        rc = mod.main(["set", "--host", "github.com", "--repo", "me/a", "--apply"])
        assert rc == 0
        assert ["mode", "apply"] in records(capsys.readouterr().out)

    @pytest.mark.parametrize(
        "argv",
        [
            ["set", "--host", "github.com", "--apply", "--dry-run"],
            ["set", "--host", "github.com", "--repo", "me/a", "--repo-pattern", "*"],
            ["set", "--host", "github.com", "--owner", "me", "--repo", "other/a"],
            ["set", "--host", "github.com", "--repo", "not-a-slug"],
            ["set", "--host", ""],
            ["set", "--host", "github.com", "--owner", ""],
            ["set", "--host", "github.com", "--bogus"],
            ["set", "--host", "github.com", "--token", "x"],
            ["status", "--host", "github.com", "--apply"],
        ],
    )
    def test_bad_input_exits_2(self, mod, me, capsys, argv):
        assert mod.main(argv) == 2
        assert records(capsys.readouterr().out)[0][0] == "error"
        assert secret_set_calls(me) == []

    def test_owner_mismatch_against_auth_user(self, mod, me, capsys):
        assert mod.main(["set", "--host", "github.com", "--repo", "someone/a"]) == 2

    def test_zero_targets_exits_1(self, mod, me, capsys):
        api_fixture(me, user_repos_path(1), [repo("nothing")])
        assert mod.main(["set", "--host", "github.com"]) == 1
        assert records(capsys.readouterr().out)[0][0] == "error"

    def test_auth_failure_exits_1(self, mod, stub, capsys):
        assert mod.main(["set", "--host", "github.com"]) == 1
        assert "gh auth login --hostname github.com" in capsys.readouterr().out


class TestApply:
    def test_pat_goes_to_stdin_only(self, mod, stub, capsys, monkeypatch):
        monkeypatch.setattr(mod, "require_tty", lambda: None)
        prompts = []
        monkeypatch.setattr(mod, "read_pat", lambda: prompts.append(1) or PAT + "\n")

        rc = mod.main(["apply", "--host", "ghe.example.com", "--repo", "me/a", "--repo", "me/b"])

        out = capsys.readouterr()
        sets = secret_set_calls(stub)
        assert rc == 0
        assert len(prompts) == 1
        assert [c["argv"] for c in sets] == [
            ["secret", "set", "PROJECT_BOARD_PAT", "--repo", "me/a"],
            ["secret", "set", "PROJECT_BOARD_PAT", "--repo", "me/b"],
        ]
        assert all(c["stdin"] == PAT for c in sets)
        assert all(c["host"] == "ghe.example.com" for c in sets)
        for c in calls(stub):
            assert PAT not in " ".join(c["argv"])
            assert not any(PAT in v for v in c["env"])
        assert PAT not in out.out + out.err
        assert PAT not in os.environ.values()
        assert ["set_summary", "2", "0"] in records(out.out)
        assert not any(
            PAT in p.read_text(errors="ignore") for p in stub.iterdir() if p.is_file() and p.name != "calls.jsonl"
        )

    def test_mid_failure_continues_and_exits_1(self, mod, stub, capsys, monkeypatch):
        monkeypatch.setattr(mod, "require_tty", lambda: None)
        monkeypatch.setattr(mod, "read_pat", lambda: PAT)
        monkeypatch.setenv("STUB_FAIL_REPOS", "me/b")

        rc = mod.main(["apply", "--host", "github.com", "--repo", "me/a", "--repo", "me/b", "--repo", "me/c"])

        recs = records(capsys.readouterr().out)
        assert rc == 1
        assert len(secret_set_calls(stub)) == 3
        assert ["result", "me/a", "ok", "-"] in recs
        assert [r[:3] for r in recs if r[0] == "result" and r[1] == "me/b"] == [["result", "me/b", "fail"]]
        assert ["result", "me/c", "ok", "-"] in recs
        assert ["set_summary", "2", "1"] in recs

    def test_no_tty_exits_before_prompt(self, mod, stub, capsys, monkeypatch):
        def no_tty():
            raise mod.RunError("no tty")

        monkeypatch.setattr(mod, "require_tty", no_tty)
        monkeypatch.setattr(mod, "read_pat", no_pat_prompt)
        assert mod.main(["apply", "--host", "github.com", "--repo", "me/a"]) == 1
        assert secret_set_calls(stub) == []

    def test_require_tty_fails_without_controlling_terminal(self, mod, monkeypatch):
        def boom(*_a, **_k):
            raise OSError("No such device or address")

        monkeypatch.setattr(mod.os, "open", boom)
        with pytest.raises(mod.RunError):
            mod.require_tty()

    @pytest.mark.parametrize("value", ["", "   \n"])
    def test_empty_input_exits_1(self, mod, stub, capsys, monkeypatch, value):
        monkeypatch.setattr(mod, "require_tty", lambda: None)
        monkeypatch.setattr(mod, "read_pat", lambda: value)
        assert mod.main(["apply", "--host", "github.com", "--repo", "me/a"]) == 1
        assert secret_set_calls(stub) == []

    @pytest.mark.parametrize("exc", [KeyboardInterrupt, EOFError])
    def test_cancelled_input_exits_1(self, mod, stub, capsys, monkeypatch, exc):
        def cancel():
            raise exc

        monkeypatch.setattr(mod, "require_tty", lambda: None)
        monkeypatch.setattr(mod, "read_pat", cancel)
        assert mod.main(["apply", "--host", "github.com", "--repo", "me/a"]) == 1
        assert secret_set_calls(stub) == []

    def test_apply_requires_repo(self, mod, stub, capsys):
        assert mod.main(["apply", "--host", "github.com"]) == 2


class TestStatus:
    def test_counts_present_missing(self, mod, me, capsys):
        (me / "secrets_me_a").write_text(json.dumps([{"name": "PROJECT_BOARD_PAT"}]))
        (me / "secrets_me_b").write_text(json.dumps([{"name": "OTHER"}]))
        rc = mod.main(["status", "--host", "github.com", "--repo", "me/a", "--repo", "me/b", "--repo", "me/c"])
        recs = records(capsys.readouterr().out)
        assert rc == 1
        assert ["status", "me/a", "present", "-"] in recs
        assert ["status", "me/b", "missing", "-"] in recs
        assert [r[:3] for r in recs if r[0] == "status" and r[1] == "me/c"] == [["status", "me/c", "error"]]
        assert ["status_summary", "1", "1", "1"] in recs
        assert all(c["argv"][:2] != ["secret", "set"] for c in calls(me))

    def test_all_present_exits_0(self, mod, me, capsys):
        (me / "secrets_me_a").write_text(json.dumps([{"name": "PROJECT_BOARD_PAT"}]))
        assert mod.main(["status", "--host", "github.com", "--repo", "me/a"]) == 0
