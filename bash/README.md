# Bash Configuration Modules

This directory contains modular bash configuration files that are automatically loaded by `main.bash`.

## Directory Structure

```
bash/
├── alias/              # Command aliases and shortcuts
├── app/                # Application-specific configurations
├── ux_lib/             # UX library (logging, progress, menu)
├── env/                # Environment variables
├── util/               # General utility functions
├── main.bash           # Main entry point (sources all modules)
├── profile.bash        # Bash profile configuration
└── setup.sh            # Setup script (creates symlinks)
```

## Module Loading Order

Files are loaded in the following order (see `main.bash`):

1. **Environment Variables** (`env/*.bash`)
2. **UX Library** (`ux_lib/ux_lib.bash`)
3. **Aliases** (`alias/*.bash`)
4. **Applications** (`app/*.bash`)
5. **Utilities** (`util/*.bash`)

## UX Library (ux_lib/)

### ux_lib/ux_lib.bash

Central UX library providing consistent styling, logging, and interactive features.

**Features:**
- **Semantic Colors**: `UX_PRIMARY`, `UX_SUCCESS`, `UX_ERROR`, etc.
- **Output Functions**: `ux_header`, `ux_section`, `ux_success`, `ux_error`
- **Progress Indicators**: `ux_spinner`, `ux_with_progress`
- **Interactive Components**: `ux_confirm`, `ux_menu`, `ux_input`

**Example:**
```bash
source "${DOTFILES_BASH_DIR}/ux_lib/ux_lib.bash"

ux_header "My Script"
ux_info "This is an informational message"

if ux_confirm "Do you want to proceed?"; then
    ux_with_spinner "Processing..." sleep 2
    ux_success "Done!"
else
    ux_error "Cancelled"
fi
```

## Environment Modules (env/)

### development.bash
Development environment settings and variables.

### editor.bash
Default editor configuration (EDITOR, VISUAL variables).

### korean.bash
Korean language support settings for terminal.

### locale.bash
Locale settings (UTF-8, language preferences).

### path.bash
PATH environment variable configuration. Add custom paths here.

**Example additions:**
```bash
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/myapp/bin:$PATH"
```

### proxy.bash
Proxy server configuration (http_proxy, https_proxy, no_proxy).

**Usage:**
```bash
# Set proxy
export http_proxy="http://proxy.example.com:8080"
export https_proxy="http://proxy.example.com:8080"
export no_proxy="localhost,127.0.0.1"
```

### security.bash
Security-related environment variables and settings.

## Alias Modules (alias/)

### core_aliases.bash
Core command aliases used across the system.

### directory_aliases.bash
Directory navigation aliases (ls variants, cd shortcuts).

**Common aliases:**
```bash
ll='ls -alF'
la='ls -A'
l='ls -CF'
```

### python_alias.bash
Python-related aliases and shortcuts.

### system_aliases.bash
System administration and maintenance aliases.

## Application Modules (app/)

### claude.bash
Claude AI CLI configuration and shortcuts.

### cursor.bash
Cursor editor integration.

### custom_project.bash
Custom project-specific settings.

### gemini.bash
Google Gemini AI CLI configuration.

### git.bash
Git command aliases and enhanced functionality.

**Features:**
- Git status shortcuts
- Branch management helpers
- Commit shortcuts

### jetbrain.bash
JetBrains IDE integration.

### mysql.bash
MySQL database client configuration and shortcuts.

**Features:**
- Connection shortcuts
- Common query aliases
- Database management helpers

### npm.bash
Node.js and npm configuration.

See [npm.bash.md](app/npm.bash.md) for detailed documentation.

### obsidian.bash
Obsidian note-taking app integration.

### postgresql.bash
PostgreSQL database configuration and helpers.

**Features:**
- psql connection shortcuts
- Database management functions
- PostgreSQL environment variables

### pyenv.bash
Python version manager (pyenv) integration.

**Setup:**
```bash
# Initializes pyenv if installed
eval "$(pyenv init -)"
```

### python.bash
Python environment configuration.

### uv.bash
UV (fast Python package installer) configuration.

**Features:**
- UV command shortcuts
- Virtual environment helpers

## Utility Modules (util/)

### my_man.bash
Custom manual page viewer and help system.

## Creating Custom Modules

### Adding a New Alias File

1. Create a new file in `alias/`:
   ```bash
   touch bash/alias/my_aliases.bash
   ```

2. Add your aliases:
   ```bash
   # bash/alias/my_aliases.bash
   alias mycommand='long command here'
   alias shortcut='another command'
   ```

3. It will be automatically loaded by `main.bash`

### Adding a New Application Configuration

1. Create a new file in `app/`:
   ```bash
   touch bash/app/myapp.bash
   ```

2. Add your configuration:
   ```bash
   # bash/app/myapp.bash

   # Environment variables
   export MYAPP_HOME="/path/to/myapp"
   export MYAPP_CONFIG="${HOME}/.config/myapp"

   # Aliases
   alias myapp-start='myapp daemon start'
   alias myapp-stop='myapp daemon stop'

   # Functions
   myapp_status() {
       myapp status --verbose
   }
   ```

3. It will be automatically sourced on next shell startup

### Adding Environment Variables

1. Create or edit a file in `env/`:
   ```bash
   vim bash/env/local.bash
   ```

2. Add your variables:
   ```bash
   # bash/env/local.bash
   export MY_VAR="value"
   export ANOTHER_VAR="another value"
   ```

### Best Practices

1. **Use descriptive file names**: `myapp.bash` not `app1.bash`
2. **Document your code**: Add comments explaining what each section does
3. **Check dependencies**: Use conditional loading for optional tools:
   ```bash
   if command -v myapp &> /dev/null; then
       alias myapp-quick='myapp --fast'
   fi
   ```
4. **Avoid side effects**: Don't automatically start services or modify files
5. **Keep it modular**: One app or purpose per file

## Configuration File Structure Template

```bash
#!/usr/bin/env bash
# bash/app/myapp.bash
# Description: Configuration for MyApp

# Check if myapp is installed
if ! command -v myapp &> /dev/null; then
    return 0
fi

# Environment Variables
export MYAPP_HOME="${HOME}/.myapp"
export MYAPP_CONFIG="${MYAPP_HOME}/config"

# Aliases
alias myapp-start='myapp daemon start'
alias myapp-stop='myapp daemon stop'
alias myapp-status='myapp status --verbose'

# Functions
myapp_init() {
    # Initialize myapp configuration
    mkdir -p "${MYAPP_CONFIG}"
    log_info "MyApp initialized at ${MYAPP_HOME}"
}

myapp_clean() {
    # Clean myapp cache
    rm -rf "${MYAPP_HOME}/cache"/*
    log_info "MyApp cache cleaned"
}

# Auto-initialization (optional)
# [[ ! -d "${MYAPP_HOME}" ]] && myapp_init
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
1. Check file extension is `.bash`
2. Verify file is in correct directory
3. Check file permissions: `chmod 644 bash/app/myapp.bash`
4. Look for syntax errors: `bash -n bash/app/myapp.bash`

**Conflicts between modules:**
1. Check for duplicate aliases/functions
2. Verify load order (env → alias → app → util)
3. Use unique prefixes for function names

**Performance issues:**
1. Minimize expensive operations in module files
2. Use lazy loading for rarely-used functions
3. Profile startup time: `time bash -c 'source ~/.bashrc'`

## Related Files

- [../README.md](../README.md) - Main project documentation
- [setup.sh](setup.sh) - Bash configuration setup script
- [main.bash](main.bash) - Main entry point source code