#!/usr/bin/env bats
# tests/bats/functions/gh_issue_review.bats
# gh_issue_review engine (#2381) with `gh` and the AI CLIs stubbed: material
# filtering, perspective choice, the shared output gate, required
# --repo/--host, the fail-closed leak guard, --workdir transport and the
# body-hash marker. No live GitHub call, no real AI CLI.
load '../test_helper'

setup() {
    setup_isolated_home
    STUB="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB"
    export GH_LOG="$TEST_TEMP_HOME/gh.log" POSTED="$TEST_TEMP_HOME/posted.md"
    export GH_FIXTURE="$TEST_TEMP_HOME/issue.json" GH_LOGIN="me"
    export AI_SEEN="$TEST_TEMP_HOME/ai"
    mkdir -p "$AI_SEEN"
    export AI_REPLY='[FOLLOW-UP] 범위 — 테스트 이름 없음
판정: 우려있음'
    export DOTFILES_SETUP_MODE=external LEAK_PATTERNS_ERE=""
    cat >"$GH_FIXTURE" <<'EOF'
{"title":"feat(engine): add issue review","body":"Body text","comments":[
 {"author":{"login":"alice"},"createdAt":"2026-01-01T00:00:00Z","body":"human comment"},
 {"author":{"login":"me"},"createdAt":"2026-01-02T00:00:00Z","body":"<!-- ai-issue-review:claude:000000000000 -->\nold ai review"}]}
EOF
    cat >"$STUB/gh" <<'EOF'
#!/bin/bash
echo "GH_HOST=$GH_HOST $*" >>"$GH_LOG"
case "$1 $2" in
"issue view")
    jq_expr=""
    while [ "$#" -gt 0 ]; do [ "$1" = "--jq" ] && jq_expr="$2"; shift; done
    jq -r "$jq_expr" "$GH_FIXTURE" ;;
"api user") echo "$GH_LOGIN" ;;
"issue comment")
    while [ "$#" -gt 0 ]; do [ "$1" = "--body-file" ] && cp "$2" "$POSTED"; shift; done
    echo "https://github.com/o/r/issues/7#issuecomment-1" ;;
*) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
EOF
    # codex / opencode stubs record cwd, argv and the prompt they were given.
    cat >"$STUB/codex" <<'EOF'
#!/bin/sh
pwd -P >"$AI_SEEN/cwd"
cat >"$AI_SEEN/prompt"
printf '%s\n' "$AI_REPLY"
EOF
    cat >"$STUB/opencode" <<'EOF'
#!/bin/sh
pwd -P >"$AI_SEEN/cwd"
: >"$AI_SEEN/args"
for a in "$@"; do printf '[%s]\n' "$a" >>"$AI_SEEN/args"; done
prev=""
for a in "$@"; do [ "$prev" = "--file" ] && cp "$a" "$AI_SEEN/prompt" && echo "$a" >"$AI_SEEN/file"; prev="$a"; done
printf '%s\n' "$AI_REPLY"
EOF
    chmod +x "$STUB/gh" "$STUB/codex" "$STUB/opencode"
    export PATH="$STUB:$PATH" DOTFILES_OPENCODE_REVIEW_MODEL="example-corp/example-model"
    # shellcheck disable=SC1090
    DOTFILES_FORCE_INIT=1 source "${_BATS_REAL_SHELL_COMMON:?}/functions/gh_issue_review.sh"
    WD="$TEST_TEMP_HOME/wd"
    mkdir -p "$WD"
    git -C "$WD" init -q -b feature
    git -C "$WD" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
    WD_REAL=$(cd -P "$WD" && pwd)
}

teardown() {
    teardown_isolated_home
}

_hash() { printf '%s' "Body text" | sha256sum | cut -c1-12; }

@test "args: missing --repo or --host is refused with rc 2, no gh call" {
    run _gh_issue_review_main --ai codex --host github.com 7
    assert_failure 2
    assert_output --partial "--repo <owner/repo> is required"
    run _gh_issue_review_main --ai codex --repo o/r 7
    assert_failure 2
    assert_output --partial "--host <host> is required"
    [ ! -s "$GH_LOG" ]
}

@test "material: marker comments are dropped, human comments kept" {
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_success
    grep -q "human comment" "$AI_SEEN/prompt"
    grep -q "Body text" "$AI_SEEN/prompt"
    ! grep -q "old ai review" "$AI_SEEN/prompt" || false
}

@test "perspective: chosen from the conventional-commit prefix" {
    run _gh_issue_review_perspective "feat(engine): x"
    assert_output feat
    run _gh_issue_review_perspective "Fix!: y"
    assert_output fix
    run _gh_issue_review_perspective "docs: z"
    assert_output common
    run _gh_issue_review_perspective "feature request"
    assert_output common
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_success
    grep -q "Perspective: new feature" "$AI_SEEN/prompt"
}

@test "output gate: exit 0 without a 판정 line (usage-limit notice) posts nothing, rc != 0" {
    AI_REPLY="You've hit your usage limit. Try again later." \
        run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_failure 1
    assert_output --partial "no verdict line"
    [ ! -e "$POSTED" ]
    ! grep -q "issue comment" "$GH_LOG" || false
}

@test "post: body-hash marker pair, review basis and metrics footer" {
    run _gh_issue_review_main --ai codex --repo o/r --host github.com --workdir "$WD" 7
    assert_success
    assert_output --partial "[OK] issue #7 reviewed by codex"
    local h
    h=$(_hash)
    grep -qxF "<!-- ai-issue-review:codex:$h -->" "$POSTED"
    grep -qxF "<!-- /ai-issue-review:codex:$h -->" "$POSTED"
    grep -q '^리뷰 기준: `feature@[0-9a-f]\{7,\}`$' "$POSTED"
    grep -q "<!-- ai-metrics:gh-issue-review -->" "$POSTED"
    grep -q "판정: 우려있음" "$POSTED"
}

