# AI CLI Invocation — for gh:pr-review

Maps the five supported `--ai` values to concrete CLI commands. The
prompt (built from `references/review-presets.md`) is passed via
**stdin** by default; the PR diff is appended to that same stdin
payload. Exceptions: `agy --print` takes the prompt as an argv string,
and `opencode run` / `hermes exec` receive a short instruction as argv plus
`--file "$PROMPT_FILE"` because stdin is not their supported review path.

## PATH pre-flight

Before dispatch, every invocation must check:

```sh
command -v "$AI_BIN" >/dev/null 2>&1 || {
    printf "Required CLI '%s' not found in PATH\n" "$AI_BIN" >&2
    exit 1
}
```

`AI_BIN` is the literal command name: `codex`, `agy`, `claude`,
`opencode`, or `hermes`. For `opencode` and `hermes`, first source
`${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/integrations/claude.sh`
when needed and require `_dotfiles_setup_mode` to return `internal`; any
other value fails with
`--ai <name> is internal-PC only (~/.dotfiles-setup-mode != internal)`
before invoking the CLI.

## stdin payload shape

The shared review material has this shape:

```text
<common-prompt-prefix-from-review-presets.md>

<preset-body-for-selected-enum>

--- PR DIFF (PR #<N>, repo <TARGET_REPO>, base <base> → head <head>) ---
<output of `gh pr diff <N> --repo <TARGET_REPO>`>
--- END PR DIFF ---
```

`PROMPT_FILE` is created via
`_gh_pr_review_mktemp_prompt <ai> <PR#>` (SSOT in
`shell-common/functions/gh_pr_review.sh`), which expands to
`mktemp "/tmp/gh-pr-review-prompt.<ai>.<PR#>.XXXXXX"` — the same
`<ai>`-discriminated template the stderr file uses. The `<ai>` + PR
discriminators are mandatory, not cosmetic: `devx:pr-review-all` runs the
agy and codex lanes concurrently, and a shared path lets one lane clobber
the other's prompt so both CLIs review identical bytes (#1276).

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
  stdin-based CLIs see identical inputs and outputs stay comparable.

`--color=never` keeps the output free of ANSI escapes so the PR
comment renders cleanly. The CLI's exit code propagates; non-zero →
quote the first stderr line and exit 1.

## `--ai agy`

```sh
agy --print < "$PROMPT_FILE"
```

`agy --print` runs the Antigravity CLI non-interactively, reading the
prompt (and appended diff) from stdin. Model selection intentionally
falls back to agy's own default; no `--model` flag is passed.

Stderr policy is identical to codex: non-zero exit → noise-filtered
summary + full stderr tail + persistent stderr log on disk. The stderr
file is created via `mktemp "/tmp/gh-pr-review-stderr.<ai>.XXXXXX"`
to avoid the predictable-PID symlink-attack class.

## `--ai claude` (no `--user`)

```sh
claude -p < "$PROMPT_FILE"
```

Same stdin pattern as the agy invocation — `claude -p` reads from
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
    echo "--user is only valid with --ai claude (codex/agy/opencode/hermes have no multi-account routing)" >&2
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

## `--ai opencode`

```sh
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/integrations/claude.sh"
[ "$(_dotfiles_setup_mode)" = "internal" ] || {
    echo "--ai opencode is internal-PC only (~/.dotfiles-setup-mode != internal)" >&2
    exit 1
}

opencode run "첨부 파일의 지시사항에 따라 위 PR diff를 리뷰해줘." \
    --model codemate/CodeLLMPro \
    --dir "$OPENCODE_WORKDIR" \
    --file "$PROMPT_FILE"
```

The model is fixed to `codemate/CodeLLMPro`; no user-facing `--model`
override is accepted. `codemate/CodeLLMMax` is intentionally absent from
the code path. Because OpenCode is agentic and may have filesystem
permissions, the dispatcher creates an isolated temporary run directory,
passes it with `--dir`, and removes it after the run. The PR worktree is
not the OpenCode process directory, so relative agent writes do not leak
into the caller checkout or race with `/simplify`.

