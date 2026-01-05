# shell-common - Shared POSIX Shell Configuration

This directory contains shell-agnostic configuration and utility files shared between bash and zsh. All files follow POSIX conventions and work with any POSIX-compatible shell.

## Directory Structure

```
shell-common/
├── env/                # Environment variable definitions
│   ├── development.sh
│   ├── editor.sh
│   ├── fcitx.sh
│   ├── locale.sh
│   ├── path.sh
│   ├── proxy.sh
│   ├── security.sh
│   └── local.sh.example
├── aliases/            # Portable command aliases
│   ├── core.sh
│   ├── directory.sh
│   ├── directory_project.sh
│   ├── disk_usage.sh
│   ├── git.sh
│   ├── kill.sh
│   ├── mytool.sh
│   └── system.sh
├── functions/          # Shared functions (help systems, utilities)
│   ├── bat_help.sh
│   ├── cc_help.sh
│   ├── cli_help.sh
│   ├── dot_help.sh
│   ├── fasd.sh
│   ├── fd.sh
│   ├── fzf.sh
│   ├── git_help.sh
│   ├── my_help.sh
│   ├── my_man.sh
│   ├── mytool_help.sh
│   ├── ux_help.sh
│   └── ... (30+ help/utility functions)
├── tools/
│   ├── custom/         # Installation scripts and custom utilities
│   ├── external/       # External tool integrations (fzf, bat, fd, etc.)
│   └── ux_lib/         # UX library (logging, colors, interactive components)
├── projects/           # Project-specific utilities
│   ├── dmc.sh
│   ├── finrx.sh
│   └── smithery.sh
├── config/             # Configuration files
├── setup.sh            # Environment-specific setup
└── README.md           # This file
```

## Module Loading Order

Files are loaded in the following order (see `bash/main.bash` or `zsh/main.zsh`):

1. **Guards & Initialization** (Check for DOTFILES_SKIP_INIT, CODEX environment)
2. **UX Library** (`shell-common/tools/ux_lib/ux_lib.sh`)
3. **Common Environment** (`shell-common/env/*.sh`)
4. **Common Aliases** (`shell-common/aliases/*.sh`)
5. **Common Functions** (`shell-common/functions/*.sh`)
6. **External Tools** (`shell-common/tools/external/*.sh`)
7. **Projects** (`shell-common/projects/*.sh`)
8. **Shell-Specific Environment** (`bash/env/*.sh` or `zsh/env/*.sh`)
9. **Auto-discovery** (Additional shell-specific files)
10. **FZF Bindings** (If fzf is installed)

## Environment Modules (env/)

### Shared Environment Variables

All files in `env/` contain pure environment variable exports or simple POSIX shell commands.

| File | Description |
|------|-------------|
| `development.sh` | Development tools (PYTHONPATH, NODE_ENV, JAVA_HOME) |
| `editor.sh` | Editor configuration (EDITOR, VISUAL, GIT_EDITOR) |
| `fcitx.sh` | Korean input (fcitx) configuration |
| `locale.sh` | Locale and timezone settings (LANG, TZ) |
| `path.sh` | PATH environment with deduplication |
| `proxy.sh` | Network proxy configuration (http_proxy, https_proxy, no_proxy) |
| `security.sh` | Security settings (SSH_AUTH_SOCK, GPG_TTY) |
| `local.sh.example` | Template for local environment overrides |

**Environment Control Variables:**
- `DOTFILES_FORCE_INIT`: Force loading even in non-interactive shells or restricted environments
- `DOTFILES_SKIP_INIT`: Skip loading the dotfiles configuration
- `CODEX_MANAGED_BY_NPM` / `CODEX_CLI`: Auto-detected to prevent loading in Codex CLI

### Alias Modules (aliases/)

All files in `aliases/` contain portable `alias` definitions and shell-independent helper functions.

| File | Description |
|------|-------------|
| `core.sh` | Basic command aliases (reload, src, cd shortcuts) |
| `directory.sh` | Directory navigation aliases (ls variants, cd helpers) |
| `directory_project.sh` | Project-specific directory navigation |
| `disk_usage.sh` | Disk usage and cleanup aliases |
| `git.sh` | Git command shortcuts and aliases |
| `kill.sh` | Process management aliases |
| `mytool.sh` | Custom tool aliases |
| `system.sh` | System administration and maintenance aliases |

### Function Modules (functions/)

These files provide help systems and utilities shared between bash and zsh. Most files follow the `*_help.sh` naming convention.

