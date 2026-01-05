# Dotfiles SOLID Review (Follow-up)

> **Reviewer**: ChatGPT (GPT-5)  
> **Date**: 2026-01-06  
> **Scope**: Commit `d3d80e9` (shell-common refactors from abc-review-CX feedback)

## Findings (ordered by severity)

- **High** — `shell-common/tools/custom/cp_wdown.sh` is not wired into any loader or alias; `cp_wdown` was removed from `aliases/directory.sh` but never re-exported, so the command disappears in new shells. Users lose the workflow entirely (regression vs prior behavior). Add an alias (e.g., in `aliases/directory.sh`) or source the script in shell loaders.
- **High** — `shell-common/env/proxy.sh` removed `check-proxy` alias/wrapper. The new `functions/proxy_help.sh` documents `check-proxy`, but no function or alias exists, so diagnostics can no longer be invoked. Reinstate the alias pointing to `tools/custom/check_proxy.sh` (or a POSIX wrapper) to preserve the interface.
- **Medium** — `shell-common/tools/custom/init.sh:18-29` calls `ux_error` before the UX library is guaranteed to be loaded and before fallback definitions are set. In a failure path (missing DOTFILES_ROOT), this will emit “command not found” instead of a UX-formatted error. Define minimal UX fallbacks before the validation block or avoid using UX functions until after loading.

## Note

Other refactors (POSIX shebangs, proxy_help extraction, README updates, apt/agents_init alias split) align with the previous review. The above gaps should be patched to restore interfaces and avoid regressions.
