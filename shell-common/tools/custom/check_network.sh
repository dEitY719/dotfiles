#!/bin/bash
# shell-common/tools/custom/check_network.sh
# Comprehensive internet connectivity diagnostic script
# Usage: check_network [quick|dns|ping|https|git|apt|pip|curl|all]

source "$(dirname "$0")/init.sh" || exit 1

NETWORK_DNS_TARGET="${NETWORK_DNS_TARGET:-example.com}"
NETWORK_PING_TARGET="${NETWORK_PING_TARGET:-1.1.1.1}"
NETWORK_HTTPS_TARGET="${NETWORK_HTTPS_TARGET:-https://example.com}"
NETWORK_GIT_TARGET="${NETWORK_GIT_TARGET:-https://github.com/git/git.git}"
NETWORK_PIP_TARGET_DEFAULT="${NETWORK_PIP_TARGET_DEFAULT:-https://pypi.org/simple/pip/}"

NETWORK_PASS_COUNT=0
NETWORK_WARN_COUNT=0
NETWORK_FAIL_COUNT=0

record_pass() {
    NETWORK_PASS_COUNT=$((NETWORK_PASS_COUNT + 1))
}

record_warn() {
    NETWORK_WARN_COUNT=$((NETWORK_WARN_COUNT + 1))
}

record_fail() {
    NETWORK_FAIL_COUNT=$((NETWORK_FAIL_COUNT + 1))
}

test_http_head() {
    local url="$1"
    local http_code=""

    if ! have_command curl; then
        return 127
    fi

    http_code="$(curl -I -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)"
    if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
        printf "%s\n" "$http_code"
        return 0
    fi

    return 1
}

test_http_get() {
    local url="$1"
    local http_code=""

    if ! have_command curl; then
        return 127
    fi

    http_code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)"
    if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
        printf "%s\n" "$http_code"
        return 0
    fi

    return 1
}

detect_pip_target() {
    local configured_repo=""

    if have_command pip; then
        configured_repo="$(pip config list 2>/dev/null | grep "global.index-url" | head -n 1 | cut -d "=" -f 2- | tr -d "'" | xargs)"
    fi

    if [ -n "${PIP_INDEX_URL:-}" ]; then
        configured_repo="${PIP_INDEX_URL}"
    fi

    if [ -n "$configured_repo" ]; then
        printf "%s\n" "$configured_repo"
    else
        printf "%s\n" "$NETWORK_PIP_TARGET_DEFAULT"
    fi
}

