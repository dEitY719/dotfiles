# Module Context
- **Purpose**: POSIX-compatible shared shell utilities for bash and zsh
- **Scope**: Environment variables, aliases, functions, external tool integrations, project utilities
- **Structure**: 5 subdirectories (env, aliases, functions, tools, projects) with 50+ shell scripts
- **Dependencies**: None (self-contained, sourced by bash/main.bash and zsh/main.zsh)

# Operational Commands
- **Lint**: `tox -e shellcheck -- shell-common/**/*.sh`
- **Format**: `shfmt -w -i 4 shell-common/`
- **Reload**: `source ~/.bashrc` (bash) or `source ~/.zshrc` (zsh)
- **Test**: Manual validation via `bash -n <file>` or `zsh -n <file>`

# Implementation Patterns

## File Structure
```bash
#!/bin/sh
# shell-common/<category>/<module>.sh
# POSIX-compatible - no bash/zsh-specific syntax

# Check if command exists
_have() {
    command -v "$1" >/dev/null 2>&1
}

# Guard for optional dependencies
if ! _have mytool; then
    return 0
fi

# Implementation
alias myalias='command --flag'
export MY_VAR="value"
```

## Shell Detection Pattern
```bash
# When bash/zsh-specific features needed
if [ -n "$BASH_VERSION" ]; then
    # Bash-specific code
    IFS=':' read -r -a array <<<"$PATH"
elif [ -n "$ZSH_VERSION" ]; then
    # Zsh-specific code
    array=("${(@s/:/)PATH}")
else
    # POSIX fallback
    OLD_IFS="$IFS"
    IFS=':'
    set -- $PATH
    IFS="$OLD_IFS"
fi
```

## Naming Conventions
- Files: `snake_case.sh`
- Functions: `snake_case` or `tool_command` (e.g., `git_help`, `uv_help`)
- Aliases: Can use dashes (e.g., `bat-help` as alias to `bat_help`)
- Private helpers: Prefix with `_` (e.g., `_have`, `_need`)

# Golden Rules

## POSIX Compatibility
- **DO**: Use `>/dev/null 2>&1` (POSIX)
- **DON'T**: Use `&>/dev/null` (bash-only)
- **DO**: Use `[ ]` for tests (POSIX)
- **DON'T**: Use `[[ ]]` unless in shell-detected branches (bash/zsh-only)
- **DO**: Use `#!/bin/sh` shebang
- **DON'T**: Use bash arrays/associative arrays without shell detection

## Bash/Zsh Sourcing Rules
When sourcing files from scripts loaded by both bash and zsh loaders:
- **Forbidden**: `source "${BASH_SOURCE[0]%/*}/file.sh"` (bash-only, breaks in zsh)
- **Required**: Use pre-defined env vars: `source "${SHELL_COMMON}/tools/custom/file.sh"`
- **Required**: Use DOTFILES_ROOT when appropriate: `source "${DOTFILES_ROOT}/path/to/file.sh"`
- **Acceptable**: Direct execution only: `source "$(dirname "$0")/file.sh"` (for executable scripts)
- **Test in both**: `bash -i -c 'source main.bash && function_name'` and `zsh -c 'source main.zsh && function_name'`

## Output Standards
- **DO**: Use `ux_lib` functions (`ux_header`, `ux_success`, `ux_error`)
- **DON'T**: Use raw `echo` or `printf` (violates UX consistency)
- **Exception**: Simple error messages can use `echo ... >&2` if ux_lib unavailable

## Module Organization
- **env/**: Only `export` statements, no functions
- **aliases/**: Only `alias` definitions, no complex logic
- **functions/**: Utility functions and help systems
- **tools/external/**: Third-party tool integrations (fzf, bat, fd, etc.)
- **tools/custom/**: Installation scripts and custom utilities
- **tools/ux_lib/**: UX library (loaded first by main loaders)
- **projects/**: Project-specific utilities (finrx, dmc, smithery)

## Dependency Management
- Files must be self-contained or check dependencies with `_have`
- No assumptions about load order (except ux_lib loads first)
- Guard expensive operations (e.g., pyenv init) with conditionals

# Testing Strategy

## Manual Testing
```bash
# Test POSIX compliance
shellcheck -s sh shell-common/<category>/<file>.sh

# Test in both shells
bash -n shell-common/<category>/<file>.sh
zsh -n shell-common/<category>/<file>.sh

# Source and test function
bash -c "source shell-common/functions/git.sh && type git_help"
zsh -c "source shell-common/functions/git.sh && type git_help"
```

## Validation Checklist
- [ ] No bash-specific syntax without shell detection
- [ ] No zsh-specific syntax without shell detection
- [ ] All `_have` checks in place for optional tools
- [ ] POSIX-compliant redirections (`>/dev/null 2>&1`)
- [ ] Shebang is `#!/bin/sh` (not `#!/bin/bash`)

# Directory Map

- **[Environment Variables](./env/)** — PATH, locale, editor, proxy, security settings
- **[Aliases](./aliases/)** — Core, directory, git, system, disk usage shortcuts
- **[Functions](./functions/)** — Help systems (my_help, git_help, etc.), utilities
- **[External Tools](./tools/external/)** — fzf, bat, fd, pyenv, nvm integrations
- **[Custom Tools](./tools/custom/)** — Installation scripts, setup utilities
- **[UX Library](./tools/ux_lib/AGENTS.md)** — Styling, logging, interactive components
- **[Projects](./projects/)** — FinRx, dmc-playground, smithery-playground utilities

# Maintenance

## Adding New Modules
1. Choose correct subdirectory (env, aliases, functions, tools, projects)
2. Create `<module>.sh` with `#!/bin/sh` shebang
3. Use POSIX-compatible syntax or shell detection
4. Add `_have` checks for dependencies
5. Test with both bash and zsh
6. Run `shellcheck -s sh <file>.sh`

## Splitting Large Files
If any file exceeds 200 lines:
- Split by functional boundary
- Create new file with clear name
- Update references in loaders (bash/main.bash, zsh/main.zsh)

# Known Issues & Workarounds

## Issue: Shell-specific syntax needed
**Workaround**: Use shell detection pattern (see Implementation Patterns)

## Issue: Function not available in zsh
**Cause**: Bash-only `export -f` used (e.g., in tools/external/zsh.sh)
**Fix**: Add guard `[ -n "$BASH_VERSION" ] || return 0` at top of file

## Issue: Array syntax incompatible
**Cause**: Using bash arrays in POSIX context
**Fix**: Use shell detection or POSIX-compatible loop with `set --`

# References
- **[Bash Module](../bash/AGENTS.md)** — Bash-specific configuration
- **[Zsh Module](../zsh/AGENTS.md)** — Zsh-specific configuration
- **[UX Guidelines](./tools/ux_lib/UX_GUIDELINES.md)** — Output styling standards
- **[Root Context](../AGENTS.md)** — Project-wide standards and TDD protocol
