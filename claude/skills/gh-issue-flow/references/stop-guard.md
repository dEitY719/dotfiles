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

`claude/hooks/gh_issue_flow_stop_guard.py` is registered on **both**
`Stop` and `SubagentStop` in the tracked `claude/settings.json` SSOT
(`Stop` since #584, `SubagentStop` since #1434 — see the dedicated
section below). The legacy `_migrate_install_gh_issue_flow_stop_hook`
helper in `claude/setup.sh` is left in place as a defense-in-depth no-op
for installs whose live file still lacks the `Stop` entry.

On every Stop / SubagentStop event:

1. Read JSON from stdin (`hook_event_name`, `transcript_path`,
   `agent_transcript_path`, `stop_hook_active`, …) and **resolve which
   transcript to parse** — `agent_transcript_path` wins when present
   (#1434, see below).
2. Bail out (allow stop) if any of these is true:
   - stdin is empty / not JSON / not a dict
   - `stop_hook_active == true` (we already blocked once in this chain)
   - the resolved transcript path is missing or unreadable (no fallback
     to the other key — #1434)
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

   **Bash fallback channel (#1270), pair-matched.** Assistant text is the
   canonical channel — `references/report-template.md` requires the Step 3
   report to be plain assistant text. But models sometimes print it
   through `Bash` (`cat <<'EOF' … EOF`, `printf`), in which case the
   report text only ever exists in the tool_use `input.command` string and
   in a `tool_result`, and the flow could never terminate. So the scan
   also accepts a `Bash` tool_use — but only when a **stricter** marker
   regex (one that requires a literal digit where the templates carry
   `<N>` / `<i>`) matches **both**:
   1. the tool_use's `input.command`, **and**
   2. the `tool_result` whose `tool_use_id` equals that tool_use's `id`
      — which must **additionally** carry a report *field* line, `PR
      URL:` (success form) or `Resume after fix:` (failure form) (#1274).

   Condition 1 alone proves only that the model *mentioned* the marker:
   `cat <<'EOF' > /tmp/report.txt` redirects it into a file, and a marker
   in a shell comment never surfaces either. Condition 2 is what proves
   the report reached stdout — a redirect produces none, so no pair forms.
   Condition 2 alone is the #608 hazard (SKILL.md read into a
   `tool_result`); that path can never satisfy condition 1, because the
   command doing the reading (`Read`, `cat SKILL.md`) carries no literal
   digit. **The pair is strictly narrower than either half**, so adding it
   does not reopen #608. This lookup is the only place in the hook that
   reads a `tool_result` at all, and only for an id whose command already
   matched. A `Bash` block with no usable `id` is unpairable and never
   terminates.

   **Full report shape on the result side (#1274).** The marker line alone
   used to be enough on the result side, which left one false positive:
   `grep "gh:issue-flow complete (#1270)" some.log` satisfies condition 1
   (literal-digit marker in the command) and condition 2 (grep echoes the
   matched line back), so a plain log search could terminate a live flow.
   The result must therefore also carry a report field line — a real Step
   3 report is multi-line and always has `PR URL:` or `Resume after fix:`,
   which one grepped line cannot reproduce. The requirement sits on the
   *result* only; the command side stays the plain marker match, so a
   heredoc still qualifies however its field line is quoted or built. When
   `tool_result.content` is a list of text blocks, the blocks are joined
   before matching — Claude Code may split one command's stdout, and a
   genuine report whose marker and field line land in different sub-blocks
   must still match. Residual risk left standing: a context grep that
   drags a real report's field line along with its marker line (`grep -A5
   "gh:issue-flow complete (#1270)" some.log` over a log holding a genuine
   past report) — far more contrived than the bare `grep` it replaces,
   which is the point. A **drift test** ties the field names to
   `references/report-template.md`, so renaming them there fails loudly
   instead of silently staling the hook.

   **Only `Bash` is scanned**: `Write`/`Edit` inputs legitimately carry
   real template text whenever the skill's own files are edited.
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

## SubagentStop registration (#1434)

### Why

A subagent's turn-end fires `SubagentStop`, not `Stop`. With the guard
registered on `Stop` only, any gh:issue-flow that ran *inside* a
subagent lost the third of the three layered guards entirely — the
harness layer, the only one that does not need the model's cooperation.
Just the two prompt-layer mitigations remained, i.e. exactly the
condition under which #333 / #383 / #1270 each recurred. The exposed
path is the issue-watcher unattended dispatch (#1389): nobody is
watching it, so a silently truncated chain leaves an unreviewed,
un-rebased PR behind with no error and no warning.

### Measured payload contract

`Stop` and `SubagentStop` do **not** carry the same keys:

| key | `Stop` | `SubagentStop` | meaning |
| --- | --- | --- | --- |
| `transcript_path` | yes | yes | **the parent session's** transcript |
| `agent_transcript_path` | no | yes | **the subagent's own** transcript |
| `agent_id` / `agent_type` | no | yes | which subagent ended |
| `stop_hook_active` | yes | yes | re-fire flag (loop safety valve) |

Measured on one real `SubagentStop` event:

- `transcript_path` = `<projects>/<session_id>.jsonl` — parent
- `agent_transcript_path` =
  `<projects>/<session_id>/subagents/agent-<agent_id>.jsonl` — subagent

So the hazard was never "the key is missing"; it was **the wrong
transcript**. Registering the guard without a resolution rule would have
had it parse the *parent* transcript, find no gh-issue-flow boundary
there (the watcher parent never runs the flow itself), and fail open —
a silent no-op that looks installed.

### Resolution rule, and why there is no fallback

On `SubagentStop` the hook accepts **only** `agent_transcript_path`; on
every other event (`Stop`, or a payload naming no event) it prefers
`agent_transcript_path` and falls back to `transcript_path`. If the
*chosen* file does not exist the hook fails open; it does **not** then
try the other key. A subagent must never be judged by its parent's flow
state — the parent could be mid-flow while the subagent does something
unrelated (spurious block), or the reverse (missed block). For a
transcript we cannot read, fail-open is the correct answer.

The event-awareness is a PR #1438 (agy) tightening: the preference chain
used to be unconditional, so a `SubagentStop` with an absent or empty
`agent_transcript_path` silently walked on to the **parent's**
transcript — the same cross-session contamination the no-fallback rule
above exists to prevent. Such an event now fails open instead.

### Everything else carries over unchanged

The subagent transcript uses the same JSONL schema as the parent's, with
the dispatch prompt as its first `role=user` text entry. All four L1
boundary surfaces, the L1.5 terminal-marker scan (assistant text plus
the `Bash` command/result pair), the stale-boundary expiry valve and
every fail-open rail therefore apply verbatim.

`stop_hook_active` behaves identically too: `False` on the first
`SubagentStop`, `True` on the event re-fired after a block — so the
infinite-loop valve holds on this path.

### A block really does continue a subagent (U-4)

Confirmed by execution, not inference: "the hook fires" and "the chain
actually resumes" are different claims, and closing the issue on the
first one would leave the path undefended while looking fixed.

Emitting `{"decision":"block","reason":"…"}` on a subagent's first
`SubagentStop` injected `Stop hook feedback:\n<reason>` into **the
subagent's own** user channel, and the subagent then performed another
full turn (thinking -> tool_use -> tool_result -> final text) before
stopping again. Same mechanism as the `Stop` path.

`Stop hook feedback:` is already one of the `_HARNESS_INJECTION_RE`
markers, so the guard's own re-injections do not inflate the
fresh-prompt counter on this path either — the expiry valve keeps
counting only genuine human prompts.

### How the payload was measured (non-obvious — you will need this again)

Registering a hook in the **running** session's settings does *not*
work: Claude Code snapshots the hook set at session start, so a
mid-session registration never fires. The payload was captured from a
separate headless session instead:

```bash
cat > /tmp/probe.sh <<'EOF'
#!/bin/sh
tee -a /tmp/subagentstop-payload.jsonl >/dev/null
EOF
chmod +x /tmp/probe.sh
# probe-settings.json registers /tmp/probe.sh on SubagentStop
claude -p --settings /tmp/probe-settings.json --model haiku \
  --dangerously-skip-permissions "<prompt that dispatches one subagent>"
```

The probe hook `tee`s stdin to a file. U-4 was measured by having the
same probe emit one `{"decision":"block"}` and then reading the
subagent's own transcript for the turns that followed.

### Rollout path (the live settings.json, not just the SSOT)

Adding `SubagentStop` to the tracked `claude/settings.json` is not the
whole deployment: every mode's live settings.json is a **real file**, so
something has to carry the new event key over.

- external / multi-account — `_claude_ensure_settings_copy`
  (`shell-common/tools/integrations/claude.sh`) copies the SSOT over the
  live file whenever the two differ, on `./setup.sh`.
- internal — `claude/hooks/session-start-settings-drift.sh` re-assigns
  the SSOT's whole `.hooks` block into the live file at every
  SessionStart.

Both propagate a wholly NEW event key, not just changed values; a
regression test in `tests/bats/skills/session_start_settings_drift_hook.bats`
pins that (live file with `Stop` but no `SubagentStop` → healed live
file carries the guard under `.hooks.SubagentStop`).

### Known gap, left open on purpose

`claude/hooks/devx_autopilot_stop_guard.py` and
`claude/hooks/skill_completion_guard.py` both have the **same structural
exposure** — `Stop`-only registration plus a `transcript_path`-only
lookup — and were deliberately **not** registered on `SubagentStop` in
this change. #1434 scopes them out pending the result here. This is a
documented gap, not an oversight.

### Deployment caveat

The live `~/.claude*/settings.json` is a real file, not a symlink (#940
/ #1086), so this new registration does not reach a running install on
`git pull` alone — it takes effect on the **next** session, never in the
one that pulled the commit. Which mode heals automatically and which
only warns is owned by `claude/AGENTS.md` → "Configuration Files"; do
not restate the re-seed rules here, they have already changed once.

## Safety rails

The hook runs on every Stop *and* SubagentStop event in the session,
not just gh-issue-flow ones, so misbehaviour would be very visible.
Defenses:

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

1. **Comment the entries out** in `~/.claude/settings.json` (or
   whichever account-specific copy you use) — both the `Stop` and the
   `SubagentStop` one — and restart the session.
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
  **with its paired `tool_result`** → allow (string- and list-shaped
  `tool_result.content` both); a `Bash` command that only greps the
  template text (no literal issue/step digit) → still block; the same
  template text arriving via `tool_result`, or a real marker inside an
  `Edit`/`Write` tool input → still block.
- #1270 / PR #1272 (pair matching): command matches but output was
  redirected to a file (empty `tool_result`) → still block; marker only
  in a shell comment (unrelated output) → still block; marker in the
  `tool_result` of a non-matching `cat` command → still block; command
  under `toolu_A` with a marker-bearing result under `toolu_B` → still
  block; `Bash` tool_use with no `id` → still block.
- #1274 (full report shape): `grep "gh:issue-flow complete (#1270)"
  some.log` whose result is just that one echoed line — both halves of
  the #1272 pair match, but no `PR URL:` / `Resume after fix:` field is
  present → still block. Plus a **drift test** asserting both field
  strings still occur in `references/report-template.md`, so renaming
  them there breaks the build instead of silently staling the hook.
- #1270 F-2: 3 fresh unrelated user prompts after an unfinished flow
  → allow (stale boundary); 2 → still block; skill-expansion,
  `tool_result`-only and `<system-reminder>`-only messages are not
  counted; `GH_ISSUE_FLOW_STOP_GUARD_MAX_USER_TURNS=0` disables expiry.
- #1270 / PR #1272: `isMeta` entries, `Stop hook feedback:` blocks,
  `<task-notification>` and `[SYSTEM NOTIFICATION - NOT USER INPUT]`
  messages are not counted; a message carrying both human text and a
  `tool_result` **is** counted.
- #1434 (`SubagentStop`): a **registration test** asserts the tracked
  `claude/settings.json` wires this hook onto `SubagentStop` as well as
  `Stop` — the one check that would have caught the original gap. Plus
  transcript resolution (`agent_transcript_path` preferred over
  `transcript_path`; a missing chosen file fails open instead of
  falling back), a mid-flow subagent transcript → block, an
  unrelated subagent stop → allow, and the six existing fail-open rails
  re-asserted against a `SubagentStop`-shaped payload.

Run: `pytest tests/integration/test_gh_issue_flow_stop_guard.py -v`.
