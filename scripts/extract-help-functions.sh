#!/bin/bash
# Extract help functions from bash files and create shell-common versions

# List of help functions to extract: NAME | FILE | START | END
help_functions=(
    "cchelp|/home/bwyoon/dotfiles/bash/app/ccusage.bash|40|52"
    "claudehelp|/home/bwyoon/dotfiles/bash/app/claude.bash|35|81"
    "clihelp|/home/bwyoon/dotfiles/bash/app/custom_project.bash|173|211"
    "codexhelp|/home/bwyoon/dotfiles/bash/app/codex.bash|33|56"
    "dockerhelp|/home/bwyoon/dotfiles/bash/app/docker.bash|578|634"
    "dproxyhelp|/home/bwyoon/dotfiles/bash/app/docker.bash|502|549"
    "duhelp|/home/bwyoon/dotfiles/bash/coreutils/disk_usage.bash|15|27"
    "dirhelp|/home/bwyoon/dotfiles/bash/alias/directory_aliases.bash|194|236"
    "gc_help|/home/bwyoon/dotfiles/bash/app/git-crypt.bash|84|181"
    "geminihelp|/home/bwyoon/dotfiles/bash/app/gemini.bash|31|51"
    "githelp|/home/bwyoon/dotfiles/bash/app/git.bash|562|631"
    "gpuhelp|/home/bwyoon/dotfiles/bash/app/gpu.bash|176|206"
    "litellm_help|/home/bwyoon/dotfiles/bash/app/litellm.bash|328|351"
    "mysql_help|/home/bwyoon/dotfiles/bash/app/mysql.bash|331|348"
    "mytool_help|/home/bwyoon/dotfiles/bash/app/mytool.bash|8|24"
    "npmhelp|/home/bwyoon/dotfiles/bash/app/npm.bash|103|150"
    "nvmhelp|/home/bwyoon/dotfiles/bash/app/nvm.bash|8|20"
    "pphelp|/home/bwyoon/dotfiles/bash/alias/python_alias.bash|33|60"
    "psqlhelp|/home/bwyoon/dotfiles/bash/app/postgresql.bash|707|735"
    "pyhelp|/home/bwyoon/dotfiles/bash/app/python.bash|26|56"
    "syshelp|/home/bwyoon/dotfiles/bash/alias/system_aliases.bash|37|73"
    "uvhelp|/home/bwyoon/dotfiles/bash/app/uv.bash|38|64"
    "zsh-help|/home/bwyoon/dotfiles/bash/app/zsh.bash|35|79"
)

# Extract function from file
extract_function() {
    local name=$1
    local file=$2
    local start=$3
    local end=$4

    # Extract lines from start to end
    sed -n "${start},${end}p" "$file"
}

# Create shell-common function file
create_shell_common_file() {
    local name=$1
    local file=$2
    local start=$3
    local end=$4

    local output_file="/home/bwyoon/dotfiles/shell-common/functions/${name}.sh"

    echo "#!/bin/sh" > "$output_file"
    echo "# shell-common/functions/${name}.sh" >> "$output_file"
    echo "# $(echo $name | sed 's/_/ /g' | sed 's/help/Help/') - shared between bash and zsh" >> "$output_file"
    echo "" >> "$output_file"

    extract_function "$name" "$file" "$start" "$end" >> "$output_file"

    echo "Created: $output_file"
}

# Main loop
for entry in "${help_functions[@]}"; do
    IFS='|' read -r name file start end <<< "$entry"
    create_shell_common_file "$name" "$file" "$start" "$end"
done

echo "Done! All help functions extracted."
