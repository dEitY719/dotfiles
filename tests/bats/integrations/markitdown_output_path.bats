#!/usr/bin/env bats
# tests/bats/integrations/markitdown_output_path.bats
# markitdown wrapper (shell-common/tools/integrations/markitdown.sh): a source
# is saved as <name>.md in the cwd or --output-path DIR; -o, stdin and a
# redirected stdout keep the original stdout behavior.

load '../test_helper'

WRAPPER="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/markitdown.sh"

setup() {
    setup_isolated_home
    STUB_DIR="$TEST_TEMP_HOME/bin"
    STUB_LOG="$TEST_TEMP_HOME/markitdown.log"
    WORK="$TEST_TEMP_HOME/work"
    mkdir -p "$STUB_DIR" "$WORK"
    # Logs argv; writes "converted" to the -o file, else to stdout.
    cat >"$STUB_DIR/markitdown" <<EOF
#!/bin/sh
echo "ARGS=\$*" >'$STUB_LOG'
out=
while [ \$# -gt 0 ]; do
    [ "\$1" = -o ] && out=\$2
    shift
done
if [ -n "\$out" ]; then echo converted >"\$out"; else echo converted; fi
EOF
    chmod +x "$STUB_DIR/markitdown"
}

teardown() {
    teardown_isolated_home
}

# Runs the wrapper in $WORK. $1 = "tty" fakes a terminal stdout via script(1).
md() {
    local mode=$1
    shift
    printf '%s\n' "cd '$WORK' || exit 1" "PATH='$STUB_DIR':\$PATH" \
        "DOTFILES_FORCE_INIT=1" ". '$WRAPPER'" "markitdown $*" >"$TEST_TEMP_HOME/run.sh"
    if [ "$mode" = tty ]; then
        run script -qec "bash '$TEST_TEMP_HOME/run.sh'" /dev/null
    else
        run bash "$TEST_TEMP_HOME/run.sh"
    fi
}

@test "tty: saves a local file as <stem>.md in the cwd" {
    md tty report.pdf
    assert_success
    run cat "$WORK/report.md"
    assert_output converted
    run cat "$STUB_LOG"
    assert_output "ARGS=report.pdf -o ./report.md"
}

@test "tty: names a URL by its last path segment, dropping the query" {
    md tty "'https://youtube.com/shorts/nGKKWne_O2s?si=abc'"
    assert_success
    [ -f "$WORK/nGKKWne_O2s.md" ]
}

@test "tty: names a YouTube watch URL by its v= id" {
    md tty "'https://www.youtube.com/watch?v=ID123&t=5'"
    assert_success
    [ -f "$WORK/ID123.md" ]
}

@test "--output-path DIR saves into DIR and creates it" {
    md plain report.pdf --output-path out/sub
    assert_success
    run cat "$WORK/out/sub/report.md"
    assert_output converted
    run cat "$STUB_LOG"
    assert_output "ARGS=report.pdf -o out/sub/report.md"
}

@test "--output-path=DIR form works too" {
    md plain --output-path=out report.pdf
    assert_success
    [ -f "$WORK/out/report.md" ]
}

@test "value options keep their value and do not become the source" {
    md plain -x pdf report.bin --output-path out
    assert_success
    [ -f "$WORK/out/report.md" ]
    run cat "$STUB_LOG"
    assert_output "ARGS=-x pdf report.bin -o out/report.md"
}

@test "never overwrites an existing file" {
    echo keep >"$WORK/report.md"
    md tty report.pdf
    assert_failure
    run cat "$WORK/report.md"
    assert_output keep
}

@test "-o is passed through unchanged" {
    md tty report.pdf -o mine.md
    assert_success
    run cat "$STUB_LOG"
    assert_output "ARGS=report.pdf -o mine.md"
}

@test "redirected stdout without --output-path keeps stdout behavior" {
    md plain report.pdf
    assert_success
    assert_output converted
    [ ! -e "$WORK/report.md" ]
}

@test "stdin with --output-path is refused" {
    md plain --output-path out "</dev/null"
    assert_failure
    assert_output --partial '-o'
}
