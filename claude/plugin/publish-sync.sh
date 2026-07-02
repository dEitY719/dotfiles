#!/usr/bin/env bash
# claude/plugin/publish-sync.sh
#
# Publishes claude/plugin/{marketplaces,plugins}.json (and, on internal
# PCs, claude/plugin/company/{marketplaces,plugins}.json) changes that
# claude/hooks/plugin-sync.sh committed locally but could never push —
# both repos require changes to land via PR (branch protection / GHES
# ruleset), so a direct `git push` always fails.
#
# Never checks out a branch, touches the real index, or moves HEAD in the
# target repo: the publish commit is built with plumbing commands
# (hash-object, read-tree into a scratch index, write-tree, commit-tree)
# against origin/main, landed as a new ref, then pushed. Local `main` is
# only ever fast-forwarded afterward, and only when every commit it was
# ahead by is a pure "chore(claude-plugin): sync manifest" commit (see
# _cleanup_local_main_if_pure_sync).
#
# See docs/feature/superpowers-specs/2026-07-02-plugin-manifest-batch-publish-design.md
set -uo pipefail

SYNC_MSG="chore(claude-plugin): sync manifest"

# _repo_target <repo_dir>
#
# Print "<owner>/<repo>" parsed from that repo's `origin` remote URL —
# works for github.com or any GHES host, https or git@ SSH form.
_repo_target() {
	local url tmp
	url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
	url="${url%.git}"
	case "$url" in
	git@*:*)
		printf '%s\n' "${url#*:}"
		;;
	https://* | http://*)
		tmp="${url#*//}"
		printf '%s\n' "${tmp#*/}"
		;;
	*)
		return 1
		;;
	esac
}

# _manifest_diff_exists <repo_dir> <file...>
#
# Assumes `origin` has already been fetched by the caller. Returns 0 if
# any of the given paths' current content differs from origin/main.
_manifest_diff_exists() {
	local repo_dir="$1"
	shift
	! git -C "$repo_dir" diff --quiet origin/main -- "$@" 2>/dev/null
}

# _build_publish_commit <repo_dir> <file...>
#
# Build (but do not reference, push, or check out) a commit on top of
# origin/main whose tree is origin/main's tree with the given paths
# replaced by their CURRENT on-disk content in repo_dir. Uses a scratch
# index file so repo_dir's real index/HEAD/working tree are never
# touched. Prints the new commit SHA.
_build_publish_commit() {
	local repo_dir="$1"
	shift
	local base tmp_dir tmp_index new_tree new_commit f blob rc=0

	base=$(git -C "$repo_dir" rev-parse origin/main) || return 1
	tmp_dir=$(mktemp -d) || return 1 # atomically-created private dir avoids the symlink race
	tmp_index="$tmp_dir/index"

	GIT_INDEX_FILE="$tmp_index" git -C "$repo_dir" read-tree origin/main || {
		rm -rf "$tmp_dir"
		return 1
	}
	for f in "$@"; do
		[ -f "$repo_dir/$f" ] || continue
		blob=$(git -C "$repo_dir" hash-object -w "$repo_dir/$f") || {
			rc=1
			break
		}
		GIT_INDEX_FILE="$tmp_index" git -C "$repo_dir" update-index \
			--add --cacheinfo "100644,${blob},${f}" || {
			rc=1
			break
		}
	done
	if [ "$rc" -ne 0 ]; then
		rm -rf "$tmp_dir"
		return 1
	fi

	new_tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$repo_dir" write-tree) || {
		rm -rf "$tmp_dir"
		return 1
	}
	rm -rf "$tmp_dir"

	new_commit=$(git -C "$repo_dir" commit-tree "$new_tree" -p "$base" \
		-m "$SYNC_MSG") || return 1
	printf '%s\n' "$new_commit"
}

# _publish_branch <repo_dir> <label> <commit_sha>
#
# Create refs/heads/chore/plugin-sync-publish-<label>-<timestamp> pointing
# at commit_sha, push it to origin, print the branch name.
_publish_branch() {
	local repo_dir="$1" label="$2" commit="$3" branch
	branch="chore/plugin-sync-publish-${label}-$(date +%Y%m%d-%H%M%S)"
	git -C "$repo_dir" update-ref "refs/heads/$branch" "$commit" || return 1
	git -C "$repo_dir" push --quiet origin \
		"refs/heads/$branch:refs/heads/$branch" 2>/dev/null || return 1
	printf '%s\n' "$branch"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	echo "publish-sync.sh: not yet wired to a main entrypoint (Task 8)" >&2
	exit 1
fi
