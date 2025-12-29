# Dotfiles Architecture - SOLID Principles

This document describes the complete bash/zsh separation architecture following SOLID design principles.

## Overview

The dotfiles have been redesigned to completely separate bash and zsh configurations while maintaining shared, portable functionality. This eliminates the need for bash emulation mode in zsh and provides native, optimized configurations for each shell.

**Key Achievement:** Reduced ~/.zshrc from 87 lines of complex bash emulation code to 7 lines of clean, native zsh code.

## Directory Structure

```
dotfiles/
├── shell-common/          # POSIX-compatible shared code (both shells)
│   ├── env/               # Environment variables (editor, locale, etc.)
│   ├── aliases/           # Shell aliases (core, system)
│   ├── functions/         # POSIX functions (TBD - for future expansion)
│   └── README.md          # Portable shell configuration guide
│
├── bash/                  # Bash-specific configuration
│   ├── env/               # Bash-specific settings (bash_settings.bash, path.bash)
│   ├── app/               # Bash application modules (git, docker, zsh, etc.)
│   ├── alias/             # Bash-specific aliases (directory_aliases, python_alias)
│   ├── util/              # Bash utilities (myhelp.bash)
│   ├── ux_lib/            # UX library for bash
│   ├── config/            # Configuration files
│   └── main.bash          # Main bash loader (UPDATED)
│
├── zsh/                   # Zsh-specific configuration (NEW)
│   ├── env/               # Zsh-specific settings (empty - placeholder)
│   ├── app/               # Zsh application modules
│   │   ├── zsh.zsh        # Zsh management functions
│   │   └── git.zsh        # Git helper functions
│   ├── util/              # Zsh utilities
│   │   └── myhelp.zsh     # Help system for zsh
│   ├── ux_lib/            # UX library for zsh (NEW)
│   │   └── ux_lib.zsh     # Ported from bash version
│   └── main.zsh           # Main zsh loader (NEW)
│
├── ~/.bashrc              # (Not in repo) → dotfiles/bash/main.bash
└── ~/.zshrc               # (Personal, simplified) → dotfiles/zsh/main.zsh
```

## SOLID Principles Application

### 1. Single Responsibility Principle

Each file/directory has ONE clear responsibility:

