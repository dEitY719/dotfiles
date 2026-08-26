#!/usr/bin/env bats
# tests/bats/functions/gh_pr_review.bats
# Coverage for the production shell function `gh_pr_review` introduced
# in issue #664. Exercises the deterministic surface (loading, help,
# require_ai_cli, prompt builder, comment body builder, post-comment
# guards) without invoking real AI CLIs or the live GitHub API.
#
# The Step 1 arg-parser is already covered by
# tests/bats/skills/gh_pr_review_arg_parse.bats (the fixture now
# sources this same production file); this suite does NOT duplicate
# those cases — it covers what the fixture cannot.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    # Sweep this file's own /tmp naming convention even when a test's
    # assertions abort mid-body before its own `rm -f` runs (agy review,
    # PR #1282 / issue #1276) — teardown_isolated_home only cleans
    # $TEST_TEMP_HOME, not real /tmp.
    rm -f /tmp/gh-pr-review-prompt.*
    # Same reason for the #1283 fallback-path tests, scoped to this
    # process's own PID so a concurrent run is never touched.
    rm -f "/tmp/gh-pr-review-out.$$" "/tmp/gh-pr-review-body.$$"
    # Same for the #1286 stderr-allocator tests, one path per AI lane.
    rm -f "/tmp/gh-pr-review-stderr.codex.$$" \
        "/tmp/gh-pr-review-stderr.agy.$$" \
        "/tmp/gh-pr-review-stderr.claude.$$" \
        "/tmp/gh-pr-review-stderr.opencode.$$"
    # The #1286 interrupt harness runs gh_pr_review in its own process
    # group, so its fallback paths carry the harness PID, not ours. Kill
    # any survivor of an aborted assertion and sweep its litter.
    if [ -n "${_HARNESS_PID-}" ]; then
        kill -9 "-$_HARNESS_PID" 2>/dev/null || true
        rm -f "/tmp/gh-pr-review-out.$_HARNESS_PID" \
            "/tmp/gh-pr-review-body.$_HARNESS_PID" \
            "/tmp/gh-pr-review-stderr.codex.$_HARNESS_PID"
    fi
    teardown_isolated_home
}

# Source the production module directly into the bats shell. The
# interactive guard would normally short-circuit, but DOTFILES_FORCE_INIT
# (set by test_helper) bypasses it. This is the same pattern the
# fixture uses, so loading semantics stay aligned.
_source_module() {
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh"
}

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

@test "bash: gh_pr_review function exists after sourcing" {
    run_in_bash 'declare -f gh_pr_review >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gh-pr-review alias resolves to gh_pr_review" {
    run_in_bash "alias gh-pr-review 2>/dev/null | grep -q gh_pr_review && echo ok"
    assert_success
    assert_output --partial "ok"
}

@test "zsh: gh_pr_review function exists after sourcing" {
    run_in_zsh 'typeset -f gh_pr_review >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# Issue #1454: the guard read ${BASH_SOURCE[0]}, which zsh never populates,
# so under zsh it self-disabled on the very first line and every prior test
# here only ever proved the bash path. Prove the guard really fires when a
# zsh shell sources this file, with a $HOME whose dotfiles is an unrelated
# repo. The file is re-sourced explicitly rather than read off zsh/main.zsh
# Phase 5 because both loaders source with `2>/dev/null` (safe_source /
# load_category), which would swallow the very stderr under test.
@test "zsh: #1454 foreign-checkout guard warns when sourced under zsh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    command -v git >/dev/null 2>&1 || skip "git not available"

    local foreign_home="$TEST_TEMP_HOME/foreign-home"
    mkdir -p "$foreign_home/dotfiles"
    git -C "$foreign_home/dotfiles" init -q -b main
    git -C "$foreign_home/dotfiles" -c user.email=t@t -c user.name=t \
        commit --allow-empty -q -m init

    export HOME="$foreign_home"
    run_in_zsh '. "$SHELL_COMMON/functions/gh_pr_review.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/gh_pr_review.sh"
}

# ---------------------------------------------------------------------------
# Help surface (bypasses all preconditions)
# ---------------------------------------------------------------------------

@test "bash: no args prints help" {
    run_in_bash 'gh_pr_review'
    assert_success
    assert_output --partial "gh-pr-review"
    assert_output --partial "--ai"
}

@test "bash: --help prints help with usage block" {
    run_in_bash 'gh_pr_review --help'
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "gh-pr-review --ai"
}

@test "bash: -h prints help" {
    run_in_bash 'gh_pr_review -h'
    assert_success
    assert_output --partial "Usage:"
}

@test "bash: help documents all five review presets" {
    # The closed enum is part of the user contract. If any preset is
    # ever silently dropped, /gh-pr-review --review <preset> still
    # 'works' but the helper can no longer route correctly. Catch the
    # drift at help generation time.
    run_in_bash 'gh_pr_review --help'
    assert_success
    assert_output --partial "default"
    assert_output --partial "quick"
    assert_output --partial "thorough"
    assert_output --partial "security"
    assert_output --partial "performance"
}

@test "gh_pr_review: parser errors preserve exit 2" {
    _source_module

    run gh_pr_review --ai chatgpt 99
    assert_failure 2
    assert_output --partial "Unknown --ai value: 'chatgpt'"
}

# ---------------------------------------------------------------------------
# _gh_pr_review_require_ai_cli — PATH pre-flight
# ---------------------------------------------------------------------------

@test "require_ai_cli: unknown value → exit 2" {
    _source_module
    run _gh_pr_review_require_ai_cli chatgpt
    assert_failure 2
    assert_output --partial "Unknown --ai value: 'chatgpt'"
}

@test "require_ai_cli: missing CLI → exit 1 with canonical message" {
    # Force an empty PATH so no AI CLI can possibly be found. The bash
    # builtins still resolve because `command -v` is a shell builtin.
    _source_module
    PATH="" run _gh_pr_review_require_ai_cli codex
    assert_failure 1
    assert_output --partial "Required CLI 'codex' not found in PATH"
}

@test "require_ai_cli: present CLI → exit 0" {
    # Stage a stub `codex` binary in a sandbox PATH so we can verify the
    # success branch without depending on whatever the host has installed.
    _source_module
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$stub_dir/codex"
    PATH="$stub_dir:$PATH" run _gh_pr_review_require_ai_cli codex
    assert_success
}

@test "require_ai_cli: opencode on non-internal PC refuses before PATH check" {
    _source_module
    _dotfiles_setup_mode() { echo external; }

    PATH="" run _gh_pr_review_require_ai_cli opencode
    assert_failure 1
    assert_output --partial "--ai opencode is internal-PC only"
    refute_output --partial "Required CLI 'opencode' not found in PATH"
}

@test "require_ai_cli: opencode on internal PC still requires the CLI" {
    _source_module
    _dotfiles_setup_mode() { echo internal; }

    PATH="" run _gh_pr_review_require_ai_cli opencode
    assert_failure 1
    assert_output --partial "Required CLI 'opencode' not found in PATH"
}

