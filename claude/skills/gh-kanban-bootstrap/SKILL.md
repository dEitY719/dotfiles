---
name: gh:kanban-bootstrap
description: >-
  Bootstrap a GitHub Projects v2 kanban board for the current repo in one
  shot — prereq validation, target repo identification, label bootstrap
  from SSOT, dry-run dispatch, real run, and host-aware UI checklist.
  Use when the user runs /gh:kanban-bootstrap, /gh-kanban-bootstrap, or
  asks "kanban 보드 셋업", "프로젝트 보드 자동화 셋업", "set up the kanban
  board". Wraps the single SSOT script `lib/setup.sh` (absorbed from
  the former scripts/ location per issue #699). Accepts the
  same flags as the script (`--owner`, `--repo`, `--title`,
  `--auto-archive-window`, `--hide-columns`, `--dry-run`,
  `--skip-pr-template`, `--no-auto-approve-env`) plus
  `--no-bootstrap-labels`, `--force-label-sync`,
  `--with-smoke-test`. Accepts `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep
---

# gh:kanban-bootstrap — Kanban Board Setup

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Resolve Skill Dir

Record `START_TS=$(date +%s)` immediately.

Locate `SKILL_DIR` (this file's directory). The script lives at
`${SKILL_DIR}/lib/setup.sh`; label SSOT at
`${SKILL_DIR}/references/labels.md`.

## Step 2: Prereq Check

Follow `references/prereq.md` for tool / host / token-scope checks
(including the `gh api --hostname` vs `gh auth refresh -h` flag-naming
inconsistency). On any miss the helper prints the install or
`gh auth refresh -h <host> -s project` hint and aborts (rc=1).

## Step 3: Target Repo

Always `origin` (memory policy — never prompt for remote selection on
this repo). Detect `OWNER/REPO` via `gh repo view`. If user passed
`--owner`/`--repo` explicitly, those override.

## Step 4: Options

If `--hide-columns` was not passed and this looks like a personal repo,
ask the user once (1-line question) — do not auto-infer from
collaborator count (NF-3 / privacy).

Parse `--no-bootstrap-labels` (skip Step 5 entirely) and
`--force-label-sync` (Step 5 sync mode).

## Step 5: Label Bootstrap

Apply the 8 SSOT labels per `references/labels.md` — the "Apply
decision matrix" section there resolves skip / PATCH (on
`--force-label-sync`) / POST per label. `--no-bootstrap-labels` skips
the whole step with a one-line notice. Per-label permission errors
warn on stderr and continue — label absence does not block board
setup.

## Step 6: Dry-run Dispatch

```
bash "${SKILL_DIR}/lib/setup.sh" --dry-run <user-flags>
```

On non-zero exit → abort (do not proceed to Step 7). Quote the script's
stderr first line.

## Step 7: Real Run

```
bash "${SKILL_DIR}/lib/setup.sh" <user-flags>
```

Parse stdout for `Project board setup finished` (success) or
`A project titled '<TITLE>' already exists` (idempotent re-run). Extract
the Project URL and number.

After board creation the script also performs **Step 7 (env wiring)**:
idempotently appends `OWNER/REPO` into the
`GH_PR_REPLY_AUTO_APPROVE_REPOS` CSV in `~/.zshrc.local` so the next
session passes the `gh:pr-reply` Step 8 solo-repo auto-approve G1
(repo allowlist) guard without manual edits. Suppress with
`--no-auto-approve-env` (e.g. org/collab repos).

## Step 8: UI Checklist + Report

The script's `print_final_report` already emits host-aware URLs (post-
#699 fix) and the workflow #3 `DISABLE` instruction. Pass-through its
output. Append:
- Smoke test command block (host-corrected; do not execute unless
  `--with-smoke-test`).
- Compact closing report: project URL, project number, label bootstrap
  summary (`<n> created, <m> skipped, <k> synced`), elapsed time.

## Constraints

- Never mutate the script's behavior — wrap, don't rewrite.
- Never auto-execute smoke test without explicit `--with-smoke-test`.
- Never echo token / collaborator / project ID to stdout (NF-3).
- Never silently fall back to a different remote — `origin` only.
- `lib/setup.sh` is the sole entry point — do not reintroduce the old `scripts/` location (removed in #699).
