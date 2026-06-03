#!/bin/sh
# shell-common/functions/claude_allow_clean.sh
#
# Removes accumulated junk from Claude Code's permissions.allow list in
# .claude/settings.local.json. Junk accretes from per-session auto-approvals
# that are one-time (e.g., __NEW_LINE__ tokens), structurally broken
# (multi-line command artifacts), or should never be pre-approved (--no-verify).
#
# Usage: claude-allow-clean [--dry-run] [path/to/settings.local.json]

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_claude_allow_clean_usage() {
	ux_info "Usage: claude-allow-clean [--dry-run] [path]"
	ux_bullet "options"
	ux_bullet_sub "--dry-run, -n  preview removals without modifying"
	ux_bullet_sub "path           override auto-detected file"
	ux_bullet "auto-detects <git-root>/.claude/settings.local.json"
	ux_bullet "global fallback: ~/.claude/settings.local.json"
}

_claude_allow_clean_find_file() {
	_cac_root=$(git rev-parse --show-toplevel 2>/dev/null)
	if [ -n "$_cac_root" ] && [ -f "$_cac_root/.claude/settings.local.json" ]; then
		printf '%s/.claude/settings.local.json\n' "$_cac_root"
		return 0
	fi
	if [ -f "${HOME}/.claude/settings.local.json" ]; then
		printf '%s/.claude/settings.local.json\n' "$HOME"
		return 0
	fi
	return 1
}

_claude_allow_clean_write_filter() {
	# $1 = output file path for the jq filter
	#
	# Keeps an entry only if ALL conditions hold:
	#   1. Matches a known permission prefix (Bash/Read/Write/Edit/WebFetch/
	#      WebSearch/Skill/mcp__/Agent) — anything else is structural junk.
	#   2. No embedded newlines — multi-line heredoc git-commit commands that
	#      got approved whole are artifacts that will never re-match.
	#   3. Not a __NEW_LINE__ per-line token — auto-generated for multi-line
	#      commands; the hash never recurs so the entry is permanently dead.
	#   4. Not a bare shell syntax fragment (Bash(}), Bash(EOF)).
	#   5. Not a --no-verify Bash command — should never be pre-approved.
	#   6. Not a debug-trace invocation (GIT_TRACE=, PS4=).
	cat >"$1" <<'JQEOF'
.permissions.allow = ((.permissions.allow // []) | map(select(
  test("^(Bash|Read|Write|Edit|WebFetch|WebSearch|Skill|mcp__|Agent)") and
  (contains("\n") | not) and
  (startswith("Bash(__NEW_LINE_") | not) and
  . != "Bash(})" and
  . != "Bash(EOF)" and
  ((startswith("Bash(") and contains("--no-verify")) | not) and
  (startswith("Bash(GIT_TRACE=") | not) and
  (startswith("Bash(PS4=") | not)
)))
JQEOF
}

claude_allow_clean() {
	_cac_dry_run=0
	_cac_target=""

	while [ $# -gt 0 ]; do
		case "$1" in
		--dry-run | -n)
			_cac_dry_run=1
			shift
			;;
		-h | --help | help)
			_claude_allow_clean_usage
			return 0
			;;
		--)
			shift
			_cac_target="${1:-}"
			break
			;;
		-*)
			ux_error "Unknown option: $1"
			_claude_allow_clean_usage
			return 1
			;;
		*)
			_cac_target="$1"
			shift
			;;
		esac
	done

	if [ -z "$_cac_target" ]; then
		_cac_target=$(_claude_allow_clean_find_file) || {
			ux_error "No .claude/settings.local.json found"
			ux_info "Run from a git repo or ensure ~/.claude/settings.local.json exists"
			return 1
		}
	fi

	[ -f "$_cac_target" ] || {
		ux_error "File not found: $_cac_target"
		return 1
	}
	command -v jq >/dev/null 2>&1 || {
		ux_error "jq is required"
		return 1
	}

	_cac_filter=$(mktemp "${TMPDIR:-/tmp}/cac_filter.XXXXXX")
	_cac_out=$(mktemp "${TMPDIR:-/tmp}/cac_out.XXXXXX")
	_claude_allow_clean_write_filter "$_cac_filter"

	if ! jq -f "$_cac_filter" "$_cac_target" >"$_cac_out" 2>/dev/null; then
		ux_error "Failed to parse: $_cac_target"
		rm -f "$_cac_filter" "$_cac_out"
		return 1
	fi
	rm -f "$_cac_filter"

	_cac_before=$(jq '.permissions.allow | length' "$_cac_target")
	_cac_after=$(jq '.permissions.allow | length' "$_cac_out")
	_cac_removed=$((_cac_before - _cac_after))

	if [ "$_cac_removed" -eq 0 ]; then
		ux_success "Already clean: $_cac_before entries, nothing to remove"
		rm -f "$_cac_out"
		return 0
	fi

	if [ "$_cac_dry_run" -eq 1 ]; then
		ux_header "Dry-run: $(basename "$(dirname "$_cac_target")")/$(basename "$_cac_target")"
		ux_info "Before: $_cac_before  After: $_cac_after  Remove: $_cac_removed"
		_cac_tmp_b=$(mktemp "${TMPDIR:-/tmp}/cac_b.XXXXXX")
		_cac_tmp_a=$(mktemp "${TMPDIR:-/tmp}/cac_a.XXXXXX")
		jq -r '.permissions.allow[]' "$_cac_target" | sort >"$_cac_tmp_b"
		jq -r '.permissions.allow[]' "$_cac_out" | sort >"$_cac_tmp_a"
		ux_section "Entries to remove:"
		comm -23 "$_cac_tmp_b" "$_cac_tmp_a"
		rm -f "$_cac_tmp_b" "$_cac_tmp_a" "$_cac_out"
		return 0
	fi

	mv "$_cac_out" "$_cac_target"
	ux_success "Cleaned $_cac_removed entries  ($_cac_before → $_cac_after)"
	ux_info "$_cac_target"
}

alias claude-allow-clean='claude_allow_clean'
