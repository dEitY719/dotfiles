#!/usr/bin/env bash
# claude/plugin/publish-sync.sh
#
# Publishes claude/plugin/{marketplaces,plugins}.json (and, on internal
# PCs, claude/plugin/company/{marketplaces,plugins}.json) changes that
# claude/hooks/plugin-sync.sh committed locally but could never push —
# both repos require changes to land via PR (branch protection / GHES
# ruleset), so a direct `git push` always fails.
#
# Never checks out a branch, touches the real index, or moves HEAD to build
# the publish commit: it is built with plumbing commands (hash-object,
# read-tree into a scratch index, write-tree, commit-tree) against
# origin/main, landed as a new ref, then pushed. Afterward local `main` is
# advanced to the published origin/main — fast-forwarded when it is a strict
# ancestor, or (the usual case, since the hook's local sync commit and the
# PR-merged one share content but not SHA and therefore diverge) rebased onto
# it — but ONLY when every commit main was ahead by is a pure
# "chore(claude-plugin): sync manifest" commit AND the working tree is clean.
# git's patch-id detection drops the now-redundant published commit while
# replaying any pure-sync commit whose content never actually landed, so
# nothing is lost (see _cleanup_local_main_if_pure_sync).
#
# See docs/feature/superpowers-specs/2026-07-02-plugin-manifest-batch-publish-design.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load UX library for semantic log colors (#1114). Cosmetic only — colors
# are emitted only to an interactive TTY, so piped/redirected/automation
# runs stay byte-plain for grep/snapshot consumers (#1116); a missing lib
# also falls back to plain. ux_lib.sh self-disables on
# NO_COLOR / TERM=dumb / DOTFILES_TEST_MODE as well.
UX_LIB="$SCRIPT_DIR/../../shell-common/tools/ux_lib/ux_lib.sh"
if [ -t 1 ] && [ -r "$UX_LIB" ]; then
	# shellcheck source=../../shell-common/tools/ux_lib/ux_lib.sh
	source "$UX_LIB"
else
	UX_SUCCESS="" UX_ERROR="" UX_WARNING="" UX_MUTED="" UX_RESET=""
fi

# MUST stay byte-identical to SYNC_MSG in claude/hooks/plugin-sync.sh:30 —
# _cleanup_local_main_if_pure_sync matches local commits against this string
# to decide which are safe to fast-forward past. If the two drift, cleanup
# silently stops recognizing the hook's real sync commits (no error, just a
# skipped tidy-up). Shared-constant extraction tracked as a follow-up.
SYNC_MSG="chore(claude-plugin): sync manifest"

# _repo_target <repo_dir>
#
# Print "<host>/<owner>/<repo>" parsed from that repo's `origin` remote
# URL — works for github.com or any GHES host, https or git@ SSH form.
# The host must travel with owner/repo: `gh --repo owner/repo` silently
# defaults to github.com, which would target the wrong host for a GHES
# remote (e.g. the internal company/ repo). `gh` accepts the
# HOST/OWNER/REPO form for --repo, and github.com/owner/repo works fine
# too.
_repo_target() {
	local url host_path
	url=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || return 1
	url="${url%.git}"
	case "$url" in
	git@*:*)
		host_path="${url#git@}"
		printf '%s\n' "${host_path%%:*}/${host_path#*:}"
		;;
	https://* | http://*)
		printf '%s\n' "${url#*//}"
		;;
	*)
		return 1
		;;
	esac
}

