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
| `#N 완료 후` | `#13 완료 후에 진행` |
| `#N 이후` | `#13 이후에 재확인` |
| `선행 이슈: #N` | `선행 이슈: #13` (full-width `：` also matches) |
| `depends on #N` | `This depends on #13` |
| `blocked by #N` | `blocked by #13` |

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
Detection alone never writes anything, so it is safe to run before the issue
exists.

## Step 4.5 — Linking (F-2)

The new issue's number only exists after Step 4, which is why the mutation
runs here rather than inside Step 2.6. For each `N` in `DEP_NUMS`, resolve
both node ids in one round trip (aliases), then mutate:

```bash
# Variables: $owner String!, $name String!, $new Int!, $dep Int!
IDS=$(GH_HOST="$TARGET_HOST" gh api graphql \
    -f owner="${TARGET_REPO%%/*}" -f name="${TARGET_REPO##*/}" \
    -F new="$NEW_NUM" -F dep="$N" \
    -f query='
      query($owner:String!, $name:String!, $new:Int!, $dep:Int!) {
        repository(owner:$owner, name:$name) {
          newIssue: issue(number:$new) { id }
          depIssue: issue(number:$dep) { id }
        }
      }' --jq '.data.repository | "\(.newIssue.id) \(.depIssue.id)"') || IDS=""

if [ -n "$IDS" ]; then
    # Variables: $issueId ID!, $blockedById ID!
    GH_HOST="$TARGET_HOST" gh api graphql \
        -f issueId="${IDS% *}" -f blockedById="${IDS#* }" \
        -f query='
          mutation($issueId:ID!, $blockedById:ID!) {
            addBlockedBy(input:{issueId:$issueId, blockedByIds:[$blockedById]}) {
              issue { number }
            }
          }' >/dev/null || IDS=""
fi
```

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
`DEP_NUMS` entry that does not exist, a rejected mutation — emits one stderr
line and adds one line to the Step 5 report:

```
[WARN] Blocked by #<N> 링크 실패 — GH UI에서 수동 추가 필요
```

Never retry, never fall back to a label or a body trailer: a half-applied
dependency the operator cannot see is worse than a visible warning.

## Out of v1 scope

- Adding or removing a dependency on an **existing** issue — a separate
  command, tracked separately.
- Cross-repo (`owner/repo#N`) dependencies — detected, warned, skipped.
- The consumer side (a dispatcher gating on `blockedBy`) — different repo.

## Test fixture

Detection is mirrored in
`tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh` and locked
by `tests/bats/skills/gh_issue_create_dependency_detect.bats`. That fixture's
header carries the sync rule for trigger-phrase changes. The GraphQL half is
not fixtured.
