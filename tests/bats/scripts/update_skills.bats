#!/usr/bin/env bats
# tests/bats/scripts/update_skills.bats
# Validate scripts/update-skills.sh (#1825): runs git-clone-skills -> git-pull-skills ->
# claude/setup.sh -> update-plugins -> restore --check -> setup-skills-ssot.sh in
# order (#1903, #2366), with --restore opting into install before update. Stops on clone/pull failure, --dry-run previews
# dry-run only.
# #2126: summary mode (shared step runner) vs -v / SKILLS_SYNC_VERBOSE=1 streaming.

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/scripts/update-skills.sh"

# Build a fake dotfiles tree: a copy of the wrapper plus 6 stub steps that
# append their name (and args) to $CALL_LOG. The wrapper resolves its root
# from its own (realpath'd) location, so the copy drives the stubs.
_make_fake_root() {
    local pull_rc="$1" clone_rc="${2:-0}" plugins_rc="${3:-0}" restore_rc="${4:-0}"
    FAKE_ROOT="${TEST_TEMP_HOME}/fake-dotfiles"
    CALL_LOG="${TEST_TEMP_HOME}/calls.log"
    export CALL_LOG
    : >"$CALL_LOG"
    rm -rf "$FAKE_ROOT"
    mkdir -p "$FAKE_ROOT/scripts" "$FAKE_ROOT/claude/plugin" "$FAKE_ROOT/shell-common/tools"
    cp "$SCRIPT_UNDER_TEST" "$FAKE_ROOT/scripts/update-skills.sh"
    ln -s "${DOTFILES_ROOT}/shell-common/tools/ux_lib" "$FAKE_ROOT/shell-common/tools/ux_lib"
    _stub "$FAKE_ROOT/claude/plugin/git-clone-skills.sh" clone "$clone_rc"
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull "$pull_rc"
    _stub "$FAKE_ROOT/claude/setup.sh" claude-setup 0
    _stub "$FAKE_ROOT/claude/plugin/restore.sh" restore "$restore_rc"
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins "$plugins_rc"
    _stub "$FAKE_ROOT/scripts/setup-skills-ssot.sh" skills-ssot 0
}

# _stub <path> <name> <rc> [stdout-text]
_stub() {
    printf '#!/bin/bash\necho %s "$@" >>"$CALL_LOG"\nprintf "%%b" %q\nexit %s\n' "$2" "${4:-}" "$3" >"$1"
    chmod +x "$1"
}

setup() {
    setup_isolated_home
    export TMPDIR="$TEST_TEMP_HOME"
    unset SKILLS_SYNC_VERBOSE
}

teardown() {
    teardown_isolated_home
}

@test "update-skills.sh passes bash syntax check" {
    run bash -n "$SCRIPT_UNDER_TEST"
    assert_success
}

@test "update-skills.sh is executable" {
    [ -x "$SCRIPT_UNDER_TEST" ]
}

@test "update-skills.sh runs the 6 default read-only steps in order, passing args to pull only" {
    _make_fake_root 0
    cd /
    run "$FAKE_ROOT/scripts/update-skills.sh" --all-branches
    assert_success
    run cat "$CALL_LOG"
    assert_output "clone
pull --all-branches
claude-setup
update-plugins
restore --check
skills-ssot"
}

@test "update-skills.sh still runs setup-skills-ssot when update-plugins fails, then fails" {
    _make_fake_root 0 0 1
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure 1
    run cat "$CALL_LOG"
    assert_output "clone
pull
claude-setup
update-plugins
restore --check
skills-ssot"
}

@test "update-skills.sh stops before synthesis when git-pull-skills fails" {
    _make_fake_root 1
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure
    run cat "$CALL_LOG"
    assert_output "clone
pull"
}

@test "update-skills.sh stops before pull when git-clone-skills fails" {
    _make_fake_root 0 1
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure
    run cat "$CALL_LOG"
    assert_output "clone"
}

@test "update-skills.sh --dry-run runs clone, pull, update and the read-only check" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run
    assert_success
    run cat "$CALL_LOG"
    assert_output "clone --dry-run
pull --dry-run
update-plugins --dry-run
restore --check"
}

@test "update-skills.sh --restore installs before update and keeps the drift check" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --restore
    assert_success
    run cat "$CALL_LOG"
    assert_output "clone
pull
claude-setup
restore --skip-without-claude
update-plugins
restore --check
skills-ssot"
}

