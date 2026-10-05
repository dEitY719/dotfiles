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
  # Fixture commits must not land on main/master: git/hooks/checks/main_branch_guard.sh
  # blocks those, which would fail every case here for the wrong reason
  # (git init picks main or master depending on init.defaultBranch).
  git -C "$repo_dir" symbolic-ref HEAD refs/heads/hook-fixture
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

test_allows_library_purity_commented_install() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  mkdir -p "$repo_dir/shell-common/tools/integrations"
  cat >"$repo_dir/shell-common/tools/integrations/ok.sh" <<'EOF'
#!/bin/sh
# Example:
#   npm install -g some-package
#   apt-get install -y something
alias foo='bar'
EOF

  git -C "$repo_dir" add shell-common/tools/integrations/ok.sh
  assert_success "git -C \"$repo_dir\" commit -m \"commented install ok\""

  rm -rf "$repo_dir"
}

test_blocks_hardcoded_home_path_in_zshrc() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  # Simulate the bun installer re-appending a resolved /home/<user> path.
  cat >>"$repo_dir/zsh/main.zsh" <<'EOF'
[ -s "/home/example-user/.bun/_bun" ] && source "/home/example-user/.bun/_bun"
EOF
  git -C "$repo_dir" add zsh/main.zsh
  assert_failure "git -C \"$repo_dir\" commit -m \"hardcoded bun path\""

  rm -rf "$repo_dir"
}

test_allows_hardcoded_home_path_with_marker() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  cat >>"$repo_dir/zsh/main.zsh" <<'EOF'
# allow-abs-home — example only, this PC's owner asked for a fixed path
[ -s "/home/example-user/.bun/_bun" ] && source "/home/example-user/.bun/_bun" # allow-abs-home
EOF
  git -C "$repo_dir" add zsh/main.zsh
  assert_success "git -C \"$repo_dir\" commit -m \"allow-listed path\""

  rm -rf "$repo_dir"
}

test_allows_home_var_reference() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  cat >>"$repo_dir/zsh/main.zsh" <<'EOF'
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
EOF
  git -C "$repo_dir" add zsh/main.zsh
  assert_success "git -C \"$repo_dir\" commit -m \"portable path\""

  rm -rf "$repo_dir"
}

# Issue #1142: a file that already carries a pre-existing absolute home path
# (debt predating the #737 guard) must NOT block an unrelated one-line edit —
# only added diff lines are scanned, so the untouched legacy line is ignored.
test_allows_preexisting_abs_home_on_unrelated_edit() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_repo "$repo_dir"

  # Seed legacy debt: commit an abs-home line while bypassing the guard,
  # simulating a path that landed before the guard existed.
  cat >"$repo_dir/zsh/legacy.zsh" <<'EOF'
#!/bin/zsh
[ -s "/home/example-user/.bun/_bun" ] && source "/home/example-user/.bun/_bun"
EOF
  git -C "$repo_dir" add zsh/legacy.zsh
  git -C "$repo_dir" commit -q --no-verify -m "legacy debt (pre-guard)"

  # Unrelated edit that does NOT touch the legacy line — must pass.
  cat >>"$repo_dir/zsh/legacy.zsh" <<'EOF'
export EDITOR=vim
EOF
  git -C "$repo_dir" add zsh/legacy.zsh
  assert_success "git -C \"$repo_dir\" commit -m \"unrelated edit of legacy file\""

  rm -rf "$repo_dir"
}

# Issue #1970 — commit-time leak guard. Fake patterns only.
LEAK_TEST_UPSTREAM='github\.com[:/]example-owner/example-repo(\.git)?$'
LEAK_TEST_PATTERNS='corp-internal\.example\.invalid|EMP[0-9]{5}'

make_leak_repo() {
  make_repo "$1"
  git -C "$1" remote add upstream "$2"
  echo "host = corp-internal.example.invalid" >"$1/leak.txt"
  git -C "$1" add leak.txt
}

