#!/bin/sh
# shell-common/functions/devops_help.sh
# Bundle: DevOps tool help functions

# --- docker_help (from docker_help.sh) ---

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_docker_help_summary() {
    ux_info "Usage: docker-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "compose: dc | dcu | dcud | dcd | dcl | dce"
    ux_bullet_sub "compose-extra: dcps | dcb | dcr | dcdv | dcstop | dcstart"
    ux_bullet_sub "basics: dps | dpsa | di | dstats | dstop | drm | drmi | dlogs | dinspect"
    ux_bullet_sub "resources: ddf | dprune | dprune_full | dvols | dvol_rm | dnetwork_prune | dbuild_prune"
    ux_bullet_sub "utilities: dbash | denv | dinspect_env | dstopall | drmall | dexport | dinstall | dproxy_setup"
    ux_bullet_sub "i-want: goal-based lookup  (example: docker-help i-want)"
    ux_bullet_sub "--map: intent -> alias -> raw command table"
    ux_bullet_sub "raw: copy-paste-ready full commands  (example: docker-help raw resources)"
    ux_bullet_sub "lookup: alias -> raw command  (example: docker-help dprune)"
    ux_bullet_sub "details: docker-help <section>  (example: docker-help compose)"
}

_docker_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "compose"
    ux_bullet_sub "compose-extra"
    ux_bullet_sub "basics"
    ux_bullet_sub "resources"
    ux_bullet_sub "utilities"
    ux_bullet_sub "i-want"
    ux_bullet_sub "map"
}

_docker_help_rows_compose() {
    ux_table_row "dc" "docker compose" "Base command"
    ux_table_row "dcu" "docker compose up" "Foreground start"
    ux_table_row "dcud" "docker compose up -d" "Detached start"
    ux_table_row "dcd" "docker compose down" "Stop & remove"
    ux_table_row "dcl" "logs <svc>" "Smart logs (service/container)"
    ux_table_row "dce" "exec <svc> <cmd>" "Execute command"
}

_docker_help_rows_compose_extra() {
    ux_table_row "dcps" "docker compose ps" "Status"
    ux_table_row "dcb" "docker compose build" "Build services"
    ux_table_row "dcr" "docker compose restart" "Restart services"
    ux_table_row "dcdv" "down -v" "Stop & remove volumes"
    ux_table_row "dcstop" "stop" "Stop containers"
    ux_table_row "dcstart" "start" "Start containers"
}

_docker_help_rows_basics() {
    ux_table_row "dps" "docker ps" "Running containers"
    ux_table_row "dpsa" "docker ps -a" "All containers"
    ux_table_row "di/dim" "docker images" "List images"
    ux_table_row "dstats" "docker stats" "Resource usage"
    ux_table_row "dstop" "docker stop" "Stop container"
    ux_table_row "drm" "docker rm" "Remove container"
    ux_table_row "drmi" "docker rmi" "Remove image"
    ux_table_row "dlogs" "docker logs -f" "Follow logs"
    ux_table_row "dinspect" "docker inspect" "Inspect object"
}

_docker_help_rows_resources() {
    ux_table_row "ddf" "system df" "Disk usage"
    ux_table_row "dprune" "system prune -f" "Basic cleanup (-f only; keeps images & volumes)"
    ux_table_row "dprune_full" "system prune -a --volumes" "Deep cleanup (interactive; removes images+volumes)"
    ux_table_row "dvols" "volume ls -f dangling" "Dangling volumes"
    ux_table_row "dvol_rm" "volume rm" "Remove volume"
    ux_table_row "dnetwork_prune" "network prune" "Cleanup networks"
    ux_table_row "dbuild_prune" "builder prune" "Cleanup build cache"
}

