#!/usr/bin/env bats
# tests/bats/tools/sudo_keep_alive.bats
# tools/custom sudo keep-alive loops must probe the parent with kill -0 "$$"
# (#1941). install_docker.sh had kill -0 "$", which always fails, so the loop
# exited after one 60s pass and sudo could re-prompt mid-install.

load '../test_helper'

@test "sudo keep-alive loops: every kill -0 targets \"\$\$\" and scripts parse" {
    local f found=0 bad=""
    for f in "${SHELL_COMMON}"/tools/custom/*.sh; do
        grep -q 'while true; do sudo -n true' "$f" || continue
        found=$((found + 1))
        bash -n "$f" || bad="$bad $f(bash -n)"
        grep 'while true; do sudo -n true' "$f" | grep -qv 'kill -0 "\$\$"' &&
            bad="$bad $f"
    done
    [ "$found" -ge 5 ]
    [ -z "$bad" ] || { echo "bad keep-alive:$bad"; false; }
}