# _fetch_origin <repo_dir>
#
# Fetch origin with a few retries. The SSH-over-443 handshake to GitHub
# intermittently times out ("Connection timed out during banner exchange")
# — a transient network fault that a single-shot fetch would turn into a
# hard "publish skipped" for the whole run. Retries PUBLISH_SYNC_FETCH_TRIES
# times (default 3) with a PUBLISH_SYNC_FETCH_DELAY-second backoff (default
# 3); on the final failure it prints git's REAL stderr (banner-exchange
# timeout, auth error, …) rather than the old bare "fetch 실패" that hid the
# cause. Prints nothing on success; returns the last fetch's exit status.
_fetch_origin() {
	local repo_dir="$1"
	local tries="${PUBLISH_SYNC_FETCH_TRIES:-3}"
	local delay="${PUBLISH_SYNC_FETCH_DELAY:-3}"
	local i=1 err rc=0
	while :; do
		err=$(git -C "$repo_dir" fetch origin --quiet 2>&1)
		rc=$?
		[ "$rc" -eq 0 ] && return 0
		[ "$i" -ge "$tries" ] && break
		i=$((i + 1))
		sleep "$delay"
	done
	[ -n "$err" ] && printf '%s\n' "$err" >&2
	return "$rc"
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
	# Explicit template (not bare `mktemp -d`): BSD/macOS mktemp requires one.
	tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/publish-sync.XXXXXX") || return 1 # atomically-created private dir avoids the symlink race
	tmp_index="$tmp_dir/index"
	# Explicit cleanup at each exit site rather than a `trap ... RETURN`: a
	# RETURN trap is not cleared when this function returns, so under `set -u`
	# it would keep firing on later (bats/`run`) function returns where the
	# local `tmp_dir` is out of scope — an "unbound variable" abort. The
	# per-return `rm -rf` avoids that footgun.

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
# Create refs/heads/chore/plugin-sync-publish-<label>-<timestamp>-<pid>
# pointing at commit_sha, push it to origin, print the branch name. The
# pid suffix avoids a same-second collision when two runs land in the
# same wall-clock second.
_publish_branch() {
	local repo_dir="$1" label="$2" commit="$3" branch
	branch="chore/plugin-sync-publish-${label}-$(date +%Y%m%d-%H%M%S)-$$"
	git -C "$repo_dir" update-ref "refs/heads/$branch" "$commit" || return 1
	if ! git -C "$repo_dir" push --quiet origin \
		"refs/heads/$branch:refs/heads/$branch"; then
		# Push failed (network/auth/policy) — drop the local ref we just
		# created so repeated failed runs don't litter the repo with orphaned
		# chore/plugin-sync-publish-* branches.
		git -C "$repo_dir" update-ref -d "refs/heads/$branch" 2>/dev/null || true
		return 1
	fi
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
	local tries=0 state="pending" saw_checks=0

	target=$(_repo_target "$repo_dir") || {
		echo "${UX_ERROR}publish-sync: origin remote를 해석하지 못함 ($repo_dir)${UX_RESET}" >&2
		return 1
	}

	local pr_out
	pr_out=$(gh pr create --repo "$target" --head "$branch" --base main \
		--title "$SYNC_MSG" \
		--body "plugin-sync.sh가 로컬에 쌓아둔 매니페스트 변경을 게시합니다. 자동 생성됨." \
		2>&1) || {
		echo "${UX_ERROR}publish-sync: PR 생성 실패 — $pr_out${UX_RESET}" >&2
		return 1
	}
	# gh can fold warnings/deprecation notices into stdout via the 2>&1 above;
	# pull the real PR URL out by pattern rather than trusting the whole blob,
	# so a stray line can't corrupt `${pr_url##*/}` and silently target the
	# wrong PR (or an empty number) at merge time. Take the last match.
	pr_url=$(printf '%s\n' "$pr_out" | grep -oE 'https?://[^[:space:]]+/pull/[0-9]+' | tail -n1)
	pr_number="${pr_url##*/}"
	if [ -z "$pr_number" ]; then
		echo "${UX_ERROR}publish-sync: PR URL 파싱 실패 — gh 출력: $pr_out${UX_RESET}" >&2
		return 1
	fi
	echo "${UX_SUCCESS}publish-sync: PR 생성됨 — $pr_url${UX_RESET}"

	# The `--json bucket` flag on the `pr checks` subcommand does not exist
	# on gh <2.46ish (unknown flag: --json) — verified on gh 2.45.0, which
	# every poll would error on, always falling to "pending" and eventually
	# timing out even when checks are green. `gh pr view --json
	# statusCheckRollup` works on 2.45.0 and returns each check as either a
	# CheckRun (`status` + `conclusion`) or a StatusContext (`state`, no
	# `conclusion`); the jq below normalizes both shapes to one aggregate
	# word, fail-closed on any unrecognized shape. Unlike the old `gh pr
	# checks` subcommand, `gh pr view --json statusCheckRollup` has no "no
	# checks reported" signal — a genuinely checkless repo just exits 0
	# with an empty `statusCheckRollup: []`, indistinguishable from checks
	# that simply haven't registered yet. So an empty rollup polls as
	# "pending" for the FULL window below (never a premature give-up);
	# "checkless" is only declared at timeout if checks were never once
	# observed (see saw_checks below).
	while [ "$tries" -lt "$max_tries" ]; do
		# shellcheck disable=SC2016 # `$v` below is jq's `as $v` binding, not a shell variable — single-quoted on purpose.
		state=$(gh pr view "$pr_number" --repo "$target" \
			--json statusCheckRollup \
			--jq '[ .statusCheckRollup[]? | if (.conclusion != null) then (if (.conclusion == "FAILURE" or .conclusion == "CANCELLED" or .conclusion == "TIMED_OUT" or .conclusion == "ACTION_REQUIRED" or .conclusion == "STARTUP_FAILURE") then "fail" elif (.conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "pass" else "pending" end) elif (.status != null and .status != "COMPLETED") then "pending" elif (.state != null) then (if (.state == "FAILURE" or .state == "ERROR") then "fail" elif (.state == "SUCCESS") then "pass" else "pending" end) else "pending" end ] as $v | if ($v|length)==0 then "empty" elif ($v|any(.=="fail")) then "failed" elif ($v|any(.=="pending")) then "pending" else "success" end' \
			2>/dev/null) || {
			# gh exits non-zero on auth/network errors — stay "pending" and
			# retry; a transient error message must not abort the poll loop.
			state="pending"
		}
		# Record whether we've ever seen a non-empty rollup BEFORE folding
		# "empty" into "pending" for the loop's own break/continue logic.
		[ "$state" != "empty" ] && saw_checks=1
		[ "$state" = "empty" ] && state="pending"
		[ "$state" = "success" ] && break
		[ "$state" = "failed" ] && break
		tries=$((tries + 1))
		sleep "$interval"
	done

	case "$state" in
	success) ;;
	failed)
		echo "${UX_ERROR}publish-sync: status check 실패 — $pr_url 를 직접 확인하세요${UX_RESET}" >&2
		return 1
		;;
	*)
		# Loop exhausted without success/failed. If checks were NEVER
		# observed (rollup was empty on every single poll), treat this as a
		# genuinely checkless repo; otherwise checks appeared but stayed
		# pending the whole window.
		if [ "$saw_checks" -eq 0 ]; then
			echo "${UX_WARNING}publish-sync: status check가 구성되지 않은 리포 — 자동 병합하지 않습니다. $pr_url 를 직접 검토/병합하세요${UX_RESET}" >&2
		else
			echo "${UX_ERROR}publish-sync: status check 대기 타임아웃 — $pr_url 를 직접 확인하세요${UX_RESET}" >&2
		fi
		return 1
		;;
	esac

	gh pr merge "$pr_number" --repo "$target" --admin --rebase --delete-branch 2>&1 || {
		echo "${UX_ERROR}publish-sync: admin merge 실패 — $pr_url 를 직접 확인하세요${UX_RESET}" >&2
		return 1
	}
	echo "${UX_SUCCESS}publish-sync: 병합 완료 — $pr_url${UX_RESET}"
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

	_fetch_origin "$repo_dir" || {
		echo "${UX_ERROR}[$label] origin fetch 실패 (재시도 후) — 건너뜀${UX_RESET}" >&2
		return 1
	}

	if ! _manifest_diff_exists "$repo_dir" "$@"; then
		echo "${UX_MUTED}[$label] 변경 없음 — 할 일 없음${UX_RESET}"
		return 0
	fi
	echo "${UX_MUTED}[$label] 변경 감지됨${UX_RESET}"

	if [ "${DRY_RUN:-0}" = "1" ]; then
		git -C "$repo_dir" diff origin/main -- "$@"
		return 0
	fi

	# Captured only on the real publish path (after the no-op / dry-run
	# early returns) since it is consumed solely by the post-merge cleanup —
	# saves a git fork on the common "nothing to publish" and dry-run runs.
	before_origin=$(git -C "$repo_dir" rev-parse origin/main) || return 1

	local commit branch
	commit=$(_build_publish_commit "$repo_dir" "$@") || {
		echo "${UX_ERROR}[$label] publish 커밋 생성 실패${UX_RESET}" >&2
		return 1
	}
	branch=$(_publish_branch "$repo_dir" "$label" "$commit") || {
		echo "${UX_ERROR}[$label] 브랜치 push 실패${UX_RESET}" >&2
		return 1
	}
	_open_and_merge_pr "$repo_dir" "$branch" || return 1

	# Publish landed. `gh pr merge --delete-branch` removed the REMOTE branch,
	# but the local ref we created in $repo_dir via update-ref survives — drop
	# it so successful runs don't accumulate orphaned chore/plugin-sync-publish-*
	# refs (mirrors the push-failure cleanup in _publish_branch).
	git -C "$repo_dir" update-ref -d "refs/heads/$branch" 2>/dev/null || true

	# Local-main cleanup is best-effort AFTER the irreversible publish — its
	# own stderr already explains any skip/failure; never let it flip the
	# orchestrator's result, or Task 8's loop would misread a successful
	# publish as needing a retry.
	_cleanup_local_main_if_pure_sync "$repo_dir" "$before_origin" "$@" || true
	return 0
}

