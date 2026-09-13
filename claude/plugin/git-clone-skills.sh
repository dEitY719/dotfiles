#!/usr/bin/env bash
# claude/plugin/git-clone-skills.sh
#
# First-time clone of every skill repository listed in the plugin manifest
# (claude/plugin/marketplaces.json) into the skills workspace.
#
# Companion to git-pull-skills.sh: that one refreshes repositories already
# on disk, this one brings the missing ones down. Idempotent by design — a
# destination directory that already exists is reported and left untouched,
# never deleted or overwritten (refreshing it is git-pull-skills' job).
#
# The repository list is read from the manifest at run time; nothing is
# hard-coded here, so adding a marketplace to marketplaces.json is the only
# step needed to have it cloned.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load UX library for semantic log colors (#1114)
UX_LIB="$SCRIPT_DIR/../../shell-common/tools/ux_lib/ux_lib.sh"
if [ -t 1 ] && [ -r "$UX_LIB" ]; then
	# shellcheck source=../../shell-common/tools/ux_lib/ux_lib.sh
	source "$UX_LIB"
else
	UX_PRIMARY="" UX_SUCCESS="" UX_ERROR="" UX_WARNING="" UX_INFO="" UX_MUTED="" UX_RESET="" UX_BOLD=""
	ux_header() { printf '\n=== %s ===\n' "$1"; }
	ux_section() { printf '\n--- %s ---\n' "$1"; }
	ux_success() { printf 'OK: %s\n' "$1"; }
	ux_error() { printf 'ERR: %s\n' "$1" >&2; }
	ux_warning() { printf 'WARN: %s\n' "$1"; }
	ux_info() { printf 'INFO: %s\n' "$1"; }
	ux_bullet() { printf '  * %s\n' "$1"; }
fi

# Host pinning SSOT (#703 / #1403 / #1407). Prefer $SHELL_COMMON, fall back to
# this script's own tree rather than $HOME so a foreign checkout stays
# self-consistent; github.com is the last-resort default, matching
# _gh_resolve_host's own fail-safe branch.
GH_HOST_LIB="${SHELL_COMMON:-$SCRIPT_DIR/../../shell-common}/functions/gh_host.sh"
if [ -r "$GH_HOST_LIB" ]; then
	# shellcheck source=../../shell-common/functions/gh_host.sh
	. "$GH_HOST_LIB"
fi
if command -v _gh_resolve_host >/dev/null 2>&1; then
	GH_TARGET_HOST="$(_gh_resolve_host)"
else
	GH_TARGET_HOST=""
fi
[ -n "$GH_TARGET_HOST" ] || GH_TARGET_HOST="github.com"

TARGET_DIR="${SKILLS_DIR:-$HOME/para/project/skills}"
MANIFEST="$SCRIPT_DIR/marketplaces.json"
OWNER_FILTER="dEitY719"
ALL_OWNERS=false
DRY_RUN=false
NO_UPSTREAM=false

_usage() {
	cat <<USAGE
Usage: git-clone-skills.sh [options]

Clone every skill repository listed in the plugin manifest into the skills
workspace. Repositories already present on disk are skipped, never touched.

Options:
  --dry-run             List what would be cloned without writing anything to disk
  --all                 Clone every repository in the manifest (no owner filter)
  --owner <owner>       Owner to filter the manifest by (default: dEitY719)
  --manifest <path>     Manifest to read the repository list from
                        (default: claude/plugin/marketplaces.json)
  --no-upstream         Do not query gh for fork parents / add upstream remotes
  --target <dir>        Directory to clone into, created when missing
                        (default: \$SKILLS_DIR, else ~/para/project/skills)
  -h, --help, help      Show this help message
USAGE
}