_docker_help_rows_utilities() {
    ux_table_row "dbash" "dbash <name>" "Shell access (bash/sh)"
    ux_table_row "denv" "denv <name>" "Show env vars"
    ux_table_row "dinspect_env" "inspect env" "Inspect env section"
    ux_table_row "dstopall" "Stop all" "Stop all running"
    ux_table_row "drmall" "Remove all" "Remove all containers"
    ux_table_row "dexport" "Export all" "Backup to tar files"
    ux_table_row "dinstall" "Install script" "Install Docker on WSL"
    ux_table_row "dproxy_setup" "Proxy setup" "Corporate proxy config"
    ux_info "Note: 'docker compose' (V2) is used by default."
}

_docker_help_rows_intent() {
    ux_table_row "start a stack" "dcud" "docker compose up -d"
    ux_table_row "start with overlay" "(raw)" "docker compose -f a.yml -f b.yml up -d --build"
    ux_table_row "stop a stack" "dcd" "docker compose down"
    ux_table_row "wipe data too" "dcdv" "docker compose down -v"
    ux_table_row "rebuild a service" "dcb <svc>" "docker compose build <svc>"
    ux_table_row "reset stack with volumes + rebuild" "(raw)" "docker compose -f <file> down -v && docker compose -f <file> up -d --build"
    ux_table_row "restart a service" "dcr <svc>" "docker compose restart <svc>"
    ux_table_row "follow logs" "dcl <svc>" "docker compose logs -f <svc>"
    ux_table_row "shell into container" "dbash <name>" "docker exec -it <name> bash"
    ux_table_row "list running" "dps" "docker ps"
    ux_table_row "list all" "dpsa" "docker ps -a"
    ux_table_row "disk usage" "ddf" "docker system df"
    ux_table_row "clean dangling" "dprune" "docker system prune -f"
    ux_table_row "reclaim everything" "dprune_full" "docker system prune -a --volumes"
    # 'docker-help here' is owned by #777 — keep the issue ref in code only,
    # not in the user-facing hint (gemini-code-assist review on PR #803).
    ux_info "Hint: 'docker-help here' inspects the current directory for compose files."
}

_docker_help_rows_map() {
    ux_table_header "Intent" "Alias" "Raw command"
    _docker_help_rows_intent
}

_docker_help_render_section() {
    ux_section "$1"
    "$2"
}

_docker_help_section_rows() {
    case "$1" in
        compose)
            _docker_help_rows_compose
            ;;
        compose-extra|extra)
            _docker_help_rows_compose_extra
            ;;
        basics|basic)
            _docker_help_rows_basics
            ;;
        resources|resource|prune)
            _docker_help_rows_resources
            ;;
        utilities|util|utils)
            _docker_help_rows_utilities
            ;;
        i-want|iwant|intent|want|goals|goal)
            _docker_help_rows_intent
            ;;
        map)
            _docker_help_rows_map
            ;;
        *)
            ux_error "Unknown docker-help section: $1"
            ux_info "Try: docker-help --list"
            return 1
            ;;
    esac
}

_docker_help_full() {
    ux_header "Docker / Docker Compose Quick Commands"

    _docker_help_render_section "Docker Compose Basics" _docker_help_rows_compose
    _docker_help_render_section "Docker Compose Extra" _docker_help_rows_compose_extra
    _docker_help_render_section "Docker Basics" _docker_help_rows_basics
    _docker_help_render_section "Resource Management" _docker_help_rows_resources
    _docker_help_render_section "Utilities" _docker_help_rows_utilities
    _docker_help_render_section "Intent -> Alias -> Raw" _docker_help_rows_map
}

# --- docker_help recommend (#777) ---
#
# PWD-aware Docker Compose project recommendation. Scans the current
# directory (NOT parent directories — by design, to avoid catching an
# unintended compose file) and prints a single ready-to-copy command.

_docker_help_compose_bases_in_pwd() {
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
}

