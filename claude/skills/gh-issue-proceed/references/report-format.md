# gh:issue-proceed — Reporting (Step 4)

## Per-step audit (always)

| # | Step | Result | Classification | Verb applied | Duration |
|---|---|---|---|---|---|
| 1 | help | PASS | PASS | continue | 4s |
| 2 | stock list 1 10 | FAIL-CLI | FAIL-CLI | file_issue: #NN | 12s |
| ... | | | | | |

## Write-action audit

```markdown
### Write actions executed
| # | Action | Target | Triggered by step | Triggered by rule |
|---|---|---|---|---|

### Blocked attempts
(none) | <list>

### Aborts
(none) | reason: <layer-N pattern>
```

## Done-criteria reconciliation

Compare the §done_criteria checklist to actual step outcomes. Any unchecked
item lists the reason (`step skipped: SKIP-NET`, `ambiguous match`, etc.).

## Outcome

| All done + no abort | Partial | Abort |
|---|---|---|
| `close_issue: <self>` + final comment | keep-open + final comment `N/M criteria met` | keep-open + final comment `[aborted] <layer> <pattern>` |

## ai-metrics

Appended after the report (omit entirely when `GH_DISABLE_AI_METRICS=1`):

```
[ai-metrics:gh-issue-proceed] ~{ELAPSED} min — write actions: {N}, blocked: {M}
```

The proceed issue thread is the single audit surface: the per-step table,
the write-action audit, and the done-criteria reconciliation together let a
human reconstruct exactly what the skill did and why, without re-reading
the transcript.
