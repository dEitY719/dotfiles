# shell-common - POSIX Compatible Shell Configuration

This directory contains shell-agnostic configuration files that work with any POSIX-compatible shell (bash, zsh, sh, etc.).

## Directory Structure

```
shell-common/
├── env/          # Environment variable definitions
├── aliases/      # Portable alias definitions
├── functions/    # POSIX-compatible functions (TBD)
└── README.md     # This file
```

## Contents

### env/ - Environment Variables

All files in `env/` contain pure environment variable exports or simple POSIX shell commands.

| File | Source | Description |
|------|--------|-------------|
| `editor.sh` | `bash/env/editor.bash` | Editor configuration (EDITOR, VISUAL, GIT_EDITOR) |
| `locale.sh` | `bash/env/locale.bash` | Locale and timezone settings (LANG, TZ) |
| `development.sh` | `bash/env/development.bash` | Development tools (PYTHONPATH, NODE_ENV, JAVA_HOME) |
| `proxy.sh` | `bash/env/proxy.bash` | Network proxy configuration (no_proxy, http_proxy) |
| `security.sh` | `bash/env/security.bash` (converted) | Security settings (SSH_AUTH_SOCK, GPG_TTY) |
| `fcitx.sh` | `bash/env/fcitx.bash` (converted) | Korean input (fcitx) configuration |

**POSIX Conversion Notes:**
- `security.sh`: Converted bash `[[ ]]` to POSIX `[ ]`
- `fcitx.sh`: Converted bash `[[ ]]` to POSIX `[ ]`

### aliases/ - Shell Aliases

All files in `aliases/` contain pure `alias` definitions. These work identically in bash and zsh.

| File | Source | Description |
|------|--------|-------------|
| `core.sh` | `bash/alias/core_aliases.bash` | Basic command aliases (ll, la, cd, rm, cp, mv, etc.) |
| `system.sh` | `bash/alias/system_aliases.bash` | System aliases (ports, myip, top, htop, update, etc.) |

**Note:** These files also contain helper functions (`hg()`, `syshelp()`) that are shell-independent.

## Usage

### Loading in Bash

Add to `~/.bashrc` or via `bash/main.bash`:

```bash
SHELL_COMMON="${HOME}/dotfiles/shell-common"

# Load environment variables
for f in "${SHELL_COMMON}"/env/*.sh; do
    [ -f "$f" ] && source "$f"
done

# Load aliases
for f in "${SHELL_COMMON}"/aliases/*.sh; do
    [ -f "$f" ] && source "$f"
done
```

### Loading in Zsh

Add to `~/.zshrc` or via `zsh/main.zsh`:

```zsh
SHELL_COMMON="${HOME}/dotfiles/shell-common"

# Load environment variables
for f in "${SHELL_COMMON}"/env/*.sh; do
    [ -f "$f" ] && source "$f"
done

# Load aliases
for f in "${SHELL_COMMON}"/aliases/*.sh; do
    [ -f "$f" ] && source "$f"
done
```

## Not Included (Shell-Specific)

Files that remain in their respective shell directories:

### bash/env/
- `bash_settings.bash` - Bash-specific settings (shopt, HISTCONTROL)
- `path.bash` - Contains `clean_paths()` function using bash arrays

### bash/alias/
- `directory_aliases.bash` - Complex directory navigation (may contain bash-specific functions)
- `python_alias.bash` - Python-specific aliases (may be ported later)

## Design Principles (SOLID)

- **Single Responsibility**: Each file focuses on one domain (editor, locale, security, etc.)
- **Open/Closed**: New shells can load these files without modification
- **Liskov Substitution**: All shell loaders can use the same loading pattern
- **Interface Segregation**: Each shell loads only what it needs
- **Dependency Inversion**: Shells depend on this abstraction, not specific shell-dependent code

## POSIX Compatibility

All files follow POSIX shell conventions:
- Use `[ ]` instead of `[[ ]]`
- Use `[ -f file ]` instead of `[[ -f file ]]`
- Use command substitution `$(...)` instead of backticks where needed
- No bash-specific syntax (arrays, pattern matching, etc.)

## Future Enhancements

- [ ] Port remaining portable aliases from `bash/alias/`
- [ ] Extract portable functions from app modules
- [ ] Add cross-shell compatible helper functions in `functions/`
- [ ] Document any caveats for specific shells
