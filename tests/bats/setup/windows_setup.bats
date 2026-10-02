#!/usr/bin/env bats
# tests/bats/setup/windows_setup.bats
# Coverage for windows/setup.sh — idempotent Shift+Enter merge into Windows
# Terminal settings.json. WT_SETTINGS_FILE points it at a temp file.

load '../test_helper'

WIN_SETUP="${_BATS_REAL_DOTFILES_ROOT}/windows/setup.sh"

setup() {
    setup_isolated_home
    export WT_SETTINGS_FILE="${TEST_TEMP_HOME}/settings.json"
}

teardown() {
    teardown_isolated_home
}

shift_enter_count() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(b.get("keys")=="shift+enter" for b in d["keybindings"]))' "$WT_SETTINGS_FILE"
}

@test "adds shift+enter sendInput ESC+CR once, idempotent on rerun" {
    printf '{"actions": [], "keybindings": [{"id": "Terminal.CopyToClipboard", "keys": "ctrl+c"}]}' > "$WT_SETTINGS_FILE"
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ "$(shift_enter_count)" = "1" ]
    python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["actions"][0]; assert a["command"]["input"]=="\x1b\r"' "$WT_SETTINGS_FILE"
    ls "${WT_SETTINGS_FILE}".bak-* >/dev/null

    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ "$(shift_enter_count)" = "1" ]
}

@test "existing user shift+enter binding is left untouched" {
    printf '{"keybindings": [{"id": "Mine", "keys": "shift+enter"}]}' > "$WT_SETTINGS_FILE"
    before=$(cat "$WT_SETTINGS_FILE")
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ "$(cat "$WT_SETTINGS_FILE")" = "$before" ]
}

@test "unparseable JSONC soft-fails without touching the file" {
    printf '{ // comment\n "keybindings": [] }' > "$WT_SETTINGS_FILE"
    before=$(cat "$WT_SETTINGS_FILE")
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ "$(cat "$WT_SETTINGS_FILE")" = "$before" ]
}

@test "missing settings.json is a skip, not an error" {
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ ! -e "$WT_SETTINGS_FILE" ]
}
