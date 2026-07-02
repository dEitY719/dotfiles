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
    assert_output "github.com/dEitY719/dotfiles"
}

@test "_repo_target parses https form on a GHES host" {
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin "https://github.samsungds.net/byoungwoo-yoon/claude-plugin-jira.git"

    run _repo_target "$REPO"
    assert_success
    assert_output "github.samsungds.net/byoungwoo-yoon/claude-plugin-jira"
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

_commit_pure_sync_change() {
    # Write <content> to <repo_dir>/<rel_path>, stage it, and commit with the
    # canonical sync-manifest subject. Collapses the echo+add+commit trio that
    # nearly every test repeats.
    local repo_dir="$1" rel_path="$2" content="$3"
    printf '%s\n' "$content" >"$repo_dir/$rel_path"
    git -C "$repo_dir" add "$rel_path"
    git -C "$repo_dir" commit -q -m "chore(claude-plugin): sync manifest"
}

_route_origin_offline() {
    # Point <repo_dir>'s origin at a parseable GitHub URL (so _repo_target and
    # `gh` see a real host/owner/repo) while redirecting actual git transport to
    # the local bare repo via insteadOf — keeps the end-to-end tests fully
    # offline. `git config --get remote.origin.url` still returns the raw fake
    # URL (insteadOf is applied only at transport, not by config --get).
    local repo_dir="$1" fake_url="$2" bare_path="$3"
    git -C "$repo_dir" remote set-url origin "$fake_url"
    git -C "$repo_dir" config "url.${bare_path}.insteadOf" "$fake_url"
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
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
    git -C "$REPO" fetch origin --quiet

    run _manifest_diff_exists "$REPO" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
}

@test "_build_publish_commit snapshots current file content onto origin/main without touching the real index" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
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
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
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
    assert_output --regexp '^chore/plugin-sync-publish-public-[0-9]{8}-[0-9]{6}-[0-9]+$'

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
#   checks_result   - "success" | "failed" | "pending" | "empty" | "nochecks"
#                     | "state-success" | "state-failed" (default: success)
#   merge_result    - "success" | "failed" (default: success)
#
# The script polls via `gh pr view --json statusCheckRollup --jq ...`
# (real gh 2.45.0 has no `--json` on `gh pr checks` at all — verified
# live, see publish-sync.sh comment). The stub's `pr view` branch emits
# REAL `statusCheckRollup`-shaped JSON so the script's actual `--jq`
# aggregation expression runs and is exercised end-to-end (rather than a
# pre-aggregated string):
#   success -> CheckRun conclusion=SUCCESS   failed -> conclusion=FAILURE
#   pending -> CheckRun status=IN_PROGRESS, conclusion=null
#   state-success / state-failed -> StatusContext shape (state=SUCCESS /
#               state=FAILURE, no conclusion) to exercise that jq branch
# Two more sentinels exercise the fail-closed edges FIX 1 addresses:
#   empty    -> {"statusCheckRollup":[]} (checks not yet registered — must
#               stay "pending" until tries>=2, never premature-"success")
#   nochecks -> {"statusCheckRollup":[]} too — relies on the same
#               empty-after-retries -> "nochecks" path as "empty" (a
#               genuinely checkless repo looks identical to a not-yet-
#               registered one from `gh pr view`'s point of view)
_install_gh_stub() {
    GH_STUB_DIR="$TEST_TEMP_HOME/gh-stub"
    mkdir -p "$GH_STUB_DIR/bin"
    GH_STUB_LOG="$GH_STUB_DIR/log"
    : >"$GH_STUB_LOG"
    echo "success" >"$GH_STUB_DIR/checks_result"
    echo "success" >"$GH_STUB_DIR/merge_result"

    # Generate stub; use double quotes to expand paths, escape runtime vars
    cat >"$GH_STUB_DIR/bin/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$GH_STUB_LOG"
case "\$1 \$2" in
"pr create")
    echo "https://example.com/owner/repo/pull/42"
    exit 0
    ;;
"pr view")
    RESULT=\$(cat "$GH_STUB_DIR/checks_result")
    case "\$RESULT" in
    success) ROLLUP='[{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS","state":null}]' ;;
    failed) ROLLUP='[{"name":"CI","status":"COMPLETED","conclusion":"FAILURE","state":null}]' ;;
    pending) ROLLUP='[{"name":"CI","status":"IN_PROGRESS","conclusion":null,"state":null}]' ;;
    state-success) ROLLUP='[{"name":"ci/legacy","conclusion":null,"state":"SUCCESS"}]' ;;
    state-failed) ROLLUP='[{"name":"ci/legacy","conclusion":null,"state":"FAILURE"}]' ;;
    empty) ROLLUP='[]' ;;
    nochecks) ROLLUP='[]' ;;
    *) ROLLUP="\$RESULT" ;;
    esac
    JSON="{\\"statusCheckRollup\\":\$ROLLUP}"
    # Pull out the --jq filter the caller passed and run it for real via
    # the system jq, so the script's actual aggregation expression is
    # exercised end-to-end instead of re-implemented here.
    JQ_FILTER=""
    PREV=""
    for ARG in "\$@"; do
        if [ "\$PREV" = "--jq" ]; then
            JQ_FILTER="\$ARG"
            break
        fi
        PREV="\$ARG"
    done
    if [ -n "\$JQ_FILTER" ]; then
        echo "\$JSON" | jq -r "\$JQ_FILTER"
    else
        echo "\$JSON"
    fi
    exit 0
    ;;
