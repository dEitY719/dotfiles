#!/usr/bin/env bats
# tests/bats/skills/devx_session_close.bats
# Offline coverage for claude/skills/devx-session-close/lib/*.sh (issue #1327).
#
# Verification map:
#   F-3/C-1  check-repos.sh     — clean repo, 미커밋 변경, untracked,
#                                 원격 미반영 커밋, 진행중 merge, stash
#   NF-4     check-repos.sh     — internal 모드 + github.com origin 이면
#                                 원격 미반영 커밋을 NOTE 로 강등
#   F-5/C-3  check-artifacts.sh — 0 바이트 untracked 를 "버려진 예약 파일"
#                                 로 분류, 임시 파일, scratchpad 잔재
#   NF-6     both               — 대상 0개면 "검사 대상 없음" 을 명시
#   NF-1     both               — 실행 전후 저장소 상태가 바이트 단위로 동일
#   NF-2     grep               — 위험 명령이 스킬 어디에도 없다

load '../test_helper'

SKILL_DIR="${DOTFILES_ROOT}/claude/skills/devx-session-close"
CHECK_REPOS="${SKILL_DIR}/lib/check-repos.sh"
CHECK_ARTIFACTS="${SKILL_DIR}/lib/check-artifacts.sh"

setup() {
    setup_isolated_home
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/devx-session-close"
    CHECK_REPOS="${SKILL_DIR}/lib/check-repos.sh"
    CHECK_ARTIFACTS="${SKILL_DIR}/lib/check-artifacts.sh"

    WORK="$(mktemp -d)"
}

teardown() {
    if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
        rm -rf "$WORK"
    fi
    teardown_isolated_home
}

# Throwaway git repo with a bare "remote" so @{u} is real. Never a user repo.
# Sets REPO (working clone) and REMOTE (bare upstream).
make_repo() {
    local name="${1:-repo}"
    REMOTE="${WORK}/${name}.git"
    REPO="${WORK}/${name}"

    git init -q --bare "$REMOTE"
    git init -q -b main "$REPO"
    git -C "$REPO" config user.email "test@example.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" config commit.gpgsign false
    git -C "$REPO" remote add origin "$REMOTE"
    printf 'seed\n' >"${REPO}/README.md"
    git -C "$REPO" add -- README.md
    git -C "$REPO" commit -q -m "seed"
    git -C "$REPO" push -q -u origin main
}

# Isolated-HOME mode file. setup_isolated_home already pointed HOME at a
# scratch dir, so this never touches the real ~/.dotfiles-setup-mode.
set_mode() {
    printf '%s\n' "$1" >"${HOME}/.dotfiles-setup-mode"
}

# Adds one commit to REPO that origin doesn't have yet — the "@{u}..HEAD
# ahead" state every C-1/NF-4 unsynced-commit test needs before it varies
# the origin URL or mode.
commit_unsynced() {
    printf 'more\n' >>"${REPO}/README.md"
    git -C "$REPO" add -- README.md
    git -C "$REPO" commit -q -m "local only"
}

# ── C-1: clean baseline ───────────────────────────────────────────────

@test "C-1: a clean repo produces no BLOCKED lines" {
    make_repo clean

    run bash "$CHECK_REPOS" "$REPO"
    assert_success
    assert_output --partial 'VERDICT: OK'
    refute_output --partial 'BLOCKED:'
    assert_output --partial '미커밋 변경 없음'
    assert_output --partial 'untracked 파일 없음'
    assert_output --partial '원격에 모두 반영됨'
}

@test "C-1: a clean repo has no artifacts either" {
    make_repo clean

    run bash "$CHECK_ARTIFACTS" "$REPO"
    assert_success
    assert_output --partial 'VERDICT: OK'
    refute_output --partial 'NOTE:'
}

# ── C-1: BLOCKED-worthy signals ───────────────────────────────────────

@test "C-1: an uncommitted change is BLOCKED" {
    make_repo dirty
    printf 'edited\n' >>"${REPO}/README.md"

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure
    assert_output --partial 'BLOCKED:'
    assert_output --partial '미커밋 변경 1건'
    assert_output --partial 'VERDICT: BLOCKED'
}

@test "C-1: an untracked file is BLOCKED" {
    make_repo untracked
    printf 'new work\n' >"${REPO}/notes.md"

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure
    assert_output --partial 'untracked 파일 1건'
}

