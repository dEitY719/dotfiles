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
JOBS="${DOTFILES_SKILLS_JOBS:-4}"

_usage() {
	cat <<USAGE
Usage: git-pull-skills.sh [options]

Options:
  --dry-run             Check repository status and incoming updates without pulling
  --all-branches        Pull non-main branches if tracking remote exists (default: skips non-main branches)
  --target <dir>        Target directory to search for git repositories (default: ~/para/project/skills)
  --jobs <N>            Repositories processed in parallel (default: \$DOTFILES_SKILLS_JOBS or 4; 1 = sequential)
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
			ux_error "--target requires a directory argument."
			exit 2
		fi
		TARGET_DIR="$2"
		shift 2
		;;
	--target=*)
		TARGET_DIR="${1#*=}"
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

if [ ! -d "$TARGET_DIR" ]; then
	ux_error "Target directory does not exist: $TARGET_DIR"
	exit 1
fi

ux_header "Git Pull Skills: $TARGET_DIR"
if $DRY_RUN; then
	ux_info "Mode: DRY-RUN (no working directory modifications)"
fi

UPDATED=0
UP_TO_DATE=0
SKIPPED_DIRTY=0
SKIPPED_BRANCH=0
SKIPPED_NOT_GIT=0
FAILED=0

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
			ux_error "$(cat "$POOL_DIR/$n.name"): job exited without a result"
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
		printf '%s\n' "${item##*/}" >"$POOL_DIR/$POOL_SEQ.name"
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
POOL_DIR="$(mktemp -d)" || {
	ux_error "mktemp -d failed — cannot buffer job output."
	exit 1
}
trap 'rm -rf "$POOL_DIR"' EXIT
# --- end job pool ------------------------------------------------------------

