"""Render the tracked watch list into the per-PC watched-repos.json (#2285).

avatar/watched-repos.public.json is tracked and public-safe: each entry names a
repo and a HOME-relative checkout path (`rel`). This module merges it into the
file avatar_issue_watcher.sh reads, keyed on `repo`:

  - an entry only the target has (a private repo, say) is kept as it is;
  - a repo both have keeps the target's `path` (a per-PC override) and takes
    every other field from the tracked entry -- unless the target names a
    different `host` (an internal GHES mirror, say): that entry is a per-PC
    override and is kept as it is;
  - a repo only the tracked file has is added as `$HOME/<rel>` when that
    directory exists, and reported as skipped otherwise.

A kept target entry still carrying the old `verify_skill` key (#2296) is
migrated to `post_merge_verify: true` + `post_merge_verify_skill: <value>`;
new keys already present win and the old key is dropped. A value outside the
allowlist is left as it is and reported. A merged entry drops the old key,
since the tracked entry owns the new ones.

Usage: python3 -s -E -m dotfiles_tools.issue_watcher.watched_repos \
           render <tracked> <target> <home> [--dry-run]

stdout is TSV the shell turns into ux_lib output:

  skip<TAB><repo><TAB><path>   tracked repo whose checkout does not exist
  warn<TAB><repo><TAB><value>  old verify_skill outside the allowlist, kept
  diff<TAB><line>              unified diff line (--dry-run only)
  unchanged                    target already matches; nothing written
  would-write                  --dry-run and the target would change
  written<TAB><backup|->       target written; backup path, or - when new

Exit codes: 0 done, 2 unreadable input or bad usage (stdout empty, reason on
stderr). The target is never touched on exit 2.
"""

from __future__ import annotations

import difflib
import json
import os
import shutil
import sys
import tempfile
import time
from collections.abc import Callable
from typing import Any

# Fields the tracked entry owns; anything else in a target entry is kept.
_TRACKED_FIELDS = ("host", "post_merge_verify", "post_merge_verify_skill")
_OLD_FIELD = "verify_skill"  # pre-#2296 schema; migrated on render
_VERIFY_SKILLS = ("gh-verify:merged", "gh-verify:live")


class InputError(Exception):
    """Unreadable or malformed input; maps to exit 2."""


def load_tracked(raw: str) -> list[dict[str, str]]:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise InputError(f"tracked file is not valid JSON: {exc}") from exc
    if not isinstance(data, list):
        raise InputError("tracked file must be a JSON array")
    seen: set[str] = set()
    for entry in data:
        if not isinstance(entry, dict):
            raise InputError("tracked entries must be objects")
        repo, rel = entry.get("repo"), entry.get("rel")
        if not isinstance(repo, str) or not repo or not isinstance(rel, str) or not rel:
            raise InputError(f"tracked entry needs string repo and rel: {entry}")
        if os.path.isabs(rel) or ".." in rel.split("/"):
            raise InputError(f"rel must be HOME-relative: {repo} -> {rel}")
        if repo.lower() in seen:
            raise InputError(f"duplicate repo in tracked file: {repo}")
        seen.add(repo.lower())
    return data


def _migrate(entry: Any, warnings: list[tuple[str, str]]) -> Any:
    """Rewrite a kept entry's old `verify_skill` into the two-key schema."""
    if not isinstance(entry, dict) or _OLD_FIELD not in entry:
        return entry
    old = entry[_OLD_FIELD]
    out = {k: v for k, v in entry.items() if k != _OLD_FIELD}
    if "post_merge_verify" in entry or "post_merge_verify_skill" in entry:
        return out  # new keys win
    if old not in _VERIFY_SKILLS:
        warnings.append((str(entry.get("repo", "?")), str(old)))
        return entry
    return {**out, "post_merge_verify": True, "post_merge_verify_skill": old}


