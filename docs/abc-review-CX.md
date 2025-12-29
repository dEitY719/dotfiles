# Bash/Zsh Integration Review (CX)

Context: Reviewed bash/zsh loaders and shared assets for dual-shell use. Touched files for analysis: `bash/main.bash`, `bash/app/git.bash`, `shell-common/aliases/*.sh`, `zsh/main.zsh`, `zsh/app/git.zsh`, `zsh/util/myhelp.zsh`.

## Findings
- Pager regression: `bash/app/git.bash:72` redefines `gb` as `git branch`, overriding the pager-safe alias in `shell-common/aliases/git.sh:26`, so `gb -a` drops into `less`.
- myhelp in zsh: `zsh/util/myhelp.zsh` exists but availability depends on `~/.zshrc` sourcing `zsh/main.zsh`; the loader pins `DOTFILES_ROOT=${HOME}/dotfiles` and returns early if the path differs, so myhelp is missing when the repo lives elsewhere.
- Shared config duplication: `bash/env/*` and `bash/alias/*` duplicate the portable content already in `shell-common/env` and `shell-common/aliases`, causing redefinitions (e.g., git aliases) and future drift.
- Portability gaps: portable aliases still contain bash-specific behavior (`reload`, `src` in `shell-common/aliases/core.sh:5-7`), so adding aliases there does not guarantee correct behavior in zsh.
- No shared function layer: `shell-common/functions/` is empty, so any function defined today lives in shell-specific trees; there is no place to define a function once and load it in both shells.
- Help system split: bash `myhelp` auto-discovers `*help` functions, while zsh `myhelp` relies on manual `HELP_DESCRIPTIONS`; shell-common help topics are not registered, so the experience diverges.
- Loader compliance: zsh loader uses raw `echo`, lacks the `[[ $- == *i* ]]` guard, and loads aliases before UX (opposite of the documented Env → UX → Alias → App order), which drifts from the project rules.

## Plan
- P1 Loader resilience and UX: make the zsh loader resolve its root from the script path, honor the Env → UX → Alias → App order, use `ux_*` logging, and guard non-interactive sessions.
- P2 Shared config dedup: keep portable env/aliases only in `shell-common`, remove or gate duplicates under `bash/`, and ensure git aliases (including `gb`) are sourced from one place.
- P3 Help and function unification: provide a shell-common help registry plus a shared functions directory so new aliases/functions can be defined once and consumed by both shells.

## Tasks
- T1 `gb` pager fix: drop or change the override in `bash/app/git.bash:72` to keep `--no-pager`; verify `bash -ic 'gb -a'` and `zsh -ic 'gb -a'` both print inline.
- T2 zsh loader hardening: compute `DOTFILES_ROOT` from `${(%):-%N}` or `$0`, add the interactive guard, switch warnings to `ux_*`, and reorder loading to Env → UX → Alias → App.
- T3 myhelp availability: confirm `~/.zshrc` symlink to `zsh/zshrc`, ensure `zsh/util/myhelp.zsh` loads before app registrations, and add a smoke test (`zsh -ic 'myhelp'`).
- T4 Help registry parity: either teach zsh `myhelp` to auto-scan `*help` functions (matching bash) or register shell-common topics explicitly so both shells show the same help surface.
- T5 Shared function layer: introduce `shell-common/functions/`, move portable helpers there (after a POSIX audit), and load from both main scripts to satisfy the “define once, use in both shells” requirement.
- T6 Shared config cleanup: remove duplicated env/alias files from `bash/` or mark them bash-only; fix portable aliases like `reload`/`src` to be shell-aware so they behave correctly in zsh.
- T7 Compliance sweep: replace raw `echo` in zsh app/main files with `ux_*`, add interactive guards where PS1 or exec is set, and run `tox -e shellcheck` after the refactor.
