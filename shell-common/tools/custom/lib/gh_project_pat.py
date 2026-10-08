#!/usr/bin/env python3
"""PROJECT_BOARD_PAT 다중 저장소 등록/조회 helper (issue #2064).

Called by `gh_project_pat` (shell-common/functions/gh_project_pat.sh); not a
user-facing command. Output is tab-separated records on stdout that the shell
renders with ux_lib. The PAT is read once from the TTY and handed to
`gh secret set` on stdin only — never argv, env, output or files.

Subcommands:
  set    --host H [--owner O] [--repo O/R ...|--repo-pattern P] [--dry-run|--apply]
         resolve targets and print the plan (writes nothing)
  apply  --host H --repo O/R [...]   prompt for the PAT once and write the secret
  status --host H [--owner O] [--repo O/R ...|--repo-pattern P]

Exit codes: 0 ok, 1 partial failure / missing secret / zero targets / no TTY,
2 bad input.
"""

import argparse
import fnmatch
import getpass
import json
import os
import re
import subprocess
import sys

SECRET_NAME = "PROJECT_BOARD_PAT"
DEFAULT_PATTERN = "*-skills"
PER_PAGE = 100
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


class InputError(Exception):
    """Bad option / host / owner -> exit 2."""


class RunError(Exception):
    """Runtime failure before or during work -> exit 1."""


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise InputError(message)


def emit(*fields):
    # Empty fields would collapse under the shell's IFS=tab read.
    print("\t".join(str(f) if str(f) else "-" for f in fields), flush=True)


def gh(host, args, stdin=None):
    env = dict(os.environ, GH_HOST=host)
    try:
        return subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True, env=env)
    except FileNotFoundError:
        raise RunError("gh CLI not found (install gh first)") from None


def first_line(text):
    lines = (text or "").strip().splitlines()
    return lines[0] if lines else "unknown error"


def gh_api(host, path):
    r = gh(host, ["api", "--hostname", host, path])
    if r.returncode != 0:
        raise RunError(f"gh api {path}: {first_line(r.stderr)}")
    return json.loads(r.stdout or "null")


def auth_login(host):
    try:
        return gh_api(host, "user")["login"]
    except (RunError, TypeError, KeyError, ValueError):
        raise RunError(f"{host} 인증 실패: gh auth login --hostname {host}") from None


def paginate(host, base):
    repos: list[dict[str, object]] = []
    page = 1
    while True:
        batch = gh_api(host, f"{base}&per_page={PER_PAGE}&page={page}") or []
        repos.extend(batch)
        if len(batch) < PER_PAGE:
            return repos
        page += 1


def list_repos(host, owner, login):
    if owner.lower() == login.lower():
        # user/repos is the only listing that includes the caller's private repos.
        return paginate(host, "user/repos?affiliation=owner&visibility=all")
    try:
        return paginate(host, f"orgs/{owner}/repos?type=all")
    except RunError:
        return paginate(host, f"users/{owner}/repos?type=owner")


def add_target_args(p):
    p.add_argument("--host", required=True)
    p.add_argument("--owner")
    p.add_argument("--repo", action="append", default=[])
    p.add_argument("--repo-pattern")


def require_nonempty(name, value):
    if value is not None and not value.strip():
        raise InputError(f"--{name} 값이 비어 있습니다")


def validate_repos(repos):
    for r in repos:
        if not REPO_RE.match(r):
            raise InputError(f"--repo 는 OWNER/REPO 형식이어야 합니다: {r}")


def resolve_targets(args):
    require_nonempty("host", args.host)
    require_nonempty("owner", args.owner)
    if args.repo and args.repo_pattern is not None:
        raise InputError("--repo 와 --repo-pattern 은 함께 쓸 수 없습니다")
    require_nonempty("repo-pattern", args.repo_pattern)
    validate_repos(args.repo)
    login = auth_login(args.host)  # also fails early on an unauthenticated host
    owner = args.owner or login
    if args.repo:
        for r in args.repo:
            if r.split("/")[0].lower() != owner.lower():
                raise InputError(f"repo owner 불일치: {r} (owner={owner})")
        targets = list(dict.fromkeys(args.repo))
    else:
        pattern = args.repo_pattern or DEFAULT_PATTERN
        targets = sorted(
            r["full_name"] for r in list_repos(args.host, owner, login) if fnmatch.fnmatchcase(r["name"], pattern)
        )
    if not targets:
        raise RunError(f"대상 저장소가 0개입니다 (owner={owner})")
    emit("host", args.host)
    emit("owner", owner)
    emit("secret", SECRET_NAME)
    return targets


