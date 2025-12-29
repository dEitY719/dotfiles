#!/bin/bash
# Remove help functions from bash files (no longer needed - using shell-common versions)

# Define which functions to remove from which files
# Format: FILE | FUNCTION_NAME | START_LINE | END_LINE
cleanup_list=(
    "/home/bwyoon/dotfiles/bash/app/apt.bash|apthelp|165|221"
    "/home/bwyoon/dotfiles/bash/app/ccusage.bash|cchelp|40|52"
    "/home/bwyoon/dotfiles/bash/app/claude.bash|claudehelp|35|81"
    "/home/bwyoon/dotfiles/bash/app/custom_project.bash|clihelp|173|211"
    "/home/bwyoon/dotfiles/bash/app/codex.bash|codexhelp|33|56"
    "/home/bwyoon/dotfiles/bash/app/docker.bash|dproxyhelp|502|549"
    "/home/bwyoon/dotfiles/bash/app/docker.bash|dockerhelp|578|634"
    "/home/bwyoon/dotfiles/bash/coreutils/disk_usage.bash|duhelp|15|27"
    "/home/bwyoon/dotfiles/bash/alias/directory_aliases.bash|dirhelp|194|236"
    "/home/bwyoon/dotfiles/bash/app/git-crypt.bash|gc_help|84|181"
    "/home/bwyoon/dotfiles/bash/app/gemini.bash|geminihelp|31|51"
    "/home/bwyoon/dotfiles/bash/app/git.bash|githelp|562|631"
    "/home/bwyoon/dotfiles/bash/app/gpu.bash|gpuhelp|176|206"
    "/home/bwyoon/dotfiles/bash/app/litellm.bash|litellm_help|328|351"
    "/home/bwyoon/dotfiles/bash/app/mysql.bash|mysql_help|331|348"
    "/home/bwyoon/dotfiles/bash/app/mytool.bash|mytool_help|8|24"
    "/home/bwyoon/dotfiles/bash/app/npm.bash|npmhelp|103|150"
    "/home/bwyoon/dotfiles/bash/app/nvm.bash|nvmhelp|8|20"
    "/home/bwyoon/dotfiles/bash/alias/python_alias.bash|pphelp|33|60"
    "/home/bwyoon/dotfiles/bash/app/postgresql.bash|psqlhelp|707|735"
    "/home/bwyoon/dotfiles/bash/app/python.bash|pyhelp|26|56"
    "/home/bwyoon/dotfiles/bash/alias/system_aliases.bash|syshelp|37|73"
    "/home/bwyoon/dotfiles/bash/app/uv.bash|uvhelp|38|64"
    "/home/bwyoon/dotfiles/bash/app/zsh.bash|zsh-help|35|79"
)

# Group cleanup items by file and sort by start line descending
# This ensures we process functions in reverse order within each file
# to avoid line number shifts

declare -A file_removals

for entry in "${cleanup_list[@]}"; do
    IFS='|' read -r file func_name start end <<< "$entry"
    file_removals["$file"]+="$start|$end
"
done

# Process each file
for file in "${!file_removals[@]}"; do
    if [ ! -f "$file" ]; then
        echo "File not found: $file"
        continue
    fi

    echo "Processing $file..."

    # Create backup
    cp "$file" "$file.bak"

    # Read all the ranges and sort in descending order by start line
    # Process from bottom to top to avoid line number shifts
    while IFS='|' read -r start end; do
        if [ -n "$start" ]; then
            echo "  Removing lines $start-$end"
            sed -i "${start},${end}d" "$file"
        fi
    done < <(echo -n "${file_removals[$file]}" | sort -rn)
done

echo "Cleanup complete. Backup files created with .bak extension."
