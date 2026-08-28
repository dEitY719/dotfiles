#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_post_merge_verify.sh
# Source-of-truth mirror for the dispatch block documented in
#   claude/skills/gh-pr-post-merge-verify/SKILL.md  (issue #1511)
# whose verbatim shell lives in
#   claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md
#
# The skill runs inside a Claude session, but everything it decides is a small
# shell block: given watched-repos.json, `herdr agent list` and the state of
# the main checkout, does it close a tab, rebase, open a verification session,
# or silently do nothing? Keep this file in sync with dispatch.sh.md — if the
# skill block changes, mirror the change here so bats catches the drift.
#
# Every function takes explicit arguments. No globals beyond the FAKE_* knobs
# the stand-ins read, and no network.

# ============================================================
# Stand-ins for the external commands (tests drive them via FAKE_*)
# ============================================================

# Stand-in for `command -v herdr >/dev/null 2>&1`.
_pmv_herdr_present() { [ "${FAKE_HERDR_PRESENT:-1}" = "1" ]; }

# Stand-in for `command -v jq >/dev/null 2>&1`. Without jq the registry cannot
# be read at all, so the feature is unavailable — silently, never a WARN.
_pmv_jq_present() { [ "${FAKE_JQ_PRESENT:-1}" = "1" ]; }

# Stand-in for the `herdr` CLI. Records its argv into $FAKE_HERDR_LOG when the
# test sets it, echoes $FAKE_HERDR_OUT_<SUB_CMD> and returns
# $FAKE_HERDR_RC_<SUB_CMD> (e.g. FAKE_HERDR_OUT_TAB_CREATE, defaults rc 0).
_pmv_herdr() {
    local _key _out _rc
    [ -z "${FAKE_HERDR_LOG-}" ] || printf 'herdr %s\n' "$*" >>"$FAKE_HERDR_LOG"
    _key=$(printf '%s_%s' "$1" "$2" | tr 'a-z-' 'A-Z_')
    _out="FAKE_HERDR_OUT_${_key}"
    _rc="FAKE_HERDR_RC_${_key}"
    printf '%s' "${!_out-}"
    return "${!_rc:-0}"
}

# Stand-in for `sleep`. Records the wait into the herdr log instead of paying
# it, so the settle waits (#1571) can be asserted — and ordered against the
# herdr calls they sit between — without the suite sleeping 26 real seconds per
# dispatch test.
_pmv_sleep() {
    [ -z "${FAKE_HERDR_LOG-}" ] || printf 'sleep %s\n' "$1" >>"$FAKE_HERDR_LOG"
    return 0
}

# Stand-in for `git -C <root> worktree list --porcelain`.
_pmv_git_worktree_list() {
    printf '%s' "${FAKE_WORKTREE_PORCELAIN-}"
    return "${FAKE_WORKTREE_RC:-0}"
}

# Stand-in for `git -C <root> rev-parse --show-toplevel`. Empty output means
# "not a git worktree" — what a bogus or empty MAIN_ROOT produces.
_pmv_git_toplevel() {
    [ -z "${FAKE_GIT_LOG-}" ] || printf 'toplevel %s\n' "$1" >>"$FAKE_GIT_LOG"
    printf '%s' "${FAKE_MAIN_TOPLEVEL-$1}"
}

# Stand-in for `git -C <root> rev-parse --abbrev-ref HEAD`. Answers `HEAD` on a
# detached checkout, exactly as git does.
_pmv_git_current_branch() {
    [ -z "${FAKE_GIT_LOG-}" ] || printf 'branch %s\n' "$1" >>"$FAKE_GIT_LOG"
    printf '%s' "${FAKE_MAIN_BRANCH-main}"
}

# Stand-in for `git -C <root> status --porcelain` being non-empty.
_pmv_git_is_dirty() {
    [ -z "${FAKE_GIT_LOG-}" ] || printf 'status %s\n' "$1" >>"$FAKE_GIT_LOG"
    [ "${FAKE_MAIN_DIRTY:-0}" = "1" ]
}

# Stand-in for `git -C <root> fetch <remote> <base> && git -C <root> rebase <remote>/<base>`.
_pmv_git_sync() {
    [ -z "${FAKE_GIT_LOG-}" ] || printf 'sync %s %s %s\n' "$1" "$2" "$3" >>"$FAKE_GIT_LOG"
    return "${FAKE_SYNC_RC:-0}"
}