"pr merge")
    if [ "\$(cat "$GH_STUB_DIR/merge_result")" = "success" ]; then
        # Simulate the merge by updating the bare repo's main to the latest
        # chore/plugin-sync-publish-* branch commit (the one just pushed).
        if [ -n "\${GH_STUB_BARE_REPO:-}" ]; then
            BRANCH=\$(git -C "\$GH_STUB_BARE_REPO" for-each-ref --format='%(refname:short)' 'refs/heads/chore/plugin-sync-publish-*' --sort=-creatordate | head -1)
            if [ -n "\$BRANCH" ]; then
                COMMIT=\$(git -C "\$GH_STUB_BARE_REPO" rev-parse "\$BRANCH")
                git -C "\$GH_STUB_BARE_REPO" update-ref refs/heads/main "\$COMMIT"
            fi
        fi
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
    GH_STUB_BARE_REPO="${GH_STUB_BARE_REPO:-}"
    export PATH PUBLISH_SYNC_CHECK_INTERVAL PUBLISH_SYNC_CHECK_MAX_TRIES GH_STUB_BARE_REPO
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

@test "_open_and_merge_pr admin-merges when checks report a StatusContext state=SUCCESS (no conclusion field)" {
    # Exercises the jq's StatusContext branch (`.state`, no `.conclusion`) —
    # e.g. legacy commit statuses, distinct from the CheckRun
    # status/conclusion branch covered by the "success" sentinel above.
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" remote set-url origin "https://github.com/owner/repo.git"
    _install_gh_stub
    echo "state-success" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_success
    run grep -c "^pr merge.*--admin" "$GH_STUB_LOG"
    assert_output "1"
}

@test "_open_and_merge_pr does not merge when a StatusContext reports state=FAILURE" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" remote set-url origin "https://github.com/owner/repo.git"
    _install_gh_stub
    echo "state-failed" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_failure
    run grep -c "^pr merge" "$GH_STUB_LOG"
    assert_output "0"
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

@test "_open_and_merge_pr never premature-merges when checks report an empty rollup array" {
    # FIX 1 (blocker): an empty `statusCheckRollup: []` (checks not yet
    # registered right after PR creation) must map to "pending" on the
    # first couple of polls, NOT fall through the jq's `else "success"`
    # branch into a premature --admin merge. With PUBLISH_SYNC_CHECK_MAX_TRIES=3
    # the empty result keeps polling as "pending" until tries>=2, at which
    # point it becomes the same terminal "nochecks" state a genuinely
    # checkless repo would hit (indistinguishable from `gh pr view`'s point
    # of view) — never a premature merge either way.
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" remote set-url origin "https://github.com/owner/repo.git"
    _install_gh_stub
    echo "empty" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_failure
    assert_output --partial "status check가 구성되지 않은 리포"
    run grep -c "^pr merge" "$GH_STUB_LOG"
    assert_output "0"
}

