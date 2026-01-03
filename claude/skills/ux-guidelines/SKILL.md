---
name: ux-guidelines
description: Apply UX_GUIDELINES.md standards to shell functions and help text. Use when refactoring help functions, creating new help commands, or ensuring consistent formatting with semantic UX functions (ux_header, ux_section, ux_bullet, etc).
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# UX Guidelines Skill

## Role

You are the UX Consistency Specialist. Ensure all help functions and user-facing shell commands follow the dotfiles UX guidelines. Refactor hardcoded text output to use semantic UX library functions, maintain consistent color schemes, and improve readability.

## Trigger Scenarios

Use this skill when:

- "proxy_help() 함수를 UX 가이드라인에 따라 리팩토링해"
- "새 help 함수를 만드는데 UX_GUIDELINES 규칙을 따르고 싶어"
- "현재 help 텍스트를 ux_lib 함수들로 다시 작성해"
- "이 함수를 cc_help 스타일로 리팩토링해"
- "help 함수들의 formatting을 일관되게 해줘"

## UX Guidelines Foundation

The UX guidelines are defined in: `shell-common/tools/ux_lib/UX_GUIDELINES.md`

### Core Principles

1. **Consistency**: All functions use the same color scheme and formatting
2. **Discoverability**: Help text is always available with no arguments; `my-help` lists all topics
3. **Safety**: Destructive operations require explicit confirmation
4. **Feedback**: Clear success/error/warning messages with progress indicators
5. **Readability**: Well-structured output with semantic colors

### Color Semantics

| Color | Usage | Function |
|-------|-------|----------|
| **Primary (Blue)** | Headers, section titles, command names | `ux_header()`, `ux_section()` |
| **Success (Green)** | Successful operations, valid states | `ux_success()` |
| **Warning (Yellow)** | Warnings, confirmations, risky actions | `ux_warning()` |
| **Error (Red)** | Errors, failed operations, critical issues | `ux_error()` |
| **Info (Cyan)** | Information, tips, guidance | `ux_info()` |
| **Muted (Gray)** | Secondary info, hints, dividers | `ux_divider()` |

## Available UX Functions

```bash
ux_header "Title"              # Styled header with border box
ux_section "Title"             # Section header with underline
ux_success "Message"           # Green success message
ux_error "Message"             # Red error message
ux_warning "Message"           # Yellow warning message
ux_info "Message"              # Cyan info message
ux_bullet "Text"               # Bullet point with • prefix
ux_numbered "N" "Text"         # Numbered list item
ux_divider                     # Thin horizontal line
ux_divider_thick               # Thick horizontal line
ux_confirm "Question"          # Interactive yes/no prompt
ux_input "Prompt"              # Interactive text input
ux_menu "Item1" "Item2" ...    # Interactive menu selection
ux_table_row "Col1" "Col2"...  # Formatted table row
ux_table_header "Col1" ...     # Table header row
```

## Refactoring Pattern

### Step 1: Identify Current Implementation

Check if the function uses:
- Hardcoded `cat <<EOF ... EOF` output
- Hardcoded ANSI color codes
- Plain text formatting with emojis
- Inconsistent spacing/alignment

### Step 2: Load UX Library

Add conditional loading at module startup:

```bash
# Load UX library if not already loaded
if ! declare -f ux_header >/dev/null 2>&1; then
    source "${BASH_SOURCE[0]%/*}/../tools/ux_lib/ux_lib.sh" 2>/dev/null || true
fi
```

### Step 3: Replace Output with UX Functions

**Before:**
```bash
proxy_help() {
    cat <<-'EOF'

[Proxy(Corporate) Commands & Diagnostics]

🔍 DIAGNOSTIC COMMANDS
  check-proxy          # Run full diagnostic
  check-proxy env      # Environment variables only
EOF
}
```

**After:**
```bash
proxy_help() {
    ux_header "Proxy(Corporate) Commands & Diagnostics"

    ux_section "Diagnostic Commands"
    ux_bullet "check-proxy          Run full diagnostic"
    ux_bullet "check-proxy env      Environment variables only"
    echo ""
}
```