## `--ai hermes`

```sh
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/tools/integrations/claude.sh"
[ "$(_dotfiles_setup_mode)" = "internal" ] || {
    echo "--ai hermes is internal-PC only (~/.dotfiles-setup-mode != internal)" >&2
    exit 1
}

hermes exec "첨부 파일의 지시사항에 따라 위 PR diff를 리뷰해줘." \
    --file "$PROMPT_FILE"
```

`hermes` is the Samsung DS internal AI coding CLI (setup module: `hermes/`),
so the lane is gated to internal PCs exactly like `opencode` — a stray
binary on a personal PC cannot reach the internal provider.

**Assumption pending real-CLI verification (issue #1377 Open Questions):**
hermes-agent's non-interactive review subcommand is not yet confirmed —
`hermes-help` and `hermes/AGENTS.md` document `hermes doctor`,
`hermes config`, and `hermes --version` only. The invocation above mirrors
the opencode pattern (short instruction argv + `--file "$PROMPT_FILE"`)
with `exec` as the verb, matching codex's naming for agentic dev CLIs.
Revisit once `hermes --help` is checked on an internal PC. Until then a
wrong verb surfaces as a normal non-zero exit → soft SKIP in
`devx:pr-review-all`, never a hard failure of the other lanes.

No `--model` flag is passed; hermes uses whatever endpoint its own config
resolves (custom LLM endpoints are handled by `hermes/setup.sh`).

## Step 5 dispatch procedure (`_gh_pr_review_run_ai`)

Step 5 of the skill delegates to `_gh_pr_review_run_ai` in
`shell-common/functions/gh_pr_review.sh`. The function pipes
`PROMPT_FILE` into the chosen CLI with the exact invocation shape
documented above (`codex exec --color=never`, `agy --print`, `claude -p`,
`opencode run ... --model codemate/CodeLLMPro --dir ... --file`, or
`hermes exec ... --file`, plus the
`CLAUDE_CONFIG_DIR` injection for `--user`). Stdout streams to
the user verbatim — no reformatting, no summarization, no truncation.

On non-zero exit from the external CLI the helper writes
`External AI CLI '<name>' failed: <first stderr line>` to stderr and
returns the CLI's exit code. The skill propagates that as exit 1 and
skips Step 6; partial output is discarded.

## Common error mapping

| Condition | Exit | stderr |
|-----------|------|--------|
| `--ai` missing | 2 | `missing required flag: --ai <codex\|agy\|claude\|opencode\|hermes>` |
| `--ai` unknown | 2 | `Unknown --ai value: '<x>' (allowed: codex, agy, claude, opencode, hermes)` |
| `--user` with codex/agy/opencode/hermes | 2 | `--user is only valid with --ai claude (codex/agy/opencode/hermes have no multi-account routing)` |
| `--user <bogus>` with claude | 1 | `Unknown claude account: '<bogus>' (allowed: ...)` |
| `--ai opencode` outside internal mode | 1 | `--ai opencode is internal-PC only (~/.dotfiles-setup-mode != internal)` |
| `--ai hermes` outside internal mode | 1 | `--ai hermes is internal-PC only (~/.dotfiles-setup-mode != internal)` |
| AI CLI not on PATH | 1 | `Required CLI '<name>' not found in PATH` |
| AI CLI non-zero exit | 1 | `External AI CLI '<name>' failed (exit <rc>): <noise-filtered first line>` + full tail + `/tmp/gh-pr-review-stderr.<pid>.<ai>.log` (issue #694 Bug B — no longer surfaces codex's "Reading prompt from stdin…" banner as the failure cause) |
| PR closed / merged / draft | 1 | `PR #<N> is <state>; aborting` |
| `gh pr comment` post failed | 0 | `[WARN] PR comment post failed — output retained on stdout` (soft fail) |
