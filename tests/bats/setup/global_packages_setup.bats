#!/usr/bin/env bats
# tests/bats/setup/global_packages_setup.bats
# Coverage for global-packages/setup.sh — syncs global uv tools from
# uv-tools.txt. `uv` is stubbed on a tight PATH so nothing touches the
# network or the developer's real uv tool installs.

load '../test_helper'

GP_SETUP="${_BATS_REAL_DOTFILES_ROOT}/global-packages/setup.sh"

setup() {
    setup_isolated_home
    STUB_BIN="$(mktemp -d)"
    UV_LOG="${STUB_BIN}/uv.log"
    UV_INSTALLED="${STUB_BIN}/installed.txt"
    : >"$UV_LOG"
    : >"$UV_INSTALLED"
    export UV_LOG UV_INSTALLED
    export GLOBAL_PACKAGES_LIST="${STUB_BIN}/uv-tools.txt"
    # /usr/bin + /bin only: the real uv and mise live under ~/.local and
    # must not satisfy `command -v`.
    export PATH="${STUB_BIN}:/usr/bin:/bin"
}

teardown() {
    teardown_isolated_home
    rm -rf "$STUB_BIN"
}

# uv stub: `tool list` prints $UV_INSTALLED; `tool dir` prints
# ${STUB_BIN}/tools (receipts live there); `tool install` logs its args and
# fails when UV_FAIL_SPEC matches the last arg.
stub_uv() {
    cat >"${STUB_BIN}/uv" <<'EOF'
#!/bin/sh
echo "$*" >>"$UV_LOG"
case "$1 $2" in
    "tool list") cat "$UV_INSTALLED"; exit 0 ;;
    "tool dir") echo "${UV_INSTALLED%/*}/tools"; exit 0 ;;
    "tool install")
        for last in "$@"; do :; done
        [ -n "${UV_FAIL_SPEC-}" ] && [ "$last" = "$UV_FAIL_SPEC" ] && exit 1
        exit 0 ;;
esac
exit 0
EOF
    chmod +x "${STUB_BIN}/uv"
}

@test "installs a missing spec with --native-tls" {
    stub_uv
    printf 'markitdown[all]\n' >"$GLOBAL_PACKAGES_LIST"
    run bash "$GP_SETUP"
    assert_success
    run grep -Fx 'tool install --native-tls markitdown[all]' "$UV_LOG"
    assert_success
}

@test "skips an already-installed tool" {
    stub_uv
    printf 'browser-use\n' >"$GLOBAL_PACKAGES_LIST"
    printf 'browser-use v0.13.8\n- browser-use\n' >"$UV_INSTALLED"
    run bash "$GP_SETUP"
    assert_success
    refute_output --partial '⚠'
    run grep -F 'tool install' "$UV_LOG"
    assert_failure
}

@test "strips extras and version specifiers when matching installed names" {
    stub_uv
    printf 'markitdown[all]\nruff>=0.5\n' >"$GLOBAL_PACKAGES_LIST"
    printf 'markitdown v0.1.5\n- markitdown\nruff v0.6.0\n- ruff\n' >"$UV_INSTALLED"
    run bash "$GP_SETUP"
    assert_success
    run grep -F 'tool install' "$UV_LOG"
    assert_failure
}

@test "ignores comments and blank lines" {
    stub_uv
    printf '# a comment\n\n   \nbrowser-use  # trailing\n' >"$GLOBAL_PACKAGES_LIST"
    run bash "$GP_SETUP"
    assert_success
    run grep -F 'tool install' "$UV_LOG"
    assert_output 'tool install --native-tls browser-use'
}

@test "warns about an unlisted installed tool and never uninstalls it" {
    stub_uv
    printf 'browser-use\n' >"$GLOBAL_PACKAGES_LIST"
    printf 'browser-use v0.13.8\n- browser-use\nhttpie v3.2.4\n- http\n' >"$UV_INSTALLED"
    run bash "$GP_SETUP"
    assert_success
    assert_output --partial '⚠'
    assert_output --partial 'httpie'
    run grep -F 'uninstall' "$UV_LOG"
    assert_failure
}

