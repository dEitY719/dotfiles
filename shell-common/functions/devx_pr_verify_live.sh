#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/devx_pr_verify_live.sh
# Pure arg parser for the devx:pr-verify-live skill. Mirrors the
# devx_pr_review_all_parse contract: one `key=value` line per resolved arg
# on success, errors to stderr. Exit 0 ok/help, exit 2 arg error. Runtime
# checks (PR state, gh auth, dev-server reachability) belong to the skill body.

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
    _dry_run=0
    _no_issue=0
    _rest=""
    _item=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --url)
            [ "$#" -lt 2 ] && {
                echo "missing value for --url" >&2
                return 2
            }
            url="$2"
            shift 2
            ;;
        --url=*)
            url="${1#--url=}"
            shift
            ;;
        --api-url)
            [ "$#" -lt 2 ] && {
                echo "missing value for --api-url" >&2
                return 2
            }
            api_url="$2"
            shift 2
            ;;
        --api-url=*)
            api_url="${1#--api-url=}"
            shift
            ;;
        --start)
            [ "$#" -lt 2 ] && {
                echo "missing value for --start" >&2
                return 2
            }
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
            [ "$#" -lt 2 ] && {
                echo "missing value for --matrix" >&2
                return 2
            }
            matrix="$2"
            shift 2
            ;;
        --matrix=*)
            matrix="${1#--matrix=}"
            shift
            ;;
        --viewports)
            [ "$#" -lt 2 ] && {
                echo "missing value for --viewports" >&2
                return 2
            }
            viewports="$2"
            shift 2
            ;;
        --viewports=*)
            viewports="${1#--viewports=}"
            shift
            ;;
        --locales)
            [ "$#" -lt 2 ] && {
                echo "missing value for --locales" >&2
                return 2
            }
            locales="$2"
            shift 2
            ;;
        --locales=*)
            locales="${1#--locales=}"
            shift
            ;;
        --dry-run)
            _dry_run=1
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
        case "$pr" in
        *[!0-9]*)
            echo "PR# must be a positive integer: '$pr'" >&2
            return 2
            ;;
        *[!0]*) ;;
        *)
            echo "PR# must be a positive integer: '$pr'" >&2
            return 2
            ;;
        esac
    fi

    if [ -n "$url" ]; then
        case "$url" in
        http://* | https://*) ;;
        *)
            echo "--url must be an http(s) URL: '$url'" >&2
            return 2
            ;;
        esac
    fi

    if [ -n "$api_url" ]; then
        case "$api_url" in
        http://* | https://*) ;;
        *)
            echo "--api-url must be an http(s) URL: '$api_url'" >&2
            return 2
            ;;
        esac
    fi

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
            case "$_item" in
            "" | *[!0-9]*)
                echo "--viewports must be a CSV of positive integers: '$viewports'" >&2
                return 2
                ;;
            *[!0]*) ;;
            *)
                echo "--viewports must be a CSV of positive integers: '$viewports'" >&2
                return 2
                ;;
            esac
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
    elif [ "$_dry_run" -eq 1 ]; then
        issue_mode="dry-run"
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
