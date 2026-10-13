#!/usr/bin/env bash
# claude/plugin/update-plugins.sh
#
# Refresh Claude Code's PLUGIN STORE from upstream: re-fetch each selected
# marketplace clone, then bump every manifest plugin of that marketplace to
# its latest version.
#
# Why this exists: skills-sync (scripts/update-skills.sh) pulls the skills
# WORKSPACE clones (~/para/project/skills/<repo>), but Claude Code does not
# load skills from there — it loads them from its plugin store
# (plugins/marketplaces/<mkt> + versioned plugins/cache/<mkt>/<plugin>/<ver>).
# The dEitY719 marketplaces carry no autoUpdate, so without this step the
# installed version silently lags the source (gh-flow sat on 0.1.13 while the
# source was 0.2.0).
#
# Selection mirrors git-clone-skills.sh: marketplaces from
# claude/plugin/marketplaces.json ({name: "owner/repo"}) filtered by owner
# (default dEitY719, --owner <o>, --all for none); plugins from
# claude/plugin/plugins.json (.plugins[] "plugin@marketplace") whose
# marketplace was selected. On an internal PC with claude/plugin/company/.git
# the private company manifest is included too (same gate as restore.sh) —
# unfiltered by owner, since its sources are GHES URLs rather than owner/repo.
#
# Only updates what is already registered/installed; adding missing entries is
# restore.sh's job.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load UX library for semantic log colors (#1114). Colors only on a TTY; piped
# / automation / bats runs get the plain fallbacks below.
UX_LIB="$SCRIPT_DIR/../../shell-common/tools/ux_lib/ux_lib.sh"
if [ -t 1 ] && [ -r "$UX_LIB" ]; then
	# shellcheck source=../../shell-common/tools/ux_lib/ux_lib.sh
	source "$UX_LIB"
else
	ux_header() { printf '\n=== %s ===\n' "$1"; }
	ux_section() { printf '\n--- %s ---\n' "$1"; }
	ux_success() { printf 'OK: %s\n' "$1"; }
	ux_error() { printf 'ERR: %s\n' "$1" >&2; }
	ux_warning() { printf 'WARN: %s\n' "$1"; }
	ux_info() { printf 'INFO: %s\n' "$1"; }
	ux_bullet() { printf '  * %s\n' "$1"; }
fi

# Setup-mode reader SSOT (#1810) — same lookup chain as restore.sh.
for _rsm_dir in "${SHELL_COMMON:-}" "${DOTFILES_ROOT:-}/shell-common" "$HOME/dotfiles/shell-common"; do
	if [ -r "${_rsm_dir}/util/setup_mode_read.sh" ]; then
		# shellcheck disable=SC1091
		. "${_rsm_dir}/util/setup_mode_read.sh"
		break
	fi
done

OWNER_FILTER="dEitY719"
ALL_OWNERS=false
DRY_RUN=false
USER_ACCOUNT=""

_usage() {
	cat <<'USAGE'
Usage: update-plugins.sh [options]

Refresh Claude Code marketplaces from upstream and update their installed
plugins to the latest version (claude plugin marketplace update / plugin update).

Options:
  --dry-run          Print the plan without calling claude (claude CLI not required)
  --all              Every marketplace in the manifest (no owner filter)
  --owner <owner>    Owner to filter marketplaces by (default: dEitY719)
  --user <account>   Target ~/.claude-<account> (public/external mode)
  -h, --help, help   Show this help message

public/external: ~/.claude-<account>/plugins all link to ~/.claude-shared/plugins,
so one run updates every account. internal: single-account ~/.claude/plugins
(no ~/.claude-shared) is updated directly.
Restart running Claude Code sessions to load updated plugins.
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--all)
		ALL_OWNERS=true
		shift
		;;
	--owner)
		if [ -z "${2:-}" ]; then
			ux_error "--owner requires an owner argument."
			exit 2
		fi
		OWNER_FILTER="$2"
		shift 2
		;;
	--owner=*)
		OWNER_FILTER="${1#*=}"
		shift
		;;
	--user)
		if [ -z "${2:-}" ]; then
			ux_error "--user requires an account argument."
			exit 2
		fi
		USER_ACCOUNT="$2"
		shift 2
		;;
	--user=*)
		USER_ACCOUNT="${1#*=}"
		shift
		;;
	-h | --help | help)
		_usage
		exit 0
		;;
	*)
		ux_error "Unknown argument: $1"
		_usage >&2
		exit 2
		;;
	esac
