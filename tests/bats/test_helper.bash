#!/usr/bin/env bash
# tests/bats/test_helper.bash
# Common helper for all bats tests.
# Provides environment isolation and dotfiles loading via subprocesses.

# Load bats libraries
_BATS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
load "${_BATS_LIB_DIR}/bats-support/load"
load "${_BATS_LIB_DIR}/bats-assert/load"

# Project paths
export DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

# Frozen snapshot. setup_isolated_dotfiles_root overrides DOTFILES_ROOT for
# its caller's test body; setup_isolated_home / teardown_isolated_home use
# this snapshot to restore the real-tree value before/after each test so a
# stale override from the previous test cannot leak.
_BATS_REAL_DOTFILES_ROOT="$DOTFILES_ROOT"
_BATS_REAL_SHELL_COMMON="$SHELL_COMMON"

# Test isolation
export DOTFILES_TEST_MODE=1
export DOTFILES_FORCE_INIT=1

setup_isolated_home() {
    # Restore real DOTFILES_ROOT first — the previous test may have pointed
    # it at a (now-deleted) isolated tree via setup_isolated_dotfiles_root.
    export DOTFILES_ROOT="$_BATS_REAL_DOTFILES_ROOT"
    export SHELL_COMMON="$_BATS_REAL_SHELL_COMMON"

    TEST_TEMP_HOME="$(mktemp -d)"
    export HOME="$TEST_TEMP_HOME"
    # An isolated $HOME is NOT isolation while CLAUDE_CONFIG_DIR still points
    # at the developer's real account dir: every `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`
    # consumer (statusline-command.sh, session-start-settings-drift.sh,
    # aws/setup.sh's #1364 hook re-registration, …) would escape the sandbox and
    # write to the live config. Suites that need the override set it themselves
    # (see tests/bats/skills/session_start_settings_drift_hook.bats).
    unset CLAUDE_CONFIG_DIR
    export ZDOTDIR="$TEST_TEMP_HOME"
    export XDG_CONFIG_HOME="$TEST_TEMP_HOME"
    export XDG_CACHE_HOME="$TEST_TEMP_HOME"
    export XDG_DATA_HOME="$TEST_TEMP_HOME"
    export TERM=dumb
}

teardown_isolated_home() {
    if [ -n "$TEST_TEMP_HOME" ] && [ -d "$TEST_TEMP_HOME" ]; then
        rm -rf "$TEST_TEMP_HOME"
    fi
    export DOTFILES_ROOT="$_BATS_REAL_DOTFILES_ROOT"
    export SHELL_COMMON="$_BATS_REAL_SHELL_COMMON"
}

# Stage an isolated DOTFILES_ROOT for tests that invoke claude/setup.sh or
# write to ${DOTFILES_ROOT}/claude/. Without this, setup.sh leaves
# `settings.json.pre-statusline-fix-*` backup files in the version-controlled
# tree and fixture writes mutate the gitignored claude/settings.json — both
# survive interrupted runs (issue #303).
#
# Layout: $TEST_TEMP_HOME/dotfiles-iso/
#   bash, zsh, shell-common  → symlinks to real tree (read-only by tests)
#   claude/                  → real dir (mutable; setup.sh writes backups here)
#     setup.sh               → cp of real (NOT symlink — setup.sh resolves
#                              DOTFILES_ROOT via realpath of its own path,
#                              so a symlink would escape isolation)
#     statusline-command.sh  → symlink (read-only)
#     settings.json          → cp of real tracked SSOT (mutable copy; see #584)
#     skills/, docs/, global-memory/ → empty dirs (satisfy setup.sh's
#                              `[ -d ]` source-existence guards)
#
# Side effect: re-exports DOTFILES_ROOT and SHELL_COMMON to point at the
# isolated tree. teardown_isolated_home restores the real values.
# Precondition: setup_isolated_home must have run (TEST_TEMP_HOME exists).
setup_isolated_dotfiles_root() {
    # Hard-fail if the precondition isn't met. Without this, an empty
    # TEST_TEMP_HOME makes `iso_root` resolve to `/dotfiles-iso` (system root).
    [ -n "$TEST_TEMP_HOME" ] || {
        echo "setup_isolated_dotfiles_root: TEST_TEMP_HOME not set — call setup_isolated_home first" >&2
        return 1
    }
    local real_root="$_BATS_REAL_DOTFILES_ROOT"
    local iso_root="$TEST_TEMP_HOME/dotfiles-iso"

    mkdir -p "$iso_root/claude"
    ln -s "$real_root/shell-common" "$iso_root/shell-common"
    ln -s "$real_root/bash" "$iso_root/bash"
    ln -s "$real_root/zsh" "$iso_root/zsh"

    cp "$real_root/claude/setup.sh" "$iso_root/claude/setup.sh"
    ln -s "$real_root/claude/statusline-command.sh"  "$iso_root/claude/statusline-command.sh"

    mkdir -p "$iso_root/claude/skills" "$iso_root/claude/docs" "$iso_root/claude/global-memory" \
        "$iso_root/claude/workflows"
    cp "$real_root/claude/CLAUDE.md" "$iso_root/claude/CLAUDE.md"

    if [ -f "$real_root/claude/settings.json" ]; then
        cp "$real_root/claude/settings.json" "$iso_root/claude/settings.json"
    else
        echo '{}' > "$iso_root/claude/settings.json"
    fi

    export DOTFILES_ROOT="$iso_root"
    export SHELL_COMMON="$iso_root/shell-common"
}