@test "gh_pr_review: opencode non-internal preflight returns 1" {
    _source_module
    _stub_gh_noop
    _dotfiles_setup_mode() { echo external; }

    run gh_pr_review --ai opencode 1337 origin
    assert_failure 1
    assert_output --partial "--ai opencode is internal-PC only"
}

@test "require_ai_cli: hermes on non-internal PC refuses before PATH check" {
    _source_module
    _dotfiles_setup_mode() { echo external; }

    PATH="" run _gh_pr_review_require_ai_cli hermes
    assert_failure 1
    assert_output --partial "--ai hermes is internal-PC only"
    refute_output --partial "Required CLI 'hermes' not found in PATH"
}

@test "require_ai_cli: hermes on internal PC still requires the CLI" {
    _source_module
    _dotfiles_setup_mode() { echo internal; }

    PATH="" run _gh_pr_review_require_ai_cli hermes
    assert_failure 1
    assert_output --partial "Required CLI 'hermes' not found in PATH"
}

@test "gh_pr_review: hermes non-internal preflight returns 1" {
    _source_module
    _stub_gh_noop
    _dotfiles_setup_mode() { echo external; }

    run gh_pr_review --ai hermes 1337 origin
    assert_failure 1
    assert_output --partial "--ai hermes is internal-PC only"
}

# ---------------------------------------------------------------------------
# Prompt builder — preset selection + diff section
# ---------------------------------------------------------------------------

# Stub `gh` so `_gh_pr_review_build_prompt` can exercise its diff-fetch
# branch without reaching the live GitHub API. The builder tolerates a
# non-zero `gh pr diff` exit (`|| true`), so the stub is allowed to be
# a no-op; the framing markers must still land in the output file.
_stub_gh_noop() {
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$stub_dir/gh"
    export PATH="$stub_dir:$PATH"
}

@test "build_prompt: default preset writes 7-dimension body + diff markers" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-default.txt"
    _gh_pr_review_build_prompt default "$out" 99 owner/repo main feature
    [ -f "$out" ]
    run grep -q "second-opinion reviewer" "$out"
    assert_success
    run grep -q "7 dimensions" "$out"
    assert_success
    run grep -q "PR DIFF (PR #99, repo owner/repo" "$out"
    assert_success
    run grep -q "END PR DIFF" "$out"
    assert_success
}

@test "build_prompt: quick preset routes to BLOCKER-only body" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-quick.txt"
    _gh_pr_review_build_prompt quick "$out" 1 a/b base head
    run grep -q "ONLY surface BLOCKER findings" "$out"
    assert_success
}

@test "build_prompt: security preset routes to security-lens body" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-sec.txt"
    _gh_pr_review_build_prompt security "$out" 2 a/b base head
    run grep -q "Security-focused review" "$out"
    assert_success
}

@test "build_prompt: unknown preset returns exit 2" {
    _source_module
    _stub_gh_noop
    local out="$TEST_TEMP_HOME/prompt-bad.txt"
    run _gh_pr_review_build_prompt unknown "$out" 1 a/b base head
    assert_failure 2
}

# ---------------------------------------------------------------------------
# Prompt-file path allocator — parallel-lane collision guard (issue #1276)
# ---------------------------------------------------------------------------

@test "mktemp_prompt: different ai, same PR → two distinct lane-tagged paths" {
    _source_module
    local agy_path codex_path
    agy_path=$(_gh_pr_review_mktemp_prompt agy 99)
    codex_path=$(_gh_pr_review_mktemp_prompt codex 99)
    [ -n "$agy_path" ]
    [ -n "$codex_path" ]
    [ "$agy_path" != "$codex_path" ]
    case "$agy_path" in *agy*) ;; *) false ;; esac
    case "$codex_path" in *codex*) ;; *) false ;; esac
    rm -f "$agy_path" "$codex_path"
}