test_leak_guard_blocks_without_echoing_match() {
  local repo_dir out code
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_leak_repo "$repo_dir" "git@github.com:example-owner/example-repo.git"

  set +e
  out=$(UPSTREAM_REMOTES_ERE="$LEAK_TEST_UPSTREAM" LEAK_PATTERNS_ERE="$LEAK_TEST_PATTERNS" \
    git -C "$repo_dir" commit -m "leak" 2>&1)
  code=$?
  set -e
  [ $code -ne 0 ] || die "Expected leak guard to block the commit"
  echo "$out" | grep -q "leak.txt:1" || die "Expected file:line in output, got: $out"
  if echo "$out" | grep -q "corp-internal.example.invalid"; then
    die "Leak guard echoed the matched text: $out"
  fi

  rm -rf "$repo_dir"
}

# Issue #1997 — a file NAME that matches is caught and never printed.
test_leak_guard_redacts_matching_path() {
  local repo_dir out code
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_leak_repo "$repo_dir" "git@github.com:example-owner/example-repo.git"
  mkdir "$repo_dir/d"
  echo clean >"$repo_dir/d/qx9FAKETOKEN77.conf"
  echo "qx9FAKETOKEN88 again" >"$repo_dir/d/qx9FAKETOKEN99.txt"
  git -C "$repo_dir" add -A

  set +e
  out=$(UPSTREAM_REMOTES_ERE="$LEAK_TEST_UPSTREAM" LEAK_PATTERNS_ERE="$LEAK_TEST_PATTERNS|qx9FAKE[A-Z]+[0-9]+" \
    git -C "$repo_dir" commit -m "path leak" 2>&1)
  code=$?
  set -e
  [ $code -ne 0 ] || die "Expected leak guard to block a matching path"
  if echo "$out" | grep -q "qx9FAKE"; then
    die "Leak guard echoed a matching path or text: $out"
  fi
  [ "$(echo "$out" | grep -cE "<redacted path: [0-9]+ chars, matches LEAK_PATTERNS_ERE>  \(use: git diff --cached --name-only")" -eq 2 ] \
    || die "Expected one redacted-path hint per matching path, got: $out"
  echo "$out" | grep -q "<redacted path: 20 chars>:1  (matches LEAK_PATTERNS_ERE)" \
    || die "Expected redacted path:line for content hit, got: $out"
  echo "$out" | grep -q "leak.txt:1" || die "Expected ordinary path to print normally, got: $out"

  rm -rf "$repo_dir"
}

test_leak_guard_inert_without_upstream_remote() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_leak_repo "$repo_dir" "git@private-mirror.example.invalid:team/dotfiles.git"
  assert_success "UPSTREAM_REMOTES_ERE='$LEAK_TEST_UPSTREAM' LEAK_PATTERNS_ERE='$LEAK_TEST_PATTERNS' git -C \"$repo_dir\" commit -m \"private only\""
  rm -rf "$repo_dir"
}

test_leak_guard_skip_escape_hatch() {
  local repo_dir
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_leak_repo "$repo_dir" "https://github.com/example-owner/example-repo.git"
  assert_success "SKIP_LEAK_GUARD=1 UPSTREAM_REMOTES_ERE='$LEAK_TEST_UPSTREAM' LEAK_PATTERNS_ERE='$LEAK_TEST_PATTERNS' git -C \"$repo_dir\" commit -m \"skip\""
  rm -rf "$repo_dir"
}

# ---------------------------------------------------------------------------
# Issue #1664 — global wrappers for the non-pre-commit hooks.
#
# core.hooksPath REPLACES .git/hooks for every repo on the machine, so
# git/hooks/pre-push & friends only ever run when a global wrapper forwards
# to them. Two properties matter and are asserted below:
#   1. In a repo that carries its own git/hooks/<name>, the wrapper delegates
#      (args, stdin and exit code passed through).
#   2. In any other repo the wrapper is a silent no-op — dotfiles-specific
#      logic (`mise run test`, protected branches, leak guard) must never
#      fire in an unrelated repository.
#
# The wrappers are invoked directly with synthetic argv/stdin (the technique
# git/test/test-pre-push.sh already uses) instead of driving a real push.
# ---------------------------------------------------------------------------

