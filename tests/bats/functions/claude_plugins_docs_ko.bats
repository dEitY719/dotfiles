#!/usr/bin/env bats
# tests/bats/functions/claude_plugins_docs_ko.bats
# Coverage for generate_plugin_doc_ko's agy branch (issue #1767, #1769 codex
# BLOCKER: this call site had no regression coverage for the stream-json
# transport at all).

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    PLUGIN_FILE="$TEST_TEMP_HOME/plugin.md"
    OUTPUT_FILE="$TEST_TEMP_HOME/out_KO.md"
    printf '# A Plugin\n\nDoes a thing.\n' >"$PLUGIN_FILE"
}

teardown() {
    teardown_isolated_home
}

# Stub agy speaking the stream-json protocol: reads the {event:"user",...}
# NDJSON message on stdin, writes a diagnostic line to STDERR (the exact
# channel the pre-fix code merged into $output_file via `2>&1`), then the
# result event on stdout.
_stub_agy_success() {
    cat >"$STUB_BIN/agy" <<'STUB'
#!/usr/bin/env bash
printf 'agy-stub: diagnostic noise on stderr\n' >&2
jq -Rs '{event: "result", result: {status: "SUCCESS", response: "한국어 요약 결과"}}' </dev/null
exit 0
STUB
    chmod +x "$STUB_BIN/agy"
}

_stub_agy_error_status() {
    cat >"$STUB_BIN/agy" <<'STUB'
#!/usr/bin/env bash
printf 'agy-stub: diagnostic noise on stderr\n' >&2
printf '{"event":"result","result":{"status":"ERROR","error":"stub failure"}}\n'
exit 0
STUB
    chmod +x "$STUB_BIN/agy"
}

_run_generate() {
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:/usr/bin:/bin'
        . '${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        . '${DOTFILES_ROOT}/shell-common/functions/claude_plugins_docs_ko.sh'
        generate_plugin_doc_ko '${PLUGIN_FILE}' '${OUTPUT_FILE}' agy
        echo \"rc=\$?\"
    "
}

@test "generate_plugin_doc_ko agy: output file holds the response text only, no stderr noise (issue #1769 agy BLOCKER)" {
    _stub_agy_success

    _run_generate

    assert_output --partial "rc=0"
    [ -f "$OUTPUT_FILE" ]
    grep -q "한국어 요약 결과" "$OUTPUT_FILE"
    ! grep -q "diagnostic noise" "$OUTPUT_FILE"
}

@test "generate_plugin_doc_ko agy: non-SUCCESS result fails and removes the output file" {
    _stub_agy_error_status

    _run_generate

    refute_output --partial "rc=0"
    [ ! -f "$OUTPUT_FILE" ]
}
