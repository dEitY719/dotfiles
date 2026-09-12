#!/usr/bin/env bash
# claude/plugin/git-pull-skills.sh
#
# Batch fetch/pull/rebase all git repositories under ~/para/project/skills.
# Safely skips dirty trees and detached/non-main branches.
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

TARGET_DIR="${SKILLS_DIR:-$HOME/para/project/skills}"
DRY_RUN=false
ALL_BRANCHES=false

_usage() {
	cat <<USAGE
Usage: git-pull-skills.sh [options]

Options:
  --dry-run             Check repository status and incoming updates without pulling
  --all-branches        Pull non-main branches if tracking remote exists (default: skips non-main branches)
  --target <dir>        Target directory to search for git repositories (default: ~/para/project/skills)
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
	--all-branches)
		ALL_BRANCHES=true
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

if [ ! -d "$TARGET_DIR" ]; then
	ux_error "Target directory does not exist: $TARGET_DIR"
	exit 1
fi

ux_header "Git Pull Skills: $TARGET_DIR"
if $DRY_RUN; then
	ux_info "Mode: DRY-RUN (no working directory modifications)"
fi

TOTAL=0
UPDATED=0
UP_TO_DATE=0
SKIPPED_DIRTY=0
SKIPPED_BRANCH=0
SKIPPED_NOT_GIT=0
FAILED=0