@test "skills-sync alias points at update-skills.sh" {
    run bash -c "source '${SHELL_COMMON}/aliases/skills_sync.sh' && alias skills-sync"
    assert_success
    assert_output --partial '${HOME}/dotfiles/scripts/update-skills.sh'
}

@test "summary mode: all-green run is header + 6 step lines + 1 summary line" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 'noise up-to-date\n  ◆ Updated: 0\n  ◆ Up to date: 17\n'
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 'marketplace refreshed\n  ◆ Plugins updated: 2\n  ◆ Plugins up to date: 15\n  ◆ Failed: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_equal "$(grep -c . <<<"$output")" 8
    assert_output --partial "skills-sync (요약 모드"
    assert_output --regexp '✅ git-clone-skills \([0-9]+\.[0-9]s\)'
    assert_output --regexp '✅ git-pull-skills \([0-9]+\.[0-9]s\) — 갱신 0 / 최신 17'
    assert_output --regexp '✅ claude/setup.sh \('
    assert_output --regexp '✅ update-plugins \([0-9]+\.[0-9]s\) — 갱신 2 / 최신 15'
    assert_output --regexp '✅ restore --check \('
    assert_output --regexp '✅ setup-skills-ssot \('
    assert_output --partial "skills-sync 완료: 6개 스텝 모두 정상"
    refute_output --partial "noise"
    refute_output --partial "전체 로그"
}

@test "summary mode: digest survives tput sgr0 escapes (\\e(B\\e[m) around the bullet" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 '  \033[34m◆\033(B\033[m Updated: 3\n  \033[34m◆\033(B\033[m Up to date: 9\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --regexp '✅ git-pull-skills \([0-9]+\.[0-9]s\) — 갱신 3 / 최신 9'
}

@test "--help prints usage and runs no step" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --help
    assert_success
    assert_output --partial "skills-sync"
    assert_output --partial "--dry-run"
    [ ! -s "$CALL_LOG" ]
}

@test "summary mode: ux_lib-fallback WARN: line marks the step as warning and is shown" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 'WARN: notes-skills: dirty working tree\nfine\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --regexp '⚠️  git-pull-skills \([0-9]+\.[0-9]s\) — 경고 1줄'
    assert_output --partial "WARN: notes-skills: dirty working tree"
    assert_output --partial "경고 스텝: git-pull-skills"
    assert_output --partial "전체 로그: $TMPDIR/skills-sync-"
}

@test "summary mode: update-plugins failure runs step 6, lists it, exits with its rc" {
    _make_fake_root 0 0 7
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure 7
    assert_output --partial "update-plugins 실패 [optional] (exit 7"
    assert_output --partial "실패 스텝(optional): update-plugins"
    assert_output --regexp '✅ setup-skills-ssot \('
    run tail -n 1 "$CALL_LOG"
    assert_output "skills-ssot"
}

@test "summary mode: claude/setup.sh and setup-skills-ssot failures stop with non-zero" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/setup.sh" claude-setup 2
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure
    assert_output --partial "claude/setup.sh 실패 [critical]"
    run cat "$CALL_LOG"
    assert_output "clone
pull
claude-setup"
    _make_fake_root 0
    _stub "$FAKE_ROOT/scripts/setup-skills-ssot.sh" skills-ssot 4
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure
    assert_output --partial "setup-skills-ssot 실패 [critical]"
}

@test "-v streams sub-script output and is not forwarded to git-pull-skills" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 'pull-detail-line\n'
    run "$FAKE_ROOT/scripts/update-skills.sh" -v --all-branches
    assert_success
    assert_output --partial "pull-detail-line"
    assert_output --partial "2/6 git-pull-skills"
    refute_output --partial "요약 모드"
    run grep '^pull' "$CALL_LOG"
    assert_output "pull --all-branches"
}

@test "SKILLS_SYNC_VERBOSE=1 streams like -v" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 'pull-detail-line\n'
    SKILLS_SYNC_VERBOSE=1 run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "pull-detail-line"
    refute_output --partial "요약 모드"
}

@test "--dry-run uses the summary runner with (dry-run) labels and exits 0" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run
    assert_success
    assert_output --partial "skills-sync (요약 모드"
    assert_output --regexp '✅ git-clone-skills \(dry-run\) \('
    assert_output --regexp '✅ git-pull-skills \(dry-run\) \('
    assert_output --regexp '✅ update-plugins \(dry-run\) \('
    assert_output --regexp '✅ restore --check \('
    assert_output --partial "skills-sync (dry-run) 완료: 4개 스텝 모두 정상"
}

