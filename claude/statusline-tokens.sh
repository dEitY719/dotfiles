#!/bin/bash

# Session-cumulative token usage segment for claude/statusline-command.sh (#1380).
#
# Renders "📥 1,235k 💰87% 📤 46k":
#   📥 real_read = Σ(input_tokens + cache_creation_input_tokens) — the tokens
#                  that were NOT a cache hit, i.e. billed at ≥ 1.0x
#   💰 hit_ratio = cache_read / (input + cache_creation + cache_read)
#   📤 out       = Σ(output_tokens)
#
# All three come from the session transcript JSONL, not from the per-render
# payload: `.context_window.current_usage` is a single most-recent snapshot and
# carries no output_tokens at all, so a transcript scan is unavoidable — and
# once it is, the hit ratio must use the same source or the three numbers would
# describe different scopes.
#
# This file is *sourced* by statusline-command.sh (never executed) and has no
# side effects at source time — it only defines the two functions below. It is
# not part of shell init, so it carries no interactive guard.

# Round to thousands and group with commas: 1234567 -> "1,235k", 45678 -> "46k".
# Values under 1000 would round to a useless "0k", so they print raw (F-5).
# Integer arithmetic only, no external calculator fork (NF-4).
_sl_k() {
    local n=$1 k s o=
    k=$(((n + 500) / 1000))
    if [ "$k" -eq 0 ]; then
        printf '%s' "$n"
        return 0
    fi
    s=$k
    while [ ${#s} -gt 3 ]; do
        o=",${s: -3}$o"
        s=${s:0:${#s}-3}
    done
    printf '%s%sk' "$s" "$o"
}

# _token_segment <transcript_path> <session_id>
#
# Echoes the rendered segment, or nothing at all when it cannot be computed —
# a missing jq, a missing/unreadable transcript and a malformed JSONL all fail
# soft to an empty string (NF-3), matching how ctx_info / git_status_info
# already signal "absent" elsewhere in the statusline.
_token_segment() {
    local transcript="$1" session_id="$2"

    [ -n "$transcript" ] || return 0
    [ -r "$transcript" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # The statusline re-renders on every prompt while the transcript keeps
    # growing to tens of thousands of lines, so the scan is cached against the
    # file's mtime: within one turn the file is untouched and the cached string
    # is reused verbatim (NF-2).
    local mtime
    mtime=$(stat -c %Y "$transcript" 2>/dev/null || stat -f %m "$transcript" 2>/dev/null)
    [ -n "$mtime" ] || mtime=0

    local key="${session_id:-$transcript}"
    key="${key//[^A-Za-z0-9_-]/_}"
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/claude-statusline"
    local cache_file="${cache_dir}/${key}.seg"

    local cached_mtime="" cached_seg=""
    if [ -r "$cache_file" ]; then
        { read -r cached_mtime && read -r cached_seg; } <"$cache_file" 2>/dev/null
        if [ -n "$cached_mtime" ] && [ "$cached_mtime" = "$mtime" ]; then
            printf '%s' "$cached_seg"
            return 0
        fi
    fi

    # One assistant turn is written to the transcript once per content block,
    # each copy repeating an identical `message.usage` — summing naively
    # overcounts it 2-3x, so every `message.id` is counted exactly once (NF-1).
    # `-n` + `inputs` streams the JSONL instead of slurping it into memory.
    local nums
    nums=$(jq -n -r '
      reduce (inputs | select(type == "object")) as $line
        ({seen: {}, i: 0, c: 0, r: 0, o: 0};
          (($line.message // {}) | select(type == "object")) as $m
          | ($m.usage // null) as $u
          | ($m.id // null) as $id
          | if $u == null or $id == null or (.seen[$id] // false) then .
            else .seen[$id] = true
              | .i += ($u.input_tokens // 0)
              | .c += ($u.cache_creation_input_tokens // 0)
              | .r += ($u.cache_read_input_tokens // 0)
              | .o += ($u.output_tokens // 0)
            end)
      | "\(.i) \(.c) \(.r) \(.o)"
    ' <"$transcript" 2>/dev/null) || return 0

    local in_tok cache_c cache_r out_tok
    read -r in_tok cache_c cache_r out_tok <<<"$nums"
    # Every field must be a non-empty run of digits: a jq that died mid-file
    # leaves some or all of them empty, which the arithmetic below would
    # otherwise turn into a bash syntax error.
    case "${in_tok}:${cache_c}:${cache_r}:${out_tok}" in
    :* | *: | *::* | *[!0-9:]*) return 0 ;;
    esac

    local total=$((in_tok + cache_c + cache_r))
    local real_read=$((in_tok + cache_c))
    local seg=""
    if [ "$total" -gt 0 ] || [ "$out_tok" -gt 0 ]; then
        local pct=0
        # round-half-up without floating point
        [ "$total" -gt 0 ] && pct=$(((cache_r * 200 + total) / (total * 2)))
        seg="\033[34m📥 $(_sl_k "$real_read")\033[0m"
        seg="${seg} \033[32m💰${pct}%\033[0m"
        seg="${seg} \033[34m📤 $(_sl_k "$out_tok")\033[0m"
    fi

    # $$ suffix: several panes can render at once, and a shared temp name would
    # let one truncate the file another is still writing.
    if mkdir -p "$cache_dir" 2>/dev/null; then
        local tmp="${cache_file}.$$"
        if printf '%s\n%s\n' "$mtime" "$seg" >"$tmp" 2>/dev/null; then
            mv -f "$tmp" "$cache_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
        else
            rm -f "$tmp" 2>/dev/null
        fi
    fi

    printf '%s' "$seg"
}
