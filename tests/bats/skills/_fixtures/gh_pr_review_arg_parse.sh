#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_pr_review_arg_parse.sh
# Source-of-truth mirror for the Step 1 arg-parsing + Step 3 preset-
# normalization logic documented in claude/skills/gh-pr-review/SKILL.md
# and claude/skills/gh-pr-review/references/review-presets.md.
#
# The skill body itself runs inside a Claude session, but its argument
# contract is a flat POSIX-style state machine that can be tested in
# isolation. Keep this file in sync with the SKILL — if either the SKILL
# or references/review-presets.md changes, mirror the change here so the
# bats suite catches drift.

# gh_pr_review_parse — parses the same arg surface as the skill.
# Echoes one key=value per line on success; writes errors to stderr.
# Exit codes mirror the skill:
#   0 — parsed ok
#   1 — runtime failure (unknown --user account; not produced here —
#       account whitelist resolution is left to the live helper)
#   2 — argument error (missing --ai, unknown --ai, unknown --review,
#       --user with non-claude --ai)
gh_pr_review_parse() {
    local ai=""
    local review="default"
    local user=""
    local post_comment=1
    local pr=""
    local remote="origin"

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --ai)
            ai="$2"
            shift 2
            ;;
        --ai=*)
            ai="${1#--ai=}"
            shift
            ;;
        --review)
            review="$2"
            shift 2
            ;;
        --review=*)
            review="${1#--review=}"
            shift
            ;;
        --user)
            user="$2"
            shift 2
            ;;
        --user=*)
            user="${1#--user=}"
            shift
            ;;
        --no-post-comment)
            post_comment=0
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
            elif [ "$remote" = "origin" ]; then
                remote="$1"
            else
                echo "Unexpected positional arg: $1" >&2
                return 2
            fi
            shift
            ;;
        esac
    done

    # --ai is required.
    if [ -z "$ai" ]; then
        echo "missing required flag: --ai <codex|gemini|claude>" >&2
        return 2
    fi

    # --ai must be one of the three allowed values.
    case "$ai" in
    codex | gemini | claude) ;;
    *)
        echo "Unknown --ai value: '$ai' (allowed: codex, gemini, claude)" >&2
        return 2
        ;;
    esac

    # --user is claude-only.
    if [ -n "$user" ] && [ "$ai" != "claude" ]; then
        echo "--user is only valid with --ai claude (codex/gemini have no multi-account routing)" >&2
        return 2
    fi

    # Normalize --review (KR aliases → English enum).
    case "$review" in
    보통) review="default" ;;
    간단) review="quick" ;;
    꼼꼼 | 꼼꼼하게) review="thorough" ;;
    보안) review="security" ;;
    성능) review="performance" ;;
    esac

    case "$review" in
    default | quick | thorough | security | performance) ;;
    *)
        cat >&2 <<EOF
Unknown --review value: '$review'
Allowed: default | quick | thorough | security | performance
Korean aliases: 보통 | 간단 | 꼼꼼 (꼼꼼하게) | 보안 | 성능
EOF
        return 2
        ;;
    esac

    echo "ai=$ai"
    echo "review=$review"
    echo "user=$user"
    echo "post_comment=$post_comment"
    echo "pr=$pr"
    echo "remote=$remote"
    return 0
}