| Category | Files |
|----------|-------|
| **Help System** | `my_help.sh`, `my_man.sh` |
| **Tool Help** | `bat_help.sh`, `cc_help.sh`, `claude_help.sh`, `cli_help.sh`, etc. |
| **Directory Utilities** | `dot_help.sh`, `dir_help.sh` |
| **Tool Integration** | `fasd.sh`, `fd.sh`, `fzf.sh`, `git.sh`, `pet.sh`, `ripgrep.sh` |
| **System Help** | `docker_help.sh`, `gpu_help.sh`, `security_help.sh`, `sys_help.sh`, `ux_help.sh` |
| **Language/Framework** | `py_help.sh`, `npm_help.sh`, `nvm_help.sh`, `uv_help.sh` |
| **Database** | `mysql_help.sh`, `psql_help.sh` |
| **Shell-Specific** | `zsh_help.sh`, `zsh.sh` (zsh integration) |

### UX Library (tools/ux_lib/)

Central library providing consistent styling and interactive features across bash and zsh.

**Key Functions:**
- `ux_header()` - Styled headers with decorative borders
- `ux_section()` - Section titles with underlines
- `ux_success()`, `ux_error()`, `ux_warning()`, `ux_info()` - Colored messages
- `ux_bullet()`, `ux_numbered()` - List formatting
- `ux_table_row()`, `ux_table_header()` - Table formatting
- `ux_confirm()`, `ux_input()`, `ux_menu()` - Interactive prompts
- `ux_divider()`, `ux_divider_thick()` - Visual separators
- `ux_spinner()`, `ux_with_progress()` - Progress indicators

**Example:**
```bash
ux_header "My Script"
ux_section "Configuration"
ux_bullet "Option 1: Description"
ux_bullet "Option 2: Description"

if ux_confirm "Do you want to proceed?"; then
    ux_with_spinner "Processing..." sleep 2
    ux_success "Done!"
else
    ux_error "Cancelled"
fi
```

### External Tool Integration (tools/external/)

Automatic integration scripts for external tools:
- FZF, bat, fd, ripgrep
- Python tools (pyenv, uv, poetry)
- Node.js tools (nvm, npm)
- Database tools (MySQL, PostgreSQL)
- AI CLI tools (Claude, Gemini)

### Project Utilities (projects/)

Project-specific utility functions:
- `finrx.sh` - FinRx project utilities
- `dmc.sh` - dmc-playground (FastAPI + PostgreSQL) utilities
- `smithery.sh` - smithery-playground (FastAPI) utilities

## Creating Custom Modules

### Adding a New Alias File (Shared)

1. Create a new file in `shell-common/aliases/`:
   ```bash
   touch shell-common/aliases/my_aliases.sh
   ```

2. Add your aliases:
   ```bash
   #!/bin/sh
   # shell-common/aliases/my_aliases.sh
   alias mycommand='long command here'
   alias shortcut='another command'
   ```

3. It will be automatically loaded by both bash and zsh

### Adding a New Function Module (Shared)

1. Create a new file in `shell-common/functions/`:
   ```bash
   touch shell-common/functions/myapp.sh
   ```

2. Add your functions:
   ```bash
   #!/bin/sh
   # shell-common/functions/myapp.sh

   # Check if command exists
   _have() {
       command -v "$1" > /dev/null 2>&1
   }

   myapp_status() {
       _have myapp || { echo "myapp not installed" >&2; return 1; }
       myapp status --verbose
   }
   ```

3. It will be automatically sourced on next shell startup

### Adding Environment Variables (Shared)

1. Create or edit a file in `shell-common/env/`:
   ```bash
   vim shell-common/env/local.sh
   ```

2. Add your variables:
   ```bash
   #!/bin/sh
   # shell-common/env/local.sh
   export MY_VAR="value"
   export ANOTHER_VAR="another value"
   ```

### Adding Bash-Specific Configuration

1. Create a file in `bash/env/` or `bash/util/`:
   ```bash
   touch bash/env/my_bash_config.sh
   ```

2. Add bash-specific code:
   ```bash
   #!/bin/bash
   # bash/env/my_bash_config.sh

   # Bash-specific features only
   shopt -s histappend
   export HISTCONTROL=ignoredups:erasedups
   ```

## Best Practices

1. **Use descriptive file names**: `myapp.sh` not `app1.sh`
2. **Choose the right location**:
   - Shared code → `shell-common/` (use POSIX-compatible syntax)
   - Bash-only code → `bash/` (can use bash-specific features)
