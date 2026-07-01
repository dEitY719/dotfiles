# gh:pr-review — Critical Review by Default (Design)

Issue: [#1057](https://github.com/dEitY719/dotfiles/issues/1057)

## Problem

`gh:pr-review` delegates a PR review to an external AI CLI using one of
five closed-enum presets (`default` / `quick` / `thorough` / `security`
/ `performance`). None of them require the reviewing AI to challenge
the PR's own assumptions — nothing stops a rubber-stamp "looks good"
response.

Three review-persona issues from a separate, unrelated repo
(`dev-team-404/AgentToolbox#1744/#1745/#1746` — frontend/UX,
backend/data, AI/authoring/governance lenses) were reviewed as
reference material. All three share a structure worth adopting: a
mandatory "point out at least one questionable assumption" clause and
a fixed overall verdict tag (`판정: [LGTM / 우려있음 / 블로킹]`). Their
per-domain lens and reading lists are specific to that repo and are
*not* adopted — only the structural pattern is.

## Decision

Bake the pattern directly into `gh:pr-review`'s **common prompt
prefix** (shared by all five presets) instead of adding new flags or
new `--review` enum values:

1. **Adversarial-stance directive** — explicitly instructs the
   reviewing AI not to rubber-stamp, and to actively look for weak
   assumptions, missing edge cases, and alternative approaches.
2. **Mandatory assumption critique** — one line identifying a
   questionable "obviously correct" assumption in the PR, or an
   explicit "none found" if genuinely absent (never silently skipped).
3. **Mandatory verdict line** — a single overall call appended after
   the per-finding list: `판정: [LGTM|우려있음|블로킹]` for
   Korean-dominant diffs, `Verdict: [LGTM|CONCERNS|BLOCKING]` for
   English-dominant diffs, reusing the existing "reply in the diff's
   dominant language" rule.

This applies uniformly to all five presets, `quick` included — since
the change lives in the shared prefix rather than any preset body,
there is no per-preset branching and no way to accidentally omit it.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| `--role "<free text>"` flag | Free-text input widens the prompt-injection surface and conflicts with the skill's closed-enum-only design (`references/constraints.md`). |
| New `frontend` / `backend` / `ai-governance` lens presets (mirroring the 3 reference issues) | Widens the enum surface for a benefit ("pick a lens") the user didn't ask for; the user explicitly wants critical review to be automatic, not something requiring a manual choice. |
| `--no-critical` opt-out flag | The user explicitly chose "always on" after being shown the trade-off (no way to get a purely-praising pass) — adding an escape hatch would undercut the point of the feature. |

## Architecture / components

No new components. `SKILL.md` Step 3 already composes
`<common-prompt-prefix> + <preset-body>`; only the prefix text in
`references/review-presets.md` changes. No parser, flag, or
`shell-common/functions/gh_pr_review.sh` changes are needed.

Touched files:
- `claude/skills/gh-pr-review/references/review-presets.md` — prefix
  text + new "Why critical review is always on" rationale section.
- `claude/skills/gh-pr-review/references/help.md` — two lines
  reflecting the new default behavior for `--help` output.
- `claude/skills/gh-pr-review/SKILL.md` — one clause in the Role
  section pointing at the rationale.

## Data flow

Unchanged. `Step 3` builds `prompt = prefix + preset_body`; `Step 4`
appends the PR diff as stdin; `Step 5` streams the external CLI's raw
stdout; `Step 6` posts it verbatim as a PR comment. The new prefix
content flows through the same pipe — no new data, no new state.

## Error handling

If the external AI CLI ignores the new instructions and omits the
assumption line or verdict tag, `gh:pr-review` does not detect,
retry, or reformat this — the existing "never reformat the external
AI's stdout" constraint (`references/constraints.md`) applies
unchanged. This is a prompt-level request, not a parsed/validated
contract.

## Testing

- Existing bats coverage (`tests/bats/functions/gh_pr_review.bats`)
  greps for fixed strings in preset bodies (e.g. `"ONLY surface
  BLOCKER findings"`); those strings are preserved verbatim, so no
  test changes are required.
- No new automated test is added for prompt *content* — the repo has
  no existing pattern for asserting on prompt text beyond the
  substring greps already in place, and adding one would test prose
  wording rather than behavior.
- Manual verification: run `/gh-pr-review --ai <cli> --review quick
  <PR#>` and confirm the streamed output contains an `Assumption:`
  line and a closing `판정:`/`Verdict:` line.

## Out of scope

- No lens/role presets (frontend/backend/ai-governance).
- No opt-out flag.
- No changes to `gh:pr-approve` or `gh:pr-reply` (decision-making and
  per-comment replies remain their responsibility, unchanged).
