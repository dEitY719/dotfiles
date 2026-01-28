# Help System Refactoring: Hierarchical Organization (C2)

**Target**: Refactor my-help system from flat 47-item list to hierarchical categorized structure
**Scope**: `/home/bwyoon/dotfiles/shell-common/functions/my_help.sh`
**AI Tools**: Gemini, Codex (use this document as specification)

---

## 📋 Current State Analysis

### Existing Help Functions (47 total)
All currently registered in `HELP_DESCRIPTIONS` associative array (lines 90-137):

**Package Managers** (5): `uv_help`, `npm_help`, `nvm_help`, `apt_help`, `pip_help`
**Version Control** (1): `git_help`
**System/Network** (7): `sys_help`, `gpu_help`, `proxy_help`, `mount_help`, `docker_help`, `dproxy_help`, `mysql_help`
**Development Tools** (7): `py_help`, `pp_help`, `cli_help`, `mytool_help`, `ux_help`, `psql_help`, `du_help`
**AI/LLM Assistants** (8): `claude_help`, `cc_help`, `claude_plugins_help`, `claude_skills_marketplace_help`, `gemini_help`, `codex_help`, `litellm_help`, `ollama_help`
**Command Line Utilities** (10): `fzf-help`, `fd-help`, `fasd-help`, `ripgrep-help`, `pet-help`, `bat-help`, `p10k_help`, `crt_help`, `zsh-help`, `gc_help`
**Documentation & Knowledge** (5): `dot_help`, `show_doc_help`, `notion_help`, `work_log_help`, `work_help`
**Meta/System** (4): `dir_help`, `opencode_help`, `category_help`, `register_help`

### Current UX Problem
- **`my-help`** output shows all 47 commands as flat list (line 205: "Available help commands(47)")
- Users cannot discover related commands (e.g., "what other AI assistants are available?")
- No way to show help by category (except semi-functional `category_help`)
- Help navigation is overwhelming for new users

---

## 🎯 Target State: Hierarchical Categories

### Proposed Category Taxonomy (9 primary categories)

```
my-help [CATEGORY]
├── Development: git, uv, py, nvm, npm, pp, cli, ux, du, psql, mytool
├── DevOps/Infrastructure: docker, dproxy, sys, proxy, mount, mysql, gpu
├── AI/LLM Assistants: claude, cc, gemini, codex, litellm, ollama, claude_plugins, claude_skills_marketplace
├── CLI Utilities: fzf, fd, fasd, rg (ripgrep), pet, bat, zsh, gc (git-crypt)
├── Configuration: p10k, crt, apt, pip
├── Documentation: dot, show_doc, notion, work_log, work
├── System/Tools: dir, opencode
└── Meta/Help: category, register
```

### Help Invocation Pattern (Final UX)

```bash
# Current (flat list)
my-help                       # Shows all 47 commands

# Target (hierarchical)
my-help                       # Shows categories + instruction
my-help development           # Shows git, uv, py, npm, nvm, pp, cli, ux, du, psql, mytool
my-help ai                    # Shows claude, gemini, codex, litellm, ollama, claude-*, etc.
my-help cli                   # Shows fzf, fd, fasd, rg, pet, bat, zsh, gc
my-help docker                # Shows specific command help (existing behavior)
```

### Hierarchy Structure in Code

Create **category registry** alongside existing help registry:

```bash
# New: Category definitions with parent-child relationships
declare -gA HELP_CATEGORIES=(
    ["development"]="Git, Python, Package Managers, Development Tools"
    ["devops"]="Docker, System, Networking, Database"
    ["ai"]="Claude, Gemini, Codex, LiteLLM, Ollama"
    ["cli"]="Fuzzy Find, File Tools, Shell Utilities"
    # ... etc
)

declare -gA HELP_CATEGORY_MEMBERS=(
    ["development"]="git uv py nvm npm pp cli ux du psql mytool"
    ["devops"]="docker dproxy sys proxy mount mysql gpu"
    ["ai"]="claude cc gemini codex litellm ollama claude_plugins claude_skills_marketplace"
    ["cli"]="fzf fd fasd ripgrep pet bat zsh gc"
    ["config"]="p10k crt apt pip"
    ["docs"]="dot show_doc notion work_log work"
    ["system"]="dir opencode"
    ["meta"]="category register"
)

declare -gA HELP_COMMAND_TO_CATEGORY=(
    ["git"]="development"
    ["uv"]="development"
    ["py"]="development"
    ["docker"]="devops"
    ["claude"]="ai"
    ["fzf"]="cli"
    # ... etc (reverse lookup)
)
```

---

## 📝 Implementation Requirements

### Requirement 1: Category Registry System

**What**: Create category metadata structure
**File**: `shell-common/functions/my_help.sh` (around line 85-140)

