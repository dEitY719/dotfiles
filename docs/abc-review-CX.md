# abc-review-CX (ChatGPT UX Guidelines Review)

## 1) Reviewer Info

- Reviewer: ChatGPT (GPT-5.2)
- Date: 2026-01-19
- Scope: UX guideline compliance audit of `shell-common/**/*.sh` (help functions + user-facing scripts)
- Reference: `shell-common/tools/ux_lib/UX_GUIDELINES.md` and `claude/skills/ux-guidelines/SKILL.md`

## 2) Project Structure Summary

| Path | Purpose |
|------|---------|
| `shell-common/tools/ux_lib/ux_lib.sh` | Central UX library (semantic colors + `ux_*` helpers) |
| `shell-common/functions/*.sh` | Auto-sourced shell commands (`*_help` entry points) |
| `shell-common/tools/custom/*.sh` | Utility scripts (installers, diagnostics) |
| `shell-common/tools/integrations/*.sh` | External tool wrappers |
| `shell-common/setup.sh` | Configuration generator (legacy output style) |

## 3) SOLID Principle Evaluation (UX Surface Area)

- SRP (7/10): UX library is cohesive, but some scripts mix “work + UI formatting + docs generation” (e.g. `shell-common/setup.sh`).
- OCP (8/10): `ux_lib` enables consistent extension, but scripts that bypass it reduce extensibility of UX changes.
- LSP (6/10): Some help functions assume `ux_lib` is always loaded; fewer provide fallback behavior in minimal contexts.
- ISP (8/10): `ux_*` helpers are small and composable; opportunity to standardize spacing/newline patterns.
- DIP (6/10): A few scripts still depend on local ad-hoc output (ANSI codes, `echo -e`) instead of depending on `ux_lib`.

Total: 35/50

## 4) UX Compliance Summary

**Inventory & Adoption:**
- 136 total shell scripts under `shell-common/`
- 102 scripts (75%) call at least one `ux_*` function ✓
- 34 scripts (25%) do not use `ux_*` (mostly `env/` exports, but `setup.sh` is a user-facing exception)

**Key UX Rules:**
- Use semantic `ux_*` helpers instead of hardcoded ANSI codes
- Structure output with `ux_header`, `ux_section`, `ux_table_row`, `ux_bullet`
- Ensure discoverable help and robust error messaging

## 5) Issues (By Severity)

### High Severity

- `shell-common/setup.sh` hardcodes ANSI colors + uses `echo -e` and custom glyphs instead of `ux_lib`.
  - Evidence: `shell-common/setup.sh:10`–`shell-common/setup.sh:15` (`'\033[...]m'` colors), `shell-common/setup.sh:65`–`shell-common/setup.sh:79` (`print_*` wrappers using `echo -e`).
  - UX impact: inconsistent styling vs the rest of the dotfiles; harder to evolve color/format system-wide.
  - Recommendation: source `shell-common/tools/ux_lib/ux_lib.sh` and replace `print_header/print_success/print_info/print_error` with `ux_header/ux_success/ux_info/ux_error`.

- “POSIX sh” help modules using bash-only constructs (`declare -f`, `source`, `BASH_SOURCE`) without a zsh-safe fallback.
  - Evidence:
    - `shell-common/functions/dot_help.sh:6`–`shell-common/functions/dot_help.sh:8`
    - `shell-common/functions/npm_help.sh:8`–`shell-common/functions/npm_help.sh:10`
  - UX impact: help entrypoints become brittle (zsh startup/sourcing behavior, standalone sourcing, linting expectations).
  - Recommendation: standardize UX lib loading with `$SHELL_COMMON` and portable checks (e.g., `type ux_header >/dev/null 2>&1`), and avoid `BASH_SOURCE` in shared modules.

- `shell-common/functions/proxy_help.sh` uses `ux_error` on an error path without guarding that `ux_lib` is loaded.
  - Evidence: `shell-common/functions/proxy_help.sh:79`
  - UX impact: error message can degrade into “command not found” if `ux_error` is unavailable in a minimal shell context.
  - Recommendation: use `type ux_error >/dev/null 2>&1` fallback to `echo ... >&2`, or ensure `ux_lib` is loaded once per session (and document that assumption).

### Medium Severity

- Mixed formatting: `ux_*` helpers combined with raw `echo` and manual `${UX_*}` injections reduces consistency.
  - Example: `shell-common/functions/dproxy_help.sh:14`–`shell-common/functions/dproxy_help.sh:43` prints example blocks and warning text via raw `echo`, includes emoji in-line.
  - Recommendation: render examples as structured bullets/table rows and use `ux_warning/ux_info` consistently (avoid manual `${UX_SUCCESS}...${UX_RESET}` inside raw `echo`).

- “Progress-style” output implemented with raw `echo` + emojis instead of semantic UX helpers.
  - Example: `shell-common/tools/integrations/docker.sh:435`–`shell-common/tools/integrations/docker.sh:471` (`dexport()` output uses emojis + manual `${UX_*}` with plain `echo`).
  - Recommendation: use `ux_section` + `ux_info/ux_success/ux_error` for progress and results; keep raw `echo` limited to command output passthrough.

- Inconsistent iconography across scripts (e.g., `✓/✗/ℹ` vs `✅/❌/ℹ️`) due to local ad-hoc printers.
  - Example: `shell-common/setup.sh:69`–`shell-common/setup.sh:79` vs `shell-common/tools/ux_lib/ux_lib.sh` output conventions.
  - Recommendation: unify through `ux_lib` (single SSOT for icons and style).

### Low Severity

- Spacing/newlines: many help functions use `echo ""` between sections.
  - This is already common in the codebase (and `ux_lib` also uses `echo` for spacing), but if stricter consistency is desired, add/standardize a dedicated spacing helper (e.g., `ux_newline`).

- Emoji in headers like `ux_header "✅ ..."` is widespread.
  - If a “no emojis anywhere” policy is desired, it conflicts with current `ux_lib` conventions and should be clarified at the policy level first.

## 6) Action Items (Priority)

- [ ] P0: Refactor `shell-common/setup.sh` output to depend on `ux_lib` (remove ANSI codes + `echo -e` wrappers).
- [ ] P0: Fix shared-shell portability in `shell-common/functions/dot_help.sh` and `shell-common/functions/npm_help.sh` (no `BASH_SOURCE`/`declare -f` in `#!/bin/sh` modules).
- [ ] P1: Harden `shell-common/functions/proxy_help.sh` error path (guard `ux_error` or ensure `ux_lib` is loaded).
- [ ] P1: Refactor `shell-common/functions/dproxy_help.sh` to avoid raw `echo` blocks and manual color injections where `ux_*` can express the layout.
- [ ] P1: Refactor `dexport()` output in `shell-common/tools/integrations/docker.sh` to use semantic UX functions for progress/results.
- [ ] P2: Clarify emoji policy (allowed in terminal output vs prohibited in docs/code) to resolve current ambiguity.

## 7) Conclusion

**Assessment:**
The codebase shows strong `ux_lib` adoption (75%) with clear guidance for consistent UX. However, legacy scripts (`setup.sh`, help portability issues) bypass the library, creating inconsistency and maintainability friction.

**Summary Metrics:**
- **UX Compliance**: 75% (102/136 scripts using `ux_*`)
- **SOLID Principles**: 35/50 (7.0 average)
- **Overall Health**: Good baseline with targeted improvements needed

**Next Steps:**
Focus on P0/P1 action items to achieve consistent UX across all user-facing interactions.