@test "exits 0 with a warning when uv and mise are both absent" {
    printf 'browser-use\n' >"$GLOBAL_PACKAGES_LIST"
    run bash "$GP_SETUP"
    assert_success
    assert_output --partial '⚠'
}

@test "exits 0 and continues when one install fails" {
    stub_uv
    export UV_FAIL_SPEC='bad-tool'
    printf 'bad-tool\nbrowser-use\n' >"$GLOBAL_PACKAGES_LIST"
    run bash "$GP_SETUP"
    assert_success
    assert_output --partial '⚠'
    run grep -Fx 'tool install --native-tls browser-use' "$UV_LOG"
    assert_success
}

@test "passes per-tool options through with the spec last" {
    stub_uv
    printf 'markitdown[all] --python 3.12 --with pip-system-certs  # why\n' >"$GLOBAL_PACKAGES_LIST"
    run bash "$GP_SETUP"
    assert_success
    run grep -Fx 'tool install --native-tls --python 3.12 --with pip-system-certs markitdown[all]' "$UV_LOG"
    assert_success
}

# Receipt for an installed markitdown built with python $1 and --with $2.
write_receipt() {
    mkdir -p "${STUB_BIN}/tools/markitdown"
    cat >"${STUB_BIN}/tools/markitdown/uv-receipt.toml" <<EOF
[tool]
requirements = [
    { name = "markitdown", extras = ["all"] },
    { name = "$2" },
]
python = "$1"
EOF
}

@test "skips an installed tool whose receipt matches its options" {
    stub_uv
    printf 'markitdown[all] --python 3.12 --with pip-system-certs\n' >"$GLOBAL_PACKAGES_LIST"
    printf 'markitdown v0.1.5\n- markitdown\n' >"$UV_INSTALLED"
    write_receipt 3.12 pip-system-certs
    run bash "$GP_SETUP"
    assert_success
    assert_output --partial '건너뜀: markitdown'
    run grep -F 'tool install' "$UV_LOG"
    assert_failure
}

@test "force-reinstalls an installed tool whose receipt is missing" {
    stub_uv
    printf 'markitdown[all] --python 3.12 --with pip-system-certs\n' >"$GLOBAL_PACKAGES_LIST"
    printf 'markitdown v0.1.5\n- markitdown\n' >"$UV_INSTALLED"
    run bash "$GP_SETUP"
    assert_success
    run grep -Fx 'tool install --native-tls --force --python 3.12 --with pip-system-certs markitdown[all]' "$UV_LOG"
    assert_success
}

@test "force-reinstalls when the receipt python differs" {
    stub_uv
    printf 'markitdown[all] --python 3.12 --with pip-system-certs\n' >"$GLOBAL_PACKAGES_LIST"
    printf 'markitdown v0.1.5\n- markitdown\n' >"$UV_INSTALLED"
    write_receipt 3.13 pip-system-certs
    run bash "$GP_SETUP"
    assert_success
    run grep -Fx 'tool install --native-tls --force --python 3.12 --with pip-system-certs markitdown[all]' "$UV_LOG"
    assert_success
}

@test "force-reinstalls when a --with package is missing from the receipt" {
    stub_uv
    printf 'markitdown[all] --python 3.12 --with pip-system-certs\n' >"$GLOBAL_PACKAGES_LIST"
    printf 'markitdown v0.1.5\n- markitdown\n' >"$UV_INSTALLED"
    write_receipt 3.12 other-pkg
    run bash "$GP_SETUP"
    assert_success
    run grep -Fx 'tool install --native-tls --force --python 3.12 --with pip-system-certs markitdown[all]' "$UV_LOG"
    assert_success
}
