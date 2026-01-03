# Bash Configuration Modules

This directory contains modular bash configuration files that are automatically loaded by `main.bash`.

## Directory Structure

```
bash/
├── env/                # Bash-specific environment variables
│   └── bash_interactive.sh
├── util/               # Bash-specific utility functions
│   └── init.bash
├── main.bash           # Main entry point (sources all modules)
├── profile.bash        # Bash profile configuration
├── setup.sh            # Setup script (creates symlinks)
├── README.md           # This file
└── AGENTS.md           # Context for AI agents

shell-common/           # Shared modules (used by both bash and zsh)
├── env/                # Shared environment variables (PATH, locale, etc.)
├── aliases/            # Command aliases and shortcuts
├── functions/          # Shared functions (help systems, git, etc.)
├── tools/
│   ├── custom/         # Installation scripts and utilities
│   ├── external/       # External tool integrations
│   └── ux_lib/         # UX library (logging, progress, styling)
└── projects/           # Project-specific utilities (finrx, dmc, smithery)
```

## Environment Control Variables

You can control the loading behavior of the dotfiles using the following environment variables:

- **`DOTFILES_FORCE_INIT`**: Set this to `1` (or any non-empty value) to force loading the dotfiles configuration even in non-interactive shells or restricted environments (like Codex). This also forces the regeneration of dynamic configurations (MySQL, PostgreSQL).
- **`DOTFILES_SKIP_INIT`**: Set this to `1` to explicitly skip loading the dotfiles configuration.
- **`CODEX_MANAGED_BY_NPM` / `CODEX_CLI`**: Automatically detected to prevent loading in Codex CLI environments to avoid permission errors and timeouts.

## Module Loading Order

Files are loaded in the following order (see `main.bash`):

1. **Guards & Initialization** (Check for DOTFILES_SKIP_INIT, CODEX environment)
2. **UX Library** (`shell-common/tools/ux_lib/ux_lib.sh`)
3. **Common Environment** (`shell-common/env/*.sh`)
4. **Common Aliases** (`shell-common/aliases/*.sh`)
5. **Common Functions** (`shell-common/functions/*.sh`)
6. **External Tools** (`shell-common/tools/external/*.sh`)
7. **Projects** (`shell-common/projects/*.sh`)
8. **Bash Environment** (`bash/env/*.sh`)
9. **Auto-discovery** (Additional bash-specific files)
10. **FZF Bindings** (If fzf is installed)

## UX Library (shell-common/tools/ux_lib/)

### shell-common/tools/ux_lib/ux_lib.sh

Central UX library providing consistent styling, logging, and interactive features across bash and zsh.

**Features:**
- **Semantic Colors**: `UX_PRIMARY`, `UX_SUCCESS`, `UX_ERROR`, etc.
- **Output Functions**: `ux_header`, `ux_section`, `ux_success`, `ux_error`
- **Progress Indicators**: `ux_spinner`, `ux_with_progress`
- **Interactive Components**: `ux_confirm`, `ux_menu`, `ux_input`

**Example:**
```bash
# Already loaded by main.bash

ux_header "My Script"
ux_info "This is an informational message"

if ux_confirm "Do you want to proceed?"; then
    ux_with_spinner "Processing..." sleep 2
    ux_success "Done!"
else
    ux_error "Cancelled"
fi
```

## Environment Modules

### Shared Environment (shell-common/env/)

These environment modules are shared between bash and zsh:

- **development.sh**: Development environment settings and variables
- **editor.sh**: Default editor configuration (EDITOR, VISUAL variables)
- **fcitx.sh**: Fcitx input method configuration (exported env vars and optional autostart; enable with ENABLE_FCITX=true, disabled by default)
- **locale.sh**: Locale settings (UTF-8, language preferences)
- **path.sh**: PATH environment variable configuration with deduplication
- **proxy.sh**: Proxy server configuration (http_proxy, https_proxy, no_proxy)
- **security.sh**: Security-related environment variables
- **local.sh.example**: Template for local overrides (not tracked in git)

