#!/usr/bin/env -S python3 -I
"""skills-map engine (#2461): usage-aware skill exposure for Claude Code.

stdlib only, so the plugin works outside the dotfiles stack. One JSON
interface ('--json') feeds every UI (CLI, herdr popup, a future mods pane).

Paths derive from CLAUDE_CONFIG_DIR (default ~/.claude):
  inventory  <cfg>/skills/*/SKILL.md + 'claude plugin list --json'
  usage      <cfg>/projects/**/*.jsonl, windowed by record timestamp
  state      $XDG_CONFIG_HOME/skills-map/state-<hash>.json  (SSOT, default ~/.config)
  cache      $XDG_CACHE_HOME/skills-map/usage-<hash>.json   (default ~/.cache)
  projection <cfg>/settings.local.json .skillOverrides (SKILLS_MAP_SETTINGS
             overrides the file name, e.g. settings.json)

Exit codes: 0 ok, 1 refused/failed, 2 usage error, 3 write conflict.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import difflib
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

STATES = ("on", "name-only", "user-invocable-only", "off")
ALIASES = {"user-only": "user-invocable-only"}
SHOW = {"user-invocable-only": "user-only"}
RANK = {"on": 0, "name-only": 1, "user-invocable-only": 2, "off": 3}
# Claude Code built-in slash commands: never counted as skill use.
BUILTINS = frozenset(
    "add-dir agents bashes bug clear compact config context cost doctor exit export feedback help hooks ide init "
    "install-github-app login logout mcp memory model output-style permissions plugin plugins pr-comments "
    "privacy-settings release-notes reload-skills resume review rewind security-review skills skill-doctor "
    "status statusline terminal-setup todos upgrade usage vim fast effort theme".split()
)
CMD_RE = re.compile(r"<command-name>/?([^<\s]+)</command-name>")
REF_RES = (
    re.compile(r"Skill\(\s*[\"']?([A-Za-z0-9_.:-]+)"),
    re.compile(r"(?<![\w/.~-])/([a-z][a-z0-9_-]*(?::[a-z0-9_-]+)?)"),
    re.compile(r"\b([a-z][a-z0-9_-]*:[a-z][a-z0-9_-]*)\b"),
)
AF_RE = re.compile(r"-af\d+$")
CACHE_TTL = 86400


class Refused(Exception):
    def __init__(self, msg: str, code: int = 1) -> None:
        super().__init__(msg)
        self.code = code


def warn(msg: str) -> None:
    print(f"skills-map: {msg}", file=sys.stderr)


# --- paths -------------------------------------------------------------------


def cfg_dir() -> Path:
    raw = os.environ.get("CLAUDE_CONFIG_DIR") or str(Path.home() / ".claude")
    return Path(raw).expanduser()


def cfg_hash() -> str:
    return hashlib.sha256(str(cfg_dir().resolve()).encode()).hexdigest()[:12]


def xdg(var: str, default: str) -> Path:
    return Path(os.environ.get(var) or str(Path.home() / default)) / "skills-map"


def state_path() -> Path:
    return xdg("XDG_CONFIG_HOME", ".config") / f"state-{cfg_hash()}.json"


def cache_path() -> Path:
    return xdg("XDG_CACHE_HOME", ".cache") / f"usage-{cfg_hash()}.json"


def settings_path() -> Path:
    return cfg_dir() / os.environ.get("SKILLS_MAP_SETTINGS", "settings.local.json")


# --- inventory ---------------------------------------------------------------


def frontmatter(text: str) -> dict[str, str]:
    """Minimal YAML frontmatter: scalar, quoted and block (| >) values."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    out: dict[str, str] = {}
    key = ""
    block: list[str] = []
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if m:
            if key:
                out[key] = " ".join(block).strip()
            key, val = m.group(1), m.group(2).strip()
            val = re.sub(r"\s+#.*$", "", val) if val[:1] not in "\"'" else val  # YAML comment
            block = [] if val in ("|", ">", "|-", ">-") else [val.strip("\"'")]
        elif key:
            block.append(line.strip())
    if key:
        out[key] = " ".join(block).strip()
    return out