@test "_open_and_merge_pr hits the terminal no-checks state and does not merge on a checkless repo" {
    # FIX 1 (blocker): `gh pr checks` exiting non-zero with "no checks
    # reported" on every poll (a repo with no status checks configured at
    # all) must become a terminal "nochecks" state after a couple of
    # retries, not loop silently to the generic 5-minute timeout, and must
    # never merge.
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    git -C "$REPO" remote set-url origin "https://github.com/owner/repo.git"
    _install_gh_stub
    echo "nochecks" >"$GH_STUB_DIR/checks_result"

    run _open_and_merge_pr "$REPO" "chore/plugin-sync-publish-public-20260702-000000"
    assert_failure
    assert_output --partial "status check가 구성되지 않은 리포"
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
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
    _install_gh_stub
    DRY_RUN=1

    run _publish_manifest_diff "$REPO" "public" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    assert_output --partial "anthropic-agent-skills"
    run grep -c "^pr create" "$GH_STUB_LOG"
    assert_output "0"

    # dry-run must not push any branch to origin
    run bash -c "git -C '$TEST_TEMP_HOME/origin.git' for-each-ref --format='%(refname)' 'refs/heads/chore/plugin-sync-publish-*' | wc -l"
    assert_output "0"
}

@test "_publish_manifest_diff publishes end-to-end when there is a diff" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    BARE=$(git -C "$REPO" remote get-url origin)

    # Pass the bare repo path to the stub so it can actually perform the merge
    GH_STUB_BARE_REPO="$BARE"
    export GH_STUB_BARE_REPO

    _install_gh_stub

    # Re-point origin's stored URL to a parseable GitHub URL, and redirect the
    # actual transport back to the local bare repo via insteadOf so fetch/push
    # stay offline. _repo_target sees owner/repo; git I/O hits the bare repo.
    _route_origin_offline "$REPO" "https://github.com/dEitY719/dotfiles.git" "${BARE}"

    # sanity: config --get returns the raw parseable URL (insteadOf never
    # applied to config --get, unlike `remote get-url` which rewrites it).
    run git -C "$REPO" config --get remote.origin.url
    assert_output "https://github.com/dEitY719/dotfiles.git"

    # create a manifest diff vs origin/main
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'

    DRY_RUN=0
    run _publish_manifest_diff "$REPO" "public" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    # Local-main cleanup afterward is best-effort and its ff-only outcome is
    # not asserted here: the published commit is built independently via
    # plumbing (_build_publish_commit), so it is generally a SIBLING of
    # local main sharing before_origin as parent (fast-forward fails, loud
    # stderr — see the dedicated _cleanup_local_main_if_pure_sync tests),
    # not an ancestor. The publish pipeline's own success must not depend
    # on that outcome (`_cleanup... || true` at the call site).

    # full pipeline ran: PR created + admin-merged (assert via the gh stub log)
    run grep -c "^pr create" "$GH_STUB_LOG"
    assert_output "1"
    run grep -c "^pr merge.*--admin" "$GH_STUB_LOG"
    assert_output "1"

    # the branch really landed on the (offline) bare origin
    run bash -c "git -C '$BARE' for-each-ref --format='%(refname)' 'refs/heads/chore/plugin-sync-publish-public-*' | wc -l"
    assert_output "1"
}

