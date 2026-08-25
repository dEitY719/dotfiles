# gh:issue-create — Dependency Auto-detect (Step 2.6 + Step 4.5)

Detail companion to SKILL.md Step 2.6 (detect) and Step 4.5 (link).
The skill scans the conversation for an explicit *선행 이슈* statement and,
after the new issue exists, wires it up with GitHub's **native Issue
Dependencies** (`addBlockedBy`) so the web UI shows `Blocked by #N` in the
sidebar and the state can never drift from the referenced issue's real state.

Native dependencies were chosen over a `blocked-by-13` label (nobody owns
removing it when `#13` closes) and over making the `Depends on #13` body line
this repo already uses the *only* channel — a plain-text trailer cannot be
queried the way GitHub's own dependency graph can. Both alternatives and their
rejection reasons are recorded in issue #1424.

The trailer is not hypothetical here, so the two channels now coexist:
`references/templates/feat.md` still tells Step 3 to write `Depends on #N`
under `## Dependencies`, and [[gh-issue-implement]] (`references/claim.md`
Step 3.5) and [[gh-issue-proceed]] (`references/claim.md` Step 2.1.5) both
grep issue bodies for that exact line. Those two guards read the body only —
a native link created here is invisible to them, and a trailer written by
Step 3 is not linked natively. Reconciling the two is out of v1 scope.

`Issue.blockedBy` / `Issue.blocking` and the `addBlockedBy` /
`removeBlockedBy` mutations are available on `github.com` and on GHES 3.19+,
so the step works on either host without a capability probe.

## Step 2.6 — Detection (F-1)

Skip entirely when `--no-auto-deps` **or** `DISCUSSION_MODE=1` is set —
Discussions have no dependency graph. `--no-auto-deps` skips detection *and*
therefore Step 4.5, mirroring how `--no-auto-labels` short-circuits Step 2.5.

These phrases mark a dependency. Korean forms trail the reference, English
forms lead it, and matching is case-insensitive:

| Trigger | Example |
|---|---|
| `#N (완료\|해결)(후\|뒤\|되면\|하고\|하면)` | `#13 완료 후에 진행`, `#13 완료되면`, `#13 해결 후` |
| `#N 이후` | `#13 이후에 재확인` |
| `선행 이슈 #N` | `선행 이슈: #13`, `선행이슈 #13` (colon optional, full-width `：` also matches) |
| `depends on #N` | `This depends on #13` |
| `blocked by #N` | `blocked by #13` |

The 완료/해결 row enumerates conjugations rather than matching a loose
`#N .* 후`: the reference and the trigger word must stay adjacent, or
`#13 참고. 검토 후 진행` would link `#13` to an unrelated clause.

A plain mention is **not** a trigger — `#13 참고`, `#13 관련`, and a bare
`#13` all yield nothing. That asymmetry is the whole point: an auto-linked
false positive is worse than a missed link, because it silently blocks the
new issue in the dispatcher's view.

The reference regex keeps the `owner/repo` prefix optional:

```
([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#[0-9]+
```

so a cross-repo reference is *recognised* and then rejected (NF-2) rather
than being mistaken for the same-numbered issue in `$TARGET_REPO`:

```
dependency-detect: cross-repo dependency detected but not supported in v1 — skip (owner/repo#13)
```

Stash the surviving numbers (ascending, de-duped) as `DEP_NUMS` for Step 4.5.
Detection touches no GitHub state — its only outputs are `DEP_NUMS` and the
NF-2 stderr line above — so it is safe to run before the issue exists.

Detection ends in `grep`, which exits 1 when the conversation names no
dependency at all. That is the common case, so the pipeline must absorb it:
under a caller's `set -e` + `set -o pipefail` an unguarded exit 1 would abort
the whole issue creation over "nothing to link".

## Step 4.5 — Linking (F-2)

The new issue's number only exists after Step 4, which is why the mutation
runs here rather than inside Step 2.6. For each `N` in `DEP_NUMS`, resolve
both node ids in one round trip (aliases), then mutate:

