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

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	echo "publish-sync.sh: not yet wired to a main entrypoint (Task 8)" >&2
	exit 1
fi