def cmd_set(args):
    if args.apply and args.dry_run:
        raise InputError("--dry-run 과 --apply 는 함께 쓸 수 없습니다")
    targets = resolve_targets(args)
    emit("mode", "apply" if args.apply else "dry-run")
    for t in targets:
        emit("target", t)
    emit("count", len(targets))
    return 0


def require_tty():
    try:
        os.close(os.open("/dev/tty", os.O_RDWR))
    except OSError:
        raise RunError("TTY 가 없어 PAT 를 입력받을 수 없습니다 (터미널에서 직접 실행)") from None


def read_pat():
    return getpass.getpass(f"{SECRET_NAME} (입력은 화면에 표시되지 않음): ")


def cmd_apply(args):
    require_nonempty("host", args.host)
    if not args.repo:
        raise InputError("apply 에는 --repo 가 하나 이상 필요합니다")
    validate_repos(args.repo)
    require_tty()
    try:
        pat = (read_pat() or "").strip()
    except (KeyboardInterrupt, EOFError):
        raise RunError("입력이 취소됐습니다. secret 을 쓰지 않았습니다") from None
    if not pat:
        raise RunError("빈 입력입니다. secret 을 쓰지 않았습니다")
    ok = fail = 0
    for repo in dict.fromkeys(args.repo):
        r = gh(args.host, ["secret", "set", SECRET_NAME, "--repo", repo], stdin=pat)
        if r.returncode == 0:
            ok += 1
            emit("result", repo, "ok", "-")
        else:
            fail += 1
            emit("result", repo, "fail", first_line(r.stderr).replace(pat, "***"))
    emit("set_summary", ok, fail)
    return 1 if fail else 0


def cmd_status(args):
    counts = {"present": 0, "missing": 0, "error": 0}
    for repo in resolve_targets(args):
        r = gh(args.host, ["secret", "list", "--repo", repo, "--json", "name"])
        if r.returncode != 0:
            state, detail = "error", first_line(r.stderr)
        else:
            try:
                names = {s["name"] for s in json.loads(r.stdout or "[]")}
                state, detail = ("present" if SECRET_NAME in names else "missing"), "-"
            except (ValueError, TypeError, KeyError):
                state, detail = "error", "unexpected gh output"
        counts[state] += 1
        emit("status", repo, state, detail)
    emit("status_summary", counts["present"], counts["missing"], counts["error"])
    return 0 if counts["missing"] == counts["error"] == 0 else 1


def build_parser():
    parser = _Parser(prog="gh_project_pat.py", add_help=False, allow_abbrev=False)
    sub = parser.add_subparsers(dest="cmd", required=True, parser_class=_Parser)
    p_set = sub.add_parser("set", add_help=False, allow_abbrev=False)
    add_target_args(p_set)
    p_set.add_argument("--apply", action="store_true")
    p_set.add_argument("--dry-run", action="store_true")
    p_set.set_defaults(func=cmd_set)
    p_apply = sub.add_parser("apply", add_help=False, allow_abbrev=False)
    p_apply.add_argument("--host", required=True)
    p_apply.add_argument("--repo", action="append", default=[])
    p_apply.set_defaults(func=cmd_apply)
    p_status = sub.add_parser("status", add_help=False, allow_abbrev=False)
    add_target_args(p_status)
    p_status.set_defaults(func=cmd_status)
    return parser


def main(argv=None):
    try:
        args = build_parser().parse_args(argv)
        return args.func(args)
    except InputError as e:
        emit("error", e)
        return 2
    except RunError as e:
        emit("error", e)
        return 1
    except KeyboardInterrupt:
        emit("error", "중단됐습니다. 이미 쓴 secret 은 그대로 둡니다 (재실행하면 수렴)")
        return 1


if __name__ == "__main__":
    sys.exit(main())
