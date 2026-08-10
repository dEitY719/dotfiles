#!/bin/bash

# Status line command for Claude Code
# Format: [한글|영어] HH:MM:SS | model | [effort] | project(branch) | git-status
# ([한글|영어]는 fcitx-remote가 설치된 환경에서만 나타나는 optional 필드)
# CLAUDE_STATUSLINE_SKIP_FCITX=1 이면 fcitx-remote 호출 자체를 생략한다.
# Windows Terminal / VS Code Remote-WSL 콘솔은 X11 클라이언트가 아니라 fcitx
# XIM 경로에 아예 안 걸려 상태가 항상 비어있다 — 매 프롬프트마다 의미 없는
# timeout 0.3s 대기만 생기므로, 이런 PC는 ~/.zshrc.local 에 export 로 꺼둔다.

# ANSI color codes
CYAN='\033[36m'
ORANGE='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
MAGENTA='\033[35m'
BLUE='\033[34m'
BOLD='\033[1m'
RESET='\033[0m'

# Read JSON input from stdin
input=$(cat)

# Extract everything we need in a single jq pass — statusline runs on every
# prompt render, so consolidating 5 jq forks into 1 is a meaningful win.
#
# One value per line + `mapfile`, NOT `@tsv` + `IFS=$'\t' read`: tab is an
# IFS *whitespace* character, so bash merges runs of tabs into one delimiter
# and strips leading ones — every empty field vanishes and the fields after
# it shift left. That stayed invisible while the only fields that could be
# empty (used_pct, total_tokens) sat at the end of the list; adding
# `.effort.level` moves them into the middle and turns it into a real bug.
mapfile -t _sl_fields < <(
    echo "$input" | jq -r '
      (.context_window.current_usage // {}) as $u
      | [
          (.workspace.current_dir // .cwd // ""),
          (.model.id // ""),
          (.model.display_name // ""),
          (.context_window.used_percentage // ""),
          (($u.input_tokens // 0)
            + ($u.cache_read_input_tokens // 0)
            + ($u.cache_creation_input_tokens // 0)
            | if . > 0 then tostring else "" end),
          (.effort.level // "")
        ]
      | .[] | tostring
    '
)
cwd="${_sl_fields[0]-}"
model_id="${_sl_fields[1]-}"
model_display="${_sl_fields[2]-}"
used_pct="${_sl_fields[3]-}"
total_tokens="${_sl_fields[4]-}"
effort_level="${_sl_fields[5]-}"

# Get current time in HH:MM:SS format
current_time=$(date +%H:%M:%S)
current_hour="${current_time%%:*}"

# Current input method (fcitx only — ibus/fcitx5 not supported): state
# 2=active(한글) 1=inactive(영어). State 0 (daemon closed) or fcitx-remote
# missing both fall through to an empty ime_label (no label shown).
# `timeout 0.3` bounds a hung/no-DBus fcitx-remote so it can't stall the
# whole statusline render.
ime_label=""
if [ "${CLAUDE_STATUSLINE_SKIP_FCITX:-0}" != "1" ] && command -v fcitx-remote >/dev/null 2>&1; then
    case "$(timeout 0.3 fcitx-remote 2>/dev/null)" in
    2) ime_label="한글" ;;
    1) ime_label="영어" ;;
    esac
fi

# Determine time-based emoji
# 10# forces base-10 — a bare "08"/"09" would otherwise be parsed as
# (invalid) octal and abort the arithmetic comparison.
if ((10#$current_hour >= 6 && 10#$current_hour < 12)); then
    time_emoji="🌅" # Morning
elif ((10#$current_hour >= 12 && 10#$current_hour < 18)); then
    time_emoji="☀️" # Afternoon
else
    time_emoji="🌙" # Night
fi

# Use full display name from JSON input
# Examples:
#   "Haiku 4.5"
#   "Claude 3.5 Sonnet"
#   "Opus 4"
# Fallback to model ID if display_name is missing
if [[ -n "$model_display" ]]; then
    model_name="$model_display"
else
    # Fallback: use model ID if display_name is not available
    model_name="${model_id:-unknown}"
fi

# Add model emoji based on model name
if [[ "$model_name" == *"Haiku"* ]]; then
    model_emoji="🐰" # Haiku - rabbit (small, fast)
elif [[ "$model_name" == *"Sonnet"* ]]; then
    model_emoji="🎼" # Sonnet - musical notation
elif [[ "$model_name" == *"Opus"* ]]; then
    model_emoji="🎭" # Opus - theater mask
else
    model_emoji="🧠" # Default - brain
fi

# Effort level → moon-phase glyph, waxing with reasoning depth:
#   🌑 low  🌒 medium  🌓 high  🌔 xhigh  🌕 max
# The `.effort` key only exists when the model supports effort levels
# (claude-3-*, opus-4-0/4-1, sonnet-4-0/4-5 … don't) — then the segment and
# its separator drop out entirely, leaving the line byte-identical to before.
# `ultracode` is deliberately absent: it is a session mode, not a level, and
# it forces effortValue to "xhigh", so the payload cannot distinguish the two.
# An unmapped value renders as bare text rather than vanishing, so a future
# level stays visible.
effort_info=""
if [ -n "$effort_level" ]; then
    case "$effort_level" in
    low) effort_glyph="🌑" ;;
    medium) effort_glyph="🌒" ;;
    high) effort_glyph="🌓" ;;
    xhigh) effort_glyph="🌔" ;;
    max) effort_glyph="🌕" ;;
    *) effort_glyph="" ;;
    esac
    effort_info="${ORANGE}${effort_glyph:+${effort_glyph} }${effort_level}${RESET}"
fi

# Active account tag from CLAUDE_CONFIG_DIR (set by `claude-yolo --user <name>`).
# Convention: ~/.claude-<name> → <name>; bare ~/.claude → single-account (no tag).
# Tag = uppercase first letter + trailing digits:
#   personal → P   work → W   work1 → W1
account_info=""
account_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
account_dir="${account_dir%/}"    # tolerate a trailing slash
account_dir="${account_dir##*/}"  # basename via param expansion (no fork)
case "$account_dir" in
.claude-*)
    account="${account_dir#.claude-}"
    acct_first="${account:0:1}"
    acct_first="${acct_first^^}"      # bash uppercase
    acct_digits="${account##*[!0-9]}" # trailing run of digits (empty if none)
    user_tag="${acct_first}${acct_digits}"
    account_info="${BOLD}👤 ${user_tag}${RESET}"
    ;;
esac

# Extract last folder name from current directory
project_name=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    project_name=$(basename "$cwd")
else
    project_name="unknown"
fi

# Get git branch name (remove origin/ prefix if present)
git_branch=""
branch_emoji=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
        git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
        # Remove origin/ prefix if present
        git_branch="${git_branch#origin/}"
        # Add branch emoji
        if [[ "$git_branch" == "main" ]]; then
            branch_emoji="🌳" # Main branch - tree
        elif [[ "$git_branch" == "master" ]]; then
            branch_emoji="👑" # Master branch - crown
        elif [[ "$git_branch" == pr/* ]]; then
            branch_emoji="⬆️" # PR branch - pull request
        elif [[ "$git_branch" == feat/* ]]; then
            branch_emoji="✨" # Feature branch - sparkles
        else
            branch_emoji="🌿" # Other branch - leaf
        fi
    else
        git_branch="no-git"
        branch_emoji="⚠️" # No git - warning
    fi
else
    git_branch="no-dir"
    branch_emoji="❓" # No directory - question
fi

# Combine project name with branch: "📁 quantfolio(🌳 main)"
project_branch="📁 ${project_name}(${branch_emoji} ${git_branch})"

# Compact git status: dirty count / ahead / behind
# Shows what workflow step is next:
#   ●N  = N uncommitted changes (staged + unstaged + untracked) → /gh-commit
#   ↑N  = N commits ahead of upstream → /gh-pr (after push)
#   ↓N  = N commits behind upstream (need pull)
#   ✓   = clean and in sync
git_status_text=""
git_status_color="$GREEN"
if [ -n "$cwd" ] && [ -d "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    dirty_count=$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    ahead=0
    behind=0
    if git -C "$cwd" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        ahead=$(git -C "$cwd" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
        behind=$(git -C "$cwd" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    fi

    parts=()
    [ "${dirty_count:-0}" -gt 0 ] && parts+=("●${dirty_count}")
    [ "${ahead:-0}"       -gt 0 ] && parts+=("↑${ahead}")
    [ "${behind:-0}"      -gt 0 ] && parts+=("↓${behind}")

    if [ ${#parts[@]} -eq 0 ]; then
        git_status_text="✓"
        git_status_color="$GREEN"
    else
        git_status_text="${parts[*]}"
        if [ "${dirty_count:-0}" -gt 0 ]; then
            git_status_color="$RED"      # uncommitted work — commit first
        else
            git_status_color="$ORANGE"   # committed but not in sync with remote
        fi
    fi
fi

git_status_info=""
if [ -n "$git_status_text" ]; then
    git_status_info="${git_status_color}📝 ${git_status_text}${RESET}"
fi

# Format tokens: 65700 -> 65.7k
fmt_tokens() {
    local n=$1
    if [ "$n" -ge 1000 ]; then
        awk -v n="$n" 'BEGIN{ printf "%.1fk", n/1000 }'
    else
        printf '%s' "$n"
    fi
}

# Build context segment like "65.7k / 7%"
ctx_segment=""
if [ -n "$total_tokens" ] && [ -n "$used_pct" ]; then
    ctx_segment="$(printf '%s / %.0f%%' "$(fmt_tokens "$total_tokens")" "$used_pct")"
elif [ -n "$used_pct" ]; then
    ctx_segment="$(printf '%.0f%%' "$used_pct")"
elif [ -n "$total_tokens" ]; then
    ctx_segment="$(fmt_tokens "$total_tokens")"
fi

ctx_info=""
if [ -n "$ctx_segment" ]; then
    ctx_info="${BLUE}🧮 ${ctx_segment}${RESET}"
fi

# Bedrock cost display (internal only)
SETUP_MODE=""
[ -f "$HOME/.dotfiles-setup-mode" ] && SETUP_MODE=$(cat "$HOME/.dotfiles-setup-mode")

cost_info=""
if [ "$SETUP_MODE" = "internal" ]; then
    _KNOX_ID="byoungwoo.yoon"
    _BUDGET=175
    _CACHE_FILE="/tmp/.claude_bedrock_cost_cache"
    _CACHE_TTL=300
    _API_URL="https://claude-usage-api-dscloud-mchat-bot-swe.svc01.stg.dss.samsungds.net/?id=${_KNOX_ID}"
    _now=$(date +%s)
    _cache_ts=""
    _cost=""
    if [ -f "$_CACHE_FILE" ]; then
        _line1=$(sed -n '1p' "$_CACHE_FILE" 2>/dev/null)
        case "$_line1" in
        '' | *[!0-9]*) ;; # not a pure-integer timestamp → ignore corrupt cache
        *)
            _cache_ts="$_line1"
            _cost=$(sed -n '2p' "$_CACHE_FILE" 2>/dev/null)
            ;;
        esac
    fi

    if [ -z "$_cache_ts" ]; then
        printf '%s\n\n' "$_now" >"$_CACHE_FILE"
        (
            _new=$(curl -sf --max-time 5 "$_API_URL" 2>/dev/null | jq -r '.latest_cost // .cost // empty' 2>/dev/null)
            [[ "$_new" =~ ^[0-9]*\.?[0-9]+$ ]] && printf '%s\n%s\n' "$(date +%s)" "$_new" >"$_CACHE_FILE"
        ) >/dev/null 2>&1 &
    else
        _age=$((_now - _cache_ts))
        if [ "$_age" -ge "$_CACHE_TTL" ]; then
            printf '%s\n%s\n' "$_now" "$_cost" >"$_CACHE_FILE"
            (
                _new=$(curl -sf --max-time 5 "$_API_URL" 2>/dev/null | jq -r '.latest_cost // .cost // empty' 2>/dev/null)
                [[ "$_new" =~ ^[0-9]*\.?[0-9]+$ ]] && printf '%s\n%s\n' "$(date +%s)" "$_new" >"$_CACHE_FILE"
            ) >/dev/null 2>&1 &
        fi
    fi

    if [ -n "$_cost" ]; then
        _current_day=$(date +%d)
        _current_day=${_current_day#0}
        _days_in_month=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%d 2>/dev/null ||
            cal "$(date +%m)" "$(date +%Y)" | awk 'NF{f=$NF}END{print f}')
        _ratio=$(awk -v c="$_cost" -v dim="$_days_in_month" -v cd="$_current_day" -v b="$_BUDGET" \
            'BEGIN{ printf "%.4f", c * dim / cd / b }')
        _cost_disp=$(awk -v c="$_cost" -v b="$_BUDGET" 'BEGIN{ printf "$%.1f / $%d", c, b }')

        if awk -v r="$_ratio" 'BEGIN{exit !(r+0 <= 0.5)}'; then
            cost_info="${CYAN}💪 ${_cost_disp}${RESET}"
        elif awk -v r="$_ratio" 'BEGIN{exit !(r+0 <= 1.0)}'; then
            cost_info="${GREEN}🟢 ${_cost_disp}${RESET}"
        elif awk -v r="$_ratio" 'BEGIN{exit !(r+0 <= 1.2)}'; then
            cost_info="${ORANGE}🔥 ${_cost_disp}${RESET}"
        else
            cost_info="${RED}🚨 ${_cost_disp}${RESET}"
        fi
    fi
fi

# Output format with colors and emojis
# Time: Cyan, Model+Effort: Orange, Project+Branch: Magenta, Context: Blue, Cost: varies, Git status: Red/Orange/Green
# Effort shares the model's colour so the two read as one "model config" group.
# It sits mid-line, so the separator is folded into the expansion (`:+ | …`)
# rather than appended by a trailing `if` like the optional tail segments.
out="${CYAN}${time_emoji} ${ime_label:+$ime_label }${current_time}${RESET} | ${ORANGE}${model_emoji} ${model_name}${RESET}${effort_info:+ | ${effort_info}} | ${MAGENTA}${project_branch}${RESET}"
if [[ -n "$account_info" ]]; then
    out="${account_info} | ${out}"
fi
if [[ -n "$ctx_info" ]]; then
    out="${out} | ${ctx_info}"
fi
if [[ -n "$cost_info" ]]; then
    out="${out} | ${cost_info}"
fi
if [[ -n "$git_status_info" ]]; then
    out="${out} | ${git_status_info}"
fi
echo -e "$out"