# Use `find -maxdepth 1` instead of POSIX shell globs because zsh
# defaults to `nomatch` errors on unmatched globs (zsh-side regression
# during early dev: `for f in compose.*.yml` aborted the function).
# `find` is shell-agnostic and ignores empty matches naturally.
_docker_help_compose_variants_in_pwd() {
    find . -maxdepth 1 -type f \( \
        -name 'docker-compose.*.yml' -o \
        -name 'docker-compose.*.yaml' -o \
        -name 'compose.*.yml' -o \
        -name 'compose.*.yaml' \
        \) 2>/dev/null | sed 's|^\./||' | sort
}

_docker_help_has_compose_in_pwd() {
    # Assign-without-outer-quotes form so the pre-commit naming check
    # (`git/hooks/checks/naming_check.sh`) does not mis-flag these as
    # snake_case user-facing text inside quoted strings.
    local _bases _variants
    _bases=$(_docker_help_compose_bases_in_pwd)
    [ -n "$_bases" ] && return 0
    _variants=$(_docker_help_compose_variants_in_pwd)
    [ -n "$_variants" ] && return 0
    return 1
}

_docker_help_recommend_print() {
    # $1 = command, $2 = base, $3 = variant (may be empty), $4 = mode
    ux_section "Recommended command"
    # Bare monospace line for copy-paste (no icon / bullet). ux_lib has
    # no plain-text helper for code lines and the AC requires the user
    # to be able to paste this verbatim — see #777 Step 3.
    printf '  %s\n' "$1"
    ux_info ""
    ux_section "Why"
    [ -n "$2" ] && ux_bullet "base:    $2"
    [ -n "$3" ] && ux_bullet "variant: $3"
    [ -n "$4" ] && ux_bullet "mode:    $4"
}

_docker_help_recommend() {
    local bases variants base variant fake_variant variant_count

    bases=$(_docker_help_compose_bases_in_pwd)
    variants=$(_docker_help_compose_variants_in_pwd)

    if [ -z "$bases" ] && [ -z "$variants" ]; then
        ux_info "No Docker Compose files in current directory."
        ux_info "Run \`docker-help --all\` for the full alias catalog."
        return 1
    fi

    ux_info "Detected Docker Compose project."

    base="$(printf '%s\n' "$bases" | head -n1)"
    if [ -n "$variants" ]; then
        variant_count="$(printf '%s\n' "$variants" | grep -c .)"
    else
        variant_count=0
    fi
    fake_variant="$(printf '%s\n' "$variants" | grep -E '\.fake\.(yml|yaml)$' | head -n1)"

    if [ -n "$base" ] && [ -n "$fake_variant" ]; then
        _docker_help_recommend_print \
            "docker compose -f $base -f $fake_variant up -d --build" \
            "$base" "$fake_variant" "detached + rebuild"
    elif [ -n "$base" ] && [ "$variant_count" -eq 1 ]; then
        variant="$(printf '%s\n' "$variants" | head -n1)"
        _docker_help_recommend_print \
            "docker compose -f $base -f $variant up -d --build" \
            "$base" "$variant" "detached + rebuild"
    elif [ -n "$base" ] && [ "$variant_count" -ge 2 ]; then
        ux_info "Multiple compose variants detected — no single recommendation."
        ux_section "Candidate compose files"
        ux_bullet "$base (base)"
        printf '%s\n' "$variants" | while IFS= read -r f; do
            [ -n "$f" ] && ux_bullet "$f (variant)"
        done
        ux_info ""
        ux_info "Hint: check the project's helper scripts first — e.g.,"
        ux_info "  bun run 2>&1 | grep docker"
        ux_info "  jq -r '.scripts | keys[]' package.json 2>/dev/null | grep docker"
        ux_info "  grep -E '^[a-z_-]+:' Makefile 2>/dev/null"
    elif [ -n "$base" ]; then
        _docker_help_recommend_print \
            "docker compose up -d --build" \
            "$base" "" "detached + rebuild"
    else
        ux_info "Compose variant(s) found but no base file — no recommendation."
        ux_section "Candidate compose files"
        printf '%s\n' "$variants" | while IFS= read -r f; do
            [ -n "$f" ] && ux_bullet "$f (variant)"
        done
    fi

    ux_info ""
    ux_section "More"
    ux_bullet "docker-help compose"
    ux_bullet "docker-help --all"
}