ZERO_SHA="0000000000000000000000000000000000000000"
GLOBAL_HOOKS_DIR="${DOTFILES_ROOT}/git/global-hooks"

# Throwaway repo with one commit and no project-level hooks at all.
make_plain_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q
  git -C "$repo_dir" config user.email "hook-test@example.com"
  git -C "$repo_dir" config user.name "hook-test"
  git -C "$repo_dir" config commit.gpgsign false

  echo "seed" >"$repo_dir/seed.txt"
  git -C "$repo_dir" add seed.txt
  git -C "$repo_dir" -c core.hooksPath=/dev/null commit -q -m "seed"
}

# Copy the real project-level pre-push (plus the rules file it sources) into
# a throwaway repo, mirroring this repo's layout.
install_project_pre_push() {
  local repo_dir="$1"

  mkdir -p "$repo_dir/git/hooks" "$repo_dir/git/config"
  cp "${DOTFILES_ROOT}/git/hooks/pre-push" "$repo_dir/git/hooks/pre-push"
  chmod +x "$repo_dir/git/hooks/pre-push"
  cp "${DOTFILES_ROOT}/git/config/pre-push-rules.sh" "$repo_dir/git/config/pre-push-rules.sh"
}

# Stub project hook that records the argv it was handed and exits with $3.
install_recording_project_hook() {
  local repo_dir="$1"
  local hook_name="$2"
  local exit_code="${3:-0}"

  mkdir -p "$repo_dir/git/hooks"
  cat >"$repo_dir/git/hooks/${hook_name}" <<EOF
#!/bin/bash
printf 'DELEGATED:%s\n' "\$*" >"${repo_dir}/.delegated"
exit ${exit_code}
EOF
  chmod +x "$repo_dir/git/hooks/${hook_name}"
}

# Run a global wrapper with $repo_dir as cwd. stdout+stderr land in
# $WRAPPER_OUT; the wrapper's exit code is returned. stdin is inherited so
# callers can feed the pre-push ref list.
run_global_hook() {
  local repo_dir="$1"
  local hook_name="$2"
  shift 2

  # `&& rc=0 || rc=$?` keeps the wrapper inside a tested context so the
  # suite's errexit does not abort on an intentionally failing hook.
  local out rc
  out=$(cd "$repo_dir" && "${GLOBAL_HOOKS_DIR}/${hook_name}" "$@" 2>&1) && rc=0 || rc=$?
  WRAPPER_OUT="$out"
  return "$rc"
}

# Every hook named by the SSOT must exist as an executable wrapper.
test_global_hook_set_matches_ssot() {
  # shellcheck source=../config/hook-config.sh
  . "${DOTFILES_ROOT}/git/config/hook-config.sh"

  if [ "${#GIT_GLOBAL_HOOKS[@]}" -eq 0 ]; then
    die "GIT_GLOBAL_HOOKS is empty — the global hook SSOT must not be empty"
  fi

  local hook_name
  for hook_name in "${GIT_GLOBAL_HOOKS[@]}"; do
    [ -f "${GLOBAL_HOOKS_DIR}/${hook_name}" ] ||
      die "Missing global hook wrapper: git/global-hooks/${hook_name}"
    [ -x "${GLOBAL_HOOKS_DIR}/${hook_name}" ] ||
      die "Global hook wrapper is not executable: git/global-hooks/${hook_name}"
  done
}

