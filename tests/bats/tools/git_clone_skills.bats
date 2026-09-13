#!/usr/bin/env bats
# tests/bats/tools/git_clone_skills.bats
# Validate git-clone-skills.sh: syntax, options, manifest-driven repo
# selection, idempotent cloning, and fork upstream registration.
#
# Every test runs fully offline. Network access is prevented two ways:
#   1. PATH is replaced with a minimal stub directory (`_setup_stub_path`),
#      so the only `git` and `gh` reachable are the stubs written here.
#   2. The `git` stub rewrites any `https://<host>/<owner>/<repo>.git` URL
#      passed to `git clone` into a local bare repo under $FAKE_REMOTES.
# A repo with no local bare fixture therefore fails to clone, which is how
# the failure/exit-code path is exercised.

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/claude/plugin/git-clone-skills.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# --- fixtures ---------------------------------------------------------------

# Write a manifest with two dEitY719 repos and one foreign-owner repo, so
# the default owner filter and --all / --owner can be told apart.
_write_manifest() {
    MANIFEST="${TEST_TEMP_HOME}/marketplaces.json"
    cat >"$MANIFEST" <<'JSON'
{
  "alpha-mkt": "dEitY719/alpha-skills",
  "beta-mkt": "otherowner/beta-skills",
  "gamma-mkt": "dEitY719/gamma-skills"
}
JSON
}

# Minimal PATH containing only the utilities the script needs plus our
# stubs. Guarantees no real `gh` and no network-capable `git` is reachable.
_setup_stub_path() {
    STUB_BIN="${TEST_TEMP_HOME}/stub-bin"
    FAKE_REMOTES="${TEST_TEMP_HOME}/remotes"
    GIT_CALL_LOG="${TEST_TEMP_HOME}/git-calls.log"
    GH_CALL_LOG="${TEST_TEMP_HOME}/gh-calls.log"
    GH_PARENTS="${TEST_TEMP_HOME}/gh-parents"
    mkdir -p "$STUB_BIN" "$FAKE_REMOTES" "$GH_PARENTS"
    : >"$GIT_CALL_LOG"
    : >"$GH_CALL_LOG"

    REAL_GIT="$(command -v git)"

    local util util_path
    for util in bash env dirname basename mkdir sort cat sed tr grep rm uname jq; do
        util_path="$(command -v "$util" 2>/dev/null)" || continue
        ln -sf "$util_path" "${STUB_BIN}/${util}"
    done

    cat >"${STUB_BIN}/git" <<EOF
#!/bin/bash
# Test stub: rewrite remote https URLs on \`git clone\` to local bare repos.
printf 'git %s\n' "\$*" >>"${GIT_CALL_LOG}"
args=()
if [ "\${1:-}" = "clone" ]; then
    for a in "\$@"; do
        case "\$a" in
        https://*) a="${FAKE_REMOTES}/\${a##*/}" ;;
        esac
        args+=("\$a")
    done
else
    args=("\$@")
fi
exec "${REAL_GIT}" "\${args[@]}"
EOF
    chmod +x "${STUB_BIN}/git"
}

# `gh repo view --repo <owner>/<repo> --json parent` stub.
# Returns ${GH_PARENTS}/<repo>.json when present, else {"parent":null}.
# Set GH_STUB_FAIL=1 in the child env to simulate an API/auth failure.
_install_gh_stub() {
    cat >"${STUB_BIN}/gh" <<EOF
#!/bin/bash
printf 'gh %s\n' "\$*" >>"${GH_CALL_LOG}"
if [ -n "\${GH_STUB_FAIL:-}" ]; then
    echo "gh: stubbed failure" >&2
    exit 1
fi
slug=""
prev=""
for a in "\$@"; do
    [ "\$prev" = "--repo" ] && slug="\$a"
    prev="\$a"
done
repo="\${slug##*/}"
if [ -f "${GH_PARENTS}/\${repo}.json" ]; then
    cat "${GH_PARENTS}/\${repo}.json"
else
    echo '{"parent":null}'
fi
EOF
    chmod +x "${STUB_BIN}/gh"
}

_set_gh_parent() {
    # $1 = repo name, $2 = parent owner, $3 = parent repo
    cat >"${GH_PARENTS}/${1}.json" <<EOF
{"parent":{"owner":{"login":"$2"},"name":"$3"}}
EOF
}

# Create a local bare repo the git stub can clone from.
_make_fake_remote() {
    local name="$1"
    local work="${TEST_TEMP_HOME}/seed-${name}"
    mkdir -p "$work"
    "$REAL_GIT" -C "$work" init -q -b main
    echo "$name" >"${work}/README.md"
    "$REAL_GIT" -C "$work" -c user.name=Test -c user.email=test@example.com add README.md
    "$REAL_GIT" -C "$work" -c user.name=Test -c user.email=test@example.com commit -q -m init
    "$REAL_GIT" clone -q --bare "$work" "${FAKE_REMOTES}/${name}.git"
}

# --- syntax / usage ---------------------------------------------------------

