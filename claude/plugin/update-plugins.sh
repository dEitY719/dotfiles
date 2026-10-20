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
# (default dEitY719, --owner <o>, --all for none; case-insensitive); plugins
# from claude/plugin/plugins.json (.plugins[] "plugin@marketplace") whose
# marketplace was selected. Each manifest is unioned with its gitignored
# machine-local overlay (*.local.json, #1685) — the same set restore.sh
# installs from. On an internal PC with claude/plugin/company/.git the private
# company manifest is included too (same gate as restore.sh) — unfiltered by
# owner, since its sources are GHES URLs rather than owner/repo.
#
# Only updates what is already registered/installed: when the plugin store's
# known_marketplaces.json / installed_plugins.json exist, entries missing from
# them (not yet restored, or uninstalled on purpose) are skipped rather than
# failed. Adding missing entries is restore.sh's job.
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

# Setup-mode reader SSOT (#1810) — restore.sh's lookup chain plus this
# checkout's own shell-common, so a dotfiles clone outside ~/dotfiles run with
# no SHELL_COMMON (skills-sync does not export DOTFILES_ROOT) still sees the
# internal mode instead of silently targeting ~/.claude-personal.
for _rsm_dir in "${SHELL_COMMON:-}" "${DOTFILES_ROOT:-}/shell-common" "$HOME/dotfiles/shell-common" "$SCRIPT_DIR/../../shell-common"; do
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
JOBS="${DOTFILES_SKILLS_JOBS:-4}"

_usage() {
	cat <<'USAGE'
Usage: update-plugins.sh [options]

Refresh Claude Code marketplaces from upstream and update their installed
plugins to the latest version (claude plugin marketplace update / plugin update).

Options:
  --dry-run          Print the plan without calling claude (claude CLI not required)
  --all              Every marketplace in the manifest (no owner filter)
  --owner <owner>    Owner to filter marketplaces by (default: dEitY719, case-insensitive)
  --user <account>   Target ~/.claude-<account> (public/external mode)
  --jobs <N>         Marketplaces processed in parallel (default: $DOTFILES_SKILLS_JOBS or 4; 1 = sequential)
  -h, --help, help   Show this help message

The store is ~/.claude-shared/plugins in every mode. public/external: each
~/.claude-<account>/plugins links to it, so one run updates every account.
internal: the single-account ~/.claude/plugins links to it.
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
	--jobs)
		JOBS="${2:-}"
		shift $(($# > 1 ? 2 : 1))
		;;
	--jobs=*)
		JOBS="${1#*=}"
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

case "$JOBS" in
'' | *[!0-9]* | 0*)
	ux_error "--jobs (or DOTFILES_SKILLS_JOBS) must be a positive integer, got '$JOBS'."
	exit 2
	;;
esac

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

PRIV="$SCRIPT_DIR/company"
MODE=$(_dotfiles_setup_mode 2>/dev/null || echo "")
COMPANY_ACTIVE=false
# Rule SSOT: _dotfiles_company_active (#2251); missing shell-common => inactive.
if command -v _dotfiles_company_active >/dev/null 2>&1 && _dotfiles_company_active "$SCRIPT_DIR"; then
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

# Unlike restore.sh there is no --all-accounts. The plugin store
# (~/.claude-shared/plugins) is symlinked into every ~/.claude-<account>
# (public/external) or into the single ~/.claude (internal, claude/setup.sh),
# so updating through the FIRST resolved config dir updates all accounts at
# once. Nothing here depends on the shared path itself — the claude CLI writes
# into $CLAUDE_CONFIG_DIR/plugins either way (a PC whose setup has not re-run
# yet may still have a real ~/.claude/plugins dir).
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

