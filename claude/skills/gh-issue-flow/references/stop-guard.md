# Stop hook — harness-level guard against gh-issue-flow early-stop

SSOT for the guard's detection contract. Other docs (`SKILL.md`,
`references/report-template.md`) state the *rule* for report authors and
point here for the *mechanism*.

## Why this exists

`gh:issue-flow` chains 6 sub-skills (`gh:issue-implement` → `gh:commit` →
`gh:pr` → `devx:pr-review-all` → `gh:pr-resolve-conflict` →
`gh:pr-resolve-outdated`) plus a final Step 3 report. The post-PR quality
gate (agy ∥ codex ∥ `/simplify`, with commit+push) and the deferred
`/gh-pr-reply` scheduling now live *inside* the delegated
`devx:pr-review-all` (Step 2.4) — they are no longer dispatched inline by
gh:issue-flow. `devx-pr-review-all` is the 4th entry of the hook's
`EXPECTED_CHAIN`, and `gh-pr-resolve-outdated` is the 6th. Across multiple
revisions of this skill (issue #333, issue #383) the model has repeatedly
invented a "I'm done now" markdown block between Skill() calls and ended
its turn early — leaving the user to manually finish the chain.

Because the quality gate and pr-reply scheduling are folded into a single
`Skill(devx:pr-review-all)` call, Step 2 is a clean six-`Skill()` sequence:
there is no inline Agent/Bash gate work between the chain skills for the
hook to reason about. The terminal-marker gating (L1.5 below) blocks
turn-end until a Step 3 marker appears.

> History (pre-#1160): the quality gate used to be dispatched inline as
> steps 2.3.1 (codex review) ∥ 2.3.2 (`/simplify`) → 2.3.3 (commit+push)
> via Agent/git tool calls, and pr-reply was scheduled by a separate
> `devx:schedule` step that occupied the 4th `EXPECTED_CHAIN` slot. Both
> were consolidated into `devx:pr-review-all`.

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
hook in the tracked `claude/settings.json` SSOT (#584). The legacy
`_migrate_install_gh_issue_flow_stop_hook` helper in `claude/setup.sh`
is left in place as a defense-in-depth no-op for installs whose live
file still lacks the entry.

On every Stop event:

1. Read JSON from stdin (`hook_event_name`, `transcript_path`,
   `stop_hook_active`, …).
2. Bail out (allow stop) if any of these is true:
   - stdin is empty / not JSON / not a dict
   - `stop_hook_active == true` (we already blocked once in this chain)
   - `transcript_path` missing or unreadable
3. **L1 — Boundary detection.** Walk the transcript JSONL backwards to
   find the most recent gh-issue-flow start. Four boundary surfaces
   are matched (defense in depth against Claude Code wrapper drift):
   - assistant `Skill(gh-issue-flow)` tool_use
   - user text starting with `/gh-issue-flow` (or `/gh:issue-flow`)
     at a line start
   - user text containing `<command-name>/gh-issue-flow</command-name>`
     (or colon namespace form) — the wrapper Claude Code emits for
     interactively-typed slash commands (#607)
   - user text containing the SKILL prompt markers
     `Base directory for this skill: …/gh-issue-flow` or the H1 line
     `# gh:issue-flow — Issue → PR composition` (#608, defensive
     anchors for future wrapper variants)
4. **L1.5 — Terminal-marker scan.** From the message *after* the
   boundary, scan only `role=assistant` text blocks (not `tool_result`,
   not user-role text) for any Step 3 terminal marker:
   - `gh:issue-flow complete (#`
   - `gh:issue-flow stopped at step`
   - (and the hyphen variants)
   This narrow scope is load-bearing. The SKILL.md body, delivered as
   a `role=user` text block when a slash command expands, literally
   contains those marker strings as Step 3 *instructions*. Scanning
   user text would silently false-match every real invocation and
   fail-open the hook (issue #608, 5th regression).

   **Bash fallback channel (#1270).** Assistant text is the canonical
   channel — `references/report-template.md` requires the Step 3 report
   to be plain assistant text. But models sometimes print it through
   `Bash` (`cat <<'EOF' … EOF`, `printf`), in which case the report text
   only ever exists in the tool_use `input.command` string and in a
   `tool_result`, and the flow could never terminate. So the scan also
   matches an assistant `Bash` tool_use command against a **stricter**
   regex that requires a literal digit where the templates carry `<N>` /
   `<i>` — `grep "gh:issue-flow complete" SKILL.md` therefore cannot
   false-terminate. **Only `Bash` is scanned**: `Write`/`Edit` inputs
   legitimately carry real template text whenever the skill's own files
   are edited.
5. **Boundary expiry (#1270).** Count *fresh* user prompts after the
   boundary. A user-role entry counts only when all of:
   - the **outer** transcript entry is not flagged `isMeta` — Claude Code
     stamps that on text it injects into the user channel itself and never
     on a human prompt. It sits on the entry, not on the inner `message`,
     so the counter reads role/content from `message` but the flag from
     the entry;
   - its text — collected with `include_tool_results=False`, then with
     every `<system-reminder>…</system-reminder>` span deleted — is
     non-empty. This is what excludes tool output: `tool_result` blocks
     contribute no text, so a tool-output-only message yields `""`. There
     is deliberately **no** "contains a tool_result ⇒ skip" rule — a
     human prompt bundled in the same turn as tool output must still
     count, or an abandoned flow could never expire;
   - it shows no *skill-expansion* marker (`Base directory for this
     skill:`, `<command-name>`, `<command-message>`,
     `<local-command-stdout>`, `is already loaded above`) and no
     *harness-injection* marker (`Stop hook feedback:`, `gh-issue-flow
     incomplete:`, `<task-notification>`, `[SYSTEM NOTIFICATION - NOT
     USER INPUT]`, `<local-command-caveat>`).

   At 3 or more (`GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS`, `0`
   disables), the boundary is declared stale and the hook fails open.
   Without it a boundary lives for the rest of the session:
   `stop_hook_active` only breaks the loop *within* a turn and resets on
   the next user message, so an un-terminated flow would keep blocking
   unrelated turns.

   > The harness-injection markers exist because the counter used to
   > over-count catastrophically: on a real 2489-entry transcript it saw
   > 102 "fresh prompts" of which only 4 were human — 62 were this hook's
   > own `reason` re-injected as `Stop hook feedback: …` and 40 were
   > `<task-notification>` background-agent completions. The limit of 3
   > was hit at entry 322 with 1/6 sub-skills done, so the guard turned
   > itself off mid-flow. `devx:pr-review-all` (Step 2.4) fans out three
   > background agents, which made that the normal path (PR #1272).
6. If no terminal marker is present, count the distinct sub-skill
   `Skill()` invocations after the boundary and pick the *next* one
   in the canonical chain.
7. Emit `{"decision":"block","reason":"…"}` on stdout. The `reason`
   tells the model exactly which Skill() call to make next, with the
   "no conversational text" rule restated.

When `GH_ISSUE_FLOW_STOP_GUARD_TRACE=1`, each decision logs a
`[stop-guard] … layer=L1|L1.5` line on stderr so the layer
attribution is greppable in post-mortems.

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
- **Boundary expiry (#1270).** A boundary that outlives 3 fresh user
  prompts is declared stale and the hook fails open — see step 5 above.
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
- L1 boundary surfaces (#608): raw slash, `<command-name>` wrapper,
  `Base directory for this skill: …/gh-issue-flow`, and the H1 line —
  positive + false-positive (inside `tool_result`) variants for each
- L1.5 (#608, root cause of 5th regression): a real `/gh-issue-flow`
  invocation whose user message includes the SKILL prompt body
  (which literally quotes the Step 3 template) must still **block**
  the mid-chain stop. A defensive variant covers the case where the
  model reads `gh_issue_flow_stop_guard.py` itself inside the flow.
- #1270 F-1: a Step 3 report emitted through a `Bash` heredoc/`printf`
  → allow; a `Bash` command that only greps the template text (no
  literal issue/step digit) → still block; the same template text
  arriving via `tool_result`, or a real marker inside an `Edit`/`Write`
  tool input → still block.
- #1270 F-2: 3 fresh unrelated user prompts after an unfinished flow
  → allow (stale boundary); 2 → still block; skill-expansion,
  `tool_result`-only and `<system-reminder>`-only messages are not
  counted; `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS=0` disables expiry.
- #1270 / PR #1272: `isMeta` entries, `Stop hook feedback:` blocks,
  `<task-notification>` and `[SYSTEM NOTIFICATION - NOT USER INPUT]`
  messages are not counted; a message carrying both human text and a
  `tool_result` **is** counted.

Run: `pytest tests/integration/test_gh_issue_flow_stop_guard.py -v`.