@test "git-clone-skills.sh passes bash syntax check" {
    run bash -n "$SCRIPT_UNDER_TEST"
    assert_success
}

@test "git-clone-skills.sh is executable" {
    [ -x "$SCRIPT_UNDER_TEST" ]
}

@test "git-clone-skills.sh --help displays usage" {
    run bash "$SCRIPT_UNDER_TEST" --help
    assert_success
    assert_output --partial "Usage: git-clone-skills.sh"
    assert_output --partial "--dry-run"
    assert_output --partial "--all"
    assert_output --partial "--target"
    assert_output --partial "--owner"
    assert_output --partial "--manifest"
    assert_output --partial "--no-upstream"
}

@test "git-clone-skills.sh rejects unknown argument with exit 2" {
    run bash "$SCRIPT_UNDER_TEST" --bogus-flag
    [ "$status" -eq 2 ]
    assert_output --partial "Unknown argument: --bogus-flag"
}

@test "git-clone-skills.sh fails on missing manifest" {
    run bash "$SCRIPT_UNDER_TEST" --manifest "${TEST_TEMP_HOME}/nope.json" --dry-run
    assert_failure
    assert_output --partial "Manifest not found"
}

@test "git-clone-skills.sh fails clearly when jq is unavailable" {
    _write_manifest
    local nojq="${TEST_TEMP_HOME}/nojq-bin"
    mkdir -p "$nojq"
    local util util_path
    for util in bash dirname; do
        util_path="$(command -v "$util")"
        ln -sf "$util_path" "${nojq}/${util}"
    done

    run env PATH="$nojq" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "${TEST_TEMP_HOME}/skills" --dry-run
    assert_failure
    assert_output --partial "jq"
}

@test "git-clone-skills.sh fails on a manifest that is not valid JSON" {
    local broken="${TEST_TEMP_HOME}/broken.json"
    echo "{ not json" >"$broken"

    run bash "$SCRIPT_UNDER_TEST" \
        --manifest "$broken" --target "${TEST_TEMP_HOME}/skills" --dry-run
    assert_failure
    assert_output --partial "Failed to read repository list from manifest"
}

# --- manifest-driven selection ---------------------------------------------

@test "git-clone-skills.sh selects only the default owner from the manifest" {
    _write_manifest
    _setup_stub_path

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "${TEST_TEMP_HOME}/skills" --dry-run
    assert_success
    assert_output --partial "alpha-skills"
    assert_output --partial "gamma-skills"
    refute_output --partial "beta-skills"
    assert_output --partial "Total: 2"
}

@test "git-clone-skills.sh --all drops the owner filter" {
    _write_manifest
    _setup_stub_path

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "${TEST_TEMP_HOME}/skills" --all --dry-run
    assert_success
    assert_output --partial "alpha-skills"
    assert_output --partial "beta-skills"
    assert_output --partial "gamma-skills"
    assert_output --partial "Total: 3"
}

@test "git-clone-skills.sh --owner replaces the default owner filter" {
    _write_manifest
    _setup_stub_path

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "${TEST_TEMP_HOME}/skills" \
        --owner otherowner --dry-run
    assert_success
    assert_output --partial "beta-skills"
    refute_output --partial "alpha-skills"
    assert_output --partial "Total: 1"
}

@test "git-clone-skills.sh reads the repo list from the manifest, not a hardcoded list" {
    _setup_stub_path
    local custom="${TEST_TEMP_HOME}/custom.json"
    cat >"$custom" <<'JSON'
{ "only-mkt": "dEitY719/solo-skills" }
JSON

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$custom" --target "${TEST_TEMP_HOME}/skills" --dry-run
    assert_success
    assert_output --partial "solo-skills"
    assert_output --partial "Total: 1"
    refute_output --partial "gh-pr-skills"
}

@test "git-clone-skills.sh uses the resolved host in the clone URL" {
    _write_manifest
    _setup_stub_path

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "${TEST_TEMP_HOME}/skills" --dry-run
    assert_success
    assert_output --partial "https://github.com/dEitY719/alpha-skills.git"
}

# --- dry-run purity ---------------------------------------------------------

@test "git-clone-skills.sh --dry-run touches no disk state" {
    _write_manifest
    _setup_stub_path
    local target="${TEST_TEMP_HOME}/skills-dry"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target" --dry-run
    assert_success
    assert_output --partial "DRY-RUN"
    [ ! -d "$target" ]
    [ ! -s "$GIT_CALL_LOG" ]
}

# --- real clone -------------------------------------------------------------

@test "git-clone-skills.sh clones missing repositories and creates the target dir" {
    _write_manifest
    _setup_stub_path
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success
    assert_output --partial "alpha-skills: cloned"
    assert_output --partial "gamma-skills: cloned"
    assert_output --partial "Cloned: 2"
    assert_output --partial "Failed: 0"

    [ -f "${target}/alpha-skills/README.md" ]
    [ -f "${target}/gamma-skills/README.md" ]
    # Clone path is <target>/<repo>, owner is not part of the path.
    [ ! -d "${target}/dEitY719" ]
}

