#!/usr/bin/env bash
# git/hooks/checks/backup_file_check.sh
#
# Checks for accidentally committed or untracked backup files (*.backup.*)
# in the repository and recommends cleanup.

# check_backup_files REPO_ROOT OUTPUT_FILE
#
# Returns 0 if no backup files found, 1 if backup files exist
# Populates OUTPUT_FILE with list of found backup files
check_backup_files() {
    local repo_root="$1"
    local output_file="$2"

    # Find all *.backup.* files in the repo (excluding .git)
    local backup_files
    backup_files=$(find "$repo_root" \
        -type f \
        -name "*.backup.*" \
        ! -path "$repo_root/.git/*" \
        2>/dev/null | sort)

    if [ -z "$backup_files" ]; then
        return 0
    fi

    # Write backup files to output file
    echo "$backup_files" | while read -r file; do
        echo "${file#$repo_root/}" >> "$output_file"
    done

    return 1
}