# Parse options
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
	--no-upstream)
		NO_UPSTREAM=true
		shift
		;;
	--owner)
		if [ -z "${2:-}" ]; then
			echo "${UX_ERROR}Error: --owner requires an owner argument.${UX_RESET}" >&2
			exit 2
		fi
		OWNER_FILTER="$2"
		shift 2
		;;
	--owner=*)
		OWNER_FILTER="${1#*=}"
		shift
		;;
	--manifest)
		if [ -z "${2:-}" ]; then
			echo "${UX_ERROR}Error: --manifest requires a path argument.${UX_RESET}" >&2
			exit 2
		fi
		MANIFEST="$2"
		shift 2
		;;
	--manifest=*)
		MANIFEST="${1#*=}"
		shift
		;;
	--target)
		if [ -z "${2:-}" ]; then
			echo "${UX_ERROR}Error: --target requires a directory argument.${UX_RESET}" >&2
			exit 2
		fi
		TARGET_DIR="$2"
		shift 2
		;;
	--target=*)
		TARGET_DIR="${1#*=}"
		shift
		;;
	-h | --help | help)
		_usage
		exit 0
		;;
	*)
		echo "${UX_ERROR}Unknown argument: $1${UX_RESET}" >&2
		_usage >&2
		exit 2
		;;
	esac
done

if ! command -v jq >/dev/null 2>&1; then
	ux_error "jq is required to read the plugin manifest but was not found in PATH."
	ux_info "Install jq (e.g. 'sudo apt install jq') and re-run."
	exit 1
fi

if [ ! -r "$MANIFEST" ]; then
	ux_error "Manifest not found or unreadable: $MANIFEST"
	exit 1
fi

# _read_repo_slugs — emit the manifest's "<owner>/<repo>" values, one per line.
#
# Non-string values are ignored so a future manifest that grows nested objects
# cannot turn into bogus clone targets. sort -u collapses two marketplaces that
# happen to name the same repository.
_read_repo_slugs() {
	if $ALL_OWNERS; then
		jq -r '.[] | select(type == "string")' "$MANIFEST"
	else
		jq -r --arg owner "$OWNER_FILTER" \
			'.[] | select(type == "string") | select(startswith($owner + "/"))' \
			"$MANIFEST"
	fi
}

if ! REPO_SLUGS="$(_read_repo_slugs 2>/dev/null | LC_ALL=C sort -u)"; then
	ux_error "Failed to read repository list from manifest: $MANIFEST"
	exit 1
fi

ux_header "Git Clone Skills: $TARGET_DIR"
ux_info "Manifest: $MANIFEST"
ux_info "Host: $GH_TARGET_HOST"
if $ALL_OWNERS; then
	ux_info "Owner filter: (none, --all)"
else
	ux_info "Owner filter: $OWNER_FILTER"
fi
if $DRY_RUN; then
	ux_info "Mode: DRY-RUN (no disk modifications)"
fi

TOTAL=0
CLONED=0
ALREADY=0
UPSTREAM_ADDED=0
FAILED=0

