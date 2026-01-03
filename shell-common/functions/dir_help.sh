#!/bin/sh
# shell-common/functions/dir_help.sh
# dirHelp - shared between bash and zsh

dir_help() {
    ux_header "Directory Navigation"

    ux_section "Core Directories"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd_dot" "\$HOME/dotfiles" "Dotfiles repository root"
    ux_table_row "cd_down" "\$HOME/downloads" "Downloads folder"
    ux_table_row "cd_work" "\$HOME/workspace" "Workspace root"
    echo ""

    ux_section "Windows (WSL)"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "cd_wdocu" "Windows Documents" "Access Windows documents"
    ux_table_row "cd_wobsidian" "Windows Obsidian" "Obsidian vault location"
    ux_table_row "cd_wdown" "Windows Downloads" "Quick access to downloads"
    ux_table_row "cd_wpicture" "Windows Pictures" "Photo library"
    ux_table_row "cd_tilnote" "Obsidian TilNote" "TilNote vault"
    ux_table_row "cd_obsidian" "Obsidian vault" "Default vault in WSL"
    echo ""

    ux_section "PARA Method"
    ux_table_header "Command" "Destination" "Purpose"
    ux_table_row "mkpara" "para/{archive,area,project,resource}" "Create PARA directories"
    ux_table_row "cd_para" "\$HOME/para" "PARA root"
    ux_table_row "cd_project" "\$HOME/para/project" "Projects workspace"
    ux_table_row "cd_area" "\$HOME/para/area" "Areas of responsibility"
    ux_table_row "cd_vault" "\$HOME/para/area/vault" "Vault under Areas"
    ux_table_row "cd_resource" "\$HOME/para/resource" "Reference materials"
    ux_table_row "cd_archive" "\$HOME/para/archive" "Archived items"
    echo ""

    ux_section "Windows Copy Utility"
    ux_table_header "Command" "Usage" "Purpose"
    ux_table_row "cp_wdown" "cp_wdown [options] <file...>" "Copy from Windows Downloads into WSL (run -h for details)"
    echo ""

    ux_section "Quick Examples"
    ux_table_header "Command" "Description"
    ux_table_row "cd_dot" "Jump to dotfiles repository"
    ux_table_row "cd_obsidian" "Open Obsidian vault"
    ux_table_row 'cp_wdown "*.pdf"' "Copy all PDF files from Windows Downloads"
    ux_table_row "cp_wdown -r folder" "Copy an entire folder"
    echo ""
}

# Alias for dir-help format (using dash instead of underscore)
alias dir-help='dir_help'