@test "git-clone-skills.sh is idempotent: existing directories are skipped" {
    _write_manifest
    _setup_stub_path
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success

    # Marker file must survive the second run untouched.
    echo "local work" >"${target}/alpha-skills/LOCAL_MARKER"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success
    assert_output --partial "alpha-skills: already present (skipped)"
    assert_output --partial "Already present: 2"
    assert_output --partial "Cloned: 0"
    [ -f "${target}/alpha-skills/LOCAL_MARKER" ]
}

@test "git-clone-skills.sh reports failure and exits 1 when a clone fails" {
    _write_manifest
    _setup_stub_path
    # Only alpha has a local bare fixture; gamma's clone must fail.
    _make_fake_remote "alpha-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_failure
    assert_output --partial "alpha-skills: cloned"
    assert_output --partial "gamma-skills: git clone failed"
    assert_output --partial "Failed: 1"
}

# --- upstream registration --------------------------------------------------

@test "git-clone-skills.sh adds an upstream remote for forks" {
    _write_manifest
    _setup_stub_path
    _install_gh_stub
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    _set_gh_parent "alpha-skills" "upstreamowner" "alpha-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success
    assert_output --partial "alpha-skills: upstream remote added (upstreamowner/alpha-skills)"
    assert_output --partial "Upstream added: 1"

    run "$REAL_GIT" -C "${target}/alpha-skills" config --get remote.upstream.url
    assert_success
    assert_output "https://github.com/upstreamowner/alpha-skills.git"

    # Non-fork repo must not get an upstream remote.
    run "$REAL_GIT" -C "${target}/gamma-skills" config --get remote.upstream.url
    assert_failure
}

@test "git-clone-skills.sh pins GH_HOST and --repo on every gh call" {
    _write_manifest
    _setup_stub_path
    _install_gh_stub
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success

    # The stub only ever sees the argv, so --repo is asserted from the log and
    # GH_HOST from the environment the stub was invoked with.
    grep -q -- "--repo dEitY719/alpha-skills" "$GH_CALL_LOG"
    grep -q -- "--json parent" "$GH_CALL_LOG"

    # Source-level contract check (#1403/#1407): prefix and --repo together.
    grep -q 'GH_HOST="\$GH_TARGET_HOST" gh repo view --repo' "$SCRIPT_UNDER_TEST"
}

@test "git-clone-skills.sh succeeds with only a warning when gh is absent" {
    _write_manifest
    _setup_stub_path
    # No _install_gh_stub: the minimal PATH has no gh at all.
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success
    assert_output --partial "gh not found"
    assert_output --partial "Cloned: 2"
    assert_output --partial "Upstream added: 0"
    assert_output --partial "Failed: 0"
}

@test "git-clone-skills.sh succeeds with only a warning when gh fails" {
    _write_manifest
    _setup_stub_path
    _install_gh_stub
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" GH_STUB_FAIL=1 bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success
    assert_output --partial "upstream detection skipped"
    assert_output --partial "Cloned: 2"
    assert_output --partial "Failed: 0"
}

@test "git-clone-skills.sh --no-upstream skips fork detection entirely" {
    _write_manifest
    _setup_stub_path
    _install_gh_stub
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    _set_gh_parent "alpha-skills" "upstreamowner" "alpha-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target" --no-upstream
    assert_success
    assert_output --partial "Cloned: 2"
    assert_output --partial "Upstream added: 0"
    [ ! -s "$GH_CALL_LOG" ]

    run "$REAL_GIT" -C "${target}/alpha-skills" config --get remote.upstream.url
    assert_failure
}

@test "git-clone-skills.sh leaves a pre-existing upstream remote alone" {
    _write_manifest
    _setup_stub_path
    _install_gh_stub
    _make_fake_remote "alpha-skills"
    _make_fake_remote "gamma-skills"
    _set_gh_parent "alpha-skills" "upstreamowner" "alpha-skills"
    local target="${TEST_TEMP_HOME}/skills"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success

    "$REAL_GIT" -C "${target}/alpha-skills" remote set-url upstream \
        "https://github.com/handpicked/upstream.git"

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --manifest "$MANIFEST" --target "$target"
    assert_success
    assert_output --partial "Already present: 2"

    run "$REAL_GIT" -C "${target}/alpha-skills" config --get remote.upstream.url
    assert_success
    assert_output "https://github.com/handpicked/upstream.git"
}

# --- integration with the real manifest ------------------------------------

@test "git-clone-skills.sh default manifest yields the dEitY719 skill repos" {
    _setup_stub_path

    run env PATH="$STUB_BIN" bash "$SCRIPT_UNDER_TEST" \
        --target "${TEST_TEMP_HOME}/skills" --dry-run
    assert_success
    assert_output --partial "gh-pr-skills"
    refute_output --partial "anthropics/skills"
}

@test "git-clone-skills.sh registers a shell alias and help entry" {
    grep -q "alias git-clone-skills=" "${DOTFILES_ROOT}/shell-common/aliases/claude_plugins.sh"
    grep -q "git-clone-skills" "${DOTFILES_ROOT}/shell-common/functions/claude_plugins_help.sh"
}