**Implementation**:
1. After `HELP_DESCRIPTIONS` initialization (line 40), add `HELP_CATEGORIES` associative array
2. Add `HELP_CATEGORY_MEMBERS` associative array mapping categories to space-separated command list
3. Add `HELP_COMMAND_TO_CATEGORY` reverse-lookup array for fast category discovery
4. Register in `_register_default_help_descriptions()` function

**Success Criteria**:
- `HELP_CATEGORIES["development"]` returns description
- `HELP_CATEGORY_MEMBERS["development"]` returns "git uv py nvm npm pp cli ux du psql mytool"
- `HELP_COMMAND_TO_CATEGORY["git"]` returns "development"

---

### Requirement 2: Update `_my_help_show_all()` Function

**What**: Show categories instead of flat command list
**File**: Lines 144-236

**Current behavior** (line 205):
```bash
ux_section "Available help commands($unique_count)"
# Lists all 47 commands alphabetically
```

**New behavior**:
```bash
# Show 3 sections:
# 1. Category Overview
#    ├── Development (11 commands): git, uv, py, npm, nvm, pp, cli, ux, du, psql, mytool
#    ├── DevOps (7 commands): docker, dproxy, sys, proxy, mount, mysql, gpu
#    ├── AI/LLM (8 commands): claude, cc, gemini, codex, litellm, ollama, claude_plugins, claude_skills_marketplace
#    ... (9 categories total)
#
# 2. Top 5 Popular Commands (sorted by frequency heuristic)
#    → my-help git    (Git version control)
#    → my-help docker (Docker container management)
#    → my-help claude (Claude AI assistant)
#    ... etc
#
# 3. Help Navigation
#    my-help development  - Show all development tools
#    my-help ai           - Show all AI/LLM assistants
#    my-help [command]    - Show specific command help
```

**Implementation Tasks**:
1. Create helper function `_my_help_show_categories()` (new, ~40 lines)
   - Loop through `HELP_CATEGORIES` keys sorted alphabetically
   - For each category: print header + list all members from `HELP_CATEGORY_MEMBERS`
   - Show count: "Development (11 commands)"
2. Modify main `_my_help_show_all()` logic:
   - Keep existing help function discovery (lines 174-196)
   - Replace flat list display (lines 205-220) with category display
   - Simplify example (line 227) to show category usage
3. Update instructions at lines 229-233 to reflect category system

**Success Criteria**:
- Running `my-help` shows 9 categories
- Each category shows member count and abbreviated member list
- No flat 47-item list visible

---

### Requirement 3: Add Category Listing Command

**What**: Allow `my-help [category]` to show all commands in that category
**File**: Lines 239-320 (my_help_impl function)

**New behavior**:
```bash
my-help development       # Show all development tools + their descriptions
my-help ai               # Show all AI assistants + their descriptions
my-help cli              # Show all CLI utilities + their descriptions
```

**Implementation**:
1. Add new function `_my_help_show_category()` (~50 lines)
   - Input: category name (e.g., "development")
   - Validate against `HELP_CATEGORIES` keys
   - Display category description from `HELP_CATEGORIES[category]`
   - List all members from `HELP_CATEGORY_MEMBERS[category]` with their descriptions
   - Format: Similar to current all-commands view but filtered

2. Modify `my_help_impl()` (lines 239-330):
   - Add logic before line 267 to detect if `$1` is a category
   - If category exists: call `_my_help_show_category "$1"`
   - If not found: try existing command lookup (current behavior)
   - Add fallback suggestion: "Did you mean: [closest category]?"

**Edge Cases**:
- Category name case-insensitive: `my-help DEVELOPMENT` = `my-help development`
- Partial category match: `my-help ai` matches `["ai"]` even if user types `my-help "a"` (fuzzy match optional)
- Typo handling: Suggest closest category using fuzzy matching

**Success Criteria**:
- `my-help development` shows all 11 development tools + descriptions
- `my-help ai` shows all 8 AI assistants + descriptions
- `my-help git` still works (existing command, not category)
- `my-help xyz` shows "Category 'xyz' not found. Did you mean: [suggestions]?"

---

### Requirement 4: Update Help Descriptions

**What**: Refine descriptions to reflect hierarchy
**File**: Lines 86-137

**Current examples**:
```bash
HELP_DESCRIPTIONS[git_help]="Git shortcuts and aliases"
HELP_DESCRIPTIONS[uv_help]="UV package manager commands"
```

**Target improvements**:
- Add category context to descriptions
- Make descriptions scannable in category view
- Maximum length: 60 characters

