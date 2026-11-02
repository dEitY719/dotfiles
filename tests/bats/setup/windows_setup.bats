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
    # A failed test can leave the read-only fixture behind; rm needs it back.
    chmod -R u+rwx "$TEST_TEMP_HOME" 2>/dev/null || true
    teardown_isolated_home
}

shift_enter_count() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(b.get("keys")=="shift+enter" for b in d["keybindings"]))' "$WT_SETTINGS_FILE"
}

bak_count() {
    find "$(dirname "$WT_SETTINGS_FILE")" -maxdepth 1 -name "$(basename "$WT_SETTINGS_FILE").bak-*" | wc -l
}

# Stdin becomes a sitecustomize module for the python3 that windows/setup.sh runs.
python_preload() {
    mkdir -p "${TEST_TEMP_HOME}/pylib"
    cat > "${TEST_TEMP_HOME}/pylib/sitecustomize.py"
    export PYTHONPATH="${TEST_TEMP_HOME}/pylib"
}

skip_if_root() {
    [ "$(id -u)" -ne 0 ] || skip "root ignores file permission bits"
}

@test "adds shift+enter sendInput ESC+CR once, idempotent on rerun" {
    printf '{"actions": [], "keybindings": [{"id": "Terminal.CopyToClipboard", "keys": "ctrl+c"}]}' > "$WT_SETTINGS_FILE"
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ "$(shift_enter_count)" = "1" ]
    python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["actions"][0]; assert a["command"]["input"]=="\x1b\r"' "$WT_SETTINGS_FILE"
    [ "$(bak_count)" = "1" ]

    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"이미 있음"* ]]
    [ "$(shift_enter_count)" = "1" ]
    [ "$(bak_count)" = "1" ]
}

# /mnt/c (9p) rejects utime, which shutil.copy2 calls after copying the bytes.
@test "binding is added on a filesystem that rejects utime (9p /mnt/c)" {
    python_preload <<'EOF'
import os


def _reject_utime(*args, **kwargs):
    raise PermissionError(1, "Operation not permitted")


os.utime = _reject_utime
EOF
    printf '{"actions": [], "keybindings": []}' > "$WT_SETTINGS_FILE"
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"바인딩 추가"* ]]
    [ "$(shift_enter_count)" = "1" ]
    [ "$(bak_count)" = "1" ]
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
    [[ "$output" == *"JSON 파싱 실패"* ]]
    [[ "$output" == *"line 1"* ]]
    [[ "$output" != *"쓰기 실패"* ]]
    [ "$(bak_count)" = "0" ]
}

@test "unwritable file warns about permissions and leaves no .bak" {
    skip_if_root
    printf '{"keybindings": []}' > "$WT_SETTINGS_FILE"
    chmod 444 "$WT_SETTINGS_FILE"
    before=$(cat "$WT_SETTINGS_FILE")
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ "$(cat "$WT_SETTINGS_FILE")" = "$before" ]
    [[ "$output" == *"쓰기 실패"* ]]
    [[ "$output" == *"Permission denied"* ]]
    [[ "$output" != *"JSON 파싱 실패"* ]]
    [ "$(bak_count)" = "0" ]
}

@test "unreadable file warns about permissions" {
    skip_if_root
    printf '{"keybindings": []}' > "$WT_SETTINGS_FILE"
    chmod 000 "$WT_SETTINGS_FILE"
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"쓰기 실패"* ]]
    [[ "$output" == *"Permission denied"* ]]
    [ "$(bak_count)" = "0" ]
}

@test "read-only directory warns about permissions and keeps the file" {
    skip_if_root
    mkdir "${TEST_TEMP_HOME}/ro"
    export WT_SETTINGS_FILE="${TEST_TEMP_HOME}/ro/settings.json"
    printf '{"keybindings": []}' > "$WT_SETTINGS_FILE"
    before=$(cat "$WT_SETTINGS_FILE")
    chmod 555 "${TEST_TEMP_HOME}/ro"
    run bash "$WIN_SETUP"
    chmod 755 "${TEST_TEMP_HOME}/ro"
    [ "$status" -eq 0 ]
    [ "$(cat "$WT_SETTINGS_FILE")" = "$before" ]
    [[ "$output" == *"쓰기 실패"* ]]
    [ "$(bak_count)" = "0" ]
}

# A 1 KiB file-size limit fails the settings write partway: the .bak is then the
# only intact copy, so F-3's cleanup must not delete it.
@test "write failing partway keeps the .bak as the only intact copy" {
    python3 -c 'import json,sys; json.dump({"keybindings": [], "pad": "x" * 900}, open(sys.argv[1], "w"))' "$WT_SETTINGS_FILE"
    before=$(cat "$WT_SETTINGS_FILE")
    python_preload <<'EOF'
import resource

resource.setrlimit(resource.RLIMIT_FSIZE, (1024, resource.getrlimit(resource.RLIMIT_FSIZE)[1]))
EOF
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"쓰기 실패"* ]]
    [[ "$output" == *"backup kept"* ]]
    [ "$(bak_count)" = "1" ]
    [ "$(cat "${WT_SETTINGS_FILE}".bak-*)" = "$before" ]
}

@test "valid JSON of an unexpected shape soft-fails with the cause" {
    printf '[]' > "$WT_SETTINGS_FILE"
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ "$(cat "$WT_SETTINGS_FILE")" = "[]" ]
    [[ "$output" == *"AttributeError"* ]]
    [[ "$output" != *"JSON 파싱 실패"* ]]
    [[ "$output" != *"쓰기 실패"* ]]
    [ "$(bak_count)" = "0" ]
}

@test "missing settings.json is a skip, not an error" {
    run bash "$WIN_SETUP"
    [ "$status" -eq 0 ]
    [ ! -e "$WT_SETTINGS_FILE" ]
}
