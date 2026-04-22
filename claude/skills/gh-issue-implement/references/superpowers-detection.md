# gh:issue-implement — superpowers Plugin Detection

## Detection rule

```bash
test -d "$HOME/.claude/plugins/cache/superpowers-dev"
```

- Exit 0 → plugin installed → honor requested mode.
- Exit non-zero → plugin missing → force `direct` mode.

## Fallback behavior

When falling back:

1. Print exactly one warning line (no stack of warnings):
   ```
   ⚠️  superpowers plugin not installed — falling back to direct mode.
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

When in `plan` mode (plugin present):

1. Invoke `Skill(superpowers:writing-plans)` after issuing a 1-line
   context block to the main model:
   ```
   Context for writing-plans: implementing issue #<N> of <TARGET_REPO>.
   Issue body follows below. Save plan to docs/superpowers/plans/.
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
