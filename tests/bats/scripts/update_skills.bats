#!/usr/bin/env bats
# tests/bats/scripts/update_skills.bats
# Validate scripts/update-skills.sh (#1825): runs git-clone-skills -> git-pull-skills ->
# claude/setup.sh -> update-plugins -> setup-skills-ssot.sh in order (#1903), stops on
# clone/pull failure, --dry-run clones/pulls/update-plugins in dry-run only.
# #2126: summary mode (shared step runner) vs -v / SKILLS_SYNC_VERBOSE=1 streaming.

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/scripts/update-skills.sh"

# Build a fake dotfiles tree: a copy of the wrapper plus 5 stub steps that
# append their name (and args) to $CALL_LOG. The wrapper resolves its root
# from its own (realpath'd) location, so the copy drives the stubs.
_make_fake_root() {
    local pull_rc="$1" clone_rc="${2:-0}" plugins_rc="${3:-0}"
    FAKE_ROOT="${TEST_TEMP_HOME}/fake-dotfiles"
    CALL_LOG="${TEST_TEMP_HOME}/calls.log"
    export CALL_LOG
    rm -rf "$FAKE_ROOT"
    mkdir -p "$FAKE_ROOT/scripts" "$FAKE_ROOT/claude/plugin" "$FAKE_ROOT/shell-common/tools"
    cp "$SCRIPT_UNDER_TEST" "$FAKE_ROOT/scripts/update-skills.sh"
    ln -s "${DOTFILES_ROOT}/shell-common/tools/ux_lib" "$FAKE_ROOT/shell-common/tools/ux_lib"
    _stub "$FAKE_ROOT/claude/plugin/git-clone-skills.sh" clone "$clone_rc"
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull "$pull_rc"
    _stub "$FAKE_ROOT/claude/setup.sh" claude-setup 0
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

@test "update-skills.sh runs the 5 steps in order, passing args to pull only" {
    _make_fake_root 0
    cd /
    run "$FAKE_ROOT/scripts/update-skills.sh" --all-branches
    assert_success
    run cat "$CALL_LOG"
    assert_output "clone
pull --all-branches
claude-setup
update-plugins
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

@test "update-skills.sh --dry-run runs only the clone, pull and update-plugins dry-runs" {
    _make_fake_root 0
    run "$FAKE_ROOT/scripts/update-skills.sh" --dry-run
    assert_success
    run cat "$CALL_LOG"
    assert_output "clone --dry-run
pull --dry-run
update-plugins --dry-run"
}

@test "skills-sync alias points at update-skills.sh" {
    run bash -c "source '${SHELL_COMMON}/aliases/skills_sync.sh' && alias skills-sync"
    assert_success
    assert_output --partial '${HOME}/dotfiles/scripts/update-skills.sh'
}

@test "summary mode: all-green run is header + 5 step lines + 1 summary line" {
    _make_fake_root 0
    _stub "$FAKE_ROOT/claude/plugin/git-pull-skills.sh" pull 0 'noise up-to-date\n  ◆ Updated: 0\n  ◆ Up to date: 17\n'
    _stub "$FAKE_ROOT/claude/plugin/update-plugins.sh" update-plugins 0 'marketplace refreshed\n  ◆ Plugins updated: 2\n  ◆ Plugins up to date: 15\n  ◆ Failed: 0\n'
    run "$FAKE_ROOT/scripts/update-skills.sh"
    assert_success
    assert_equal "$(grep -c . <<<"$output")" 7
    assert_output --partial "skills-sync (요약 모드"
    assert_output --regexp '✅ git-clone-skills \([0-9]+\.[0-9]s\)'
    assert_output --regexp '✅ git-pull-skills \([0-9]+\.[0-9]s\) — 갱신 0 / 최신 17'
    assert_output --regexp '✅ claude/setup.sh \('
    assert_output --regexp '✅ update-plugins \([0-9]+\.[0-9]s\) — 갱신 2 / 최신 15'
    assert_output --regexp '✅ setup-skills-ssot \('
    assert_output --partial "skills-sync 완료: 5개 스텝 모두 정상"
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

@test "summary mode: update-plugins failure runs step 5, lists it, exits with its rc" {
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
    assert_output --partial "2/5 git-pull-skills"
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
    assert_output --partial "skills-sync (dry-run) 완료: 3개 스텝 모두 정상"
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
}