def read_skill(md: Path, prefix: str = "") -> dict[str, Any]:
    fm = frontmatter(md.read_text(encoding="utf-8", errors="replace"))
    base = fm.get("name") or md.parent.name
    desc = fm.get("description", "")
    return {
        "name": f"{prefix}:{base}" if prefix else base,
        "base": base,
        "description": desc,
        "tokens": round((len(base) + len(desc)) / 4),
        "dir": str(md.parent),
    }


def claude_bin() -> str:
    return os.environ.get("SKILLS_MAP_CLAUDE", "claude")


def plugin_list() -> list[dict[str, Any]] | None:
    """Installed plugins via the documented 'claude plugin list --json'; None if unavailable."""
    try:
        proc = subprocess.run([claude_bin(), "plugin", "list", "--json"], capture_output=True, text=True, timeout=60)
        data = json.loads(proc.stdout) if proc.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        data = None
    return data if isinstance(data, list) else None


def inventory() -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]] | None]:
    skills: list[dict[str, Any]] = []
    for md in sorted((cfg_dir() / "skills").glob("*/SKILL.md")):
        s = read_skill(md)
        s.update(source="skill", plugin=None)
        skills.append(s)
    plist = plugin_list()
    plugins: dict[str, dict[str, Any]] | None = None
    if plist is None:
        warn("claude CLI unavailable: plugin skills not listed, plugin commands disabled")
    else:
        plugins = {}
        for p in plist:
            if not isinstance(p, dict):
                continue
            pid = str(p.get("id", ""))
            name = pid.split("@")[0]
            plugins[name] = {"id": pid, "enabled": bool(p.get("enabled")), "path": str(p.get("installPath") or "")}
            if not plugins[name]["path"]:
                continue
            for md in sorted(Path(plugins[name]["path"]).glob("skills/*/SKILL.md")):
                s = read_skill(md, name)
                s.update(source=f"plugin:{name}", plugin=name)
                skills.append(s)
    return skills, plugins


# --- usage -------------------------------------------------------------------


def parse_ts(raw: Any) -> float | None:
    if isinstance(raw, int | float) and not isinstance(raw, bool):
        return float(raw) / (1000 if raw > 1e11 else 1)
    if not isinstance(raw, str):
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return (dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)).timestamp()


def events(rec: dict[str, Any]) -> Iterator[str]:
    msg = rec.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    items = content if isinstance(content, list) else [content]
    for it in items:
        if isinstance(it, dict) and it.get("type") == "tool_use" and it.get("name") == "Skill":
            inp = it.get("input")
            skill = inp.get("skill") if isinstance(inp, dict) else None
            if isinstance(skill, str) and skill:
                yield skill.lstrip("/")
        text = it if isinstance(it, str) else (it.get("text") if isinstance(it, dict) else None)
        if isinstance(text, str) and "<command-name>" in text:
            for name in CMD_RE.findall(text):
                if name not in BUILTINS:
                    yield name


def bump(counts: dict[str, dict[str, Any]], name: str, ts: float) -> None:
    c = counts.setdefault(name, {"uses": 0, "last": 0.0})
    c["uses"] += 1
    c["last"] = max(c["last"], ts)


def scan_usage(days: int) -> tuple[dict[str, dict[str, Any]], float, bool]:
    """Count skill events in the last days by record timestamp. Returns (counts, scanned_at, found_dir)."""
    root = cfg_dir() / "projects"
    now = time.time()
    cutoff = now - days * 86400
    counts: dict[str, dict[str, Any]] = {}
    if not root.is_dir():
        warn(f"no transcript directory ({root}): usage is 0")
        return counts, now, False
    seen: set[str] = set()
    skipped = 0
    for f in root.rglob("*.jsonl"):
        try:
            if f.stat().st_mtime < cutoff:  # pre-filter only; the window is the record timestamp
                continue
            fh = f.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"Skill"' not in line and "<command-name>" not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(rec, dict) or rec.get("type", "assistant") not in ("assistant", "user"):
                    continue  # e.g. api-request-blob repeats an assistant message without a timestamp
                names = list(events(rec))
                if not names:
                    continue
                ts = parse_ts(rec.get("timestamp"))
                if ts is None:
                    skipped += 1
                    continue
                if ts < cutoff:
                    continue
                uid = rec.get("uuid")
                if isinstance(uid, str):  # resumed sessions copy history into new files
                    if uid in seen:
                        continue
                    seen.add(uid)
                for name in names:
                    bump(counts, name, ts)
    if skipped:
        warn(f"{skipped} skill record(s) without a readable timestamp were not counted")
    return counts, now, True