# Delegation: the real project pre-push runs and blocks a protected branch.
# The branch name arrives on stdin, so this also proves stdin passthrough.
test_global_pre_push_delegates_to_project_hook() {
  local repo_dir sha
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_plain_repo "$repo_dir"
  install_project_pre_push "$repo_dir"
  sha="$(git -C "$repo_dir" rev-parse HEAD)"

  if SKIP_LOCAL_PYTEST=1 run_global_hook "$repo_dir" pre-push \
    origin "https://github.com/owner/repo.git" \
    < <(printf 'refs/heads/main %s refs/heads/main %s\n' "$sha" "$ZERO_SHA"); then
    die "Expected the delegated pre-push to block a protected branch: $WRAPPER_OUT"
  fi

  echo "$WRAPPER_OUT" | grep -q "Delegating to project hook" ||
    die "Expected delegation notice but got: $WRAPPER_OUT"
  echo "$WRAPPER_OUT" | grep -q "Cannot push directly to protected branch" ||
    die "Expected protected-branch block but got: $WRAPPER_OUT"

  rm -rf "$repo_dir"
}

# THE regression that matters: a repo with no git/hooks/pre-push must get a
# silent no-op — no output, exit 0, and `mise run test` never invoked.
test_global_pre_push_is_noop_in_unrelated_repo() {
  local repo_dir sha stub_dir sentinel
  repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_plain_repo "$repo_dir"
  sha="$(git -C "$repo_dir" rev-parse HEAD)"

  # A mise stub that records any invocation. Nothing should ever call it.
  stub_dir="$repo_dir/.stub"
  sentinel="$repo_dir/.mise-invoked"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/mise" <<EOF
#!/bin/sh
printf 'MISE_CALLED:%s\n' "\$*" >>"${sentinel}"
exit 0
EOF
  chmod +x "$stub_dir/mise"

  # "main" is a PROTECTED_BRANCH for this repo — in an unrelated repo that
  # rule must not apply either.
  if ! PATH="${stub_dir}:${PATH}" run_global_hook "$repo_dir" pre-push \
    origin "https://github.com/owner/repo.git" \
    < <(printf 'refs/heads/main %s refs/heads/main %s\n' "$sha" "$ZERO_SHA"); then
    die "Global pre-push wrapper must be a no-op without a project hook: $WRAPPER_OUT"
  fi

  [ -z "$WRAPPER_OUT" ] ||
    die "Expected silent no-op but wrapper printed: $WRAPPER_OUT"
  [ ! -f "$sentinel" ] ||
    die "mise was invoked in an unrelated repo: $(cat "$sentinel")"

  rm -rf "$repo_dir"
}

# In a linked worktree `.git` is a FILE, not a directory (agy + codex review,
# PR #1674). A hook that ships only at the standard `.git/hooks/<name>`
# location (Husky-style — no `git/hooks/` or `.githooks/` candidate) must
# still be found and run when the wrapper is invoked from the worktree, not
# just from the main checkout.
test_global_pre_push_delegates_from_linked_worktree() {
  local main_dir wt_dir hook_target sha
  main_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  make_plain_repo "$main_dir"

  # $main_dir is a normal (non-worktree) repo, so its .git is a real
  # directory — a plain path join is fine here. The wrapper-under-test is
  # what must resolve this via --git-common-dir instead of a path join
  # (see delegate.sh / pre-commit); using --git-path here to build the
  # fixture would itself resolve against this machine's real
  # core.hooksPath when one is configured, planting the honeypot hook at
  # a real global location instead of inside the throwaway test repo.
  hook_target="$main_dir/.git/hooks/pre-push"
  mkdir -p "$(dirname "$hook_target")"
  cat >"$hook_target" <<EOF
#!/bin/bash
printf 'DELEGATED:%s\n' "\$*" >"${main_dir}/.delegated"
exit 0
EOF
  chmod +x "$hook_target"

  wt_dir="$(mktemp -u /tmp/dotfiles-hook-test.XXXXXX)"
  git -C "$main_dir" worktree add -q "$wt_dir" -b hook-fixture-wt >/dev/null 2>&1 ||
    die "Failed to create a linked worktree for the delegation test"

  [ -f "$wt_dir/.git" ] ||
    die "Expected the linked worktree's .git to be a file (test precondition)"

  sha="$(git -C "$wt_dir" rev-parse HEAD)"

  if SKIP_LOCAL_PYTEST=1 run_global_hook "$wt_dir" pre-push \
    origin "https://github.com/owner/repo.git" \
    < <(printf 'refs/heads/hook-fixture-wt %s refs/heads/hook-fixture-wt %s\n' "$sha" "$ZERO_SHA"); then
    :
  else
    die "Expected the pre-push wrapper to succeed from a linked worktree: $WRAPPER_OUT"
  fi

  echo "$WRAPPER_OUT" | grep -q "Delegating to project hook" ||
    die "Expected delegation notice from the linked worktree but got: $WRAPPER_OUT"
  [ -f "$main_dir/.delegated" ] ||
    die "Expected the shared .git/hooks/pre-push to run from the linked worktree: $WRAPPER_OUT"

  git -C "$main_dir" worktree remove -f "$wt_dir" >/dev/null 2>&1
  rm -rf "$main_dir" "$wt_dir"
}

