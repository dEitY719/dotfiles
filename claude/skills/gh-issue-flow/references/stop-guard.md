# Stop hook — harness-level guard against gh-issue-flow early-stop

## Why this exists

`gh:issue-flow` chains 5 sub-skills (`gh:issue-implement` → `gh:commit` →
`gh:pr` → `devx:schedule` → `gh:pr-resolve-conflict`) plus a final Step 3
report. Across multiple revisions of this skill (issue #333, issue #383)
the model has repeatedly invented a "I'm done now" markdown block between
Skill() calls and ended its turn early — leaving the user to manually
finish the chain.

Two earlier mitigations help but are not sufficient:

- **`--no-next-hint`** (#333): suppresses the sub-skill's own trailing
  `Next: /gh-commit && /gh-pr <N>` line so it stops looking like a final
  answer. Effective for the original failure mode.
- **Prose rules in `SKILL.md`** that forbid conversational text between
  Skill() calls. Documented but not enforced — observed bypass rate of
  ~50% in practice, even with bold/CRITICAL framing.

#383 confirmed both are insufficient: the model authors a fresh
`gh:issue-implement #N complete` block + bullet recap + ai-metrics line
on its own — none of which `--no-next-hint` controls — and the prose
rule is silently violated.

The fix: a **Stop hook** that mechanically blocks turn-end while a
gh-issue-flow chain is mid-flight. The hook does not need the model's
cooperation; it intervenes after the model has already decided to stop.

## What it does

`claude/hooks/gh_issue_flow_stop_guard.py` is registered as a `Stop`
hook in `claude/settings.template.json` (and auto-installed into
existing `claude/settings.json` by `claude/setup.sh` via
`_migrate_install_gh_issue_flow_stop_hook`).

On every Stop event:

1. Read JSON from stdin (`hook_event_name`, `transcript_path`,
   `stop_hook_active`, …).
2. Bail out (allow stop) if any of these is true:
   - stdin is empty / not JSON / not a dict
   - `stop_hook_active == true` (we already blocked once in this chain)
   - `transcript_path` missing or unreadable
3. Walk the transcript JSONL backwards to find the most recent
   gh-issue-flow boundary — either the user typed `/gh-issue-flow` or
   the assistant invoked `Skill(gh-issue-flow)`.
4. From that boundary forward, scan all assistant text for any
   terminal Step 3 marker:
   - `gh:issue-flow complete (#`
   - `gh:issue-flow stopped at step`
   - (and the hyphen variants)
5. If no terminal marker is present, count the distinct sub-skill
   `Skill()` invocations after the boundary and pick the *next* one
   in the canonical chain.
6. Emit `{"decision":"block","reason":"…"}` on stdout. The `reason`
   tells the model exactly which Skill() call to make next, with the
   "no conversational text" rule restated.

## Safety rails

The hook runs on every Stop event in the session, not just
gh-issue-flow ones, so misbehaviour would be very visible. Defenses:

- **Fail-open everywhere.** Every code path that hits an unexpected
  state — bad JSON, missing file, no boundary, etc. — exits 0 with
  no output, which Claude Code interprets as "allow the stop."
- **Outermost `try/except`** in `__main__` catches any uncaught
  exception and exits 0.
- **`stop_hook_active` short-circuit.** When Claude Code re-fires Stop
  after a previous block, the field is set; the hook bails out so we
  never form an infinite Stop→block→Stop loop within a single chain.
- **No state file, no network, no writes.** The hook only reads stdin
  and the transcript. There is nothing to corrupt.

## Disabling temporarily

Three escape hatches when debugging or when you genuinely want to
end a turn mid-flow:

1. **Comment the entry out** in `~/.claude/settings.json` (or whichever
   account-specific copy you use) and restart the session.
2. **Rename or `chmod -x`** the script — the hook command will fail to
   exec and Claude Code will treat that as a no-op (allow stop).
3. **Patch the script** to `print('{}'); return 0` at the top of
   `main()` for the duration of the debug session.

Re-install via `./setup.sh` to restore the default behaviour.

## Tests

`tests/integration/test_gh_issue_flow_stop_guard.py` covers:

- empty stdin / malformed JSON → allow
- missing transcript_path → allow
- transcript with no gh-issue-flow boundary → allow
- mid-flow transcript (e.g. only `gh:issue-implement` invoked) → block
  with a reason naming the next sub-skill
- complete transcript (terminal Step 3 marker present) → allow
- `stop_hook_active == true` → allow regardless of mid-flow state

Run: `pytest tests/integration/test_gh_issue_flow_stop_guard.py -v`.