**Examples** (NEW):
```bash
HELP_DESCRIPTIONS[git_help]="[Development] Git version control shortcuts"
HELP_DESCRIPTIONS[uv_help]="[Development] UV package manager and environments"
HELP_DESCRIPTIONS[claude_help]="[AI/LLM] Claude Code CLI and MCP integration"
HELP_DESCRIPTIONS[docker_help]="[DevOps] Docker container commands and aliases"
HELP_DESCRIPTIONS[fzf_help]="[CLI] fzf fuzzy finder keybindings and usage"
```

**Implementation**:
- Optional: Prepend category tags in brackets (e.g., `[Development]`)
- Or: Use consistent format "Category: subcategory - description"
- Must not break existing display logic

**Success Criteria**:
- Descriptions in `_my_help_show_category()` output show category context
- Descriptions fit in ~80 char terminal width
- Descriptions are action-oriented (verbs, not nouns)

---

### Requirement 5: Update Category Helper Function

**What**: Improve existing `category_help` function
**File**: Likely in `shell-common/functions/` (find it)

**Current state**: `category_help` exists (line 133) but may be stub or basic
**Target**: Make it primary interface for category discovery

**Enhancement**:
```bash
category_help()   # Existing function - enhance it
# Should show:
# 1. All available categories
# 2. Brief description of each
# 3. Examples: "category_help development", "my-help ai"
# 4. Interactive: "Show help for category: [development/devops/ai/...]"
```

**Implementation**:
- Find and enhance existing `category_help` function
- Ensure it calls `_my_help_show_all()` or equivalent
- Add category selector/menu if desired

---

## 🔍 Detailed Category Taxonomy

### Categories (Alphabetically Sorted)

```
[AI/LLM Assistants] (8 commands)
- claude_help:                Claude Code MCP assistant
- cc_help:                    Claude Code CLI operations
- claude_plugins_help:        Claude plugins configuration
- claude_skills_marketplace_help: Skills marketplace system
- gemini_help:                Google Gemini AI assistant
- codex_help:                 Codex LLM operations
- litellm_help:               LiteLLM proxy/routing
- ollama_help:                Ollama local model server

[CLI Utilities] (10 commands)
- fzf_help:                   fzf fuzzy finder
- fd_help:                    fd fast file finder
- fasd_help:                  fasd quick directory access
- ripgrep_help:               ripgrep (rg) fast search
- pet_help:                   pet snippet manager
- bat_help:                   bat file viewer
- zsh_help:                   Zsh shell management
- gc_help:                    git-crypt encryption

[Configuration] (4 commands)
- p10k_help:                  Powerlevel10k prompt
- crt_help:                   Certificate management
- apt_help:                   APT package manager
- pip_help:                   Pip Python packages

[Development] (11 commands)
- git_help:                   Git version control
- uv_help:                    UV package manager
- py_help:                    Python environments
- nvm_help:                   Node version manager
- npm_help:                   NPM package manager
- pp_help:                    Python code quality
- cli_help:                   Custom CLI tools
- ux_help:                    UX library functions
- du_help:                    Disk usage analysis
- psql_help:                  PostgreSQL commands
- mytool_help:                Custom utility scripts

[DevOps/Infrastructure] (7 commands)
- docker_help:                Docker containers
- dproxy_help:                Docker corporate proxy
- sys_help:                   System management
- proxy_help:                 Network proxy config
- mount_help:                 Mount management
- mysql_help:                 MySQL database
- gpu_help:                   GPU monitoring

[Documentation] (5 commands)
- dot_help:                   Dotfiles project overview
- show_doc_help:              Documentation viewer
- notion_help:                Notion API integration
- work_log_help:              Work activity tracking
- work_help:                  Work management system

[Meta/System] (2 commands)
- dir_help:                   Directory navigation
- opencode_help:              OpenCode CLI setup

[Meta/Help System] (2 commands)
- category_help:              Category browsing
- register_help:              Help registration guide
```

---

## 📊 Implementation Checklist

### Phase 1: Core Registry (Lines 85-140)
- [ ] Add `HELP_CATEGORIES` associative array
- [ ] Add `HELP_CATEGORY_MEMBERS` associative array (9 categories, 47 members)
- [ ] Add `HELP_COMMAND_TO_CATEGORY` reverse-lookup array
- [ ] Register categories in `_register_default_help_descriptions()`
- [ ] Test: All lookup arrays work correctly

### Phase 2: Display Functions (Lines 144-236)
- [ ] Create `_my_help_show_categories()` function
  - Loop categories sorted alphabetically
  - Print category with member count
  - Show abbreviated member list (max 5 visible, +N more if needed)
- [ ] Modify `_my_help_show_all()` to use new function
- [ ] Remove flat 47-item list from output
- [ ] Test: `my-help` shows categories, not flat list

### Phase 3: Category Command (Lines 267-320)
- [ ] Create `_my_help_show_category()` function
  - Validate category name
  - Display all members with descriptions
  - Format similar to current all-commands view
