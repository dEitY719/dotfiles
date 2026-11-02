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

@test "sitecustomize: installed into the hermes pinned python only when a corporate CA is set" {
    lib="${HOME}/.hermes/tools/python-3.99.0-linux-x64/lib/python3.99"
    mkdir -p "$lib"

    # The dev shell may already export a corporate CA; the no-CA case needs it unset.
    run env -u SSL_CERT_FILE bash "${HERMES_SETUP}"
    assert_success
    [ ! -e "${lib}/sitecustomize.py" ]

    SSL_CERT_FILE=/dev/null run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "installed sitecustomize.py"
    cmp -s "${_BATS_REAL_DOTFILES_ROOT}/hermes/sitecustomize.py" "${lib}/sitecustomize.py"
}

# --- Part 3: endpoint values from .enc.env (#2096) --------------------------
# sops is stubbed (plain copy of fake values); the hermes stub logs each
# `config set` key so the test proves the value went in without printing it.

_part3_stubs() {
    cat > "${STUB_BIN}/sops" <<'STUB'
#!/bin/sh
for last in "$@"; do :; done
cat "$last"
STUB
    cat > "${STUB_BIN}/hermes" <<STUB
#!/bin/sh
[ "\$1" = "--version" ] && { echo "Hermes Agent v0.0.0-stub"; exit 0; }
[ "\$1 \$2" = "config set" ] && echo "\$3=\$4" >> "${HOME}/hermes-set.log"
exit 0
STUB
    chmod +x "${STUB_BIN}/sops" "${STUB_BIN}/hermes"
    mkdir -p "${HOME}/.config/sops/age"
    printf 'AGE-SECRET-KEY-1FAKE\n' > "${HOME}/.config/sops/age/keys.txt"
    chmod 600 "${HOME}/.config/sops/age/keys.txt"
    export DOTFILES_ENC_ENV="${HOME}/fake.enc.env"
}

@test "endpoint: HERMES_LLM_* come from .enc.env and are never printed" {
    _part3_stubs
    printf 'HERMES_LLM_BASE_URL=https://fake-endpoint.invalid/v1\nHERMES_LLM_API_KEY=fake-key-123\nEXA_API_KEY=fake-exa\n' > "$DOTFILES_ENC_ENV"
    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "LLM endpoint values from .enc.env"
    assert_output --partial "set model.api_key (value not printed)"
    refute_output --partial "fake-key-123"
    refute_output --partial "fake-endpoint.invalid"
    grep -qx "model.base_url=https://fake-endpoint.invalid/v1" "${HOME}/hermes-set.log"
    grep -qx "model.api_key=fake-key-123" "${HOME}/hermes-set.log"
}

@test "endpoint: .enc.env without HERMES keys notes it and falls back" {
    _part3_stubs
    printf 'EXA_API_KEY=fake-exa\n' > "$DOTFILES_ENC_ENV"
    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial ".enc.env has no HERMES_LLM_BASE_URL"
    # An absent key is expected, not a problem: the line must be rendered by
    # ux_info (U+2139 info glyph), never ux_warning (U+26A0 warning glyph).
    local note_line
    note_line="$(printf '%s\n' "$output" | grep -F ".enc.env has no HERMES_LLM_BASE_URL")"
    [[ "$note_line" == *$'\xe2\x84\xb9'* ]] || fail "note not rendered as info: $note_line"
    [[ "$note_line" != *$'\xe2\x9a\xa0'* ]] || fail "note rendered as a warning: $note_line"
    assert_output --partial "No custom LLM endpoint configured"
    [ ! -e "${HOME}/hermes-set.log" ]
}

@test "endpoint: no age key warns and falls back without failing setup" {
    _part3_stubs
    rm "${HOME}/.config/sops/age/keys.txt"
    printf 'HERMES_LLM_API_KEY=fake-key-123\n' > "$DOTFILES_ENC_ENV"
    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "senv key import"
    assert_output --partial "No custom LLM endpoint configured"
    [ ! -e "${HOME}/hermes-set.log" ]
}

@test "endpoint: DOTFILES_SKIP_LOCAL_ENV skips the real .enc.env unless one is named" {
    _part3_stubs
    printf 'HERMES_LLM_API_KEY=fake-key-123\n' > "$DOTFILES_ENC_ENV"
    unset DOTFILES_ENC_ENV
    run bash "${HERMES_SETUP}"
    assert_success
    refute_output --partial "LLM endpoint values from .enc.env"
    refute_output --partial "senv key import"
    assert_output --partial "No custom LLM endpoint configured"
    [ ! -e "${HOME}/hermes-set.log" ]
}

# --- Part 2: CLI install (#2340) ---------------------------------------------
# hermes is absent and curl is stubbed, so run_remote_installer executes
# ${HOME}/installer.sh instead of the real one. Its body mimics the upstream
# wire_shell_path: a plain `>>`, which writes through a symlinked rc file and
# which no flag of the real installer disables.

