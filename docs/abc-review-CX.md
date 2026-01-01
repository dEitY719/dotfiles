## Cross-Shell Loader Review

### Directory Highlights
- **`bash/`** — `main.bash` now focuses on guarding non-interactive shells, normalizing `DOTFILES_BASH_DIR`, and delegating everything else to `shell-common`. Only `env/`, `util/`, and setup glue remain, so most feature work has moved out of this tree.
- **`zsh/`** — Native loader (`main.zsh`) plus `app/` overrides and the stock `zshrc`. zsh keeps Oh My Zsh bootstrap logic, then mirrors the same Env → UX → Alias/Function → App phases the bash loader performs.
- **`shell-common/`** — Real “single source of truth”: POSIX-ish env exports, shared aliases, functions, `projects/` helpers, and both `tools/external` (sourced at login) and `tools/custom` (standalone executables). `tools/ux_lib` centralizes all UX primitives that bash/zsh depend on.

### SOLID Assessment
- **SRP** — Most files handle one concern (e.g., `shell-common/functions/git.sh`, `shell-common/env/path.sh`). Exceptions: `shell-common/projects/custom.sh` mixes FinRx, dmc-playground, smithery, and shared secrets in one blob, so splitting per project would restore SRP.
- **OCP** — Adding a new alias/tool typically means dropping a `.sh` file into the right directory; loaders auto-source by glob. This refactor clearly improved openness to extension.
- **LSP** — Shared modules assume `ux_lib` + POSIX shell semantics. They mostly work in both bash and zsh, but `shell-common/tools/external/zsh.sh` uses bash-only features (`export -f`), so zsh cannot substitute cleanly until that script is hardened or gated.
- **ISP** — Bash/zsh consume only what they need (env, alias, ux, app). The lingering “mega project” module forces consumers to pull in unrelated project state, so splitting that file plus providing opt-in wrappers would tighten interfaces.
- **DIP** — Both shells depend on abstractions: `ux_lib`, `safe_source`, and `shell-common` definitions. A few modules still fall back to `echo`/emoji instead of going through `ux_lib`, which weakens the dependency boundary.

### Findings & Recommendations
1. **zsh loader sets `local` at top-level** — `zsh/main.zsh:156-175` calls `local app_files=()` outside any function, which raises `local: not in a function` each time `.zshrc` loads. Wrap the app-loading logic in a helper (e.g., `load_zsh_apps()`) or replace `local` with `typeset -ga` inside a function so zsh stays quiet.
2. **`shell-common/tools/external/zsh.sh` is bash-only** — The file is sourced by both shells (`zsh/main.zsh` line 109) but begins with `#!/bin/bash` and ends with `export -f install-zsh ...` (`shell-common/tools/external/zsh.sh:63`), which zsh does not support. Either (a) move bash-only exports back under `bash/`, (b) guard the file with `[ -n "$BASH_VERSION" ] || return 0`, or (c) convert it to POSIX so zsh can source it without errors.
3. **Loaders still emit raw `echo` output** — Both `bash/main.bash:231-234` and `zsh/main.zsh:41-77` use `echo` (and emojis) for success/warning text even though the UX guidelines require `ux_success/ux_error`. Replace those printfs with the UX helpers (once the UX lib is confirmed loaded) to keep output consistent.
4. **`shell-common/projects/custom.sh` violates SRP and leaks config** — One file currently defines hosts, DB credentials, and runners for three unrelated projects (`shell-common/projects/custom.sh:1-190`). Break these into `projects/finrx.sh`, `projects/dmc.sh`, etc., move secrets into `shell-common/env/local.sh.example`, and expose a lightweight dispatcher that sources only the project the user asked for.
5. **Shared modules still mix in raw `echo`/emoji** — Example: `shell-common/tools/external/docker.sh:33-86` prints usage via literal `echo` statements and emoji bullets, bypassing `ux_bullet` / `ux_info`. Standardizing on the UX helpers will satisfy the “No raw echo” rule and make CLI output uniform.
6. **Docs drifted after the refactor** — `bash/README.md:7-37` and `bash/AGENTS.md:1-39` still describe the pre-refactor tree (`alias/`, `app/`, `ux_lib/` folders that no longer exist in `bash/`). Update those docs to explain that most modules now live under `shell-common/`, otherwise new contributors will keep hunting for directories that were deleted.
7. **POSIX headers do not match implementation** — Several files under `shell-common/` start with `#!/bin/sh` but rely on bash-isms like `local` (e.g., `shell-common/projects/custom.sh:130-164`). Either change the shebang to `#!/usr/bin/env bash`/`zsh` or remove non-POSIX constructs so sourcing through `/bin/sh` truly works.

### Next Steps
1. Harden `zsh/main.zsh` and `shell-common/tools/external/zsh.sh` so zsh sources complete without warnings, then smoke-test with `zsh -f` to ensure no regressions.
2. Refactor `shell-common/projects/custom.sh` into smaller project-scoped modules, and relocate sensitive defaults into `env/local.sh.example` so they can be overridden without editing tracked files.
3. Sweep the shared modules for `echo`/emoji usage and replace them with `ux_lib` helpers; start with the loader completion messages and the high-traffic Docker/Apt helpers.
4. Refresh `bash/README.md` and `bash/AGENTS.md` to describe the new architecture and point readers toward `shell-common/` for most modules.
