#!/usr/bin/env bats
# tests/bats/functions/secret_run.bats
# secret-run / mcporter / twitter wrappers and mcporter-exa-setup (issue #2096).
# sops is a stub: the "encrypted" .enc.env is a plain file of fake values, so no
# real age key or secret is involved (NF-3).

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/stubbin"
    KEY_FILE="$TEST_TEMP_HOME/.config/sops/age/keys.txt"
    ENC="$TEST_TEMP_HOME/repo/.enc.env"
    WORK="$TEST_TEMP_HOME/work"
    mkdir -p "$STUB_BIN" "$(dirname "$KEY_FILE")" "$(dirname "$ENC")" "$WORK"
    cat >"$STUB_BIN/sops" <<'STUB'
#!/bin/sh
[ -n "${SOPS_STUB_FAIL-}" ] && { echo "stub decrypt failure" >&2; exit 1; }
for last in "$@"; do :; done
cat "$last"
STUB
    # Stand-ins for the real CLIs: print what they received, nothing else.
    for t in twitter mcporter; do
        cat >"$STUB_BIN/$t" <<'STUB'
#!/bin/sh
printf 'argv=%s|exa=%s|tok=%s|ct0=%s|other=%s\n' "$*" "${EXA_API_KEY-}" "${TWITTER_AUTH_TOKEN-}" "${TWITTER_CT0-}" "${OTHER-}"
STUB
    done
    chmod +x "$STUB_BIN"/*
    printf 'AGE-SECRET-KEY-1FAKE\n' >"$KEY_FILE"
    chmod 600 "$KEY_FILE"
    printf '# fake values\nEXA_API_KEY=fake-exa\nTWITTER_AUTH_TOKEN=fake tok\nTWITTER_CT0=$(touch pwned)\nOTHER=fake-other\n' >"$ENC"
}

teardown() {
    teardown_isolated_home
}

# Run in $WORK (not the repo dir) with the stubs first on PATH. The stubs are
# also on PATH while the loader runs, because the wrappers are only defined
# when their CLI is installed.
_sr() {
    PATH="$STUB_BIN:$PATH" run_in_bash "PATH='$STUB_BIN:/usr/bin:/bin'; export DOTFILES_ENC_ENV='$ENC'; cd '$WORK' && $1"
}

@test "functions are defined after the bash loader runs" {
    _sr "declare -f dotfiles_secret_run mcporter twitter mcporter_exa_setup _senv_export_lines >/dev/null; alias secret-run"
    assert_success
    assert_output --partial "secret-run='dotfiles_secret_run'"
}

@test "secret-run injects values literally without changing cwd or writing files" {
    _sr "dotfiles_secret_run sh -c 'printf \"%s|%s|%s\\n\" \"\$PWD\" \"\$TWITTER_AUTH_TOKEN\" \"\$TWITTER_CT0\"'; printf 'after=%s\\n' \"\$PWD\"; printf 'leak=%s\\n' \"\${EXA_API_KEY-unset}\""
    assert_success
    assert_line "$WORK|fake tok|\$(touch pwned)"
    assert_line "after=$WORK"
    # The calling shell never holds the values.
    assert_line "leak=unset"
    [ ! -e "$WORK/pwned" ]
    [ -z "$(ls -A "$WORK")" ]
    [ "$(ls -A "$(dirname "$ENC")")" = ".enc.env" ]
}

@test "secret-run -k injects only the named keys" {
    _sr "dotfiles_secret_run -k EXA_API_KEY sh -c 'printf \"%s|%s\\n\" \"\$EXA_API_KEY\" \"\${OTHER-none}\"'"
    assert_success
    assert_output "fake-exa|none"
}

@test "secret-run propagates the exit code and needs a command" {
    _sr "dotfiles_secret_run sh -c 'exit 7'"
    [ "$status" -eq 7 ]
    _sr "dotfiles_secret_run"
    [ "$status" -eq 2 ]
    assert_output --partial "secret-run needs a command"
    _sr "dotfiles_secret_run -k"
    [ "$status" -eq 2 ]
}

@test "decrypt failure warns and runs the command without values" {
    _sr "SOPS_STUB_FAIL=1 dotfiles_secret_run sh -c 'printf \"ran:%s\\n\" \"\${EXA_API_KEY-none}\"; exit 3'"
    [ "$status" -eq 3 ]
    assert_output --partial "could not decrypt"
    assert_output --partial "ran:none"
    refute_output --partial "fake-exa"
}

@test "missing key file warns with senv key import and still runs" {
    rm "$KEY_FILE"
    _sr "dotfiles_secret_run sh -c 'echo ran'"
    assert_success
    assert_output --partial "senv key import"
    assert_output --partial "ran"
}

@test "key file not mode 600 is refused with a chmod hint" {
    chmod 644 "$KEY_FILE"
    _sr "dotfiles_secret_run sh -c 'printf \"ran:%s\\n\" \"\${EXA_API_KEY-none}\"'"
    assert_success
    assert_output --partial "chmod 600"
    assert_output --partial "ran:none"
}

@test "missing sops warns and runs" {
    rm "$STUB_BIN/sops"
    { [ -x /usr/bin/sops ] || [ -x /bin/sops ]; } && skip "a real sops is on the test PATH"
    _sr "dotfiles_secret_run sh -c 'echo ran'"
    assert_success
    assert_output --partial "sops not installed"
    assert_output --partial "ran"
}

@test "missing .enc.env warns and runs" {
    rm "$ENC"
    _sr "dotfiles_secret_run sh -c 'echo ran'"
    assert_success
    assert_output --partial ".enc.env not found"
    assert_output --partial "ran"
}

@test "twitter wrapper passes only the Twitter cookies to the real binary" {
    _sr "twitter status"
    assert_success
    assert_output "argv=status|exa=|tok=fake tok|ct0=\$(touch pwned)|other="
}

@test "mcporter wrapper passes only EXA_API_KEY" {
    _sr "mcporter list"
    assert_success
    assert_output "argv=list|exa=fake-exa|tok=|ct0=|other="
}

@test "mcporter-exa-setup swaps a literal key for the placeholder and keeps other servers" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    mkdir -p "$HOME/.mcporter"
    printf '{"mcpServers":{"exa":{"baseUrl":"https://mcp.exa.ai/mcp?exaApiKey=OLDSECRET","x":1},"other":{"command":"o"}}}' >"$HOME/.mcporter/mcporter.json"
    _sr "mcporter_exa_setup"
    assert_success
    refute_output --partial "OLDSECRET"
    cfg="$HOME/.mcporter/mcporter.json"
    [ "$(jq -r '.mcpServers.exa.baseUrl' "$cfg")" = 'https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY:-}' ]
    [ "$(jq -r '.mcpServers.exa.x' "$cfg")" = "1" ]
    [ "$(jq -r '.mcpServers.other.command' "$cfg")" = "o" ]
    run grep -q OLDSECRET "$cfg"
    assert_failure
    [ "$(stat -c '%a' "$cfg" 2>/dev/null || stat -f '%Lp' "$cfg")" = "600" ]
    # Idempotent, and creates the file when absent.
    rm "$cfg"
    _sr "mcporter_exa_setup && mcporter_exa_setup"
    assert_success
    [ "$(jq -r '.mcpServers.exa.baseUrl' "$cfg")" = 'https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY:-}' ]
}

@test "mcporter-exa-setup replaces a url field too" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    mkdir -p "$HOME/.mcporter"
    printf '{"mcpServers":{"exa":{"url":"https://mcp.exa.ai/mcp?exaApiKey=OLDSECRET"}}}' >"$HOME/.mcporter/mcporter.json"
    _sr "mcporter_exa_setup"
    assert_success
    [ "$(jq -r '.mcpServers.exa | keys | join(",")' "$HOME/.mcporter/mcporter.json")" = "baseUrl" ]
}

@test "mcporter-exa-setup refuses when .enc.env has no EXA_API_KEY, cannot decrypt, or the config is a symlink" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    mkdir -p "$HOME/.mcporter"
    cfg="$HOME/.mcporter/mcporter.json"
    printf '{"mcpServers":{"exa":{"baseUrl":"https://mcp.exa.ai/mcp?exaApiKey=OLDSECRET"}}}' >"$cfg"

    printf 'OTHER=x\nEXA_API_KEY=\n' >"$ENC"
    _sr "mcporter_exa_setup"
    assert_failure
    assert_output --partial "no EXA_API_KEY"
    grep -q OLDSECRET "$cfg"

    printf 'EXA_API_KEY=fake-exa\n' >"$ENC"
    _sr "SOPS_STUB_FAIL=1 mcporter_exa_setup"
    assert_failure
    assert_output --partial "left unchanged"
    grep -q OLDSECRET "$cfg"

    mv "$cfg" "$HOME/real.json"
    ln -s "$HOME/real.json" "$cfg"
    _sr "mcporter_exa_setup"
    assert_failure
    assert_output --partial "symlink"
    [ -L "$cfg" ]
    refute_output --partial "OLDSECRET"
}

@test "wrappers are not defined when their CLI is not installed" {
    rm "$STUB_BIN/twitter" "$STUB_BIN/mcporter"
    command -v twitter >/dev/null 2>&1 && skip "a real twitter is installed"
    command -v mcporter >/dev/null 2>&1 && skip "a real mcporter is installed"
    _sr "type twitter; type mcporter; true"
    refute_output --partial "is a function"
}

@test "zsh: secret-run injects literally, keeps cwd, propagates exit code" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run_in_zsh "PATH='$STUB_BIN:/usr/bin:/bin'; export DOTFILES_ENC_ENV='$ENC'; cd '$WORK' && dotfiles_secret_run -k TWITTER_CT0 -k OTHER sh -c 'echo \"\$PWD|\$TWITTER_CT0|\$OTHER|\${EXA_API_KEY-none}\"; exit 5'"
    [ "$status" -eq 5 ]
    assert_output "$WORK|\$(touch pwned)|fake-other|none"
    [ ! -e "$WORK/pwned" ]
}
