#!/usr/bin/env bash
# skill-check step: Declared cross-file facts agree
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import os, re, sys, subprocess, pathlib, yaml
# The step above gates one hardcoded equality (version) over one
# hardcoded file list. This one gates a built-in set plus any
# equality a caller declares, because most facts that drift are
# repo-specific: `license` is stated six times in all sixteen repos,
# while claudecode-skills pins a bundled-asset SHA in six places of
# its own.
#
# Which gate a fact belongs in: a fact a caller must not be able to
# switch off by omitting it is hardcoded, never read from the input
# -- as the step above when a JSON key path pins the value more
# exactly than a regex could (`version` reads marketplace.json's
# plugins[0]), or as a built-in set below when a regex reaches it.
# A repo-specific fact comes through this input, and is merged into
# the built-ins rather than replacing them.
#
# A value is a regex capture group, never a YAML/JSON key path. The
# SHA case is a bare string in prose, so key-only extraction would
# cover `license` and miss the case that motivated the gate; one
# mechanism that covers both beats two that each cover half.
#
# `license` is the DEFAULT set, not a caller's opt-in: the same four
# globs hold in all sixteen repos (harness-skills#23), so an
# opt-in-only gate would leave sixteen already-agreeing repos free to
# drift apart -- and would need sixteen copies of this config to say
# so. LICENSE's own regex names MIT on purpose: a relicense then
# fails on this file by name, which is the one file whose prose has
# to be rewritten by hand anyway; the other three carry an SPDX id
# and compare as one.
#
# It lives here rather than in the input's `default:` because an
# input default is REPLACED by a caller's value. A caller declaring
# its own set (claudecode-skills' bundled-asset SHA set) must ADD to
# this one -- silently dropping its license gate is the same
# silent-pass shape this whole step exists to remove.
DEFAULT_SETS = r"""
license:
  LICENSE: '^(MIT) License'
  '.*-plugin/plugin.json': '"license":\s*"([^"]+)"'
  package.json: '"license":\s*"([^"]+)"'
  'skills/*/SKILL.md': '^license:\s*(\S+)'
"""
sets = yaml.safe_load(DEFAULT_SETS)
raw = os.environ.get("CONSISTENCY_CHECKS", "").strip()
if raw:
    try:
        extra = yaml.safe_load(raw)
    except yaml.YAMLError as e:
        sys.exit(f"FAIL  consistency-checks is not valid YAML: {e}")
    if not isinstance(extra, dict) or not extra:
        sys.exit("FAIL  consistency-checks must be a mapping of "
                 "<set name> -> {<path glob>: <regex>}")
    clash = sorted(set(extra) & set(sets))
    if clash:
        sys.exit(f"FAIL  consistency-checks redefines built-in set "
                 f"{clash}: the built-in set always runs, so name "
                 f"the caller's set something else")
    sets.update(extra)

# A vendored directory can legitimately carry a different license
# than the repo around it -- authoring-skills#14: skills/skill-create/
# is an Apache-2.0 derivative of Anthropic's skill-creator inside an
# MIT repo, and Apache-2.0 section 4(a) forbids relicensing it. The
# built-in set cannot simply be widened to allow two values: "these
# files disagree" is the whole signal. So the exception is DECLARED,
# per path, with the value it must carry.
#
# This is not an opt-out, for the same reason the caller cannot
# redefine the built-in set: a declared file is still gated, just
# against the value named here instead of against its siblings. A
# glob that matches nothing fails loudly, like every other dead glob
# in this step -- an exception for a file that moved away is an
# exception nobody is checking.
exc_raw = os.environ.get("LICENSE_EXCEPTIONS", "").strip()
exceptions = {}
if exc_raw:
    try:
        decl = yaml.safe_load(exc_raw)
    except yaml.YAMLError as e:
        sys.exit(f"FAIL  license-exceptions is not valid YAML: {e}")
    if not isinstance(decl, dict) or not decl:
        sys.exit("FAIL  license-exceptions must be a mapping of "
                 "<path glob> -> <expected license>")
    for glob, want in decl.items():
        proc = subprocess.run(["git", "ls-files", "-z", "--", f":(glob){glob}"],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            sys.exit(f"FAIL  license-exceptions: git rejected glob "
                     f"{glob!r}: {proc.stderr.strip()}")
        hit = [x for x in proc.stdout.split("\0") if x]
        if not hit:
            sys.exit(f"FAIL  license-exceptions: glob {glob!r} matched no file")
        for x in hit:
            exceptions[x] = str(want)
fail = 0
for name, sites in sets.items():
    if not isinstance(sites, dict) or not sites:
        print(f"FAIL  {name}: needs a mapping of <path glob> -> <regex>")
        fail = 1
        continue
    seen = {}
    for glob, pattern in sites.items():
        try:
            rx = re.compile(str(pattern), re.M)
        except re.error as e:
            print(f"FAIL  {name}: bad regex {pattern!r}: {e}")
            fail = 1
            continue
        # Discovery is over TRACKED files, like every other step
        # here: an untracked scratch file must not be able to fail a
        # repo's gate. `:(glob)` keeps `*` from crossing `/`, so
        # `skills/*/SKILL.md` means what it looks like.
        proc = subprocess.run(["git", "ls-files", "-z", "--", f":(glob){glob}"],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            print(f"FAIL  {name}: git rejected glob {glob!r}: {proc.stderr.strip()}")
            fail = 1
            continue
        paths = sorted(pathlib.Path(x) for x in proc.stdout.split("\0") if x)
        paths = [x for x in paths if x.is_file() and not x.is_symlink()]
        if not paths:
            # Loud, for the same reason the shellcheck step refuses a
            # failed discovery: a set that quietly checks nothing is
            # indistinguishable from a set that passed.
            print(f"FAIL  {name}: glob {glob!r} matched no file")
            fail = 1
            continue
        for p in paths:
            try:
                text = p.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError) as e:
                print(f"FAIL  {name}: {p} is unreadable as text: {e}")
                fail = 1
                continue
            # First match wins: this set is about agreement ACROSS
            # files, and a fact stated twice inside one file is that
            # file's own problem.
            m = rx.search(text)
            if not m or not m.groups():
                print(f"FAIL  {name}: {p} has no capture-group match for {pattern!r}")
                fail = 1
                continue
            # Declared exceptions are gated against their own
            # value and kept out of `seen`, so they neither satisfy
            # nor break the agreement check for everyone else.
            if name == "license" and str(p) in exceptions:
                want = exceptions[str(p)]
                if m.group(1) != want:
                    print(f"FAIL  {name}: {p} is declared as {want} "
                          f"but carries {m.group(1)}")
                    fail = 1
                else:
                    print(f"ok    {name}: {p} = {want} (declared exception)")
                continue
            if str(p) in seen:
                print(f"FAIL  {name}: {p} is matched by two globs, so one regex would "
                      f"silently win over the other")
                fail = 1
                continue
            seen[str(p)] = m.group(1)
    # Every file and its value, always -- "these files disagree" is
    # only actionable next to the values it is talking about.
    for f, v in sorted(seen.items()):
        print(f"{v}\t{f}")
    distinct = sorted(set(seen.values()))
    if len(distinct) > 1:
        print(f"FAIL  {name}: sites disagree: {distinct}")
        fail = 1
    elif distinct:
        print(f"ok    {name} = {distinct[0]} across {len(seen)} file(s)")
sys.exit(fail)
PY