# Iterate over subdirectories sorted alphabetically
while IFS= read -r repo_dir; do
	[ -n "$repo_dir" ] || continue
	repo_name="$(basename "$repo_dir")"
	TOTAL=$((TOTAL + 1))

	# 1. Check if git repo
	if ! git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		ux_warning "$repo_name: not a git repository (skipped)"
		SKIPPED_NOT_GIT=$((SKIPPED_NOT_GIT + 1))
		continue
	fi

	# 2. Check current branch
	branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || true)"
	if [ -z "$branch" ]; then
		ux_warning "$repo_name: detached HEAD (skipped)"
		SKIPPED_BRANCH=$((SKIPPED_BRANCH + 1))
		continue
	fi

	# Skip non-main/master branches by default unless --all-branches is set
	if ! $ALL_BRANCHES && [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
		ux_info "$repo_name: on non-main branch '$branch' (skipped, use --all-branches to include)"
		SKIPPED_BRANCH=$((SKIPPED_BRANCH + 1))
		continue
	fi

	# 3. Check dirty state (uncommitted changes)
	status_porcelain="$(git -C "$repo_dir" status --porcelain 2>/dev/null || true)"
	if [ -n "$status_porcelain" ]; then
		ux_warning "$repo_name: dirty working tree on '$branch' (skipped)"
		SKIPPED_DIRTY=$((SKIPPED_DIRTY + 1))
		continue
	fi

	# 4. Check remote origin
	if ! git -C "$repo_dir" config --get remote.origin.url >/dev/null 2>&1; then
		ux_warning "$repo_name: no remote 'origin' configured (skipped)"
		SKIPPED_BRANCH=$((SKIPPED_BRANCH + 1))
		continue
	fi

	# 4.1 Check dual-remote (origin + upstream)
	has_upstream=false
	if git -C "$repo_dir" config --get remote.upstream.url >/dev/null 2>&1; then
		has_upstream=true
	fi

	if $has_upstream; then
		# Fetch origin and upstream (without refspec to update tracking refs)
		if ! git -C "$repo_dir" fetch origin >/dev/null 2>&1; then
			ux_error "$repo_name: git fetch origin failed"
			FAILED=$((FAILED + 1))
			continue
		fi
		if ! git -C "$repo_dir" fetch upstream >/dev/null 2>&1; then
			ux_error "$repo_name: git fetch upstream failed"
			FAILED=$((FAILED + 1))
			continue
		fi

		start_sha="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"

		# Check if local has incorporated both origin and upstream, and origin is at HEAD
		if git -C "$repo_dir" merge-base --is-ancestor "origin/$branch" HEAD 2>/dev/null && \
		   git -C "$repo_dir" merge-base --is-ancestor "upstream/$branch" HEAD 2>/dev/null && \
		   git -C "$repo_dir" merge-base --is-ancestor HEAD "origin/$branch" 2>/dev/null; then
			ux_success "$repo_name: up-to-date (origin+upstream: $branch)"
			UP_TO_DATE=$((UP_TO_DATE + 1))
			continue
		fi

		if $DRY_RUN; then
			ux_info "$repo_name: updates available from origin/upstream ($branch, dry-run)"
			UPDATED=$((UPDATED + 1))
			continue
		fi

		# Merge origin then upstream
		if ! git -C "$repo_dir" merge --no-edit "origin/$branch" >/dev/null 2>&1; then
			git -C "$repo_dir" merge --abort >/dev/null 2>&1 || true
			git -C "$repo_dir" reset --hard "$start_sha" >/dev/null 2>&1 || true
			ux_error "$repo_name: merge origin/$branch failed (conflict)"
			FAILED=$((FAILED + 1))
			continue
		fi

		if ! git -C "$repo_dir" merge --no-edit "upstream/$branch" >/dev/null 2>&1; then
			git -C "$repo_dir" merge --abort >/dev/null 2>&1 || true
			git -C "$repo_dir" reset --hard "$start_sha" >/dev/null 2>&1 || true
			ux_error "$repo_name: merge upstream/$branch failed (conflict)"
			FAILED=$((FAILED + 1))
			continue
		fi

		# Push to origin
		if git -C "$repo_dir" push origin "$branch" >/dev/null 2>&1; then
			ux_success "$repo_name: synced and pushed to origin ($branch)"
			UPDATED=$((UPDATED + 1))
		else
			ux_error "$repo_name: git push origin failed"
			FAILED=$((FAILED + 1))
		fi
		continue
	fi

	# Fetch origin
	if ! git -C "$repo_dir" fetch origin >/dev/null 2>&1; then
		ux_error "$repo_name: git fetch origin failed"
		FAILED=$((FAILED + 1))
		continue
	fi

	# Determine tracking remote ref
	remote_ref="origin/$branch"
	if ! git -C "$repo_dir" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
		# If branch is master/main and origin only has the other one, check fallback
		if [ "$branch" = "master" ] && git -C "$repo_dir" rev-parse --verify "origin/main" >/dev/null 2>&1; then
			remote_ref="origin/main"
		elif [ "$branch" = "main" ] && git -C "$repo_dir" rev-parse --verify "origin/master" >/dev/null 2>&1; then
			remote_ref="origin/master"
		else
			ux_warning "$repo_name: remote ref '$remote_ref' not found (skipped)"
			SKIPPED_BRANCH=$((SKIPPED_BRANCH + 1))
			continue
		fi
	fi

	# Compare local branch with remote ref
	local_sha="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
	remote_sha="$(git -C "$repo_dir" rev-parse "$remote_ref" 2>/dev/null)"

	if [ "$local_sha" = "$remote_sha" ]; then
		ux_success "$repo_name: up-to-date ($branch)"
		UP_TO_DATE=$((UP_TO_DATE + 1))
		continue
	fi

	# Check divergence
	base_sha="$(git -C "$repo_dir" merge-base HEAD "$remote_ref" 2>/dev/null || true)"
	if [ "$base_sha" = "$remote_sha" ]; then
		ux_info "$repo_name: local is ahead of $remote_ref ($branch)"
		UP_TO_DATE=$((UP_TO_DATE + 1))
		continue
	fi

	if $DRY_RUN; then
		if [ "$base_sha" = "$local_sha" ]; then
			ux_info "$repo_name: updates available from $remote_ref (dry-run)"
		else
			ux_warning "$repo_name: diverged from $remote_ref (dry-run, rebase required)"
		fi
		UPDATED=$((UPDATED + 1))
		continue
	fi

	# Pull / rebase
	if git -C "$repo_dir" pull --ff-only origin "$branch" >/dev/null 2>&1; then
		ux_success "$repo_name: updated via ff-only ($branch)"
		UPDATED=$((UPDATED + 1))
	elif git -C "$repo_dir" rebase "$remote_ref" >/dev/null 2>&1; then
		ux_success "$repo_name: updated via rebase ($remote_ref)"
		UPDATED=$((UPDATED + 1))
	else
		# Abort rebase if in progress to keep repo clean
		git -C "$repo_dir" rebase --abort >/dev/null 2>&1 || true
		ux_error "$repo_name: update failed (conflict or rebase error)"
		FAILED=$((FAILED + 1))
	fi

done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

ux_section "Summary"
ux_bullet "Total scanned: $TOTAL"
if $DRY_RUN; then
	ux_bullet "Updates available: $UPDATED"
else
	ux_bullet "Updated: $UPDATED"
fi
ux_bullet "Up to date: $UP_TO_DATE"
ux_bullet "Skipped (dirty): $SKIPPED_DIRTY"
ux_bullet "Skipped (non-main / detached): $SKIPPED_BRANCH"
ux_bullet "Skipped (not git): $SKIPPED_NOT_GIT"
if [ "$FAILED" -gt 0 ]; then
	ux_bullet "Failed: $FAILED"
	exit 1
fi

exit 0