```bash
DEP_WARNINGS=""
for N in $DEP_NUMS; do
    # Variables: $owner String!, $name String!, $new Int!, $dep Int!
    # `// ""` on both ids is what keeps a GraphQL null out of the mutation:
    # a missing issue resolves to null, and interpolating that would send the
    # literal string "null" as an ID!.
    IDS=$(GH_HOST="$TARGET_HOST" gh api graphql \
        -f owner="${TARGET_REPO%%/*}" -f name="${TARGET_REPO##*/}" \
        -F new="$NEW_NUM" -F dep="$N" \
        -f query='
          query($owner:String!, $name:String!, $new:Int!, $dep:Int!) {
            repository(owner:$owner, name:$name) {
              newIssue: issue(number:$new) { id }
              depIssue: issue(number:$dep) { id }
            }
          }' --jq '(.data.repository // {}) |
                   "\(.newIssue.id // "") \(.depIssue.id // "")"') || IDS=""

    _new_id="${IDS%% *}"
    _dep_id="${IDS##* }"
    _rc=1
    if [ -n "$_new_id" ] && [ -n "$_dep_id" ]; then
        # Variables: $issueId ID!, $blockedById ID!
        GH_HOST="$TARGET_HOST" gh api graphql \
            -f issueId="$_new_id" -f blockedById="$_dep_id" \
            -f query='
              mutation($issueId:ID!, $blockedById:ID!) {
                addBlockedBy(input:{issueId:$issueId, blockedByIds:[$blockedById]}) {
                  issue { number }
                }
              }' >/dev/null 2>&1 && _rc=0
    fi

    # NF-1: one warning per failed N, on stderr *and* stacked for Step 5.
    # Emitting only to stderr would lose it — Step 5's report is the artifact
    # the operator actually reads.
    if [ "$_rc" -ne 0 ]; then
        _w="[WARN] Blocked by #${N} 링크 실패 — GH UI에서 수동 추가 필요"
        printf '%s\n' "$_w" >&2
        DEP_WARNINGS="${DEP_WARNINGS}${_w}
"
    fi
done
```

`$DEP_WARNINGS` is what Step 5 prepends to its verdict line
(`references/report-template.md`). An empty value means every `N` linked.

Aliasing both lookups into one query keeps this at 2 round trips per `N`.
Batching every `N` into a single `blockedByIds` list would cut it further,
but NF-1 promises a per-`N` warning line and one bad number must not reject
its siblings — so the per-`N` mutation stays.

`GH_HOST` is mandatory here for the same reason it is on every other `gh`
call in this skill (#1403): the GraphQL endpoint is chosen by host, and a
dual-host login otherwise resolves node ids on the wrong server — where the
query succeeds and returns ids for a stranger's issues.

## Failure handling (NF-1)

The issue already exists by the time Step 4.5 runs, so nothing here is
allowed to abort. Any failure — missing permission, network error, a
`DEP_NUMS` entry that does not exist, a null node id, a rejected mutation,
or a host whose schema has no `addBlockedBy` at all — takes the same path:
one stderr line, one line stacked into `$DEP_WARNINGS` for the Step 5 report.

```
[WARN] Blocked by #<N> 링크 실패 — GH UI에서 수동 추가 필요
```

Never retry, never fall back to a label or a body trailer: a half-applied
dependency the operator cannot see is worse than a visible warning.

That one path is also why the availability claim above needs no capability
probe. If a target's schema turns out not to expose `addBlockedBy`, the
mutation is rejected and the operator gets the warning — the same outcome a
probe would produce, minus a round trip on every run.

Known non-error cause of that warning: GitHub's own replication lag. The new
issue is seconds old when its node id is queried, and a read can miss it.
The result is a warning, not a wrong link, and the fix stays manual — a retry
loop here would contradict the never-retry rule above and delay the report
for the one case the operator can resolve in two clicks.

## Out of v1 scope

- Adding or removing a dependency on an **existing** issue — a separate
  command, tracked separately.
- Cross-repo (`owner/repo#N`) dependencies — detected, warned, skipped.
- The consumer side (a dispatcher gating on `blockedBy`) — different repo.

## Test fixture

Detection **and** the Step 4.5 outcome classification are mirrored in
`tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh`, locked by
`tests/bats/skills/gh_issue_create_dependency_detect.bats`. That fixture's
header carries the sync rule for trigger-phrase changes.

What the suite covers: the trigger matrix, the plain-mention negatives, the
NF-2 cross-repo skip, `--no-auto-deps`, and every id/mutation state that
produces (or suppresses) the NF-1 warning. A drift guard asserts that the
reference regex printed in this doc is byte-identical to the fixture's, so
editing one without the other turns the suite red.

What it does not cover: the two GraphQL invocations themselves —
mocking `gh` would test the mock. Everything that decides what happens
*around* them is fixtured, which is where the branching lives.
