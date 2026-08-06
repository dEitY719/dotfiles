#!/usr/bin/env bats
# tests/bats/skills/pbd_ms_lib.bats
# Unit coverage for claude/hooks/lib/pbd_ms.sh — the _pbd_ms epoch-milliseconds
# helper the #1258 stage-timing instrumentation depends on.
#
# Why a separate file instead of driving the dispatcher: post-bash-dispatch.sh
# reads stdin and `exit`s early, so it can never be sourced, and running it as a
# subprocess cannot exercise the no-EPOCHREALTIME tiers — a fresh
# `#!/usr/bin/env bash` repopulates EPOCHREALTIME regardless of what the parent
# shell unset. Sourcing the extracted library into THIS shell is what finally
# makes the BSD-date fallback tier reachable; that tier had zero coverage and
# had already regressed silently once.

load '../test_helper'

PBD_MS_LIB="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/lib/pbd_ms.sh"

setup() {
    setup_isolated_home
    # Safe: the library is a pure function definition with no top-level side
    # effects (no stdin read, no exit, no output).
    # shellcheck source=/dev/null
    . "$PBD_MS_LIB"
}

teardown() {
    teardown_isolated_home
}

@test "pbd_ms (#1258): the library sources cleanly and defines only _pbd_ms" {
    run bash -c ". '$PBD_MS_LIB' && declare -F _pbd_ms"
    assert_success
    assert_output '_pbd_ms'
}

@test "pbd_ms (#1258): EPOCHREALTIME snapshot → seconds + 3 fractional digits" {
    _pbd_ms result "1735999999.123456"
    [ "$result" = "1735999999123" ]
    # Locale decimal comma is handled by the same [.,] pattern.
    _pbd_ms result "1735999999,123456"
    [ "$result" = "1735999999123" ]
    # A short fraction is right-padded, never truncated into a bogus value.
    _pbd_ms result "1735999999.1"
    [ "$result" = "1735999999100" ]
}

@test "pbd_ms (#1258): BSD date (%3N unsupported) → whole-second fallback, no literal N" {
    # The coverage gap this closes. A BSD/macOS `date` does not understand
    # `%3N` and echoes the literal characters back; without the fallback tier
    # the timing row would carry `1735999999N` and hook-perf-report.sh would
    # silently drop it as malformed.
    local real_date stub_dir
    real_date="$(command -v date)"
    stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/date" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
+%s%3N) printf '%sN\n' "\$('$real_date' +%s)" ;;   # BSD: %N echoed literally
*) exec '$real_date' "\$@" ;;
esac
EOF
    chmod +x "$stub_dir/date"
    PATH="$stub_dir:$PATH"
    hash -r 2>/dev/null || true
    # A bash-4 host has no EPOCHREALTIME; the empty snapshot arg is what
    # actually selects the fallback branch, and unsetting keeps the simulated
    # host consistent. Safe because sourcing ran in THIS shell.
    unset EPOCHREALTIME

    _pbd_ms result ""
    [[ "$result" =~ ^[0-9]+000$ ]] || {
        echo "expected whole-second epoch-ms, got '$result'" >&2
        return 1
    }
}

@test "pbd_ms (#1258): no EPOCHREALTIME but working date → plausible epoch-ms" {
    # The everyday "EPOCHREALTIME somehow unset on an otherwise normal box"
    # case: `date` is not stubbed, so the GNU `%3N` tier answers.
    unset EPOCHREALTIME
    _pbd_ms result ""
    # Plausible epoch-ms (13 digits) rather than seconds — same assertion shape
    # as the dispatcher's timing tests.
    [[ "$result" =~ ^[0-9]{13}$ ]] || {
        echo "expected a 13-digit epoch-ms value, got '$result'" >&2
        return 1
    }
}