# _union_marketplaces <tracked> <overlay> — {name: repo} union of the tracked
# manifest and its machine-local overlay (#1685), tracked winning on a key
# conflict like restore.sh. Prints nothing when neither exists; a malformed
# file makes jq (and so this function) fail.
_union_marketplaces() {
	local f files=()
	for f in "$2" "$1"; do
		[ -r "$f" ] && files+=("$f")
	done
	[ ${#files[@]} -gt 0 ] || return 0
	jq -s 'reduce .[] as $m ({}; . * $m)' "${files[@]}"
}

# _union_plugins <tracked> <overlay> — {plugins: [...]} set union of both.
_union_plugins() {
	local f files=()
	for f in "$1" "$2"; do
		[ -r "$f" ] && files+=("$f")
	done
	[ ${#files[@]} -gt 0 ] || {
		echo '{"plugins":[]}'
		return 0
	}
	jq -s '{plugins: (map(.plugins // []) | add | unique)}' "${files[@]}"
}

# _select_marketplaces <mp json> <filter:true|false> — marketplace names, one per line.
# Owners are compared case-insensitively, as GitHub does. Only string sources
# ("owner/repo" or a git URL) are supported; any other shape is warned about on
# stderr instead of being dropped silently.
_select_marketplaces() {
	local bad
	bad="$(printf '%s' "$1" | jq -r 'to_entries[] | select(.value | type != "string") | .key')" || return 1
	[ -z "$bad" ] || ux_warning "Unsupported (non-string) marketplace source — skipped: $(printf '%s' "$bad" | paste -sd, -)" >&2
	if [ "$2" = true ] && ! $ALL_OWNERS; then
		printf '%s' "$1" | jq -r --arg owner "$OWNER_FILTER" \
			'to_entries[] | select(.value | type == "string")
			 | select(.value | ascii_downcase | startswith(($owner | ascii_downcase) + "/")) | .key'
	else
		printf '%s' "$1" | jq -r 'to_entries[] | select(.value | type == "string") | .key'
	fi
}

# _plugins_of <pl json> <marketplace> — "plugin@marketplace" ids of that marketplace.
_plugins_of() {
	printf '%s' "$1" | jq -r --arg mp "$2" '(.plugins // [])[] | select(type == "string")
		| select(split("@") | last == $mp)'
}

export CLAUDE_CONFIG_DIR
CLAUDE_CONFIG_DIR="$(_target_config_dir)"

# What the plugin store already has. Only read when the file exists — a missing
# store file (fresh config dir, tests) disables that filter rather than
# skipping everything. A name absent from a present file is "not restored yet"
# or "uninstalled on purpose" (restore.sh tombstone): updating it can only
# fail, which would turn every skills-sync red.
STORE_DIR="$CLAUDE_CONFIG_DIR/plugins"
# A missing store means setup has not linked this account to the shared store
# yet. Running claude now would create a real $STORE_DIR that claude/setup.sh's
# link convergence then has to back up — so stop and point at setup instead.
if ! $DRY_RUN && [ ! -e "$STORE_DIR" ]; then
	ux_warning "Plugin store not found: $STORE_DIR — run ./claude/setup.sh (and claude/plugin/restore.sh) first. Skipping."
	exit 0
fi
KNOWN_MPS=""
KNOWN_MPS_SET=false
INSTALLED_PLS=""
INSTALLED_PLS_SET=false
if [ -r "$STORE_DIR/known_marketplaces.json" ] &&
	KNOWN_MPS="$(jq -r 'keys[]' "$STORE_DIR/known_marketplaces.json" 2>/dev/null)"; then
	KNOWN_MPS_SET=true
fi
if [ -r "$STORE_DIR/installed_plugins.json" ] &&
	INSTALLED_PLS="$(jq -r '(.plugins // {}) | keys[]' "$STORE_DIR/installed_plugins.json" 2>/dev/null)"; then
	INSTALLED_PLS_SET=true
fi

# A store file that exists but lists nothing (`{}`) would silently skip every
# entry below and still exit 0 — indistinguishable from a healthy run.
if { $KNOWN_MPS_SET && [ -z "$KNOWN_MPS" ]; } || { $INSTALLED_PLS_SET && [ -z "$INSTALLED_PLS" ]; }; then
	ux_warning "Plugin store at $STORE_DIR lists no marketplaces/plugins — nothing will be updated (run claude/plugin/restore.sh)."
fi

# _in_list <needle> <newline list>
_in_list() {
	printf '%s\n' "$2" | grep -Fxq -- "$1"
}

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
PL_UNKNOWN=0
PL_SKIPPED=0
FAILED=0

# _update_plugin <id> — `claude plugin update --json` and classify the outcome.
# `</dev/null`: claude must not drain the caller's here-doc/loop stdin.
_update_plugin() {
	local id="$1" out rc json outcome="" old="" new="" line
	if $INSTALLED_PLS_SET && ! _in_list "$id" "$INSTALLED_PLS"; then
		ux_info "  $id: not installed — skipped (restore.sh installs it)"
		_count PL_SKIPPED
		return 0
	fi
	_count PL_TOTAL
	if $DRY_RUN; then
		ux_info "  $id: would run 'claude plugin update $id' (dry-run)"
		return 0
	fi
	# Plugin installs from parallel marketplace jobs all rewrite the shared
	# installed_plugins.json, so they take one lock (#2198 fallback); the slow
	# marketplace refreshes stay parallel. The lock lives outside $POOL_DIR so
	# two concurrent runs (--user a / --user b share one store) exclude each
	# other too. shortcut: no lock where flock is missing (stock macOS) — add a
	# mkdir lock if a store race shows up there.
	if command -v flock >/dev/null 2>&1; then
		out="$(flock "${TMPDIR:-/tmp}/dotfiles-update-plugins.$(id -u).lock" \
			claude plugin update "$id" --json </dev/null 2>&1)"
	else
		out="$(claude plugin update "$id" --json </dev/null 2>&1)"
	fi
	rc=$?
	if [ "$rc" -ne 0 ]; then
		ux_warning "  $id: update failed (exit $rc) — continuing"
		while IFS= read -r line; do
			[ -n "$line" ] && ux_bullet "$line"
		done <<EOF
$out
EOF
		_count FAILED
		return 0
	fi
	# stdout and stderr share $out (the error path above shows both), so the
	# JSON result is the last line that starts with `{` — not blindly the last
	# line, which a trailing stderr notice would turn into a parse failure.
	json="$(printf '%s\n' "$out" | grep '^[[:space:]]*{' | tail -n 1)"
	if [ -n "$json" ]; then
		IFS='|' read -r outcome old new <<EOF
$(printf '%s\n' "$json" | jq -r '[.updateOutcome // "", .oldVersion // "", .newVersion // ""] | join("|")' 2>/dev/null)
EOF
	fi
	# Only the two outcomes the CLI documents are counted; anything else (no
	# JSON, a new outcome value) is reported as unknown rather than as "updated",
	# which would print a false restart hint.
	if [ "$outcome" = "up_to_date" ] || { [ -z "$outcome" ] && printf '%s' "$out" | grep -q 'already at the latest'; }; then
		ux_info "  $id: up to date${new:+ ($new)}"
		_count PL_UPTODATE
	elif [ "$outcome" = "updated" ]; then
		ux_success "  $id: updated${old:+ $old -> $new}"
		_count PL_UPDATED
	else
		ux_warning "  $id: unrecognized update result (${outcome:-no JSON}) — check 'claude plugin update $id' by hand"
		_count PL_UNKNOWN
	fi
}

# _update_scope <label> <scope dir> <filter:true|false> — reads
# <dir>/{marketplaces,plugins}.json plus their *.local.json overlays.
_update_scope() {
	local label="$1" dir="$2" filter="$3" mp_json pl_json names name
	if ! mp_json="$(_union_marketplaces "$dir/marketplaces.json" "$dir/marketplaces.local.json" 2>/dev/null)"; then
		ux_error "Failed to read marketplace manifest: $dir/marketplaces{,.local}.json"
		FAILED=$((FAILED + 1))
		return 0
	fi
	if [ -z "$mp_json" ]; then
		ux_info "($label manifest not found — skipped)"
		return 0
	fi
	if ! pl_json="$(_union_plugins "$dir/plugins.json" "$dir/plugins.local.json" 2>/dev/null)"; then
		ux_error "Failed to read plugin manifest: $dir/plugins{,.local}.json"
		FAILED=$((FAILED + 1))
		return 0
	fi
	if ! names="$(_select_marketplaces "$mp_json" "$filter")"; then
		ux_error "Failed to read marketplace list: $dir/marketplaces.json"
		FAILED=$((FAILED + 1))
		return 0
	fi
	ux_section "$label marketplaces"
	local mps=()
	while IFS= read -r name; do
		[ -n "$name" ] && mps+=("$name")
	done <<EOF
$names
EOF
	SCOPE_PL_JSON="$pl_json"
	_run_pool _update_marketplace ${mps[@]+"${mps[@]}"}
}

# _update_marketplace <name> — refresh one marketplace, then update its
# plugins in manifest order. Marketplaces are independent, so _run_pool runs
# several of these at once (#2198); plugins of one marketplace stay serial.
_update_marketplace() {
	local name="$1" id
	if $KNOWN_MPS_SET && ! _in_list "$name" "$KNOWN_MPS"; then
		# Its plugins cannot be installed without it either — skip both.
		ux_info "$name: marketplace not registered — skipped (restore.sh adds it)"
		return 0
	fi
	_count MP_TOTAL
	if $DRY_RUN; then
		ux_info "$name: would run 'claude plugin marketplace update $name' (dry-run)"
	elif claude plugin marketplace update "$name" </dev/null >/dev/null 2>&1; then
		ux_success "$name: marketplace refreshed"
		_count MP_REFRESHED
	else
		# Plugins are still attempted: an update against the cached
		# marketplace is harmless and may report its own failure.
		ux_warning "$name: marketplace update failed — continuing"
		_count FAILED
	fi
	while IFS= read -r id; do
		[ -n "$id" ] || continue
		_update_plugin "$id"
	done <<EOF
$(_plugins_of "$SCOPE_PL_JSON" "$name")
EOF
}

POOL_COUNTERS="MP_TOTAL MP_REFRESHED PL_TOTAL PL_UPDATED PL_UPTODATE PL_UNKNOWN PL_SKIPPED FAILED"
# --- job pool (#2198) -------------------------------------------------------
# Same block in git-pull-skills.sh and update-plugins.sh: each script must stay
# runnable as a single copied file (the bats fixtures copy it alone).

# _count <VAR> — record one outcome for <VAR>. Jobs run in subshells, so a
# plain VAR=$((VAR + 1)) would be lost; _pool_flush sums these files instead.
_count() {
	printf '%s\n' "$1" >>"$RES_FILE"
}

# _pool_wait — block until a job finishes. `wait -n` needs bash 4.3+; older
# bash (stock macOS 3.2) waits for the whole running batch instead.
_pool_wait() {
	if [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }; then
		wait -n
	else
		wait
	fi
}

# _pool_flush [all] — replay finished jobs in launch order and sum their
# outcomes, stopping at the first job still running: output streams while the
# pool works yet stays in argument order, so --jobs 1 and --jobs N print the
# same. "all" (after the final wait) also replays a job that died before its
# DONE line, and counts it as failed.
_pool_flush() {
	local n k
	while [ "$POOL_NEXT" -le "$POOL_SEQ" ]; do
		n=$POOL_NEXT
		if ! grep -qx DONE "$POOL_DIR/$n.res" 2>/dev/null; then
			[ "${1:-}" = all ] || return 0
			ux_error "${POOL_NAMES[n]}: job exited without a result"
			FAILED=$((FAILED + 1))
		fi
		cat "$POOL_DIR/$n.out"
		cat "$POOL_DIR/$n.err" >&2
		if [ -f "$POOL_DIR/$n.res" ]; then
			while IFS= read -r k; do
				case " $POOL_COUNTERS " in
				*" $k "*) printf -v "$k" '%d' $((${!k} + 1)) ;;
				esac
			done <"$POOL_DIR/$n.res"
		fi
		POOL_NEXT=$((n + 1))
	done
}

# _run_pool <worker> <item>... — run `<worker> <item>` for each item, at most
# $JOBS at once, each buffered under $POOL_DIR/<seq>.{out,err,res}.
_run_pool() {
	local worker="$1" item
	shift
	for item in "$@"; do
		while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
			_pool_wait
			_pool_flush
		done
		POOL_SEQ=$((POOL_SEQ + 1))
		POOL_NAMES[POOL_SEQ]="${item##*/}"
		(
			RES_FILE="$POOL_DIR/$POOL_SEQ.res"
			"$worker" "$item"
			_count DONE
		) >"$POOL_DIR/$POOL_SEQ.out" 2>"$POOL_DIR/$POOL_SEQ.err" &
	done
	wait
	_pool_flush all
}

POOL_SEQ=0
POOL_NEXT=1
POOL_NAMES=()
POOL_DIR="$(mktemp -d)" || {
	ux_error "mktemp -d failed — cannot buffer job output."
	exit 1
}
trap 'rm -rf "$POOL_DIR"' EXIT
# --- end job pool ------------------------------------------------------------

_update_scope "Public" "$SCRIPT_DIR" true
if $COMPANY_ACTIVE; then
	_update_scope "Company" "$PRIV" false
fi

# Marketplace refreshes run unlocked in parallel and also write the shared
# store (#2198 review). Measured clean, but a lost or torn write must not pass
# silently: re-read both store files and fail the run if either is no longer
# valid JSON or lost a marketplace it listed before.
_check_store() {
	local f="$1" before="$2" query="$3" after name
	[ -r "$STORE_DIR/$f" ] || return 0
	if ! after="$(jq -r "$query" "$STORE_DIR/$f" 2>/dev/null)"; then
		ux_error "Plugin store file is not valid JSON after the update: $STORE_DIR/$f"
		FAILED=$((FAILED + 1))
		return 0
	fi
	while IFS= read -r name; do
		[ -n "$name" ] || continue
		if ! _in_list "$name" "$after"; then
			ux_error "Plugin store lost '$name' during the update: $STORE_DIR/$f"
			FAILED=$((FAILED + 1))
		fi
	done <<EOF
$before
EOF
}
if ! $DRY_RUN; then
	_check_store known_marketplaces.json "$KNOWN_MPS" 'keys[]'
	_check_store installed_plugins.json "$INSTALLED_PLS" '(.plugins // {}) | keys[]'
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
if [ "$PL_UNKNOWN" -gt 0 ]; then
	ux_bullet "Plugins with an unrecognized result: $PL_UNKNOWN"
fi
if [ "$PL_SKIPPED" -gt 0 ]; then
	ux_bullet "Plugins skipped (not installed): $PL_SKIPPED"
fi

if [ "$PL_UPDATED" -gt 0 ]; then
	ux_info "Restart running Claude Code sessions to load the updated plugins."
fi

if [ "$FAILED" -gt 0 ]; then
	exit 1
fi
exit 0