# --- raw-command catalog + learning surfaces (#899) ---
#
# SSOT for the (alias -> full raw command -> description) relationship,
# tagged by section. The cryptic aliases (dprune etc.) live only in THIS
# environment; this catalog is the teaching surface that surfaces the
# portable, copy-paste-ready `docker ...` command behind each one so the
# raw command — not the alias — is what gets learned. Both the raw-first
# renderer and the reverse-lookup consume this single source.
#
# Format per line: alias|full raw command|description|section
_docker_help_catalog() {
    printf '%s\n' \
        'dc|docker compose|Base command|compose' \
        'dcu|docker compose up|Foreground start|compose' \
        'dcud|docker compose up -d|Detached start|compose' \
        'dcd|docker compose down|Stop & remove|compose' \
        'dcl|docker compose logs -f <svc>|Smart logs (service/container)|compose' \
        'dce|docker compose exec <svc> <cmd>|Execute command|compose' \
        'dcps|docker compose ps|Status|compose-extra' \
        'dcb|docker compose build|Build services|compose-extra' \
        'dcr|docker compose restart <svc>|Restart services|compose-extra' \
        'dcdv|docker compose down -v|Stop & remove volumes|compose-extra' \
        'dcstop|docker compose stop|Stop containers|compose-extra' \
        'dcstart|docker compose start|Start containers|compose-extra' \
        'dps|docker ps|Running containers|basics' \
        'dpsa|docker ps -a|All containers|basics' \
        'di|docker images|List images|basics' \
        'dim|docker images|List images (alias of di)|basics' \
        'dstats|docker stats|Resource usage|basics' \
        'dstop|docker stop <name>|Stop container|basics' \
        'drm|docker rm <name>|Remove container|basics' \
        'drmi|docker rmi <image>|Remove image|basics' \
        'dlogs|docker logs -f <name>|Follow logs|basics' \
        'dinspect|docker inspect <object>|Inspect object|basics' \
        'ddf|docker system df|Disk usage|resources' \
        'dprune|docker system prune -f|Basic cleanup (-f only; keeps images & volumes)|resources' \
        'dprune_full|docker system prune -a --volumes|Deep cleanup (removes images+volumes)|resources' \
        'dvols|docker volume ls -f dangling=true|Dangling volumes|resources' \
        'dvol_rm|docker volume rm <name>|Remove volume|resources' \
        'dnetwork_prune|docker network prune -f|Cleanup networks|resources' \
        'dbuild_prune|docker builder prune -f|Cleanup build cache|resources' \
        'dbash|docker exec -it <name> bash|Shell access (bash/sh)|utilities' \
        'denv|docker exec <name> env|Show env vars|utilities'
}

# Normalize a user-supplied section token to a canonical catalog section.
# Mirrors the synonym set in _docker_help_section_rows so `raw <section>`
# accepts the same aliases (e.g. prune -> resources).
_docker_help_normalize_section() {
    case "$1" in
        compose) printf 'compose\n' ;;
        compose-extra | extra) printf 'compose-extra\n' ;;
        basics | basic) printf 'basics\n' ;;
        resources | resource | prune) printf 'resources\n' ;;
        utilities | util | utils) printf 'utilities\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

_docker_help_is_alias() {
    _docker_help_catalog | cut -d'|' -f1 | grep -qx "$1"
}

