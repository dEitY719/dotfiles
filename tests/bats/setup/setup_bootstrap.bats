#!/usr/bin/env bats
# tests/bats/setup/setup_bootstrap.bats
# Root ./setup.sh seven-phase flow (#2343) driven end to end in a sandbox: a
# non-git copy of setup.sh + ux_lib/lib/util with every step script replaced by
# a tracing stub, a sandboxed $HOME and a PATH holding only what each test
# links in. The real installers, sudo and the network are unreachable, and
# without git on PATH setup.sh cannot canonicalize back to a real checkout.

load '../test_helper'

_REAL="${_BATS_REAL_DOTFILES_ROOT}"
# Resolved before setup() narrows PATH to the sandbox bin.
_JQ="$(command -v jq)"
BASE_TOOLS="bash sh cat grep sed dirname date mkdir rm tail head tr wc cut sort tee chmod ln touch id uname readlink mktemp sleep env ls"

_stub() { # _stub <path> [extra shell lines]
    mkdir -p "$(dirname "$1")"
    printf '#!/bin/sh\necho "%s" >>"$TRACE"\n%s\n' "${1#"$ROOT"/}" "${2:-}" >"$1"
    chmod +x "$1"
}

_tool() { # _tool <name> [body]: a fake command on the sandbox PATH
    printf '#!/bin/sh\necho "tool:%s $*" >>"$TRACE"\n%s\n' "$1" "${2:-}" >"$BIN/$1"
    chmod +x "$BIN/$1"
}

_all_tools() {
    local t
    for t in zsh gh socat mise uv sops age; do
        _tool "$t"
    done
    ln -sf "$_JQ" "$BIN/jq"
}

_age_key() {
    mkdir -p "$XDG_CONFIG_HOME/sops/age"
    echo key >"$XDG_CONFIG_HOME/sops/age/keys.txt"
}

setup() {
    setup_isolated_home
    export TMPDIR="$BATS_TEST_TMPDIR"
    ROOT="$BATS_TEST_TMPDIR/root"
    BIN="$BATS_TEST_TMPDIR/bin"
    export TRACE="$BATS_TEST_TMPDIR/trace"
    : >"$TRACE"
    mkdir -p "$ROOT/shell-common/tools" "$BIN"
    cp "$_REAL/setup.sh" "$ROOT/"
    cp -r "$_REAL/shell-common/tools/ux_lib" "$ROOT/shell-common/tools/"
    cp -r "$_REAL/shell-common/lib" "$_REAL/shell-common/util" "$_REAL/shell-common/env" "$ROOT/shell-common/"
    mkdir -p "$ROOT/shell-common/tools/custom/lib"
    cp "$_REAL/shell-common/tools/custom/lib/install_helpers.sh" "$ROOT/shell-common/tools/custom/lib/"
    local s
    for s in scripts/disable-git-crypt-local.sh scripts/setup-skills-ssot.sh scripts/verify-config-files.sh \
        bash/setup.sh zsh/setup.sh git/setup.sh obsidian/setup.sh herdr/setup.sh hermes/setup.sh claude/setup.sh \
        agy/setup.sh vscode-extensions/setup.sh .vscode/sync-push.sh global-packages/setup.sh mcporter/setup.sh \
        ssh/setup.sh gh/setup.sh windows/setup.sh claude/plugin/git-clone-skills.sh claude/plugin/restore.sh \
        shell-common/tools/custom/symlink-manager.sh shell-common/tools/custom/avatar_watched_repos.sh \
        shell-common/tools/custom/install_uv.sh shell-common/tools/custom/install_sops_age.sh; do
        _stub "$ROOT/$s"
    done
    _stub "$ROOT/shell-common/setup.sh" 'case "$2" in public|internal|external) echo "$2" >"$HOME/.dotfiles-setup-mode" ;; esac'
    _stub "$ROOT/shell-common/tools/custom/install_claude.sh" \
        'mkdir -p "$HOME/.local/bin"; printf "#!/bin/sh\necho \"claude \$*\" >>\"$TRACE\"\n" >"$HOME/.local/bin/claude"; chmod +x "$HOME/.local/bin/claude"'
    echo '{"plugins":[]}' >"$ROOT/claude/plugin/plugins.json"
    for s in $BASE_TOOLS; do ln -s "$(command -v "$s")" "$BIN/$s"; done
    _tool locale 'echo en_US.utf8'
    _tool apt-get
    _tool sudo 'echo "SUDO CALLED" >>"$TRACE"; exit 1'
    _tool curl 'echo "CURL CALLED" >>"$TRACE"; exit 7'
    export PATH="$BIN"
    export DOTFILES_SETUP_CHOICE=1
    unset DOTFILES_SETUP_VERBOSE SOPS_AGE_KEY_FILE
}

teardown() {
    teardown_isolated_home
}

