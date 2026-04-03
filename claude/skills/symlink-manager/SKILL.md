---
name: symlink-manager
description: >-
  Manage dotfiles configuration files via symbolic links following standard
  patterns. Use when users request to manage config files with symbolic links,
  organize dotfiles, or set up configuration management.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Dotfiles Symbolic Link Management Skill

## Help

If the argument is `help`, read `references/help.md` and output its content verbatim, then stop.

## Role

Dotfiles Configuration Manager — systematic symbolic link management for
configuration files following established patterns.

## Design Principles

```text
Source:  ~/dotfiles/bash/<category>/<filename>
Target:  ~/<target_dir>/<filename> -> Source
```

**Categories**: `bash/claude/` (Claude Code), `bash/app/` (app-specific),
`bash/config/` (general config), `bash/env/` (environment vars)

**Strategy**: Move original → auto-backup (.backup) → create symlink → verify

## Execution Workflow

### Phase 0: Analysis (ALWAYS)

Identify target file, determine category, locate management script, plan paths.
Read `references/implementation-commands.md` for exact bash commands.

### Phase 1: File Migration (SEQUENTIAL)

Copy file to dotfiles, remove original, create symbolic link, verify.
Read `references/implementation-commands.md` for exact bash commands.

### Phase 2: Management Functions

Add `<app>_init` and optional `<app>_edit_<config>` to `bash/app/<app>.bash`.
Read `references/function-templates.md` for code templates.

### Phase 3: Help Documentation

Update `<app>help` function with new management function descriptions.
Read `references/function-templates.md` for the help block template.

### Phase 4: Version Control (SEQUENTIAL)

Stage and commit all changes.
Read `references/implementation-commands.md` for git commands.

### Phase 5: Validation (ALWAYS)

Read `references/validation.md` for checklists and quality gates.

## Advanced Use Cases

For template file management, multi-environment support, or safety guidelines,
read `references/advanced-patterns.md`.

For a real-world example (Claude Code settings.json),
read `references/example-claude-settings.md`.

## Report

After completion, summarize:
- Files created/modified
- Symbolic links established
- Functions added
- Git commit status
- Validation results

## Command

**When invoked, IMMEDIATELY analyze the target file, determine the appropriate
category, and EXECUTE the symbolic link management workflow following all
phases above.**

Start with Phase 0 analysis and announce plan before making any changes.
