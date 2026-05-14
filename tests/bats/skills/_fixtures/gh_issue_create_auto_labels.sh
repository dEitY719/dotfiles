#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_create_auto_labels.sh
# Source-of-truth mirror for the Step 2.5 dispatch flow documented in
# claude/skills/gh-issue-create/SKILL.md and references/auto-labels.md.
#
# The skill itself runs inside Claude, but the dispatch logic boils down
# to: "given an SSOT file (or none), a conventional-commit prefix, a
# comma-separated list of user-supplied labels, the set of labels that
# already exist on the target repo, and the --no-auto-labels flag —
# what is the final label set we hand to `gh issue create`?"
#
# Keep this file in sync with SKILL.md Step 2.5 + references/auto-labels.md.
# If the dispatch order changes, mirror the change here so the bats
# suite catches drift.

# Load the real awk parser.
# shellcheck disable=SC1091
. "${_BATS_REAL_SHELL_COMMON}/functions/parse_yaml_defaults.sh"

# gh_issue_create_compose_labels
#   $1 — path to .gh-issue-defaults.yml ("" => no SSOT, signal absent)
#   $2 — conventional-commit prefix (feat/fix/refactor/test/ci/docs/chore/...)
#   $3 — comma-separated user labels passed via `--label`
#   $4 — comma-separated labels that exist on the target repo (mock)
#   $5 — "1" if --no-auto-labels, "0" otherwise
#
#   Env: $DISCUSSION_MODE — "1" when --as-discussion was set in Step 1.1
#                          (#619). Forces Step 2.5 to skip entirely and
#                          drops any user labels with no warning here
#                          (the SKILL warns once in Step 1.1).
#
# Stdout: final kept labels, one per line, in dispatch order
#         (static first, then prefix-mapped, then user labels), de-duped.
# Stderr: one `auto-labels: label '<x>' not found ...` line per dropped.
# Returns: 0 always (the skill never aborts the issue creation).
gh_issue_create_compose_labels() {
    _yml="$1"
    _prefix="$2"
    _user_csv="$3"
    _existing_csv="$4"
    _no_auto="$5"

    # --as-discussion (#619) skips Step 2.5 entirely AND drops user
    # labels — Discussions do not carry labels. The SKILL emits the
    # 1-line warning once in Step 1.1; the composer is silent here so
    # callers can distinguish "label dropped due to missing repo label"
    # from "label dropped due to Discussion mode" by checking
    # $DISCUSSION_MODE in the caller.
    if [ "${DISCUSSION_MODE:-0}" = "1" ]; then
        return 0
    fi

    # User labels are unconditional unless --no-auto-labels is set, in
    # which case Step 2.5 is skipped and only user labels remain.
    if [ "$_no_auto" = "1" ]; then
        _emit_csv "$_user_csv" "$_existing_csv"
        return 0
    fi

    # Stage-1 signal: SSOT file present. For the bats suite this is the
    # only signal we exercise — the others (rollup workflow, agent-toolbox
    # dir, AGENTS.md grep) reduce to the same "load YAML or skip" branch
    # and are documented in references/auto-labels.md.
    if [ -z "$_yml" ] || [ ! -r "$_yml" ]; then
        _emit_csv "$_user_csv" "$_existing_csv"
        return 0
    fi

    _static=$(_parse_yaml_defaults_static "$_yml")
    _prefix_labels=$(_parse_yaml_defaults_by_prefix "$_yml" "$_prefix")

    # Merge static ∪ prefix ∪ user, preserving order, then validate.
    {
        [ -n "$_static" ] && printf '%s\n' "$_static"
        [ -n "$_prefix_labels" ] && printf '%s\n' "$_prefix_labels"
        _emit_csv_raw "$_user_csv"
    } | _validate_against "$_existing_csv"
}

# Emit the user-only label set, validated against existing repo labels.
_emit_csv() {
    _csv="$1"
    _existing="$2"
    _emit_csv_raw "$_csv" | _validate_against "$_existing"
}

_emit_csv_raw() {
    _csv="$1"
    [ -z "$_csv" ] && return 0
    printf '%s' "$_csv" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}

_validate_against() {
    _existing_csv="$1"
    awk -v existing="$_existing_csv" '
        BEGIN {
            n = split(existing, parts, ",")
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                if (parts[i] != "") have[parts[i]] = 1
            }
        }
        {
            if (seen[$0]++) next
            if ($0 == "") next
            if ($0 in have) {
                print
            } else {
                printf("auto-labels: label '\''%s'\'' not found in target repo — skip\n", $0) > "/dev/stderr"
            }
        }
    '
}
