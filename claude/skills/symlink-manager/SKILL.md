---
name: symlink-manager
description: Manage dotfiles configuration files via symbolic links following standard patterns. Use when users request to manage config files with symbolic links, organize dotfiles, or set up configuration management.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Dotfiles Symbolic Link Management Skill

## Role

You are the Dotfiles Configuration Manager. Implement systematic symbolic link management for configuration files following established patterns and best practices.

## Purpose

Define and enforce standard patterns for managing configuration files as symbolic links in the dotfiles project, ensuring consistency, maintainability, and proper version control.

## Trigger Scenarios

Use this skill when users request:

- "xxx.yyy 파일을 symbolic link로 관리해"
- "dotfiles로 zzz 설정 파일 관리하고 싶어"
- "aaa.conf를 symbolic link로 설정해줘"
- "Manage [file] with dotfiles"
- "Set up symbolic link for [config]"

## Design Principles

### 1. File Location Strategy

```text
Original location: ~/dotfiles/bash/<category>/<filename>
Symbolic link:     ~/<target_dir>/<filename> -> ~/dotfiles/bash/<category>/<filename>
```

**Category Selection Criteria:**

- `bash/claude/`: Claude Code related configuration
- `bash/app/`: Application-specific config and management scripts
- `bash/config/`: General configuration files
- `bash/env/`: Environment variable configuration

### 2. Symbolic Link Creation Strategy

- Move original file to dotfiles repository
- Auto-backup existing files (.backup extension)
- Create and verify symbolic link
- Ensure proper permissions

### 3. Management Functions

Add management functions to corresponding bash script:

- `<app>_init`: Symbolic link initialization function
- `<app>_edit_<config>`: Configuration file editing function (optional)

### 4. Help Documentation

Update `<app>help` function with new management function descriptions.

## Implementation Protocol

### Phase 0: Analysis (ALWAYS)

Execute BEFORE making any changes:

1. **Identify Target File**

   ```bash
   # Verify file exists and check content
   cat <target_file>
   ls -la <target_file>
   ```

2. **Determine Category**

   - Analyze file purpose and content
   - Select appropriate category (claude/app/config/env)
   - Check category directory structure

3. **Locate Management Script**

   ```bash
   # Find or identify bash script location
   cat ~/dotfiles/shell-common/tools/external/<app>.sh
   ```

4. **Plan File Paths**

   - Source: `~/dotfiles/bash/<category>/<filename>`
   - Target: Original file location
   - Backup: `<target_file>.backup`

Output: File analysis, category decision, path planning

### Phase 1: File Migration (SEQUENTIAL)

Execute steps in order:

1. **Backup Current File**

   ```bash
   # Copy to dotfiles location
   cp <target_file> ~/dotfiles/bash/<category>/<filename>

   # Verify copy
   cat ~/dotfiles/bash/<category>/<filename>
   ```

2. **Create Symbolic Link**

   ```bash
   # Remove original file
   rm <target_file>

   # Create symbolic link
   ln -s ~/dotfiles/bash/<category>/<filename> <target_file>
   ```

3. **Verify Link**

   ```bash
   # Check symbolic link
   ls -la <target_file>

   # Verify content accessibility
   cat <target_file>
   ```

### Phase 2: Management Function Implementation

Add to `bash/app/<app>.bash`:

```bash
# Symbolic link initialization function
<app>_init() {
    local source="$HOME/dotfiles/bash/<category>/<filename>"
    local target="<target_file>"

    echo "Initializing <app> configuration..."

    # Create directory if needed
    if [[ ! -d "$(dirname "$target")" ]]; then
        echo "Creating $(dirname "$target") directory..."
        mkdir -p "$(dirname "$target")"
    fi

    # Handle symbolic link
    if [[ -L "$target" ]]; then
        echo "<filename> symbolic link already exists"
    elif [[ -f "$target" ]]; then
        echo "<filename> exists as regular file"
        echo "Backing up to <filename>.backup..."
        mv "$target" "$target.backup"
        ln -s "$source" "$target"
        echo "Created symbolic link for <filename>"
    else
        ln -s "$source" "$target"
        echo "Created symbolic link for <filename>"
    fi

    echo ""
    echo "<app> configuration initialization complete!"
    echo ""
    echo "Symbolic link:"
    ls -la "$target"
}

# Configuration file editing function (optional)
<app>_edit_<config>() {
    local config_file="$HOME/dotfiles/bash/<category>/<filename>"

    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    echo "Editing <app> configuration..."
    echo "File: $config_file"
    echo ""

    ${EDITOR:-vim} "$config_file"

    echo ""
    echo "Configuration file edited"
    echo "Changes will take effect immediately (symlinked)"
}
```

