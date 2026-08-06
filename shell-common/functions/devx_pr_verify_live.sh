#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/devx_pr_verify_live.sh
# Pure arg parser for the devx:pr-verify-live skill. Mirrors the
# devx_pr_review_all_parse contract: one `key=value` line per resolved arg
# on success, errors to stderr. Exit 0 ok/help, exit 2 arg error. Runtime
# checks (PR state, gh auth, dev-server reachability) belong to the skill body.

_devx_pr_verify_live_pos_int() {
    case "$1" in
    "" | *[!0-9]*) return 1 ;;
    *[!0]*) return 0 ;;
    *) return 1 ;;
    esac
}

devx_pr_verify_live_parse() {
    pr=""
    remote="origin"
    url=""
    api_url=""
    start_cmd=""
    matrix="auto"
    viewports=""
    locales=""
    issue_mode="create"
    allow_remote_host=0
    _remote_set=0
    _start_set=0
    _no_issue=0
    _rest=""
    _item=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --url | --api-url | --start | --matrix | --viewports | --locales)
            [ "$#" -lt 2 ] && {
                echo "missing value for $1" >&2
                return 2
            }
            ;;
        esac
        case "$1" in
        --url)
            url="$2"
            shift 2
            ;;
        --url=*)
            url="${1#--url=}"
            shift
            ;;
        --api-url)
            api_url="$2"
            shift 2
            ;;
        --api-url=*)
            api_url="${1#--api-url=}"
            shift
            ;;
        --start)
            start_cmd="$2"
            _start_set=1
            shift 2
            ;;
        --start=*)
            start_cmd="${1#--start=}"
            _start_set=1
            shift
            ;;
        --matrix)
            matrix="$2"
            shift 2
            ;;
        --matrix=*)
            matrix="${1#--matrix=}"
            shift
            ;;
        --viewports)
            viewports="$2"
            shift 2
            ;;
        --viewports=*)
            viewports="${1#--viewports=}"
            shift
            ;;
        --locales)
            locales="$2"
            shift 2
            ;;
        --locales=*)
            locales="${1#--locales=}"
            shift
            ;;
        --dry-run)
            issue_mode="dry-run"
            shift
            ;;
        --no-issue)
            _no_issue=1
            shift
            ;;
        --allow-remote-host)
            allow_remote_host=1
            shift
            ;;
        -h | --help | help)
            echo "help_requested=1"
            return 0
            ;;
        --*)
            echo "Unknown flag: $1" >&2
            return 2
            ;;
        *)
            if [ -z "$pr" ]; then
                pr="$1"
            elif [ "$_remote_set" -eq 0 ]; then
                remote="$1"
                _remote_set=1
            else
                echo "Unexpected positional arg: $1" >&2
                return 2
            fi
            shift
            ;;
        esac
    done

    if [ -n "$pr" ]; then
        _devx_pr_verify_live_pos_int "$pr" || {
            echo "PR# must be a positive integer: '$pr'" >&2
            return 2
        }
    fi

    case "$url" in
    "" | http://* | https://*) ;;
    *)
        echo "--url must be an http(s) URL: '$url'" >&2
        return 2
        ;;
    esac

    case "$api_url" in
    "" | http://* | https://*) ;;
    *)
        echo "--api-url must be an http(s) URL: '$api_url'" >&2
        return 2
        ;;
    esac

    if [ "$_start_set" -eq 1 ] && [ -z "$start_cmd" ]; then
        echo "--start value must not be empty" >&2
        return 2
    fi

    case "$matrix" in
    auto | full) ;;
    *)
        echo "--matrix must be auto or full: '$matrix'" >&2
        return 2
        ;;
    esac

    if [ -n "$viewports" ]; then
        _rest="${viewports},"
        while [ -n "$_rest" ]; do
            _item="${_rest%%,*}"
            _rest="${_rest#*,}"
            if ! _devx_pr_verify_live_pos_int "$_item"; then
                echo "--viewports must be a CSV of positive integers: '$viewports'" >&2
                return 2
            fi
        done
    fi

    if [ -n "$locales" ]; then
        _rest="${locales},"
        while [ -n "$_rest" ]; do
            _item="${_rest%%,*}"
            _rest="${_rest#*,}"
            if [ -z "$_item" ]; then
                echo "--locales must be a CSV of non-empty locale tags: '$locales'" >&2
                return 2
            fi
        done
    fi

    if [ "$_no_issue" -eq 1 ]; then
        issue_mode="none"
    fi

    printf '%s\n' "pr=$pr"
    printf '%s\n' "remote=$remote"
    printf '%s\n' "url=$url"
    printf '%s\n' "api_url=$api_url"
    printf '%s\n' "start_cmd=$start_cmd"
    printf '%s\n' "matrix=$matrix"
    printf '%s\n' "viewports=$viewports"
    printf '%s\n' "locales=$locales"
    printf '%s\n' "issue_mode=$issue_mode"
    printf '%s\n' "allow_remote_host=$allow_remote_host"
    return 0
}
