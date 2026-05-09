#!/usr/bin/env bats
# tests/bats/functions/gh_audit_builtin_workflows.bats
# Unit tests for gh_audit_builtin_workflows. The live GraphQL path needs
# a real projectV2 with workflows visible to the caller, which is
# impractical to fixture. We exercise loading, help/usage, arg
# validation, the forbidden-list membership helper, and four end-to-end
# audit scenarios via a fake `gh` shim that returns synthetic
# repository.projectsV2.nodes[].workflows.nodes[] payloads.
#
# Coverage matches the issue #397 acceptance criteria:
#   1. policy match (✅, exit 0)
#   2. policy violation — "Pull request linked to issue" ON (✗, exit 2)
#   3. multiple boards, mixed state (one violation surfaces)
#   4. repo without any projectV2 (silent skip, exit 0)

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

@test "bash: gh_audit_builtin_workflows function exists" {
    run_in_bash 'declare -f gh_audit_builtin_workflows >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gh-audit-builtin-workflows alias resolves to gh_audit_builtin_workflows" {
    run_in_bash "alias gh-audit-builtin-workflows 2>/dev/null | grep -q gh_audit_builtin_workflows && echo ok"
    assert_success
    assert_output --partial "ok"
}

@test "zsh: gh_audit_builtin_workflows function exists" {
    run_in_zsh 'typeset -f gh_audit_builtin_workflows >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_audit_builtin_workflows_is_forbidden helper exists" {
    run_in_bash 'declare -f _gh_audit_builtin_workflows_is_forbidden >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Help surface
# ---------------------------------------------------------------------------

@test "help: --help prints usage" {
    run_in_bash 'gh_audit_builtin_workflows --help'
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "gh-audit-builtin-workflows"
}

@test "help: -h prints usage" {
    run_in_bash 'gh_audit_builtin_workflows -h'
    assert_success
    assert_output --partial "Usage"
}

@test "help: text mentions Pull request linked to issue policy" {
    run_in_bash 'gh_audit_builtin_workflows --help'
    assert_success
    assert_output --partial "Pull request linked to issue"
    assert_output --partial "DISABLED"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "validation: unknown option exits 2" {
    run_in_bash 'gh_audit_builtin_workflows --bogus 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial "unknown option: --bogus"
}

@test "validation: --repo without value exits 2" {
    run_in_bash 'gh_audit_builtin_workflows --repo 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial "--repo requires an argument"
}

@test "validation: --repo with malformed spec exits 2" {
    # No-slash spec is malformed — resolver returns 1, function exits 2.
    run_in_bash 'gh_audit_builtin_workflows --repo no-slash 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial "could not resolve repo"
}

# ---------------------------------------------------------------------------
# Forbidden-list membership semantics
# ---------------------------------------------------------------------------

@test "forbidden: 'Pull request linked to issue' matches" {
    run_in_bash '_gh_audit_builtin_workflows_is_forbidden "Pull request linked to issue" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

@test "forbidden: unrelated workflow name does not match" {
    run_in_bash '_gh_audit_builtin_workflows_is_forbidden "Item closed" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "NO"
}

@test "forbidden: empty value never matches" {
    run_in_bash '_gh_audit_builtin_workflows_is_forbidden "" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "NO"
}

# ---------------------------------------------------------------------------
# End-to-end audit via fake `gh`
#
# The shim emits the same line shape the real --jq filter produces:
#   project_url|project_title|workflow_name|enabled
#
# Mode is selected by FAKE_AUDIT_MODE:
#   compliant     → one project, "Pull request linked to issue" disabled
#   violation     → one project, "Pull request linked to issue" enabled
#   mixed         → two projects; first compliant, second violates
#   no-projects   → empty stdout (no projectV2 attached or no access)
# ---------------------------------------------------------------------------

_setup_fake_gh_audit() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB_BIN"
    # Tab-separated output mirrors the real --jq filter (PR #402 review:
    # tab is safer than `|` for project titles containing that character).
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Multiplexed: only `repo view --json nameWithOwner` and `api graphql` shapes.
T=$'\t'
case "$1 $2" in
    "repo view")
        echo "owner/reponame"
        exit 0
        ;;
    "api graphql")
        case "${FAKE_AUDIT_MODE:-no-projects}" in
            compliant)
                printf 'https://github.com/orgs/owner/projects/1%sTeam Board%sPull request linked to issue%sfalse\n' "$T" "$T" "$T"
                printf 'https://github.com/orgs/owner/projects/1%sTeam Board%sItem closed%strue\n' "$T" "$T" "$T"
                ;;
            violation)
                printf 'https://github.com/orgs/owner/projects/1%sTeam Board%sPull request linked to issue%strue\n' "$T" "$T" "$T"
                printf 'https://github.com/orgs/owner/projects/1%sTeam Board%sItem closed%strue\n' "$T" "$T" "$T"
                ;;
            mixed)
                printf 'https://github.com/orgs/owner/projects/1%sTeam Board%sPull request linked to issue%sfalse\n' "$T" "$T" "$T"
                printf 'https://github.com/orgs/owner/projects/2%sSide Board%sPull request linked to issue%strue\n' "$T" "$T" "$T"
                ;;
            no-projects)
                # repo has no projectV2 OR caller lacks workflow read perm.
                exit 0
                ;;
        esac
        exit 0
        ;;
esac
exit 0
GH
    chmod +x "$STUB_BIN/gh"
}

# Run the audit in bash with the fake gh on PATH. Mirrors the pattern in
# gh_project_status.bats so isolation/env wiring stays consistent.
_run_audit_bash() {
    local mode="$1" args="$2"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:${PATH}'
        export FAKE_AUDIT_MODE='${mode}'
        source '${DOTFILES_ROOT}/bash/main.bash'
        gh_audit_builtin_workflows ${args} 2>&1
        echo \"rc=\$?\"
    "
}

@test "audit: compliant project — exit 0 with success marker" {
    _setup_fake_gh_audit
    _run_audit_bash compliant ''
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "policy-compliant"
    refute_output --partial "ENABLED"
}

@test "audit: violation — exit 2 with violation marker and settings URL" {
    _setup_fake_gh_audit
    _run_audit_bash violation ''
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial "Pull request linked to issue"
    assert_output --partial "ENABLED"
    assert_output --partial "Settings"
    assert_output --partial "/workflows"
}

@test "audit: mixed boards — surfaces the violating board only" {
    _setup_fake_gh_audit
    _run_audit_bash mixed ''
    assert_success
    assert_output --partial "rc=2"
    assert_output --partial "Side Board"
    refute_output --partial "Team Board: \"Pull request linked to issue\" is ENABLED"
}

@test "audit: no projects attached — exit 0 with skip notice" {
    _setup_fake_gh_audit
    _run_audit_bash no-projects ''
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "no projectV2 attached"
}
