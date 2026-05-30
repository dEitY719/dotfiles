# Step 5 — 보드 status `In review` 복귀 (soft-fail)

Applies **only when `mergeable == MERGEABLE`**.

`changes-requested` → fix push → 카드가 `In progress` 또는 `Changes requested` 에
머무는 흐름을 자동으로 끊어 리뷰어 큐 (`In review`) 로 되돌린다. 신규 PR
단계의 conflict (카드가 이미 `In review` / `Approved` / `Done`) 는
`--only-from` 가드가 막아 후퇴시키지 않는다. 자세한 lifecycle 근거는 issue #591.

```bash
if [ "$MERGEABLE" = "MERGEABLE" ]; then
    # Defense-in-depth (#724): the chained-`&&` form below silently no-ops
    # when the helper sources but never defines `_gh_project_status_sync`
    # (interactive-guard regression, partial source). Split into an
    # explicit guard so the failure prints a stderr warning instead of
    # collapsing into the `|| echo [WARN]` branch (which falsely suggests
    # a board sync was attempted).
    _HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
    if [ -r "$_HELPER" ]; then
        . "$_HELPER"
        if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
            printf '[gh-pr-resolve-conflict] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
                "$_HELPER" >&2
        elif _gh_project_status_sync pr "$PR_NUMBER" "In review" \
                --only-from "In progress,Changes requested"; then
            echo "[OK] PR 카드 \`In review\` 로 복귀됨"
        else
            echo "[WARN] 보드 sync 실패 — 카드 수동 이동 필요할 수 있음"
        fi
    fi
fi
```

`GH_PROJECT_STATUS_SYNC=0` opt-out 은 helper 자체가 흡수한다. projectV2
보드가 없는 레포는 helper 가 silent 0 반환. `--only-from` 의 missing column
은 helper 가 silently skip 하므로 `Changes requested` 컬럼 없는 보드와도
호환된다.
