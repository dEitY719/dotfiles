# Post-merge verification dispatch — the verbatim block

Step 3 pastes this. It expects `PR_NUMBER`, `TARGET_REPO` and `TARGET_HOST`
already bound (Step 2), and it is a no-op for any repo missing from
`docs/.ssot/watched-repos.json`.

Executable mirror + regression suite:
`tests/bats/skills/_fixtures/gh_pr_post_merge_verify.sh` and
`tests/bats/skills/gh_pr_post_merge_verify.bats`. Change one, change both.

```bash
# --- 0. F-1 gate. Unregistered repo => do nothing at all, no output. -------
WATCHED_FILE="${DOTFILES_ROOT:-$HOME/dotfiles}/docs/.ssot/watched-repos.json"
VERIFY_SKILL=""
if [ -r "$WATCHED_FILE" ]; then
    if ! VERIFY_SKILL=$(jq -r --arg r "$TARGET_REPO" \
        '.[$r].verify_skill // empty' "$WATCHED_FILE" 2>/dev/null); then
        # The file exists but is not JSON: a broken SSOT, not an opt-out.
        printf '[WARN] gh:pr-post-merge-verify: %s is not valid JSON — post-merge verification skipped.\n' \
            "$WATCHED_FILE"
        VERIFY_SKILL=""
    fi
fi
[ -n "$VERIFY_SKILL" ] || return 0 2>/dev/null || exit 0
command -v herdr >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

# --- helpers --------------------------------------------------------------
# First string value of a flat key anywhere in the document. `herdr tab create`
# answers `.result.pane.pane_id` and `herdr workspace create` answers
# `.result.root_pane.pane_id`; keying on the leaf name survives both, and any
# third shape the CLI adds. The key travels as a jq *argument*, never as
# interpolated program text. (Same helper as _pmt_json_first.)
pmv_json_first() {
    jq -r --arg k "$1" \
        '[.. | objects | .[$k]? // empty] | map(select(type == "string")) | first // empty' \
        2>/dev/null || return 0
}
# `.error.code` off a failed herdr answer, or empty. Fixed filter, so nothing
# is ever interpolated into the jq program text.
pmv_error_code() { jq -r '.error.code // empty' 2>/dev/null || return 0; }
pmv_slug() { printf '%s%s' "$1" "$(printf '%s' "$2" | tr -c 'A-Za-z0-9._-' '-')"; }
pmv_physical_path() { (cd -P "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }

# tab_id of a live agent sitting on <physical path>: rc 0 = matched, rc 1 =
# herdr could not be asked, rc 3 = herdr answered and nothing is on that path.
# An empty answer from herdr is "unknown", never "nothing running" — the one
# mistake this signal cannot afford (issue_watcher_cron.sh's lesson). Match
# BOTH cwd and foreground_cwd, prefix-match the PHYSICAL path, and never match
# on an empty prefix (it would select an unrelated tab).
pmv_tab_for_cwd() {
    [ -n "$1" ] || return 3
    _pmv_json=$(herdr agent list 2>/dev/null) || return 1
    [ -n "$_pmv_json" ] || return 1
    _pmv_tab=$(printf '%s' "$_pmv_json" | jq -r --arg p "$1" '
        if (.result.agents | type) == "array" then
          [ .result.agents[]?
            | select(((.cwd // "") | startswith($p)) or ((.foreground_cwd // "") | startswith($p)))
            | .tab_id // empty ]
          | map(select(type == "string" and . != "")) | first // empty
        else error("no agent list") end
    ' 2>/dev/null) || return 1
    [ -n "$_pmv_tab" ] || return 3
    printf '%s' "$_pmv_tab"
}

# --- the main checkout (never a worktree) ---------------------------------
# `main_checkout` from the registry when set; otherwise git's common dir,
# which answers `<main-checkout>/.git` even from inside a linked worktree.
MAIN_ROOT=$(jq -r --arg r "$TARGET_REPO" '.[$r].main_checkout // empty' "$WATCHED_FILE" 2>/dev/null)
case "$MAIN_ROOT" in
'~'/*) MAIN_ROOT="${HOME}/${MAIN_ROOT#'~'/}" ;;
'') MAIN_ROOT=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    MAIN_ROOT="${MAIN_ROOT%/.git}" ;;
esac

# --- 1/2. F-2: close the implementation tab (best-effort, never blocking) --
IMPL_WT=$(git worktree list --porcelain 2>/dev/null |
    awk -v b="refs/heads/${HEAD_BRANCH}" '
        /^worktree / { p = substr($0, 10) }
        $0 == ("branch " b) { print p; exit }
    ')
if [ -z "$IMPL_WT" ]; then
    printf '[INFO] gh:pr-post-merge-verify: no local worktree for %s — nothing to close.\n' "$HEAD_BRANCH"
elif IMPL_TAB=$(pmv_tab_for_cwd "$(pmv_physical_path "$IMPL_WT")"); then
    if herdr tab close "$IMPL_TAB" >/dev/null 2>&1; then
        printf '[INFO] gh:pr-post-merge-verify: closed implementation tab %s (%s).\n' "$IMPL_TAB" "$IMPL_WT"
    else
        printf '[WARN] gh:pr-post-merge-verify: herdr tab close %s failed — continuing.\n' "$IMPL_TAB"
    fi
else
    printf '[INFO] gh:pr-post-merge-verify: no live herdr tab on %s — nothing to close.\n' "$IMPL_WT"
fi

# --- 3. F-3: the main checkout must be clean and rebased, or we stop -------
if [ -n "$(git -C "$MAIN_ROOT" status --porcelain 2>/dev/null)" ]; then
    printf '[WARN] gh:pr-post-merge-verify: %s has uncommitted changes — not rebasing, verification skipped.\n' "$MAIN_ROOT"
    return 0 2>/dev/null || exit 0
fi
if ! (git -C "$MAIN_ROOT" fetch origin main &&
    git -C "$MAIN_ROOT" rebase origin/main) >/dev/null 2>&1; then
    # Restore, never resolve: picking sides is the human's call, but leaving
    # the user's main checkout parked mid-rebase is a worse failure.
    git -C "$MAIN_ROOT" rebase --abort >/dev/null 2>&1 || true
    printf '[WARN] gh:pr-post-merge-verify: fetch/rebase failed in %s (rebase aborted, conflict not resolved) — verification skipped.\n' "$MAIN_ROOT"
    return 0 2>/dev/null || exit 0
fi

# --- 4. F-4: the verification tab -----------------------------------------
WS_JSON=$(herdr worktree list --cwd "$MAIN_ROOT" --json 2>/dev/null) || WS_JSON=""
WS_ID=$(printf '%s' "$WS_JSON" | jq -r --arg p "$MAIN_ROOT" '
    [ (.result.source.source_workspace_id? // empty),
      (.result.worktrees[]? | select(.path == $p) | .open_workspace_id? // empty) ]
    | map(select(type == "string" and . != "")) | first // empty
' 2>/dev/null) || WS_ID=""
[ -n "$WS_ID" ] || WS_ID=$(printf '%s' "$WS_JSON" | pmv_json_first source_workspace_id)
if [ -z "$WS_ID" ]; then
    printf '[WARN] gh:pr-post-merge-verify: no herdr workspace for %s — verification tab not created.\n' "$MAIN_ROOT"
    return 0 2>/dev/null || exit 0
fi

set -- tab create --workspace "$WS_ID" --cwd "$MAIN_ROOT" --label "pr-${PR_NUMBER}" --no-focus
[ -z "${CLAUDE_CONFIG_DIR-}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR}"
TAB_JSON=$(herdr "$@" 2>/dev/null) || TAB_JSON=""
NEW_PANE=$(printf '%s' "$TAB_JSON" | pmv_json_first pane_id)
NEW_TAB=$(printf '%s' "$TAB_JSON" | pmv_json_first tab_id)
if [ -z "$NEW_PANE" ]; then
    printf '[WARN] gh:pr-post-merge-verify: herdr tab create failed for label pr-%s — verification skipped.\n' "$PR_NUMBER"
    return 0 2>/dev/null || exit 0
fi

# --- 5. F-4: the agent ----------------------------------------------------
# Host-qualified: `owner/repo` alone is not unique across GitHub servers, so a
# slug-only name would undo #1403/#1407's pinning at the session-identity
# layer (same rationale as _PMT_AGENT_PREFIX).
PMV_AGENT=$(pmv_slug "pmv-" "${TARGET_HOST}/${TARGET_REPO}-${PR_NUMBER}")
# `--dangerously-skip-permissions` is required, not a convenience: nobody is at
# the keyboard of this pane, so one permission prompt would park the
# verification forever instead of failing it (same reason as #1393).
if ! START_JSON=$(herdr agent start "$PMV_AGENT" --kind claude --pane "$NEW_PANE" \
    -- --dangerously-skip-permissions 2>/dev/null); then
    # Race backstop: the name can be claimed between the probe and the start,
    # and its holder is by definition a usable agent — prompt it rather than
    # failing the dispatch (same backstop as _pmt_launch_fresh).
    START_CODE=$(printf '%s' "$START_JSON" | pmv_error_code)
    if [ "$START_CODE" != "agent_name_taken" ]; then
        printf '[WARN] gh:pr-post-merge-verify: herdr agent start %s failed on pane %s (%s) — verification skipped.\n' \
            "$PMV_AGENT" "$NEW_PANE" "${START_CODE:-unknown}"
        return 0 2>/dev/null || exit 0
    fi
    printf '[WARN] gh:pr-post-merge-verify: agent %s already registered — prompting the existing session.\n' "$PMV_AGENT"
fi

# --- 6. F-5: hand the verification over -----------------------------------
# The registry stores the skill id (`devx:pr-verify-merged`); a pane is typed
# the dash form, which is what a Claude session accepts as a slash command.
VERIFY_PROMPT="/$(printf '%s' "$VERIFY_SKILL" | tr ':' '-') ${PR_NUMBER}"
if ! PROMPT_JSON=$(herdr agent prompt "$PMV_AGENT" "$VERIFY_PROMPT" \
    --wait --until idle --timeout "${PMV_PROMPT_TIMEOUT_MS:-900000}" 2>/dev/null); then
    PROMPT_CODE=$(printf '%s' "$PROMPT_JSON" | pmv_error_code)
    printf '[WARN] gh:pr-post-merge-verify: herdr agent prompt %s failed (%s) — attach and run it by hand.\n' \
        "$PMV_AGENT" "${PROMPT_CODE:-unknown}"
fi

# --- 7. report ------------------------------------------------------------
printf 'post-merge verification dispatched\n'
printf '  tab:    %s (label pr-%s)\n' "${NEW_TAB:--}" "$PR_NUMBER"
printf '  agent:  %s\n' "$PMV_AGENT"
printf '  verify: %s\n' "$VERIFY_PROMPT"
printf '  attach: herdr agent attach %s\n' "$PMV_AGENT"
```

## Inputs

| Variable | Bound by | Notes |
|---|---|---|
| `PR_NUMBER` | Step 1 | The merged PR |
| `TARGET_REPO` / `TARGET_HOST` | Step 2 | One remote URL, #1403/#1407 |
| `HEAD_BRANCH` | caller | The merged PR's head branch, used to find the impl worktree |
| `PMV_PROMPT_TIMEOUT_MS` | env, optional | `herdr agent prompt --wait` cap, default 900000 (15 min) |

`--wait --until idle` waits for the dispatched session to settle, so the
timeout is generous. Hitting it is a `[WARN]`, not a failure: the prompt has
already landed, and the attach hint is still printed.

## herdr JSON shapes this relies on (verified against herdr 0.7.5)

| Call | Field read |
|---|---|
| `herdr agent list` | `.result.agents[].cwd`, `.foreground_cwd`, `.tab_id` (no `--json` flag; it answers JSON on stdout already) |
| `herdr worktree list --cwd P --json` | `.result.source.source_workspace_id`, `.result.worktrees[].path`, `.open_workspace_id` |
| `herdr tab create` | `pane_id` / `tab_id`, read by leaf name |
| `herdr agent start` / `prompt` | `.error.code` on failure |
