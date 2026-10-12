#!/usr/bin/env bats
# tests/bats/functions/secret_run_real.bats
# secret-run against the real sops + age and mcporter binaries (issue #2105).
# secret_run.bats stubs sops with `cat`; these cases cover what the stub hides:
# real dotenv decrypt output, and mcporter expanding ${EXA_API_KEY:-}.
# Each case skips when its tools are not installed (CI has no guarantee).
# Only a throwaway age key and fake values are used: the real
# ~/.config/sops/age/keys.txt and the repo .enc.env are never read.

load '../test_helper'

setup() {
    setup_isolated_home
    KEY_FILE="$TEST_TEMP_HOME/.config/sops/age/keys.txt"
    REPO="$TEST_TEMP_HOME/repo"
    ENC="$REPO/.enc.env"
    WORK="$TEST_TEMP_HOME/work"
    CFG="$TEST_TEMP_HOME/.mcporter/mcporter.json"
    mkdir -p "$(dirname "$KEY_FILE")" "$REPO" "$WORK"
    # Pin sops to the throwaway key even if the developer exports their own.
    export SOPS_AGE_KEY_FILE="$KEY_FILE"
    unset SOPS_AGE_KEY SOPS_AGE_KEY_CMD
}

teardown() {
    teardown_isolated_home
}

_need() {
    local t
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || skip "$t not installed"
    done
}

# Make a throwaway age key (mode 600) and encrypt dotenv text $1 into $ENC
# with a temporary .sops.yaml. The plaintext only lives in a pipe.
_make_enc() {
    local pub
    age-keygen -o "$KEY_FILE" 2>/dev/null
    chmod 600 "$KEY_FILE"
    pub=$(age-keygen -y "$KEY_FILE")
    printf 'creation_rules:\n  - path_regex: \\.enc\\.env$\n    age: %s\n' "$pub" >"$REPO/.sops.yaml"
    printf '%s' "$1" | sops --config "$REPO/.sops.yaml" -e --input-type dotenv --output-type dotenv \
        --filename-override "$ENC" /dev/stdin >"$ENC"
    # The ciphertext must not carry the fake values in the clear.
    # `! cmd` is exempt from errexit, so test the match explicitly.
    # Long markers only: a short one like 'fake' can match base64 by chance.
    if grep -qF -e 'fake tok' -e 'fake-exa-key' "$ENC"; then
        echo "ciphertext leaks plaintext" >&2
        return 1
    fi
}

# Run $1 in a fresh dotfiles shell ($2: run_in_bash default, or run_in_zsh).
_sr() {
    "${2:-run_in_bash}" "export SOPS_AGE_KEY_FILE='$KEY_FILE' DOTFILES_ENC_ENV='$ENC'; cd '$WORK' && $1"
}

# Values that break naive parsing: spaces, both quotes, '=', $(...), backticks,
# and an escaped newline (sops keeps it as the two characters \n).
# The expected DQ/SQ/NL forms are what sops 3.x dotenv emits on decrypt (kept
# quotes, re-escaped \n); a sops upgrade that changes that store fails here
# first, before secret-run is suspected.
_FAKE='SP=fake tok with spaces
DQ="fake quoted"
SQ='"'"'fake single'"'"'
EQ=fake=a==b
CMD=$(touch pwned)
BT=`touch pwned2`
NL=fake1\nfake2
EXA_API_KEY=fake-exa-key
'

@test "real sops: secret-run injects tricky values literally, no eval, no plaintext file" {
    _need sops age age-keygen
    _make_enc "$_FAKE"
    cat >"$TEST_TEMP_HOME/show.sh" <<'SH'
#!/bin/sh
printf 'SP=[%s]\nDQ=[%s]\nSQ=[%s]\nEQ=[%s]\nCMD=[%s]\nBT=[%s]\nNL=[%s]\n' \
    "$SP" "$DQ" "$SQ" "$EQ" "$CMD" "$BT" "$NL"
SH
    _sr "dotfiles_secret_run sh '$TEST_TEMP_HOME/show.sh'; printf 'leak=%s\\n' \"\${SP-unset}\""
    assert_success
    assert_line "SP=[fake tok with spaces]"
    assert_line 'DQ=["fake quoted"]'
    assert_line "SQ=['fake single']"
    assert_line "EQ=[fake=a==b]"
    assert_line 'CMD=[$(touch pwned)]'
    assert_line 'BT=[`touch pwned2`]'
    assert_line 'NL=[fake1\nfake2]'
    assert_line "leak=unset"
    [ ! -e "$WORK/pwned" ]
    [ ! -e "$WORK/pwned2" ]
    # No plaintext anywhere: work dir empty, repo dir holds only config + ciphertext.
    [ -z "$(ls -A "$WORK")" ]
    [ "$(ls -A "$REPO" | sort | tr '\n' ' ')" = ".enc.env .sops.yaml " ]
    run grep -rl 'fake tok' "$TEST_TEMP_HOME"
    assert_failure
}

@test "real sops: -k limits injection and works under zsh" {
    _need sops age age-keygen zsh
    _make_enc "$_FAKE"
    _sr "dotfiles_secret_run -k CMD -k EQ sh -c 'echo \"\$CMD|\$EQ|\${SP-none}\"; exit 4'" run_in_zsh
    [ "$status" -eq 4 ]
    assert_output '$(touch pwned)|fake=a==b|none'
    [ ! -e "$WORK/pwned" ]
}

@test "real sops: a key that cannot decrypt warns and runs without values" {
    _need sops age age-keygen
    _make_enc "$_FAKE"
    age-keygen -o "$KEY_FILE.other" 2>/dev/null
    mv -f "$KEY_FILE.other" "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    _sr "dotfiles_secret_run sh -c 'echo ran:\${SP-none}; exit 3'"
    [ "$status" -eq 3 ]
    assert_output --partial "could not decrypt"
    assert_output --partial "ran:none"
    refute_output --partial "fake"
}

# mcporter config get resolves the config locally; it opens no connection.
# Its output can hold the key, so it is compared in the shell, never printed.
_mcporter_url_is() {
    run sh -c 'u=$(mcporter config get exa --json | jq -r .baseUrl) && [ "$u" = "$1" ] && echo match' _ "$1"
}

@test "mcporter expands \${EXA_API_KEY:-} in the placeholder config, empty when unset" {
    _need mcporter jq
    mkdir -p "$(dirname "$CFG")"
    printf '%s\n' '{"mcpServers":{"exa":{"baseUrl":"https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY:-}"}}}' >"$CFG"
    cd "$WORK"
    EXA_API_KEY=fake-exa-key _mcporter_url_is "https://mcp.exa.ai/mcp?exaApiKey=fake-exa-key"
    assert_success
    assert_output "match"
    unset EXA_API_KEY
    _mcporter_url_is "https://mcp.exa.ai/mcp?exaApiKey="
    assert_success
    assert_output "match"
}

@test "real sops + mcporter: mcporter-exa-setup then the wrapper feeds the key from .enc.env" {
    _need sops age age-keygen mcporter jq
    _make_enc "$_FAKE"
    _sr "mcporter_exa_setup >/dev/null && u=\$(mcporter config get exa --json | jq -r .baseUrl) && [ \"\$u\" = 'https://mcp.exa.ai/mcp?exaApiKey=fake-exa-key' ] && echo match; printf 'leak=%s\\n' \"\${EXA_API_KEY-unset}\""
    assert_success
    assert_line "match"
    assert_line "leak=unset"
    refute_output --partial "fake-exa-key"
}
