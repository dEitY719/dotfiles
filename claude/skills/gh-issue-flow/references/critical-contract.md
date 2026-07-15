# gh:issue-flow — CRITICAL CONTRACT (read before editing Step 2)

**Recurring failure mode: early-stop after Step 2.x.** When a sub-skill
(`gh:issue-implement`, `gh:commit`, …) returns, the model treats its own
self-authored success block as a turn-ending answer and stops mid-chain —
leaving the user to manually re-trigger the rest. Reported by users as
"100번 실행하면 50번은 stop" (half of all runs stop early). History:
issue #333 (introduced `--no-next-hint`), issue #383 (re-occurred even
with `--no-next-hint`).

**Three guards are layered against this — do not remove any of them.**

1. **`--no-next-hint` on Step 2.1** — suppresses `gh:issue-implement`'s
   trailing `Next:` hint, the original trip-wire from #333. Load-bearing
   even though insufficient on its own (see #383).
2. **Zero conversational text between the six `Skill()` calls in Step 2** —
   no recap, no "now committing", no markdown headers, no progress
   bullets. Those tokens read as a turn-ending summary and re-introduce
   the early-stop. The only prose allowed inside Step 2 is the final
   Step 3 report. The six calls are `gh:issue-implement`, `gh:commit`,
   `gh:pr`, `devx:pr-review-all`, `gh:pr-resolve-conflict`, and
   `gh:pr-resolve-outdated`. The quality gate is no longer inline here —
   it runs inside the delegated `devx:pr-review-all` (Step 2.4), so
   issue-flow makes only that one `Skill()` call with no inline Agent
   dispatch or Bash commit+push between calls. (Historically, in the
   pre-#1160 inline gate, the 2.3.1/2.3.2 Agent dispatch and the 2.3.3
   Bash commit+push ran between Skill() calls and were permitted as
   non-prose tool calls; that gate work now lives in the delegated skill.)
   Terminal-marker gating (see guard 3) covers any tool steps automatically.
3. **Harness Stop hook (`claude/hooks/gh_issue_flow_stop_guard.py`)** —
   when the model nonetheless tries to end its turn mid-flow, this hook
   parses the transcript, detects that fewer than 6 sub-skills have run
   without a Step 3 marker, and returns `{"decision":"block","reason":...}`
   so Claude Code re-prompts the model to invoke the next sub-skill.
   See `references/stop-guard.md` for the detection logic, safety rails,
   and how to disable it temporarily for debugging.

If you edit Step 2 in any way, re-verify all three guards are still in
place. The harness guard is a backstop, not a license to weaken the
prose rules — Claude can still emit verbose text BEFORE attempting to
stop, which the hook cannot prevent.