@test "--dry-run: update-plugins failure is reported as optional and becomes the exit code" {
    _make_fake_root 0 0 5
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run
    assert_failure 5
    assert_output --partial "update-plugins (dry-run) 실패 [optional] (exit 5"
    assert_output --partial "실패 스텝(optional): update-plugins (dry-run)"
}

@test "summary mode: all-green run deletes its log; a warning run keeps it" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    run bash -c "ls '$TMPDIR' | grep -c '^skills-sync-'"
    assert_output "0"
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 'WARN: dirty\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    run bash -c "ls '$TMPDIR' | grep -c '^skills-sync-.*\.log$'"
    assert_output "1"
}

@test "a --target value that looks like -v or help is passed to git-pull-skills untouched" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --target -v
    assert_success
    assert_output --partial "요약 모드"
    run grep '^pull' "$CALL_LOG"
    assert_output "pull --target -v"
}

@test "update-plugins digest flags a needed session restart and unrecognized results" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 '  ◆ Plugins updated: 1\n  ◆ Plugins up to date: 16\n  ◆ Failed: 0\n  ◆ Plugins with an unrecognized result: 2\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "— 갱신 1 / 최신 16 (실행 중인 Claude Code 세션 재시작 필요) / 미인식 2"
}

@test "--jobs N / --jobs=N reach both pull and update-plugins through DOTFILES_SKILLS_JOBS (#2198)" {
    _make_fake_root 0
    local s
    for s in git-pull-skills:pull update-plugins:update-plugins; do
        printf '#!/bin/bash\necho %s "jobs=${DOTFILES_SKILLS_JOBS:-}" "$@" >>"$CALL_LOG"\n' "${s#*:}" \
            >"$FAKE_ROOT/claude/plugin/${s%%:*}.sh"
    done
    cd /
    run "$FAKE_ROOT/scripts/update-skills.sh" --jobs 2 --all-branches
    assert_success
    run grep -E '^(pull|update-plugins) ' "$CALL_LOG"
    assert_line "pull jobs=2 --all-branches"
    assert_line "update-plugins jobs=2"
    : >"$CALL_LOG"
    run "$FAKE_ROOT/scripts/update-skills.sh" --jobs=1
    assert_success
    run grep -c 'jobs=1' "$CALL_LOG"
    assert_output "2"
}

# --- #2337: STEP_DETAIL — updated / cloned items as dim indented lines ---

@test "summary mode: update-plugins lists each updated plugin under its step line (#2337)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 '✅   gh-flow@gh-flow-skills: updated 0.3.1 -> 0.3.2\nℹ️    notes@notes-skills: up to date (1.0.0)\nOK:   bare@mkt: updated\n  ◆ Plugins updated: 2\n  ◆ Plugins up to date: 1\n  ◆ Failed: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    local step_line next
    step_line=$(grep -n '✅ update-plugins' <<<"$output" | cut -d: -f1)
    next=$(sed -n "$((step_line + 1))p;$((step_line + 2))p" <<<"$output")
    assert_equal "$next" "  gh-flow@gh-flow-skills: 0.3.1 -> 0.3.2
  bare@mkt"
    refute_output --partial "notes@notes-skills"
}

@test "summary mode: git-pull-skills and git-clone-skills list updated / cloned repos (#2337)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-clone-skills.sh" clone 0 'ℹ️  old-skills: already present (skipped)\n✅ new-skills: cloned from git@github.com:o/new-skills.git\n  ◆ Cloned: 1\n'
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 '✅ a-skills: updated via ff-only (main)\n✅ b-skills: updated via rebase (upstream/main)\n✅ c-skills: synced and pushed to origin (main)\n✅ d-skills: up-to-date (main)\n  ◆ Updated: 3\n  ◆ Up to date: 1\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --regexp '✅ git-clone-skills \([0-9]+\.[0-9]s\) — 신규 clone 1
  new-skills
✅ git-pull-skills \([0-9]+\.[0-9]s\) — 갱신 3 / 최신 1
  a-skills
  b-skills
  c-skills
✅ claude/setup.sh'
    refute_output --partial "d-skills"
    refute_output --partial "old-skills"
}

