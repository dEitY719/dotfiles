#!/usr/bin/env bash
# git-sync.sh — origin/main + upstream/main 을 로컬 main 에 합치고 origin/main push
#
# `git sync` alias 가 호출하는 스크립트 (dotfiles #1721 로 전역 이식).
# 원본은 agent-toolbox 의 저장소-로컬 `scripts/git-sync.sh` (agent-toolbox
# #1943/#2374); 동작은 그대로 두고 리포 로컬 경로 의존만 걷어냈다.
# 구 oneliner alias (fetch && merge && pull && push) 가 충돌 시 && 체인이
# 끊긴 채 멈추고 "이제 뭘 해야 하는지" 안내가 없던 문제를 해결한다.
#
# 5단계 오케스트레이션:
#   1. 사전 가드: upstream 리모트 존재 + 현재 브랜치 = main
#   2. git fetch upstream main + git fetch origin main
#   3. git merge --no-edit origin/main     ← 충돌 지점 A
#   4. git merge --no-edit upstream/main   ← 충돌 지점 B
#   5. git push origin main                ← 거부 지점 C
#
# origin 을 먼저 병합하는 이유: 여러 명이 비슷한 시각에 git sync 를 돌리면
#   upstream 을 먼저 병합하는 순서에서는 모두 "자기가 fetch 한 시점의 origin" 위에서
#   같은 upstream 진행분을 각자 병합해, 동일한 반영이 서로 다른 merge commit 으로
#   origin 에 중복 기록된다. origin 을 먼저 흡수하면 남이 이미 올린 upstream 반영을
#   그대로 물려받아 뒤이은 upstream merge 가 no-op 으로 끝나고, 충돌 해결도 항상
#   최신 origin 기준으로 이뤄진다. (초 단위 완전 동시 실행의 경합은 여전히 남으며,
#   그때는 5단계 push 거부 → 재실행 안내가 받아낸다.)
#
# 멱등 재개: 시작 시 .git/MERGE_HEAD 를 감지해 이전 충돌 해결을 이어간다.
#   세 실패 지점(A/B/C) 모두 "멈추고 안내만" — 자동 abort/재시도/재pull 하지 않는다.
#   merge --abort 를 하지 않는 것이 멱등 재개의 핵심(해결분 보존).
#
# 사용:
#   git sync                       # 전역 alias (git/.gitconfig SSOT)
#   bash "${DOTFILES_ROOT:-$HOME/dotfiles}/git/scripts/git-sync.sh"
#   git sync -h                    # 도움말
set -euo pipefail

BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'
[[ -t 1 ]] || {
    BOLD=""
    DIM=""
    RESET=""
}
log_start() { printf '%s▶ %s%s\n' "$BOLD" "$1" "$RESET"; }
log_step() { printf '%s  $ %s%s\n' "$DIM" "$1" "$RESET"; }
log_info() { printf '  %s\n' "$1"; }
log_done() { printf '%s✓ %s%s\n' "$BOLD" "$1" "$RESET"; }
log_fail() { printf '%s✗ %s%s\n' "$BOLD" "$1" "$RESET" >&2; }

usage() {
    cat <<'EOF'
git-sync.sh — origin/main + upstream/main 동기화 후 origin/main push

  git sync       origin/main·upstream/main 흡수 후 origin/main push
  git sync -h    이 도움말

`git sync --help` 는 git 이 alias 정의 출력으로 가로채므로 이 도움말이
나오지 않습니다 — `-h` 또는 `git sync help` 를 쓰세요.

충돌 시 멈추고 안내만 합니다. 충돌 파일을 해결하고 `git add` 한 뒤
`git sync` 를 재실행하면 남은 단계를 이어서 진행합니다(멱등 재개).

환경 변수(테스트/특수 환경용):
  GIT_SYNC_INTERNAL_REMOTE  기본 origin
  GIT_SYNC_EXTERNAL_REMOTE  기본 upstream
  GIT_SYNC_BRANCH           기본 main
EOF
}

# 접두사가 GIT_SYNC_* 인 이유: SYNC_* 는 shell-common/tools/integrations/sync_to_deploy.sh
# 가 다른 의미로 이미 쓰고 있어(같은 이름·같은 기본값) 한쪽 export 가 다른 쪽을 조용히 바꾼다.
INTERNAL_REMOTE="${GIT_SYNC_INTERNAL_REMOTE:-origin}"
EXTERNAL_REMOTE="${GIT_SYNC_EXTERNAL_REMOTE:-upstream}"
BRANCH="${GIT_SYNC_BRANCH:-main}"

case "${1-}" in
"") ;;
-h | --help | help)
    usage
    exit 0
    ;;
*)
    log_fail "알 수 없는 인자: $1 (지원: -h)"
    exit 1
    ;;
esac

EXT_REF="${EXTERNAL_REMOTE}/${BRANCH}"
INT_REF="${INTERNAL_REMOTE}/${BRANCH}"

# 미해결 충돌 판정 — (1) git add 전 미병합 경로가 남았거나,
# (2) git add 됐더라도 스테이징 내용에 충돌 마커가 잔존하면 true.
# (`git diff --check` 는 마커 발견 시 non-zero 지만 whitespace 오류 등 다른
#  사유와 구분하려 출력 문자열의 'conflict marker' 만 신뢰한다.)
has_unresolved_conflicts() {
    [[ -n "$(git ls-files --unmerged)" ]] && return 0
    local check
    check=$(git diff --cached --check 2>/dev/null || true)
    [[ "$check" == *"conflict marker"* ]] && return 0
    return 1
}