@test "C-1: an in-progress merge is BLOCKED" {
    make_repo merging
    : >"$(git -C "$REPO" rev-parse --absolute-git-dir)/MERGE_HEAD"

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure
    assert_output --partial '병합(merge) 진행중'
    assert_output --partial 'VERDICT: BLOCKED'
}

@test "C-1: an in-progress rebase and cherry-pick are BLOCKED too" {
    make_repo midflight
    gitdir="$(git -C "$REPO" rev-parse --absolute-git-dir)"
    mkdir -p "${gitdir}/rebase-merge"
    : >"${gitdir}/CHERRY_PICK_HEAD"

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure
    assert_output --partial '리베이스(rebase) 진행중'
    assert_output --partial 'cherry-pick 진행중'
}

@test "C-1: a commit not yet on the remote is BLOCKED" {
    make_repo ahead
    commit_unsynced

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure
    assert_output --partial '원격 미반영 커밋 1건'
    assert_output --partial 'BLOCKED:'
}

@test "C-1: a stash entry is a NOTE, never BLOCKED" {
    make_repo stashed
    printf 'wip\n' >>"${REPO}/README.md"
    git -C "$REPO" stash -q

    run bash "$CHECK_REPOS" "$REPO"
    assert_success
    assert_output --partial 'stash 1건'
    refute_output --partial 'BLOCKED:'
}

# ── NF-4: 사내PC 강등 ─────────────────────────────────────────────────

@test "NF-4: internal mode + github.com origin demotes an unsynced commit to NOTE" {
    make_repo internal
    commit_unsynced
    git -C "$REPO" remote set-url origin 'https://github.com/testorg/testrepo.git'
    set_mode internal

    run bash "$CHECK_REPOS" "$REPO"
    assert_success
    assert_output --partial 'MODE: internal'
    assert_output --partial 'NOTE:'
    assert_output --partial '원격 미반영 커밋 1건'
    assert_output --partial 'NF-4'
    refute_output --partial 'BLOCKED:'
    assert_output --partial 'VERDICT: OK'
}

@test "NF-4: the legacy numeric mode value 2 also means internal" {
    make_repo legacy
    commit_unsynced
    git -C "$REPO" remote set-url origin 'git@github.com:testorg/testrepo.git'
    set_mode 2

    run bash "$CHECK_REPOS" "$REPO"
    assert_success
    assert_output --partial 'MODE: internal'
    refute_output --partial 'BLOCKED:'
}

@test "NF-4: internal mode does NOT demote a GHES origin" {
    make_repo ghes
    commit_unsynced
    git -C "$REPO" remote set-url origin 'https://github.samsungds.net/testorg/testrepo.git'
    set_mode internal

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure
    assert_output --partial 'BLOCKED:'
    assert_output --partial '원격 미반영 커밋 1건'
}

@test "NF-4: external mode keeps a github.com unsynced commit BLOCKED" {
    make_repo external
    commit_unsynced
    git -C "$REPO" remote set-url origin 'https://github.com/testorg/testrepo.git'
    set_mode external

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure
    assert_output --partial 'BLOCKED:'
}

# ── upstream 없음 ─────────────────────────────────────────────────────

@test "C-1: a branch with no upstream warns instead of blocking" {
    make_repo noupstream
    git -C "$REPO" checkout -q -b feature/no-upstream

    run bash "$CHECK_REPOS" "$REPO"
    assert_success
    assert_output --partial 'upstream 없음'
    assert_output --partial 'WARN:'
    refute_output --partial 'BLOCKED:'
}

@test "C-1: a repo with no commits at all warns instead of blocking" {
    empty="${WORK}/empty"
    git init -q -b main "$empty"

    run bash "$CHECK_REPOS" "$empty"
    assert_success
    assert_output --partial 'WARN:'
    refute_output --partial 'BLOCKED:'
}

# ── NF-6: 빈 검사 조용히 통과 금지 ────────────────────────────────────

@test "NF-6: check-repos with zero targets says 검사 대상 없음" {
    run bash "$CHECK_REPOS"
    [ "$status" -eq 2 ]
    assert_output --partial '검사 대상 없음'
    refute_output --partial 'VERDICT: OK'
}