@test "gh: every call pins GH_HOST and every issue call carries --repo" {
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_success
    ! grep -v '^GH_HOST=github.com ' "$GH_LOG" || false
    ! grep '^GH_HOST=github.com issue' "$GH_LOG" | grep -v -- '--repo o/r' || false
}

@test "dedupe: same ai + same body hash by this login skips without running the CLI" {
    local h
    h=$(_hash)
    jq --arg m "<!-- ai-issue-review:codex:$h -->" \
        '.comments += [{"author":{"login":"me"},"createdAt":"x","body":$m}]' \
        "$GH_FIXTURE" >"$GH_FIXTURE.new" && mv "$GH_FIXTURE.new" "$GH_FIXTURE"
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_success
    assert_output --partial "[SKIP] issue #7 already reviewed by codex"
    [ ! -e "$AI_SEEN/prompt" ]
    # Another account's marker does not count (#1639).
    GH_LOGIN=other run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_success
    assert_output --partial "[OK] issue #7"
}

@test "leak guard: internal + github.com + pattern hit -> not posted, rc 3, held file kept" {
    export DOTFILES_SETUP_MODE=internal LEAK_PATTERNS_ERE='우려있음'
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_failure 3
    assert_output --partial "leak-guard"
    assert_output --partial "held comment saved to:"
    [ ! -e "$POSTED" ]
    local held
    held=$(printf '%s\n' "$output" | sed -n 's/.*held comment saved to: //p')
    [ -s "$held" ]
    rm -f "$held"
}

@test "leak guard: internal + github.com + empty LEAK_PATTERNS_ERE -> not posted" {
    export DOTFILES_SETUP_MODE=internal LEAK_PATTERNS_ERE=""
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_failure 3
    assert_output --partial "LEAK_PATTERNS_ERE is empty"
    [ ! -e "$POSTED" ]
}

@test "leak guard: an unloadable setup-mode reader counts as internal" {
    unset -f _dotfiles_setup_mode_is _dotfiles_setup_mode
    export DOTFILES_SETUP_MODE=external LEAK_PATTERNS_ERE=""
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_failure 3
    [ ! -e "$POSTED" ]
}

@test "leak guard: external mode or a GHES target is not checked" {
    export DOTFILES_SETUP_MODE=external LEAK_PATTERNS_ERE='우려있음'
    run _gh_issue_review_main --ai codex --repo o/r --host github.com 7
    assert_success
    rm -f "$POSTED"
    export DOTFILES_SETUP_MODE=internal LEAK_PATTERNS_ERE=""
    run _gh_issue_review_main --ai codex --repo o/r --host ghes.example.invalid 7
    assert_success
    [ -s "$POSTED" ]
}

@test "workdir: the CLI runs in --workdir and the caller's cwd is unchanged" {
    local before="$PWD"
    _gh_issue_review_main --ai codex --repo o/r --host github.com --workdir "$WD" 7 >/dev/null
    [ "$PWD" = "$before" ]
    [ "$(cat "$AI_SEEN/cwd")" = "$WD_REAL" ]
}

@test "workdir: opencode gets it as --dir, the prompt copy lives inside and is removed" {
    run _gh_issue_review_main --ai opencode --repo o/r --host github.com --workdir "$WD" 7
    assert_success
    grep -qxF "[--dir]" "$AI_SEEN/args"
    grep -qxF "[$WD_REAL]" "$AI_SEEN/args"
    grep -qxF "[첨부 파일의 지시사항에 따라 이슈를 리뷰해줘.]" "$AI_SEEN/args"
    case "$(cat "$AI_SEEN/file")" in "$WD_REAL"/.ai-cli-prompt.*) ;; *) false ;; esac
    [ ! -e "$(cat "$AI_SEEN/file")" ]
    grep -q "Body text" "$AI_SEEN/prompt"
}

@test "run_ai without workdir (PR path): opencode keeps a private temp --dir and the PR sentence" {
    local f="$TEST_TEMP_HOME/prompt.txt"
    printf 'review this diff' >"$f"
    run _gh_pr_review_run_ai opencode "$f"
    assert_success
    grep -qxF "[첨부 파일의 지시사항에 따라 위 PR diff를 리뷰해줘.]" "$AI_SEEN/args"
    ! grep -qxF "[$WD_REAL]" "$AI_SEEN/args" || false
    case "$(cat "$AI_SEEN/file")" in */gh-pr-review-opencode.*/prompt.md) ;; *) false ;; esac
}

@test "help: -h prints usage without any gh call" {
    run _gh_issue_review_main -h
    assert_success
    assert_output --partial "gh-issue-review --ai <ai> --repo <owner/repo> --host <host>"
    [ ! -s "$GH_LOG" ]
}

@test "zsh: the engine posts under zsh too (emulate -L sh paths)" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -fc "export SHELL_COMMON='${_BATS_REAL_SHELL_COMMON}'
        DOTFILES_FORCE_INIT=1 . \"\$SHELL_COMMON/functions/gh_issue_review.sh\"
        _gh_issue_review_main --ai codex --repo o/r --host github.com --workdir '$WD' 7
        echo \"rc=\$? pwd=\$PWD\""
    assert_success
    assert_output --partial "[OK] issue #7 reviewed by codex"
    assert_output --partial "rc=0 pwd=$PWD"
    [ "$(cat "$AI_SEEN/cwd")" = "$WD_REAL" ]
}