### Step 4: Organize Content Logically

Use UX sections to group related commands:

- `ux_header()` - Main title
- `ux_section()` - Each logical grouping
- `ux_bullet()` - Command lists
- `ux_numbered()` - Step-by-step instructions
- `ux_warning()` / `ux_info()` - Important notes
- `echo ""` - Visual separators between sections

### Step 5: Test Output

```bash
bash -c "source ./shell-common/env/proxy.sh && proxy_help"
```

Verify:
- Colors display correctly
- Alignment is consistent
- All information is visible
- Sections are clearly separated

## Reference Example

See: `shell-common/functions/cc_help.sh`

```bash
cc_help() {
    ux_header "Claude Code Usage Commands"

    ux_section "Installation"
    ux_bullet "Global prefix: npm install -g ccusage --prefix=\$HOME/.npm-global"
    echo ""

    ux_section "Quick Commands (Aliases)"
    ux_table_row "ccd" "ccusage daily --breakdown" "Token usage by model"
    ux_table_row "ccs" "ccusage session --sort tokens" "Session analysis"
    echo ""
}

alias cc-help='cc_help'
```

## Decision Framework

### Use `ux_bullet()` For:
- Command lists
- Quick reference items
- Short descriptions

### Use `ux_numbered()` For:
- Step-by-step instructions
- Recipes that must be followed in order
- Conditional procedures

### Use `ux_table_row()` For:
- Command-to-description mappings
- Structured data with multiple columns
- Command aliases and their meanings

### Use `ux_section()` For:
- Logical groupings of related commands
- Different use cases or modes
- Separating concerns (Setup, Configuration, Troubleshooting, etc)

### Use `ux_warning()` / `ux_info()` For:
- Important caveats
- Reference links
- Notes and tips
- Best practices

## Workflow

When refactoring a help function:

1. **Read** the current help function implementation
2. **Identify** sections and logical groupings
3. **Create** a plan of which UX functions to use
4. **Edit** to replace hardcoded output with UX functions
5. **Test** the output to verify formatting
6. **Commit** with clear message about UX improvements

## Example Commit Message

```
refactor: Reformat proxy_help() to follow UX guidelines

Refactor proxy_help() function to use UX library functions (ux_header,
ux_section, ux_bullet, ux_numbered, ux_warning, ux_info) instead of
hardcoded text with cat <<EOF.

Changes:
- Load ux_lib.sh conditionally at module startup
- Replace hardcoded text output with semantic UX function calls
- Reorganize help content into logical sections
- Use ux_bullet() for command lists
- Use ux_numbered() for step-by-step recipes
- Use ux_warning() and ux_info() for notes

Benefits:
- Consistent with UX_GUIDELINES.md standards
- Automatic color and formatting consistency
- Better readability and structure
- Easier to maintain
```

## Best Practices

1. **Never hardcode colors** - Use `UX_PRIMARY`, `UX_SUCCESS`, etc via UX functions
2. **Use semantic functions** - Prefer `ux_success()` over `echo "${UX_SUCCESS}..."`
3. **Provide clear feedback** - Inform user about operation state
4. **Keep it clean** - Remove commented-out `tput` definitions after migration
5. **Test across shells** - Verify in both bash and zsh
6. **Document choices** - Explain why sections are organized certain way

## Files to Know

```
shell-common/tools/ux_lib/ux_lib.sh         # UX function library
shell-common/tools/ux_lib/UX_GUIDELINES.md  # Full guidelines
shell-common/functions/cc_help.sh            # Reference pattern
shell-common/tools/custom/demo_ux.sh        # Interactive demo
shell-common/tools/custom/check_ux_consistency.sh  # Validation tool
```

## Validation

Run consistency checker to ensure all help functions follow guidelines:

```bash
shell-common/tools/custom/check_ux_consistency.sh
```

## Execution

When invoked:

1. Read the current help function/module
2. Identify sections and organize logically
3. Plan which UX functions to use
4. Conditionally load ux_lib.sh if needed
5. Replace hardcoded output with UX function calls
6. Test the refactored output
7. Create commit documenting the changes

**Start by reading the target file and understanding its current structure.**