@test "_cleanup_local_main_if_pure_sync moves local main via update-ref when a different branch is checked out" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    BEFORE_ORIGIN=$(git -C "$REPO" rev-parse origin/main)

    # local main advances by a pure sync commit — this is the commit
    # plugin-sync.sh's hook left locally; it can never be pushed directly
    # because of branch protection.
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'

    # move off main WITHOUT touching the main ref, mirroring a repo that is
    # not currently checked out on main when cleanup runs
    git -C "$REPO" checkout -q -b other

    # simulate the real publish pipeline landing a DIFFERENT sibling commit
    # (built independently on top of before_origin, as
    # _build_publish_commit does) on origin/main — this is the published
    # snapshot, never an ancestor/descendant of local main
    git -C "$REPO" checkout -q "$BEFORE_ORIGIN"
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills-published"}'
    PUBLISHED=$(git -C "$REPO" rev-parse HEAD)
    git -C "$REPO" push -q origin "${PUBLISHED}:refs/heads/main"
    git -C "$REPO" checkout -q other

    LOCAL_MAIN_BEFORE=$(git -C "$REPO" rev-parse main)
    assert_not_equal "$LOCAL_MAIN_BEFORE" "$PUBLISHED"

    run _cleanup_local_main_if_pure_sync "$REPO" "$BEFORE_ORIGIN" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_success
    assert_output --partial "정리했습니다"
    # a genuine move via update-ref, not a no-op and not a merge
    MAIN_SHA=$(git -C "$REPO" rev-parse main)
    assert_equal "$MAIN_SHA" "$PUBLISHED"
    assert_not_equal "$MAIN_SHA" "$LOCAL_MAIN_BEFORE"
}

@test "_cleanup_local_main_if_pure_sync leaves checked-out main untouched and fails loudly when it has diverged from origin/main" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    BEFORE_ORIGIN=$(git -C "$REPO" rev-parse origin/main)

    # local main is checked out and ahead of before_origin by a pure sync
    # commit — the real post-publish state: plugin-sync.sh's hook
    # committed locally but could never push.
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
    LOCAL_MAIN=$(git -C "$REPO" rev-parse main)

    # origin/main advances to a DIFFERENT sibling commit sharing
    # before_origin as parent — the actual publish pipeline builds this
    # independently via plumbing (_build_publish_commit), so it is never
    # an ancestor/descendant of local main: a real fast-forward is
    # impossible.
    git -C "$REPO" checkout -q "$BEFORE_ORIGIN"
    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills-published"}'
    PUBLISHED=$(git -C "$REPO" rev-parse HEAD)
    git -C "$REPO" push -q origin "${PUBLISHED}:refs/heads/main"

    # back to main, checked out, still sitting at the pre-publish local commit
    git -C "$REPO" checkout -q main
    assert_equal "$(git -C "$REPO" rev-parse HEAD)" "$LOCAL_MAIN"

    run _cleanup_local_main_if_pure_sync "$REPO" "$BEFORE_ORIGIN" claude/plugin/marketplaces.json claude/plugin/plugins.json
    assert_failure
    assert_output --partial "갈라져 fast-forward 불가"

    # local main must be left completely untouched — no reset, no rebase
    assert_equal "$(git -C "$REPO" rev-parse main)" "$LOCAL_MAIN"
}

