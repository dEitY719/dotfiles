#!/bin/sh
# shell-common/tools/integrations/redis.sh
# Redis service bootstrap and helpers for WSL

# -------------------------------
# Configuration
# -------------------------------
REDIS_DEFAULT_HOST="${REDIS_DEFAULT_HOST:-127.0.0.1}"
REDIS_DEFAULT_PORT="${REDIS_DEFAULT_PORT:-6379}"
# Authentication: set REDISCLI_AUTH env var for password-protected instances.
# redis-cli reads REDISCLI_AUTH automatically, so all wrapper functions
# work transparently with or without a password.

# -------------------------------
# Internal helpers
# -------------------------------
_redis_has_systemd() {
    command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]
}

_redis_cli() {
    redis-cli -h "$REDIS_DEFAULT_HOST" -p "$REDIS_DEFAULT_PORT" "$@"
}

# -------------------------------
# 1) Server Management
# -------------------------------
redis_server() {
    local action="${1:-}"

    if [ -z "$action" ]; then
        ux_usage "redis-server-ctl" "<start|stop|restart|status>" "Manage Redis service"
        ux_section "Commands"
        ux_bullet "start   — Start Redis server"
        ux_bullet "stop    — Stop Redis server"
        ux_bullet "restart — Restart Redis server"
        ux_bullet "status  — Show service status"
        return 1
    fi

    case "$action" in
    start | stop | restart | status)
        if _redis_has_systemd; then
            ux_info "Running: sudo systemctl $action redis-server"
            sudo systemctl "$action" redis-server
        else
            ux_info "Running: sudo service redis-server $action"
            sudo service redis-server "$action"
        fi
        ;;
    *)
        ux_error "Unknown action: $action"
        ux_usage "redis-server-ctl" "<start|stop|restart|status>" ""
        return 1
        ;;
    esac
}

# -------------------------------
# 2) Quick Commands
# -------------------------------
redis_ping() {
    local host="${1:-$REDIS_DEFAULT_HOST}"
    local port="${2:-$REDIS_DEFAULT_PORT}"
    local result
    result=$(redis-cli -h "$host" -p "$port" ping 2>/dev/null)
    if [ "$result" = "PONG" ]; then
        ux_success "Redis is running (${host}:${port})"
    else
        ux_error "Redis is not responding (${host}:${port})"
        if [ -z "${REDISCLI_AUTH:-}" ]; then
            ux_info "If Redis requires a password, set: export REDISCLI_AUTH=<password>"
        fi
        return 1
    fi
}

redis_info() {
    local section="${1:-server}"
    _redis_cli INFO "$section"
}

redis_monitor() {
    ux_warning "Entering MONITOR mode (Ctrl+C to exit)"
    ux_info "Shows all commands processed by Redis in real-time"
    _redis_cli MONITOR
}

redis_dbsize() {
    local result
    result=$(_redis_cli DBSIZE 2>/dev/null)
    ux_info "Database size: $result"
}

redis_keys() {
    local pattern="${1:-*}"
    local limit="${2:-20}"
    ux_info "Scanning keys matching '$pattern' (max: $limit results)"
    _redis_cli --scan --pattern "$pattern" | head -n "$limit"
}

redis_flush() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        ux_usage "redis-flush" "<db|all>" "Flush Redis data"
        ux_bullet "db  — Flush current database (FLUSHDB)"
        ux_bullet "all — Flush all databases (FLUSHALL)"
        return 1
    fi

    case "$target" in
    db)
        if ux_confirm "Flush current Redis database?" "n"; then
            _redis_cli FLUSHDB
            ux_success "Current database flushed."
        else
            ux_info "Operation cancelled."
        fi
        ;;
    all)
        if ux_confirm "Flush ALL Redis databases? This cannot be undone!" "n"; then
            _redis_cli FLUSHALL
            ux_success "All databases flushed."
        else
            ux_info "Operation cancelled."
        fi
        ;;
    *)
        ux_error "Unknown target: $target (use 'db' or 'all')"
        return 1
        ;;
    esac
}

redis_config_get() {
    local param="${1:-}"
    if [ -z "$param" ]; then
        ux_usage "redis-config-get" "<parameter>" "Get Redis config value"
        ux_bullet "Example: redis-config-get maxmemory"
        return 1
    fi
    _redis_cli CONFIG GET "$param"
}

redis_slowlog() {
    local count="${1:-10}"
    ux_header "Redis Slow Log (last $count entries)"
    _redis_cli SLOWLOG GET "$count"
}

redis_clients() {
    ux_header "Connected Redis Clients"
    _redis_cli CLIENT LIST
}

redis_memory() {
    ux_header "Redis Memory Usage"
    _redis_cli INFO memory
}

# -------------------------------
# 3) Install Wrapper
# -------------------------------
install_redis() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_redis.sh"
}

# -------------------------------
# 4) Aliases (dash-form)
# -------------------------------
alias redis-server-ctl='redis_server'
alias redis-ping='redis_ping'
alias redis-info='redis_info'
alias redis-monitor='redis_monitor'
alias redis-dbsize='redis_dbsize'
alias redis-keys='redis_keys'
alias redis-flush='redis_flush'
alias redis-config-get='redis_config_get'
alias redis-slowlog='redis_slowlog'
alias redis-clients='redis_clients'
alias redis-memory='redis_memory'
alias install-redis='install_redis'