# Stand-in for `git -C <root> rebase --abort` (best-effort restore, never a fix).
_pmv_git_rebase_abort() {
    [ -z "${FAKE_GIT_LOG-}" ] || printf 'rebase-abort %s\n' "$1" >>"$FAKE_GIT_LOG"
    return 0
}

# ============================================================
# JSON helpers
# ============================================================

# First string value of a flat key anywhere in the document, read from stdin.
# `herdr tab create` and `herdr workspace create` both answer with a pane but
# nest it under different parents (`.result.pane` vs `.result.root_pane`), and
# the CLI is free to add another — keying on the leaf name rather than the path
# keeps this working across both shapes (same helper as _pmt_json_first in
# shell-common/tools/custom/pr_merge_train_cron.sh). The key travels as a jq
# *argument*, never as interpolated program text.
pmv_json_first() {
    jq -r --arg k "$1" \
        '[.. | objects | .[$k]? // empty] | map(select(type == "string")) | first // empty' \
        2>/dev/null || return 0
}

# `.error.code` off a failed herdr answer on stdin, or empty. Fixed filter, so
# nothing is ever interpolated into the jq program text.
pmv_error_code() {
    jq -r '.error.code // empty' 2>/dev/null || return 0
}

# ============================================================
# F-1 — the watched-repos.json gate
# ============================================================

# pmv_gate <watched_file> <owner/repo>
#
# Echo the repo's `verify_skill` and return 0 when the repo is registered.
#   1 — file missing/unreadable, or the repo is not registered. The caller
#       must then do NOTHING AT ALL: an unwatched repo has to behave exactly
#       as it did before #1511, warning included (there is none).
#   2 — the file exists but is not parseable JSON. That is a broken SSOT, not
#       an opt-out, so the caller warns once and still skips.
pmv_gate() {
    local _file="$1" _repo="$2" _val _rc

    # No jq → the registry cannot be read, so the feature is unavailable. That
    # is rc 1 (skip silently), never rc 2: an absent tool is not a broken SSOT,
    # and gh:pr-merge's contract is that an unwatched repo prints nothing.
    _pmv_jq_present || return 1
    [ -r "$_file" ] || return 1

    _val=$(jq -r --arg r "$_repo" '.[$r].verify_skill // empty' "$_file" 2>/dev/null)
    _rc=$?
    [ "$_rc" -eq 0 ] || return 2
    [ -n "$_val" ] || return 1

    printf '%s' "$_val"
}

# pmv_verify_skill_allowed <verify_skill>
#
# The registry value is typed into a session started with
# `--dangerously-skip-permissions`, so it is an *input to a prompt*, not a
# label. Anything outside this allowlist is refused before a single herdr
# mutation runs — a registry someone else can edit must not be able to steer
# an unattended agent. Keep this list in sync with
# `references/watched-repos-schema.md`.
pmv_verify_skill_allowed() {
    case "$1" in
    devx:pr-verify-merged | devx:pr-verify-live) return 0 ;;
    esac
    return 1
}