- [ ] Modify `my_help_impl()` to detect category argument
- [ ] Add case-insensitive category lookup
- [ ] Add fuzzy match fallback
- [ ] Test: `my-help development`, `my-help ai`, etc.

### Phase 4: Polish & Enhancement
- [ ] Update help descriptions with category context (optional)
- [ ] Enhance existing `category_help` function
- [ ] Add interactive category selector (nice-to-have)
- [ ] Test all edge cases (invalid categories, typos, etc.)
- [ ] Document new patterns for future helpers

### Phase 5: Verification
- [ ] `my-help` shows 9 categories (not 47 flat commands)
- [ ] Each category shows member count
- [ ] `my-help [category]` works for all 9 categories
- [ ] `my-help [command]` still works (backward compatibility)
- [ ] Descriptions render correctly
- [ ] No errors or warnings in output
- [ ] Works in both bash and zsh

---

## 💡 Implementation Notes for AI Tools

### Code Style
- Use same formatting as existing code (spacing, indentation, comments)
- Follow POSIX shell compatibility (works in bash/zsh)
- Maintain associative array approach (`declare -gA` pattern)
- Use existing `ux_*` functions for output (ux_header, ux_section, ux_bullet, etc.)

### Function Naming
- Private functions: `_my_help_*` (underscore prefix)
- Public functions: `*_help` (suffix pattern)
- Consistent with existing patterns

### Variable Scope
- Use `declare -gA` for global arrays (bash)
- Use `typeset -gA` for zsh compatibility
- Check examples in lines 35-40

### Error Handling
- Validate category names before lookup
- Return appropriate exit codes (0 for success, 1 for error)
- Provide helpful error messages (e.g., "Category not found. Did you mean...")

### Performance
- Use temp files for large output (see lines 154-222 pattern)
- Avoid repeated lookups (cache results if needed)
- Keep function logic simple and readable

---

## 🧪 Test Cases

### Test 1: Display Categories
```bash
my-help
# Expected: Shows 9 categories with member counts
# NOT: Shows flat list of 47 commands
```

### Test 2: Browse Category
```bash
my-help development
# Expected: Shows all 11 development tools with descriptions
my-help ai
# Expected: Shows all 8 AI assistants with descriptions
```

### Test 3: Backward Compatibility
```bash
my-help git
# Expected: Shows git_help output (existing behavior)
my-help docker
# Expected: Shows docker_help output (existing behavior)
```

### Test 4: Error Handling
```bash
my-help xyz
# Expected: "Category 'xyz' not found. Did you mean: [suggestions]?"
my-help DEVELOPMENT
# Expected: Same as my-help development (case-insensitive)
```

### Test 5: Shell Compatibility
```bash
# In bash: my-help → works
# In zsh:  my-help → works
# Both show identical output
```

---

## 📚 Related Files

**Primary file**: `/home/bwyoon/dotfiles/shell-common/functions/my_help.sh`

**Reference files**:
- `/home/bwyoon/dotfiles/shell-common/tools/ux_lib/ux_lib.sh` (for ux_* functions)
- `/home/bwyoon/dotfiles/shell-common/functions/` (other help implementations)
- `/home/bwyoon/dotfiles/.bashrc` (initialization)
- `/home/bwyoon/dotfiles/.zshrc` (initialization)

**Testing**:
```bash
source ~/.bashrc  # or ~/.zshrc
my-help
my-help development
my-help git
```

---

## 📞 Questions for Implementation

1. Should category names be case-insensitive? (Recommended: YES)
2. Should we show member preview in category listing? (Recommended: YES, max 5 names)
3. Should descriptions include category prefix? (Recommended: YES for clarity)
4. Should there be interactive category selection? (Recommended: NICE-TO-HAVE for v2)
5. Should old flat-list view be kept as hidden option? (Recommended: NO, keep clean)

---

## ✅ Success Criteria (Final)

- [ ] `my-help` shows 9 categories instead of 47 flat commands
- [ ] Each category shows member count: "Development (11 commands)"
- [ ] `my-help [category]` displays all commands in that category
- [ ] `my-help [command]` still works for individual help (backward compatible)
- [ ] Category names are case-insensitive
- [ ] All 47 help functions still work (no breaking changes)
- [ ] Output formatted consistently with existing UX (colors, sections, etc.)
- [ ] Works in both bash and zsh shells
- [ ] No errors or warnings in output
- [ ] Code is maintainable and well-commented
- [ ] New helpers can be easily added to categories in future

---

*Document Version*: 1.0
*Created*: 2026-01-28
*Status*: SPECIFICATION READY FOR AI IMPLEMENTATION
*Target Tools*: Gemini, Codex
