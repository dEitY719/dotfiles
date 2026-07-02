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

@test "_build_publish_commit skips a path that does not exist on disk" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"
    git -C "$REPO" fetch origin --quiet

    run _build_publish_commit "$REPO" claude/plugin/marketplaces.json claude/plugin/nonexistent.json
    assert_success
    NEW_COMMIT="$output"

    # tree carries the edited real file's content
    run git -C "$REPO" show "${NEW_COMMIT}:claude/plugin/marketplaces.json"
    assert_output '{"anthropic-agent-skills": "anthropics/skills"}'

    # the nonexistent path was never added to the tree
    run git -C "$REPO" ls-tree -r --name-only "$NEW_COMMIT"
    refute_output --partial "claude/plugin/nonexistent.json"
}

@test "_publish_branch creates a timestamped branch and pushes it to origin" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" fetch origin --quiet
    COMMIT=$(_build_publish_commit "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json)

    run _publish_branch "$REPO" "public" "$COMMIT"
    assert_success
    BRANCH="$output"

    run echo "$BRANCH"
    assert_output --regexp '^chore/plugin-sync-publish-public-[0-9]{8}-[0-9]{6}$'

    # the branch exists on the bare "origin" with the right commit
    run git -C "$TEST_TEMP_HOME/origin.git" rev-parse "refs/heads/$BRANCH"
    assert_output "$COMMIT"
}

@test "_publish_branch fails when the push to origin fails" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" fetch origin --quiet
    COMMIT=$(_build_publish_commit "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json)

    # break origin: point it at a local path that is not a git repo at all,
    # so the push fails fast without touching the network.
    git -C "$REPO" remote set-url origin "$TEST_TEMP_HOME/does-not-exist.git"

    run _publish_branch "$REPO" "public" "$COMMIT"
    assert_failure
}

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
    # Set up origin remote as a proper URL format for _repo_target parsing
    git -C "$REPO" remote set-url origin "https://github.com/owner/repo.git"
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
    # Set up origin remote as a proper URL format for _repo_target parsing
    git -C "$REPO" remote set-url origin "https://github.com/owner/repo.git"
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
    # Set up origin remote as a proper URL format for _repo_target parsing
    git -C "$REPO" remote set-url origin "https://github.com/owner/repo.git"
    _install_gh_stub
    echo "pending" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_failure
    run grep -c "^pr merge" "$GH_STUB_LOG"
    assert_output "0"
}

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
    _install_gh_stub

    # Re-point origin's stored URL to a parseable GitHub URL, and redirect the
    # actual transport back to the local bare repo via insteadOf so fetch/push
    # stay offline. _repo_target sees owner/repo; git I/O hits the bare repo.
    BARE=$(git -C "$REPO" remote get-url origin)
    git -C "$REPO" remote set-url origin "https://github.com/dEitY719/dotfiles.git"
    git -C "$REPO" config "url.${BARE}.insteadOf" "https://github.com/dEitY719/dotfiles.git"

    # sanity: config --get returns the raw parseable URL (insteadOf never
    # applied to config --get, unlike `remote get-url` which rewrites it).
    run git -C "$REPO" config --get remote.origin.url
    assert_output "https://github.com/dEitY719/dotfiles.git"

    # create a manifest diff vs origin/main
    echo '{"anthropic-agent-skills": "anthropics/skills"}' >"$REPO/claude/plugin/marketplaces.json"
    git -C "$REPO" add claude/plugin/marketplaces.json
    git -C "$REPO" commit -q -m "chore(claude-plugin): sync manifest"

    DRY_RUN=0
    run _publish_manifest_diff "$REPO" "public" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success

    # full pipeline ran: PR created + admin-merged (assert via the gh stub log)
    run grep -c "^pr create" "$GH_STUB_LOG"
    assert_output "1"
    run grep -c "^pr merge.*--admin" "$GH_STUB_LOG"
    assert_output "1"

    # the branch really landed on the (offline) bare origin
    run bash -c "git -C '$BARE' for-each-ref --format='%(refname)' 'refs/heads/chore/plugin-sync-publish-public-*' | wc -l"
    assert_output "1"
}