def usage(days: int, refresh: bool) -> tuple[dict[str, dict[str, Any]], float, bool]:
    cp = cache_path()
    if not refresh:
        try:
            if time.time() - cp.stat().st_mtime < CACHE_TTL:
                c = json.loads(cp.read_text())
                if c.get("days") == days:
                    return c["counts"], float(c["scanned_at"]), bool(c["found"])
        except (OSError, ValueError, KeyError, AttributeError):
            pass
    counts, at, found = scan_usage(days)
    if not found:
        return counts, at, found  # never cache "no transcripts": it would stick for a day
    with contextlib.suppress(OSError):
        cp.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(cp, json.dumps({"days": days, "scanned_at": at, "found": found, "counts": counts}))
    return counts, at, found


def merge_store(counts: dict[str, dict[str, Any]], store: Path, scanned_at: float) -> None:
    """Add live mod records ({skill, source, ts}) newer than the transcript scan, deduped by key."""
    try:
        recs = json.loads(store.read_text())
    except (OSError, ValueError):
        warn(f"store {store} unreadable: transcript counts only")
        return
    seen: set[tuple[str, str, float]] = set()
    for r in recs if isinstance(recs, list) else []:
        if not isinstance(r, dict):
            continue
        ts, skill = parse_ts(r.get("ts")), r.get("skill")
        if ts is None or not isinstance(skill, str) or ts <= scanned_at:
            continue  # the transcript scan already covers this window
        key = (skill, str(r.get("source", "")), ts)
        if key in seen:
            continue
        seen.add(key)
        bump(counts, skill, ts)


# --- pins (F-8) --------------------------------------------------------------


def resolve(ref: str, names: set[str], by_base: dict[str, list[str]]) -> str | None:
    """plugin:name exact -> name without trailing -afNN -> unique plugin skill with that base."""
    for cand in dict.fromkeys((ref, AF_RE.sub("", ref))):
        if cand in names:
            return cand
        if ":" not in cand and len(by_base.get(cand, [])) == 1:
            return by_base[cand][0]
    return None


def refs_in(text: str) -> set[str]:
    return {m for rx in REF_RES for m in rx.findall(text)}


def pin_sources(skills: list[dict[str, Any]], plugins: dict[str, dict[str, Any]] | None) -> list[tuple[str, Path]]:
    """(a) bodies of model-visible skills, (b) agents, (c) unattended job manifests."""
    out: list[tuple[str, Path]] = []
    for s in skills:
        if s["state"] != "off":  # a user-only skill still runs its body when invoked by /name
            d = Path(s["dir"])
            out += [(s["name"], p) for p in [d / "SKILL.md", *sorted(d.glob("references/**/*.md"))] if p.is_file()]
    agent_dirs = [cfg_dir() / "agents", Path.cwd() / ".claude" / "agents"]
    agent_dirs += [Path(p["path"]) / "agents" for p in (plugins or {}).values() if p["enabled"] and p["path"]]
    for d in agent_dirs:
        out += [(f"agent:{p.stem}", p) for p in sorted(d.glob("**/*.md"))]
    manifest = Path.home() / "dotfiles/shell-common/tools/custom/cron-jobs.json"
    default = os.environ.get("AICRON_MANIFEST") or str(manifest)
    for raw in (os.environ.get("SKILLS_MAP_PIN_SOURCES") or default).split(":"):
        if raw and Path(raw).expanduser().is_file():
            out.append((f"cron:{Path(raw).name}", Path(raw).expanduser()))
    return out