- **shell-common/env/**: Only environment variable exports (pure, no logic)
- **shell-common/aliases/**: Only alias definitions (pure, no functions)
- **bash/env/**: Only bash-specific settings (shopt, HISTCONTROL)
- **zsh/app/**: Only zsh application modules (zsh management, help)
- **zsh/ux_lib/**: Only UX library for zsh
- **bash/app/**: Only bash application modules

### 2. Open/Closed Principle

The architecture is **open for extension, closed for modification**:

- New shells can be added (fish, nushell) without modifying existing code
- New portable functions can be added to shell-common/functions/
- New environment variables added to shell-common/env/ are automatically loaded
- Each shell has its own loader (bash/main.bash, zsh/main.zsh)

### 3. Liskov Substitution Principle

**All shells can substitute for each other** while maintaining interface compatibility:

- Same aliases work in bash and zsh (defined in shell-common/aliases/)
- Same environment variables available to both shells (shell-common/env/)
- Both shells can access same help functions
- Functions with same interface work across shells

### 4. Interface Segregation Principle

Each shell **only loads what it needs**:

- Bash doesn't load zsh/*.zsh files
- Zsh doesn't load bash/env/bash_settings.bash
- Portable code goes to shell-common/
- Shell-specific code stays in respective directories
- No unnecessary dependencies

### 5. Dependency Inversion Principle

**High-level code depends on abstractions, not concretions**:

- Loaders (bash/main.bash, zsh/main.zsh) depend on directory structure, not specific files
- UX library provides abstract interface (ux_header, ux_success) not concrete colors
- Configuration is abstracted from shell implementation
- Both loaders follow same pattern of loading env→aliases→utils→apps

## Loading Flow

### Bash Initialization (bash/main.bash)

```
bash/main.bash
  ↓
Load initialization guards & UX library
  ↓
Load shell-common/env/*.sh      (POSIX environment variables)
  ↓
Load shell-common/aliases/*.sh  (POSIX aliases)
  ↓
Load bash/env/*.bash            (Bash-specific settings)
  ↓
Load bash/util/myhelp.bash      (Help system)
  ↓
Load bash/app/*.bash            (Application modules)
  ↓
Output completion message & clean PATH
```

### Zsh Initialization (zsh/main.zsh)

```
~/.zshrc (oh-my-zsh)
  ↓
Load zsh/main.zsh
  ↓
Load shell-common/env/*.sh      (POSIX environment variables)
  ↓
Load shell-common/aliases/*.sh  (POSIX aliases)
  ↓
Load zsh/ux_lib/ux_lib.zsh      (Zsh UX library)
  ↓
Load zsh/env/*.zsh              (Zsh-specific settings)
  ↓
Load zsh/util/myhelp.zsh        (Help system)
  ↓
Load zsh/app/*.zsh              (Application modules)
  ↓
Completion (no output by default)
```

## Files Moved to shell-common/

### Environment Variables (shell-common/env/)

| Original | New | Portability |
|----------|-----|-------------|
| bash/env/editor.bash | shell-common/env/editor.sh | Pure exports ✅ |
| bash/env/locale.bash | shell-common/env/locale.sh | Pure exports ✅ |
| bash/env/development.bash | shell-common/env/development.sh | Pure exports ✅ |
| bash/env/proxy.bash | shell-common/env/proxy.sh | Pure exports ✅ |
| bash/env/security.bash | shell-common/env/security.sh | Converted [[ ]] → [ ] ✅ |
| bash/env/fcitx.bash | shell-common/env/fcitx.sh | Converted [[ ]] → [ ] ✅ |

**Still in bash/env/ (bash-specific):**
- bash_settings.bash - Uses shopt (bash-only feature)
- path.bash - Uses bash arrays and functions

### Aliases (shell-common/aliases/)

| Original | New | Portability |
|----------|-----|-------------|
| bash/alias/core_aliases.bash | shell-common/aliases/core.sh | Pure aliases + simple functions ✅ |
| bash/alias/system_aliases.bash | shell-common/aliases/system.sh | Pure aliases + UX functions ✅ |

## Zsh-Specific Porting

### Key Adaptations (bash → zsh)

| Feature | Bash | Zsh | Notes |
|---------|------|-----|-------|
| Script directory | `BASH_SOURCE[0]` | `${0:h}` | Zsh parameter expansion |
| Array ranges | `$(seq 1 5)` | `{1..5}` | Zsh brace expansion |
| String matching | `[[ $x =~ regex ]]` | `[[ $x =~ regex ]]` | Same in zsh |
| Arithmetic | `$((expr))` | `$((expr))` | Same in both |
| Conditionals | `[[ ]]` test | `[[ ]]` test | Both support bash-style |

### Ported Components

1. **ux_lib.zsh** - Full UX library ported from bash
   - All color definitions work (tput-based)
   - All functions ported (header, success, error, spinner, etc.)
   - Minor syntax adjustments for zsh

2. **zsh/app/zsh.zsh** - Zsh management functions
   - Theme switching (zsh-theme, zsh-themes)
   - Plugin management (zsh-plugins, zsh-update)
   - Config utilities (zsh-edit, zsh-reload, zsh-snippet)
   - Help system (zsh-help)

3. **zsh/app/git.zsh** - Git helper functions
   - Basic git help and command reference
   - Integration with oh-my-zsh git plugin

4. **zsh/util/myhelp.zsh** - Help system
   - Help function registry
   - Centralized help display
   - Category-based help

## Benefits

### ✅ Complete Separation

- No bash emulation mode in zsh (no `emulate -L bash`)
- No bash variable cleanup needed
- No prompt conflicts between shells
- Each shell runs natively

### ✅ Cleaner Code

- 87-line ~.zshrc → 7-line ~/.zshrc
- No complex bash emulation tricks
- Clear responsibility for each module
- Easier to understand and maintain

### ✅ Reduced Blank Line Issues

- Original problem: Blank lines in zsh output (e.g., `gb -a`)
- Root cause: Bash terminal control sequences interfering
- Solution: Native zsh execution without emulation
- Result: Clean output, no extra blank lines ✅

### ✅ Better Performance

- No emulation overhead
- Faster shell startup
- Optimized zsh path
- Better integration with oh-my-zsh

### ✅ Scalability

- Easy to add new shells (fish, nushell)
- New shells just create their own /fish, /nu directories
- Portable code automatically shared via shell-common/
- No changes to existing bash/zsh code needed

### ✅ Maintainability

- Clear structure and organization
- SOLID principles ensure flexibility
- Single responsibility makes debugging easier
- Explicit dependencies and loading order

## Testing Checklist

✅ Bash initialization works
✅ Bash aliases load (ll, la, grep with colors, etc.)
✅ Bash environment variables set (EDITOR=vim, LANG=en_US.UTF-8, etc.)
✅ Zsh initialization works
✅ Zsh aliases load from shell-common
✅ Zsh environment variables set from shell-common
✅ Zsh-specific functions available (zsh-theme, zsh-help, etc.)
✅ UX library works in both shells
✅ No blank line issues in zsh
✅ Shell switching works (bash-switch, zsh-switch)
✅ Portable functions (ux_success, ux_error, etc.) available in both

## Configuration Locations

### Shared Configuration (Use for both bash and zsh)
- Add to `shell-common/env/*.sh`
- Add to `shell-common/aliases/*.sh`
- Add to `shell-common/functions/` (when needed)

### Bash-Only Configuration
- Add to `bash/env/*.bash`
- Add to `bash/app/*.bash`
- Add to `bash/alias/*.bash`

### Zsh-Only Configuration
- Add to `zsh/env/*.zsh`
- Add to `zsh/app/*.zsh`

## Migration Notes

### From Old Architecture

If you had:
```bash
# ~/.zshrc (OLD)
emulate -L bash
setopt shwordsplit
source ...bash files...
emulate -L zsh
PROMPT restoration code
```

Now use:
```zsh
# ~/.zshrc (NEW - simplified)
if [ -f "$HOME/dotfiles/zsh/main.zsh" ]; then
    source "$HOME/dotfiles/zsh/main.zsh"
fi
```

All configuration is automatically loaded from:
- shell-common/ (shared)
- zsh/ (zsh-specific)

## Future Enhancements

1. **shell-common/functions/** - Extract portable POSIX functions
2. **Fish shell support** - Create fish/ directory with fish-specific code
3. **Nushell support** - Create nu/ directory with nushell-specific code
4. **Documentation** - Expand with usage examples and best practices
5. **Testing** - Add automated tests for each shell
6. **Performance** - Profile and optimize loading times

## References

- SOLID Principles: https://en.wikipedia.org/wiki/SOLID
- Bash Manual: https://www.gnu.org/software/bash/manual/
- Zsh Manual: http://zsh.sourceforge.net/Doc/
- Oh My Zsh: https://ohmyz.sh/

## Summary

This architecture achieves **complete separation of concerns** between bash and zsh while maintaining **shared, portable functionality** through shell-common/. By following SOLID principles, the system is:

- **Maintainable**: Clear structure and single responsibility
- **Extensible**: Easy to add new shells or features
- **Testable**: Each component can be tested independently
- **Performant**: Native shell execution without emulation overhead
- **Reliable**: No conflicts between shells, no bash emulation issues

The resulting system is simpler, faster, and more maintainable than the previous bash-emulation-based approach.