**Example PATH additions:**
```bash
# In shell-common/env/path.sh
export PATH="$HOME/.local/bin:$PATH"
export PATH="/usr/local/go/bin:$PATH"
```

**Example proxy configuration:**
```bash
# In shell-common/env/proxy.sh
export http_proxy="http://proxy.example.com:8080"
export https_proxy="http://proxy.example.com:8080"
export no_proxy="localhost,127.0.0.1"
```

### Bash-Specific Environment (bash/env/)

- **bash_interactive.sh**: Bash-specific interactive shell settings

## Alias Modules (shell-common/aliases/)

These alias files are shared between bash and zsh:

- **core.sh**: Core command aliases (reload, src, cd shortcuts)
- **directory.sh**: Directory navigation aliases (ls variants, cd helpers)
- **directory_project.sh**: Project-specific directory navigation
- **disk_usage.sh**: Disk usage and cleanup aliases
- **git.sh**: Git command shortcuts and aliases
- **kill.sh**: Process management aliases
- **mytool.sh**: Custom tool aliases
- **system.sh**: System administration and maintenance aliases

**Example usage:**
```bash
# From core.sh
reload              # Reload shell configuration
src                 # Source appropriate rc file

# From directory.sh
ll                  # ls -alF
la                  # ls -A

# From git.sh
ga                  # git add
gc                  # git commit
gp                  # git push
```

## Function Modules (shell-common/functions/)

These function files provide help systems and utilities shared between bash and zsh:

- **my_help.sh**: Main help system registry and display
- **my_man.sh**: Custom manual page viewer
- **bat.sh**: bat (cat alternative) integration
- **cc_help.sh**: Claude Code help
- **claude_help.sh**: Claude AI CLI help
- **cli_help.sh**: CLI tools help
- **codex_help.sh**: Codex help functions
- **dir_help.sh**: Directory navigation help
- **docker_help.sh**: Docker help
- **dproxy_help.sh**: Docker proxy help
- **du_help.sh**: Disk usage help
- **fasd.sh**: Fast directory navigation
- **fd.sh**: fd (find alternative) integration
- **fzf.sh**: Fuzzy finder integration
- **gc_help.sh**: Garbage collection help
- **gemini_help.sh**: Gemini AI help
- **git_help.sh**, **git.sh**: Git help and utilities
- **gpu_help.sh**: GPU monitoring help
- **litellm_help.sh**: LiteLLM help
- **mysql_help.sh**: MySQL help
- **mytool_help.sh**, **mytool.sh**: Custom tool help
- **npm_help.sh**: npm help
- **nvm_help.sh**: nvm (Node version manager) help
- **p10k.sh**: Powerlevel10k theme integration
- **pet.sh**: Pet (snippet manager) integration
- **pp_help.sh**: Project-specific help
- **psql_help.sh**: PostgreSQL help
- **py_help.sh**: Python help
- **ripgrep.sh**: ripgrep integration
- **sys_help.sh**: System help
- **uv_help.sh**: uv (Python package manager) help
- **ux_help.sh**: UX library help
- **zsh_help.sh**, **zsh.sh**: Zsh help and utilities

## External Tool Integration (shell-common/tools/external/)

Integration scripts for external tools (automatically loaded):

- FZF, bat, fd, ripgrep integrations
- Python tools (pyenv, uv, poetry)
- Node.js tools (nvm, npm)
- Database tools (MySQL, PostgreSQL)
- AI CLI tools (Claude, Gemini)

## Project Utilities (shell-common/projects/)

Project-specific utility functions:

- **finrx.sh**: FinRx project utilities
- **dmc.sh**: dmc-playground (FastAPI + PostgreSQL) utilities
- **smithery.sh**: smithery-playground (FastAPI) utilities

## Bash Utility Modules (bash/util/)

- **init.bash**: Bash initialization utilities

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

### Best Practices

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

## Configuration File Structure Templates

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

The main.bash script shows:
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

## Related Files

- [../README.md](../README.md) - Main project documentation
- [setup.sh](setup.sh) - Bash configuration setup script
- [main.bash](main.bash) - Main entry point source code