# Every wrapper forwards argv to the project hook of the current repo.
test_global_wrappers_delegate_argv() {
  local hook_name repo_dir
  for hook_name in pre-push commit-msg prepare-commit-msg post-commit post-merge post-rewrite; do
    repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
    make_plain_repo "$repo_dir"
    install_recording_project_hook "$repo_dir" "$hook_name" 0

    run_global_hook "$repo_dir" "$hook_name" alpha beta </dev/null ||
      die "Expected ${hook_name} delegation to succeed: $WRAPPER_OUT"

    grep -q "^DELEGATED:alpha beta$" "$repo_dir/.delegated" ||
      die "Expected ${hook_name} to receive argv, got: $(cat "$repo_dir/.delegated" 2>/dev/null)"

    rm -rf "$repo_dir"
  done
}

# Every wrapper propagates the project hook's exit code verbatim.
test_global_wrappers_propagate_exit_code() {
  local hook_name repo_dir rc
  for hook_name in pre-push commit-msg prepare-commit-msg post-commit post-merge post-rewrite; do
    repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
    make_plain_repo "$repo_dir"
    install_recording_project_hook "$repo_dir" "$hook_name" 42

    rc=0
    run_global_hook "$repo_dir" "$hook_name" </dev/null || rc=$?

    [ "$rc" -eq 42 ] ||
      die "Expected ${hook_name} wrapper to exit 42, got ${rc}: $WRAPPER_OUT"

    rm -rf "$repo_dir"
  done
}

# No project hook of that type -> silent no-op for every wrapper.
test_global_wrappers_are_noop_without_project_hook() {
  local hook_name repo_dir
  for hook_name in pre-push commit-msg prepare-commit-msg post-commit post-merge post-rewrite; do
    repo_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
    make_plain_repo "$repo_dir"

    run_global_hook "$repo_dir" "$hook_name" </dev/null ||
      die "Expected ${hook_name} wrapper to exit 0 without a project hook: $WRAPPER_OUT"

    [ -z "$WRAPPER_OUT" ] ||
      die "Expected ${hook_name} wrapper to stay silent but got: $WRAPPER_OUT"

    rm -rf "$repo_dir"
  done
}

# Outside any git repository the wrappers must exit 0 without noise.
test_global_wrappers_are_noop_outside_git_repo() {
  local hook_name work_dir
  work_dir="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  # Detach from any enclosing repository (mktemp dirs live under /tmp).
  export GIT_CEILING_DIRECTORIES="$work_dir"

  for hook_name in pre-push commit-msg prepare-commit-msg post-commit post-merge post-rewrite; do
    run_global_hook "$work_dir" "$hook_name" </dev/null ||
      die "Expected ${hook_name} wrapper to exit 0 outside a repo: $WRAPPER_OUT"
    [ -z "$WRAPPER_OUT" ] ||
      die "Expected ${hook_name} wrapper to stay silent outside a repo: $WRAPPER_OUT"
  done

  unset GIT_CEILING_DIRECTORIES
  rm -rf "$work_dir"
}

# ---------------------------------------------------------------------------
# Issue #1838 — post-merge / post-rewrite graphify refresh
# ---------------------------------------------------------------------------

