#!/usr/bin/env bash
# tests/bats/skills/_fixtures/pace_control.sh
# Sourced by gh_add_ai_metrics_pace.bats. Mirrors the helpers in
# claude/skills/gh-add-ai-metrics/references/pace-control.md so bats
# can verify the intended logic. If the markdown changes, update this
# file in lockstep — it is the testable copy of the same algorithm.

parse_duration() {
    local raw="$1"
    local total=0 num unit
    local rest="$raw"
    [ -n "$rest" ] || return 1
    while [ -n "$rest" ]; do
        [[ "$rest" =~ ^([0-9]+)([smh])(.*)$ ]] || return 1
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
        case "$unit" in
            s) total=$((total + num)) ;;
            m) total=$((total + num * 60)) ;;
            h) total=$((total + num * 3600)) ;;
        esac
    done
    printf '%s\n' "$total"
}

format_duration() {
    local s="$1" h m
    h=$(( s / 3600 )); s=$(( s % 3600 ))
    m=$(( s / 60 ));   s=$(( s % 60 ))
    local out=""
    [ "$h" -gt 0 ] && out="${out}${h}h"
    [ "$m" -gt 0 ] && out="${out}${m}m"
    [ "$s" -gt 0 ] && out="${out}${s}s"
    [ -z "$out" ] && out="0s"
    printf '%s\n' "$out"
}

sleep_pace() {
    local secs="${1:-0}"
    [ "$secs" -gt 0 ] || return 0
    sleep "$secs"
}

check_budget() {
    local elapsed="$1" budget="${2:-0}"
    [ "$budget" -gt 0 ] || return 1
    [ "$elapsed" -ge "$budget" ]
}

compute_eta() {
    local writes="$1" pace_secs="${2:-0}"
    if [ "$writes" -le 0 ]; then
        printf '0s (no writes)\n'
        return 0
    fi
    if [ "$pace_secs" -le 0 ]; then
        printf '<1m (no pace)\n'
        return 0
    fi
    local total=$(( (writes - 1) * pace_secs ))
    [ "$total" -lt 0 ] && total=0
    format_duration "$total"
}
