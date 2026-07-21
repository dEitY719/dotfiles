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
metadata:
  model_recommendation:
    tier: haiku
    reason: "structured Projects v2 board bootstrap; wraps deterministic lib/setup.sh, bounded report output, low reasoning"
    claude: prefer
    non_claude: advisory-only
---

# gh:kanban-bootstrap — Kanban Board Setup

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Resolve Skill Dir

Record `START_TS=$(date +%s)` immediately. Locate `SKILL_DIR` (this
file's directory): the script lives at `${SKILL_DIR}/lib/setup.sh`. The
label bootstrap is delegated to the sibling `gh:label-bootstrap` skill,
whose SSOT is `../gh-label-bootstrap/references/gh-labels.md` (issue #1226).

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
ask the user once (1-line question) — never auto-infer from collaborator
count (NF-3 / privacy). Parse `--no-bootstrap-labels` (skip Step 5).
`--force-label-sync` is a back-compat **no-op** (accept silently): the
delegated `gh:label-bootstrap` now always force-syncs SSOT label
colors/descriptions, so flag-present and flag-absent behave identically
(intentional, per F-3 of issue #1226).

## Step 5: Label Bootstrap

Delegate to the sibling `gh:label-bootstrap` skill (SSOT:
`../gh-label-bootstrap/references/gh-labels.md`):

```
bash "${SKILL_DIR}/../gh-label-bootstrap/lib/label-bootstrap.sh" \
    --repo "$OWNER/$REPO"
```

Pass `--dry-run` through on the dry-run dispatch (Step 6). It force-syncs
the 10 SSOT labels' color/description and renames the 3 alias labels.
`--no-bootstrap-labels` skips this step entirely with a one-line notice.
Per-label permission errors warn on stderr and continue (label absence
never blocks board setup).

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
the Project URL and number. The script then idempotently wires the
`gh:pr-reply` auto-approve env per `references/env-wiring.md` (suppress
with `--no-auto-approve-env`).

## Step 8: UI Checklist + Report

The script's `print_final_report` already emits host-aware URLs (post-
#699 fix) and the workflow #3 `DISABLE` instruction — pass it through,
then append the smoke-test block and compact closing report per
`references/report-template.md`.

## Constraints

- Never mutate the script's behavior — wrap, don't rewrite.
- Never auto-execute smoke test without explicit `--with-smoke-test`.
- Never echo token / collaborator / project ID to stdout (NF-3).
- Never silently fall back to a different remote — `origin` only.
- `lib/setup.sh` is the sole entry point — do not reintroduce the old `scripts/` location (removed in #699).
