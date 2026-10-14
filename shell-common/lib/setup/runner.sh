#!/bin/sh
# shellcheck shell=bash
# shell-common/lib/setup/runner.sh — summary-mode step runner for setup (#2137)
#
# The runner itself lives in shell-common/tools/ux_lib/step_runner.sh (moved
# out of root setup.sh by #2126, also used by skills-sync). This entry point
# only gives setup consumers one lib/setup/ path for it, so there is a single
# implementation: step_init / step_run / step_summary + STEP_* knobs, as
# documented in that file. bash only (the runner uses arrays), explicit
# source only; bootstrap via SHELL_COMMON / DOTFILES_ROOT like common.sh.

: "${SHELL_COMMON:=${DOTFILES_ROOT:?export SHELL_COMMON or DOTFILES_ROOT before sourcing lib/setup}/shell-common}"
# shellcheck source=shell-common/tools/ux_lib/step_runner.sh
. "${SHELL_COMMON}/tools/ux_lib/step_runner.sh"
