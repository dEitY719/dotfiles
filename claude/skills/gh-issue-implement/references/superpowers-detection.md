# gh:issue-implement — superpowers Plugin Detection

## Detection rule

superpowers is present if EITHER is true:

1. Plugin cache directory exists:
   ```bash
   test -d "$HOME/.claude/plugins/cache/superpowers-dev"
   ```
2. The required skills are resolvable via the Skill tool (checked by
   attempting to describe `superpowers:writing-plans`,
   `superpowers:brainstorming`, `superpowers:test-driven-development`,
   and `superpowers:subagent-driven-development`, and verifying they all
   return a skill definition, not a "not found" error).

If either check passes → honor requested mode.
If both fail → force `direct` mode.

This disjunction handles manual/symlink installs that bypass the
plugin cache but still expose the skills to the Skill tool.

## What detection gates

| Mode | Detected | Not detected |
|---|---|---|
| `plan` | `Skill(superpowers:writing-plans)` | forced to `direct` + warning |
| `brainstorming` | `Skill(superpowers:brainstorming)` | forced to `direct` + warning |
| `direct` | TDD path — `Skill(superpowers:test-driven-development)`, only when a test runner was also detected (see `references/implementation-flow.md` → "Common steps") | built-in fallback path |

`direct` mode is never blocked by detection — it only picks a different
implementation path (`references/implementation-flow.md`), and that
path choice also depends on test-runner presence, not detection alone.

If `superpowers:test-driven-development` or
`superpowers:subagent-driven-development` specifically fails to resolve
at invocation time (partial install), take the fallback path — or, for
`plan`/`brainstorming`, proceed without the TDD guarantee — and print
one warning line naming the missing skill, e.g.:

```
[WARN] superpowers:test-driven-development unavailable — using built-in implementation flow.
[WARN] superpowers:subagent-driven-development unavailable — plan/brainstorming will not guarantee TDD.
```

## Fallback behavior

When falling back:

1. Print exactly one warning line (no stack of warnings):
   ```
   [WARN] superpowers plugin not installed — falling back to direct mode.
   ```
2. Proceed to direct-mode implementation flow.
3. Do NOT error out. The skill should still deliver value when the
   plugin is absent — that's the whole point of the fallback.

## Why this rule

`gh:issue-implement` is shared across teammates with different plugin
setups. Hard-requiring superpowers would make the skill fail entirely
on some machines. Graceful degradation (direct mode is always
available) keeps the skill useful everywhere.

## Invocation of superpowers skills

In `direct` mode (plugin present) — the default path:

1. Capture the pre-edit test baseline FIRST
   (`references/implementation-flow.md` → "Direct-mode flow" step 4).
   The TDD cycle must not start before `pre_existing_failures` is known.
2. Invoke `Skill(superpowers:test-driven-development)` after issuing a
   context block to the main model:
   ```
   Context for test-driven-development: implementing issue #<N> of <TARGET_REPO>.
   Issue body follows below. Test runner: <TEST_CMD>.
   Pre-existing failures (do NOT fix, report as-is): <list or "none">.
   ```
3. Drive the issue as a sequence of red-green-refactor cycles, one
   behavior per cycle, until the issue's intent is satisfied.
4. Carry the pre-existing exception through every cycle — see
   "Pre-existing exception" below.
5. Return to Step 6 (report) with the changed-file list and the final
   `$TEST_CMD` result.

`plan` and `brainstorming` modes reach TDD indirectly: their plans are
executed through `superpowers:subagent-driven-development`, whose
subagents follow `superpowers:test-driven-development` per task. Step 2
now verifies both skills resolve before honoring these modes, so a
partial install (e.g. `subagent-driven-development` missing while
`writing-plans` still resolves) is caught up front instead of failing
deep inside plan execution. This does not audit `writing-plans` /
`executing-plans`'s own internals beyond that resolve check — a failure
inside those skills themselves is out of scope here.

### Pre-existing exception (direct-mode TDD path)

`superpowers:test-driven-development` → "Verify GREEN" says **"Other
tests fail? Fix now."** That instruction is scoped here: it applies only
to failures NOT in `pre_existing_failures`.

- A failing test already in `pre_existing_failures` → leave it alone,
  carry it to the final report as pre-existing.
- Any other failing test → fix now, per the TDD skill.

This is a `gh:issue-implement` scope rule, not an edit to the TDD skill.
`references/constraints.md` → "Never dismiss pre-existing test failures"
is a hard constraint and outranks the TDD skill's blanket wording.

When in `plan` mode (plugin present):

1. Invoke `Skill(superpowers:writing-plans)` after issuing a 1-line
   context block to the main model:
   ```
   Context for writing-plans: implementing issue #<N> of <TARGET_REPO>.
   Issue body follows below. Save plan to docs/feature/superpowers-plans/.
   ```
2. Wait for the plan document to be committed.
3. Then invoke `Skill(superpowers:executing-plans)` or proceed to
   execute inline — both are valid; execute inline for the single-skill
   happy path.

In `brainstorming` mode:

1. Invoke `Skill(superpowers:brainstorming)` with the issue as the
   input idea.
2. brainstorming → writing-plans → execute, per its own terminal state.

## Ambiguity → auto-promote from plan to brainstorming

When mode is `plan`, check these signals on the fetched issue BEFORE
invoking writing-plans. If any is true, invoke brainstorming instead:

- Issue body is empty or `< 200` characters.
- No action verb in title or body (추가/수정/삭제/구현/변경/fix/add/
  update/remove/refactor).
- Body contains "어떻게 할지 상의", "논의 필요", "아이디어", "TBD",
  "to discuss".
- Comments contain contradictory requirements (e.g., one comment
  says "use X", another says "don't use X").

Print one line before promoting:

```
Issue #<N> looks ambiguous — upgrading 'plan' to 'brainstorming' for design alignment.
```
