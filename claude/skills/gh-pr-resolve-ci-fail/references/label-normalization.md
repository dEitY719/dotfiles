# gh:pr-resolve-ci-fail — Label Normalization

F-7 SSOT: variant inputs that the operator (or a typo-prone teammate)
might pass via `--label-variant <input>` map to the canonical GitHub
label `CI fail`. The skill uses this table to:

1. Reject obviously-wrong inputs (`bug`, `enhancement`, etc.) up front
   with a fail-fast message that prints the canonical name and table.
2. Tolerate case / spacing / common typos without forcing the user to
   memorize the exact label string.

## Variant → Canonical

| Input variant | Canonical |
|---|---|
| `CI fail` | `CI fail` |
| `ci fail` | `CI fail` |
| `CI Fail` | `CI fail` |
| `ci-fail`, `CI-fail`, `CI-Fail` | `CI fail` |
| `ci_fail`, `CI_fail`, `CI_Fail` | `CI fail` |
| `CI fial`, `ci fial`, `CI Fial` (typo: `fial` ↔ `fail`) | `CI fail` |
| `CI failed`, `ci failed` (past tense slip) | `CI fail` |
| `ci/fail`, `CI/fail` (slash) | `CI fail` |

## Lookup procedure

1. Lower-case the input, strip leading/trailing whitespace.
2. Replace `-`, `_`, `/` with a single space.
3. Collapse runs of whitespace to one space.
4. Match against the lower-cased canonical form `ci fail`.
5. Apply the typo carveout: replace `fial` → `fail` once before matching.
6. Past-tense carveout: trim trailing `ed` once before matching.

If steps 1-6 produce `ci fail` → canonical = `CI fail`. Otherwise →
fail-fast.

## Fail-fast message

```
[FAIL] unknown label-variant '<input>' — expected one of the variants below.
Canonical label: CI fail

Accepted variants:
  CI fail, ci fail, CI Fail
  ci-fail, ci_fail, ci/fail (and case variations)
  CI fial (typo), CI failed (past tense)

Pass --label-variant '<variant>' or omit the flag to use 'CI fail'.
```

## Why a separate file (not inline in SKILL.md)

The table is content (data), not workflow (procedure). Progressive
Disclosure (skill:check Check 2) says workflow phases stay in SKILL.md
and detail moves to `references/`. The table will also grow over time
as new variants appear in the wild — keeping it here means SKILL.md
doesn't churn for label-name additions.

## Future: external SSOT yaml

Open Question from issue #673: should this table move to
`.gh-pr-labels.yml` at the repo root so AgentToolbox / dotfiles / etc.
can each declare their own label conventions? Defer until a second
repo with different label naming actually appears. KISS — internal
table is fine for v1.