# Fixture: $GFY_DIR/upstream (branch main) cloned to $GFY_DIR/clone, a fake
# `graphify` in $GFY_DIR/bin that appends its argv to $GFY_DIR/calls.
# $1 = "graph" to create clone/graphify-out/graph.json (the opt-in signal).
setup_graphify_fixture() {
  GFY_DIR="$(mktemp -d /tmp/dotfiles-hook-test.XXXXXX)"
  mkdir -p "$GFY_DIR/bin"
  cat >"$GFY_DIR/bin/graphify" <<EOF
#!/bin/sh
echo "\$*" >>"$GFY_DIR/calls"
EOF
  chmod +x "$GFY_DIR/bin/graphify"

  git init -q -b main "$GFY_DIR/upstream"
  git -C "$GFY_DIR/upstream" config user.email "hook-test@example.com"
  git -C "$GFY_DIR/upstream" config user.name "hook-test"
  echo "seed" >"$GFY_DIR/upstream/seed.txt"
  git -C "$GFY_DIR/upstream" add seed.txt
  git -C "$GFY_DIR/upstream" -c core.hooksPath=/dev/null commit -q -m "seed"

  git clone -q "$GFY_DIR/upstream" "$GFY_DIR/clone"
  git -C "$GFY_DIR/clone" config user.email "hook-test@example.com"
  git -C "$GFY_DIR/clone" config user.name "hook-test"
  git -C "$GFY_DIR/clone" config commit.gpgsign false
  if [ "${1:-}" = graph ]; then
    mkdir -p "$GFY_DIR/clone/graphify-out"
    echo '{}' >"$GFY_DIR/clone/graphify-out/graph.json"
  fi
}

# A new upstream commit for the clone to pull.
advance_upstream() {
  echo "$1" >"$GFY_DIR/upstream/$1.txt"
  git -C "$GFY_DIR/upstream" add "$1.txt"
  git -C "$GFY_DIR/upstream" -c core.hooksPath=/dev/null commit -q -m "$1"
}

# Run git in the clone with the global wrappers active and the fake graphify
# first on PATH.
gfy_git() {
  PATH="$GFY_DIR/bin:$PATH" git -C "$GFY_DIR/clone" -c core.hooksPath="$GLOBAL_HOOKS_DIR" "$@"
}

# Count fake graphify calls. The call is backgrounded, so poll up to ~5s when
# one is expected; otherwise give a stray call a moment to land.
graphify_calls() {
  local expected="$1" i
  if [ "$expected" -gt 0 ]; then
    for i in $(seq 50); do
      [ -f "$GFY_DIR/calls" ] && break
      sleep 0.1
    done
  else
    sleep 0.5
  fi
  if [ -f "$GFY_DIR/calls" ]; then wc -l <"$GFY_DIR/calls" | tr -d ' '; else echo 0; fi
}

test_graphify_ff_pull_on_default_branch() {
  local n
  setup_graphify_fixture graph
  advance_upstream ff
  local out
  out=$(gfy_git pull -q --no-rebase --ff-only 2>&1) || die "ff pull failed"
  case "$out" in *"graphify: update started"*) ;; *) die "Expected graphify start notice, got: $out" ;; esac
  n=$(graphify_calls 1)
  [ "$n" -eq 1 ] || die "Expected 1 graphify call on ff pull, got $n"
  grep -qx "update ." "$GFY_DIR/calls" || die "Expected 'graphify update .', got: $(cat "$GFY_DIR/calls")"
  rm -rf "$GFY_DIR"
}

test_graphify_rebase_pull_on_default_branch() {
  local n
  setup_graphify_fixture graph
  advance_upstream remote
  echo local >"$GFY_DIR/clone/local.txt"
  git -C "$GFY_DIR/clone" add local.txt
  git -C "$GFY_DIR/clone" -c core.hooksPath=/dev/null commit -q -m local
  gfy_git pull -q --rebase >/dev/null 2>&1 || die "rebase pull failed"
  n=$(graphify_calls 1)
  [ "$n" -eq 1 ] || die "Expected 1 graphify call on rebase pull, got $n"
  rm -rf "$GFY_DIR"
}