### Phase 3: Help Documentation Update

Add to `<app>help` function:

```bash
${bold}${blue}[Configuration Management]${reset}

  ${green}<app>_init${reset}         : <app> 설정 파일 symbolic link 초기화
                        (dotfiles/bash/<category>/<filename> ↔ <target_file>)
  ${green}<app>_edit_<config>${reset} : <filename> 파일 편집
```

### Phase 4: Version Control (SEQUENTIAL)

```bash
# Check .gitignore if needed
grep "<filename>" .gitignore

# Stage changes
git add bash/<category>/<filename>
git add bash/app/<app>.bash
git add .gitignore  # if modified

# Commit with descriptive message
git commit -m "feat: manage <filename> via dotfiles with symbolic link"
```

### Phase 5: Validation (ALWAYS)

Verify ALL:

- [ ] Symbolic link exists and points to correct source
- [ ] Source file readable via symbolic link
- [ ] `<app>_init` function works correctly
- [ ] `<app>_edit_<config>` function works (if implemented)
- [ ] Help function shows new commands
- [ ] Files staged in git
- [ ] Sensitive files in .gitignore (if applicable)

## Real-World Example: Claude Code settings.json

### Implementation Result

```text
Original location: ~/dotfiles/bash/claude/settings.json
Symbolic link:     ~/.claude/settings.json -> ~/dotfiles/bash/claude/settings.json
Management script: ~/dotfiles/shell-common/tools/external/claude.sh
```

### Added Functions

- `claude_init`: Initialize Claude Code config symbolic links
  - Manages settings.json and statusline-command.sh
  - Auto-backup functionality
- `claude_edit_settings`: Edit settings.json

### Usage

```bash
# Initial setup or reset
claude_init

# Edit configuration
claude_edit_settings

# Show help
claude-help
```

## Safety Guidelines

### File Permissions

- Add sensitive files to .gitignore
- Consider git-crypt for secrets
- Verify file permissions after linking

### Category Selection

- Application-specific management: `bash/app/<app>/`
- Simple config files: `bash/config/`
- Environment variables: `bash/env/`

### Multi-File Management

- Handle multiple config files in single `<app>_init` function
- Example: claude_init manages both settings.json and statusline-command.sh

### Function Naming Convention

- Initialization: `<app>_init`
- Editing: `<app>_edit_<config>`
- Help: `<app>help`

## Advanced Patterns

### Template File Management

For sensitive information:

```bash
# Create template file
cp config.json config.json.template
git add config.json.template

# Add actual file to .gitignore
echo "bash/<category>/config.json" >> .gitignore

# Add template copy logic to init function
if [[ ! -f "$source" ]] && [[ -f "$source.template" ]]; then
    cp "$source.template" "$source"
fi
```

### Multi-Environment Support

```bash
# Environment-specific files
config.local.json    # .gitignore
config.dev.json      # git managed
config.prod.json     # git managed

# Environment selection in init
<app>_init() {
    local env="${1:-local}"
    local source="$HOME/dotfiles/bash/<category>/config.$env.json"
    # ...
}
```

## Execution Workflow

When this skill is invoked:

1. **Analyze** target file and determine category (Phase 0)
2. **Plan & Confirm** file paths and migration strategy
3. **Migrate** file and create symbolic link (Phase 1)
4. **Implement** management functions (Phase 2)
5. **Update** help documentation (Phase 3)
6. **Commit** to version control (Phase 4)
7. **Validate** all changes and functionality (Phase 5)
8. **Report** summary:
   - Files created/modified
   - Symbolic links established
   - Functions added
   - Git commit status
   - Validation results

## Quality Gates

Before completion, ensure ALL:
1. Symbolic link verified and functional
2. Management functions tested
3. Help documentation updated
4. Changes committed to git
5. No sensitive data in repository
6. Backup created for original file

## Command

**When invoked, IMMEDIATELY analyze the target file, determine the appropriate category, and EXECUTE the symbolic link management workflow following all protocols above.**

Start with Phase 0 analysis and announce plan before making any changes.
