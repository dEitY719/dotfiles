# devx:ai-context — Report Template

Use this template for every action. Fields marked `…` are populated by the
caller. Always end with a `Next:` line.

```
## devx:ai-context — <action>
File:     <resolved-path>
Kind:     <agents|claude|gemini>
Baseline: <industry-baseline.md snapshot date>

| # | Check                       | Result | Notes                              |
|---|-----------------------------|--------|------------------------------------|
| C1    | Role / Purpose          | PASS   | …                                  |
| C2    | Operational Commands    | PASS   | …                                  |
| C3    | Loading & Scope Model   | WARN   | …                                  |
| C4    | Modular References      | PASS   | …                                  |
| C5    | Naming Conventions      | PASS   | …                                  |
| C6    | Constraints / Rules     | PASS   | …                                  |
| C7    | Size / Context Budget   | PASS   | <N> lines — within limit           |
| A-…1  | <adapter check 1>       | PASS   | …                                  |
| A-…2  | <adapter check 2>       | WARN   | …                                  |
| …                                                                              |

Verdict: [OK] X/Y passed (Z warnings)        # or [FAIL] when any check fails

Issues & Improvements
  - FAIL: <Check> — <quote> → <fix>
  - WARN: <Check> — <quote> → <fix>

Next: <fix highest-FAIL first | run check after create | verify after refactor>
```

## Verdict rules

- All checks PASS → `[OK]`.
- Any FAIL → `[FAIL]`.
- WARN-only → `[OK]` with warning count surfaced.

## Issues section

- Include only WARN and FAIL entries.
- Quote actual lines from the target file when describing problems.
- Reference `industry-baseline.md` when rationale comes from external spec.

## Next-action hints

| Action / Result            | Suggested next                                              |
|----------------------------|-------------------------------------------------------------|
| `check` with FAIL          | Fix highest-FAIL check; re-run `devx:ai-context check`      |
| `check` with WARN only     | Address WARN items at convenience; document why if accepted |
| `check` all PASS           | Re-run after any structural change                          |
| `create` complete          | Run `devx:ai-context check` to audit the new file           |
| `refactor` complete        | Run `devx:ai-context check`; verify nested files load       |