# Reverse lookup: alias -> raw command. Teaches what an alias actually runs
# so the portable command can be verified and learned (#899 F-2).
_docker_help_reverse() {
    local al raw desc sec found
    # Pure POSIX while-read over a here-doc (no awk/cut subprocesses, and no
    # `awk -v` backslash-escape interpretation of the input) — gemini PR #901.
    found=0
    while IFS='|' read -r al raw desc sec; do
        if [ "$al" = "$1" ]; then
            found=1
            break
        fi
    done <<EOF
$(_docker_help_catalog)
EOF

    if [ "$found" -eq 0 ]; then
        ux_error "Unknown docker alias: $1"
        ux_info "Try: docker-help --list  or  docker-help raw"
        return 1
    fi
    ux_section "Alias -> raw command"
    # Bare monospace line so the raw command is copy-paste ready (no icon /
    # bullet) — same rationale as _docker_help_recommend_print (#777).
    printf '  %s  ->  %s\n' "$1" "$raw"
    ux_info "  $desc"
    ux_info ""
    ux_info "Tip: run the raw command anywhere — it works without these aliases."
}

# Raw-first rendering: full canonical commands as the primary, copy-paste
# ready surface, alias demoted to an annotation (#899 F-1). Optional
# section filter reuses the catalog's section tags.
_docker_help_raw() {
    local want_section printed al raw desc sec
    # Split guard onto its own lines: a one-line `[ -n "..." ] && x=$(fn "$1")`
    # form flanks the private-function call with quotes, which the pre-commit
    # naming_check mis-reads as snake_case user-facing text.
    want_section=""
    if [ -n "${1:-}" ]; then
        want_section=$(_docker_help_normalize_section "$1")
    fi

    if [ -n "$want_section" ]; then
        ux_section "Raw commands — $want_section (copy-paste ready)"
    else
        ux_section "Raw commands (copy-paste ready)"
    fi

    printed=0
    # Read into a temp stream so the loop body can set `printed` in the
    # current shell (a piped `while` would run in a subshell and lose it).
    while IFS='|' read -r al raw desc sec; do
        [ -z "$al" ] && continue
        if [ -n "$want_section" ] && [ "$sec" != "$want_section" ]; then
            continue
        fi
        printf '  %s\n' "$raw"
        ux_info "    alias: $al   -- $desc"
        printed=1
    done <<EOF
$(_docker_help_catalog)
EOF

    if [ "$printed" -eq 0 ]; then
        ux_error "No raw commands for section: ${1:-}"
        ux_info "Try: docker-help --list  (sections), or docker-help raw (all)"
        return 1
    fi
}

docker_help() {
    case "${1:-}" in
        "")
            # PWD compose project → recommend; otherwise fall back to
            # the canonical summary so non-compose dirs see no regression.
            if _docker_help_has_compose_in_pwd; then
                _docker_help_recommend
            else
                _docker_help_summary
            fi
            ;;
        here)
            _docker_help_recommend
            ;;
        -h|--help|help)
            _docker_help_summary
            ;;
        --list|list|section|sections)
            _docker_help_list_sections
            ;;
        --all|all)
            _docker_help_full
            ;;
        --map)
            _docker_help_rows_map
            ;;
        raw | --raw)
            _docker_help_raw "${2:-}"
            ;;
        *)
            # A known alias (dprune, dcud, ...) -> reverse lookup to its raw
            # command; otherwise treat the token as a section name. Section
            # keywords and alias names do not overlap, so order is safe and
            # the unknown-section error path is preserved (#899 F-2).
            if _docker_help_is_alias "$1"; then
                _docker_help_reverse "$1"
            else
                _docker_help_section_rows "$1"
            fi
            ;;
    esac
}

alias docker-help='docker_help'

# --- proxy_help (from proxy_help.sh) ---

_proxy_help_summary() {
    ux_info "Usage: proxy-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "diagnostics: check-proxy | env | file | shell | conn | git"
    ux_bullet_sub "commands: \$http_proxy | \$https_proxy | \$no_proxy | env | grep proxy"
    ux_bullet_sub "set: export http_proxy | https_proxy | no_proxy"
    ux_bullet_sub "unset: unset HTTP_PROXY HTTPS_PROXY NO_PROXY"
    ux_bullet_sub "git: connectTimeout | lowSpeedLimit | lowSpeedTime | view config"
    ux_bullet_sub "related: check-network quick | check-network"
    ux_bullet_sub "notes: NO_PROXY commas | uppercase env | proxy-only check"
    ux_bullet_sub "details: proxy-help <section>  (example: proxy-help set)"
}

