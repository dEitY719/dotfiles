# gh:kanban-bootstrap — Help

Bootstrap a GitHub Projects v2 kanban board for the current repo.
Wraps the single SSOT script at `lib/setup.sh` with prereq checks,
label bootstrap, and host-aware UI checklist.

## Usage

```
/gh-kanban-bootstrap [--owner <login>] [--repo <name>] [options]
```

## Options (skill-layer)

| Option | Description | Default |
|---|---|---|
| `--no-bootstrap-labels` | Skip the label registration step (target repo follows a different label policy) | labels bootstrapped |
| `--force-label-sync` | PATCH existing labels whose color/description differ from the SSOT (`references/labels.md`) | preserve (no color change) |
| `--with-smoke-test` | Execute the smoke test commands instead of only printing them | print-only |

## Options (passed through to `lib/setup.sh`)

| Option | Description | Default |
|---|---|---|
| `--owner <login>` | GitHub user or org | auto from `gh repo view` |
| `--repo <name>` | Repository name | auto |
| `--title <board-title>` | Project title | repo name |
| `--auto-archive-window <dur>` | Done auto-archive filter | `2d` |
| `--hide-columns` | Add solo-repo hide guidance for `Approved` and `Ready` | off |
| `--dry-run` | Print the plan without mutations | off |
| `--skip-pr-template` | Skip remote PR template creation/check | off |
| `--no-auto-approve-env` | Skip wiring `GH_PR_REPLY_AUTO_APPROVE_REPOS` into `~/.zshrc.local` (non-solo / org / collab repos) | env wired |

## Prerequisites

- `gh` CLI installed and authenticated.
- `jq` installed.
- Token has `project` scope. Refresh with:
  `gh auth refresh -h <host> -s project`.

## What the skill does

1. Checks `gh` / `jq` + `project` scope (rc=1 on miss).
2. Resolves target repo (always `origin` — single dotfiles policy).
3. Bootstraps the 8 SSOT labels (`feat`, `refactor`, `test`, `ci`,
   `chore`, `performance`, `build`, `skill`) — idempotent.
4. Dry-runs `lib/setup.sh`. Aborts if dry-run fails.
5. Real-runs `lib/setup.sh`. Captures Project URL and number.
6. Idempotently wires `OWNER/REPO` into
   `GH_PR_REPLY_AUTO_APPROVE_REPOS` (in `~/.zshrc.local`) so the
   `gh:pr-reply` Step 8 solo-repo auto-approve G1 guard passes on
   the next session. Disable with `--no-auto-approve-env`.
7. Prints the host-aware UI checklist with workflow #3 disable
   guidance (per SSOT decision #289) and the smoke test commands.

## Re-run safety

If a board with the same title already exists, `lib/setup.sh` exits
cleanly with rc=0 and the existing URL. The skill surfaces this as
"이미 보드가 있어 재셋업을 건너뜁니다".

## Single SSOT note

The script `lib/setup.sh` (relocated from its former scripts/ location
in issue #699) lives only inside this skill. Invoke it directly from
non-Claude-Code contexts:
`bash claude/skills/gh-kanban-bootstrap/lib/setup.sh [...]`.

## Related

- SSOT: `docs/.ssot/github-project-board.md`
- Playbook: `docs/guide/playbooks/kanban-board-setup.md`
- Decision: #289 (3-stage issue lifecycle, workflow #3 disabled)
