#!/bin/bash

# Status line command for Claude Code
# Format: YY-MM-DD HH:MM:SS | model | project-name(git-branch)

# ANSI color codes
CYAN='\033[36m'
ORANGE='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
MAGENTA='\033[35m'
RESET='\033[0m'

# Read JSON input from stdin
input=$(cat)

# Debug: Log full JSON to find weekly usage information
{
  echo "=== Full JSON Structure ==="
  echo "$input" | jq . 2>/dev/null || echo "$input"
  echo "=== Debug Info ==="
  echo "Time: $(date)"
  echo "---"
} >> /tmp/statusline-weekly-debug.log 2>&1

# Extract current directory and model from JSON input
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model_id=$(echo "$input" | jq -r '.model.id // ""')
model_display=$(echo "$input" | jq -r '.model.display_name // ""')

# Extract context window information from Claude Code input
total_input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
context_window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

# Use Claude Code's official used_percentage first (most accurate)
context_used=$(echo "$input" | jq -r '.context_window.used_percentage // ""')

# If not available, calculate from token counts
if [[ -z "$context_used" ]] || [[ "$context_used" == "null" ]]; then
    if [[ "$total_input_tokens" =~ ^[0-9]+$ ]] && [[ "$total_output_tokens" =~ ^[0-9]+$ ]] && [[ "$context_window_size" -gt 0 ]]; then
        total_tokens=$((total_input_tokens + total_output_tokens))
        # Simple calculation: (total_tokens / context_window_size) * 100
        context_used=$(( (total_tokens * 100) / context_window_size ))
    fi
fi

weekly_used=$(echo "$input" | jq -r '.context_window.weekly_percentage // ""')

# Extract cost information from Claude Code
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // ""')

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

# Format usage information and determine color based on usage percentage
usage_info=""
usage_color="$GREEN"  # Default to green
if [[ -n "$context_used" ]]; then
    # Determine color based on usage percentage
    if ((context_used >= 90)); then
        usage_color="$RED"
    elif ((context_used >= 70)); then
        usage_color="$ORANGE"
    else
        usage_color="$GREEN"
    fi

    if [[ -n "$weekly_used" ]]; then
        # Show current usage with weekly context
        usage_info="${usage_color}📊 ${context_used}% used | Weekly: ${weekly_used}%${RESET}"
    else
        # Show only current usage
        usage_info="${usage_color}📊 ${context_used}% used${RESET}"
    fi
fi

# Format cost information with dynamic color coding
cost_info=""
cost_color="$GREEN"  # Default to green
if [[ -n "$total_cost" ]] && [[ "$total_cost" != "null" ]]; then
    # Determine color based on cost amount
    # Green: $0-5, Orange: $5-20, Red: $20+
    cost_numeric=$(printf "%.2f" "$total_cost" 2>/dev/null || echo "0")
    cost_comparison=$(echo "$cost_numeric >= 20" | bc 2>/dev/null)

    if [[ "$cost_comparison" == "1" ]]; then
        cost_color="$RED"
    else
        cost_comparison=$(echo "$cost_numeric >= 5" | bc 2>/dev/null)
        if [[ "$cost_comparison" == "1" ]]; then
            cost_color="$ORANGE"
        else
            cost_color="$GREEN"
        fi
    fi

    cost_info=" | ${cost_color}💰 \$$cost_numeric${RESET}"
fi

# Output format with colors and emojis
# Time: Cyan, Model: Orange, Project+Branch: Magenta, Usage: Dynamic color (Red/Orange/Green)
if [[ -n "$usage_info" ]]; then
    echo -e "${CYAN}${time_emoji} ${current_time}${RESET} | ${ORANGE}${model_emoji} ${model_name}${RESET} | ${MAGENTA}${project_branch}${RESET} | ${usage_info}${cost_info}"
else
    echo -e "${CYAN}${time_emoji} ${current_time}${RESET} | ${ORANGE}${model_emoji} ${model_name}${RESET} | ${MAGENTA}${project_branch}${RESET}${cost_info}"
fi
