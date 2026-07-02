# claude/plugin/publish-sync.sh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `claude/plugin/publish-sync.sh`, a standalone shell script that publishes the manifest changes `claude/hooks/plugin-sync.sh` commits locally (but can never push, because both the public dotfiles repo and the internal GHES `company/` repo require changes to land via PR) — via a real branch + PR + admin-merge, run manually whenever the user wants.

**Architecture:** One function per concern (repo-target parsing, diff detection, snapshot-commit construction via git plumbing, branch/push, PR-create/check-wait/admin-merge, orchestration, post-merge local cleanup), all defined in a single file and guarded behind a `[ "${BASH_SOURCE[0]}" = "${0}" ]` check so bats can `source` the file and unit-test each function directly, while the file also runs end-to-end when executed. The orchestration function is called once for the public repo and — only when `claude/plugin/company/.git` exists — once more for that repo, using the exact same code path for both (no host-specific branching; each repo's own `origin` remote resolves the right host).

**Tech Stack:** POSIX-ish bash (matches `claude/hooks/plugin-sync.sh` / `claude/plugin/restore.sh` style), `git` plumbing commands, GitHub CLI (`gh`), bats + bats-support/bats-assert for tests.

## Global Constraints

- Never checks out a branch, mutates the real index, or moves `HEAD` in the target repo — all commit construction happens via `GIT_INDEX_FILE`-scoped scratch indexes and plumbing commands (`hash-object`, `read-tree`, `write-tree`, `commit-tree`, `update-ref`). This matters because the repo directory may be the user's actual working copy, possibly in concurrent use by another session.
- Never force-pushes, rebases, or resets destructively. Local `main` is only ever fast-forwarded (`merge --ff-only` or, if not checked out, `update-ref`), and only under the exact safety condition in Task 7.
- Commit message for every publish commit is the literal string `chore(claude-plugin): sync manifest` (matches `claude/hooks/plugin-sync.sh`'s `SYNC_MSG`).
- No `jq` dependency — this script only diffs/copies opaque file content, never parses the manifest JSON semantically.
- Interactive guard from `CLAUDE.md` does NOT apply — this script produces output only when run directly by a human (matches `restore.sh`, which also has no guard).
- File header comment must cite `docs/feature/superpowers-specs/2026-07-02-plugin-manifest-batch-publish-design.md`.
- Every new bats file starts with `load '../test_helper'` and uses `setup_isolated_home` / `teardown_isolated_home`, matching `tests/bats/tools/claude_plugin_restore.bats`.

---

### Task 1: Scaffold the script + `_repo_target`

**Files:**
- Create: `claude/plugin/publish-sync.sh`
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`

**Interfaces:**
- Produces: `_repo_target <repo_dir>` — prints `<owner>/<repo>` (no `.git` suffix) parsed from that repo's `origin` remote URL to stdout, returns 1 if the remote is missing or unparseable. Handles `git@host:owner/repo(.git)` and `https://host/owner/repo(.git)` forms for any host (github.com or GHES).

- [ ] **Step 1: Write the failing test**

Create `tests/bats/tools/claude_plugin_publish_sync.bats`:

```bash
#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_publish_sync.bats
# claude/plugin/publish-sync.sh — publishes plugin-sync.sh's local-only
# manifest commits to origin (and, on internal PCs, the GHES company/
# repo) via branch + PR + admin-merge, since both repos require PRs.

load '../test_helper'

PUBLISH_SYNC="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/publish-sync.sh"

setup() {
    setup_isolated_home
    source "$PUBLISH_SYNC"
}

teardown() {
    teardown_isolated_home
}

@test "_repo_target parses git@ SSH form" {
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "git@github.com:dEitY719/dotfiles.git"

    run _repo_target "$REPO"
    assert_success
    assert_output "dEitY719/dotfiles"
}

@test "_repo_target parses https form on a GHES host" {
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "https://github.samsungds.net/byoungwoo-yoon/claude-plugin-jira.git"

    run _repo_target "$REPO"
    assert_success
    assert_output "byoungwoo-yoon/claude-plugin-jira"
}

@test "_repo_target fails when origin remote is missing" {
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q

    run _repo_target "$REPO"
    assert_failure
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — `claude/plugin/publish-sync.sh: No such file or directory` (script doesn't exist yet).

- [ ] **Step 3: Create the script with `_repo_target`**

Create `claude/plugin/publish-sync.sh`:

```bash
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
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x claude/plugin/publish-sync.sh && ./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: PASS (3 tests).

- [ ] **Step 5: Lint and commit**

Run: `mise run lint-sh`
Expected: clean (shellcheck + shfmt -d both pass).

```bash
git add claude/plugin/publish-sync.sh tests/bats/tools/claude_plugin_publish_sync.bats
git commit -m "feat(claude-plugin): publish-sync.sh 스캐폴드 + _repo_target"
```

---

### Task 2: `_manifest_diff_exists`

**Files:**
- Modify: `claude/plugin/publish-sync.sh`
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`

**Interfaces:**
- Consumes: nothing new.
- Produces: `_manifest_diff_exists <repo_dir> <file...>` — returns 0 if any of the given paths' current on-disk content (on whatever branch is checked out) differs from `origin/main`, 1 otherwise. **Assumes `origin` has already been fetched** by the caller — this function does no network I/O itself, so it stays fast and independently testable.

- [ ] **Step 1: Write the failing test**

Append to `tests/bats/tools/claude_plugin_publish_sync.bats`:

```bash
_seed_repo_with_origin() {
    # $1 = repo dir to create. Sets up repo_dir with an `origin` remote
    # pointing at a local bare repo, one commit on main in both, so tests
    # can freely diverge repo_dir from origin/main.
    local repo_dir="$1"
    local bare="$TEST_TEMP_HOME/origin.git"
    git init -q --bare "$bare"

    mkdir -p "$repo_dir/claude/plugin"
    git -C "$repo_dir" init -q -b main
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "test"
    echo '{}' >"$repo_dir/claude/plugin/marketplaces.json"
    echo '{"plugins": []}' >"$repo_dir/claude/plugin/plugins.json"
    git -C "$repo_dir" add claude/plugin
    git -C "$repo_dir" commit -q -m "seed"
    git -C "$repo_dir" remote add origin "$bare"
    git -C "$repo_dir" push -q origin main
}

@test "_manifest_diff_exists returns false when files match origin/main" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" fetch origin --quiet

    run _manifest_diff_exists "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_failure
}

@test "_manifest_diff_exists returns true when local file changed" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    git -C "$REPO" fetch origin --quiet

    run _manifest_diff_exists "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — `_manifest_diff_exists: command not found`.

- [ ] **Step 3: Implement**

Insert into `claude/plugin/publish-sync.sh`, after `_repo_target`:

```bash
# _manifest_diff_exists <repo_dir> <file...>
#
# Assumes `origin` has already been fetched by the caller. Returns 0 if
# any of the given paths' current content differs from origin/main.
_manifest_diff_exists() {
	local repo_dir="$1"
	shift
	! git -C "$repo_dir" diff --quiet origin/main -- "$@" 2>/dev/null
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: PASS (5 tests).

- [ ] **Step 5: Lint and commit**

```bash
mise run lint-sh
git add claude/plugin/publish-sync.sh tests/bats/tools/claude_plugin_publish_sync.bats
git commit -m "feat(claude-plugin): publish-sync.sh — _manifest_diff_exists"
```

---

### Task 3: `_build_publish_commit`

**Files:**
- Modify: `claude/plugin/publish-sync.sh`
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`

**Interfaces:**
- Consumes: `SYNC_MSG` (global, defined in Task 1).
- Produces: `_build_publish_commit <repo_dir> <file...>` — prints the SHA of a **new, unreferenced** commit object whose tree is `origin/main`'s tree with the given paths replaced by their current on-disk content in `repo_dir`, parented on `origin/main`. Does not create or move any ref, and does not touch `repo_dir`'s real index/HEAD/working tree.

- [ ] **Step 1: Write the failing test**

Append:

```bash
@test "_build_publish_commit snapshots current file content onto origin/main without touching the real index" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    git -C "$REPO" fetch origin --quiet

    BEFORE_HEAD=$(git -C "$REPO" rev-parse HEAD)
    BEFORE_STATUS=$(git -C "$REPO" status --porcelain)

    run _build_publish_commit "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    NEW_COMMIT="$output"

    # parent is origin/main, not the diverged local HEAD
    run git -C "$REPO" rev-parse "${NEW_COMMIT}^"
    assert_output "$(git -C "$REPO" rev-parse origin/main)"

    # tree carries the current (edited) marketplaces.json content
    run git -C "$REPO" show "${NEW_COMMIT}:claude/plugin/marketplaces.json"
    assert_output '{"anthropic-agent-skills": "anthropics/skills"}'

    # real HEAD/index/working tree untouched
    assert_equal "$(git -C "$REPO" rev-parse HEAD)" "$BEFORE_HEAD"
    assert_equal "$(git -C "$REPO" status --porcelain)" "$BEFORE_STATUS"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — `_build_publish_commit: command not found`.

- [ ] **Step 3: Implement**

Insert after `_manifest_diff_exists`:

```bash
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
	local base tmp_index new_tree new_commit f blob rc=0

	base=$(git -C "$repo_dir" rev-parse origin/main) || return 1
	tmp_index=$(mktemp -u) # read-tree wants a fresh/absent path

	GIT_INDEX_FILE="$tmp_index" git -C "$repo_dir" read-tree origin/main || {
		rm -f "$tmp_index"
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
		rm -f "$tmp_index"
		return 1
	fi

	new_tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$repo_dir" write-tree) || {
		rm -f "$tmp_index"
		return 1
	}
	rm -f "$tmp_index"

	new_commit=$(git -C "$repo_dir" commit-tree "$new_tree" -p "$base" \
		-m "$SYNC_MSG") || return 1
	printf '%s\n' "$new_commit"
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: PASS (6 tests).

- [ ] **Step 5: Lint and commit**

```bash
mise run lint-sh
git add claude/plugin/publish-sync.sh tests/bats/tools/claude_plugin_publish_sync.bats
git commit -m "feat(claude-plugin): publish-sync.sh — _build_publish_commit"
```

---

### Task 4: `_publish_branch`

**Files:**
- Modify: `claude/plugin/publish-sync.sh`
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`

**Interfaces:**
- Consumes: a commit SHA from `_build_publish_commit`.
- Produces: `_publish_branch <repo_dir> <label> <commit_sha>` — creates `refs/heads/chore/plugin-sync-publish-<label>-<YYYYMMDD-HHMMSS>` pointing at `commit_sha`, pushes it to `origin`, and prints the branch name.

- [ ] **Step 1: Write the failing test**

Append:

```bash
@test "_publish_branch creates a timestamped branch and pushes it to origin" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" fetch origin --quiet
    COMMIT=$(_build_publish_commit "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json)

    run _publish_branch "$REPO" "public" "$COMMIT"
    assert_success
    BRANCH="$output"
    [[ "$BRANCH" == chore/plugin-sync-publish-public-* ]]

    # the branch exists on the bare "origin" with the right commit
    run git -C "$TEST_TEMP_HOME/origin.git" rev-parse "refs/heads/$BRANCH"
    assert_output "$COMMIT"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — `_publish_branch: command not found`.

- [ ] **Step 3: Implement**

Insert after `_build_publish_commit`:

```bash
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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: PASS (7 tests).

- [ ] **Step 5: Lint and commit**

```bash
mise run lint-sh
git add claude/plugin/publish-sync.sh tests/bats/tools/claude_plugin_publish_sync.bats
git commit -m "feat(claude-plugin): publish-sync.sh — _publish_branch"
```

---

### Task 5: `gh` stub helper + `_open_and_merge_pr`

**Files:**
- Modify: `claude/plugin/publish-sync.sh`
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`

**Interfaces:**
- Consumes: a branch name from `_publish_branch`; `_repo_target` (Task 1).
- Produces: `_open_and_merge_pr <repo_dir> <branch>` — opens a PR from `branch` onto `main`, polls `gh pr checks` (interval/attempts overridable via `PUBLISH_SYNC_CHECK_INTERVAL` / `PUBLISH_SYNC_CHECK_MAX_TRIES`, defaulting to `15` / `20`), and on success merges with `gh pr merge --admin --rebase` (self-authored PRs can never be approved by their own author — see `claude/skills/gh-pr-approve/references/self-pr-handling.md`). Returns 1 without merging on PR-create failure, a failing check, or a check-wait timeout.

This task introduces a **fake `gh` executable** so the rest of the suite can exercise the full PR/merge flow offline. Every later bats test in this file that reaches `_open_and_merge_pr` (Tasks 6, 8) reuses this helper.

- [ ] **Step 1: Write the failing test**

Append:

```bash
# Installs a fake `gh` at the front of PATH. Every invocation is appended
# to $GH_STUB_LOG as one line (argv joined by spaces). Behavior is
# controlled by files under $GH_STUB_DIR:
#   checks_result   - "success" | "failed" | "pending" (default: success)
#   merge_result    - "success" | "failed" (default: success)
_install_gh_stub() {
    GH_STUB_DIR="$TEST_TEMP_HOME/gh-stub"
    mkdir -p "$GH_STUB_DIR/bin"
    GH_STUB_LOG="$GH_STUB_DIR/log"
    : >"$GH_STUB_LOG"
    echo "success" >"$GH_STUB_DIR/checks_result"
    echo "success" >"$GH_STUB_DIR/merge_result"

    cat >"$GH_STUB_DIR/bin/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$GH_STUB_LOG"
case "\$1 \$2" in
"pr create")
    echo "https://example.com/owner/repo/pull/42"
    exit 0
    ;;
"pr checks")
    cat "$GH_STUB_DIR/checks_result"
    exit 0
    ;;
"pr merge")
    if [ "\$(cat "$GH_STUB_DIR/merge_result")" = "success" ]; then
        exit 0
    fi
    echo "merge blocked" >&2
    exit 1
    ;;
*)
    exit 0
    ;;
esac
STUB
    chmod +x "$GH_STUB_DIR/bin/gh"
    PATH="$GH_STUB_DIR/bin:$PATH"
    PUBLISH_SYNC_CHECK_INTERVAL=0
    PUBLISH_SYNC_CHECK_MAX_TRIES=3
    export PATH PUBLISH_SYNC_CHECK_INTERVAL PUBLISH_SYNC_CHECK_MAX_TRIES
}

@test "_open_and_merge_pr creates a PR, waits for checks, and admin-merges on success" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    _install_gh_stub
    echo "success" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_success
    run grep -c "^pr create" "$GH_STUB_LOG"
    assert_output "1"
    run grep -c "^pr merge.*--admin" "$GH_STUB_LOG"
    assert_output "1"
}

@test "_open_and_merge_pr does not merge when checks fail" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    _install_gh_stub
    echo "failed" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_failure
    run grep -c "^pr merge" "$GH_STUB_LOG"
    assert_output "0"
}

@test "_open_and_merge_pr times out and does not merge when checks stay pending" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    _install_gh_stub
    echo "pending" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_failure
    run grep -c "^pr merge" "$GH_STUB_LOG"
    assert_output "0"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — `_open_and_merge_pr: command not found`.

- [ ] **Step 3: Implement**

Insert after `_publish_branch`:

```bash
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
```

Note for the stub test above: the fake `gh`'s `pr checks` branch ignores `--json`/`--jq` and just cats the canned result file directly (the stub owns its own output contract — it doesn't need to replicate real `gh`'s JSON filtering, only to return the same three strings `_open_and_merge_pr` branches on).

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: PASS (10 tests).

- [ ] **Step 5: Lint and commit**

```bash
mise run lint-sh
git add claude/plugin/publish-sync.sh tests/bats/tools/claude_plugin_publish_sync.bats
git commit -m "feat(claude-plugin): publish-sync.sh — gh stub + _open_and_merge_pr"
```

---

### Task 6: `_publish_manifest_diff` orchestrator + `--dry-run`

**Files:**
- Modify: `claude/plugin/publish-sync.sh`
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`

**Interfaces:**
- Consumes: `_manifest_diff_exists`, `_build_publish_commit`, `_publish_branch`, `_open_and_merge_pr`; a global `DRY_RUN` (`0`/`1`) set by the caller before invoking.
- Produces: `_publish_manifest_diff <repo_dir> <label> <file...>` — fetches `origin`, no-ops if there's no diff, prints the diff and returns without side effects when `DRY_RUN=1`, otherwise runs the full build→branch→PR→merge pipeline. Returns the pipeline's exit status.

- [ ] **Step 1: Write the failing test**

Append:

```bash
@test "_publish_manifest_diff no-ops when there is nothing to publish" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    DRY_RUN=0

    run _publish_manifest_diff "$REPO" "public" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    assert_output --partial "변경 없음"
}

@test "_publish_manifest_diff --dry-run prints the diff without pushing or opening a PR" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    _install_gh_stub
    DRY_RUN=1

    run _publish_manifest_diff "$REPO" "public" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    assert_output --partial "anthropic-agent-skills"
    run grep -c "^pr create" "$GH_STUB_LOG"
    assert_output "0"
}

@test "_publish_manifest_diff publishes end-to-end when there is a diff" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    _install_gh_stub
    DRY_RUN=0

    run _publish_manifest_diff "$REPO" "public" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    run grep -c "^pr create" "$GH_STUB_LOG"
    assert_output "1"
    run grep -c "^pr merge.*--admin" "$GH_STUB_LOG"
    assert_output "1"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — `_publish_manifest_diff: command not found`.

- [ ] **Step 3: Implement**

Insert after `_open_and_merge_pr`:

```bash
# _publish_manifest_diff <repo_dir> <label> <file...>
#
# Fetch origin; no-op if the given paths already match origin/main;
# otherwise build+push a single snapshot commit and open+merge a PR for
# it. Honors the global DRY_RUN (0/1), which stops after printing the
# diff. Returns nonzero on any failure of the publish pipeline.
_publish_manifest_diff() {
	local repo_dir="$1" label="$2"
	shift 2

	git -C "$repo_dir" fetch origin --quiet 2>/dev/null || {
		echo "[$label] origin fetch 실패 — 건너뜀" >&2
		return 1
	}

	if ! _manifest_diff_exists "$repo_dir" "$@"; then
		echo "[$label] 변경 없음 — 할 일 없음"
		return 0
	fi
	echo "[$label] 변경 감지됨"

	if [ "${DRY_RUN:-0}" -eq 1 ]; then
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
	_open_and_merge_pr "$repo_dir" "$branch"
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: PASS (13 tests).

- [ ] **Step 5: Lint and commit**

```bash
mise run lint-sh
git add claude/plugin/publish-sync.sh tests/bats/tools/claude_plugin_publish_sync.bats
git commit -m "feat(claude-plugin): publish-sync.sh — _publish_manifest_diff orchestrator"
```

---

### Task 7: `_cleanup_local_main_if_pure_sync`

**Files:**
- Modify: `claude/plugin/publish-sync.sh`
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`

**Interfaces:**
- Consumes: `SYNC_MSG`.
- Produces: `_cleanup_local_main_if_pure_sync <repo_dir> <before_origin_sha> <file...>` — after a successful publish, re-fetches `origin` and, only if every commit `main` was ahead of `before_origin_sha` by is a `SYNC_MSG` commit touching exactly the given files, fast-forwards local `main` to the new `origin/main` (`merge --ff-only` if `main` is checked out, otherwise a plain `update-ref`). Otherwise leaves `main` untouched and prints a manual-reconcile message.

- [ ] **Step 1: Write the failing test**

Append:

```bash
@test "_cleanup_local_main_if_pure_sync fast-forwards when every ahead commit is a pure sync commit" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    BEFORE_ORIGIN=$(git -C "$REPO" rev-parse origin/main)

    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"

    # simulate the publish having landed on origin already
    git -C "$TEST_TEMP_HOME/origin.git" update-ref refs/heads/main "$(git -C "$REPO" rev-parse HEAD)"

    run _cleanup_local_main_if_pure_sync "$REPO" "$BEFORE_ORIGIN" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    assert_output --partial "정리했습니다"
    run git -C "$REPO" rev-parse main
    assert_output "$(git -C "$TEST_TEMP_HOME/origin.git" rev-parse refs/heads/main)"
}

@test "_cleanup_local_main_if_pure_sync skips when an unrelated commit is mixed in" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    BEFORE_ORIGIN=$(git -C "$REPO" rev-parse origin/main)

    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    echo "unrelated change" >"$REPO/README.md"
    git -C "$REPO" add README.md
    git -C "$REPO" commit -q -m "docs: unrelated"
    LOCAL_HEAD=$(git -C "$REPO" rev-parse HEAD)

    run _cleanup_local_main_if_pure_sync "$REPO" "$BEFORE_ORIGIN" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    assert_output --partial "정리를 건너뜁니다"
    run git -C "$REPO" rev-parse main
    assert_output "$LOCAL_HEAD"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — `_cleanup_local_main_if_pure_sync: command not found`.

- [ ] **Step 3: Implement**

Insert after `_publish_manifest_diff`:

```bash
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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: PASS (15 tests).

- [ ] **Step 5: Wire cleanup into the orchestrator, lint, commit**

In `_publish_manifest_diff`, capture the pre-fetch `origin/main` SHA and call cleanup after a successful merge:

```bash
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

	if [ "${DRY_RUN:-0}" -eq 1 ]; then
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
```

Update the Task 6 end-to-end test (`_publish_manifest_diff publishes end-to-end when there is a diff`) to also assert cleanup ran — add after the existing assertions:

```bash
    assert_output --partial "정리했습니다"
```

Run: `mise run lint-sh && ./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: both clean/PASS (15 tests).

```bash
git add claude/plugin/publish-sync.sh tests/bats/tools/claude_plugin_publish_sync.bats
git commit -m "feat(claude-plugin): publish-sync.sh — post-merge local main cleanup"
```

---

### Task 8: Main entrypoint (dual-repo) + `claude-help` + `AGENTS.md`

**Files:**
- Modify: `claude/plugin/publish-sync.sh`
- Modify: `shell-common/functions/ai_tools_help.sh:89-92` (`_claude_help_rows_plugin`)
- Modify: `claude/AGENTS.md:103-104` (Plugin Manifest section)
- Test: `tests/bats/tools/claude_plugin_publish_sync.bats`, `tests/bats/functions/claude_help_plugin.bats`

**Interfaces:**
- Consumes: `_publish_manifest_diff`.
- Produces: running `claude/plugin/publish-sync.sh [--dry-run]` directly publishes `$HOME/dotfiles` always, and `$HOME/dotfiles/claude/plugin/company` only when `claude/plugin/company/.git` exists — matching the exact guard `claude/hooks/plugin-sync.sh` already uses.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bats/tools/claude_plugin_publish_sync.bats`:

```bash
@test "running the script end-to-end publishes only the public repo when company/ has no .git" {
    mkdir -p "$TEST_TEMP_HOME/dotfiles"
    _seed_repo_with_origin "$TEST_TEMP_HOME/dotfiles"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$TEST_TEMP_HOME/dotfiles/claude/plugin/marketplaces.json"
    git -C "$TEST_TEMP_HOME/dotfiles" add claude/plugin/marketplaces.json
    git -C "$TEST_TEMP_HOME/dotfiles" commit -q -m "chore(claude-plugin): sync manifest"
    _install_gh_stub

    run bash "$PUBLISH_SYNC"
    assert_success
    assert_output --partial "[public] 변경 감지됨"
    refute_output --partial "[company]"
}

@test "running the script end-to-end also publishes company/ when it has its own .git" {
    mkdir -p "$TEST_TEMP_HOME/dotfiles"
    _seed_repo_with_origin "$TEST_TEMP_HOME/dotfiles"
    _seed_repo_with_origin "$TEST_TEMP_HOME/dotfiles/claude/plugin/company"
    echo '{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}' \
        >"$TEST_TEMP_HOME/dotfiles/claude/plugin/company/claude/plugin/marketplaces.json"
    # _seed_repo_with_origin always seeds under claude/plugin/ inside the repo
    # it's given — for company/ that's an extra nesting level we don't want,
    # so move the seeded files up to the repo root instead.
    mv "$TEST_TEMP_HOME/dotfiles/claude/plugin/company/claude/plugin/marketplaces.json" \
        "$TEST_TEMP_HOME/dotfiles/claude/plugin/company/marketplaces.json"
    mv "$TEST_TEMP_HOME/dotfiles/claude/plugin/company/claude/plugin/plugins.json" \
        "$TEST_TEMP_HOME/dotfiles/claude/plugin/company/plugins.json"
    rm -rf "$TEST_TEMP_HOME/dotfiles/claude/plugin/company/claude"
    git -C "$TEST_TEMP_HOME/dotfiles/claude/plugin/company" add -A
    git -C "$TEST_TEMP_HOME/dotfiles/claude/plugin/company" commit -q -m "chore(claude-plugin): sync manifest"
    _install_gh_stub

    run bash "$PUBLISH_SYNC"
    assert_success
    assert_output --partial "[company] 변경 감지됨"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats`
Expected: FAIL — running the script exits 1 with the Task-1 placeholder message.

- [ ] **Step 3: Wire the main entrypoint**

Replace the placeholder block at the bottom of `claude/plugin/publish-sync.sh`:

```bash
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	command -v gh >/dev/null 2>&1 || {
		echo "gh CLI가 필요합니다." >&2
		exit 1
	}
	DRY_RUN=0
	[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

	MAIN_ROOT="$HOME/dotfiles"
	PRIV_DIR="$MAIN_ROOT/claude/plugin/company"
	RC=0

	_publish_manifest_diff "$MAIN_ROOT" "public" \
		claude/plugin/marketplaces.json claude/plugin/plugins.json || RC=1

	if [ -d "$PRIV_DIR/.git" ]; then
		_publish_manifest_diff "$PRIV_DIR" "company" \
			marketplaces.json plugins.json || RC=1
	fi

	exit $RC
fi
```

- [ ] **Step 4: Register in `claude-help plugin`**

In `shell-common/functions/ai_tools_help.sh`, extend `_claude_help_rows_plugin` (currently lines 89-92):

```bash
_claude_help_rows_plugin() {
    ux_table_row "claude plugin marketplace add/remove, install/uninstall" "자동으로 claude/plugin/*.json에 동기화됨 (hook)" ""
    ux_table_row "./claude/plugin/restore.sh" "신규 PC에서 manifest 기반 일괄 재설치" ""
    ux_table_row "./claude/plugin/restore.sh --dry-run" "실행 없이 계획만 출력" ""
    ux_table_row "./claude/plugin/publish-sync.sh" "로컬에 쌓인 manifest sync 커밋을 PR로 origin에 게시" ""
    ux_table_row "./claude/plugin/publish-sync.sh --dry-run" "게시할 diff만 출력, 변경 없음" ""
}
```

Add matching assertions to `tests/bats/functions/claude_help_plugin.bats`, in the existing `"claude-help plugin shows restore.sh usage"` test (extend, don't duplicate the test):

```bash
    assert_output --partial 'claude/plugin/publish-sync.sh'
```

- [ ] **Step 5: Update `claude/AGENTS.md`**

In `claude/AGENTS.md`, replace:

```markdown
신규 PC: `./claude/plugin/restore.sh` (mode-aware, `--dry-run` 지원).
자세한 설계: `docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md`.
```

with:

```markdown
신규 PC: `./claude/plugin/restore.sh` (mode-aware, `--dry-run` 지원).

두 레포 모두 "PR을 통해서만 변경 가능" 규칙이 걸려 있어 hook의 로컬 커밋이
origin에 직접 push되지 않는다 — `./claude/plugin/publish-sync.sh`
(`--dry-run` 지원)를 수동 실행하면 쌓인 변경분을 브랜치+PR+admin-merge로
게시한다. 자세한 설계: `docs/feature/superpowers-specs/2026-07-01-claude-plugin-manifest-design.md`,
`docs/feature/superpowers-specs/2026-07-02-plugin-manifest-batch-publish-design.md`.
```

- [ ] **Step 6: Run all tests and lint**

Run: `mise run lint-sh && ./tests/bats/lib/bats-core/bin/bats tests/bats/tools/claude_plugin_publish_sync.bats tests/bats/functions/claude_help_plugin.bats`
Expected: all clean/PASS (17 + 6 tests).

- [ ] **Step 7: Commit**

```bash
git add claude/plugin/publish-sync.sh shell-common/functions/ai_tools_help.sh \
    claude/AGENTS.md tests/bats/tools/claude_plugin_publish_sync.bats \
    tests/bats/functions/claude_help_plugin.bats
git commit -m "feat(claude-plugin): publish-sync.sh 메인 엔트리포인트 + claude-help/AGENTS.md 등록"
```

---

### Task 9: Live smoke test (manual, not automated)

**Files:** none (verification only).

This repo's local `main` already carries real unpushed `chore(claude-plugin): sync manifest` commits from live testing earlier in this project — an ideal, zero-setup live smoke test target.

- [ ] **Step 1:** `./claude/plugin/publish-sync.sh --dry-run` — confirm it reports `[public] 변경 감지됨` and prints a diff matching `git diff origin/main -- claude/plugin/marketplaces.json claude/plugin/plugins.json`, with no branch pushed and no PR opened (`gh pr list --author @me` unchanged).
- [ ] **Step 2:** `./claude/plugin/publish-sync.sh` (real run) — confirm: a `chore/plugin-sync-publish-public-*` branch appears on `origin`, a PR opens, `gh pr checks` is polled (watch the script's own progress output), and the PR merges via `gh pr merge --admin` once checks pass.
- [ ] **Step 3:** Confirm the real `gh pr checks --json bucket` field/value shapes match what Task 5's `_open_and_merge_pr` expects (`pass`/`fail`/`pending`/etc.) — this was flagged as an open question in the design spec (admin-merge-vs-check-wait interaction) and can only be confirmed against the real API. Adjust the `--jq` expression in `_open_and_merge_pr` if the real values differ, and add a regression bats case for whatever shape was actually wrong.
- [ ] **Step 4:** Confirm local `main` fast-forwarded to the new `origin/main` afterward (`git log --oneline -3`, `git status --short` clean).
- [ ] **Step 5:** If an internal PC with `claude/plugin/company/.git` is available, repeat steps 1-4 for the company/ repo to confirm the GHES path works identically.

---

## Self-Review Notes

- **Spec coverage:** diff-only-final-state publish (✅ Tasks 2-3, 6), multi-repo generalization via directory-parameterized function (✅ Task 8), self-authored admin-merge reusing the `gh-pr-approve` pattern (✅ Task 5), check-wait before merge (✅ Task 5), post-merge safe local cleanup with mixed-commit guard (✅ Task 7), `--dry-run` (✅ Task 6), `claude-help`/`AGENTS.md` registration (✅ Task 8), never touching the real working tree/index/HEAD (✅ Task 3, asserted directly in its test). The two spec Open Questions (admin-merge-vs-checks interaction, GHES ruleset presence) are both carried into Task 9 rather than silently dropped.
- **Placeholder scan:** no TBD/TODO; every step has complete, runnable code.
- **Type/name consistency checked:** `_repo_target`, `_manifest_diff_exists`, `_build_publish_commit`, `_publish_branch`, `_open_and_merge_pr`, `_publish_manifest_diff`, `_cleanup_local_main_if_pure_sync` — each name and its exact argument order stays identical from its introducing task through every later call site (Tasks 6-8).