# _cleanup_local_main_if_pure_sync <repo_dir> <before_origin_sha> <file...>
#
# After a successful publish, advance local main to the new origin/main IF
# every commit main was ahead of before_origin_sha by is a pure SYNC_MSG
# commit touching only the given files. Fast-forwards when local main is a
# strict ancestor; otherwise (main diverged because the PR-merged sync
# commit landed with a different SHA than the hook's local one — the usual
# case) rebases onto origin/main, but only when the working tree is clean —
# git's patch-id detection drops the redundant published commit while
# replaying any pure-sync commit whose content never landed, so nothing is
# lost. Leaves main untouched with an explanatory message when the tree is
# dirty, the rebase conflicts, or purity fails. Never force-resets.
_cleanup_local_main_if_pure_sync() {
	local repo_dir="$1" before_origin="$2"
	shift 2
	local sha msg f pure=1 match want cur_branch

	_fetch_origin "$repo_dir" || {
		echo "${UX_ERROR}publish-sync: 정리 단계 fetch 실패 (재시도 후) — 로컬 main은 그대로 둡니다${UX_RESET}" >&2
		return 1
	}

	for sha in $(git -C "$repo_dir" rev-list "${before_origin}..main" 2>/dev/null); do
		msg=$(git -C "$repo_dir" log -1 --format=%s "$sha")
		if [ "$msg" != "$SYNC_MSG" ]; then
			pure=0
			break
		fi
		# `git show --name-only` is newline-delimited; read line-by-line via
		# process substitution (keeps the loop in this shell so `break 2` still
		# escapes the outer rev-list loop) so a path containing spaces isn't
		# word-split into false mismatches.
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			match=0
			for want in "$@"; do
				[ "$f" = "$want" ] && match=1 && break
			done
			[ "$match" -eq 1 ] || {
				pure=0
				break 2
			}
		done < <(git -C "$repo_dir" show --format= --name-only "$sha")
	done

	if [ "$pure" -ne 1 ]; then
		echo "${UX_WARNING}publish-sync: 로컬 main에 sync 외 다른 커밋이 섞여 있어 정리를 건너뜁니다 — 직접 확인하세요${UX_RESET}" >&2
		return 0
	fi

	cur_branch=$(git -C "$repo_dir" symbolic-ref --short HEAD 2>/dev/null || echo "")
	if [ "$cur_branch" = "main" ]; then
		if git -C "$repo_dir" merge --ff-only origin/main --quiet 2>/dev/null; then
			: # local main was a strict ancestor — a plain fast-forward sufficed
		elif git -C "$repo_dir" diff --quiet && git -C "$repo_dir" diff --cached --quiet; then
			# Diverged, but purity is already proven (pure=1) and the working
			# tree is clean. Rebase onto the new origin/main: git's patch-id
			# detection drops the now-redundant published sync commit (the manual
			# `git rebase origin/main` a user would otherwise run every publish),
			# while REPLAYING any pure-sync commit whose content never actually
			# landed — so nothing is lost. `--ff-only` can never succeed here
			# because `gh pr merge --rebase` re-commits the snapshot under a new
			# SHA, which is why the old code fell through to a manual-cleanup
			# message on every real publish.
			if ! git -C "$repo_dir" rebase origin/main >/dev/null 2>&1; then
				git -C "$repo_dir" rebase --abort >/dev/null 2>&1 || true
				echo "${UX_ERROR}publish-sync: 로컬 main rebase 중 충돌 — publish 는 성공했으니 'git rebase origin/main' 으로 직접 정리하세요${UX_RESET}" >&2
				return 1
			fi
		else
			echo "${UX_WARNING}publish-sync: 로컬 main 워킹트리에 미커밋 변경이 있어 정리를 건너뜁니다 — publish 는 성공했으니 필요하면 'git pull' 로 직접 정리하세요${UX_RESET}" >&2
			return 1
		fi
	else
		# `branch -f` (not `update-ref`) refuses to move main if it's checked
		# out in another linked worktree, avoiding a phantom diff there.
		git -C "$repo_dir" branch -f main origin/main || return 1
	fi
	echo "${UX_SUCCESS}publish-sync: 로컬 main을 origin/main으로 정리했습니다${UX_RESET}"
}

