#!/usr/bin/env bats
# tests/bats/tools/mirror_pages_activate.bats
# Tests for mirror-pages-activate.sh (issue #944).

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/mirror-pages-activate.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mirror-pages-test.XXXXXX")"
}

teardown() {
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Syntax & basics
# ---------------------------------------------------------------------------

@test "mirror-pages-activate: bash syntax check" {
    run bash -n "${SCRIPT}"
    assert_success
}

@test "mirror-pages-activate: --help exits 0 and prints usage" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "Usage: mirror-pages-activate"
    assert_output --partial "--dry-run"
}

@test "mirror-pages-activate: unknown option exits 1" {
    run bash "${SCRIPT}" --unknown
    assert_failure
}

# ---------------------------------------------------------------------------
# Precondition guards (no git repo)
# ---------------------------------------------------------------------------

@test "mirror-pages-activate: fails outside a git repo" {
    run bash -c "cd '${_WORK_DIR}' && bash '${SCRIPT}' --dry-run"
    assert_failure
}

# ---------------------------------------------------------------------------
# Helpers: build a minimal fake git repo with controlled remotes + mock gh
# ---------------------------------------------------------------------------

_setup_fake_repo() {
    local origin_url="${1}"
    local upstream_url="${2}"
    cd "${_WORK_DIR}"
    git init -q
    git remote add origin "${origin_url}"
    git remote add upstream "${upstream_url}"
}

_write_mock_gh() {
    # Writes a stub `gh` that returns NOT_FOUND for pages GET calls.
    # Place it early in PATH so it overrides the real gh.
    local bin_dir="${_WORK_DIR}/bin"
    mkdir -p "${bin_dir}"
    cat >"${bin_dir}/gh" <<'EOF'
#!/bin/bash
# Stub: pages GET -> NOT_FOUND; pages POST -> success
if [[ "$*" == *"/pages"* ]]; then
    case "$*" in
        *"--method POST"*) exit 0 ;;
        *) printf 'NOT_FOUND'; exit 0 ;;
    esac
fi
exit 0
EOF
    chmod +x "${bin_dir}/gh"
    export PATH="${bin_dir}:${PATH}"
}

_write_mock_gh_pages_active() {
    local bin_dir="${_WORK_DIR}/bin"
    mkdir -p "${bin_dir}"
    cat >"${bin_dir}/gh" <<'EOF'
#!/bin/bash
# Stub: pages already active
if [[ "$*" == *"/pages"* ]]; then
    printf 'built'; exit 0
fi
exit 0
EOF
    chmod +x "${bin_dir}/gh"
    export PATH="${bin_dir}:${PATH}"
}

# ---------------------------------------------------------------------------
# Remote validation
# ---------------------------------------------------------------------------

@test "mirror-pages-activate: fails when origin is missing" {
    cd "${_WORK_DIR}"
    git init -q
    git remote add upstream "https://github.com/owner/repo"
    run bash "${SCRIPT}" --dry-run
    assert_failure
    assert_output --partial "No 'origin' remote found"
}

@test "mirror-pages-activate: fails when upstream is missing" {
    cd "${_WORK_DIR}"
    git init -q
    git remote add origin "https://ghe.example.com/user/repo"
    run bash "${SCRIPT}" --dry-run
    assert_failure
    assert_output --partial "No 'upstream' remote found"
}

@test "mirror-pages-activate: fails when origin points to github.com" {
    _setup_fake_repo \
        "https://github.com/owner/repo" \
        "https://github.com/owner/repo"
    run bash -c "cd '${_WORK_DIR}' && bash '${SCRIPT}' --dry-run"
    assert_failure
    assert_output --partial "origin points to github.com"
}

# ---------------------------------------------------------------------------
# Dry-run: no mutation
# ---------------------------------------------------------------------------

@test "mirror-pages-activate: --dry-run prints planned actions" {
    _setup_fake_repo \
        "https://ghe.example.com/mirror-user/my-plugin" \
        "https://github.com/upstream-owner/my-plugin"
    _write_mock_gh
    printf 'See docs at https://upstream-owner.github.io/my-plugin/\n' \
        >README.md
    run bash -c "cd '${_WORK_DIR}' && PATH='${_WORK_DIR}/bin:${PATH}' bash '${SCRIPT}' --dry-run"
    assert_success
    assert_output --partial "dry-run"
    # README must NOT be modified
    run grep -c "upstream-owner.github.io" "${_WORK_DIR}/README.md"
    assert_output "1"
}