done

if ! command -v jq >/dev/null 2>&1; then
	ux_error "jq is required to read the plugin manifest but was not found in PATH."
	exit 1
fi

# --dry-run needs no claude binary. A real run on a machine without claude is
# not an error: skills-sync must not fail on PCs that never installed it.
if ! $DRY_RUN && ! command -v claude >/dev/null 2>&1; then
	ux_warning "claude CLI not found — skipping plugin update (install with clinstall)."
	exit 0
fi

MP_MANIFEST="$SCRIPT_DIR/marketplaces.json"
PL_MANIFEST="$SCRIPT_DIR/plugins.json"
PRIV="$SCRIPT_DIR/company"
MODE=$(_dotfiles_setup_mode 2>/dev/null || echo "")
COMPANY_ACTIVE=false
# `-e` not `-d`: worktree-safe, and avoids git walking up into dotfiles (see restore.sh).
if [ "$MODE" = "internal" ] && [ -e "$PRIV/.git" ]; then
	COMPANY_ACTIVE=true
fi

# _valid_acct / _target_config_dir — account routing copied from restore.sh
# (#1103): internal → ~/.claude, otherwise ~/.claude-<account>.
_valid_acct() {
	case "$1" in
	[a-z]*) ;;
	*) return 1 ;;
	esac
	case "$1" in
	*[!a-z0-9_-]*) return 1 ;;
	esac
	return 0
}

# Unlike restore.sh there is no --all-accounts. public/external: the plugin
# store (~/.claude-shared/plugins) is symlinked into every ~/.claude-<account>,
# so updating through the FIRST resolved config dir updates all accounts at
# once. internal: single-account ~/.claude owns a real plugins/ dir and
# ~/.claude-shared does not exist — nothing here depends on it; the claude CLI
# writes into $CLAUDE_CONFIG_DIR/plugins either way.
_target_config_dir() {
	if [ "$MODE" = "internal" ]; then
		echo "$HOME/.claude"
		return 0
	fi
	local acct="${USER_ACCOUNT:-${CLAUDE_DEFAULT_ACCOUNT:-personal}}"
	if _valid_acct "$acct"; then
		echo "$HOME/.claude-$acct"
		return 0
	fi
	ux_warning "Invalid account name '$acct' — falling back to ~/.claude" >&2
	echo "$HOME/.claude"
}

# _select_marketplaces <manifest> <filter:true|false> — marketplace names, one per line.
_select_marketplaces() {
	[ -r "$1" ] || return 0
	if [ "$2" = true ] && ! $ALL_OWNERS; then
		jq -r --arg owner "$OWNER_FILTER" \
			'to_entries[] | select(.value | type == "string")
			 | select(.value | startswith($owner + "/")) | .key' "$1"
	else
		jq -r 'to_entries[] | select(.value | type == "string") | .key' "$1"
	fi
}

# _plugins_of <manifest> <marketplace> — "plugin@marketplace" ids of that marketplace.
_plugins_of() {
	[ -r "$1" ] || return 0
	jq -r --arg mp "$2" '(.plugins // [])[] | select(type == "string")
		| select(split("@") | last == $mp)' "$1"
}

export CLAUDE_CONFIG_DIR
CLAUDE_CONFIG_DIR="$(_target_config_dir)"

ux_header "Claude Plugin Update"
if [ "$MODE" = "internal" ]; then
	ux_info "Config dir: $CLAUDE_CONFIG_DIR (internal, single-account plugin store)"
else
	ux_info "Config dir: $CLAUDE_CONFIG_DIR (plugin store shared across accounts)"
fi
if $ALL_OWNERS; then
	ux_info "Owner filter: (none, --all)"
else
	ux_info "Owner filter: $OWNER_FILTER"
fi
$COMPANY_ACTIVE && ux_info "Company manifest: included ($PRIV)"
$DRY_RUN && ux_info "Mode: DRY-RUN (no claude calls)"

