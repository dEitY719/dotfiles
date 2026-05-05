#!/usr/bin/env bash
# tests/bats/skills/_fixtures/date_parsing.sh
# Sourced by gh_add_ai_metrics_date.bats. Mirrors the helpers in
# claude/skills/gh-add-ai-metrics/references/date-parsing.md so bats
# can verify the intended logic. If the markdown changes, update this
# file in lockstep — it is the testable copy of the same algorithm.

last_day_of_month() {
    local yyyy="$1" mm="$2" out=""
    out=$(date -d "${yyyy}-${mm}-01 +1 month -1 day" +%d 2>/dev/null) \
        && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    out=$(date -j -f "%Y-%m-%d" -v+1m -v-1d "${yyyy}-${mm}-01" +%d 2>/dev/null) \
        && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    out=$(python3 -c "import calendar; print('%02d' % calendar.monthrange($yyyy, int('$mm'))[1])" 2>/dev/null) \
        && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    return 1
}

_minus_one_day() {
    local d="$1" out=""
    out=$(date -d "$d -1 day" +%Y-%m-%d 2>/dev/null) \
        && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    out=$(date -j -f "%Y-%m-%d" -v-1d "$d" +%Y-%m-%d 2>/dev/null) \
        && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    out=$(python3 -c "import datetime; print((datetime.date.fromisoformat('$d') - datetime.timedelta(days=1)).isoformat())" 2>/dev/null) \
        && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    return 1
}

_expand_day() {
    local d="$1"
    case "${#d}" in
        8)  [[ "$d" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            printf '20%s\n' "$d" ;;
        10) [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            printf '%s\n' "$d" ;;
        *)  return 1 ;;
    esac
}

_emit_month() {
    local yyyy="$1" mm="$2" last
    last=$(last_day_of_month "$yyyy" "$mm") || return 1
    printf 'month %s-%s-01 %s-%s-%s\n' "$yyyy" "$mm" "$yyyy" "$mm" "$last"
}

parse_date_arg() {
    local raw="$1"
    [ -n "$raw" ] || return 1
    local arg="${raw//\~/..}"

    if [[ "$arg" == *..* ]]; then
        local start end
        start="${arg%%..*}"
        end="${arg##*..}"
        [ -n "$start" ] && [ -n "$end" ] || return 1
        start=$(_expand_day "$start") || return 1
        end=$(_expand_day "$end") || return 1
        end=$(_minus_one_day "$end") || return 1
        printf 'range %s %s\n' "$start" "$end"
        return 0
    fi

    case "${#arg}" in
        5)
            [[ "$arg" =~ ^[0-9]{2}-[0-9]{2}$ ]] || return 1
            local yy="${arg%-*}" mm="${arg#*-}"
            _emit_month "20$yy" "$mm"
            ;;
        7)
            [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}$ ]] || return 1
            local yyyy="${arg%-*}" mm="${arg#*-}"
            _emit_month "$yyyy" "$mm"
            ;;
        8)
            [[ "$arg" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            printf 'single 20%s\n' "$arg"
            ;;
        10)
            [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            printf 'single %s\n' "$arg"
            ;;
        *)  return 1 ;;
    esac
}

build_search_clause() {
    local kind="$1" a="$2" b="$3"
    case "$kind" in
        single)      printf 'created:%s\n' "$a" ;;
        month|range) printf 'created:%s..%s\n' "$a" "$b" ;;
        *)           return 1 ;;
    esac
}