def compute_pins(skills: list[dict[str, Any]], plugins: dict[str, dict[str, Any]] | None) -> None:
    names = {s["name"] for s in skills}
    by_base: dict[str, list[str]] = {}
    for s in skills:
        if s["plugin"]:
            by_base.setdefault(s["base"], []).append(s["name"])
    pins: dict[str, set[str]] = {}
    for who, path in pin_sources(skills, plugins):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for ref in refs_in(text):
            target = resolve(ref, names, by_base)
            if target and target != who:
                pins.setdefault(target, set()).add(who)
    for s in skills:
        s["pinned_by"] = sorted(pins.get(s["name"], ()))


# --- state & settings --------------------------------------------------------


def private_write(path: Path, text: str, like: Path | None = None) -> None:
    """Write text created 0600 (settings may hold secrets), then copy the mode of like if it exists."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    if like is not None and like.exists():
        shutil.copymode(like, path)


def atomic_write(path: Path, text: str) -> None:
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    private_write(tmp, text, like=path)
    os.replace(tmp, path)


_held = [0]  # re-entrancy depth: a second flock on a new fd in this process would deadlock


@contextlib.contextmanager
def locked() -> Iterator[None]:
    if _held[0]:
        _held[0] += 1
        try:
            yield
        finally:
            _held[0] -= 1
        return
    d = state_path().parent
    d.mkdir(parents=True, exist_ok=True)
    with (d / ".lock").open("w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        _held[0] = 1
        try:
            yield
        finally:
            _held[0] = 0


def real_settings() -> Path:
    p = settings_path()
    if p.is_symlink():
        warn(f"{p} is a symlink: writing its target {p.resolve()}")
        return p.resolve()
    return p


def read_settings(p: Path) -> tuple[str, dict[str, Any]]:
    if not p.exists():
        # settings.local.json is the personal override file: create it next to an existing settings.json
        if p.name == "settings.local.json" and (cfg_dir() / "settings.json").exists():
            return "", {}
        raise Refused(f"no settings file in {cfg_dir()}: run Claude Code once to create it, then retry")
    raw = p.read_text(encoding="utf-8")
    try:
        obj = json.loads(raw) if raw.strip() else {}
    except ValueError as e:
        raise Refused(f"{p} is not valid JSON ({e}); not writing") from e
    if not isinstance(obj, dict):
        raise Refused(f"{p} is not a JSON object; not writing")
    return raw, obj


def before_replace(p: Path) -> None:
    """Test seam: runs between the conflict re-check read and os.replace."""


def write_overrides(overrides: dict[str, str]) -> None:
    """Project overrides into the settings file: atomic, conflict-checked, other keys preserved (NF-1)."""
    p = real_settings()
    for _ in range(3):  # first try + 2 retries
        raw, obj = read_settings(p)
        if overrides:
            obj["skillOverrides"] = dict(sorted(overrides.items()))
        else:
            obj.pop("skillOverrides", None)
        with locked():
            before_replace(p)
            now = p.read_text(encoding="utf-8") if p.exists() else ""
            if now != raw:
                continue  # someone else wrote the file since we read it
            if raw:
                private_write(p.parent / f"{p.name}.skills-map.bak", raw, like=p)
            atomic_write(p, json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
            return
    raise Refused(f"{p} kept changing while writing; nothing overwritten", 3)


def save_state(st: dict[str, Any]) -> None:
    sp = state_path()
    sp.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(sp, json.dumps(st, indent=2, sort_keys=True) + "\n")


def load_state(plugins: dict[str, dict[str, Any]] | None) -> dict[str, Any]:
    with locked():  # a first-run import must not race a concurrent set/apply
        return _load_state(plugins)


def _load_state(plugins: dict[str, dict[str, Any]] | None) -> dict[str, Any]:
    sp = state_path()
    if sp.exists():
        try:
            st = json.loads(sp.read_text())
            if not isinstance(st, dict):
                raise ValueError("not an object")
        except ValueError as e:
            raise Refused(f"state {sp} unreadable ({e}); move it aside to re-import from settings") from e
        st.setdefault("overrides", {})
        st.setdefault("plugins", {})
        return st
    # first run: import the current projection, never overwrite it
    try:
        _, obj = read_settings(real_settings())
    except Refused:
        obj = {}
    ov = obj.get("skillOverrides")
    st = {
        "version": 1,
        "overrides": {k: v for k, v in (ov if isinstance(ov, dict) else {}).items() if v in STATES},
        "plugins": {n: p["enabled"] for n, p in (plugins or {}).items()},
    }
    save_state(st)
    return st


def commit(st: dict[str, Any], old: dict[str, Any]) -> None:
    """State first, then the projection; a failed projection rolls the state back.

    shortcut: no journal file. A crash between the two writes is caught by
    'status' as drift and converged by 'sync' (F-10); add a journal if that proves too coarse.
    """
    save_state(st)
    try:
        write_overrides(st["overrides"])
    except Exception:
        save_state(old)
        raise


# --- model -------------------------------------------------------------------


class World:
    def __init__(self, days: int = 30, refresh: bool = False, store: str | None = None) -> None:
        self.skills, self.plugins = inventory()
        self.state = load_state(self.plugins)
        self.counts, self.scanned_at, self.found = usage(days, refresh)
        if store:
            merge_store(self.counts, Path(store), self.scanned_at)
        flat = {s["name"] for s in self.skills if not s["plugin"]}
        base_n: dict[str, int] = {}
        for s in self.skills:
            if s["plugin"]:
                base_n[s["base"]] = base_n.get(s["base"], 0) + 1
        for s in self.skills:
            c = dict(self.counts.get(s["name"], {"uses": 0, "last": 0.0}))
            if s["plugin"] and s["base"] not in flat and base_n[s["base"]] == 1 and s["base"] in self.counts:
                c["uses"] += self.counts[s["base"]]["uses"]
                c["last"] = max(c["last"], self.counts[s["base"]]["last"])
            s["uses"], s["last"] = c["uses"], c["last"]
            if s["plugin"]:
                s["state"] = "on" if self.plugins and self.plugins[s["plugin"]]["enabled"] else "off"
            else:
                s["state"] = self.state["overrides"].get(s["name"], "on")
        compute_pins(self.skills, self.plugins)
        self.by_name = {s["name"]: s for s in self.skills}

    def flat(self) -> list[dict[str, Any]]:
        return [s for s in self.skills if not s["plugin"]]


def plugin_pins(w: World, name: str) -> list[str]:
    """Referrers outside the plugin that pin any of its skills."""
    return sorted(
        {who for s in w.skills if s["plugin"] == name for who in s["pinned_by"] if not who.startswith(f"{name}:")}
    )


def turn_tokens(s: dict[str, Any], state: str) -> int:
    return {"on": int(s["tokens"]), "name-only": round(len(s["base"]) / 4)}.get(state, 0)


def recommend(w: World, top: int, min_uses: int) -> dict[str, str]:
    """Flat skills only. Existing off stays off; pinned never drops below name-only; ties keep current state."""
    cand = [s for s in w.flat() if s["state"] != "off"]
    cand.sort(key=lambda s: (-s["uses"], RANK[s["state"]], s["name"]))
    out: dict[str, str] = {}
    for i, s in enumerate(cand):
        if i < top and s["uses"] > 0:
            out[s["name"]] = "on"
        elif s["pinned_by"] or s["uses"] >= min_uses:
            out[s["name"]] = "name-only"
        else:
            out[s["name"]] = "user-invocable-only"
    return out


def totals(w: World, rec: dict[str, str] | None = None) -> tuple[int, int]:
    cur = sum(turn_tokens(s, s["state"]) for s in w.skills)
    rec = rec if rec is not None else recommend(w, 10, 1)
    after = sum(turn_tokens(s, rec.get(s["name"], s["state"])) for s in w.skills)
    return cur, after


def day(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def rows(w: World) -> list[dict[str, Any]]:
    keyed = sorted(w.skills, key=lambda s: (RANK[s["state"]], -s["uses"], s["name"]))
    return [
        {
            "name": s["name"],
            "state": s["state"],
            "source": s["source"],
            "uses": s["uses"],
            "last_used": day(s["last"]) if s["last"] else None,
            "tokens": s["tokens"],
            "pinned_by": s["pinned_by"],
            "description": s["description"],
        }
        for s in keyed
    ]


def table(w: World) -> str:
    cur, after = totals(w)
    lines = [f"# per-turn listing ~{cur} tokens now / ~{after} with recommend applied"]
    fmt = "{:<10} {:<34} {:<24} {:>6} {:<10} {:>5}  {}"
    lines.append(fmt.format("STATE", "NAME", "SOURCE", "USES30", "LAST", "~TOK", "PINNED"))
    for r in rows(w):
        cells = (SHOW.get(r["state"], r["state"]), r["name"], r["source"][:24], r["uses"], r["last_used"] or "-")
        pins = r["pinned_by"]
        pin = (pins[0] + (f" +{len(pins) - 1}" if len(pins) > 1 else "")) if pins else ""
        lines.append(fmt.format(*cells, r["tokens"], pin))
    return "\n".join(lines)


def diff_lines(w: World, rec: dict[str, str]) -> list[str]:
    out = []
    for n, v in sorted(rec.items()):
        cur = w.by_name[n]["state"]
        if cur != v:
            out.append(f"  {n}: {SHOW.get(cur, cur)} -> {SHOW.get(v, v)}")
    return out


def unknown(kind: str, name: str, known: list[str]) -> Refused:
    near = difflib.get_close_matches(name, known, n=3)
    return Refused(f"unknown {kind} {name}" + (f" (did you mean: {', '.join(near)})" if near else ""), 2)


def confirm(question: str, yes: bool) -> bool:
    if yes:
        return True
    if not sys.stdin.isatty():
        raise Refused("non-interactive: pass --yes to confirm")
    return input(f"{question} [y/N] ").strip().lower() in ("y", "yes")


# --- commands ----------------------------------------------------------------


def cmd_list(a: argparse.Namespace) -> int:
    w = World(a.days, a.refresh, a.with_store)
    if a.json:
        cur, after = totals(w)
        print(json.dumps({"skills": rows(w), "tokens": {"current": cur, "recommended": after}}, ensure_ascii=False))
    else:
        print(table(w))
    return 0


def cmd_set(a: argparse.Namespace) -> int:
    state = ALIASES.get(a.state, a.state)
    if ":" in a.name:
        raise Refused(f"{a.name} is a plugin skill: use 'skills-map plugin {a.name.split(':')[0]} on|off'", 2)
    w = World()
    s = w.by_name.get(a.name)
    if s is None or s["plugin"]:
        raise unknown("skill", a.name, [x["name"] for x in w.flat()])
    if RANK[state] >= 2 and s["pinned_by"] and not a.force:
        raise Refused(f"{a.name} is pinned by {', '.join(s['pinned_by'])}; --force to override")
    old = copy.deepcopy(w.state)
    w.state["overrides"][a.name] = state
    commit(w.state, old)
    print(f"{a.name}: {SHOW.get(state, state)} (takes effect in a new session)")
    return 0


def cmd_plugin(a: argparse.Namespace) -> int:
    w = World()
    if w.plugins is None:
        raise Refused("claude CLI unavailable: plugin commands disabled")
    name = a.name.split("@")[0]
    p = w.plugins.get(name)
    if p is None:
        raise unknown("plugin", name, list(w.plugins))
    if a.state == "off":
        members = [s for s in w.skills if s["plugin"] == name]
        outside = plugin_pins(w, name)
        for s in members:
            print(f"  {s['name']}: {s['uses']} use(s) in window")
        if outside and not a.force:
            raise Refused(f"plugin {name} is pinned by {', '.join(outside)}; --force to override")
        if any(s["uses"] for s in members) and not confirm(f"disable {name}?", a.yes):
            raise Refused("aborted")
    verb = "enable" if a.state == "on" else "disable"
    proc = subprocess.run([claude_bin(), "plugin", verb, p["id"]], capture_output=True, text=True)
    if proc.returncode != 0:
        raise Refused(f"claude plugin {verb} {p['id']} failed: {(proc.stderr or proc.stdout).strip()}")
    w.state["plugins"][name] = a.state == "on"
    save_state(w.state)
    print(f"plugin {name}: {a.state}")
    return 0


def cmd_recommend(a: argparse.Namespace, write: bool = False) -> int:
    w = World(a.days, a.refresh, a.with_store)
    if not w.found:
        raise Refused("no transcripts: no usage evidence to recommend from")
    rec = recommend(w, a.top, a.min_uses)
    cur, after = totals(w, rec)
    lines = diff_lines(w, rec)
    print(f"# per-turn listing ~{cur} -> ~{after} tokens; {len(lines)} change(s)")
    print("\n".join(lines) if lines else "  (no changes)")
    used = {s["plugin"] for s in w.skills if s["plugin"] and s["uses"]}
    idle = sorted(n for n, p in (w.plugins or {}).items() if p["enabled"] and n not in used)
    if idle:
        print(f"# plugins with 0 uses in {a.days}d ('skills-map plugin <name> off'): {', '.join(idle)}")
    if not write or not lines:
        return 0
    if not confirm("apply?", a.yes):
        raise Refused("aborted")
    old = copy.deepcopy(w.state)
    w.state["overrides"].update({n: v for n, v in rec.items() if w.by_name[n]["state"] != v})
    commit(w.state, old)
    print("applied (takes effect in a new session)")
    return 0


def drift(w: World) -> list[str]:
    try:
        _, obj = read_settings(real_settings())
        out: list[str] = []
    except Refused:
        obj, out = {}, [f"settings file {settings_path()} missing or unreadable"]
    raw = obj.get("skillOverrides")
    have: dict[str, Any] = raw if isinstance(raw, dict) else {}
    want = w.state["overrides"]
    for k in sorted(set(have) | set(want)):
        if have.get(k) != want.get(k):
            out.append(f"skillOverrides.{k}: settings={have.get(k)} state={want.get(k)}")
    for n, en in sorted(w.state["plugins"].items()):
        if w.plugins is not None and n in w.plugins and w.plugins[n]["enabled"] != en:
            out.append(f"plugin {n}: enabled={w.plugins[n]['enabled']} state={en}")
    return out


def cmd_status(a: argparse.Namespace) -> int:
    d = drift(World())
    print(json.dumps({"drift": d}) if a.json else ("\n".join(d) if d else "no drift"))
    return 0


def cmd_sync(a: argparse.Namespace) -> int:
    w = World()
    write_overrides(w.state["overrides"])
    for n, en in w.state["plugins"].items():
        if w.plugins and n in w.plugins and w.plugins[n]["enabled"] != en:
            verb = "enable" if en else "disable"
            outside = plugin_pins(w, n)
            if not en and outside:
                warn(f"not disabling plugin {n}: pinned by {', '.join(outside)} ('skills-map plugin {n} off --force')")
                continue
            if subprocess.run([claude_bin(), "plugin", verb, w.plugins[n]["id"]], capture_output=True).returncode:
                warn(f"claude plugin {verb} {n} failed")
    left = drift(World())
    print("synced" if not left else "\n".join(["remaining drift:", *left]))
    return 0 if not left else 1


def cmd_tui(a: argparse.Namespace) -> int:
    if not shutil.which("fzf"):
        print(table(World()))
        print("\nfzf not found: install it (apt install fzf | brew install fzf) for the TUI,")
        print("or toggle directly: skills-map set <name> on|name-only|user-only|off")
        if sys.stdin.isatty():
            input("enter to close")  # the herdr popup would otherwise close before this is read
        return 1
    keys = {"ctrl-o": "on", "ctrl-n": "name-only", "ctrl-u": "user-only", "ctrl-x": "off"}
    me = os.path.realpath(sys.argv[0])
    head = "TAB select  ctrl-o on  ctrl-n name-only  ctrl-u user-only  ctrl-x off  ctrl-r recommend  esc quit"
    while True:
        proc = subprocess.run(
            ["fzf", "--multi", "--header-lines=2", "--expect=" + ",".join([*keys, "ctrl-r"]), "--header=" + head,
             "--preview", f"{shlex.quote(sys.executable)} -I {shlex.quote(me)} _info {{2}}"],
            input=table(World()), capture_output=False, stdout=subprocess.PIPE, text=True,
        )  # fmt: skip
        out = proc.stdout.splitlines()
        if proc.returncode != 0 or not out:
            return 0
        key, picked = out[0], [ln.split()[1] for ln in out[1:] if len(ln.split()) > 1]
        if key == "ctrl-r":
            subprocess.run([sys.executable, "-I", me, "recommend"])
            input("enter to continue")
        elif key in keys:
            failed = [n for n in picked if subprocess.run([sys.executable, "-I", me, "set", n, keys[key]]).returncode]
            if failed:
                input("refused (see above); enter to continue")


def cmd_info(a: argparse.Namespace) -> int:
    s = next((r for r in rows(World()) if r["name"] == a.name), None)
    if s:
        print(f"{s['name']}  [{SHOW.get(s['state'], s['state'])}]  last: {s['last_used'] or '-'}")
        print(f"pinned by: {', '.join(s['pinned_by']) or '-'}\n\n{s['description']}")
    return 0


def parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="skills-map", description="Usage-aware skill exposure for Claude Code.")
    sub = ap.add_subparsers(dest="cmd")

    def window(p: argparse.ArgumentParser) -> None:
        p.add_argument("--days", type=int, default=30)
        p.add_argument("--refresh", action="store_true", help="ignore the usage cache")
        p.add_argument("--with-store", help="merge live mod records (JSON list of {skill, source, ts})")

    p = sub.add_parser("list", help="skills with state, usage and token cost")
    window(p)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_list)
    p = sub.add_parser("set", help="set one skill's exposure")
    p.add_argument("name")
    p.add_argument("state", choices=[*STATES, *ALIASES])
    p.add_argument("--force", action="store_true", help="override a pin")
    p.set_defaults(fn=cmd_set)
    p = sub.add_parser("plugin", help="enable/disable a plugin (claude plugin enable|disable)")
    p.add_argument("name")
    p.add_argument("state", choices=["on", "off"])
    p.add_argument("--yes", action="store_true")
    p.add_argument("--force", action="store_true", help="override a pin")
    p.set_defaults(fn=cmd_plugin)
    for verb, write in (("recommend", False), ("apply", True)):
        p = sub.add_parser(verb, help="usage-based exposure diff" + (" and write it" if write else " (no writes)"))
        window(p)
        p.add_argument("--top", type=int, default=10)
        p.add_argument("--min-uses", type=int, default=1)
        p.add_argument("--yes", action="store_true")
        p.set_defaults(fn=lambda a, _w=write: cmd_recommend(a, _w))
    p = sub.add_parser("status", help="drift between state and settings/plugins")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_status)
    sub.add_parser("sync", help="rewrite settings/plugins from state (state wins)").set_defaults(fn=cmd_sync)
    p = sub.add_parser("_info")
    p.add_argument("name")
    p.set_defaults(fn=cmd_info)
    return ap


def main(argv: list[str] | None = None) -> int:
    ap = parser()
    a = ap.parse_args(argv)
    if a.cmd is None:
        if sys.stdin.isatty() and sys.stdout.isatty():
            a.fn = cmd_tui
        else:
            a = ap.parse_args(["list"])
    try:
        if a.cmd in ("set", "plugin", "apply", "sync"):  # whole state read-modify-write under one lock
            with locked():
                return int(a.fn(a))
        return int(a.fn(a))
    except Refused as e:
        warn(str(e))
        return e.code


if __name__ == "__main__":
    sys.exit(main())