def merge(
    tracked: list[dict[str, str]],
    current: list[Any],
    home: str,
    isdir: Callable[[str], bool] = os.path.isdir,
) -> tuple[list[Any], list[tuple[str, str]], list[tuple[str, str]]]:
    """Return (merged entries, skipped (repo, path), unmigrated (repo, verify_skill))."""
    # GitHub repo names are case-insensitive; match on the folded name.
    by_repo = {t["repo"].lower(): t for t in tracked}
    merged: list[Any] = []
    done: set[str] = set()
    warnings: list[tuple[str, str]] = []
    for entry in current:
        repo = entry.get("repo") if isinstance(entry, dict) else None
        if not isinstance(repo, str) or repo.lower() not in by_repo:
            merged.append(_migrate(entry, warnings))
            continue
        t = by_repo[repo.lower()]
        done.add(repo.lower())
        if (entry.get("host") or "github.com") != t.get("host", "github.com"):
            merged.append(_migrate(entry, warnings))  # same name on another host: keep it
            continue
        out = {k: v for k, v in entry.items() if k not in (*_TRACKED_FIELDS, _OLD_FIELD)}
        merged.append({**out, **{k: t[k] for k in _TRACKED_FIELDS if k in t}})
    skipped: list[tuple[str, str]] = []
    for t in tracked:
        if t["repo"].lower() in done:
            continue
        path = os.path.join(home, t["rel"])
        if not isdir(path):
            skipped.append((t["repo"], path))
            continue
        merged.append({"repo": t["repo"], "path": path, **{k: t[k] for k in _TRACKED_FIELDS if k in t}})
    return merged, skipped, warnings


def _dump(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def render(tracked_path: str, target_path: str, home: str, dry_run: bool) -> list[str]:
    try:
        with open(tracked_path, encoding="utf-8") as fh:
            tracked = load_tracked(fh.read())
    except OSError as exc:
        raise InputError(f"cannot read tracked file: {exc}") from exc

    old_text = ""
    current_doc: Any = []
    if os.path.exists(target_path):
        try:
            with open(target_path, encoding="utf-8") as fh:
                old_text = fh.read()
            current_doc = json.loads(old_text)
        except (OSError, json.JSONDecodeError) as exc:
            raise InputError(f"target file is unreadable, left untouched: {exc}") from exc

    # The watcher accepts a bare array or an object with a `repos` array.
    if isinstance(current_doc, list):
        current = current_doc
    elif isinstance(current_doc, dict) and isinstance(repos := current_doc.get("repos") or [], list):
        current = repos  # null == absent, like jq `.repos // []`
    else:
        raise InputError("target file must be an array or an object with a repos array")

    merged, skipped, warnings = merge(tracked, current, home)
    lines = [f"warn\t{repo}\t{old}" for repo, old in warnings]
    lines += [f"skip\t{repo}\t{path}" for repo, path in skipped]
    new_doc: Any = merged if isinstance(current_doc, list) else {**current_doc, "repos": merged}

    # Compare the entries, not the doc: an object without `repos` stays as is.
    if old_text and merged == current:
        return [*lines, "unchanged"]
    new_text = _dump(new_doc)
    if dry_run:
        diff = difflib.unified_diff(old_text.splitlines(), new_text.splitlines(), target_path, target_path, lineterm="")
        return [*lines, *(f"diff\t{d}" for d in diff), "would-write"]

    target_path = os.path.realpath(target_path)  # keep a symlinked target a symlink
    target_dir = os.path.dirname(target_path) or "."
    os.makedirs(target_dir, mode=0o700, exist_ok=True)
    backup = "-"
    if old_text:
        backup = base = f"{target_path}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        n = 1
        while os.path.exists(backup):  # two renders in one second keep both backups
            backup, n = f"{base}.{n}", n + 1
        shutil.copy2(target_path, backup)
    fd, tmp = tempfile.mkstemp(dir=target_dir, prefix=".watched-repos.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(new_text)
        os.chmod(tmp, 0o600)
        os.replace(tmp, target_path)
    except BaseException:
        os.unlink(tmp)
        raise
    return [*lines, f"written\t{backup}"]


def main(argv: list[str]) -> int:
    args = [a for a in argv if a != "--dry-run"]
    if len(args) != 4 or args[0] != "render":
        print("usage: render <tracked> <target> <home> [--dry-run]", file=sys.stderr)
        return 2
    try:
        lines = render(args[1], args[2], args[3], "--dry-run" in argv)
    except InputError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    sys.stdout.buffer.write("".join(f"{line}\n" for line in lines).encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