@test "mktemp_prompt: PR token with path-traversal chars is sanitized, never escapes /tmp" {
    _source_module
    local p
    p=$(_gh_pr_review_mktemp_prompt codex "../../etc/passwd")
    [ -n "$p" ]
    case "$p" in /tmp/gh-pr-review-prompt.codex.*) ;; *) false ;; esac
    case "$p" in *..* | */etc/*) false ;; esac
    rm -f "$p"
}

@test "mktemp_prompt: same ai + PR twice → still distinct (retries never collide)" {
    _source_module
    local first second
    first=$(_gh_pr_review_mktemp_prompt codex 99)
    second=$(_gh_pr_review_mktemp_prompt codex 99)
    [ "$first" != "$second" ]
    rm -f "$first" "$second"
}

@test "mktemp_prompt: returned path exists as a file" {
    _source_module
    local p
    p=$(_gh_pr_review_mktemp_prompt claude 1276)
    [ -f "$p" ]
    case "$p" in /tmp/gh-pr-review-prompt.claude.1276.*) ;; *) false ;; esac
    rm -f "$p"
}

# ---------------------------------------------------------------------------
# Temp-path allocator — predictable-PID symlink hardening (issue #1283)
# ---------------------------------------------------------------------------

# Stage a `mktemp` that always fails, so the allocator is forced onto its
# $$-suffixed fallback branch — the branch a local attacker can predict.
# Only setup/teardown of this suite use the real mktemp, and both run
# outside the test body, so shadowing it here is safe.
_stub_mktemp_failing() {
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/mktemp" <<'EOF'
#!/bin/sh
echo "simulated mktemp failure" >&2
exit 1
EOF
    chmod +x "$stub_dir/mktemp"
    export PATH="$stub_dir:$PATH"
    hash -r 2>/dev/null || true
}

# Single source of truth for the codex/1283 fallback path these tests share,
# so the naming template only needs to change in one place. `$$` is the bats
# test process PID and is inherited unchanged by the subshell `run` uses, so
# this is exactly the path the allocator tries.
_prompt_fallback_path() {
    printf '/tmp/gh-pr-review-prompt.codex.1283.%s\n' "$$"
}

@test "mktemp_safe: mktemp fails + symlink pre-planted at fallback path → refuses, victim untouched" {
    _source_module
    _stub_mktemp_failing
    local victim="$TEST_TEMP_HOME/victim.txt"
    printf 'original\n' >"$victim"
    local fallback
    fallback=$(_prompt_fallback_path)
    rm -f "$fallback"
    ln -s "$victim" "$fallback"

    run _gh_pr_review_mktemp_prompt codex 1283
    assert_failure
    refute_output --partial "/tmp/gh-pr-review-prompt"

    # The redirect must not have followed the link.
    [ -L "$fallback" ]
    run cat "$victim"
    assert_output "original"
    rm -f "$fallback"
}

@test "mktemp_safe: mktemp fails + regular file pre-planted at fallback path → refuses, file untouched" {
    _source_module
    _stub_mktemp_failing
    local fallback
    fallback=$(_prompt_fallback_path)
    printf 'squatted\n' >"$fallback"

    run _gh_pr_review_mktemp_prompt codex 1283
    assert_failure
    refute_output --partial "/tmp/gh-pr-review-prompt"

    run cat "$fallback"
    assert_output "squatted"
    rm -f "$fallback"
}

@test "mktemp_safe: mktemp fails with a clear fallback path → exclusive create succeeds" {
    _source_module
    _stub_mktemp_failing
    local fallback
    fallback=$(_prompt_fallback_path)
    rm -f "$fallback"

    run _gh_pr_review_mktemp_prompt codex 1283
    assert_success
    assert_output "$fallback"
    [ -f "$fallback" ]
    [ ! -L "$fallback" ]
    rm -f "$fallback"
}

@test "mktemp_safe: out/body templates fall back to their own \$\$ paths, not a shared one" {
    _source_module
    _stub_mktemp_failing
    local out body
    rm -f "/tmp/gh-pr-review-out.$$" "/tmp/gh-pr-review-body.$$"
    out=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX")
    body=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-body.XXXXXX")
    [ "$out" = "/tmp/gh-pr-review-out.$$" ]
    [ "$body" = "/tmp/gh-pr-review-body.$$" ]
    [ -f "$out" ]
    [ -f "$body" ]
    rm -f "$out" "$body"
}

@test "mktemp_safe: fallback file is mode 0600 even under a permissive umask" {
    # `mktemp` guarantees 0600; the noclobber fallback creates the file with
    # a plain redirect, which honours the ambient umask instead. Under the
    # very common `022` that would leave the prompt / AI output / comment
    # body world-readable to other local users (codex review, PR #1284).
    _source_module
    _stub_mktemp_failing
    local fallback="/tmp/gh-pr-review-out.$$"
    rm -f "$fallback"

    local _prev_umask
    _prev_umask=$(umask)
    umask 022
    run _gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX"
    umask "$_prev_umask"

    assert_success
    assert_output "$fallback"
    run stat -c '%a' "$fallback"
    assert_success
    assert_output "600"
    rm -f "$fallback"
}

@test "mktemp_safe: two same-\$\$ racers on one fallback path → exactly one wins, loser fails closed" {
    # Issue #1286 item 3 — `$$` is the *parent* shell's PID and does not
    # change in a subshell, so two `&`-forked writers inside one script
    # derive the identical fallback path and genuinely race for it. This
    # reconfirms the documented contract: `set -C` opens with
    # O_CREAT|O_EXCL, which the kernel serializes, so the loser fails
    # closed (no output, non-zero exit) instead of clobbering the winner.
    # A passing run is the reason the fallback naming stays `$$`-derived
    # rather than mixing in `$RANDOM`.
    _source_module
    _stub_mktemp_failing
    local fallback="/tmp/gh-pr-review-out.$$"
    rm -f "$fallback"
    local race_dir="$TEST_TEMP_HOME/race"
    mkdir -p "$race_dir"

    local i
    for i in 1 2; do
        (
            if p=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX"); then
                printf 'racer-%s\n' "$i" >>"$p"
                printf '%s' "$p" >"$race_dir/$i.path"
                echo 0 >"$race_dir/$i.rc"
            else
                printf '%s' "$p" >"$race_dir/$i.path"
                echo 1 >"$race_dir/$i.rc"
            fi
        ) &
    done
    wait

    local rc1 rc2
    rc1=$(cat "$race_dir/1.rc")
    rc2=$(cat "$race_dir/2.rc")
    # Exactly one winner — never two, never zero.
    [ "$((rc1 + rc2))" -eq 1 ]

    local winner loser
    if [ "$rc1" -eq 0 ]; then
        winner=1
        loser=2
    else
        winner=2
        loser=1
    fi

    # Winner got the shared fallback path; the loser printed nothing.
    [ "$(cat "$race_dir/$winner.path")" = "$fallback" ]
    [ ! -s "$race_dir/$loser.path" ]

    # The winner's file is intact — the loser neither truncated it nor
    # appended to it — and still carries mktemp-equivalent 0600 bits.
    [ -f "$fallback" ]
    [ ! -L "$fallback" ]
    run stat -c '%a' "$fallback"
    assert_output "600"
    run cat "$fallback"
    assert_output "racer-$winner"
    rm -f "$fallback"
}

# ---------------------------------------------------------------------------
# gh_pr_review() temp-file failure + cascading cleanup (issue #1283)
#
# The allocator itself is covered above; these drive the *public entry point*
# far enough to hit the three guarded assignments and prove that (a) it aborts
# with the documented stderr message and (b) the `rm -f` cascade really removes
# the already-allocated files instead of leaking them (codex review, PR #1284).
#
# Everything before the temp-file block (CLI presence, auth, repo/PR
# resolution, metadata fetch, state preflight) is bypassed by redefining the
# internal helpers in the test body — `run` executes in the same shell, so the
# overrides are what gh_pr_review sees. `mktemp` is then forced to fail so all
# three allocations land on their predictable `$$` fallback paths, and the
# chosen failure site is blocked by squatting that exact path.
# ---------------------------------------------------------------------------

_stub_gh_pr_review_preconditions() {
    _stub_gh_noop # satisfies `command -v gh` and `gh auth status`
    _gh_pr_review_require_ai_cli() { return 0; }
    _gh_pr_review_resolve_target_repo() { echo "owner/repo"; }
    _gh_pr_review_resolve_pr_number() { echo "1283"; }
    _gh_pr_review_fetch_meta() {
        echo '{"state":"OPEN","isDraft":false,"baseRefName":"main","headRefName":"feat"}'
    }
    _gh_pr_review_preflight_pr_state() { return 0; }
}

@test "gh_pr_review: AI_OUT allocation fails → returns 1 and removes PROMPT_FILE" {
    _source_module
    _stub_gh_pr_review_preconditions
    _stub_mktemp_failing

    local prompt_fb="/tmp/gh-pr-review-prompt.codex.1283.$$"
    local out_fb="/tmp/gh-pr-review-out.$$"
    rm -f "$prompt_fb"
    # Squat the AI_OUT fallback so its noclobber create is refused, while
    # PROMPT_FILE still allocates successfully.
    printf 'squatted\n' >"$out_fb"

    run gh_pr_review --ai codex 1283
    assert_failure 1
    assert_output --partial "Could not create AI output temp file under /tmp"

    # The cleanup cascade must not leak the prompt file it already created.
    [ ! -e "$prompt_fb" ]
    # ...and must not have clobbered the squatted path either.
    run cat "$out_fb"
    assert_output "squatted"
    rm -f "$out_fb"
}

@test "gh_pr_review: BODY_FILE allocation fails → returns 1 and removes PROMPT_FILE + AI_OUT" {
    _source_module
    _stub_gh_pr_review_preconditions
    _stub_mktemp_failing

    local prompt_fb="/tmp/gh-pr-review-prompt.codex.1283.$$"
    local out_fb="/tmp/gh-pr-review-out.$$"
    local body_fb="/tmp/gh-pr-review-body.$$"
    rm -f "$prompt_fb" "$out_fb"
    printf 'squatted\n' >"$body_fb"

    run gh_pr_review --ai codex 1283
    assert_failure 1
    assert_output --partial "Could not create comment body temp file under /tmp"

    [ ! -e "$prompt_fb" ]
    [ ! -e "$out_fb" ]
    run cat "$body_fb"
    assert_output "squatted"
    rm -f "$body_fb"
}

# ---------------------------------------------------------------------------
# gh_pr_review() interrupt cleanup (issue #1286 item 2)
#
# Ctrl-C used to unwind the function outright, so none of the `rm -f`
# cascades ran and PROMPT_FILE / AI_OUT / BODY_FILE leaked into /tmp. The
# INT/TERM trap must (a) delete all three — plus the AI CLI's stderr
# capture, moved into the caller's scope by issue #1294 — (b) reset itself
# at every return, since this function is sourced into the user's
# *interactive* shell (a leaked handler would override their Ctrl-C at the
# prompt), and (c) surface 130 to the caller in both shells (#1294).
#
# The harness runs gh_pr_review in a real, separate process group: bash
# sets SIGINT to SIG_IGN for `&`-backgrounded children and then refuses to
# trap it, so a plain `&` would make the test silently vacuous. `setsid
# --fork` returns immediately and leaves the run signalable as a group,
# which is what a terminal Ctrl-C actually does.
# ---------------------------------------------------------------------------

# Stage stub CLIs plus a harness script that drives gh_pr_review to Step 5
# and blocks there with all three temp files allocated. `mktemp` is forced
# to fail so the three land on their deterministic `$$` fallback paths —
# the harness reports its own PID so the test can compute them.
# Args: $1 = shell to run the harness under (bash|zsh).
# Sets: _HARNESS_PID, _HARNESS_PROMPT_FB, _HARNESS_OUT_FB, _HARNESS_BODY_FB,
# _HARNESS_STDERR_FB.
_interrupt_harness_start() {
    local shell_bin="$1"
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    printf '#!/bin/sh\nexit 0\n' >"$stub_dir/gh"
    printf '#!/bin/sh\nexit 1\n' >"$stub_dir/mktemp"
    local marker="$TEST_TEMP_HOME/codex-started"
    rm -f "$marker"
    # The fake CLI announces itself, then blocks — that is the window in
    # which the interrupt has to arrive.
    cat >"$stub_dir/codex" <<EOF
#!/bin/sh
: >"$marker"
sleep 30
EOF
    chmod +x "$stub_dir/gh" "$stub_dir/mktemp" "$stub_dir/codex"

    local pidfile="$TEST_TEMP_HOME/harness.pid"
    local harness="$TEST_TEMP_HOME/harness.sh"
    rm -f "$pidfile"
    cat >"$harness" <<EOF
export DOTFILES_FORCE_INIT=1
export PATH="$stub_dir:\$PATH"
. "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh"
_gh_pr_review_require_ai_cli() { return 0; }
_gh_pr_review_resolve_target_repo() { echo "owner/repo"; }
_gh_pr_review_resolve_pr_number() { echo "1286"; }
_gh_pr_review_fetch_meta() {
    echo '{"state":"OPEN","isDraft":false,"baseRefName":"main","headRefName":"feat"}'
}
_gh_pr_review_preflight_pr_state() { return 0; }
echo \$\$ >"$pidfile"
gh_pr_review --ai codex 1286
echo "FUNC-RC=\$?"
EOF
    _HARNESS_OUT="$TEST_TEMP_HOME/harness.out"

    setsid --fork "$shell_bin" "$harness" </dev/null \
        >"$TEST_TEMP_HOME/harness.out" 2>&1

    local i
    for i in $(seq 1 150); do
        [ -f "$marker" ] && break
        sleep 0.1
    done
    [ -f "$marker" ]

    _HARNESS_PID=$(cat "$pidfile")
    [ -n "$_HARNESS_PID" ]
    _HARNESS_PROMPT_FB="/tmp/gh-pr-review-prompt.codex.1286.$_HARNESS_PID"
    _HARNESS_OUT_FB="/tmp/gh-pr-review-out.$_HARNESS_PID"
    _HARNESS_BODY_FB="/tmp/gh-pr-review-body.$_HARNESS_PID"
    # The AI CLI's stderr capture (issue #1294): allocated by gh_pr_review
    # itself, not by _gh_pr_review_run_ai, so the handler can reach it.
    _HARNESS_STDERR_FB="/tmp/gh-pr-review-stderr.codex.$_HARNESS_PID"
}

# Deliver SIGINT to the whole harness process group (what a terminal
# Ctrl-C does) and wait for the run to finish unwinding.
_interrupt_harness_interrupt() {
    local pgid
    pgid=$(ps -o pgid= -p "$_HARNESS_PID" | tr -d ' ')
    [ -n "$pgid" ]
    kill -INT "-$pgid"
    local i
    for i in $(seq 1 150); do
        kill -0 "$_HARNESS_PID" 2>/dev/null || break
        sleep 0.1
    done
    ! kill -0 "$_HARNESS_PID" 2>/dev/null
}

@test "bash: SIGINT mid-run removes PROMPT_FILE + AI_OUT + BODY_FILE + stderr file" {
    command -v setsid >/dev/null 2>&1 || skip "setsid (util-linux) not available"
    _source_module
    _interrupt_harness_start bash

    # Precondition: the run really did allocate all four before we signal.
    [ -f "$_HARNESS_PROMPT_FB" ]
    [ -f "$_HARNESS_OUT_FB" ]
    [ -f "$_HARNESS_BODY_FB" ]
    [ -f "$_HARNESS_STDERR_FB" ]

    _interrupt_harness_interrupt

    [ ! -e "$_HARNESS_PROMPT_FB" ]
    [ ! -e "$_HARNESS_OUT_FB" ]
    [ ! -e "$_HARNESS_BODY_FB" ]
    # Issue #1294: the CLI's stderr capture used to be a local of
    # _gh_pr_review_run_ai, invisible to the handler, and leaked on Ctrl-C.
    [ ! -e "$_HARNESS_STDERR_FB" ]

    # The run must abort, not resume: Step 7's report would mean Step 6
    # built and posted a PR comment from files the handler just deleted.
    run cat "$_HARNESS_OUT"
    refute_output --partial "[OK] PR #1286 reviewed"
    # bash propagates the handler's `return 130` (128 + SIGINT) as the
    # function's status, so callers can tell an interrupt from a success.
    assert_output --partial "FUNC-RC=130"
}

@test "zsh: SIGINT mid-run removes PROMPT_FILE + AI_OUT + BODY_FILE + stderr file" {
    # The function runs under `emulate -L sh` in zsh; the trap action is a
    # plain `rm -f` + `return`, but "should be fine" is not evidence.
    command -v setsid >/dev/null 2>&1 || skip "setsid (util-linux) not available"
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    _source_module
    _interrupt_harness_start zsh

    [ -f "$_HARNESS_PROMPT_FB" ]
    [ -f "$_HARNESS_OUT_FB" ]
    [ -f "$_HARNESS_BODY_FB" ]
    [ -f "$_HARNESS_STDERR_FB" ]

    _interrupt_harness_interrupt

    [ ! -e "$_HARNESS_PROMPT_FB" ]
    [ ! -e "$_HARNESS_OUT_FB" ]
    [ ! -e "$_HARNESS_BODY_FB" ]
    [ ! -e "$_HARNESS_STDERR_FB" ]

    run cat "$_HARNESS_OUT"
    refute_output --partial "[OK] PR #1286 reviewed"
    # Issue #1294: zsh used to report 0 here. It drops a trap's `return`
    # when the interrupt lands on a subshell that is being *evaluated as a
    # condition* — the old `if ! ( … | tee … ); then`. Step 5 now runs the
    # subshell standalone and reads `$?` on the next line, which propagates
    # the handler's 130 in zsh exactly as it always did in bash.
    assert_output --partial "FUNC-RC=130"
}

@test "bash: INT/TERM traps do not leak to the caller after a successful run" {
    # gh_pr_review is called directly (not via `run`) so the traps it sets
    # are visible in this very shell — `run` would hide them in a subshell
    # and make the assertion vacuous.
    _source_module
    _stub_gh_pr_review_preconditions
    local stub_dir="$TEST_TEMP_HOME/bin"
    printf '#!/bin/sh\necho "[PRAISE] a.sh:1 — ok"\nexit 0\n' >"$stub_dir/codex"
    chmod +x "$stub_dir/codex"

    local before after rc=0
    before=$(trap -p INT; trap -p TERM)
    gh_pr_review --ai codex --no-post-comment 1283 >/dev/null 2>&1 || rc=$?
    after=$(trap -p INT; trap -p TERM)

    [ "$rc" -eq 0 ]
    [ "$before" = "$after" ]
    case "$after" in *PROMPT_FILE*) false ;; esac
}

@test "bash: INT/TERM traps do not leak to the caller on an early-failure return" {
    _source_module
    _stub_gh_pr_review_preconditions
    _stub_mktemp_failing

    local prompt_fb="/tmp/gh-pr-review-prompt.codex.1283.$$"
    local out_fb="/tmp/gh-pr-review-out.$$"
    rm -f "$prompt_fb"
    # Squat the AI_OUT fallback so the run aborts after the trap is armed.
    printf 'squatted\n' >"$out_fb"

    local before after rc=0
    before=$(trap -p INT; trap -p TERM)
    gh_pr_review --ai codex 1283 >/dev/null 2>&1 || rc=$?
    after=$(trap -p INT; trap -p TERM)

    [ "$rc" -eq 1 ]
    [ "$before" = "$after" ]
    case "$after" in *PROMPT_FILE*) false ;; esac
    rm -f "$out_fb" "$prompt_fb"
}

# ---------------------------------------------------------------------------
# gh_pr_review() cleanup under caller `set -e` (codex review, issue #1294
# follow-up)
#
# The Step 5 fix above (standalone subshell + `$?` on the next line) made a
# real, non-interrupt AI-CLI failure errexit-unsafe: with the caller's shell
# under `set -e`, the subshell's non-zero status — read as a bare compound
# command, not guarded by `if`/`&&`/`||` — used to abort the shell right
# there, skipping `_gh_pr_review_disarm_trap` and every `rm -f` below it.
# `gh_pr_review` now saves/restores `-e` around just that one statement.
# Bats' own test-body semantics make a bare failing call untestable
# in-process (the same errexit machinery that's under test would end the
# test itself before any post-call assertion runs) — so, like the SIGINT
# tests above, this drives gh_pr_review from a real subprocess and checks
# survivorship on disk instead of via `$?` in this process.
# ---------------------------------------------------------------------------

@test "bash: real CLI failure under caller's set -e still cleans up temp files" {
    _source_module
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    printf '#!/bin/sh\nexit 0\n' >"$stub_dir/gh"
    printf '#!/bin/sh\nexit 1\n' >"$stub_dir/mktemp"
    printf '#!/bin/sh\necho boom >&2\nexit 4\n' >"$stub_dir/codex"
    chmod +x "$stub_dir/gh" "$stub_dir/mktemp" "$stub_dir/codex"

    local pidfile="$TEST_TEMP_HOME/errexit-harness.pid"
    local harness="$TEST_TEMP_HOME/errexit-harness.sh"
    rm -f "$pidfile"
    cat >"$harness" <<EOF
set -e
export DOTFILES_FORCE_INIT=1
export PATH="$stub_dir:\$PATH"
. "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh"
_gh_pr_review_require_ai_cli() { return 0; }
_gh_pr_review_resolve_target_repo() { echo "owner/repo"; }
_gh_pr_review_resolve_pr_number() { echo "1294"; }
_gh_pr_review_fetch_meta() {
    echo '{"state":"OPEN","isDraft":false,"baseRefName":"main","headRefName":"feat"}'
}
_gh_pr_review_preflight_pr_state() { return 0; }
echo \$\$ >"$pidfile"
gh_pr_review --ai codex --no-post-comment 1294
EOF

    run bash "$harness"
    # Before the fix: `set -e` aborted mid-function, so the CLI's own exit
    # code (4) never made it back out through `return "$_rc"` — the shell
    # just died with whatever status the aborting subshell carried, which
    # is indistinguishable from this at the `run` level. The real signal is
    # cleanup, checked below: with the bug, none of it ran.
    assert_failure 4

    local pid prompt_fb out_fb body_fb stderr_fb
    pid=$(cat "$pidfile")
    [ -n "$pid" ]
    prompt_fb="/tmp/gh-pr-review-prompt.codex.1294.$pid"
    out_fb="/tmp/gh-pr-review-out.$pid"
    body_fb="/tmp/gh-pr-review-body.$pid"
    stderr_fb="/tmp/gh-pr-review-stderr.codex.$pid"

    [ ! -e "$prompt_fb" ]
    [ ! -e "$out_fb" ]
    [ ! -e "$body_fb" ]
    # stderr file is deliberately kept on a genuine CLI failure (existing
    # behaviour, unrelated to this fix) — assert it exists, not that it's
    # gone, then clean it up ourselves.
    [ -e "$stderr_fb" ]
    rm -f "$prompt_fb" "$out_fb" "$body_fb" "$stderr_fb"
}

# ---------------------------------------------------------------------------
# Token estimator (issue #1474: takes a byte count, not a path)
# ---------------------------------------------------------------------------

@test "estimate_tokens: tiny byte count rounds up to floor 1000" {
    _source_module
    run _gh_pr_review_estimate_tokens 2
    assert_success
    assert_output "1000"
}

@test "estimate_tokens: large byte count rounds to nearest 500" {
    _source_module
    # 12 000 bytes → 3000 tokens.
    run _gh_pr_review_estimate_tokens 12000
    assert_success
    # Allow a ±500 wobble since the rounding boundary is on 500.
    [[ "$output" =~ ^[23][05]00$ ]]
}

# ---------------------------------------------------------------------------
# Token estimate is decoupled from PROMPT_FILE's lifetime (issue #1474)
# See gh_pr_review.sh — the measurement moved to just after the prompt is
# built; that comment is the single home for why.
# ---------------------------------------------------------------------------

@test "gh_pr_review: PROMPT_FILE vanishing before Step 6 does not zero the token estimate" {
    _source_module
    _stub_gh_pr_review_preconditions
    _gh_pr_review_resolve_pr_number() { echo "1474"; }
    # A prompt far above the floor, so a regression to the old
    # re-read-from-disk path is unmistakable (30000 vs 1000).
    _gh_pr_review_build_prompt() {
        yes "abcd1234" | head -c 120000 >"$2"
    }
    # Capture the tokens argument ($5) Step 6 hands the body builder — the
    # value that ends up in the PR comment's ai-metrics footer.
    local tokfile="$TEST_TEMP_HOME/tokens.txt"
    _gh_pr_review_build_comment_body() { printf '%s\n' "$5" >"$tokfile"; }

    # `_stub_gh_noop` (via the preconditions helper) already created this
    # directory and put it on PATH.
    local stub_dir="$TEST_TEMP_HOME/bin"
    # The CLI itself succeeds, but the prompt file is gone by the time it
    # returns — the #1474 symptom, root cause still open.
    cat >"$stub_dir/codex" <<'EOF'
#!/bin/sh
rm -f /tmp/gh-pr-review-prompt.codex.1474.*
echo "[PRAISE] a.sh:1 — ok"
exit 0
EOF
    chmod +x "$stub_dir/codex"

    run gh_pr_review --ai codex --no-post-comment 1474
    assert_success

    # 120 000 bytes / 4 = 30 000 tokens — the size measured before the file
    # disappeared, not the floor-1000 fallback.
    run cat "$tokfile"
    assert_output "30000"
}

@test "gh_pr_review: unreadable prompt file at measure time warns instead of silently reporting 0" {
    _source_module
    _stub_gh_pr_review_preconditions
    _gh_pr_review_resolve_pr_number() { echo "1474"; }
    # Report success while leaving no file behind — the only way the early
    # measurement can fail, and the case the old `|| echo 0` hid.
    _gh_pr_review_build_prompt() {
        rm -f "$2"
        return 0
    }

    # No codex stub is needed: Step 5 redirects the (now missing) prompt file
    # into the CLI, so the run aborts at the redirection before any binary is
    # execed. This test asserts only that the warning fired first.
    run gh_pr_review --ai codex --no-post-comment 1474
    assert_output --partial "Could not read prompt file for the token estimate"
}

# ---------------------------------------------------------------------------
# Comment body builder — required SSOT markers
# ---------------------------------------------------------------------------

@test "build_comment_body: contains ai-review + ai-metrics markers" {
    _source_module
    local out="$TEST_TEMP_HOME/body.md"
    local ai_out="$TEST_TEMP_HOME/ai-out.txt"
    printf '[BLOCKER] foo.sh:1 — bar\n' >"$ai_out"
    _gh_pr_review_build_comment_body "$out" codex thorough "$ai_out" 2500 2.5 7
    run cat "$out"
    assert_success
    assert_output --partial "AI Review · codex · --review=thorough"
    assert_output --partial "<!-- ai-review:codex -->"
    assert_output --partial "<!-- /ai-review:codex -->"
    assert_output --partial "<!-- ai-metrics:gh-pr-review -->"
    assert_output --partial "📊 ~2500 tokens · 👤 ~2.5 h · 🤖 ~7 min"
    assert_output --partial "[BLOCKER] foo.sh:1"
}

@test "human_h baseline: each preset returns the documented value" {
    _source_module
    run _gh_pr_review_human_h quick;       assert_output "0.3"
    run _gh_pr_review_human_h default;     assert_output "1.0"
    run _gh_pr_review_human_h thorough;    assert_output "2.5"
    run _gh_pr_review_human_h security;    assert_output "1.5"
    run _gh_pr_review_human_h performance; assert_output "1.5"
}

# ---------------------------------------------------------------------------
# Post-comment guards (skip paths) + soft-fail
# ---------------------------------------------------------------------------

@test "post_comment: --no-post-comment (post=0) → skipped, exit 0" {
    _source_module
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    run _gh_pr_review_post_comment 99 owner/repo "$body" 0
    assert_success
    assert_output --partial "skipped (--no-post-comment)"
}

@test "post_comment: GH_DISABLE_AI_METRICS=1 → entire comment skipped, exit 0" {
    _source_module
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    GH_DISABLE_AI_METRICS=1 run _gh_pr_review_post_comment 99 owner/repo "$body" 1
    assert_success
    assert_output --partial "skipped (GH_DISABLE_AI_METRICS=1)"
}

@test "post_comment: gh failure → soft-fail exit 0 + [WARN] line" {
    _source_module
    # Stage a stub `gh` that always fails so the post step exercises its
    # soft-fail branch. The function must NOT propagate the non-zero
    # exit — the AI output is already on the user's stdout.
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/bin/sh
echo "simulated gh failure" >&2
exit 1
EOF
    chmod +x "$stub_dir/gh"
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    PATH="$stub_dir:$PATH" run _gh_pr_review_post_comment 99 owner/repo "$body" 1
    assert_success
    assert_output --partial "[WARN] post failed"
}

@test "post_comment: gh success → URL returned, exit 0" {
    _source_module
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/bin/sh
echo "https://github.com/owner/repo/pull/99#issuecomment-1"
exit 0
EOF
    chmod +x "$stub_dir/gh"
    local body="$TEST_TEMP_HOME/body.md"
    printf 'body\n' >"$body"
    PATH="$stub_dir:$PATH" run _gh_pr_review_post_comment 99 owner/repo "$body" 1
    assert_success
    assert_output --partial "issuecomment-1"
}

# ---------------------------------------------------------------------------
# _gh_pr_review_run_ai — agy transport (issue #1244 / PR #1245 review)
# ---------------------------------------------------------------------------

# Stub `agy` so the run_ai dispatcher can exercise the --print value-argument
# path without invoking the real Antigravity CLI. Echoes its own argv back
# so tests can assert on exactly what the function passed as $1.
_stub_agy_echo() {
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/agy" <<'EOF'
#!/bin/sh
# $1 is --print; $2 is the prompt value this test asserts on.
echo "agy called with: $2"
exit 0
EOF
    chmod +x "$stub_dir/agy"
    export PATH="$stub_dir:$PATH"
}

@test "run_ai agy: small prompt → passed as value argument, not stdin" {
    _source_module
    _stub_agy_echo
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"
    run _gh_pr_review_run_ai agy "$f"
    assert_success
    assert_output --partial "agy called with: review this diff"
}

@test "run_ai agy: prompt at/over MAX_ARG_STRLEN (131072 bytes) → fails with clear message, agy never invoked" {
    _source_module
    _stub_agy_echo
    local f="$TEST_TEMP_HOME/big.txt"
    # 131072 bytes exactly — the guard's `-ge` boundary.
    head -c 131072 /dev/zero | tr '\0' 'x' >"$f"
    run _gh_pr_review_run_ai agy "$f"
    assert_failure
    assert_output --partial "over the 131072-byte argv limit"
    refute_output --partial "agy called with"
}

@test "run_ai agy: unreadable prompt file → fails, does not silently swallow the read error" {
    _source_module
    _stub_agy_echo
    local f="$TEST_TEMP_HOME/unreadable.txt"
    printf 'x' >"$f"
    chmod 000 "$f"
    run _gh_pr_review_run_ai agy "$f"
    assert_failure
    refute_output --partial "agy called with"
    chmod 644 "$f" # restore so bats can clean up TEST_TEMP_HOME
}

# ---------------------------------------------------------------------------
# _gh_pr_review_run_ai — opencode transport (issue #1334)
# ---------------------------------------------------------------------------

_stub_opencode_echo() {
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/opencode" <<'EOF'
#!/bin/sh
printf 'opencode args:'
for arg in "$@"; do
    printf ' [%s]' "$arg"
done
printf '\n'
exit 0
EOF
    chmod +x "$stub_dir/opencode"
    export PATH="$stub_dir:$PATH"
}

@test "run_ai opencode: internal mode uses CodeLLMPro and attaches prompt file" {
    _source_module
    _dotfiles_setup_mode() { echo internal; }
    _stub_opencode_echo
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    run _gh_pr_review_run_ai opencode "$f"
    assert_success
    assert_output --partial "opencode args: [run]"
    assert_output --partial "[--model] [codemate/CodeLLMPro]"
    assert_output --partial "[--dir]"
    assert_output --partial "[--file] [$f]"
}

@test "run_ai opencode: non-internal mode refuses without invoking opencode" {
    _source_module
    _dotfiles_setup_mode() { echo external; }
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/opencode" <<'EOF'
#!/bin/sh
echo "SHOULD_NOT_RUN"
exit 0
EOF
    chmod +x "$stub_dir/opencode"
    export PATH="$stub_dir:$PATH"
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    run _gh_pr_review_run_ai opencode "$f"
    assert_failure 1
    assert_output --partial "--ai opencode is internal-PC only"
    refute_output --partial "SHOULD_NOT_RUN"
}

@test "run_ai opencode: relative writes are isolated outside caller working tree" {
    _source_module
    _dotfiles_setup_mode() { echo internal; }
    local repo="$TEST_TEMP_HOME/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    printf 'before\n' >"$repo/tracked.txt"
    git -C "$repo" add tracked.txt
    git -C "$repo" commit -q -m "seed"

    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/opencode" <<'EOF'
#!/bin/sh
dir=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "--dir" ]; then
        dir="$arg"
    fi
    prev="$arg"
done
printf 'opencode dir: %s\n' "$dir"
printf 'agent write\n' >"$dir/tracked.txt"
echo "review output"
exit 0
EOF
    chmod +x "$stub_dir/opencode"
    export PATH="$stub_dir:$PATH"

    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    (
        cd "$repo"
        run _gh_pr_review_run_ai opencode "$f"
        assert_success
        assert_output --partial "review output"
        assert_equal "$(cat tracked.txt)" "before"
        dir="$(printf '%s\n' "$output" | sed -n 's/^opencode dir: //p')"
        [ -n "$dir" ]
        [ ! -d "$dir" ]
    )
}

# ---------------------------------------------------------------------------
# _gh_pr_review_run_ai — hermes transport (issue #1377, corrected in #1452:
# hermes has no `exec` subcommand — the one-shot flag is `-z` and it takes the
# prompt as a value argument, so it shares agy's MAX_ARG_STRLEN guard)
# ---------------------------------------------------------------------------

_stub_hermes_echo() {
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/hermes" <<'EOF'
#!/bin/sh
printf 'hermes args:'
for arg in "$@"; do
    printf ' [%s]' "$arg"
done
printf '\n'
exit 0
EOF
    chmod +x "$stub_dir/hermes"
    export PATH="$stub_dir:$PATH"
}

@test "run_ai hermes: small prompt → passed as value argument, not stdin" {
    _source_module
    _dotfiles_setup_mode() { echo internal; }
    _stub_hermes_echo
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    run _gh_pr_review_run_ai hermes "$f"
    assert_success
    assert_output --partial "hermes args: [-z] [review this diff]"
    refute_output --partial "[--file]"
    refute_output --partial "[exec]"
}

@test "run_ai hermes: prompt one byte under MAX_ARG_STRLEN (131071 bytes) → still succeeds, hermes invoked" {
    _source_module
    _dotfiles_setup_mode() { echo internal; }
    _stub_hermes_echo
    local f="$TEST_TEMP_HOME/almost-big.txt"
    # 131071 bytes — one under the guard's `-ge 131072` boundary.
    head -c 131071 /dev/zero | tr '\0' 'x' >"$f"

    run _gh_pr_review_run_ai hermes "$f"
    assert_success
    assert_output --partial "hermes args: [-z]"
    refute_output --partial "over the 131072-byte argv limit"
}

@test "run_ai hermes: prompt at/over MAX_ARG_STRLEN (131072 bytes) → fails with clear message, hermes never invoked" {
    _source_module
    _dotfiles_setup_mode() { echo internal; }
    _stub_hermes_echo
    local f="$TEST_TEMP_HOME/big.txt"
    # 131072 bytes exactly — the guard's `-ge` boundary.
    head -c 131072 /dev/zero | tr '\0' 'x' >"$f"

    run _gh_pr_review_run_ai hermes "$f"
    assert_failure
    assert_output --partial "over the 131072-byte argv limit"
    refute_output --partial "hermes args:"
}

@test "run_ai hermes: non-internal mode refuses without invoking hermes" {
    _source_module
    _dotfiles_setup_mode() { echo external; }
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/hermes" <<'EOF'
#!/bin/sh
echo "SHOULD_NOT_RUN"
exit 0
EOF
    chmod +x "$stub_dir/hermes"
    export PATH="$stub_dir:$PATH"
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    run _gh_pr_review_run_ai hermes "$f"
    assert_failure 1
    assert_output --partial "--ai hermes is internal-PC only"
    refute_output --partial "SHOULD_NOT_RUN"
}

# ---------------------------------------------------------------------------
# _gh_pr_review_run_ai — stderr temp file uses the SSOT allocator (issue #1286
# item 1). It used to call `mktemp` raw, so an unwritable /tmp aborted the
# whole review even though the module already had a safe fallback; and the
# fallback it does now use has to keep #1283's refuse-don't-clobber contract.
# ---------------------------------------------------------------------------

@test "run_ai: mktemp failure falls back to the safe \$\$ stderr path instead of aborting" {
    _source_module
    _stub_agy_echo
    _stub_mktemp_failing
    local fallback="/tmp/gh-pr-review-stderr.agy.$$"
    rm -f "$fallback"
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    run _gh_pr_review_run_ai agy "$f"
    assert_success
    assert_output --partial "agy called with: review this diff"
    # The success path still cleans the stderr file up after itself.
    [ ! -e "$fallback" ]
}

@test "run_ai: symlink pre-planted at the stderr fallback path → refuses, victim untouched" {
    _source_module
    _stub_agy_echo
    _stub_mktemp_failing
    local victim="$TEST_TEMP_HOME/victim.txt"
    printf 'original\n' >"$victim"
    local fallback="/tmp/gh-pr-review-stderr.agy.$$"
    rm -f "$fallback"
    ln -s "$victim" "$fallback"
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    run _gh_pr_review_run_ai agy "$f"
    assert_failure 1
    assert_output --partial "Could not create stderr temp file under /tmp"
    # Aborts before invoking the CLI — nothing is written through the link.
    refute_output --partial "agy called with"
    [ -L "$fallback" ]
    run cat "$victim"
    assert_output "original"
    rm -f "$fallback"
}

@test "run_ai: caller-supplied stderr path (\$4) is used instead of self-allocating" {
    # Issue #1294 — gh_pr_review now allocates this file itself so its
    # INT/TERM handler can delete it on Ctrl-C. A self-allocated path was a
    # local of this helper and leaked. Direct callers that pass nothing keep
    # the self-allocating behaviour (the two tests above cover that).
    _source_module
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    printf '#!/bin/sh\necho boom >&2\nexit 3\n' >"$stub_dir/agy"
    chmod +x "$stub_dir/agy"
    export PATH="$stub_dir:$PATH"
    # mktemp fails, so a self-allocation would land on this predictable
    # path — asserting it never appears proves $4 short-circuited it.
    _stub_mktemp_failing
    local self_fb="/tmp/gh-pr-review-stderr.agy.$$"
    rm -f "$self_fb"

    local caller_path="$TEST_TEMP_HOME/caller-stderr.txt"
    : >"$caller_path"
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"

    run _gh_pr_review_run_ai agy "$f" "" "$caller_path"
    assert_failure 3
    assert_output --partial "full stderr saved to: $caller_path"
    [ ! -e "$self_fb" ]
    run cat "$caller_path"
    assert_output --partial "boom"
}

# ---------------------------------------------------------------------------
# zsh regression coverage for the noclobber fallback (issue #1286 item 4)
#
# This module is sourced by both bash/main.bash and zsh/main.zsh, but the
# #1283 symlink-rejection hardening was only ever exercised under bash —
# bats itself runs in bash, and the cases above call the allocator
# in-process. These mirror the key bash cases through `run_in_zsh`, which
# sources the real zsh/main.zsh (auto-loading this module) under `zsh -f`.
#
# Constraints of the harness worth knowing when editing these:
#   - the command string is wrapped in single quotes on the bats side, so
#     it may not contain single quotes itself;
#   - `$$` expands inside the zsh subprocess, so the fallback path carries
#     *its* PID, not the bats PID — each case cleans up its own path;
#   - zsh's `trap -p` prints nothing, so trap state is inspected with a
#     bare `trap` redirected to a file (a command substitution would come
#     back empty because zsh clears traps in subshells).
# ---------------------------------------------------------------------------

# Shared zsh preamble: stage a always-failing `mktemp` on PATH (forcing the
# allocator onto its `$$` fallback) and export `$fallback` for the case body.
_zsh_mktemp_stub_preamble() {
    cat <<'EOF'
mkdir -p "$HOME/bin"
printf "#!/bin/sh\nexit 1\n" > "$HOME/bin/mktemp"
chmod +x "$HOME/bin/mktemp"
export PATH="$HOME/bin:$PATH"
rehash 2>/dev/null || true
fallback="/tmp/gh-pr-review-out.$$"
EOF
}

@test "zsh: mktemp_safe refuses a pre-planted symlink at the fallback path, victim untouched" {
    run_in_zsh "$(_zsh_mktemp_stub_preamble)"'
        victim="$HOME/victim.txt"
        printf "original\n" > "$victim"
        rm -f "$fallback"
        ln -s "$victim" "$fallback"
        if _gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX"; then
            echo "ALLOCATED"
        else
            echo "REFUSED"
        fi
        [ -L "$fallback" ] && echo "LINK_INTACT"
        printf "victim=%s\n" "$(cat "$victim")"
        rm -f "$fallback"
    '
    assert_success
    assert_output --partial "REFUSED"
    refute_output --partial "ALLOCATED"
    assert_output --partial "LINK_INTACT"
    assert_output --partial "victim=original"
}

@test "zsh: mktemp_safe refuses a pre-planted regular file at the fallback path, content untouched" {
    run_in_zsh "$(_zsh_mktemp_stub_preamble)"'
        rm -f "$fallback"
        printf "squatted\n" > "$fallback"
        if _gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX"; then
            echo "ALLOCATED"
        else
            echo "REFUSED"
        fi
        printf "content=%s\n" "$(cat "$fallback")"
        rm -f "$fallback"
    '
    assert_success
    assert_output --partial "REFUSED"
    refute_output --partial "ALLOCATED"
    assert_output --partial "content=squatted"
}

@test "zsh: mktemp_safe on a clear fallback path → exclusive create succeeds" {
    run_in_zsh "$(_zsh_mktemp_stub_preamble)"'
        rm -f "$fallback"
        p=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX")
        [ "$?" -eq 0 ] && echo "ALLOCATED"
        [ "$p" = "$fallback" ] && echo "PATH_IS_FALLBACK"
        [ -f "$p" ] && echo "IS_REGULAR_FILE"
        [ -L "$p" ] && echo "IS_SYMLINK"
        rm -f "$fallback"
    '
    assert_success
    assert_output --partial "ALLOCATED"
    assert_output --partial "PATH_IS_FALLBACK"
    assert_output --partial "IS_REGULAR_FILE"
    refute_output --partial "IS_SYMLINK"
}

@test "zsh: mktemp_safe fallback file is mode 0600 even under a permissive umask" {
    run_in_zsh "$(_zsh_mktemp_stub_preamble)"'
        rm -f "$fallback"
        umask 022
        p=$(_gh_pr_review_mktemp_safe "/tmp/gh-pr-review-out.XXXXXX")
        printf "mode=%s\n" "$(stat -c "%a" "$p")"
        rm -f "$fallback"
    '
    assert_success
    assert_output --partial "mode=600"
}

@test "zsh: INT/TERM traps do not leak to the caller after a successful run" {
    # zsh runs gh_pr_review under `emulate -L sh`; confirm the trap reset
    # behaves there too rather than assuming sh emulation matches bash.
    run_in_zsh '
        mkdir -p "$HOME/bin"
        printf "#!/bin/sh\nexit 0\n" > "$HOME/bin/gh"
        printf "#!/bin/sh\necho REVIEW-OK\nexit 0\n" > "$HOME/bin/codex"
        chmod +x "$HOME/bin/gh" "$HOME/bin/codex"
        export PATH="$HOME/bin:$PATH"
        rehash 2>/dev/null || true
        _gh_pr_review_resolve_target_repo() { echo "owner/repo"; }
        _gh_pr_review_resolve_pr_number() { echo "1286"; }
        _gh_pr_review_fetch_meta() {
            echo "{\"state\":\"OPEN\",\"isDraft\":false,\"baseRefName\":\"main\",\"headRefName\":\"feat\"}"
        }
        _gh_pr_review_preflight_pr_state() { return 0; }
        gh_pr_review --ai codex --no-post-comment 1286 >/dev/null 2>&1
        echo "rc=$?"
        trap > "$HOME/traps.after" 2>&1
        if grep -q PROMPT_FILE "$HOME/traps.after"; then
            echo "TRAP_LEAKED"
        else
            echo "TRAP_CLEAN"
        fi
    '
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "TRAP_CLEAN"
    refute_output --partial "TRAP_LEAKED"
}
