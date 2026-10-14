#!/usr/bin/env bash
# git/hooks/checks/posix_bashism_check.sh
#
# A `#!/bin/sh` file in shell-common/util or shell-common/config must not read
# bash-only ${BASH_*} variables (was golden Rule 5, moved here in #2149).
# ShellCheck does not cover it: SC3028 skips ${BASH_VERSION}-style reads.

check_posix_bashism() { # <abs_path> <repo_rel_path> <out>
    grep -q '^#!/bin/sh$' "$1" || return 0
    local hits
    hits=$(grep -n '\${BASH_' "$1") || return 0
    printf '%s\n' "$hits" | sed "s|^|$2:|" >>"$3"
    return 1
}

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
CHECK_NAME=posix_bashism
CHECK_SCOPE=per-file
CHECK_SEVERITY=blocking
CHECK_TITLE="Bash-only \${BASH_*} in a #!/bin/sh file"
CHECK_REPORT_LINES=10
check_run() {
    case "$3" in shell-common/util/*.sh | shell-common/config/*) ;; *) return 0 ;; esac
    [ -f "$1/$3" ] || return 0
    check_posix_bashism "$1/$3" "$3" "$4"
}