# 충돌 파일 목록을 들여쓰기해 출력
print_conflicted_files() {
    git diff --name-only --diff-filter=U | sed 's/^/    - /'
}

# 3/4단계 공용 merge — 충돌 시 abort 하지 않고 안내 후 중단(멱등 재개 핵심).
merge_or_guide() {
    local ref="$1" point="$2"
    log_step "git merge --no-edit $ref"
    if git merge --no-edit "$ref"; then
        return 0
    fi
    log_fail "merge conflict (지점 $point) — '$ref' 병합 중 충돌이 발생했습니다."
    log_info "충돌 파일:"
    print_conflicted_files
    log_info ""
    log_info "해결 후 재개:"
    log_info "  1) 충돌 마커(<<<<<<< / ======= / >>>>>>>)를 편집해 해결"
    log_info "  2) git add <해결한 파일>"
    log_info "  3) git sync 재실행 — 남은 단계를 이어서 진행합니다"
    log_info ""
    log_info "merge --abort 는 하지 않았습니다(해결분 보존 = 멱등 재개의 핵심)."
    exit 1
}

# ── 1. 사전 가드: upstream(외부 SSOT) 리모트 존재 ──
if ! git config --get "remote.${EXTERNAL_REMOTE}.url" >/dev/null; then
    log_fail "'$EXTERNAL_REMOTE' 리모트가 없습니다 — 이 프로젝트는 git sync 대상이 아닙니다."
    log_info "포크 워크플로라면 상위 리모트를 먼저 등록하세요:"
    log_info "  git remote add $EXTERNAL_REMOTE <상위 저장소 URL>"
    log_info "리모트 이름이 다르면 GIT_SYNC_EXTERNAL_REMOTE 로 지정할 수 있습니다."
    exit 1
fi

# ── 1b. 사전 가드: 현재 브랜치 = $BRANCH ──
# 피처 브랜치에서 실행하면 upstream/main·origin/main 이 피처 브랜치로 병합되고
# push $BRANCH 는 미갱신 로컬 $BRANCH 를 밀어 브랜치 오염·혼선을 부른다.
CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CUR_BRANCH" != "$BRANCH" ]]; then
    log_fail "현재 브랜치가 '$CUR_BRANCH' 입니다 — 동기화는 '$BRANCH' 브랜치에서 실행하세요."
    exit 1
fi

# ── 멱등 재개: 이전 충돌 해결을 이어간다 ──
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    log_start "이전 merge 재개 감지 (.git/MERGE_HEAD 존재)"
    if has_unresolved_conflicts; then
        log_fail "아직 해결되지 않은 충돌이 남아 있습니다."
        print_conflicted_files
        log_info "충돌 마커를 해결하고 git add 한 뒤 git sync 를 다시 실행하세요."
        exit 1
    fi
    log_step "git commit --no-edit  (해결된 merge 커밋)"
    git commit --no-edit >/dev/null || {
        log_fail "merge 커밋 실패."
        exit 1
    }
    log_done "이전 merge 해결분 커밋 완료 — 남은 동기화 단계를 이어서 진행합니다."
else
    # 정상 새 실행 — 진행 중 merge 가 아닌 순수 미커밋 변경은 중단
    if ! git diff-index --quiet HEAD --; then
        log_fail "커밋되지 않은 변경 사항이 있습니다 — 먼저 커밋하거나 stash 한 뒤 실행하세요."
        exit 1
    fi
fi

log_start "git sync — ${INT_REF} + ${EXT_REF} → 로컬 ${BRANCH}, 이후 ${INTERNAL_REMOTE}/${BRANCH} push"

# ── 2. Fetch (stale ref 로 merge 하면 고유분을 놓치므로 실패 시 즉시 중단) ──
# fetch 순서는 merge 순서와 일부러 반대다 — 먼저 병합할 origin 을 마지막에 받아
# 두 명령 사이 창을 최소화한다(그만큼 남의 최신 push 를 놓칠 확률이 낮아진다).
for remote in "$EXTERNAL_REMOTE" "$INTERNAL_REMOTE"; do
    log_step "git fetch $remote $BRANCH"
    git fetch "$remote" "$BRANCH" || {
        log_fail "$remote fetch 실패."
        exit 1
    }
done

# ── 3. origin/main merge (지점 A) ──
merge_or_guide "$INT_REF" "A"
# ── 4. upstream/main merge (지점 B) ──
merge_or_guide "$EXT_REF" "B"

# ── 5. origin/main push (지점 C) ──
log_step "git push $INTERNAL_REMOTE $BRANCH"
if git push "$INTERNAL_REMOTE" "$BRANCH"; then
    log_done "git sync 완료 — 로컬 ${BRANCH} 동기화 + ${INTERNAL_REMOTE}/${BRANCH} push 성공."
else
    log_fail "push 거부 (지점 C) — ${INTERNAL_REMOTE}/${BRANCH} push 가 거부되었습니다."
    log_info "원인 1) ${INTERNAL_REMOTE}/${BRANCH} 이 그새 앞서감(non-fast-forward) → git sync 재실행 시"
    log_info "        최신분을 흡수한 뒤 재푸시합니다."
    log_info "원인 2) 보호 브랜치 ruleset — ${INTERNAL_REMOTE}/${BRANCH} 직접 push 는 bypass 권한자만 가능합니다."
    log_info "자동 re-pull 은 하지 않습니다 — 재실행으로 명시적으로 진행하세요."
    exit 1
fi
