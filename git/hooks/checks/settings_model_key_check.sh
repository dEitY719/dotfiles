#!/usr/bin/env bash
# git/hooks/checks/settings_model_key_check.sh
#
# Tracked config SSOTs must not carry keys only a tool's own rewrite stamps
# (was golden Rules 6 and 7, moved here in #2149). Either key proves the
# runtime copy was a write-through symlink into this repo and the tool wrote
# one PC's state into the tracked file.
#   claude/settings.json  "model"            /model persists here (#924, #940)
#   hermes/config.yaml    _config_version    stamped by the hermes CLI
# Recovery: git checkout <file>

check_settings_model_key() { # <abs_path> <repo_rel_path> <out>
    local ere
    case "$2" in
    claude/settings.json) ere='^[[:space:]]*"model"[[:space:]]*:' ;;
    hermes/config.yaml) ere='^[[:space:]]*_config_version[[:space:]]*:' ;;
    *) return 0 ;;
    esac
    grep -qE "$ere" "$1" 2>/dev/null || return 0
    echo "$2: runtime-only key in tracked SSOT (recover: git checkout $2)" >>"$3"
    return 1
}

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
CHECK_NAME=settings_model_key
CHECK_SCOPE=per-file
CHECK_SEVERITY=blocking
CHECK_TITLE="Runtime-only key in tracked config SSOT"
check_run() {
    [ -f "$1/$3" ] || return 0
    check_settings_model_key "$1/$3" "$3" "$4"
}