@test "summary mode: more than 10 updated items cap at 9 + '... 외 N개' (#2337)" {
    _make_fake_root 0
    local body="" i
    for i in $(seq 1 12); do body="${body}✅ r$i-skills: updated via ff-only (main)\\n"; done
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 "${body}  ◆ Updated: 12\n  ◆ Up to date: 0\n"
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    local detail
    detail=$(grep -E '^  (r[0-9]+-skills|\.\.\. )' <<<"$output")
    run printf '%s\n' "$detail"
    assert_equal "${#lines[@]}" 10
    assert_line --index 0 "  r1-skills"
    assert_line --index 8 "  r9-skills"
    assert_line --index 9 "  ... 외 3개"
}

@test "summary mode: a warning step prints no detail lines (#2337)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 '✅ a-skills: updated via ff-only (main)\nWARN: b-skills: dirty\n  ◆ Updated: 1\n  ◆ Up to date: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "WARN: b-skills: dirty"
    [ "$(grep -cx '  a-skills' <<<"$output")" = 0 ]
}

@test "-v mode: no STEP_DETAIL lines are added (#2337)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 '✅ a-skills: updated via ff-only (main)\n  ◆ Updated: 1\n  ◆ Up to date: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh" -v
    assert_success
    assert_output --partial "✅ a-skills: updated via ff-only (main)"
    [ "$(grep -cx '  a-skills' <<<"$output")" = 0 ]
}

@test "update-plugins detail: a line matched by one pattern is not re-matched by the next (#2337)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 '✅   x@m: updated updated\n  ◆ Plugins updated: 1\n  ◆ Plugins up to date: 0\n  ◆ Failed: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    [ "$(grep -c '^  x@m' <<<"$output")" = 1 ]
}

@test "git-pull-skills detail needs the digest: no 'Up to date' count, no detail lines (#2337)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 '✅ a-skills: updated via ff-only (main)\n  ◆ Updated: 1\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    [ "$(grep -cx '  a-skills' <<<"$output")" = 0 ]
}

@test "the per-item wording the detail patterns parse still exists in the real sub-scripts (#2337)" {
    local p="${DOTFILES_ROOT}/claude/plugin"
    grep -qF 'ux_success "  $id: updated${old:+ $old -> $new}"' "$p/update-plugins.sh"
    grep -qF 'ux_success "$repo_name: updated via ff-only (' "$p/git-pull-skills.sh"
    grep -qF 'ux_success "$repo_name: updated via rebase (' "$p/git-pull-skills.sh"
    grep -qF 'ux_success "$repo_name: synced and pushed to origin (' "$p/git-pull-skills.sh"
    grep -qF 'ux_success "$repo_name: cloned from ' "$p/git-clone-skills.sh"
    grep -qF 'ux_success "  install: ${plugin}"' "$p/restore.sh"
    grep -qF 'ux_bullet "Plugins installed: $PL_INSTALLED"' "$p/restore.sh"
    grep -qF 'ux_bullet "Marketplaces skipped (not registered): $MP_SKIPPED"' "$p/update-plugins.sh"
}

# --- #2344 / #2366: opt-in restore-plugins step ---

@test "restore-plugins failure still runs update-plugins + synthesis, and its rc wins (#2344 F-9)" {
    _make_fake_root 0 0 7 3
    run "$FAKE_ROOT/scripts/update-skills.sh" --restore
    assert_failure 3
    assert_output --partial "restore-plugins 실패 [optional] (exit 3"
    run cat "$CALL_LOG"
    assert_line "update-plugins"
    assert_line "skills-ssot"
}

@test "restore-plugins digest: new installs, marketplaces, item detail and session hint (#2344 F-12)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/restore.sh" restore 0 '== 공용 marketplaces ==\n  add: gh-flow-skills (dEitY719/gh-flow-skills)\n  install: gh-flow@gh-flow-skills\n  install: notes@notes-skills\n  * Marketplaces added: 1\n  * Plugins installed: 2\n  * Already present: 30\n  * Failed: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh" --restore
    assert_success
    assert_output --regexp '✅ restore-plugins \([0-9]+\.[0-9]s\) — 신규 설치 2 / 마켓플레이스 1 \(새 Claude Code 세션 시작 필요\)
  gh-flow@gh-flow-skills
  notes@notes-skills'
}

@test "restore-plugins --dry-run digest previews the would-install count (#2344 F-13)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/restore.sh" restore 0 '  install: gh-flow@gh-flow-skills\n  * Marketplaces (would add): 0\n  * Plugins (would install): 1\n'
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run --restore
    assert_success
    assert_output --regexp '✅ restore-plugins \(dry-run\) \([0-9]+\.[0-9]s\) — 설치 예정 1
  gh-flow@gh-flow-skills'
    refute_output --partial "세션 시작 필요"
}