_run_setup() {
    run "$_BASH" "$ROOT/setup.sh" "$@" </dev/null
}

_BASH="$(command -v bash)"

_order() { # _order <before> <after>: first trace hit of each, in order
    local a b
    a=$(grep -n -m1 -F -- "$1" "$TRACE" | cut -d: -f1)
    b=$(grep -n -m1 -F -- "$2" "$TRACE" | cut -d: -f1)
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

_provisioned_pc() {
    _tool claude
    _all_tools
    _tool gh 'case "$1 $2" in "auth token") echo secret-token ;; esac'
    _age_key
}

@test "#2343: fully provisioned public PC finishes all seven phases, no notice" {
    _provisioned_pc
    _run_setup
    assert_success
    assert_output --partial "[1/7] 모드 선택, 네트워크 설정"
    assert_output --partial "[3/7] 사전 조건 확인"
    assert_output --partial "[7/7] 검증과 요약"
    assert_output --partial "모두 정상"
    refute_output --partial "secret-token"
    run grep -c "SUDO CALLED\|CURL CALLED\|install_claude\|install_uv\|install_sops_age" "$TRACE"
    assert_output "0"
    _order "shell-common/setup.sh" "bash/setup.sh"
}

@test "#2343: re-run of a provisioned PC stays clean and makes no claude call" {
    _provisioned_pc
    _run_setup
    assert_success
    _run_setup
    assert_success
    assert_output --partial "모두 정상"
    run grep -c "tool:claude\|restore.sh" "$TRACE"
    assert_output "0"
}

@test "#2343 F-1: missing Claude Code installs after the network step, before prerequisites" {
    _all_tools
    _tool gh 'exit 0'
    _age_key
    _run_setup
    assert_success
    assert_output --partial "다른 터미널에서 claude"
    _order "shell-common/setup.sh" "tools/custom/install_claude.sh"
    _order "tools/custom/install_claude.sh" "bash/setup.sh"
    grep -q "install_claude.sh" "$TRACE"
}

@test "#2343 F-2: failed Claude install on public stops with proxy and CA checks" {
    _stub "$ROOT/shell-common/tools/custom/install_claude.sh" 'exit 1'
    _all_tools
    _run_setup
    assert_failure 1
    assert_output --partial "curl -I https://claude.ai"
    assert_output --partial "https_proxy"
    assert_output --partial "SSL_CERT_FILE"
    assert_output --partial "setup 을 중단합니다"
    run grep -c "bash/setup.sh" "$TRACE"
    assert_output "0"
}

@test "#2343 F-4/F-5/F-6: every missing item is printed at once, before any setup step, without sudo" {
    _tool claude
    _tool locale 'echo C'
    _tool gh
    _tool mise 'exit 1'
    _stub "$ROOT/shell-common/tools/custom/install_uv.sh" 'exit 1'
    _stub "$ROOT/shell-common/tools/custom/install_sops_age.sh" 'exit 1'
    _run_setup
    assert_failure 1
    assert_output --partial "zsh: sudo apt install -y zsh"
    assert_output --partial "en_US.UTF-8: sudo apt install -y locales && sudo locale-gen en_US.UTF-8"
    assert_output --partial "jq: sudo apt install -y jq"
    assert_output --partial "socat: sudo apt install -y socat"
    assert_output --partial "uv: ./shell-common/tools/custom/install_uv.sh --yes"
    assert_output --partial "sops: ./shell-common/tools/custom/install_sops_age.sh"
    assert_output --partial "age: ./shell-common/tools/custom/install_sops_age.sh"
    run grep -c "SUDO CALLED\|bash/setup.sh\|zsh/setup.sh" "$TRACE"
    assert_output "0"
}

@test "#2343 F-6: what needs no sudo is installed automatically and the run continues" {
    _provisioned_pc
    rm "$BIN/uv" "$BIN/sops" "$BIN/age"
    _stub "$ROOT/shell-common/tools/custom/install_uv.sh" 'ln -s /bin/true "$HOME/.local/bin/uv"'
    _stub "$ROOT/shell-common/tools/custom/install_sops_age.sh" 'ln -s /bin/true "$HOME/.local/bin/sops"; ln -s /bin/true "$HOME/.local/bin/age"'
    mkdir -p "$HOME/.local/bin"
    _run_setup
    assert_success
    assert_output --partial "모두 정상"
}

@test "#2343: tools only in the mise shims are not reported missing" {
    _provisioned_pc
    rm "$BIN/uv" "$BIN/sops" "$BIN/age"
    local shims="$XDG_DATA_HOME/mise/shims"
    mkdir -p "$shims"
    ln -s /bin/true "$shims/uv"
    ln -s /bin/true "$shims/sops"
    ln -s /bin/true "$shims/age"
    _run_setup
    assert_success
    run grep -c "install_uv\|install_sops_age" "$TRACE"
    assert_output "0"
}

@test "#2343: a tool mise reports without a shim is not reported missing" {
    _provisioned_pc
    rm "$BIN/age"
    _tool mise 'if [ "$1" = which ] && [ "$2" = age ]; then echo /opt/mise/age/age; exit 0; fi; exit 1'
    _run_setup
    assert_success
    run grep -c "install_sops_age" "$TRACE"
    assert_output "0"
}

@test "#2343 F-7: unauthenticated gh and missing age key stop with next steps, then re-run continues" {
    _tool claude
    _all_tools
    _tool gh 'exit 1'
    _run_setup
    assert_failure 1
    assert_output --partial "gh auth login"
    assert_output --partial "sops/age/keys.txt"
    run grep -c "bash/setup.sh" "$TRACE"
    assert_output "0"
    _tool gh 'exit 0'
    _age_key
    _run_setup
    assert_success
    grep -q "bash/setup.sh" "$TRACE"
}

@test "#2343 F-8: skills clone precedes skills-ssot; a plugin gap runs restore.sh" {
    _provisioned_pc
    echo '{"plugins":["a@m"]}' >"$ROOT/claude/plugin/plugins.json"
    _stub "$ROOT/claude/plugin/restore.sh" \
        'mkdir -p "$HOME/.claude-personal/plugins"; echo "{\"plugins\":{\"a@m\":[]}}" >"$HOME/.claude-personal/plugins/installed_plugins.json"'
    _run_setup
    assert_success
    assert_output --partial "모두 정상"
    _order "git-clone-skills.sh" "setup-skills-ssot.sh"
    _order "setup-skills-ssot.sh" "restore.sh"
}

@test "#2343 F-9: a restore that leaves a gap is a notice, not a warning or failure" {
    _provisioned_pc
    echo '{"plugins":["a@m"]}' >"$ROOT/claude/plugin/plugins.json"
    _run_setup
    assert_success
    assert_output --partial "안내 스텝: plugins"
    assert_output --partial "./claude/plugin/restore.sh"
    refute_output --partial "확인 필요"
}

@test "#2343 F-9: tombstoned plugins do not trigger restore.sh" {
    _provisioned_pc
    echo '{"plugins":["a@m","b@gone"]}' >"$ROOT/claude/plugin/plugins.json"
    echo '{"plugins":["a@m"],"marketplaces":["gone"]}' >"$ROOT/claude/plugin/removed.local.json"
    _run_setup
    assert_success
    run grep -c "restore.sh" "$TRACE"
    assert_output "0"
}

@test "#2343 F-9: no VS Code is silently skipped, not failed or warned" {
    _provisioned_pc
    _run_setup
    assert_success
    assert_output --partial "vscode-settings 건너뜀"
    assert_output --partial "모두 정상"
    run grep -c "sync-push" "$TRACE"
    assert_output "0"
}

@test "#2343 F-9: VS Code present runs the settings step" {
    _provisioned_pc
    _tool code
    _run_setup
    assert_success
    grep -q "sync-push" "$TRACE"
}

@test "#2343 F-9: avatar watch warnings are a notice in the summary" {
    _provisioned_pc
    _stub "$ROOT/shell-common/tools/custom/avatar_watched_repos.sh" 'echo "⚠️  skip x: y not found"'
    _run_setup
    assert_success
    assert_output --partial "skip x: y not found"
    assert_output --partial "안내 스텝: avatar-watched-repos"
    refute_output --partial "경고 스텝"
}

@test "#2343: internal PC with nothing installed never runs the installer and still finishes" {
    export DOTFILES_SETUP_CHOICE=2
    _run_setup
    assert_success
    assert_output --partial "internal PC 는 claude.ai 설치 프로그램을 자동으로 실행하지 않습니다"
    assert_output --partial "zsh: sudo apt install -y zsh"
    assert_output --partial "gh auth login"
    run grep -c "install_claude\|install_uv\|install_sops_age\|SUDO CALLED\|CURL CALLED" "$TRACE"
    assert_output "0"
    grep -q "verify-config-files.sh" "$TRACE"
}

@test "#2343: external PC installs Claude Code; failure is a notice and setup continues" {
    export DOTFILES_SETUP_CHOICE=3
    _stub "$ROOT/shell-common/tools/custom/install_claude.sh" 'exit 1'
    _run_setup
    assert_success
    grep -q "install_claude.sh" "$TRACE"
    assert_output --partial "curl -I https://claude.ai"
    assert_output --partial "안내 스텝:"
    grep -q "verify-config-files.sh" "$TRACE"
    run grep -c "install_uv\|install_sops_age" "$TRACE"
    assert_output "0"
}

@test "#2343: non-interactive run with no known mode stops before any step" {
    unset DOTFILES_SETUP_CHOICE
    _run_setup
    assert_failure
    assert_output --partial "DOTFILES_SETUP_CHOICE"
    [ ! -s "$TRACE" ]
}