@test "_cleanup_local_main_if_pure_sync skips when an unrelated commit is mixed in" {
    REPO="$TEST_TEMP_HOME/repo"
    _seed_repo_with_origin "$REPO"
    BEFORE_ORIGIN=$(git -C "$REPO" rev-parse origin/main)

    _commit_pure_sync_change "$REPO" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
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

@test "running the script end-to-end publishes only the public repo when company/ has no .git" {
    mkdir -p "$TEST_TEMP_HOME/dotfiles"
    _seed_repo_with_origin "$TEST_TEMP_HOME/dotfiles"
    BARE=$(git -C "$TEST_TEMP_HOME/dotfiles" remote get-url origin)

    # Pass the bare repo path to the stub so it can actually perform the merge
    GH_STUB_BARE_REPO="$BARE"
    export GH_STUB_BARE_REPO

    _commit_pure_sync_change "$TEST_TEMP_HOME/dotfiles" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
    _install_gh_stub

    # Re-point origin's stored URL to a parseable GitHub URL, and redirect the
    # actual transport back to the local bare repo via insteadOf so fetch/push
    # stay offline.
    _route_origin_offline "$TEST_TEMP_HOME/dotfiles" "https://github.com/dEitY719/dotfiles.git" "${BARE}"

    run bash "$PUBLISH_SYNC"
    assert_success
    assert_output --partial "[public] 변경 감지됨"
    refute_output --partial "[company]"
}

@test "running the script end-to-end also publishes company/ when it has its own .git" {
    mkdir -p "$TEST_TEMP_HOME/dotfiles"
    _seed_repo_with_origin "$TEST_TEMP_HOME/dotfiles"
    BARE=$(git -C "$TEST_TEMP_HOME/dotfiles" remote get-url origin)

    # Pass the bare repo path to the stub so it can actually perform the merge
    GH_STUB_BARE_REPO="$BARE"
    export GH_STUB_BARE_REPO

    # Create changes in the public repo
    _commit_pure_sync_change "$TEST_TEMP_HOME/dotfiles" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'

    _seed_repo_with_origin "$TEST_TEMP_HOME/dotfiles/claude/plugin/company"
    COMPANY_BARE=$(git -C "$TEST_TEMP_HOME/dotfiles/claude/plugin/company" remote get-url origin)

    # Create changes in the company repo
    echo '{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}' \
        >"$TEST_TEMP_HOME/dotfiles/claude/plugin/company/marketplaces.json"
    echo '{"plugins": []}' >"$TEST_TEMP_HOME/dotfiles/claude/plugin/company/plugins.json"
    git -C "$TEST_TEMP_HOME/dotfiles/claude/plugin/company" add marketplaces.json plugins.json
    git -C "$TEST_TEMP_HOME/dotfiles/claude/plugin/company" commit -q -m "chore(claude-plugin): sync manifest"
    _install_gh_stub

    # Re-point both origins' stored URLs to parseable GitHub URLs, and redirect the
    # actual transport back to the local bare repos via insteadOf so fetch/push
    # stay offline.
    _route_origin_offline "$TEST_TEMP_HOME/dotfiles" "https://github.com/dEitY719/dotfiles.git" "${BARE}"

    _route_origin_offline "$TEST_TEMP_HOME/dotfiles/claude/plugin/company" "https://github.com/dEitY719/company-plugins.git" "${COMPANY_BARE}"

    run bash "$PUBLISH_SYNC"
    assert_success
    assert_output --partial "[public] 변경 감지됨"
    assert_output --partial "[company] 변경 감지됨"
}

@test "running the script with -h/--help prints usage and exits 0 without requiring gh" {
    # -h/--help must work even without `gh` on PATH — arg parsing happens
    # before the `command -v gh` gate.
    run env PATH="/usr/bin:/bin" bash "$PUBLISH_SYNC" --help
    assert_success
    assert_output --partial "usage: publish-sync.sh"

    run env PATH="/usr/bin:/bin" bash "$PUBLISH_SYNC" -h
    assert_success
    assert_output --partial "usage: publish-sync.sh"
}

@test "running the script with an unrecognized argument exits 2 and does not publish" {
    # A typo'd flag (e.g. --dry_run instead of --dry-run) must be rejected
    # loudly rather than silently falling through to a real, irreversible
    # publish (FIX 3).
    mkdir -p "$TEST_TEMP_HOME/dotfiles"
    _seed_repo_with_origin "$TEST_TEMP_HOME/dotfiles"
    _commit_pure_sync_change "$TEST_TEMP_HOME/dotfiles" claude/plugin/marketplaces.json '{"anthropic-agent-skills": "anthropics/skills"}'
    _install_gh_stub

    run bash "$PUBLISH_SYNC" --dry_run
    assert_failure
    assert_equal "$status" 2
    assert_output --partial "알 수 없는 인자"
    refute_output --partial "[public]"
    run grep -c "^pr create" "$GH_STUB_LOG"
    assert_output "0"
}
