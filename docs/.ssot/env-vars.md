# Environment Variables Catalog

Cross-skill / cross-tool env vars that change runtime behaviour. New
toggles MUST land here so operators can grep one file before adopting
a new repo or workspace.

> **스킬 이름 표기 (#1410 Phase 3, #1678, #1680)** — 이 문서는 스킬을 분리 후
> 플러그인 네임스페이스(`gh-issue:create`, `gh-pr:create`, `gh-flow:issue` …)로
> 적는다. dotfiles 의 `claude/skills/` 원본은 #1680 (Phase 4) 에서 삭제됐지만
> **옛 이름(`/gh-issue-create`, `/gh-pr`, `/gh-issue-flow` …)으로도 계속
> 호출된다** — `gh_flow.sh` · `issue_watcher_cron.sh` 같은 운영 자동화가
> 아직 옛 슬래시 명령을 dispatch 하기 때문이다 (#1410 NF-1, D-12; 정리는
> Phase4-3). 본문에 남은 `claude/skills/<dir>/` 경로는 삭제된 원본을 가리키는
> 이력 표기이며, 실물은 해당 marketplace repo 의 `skills/<name>/` 에 있다.

## `gh-*` skills

### `GH_DISABLE_AI_METRICS`

| Field | Value |
|---|---|
| Default | unset |
| Active when | set to `1` |
| Scope | every `gh:*` skill that writes to GitHub (issue/PR body footer, issue/PR comment) |
| Source SSOT | `claude/skills/gh-issue-create/references/metrics-helper.md` |
| Issue | [#399](https://github.com/dEitY719/dotfiles/issues/399) — design comment [#384](https://github.com/dEitY719/dotfiles/issues/384#issuecomment-4404284951) |

When the variable is `1`, the following skills skip ai-metrics
attachment and produce identical artifacts otherwise:

- `gh-issue:create` — issue body footer
- `gh-pr:create` — PR body footer
- `gh-pr:commit` — linked-issue comment
- `gh-pr:reply`, `gh-pr:approve`, `gh-pr:merge`, `gh-resolve:conflict` — PR comment
- `gh-pr:merge-emergency` — incident issue body footer
- `gh-flow:issue` — flow-aggregate issue comment (Step 2.6)

`gh-issue:implement` and `gh-issue:read` print metrics to stdout only,
so the env var has no effect there.

`gh-setup:add-ai-metrics` is the **deliberate retrofit** path and **ignores**
this var — that is its entire purpose.

Use cases:

- External / company repos that disallow AI-usage markers in artifacts
- Debugging or one-off invocations where the footer would be noise
- Mirroring a teammate's preference temporarily

Per-call examples:

```bash
GH_DISABLE_AI_METRICS=1 /gh-pr:create 399
GH_DISABLE_AI_METRICS=1 /gh-pr:commit
```

Persist for a session:

```bash
export GH_DISABLE_AI_METRICS=1
```

### `GH_PR_MERGE_SKIP_BOARD_CHECK` (retired, #1513)

Removed together with `gh-pr:merge` Step 2-B — there is no longer a
board approval gate to bypass. Setting it has no effect. Rationale:
`claude/skills/gh-pr-merge/references/board-policy.md`.

### `GH_PROJECT_STATUS_SYNC`

| Field | Value |
|---|---|
| Default | unset (treated as enabled) |
| Active when | set to `0` |
| Scope | every `gh:*` skill that calls `_gh_project_status_sync` |
| Source SSOT | `shell-common/functions/gh_project_status.sh` |

When `0`, skip pushing project-board card status updates. Repos
without a projectV2 attachment auto-skip without needing the var.

### `GH_REPO`

| Field | Value |
|---|---|
| Default | unset |
| Active when | set to `OWNER/REPO` or `HOST/OWNER/REPO` |
| Scope | `_gh_project_status_sync` / `_gh_project_status_query_current` repo resolution |
| Source SSOT | `shell-common/functions/gh_project_status.sh` |
| Issue | [#1405](https://github.com/dEitY719/dotfiles/issues/1405) |

Pins the repo whose projectV2 board is read/written, instead of
auto-detecting it. Same variable `gh` itself honors, so a value already
exported for `gh` is reused as-is. Both the `OWNER/REPO` and
`HOST/OWNER/REPO` forms are accepted; in the three-segment form the host
segment is only **structurally** checked (present and non-empty) and then
dropped. It is *not* compared against `GH_HOST` — host routing stays
`GH_HOST`'s job, so `github.com/o/r` under `GH_HOST=ghes.example.com`
resolves to `o/r` on the GHES host without complaint (PR #1409 review,
codex). Pass the two-segment form and set `GH_HOST` explicitly if you want
the host to be unambiguous.

Precedence, first non-empty wins:

1. `--repo <owner/repo>` argument to `_gh_project_status_sync` (or the
   optional 3rd positional of `_gh_project_status_query_current`)
2. `GH_REPO`
3. `TARGET_REPO`
4. `gh repo view --json owner,name` auto-detect

A malformed value at levels 1–3 fails closed (resolution returns 1) — it
does **not** fall through to auto-detect. A bare `gh repo view` reports
what `gh repo set-default` chose, not git's origin, so silently rescuing a
typo could sync a different repo's board.

### `PMV_PROMPT_TIMEOUT_MS`

| Field | Value |
|---|---|
| Default | `900000` (15 min) |
| Active when | set to a millisecond count |
| Scope | `gh-verify:post-merge-verify` — the `herdr agent prompt --wait --until idle` cap |
| Source SSOT | `claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md` |
| Issue | [#1511](https://github.com/dEitY719/dotfiles/issues/1511) |

Caps how long the dispatch waits for the verification session to settle
after the prompt lands. Generous by default because `--until idle` waits
for a whole verification turn. Hitting the cap is a `[WARN]`, never a
failure — the prompt has already been delivered and the `herdr agent
attach` hint still prints.

### `TARGET_REPO`

| Field | Value |
|---|---|
| Default | unset |
| Active when | set to `OWNER/REPO` or `HOST/OWNER/REPO` |
| Scope | `_gh_project_status_sync` / `_gh_project_status_query_current` repo resolution |
| Source SSOT | `shell-common/functions/gh_project_status.sh` |
| Issue | [#1405](https://github.com/dEitY719/dotfiles/issues/1405) |

Same meaning as `GH_REPO`, one step lower in the precedence chain above.
Exists because the `gh:*` skills already export `TARGET_REPO` when they
pin a remote, so the board helper picks it up without the skill having to
also set `GH_REPO`. Ignored when `GH_REPO` or an explicit `--repo`
argument is present.

**Staleness hazard** (PR #1409 review, agy). `TARGET_REPO` is a generic,
non-namespaced name that many `gh:*` skills export into the shell. A value
left over from an earlier skill run in the same shell can therefore be
picked up by a later board sync that meant to auto-detect — silently
writing to the wrong repo's board. Two things bound the risk, and neither
removes it:

- Every in-repo caller of the board helper now passes `--repo` explicitly
  (precedence level 1), so the env tiers are a fallback that a correct
  caller never reaches.
- A stale value that is malformed fails closed rather than falling through.

A stale value that is *well-formed but wrong* is still honored. If you
export `TARGET_REPO` by hand, unset it when you are done — and prefer
`--repo` over the env tiers in any new caller.

## How to add a new entry

1. Document the var here first (this file is the catalog SSOT).
2. Implement the env branch in the skill / function SSOT.
3. Add a regression test in `tests/bats/` that covers the set/unset
   branches.
4. Land all three in the same PR.
