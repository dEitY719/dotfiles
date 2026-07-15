#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/devx_pr_review_all.sh
# Pure arg parser for the devx:pr-review-all skill. Mirrors the
# gh_pr_review_parse contract: one `key=value` line per resolved arg on
# success, errors to stderr. Exit 0 ok/help, exit 2 arg error. Runtime
# checks (PR state, gh auth, CLI presence) belong to the skill body.

devx_pr_review_all_parse() {
    pr=""
    remote="origin"
    reply_mode="inline"
    reply_delay="8"
    _no_reply=0
    _remote_set=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --defer-reply)
            [ "$#" -lt 2 ] && {
                echo "missing value for --defer-reply" >&2
                return 2
            }
            reply_delay="$2"
            reply_mode="defer"
            shift 2
            ;;
        --defer-reply=*)
            reply_delay="${1#--defer-reply=}"
            reply_mode="defer"
            shift
            ;;
        --no-reply)
            _no_reply=1
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

    case "$pr" in
    "")
        echo "missing required arg: <PR#>" >&2
        return 2
        ;;
    *[!0-9]*)
        echo "PR# must be a positive integer: '$pr'" >&2
        return 2
        ;;
    esac

    if [ "$_no_reply" -eq 1 ]; then
        reply_mode="none"
    elif [ "$reply_mode" = "defer" ]; then
        case "$reply_delay" in
        "" | *[!0-9]*)
            echo "--defer-reply value must be a positive integer" >&2
            return 2
            ;;
        esac
    fi

    echo "pr=$pr"
    echo "remote=$remote"
    echo "reply_mode=$reply_mode"
    echo "reply_delay=$reply_delay"
    return 0
}
