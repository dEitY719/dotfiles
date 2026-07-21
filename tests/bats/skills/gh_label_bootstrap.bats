#!/usr/bin/env bats
# tests/bats/skills/gh_label_bootstrap.bats
# Offline coverage for claude/skills/gh-label-bootstrap/lib/label-bootstrap.sh
# using a mock `gh` binary injected via PATH — no real network/API calls.

load '../test_helper'

LABEL_SCRIPT="${DOTFILES_ROOT}/claude/skills/gh-label-bootstrap/lib/label-bootstrap.sh"

setup() {
    setup_isolated_home

    MOCK_BIN="${TEST_TEMP_HOME}/mock-bin"
    MOCK_LOG="${TEST_TEMP_HOME}/mock-gh.log"
    MOCK_EXISTING_FILE="${TEST_TEMP_HOME}/existing.txt"
    mkdir -p "$MOCK_BIN"
    : >"$MOCK_LOG"
    : >"$MOCK_EXISTING_FILE"

    cat >"${MOCK_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${MOCK_GH_LOG}"

# List labels: gh api repos/<repo>/labels?per_page=100 --jq '.[].name'
if [[ "${1:-}" == "api" && "${2:-}" == repos/*/labels?per_page=* ]]; then
    if [ -f "${MOCK_EXISTING_FILE:-/nonexistent}" ]; then
        cat "${MOCK_EXISTING_FILE}"
    fi
    exit 0
fi

# Repo auto-resolve (only used when --repo omitted).
if [[ "${1:-}" == "repo" && "${2:-}" == "view" ]]; then
    printf '%s\n' "${MOCK_REPO:-acme/widget}"
    exit 0
fi

# A mutation call matching MOCK_FAIL_PATTERN (grep -E, optional) fails.
if [ -n "${MOCK_FAIL_PATTERN:-}" ] && printf '%s' "$*" | grep -qE "${MOCK_FAIL_PATTERN}"; then
    exit 1
fi

# All other mutations (PATCH / POST / DELETE) succeed silently.
exit 0
EOF
    chmod +x "${MOCK_BIN}/gh"

    export MOCK_GH_LOG="$MOCK_LOG"
    export MOCK_EXISTING_FILE
    export MOCK_FAIL_PATTERN=""
    export PATH="${MOCK_BIN}:${PATH}"
}

teardown() {
    teardown_isolated_home
}

set_existing() {
    printf '%s\n' "$@" >"$MOCK_EXISTING_FILE"
}

run_bootstrap() {
    run bash "$LABEL_SCRIPT" --repo acme/widget "$@"
}

# ── SSOT label already exists → PATCH with SSOT color/description ──────
@test "existing SSOT label is PATCHed with SSOT color" {
    set_existing feat
    run_bootstrap
    assert_success
    grep -q 'repos/acme/widget/labels/feat -X PATCH' "$MOCK_LOG"
    grep -q 'color=fbca04' "$MOCK_LOG"
}

# ── SSOT label missing → POST ─────────────────────────────────────────
@test "missing SSOT label is POSTed" {
    set_existing "" # no labels exist
    run_bootstrap
    assert_success
    grep -q 'repos/acme/widget/labels -X POST -f name=feat -f color=fbca04' "$MOCK_LOG"
    grep -q 'repos/acme/widget/labels -X POST -f name=reference' "$MOCK_LOG"
}

# ── Alias bug exists → PATCH .../labels/bug new_name=fix ───────────────
@test "alias source 'bug' is renamed to 'fix' with SSOT color" {
    set_existing bug
    run_bootstrap
    assert_success
    grep -q 'repos/acme/widget/labels/bug -X PATCH -f new_name=fix -f color=d73a4a' "$MOCK_LOG"
    # 'fix' already handled by the rename → no duplicate PATCH/POST of fix.
    if grep -q 'repos/acme/widget/labels/fix -X PATCH' "$MOCK_LOG"; then
        echo "renamed target 'fix' must not be re-PATCHed" && return 1
    fi
    if grep -q 'labels -X POST -f name=fix' "$MOCK_LOG"; then
        echo "renamed target 'fix' must not be POSTed" && return 1
    fi
}

# ── Alias bug missing → POST fix directly, no PATCH on bug ─────────────
@test "alias missing: fix is POSTed directly, no bug PATCH" {
    set_existing "" # neither bug nor fix exist
    run_bootstrap
    assert_success
    grep -q 'labels -X POST -f name=fix -f color=d73a4a' "$MOCK_LOG"
    if grep -q 'labels/bug' "$MOCK_LOG"; then
        echo "no API call should target the absent 'bug' label" && return 1
    fi
}

# ── --dry-run → zero mutations, plan on stdout ────────────────────────
@test "--dry-run makes no POST/PATCH/DELETE and prints the plan" {
    set_existing feat bug zzz-custom
    run_bootstrap --dry-run --prune
    assert_success
    assert_output --partial '[dry-run]'
    for verb in PATCH POST DELETE; do
        if grep -q -- "-X ${verb}" "$MOCK_LOG"; then
            echo "dry-run must not emit -X ${verb}" && return 1
        fi
    done
}

# ── --prune off (default) → no DELETE even with non-SSOT labels ────────
@test "prune off: extraneous label is not deleted" {
    set_existing feat zzz-custom
    run_bootstrap
    assert_success
    if grep -q -- '-X DELETE' "$MOCK_LOG"; then
        echo "no DELETE without --prune" && return 1
    fi
    assert_output --partial 'Prune skipped'
}

# ── --prune on → extraneous deleted; allowlist + renamed-source kept ──
@test "prune on: deletes extraneous, keeps allowlist and renamed alias source" {
    set_existing zzz-custom enhancement bug
    run_bootstrap --prune
    assert_success
    # Genuinely extraneous custom label is deleted.
    grep -q 'repos/acme/widget/labels/zzz-custom -X DELETE' "$MOCK_LOG"
    # Allowlist default is preserved.
    if grep -q 'labels/enhancement -X DELETE' "$MOCK_LOG"; then
        echo "allowlist 'enhancement' must not be deleted" && return 1
    fi
    # 'bug' was renamed to 'fix' before prune eval → never a candidate.
    if grep -q 'labels/bug -X DELETE' "$MOCK_LOG"; then
        echo "renamed alias source 'bug' must not be deleted" && return 1
    fi
    grep -q 'repos/acme/widget/labels/bug -X PATCH -f new_name=fix' "$MOCK_LOG"
}

# ── Rename PATCH fails (bug+fix collision) → fix still synced, not skipped ──
@test "rename PATCH failure does not skip the target's SSOT sync" {
    set_existing bug fix
    MOCK_FAIL_PATTERN='labels/bug -X PATCH' run_bootstrap
    assert_success
    # The failed rename attempt is logged...
    grep -q 'repos/acme/widget/labels/bug -X PATCH -f new_name=fix' "$MOCK_LOG"
    # ...but since it failed, 'fix' must NOT be treated as already-synced —
    # step 2 (SSOT apply) must still PATCH it directly (codex review, PR #1229).
    grep -q 'repos/acme/widget/labels/fix -X PATCH -f new_name=fix -f color=d73a4a' "$MOCK_LOG"
}

# ── Standalone deployment: skill dir copied outside the dotfiles tree ──
# (codex review, PR #1231): resolve_ssot_file() must find references/gh-labels.md
# as a sibling of lib/ with no docs/.ssot/ or dotfiles repo root anywhere nearby —
# this is the whole point of moving the SSOT into the skill directory.
@test "standalone: works when the skill dir is copied outside the dotfiles repo" {
    STANDALONE_DIR="${TEST_TEMP_HOME}/standalone-gh-label-bootstrap"
    mkdir -p "$STANDALONE_DIR"
    cp -r "${DOTFILES_ROOT}/claude/skills/gh-label-bootstrap/lib" "$STANDALONE_DIR/"
    cp -r "${DOTFILES_ROOT}/claude/skills/gh-label-bootstrap/references" "$STANDALONE_DIR/"

    set_existing feat
    run bash "${STANDALONE_DIR}/lib/label-bootstrap.sh" --repo acme/widget --dry-run
    assert_success
    assert_output --partial "[dry-run] PATCH label 'feat' (color=fbca04)"
}
