# gh:issue-proceed — Protocol schema (Step 2.2)

The issue body must contain **8 required sections**, each identified by an
H2 or H3 heading whose normalized text matches one of the listed aliases
(case-insensitive substring; alias list per row is OR). SSOT for the
schema validator; the bats fixture
`tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh` mirrors this and
the suite `gh_issue_proceed_schema.bats` exercises five variants.

## 1. Required sections

**"Empty" definition** (used uniformly): section content under 50 chars
after stripping leading/trailing whitespace, markdown list markers
(`-`, `*`, `1.`), and code-fence delimiters.

| # | Key | Aliases | Failure rule |
|---|---|---|---|
| 1 | `goal` | `Goal`, `목표` | fail if empty |
| 2 | `preconditions` | `Preconditions`, `사전 조건`, `Prerequisites` | fail if empty |
| 3 | `execution_protocol` | `Execution Protocol`, `Execution Matrix`, `실행 절차`, `Steps` | fail if empty **or** no parseable steps (§3) |
| 4 | `decision_rules` | `Decision Rules`, `결정 규칙`, `Branching`, `Decision matrix` | fail if empty |
| 5 | `deliverables` | `Deliverables`, `산출물`, `Output`, `Outputs` | fail if empty |
| 6 | `done_criteria` | `Done Criteria`, `종료 조건`, `Acceptance`, `Acceptance Criteria` | fail if no `- [ ]` / `- [x]` checklist item |
| 7 | `out_of_scope` | `Out of Scope`, `Out-of-scope`, `범위 밖` | fail if empty |
| 8 | `safety` | `Safety`, `Safety / Abort`, `Abort`, `안전 규칙`, `Safety Rules` | fail if empty |

## 2. Recommended (optional, parsed if present)

- `background` — context.
- `references` — external links.
- `track` — explicit `verify-only` declaration that overrides mutation
  auto-detection (`references/preconditions.md`).

## 3. Step parsing in `execution_protocol`

Two formats, auto-detected:

| Format | Trigger | Result |
|---|---|---|
| **Matrix mode** | a markdown table whose header row contains `#`, `Workflow`/`Step`, and `Command`/`명령` | one parsed step per data row |
| **Numbered mode** | `^### \d+\.` or `^\d+\.` lines | one parsed step per numbered block until the next sibling heading |

Both normalize into the same record:
`{index, description, command_block_or_text, expected_outcome}`.

## 4. Validation failure output

```
gh:issue-proceed #<N> schema validation failed
  Missing required sections:
    - <key>  (aliases tried: ...)
  Empty required sections:
    - <key>  (heading present, content < 50 chars)
  Unparseable sections:
    - execution_protocol  (no matrix table and no numbered steps found)
  Fix the issue body to satisfy the directive schema, then retry.
  Reference: <repo>/docs/feature/gh-issue-proceed-skill/design.md §3
```

No comment is posted on the issue itself — schema failure is a caller-side
problem, and writing to a malformed directive risks acting on garbage.