_part2_stubs() {
    rm "${STUB_BIN}/hermes"
    cat > "${STUB_BIN}/curl" <<STUB
#!/bin/sh
while [ \$# -gt 0 ]; do
    [ "\$1" = "-o" ] && cp "${HOME}/installer.sh" "\$2"
    shift
done
exit 0
STUB
    chmod +x "${STUB_BIN}/curl"
    cat > "${HOME}/installer.sh" <<STUB
printf '%s\n' "\$*" > "${HOME}/installer-args"
for rc in .bashrc .bash_profile .zshrc .profile; do
    printf '\n# Hermes Agent command\nexport PATH=hermes\n' >> "${HOME}/\$rc"
done
${1:-}
exit 0
STUB
}

# ~/.bashrc, ~/.bash_profile and ~/.zshrc as setup.sh leaves them: symlinks into
# the repo (a stand-in dir here). ~/.profile is a real, untracked file.
_tracked_rc_links() {
    mkdir -p "${HOME}/dots"
    printf 'bash main\n' > "${HOME}/dots/main.bash"
    printf 'bash profile\n' > "${HOME}/dots/profile.bash"
    printf 'zsh main\n' > "${HOME}/dots/zshrc"
    ln -s "${HOME}/dots/main.bash" "${HOME}/.bashrc"
    ln -s "${HOME}/dots/profile.bash" "${HOME}/.bash_profile"
    ln -s "${HOME}/dots/zshrc" "${HOME}/.zshrc"
    printf 'local profile\n' > "${HOME}/.profile"
}

_assert_tracked_rc_clean() {
    [ "$(cat "${HOME}/dots/main.bash")" = "bash main" ]
    [ "$(cat "${HOME}/dots/profile.bash")" = "bash profile" ]
    [ "$(cat "${HOME}/dots/zshrc")" = "zsh main" ]
    [ -L "${HOME}/.bashrc" ]
    [ -L "${HOME}/.bash_profile" ]
    [ -L "${HOME}/.zshrc" ]
}

@test "install: the installer gets --non-interactive, so hermes setup never blocks" {
    _part2_stubs
    run bash "${HERMES_SETUP}"
    assert_success
    [ "$(cat "${HOME}/installer-args")" = "--non-interactive" ]
}

@test "install: a finished install tells the user to run hermes setup by hand" {
    _part2_stubs
    run bash "${HERMES_SETUP}"
    assert_success
    assert_output --partial "run it yourself: hermes setup"
    # A warning line, because step_run hides everything else in summary mode.
    assert_output --partial "⚠"
}

@test "install: an already-installed hermes gets no hermes setup prompt" {
    run bash "${HERMES_SETUP}"
    assert_success
    refute_output --partial "hermes setup"
}

@test "install: a failed install prints no hermes setup prompt and a safe retry" {
    _part2_stubs 'exit 1'
    run bash "${HERMES_SETUP}"
    assert_success
    refute_output --partial "run it yourself"
    assert_output --partial "Retry: ./hermes/setup.sh"
    refute_output --partial "| bash"
}

@test "install: lines appended through rc symlinks are reverted, with a warning" {
    _part2_stubs
    _tracked_rc_links
    run bash "${HERMES_SETUP}"
    assert_success
    _assert_tracked_rc_clean
    assert_output --partial "reverted the Hermes installer's edit to ~/.bashrc"
    assert_output --partial "reverted the Hermes installer's edit to ~/.bash_profile"
    assert_output --partial "reverted the Hermes installer's edit to ~/.zshrc"
}

@test "install: a real, untracked rc file keeps the installer's line" {
    _part2_stubs
    _tracked_rc_links
    run bash "${HERMES_SETUP}"
    assert_success
    grep -q 'export PATH=hermes' "${HOME}/.profile"
    refute_output --partial "edit to ~/.profile"
}

@test "install: uncommitted user edits already in the rc target survive the revert" {
    _part2_stubs
    _tracked_rc_links
    printf 'my unstaged edit\n' >> "${HOME}/dots/main.bash"
    run bash "${HERMES_SETUP}"
    assert_success
    [ "$(cat "${HOME}/dots/main.bash")" = "bash main
my unstaged edit" ]
}

@test "install: a failed installer still has its rc edits reverted" {
    _part2_stubs 'exit 1'
    _tracked_rc_links
    run bash "${HERMES_SETUP}"
    assert_success
    _assert_tracked_rc_clean
}

@test "install: an interrupted setup still has its rc edits reverted" {
    # $PPID is hermes/setup.sh: run_remote_installer runs `bash <file>` in-process.
    _part2_stubs 'kill -TERM $PPID; sleep 1'
    _tracked_rc_links
    run bash "${HERMES_SETUP}"
    [ "$status" -ne 0 ]
    _assert_tracked_rc_clean
}

@test "install: an rc change that is not a plain append is left alone, with a warning" {
    # git pull in the main checkout mid-install, say: restoring would undo it.
    _part2_stubs 'printf "rewritten\n" > "${HOME}/dots/main.bash"'
    _tracked_rc_links
    run bash "${HERMES_SETUP}"
    assert_success
    [ "$(cat "${HOME}/dots/main.bash")" = "rewritten" ]
    assert_output --partial "~/.bashrc changed during the Hermes install"
}
