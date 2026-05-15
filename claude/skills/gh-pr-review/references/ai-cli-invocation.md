# AI CLI Invocation — for gh:pr-review

Maps the three supported `--ai` values to concrete CLI commands. The
prompt (built from `references/review-presets.md`) is passed via
**stdin**; the PR diff is appended to that same stdin payload. None of
the three CLIs receive the prompt as a single argv string — argv has
length limits and quoting hazards, stdin doesn't.

## PATH pre-flight

Before dispatch, every invocation must check:

```sh
command -v "$AI_BIN" >/dev/null 2>&1 || {
    printf "Required CLI '%s' not found in PATH\n" "$AI_BIN" >&2
    exit 1
}
```

`AI_BIN` is the literal command name: `codex`, `gemini`, or `claude`.

## stdin payload shape

All three CLIs receive the same byte stream on stdin:

```text
<common-prompt-prefix-from-review-presets.md>

<preset-body-for-selected-enum>

--- PR DIFF (PR #<N>, repo <TARGET_REPO>, base <base> → head <head>) ---
<output of `gh pr diff <N> --repo <TARGET_REPO>`>
--- END PR DIFF ---
```

Large diffs follow the same delegation pattern as
`gh-pr-approve/references/large-diff-delegation.md`. When `additions +
deletions ≥ 800`, dispatch an Explore subagent to pre-classify
candidate findings instead of streaming the full diff into the
external CLI's context.

## `--ai codex`

```sh
codex exec --color=never < "$PROMPT_FILE"
```

Why `codex exec` instead of `codex review --base <branch>`:

- `codex review` auto-builds its own prompt and diff context — we lose
  control over the preset/lens dimensions defined in
  `references/review-presets.md`.
- `codex exec` accepts our prompt + diff verbatim on stdin, so all
  three CLIs see identical inputs and outputs stay comparable.

`--color=never` keeps the output free of ANSI escapes so the PR
comment renders cleanly. The CLI's exit code propagates; non-zero →
quote the first stderr line and exit 1.

## `--ai gemini`

```sh
gemini -p < "$PROMPT_FILE"
```

`gemini -p` reads its prompt from stdin when no argv string follows,
keeping the payload off argv entirely (no `ARG_MAX` exposure, no
quoting hazard). Model selection (`-m <model>`) intentionally falls
back to the user's environment default; add a `--gemini-model` flag
in a future iteration only if users report drift between defaults.

Stderr policy is identical to codex: non-zero exit → first stderr line
to caller, exit 1.

## `--ai claude` (no `--user`)

```sh
claude -p < "$PROMPT_FILE"
```

Same stdin pattern as the gemini invocation — `claude -p` reads from
stdin when no argv prompt is supplied. The skill inherits whatever
`CLAUDE_CONFIG_DIR` the calling shell has set. If the user is inside
`claude-yolo --user work`, that `work` account is preserved
automatically — no forced `personal` default.

## `--ai claude --user <name>`

Routes through the SSOT helper `_claude_resolve_account` (defined in
`shell-common/tools/integrations/claude.sh`) so the resolution path
is identical to `claude-yolo --user <name>`.

```sh
# Source the helper if not already in scope (login shells already source it).
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/integrations/claude.sh"

CFG_DIR=$(_claude_resolve_account "$USER_ACCOUNT") || {
    ALLOWED=$(_claude_resolve_account --list | tr '\n' ' ')
    printf "Unknown claude account: '%s' (allowed: %s)\n" \
           "$USER_ACCOUNT" "$ALLOWED" >&2
    exit 1
}

CLAUDE_CONFIG_DIR="$CFG_DIR" claude -p < "$PROMPT_FILE"
```

- The whitelist comes from `CLAUDE_ENABLED_ACCOUNTS`; the helper
  enforces the safe-identifier regex (`^[a-z][a-z0-9_-]*$`). No
  injection surface from the user-supplied account name.
- The `CFG_DIR` directory must exist — if missing, exit 1 with the
  same message style `claude-yolo` uses.

### Cross-AI `--user` rejection

```sh
if [ -n "$USER_ACCOUNT" ] && [ "$AI" != "claude" ]; then
    echo "--user is only valid with --ai claude (codex/gemini have no multi-account routing)" >&2
    exit 2
fi
```

Silent ignore is rejected on purpose: a user who typed `--user work`
expects a `work` account, and running anything else would create a
trust gap between intent and execution.

### Internal-PC behavior

On internal PCs (`~/.dotfiles-setup-mode == internal`),
`claude-yolo` short-circuits multi-account routing and uses
`$HOME/.claude` directly. This skill does **not** replicate that
branch — internal PCs typically have an empty
`CLAUDE_ENABLED_ACCOUNTS`, so `_claude_resolve_account` naturally
rejects any `--user <name>`. The cleanest user experience there is to
omit `--user` and let the current shell's `CLAUDE_CONFIG_DIR` win.

## Common error mapping

| Condition | Exit | stderr |
|-----------|------|--------|
| `--ai` missing | 2 | `missing required flag: --ai <codex\|gemini\|claude>` |
| `--ai` unknown | 2 | `Unknown --ai value: '<x>' (allowed: codex, gemini, claude)` |
| `--user` with codex/gemini | 2 | `--user is only valid with --ai claude (codex/gemini have no multi-account routing)` |
| `--user <bogus>` with claude | 1 | `Unknown claude account: '<bogus>' (allowed: ...)` |
| AI CLI not on PATH | 1 | `Required CLI '<name>' not found in PATH` |
| AI CLI non-zero exit | 1 | first line of CLI's stderr, quoted |
| PR closed / merged / draft | 1 | `PR #<N> is <state>; aborting` |
| `gh pr comment` post failed | 0 | `[WARN] PR comment post failed — output retained on stdout` (soft fail) |