# pmv_main_root <watched_file> <owner/repo> <git_common_dir>
#
# The checkout to rebase — the ORIGINAL clone, never a linked worktree.
# `main_checkout` from the registry when set (a leading `~` is expanded);
# otherwise the parent of git's common dir, because
# `git rev-parse --path-format=absolute --git-common-dir` answers
# `<main-checkout>/.git` even when run from inside a linked worktree.
pmv_main_root() {
    local _file="$1" _repo="$2" _common="$3" _v

    _v=$(jq -r --arg r "$_repo" '.[$r].main_checkout // empty' "$_file" 2>/dev/null) || _v=""
    if [ -n "$_v" ]; then
        case "$_v" in
        '~'/*) _v="${HOME}/${_v#'~'/}" ;;
        esac
        printf '%s' "$_v"
        return 0
    fi

    printf '%s' "${_common%/.git}"
}

# pmv_validate_main_root <main_root>. rc 0 = usable.
#
# An empty or bogus MAIN_ROOT is the quietly dangerous case: `git -C "" status`
# fails, which the dirty check reads as "clean", and the later
# `git -C "$MAIN_ROOT" rebase --abort` then fires wherever the shell happens to
# stand. So the path must resolve to a git worktree root before ANY step runs,
# the impl-tab close included.
pmv_validate_main_root() {
    local _root="$1" _top

    if [ -n "$_root" ]; then
        _top=$(_pmv_git_toplevel "$_root")
    else
        _top=""
    fi

    if [ -z "$_root" ] || [ -z "$_top" ] ||
        [ "$(pmv_physical_path "$_top")" != "$(pmv_physical_path "$_root")" ]; then
        printf '[WARN] gh:pr-post-merge-verify: main checkout "%s" is not a git worktree root — verification skipped.\n' "$_root"
        return 1
    fi

    return 0
}

# ============================================================
# Naming
# ============================================================

# The herdr agent-name SSOT — the very file dispatch.sh.md sources, not a
# copy of it (#1530). Mirroring the normalizer here would reintroduce exactly
# the duplication that let three call sites drift into the same broken slug.
# shellcheck source=/dev/null
. "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/herdr_agent_name.sh"

# pmv_agent_name <host> <owner/repo> <pr>  ->  mv-<repo>-pr-<N>
#
# dispatch.sh.md calls `herdr_agent_name` inline; this wrapper exists so the
# naming tests can vary <host> and prove it does not reach the name. It is
# deliberately not in the name: a host-qualified name does not fit herdr's
# 32-character budget, which is how the pre-#1530
# `pmv-<host>-<owner>-<repo>-<N>` reached 37 characters and was refused on
# every merge. The trade-off is documented at the helper. Returns non-zero,
# like the helper, when no valid name can be built.
pmv_agent_name() {
    herdr_agent_name mv "$2" "pr-$3"
}

# pmv_verify_prompt <verify_skill> <pr>  ->  `/devx-pr-verify-merged <N>`
# The registry stores the skill id (`devx:pr-verify-merged`); a pane is typed
# the dash form, which is what a Claude session accepts as a slash command.
pmv_verify_prompt() {
    printf '/%s %s' "$(printf '%s' "$1" | tr ':' '-')" "$2"
}

# ============================================================
# F-2 — find and close the implementation tab
# ============================================================

# Resolve symlinks so both sides of a prefix comparison are physical. Falls
# back to the input when the path does not exist (already-removed worktree).
pmv_physical_path() {
    (cd -P "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"
}

# pmv_worktree_for_branch <branch>  ->  local worktree path, or empty.
pmv_worktree_for_branch() {
    _pmv_git_worktree_list | awk -v b="refs/heads/$1" '
        /^worktree / { p = substr($0, 10) }
        $0 == ("branch " b) { print p; exit }
    '
}

# pmv_tab_for_cwd <physical_path>  ->  tab_id of a live agent sitting there.
#   0 — matched, tab_id on stdout
#   1 — herdr could not be asked (missing/empty answer). Unknown, NOT "nothing
#       running" — the mistake issue_watcher_cron.sh's _iw_live_agents calls out.
#   3 — herdr answered and no agent is on that path.
pmv_tab_for_cwd() {
    local _path="$1" _json _tab

    # An empty path would make every startswith() true and close a random tab.
    [ -n "$_path" ] || return 3

    _json=$(_pmv_herdr agent list) || return 1
    [ -n "$_json" ] || return 1

    # Both columns, because they answer at different moments: `cwd` is where the
    # pane was opened and `foreground_cwd` is where its shell stands now. The
    # match is the path itself or a directory BELOW it — a bare startswith()
    # would let `/work/repo-11` match the prefix `/work/repo-1` and close a
    # sibling checkout's tab (PR #1518 review). Subdirectories still count: an
    # agent inside the worktree is still that session (PR #1456 review).
    _tab=$(printf '%s' "$_json" | jq -r --arg p "$_path" '
        def under($b): . == $b or startswith($b + "/");
        if (.result.agents | type) == "array" then
          [ .result.agents[]?
            | select(((.cwd // "") | under($p)) or ((.foreground_cwd // "") | under($p)))
            | .tab_id // empty ]
          | map(select(type == "string" and . != "")) | first // empty
        else error("no agent list") end
    ' 2>/dev/null) || return 1

    [ -n "$_tab" ] || return 3
    printf '%s' "$_tab"
}

# ============================================================
# F-3 — the main checkout
# ============================================================

# pmv_sync_main <main_root> <remote> <base_branch>. rc 0 = the checkout is on a
# clean, rebased base branch. Anything else warns and returns 1, and the caller
# must STOP: verifying stale code proves nothing, so there is no point opening
# a session for it.
#
# `<remote>` is the skill's `[remote]` positional (default `origin`) and
# `<base_branch>` is the merged PR's `baseRefName`; neither is hardcoded,
# because a watched repo may default to `master`/`develop` or be reached
# through `upstream`. An empty `<base_branch>` falls back to the checkout's own
# current branch — never to a literal `main`, and never on a detached HEAD.
pmv_sync_main() {
    local _root="$1" _remote="${2:-origin}" _base="${3-}" _cur

    if _pmv_git_is_dirty "$_root"; then
        printf '[WARN] gh:pr-post-merge-verify: %s has uncommitted changes — not rebasing, verification skipped.\n' "$_root"
        return 1
    fi

    # Rebasing without checking what HEAD is on would rewrite the history of
    # whatever feature branch the main checkout happens to be parked on.
    _cur=$(_pmv_git_current_branch "$_root")
    [ "$_cur" != "HEAD" ] || _cur=""
    [ -n "$_base" ] || _base="$_cur"
    if [ -z "$_base" ] || [ "$_cur" != "$_base" ]; then
        printf '[WARN] gh:pr-post-merge-verify: %s is on %s, not the base branch %s — not rebasing, verification skipped.\n' \
            "$_root" "${_cur:-(detached HEAD)}" "${_base:-(unknown)}"
        return 1
    fi

    if ! _pmv_git_sync "$_root" "$_remote" "$_base"; then
        # Restore, never resolve: an abandoned conflicted rebase would leave the
        # user's main checkout unusable, but picking sides is the human's call.
        _pmv_git_rebase_abort "$_root"
        printf '[WARN] gh:pr-post-merge-verify: fetch/rebase failed in %s (rebase aborted, conflict not resolved) — verification skipped.\n' "$_root"
        return 1
    fi

    return 0
}

# ============================================================
# F-4 / F-5 — open the verification session
# ============================================================

# pmv_workspace_for_root <main_root>  ->  herdr workspace id, or empty.
# `herdr worktree list --json` answers `.result.source.source_workspace_id`
# for the checkout it is asked about; the linked-worktree entries carry
# `open_workspace_id` instead. Try the explicit paths, then fall back to the
# flat-key scan so a CLI that renests the field still resolves.
pmv_workspace_for_root() {
    local _root="$1" _json _ws

    _json=$(_pmv_herdr worktree list --cwd "$_root" --json) || return 0

    _ws=$(printf '%s' "$_json" | jq -r --arg p "$_root" '
        [ (.result.source.source_workspace_id? // empty),
          (.result.worktrees[]? | select(.path == $p) | .open_workspace_id? // empty) ]
        | map(select(type == "string" and . != "")) | first // empty
    ' 2>/dev/null) || _ws=""

    [ -n "$_ws" ] || _ws=$(printf '%s' "$_json" | pmv_json_first source_workspace_id)
    printf '%s' "$_ws"
}

# pmv_tab_create <workspace> <cwd> <label>  ->  "<tab_id> <pane_id>", rc 1 on failure.
pmv_tab_create() {
    local _ws="$1" _cwd="$2" _label="$3" _json _tab _pane

    # Spelled out twice rather than accumulated with `set --`: the dispatch
    # block this mirrors is pasted at the top level of the caller's shell, where
    # `set --` would destroy the caller's own "$1", "$2", … (PR #1518 review).
    # POSIX sh has no arrays, so an if/else over the full command line is the
    # only form that is both safe and portable.
    if [ -n "${CLAUDE_CONFIG_DIR-}" ]; then
        _json=$(_pmv_herdr tab create --workspace "$_ws" --cwd "$_cwd" \
            --label "$_label" --no-focus \
            --env "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR}") || return 1
    else
        _json=$(_pmv_herdr tab create --workspace "$_ws" --cwd "$_cwd" \
            --label "$_label" --no-focus) || return 1
    fi
    _pane=$(printf '%s' "$_json" | pmv_json_first pane_id)
    [ -n "$_pane" ] || return 1
    _tab=$(printf '%s' "$_json" | pmv_json_first tab_id)

    printf '%s %s' "${_tab:--}" "$_pane"
}

# pmv_agent_start <agent> <pane>. Echoes herdr's JSON so the caller can read
# `.error.code`; returns herdr's exit status.
#
# `--dangerously-skip-permissions` is required, not a convenience: the pane is
# opened for an unattended verification turn, so one permission prompt would
# park it forever instead of failing it (same rationale as #1393).
pmv_agent_start() {
    _pmv_herdr agent start "$1" --kind claude --pane "$2" -- --dangerously-skip-permissions
}

# Mirrors dispatch.sh.md's `pmv_settle`: one settle wait for both of this
# repo's herdr races — `tab create` -> `agent start` (the pane's shell is not
# interactive yet, `agent_pane_busy`) and `agent start` -> `agent prompt` (a
# fresh claude TUI reports idle while its key-input loop is still unattached,
# #1560). 13s is the repo standard; the twins are _IW_SETTLE_SECONDS /
# _IW_START_RETRY_SLEEP and _PMT_SETTLE_SECONDS / _PMT_START_RETRY_SLEEP.
# `0` disables it, the same escape _IW_IDLE_POLL_SLEEP has.
pmv_settle() {
    local _s="${PMV_SETTLE_SECONDS:-13}"
    [ "$_s" = "0" ] || _pmv_sleep "$_s"
}

# pmv_agent_prompt <agent> <text>. Same contract as pmv_agent_start.
pmv_agent_prompt() {
    _pmv_herdr agent prompt "$1" "$2" \
        --wait --until idle --timeout "${PMV_PROMPT_TIMEOUT_MS:-900000}"
}

# ============================================================
# Orchestrator
# ============================================================

# gh_pr_post_merge_verify <pr> <owner/repo> <host> <main_root> <head_branch> \
#                          <watched_file> [remote] [base_branch]
#
# `[remote]` is the skill's `[remote]` positional (default `origin`) and
# `[base_branch]` is the merged PR's `baseRefName`; both are threaded through
# instead of hardcoding `origin`/`main` (PR #1518 review).
#
# Always returns 0: every failure mode is a soft-fail (F-6), because the caller
# — gh:pr-merge — has already merged and already printed its report.
gh_pr_post_merge_verify() {
    local _pr="$1" _repo="$2" _host="$3" _main="$4" _branch="$5" _file="$6"
    local _remote="${7:-origin}" _base="${8-}"
    local _skill _rc _wt _tab _tabrc _ws _pane _agent _newtab _out _code

    _skill=$(pmv_gate "$_file" "$_repo")
    _rc=$?
    if [ "$_rc" -eq 2 ]; then
        printf '[WARN] gh:pr-post-merge-verify: %s is not valid JSON — post-merge verification skipped.\n' "$_file"
        return 0
    fi
    # Unregistered repo or no registry at all: behave exactly as before #1511.
    [ "$_rc" -eq 0 ] || return 0

    # herdr absent → the whole feature is a no-op, silently.
    _pmv_herdr_present || return 0

    # The registry value ends up in an unattended, skip-permissions agent's
    # prompt, so it is allowlisted after the herdr probe (a machine that cannot
    # run the feature stays silent) but before anything is touched.
    if ! pmv_verify_skill_allowed "$_skill"; then
        printf '[WARN] gh:pr-post-merge-verify: verify_skill "%s" for %s is not one of devx:pr-verify-merged, devx:pr-verify-live — verification skipped.\n' \
            "$_skill" "$_repo"
        return 0
    fi

    # A main checkout that is not a git worktree root makes every later git
    # probe fail open, so it is checked before the first side effect.
    pmv_validate_main_root "$_main" || return 0

    # --- 1/2. close the implementation tab (best-effort, never blocking) ---
    _wt=$(pmv_worktree_for_branch "$_branch")
    if [ -z "$_wt" ]; then
        printf '[INFO] gh:pr-post-merge-verify: no local worktree for %s — nothing to close.\n' "$_branch"
    else
        _tab=$(pmv_tab_for_cwd "$(pmv_physical_path "$_wt")")
        _tabrc=$?
        if [ "$_tabrc" -eq 0 ]; then
            if _pmv_herdr tab close "$_tab" >/dev/null 2>&1; then
                printf '[INFO] gh:pr-post-merge-verify: closed implementation tab %s (%s).\n' "$_tab" "$_wt"
            else
                printf '[WARN] gh:pr-post-merge-verify: herdr tab close %s failed — continuing.\n' "$_tab"
            fi
        elif [ "$_tabrc" -eq 1 ]; then
            # rc 1 is "herdr could not be asked", NOT "nothing is running there".
            # Reporting it as "nothing to close" is exactly the conflation
            # rationale.md forbids.
            printf '[WARN] gh:pr-post-merge-verify: herdr could not be queried — implementation tab on %s left alone.\n' "$_wt"
        else
            printf '[INFO] gh:pr-post-merge-verify: no live herdr tab on %s — nothing to close.\n' "$_wt"
        fi
    fi

    # --- 3. main checkout must be clean, on the base branch, and rebased ---
    pmv_sync_main "$_main" "$_remote" "$_base" || return 0

    # --- 4. the verification tab ---
    _ws=$(pmv_workspace_for_root "$_main")
    if [ -z "$_ws" ]; then
        printf '[WARN] gh:pr-post-merge-verify: no herdr workspace for %s — verification tab not created.\n' "$_main"
        return 0
    fi

    if ! _out=$(pmv_tab_create "$_ws" "$_main" "pr-$_pr"); then
        printf '[WARN] gh:pr-post-merge-verify: herdr tab create failed for label pr-%s — verification skipped.\n' "$_pr"
        return 0
    fi
    _newtab="${_out%% *}"
    _pane="${_out##* }"

    # --- 5. the agent ---
    # Mirrors dispatch.sh.md: a repo that cannot produce a valid herdr name
    # skips the verification rather than starting a session under a name no
    # later run can look up (#1530).
    if ! _agent=$(pmv_agent_name "$_host" "$_repo" "$_pr"); then
        printf '[WARN] gh:pr-post-merge-verify: cannot derive an agent name for %s — verification skipped.\n' "$_repo"
        return 0
    fi
    # The pane is seconds old and its shell may not be interactive yet. Waited
    # for here rather than right after the tab create so a repo whose name
    # cannot be derived skips out without paying 13s first.
    pmv_settle
    if ! _out=$(pmv_agent_start "$_agent" "$_pane"); then
        # Race backstop, same as _pmt_launch_fresh: the name can be claimed
        # between the probe and the start, and its holder is by definition a
        # usable agent — prompt it rather than failing the dispatch.
        _code=$(printf '%s' "$_out" | pmv_error_code)
        if [ "$_code" != "agent_name_taken" ]; then
            # The tab from step 4 is agent-less at this point — nothing lost
            # by closing it. Only when its id is known (#1554): guessing which
            # tab to close from a failed read would risk closing someone
            # else's. `pmv_tab_create` always returns a non-empty first
            # field, so the only "unknown" case is its own "-" placeholder.
            if [ "$_newtab" != "-" ]; then
                if _pmv_herdr tab close "$_newtab" >/dev/null 2>&1; then
                    printf '[INFO] gh:pr-post-merge-verify: closed the empty verification tab %s.\n' "$_newtab"
                else
                    printf '[WARN] gh:pr-post-merge-verify: could not close tab %s — close it by hand.\n' "$_newtab"
                fi
            fi
            printf '[WARN] gh:pr-post-merge-verify: herdr agent start %s failed on pane %s (%s) — verification skipped.\n' \
                "$_agent" "$_pane" "${_code:-unknown}"
            return 0
        fi
        # This session was already registered, so it has been up for a while
        # and takes the prompt at once — no need to pay the settle wait below.
        printf '[WARN] gh:pr-post-merge-verify: agent %s already registered — prompting the existing session.\n' "$_agent"
    else
        # A just-started claude is idle but not yet listening (#1571) — this
        # settle wait is what lets it start listening before the prompt lands.
        pmv_settle
    fi

    # --- 6. hand the verification over ---
    if ! _out=$(pmv_agent_prompt "$_agent" "$(pmv_verify_prompt "$_skill" "$_pr")"); then
        _code=$(printf '%s' "$_out" | pmv_error_code)
        printf '[WARN] gh:pr-post-merge-verify: herdr agent prompt %s failed (%s) — attach and run it by hand.\n' \
            "$_agent" "${_code:-unknown}"
    fi

    # --- 7. report ---
    printf 'post-merge verification dispatched\n'
    printf '  tab:    %s (label pr-%s)\n' "$_newtab" "$_pr"
    printf '  agent:  %s\n' "$_agent"
    printf '  verify: %s\n' "$(pmv_verify_prompt "$_skill" "$_pr")"
    printf '  attach: herdr agent attach %s\n' "$_agent"
    return 0
}
