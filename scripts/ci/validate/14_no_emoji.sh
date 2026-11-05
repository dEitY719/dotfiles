#!/usr/bin/env bash
# skill-check step: No emojis in tracked text
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
python3 - <<'PY'
import os, re, sys, subprocess, pathlib
# Pictographic planes only. Typographic marks the skills legitimately
# use (arrows, check marks, box drawing) are not emoji and must not
# trip this check.
def is_emoji(ch):
    cp = ord(ch)
    return cp >= 0x1F000 or cp == 0xFE0F
# Path prefixes a caller declared exempt, for a skill whose subject
# matter IS emoji (e.g. one that teaches emoji-styled blog headings).
# Empty by default, so every existing caller keeps the repo-wide ban.
raw = re.split(r"[,\n]", os.environ.get("ALLOW_EMOJI_PATHS", ""))
allowed = tuple(s.strip() for s in raw if s.strip())
if allowed:
    print(f"note  emoji allowed under: {', '.join(allowed)}")
# Vendored trees are not scanned at all, for the same reason the
# shellcheck step skips them: the repo may not edit them, so a finding
# there has no remedy it can apply -- fix it at the SSOT instead. Same
# input, and git's own :(exclude) carries the directory boundary, so
# `lib/vendor` never swallows a sibling `lib/vendor-tools/`.
raw = re.split(r"[,\n]", os.environ.get("SHELLCHECK_EXCLUDE_PATHS", ""))
skip = [f":(exclude){s}" for s in (x.strip().rstrip("/") for x in raw) if s]
if skip:
    print(f"note  emoji scan skips: {' '.join(skip)}")
files = subprocess.run(["git", "ls-files", "--", *skip], capture_output=True,
                       text=True, check=True).stdout.split()
bad = []
for f in files:
    p = pathlib.Path(f)
    if p.is_symlink() or not p.is_file():
        continue
    if allowed and f.startswith(allowed):
        continue
    try:
        text = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for i, line in enumerate(text.splitlines(), 1):
        for ch in line:
            if is_emoji(ch):
                bad.append(f"{f}:{i}: {ch!r}")
                break
if bad:
    print("FAIL  emoji found:")
    print("\n".join(bad))
    sys.exit(1)
print("ok    no emojis")
PY
