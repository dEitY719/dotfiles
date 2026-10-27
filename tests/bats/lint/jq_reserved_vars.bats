#!/usr/bin/env bats
# tests/bats/lint/jq_reserved_vars.bats
# Issue #2302 — jq 1.6 lexes its keywords (label, def, if, reduce, ...) as
# keyword tokens, so `as $label` or `--arg label` is a compile error there
# ("syntax error, unexpected label, expecting IDENT"). jq 1.7+ accepts them,
# so every other test passes on a 1.7 box and only this scan catches it.
# Supersedes the ai_usage.sh-only check from #2052 with a repo-wide scan.
# The vendored bats-* submodules stay out of scope (not every lib/ — shell-common/lib etc. are ours).

load '../test_helper'

# The jq 1.6 lexer's keyword list (src/lexer.l). `not` is a builtin, not a keyword.
JQ_KEYWORDS='label|def|if|then|elif|else|end|as|reduce|foreach|try|catch|import|include|module|and|or|__loc__'
# Binding sites: `as $kw`, `--arg/--argjson/--slurpfile/--rawfile kw`, `def f($kw)` / `def f(a; $kw)`.
JQ_BINDING='(^|[^A-Za-z0-9_])as[[:space:]]+[$]|--(arg|argjson|slurpfile|rawfile)[[:space:]]+|def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[(]([^)]*;)?[[:space:]]*[$]?'
JQ_KEYWORD_VAR_ERE="(${JQ_BINDING})(${JQ_KEYWORDS})([^A-Za-z0-9_]|\$)"

@test "no shell code binds a jq variable named after a jq 1.6 keyword" {
    # Positive control: the pattern must catch keyword bindings and spare
    # names that only start with a keyword, or the scan below proves nothing.
    run grep -cE "$JQ_KEYWORD_VAR_ERE" <<'EOF'
    .[1] as $label | .
    jq --arg label x
    jq --argjson if 1 '.'
    jq --slurpfile __loc__ f.json
    def f($label): .;
    def g(a; $end): .;
    .[1] as $wslabel | .
    .[1] as $labels | .
    jq --arg endpoint x
    jq --arg not x
    has $end
    def f($labels): .;
EOF
    assert_output "6"

    run grep -rnE "$JQ_KEYWORD_VAR_ERE" \
        --include='*.sh' --include='*.bash' --include='*.zsh' --include='*.bats' \
        --exclude-dir=bats-core --exclude-dir=bats-assert --exclude-dir=bats-support \
        --exclude-dir=.git --exclude-dir=.venv --exclude-dir=node_modules \
        --exclude=jq_reserved_vars.bats \
        "${_BATS_REAL_DOTFILES_ROOT}"
    assert_output ""
}
