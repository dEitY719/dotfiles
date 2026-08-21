#!/usr/bin/env bats
# tests/bats/setup/hermes_setup.bats
# Coverage for hermes/setup.sh Part 1 (_hermes_ensure_config_copy) — the
# write-through symlink leak fix (PR #1381, codex review finding: the PR
# changed this migration logic in three branches but only added a static
# grep golden rule, leaving the branches themselves untested).
#
# `hermes` is stubbed on PATH so Part 2 (CLI install) short-circuits on
# "already installed" and never touches the network. HERMES_SKIP_BROWSER=1
# skips Part 4 (npm). No custom llm_endpoint.local.sh exists in a clean
# checkout, so Part 3 self-skips.

load '../test_helper'

HERMES_SETUP="${_BATS_REAL_DOTFILES_ROOT}/hermes/setup.sh"
HERMES_CONFIG_SRC="${_BATS_REAL_DOTFILES_ROOT}/hermes/config.yaml"

setup() {
    setup_isolated_home
    STUB_BIN="$(mktemp -d)"
    cat > "${STUB_BIN}/hermes" <<'EOF'
#!/bin/sh
[ "$1" = "--version" ] && { echo "Hermes Agent v0.0.0-stub"; exit 0; }
exit 0
EOF
    chmod +x "${STUB_BIN}/hermes"
    export PATH="${STUB_BIN}:/usr/bin:/bin"
    export HERMES_SKIP_BROWSER=1
}

teardown() {
    teardown_isolated_home
    rm -rf "$STUB_BIN"
}

@test "config copy: missing file is seeded from the tracked template" {
    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "Seeded from"
    [ -f "${HOME}/.hermes/config.yaml" ]
    [ ! -L "${HOME}/.hermes/config.yaml" ]
    cmp -s "${HERMES_CONFIG_SRC}" "${HOME}/.hermes/config.yaml"
}

@test "config copy: legacy symlink is detached into a real file with live content preserved" {
    mkdir -p "${HOME}/.hermes"
    live_content="${HOME}/.hermes/.legacy-live-content.yaml"
    printf 'model:\n  provider: nous\n  default: some/model\n_config_version: 38\n' > "$live_content"
    ln -s "$live_content" "${HOME}/.hermes/config.yaml"

    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "Detached legacy symlink"

    [ -f "${HOME}/.hermes/config.yaml" ]
    [ ! -L "${HOME}/.hermes/config.yaml" ]
    cmp -s "$live_content" "${HOME}/.hermes/config.yaml"
    # The tracked template itself must never be touched by this migration.
    ! grep -q '_config_version' "${HERMES_CONFIG_SRC}"
}

@test "config copy: dangling legacy symlink falls back to seeding the template" {
    mkdir -p "${HOME}/.hermes"
    ln -s "/tmp/torn-down-DOES-NOT-EXIST/config.yaml" "${HOME}/.hermes/config.yaml"

    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "Detached legacy symlink"

    [ ! -L "${HOME}/.hermes/config.yaml" ]
    cmp -s "${HERMES_CONFIG_SRC}" "${HOME}/.hermes/config.yaml"
}

@test "config copy: an already-materialized real file is left untouched, even if diverged" {
    mkdir -p "${HOME}/.hermes"
    printf 'model:\n  provider: nous\n  default: my/chosen-model\n' > "${HOME}/.hermes/config.yaml"

    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "Local config already present"

    assert grep -q 'my/chosen-model' "${HOME}/.hermes/config.yaml"
    ! cmp -s "${HERMES_CONFIG_SRC}" "${HOME}/.hermes/config.yaml"
}

@test "config copy: idempotent — running twice in a row never re-symlinks or loses content" {
    run bash "${HERMES_SETUP}"
    assert_success
    first_content="$(cat "${HOME}/.hermes/config.yaml")"

    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "Local config already present"

    [ ! -L "${HOME}/.hermes/config.yaml" ]
    [ "$(cat "${HOME}/.hermes/config.yaml")" = "$first_content" ]
}