MP_TOTAL=0
MP_REFRESHED=0
PL_TOTAL=0
PL_UPDATED=0
PL_UPTODATE=0
FAILED=0

# _update_plugin <id> — `claude plugin update --json` and classify the outcome.
# `</dev/null`: claude must not drain the caller's here-doc/loop stdin.
_update_plugin() {
	local id="$1" out rc outcome old new
	PL_TOTAL=$((PL_TOTAL + 1))
	if $DRY_RUN; then
		ux_info "  $id: would run 'claude plugin update $id' (dry-run)"
		return 0
	fi
	out="$(claude plugin update "$id" --json </dev/null 2>&1)"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		ux_warning "  $id: update failed (exit $rc) — continuing"
		[ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/      /'
		FAILED=$((FAILED + 1))
		return 0
	fi
	outcome="$(printf '%s\n' "$out" | tail -n 1 | jq -r '.updateOutcome // empty' 2>/dev/null)"
	old="$(printf '%s\n' "$out" | tail -n 1 | jq -r '.oldVersion // empty' 2>/dev/null)"
	new="$(printf '%s\n' "$out" | tail -n 1 | jq -r '.newVersion // empty' 2>/dev/null)"
	if [ "$outcome" = "up_to_date" ] || { [ -z "$outcome" ] && printf '%s' "$out" | grep -q 'already at the latest'; }; then
		ux_info "  $id: up to date${new:+ ($new)}"
		PL_UPTODATE=$((PL_UPTODATE + 1))
	else
		ux_success "  $id: updated${old:+ $old -> $new}"
		PL_UPDATED=$((PL_UPDATED + 1))
	fi
}

# _update_scope <label> <mp manifest> <pl manifest> <filter:true|false>
_update_scope() {
	local label="$1" mp_manifest="$2" pl_manifest="$3" filter="$4" names name id
	if [ ! -r "$mp_manifest" ]; then
		ux_info "($label manifest not found — skipped)"
		return 0
	fi
	if ! names="$(_select_marketplaces "$mp_manifest" "$filter" 2>/dev/null)"; then
		ux_error "Failed to read marketplace list: $mp_manifest"
		FAILED=$((FAILED + 1))
		return 0
	fi
	ux_section "$label marketplaces"
	while IFS= read -r name; do
		[ -n "$name" ] || continue
		MP_TOTAL=$((MP_TOTAL + 1))
		if $DRY_RUN; then
			ux_info "$name: would run 'claude plugin marketplace update $name' (dry-run)"
		elif claude plugin marketplace update "$name" </dev/null >/dev/null 2>&1; then
			ux_success "$name: marketplace refreshed"
			MP_REFRESHED=$((MP_REFRESHED + 1))
		else
			# Plugins are still attempted: an update against the cached
			# marketplace is harmless and may report its own failure.
			ux_warning "$name: marketplace update failed — continuing"
			FAILED=$((FAILED + 1))
		fi
		while IFS= read -r id; do
			[ -n "$id" ] || continue
			_update_plugin "$id"
		done <<EOF
$(_plugins_of "$pl_manifest" "$name" 2>/dev/null)
EOF
	done <<EOF
$names
EOF
}

_update_scope "Public" "$MP_MANIFEST" "$PL_MANIFEST" true
if $COMPANY_ACTIVE; then
	_update_scope "Company" "$PRIV/marketplaces.json" "$PRIV/plugins.json" false
fi

ux_section "Summary"
if $DRY_RUN; then
	ux_bullet "Marketplaces (would refresh): $MP_TOTAL"
	ux_bullet "Plugins (would update): $PL_TOTAL"
else
	ux_bullet "Marketplaces refreshed: $MP_REFRESHED/$MP_TOTAL"
	ux_bullet "Plugins updated: $PL_UPDATED"
	ux_bullet "Plugins up to date: $PL_UPTODATE"
	ux_bullet "Failed: $FAILED"
fi

if [ "$PL_UPDATED" -gt 0 ]; then
	ux_info "Restart running Claude Code sessions to load the updated plugins."
fi

if [ "$FAILED" -gt 0 ]; then
	exit 1
fi
exit 0
