#!/usr/bin/env bash
# git/tests/test_hooks.sh
#
# Minimal integration tests for the 2-tier hook system:
# - Global hook (core.hooksPath) runs first
# - Delegates to project hook at git/hooks/pre-commit
#
# This script creates temporary git repos under /tmp and runs real commits.

set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
export DOTFILES_ROOT SHELL_COMMON

if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
  # shellcheck source=/dev/null
  . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
else
  ux_header() { echo "$@"; }
  ux_info() { echo "$@"; }
  ux_success() { echo "$@"; }
  ux_error() { echo "$@" >&2; }
fi

die() {
  ux_error "$1"
  exit 1
}

assert_success() {
  local cmd="$1"
  if ! eval "$cmd" >/dev/null 2>&1; then
    die "Expected success but failed: $cmd"
  fi
}

assert_failure() {
  local cmd="$1"
  local out
  set +e
  out=$(eval "$cmd" 2>&1)
  local code=$?
  set -e
  if [ $code -eq 0 ]; then
    die "Expected failure but succeeded: $cmd"
  fi
  echo "$out" | grep -q "BLOCKING" || die "Expected BLOCKING output but got: $out"
}

make_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q
  git -C "$repo_dir" config user.email "hook-test@example.com"
  git -C "$repo_dir" config user.name "hook-test"

  mkdir -p "$repo_dir/.hooks"
  cp "${DOTFILES_ROOT}/git/global-hooks/pre-commit" "$repo_dir/.hooks/pre-commit"
  chmod +x "$repo_dir/.hooks/pre-commit"
  git -C "$repo_dir" config core.hooksPath "$repo_dir/.hooks"

  mkdir -p "$repo_dir/git/hooks"
  cp "${DOTFILES_ROOT}/git/hooks/pre-commit" "$repo_dir/git/hooks/pre-commit"
  chmod +x "$repo_dir/git/hooks/pre-commit"

  mkdir -p "$repo_dir/git/hooks/checks"
  cp -R "${DOTFILES_ROOT}/git/hooks/checks/." "$repo_dir/git/hooks/checks/"

  mkdir -p "$repo_dir/git/config"
  cp "${DOTFILES_ROOT}/git/config/hook-config.sh" "$repo_dir/git/config/hook-config.sh"

  mkdir -p "$repo_dir/bash" "$repo_dir/zsh"
  cat >"$repo_dir/bash/main.bash" <<'EOF'
#!/bin/bash
# placeholder init file
EOF
  cat >"$repo_dir/zsh/main.zsh" <<'EOF'
#!/bin/zsh
# placeholder init file
EOF

  git -C "$repo_dir" add bash/main.bash zsh/main.zsh
  git -C "$repo_dir" commit -m "init" -q
}

test_allows_spaces_in_filename() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  echo "ok" >"$repo_dir/file with spaces.txt"
  git -C "$repo_dir" add "file with spaces.txt"
  assert_success "git -C \"$repo_dir\" commit -m \"spaces\""

  rm -rf "$repo_dir"
}

test_blocks_forbidden_env_file() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  echo "SECRET=1" >"$repo_dir/.env.local"
  git -C "$repo_dir" add ".env.local"
  assert_failure "git -C \"$repo_dir\" commit -m \"env\""

  rm -rf "$repo_dir"
}

test_blocks_init_sourcing_tools_custom() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  {
    echo ""
    echo ". \"\${SHELL_COMMON}/tools/custom/demo_ux.sh\""
  } >>"$repo_dir/bash/main.bash"
  git -C "$repo_dir" add bash/main.bash
  assert_failure "git -C \"$repo_dir\" commit -m \"bad init\""

  rm -rf "$repo_dir"
}

test_blocks_auto_exec_custom_script_without_guard() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  mkdir -p "$repo_dir/shell-common/tools/custom"
  cat >"$repo_dir/shell-common/tools/custom/bad.sh" <<'EOF'
#!/bin/bash
main() {
  :
}
main "$@"
EOF

  git -C "$repo_dir" add shell-common/tools/custom/bad.sh
  assert_failure "git -C \"$repo_dir\" commit -m \"bad custom\""

  rm -rf "$repo_dir"
}

test_blocks_custom_script_wrong_shebang() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  mkdir -p "$repo_dir/shell-common/tools/custom"
  cat >"$repo_dir/shell-common/tools/custom/wrong_shebang.sh" <<'EOF'
#!/bin/sh
echo "hi"
EOF

  git -C "$repo_dir" add shell-common/tools/custom/wrong_shebang.sh
  assert_failure "git -C \"$repo_dir\" commit -m \"wrong shebang\""

  rm -rf "$repo_dir"
}

test_blocks_library_purity_top_level_read() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  mkdir -p "$repo_dir/shell-common/functions"
  cat >"$repo_dir/shell-common/functions/bad.sh" <<'EOF'
#!/bin/sh
bad_func() { :; }
read -r x
EOF

  git -C "$repo_dir" add shell-common/functions/bad.sh
  assert_failure "git -C \"$repo_dir\" commit -m \"bad purity\""

  rm -rf "$repo_dir"
}

test_blocks_library_purity_top_level_install() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  mkdir -p "$repo_dir/shell-common/tools/integrations"
  cat >"$repo_dir/shell-common/tools/integrations/bad.sh" <<'EOF'
#!/bin/sh
apt-get install -y something
EOF

  git -C "$repo_dir" add shell-common/tools/integrations/bad.sh
  assert_failure "git -C \"$repo_dir\" commit -m \"bad install\""

  rm -rf "$repo_dir"
}

main() {
  ux_header "Hook integration tests"
  test_allows_spaces_in_filename
  test_blocks_forbidden_env_file
  test_blocks_init_sourcing_tools_custom
  test_blocks_auto_exec_custom_script_without_guard
  test_blocks_custom_script_wrong_shebang
  test_blocks_library_purity_top_level_read
  test_blocks_library_purity_top_level_install
  ux_success "All hook tests passed"
}

main "$@"
