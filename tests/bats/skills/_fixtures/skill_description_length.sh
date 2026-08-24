#!/usr/bin/env bash
# tests/bats/skills/_fixtures/skill_description_length.sh
# Source-of-truth mirror for Check 16 (Description Length) documented in
#   claude/skills/skill-check/references/checks.md
#
# skill:check is AI-interpreted markdown with no shell entry point; these
# functions are the executable form of Check 16's extraction and verdict
# rules, so bats can pin the boundaries against real SKILL.md files.
# Keep them in sync with checks.md whenever the thresholds change.
#
# All functions take an explicit <skill_md> path — no globals, no network.

# Thresholds (issue #1411). Keep byte-identical to the table in checks.md.
SKILL_DESC_PASS_MAX=250
SKILL_DESC_WARN_MAX=400

# skill_desc_extract <skill_md>
#
# Echo the frontmatter `description` as ONE whitespace-normalised line.
# Handles both the single-line form and YAML folded scalars (`>-`, `>`, `|`).
# Stops at the next top-level key or at the closing `---`, so metadata /
# compatibility / allowed-tools blocks are never counted as description text.
# Returns 1 when the file has no description (Check 3 owns that failure).
skill_desc_extract() {
    local _f="$1" _out
    [ -f "$_f" ] || return 1

    _out=$(awk '
		BEGIN { infm = 0; ind = 0 }
		NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
		infm == 0 { next }
		/^---[[:space:]]*$/ { exit }
		# A new top-level key ends the description block.
		ind == 1 && /^[A-Za-z_][A-Za-z0-9_-]*:/ { exit }
		/^description:[[:space:]]*/ {
			ind = 1
			sub(/^description:[[:space:]]*/, "")
			# Drop a bare folded/literal scalar marker (">-", ">", "|", "|-").
			sub(/^[>|][-+]?[[:space:]]*$/, "")
			if (length($0) > 0) print $0
			next
		}
		ind == 1 { print $0 }
	' "$_f")

    # Collapse every whitespace run (including the folded line breaks) into a
    # single space, then trim. Mirrors how a harness renders a folded scalar.
    _out=$(printf '%s' "$_out" | tr '\n' ' ' |
        sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//')

    [ -n "$_out" ] || return 1
    printf '%s\n' "$_out"
}

# skill_desc_length <skill_md>
#
# Echo the description length in CHARACTERS, not bytes. Korean trigger
# phrases are 3 bytes per glyph, so byte counting over-reports by ~3x and
# would make every bilingual description look like a FAIL.
# Returns 1 when the file has no description.
skill_desc_length() {
    local _d
    _d=$(skill_desc_extract "$1") || return 1
    printf '%s' "$_d" | LC_ALL=C.UTF-8 wc -m | tr -d '[:space:]'
}

# skill_desc_verdict <char_count>
#
# PASS <= 250 | WARN 251-400 | FAIL > 400.
# Returns 1 on a non-numeric argument.
skill_desc_verdict() {
    local _n="$1"
    case "$_n" in
    '' | *[!0-9]*) return 1 ;;
    esac

    if [ "$_n" -le "$SKILL_DESC_PASS_MAX" ]; then
        printf 'PASS\n'
    elif [ "$_n" -le "$SKILL_DESC_WARN_MAX" ]; then
        printf 'WARN\n'
    else
        printf 'FAIL\n'
    fi
}
