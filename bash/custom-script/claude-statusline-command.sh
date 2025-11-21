#!/bin/bash

# Status line command for Claude Code
# Format: YY-MM-DD HH:MM:SS | model | project-name(git-branch)

# ANSI color codes
CYAN='\033[36m'
ORANGE='\033[33m'
GREEN='\033[32m'
RESET='\033[0m'

# Read JSON input from stdin
input=$(cat)

# Extract current directory and model from JSON input
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model_id=$(echo "$input" | jq -r '.model.id // ""')
model_display=$(echo "$input" | jq -r '.model.display_name // ""')

# Get current time in YY-MM-DD HH:MM:SS format
current_time=$(date +%y-%m-%d\ %H:%M:%S)

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

# Extract last folder name from current directory
project_name=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    project_name=$(basename "$cwd")
else
    project_name="unknown"
fi

# Get git branch name (remove origin/ prefix if present)
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
        git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
        # Remove origin/ prefix if present
        git_branch="${git_branch#origin/}"
    else
        git_branch="no-git"
    fi
else
    git_branch="no-dir"
fi

# Combine project name with branch: "quantfolio(main)"
project_branch="${project_name}(${git_branch})"

# Output format with colors: YY-MM-DD HH:MM:SS | model | project(branch)
# Time: Cyan, Model: Orange, Project+Branch: Green
printf "${CYAN}%s${RESET} | ${ORANGE}%s${RESET} | ${GREEN}%s${RESET}" "$current_time" "$model_name" "$project_branch"