@test "restore-plugins digest names a skip for a PC without claude (#2344 F-10)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/restore.sh" restore 0 'claude CLI 없음 — 플러그인 복원 건너뜀 (clinstall 후 재실행)\n'
    run "$FAKE_ROOT/scripts/update-skills.sh" --restore
    assert_success
    assert_output --partial "restore-plugins"
    assert_output --partial "— claude CLI 없음 — 건너뜀"
}

@test "update-plugins digest shows still-unregistered marketplaces (#2344 F-14)" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 '  ◆ Plugins updated: 0\n  ◆ Plugins up to date: 5\n  ◆ Failed: 0\n  ◆ Marketplaces skipped (not registered): 2\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "— 갱신 0 / 최신 5 / 미등록 skip 2"
}

# --- argument pre-validation / --only / exit-2 hint / repo-vs-plugin note ---

@test "an unknown positional arg (step name) exits 2 before any step and points at --only" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" restore --check
    assert_failure 2
    assert_output --partial "알 수 없는 인자: restore"
    assert_output --partial "--only restore-check"
    assert_output --partial "skills-sync"
    [ ! -s "$CALL_LOG" ]
}

@test "an unknown option exits 2 with usage and runs no step" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --bogus
    assert_failure 2
    assert_output --partial "알 수 없는 인자: --bogus"
    refute_output --partial "--only restore-check"
    assert_output --partial "--dry-run"
    [ ! -s "$CALL_LOG" ]
}

@test "every option git-pull-skills.sh parses is still accepted and forwarded by update-skills.sh" {
    # Drift guard: update-skills.sh mirrors git-pull-skills.sh's option case.
    local opts
    opts=$(sed -En 's/^\t(-[-a-z| ]+(=\*)?)\)$/\1/p' "${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh" | tr -d ' ' | tr '|' '\n')
    assert_equal "$(tr '\n' ' ' <<<"$opts")" "--dry-run --all-branches --target --target=* --jobs --jobs=* -h --help help "
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --all-branches --target /x --target=/y
    assert_success
    run grep '^pull' "$CALL_LOG"
    assert_output "pull --all-branches --target /x --target=/y"
}

@test "a step exiting 2 (usage error) gets the argument hint, not the conflict hint" {
    _make_fake_root 2
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure
    assert_output --partial "인자 확인 — skills-sync -h"
    refute_output --partial "충돌/분기된 repo 확인"
    _make_fake_root 1
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure
    assert_output --partial "충돌/분기된 repo 확인"
    refute_output --partial "인자 확인 — skills-sync -h"
}

@test "--only restore-check runs that single step as 1/1" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_success
    assert_output --partial "skills-sync 완료: 1개 스텝 모두 정상"
    run cat "$CALL_LOG"
    assert_output "restore --check"
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" -v --only=pull --all-branches
    assert_success
    assert_output --partial "1/1 git-pull-skills"
    run cat "$CALL_LOG"
    assert_output "pull --all-branches"
}

@test "--only maps every step name to its sub-script" {
    local pair
    for pair in clone:clone pull:pull setup:claude-setup update-plugins:update-plugins \
        "restore-check:restore --check" "restore-plugins:restore --skip-without-claude" ssot:skills-ssot; do
        _make_fake_root 0
        run "$FAKE_ROOT/scripts/update-skills.sh" --only "${pair%%:*}"
        assert_success
        run cat "$CALL_LOG"
        assert_output "${pair#*:}"
    done
}

@test "--only rejects an unknown step, a missing value, and synthesis under --dry-run" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --only nope
    assert_failure 2
    assert_output --partial "알 수 없는 스텝: nope"
    run "$FAKE_ROOT/scripts/update-skills.sh" --only
    assert_failure 2
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run --only ssot
    assert_failure 2
    [ ! -s "$CALL_LOG" ]
}

@test "--help lists the --only step names" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" -h
    assert_success
    assert_output --partial "--only <step>"
    assert_output --partial "clone, pull, setup, restore-plugins, update-plugins, restore-check, ssot"
}

@test "summary explains repo-vs-plugin update mismatch in one info line" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 '✅ a-skills: updated via ff-only (main)\n✅ harness-skills: updated via rebase (upstream/main)\n  ◆ Updated: 2\n  ◆ Up to date: 5\n'
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 '✅   a@a-skills: updated 1.0.0 -> 1.0.1\n✅   ext@claude-plugins-official: updated 2.0 -> 2.1\n  ◆ Plugins updated: 2\n  ◆ Plugins up to date: 15\n  ◆ Failed: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "repo 갱신 2 / 플러그인 갱신 2 — pull 됐으나 플러그인 버전 불변: harness-skills · pull 없이 갱신(외부 marketplace): ext@claude-plugins-official"
    [ "$(grep -c 'repo 갱신' <<<"$output")" = 1 ]
}

