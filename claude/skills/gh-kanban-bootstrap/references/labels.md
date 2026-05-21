# Label Bootstrap SSOT — F-9

The skill guarantees these 8 labels on the target repo. See the issue
body of #699 for the source rationale (which SSOT each label comes
from).

## SSOT Table

| name | color | description | source |
|------|-------|-------------|--------|
| `feat` | `a2eeef` | 신규 기능 또는 개선 | `.gh-issue-defaults.yml` (`feat: [feat]`) |
| `refactor` | `fbca04` | 동작 보존하며 구조 정리 | `.gh-issue-defaults.yml` |
| `test` | `bfd4f2` | 테스트 갭 / 추가 / 변경 | `.gh-issue-defaults.yml` |
| `ci` | `1d76db` | CI / GitHub Actions | `.gh-issue-defaults.yml` |
| `chore` | `cfd3d7` | 빌드·도구·deps·스타일 | `gh-pr` Conventional Commit 매핑 |
| `performance` | `ff9500` | 성능 / 자원 사용 | `gh-pr` 매핑 |
| `build` | `0e8a16` | 빌드 시스템 | `gh-pr` 매핑 |
| `skill` | `5319e7` | `claude/skills/**` 변경 | `gh-pr` scope label |

GitHub default labels (`bug`, `documentation`, `enhancement`,
`duplicate`, `good first issue`, `help wanted`, `invalid`, `question`,
`wontfix`) are NOT re-created — the SSOT mappings (`fix: [bug]`,
`docs: [documentation]`) use them as-is.

## Plain feed (for shell consumption)

```
feat|a2eeef|신규 기능 또는 개선
refactor|fbca04|동작 보존하며 구조 정리
test|bfd4f2|테스트 갭 / 추가 / 변경
ci|1d76db|CI / GitHub Actions
chore|cfd3d7|빌드·도구·deps·스타일
performance|ff9500|성능 / 자원 사용
build|0e8a16|빌드 시스템
skill|5319e7|claude/skills/** 변경
```

## Idempotent apply helper

```sh
_kanban_ensure_labels() {
    local _repo="$1" _ssot="$2" _force="${3:-0}" _existing _name _color _desc
    _existing=$(gh api "repos/$_repo/labels?per_page=100" \
        --jq '.[].name' 2>/dev/null) || return 1
    while IFS='|' read -r _name _color _desc; do
        [ -z "$_name" ] && continue
        if printf '%s\n' "$_existing" | grep -Fxq "$_name"; then
            if [ "$_force" = "1" ]; then
                gh api "repos/$_repo/labels/$_name" -X PATCH \
                    -f "new_name=$_name" -f "color=$_color" -f "description=$_desc" \
                    --jq '.name + " => synced"' \
                    || printf "label '%s' sync FAILED\n" "$_name" >&2
            else
                printf "label '%s' already exists — skip\n" "$_name"
            fi
            continue
        fi
        gh api "repos/$_repo/labels" -X POST \
            -f "name=$_name" -f "color=$_color" -f "description=$_desc" \
            --jq '.name + " => created"' \
            || printf "label '%s' create FAILED\n" "$_name" >&2
    done < "$_ssot"
}
```

## Color collision policy (OQ-4)

`feat=#a2eeef` intentionally matches the default `enhancement` color.
The two labels are kept separate (conventional-commit `feat` vs the
catch-all `enhancement`) — the SSOT mappings in `.gh-issue-defaults.yml`
do the semantic split. If a future repo requires visual distinction,
change `feat`'s color here and re-run with `--force-label-sync`.

## Force-sync example (F-10)

```sh
# Existing repo has feat=#ededed (gray default), refactor=#ededed, etc.
# Sync them to the SSOT colors above:
_kanban_ensure_labels "dEitY719/dotfiles" /tmp/labels.feed 1
# Without the trailing "1", existing colors are preserved (default).
```
