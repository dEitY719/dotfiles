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
	url=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || return 1
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
		"refs/heads/$branch:refs/heads/$branch" || return 1
	printf '%s\n' "$branch"
}

# _open_and_merge_pr <repo_dir> <branch>
#
# Open a PR from branch onto main, wait for status checks to report, then
# merge with --admin. Self-authored PRs can never be approved by their
# own author (GitHub blocks self-approval server-side) — see
# claude/skills/gh-pr-approve/references/self-pr-handling.md for the same
# `gh pr merge --admin` pattern this reproduces in plain shell. Never
# merges on a failing or timed-out check.
_open_and_merge_pr() {
	local repo_dir="$1" branch="$2" target pr_url pr_number
	local interval="${PUBLISH_SYNC_CHECK_INTERVAL:-15}"
	local max_tries="${PUBLISH_SYNC_CHECK_MAX_TRIES:-20}"
	local tries=0 state="pending"

	target=$(_repo_target "$repo_dir") || {
		echo "publish-sync: origin remote를 해석하지 못함 ($repo_dir)" >&2
		return 1
	}

	pr_url=$(gh pr create --repo "$target" --head "$branch" --base main \
		--title "$SYNC_MSG" \
		--body "plugin-sync.sh가 로컬에 쌓아둔 매니페스트 변경을 게시합니다. 자동 생성됨." \
		2>&1) || {
		echo "publish-sync: PR 생성 실패 — $pr_url" >&2
		return 1
	}
	pr_number="${pr_url##*/}"
	echo "publish-sync: PR 생성됨 — $pr_url"

	while [ "$tries" -lt "$max_tries" ]; do
		state=$(gh pr checks "$pr_number" --repo "$target" \
			--json bucket \
			--jq '[.[].bucket] | if any(.=="fail" or .=="cancel") then "failed" elif any(.=="pending") then "pending" else "success" end' \
			2>/dev/null) || state="pending"
		[ "$state" = "success" ] && break
		[ "$state" = "failed" ] && break
		tries=$((tries + 1))
		sleep "$interval"
	done

	if [ "$state" = "failed" ]; then
		echo "publish-sync: status check 실패 — $pr_url 를 직접 확인하세요" >&2
		return 1
	fi
	if [ "$state" != "success" ]; then
		echo "publish-sync: status check 대기 타임아웃 — $pr_url 를 직접 확인하세요" >&2
		return 1
	fi

	gh pr merge "$pr_number" --repo "$target" --admin --rebase 2>&1 || {
		echo "publish-sync: admin merge 실패 — $pr_url 를 직접 확인하세요" >&2
		return 1
	}
	echo "publish-sync: 병합 완료 — $pr_url"
}

# _publish_manifest_diff <repo_dir> <label> <file...>
#
# Fetch origin; no-op if the given paths already match origin/main;
# otherwise build+push a single snapshot commit and open+merge a PR for
# it. Honors the global DRY_RUN (0/1), which stops after printing the
# diff. Returns nonzero on any failure of the publish pipeline.
_publish_manifest_diff() {
	local repo_dir="$1" label="$2"
	shift 2
	local before_origin

	git -C "$repo_dir" fetch origin --quiet 2>/dev/null || {
		echo "[$label] origin fetch 실패 — 건너뜀" >&2
		return 1
	}
	before_origin=$(git -C "$repo_dir" rev-parse origin/main) || return 1

	if ! _manifest_diff_exists "$repo_dir" "$@"; then
		echo "[$label] 변경 없음 — 할 일 없음"
		return 0
	fi
	echo "[$label] 변경 감지됨"

	if [ "${DRY_RUN:-0}" = "1" ]; then
		git -C "$repo_dir" diff origin/main -- "$@"
		return 0
	fi

	local commit branch
	commit=$(_build_publish_commit "$repo_dir" "$@") || {
		echo "[$label] publish 커밋 생성 실패" >&2
		return 1
	}
	branch=$(_publish_branch "$repo_dir" "$label" "$commit") || {
		echo "[$label] 브랜치 push 실패" >&2
		return 1
	}
	_open_and_merge_pr "$repo_dir" "$branch" || return 1

	_cleanup_local_main_if_pure_sync "$repo_dir" "$before_origin" "$@"
}

# _cleanup_local_main_if_pure_sync <repo_dir> <before_origin_sha> <file...>
#
# After a successful publish, fast-forward local main to the new
# origin/main IF every commit main was ahead of before_origin_sha by is a
# pure SYNC_MSG commit touching only the given files. Otherwise leaves
# main untouched. Never rebases or force-resets.
_cleanup_local_main_if_pure_sync() {
	local repo_dir="$1" before_origin="$2"
	shift 2
	local sha msg f changed pure=1 match cur_branch

	git -C "$repo_dir" fetch origin --quiet 2>/dev/null || {
		echo "publish-sync: 정리 단계 fetch 실패 — 로컬 main은 그대로 둡니다" >&2
		return 1
	}

	for sha in $(git -C "$repo_dir" rev-list "${before_origin}..main" 2>/dev/null); do
		msg=$(git -C "$repo_dir" log -1 --format=%s "$sha")
		if [ "$msg" != "$SYNC_MSG" ]; then
			pure=0
			break
		fi
		changed=$(git -C "$repo_dir" show --format= --name-only "$sha")
		for f in $changed; do
			match=0
			for want in "$@"; do
				[ "$f" = "$want" ] && match=1 && break
			done
			[ "$match" -eq 1 ] || {
				pure=0
				break 2
			}
		done
	done

	if [ "$pure" -ne 1 ]; then
		echo "publish-sync: 로컬 main에 sync 외 다른 커밋이 섞여 있어 정리를 건너뜁니다 — 직접 확인하세요" >&2
		return 0
	fi

	cur_branch=$(git -C "$repo_dir" symbolic-ref --short HEAD 2>/dev/null || echo "")
	if [ "$cur_branch" = "main" ]; then
		git -C "$repo_dir" merge --ff-only origin/main --quiet || return 1
	else
		git -C "$repo_dir" update-ref refs/heads/main origin/main || return 1
	fi
	echo "publish-sync: 로컬 main을 origin/main으로 정리했습니다"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	echo "publish-sync.sh: not yet wired to a main entrypoint (Task 8)" >&2
	exit 1
fi