@test "no repo-vs-plugin line when every pulled repo's plugin was updated" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 '✅ a-skills: updated via ff-only (main)\n  ◆ Updated: 1\n  ◆ Up to date: 5\n'
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 '✅   a@a-skills: updated 1.0.0 -> 1.0.1\n✅   a2@a-skills: updated 1.0.0 -> 1.0.1\n  ◆ Plugins updated: 2\n  ◆ Plugins up to date: 15\n  ◆ Failed: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    refute_output --partial "repo 갱신"
}

@test "restore check drift warns and recommends restore without failing sync" {
    _make_fake_root 0 0 0 1
    _stub "$FAKE_ROOT/claude/plugin/restore.sh" restore 1 'WARN: plugin not installed: secret@private\n'
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_success
    assert_output --partial '경고 스텝: restore --check'
    assert_output --partial 'skills-sync --restore'
}

@test "restore check store failure remains a failure without restore hint" {
    _make_fake_root 0 0 0 3
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_failure 3
    refute_output --partial 'skills-sync --restore'
}

@test "verbose restore check shows drift and records a warning" {
    _make_fake_root 0 0 0 1
    _stub "$FAKE_ROOT/claude/plugin/restore.sh" restore 1 'WARN: plugin not installed: secret@private\n'
    run "$FAKE_ROOT/scripts/update-skills.sh" -v --only restore-check
    assert_success
    assert_output --partial 'secret@private'
    assert_output --partial 'skills-sync --restore'
    assert_output --partial '경고 스텝: restore --check'
}

@test "restore hint survives more warnings than the summary displays" {
    _make_fake_root 0 0 0 1
    local warnings="" i
    for i in {1..12}; do warnings+="WARN: plugin not installed: item$i\\n"; done
    _stub "$FAKE_ROOT/claude/plugin/restore.sh" restore 1 "$warnings"
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_success
    assert_output --partial '누락 항목 설치: skills-sync --restore'
}

# --- #2443: workspace marketplace repos missing from every manifest ----------

# _ws_repo <folder> <marketplace> <plugin> — a workspace clone with an origin.
_ws_repo() {
    local d="$SKILLS_DIR/$1"
    mkdir -p "$d/.claude-plugin"
    printf '{"name":"%s","plugins":[{"name":"%s"}]}\n' "$2" "$3" >"$d/.claude-plugin/marketplace.json"
    git -C "$d" init -q
    git -C "$d" remote add origin "https://ghes.example.invalid/corp/$1.git"
}

_ws_setup() {
    _make_fake_root 0
    export SKILLS_DIR="$TEST_TEMP_HOME/ws"
    mkdir -p "$SKILLS_DIR" "$FAKE_ROOT/claude/plugin/company"
    printf '{"pub-skills":"o/pub-skills"}\n' >"$FAKE_ROOT/claude/plugin/marketplaces.json"
    printf '{"local-skills":"o/local-skills"}\n' >"$FAKE_ROOT/claude/plugin/marketplaces.local.json"
    printf '{"corp-skills":"https://ghes.example.invalid/corp/corp-skills"}\n' \
        >"$FAKE_ROOT/claude/plugin/company/marketplaces.json"
    _ws_repo pub-skills pub-skills pub
    _ws_repo local-skills local-skills loc
    _ws_repo corp-skills corp-skills corp
}

@test "#2443: unregistered workspace marketplace warns with the exact register command" {
    _ws_setup
    _ws_repo git-skills git-skills git
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "미등록 marketplace: git-skills (plugin: git)"
    assert_output --partial "skills-register https://ghes.example.invalid/corp/git-skills.git"
    assert_output --partial "skills-sync --restore"
    assert_output --partial "skills-workspace-ignore.local.json"
    refute_output --partial "미등록 marketplace: pub-skills"
    refute_output --partial "미등록 marketplace: local-skills"
    refute_output --partial "미등록 marketplace: corp-skills"
}

@test "#2443: registered and ignore-overlay marketplaces produce no warning" {
    _ws_setup
    _ws_repo jira-skills jira-skills jira
    printf '{"jira-skills":"Agent Factory catalog"}\n' \
        >"$FAKE_ROOT/claude/plugin/skills-workspace-ignore.local.json"
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    refute_output --partial "미등록 marketplace"
    refute_output --partial "skills-register"
}

