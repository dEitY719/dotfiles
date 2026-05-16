#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh
# Thin wrapper around the production SSOT for `gh_pr_review_parse`.
# The arg-parse and KR-alias-normalization logic used to live here
# (~142 lines) because the SKILL had no production shell function.
# Issue #664 introduced `shell-common/functions/gh_pr_review.sh` as
# the SSOT; this fixture now exists solely to expose the parser to
# `tests/bats/skills/gh_pr_review_arg_parse.bats` under its historical
# load path so neither the test suite nor downstream callers need to
# change.

# Force-load the production function regardless of interactive mode —
# its file uses the standard interactive guard.
DOTFILES_FORCE_INIT=1
export DOTFILES_FORCE_INIT

# Resolve the dotfiles root. The test harness exports
# _BATS_REAL_DOTFILES_ROOT before sourcing this fixture; outside the
# harness, the relative path from this file works as a fallback.
_GH_PR_REVIEW_FIXTURE_ROOT="${_BATS_REAL_DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"

# shellcheck disable=SC1091
. "${_GH_PR_REVIEW_FIXTURE_ROOT}/shell-common/functions/gh_pr_review.sh"