# _register_upstream OWNER REPO DIR
#
# Detect whether <OWNER>/<REPO> is a fork and, if so, add its parent as the
# `upstream` remote of the freshly cloned DIR. Best-effort by contract: a
# missing / unauthenticated / failing `gh`, or JSON this script cannot parse,
# warns and returns 0 — an undetectable fork must never turn a good clone
# into a failure.
#
# Every gh call carries BOTH halves of the #1403/#1407 host-pinning contract:
# the GH_HOST= prefix pins the server, and an explicit <owner>/<repo> pins the
# repository. Neither substitutes for the other — a bare `gh repo view --json
# parent` would answer for whatever repo the *current directory* resolves to.
#
# `gh repo view` takes that repository POSITIONALLY and has no --repo flag
# (--repo belongs to gh pr / gh issue / gh api). Spelling it `--repo <slug>`
# here made every call exit 1 with `unknown flag: --repo`, which this
# function's own warning path then swallowed.
_register_upstream() {
	local owner="$1" repo="$2" dir="$3"
	local gh_json parent_slug

	if git -C "$dir" config --get remote.upstream.url >/dev/null 2>&1; then
		ux_info "$repo: upstream remote already configured (left as is)"
		return 0
	fi

	if ! command -v gh >/dev/null 2>&1; then
		ux_warning "$repo: gh not found (upstream detection skipped)"
		return 0
	fi

	if ! gh_json="$(GH_HOST="$GH_TARGET_HOST" gh repo view "$owner/$repo" --json parent 2>/dev/null)" ||
		[ -z "$gh_json" ]; then
		ux_warning "$repo: gh repo view failed (upstream detection skipped)"
		return 0
	fi

	if ! parent_slug="$(printf '%s' "$gh_json" |
		jq -r '.parent | if type == "object" then "\(.owner.login)/\(.name)" else "" end' 2>/dev/null)"; then
		ux_warning "$repo: could not parse gh JSON (upstream detection skipped)"
		return 0
	fi

	case "$parent_slug" in
	"" | null | */ | */*/*)
		ux_info "$repo: not a fork (no upstream remote added)"
		return 0
		;;
	esac

	if git -C "$dir" remote add upstream "https://$GH_TARGET_HOST/$parent_slug.git" >/dev/null 2>&1; then
		ux_success "$repo: upstream remote added ($parent_slug)"
		UPSTREAM_ADDED=$((UPSTREAM_ADDED + 1))
	else
		ux_warning "$repo: failed to add upstream remote ($parent_slug)"
	fi
	return 0
}

# The target directory is created on demand — unlike git-pull-skills.sh, a
# missing workspace is the normal first-run state, not an error. Skipped in
# dry-run so the mode stays side-effect free.
if ! $DRY_RUN && [ ! -d "$TARGET_DIR" ]; then
	if ! mkdir -p "$TARGET_DIR" 2>/dev/null; then
		ux_error "Could not create target directory: $TARGET_DIR"
		exit 1
	fi
	ux_info "Created target directory: $TARGET_DIR"
fi

while IFS= read -r slug; do
	[ -n "$slug" ] || continue

	case "$slug" in
	*/*/* | /* | */)
		ux_warning "Malformed manifest entry (expected <owner>/<repo>): $slug"
		FAILED=$((FAILED + 1))
		continue
		;;
	*/*) ;;
	*)
		ux_warning "Malformed manifest entry (expected <owner>/<repo>): $slug"
		FAILED=$((FAILED + 1))
		continue
		;;
	esac

	repo_owner="${slug%%/*}"
	repo_name="${slug#*/}"
	TOTAL=$((TOTAL + 1))

	dest_dir="$TARGET_DIR/$repo_name"
	clone_url="https://$GH_TARGET_HOST/$repo_owner/$repo_name.git"

	# Idempotency: an existing destination is reported and never modified.
	if [ -e "$dest_dir" ]; then
		ux_info "$repo_name: already present (skipped)"
		ALREADY=$((ALREADY + 1))
		continue
	fi

	if $DRY_RUN; then
		ux_info "$repo_name: would clone $clone_url -> $dest_dir (dry-run)"
		CLONED=$((CLONED + 1))
		continue
	fi

	if ! git clone "$clone_url" "$dest_dir" >/dev/null 2>&1; then
		ux_error "$repo_name: git clone failed ($clone_url)"
		FAILED=$((FAILED + 1))
		continue
	fi

	ux_success "$repo_name: cloned from $clone_url"
	CLONED=$((CLONED + 1))

	$NO_UPSTREAM || _register_upstream "$repo_owner" "$repo_name" "$dest_dir"
done <<EOF
$REPO_SLUGS
EOF

ux_section "Summary"
ux_bullet "Total: $TOTAL"
if $DRY_RUN; then
	ux_bullet "Would clone: $CLONED"
else
	ux_bullet "Cloned: $CLONED"
fi
ux_bullet "Already present: $ALREADY"
ux_bullet "Upstream added: $UPSTREAM_ADDED"
ux_bullet "Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
	exit 1
fi

exit 0
