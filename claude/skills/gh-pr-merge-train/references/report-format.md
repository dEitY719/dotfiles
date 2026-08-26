# gh:pr-merge-train — Final report (F-9)

Always printed, including when the run ended early or merged nothing. Plain
assistant text — never a `Bash` heredoc, never `Write` (#1270).

## Format

```
== merge train: <owner/repo> ==
queue: <n> PR(s)  ·  approval gate: <on|off>  ·  quiet period: 11m

[MERGED]  #1466  refactor(issue-watcher): simplify   (BEHIND -> resolve-outdated -> merged)
[MERGED]  #1467  fix(gh-pr-reply): ...               (CLEAN -> merged)
[SKIPPED] #1462  test(issue-watcher): ...            checks still running (3 polls)
[FAILED]  #1469  feat(x): ...                        conflict unresolved after 3 attempts

merged 2 · skipped 1 · failed 1
```

Rules:

- **One line per PR**, in the order the train processed them — not the order
  `gh pr list` returned them. The processing order is itself information (D-2).
- Every non-`[MERGED]` line **must carry a reason**. `[SKIPPED] #1462` with no
  reason is a bug in the report, not a terse style.
- `[MERGED]` lines name the **route taken**, so a reader can tell a PR that
  merged straight through from one that needed two remediations.
- PRs excluded before the queue was built (drafts, inside the quiet period, not
  `--author @me`) are **not** listed — they were never candidates. Mention them
  only as a count, if at all.

## Status vocabulary

| Status | Meaning | Typical reason |
|---|---|---|
| `[MERGED]` | the PR is merged | — |
| `[SKIPPED]` | not merged, **and expected to be retriable** next tick | `checks still running`, `mergeability still UNKNOWN`, `approval required`, `BLOCKED: <rule>`, `draft` |
| `[FAILED]` | not merged, **and something actually went wrong** | `conflict unresolved after 3 attempts`, `gh:pr-merge failed: <message>`, `CI fix failed after 3 attempts` |

The `[SKIPPED]` / `[FAILED]` split is the load-bearing part of this output. A
cron log full of `[SKIPPED] checks still running` is a healthy train waiting on
CI; a cron log full of `[FAILED]` is a train that needs a human. Collapsing the
two would hide the second inside the first — the exact failure mode of an
unattended loop nobody reads.

## Early-exit shapes

- `gh pr list` failed → print the header, then
  `run ended: gh pr list failed — refusing to merge without knowing state`, and
  no PR lines.
- Queue empty after filtering → header plus `queue: 0 PR(s)` and
  `nothing to do`. Not an error; the dispatcher normally prevents this from
  even starting a session.
- Ruleset unreadable → the header's `approval gate:` reads
  `on (fail-closed: ruleset unreadable)`, so the reason every unapproved PR was
  skipped is visible once, at the top, rather than repeated per line.
