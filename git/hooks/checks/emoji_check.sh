#!/usr/bin/env bash
# git/hooks/checks/emoji_check.sh
#
# No emojis in the shell entry points and shell-common util/config (CLAUDE.md
# "No emojis anywhere"; was golden Rule 4, moved here in #2149). The class is
# U+1F60A-1F64F (faces), U+1F680, U+2728, U+2B50. The ai-metrics footer glyphs
# (U+1F4CA, U+1F464, U+1F916) fall outside it, which is the CLAUDE.md exception.

check_emoji() { # <abs_path> <repo_rel_path> <out>
    local hits
    # shortcut: needs GNU grep -P; without it grep exits 2 and the check passes. Upgrade if a BSD-grep host commits here.
    hits=$(LC_ALL=C.UTF-8 grep -nP '[\x{1F60A}-\x{1F64F}\x{1F680}\x{2728}\x{2B50}]' "$1" 2>/dev/null) || return 0
    printf '%s\n' "$hits" | sed "s|^|$2:|" >>"$3"
    return 1
}

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
CHECK_NAME=emoji
CHECK_SCOPE=per-file
CHECK_SEVERITY=blocking
CHECK_TITLE="Emojis in source files"
CHECK_REPORT_LINES=10
check_run() {
    case "$3" in
    bash/main.bash | zsh/main.zsh | shell-common/util/*.sh | shell-common/config/*) ;;
    *) return 0 ;;
    esac
    [ -f "$1/$3" ] || return 0
    check_emoji "$1/$3" "$3" "$4"
}
