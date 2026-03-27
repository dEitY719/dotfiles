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
- **tools/integrations/**: Third-party tool integrations (fzf, bat, fd, etc.)
- **tools/custom/**: Installation scripts and custom utilities
- **tools/ux_lib/**: UX library (loaded first by main loaders)
- **projects/**: Project-specific utilities (finrx, dmc, smithery)

# Common Mistakes & Fixes

## ERROR 1: Function placed in `tools/custom/` not auto-sourced
**Symptom**: Function defined in `tools/custom/mytool.sh` not available after shell restart
**Root Cause**: `tools/custom/` is NOT auto-sourced by bash/main.bash or zsh/main.zsh
**Fix**: Move function to `functions/` directory instead. Use `tools/custom/` only for executable scripts, not function definitions
**Example**:
```bash
# WRONG - won't be available as a function
tools/custom/my_function.sh  (contains: my_function() { ... })

# RIGHT - auto-sourced and available
functions/my_function.sh     (contains: my_function() { ... })
```

## ERROR 2: Utility script accidentally sourced globally
**Symptom**: Script side effects execute for every shell session (duplicate exports, unwanted aliases)
**Root Cause**: Executable script placed in `functions/` or auto-sourced directory
**Fix**: Place executable scripts in `tools/custom/` (explicit execution only, no auto-sourcing)
**Example**:
```bash
# WRONG - side effects run on every login
functions/setup_dev.sh  (contains: #!/bin/sh ... npm install ...)

# RIGHT - only runs when explicitly executed
tools/custom/setup_dev.sh  (then call: bash tools/custom/setup_dev.sh)
```

## ERROR 3: Hardcoded paths instead of environment variables
**Symptom**: Paths break when dotfiles directory moved or symlinked
**Root Cause**: Using absolute paths (e.g., `/home/user/dotfiles/...`) instead of `$SHELL_COMMON` or `$DOTFILES_ROOT`
**Fix**: Use pre-defined environment variables: `$SHELL_COMMON`, `$DOTFILES_ROOT`, `$HOME`
**Example**:
```bash
# WRONG - breaks if path changes
script_path="/home/bwyoon/dotfiles/shell-common/tools/custom/setup.sh"

# RIGHT - works anywhere
script_path="${SHELL_COMMON}/tools/custom/setup.sh"
```

## ERROR 4: Confusion between `tools/integrations/` vs `tools/custom/`
**Symptom**: Unclear where to place wrapper scripts or third-party integrations
**Root Cause**: Both directories contain `.sh` files, semantics unclear
**Fix**: Remember: **integrations = wrappers for external tools** (auto-sourced), **custom = utility scripts** (explicit execution)
**Example**:
```bash
# integrations/ - Auto-sourced wrappers for external tools
tools/integrations/npm.sh       (wraps npm command)
tools/integrations/docker.sh    (wraps docker command)

# custom/ - Explicit execution scripts
tools/custom/install_npm.sh     (installs npm)
tools/custom/setup_docker.sh    (configures docker)
```

## ERROR 5: Mixing concerns in a single file
**Symptom**: One file does too many things (env setup + aliases + functions), hard to maintain
**Root Cause**: Not splitting by responsibility (env vars, aliases, functions should be separate files)
**Fix**: Use multiple files for different concerns. File names should reflect purpose: `*_help.sh`, `*_env.sh`, etc.
**Example**:
```bash
# WRONG - all mixed in one file
git.sh:
  export GIT_EDITOR="vim"
  alias gs="git status"
  git_help() { ... }

# RIGHT - split by concern
git.sh or aliases/git.sh  (just: alias gs="git status")
env/git.sh               (just: export GIT_EDITOR="vim")
functions/git_help.sh    (just: git_help() { ... })
```

## ERROR 6: Using bash-specific syntax in shell-common
**Symptom**: Function works in bash but fails in zsh (array syntax, `BASH_SOURCE`, etc.)
**Root Cause**: Using bash-only features without shell detection
**Fix**: Use POSIX syntax or wrap with shell detection block (`if [ -n "$BASH_VERSION" ]`)
**Example**:
```bash
# WRONG - bash-only array syntax
my_array=("$@")
files=("${BASH_SOURCE[0]%/*}"/files/*)

# RIGHT - POSIX-compatible
my_array="$@"
for f in "${SHELL_COMMON}"/files/*; do ... done

# Or with bash/zsh detection
if [ -n "$BASH_VERSION" ]; then
    my_array=("$@")
elif [ -n "$ZSH_VERSION" ]; then
    my_array=("${(@s/ /)$@}")  # zsh array expansion
fi
```

## Dependency Management
- Files must be self-contained or check dependencies with `_have`
- No assumptions about load order (except ux_lib loads first)
- Guard expensive operations (e.g., pyenv init) with conditionals

# Decision Tree: Where to Add a New File?

```
1. Is it a simple alias?
   → YES: Add to aliases/*.sh
   → NO: Go to 2

2. Is it an environment variable export?
   → YES: Add to env/*.sh
   → NO: Go to 3

3. Is it a help function (like apt_help, git_help)?
   → YES: Add to functions/*_help.sh
   → NO: Go to 4

4. Is it a utility function called from the shell?
   → YES: Add to functions/*.sh
   → NO: Go to 5

5. Is it a wrapper/integration for a 3rd-party tool (like npm, docker)?
   → YES: Add to tools/integrations/*.sh
   → NO: Go to 6

6. Is it an executable script meant to be run explicitly?
   → YES: Add to tools/custom/*.sh
   → NO: Go to 7

7. Is it bash or zsh-specific?
   → YES: Add to bash/*.bash or zsh/*.zsh (not shell-common)
   → NO: Go to 8

8. Is it project-specific (finrx, smithery, etc.)?
   → YES: Add to projects/<project>/*.sh
   → NO: Check if it fits one of the above categories
```

**Quick Reference Table**:

| Type | Location | Auto-sourced? | Example |
|------|----------|---|---------|
| Alias | `aliases/*.sh` | yes | `gs='git status'` |
| Environment | `env/*.sh` | yes | `export PATH=...` |
| Help function | `functions/*_help.sh` | yes | `apt_help()` |
| Utility function | `functions/*.sh` | yes | `devx()`, `gitlog()` |
| 3rd-party wrapper | `tools/integrations/*.sh` | yes | `npm.sh`, `docker.sh` |
| Executable script | `tools/custom/*.sh` | no | `install_npm.sh`, `setup.sh` |
| Shell-specific | `bash/*.bash` or `zsh/*.zsh` | varies | bash prompt setup |
| Project-specific | `projects/<name>/*.sh` | yes | finrx utilities |

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
- **[Integrations](./tools/integrations/)** — 3rd-party tool wrappers (fzf, bat, fd, pyenv, nvm)
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

## Adding a New Tool Integration (3-Step Pattern)

새 외부 도구(예: bun, foo) 통합 시 항상 3개 파일이 필요:

**Step 1** — `tools/integrations/<tool>.sh` (자동 로드됨)
- PATH export, aliases, install/uninstall 함수
- UX lib guard 패턴 포함:
  ```sh
  if ! type ux_header >/dev/null 2>&1; then
      _dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
      . "${_dir}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
      unset _dir
  fi
  ```

**Step 2** — `functions/<tool>_help.sh` (자동 로드됨)
- `<tool>_help()` 함수 + `alias <tool>-help='<tool>_help'`
- `ux_table_row` / `ux_section` / `ux_bullet` 사용

**Step 3** — `functions/my_help.sh` 수동 등록 (자동 등록 안 됨!)
- `HELP_CATEGORY_MEMBERS[<category>]`에 토픽 추가
- `HELP_DESCRIPTIONS[<tool>_help]` 항목 추가
- 카테고리: `development`, `devops`, `ai`, `cli`, `config`, `docs`, `system`, `meta`

**참조 예시**: `npm.sh` + `npm_help.sh` + `my_help.sh`의 npm 항목

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