# `git rebase origin/main` with nothing local to replay fires only
# post-checkout (inside .git/rebase-merge/), never post-rewrite.
test_graphify_ff_rebase_on_default_branch() {
  local n
  setup_graphify_fixture graph
  advance_upstream ffrebase
  git -C "$GFY_DIR/clone" fetch -q
  gfy_git rebase -q origin/main >/dev/null 2>&1 || die "ff rebase failed"
  n=$(graphify_calls 1)
  [ "$n" -eq 1 ] || die "Expected 1 graphify call on ff rebase, got $n"
  rm -rf "$GFY_DIR"
}

# A rebase that replays commits fires post-checkout AND post-rewrite; only
# post-rewrite may refresh, so the graph is rebuilt once, not twice.
test_graphify_replay_rebase_refreshes_once() {
  local n
  setup_graphify_fixture graph
  advance_upstream replay
  echo local >"$GFY_DIR/clone/local.txt"
  git -C "$GFY_DIR/clone" add local.txt
  git -C "$GFY_DIR/clone" -c core.hooksPath=/dev/null commit -q -m local
  git -C "$GFY_DIR/clone" fetch -q
  gfy_git rebase -q origin/main >/dev/null 2>&1 || die "replay rebase failed"
  graphify_calls 1 >/dev/null
  sleep 0.5
  n=$(graphify_calls 1)
  [ "$n" -eq 1 ] || die "Expected exactly 1 graphify call on replay rebase, got $n"
  rm -rf "$GFY_DIR"
}

# A plain branch switch stays graphify's own post-checkout job.
test_graphify_skips_branch_switch() {
  local n
  setup_graphify_fixture graph
  git -C "$GFY_DIR/clone" switch -q -c feature
  gfy_git switch -q main >/dev/null 2>&1 || die "switch failed"
  n=$(graphify_calls 0)
  [ "$n" -eq 0 ] || die "Expected no graphify call on branch switch, got $n"
  rm -rf "$GFY_DIR"
}

test_graphify_skips_commit_amend() {
  local n
  setup_graphify_fixture graph
  gfy_git commit -q --amend -m "amended" >/dev/null 2>&1 || die "amend failed"
  n=$(graphify_calls 0)
  [ "$n" -eq 0 ] || die "Expected no graphify call on commit --amend, got $n"
  rm -rf "$GFY_DIR"
}

test_graphify_skips_non_default_branch() {
  local n
  setup_graphify_fixture graph
  git -C "$GFY_DIR/clone" switch -q -c feature --track origin/main
  advance_upstream feat
  gfy_git pull -q --no-rebase --ff-only >/dev/null 2>&1 || die "feature pull failed"
  n=$(graphify_calls 0)
  [ "$n" -eq 0 ] || die "Expected no graphify call off the default branch, got $n"
  rm -rf "$GFY_DIR"
}

test_graphify_noop_without_graph_json() {
  local n
  setup_graphify_fixture
  advance_upstream nograph
  gfy_git pull -q --no-rebase --ff-only >/dev/null 2>&1 || die "pull without graph.json failed"
  PATH="$GFY_DIR/bin:$PATH" run_global_hook "$GFY_DIR/clone" post-merge 0 </dev/null ||
    die "Expected post-merge to exit 0 without graph.json: $WRAPPER_OUT"
  [ -z "$WRAPPER_OUT" ] || die "Expected no output without graph.json, got: $WRAPPER_OUT"
  n=$(graphify_calls 0)
  [ "$n" -eq 0 ] || die "Expected no graphify call without graph.json, got $n"
  [ ! -e "$GFY_DIR/clone/graphify-out" ] || die "Expected no graphify-out side effect"
  rm -rf "$GFY_DIR"
}

