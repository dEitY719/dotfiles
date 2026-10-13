#!/usr/bin/env bats
# tests/bats/setup/mcporter_setup.bats
# Coverage for mcporter/setup.sh (issue #2106): converts mcporter.json's exa
# server to the ${EXA_API_KEY:-} placeholder from ./setup.sh. sops and mcporter
# are stubs; the "encrypted" .enc.env is a plain file of fake values.

load '../test_helper'

MC_SETUP="${_BATS_REAL_DOTFILES_ROOT}/mcporter/setup.sh"
PLACEHOLDER='https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY:-}'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/stubbin"
    KEY_FILE="$TEST_TEMP_HOME/.config/sops/age/keys.txt"
    ENC="$TEST_TEMP_HOME/repo/.enc.env"
    CFG="$TEST_TEMP_HOME/.mcporter/mcporter.json"
    mkdir -p "$STUB_BIN" "$(dirname "$KEY_FILE")" "$(dirname "$ENC")" "$(dirname "$CFG")"
    printf '#!/bin/sh\nfor last in "$@"; do :; done\ncat "$last"\n' >"$STUB_BIN/sops"
    printf '#!/bin/sh\nexit 0\n' >"$STUB_BIN/mcporter"
    chmod +x "$STUB_BIN"/*
    printf 'AGE-SECRET-KEY-1FAKE\n' >"$KEY_FILE"
    chmod 600 "$KEY_FILE"
    printf 'EXA_API_KEY=fake-exa\n' >"$ENC"
    printf '{"mcpServers":{"exa":{"baseUrl":"https://mcp.exa.ai/mcp?exaApiKey=OLDSECRET"}}}' >"$CFG"
    export DOTFILES_ENC_ENV="$ENC"
    # /usr/bin + /bin only (jq lives in /usr/bin): a real mcporter must not satisfy `command -v`.
    export PATH="$STUB_BIN:/usr/bin:/bin"
}

teardown() {
    teardown_isolated_home
}

@test "converts a literal key to the placeholder and never prints it" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    run bash "$MC_SETUP"
    assert_success
    refute_output --partial "OLDSECRET"
    [ "$(jq -r '.mcpServers.exa.baseUrl' "$CFG")" = "$PLACEHOLDER" ]
}

@test "second run is a no-op" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    bash "$MC_SETUP"
    before=$(cksum <"$CFG")
    run bash "$MC_SETUP"
    assert_success
    assert_output --partial "already uses"
    [ "$(cksum <"$CFG")" = "$before" ]
}

@test "mcporter not installed is skipped without touching the config" {
    rm "$STUB_BIN/mcporter"
    before=$(cksum <"$CFG")
    run bash "$MC_SETUP"
    assert_success
    assert_output --partial "not installed"
    [ "$(cksum <"$CFG")" = "$before" ]
}

@test "missing EXA_API_KEY warns, exits 0 and leaves the config unchanged" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    printf 'OTHER=x\n' >"$ENC"
    before=$(cksum <"$CFG")
    run bash "$MC_SETUP"
    assert_success
    assert_output --partial "setup incomplete"
    [ "$(cksum <"$CFG")" = "$before" ]
}
