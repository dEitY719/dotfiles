#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_reply_board_sync.sh
# Source-of-truth mirror for the Step 6.5 board-sync (`In review` 복귀)
# snippet documented in claude/skills/gh-pr-reply/SKILL.md.
#
# The skill itself runs inside a Claude session, but the gate is a
# small POSIX block that can be tested in isolation: given the number
# of fixes pushed in Step 6 and a stub helper, does Step 6.5 call the
# helper (push happened) or no-op silently (no push)?
#
# Keep this file in sync with SKILL.md Step 6.5. If the skill block
# changes, mirror the change here so the bats suite catches drift.

# Stand-in for _gh_project_status_sync. The real helper lives in
# shell-common/functions/gh_project_status.sh; tests inject behaviour
# via FAKE_HELPER_RC and FAKE_HELPER_LOG. Records its full argv so
# assertions can verify the `--only-from` guard arg shape.
_gh_project_status_sync() {
    : "${FAKE_HELPER_LOG:?FAKE_HELPER_LOG must be set by the test}"
    printf 'helper called args=%s\n' "$*" >>"$FAKE_HELPER_LOG"
    return "${FAKE_HELPER_RC-0}"
}

# Mirrors SKILL.md Step 6.5 verbatim. Any change here must propagate to
# the SKILL.md block, and vice versa. Always returns 0 (soft-fail policy).
gh_pr_reply_board_sync_step65() {
    local PR_NUMBER="$1" PUSHED_FIXES="$2"

    # Gate: only fire when at least one fix commit actually pushed.
    # When PUSHED_FIXES == 0 (all comments DECLINE / QUESTION) the card
    # lifecycle did not change, so there is nothing to recover.
    if [ "${PUSHED_FIXES:-0}" -gt 0 ]; then
        if _gh_project_status_sync pr "$PR_NUMBER" "In review" \
            --only-from "In progress,Changes requested"; then
            echo "[OK] PR 카드 \`In review\` 로 복귀됨"
        else
            echo "[WARN] 보드 sync 실패 — 카드 수동 이동 필요할 수 있음"
        fi
    fi

    return 0
}