test_graphify_absent_pull_succeeds() {
  local dir no_gfy_path=""
  setup_graphify_fixture graph
  # Drop every PATH entry that provides a real graphify.
  local IFS=:
  for dir in $PATH; do
    [ -x "$dir/graphify" ] || no_gfy_path="${no_gfy_path:+$no_gfy_path:}$dir"
  done
  unset IFS
  advance_upstream absent
  PATH="$no_gfy_path" git -C "$GFY_DIR/clone" -c core.hooksPath="$GLOBAL_HOOKS_DIR" pull -q --no-rebase --ff-only >/dev/null 2>&1 ||
    die "Expected pull to succeed without graphify on PATH"
  PATH="$no_gfy_path" run_global_hook "$GFY_DIR/clone" post-merge 0 </dev/null ||
    die "Expected post-merge to exit 0 without graphify: $WRAPPER_OUT"
  [ ! -e "$GFY_DIR/clone/graphify-out/.hook-update.log" ] || die "Expected no graphify run"
  rm -rf "$GFY_DIR"
}

# graphify refresh must not swallow delegation: exit code and post-rewrite's
# stdin still reach the project hook.
test_graphify_keeps_project_hook_delegation() {
  local rc=0 n
  setup_graphify_fixture graph
  install_recording_project_hook "$GFY_DIR/clone" post-merge 7
  PATH="$GFY_DIR/bin:$PATH" run_global_hook "$GFY_DIR/clone" post-merge 0 </dev/null || rc=$?
  [ "$rc" -eq 7 ] || die "Expected post-merge exit 7 from project hook, got $rc: $WRAPPER_OUT"
  grep -q "^DELEGATED:0$" "$GFY_DIR/clone/.delegated" || die "Expected project post-merge to run"
  n=$(graphify_calls 1)
  [ "$n" -eq 1 ] || die "Expected 1 graphify call before delegation, got $n"

  cat >"$GFY_DIR/clone/git/hooks/post-rewrite" <<EOF
#!/bin/bash
cat >"$GFY_DIR/clone/.stdin"
EOF
  chmod +x "$GFY_DIR/clone/git/hooks/post-rewrite"
  PATH="$GFY_DIR/bin:$PATH" run_global_hook "$GFY_DIR/clone" post-rewrite rebase \
    < <(printf 'aaa bbb\n') || die "Expected post-rewrite delegation to succeed: $WRAPPER_OUT"
  grep -qx "aaa bbb" "$GFY_DIR/clone/.stdin" || die "Expected post-rewrite stdin to reach the project hook"
  rm -rf "$GFY_DIR"
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
  test_allows_library_purity_commented_install
  test_blocks_hardcoded_home_path_in_zshrc
  test_allows_hardcoded_home_path_with_marker
  test_allows_home_var_reference
  test_allows_preexisting_abs_home_on_unrelated_edit

  # Issue #1970 — commit-time leak guard
  test_leak_guard_blocks_without_echoing_match
  test_leak_guard_redacts_matching_path
  test_leak_guard_inert_without_upstream_remote
  test_leak_guard_skip_escape_hatch

  # Issue #1664 — global wrapper delegation for pre-push & friends
  test_global_hook_set_matches_ssot
  test_global_pre_push_delegates_to_project_hook
  test_global_pre_push_is_noop_in_unrelated_repo
  test_global_pre_push_delegates_from_linked_worktree
  test_global_wrappers_delegate_argv
  test_global_wrappers_propagate_exit_code
  test_global_wrappers_are_noop_without_project_hook
  test_global_wrappers_are_noop_outside_git_repo

  # Issue #1838 — graphify refresh on default-branch pulls
  test_graphify_ff_pull_on_default_branch
  test_graphify_rebase_pull_on_default_branch
  test_graphify_ff_rebase_on_default_branch
  test_graphify_replay_rebase_refreshes_once
  test_graphify_skips_branch_switch
  test_graphify_skips_commit_amend
  test_graphify_skips_non_default_branch
  test_graphify_noop_without_graph_json
  test_graphify_absent_pull_succeeds
  test_graphify_keeps_project_hook_delegation

  ux_success "All hook tests passed"
}

main "$@"