3. **Document your code**: Add comments explaining what each section does
4. **Check dependencies**: Use conditional loading for optional tools:
   ```bash
   if command -v myapp >/dev/null 2>&1; then
       alias myapp-quick='myapp --fast'
   fi
   ```
5. **Avoid side effects**: Don't automatically start services or modify files
6. **Keep it modular**: One app or purpose per file
7. **POSIX compatibility for shared files**: Use `#!/bin/sh` and avoid bash-specific syntax in `shell-common/`

## Configuration File Templates

### Shared Module Template (shell-common/)

```bash
#!/bin/sh
# shell-common/functions/myapp.sh
# Description: MyApp utilities (shared between bash and zsh)

# Check if myapp is installed
if ! command -v myapp >/dev/null 2>&1; then
    return 0
fi

# Environment Variables (or put in shell-common/env/myapp.sh)
export MYAPP_HOME="${HOME}/.myapp"
export MYAPP_CONFIG="${MYAPP_HOME}/config"

# Aliases (or put in shell-common/aliases/myapp.sh)
alias myapp-start='myapp daemon start'
alias myapp-stop='myapp daemon stop'
alias myapp-status='myapp status --verbose'

# Helper function
_have() {
    command -v "$1" >/dev/null 2>&1
}

# Functions
myapp_init() {
    # Initialize myapp configuration
    mkdir -p "${MYAPP_CONFIG}"
    ux_info "MyApp initialized at ${MYAPP_HOME}"
}

myapp_clean() {
    # Clean myapp cache
    rm -rf "${MYAPP_HOME}/cache"/*
    ux_info "MyApp cache cleaned"
}
```

### Bash-Specific Module Template (bash/)

```bash
#!/bin/bash
# bash/env/my_bash_feature.sh
# Description: Bash-specific configuration

# Bash-only guard (optional)
[ -n "$BASH_VERSION" ] || return 0

# Use bash-specific features freely
shopt -s histappend
export HISTCONTROL=ignoredups:erasedups

# Bash arrays and associative arrays are OK here
declare -A my_config=(
    [key1]="value1"
    [key2]="value2"
)

# Bash-specific functions
my_bash_function() {
    local var="value"
    echo "Bash-specific: $var"
}
```

## Debugging

### Enable Debug Logging

Set the log level before sourcing:
```bash
export LOG_LEVEL="DEBUG"
source ~/.bashrc
```

### Check What's Loaded

The main.bash/main.zsh script shows:
- Loading progress spinner
- Total files sourced count
- Success banner

### Troubleshooting

**Module not loading:**
1. Check file extension (`.sh` for shared, `.bash` for bash-specific)
2. Verify file is in correct directory:
   - Shared: `shell-common/{env,aliases,functions,tools,projects}/`
   - Bash-only: `bash/{env,util}/`
3. Check file permissions: `chmod 644 shell-common/functions/myapp.sh`
4. Look for syntax errors:
   - Shared: `shellcheck shell-common/functions/myapp.sh`
   - Bash: `bash -n bash/env/myapp.sh`

**Conflicts between modules:**
1. Check for duplicate aliases/functions
2. Verify load order (see "Module Loading Order" section)
3. Use unique prefixes for function names
4. Check both bash/ and shell-common/ for conflicts

**Performance issues:**
1. Minimize expensive operations in module files
2. Use lazy loading for rarely-used functions
3. Profile startup time: `time bash -c 'source ~/.bashrc'`

## Design Principles (SOLID)

- **Single Responsibility**: Each file focuses on one domain (editor, locale, security, etc.)
- **Open/Closed**: New shells can load these files without modification
- **Liskov Substitution**: All shell loaders can use the same loading pattern
- **Interface Segregation**: Each shell loads only what it needs
- **Dependency Inversion**: Shells depend on this abstraction, not specific shell-dependent code

## POSIX Compatibility

All shared files follow POSIX shell conventions:
- Use `[ ]` instead of `[[ ]]`
- Use `[ -f file ]` instead of `[[ -f file ]]`
- Use command substitution `$(...)` instead of backticks where needed
- No bash-specific syntax (arrays, pattern matching, etc.)
- Shebang: `#!/bin/sh` for shared modules

## Related Documentation

- [../README.md](../README.md) - Main project documentation
- [../bash/README.md](../bash/README.md) - Bash-specific configuration
- [../zsh/README.md](../zsh/README.md) - Zsh-specific configuration
- [setup.sh](setup.sh) - Shell-common setup script
