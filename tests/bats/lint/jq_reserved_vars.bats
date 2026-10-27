#!/usr/bin/env bats
# tests/bats/lint/jq_reserved_vars.bats
# Issue #2302 — jq 1.6 lexes its keywords (label, def, if, reduce, ...) as
# keyword tokens, so `as $label` or `--arg label` is a compile error there
# ("syntax error, unexpected label, expecting IDENT"). jq 1.7+ accepts them,
# so every other test passes on a 1.7 box and only this scan catches it.
# Supersedes the ai_usage.sh-only check from #2052 with a repo-wide scan.
# lib/ is the vendored bats-core submodule and stays out of scope.

load '../test_helper'

JQ_KEYWORDS='label|def|if|then|elif|else|end|as|reduce|foreach|try|catch|import|include|and|or|not|__loc__'
JQ_KEYWORD_VAR_ERE="(as[[:space:]]+[\$]|--arg(json)?[[:space:]]+)(${JQ_KEYWORDS})([^A-Za-z0-9_]|\$)"

@test "no shell code binds a jq variable named after a jq 1.6 keyword" {
    # Positive control: the pattern must catch keyword bindings and spare
    # names that only start with a keyword, or the scan below proves nothing.
    run grep -cE "$JQ_KEYWORD_VAR_ERE" <<'EOF'
    .[1] as $label | .
    jq --arg label x
    jq --argjson if 1 '.'
    .[1] as $wslabel | .
    .[1] as $labels | .
    jq --arg endpoint x
EOF
    assert_output "3"

    run grep -rnE "$JQ_KEYWORD_VAR_ERE" \
        --include='*.sh' --include='*.bash' --include='*.zsh' --include='*.bats' \
        --exclude-dir=lib --exclude-dir=.git --exclude=jq_reserved_vars.bats \
        "${_BATS_REAL_DOTFILES_ROOT}"
    assert_output ""
}
