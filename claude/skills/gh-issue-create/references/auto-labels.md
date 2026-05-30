# gh:issue-create — Auto-labels (Step 2.5)

Detail companion to SKILL.md Step 2.5. Step 2.5 attaches default labels
and a milestone to a freshly drafted issue **only when the target repo
opts in** by checking in a `.gh-issue-defaults.yml` (the SSOT). Repos
without that file keep the original behavior — no label or milestone is
auto-applied.

## Stage 1 — Repo signal detection

Step 2.5 runs only if at least one of the following signals is present
in `$TARGET_REPO`'s working tree:

1. `.gh-issue-defaults.yml` exists at the repo root. **Primary signal.**
   When present, it is also the schema source — Step 2.5 reads it.
2. `.github/workflows/stacked-closes-rollup.yml` exists. (Inherited from
   the stacked-PR Stage-1 detection contract — co-located automation
   policy lives here.)
3. `agent-toolbox/` directory exists at the repo root.
4. `CLAUDE.md`, `AGENTS.md`, or `.claude/github-integration.md` mentions
   `.gh-issue-defaults.yml` (`grep -q`).

If none match, skip Step 2.5 entirely. The skill still creates the issue
without labels or milestones — the historical default.

If signal #1 is absent but signal #2/#3/#4 fired, Step 2.5 also stops:
without the SSOT it has no schema to follow. Print one stderr line
(`auto-labels: signal detected but .gh-issue-defaults.yml missing — skip`)
and continue to Step 4.

## Schema (recognised keys)

```yaml
default_labels:
  static:           [<label>, ...]   # appended to every new issue
  by_title_prefix:                   # conventional-commit prefix → labels
    feat:     [feat]
    fix:      [bug]
    refactor: [refactor]
    test:     [test]
    verify:   [verify]               # live verification-tracking issue
    ci:       [ci]
    docs:     [documentation]
    chore:    []                     # explicit empty = "no label"

milestone: auto                      # auto | none | "<exact name>"
```

- `static` accepts both inline (`[a, b]`) and block-list (`- a` lines).
- `by_title_prefix` keys must be lowercase conventional-commit prefixes.
  Anything not listed (e.g. `perf`, `misc`) yields no label.
- `milestone: auto` resolves to the most recent open milestone returned
  by `gh api repos/$TARGET_REPO/milestones?state=open` (highest `number`).
- `milestone: none` (or empty) skips milestone application.
- `milestone: "<name>"` matches an open milestone with that exact title;
  unknown names warn-and-skip.

The shipped parser (`shell-common/functions/parse_yaml_defaults.sh`) is
intentionally minimal and only understands those keys — anchors, nested
maps, multi-doc files, and other YAML features are NOT supported.

## Dispatch order (inside Step 2.5)

1. Detect Stage-1 signals (above). If absent → skip.
2. Source `parse_yaml_defaults.sh` and load:
   - `static_labels` ← `_parse_yaml_defaults_static <yml>`
   - `prefix_labels` ← `_parse_yaml_defaults_by_prefix <yml> <prefix>`
     (`<prefix>` = the conventional-commit prefix chosen in Step 2)
   - `milestone_value` ← `_parse_yaml_defaults_milestone <yml>`
3. Compose the **candidate label set** as
   `static_labels ∪ prefix_labels ∪ user_labels`. (`user_labels` are the
   `--label foo` values the operator passed on the CLI — they are
   merged, never overridden. `--no-auto-labels` short-circuits Step 2.5
   entirely so user labels are kept untouched.)
4. Validate each candidate against `gh label list --repo $TARGET_REPO
   --json name --jq '.[].name'`. Missing labels emit
   `auto-labels: label '<x>' not found in $TARGET_REPO — skip` on stderr
   and are dropped from the set. **Never auto-create labels** — see the
   pinned memory rule "gh labels — verify before apply".
5. Resolve the milestone:
   - `auto` → query open milestones, pick the highest `number`.
   - `none`/empty → skip.
   - `"<name>"` → match by exact title; missing → warn-skip.
6. Build the `gh issue create` arg list with one `--label <x>` per kept
   label and (optionally) `--milestone <name>`.

## Operator escapes

- `--no-auto-labels` — skip Step 2.5 entirely. User-supplied `--label`
  values still apply.
- `--auto-label-debug` — print the full Stage-1 evaluation, the YAML
  values that were loaded, and the kept/dropped sets to stderr before
  Step 4 runs.

## Compatibility matrix

| Scenario | repo signal | SSOT file | Outcome |
|---|---|---|---|
| dotfiles, title `feat: ...` | yes | yes | `--label feat` |
| dotfiles, title `chore: ...` | yes | yes | no label (chore=[]) |
| dotfiles, title `feat: ...` + `--label skill` | yes | yes | `--label feat --label skill` (union) |
| AgentToolbox, title `feat: ...` | yes | yes | static + prefix labels both applied |
| Generic repo | no | no | original behaviour, no auto labels |
| `--no-auto-labels` | n/a | n/a | original behaviour |
| dotfiles, title `docs: ...`, `documentation` label missing | yes | yes | warn + skip; other labels still apply |

The bats suite at `tests/bats/skills/gh_issue_create_auto_labels.bats`
locks all seven rows.
