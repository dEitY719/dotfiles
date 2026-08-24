#!/bin/sh
# shell-common/functions/dotfiles_bats_submodules.sh
# Ensures the bats-core/bats-support/bats-assert git submodules
# (tests/bats/lib/*) are checked out during onboarding.
#
# A plain `git clone` never populates submodules, and neither setup.sh nor
# install.sh initialized them — so `./tests/test`'s only defense was a
# `return 0` when the bats binary was missing, making a fresh clone report
# "All tests passed!" with 0 bats cases run (issue #1398). setup.sh calls
# this so onboarding fetches the submodules instead of leaving the gap open.
#
# NOTE: This file only DEFINES a function and produces no output at source
# time, so it deliberately omits the interactive guard (mirrors dotfiles_backup.sh).

dotfiles_ensure_bats_submodules() {
    local repo_root="$1"
    if [ ! -e "${repo_root}/.git" ]; then
        return 0
    fi
    git -C "$repo_root" submodule update --init --recursive tests/bats/lib
}
