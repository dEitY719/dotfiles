#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh
# Source-of-truth mirror for the Step 2.6 detection flow documented in
# claude/skills/gh-issue-create/SKILL.md and
# references/dependency-detect.md.
#
# The skill itself runs inside Claude, but the detection half boils down
# to: "given the conversation text and the --no-auto-deps flag — which
# same-repo issue numbers should Step 4.5 pass to addBlockedBy?"
#
# Only the text->numbers half lives here. The GraphQL half (node-id
# lookup + addBlockedBy) is deliberately out of scope so this fixture
# never touches the network.
#
# Keep this file in sync with SKILL.md Step 2.6 + references/dependency-detect.md.
# If a trigger phrase is added or removed, mirror the change here so the
# bats suite catches drift.

# An issue reference, with the cross-repo `owner/repo` prefix optional so
# NF-2 can detect and reject it rather than silently mis-linking it to a
# same-numbered issue in $TARGET_REPO.
_GH_DEPS_REF='([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#[0-9]+'

# The F-1 trigger set. Korean forms trail the reference ("#13 완료 후"),
# English forms lead it ("depends on #13"). Plain mentions ("#13 참고",
# "#13 관련", a bare "#13") match nothing by construction.
_GH_DEPS_TRIGGERS="\
${_GH_DEPS_REF}[[:space:]]*완료[[:space:]]*후|\
${_GH_DEPS_REF}[[:space:]]*이후|\
depends[[:space:]]+on[[:space:]]+${_GH_DEPS_REF}|\
blocked[[:space:]]+by[[:space:]]+${_GH_DEPS_REF}|\
선행[[:space:]]*이슈[[:space:]]*[:：][[:space:]]*${_GH_DEPS_REF}"

# gh_issue_create_detect_deps
#   $1 — conversation text to scan
#   $2 — "1" if --no-auto-deps, "0" otherwise (default "0")
#
# Stdout: same-repo issue numbers, ascending and de-duped, one per line.
# Stderr: one `dependency-detect: cross-repo ...` line per NF-2 skip.
# Returns: 0 always — detection never blocks issue creation (NF-1).
gh_issue_create_detect_deps() {
    _text="$1"
    _no_auto="${2:-0}"

    # F-3: the escape hatch skips detection itself, not just the linking.
    if [ "$_no_auto" = "1" ]; then
        return 0
    fi

    # Two greps, never one per match: the first anchors a reference to a
    # trigger phrase (that anchoring is the whole false-positive defence),
    # the second pulls the reference back out. Every trigger alternative
    # embeds exactly one reference, so the two streams stay 1:1 and each
    # surviving line is either a same-repo number or an NF-2 cross-repo skip.
    printf '%s\n' "$_text" |
        grep -oiE "$_GH_DEPS_TRIGGERS" |
        grep -oE "$_GH_DEPS_REF" |
        while IFS= read -r _ref; do
            case "$_ref" in
                */*)
                    printf 'dependency-detect: cross-repo dependency detected but not supported in v1 — skip (%s)\n' \
                        "$_ref" >&2
                    ;;
                *)
                    printf '%s\n' "${_ref#\#}"
                    ;;
            esac
        done | sort -n -u
    return 0
}