_proxy_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "diagnostics"
    ux_bullet_sub "commands"
    ux_bullet_sub "set"
    ux_bullet_sub "unset"
    ux_bullet_sub "git"
    ux_bullet_sub "related"
    ux_bullet_sub "notes"
}

_proxy_help_rows_diagnostics() {
    ux_bullet "check-proxy          Run full diagnostic"
    ux_bullet "check-proxy env      Environment variables only"
    ux_bullet "check-proxy file     proxy.local.sh file check"
    ux_bullet "check-proxy shell    Shell loading test"
    ux_bullet "check-proxy conn     Configured proxy connectivity test"
    ux_bullet "check-proxy git      Git configuration"
}

_proxy_help_rows_commands() {
    ux_bullet "echo \$http_proxy          Current proxy setting"
    ux_bullet "echo \$https_proxy         Current HTTPS proxy"
    ux_bullet "echo \$no_proxy            NO_PROXY exceptions"
    ux_bullet "env | grep -i proxy        Show all proxy vars"
}

_proxy_help_rows_set() {
    ux_bullet "export http_proxy=\"http://proxy.example.com:8080/\""
    ux_bullet "export https_proxy=\"http://proxy.example.com:8080/\""
    ux_bullet "export no_proxy=\"localhost,127.0.0.1,.internal.domain.com\""
}

_proxy_help_rows_unset() {
    ux_bullet "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"
}

_proxy_help_rows_git() {
    ux_bullet "git config --global http.connectTimeout 60    Increase timeout"
    ux_bullet "git config --global http.lowSpeedLimit 0      Disable low speed limit"
    ux_bullet "git config --global http.lowSpeedTime 999999   Disable low speed time"
    ux_bullet "git config --global -l | grep proxy           View git proxy config"
}

_proxy_help_rows_related() {
    ux_bullet "check-network quick       General internet access check"
    ux_bullet "check-network             DNS, HTTPS, git, apt, pip, curl checks"
}

_proxy_help_rows_notes() {
    ux_warning "NO_PROXY with spaces is not recognized - use commas only"
    ux_info "Some tools only recognize uppercase (HTTP_PROXY, HTTPS_PROXY)"
    ux_info "check-proxy focuses on proxy configuration only"
}

_proxy_help_render_section() {
    ux_section "$1"
    "$2"
}

_proxy_help_section_rows() {
    case "$1" in
        diagnostics|diag)
            _proxy_help_rows_diagnostics
            ;;
        commands|quick)
            _proxy_help_rows_commands
            ;;
        set|setting|setup)
            _proxy_help_rows_set
            ;;
        unset|disable|disabling)
            _proxy_help_rows_unset
            ;;
        git)
            _proxy_help_rows_git
            ;;
        related)
            _proxy_help_rows_related
            ;;
        notes|important)
            _proxy_help_rows_notes
            ;;
        *)
            ux_error "Unknown proxy-help section: $1"
            ux_info "Try: proxy-help --list"
            return 1
            ;;
    esac
}

_proxy_help_full() {
    ux_header "Proxy Configuration & Diagnostics"

    if type ux_section >/dev/null 2>&1; then
        _proxy_help_render_section "Diagnostic Commands" _proxy_help_rows_diagnostics
        _proxy_help_render_section "Quick Commands" _proxy_help_rows_commands
        _proxy_help_render_section "Setting Proxy (Corporate Environment)" _proxy_help_rows_set
        _proxy_help_render_section "Disabling Proxy" _proxy_help_rows_unset
        _proxy_help_render_section "Git Configuration" _proxy_help_rows_git
        _proxy_help_render_section "Related Diagnostics" _proxy_help_rows_related
        _proxy_help_render_section "Important Notes" _proxy_help_rows_notes
    else
        # Fallback for minimal shells without UX library
        echo "Diagnostic Commands:"
        echo "  check-proxy          Run full diagnostic"
        echo "  check-proxy env      Environment variables only"
        echo "  check-proxy file     proxy.local.sh file check"
        echo "  check-network quick  General internet access check"
        echo ""
        echo "Quick Commands:"
        echo "  echo \$http_proxy         Current proxy setting"
        echo "  env | grep -i proxy      Show all proxy vars"
    fi
}