detect_apt_target() {
    local apt_uri=""
    local source_file=""

    if ! have_command apt-get; then
        return 1
    fi

    apt_uri="$(apt-get indextargets --format '$(URI)' 2>/dev/null | head -n 1)"
    if [ -n "$apt_uri" ]; then
        printf "%s\n" "$apt_uri"
        return 0
    fi

    for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        if [ -f "$source_file" ]; then
            apt_uri="$(grep -E '^[[:space:]]*deb[[:space:]]+https?://' "$source_file" 2>/dev/null | awk '{print $2; exit}')"
            if [ -n "$apt_uri" ]; then
                printf "%s\n" "$apt_uri"
                return 0
            fi
        fi
    done

    for source_file in /etc/apt/sources.list.d/*.sources; do
        if [ -f "$source_file" ]; then
            apt_uri="$(grep -E '^[[:space:]]*URIs:[[:space:]]+https?://' "$source_file" 2>/dev/null | awk '{print $2; exit}')"
            if [ -n "$apt_uri" ]; then
                printf "%s\n" "$apt_uri"
                return 0
            fi
        fi
    done

    return 1
}

check_network_dns() {
    ux_header "1. DNS Resolution"
    ux_section "Target"
    ux_bullet "$NETWORK_DNS_TARGET"

    if have_command getent; then
        local result=""
        result="$(getent hosts "$NETWORK_DNS_TARGET" 2>/dev/null | head -n 1)"
        if [ -n "$result" ]; then
            ux_success "DNS lookup successful"
            ux_bullet "$result"
            record_pass
        else
            ux_error "DNS lookup failed via getent"
            record_fail
        fi
    elif have_command nslookup; then
        local result=""
        result="$(nslookup "$NETWORK_DNS_TARGET" 2>/dev/null | awk '/^Address: / { print $2; exit }')"
        if [ -n "$result" ]; then
            ux_success "DNS lookup successful"
            ux_bullet "$result"
            record_pass
        else
            ux_error "DNS lookup failed via nslookup"
            record_fail
        fi
    elif have_command host; then
        local result=""
        result="$(host "$NETWORK_DNS_TARGET" 2>/dev/null | head -n 1)"
        if [ -n "$result" ]; then
            ux_success "DNS lookup successful"
            ux_bullet "$result"
            record_pass
        else
            ux_error "DNS lookup failed via host"
            record_fail
        fi
    else
        ux_warning "No DNS lookup command available (getent/nslookup/host)"
        record_warn
    fi
    echo ""
}

check_network_ping() {
    ux_header "2. ICMP Ping"
    ux_section "Target"
    ux_bullet "$NETWORK_PING_TARGET"

    if ! have_command ping; then
        ux_warning "ping command not available"
        record_warn
        echo ""
        return 0
    fi

    if run_with_timeout 3 ping -c 1 "$NETWORK_PING_TARGET" >/dev/null 2>&1; then
        ux_success "ICMP ping successful"
        record_pass
    else
        ux_warning "No ICMP reply received"
        ux_info "This can be normal when ICMP is blocked by firewall or network policy"
        record_warn
    fi
    echo ""
}

check_network_https() {
    ux_header "3. HTTPS HEAD Request"
    ux_section "Target"
    ux_bullet "$NETWORK_HTTPS_TARGET"

    local http_code=""
    http_code="$(test_http_head "$NETWORK_HTTPS_TARGET")"
    case $? in
        0)
            ux_success "HTTPS request successful (HTTP $http_code)"
            record_pass
            ;;
        127)
            ux_warning "curl command not available"
            record_warn
            ;;
        *)
            ux_error "HTTPS request failed"
            record_fail
            ;;
    esac
    echo ""
}

check_network_git() {
    ux_header "4. Git Remote Access"
    ux_section "Target"
    ux_bullet "$NETWORK_GIT_TARGET"

    if ! have_command git; then
        ux_warning "git command not available"
        record_warn
        echo ""
        return 0
    fi

    if run_with_timeout 10 git ls-remote "$NETWORK_GIT_TARGET" HEAD >/dev/null 2>&1; then
        ux_success "Git remote access successful"
        record_pass
    else
        ux_error "Git remote access failed"
        record_fail
    fi
    echo ""
}

check_network_apt() {
    ux_header "5. APT Repository Reachability"

    if ! have_command apt-get; then
        ux_info "APT is not available on this system"
        record_warn
        echo ""
        return 0
    fi

    local apt_target=""
    apt_target="$(detect_apt_target)"
    if [ -z "$apt_target" ]; then
        ux_warning "Could not detect an APT repository URL"
        record_warn
        echo ""
        return 0
    fi

    ux_section "Target"
    ux_bullet "$apt_target"

    local http_code=""
    http_code="$(test_http_head "$apt_target")"
    case $? in
        0)
            ux_success "APT repository reachable (HTTP $http_code)"
            record_pass
            ;;
        127)
            ux_warning "curl command not available for APT reachability test"
            record_warn
            ;;
        *)
            ux_error "APT repository not reachable"
            record_fail
            ;;
    esac
    echo ""
}

check_network_pip() {
    ux_header "6. pip Repository Reachability"

    if ! have_command pip; then
        ux_warning "pip command not available"
        record_warn
        echo ""
        return 0
    fi

    local pip_target=""
    pip_target="$(detect_pip_target)"

    ux_section "Target"
    ux_bullet "$pip_target"

    local http_code=""
    http_code="$(test_http_head "$pip_target")"
    case $? in
        0)
            ux_success "pip repository reachable (HTTP $http_code)"
            record_pass
            ;;
        127)
            ux_warning "curl command not available for pip reachability test"
            record_warn
            ;;
        *)
            ux_error "pip repository not reachable"
            record_fail
            ;;
    esac
    echo ""
}

check_network_curl() {
    ux_header "7. curl External Service Access"
    ux_section "Target"
    ux_bullet "$NETWORK_HTTPS_TARGET"

    local http_code=""
    http_code="$(test_http_get "$NETWORK_HTTPS_TARGET")"
    case $? in
        0)
            ux_success "curl GET request successful (HTTP $http_code)"
            record_pass
            ;;
        127)
            ux_warning "curl command not available"
            record_warn
            ;;
        *)
            ux_error "curl GET request failed"
            record_fail
            ;;
    esac
    echo ""
}

show_usage() {
    ux_header "check-network Usage"
    ux_bullet "check-network         Run all connectivity checks"
    ux_bullet "check-network quick   Run DNS, HTTPS, and git checks"
    ux_bullet "check-network dns     DNS resolution test"
    ux_bullet "check-network ping    ICMP ping test"
    ux_bullet "check-network https   HTTPS HEAD request test"
    ux_bullet "check-network git     Git remote access test"
    ux_bullet "check-network apt     APT repository reachability"
    ux_bullet "check-network pip     pip repository reachability"
    ux_bullet "check-network curl    curl GET request test"
    echo ""
}

show_summary() {
    ux_divider_thick
    ux_section "Summary"
    ux_bullet "Passed: $NETWORK_PASS_COUNT"
    ux_bullet "Warnings: $NETWORK_WARN_COUNT"
    ux_bullet "Failures: $NETWORK_FAIL_COUNT"
    echo ""
}

run_all_checks() {
    check_network_dns
    check_network_ping
    check_network_https
    check_network_git
    check_network_apt
    check_network_pip
    check_network_curl
}

run_quick_checks() {
    check_network_dns
    check_network_https
    check_network_git
}

check_network() {
    local mode="${1:-all}"

    case "$mode" in
        quick)
            run_quick_checks
            ;;
        dns)
            check_network_dns
            ;;
        ping)
            check_network_ping
            ;;
        https)
            check_network_https
            ;;
        git)
            check_network_git
            ;;
        apt)
            check_network_apt
            ;;
        pip)
            check_network_pip
            ;;
        curl)
            check_network_curl
            ;;
        help|-h|--help)
            show_usage
            return 0
            ;;
        all)
            run_all_checks
            ;;
        *)
            ux_error "Unknown mode: $mode"
            show_usage
            record_fail
            ;;
    esac

    show_summary

    if [ "$NETWORK_FAIL_COUNT" -gt 0 ]; then
        return 1
    fi

    return 0
}

main() {
    check_network "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
