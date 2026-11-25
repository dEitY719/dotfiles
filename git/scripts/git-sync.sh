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
#   1. 사전 가드: upstream 리모트 존재 + 현재 브랜치 = main + upstream 에 main ref 존재
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
#
# 출력 헬퍼(log_*)는 ux_lib 를 쓰지 않는 의도적 예외다 (#1958):
#   - self-contained 이식 스크립트라 shell-common 없이도 돌아야 하고, ux_lib 를
#     쓰려면 같은 헬퍼의 plain fallback 을 또 둬야 해 코드만 늘어난다.
#   - tests/bats/git/test_git_sync.bats 가 log_step 줄('  $ git merge --no-edit <ref>')
#     을 sed 로 파싱해 merge 순서를 단언한다 — 형식이 테스트 계약이다.
#   - ux_info 는 아이콘을 앞에 붙여 log_info 의 들여쓴 재개 안내 목록 형태를 깨뜨린다.
#
# 출력 정책 (#2421, agent-toolbox#3843 와 같은 형태):
#   - TTY(그리고 NO_COLOR 미설정): 완료 ✓ 는 green, 실패 ✗ 는 red. fetch·merge·push 의
#     부가 출력(diffstat 등)은 dim 한 줄 요약만 화면에 남기고, 실패 시 전체 출력 + 로그 경로.
#   - non-TTY(파이프·CI·bats) 또는 NO_COLOR: 색 없이 종전처럼 전체 출력을 그대로 흘린다.
#   - 실행마다 전체 출력을 <git-dir>/git-sync-logs/<timestamp>-<pid>.log 에 남기고
#     최근 10개만 보존한다(git-dir 기준이라 worktree 별로 독립).
set -euo pipefail

BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[32m'
RED=$'\033[31m'
RESET=$'\033[0m'
QUIET=1 # 1 = 부가 출력을 dim 요약으로 접는다
if [[ ! -t 1 || -n "${NO_COLOR-}" ]]; then
    BOLD="" DIM="" GREEN="" RED="" RESET=""
    QUIET=0
fi

LOG_FILE=""
LOG_KEEP=10
# 실행 전체 출력을 로그 파일에 덧붙인다(색 없음). 로그가 없으면 no-op.
# 쓰기 실패(디스크 가득·권한)는 삼킨다 — 로그는 부가 기능이라 set -e 로 동기화를 끊으면 안 된다.
to_log() { [[ -z "$LOG_FILE" ]] || printf '%s\n' "$1" 2>/dev/null >>"$LOG_FILE" || true; }

log_start() {
    printf '%s▶ %s%s\n' "$BOLD" "$1" "$RESET"
    to_log "▶ $1"
}
log_step() {
    printf '%s  $ %s%s\n' "$DIM" "$1" "$RESET"
    to_log "  \$ $1"
}
log_info() {
    printf '  %s\n' "$1"
    to_log "  $1"
}
log_done() {
    printf '%s%s✓ %s%s\n' "$BOLD" "$GREEN" "$1" "$RESET"
    to_log "✓ $1"
}
log_fail() {
    printf '%s%s✗ %s%s\n' "$BOLD" "$RED" "$1" "$RESET" >&2
    to_log "✗ $1"
}

# <git 출력> [fd] — 명령 출력을 로그에 남기고 화면에는 TTY 면 dim 한 줄 요약,
# 아니면 종전처럼 전체를 fd(기본 1)로 흘린다.
# 요약 = 'N files changed' 줄이 있으면 그것, 없으면 마지막 비어있지 않은 줄.
show_output() {
    local out="$1" fd="${2:-1}" s
    [[ -n "$out" ]] || return 0
    to_log "$out"
    if ((QUIET == 0)); then
        printf '%s\n' "$out" >&"$fd"
        return 0
    fi
    s=$(printf '%s\n' "$out" | grep -E '[0-9]+ files? changed' | tail -n 1 || true)
    [[ -n "$s" ]] || s=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1 || true)
    s="${s#"${s%%[![:space:]]*}"}"
    if [[ -n "$s" ]]; then printf '%s    %s%s\n' "$DIM" "$s" "$RESET" >&"$fd"; fi
}

# <fd> <git 명령...> — fetch·push 용. 비-quiet 는 출력을 실시간으로 흘리며(훅·느린 네트워크 진행이
# 끝까지 안 보이면 안 된다) 로그에도 남기고, quiet 는 캡처해 성공이면 dim 요약, 실패면 전체를 보인다.
# 반환값 = git 종료 상태.
git_run() {
    local fd="$1" out
    shift
    if ((QUIET == 0)); then
        "$@" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" >&"$fd"
        # tee(로그 쓰기) 실패가 성공한 git 을 실패로 둔갑시키지 않도록 git 의 상태만 본다.
        return "${PIPESTATUS[0]}"
    fi
    if out=$("$@" 2>&1); then
        show_output "$out" "$fd"
        return 0
    fi
    show_full "$out" "$fd"
    return 1
}