proxy_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _proxy_help_summary
            ;;
        --list|list|section|sections)
            _proxy_help_list_sections
            ;;
        --all|all)
            _proxy_help_full
            ;;
        *)
            _proxy_help_section_rows "$1"
            ;;
    esac
}

# Wrapper function for check_proxy.sh diagnostic
proxy_check() {
    local check_proxy_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_proxy.sh"
    if [ -f "$check_proxy_script" ]; then
        bash "$check_proxy_script" "$@"
    else
        # Error handling with fallback (guard ux_error)
        if type ux_error >/dev/null 2>&1; then
            ux_error "check_proxy.sh not found at $check_proxy_script"
        else
            echo "Error: check_proxy.sh not found at $check_proxy_script" >&2
        fi
        return 1
    fi
}

alias proxy-help='proxy_help'
alias check-proxy='proxy_check'

# --- dproxy_help (from dproxy_help.sh) ---

_dproxy_help_summary() {
    ux_info "Usage: dproxy-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "commands: dproxy_setup | dproxy_show | dproxy-help"
    ux_bullet_sub "config: /etc/systemd/system/docker.service.d/http-proxy.conf"
    ux_bullet_sub "reference: systemctl show | nano edit | daemon-reload | docker pull test"
    ux_bullet_sub "details: dproxy-help <section>  (example: dproxy-help reference)"
}

_dproxy_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "config"
    ux_bullet_sub "reference"
}

_dproxy_help_rows_commands() {
    ux_table_row "dproxy_setup" "Interactive setup script" "Configure Docker proxy"
    ux_table_row "dproxy_show" "Show current proxy config" "Display active settings"
    ux_table_row "dproxy-help" "Show this help" ""
}

_dproxy_help_rows_config() {
    ux_info "/etc/systemd/system/docker.service.d/http-proxy.conf"
}

_dproxy_help_rows_reference() {
    ux_bullet "Check config: systemctl show --property=Environment docker"
    ux_bullet "Edit config: sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf"
    ux_bullet "Apply changes: sudo systemctl daemon-reload && sudo systemctl restart docker"
    ux_bullet "Test connection: docker pull alpine:latest"
}

_dproxy_help_render_section() {
    ux_section "$1"
    "$2"
}

_dproxy_help_section_rows() {
    case "$1" in
        commands|cmd)
            _dproxy_help_rows_commands
            ;;
        config|file)
            _dproxy_help_rows_config
            ;;
        reference|ref|quick)
            _dproxy_help_rows_reference
            ;;
        *)
            ux_error "Unknown dproxy-help section: $1"
            ux_info "Try: dproxy-help --list"
            return 1
            ;;
    esac
}

_dproxy_help_full() {
    ux_header "Docker Corporate Proxy Setup Guide"

    _dproxy_help_render_section "Commands" _dproxy_help_rows_commands
    _dproxy_help_render_section "Config File" _dproxy_help_rows_config
    _dproxy_help_render_section "Quick Reference" _dproxy_help_rows_reference
}

dproxy_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _dproxy_help_summary
            ;;
        --list|list|section|sections)
            _dproxy_help_list_sections
            ;;
        --all|all)
            _dproxy_help_full
            ;;
        *)
            _dproxy_help_section_rows "$1"
            ;;
    esac
}

alias dproxy-help='dproxy_help'