# Run a command in bash subprocess with dotfiles loaded.
#
# DOTFILES_ROOT_NO_CANONICALIZE=1 bypasses the worktree-canonicalization
# helper (issue #589) that bash/main.bash and zsh/main.zsh would otherwise
# use to rewrite ${DOTFILES_ROOT} from this worktree's path back to the
# main repo. Tests need to exercise the worktree's code, not whatever
# is installed at ~/dotfiles.
run_in_bash() {
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export TERM=dumb
        source '${DOTFILES_ROOT}/bash/main.bash'
        $1
    "
}

# Quote each argument with printf %q and print them space-joined, for
# interpolation into a `bash -c "..."` command string (e.g. a `for x in ...`
# list built from bats args). Assign the result with `args_q="$(quote_args ...)"`.
quote_args() {
    local q="" arg
    for arg in "$@"; do
        q+=" $(printf '%q' "$arg")"
    done
    printf '%s' "$q"
}

# Run BODY in a bash subprocess after sourcing a tools/custom/*.sh script that
# resolves its own dependencies via `source "$(dirname "$0")/init.sh"`.
#
# Sourcing under `bash -c` makes $0 == "bash", so `dirname "$0"` would resolve
# relative to the caller's cwd instead of the script's — hence the leading
# `cd` into TOOLS_DIR before sourcing. DOTFILES_TEST_MODE=1 makes init.sh
# return before defining ux_*, so any doubles installed in BODY are the only
# implementations in play. The script's own main() stays dormant: its
# direct-exec guard compares BASH_SOURCE[0] against $0, which never matches
# while sourced.
#
# Usage: run_sourced_tool_script TOOLS_DIR SCRIPT BODY
run_sourced_tool_script() {
    local tools_dir="$1" script="$2" body="$3"
    run bash -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        cd '${tools_dir}' || exit 1
        source '${script}'
        ${body}
    "
}

# Feed a JSON payload to claude/statusline-command.sh and capture its
# rendered line. Callers must set STATUSLINE to the script path before use
# (see tests/bats/integrations/claude_statusline_*.bats).
_render() {
    run bash -c "printf '%s' '$1' | bash '${STATUSLINE}'"
}

# Same as _render but with the ANSI colour codes stripped, so an assertion can
# pin exact segment adjacency — which is what proves a separator was *not*
# emitted. The ESC byte is interpolated rather than written as `\x1b` so the
# sed script works on BSD sed too.
_render_plain() {
    local esc
    esc=$(printf '\033')
    run bash -c "printf '%s' '$1' | bash '${STATUSLINE}' | sed 's/${esc}\[[0-9;]*m//g'"
}

# Run a command in zsh subprocess with dotfiles loaded
run_in_zsh() {
    run zsh -f -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}'
        export ZDOTDIR='${HOME}'
        export TERM=dumb
        source '${DOTFILES_ROOT}/zsh/main.zsh'
        $1
    "
}

# Assert that $1 is a name `herdr agent start` will accept.
#
# The rule is `^[a-z][a-z0-9_-]{0,31}$`, and it lives here rather than inlined
# in each suite because #1530 is exactly what happens when a naming rule is
# copied: three call sites each carried their own fold, all three were wrong,
# and 76 dispatches were refused before anyone read the stderr. The producing
# side is `shell-common/functions/herdr_agent_name.sh`; this is the
# independent oracle four suites check it against
# (`herdr_agent_name.bats`, `pr_merge_train_cron.bats`,
# `issue_watcher_cron.bats`, `gh_pr_post_merge_verify.bats`).
assert_valid_herdr_name() {
    [[ "$1" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] ||
        fail "not a valid herdr agent name: '$1'"
}