# _public_publish_allowed
#
# Return 0 if the public (github.com) dotfiles repo may be published from
# this PC, 1 if it must not. `internal` PCs are github.com **pull-only**
# (docs/.ssot/pc-environment.md §3) — pushing there is a policy violation,
# so publish-sync must not even attempt the branch/PR/merge on the public
# repo from an internal PC (#1080). The company/ GHES repo is unaffected
# (its own `[ -d "$PRIV_DIR/.git" ]` gate already scopes it to internal).
#
# Reads ~/.dotfiles-setup-mode directly (like restore.sh — this is a
# stand-alone script, not sourced with the shell-common integration layer),
# canonicalizing the legacy numeric values 1/2/3 exactly as
# shell-common/functions/gh_host.sh does so the two agree. A missing/unknown
# mode falls through to "allowed" (github.com), matching gh_host.sh's
# regression-zero fail-safe.
_public_publish_allowed() {
	local mode=""
	# Guard the read with `[ -f ]` (like gh_host.sh): a bare `<missing-file`
	# redirection leaks "bash: …: No such file or directory" to the real
	# stderr even with `2>/dev/null` on the command, since the redirection
	# failure is reported by the shell, not `tr`. A missing file means "no
	# mode set" → github.com default (allowed).
	if [ -f "$HOME/.dotfiles-setup-mode" ]; then
		mode=$(tr -d ' \t\n\r' <"$HOME/.dotfiles-setup-mode" 2>/dev/null || echo "")
	fi
	case "$mode" in
	1) mode="public" ;;
	2) mode="internal" ;;
	3) mode="external" ;;
	esac
	[ "$mode" != "internal" ]
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	DRY_RUN=0
	case "${1:-}" in
	"") ;;
	--dry-run) DRY_RUN=1 ;;
	-h | --help | help)
		echo "usage: publish-sync.sh [--dry-run]"
		echo "  Publishes claude/plugin manifest changes to origin (and the"
		echo "  internal company/ repo when present) via branch + PR + admin-merge."
		echo "  --dry-run  show the diff that would be published; no push/PR/merge."
		exit 0
		;;
	*)
		echo "${UX_ERROR}publish-sync.sh: 알 수 없는 인자: $1${UX_RESET}" >&2
		echo "usage: publish-sync.sh [--dry-run]  (-h 로 도움말)" >&2
		exit 2
		;;
	esac

	command -v gh >/dev/null 2>&1 || {
		echo "${UX_ERROR}gh CLI가 필요합니다.${UX_RESET}" >&2
		exit 1
	}

	MAIN_ROOT="$HOME/dotfiles"
	PRIV_DIR="$MAIN_ROOT/claude/plugin/company"
	RC=0

	# Serialize concurrent publishing runs — the plugin-sync hook can fire
	# while a manual `publish-sync.sh` is mid-flight, and both would otherwise
	# open a PR for the same manifest diff (the second lands as a no-op, but
	# still churns a branch + PR). Per-repo, non-blocking lock kept in the git
	# dir (untracked, so it never dirties the tree); a second run exits cleanly
	# rather than piling up. The git dir is resolved via `git rev-parse
	# --git-dir` rather than a bare `[ -d "$MAIN_ROOT/.git" ]`: in a worktree
	# `.git` is a FILE ("gitdir: …"), not a directory, so the -d test would
	# silently skip locking there (#1096 review). Skipped for --dry-run
	# (read-only) and when flock (util-linux) or the git dir is unavailable —
	# then we simply proceed. Top-level scope, so no `local`.
	if [ "$DRY_RUN" = "0" ] && command -v flock >/dev/null 2>&1; then
		GIT_DIR_PATH=$(git -C "$MAIN_ROOT" rev-parse --git-dir 2>/dev/null || echo "")
		case "$GIT_DIR_PATH" in
		"") ;;                                        # not a git repo — proceed unlocked
		/*) ;;                                        # already absolute
		*) GIT_DIR_PATH="$MAIN_ROOT/$GIT_DIR_PATH" ;; # relative → anchor to MAIN_ROOT
		esac
		if [ -n "$GIT_DIR_PATH" ] && exec 9>"$GIT_DIR_PATH/publish-sync.lock"; then
			if ! flock -n 9; then
				echo "${UX_WARNING}publish-sync: 다른 인스턴스가 실행 중 — 이번 실행은 건너뜁니다${UX_RESET}"
				exit 0
			fi
		fi
	fi

	if _public_publish_allowed; then
		_publish_manifest_diff "$MAIN_ROOT" "public" \
			claude/plugin/marketplaces.json claude/plugin/plugins.json || RC=1
	else
		echo "${UX_MUTED}[public] internal 모드 — github.com은 pull-only 정책이라 public manifest publish를 건너뜁니다 (사내→사외 push 금지)${UX_RESET}"
	fi

	if [ -d "$PRIV_DIR/.git" ]; then
		_publish_manifest_diff "$PRIV_DIR" "company" \
			marketplaces.json plugins.json || RC=1
	fi

	exit $RC
fi
