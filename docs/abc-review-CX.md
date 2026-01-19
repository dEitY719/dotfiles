# Reviewer
- Model: GPT-5.2 (Codex CLI)
- Date: 2026-01-19
- Scope: `/home/bwyoon/dotfiles/.git/hooks/pre-commit` (git pre-commit hook script)

# Project Structure Summary (Scope-Limited)
- Hook intent: enforce naming rules (dash-form in user-facing text vs snake_case internals), check shebang consistency, and suggest UX-library consistency.
- Checks performed today:
  - Shebang: checks only `*.sh` directly under `shell-common/`, `bash/`, `zsh/` (non-recursive).
  - Naming: scans `shell-common/functions/*.sh` for snake_case function names appearing in double-quoted user-facing strings.
  - Function naming: flags kebab-case function definitions inside `shell-common/functions/*.sh`.
  - UX usage: warns (non-blocking) when a file both uses `ux_*` and also uses raw `echo`.

# SOLID Evaluation (Hook Script)
- SRP (Single Responsibility): 6/10 (multiple distinct checks in one file; still cohesive as “repo hygiene gate”)
- OCP (Open/Closed): 6/10 (adding new checks requires editing the hook; little plugin/config structure)
- LSP (Liskov Substitution): 8/10 (not very applicable; functions behave predictably)
- ISP (Interface Segregation): 7/10 (helpers are separated, but output + scanning concerns are interleaved)
- DIP (Dependency Inversion): 5/10 (hard-coded paths and direct grep/head usage; no abstraction over “file list” and “reporting”)
- Total: 32/50

# Issues (By Severity)

## High
1. Reproducibility gap: hook lives in `.git/hooks/` (typically not version-controlled)
   - Impact: new clones won’t automatically get the same checks; behavior differs by machine.
   - Suggestion: store the hook under a tracked path (e.g., `git/hooks/pre-commit`) and install via `setup.sh` (symlink/copy) or document a manual install step.

2. File selection is not staged-aware and can be slow/noisy
   - Current behavior: scans whole directories, not just staged changes; can block commits for unrelated files.
   - Suggestion: base scans on `git diff --cached --name-only --diff-filter=ACM` and only check matching files (and/or only touched lines where feasible).

## Medium
1. Shebang check is non-recursive and likely incomplete vs stated intent
   - Current behavior: `for file in "$dir"/*.sh` only checks top-level `*.sh` under `shell-common/`, `bash/`, `zsh/`.
   - Suggestion: either (a) make it explicit in the header that it’s top-level only, or (b) switch to a recursive file list (preferably using `git ls-files '*.sh'` scoped to those directories).

2. Raw `echo`/`printf` usage in the hook conflicts with repo “UX output” conventions
   - Repo rule (root AGENTS): “Use ux_lib functions for ALL output” and “Don’t use raw echo or printf”.
   - Suggestion: consider sourcing `shell-common/tools/ux_lib/ux_lib.sh` from `REPO_ROOT` and using `ux_*` for hook output; if not desired for hooks, clarify an exception in docs.

3. Temporary file handling should use `mktemp` + cleanup
   - Current behavior: writes `/tmp/violations_$$.txt` and `/tmp/func_violations_$$.txt` without `trap` cleanup.
   - Suggestion: `tmp="$(mktemp ...)"` and `trap 'rm -f "$tmp1" "$tmp2"' EXIT` to prevent orphaned files on interrupt/failure.

4. Naming-violation detection is narrow and may miss/false-positive
   - Misses: single-quoted user-facing strings, heredocs, printf, multi-line messages.
   - False positives: function name matching inside other words/URLs/paths; patterns are regex-based and not token-aware.
   - Suggestion: limit checks to agreed “user-facing” functions (`ux_error`, `ux_info`, etc.) and parse only their string arguments, or define explicit patterns for “Usage:” / “Examples:” blocks.

## Low
1. Unicode symbols (e.g., warning icon) may conflict with “no emojis” policy and can render inconsistently
   - Suggestion: use plain ASCII markers (`OK`, `WARN`, `FAIL`) or keep symbols only if policy allows.

2. ShellCheck flags SC2155 warnings (declare+assign) in multiple places
   - Not functionally wrong, but easy quality win if you decide to maintain this hook long-term.

# Action Items (Prioritized)
- P0: Move the hook into a tracked location (e.g., `git/hooks/pre-commit`) and install it via `setup.sh` or a dedicated `git/hooks/setup.sh`.
- P0: Switch checks to staged files only (`git diff --cached ...`) to avoid slow commits and unrelated failures.
- P1: Replace `/tmp/*$$.txt` with `mktemp` and add `trap` cleanup.
- P1: Decide whether hooks must use `ux_lib` output; if yes, source `ux_lib.sh` and remove raw `echo`/color codes.
- P2: Clarify/expand the naming rule matcher to cover the actual user-facing output patterns used in this repo.
- P2: Make shebang scanning recursive (or explicitly document that it is top-level only).

# Conclusion
The hook captures useful project conventions, but its current location and file-selection strategy reduce reproducibility and can add friction. If you address the P0 items (tracked install + staged-only checks), it should become both reliable and fast while preserving the intended naming/shebang guardrails.