@test "#2443: the warning keeps the exit code (success and optional failure alike)" {
    _ws_setup
    _ws_repo git-skills git-skills git
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_success
    assert_output --partial "미등록 marketplace: git-skills"
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 7
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure 7
    assert_output --partial "미등록 marketplace: git-skills"
}

@test "#2443: a github.com origin points at an upstream PR, not skills-register" {
    _ws_setup
    _ws_repo gh-skills gh-skills ghp
    git -C "$SKILLS_DIR/gh-skills" remote set-url origin "git@github.com:o/gh-skills.git"
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_success
    assert_output --partial "미등록 marketplace: gh-skills"
    assert_output --partial "upstream PR (git@github.com:o/gh-skills.git)"
    refute_output --partial "skills-register git@github.com"
}

@test "#2453: the unregistered hint prints an https origin with .git appended" {
    _ws_setup
    _ws_repo git-skills git-skills git
    git -C "$SKILLS_DIR/git-skills" remote set-url origin "https://ghes.example.invalid/corp/git-skills"
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_success
    assert_output --partial "skills-register https://ghes.example.invalid/corp/git-skills.git"
}

@test "#2453: a plugin-name collision prints only the ignore hint, never skills-register" {
    _ws_setup
    _ws_repo sp-dev superpowers-dev superpowers
    printf '{"plugins":["superpowers@claude-plugins-official"]}\n' >"$FAKE_ROOT/claude/plugin/plugins.json"
    run "$FAKE_ROOT/scripts/update-skills.sh" --only restore-check
    assert_success
    assert_output --partial "미등록 marketplace: superpowers-dev (plugin: superpowers) — superpowers@claude-plugins-official 과 이름이 겹칩니다"
    assert_output --partial 'skills-workspace-ignore.local.json 에 "superpowers-dev" 추가'
    refute_output --partial "skills-register"
}

# _restore_stub <kind> — restore.sh stub: a real run reports one <kind> failure
# for superpowers@sp-dev via RESTORE_FAILURE_REPORT and exits 1; --check
# reports that plugin as not installed.
_restore_stub() {
    cat >"$FAKE_ROOT/claude/plugin/restore.sh" <<SH
#!/bin/bash
echo restore "\$@" >>"\$CALL_LOG"
if [ "\$1" = --check ]; then echo 'WARN: plugin not installed: superpowers@sp-dev'; exit 1; fi
if [ "$1" = permanent ]; then
    printf 'permanent\tsuperpowers@sp-dev\tskills-register https://ghes.example.invalid/corp/sp-dev.git\n' >>"\$RESTORE_FAILURE_REPORT"
else
    printf 'transient\tsuperpowers@sp-dev\n' >>"\$RESTORE_FAILURE_REPORT"
fi
echo '  실패: install superpowers@sp-dev'
exit 1
SH
    chmod +x "$FAKE_ROOT/claude/plugin/restore.sh"
}

@test "#2453: a permanent restore failure lists its fix and drops every re-run hint" {
    _make_fake_root 0
    _restore_stub permanent
    run "$FAKE_ROOT/scripts/update-skills.sh" --restore
    assert_failure 1
    assert_output --partial "영구 실패 조치: skills-register https://ghes.example.invalid/corp/sp-dev.git"
    assert_output --partial "재실행으로 해결되지 않는 복원 실패"
    refute_output --partial "네트워크/인증 확인 후 skills-sync 재실행"
    refute_output --partial "누락 항목 설치: skills-sync --restore"
    refute_output --partial "skills-sync --restore 를 실행하세요"
    run bash -c 'ls "$TMPDIR" | grep -c skills-sync-restore'
    assert_output 0
}

@test "#2453: a transient restore failure keeps the re-run hints" {
    _make_fake_root 0
    _restore_stub transient
    run "$FAKE_ROOT/scripts/update-skills.sh" --restore
    assert_failure 1
    assert_output --partial "네트워크/인증 확인 후 skills-sync 재실행"
    assert_output --partial "누락 항목 설치: skills-sync --restore"
    refute_output --partial "재실행으로 해결되지 않는"
}

# --- #2446: company/ refresh step before anything reads company/*.json ---