@test "mirror-pages-activate: --dry-run does not mutate README.md" {
    _setup_fake_repo \
        "https://ghe.example.com/mirror-user/my-plugin" \
        "https://github.com/upstream-owner/my-plugin"
    _write_mock_gh
    printf 'See https://upstream-owner.github.io/my-plugin/\n' >README.md
    local before
    before="$(cat "${_WORK_DIR}/README.md")"
    run bash -c "cd '${_WORK_DIR}' && PATH='${_WORK_DIR}/bin:${PATH}' bash '${SCRIPT}' --dry-run"
    assert_success
    local after
    after="$(cat "${_WORK_DIR}/README.md")"
    [ "${before}" = "${after}" ]
}

# ---------------------------------------------------------------------------
# Apply mode: URL replacement
# ---------------------------------------------------------------------------

@test "mirror-pages-activate: replaces upstream github.io URLs in README.md" {
    _setup_fake_repo \
        "https://ghe.example.com/mirror-user/my-plugin" \
        "https://github.com/upstream-owner/my-plugin"
    _write_mock_gh
    printf 'Badge: https://upstream-owner.github.io/my-plugin/badge.svg\n' \
        >README.md
    run bash -c "cd '${_WORK_DIR}' && PATH='${_WORK_DIR}/bin:${PATH}' bash '${SCRIPT}'"
    assert_success
    run grep "ghe.example.com/pages/mirror-user/my-plugin" "${_WORK_DIR}/README.md"
    assert_success
    run grep "upstream-owner.github.io" "${_WORK_DIR}/README.md"
    assert_failure
}

@test "mirror-pages-activate: replaces all occurrences" {
    _setup_fake_repo \
        "https://ghe.example.com/mirror-user/my-plugin" \
        "https://github.com/upstream-owner/my-plugin"
    _write_mock_gh
    printf 'A: https://upstream-owner.github.io/my-plugin/\nB: https://upstream-owner.github.io/my-plugin/docs\n' \
        >README.md
    run bash -c "cd '${_WORK_DIR}' && PATH='${_WORK_DIR}/bin:${PATH}' bash '${SCRIPT}'"
    assert_success
    local count
    count=$(grep -c "ghe.example.com/pages/mirror-user/my-plugin" "${_WORK_DIR}/README.md")
    [ "${count}" -eq 2 ]
}

@test "mirror-pages-activate: no README.md exits 0 (skip)" {
    _setup_fake_repo \
        "https://ghe.example.com/mirror-user/my-plugin" \
        "https://github.com/upstream-owner/my-plugin"
    _write_mock_gh
    run bash -c "cd '${_WORK_DIR}' && PATH='${_WORK_DIR}/bin:${PATH}' bash '${SCRIPT}'"
    assert_success
    assert_output --partial "README.md not found"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "mirror-pages-activate: second run exits 0 with nothing to do" {
    _setup_fake_repo \
        "https://ghe.example.com/mirror-user/my-plugin" \
        "https://github.com/upstream-owner/my-plugin"
    _write_mock_gh_pages_active
    # README already has GHE URL (no upstream URLs left)
    printf 'See https://ghe.example.com/pages/mirror-user/my-plugin/\n' \
        >README.md
    run bash -c "cd '${_WORK_DIR}' && PATH='${_WORK_DIR}/bin:${PATH}' bash '${SCRIPT}'"
    assert_success
    assert_output --partial "already active"
    assert_output --partial "nothing to do"
}

# ---------------------------------------------------------------------------
# Works for any GHE host
# ---------------------------------------------------------------------------

@test "mirror-pages-activate: works with arbitrary GHE host" {
    _setup_fake_repo \
        "https://custom-ghe.corp.example/team/plugin-x" \
        "https://github.com/oss-org/plugin-x"
    _write_mock_gh
    printf 'Link: https://oss-org.github.io/plugin-x/\n' >README.md
    run bash -c "cd '${_WORK_DIR}' && PATH='${_WORK_DIR}/bin:${PATH}' bash '${SCRIPT}'"
    assert_success
    run grep "custom-ghe.corp.example/pages/team/plugin-x" "${_WORK_DIR}/README.md"
    assert_success
}

@test "mirror-pages-activate: Pages source defaults to main branch and /docs path" {
    local bin_dir="${_WORK_DIR}/bin"
    mkdir -p "${bin_dir}"
    cat >"${bin_dir}/gh" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--method POST"* ]]; then
    exit 0
fi
printf 'NOT_FOUND'; exit 0
EOF
    chmod +x "${bin_dir}/gh"
    _setup_fake_repo \
        "https://ghe.example.com/user/repo" \
        "https://github.com/owner/repo"
    run bash -c "cd '${_WORK_DIR}' && PATH='${bin_dir}:${PATH}' bash '${SCRIPT}'"
    assert_success
    assert_output --partial "main"
    assert_output --partial "/docs"
}