# _process_repo <dir> — sync one repository. Repos share no state, so this is
# safe to run concurrently (#2198).
_process_repo() {
	local repo_dir="$1" repo_name branch status_porcelain has_upstream start_sha
	local remote_ref local_sha remote_sha base_sha
	repo_name="$(basename "$repo_dir")"

	# 1. Check if git repo
	if ! git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		ux_warning "$repo_name: not a git repository (skipped)"
		_count SKIPPED_NOT_GIT
		return 0
	fi

	# 2. Check current branch
	branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || true)"
	if [ -z "$branch" ]; then
		ux_warning "$repo_name: detached HEAD (skipped)"
		_count SKIPPED_BRANCH
		return 0
	fi

	# Skip non-main/master branches by default unless --all-branches is set
	if ! $ALL_BRANCHES && [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
		ux_info "$repo_name: on non-main branch '$branch' (skipped, use --all-branches to include)"
		_count SKIPPED_BRANCH
		return 0
	fi

	# 3. Check dirty state (uncommitted changes)
	status_porcelain="$(git -C "$repo_dir" status --porcelain 2>/dev/null || true)"
	if [ -n "$status_porcelain" ]; then
		ux_warning "$repo_name: dirty working tree on '$branch' (skipped)"
		_count SKIPPED_DIRTY
		return 0
	fi

	# 4. Check remote origin
	if ! git -C "$repo_dir" config --get remote.origin.url >/dev/null 2>&1; then
		ux_warning "$repo_name: no remote 'origin' configured (skipped)"
		_count SKIPPED_BRANCH
		return 0
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
			_count FAILED
			return 0
		fi
		if ! git -C "$repo_dir" fetch upstream >/dev/null 2>&1; then
			ux_error "$repo_name: git fetch upstream failed"
			_count FAILED
			return 0
		fi

		start_sha="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"

		# Check if local has incorporated both origin and upstream, and origin is at HEAD
		if git -C "$repo_dir" merge-base --is-ancestor "origin/$branch" HEAD 2>/dev/null && \
		   git -C "$repo_dir" merge-base --is-ancestor "upstream/$branch" HEAD 2>/dev/null && \
		   git -C "$repo_dir" merge-base --is-ancestor HEAD "origin/$branch" 2>/dev/null; then
			ux_success "$repo_name: up-to-date (origin+upstream: $branch)"
			_count UP_TO_DATE
			return 0
		fi

		if $DRY_RUN; then
			ux_info "$repo_name: updates available from origin/upstream ($branch, dry-run)"
			_count UPDATED
			return 0
		fi

		# Merge origin then upstream
		if ! git -C "$repo_dir" merge --no-edit "origin/$branch" >/dev/null 2>&1; then
			git -C "$repo_dir" merge --abort >/dev/null 2>&1 || true
			git -C "$repo_dir" reset --hard "$start_sha" >/dev/null 2>&1 || true
			git -C "$repo_dir" clean -fd >/dev/null 2>&1 || true
			ux_error "$repo_name: merge origin/$branch failed (conflict)"
			_count FAILED
			return 0
		fi

		if ! git -C "$repo_dir" merge --no-edit "upstream/$branch" >/dev/null 2>&1; then
			git -C "$repo_dir" merge --abort >/dev/null 2>&1 || true
			git -C "$repo_dir" reset --hard "$start_sha" >/dev/null 2>&1 || true
			git -C "$repo_dir" clean -fd >/dev/null 2>&1 || true
			ux_error "$repo_name: merge upstream/$branch failed (conflict)"
			_count FAILED
			return 0
		fi

		# Push to origin
		if git -C "$repo_dir" push origin "$branch" >/dev/null 2>&1; then
			ux_success "$repo_name: synced and pushed to origin ($branch)"
			_count UPDATED
		else
			ux_error "$repo_name: git push origin failed"
			_count FAILED
		fi
		return 0
	fi

	# Fetch origin
	if ! git -C "$repo_dir" fetch origin >/dev/null 2>&1; then
		ux_error "$repo_name: git fetch origin failed"
		_count FAILED
		return 0
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
			_count SKIPPED_BRANCH
			return 0
		fi
	fi

	# Compare local branch with remote ref
	local_sha="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
	remote_sha="$(git -C "$repo_dir" rev-parse "$remote_ref" 2>/dev/null)"

	if [ "$local_sha" = "$remote_sha" ]; then
		ux_success "$repo_name: up-to-date ($branch)"
		_count UP_TO_DATE
		return 0
	fi

	# Check divergence
	base_sha="$(git -C "$repo_dir" merge-base HEAD "$remote_ref" 2>/dev/null || true)"
	if [ "$base_sha" = "$remote_sha" ]; then
		ux_info "$repo_name: local is ahead of $remote_ref ($branch)"
		_count UP_TO_DATE
		return 0
	fi

	if $DRY_RUN; then
		if [ "$base_sha" = "$local_sha" ]; then
			ux_info "$repo_name: updates available from $remote_ref (dry-run)"
		else
			ux_warning "$repo_name: diverged from $remote_ref (dry-run, rebase required)"
		fi
		_count UPDATED
		return 0
	fi

	# Pull / rebase
	if git -C "$repo_dir" pull --ff-only origin "$branch" >/dev/null 2>&1; then
		ux_success "$repo_name: updated via ff-only ($branch)"
		_count UPDATED
	elif git -C "$repo_dir" rebase "$remote_ref" >/dev/null 2>&1; then
		ux_success "$repo_name: updated via rebase ($remote_ref)"
		_count UPDATED
	else
		# Abort rebase if in progress to keep repo clean
		git -C "$repo_dir" rebase --abort >/dev/null 2>&1 || true
		ux_error "$repo_name: update failed (conflict or rebase error)"
		_count FAILED
	fi
}

# Subdirectories sorted alphabetically; hidden ones (.claude, ...) are never
# skill repos.
REPO_DIRS=()
while IFS= read -r repo_dir; do
	[ -n "$repo_dir" ] && REPO_DIRS+=("$repo_dir")
done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | LC_ALL=C sort)
TOTAL=${#REPO_DIRS[@]}

POOL_COUNTERS="UPDATED UP_TO_DATE SKIPPED_DIRTY SKIPPED_BRANCH SKIPPED_NOT_GIT FAILED"
_run_pool _process_repo ${REPO_DIRS[@]+"${REPO_DIRS[@]}"}

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