@test "NF-6: check-artifacts with zero targets says 검사 대상 없음" {
    run bash "$CHECK_ARTIFACTS"
    [ "$status" -eq 2 ]
    assert_output --partial '검사 대상 없음'
    refute_output --partial 'VERDICT: OK'
}

@test "NF-6: a non-git path is reported, not silently skipped" {
    mkdir -p "${WORK}/plain"

    run bash "$CHECK_REPOS" "${WORK}/plain"
    assert_output --partial 'git 저장소가 아니다'
}

@test "NF-6: check-repos with all-invalid repos reports NO-TARGET, not OK (PR #1331 review, codex)" {
    mkdir -p "${WORK}/plain1" "${WORK}/plain2"

    run bash "$CHECK_REPOS" "${WORK}/plain1" "${WORK}/plain2"
    [ "$status" -eq 2 ]
    assert_output --partial '유효하게 검사된 저장소가 0개'
    assert_output --partial 'VERDICT: NO-TARGET'
    refute_output --partial 'VERDICT: OK'
}

@test "NF-6: check-repos with one valid + one invalid repo still verdicts normally" {
    make_repo mixed
    mkdir -p "${WORK}/plain"

    run bash "$CHECK_REPOS" "$REPO" "${WORK}/plain"
    assert_success
    assert_output --partial 'git 저장소가 아니다'
    assert_output --partial 'VERDICT: OK'
}

@test "NF-6: check-artifacts with all-invalid repos warns but keeps VERDICT: OK (PR #1331 review, codex)" {
    mkdir -p "${WORK}/plain1"

    run bash "$CHECK_ARTIFACTS" "${WORK}/plain1"
    assert_success
    assert_output --partial '유효하게 검사된 것이 0개'
    assert_output --partial 'VERDICT: OK'
}

# ── C-3: 임시 산출물 ──────────────────────────────────────────────────

@test "C-3: a 0-byte untracked file is classified as 버려진 예약 파일" {
    make_repo reserved
    : >"${REPO}/draft.md"

    run bash "$CHECK_ARTIFACTS" "$REPO"
    assert_success
    assert_output --partial '버려진 예약 파일 1건'
    assert_output --partial '0 바이트 untracked'
    assert_output --partial 'draft.md'
    assert_output --partial 'VERDICT: NOTE'
}

@test "C-3: a subdirectory target still finds artifacts inside it (PR #1331 review, agy)" {
    make_repo subdir
    mkdir -p "${REPO}/sub"
    : >"${REPO}/sub/draft.md"

    # Pass the subdirectory, not the repo root. ls-files must resolve against
    # the toplevel (not $_cra_repo) or the reconstructed path points at a
    # nonexistent file at repo root and the real artifact is silently missed.
    run bash "$CHECK_ARTIFACTS" "${REPO}/sub"
    assert_success
    assert_output --partial '버려진 예약 파일 1건'
    assert_output --partial 'sub/draft.md'
}

@test "C-3: a non-empty untracked file is not a 버려진 예약 파일" {
    make_repo notreserved
    printf 'real content\n' >"${REPO}/draft.md"

    run bash "$CHECK_ARTIFACTS" "$REPO"
    assert_success
    assert_output --partial '버려진 예약 파일 없음'
}

@test "C-3: untracked editor/merge leftovers are listed as 임시 파일" {
    make_repo leftovers
    printf 'x\n' >"${REPO}/a.tmp"
    printf 'x\n' >"${REPO}/b.orig"
    printf 'x\n' >"${REPO}/c.md~"

    run bash "$CHECK_ARTIFACTS" "$REPO"
    assert_success
    assert_output --partial '미정리 임시 파일 3건'
    assert_output --partial 'a.tmp'
    assert_output --partial 'c.md~'
}

@test "C-3: scratchpad leftovers are counted as a NOTE" {
    scratch="${WORK}/scratchpad"
    mkdir -p "${scratch}/sub"
    printf 'x\n' >"${scratch}/one.txt"
    printf 'x\n' >"${scratch}/sub/two.txt"

    run bash "$CHECK_ARTIFACTS" --scratchpad "$scratch"
    assert_success
    assert_output --partial 'scratchpad 잔재 2건'
    assert_output --partial 'VERDICT: NOTE'
}