# _make_company — internal-mode fake root whose claude/plugin/company/ tracks a
# bare origin; OTHER is a second clone standing in for another PC.
_make_company() {
    _make_fake_root 0
    export DOTFILES_SETUP_MODE=internal
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    CO="$FAKE_ROOT/claude/plugin/company"
    OTHER="$TEST_TEMP_HOME/other"
    git init -q --bare -b main "$TEST_TEMP_HOME/company.git"
    git init -q -b main "$CO"
    printf '{}\n' >"$CO/marketplaces.json"
    printf '{"plugins":[]}\n' >"$CO/plugins.json"
    printf 'local\n' >"$CO/notes.local.json"
    git -C "$CO" add . && git -C "$CO" commit -qm init
    git -C "$CO" remote add origin "$TEST_TEMP_HOME/company.git"
    git -C "$CO" push -q -u origin main
    git clone -q "$TEST_TEMP_HOME/company.git" "$OTHER"
}

# _other_publishes — origin/main gains a manifest change from another PC.
_other_publishes() {
    printf '{"x":"https://ghes.example.invalid/corp/x"}\n' >"$OTHER/marketplaces.json"
    git -C "$OTHER" commit -qam other && git -C "$OTHER" push -q origin main
}

@test "company/ (a) up-to-date main: no company/ line, exit 0 (#2446)" {
    _make_company
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    refute_output --partial "company/"
}

@test "company/ (b) behind main + uncommitted change: pulled with autostash, change kept (#2446)" {
    _make_company
    _other_publishes
    printf 'edited\n' >"$CO/notes.local.json"
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "company/ main 을 origin/main 으로 갱신했습니다"
    assert_equal "$(git -C "$CO" rev-parse HEAD)" "$(git -C "$OTHER" rev-parse HEAD)"
    assert_equal "$(cat "$CO/notes.local.json")" edited
}

@test "company/ (b) --dry-run only reports the pull it would run (#2446)" {
    _make_company
    _other_publishes
    before=$(git -C "$CO" rev-parse HEAD)
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run
    assert_success
    assert_output --partial "pull --rebase --autostash origin main"
    assert_equal "$(git -C "$CO" rev-parse HEAD)" "$before"
}

@test "company/ (c) stale feature branch: summary-mode warning names branch + switch -C, no switch (#2446)" {
    _make_company
    git -C "$CO" switch -q -c feat/old
    printf 'x\n' >"$CO/README" && git -C "$CO" add README && git -C "$CO" commit -qm readme
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "'feat/old' 브랜치"
    assert_output --partial "정리: git -C '$CO' switch -C main origin/main"
    assert_equal "$(git -C "$CO" symbolic-ref --short HEAD)" feat/old
}

@test "company/ (d) feature branch with different manifests: warning only, no fix command (#2446)" {
    _make_company
    git -C "$CO" switch -q -c feat/new
    printf '{"y":"https://ghes.example.invalid/corp/y"}\n' >"$CO/marketplaces.json"
    git -C "$CO" commit -qam y
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_output --partial "미게시 변경이 있을 수 있어"
    refute_output --partial "switch -C"
    assert_equal "$(git -C "$CO" symbolic-ref --short HEAD)" feat/new
}

@test "company/ refresh is skipped outside internal mode and fails soft on a fetch error (#2446)" {
    _make_company
    _other_publishes
    before=$(git -C "$CO" rev-parse HEAD)
    DOTFILES_SETUP_MODE=external run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    refute_output --partial "company/"
    git -C "$CO" remote set-url origin "$TEST_TEMP_HOME/missing.git"
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure 1
    assert_output --partial "company/ origin fetch 실패"
    run cat "$CALL_LOG"
    assert_line "skills-ssot"
    assert_equal "$(git -C "$CO" rev-parse HEAD)" "$before"
}

@test "company/ (b) autostash re-apply conflict is reported, not claimed as success (#2446 review)" {
    _make_company
    printf 'theirs\n' >"$OTHER/notes.local.json"
    git -C "$OTHER" commit -qam notes && git -C "$OTHER" push -q origin main
    printf 'mine\n' >"$CO/notes.local.json"
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure 1
    assert_output --partial "미커밋 변경 재적용이 충돌했습니다"
    refute_output --partial "갱신했습니다"
    run cat "$CALL_LOG"
    assert_line "skills-ssot"
}

@test "company/ (b) a rebase already in progress is left alone (#2446 review)" {
    _make_company
    _other_publishes
    mkdir "$CO/.git/rebase-apply"
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_failure 1
    assert_output --partial "진행 중인 rebase/am 이 있어"
    [ -d "$CO/.git/rebase-apply" ]
}