# 실패 출력은 요약하지 않는다 — 원인 판단에 전체가 필요하다.
show_full() {
    printf '%s\n' "$1" >&"${2:-1}"
    to_log "$1"
}

# <git-dir>/git-sync-logs 에 이번 실행 로그를 만들고 최근 $LOG_KEEP 개만 남긴다.
# 저장소 밖이거나 쓸 수 없으면 로그 없이 진행한다(로그는 부가 기능).
init_log() {
    local gd dir logs n
    gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0
    dir="$gd/git-sync-logs"
    mkdir -p "$dir" 2>/dev/null || return 0
    LOG_FILE="$dir/$(date +%Y%m%d-%H%M%S)-$$.log"
    # 0600: fetch·push 출력에 리모트 URL 이 담기므로 다른 사용자가 읽지 못하게 한다.
    (umask 077 && : >"$LOG_FILE") 2>/dev/null || {
        LOG_FILE=""
        return 0
    }
    # 파일명이 타임스탬프로 시작하므로 glob 정렬 = 오래된 순. 방금 만든 로그가 있어 비지 않는다.
    logs=("$dir"/*.log)
    [[ -e "${logs[0]}" ]] || logs=() # nullglob 없이도 매칭 0건을 빈 배열로
    n=$((${#logs[@]} - LOG_KEEP))
    if ((n > 0)); then rm -f -- "${logs[@]:0:n}"; fi
}

# TTY 에서 실패로 끝나면 전체 로그 위치를 알린다(non-TTY 는 이미 전체 출력을 흘렸다).
on_exit() {
    local rc=$?
    if ((rc != 0 && QUIET == 1)) && [[ -n "$LOG_FILE" ]]; then
        printf '  전체 로그: %s\n' "$LOG_FILE" >&2
    fi
}
trap on_exit EXIT

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

init_log

EXT_REF="${EXTERNAL_REMOTE}/${BRANCH}"
INT_REF="${INTERNAL_REMOTE}/${BRANCH}"

# 미해결 충돌 판정 — (1) git add 전 미병합 경로가 남았거나,
# (2) git add 됐더라도 스테이징 내용에 충돌 마커가 잔존하면 true.
# (`git diff --check` 는 마커 발견 시 non-zero 지만 whitespace 오류 등 다른
#  사유와 구분하려 출력 문자열의 'conflict marker' 만 신뢰한다. 비영어 로케일에서
#  이 문구가 번역되면 탐지가 조용히 실패하므로 LC_ALL=C 로 고정한다.)
has_unresolved_conflicts() {
    [[ -n "$(git ls-files --unmerged)" ]] && return 0
    local check
    check=$(LC_ALL=C git diff --cached --check 2>/dev/null || true)
    [[ "$check" == *"conflict marker"* ]] && return 0
    return 1
}

# 충돌 파일 목록을 들여쓰기해 출력
print_conflicted_files() {
    local files
    files=$(git diff --name-only --diff-filter=U | sed 's/^/    - /')
    [[ -z "$files" ]] || show_full "$files"
}

# 3/4단계 공용 merge — 충돌 시 abort 하지 않고 안내 후 중단(멱등 재개 핵심).
#
# merge 실패가 곧 충돌은 아니다: 병합이 덮어쓸 untracked 파일이 있거나 로컬 변경이
# 걸리면 git 은 병합을 **시작조차 하지 않고** 거부한다. 이때는 미병합 경로가 없어
# "충돌 파일 편집 → git add" 안내가 통하지 않으므로, 실제 미병합 경로 유무로
# 두 경우를 갈라 안내한다.
merge_or_guide() {
    local ref="$1" point="$2" out
    log_step "git merge --no-edit $ref"
    if out=$(git merge --no-edit "$ref" 2>&1); then
        show_output "$out"
        return 0
    fi

    # 충돌 없이 병합은 끝났는데 훅(commit-msg/pre-commit)이 merge 커밋만 거부하면
    # .git/MERGE_HEAD 가 남는다. "시작도 못함" 안내대로 작업 트리를 비우면 병합
    # 결과를 잃으므로 먼저 이 경우를 가른다 (#2041).
    if [[ -z "$(git ls-files --unmerged)" ]] && git rev-parse -q --verify MERGE_HEAD >/dev/null; then
        show_full "$out"
        log_fail "merge 커밋 거부 (지점 $point) — '$ref' 병합은 충돌 없이 끝났지만 커밋이 훅에 거부됐습니다."
        log_info "해결 후 재개:"
        log_info "  1) 위 훅 메시지를 확인하고 원인을 해결"
        log_info "  2) git commit  (병합 결과가 스테이징돼 있습니다 — 작업 트리를 비우지 마세요)"
        log_info "  3) git sync 재실행"
        exit 1
    fi

    if [[ -z "$(git ls-files --unmerged)" ]]; then
        log_fail "merge 실패 (지점 $point) — '$ref' 병합이 시작되지도 못했습니다."
        log_info "git 출력:"
        show_full "$(printf '%s\n' "$out" | sed 's/^/    /')"
        log_info ""
        log_info "해결 후 재개:"
        log_info "  1) 위 메시지가 지목한 파일을 삭제·이동하거나 커밋해 작업 트리를 비우기"
        log_info "  2) git sync 재실행"
        exit 1
    fi

    show_full "$out"
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
# (`git config --get remote.<name>.url` 은 url 이 여러 개일 때 git 버전에 따라 exit 2 를
#  내 "없음"으로 오판한다 — `git remote get-url` 이 정확한 존재 확인 API.)
if ! git remote get-url "$EXTERNAL_REMOTE" >/dev/null 2>&1; then
    log_fail "'$EXTERNAL_REMOTE' 리모트가 없습니다 — 이 프로젝트는 git sync 대상이 아닙니다."
    log_info "포크 워크플로라면 상위 리모트를 먼저 등록하세요:"
    log_info "  git remote add $EXTERNAL_REMOTE <상위 저장소 URL>"
    log_info "리모트 이름이 다르면 GIT_SYNC_EXTERNAL_REMOTE 로 지정할 수 있습니다."
    exit 1
fi

# ── 1a. 사전 가드: 현재 브랜치 = $BRANCH ──
# 피처 브랜치에서 실행하면 upstream/main·origin/main 이 피처 브랜치로 병합되고
# push $BRANCH 는 미갱신 로컬 $BRANCH 를 밀어 브랜치 오염·혼선을 부른다.
CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CUR_BRANCH" != "$BRANCH" ]]; then
    log_fail "현재 브랜치가 '$CUR_BRANCH' 입니다 — 동기화는 '$BRANCH' 브랜치에서 실행하세요."
    exit 1
fi

# ── 1b. 사전 가드: external 리모트에 대상 브랜치 ref 가 있는가 (빈 repo 시드 대기, #2439) ──
# 이 가드는 "접근 가능한데 ref 없음"만 담당한다. ls-remote 자체가 실패하면(네트워크 불통 등)
# 그대로 통과시켜 아래 fetch 단계의 종전 실패 경로가 원인을 보고하게 한다.
# 충돌 재개(MERGE_HEAD) 중에는 건너뛴다 — 해결분 커밋이 upstream 상태에 막히면 안 된다.
if ! git rev-parse -q --verify MERGE_HEAD >/dev/null &&
    ext_refs=$(git ls-remote "$EXTERNAL_REMOTE" "refs/heads/$BRANCH" 2>/dev/null) && [[ -z "$ext_refs" ]]; then
    log_fail "'$EXTERNAL_REMOTE' 에 '$BRANCH' 브랜치가 없습니다 (빈 repo — 시드 전, 또는 브랜치명 불일치)."
    log_info "릴레이/외부 흐름이 $EXTERNAL_REMOTE 을 채울 때까지 기다리거나, '$BRANCH' 를 먼저 push 해 시드하세요."
    log_info "브랜치 이름이 다르면 GIT_SYNC_BRANCH 로 지정할 수 있습니다."
    log_info "이 상태에서는 git sync 를 계속 진행하지 않습니다 (external 없이 sync 하지 않는다)."
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
    # git 은 fetch·push 결과를 stderr 로 쓰므로 passthrough 도 fd 2 로 흘린다(종전과 같은 스트림).
    git_run 2 git fetch "$remote" "$BRANCH" || {
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
# pre-push 훅은 확인 프롬프트를 띄우거나 오래 돌 수 있다 — 캡처하면 프롬프트가 안 보인 채
# 멈추므로, 훅이 있으면 TTY 에서도 접지 않고 실시간으로 흘린다(로그에는 그대로 남는다).
quiet_saved=$QUIET
if [[ -x "$(git rev-parse --git-path hooks/pre-push)" ]]; then QUIET=0; fi
push_ok=1
git_run 2 git push "$INTERNAL_REMOTE" "$BRANCH" || push_ok=0
QUIET=$quiet_saved
if ((push_ok)); then
    log_done "git sync 완료 — 로컬 ${BRANCH} 동기화 + ${INTERNAL_REMOTE}/${BRANCH} push 성공."
else
    log_fail "push 거부 (지점 C) — ${INTERNAL_REMOTE}/${BRANCH} push 가 거부되었습니다."
    log_info "원인 1) ${INTERNAL_REMOTE}/${BRANCH} 이 그새 앞서감(non-fast-forward) → git sync 재실행 시"
    log_info "        최신분을 흡수한 뒤 재푸시합니다."
    log_info "원인 2) 보호 브랜치 ruleset — ${INTERNAL_REMOTE}/${BRANCH} 직접 push 는 bypass 권한자만 가능합니다."
    log_info "자동 re-pull 은 하지 않습니다 — 재실행으로 명시적으로 진행하세요."
    exit 1
fi