@test "C-3: an empty scratchpad passes" {
    scratch="${WORK}/scratchpad-empty"
    mkdir -p "$scratch"

    run bash "$CHECK_ARTIFACTS" --scratchpad "$scratch"
    assert_success
    assert_output --partial 'scratchpad 잔재 없음'
    assert_output --partial 'VERDICT: OK'
}

@test "C-3: gitignored files are not reported as artifacts" {
    make_repo ignored
    printf 'build/\n' >"${REPO}/.gitignore"
    git -C "$REPO" add -- .gitignore
    git -C "$REPO" commit -q -m "ignore build"
    mkdir -p "${REPO}/build"
    : >"${REPO}/build/empty-artifact.md"

    run bash "$CHECK_ARTIFACTS" "$REPO"
    assert_success
    refute_output --partial 'empty-artifact.md'
}

# ── multi-repo coverage (F-2: cwd 하나만 보지 않는다) ──────────────────

@test "F-2: every repo passed on the command line is checked" {
    make_repo alpha
    alpha="$REPO"
    make_repo beta
    beta="$REPO"
    printf 'edited\n' >>"${beta}/README.md"

    run bash "$CHECK_REPOS" "$alpha" "$beta"
    assert_failure
    assert_output --partial "REPO: ${alpha}"
    assert_output --partial "REPO: ${beta}"
    assert_output --partial '미커밋 변경 1건'
}

# ── NF-1: read-only invariant ─────────────────────────────────────────

@test "NF-1: check-repos leaves the repo state byte-identical" {
    make_repo readonly
    printf 'edited\n' >>"${REPO}/README.md"
    printf 'x\n' >"${REPO}/untracked.txt"
    : >"${REPO}/reserved.md"

    before="$(git -C "$REPO" status --porcelain)"
    before_head="$(git -C "$REPO" rev-parse HEAD)"
    before_ls="$(cd "$REPO" && find . -path ./.git -prune -o -print | sort)"

    run bash "$CHECK_REPOS" "$REPO"
    assert_failure

    after="$(git -C "$REPO" status --porcelain)"
    after_head="$(git -C "$REPO" rev-parse HEAD)"
    after_ls="$(cd "$REPO" && find . -path ./.git -prune -o -print | sort)"

    [ "$before" = "$after" ]
    [ "$before_head" = "$after_head" ]
    [ "$before_ls" = "$after_ls" ]
}

@test "NF-1: check-artifacts leaves the repo state byte-identical" {
    make_repo readonly2
    : >"${REPO}/reserved.md"
    printf 'x\n' >"${REPO}/leftover.tmp"

    before="$(git -C "$REPO" status --porcelain)"
    before_ls="$(cd "$REPO" && find . -path ./.git -prune -o -print | sort)"

    run bash "$CHECK_ARTIFACTS" "$REPO"
    assert_success

    after="$(git -C "$REPO" status --porcelain)"
    after_ls="$(cd "$REPO" && find . -path ./.git -prune -o -print | sort)"

    [ "$before" = "$after" ]
    [ "$before_ls" = "$after_ls" ]
}

@test "NF-1: a fake git rejecting state-changing verbs still lets both run" {
    make_repo guarded
    printf 'edited\n' >>"${REPO}/README.md"

    mkdir -p "${WORK}/bin"
    cat >"${WORK}/bin/git" <<'EOF'
#!/usr/bin/env bash
# Reject anything that would mutate the repo or hit the network.
case "${1:-}" in
    -C) verb="${3:-}" ;;
    *) verb="${1:-}" ;;
esac
case "$verb" in
    add | commit | push | fetch | pull | checkout | reset | clean | stash | \
        merge | rebase | restore | apply | mv | switch | worktree)
        echo "FORBIDDEN GIT VERB: $verb" >&2
        exit 99
        ;;
esac
exec "$REAL_GIT" "$@"
EOF
    chmod +x "${WORK}/bin/git"
    REAL_GIT="$(command -v git)"
    export REAL_GIT

    run env PATH="${WORK}/bin:${PATH}" bash "$CHECK_REPOS" "$REPO"
    refute_output --partial 'FORBIDDEN GIT VERB'
    assert_output --partial '미커밋 변경 1건'

    run env PATH="${WORK}/bin:${PATH}" bash "$CHECK_ARTIFACTS" "$REPO"
    assert_success
    refute_output --partial 'FORBIDDEN GIT VERB'
}

