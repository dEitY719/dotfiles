# write:insight — help

## Usage

```
/write:insight [topic-hint]
/write-insight [topic-hint]
```

## Arguments

- `topic-hint` (optional) — a phrase anchoring which insight from the
  current chat to capture. If omitted, the skill scans recent turns and
  proposes 1–3 candidates for you to pick.

## What it does

Archives one reusable insight from the current conversation as a short
Korean note in `<repo-root>/docs/learnings/<slug>.md`, following the
repo's README-defined template (5 sections, 50–80 lines, source links to
PR / commit / file:line). Also updates `docs/learnings/README.md` index.

## Examples

```
/write:insight                       # propose candidates from recent chat
/write:insight upstream short        # focus on the %(upstream:short) finding
/write:insight gh deprecation        # focus on the gh CLI deprecation workaround
```

## Related skills

- `write-blog-dev-learnings` — narrative "삽질" blog posts in `~/para/archive/`
- `write-rca-doc` — formal RCA / postmortem (Jekyll)
- `write-task-history` — JIRA / PR description drafting from session work

If your intent matches one of those, use that skill instead — write:insight
is for short, repo-internal technical patterns aimed at human teammates.

## Refuses to write

See `references/routing.md`. Topics belonging in `docs/technic/`,
`docs/standards/`, `docs/feature/<name>/`, `claude/skills/`, or `memory/`
are routed to the correct home instead of forced into `docs/learnings/`.
