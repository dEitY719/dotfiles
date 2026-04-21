#!/bin/bash

# Status line command for Claude Code
# Format: YY-MM-DD HH:MM:SS | model | project(branch) | git-status

# ANSI color codes
CYAN='\033[36m'
ORANGE='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
MAGENTA='\033[35m'
RESET='\033[0m'

# Read JSON input from stdin
input=$(cat)

# Extract current directory and model from JSON input
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model_id=$(echo "$input" | jq -r '.model.id // ""')
model_display=$(echo "$input" | jq -r '.model.display_name // ""')

# Get current time in YY-MM-DD HH:MM:SS format
current_time=$(date +%y-%m-%d\ %H:%M:%S)
current_hour=$(date +%H)

# Determine time-based emoji
if ((current_hour >= 6 && current_hour < 12)); then
    time_emoji="🌅" # Morning
elif ((current_hour >= 12 && current_hour < 18)); then
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

# Output format with colors and emojis
# Time: Cyan, Model: Orange, Project+Branch: Magenta, Git status: Red/Orange/Green
if [[ -n "$git_status_info" ]]; then
    echo -e "${CYAN}${time_emoji} ${current_time}${RESET} | ${ORANGE}${model_emoji} ${model_name}${RESET} | ${MAGENTA}${project_branch}${RESET} | ${git_status_info}"
else
    echo -e "${CYAN}${time_emoji} ${current_time}${RESET} | ${ORANGE}${model_emoji} ${model_name}${RESET} | ${MAGENTA}${project_branch}${RESET}"
fi