# ── NF-3: C-1/C-3 are offline-only ────────────────────────────────────

@test "NF-3: neither local check invokes gh or the network" {
    for f in "${CHECK_REPOS}" "${CHECK_ARTIFACTS}"; do
        run grep -nE '(^|[^[:alnum:]_-])gh[[:space:]]+(issue|pr|api|auth)' "$f"
        assert_failure
        run grep -nE 'git[^|]*(fetch|ls-remote)' "$f"
        assert_failure
    done
}

# ── NF-1/NF-2: no dangerous command anywhere in the skill ─────────────
#
# The acceptance criterion is a grep guard for commit / push / rm / kill /
# EndConversation. A raw substring grep is unusable here — "skill" contains
# "kill" and the directory itself is claude/skills/. So the guard matches
# actual command invocations instead of bare substrings.

@test "NF-1: the skill never invokes a state-changing git verb" {
    run grep -rnE 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(commit|push|add|reset|checkout|clean|restore)([[:space:]]|$)' "$SKILL_DIR"
    assert_failure
}

@test "NF-1: the skill never deletes files" {
    run grep -rnE '(^|[;&|[:space:]])(rm|rmdir|unlink|shred|truncate)[[:space:]]+-?' "$SKILL_DIR"
    assert_failure
    run grep -rnE 'find[^\n]*-delete' "$SKILL_DIR"
    assert_failure
}

@test "NF-2: the skill never force-terminates a process or ends the conversation" {
    run grep -rnE '(^|[;&|[:space:]])(kill|pkill|killall)[[:space:]]+-?' "$SKILL_DIR"
    assert_failure
    run grep -rnF 'EndConversation' "$SKILL_DIR"
    assert_failure
}

# ── SKILL.md conventions (NF-5) ───────────────────────────────────────

@test "NF-5: SKILL.md stays within 100 lines" {
    lines="$(wc -l <"${SKILL_DIR}/SKILL.md")"
    [ "$lines" -le 100 ]
}

@test "NF-5: SKILL.md declares the devx:session-close name" {
    run grep -c '^name: devx:session-close$' "${SKILL_DIR}/SKILL.md"
    assert_output '1'
}

@test "NF-5: SKILL.md declares the model recommendation block" {
    run grep -c '^    tier: sonnet$' "${SKILL_DIR}/SKILL.md"
    assert_output '1'
    run grep -c '^allowed-tools: Bash, Read, Grep, TaskList$' "${SKILL_DIR}/SKILL.md"
    assert_output '1'
}

@test "NF-5: SKILL.md routes -h/--help/help to references/help.md verbatim" {
    run grep -n 'references/help.md` verbatim' "${SKILL_DIR}/SKILL.md"
    assert_success
    [ -f "${SKILL_DIR}/references/help.md" ]
}

@test "NF-5: every reference file the SKILL.md names exists" {
    for f in help.md checks.md report.md; do
        [ -f "${SKILL_DIR}/references/${f}" ]
    done
}

@test "F-8: the report reference pins both verdict last-lines" {
    run grep -cF '[OK] 남은 작업 없음 — 세션을 닫아도 됩니다' "${SKILL_DIR}/references/report.md"
    assert_output '1'
    run grep -cF 'Next: /exit' "${SKILL_DIR}/references/report.md"
    assert_output '1'
    run grep -F '[BLOCKED]' "${SKILL_DIR}/references/report.md"
    assert_success
}

@test "F-9: the report reference routes 미완 작업 to devx:session-handoff" {
    run grep -F 'devx:session-handoff' "${SKILL_DIR}/references/report.md"
    assert_success
}

@test "F-6: the background-task gap is documented as an Open Question" {
    run grep -F 'Open Question' "${SKILL_DIR}/references/checks.md"
    assert_success
    run grep -F '열거 수단' "${SKILL_DIR}/references/checks.md"
    assert_success
}

@test "lib scripts print their own usage on -h" {
    for s in "$CHECK_REPOS" "$CHECK_ARTIFACTS"; do
        for flag in -h --help help; do
            run bash "$s" "$flag"
            assert_success
            assert_output --partial 'Usage:'
        done
    done
}
