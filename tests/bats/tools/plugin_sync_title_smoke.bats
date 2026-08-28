#!/usr/bin/env bats
# tests/bats/tools/plugin_sync_title_smoke.bats
# shell-common/functions/plugin_sync_title.sh — direct bash/zsh sourcing smoke
# test (#1558 codex review). The indirect coverage from claude_plugin_reconcile.bats
# and plugin_sync_hook.bats only proves the two *callers* work; this proves the
# file itself sources cleanly and defines its four functions under both loaders
# that auto-source shell-common/functions/*.sh (POSIX-only per its own header).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

FILE="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/plugin_sync_title.sh"

@test "plugin_sync_title.sh sources cleanly under bash and defines all four functions" {
    run bash --noprofile --norc -c "
        source '${FILE}'
        for f in _plugin_sync_read_json_or _changed_keys_marketplaces _changed_keys_plugins _build_sync_title _plugin_sync_title; do
            command -v \"\$f\" >/dev/null 2>&1 || { echo \"missing: \$f\"; exit 1; }
        done
        echo all-defined
    "
    assert_success
    assert_output --partial 'all-defined'
}

@test "plugin_sync_title.sh sources cleanly under zsh and defines all four functions" {
    run zsh --no-rcs -c "
        source '${FILE}'
        for f in _plugin_sync_read_json_or _changed_keys_marketplaces _changed_keys_plugins _build_sync_title _plugin_sync_title; do
            command -v \"\$f\" >/dev/null 2>&1 || { echo \"missing: \$f\"; exit 1; }
        done
        echo all-defined
    "
    assert_success
    assert_output --partial 'all-defined'
}

@test "_plugin_sync_title composes an end-to-end title under bash" {
    cat > "$TEST_TEMP_HOME/current-mp.json" <<'JSON'
{"kept": "org/kept"}
JSON
    cat > "$TEST_TEMP_HOME/current-pl.json" <<'JSON'
{"plugins": ["kept-plugin@kept"]}
JSON
    TARGET_MP='{"kept": "org/kept", "added": "org/added"}'
    TARGET_PL='["kept-plugin@kept", "added-plugin@added"]'

    run bash --noprofile --norc -c "
        source '${FILE}'
        _plugin_sync_title 'sync manifest' \
            '$TEST_TEMP_HOME/current-mp.json' '$TARGET_MP' \
            '$TEST_TEMP_HOME/current-pl.json' '$TARGET_PL'
    "
    assert_success
    assert_output 'sync manifest (+added +added-plugin@added)'
}

@test "_plugin_sync_title composes an end-to-end title under zsh" {
    cat > "$TEST_TEMP_HOME/current-mp.json" <<'JSON'
{"kept": "org/kept"}
JSON
    cat > "$TEST_TEMP_HOME/current-pl.json" <<'JSON'
{"plugins": ["kept-plugin@kept"]}
JSON
    TARGET_MP='{"kept": "org/kept", "added": "org/added"}'
    TARGET_PL='["kept-plugin@kept", "added-plugin@added"]'

    run zsh --no-rcs -c "
        source '${FILE}'
        _plugin_sync_title 'sync manifest' \
            '$TEST_TEMP_HOME/current-mp.json' '$TARGET_MP' \
            '$TEST_TEMP_HOME/current-pl.json' '$TARGET_PL'
    "
    assert_success
    assert_output 'sync manifest (+added +added-plugin@added)'
}
