# Shebang Consistency Analysis Report

**Date**: 2026-01-03
**Repository**: /home/bwyoon/dotfiles
**Total Files Analyzed**: 127 (.sh and .bash files)

---

## Executive Summary

This report analyzes all shell script files for bash-specific features and shebang consistency. The goal is to ensure that:
1. Files using bash-specific features have `#!/bin/bash` shebang
2. POSIX-compatible files use `#!/bin/sh` for better portability
3. Source-only files (non-executable, sourced by other scripts) have appropriate or optional shebangs

### Statistics

| Category | Count | Description |
|----------|-------|-------------|
| **Total files** | 127 | All .sh and .bash files |
| **Bash-required** | 79 | Files using bash-specific features |
| **POSIX-compatible** | 48 | Files with no bash-specific features |
| **Correct shebang** | 88 | Files with appropriate shebang |
| **Wrong shebang** | 26 | Files needing shebang correction |
| **Missing shebang** | 6 | Files missing shebang entirely |
| **Source-only** | 7 | Non-executable files (shebang optional) |

---

## Priority Issues (shell-common/env/ and shell-common/functions/)

**13 priority files need attention** in the core environment and functions directories.

### Critical: Missing Shebangs (3 files)

These files use bash-specific features but have NO shebang:

#### 1. `shell-common/env/path.sh`
- **Current**: NONE
- **Recommended**: `#!/bin/bash`
- **Reason**: Uses `[[_]]`, `BASH_VERSION`, arrays, parameter expansion
- **Bash features detected**:
  - Double brackets `[[ ]]`
  - `BASH_VERSION` variable
  - Array operations: `declare -A`, `read -r -a`
  - Parameter expansion: `${var%/}`, `${var:+}`

#### 2. `shell-common/env/proxy.sh`
- **Current**: NONE
- **Recommended**: `#!/bin/bash`
- **Reason**: Uses `BASH_SOURCE`, parameter expansion
- **Bash features detected**:
  - `BASH_SOURCE[0]` variable
  - Parameter expansion: `${BASH_SOURCE[0]%/*}`

#### 3. `shell-common/env/security.sh`
- **Current**: NONE
- **Recommended**: `#!/bin/bash`
- **Reason**: Uses `BASH_SOURCE`, parameter expansion
- **Bash features detected**:
  - `BASH_SOURCE[0]` variable
  - Parameter expansion: `${var%/}`, `${var:-}`

### Wrong Shebangs (10 files)

These files have incorrect shebangs for their content:

#### shell-common/env/

##### 1. `shell-common/env/fcitx.sh`
- **Current**: `#!/usr/bin/env sh`
- **Recommended**: `#!/bin/bash`
- **Reason**: Uses parameter expansion `${var%/}`, `${var:-}`
- **Fix**: Change to `#!/bin/bash` (uses bash-specific parameter expansion)

#### shell-common/functions/

##### 2. `shell-common/functions/bat.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: Consider keeping as `#!/bin/sh` (false positive)
- **Note**: "source" detected in comments/strings, not actual bash source command

##### 3. `shell-common/functions/claudehelp.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: Consider keeping as `#!/bin/sh` or verify actual usage
- **Note**: May have false positive from "source" in strings

##### 4. `shell-common/functions/fzf.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: `#!/bin/bash`
- **Reason**: Uses arrays (`read -r -a`)

##### 5. `shell-common/functions/gpuhelp.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: `#!/bin/bash`
- **Reason**: Uses double brackets `[[ ]]`

##### 6. `shell-common/functions/mytool_help.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: Consider keeping as `#!/bin/sh` (false positive)
- **Note**: "source" detected in comments/strings

##### 7. `shell-common/functions/psqlhelp.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: `#!/bin/bash`
- **Reason**: Uses double brackets `[[ ]]`

##### 8. `shell-common/functions/pyhelp.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: Consider keeping as `#!/bin/sh` (false positive)
- **Note**: "source" detected in comments/strings

##### 9. `shell-common/functions/uxhelp.sh`
- **Current**: `#!/usr/bin/env sh`
- **Recommended**: Consider keeping as `#!/usr/bin/env sh` (false positive)
- **Note**: "source" detected in comments/strings

##### 10. `shell-common/functions/zsh.sh`
- **Current**: `#!/bin/sh`
- **Recommended**: Consider keeping as `#!/bin/sh` (false positive)
- **Note**: "source" detected in comments/strings

---

## All Files Needing Changes

### A. Wrong Shebang (26 files total)

#### Files that should use `#!/bin/sh` (POSIX-compatible)

These files are currently using `#!/bin/bash` but have no bash-specific features:

1. `setup.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
2. `shell-common/aliases/directory_project.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
3. `shell-common/aliases/disk_usage.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
4. `shell-common/aliases/kill.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
5. `shell-common/tools/external/gemini.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
6. `shell-common/tools/external/jetbrain.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
7. `shell-common/tools/external/nvm.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
8. `shell-common/tools/external/obsidian.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
9. `shell-common/tools/external/pyenv.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`
10. `shell-common/tools/external/uv.sh` - Currently: `#!/bin/bash` → Change to: `#!/bin/sh`

#### Files that should use `#!/bin/bash` (Bash-required)

These files use bash-specific features but have wrong shebang:

1. `shell-common/env/fcitx.sh` - Currently: `#!/usr/bin/env sh` → Change to: `#!/bin/bash`
   - Uses: parameter expansion

2. `shell-common/aliases/directory.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: arrays, process substitution, readarray/mapfile

3. `shell-common/functions/fzf.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: arrays

4. `shell-common/functions/gpuhelp.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: double brackets `[[ ]]`

5. `shell-common/functions/psqlhelp.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: double brackets `[[ ]]`

6. `shell-common/projects/dmc.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: parameter expansion

7. `shell-common/tools/custom/devx.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: BASH_SOURCE, arrays, parameter expansion

8. `shell-common/tools/external/claude.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: arrays, parameter expansion

9. `shell-common/tools/external/docker.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
   - Uses: parameter expansion

10. `shell-common/tools/ux_lib/ux_lib.sh` - Currently: `#!/bin/sh` → Change to: `#!/bin/bash`
    - Uses: BASH_SOURCE, BASH_VERSION, arrays, parameter expansion, brace expansion

### B. Missing Shebang (6 files)

These files need shebangs added:

#### Bash-required files (need `#!/bin/bash`)

1. **`bash/main.bash`** - CRITICAL
   - Recommended: `#!/bin/bash`
   - Uses: `[[_]]`, BASH_SOURCE, arrays, process substitution, parameter expansion, shopt, declare flags, regex match

2. **`bash/profile.bash`**
   - Recommended: `#!/bin/bash`
   - Uses: source command

3. **`shell-common/env/path.sh`** - PRIORITY
   - Recommended: `#!/bin/bash`
   - Uses: `[[_]]`, BASH_VERSION, arrays, parameter expansion

4. **`shell-common/env/proxy.sh`** - PRIORITY
   - Recommended: `#!/bin/bash`
   - Uses: BASH_SOURCE, parameter expansion

5. **`shell-common/env/security.sh`** - PRIORITY
   - Recommended: `#!/bin/bash`
   - Uses: BASH_SOURCE, parameter expansion

6. **`shell-common/aliases/core.sh`**
   - Recommended: `#!/bin/bash`
   - Uses: source command

---

## Source-Only Files (Shebang Optional)

These 7 files are not executable and are only sourced by other scripts. They are POSIX-compatible and don't strictly need shebangs, but adding them can help with syntax highlighting and linting:

1. `shell-common/aliases/mytool.sh`
2. `shell-common/aliases/system.sh`
3. `shell-common/env/development.sh`
4. `shell-common/env/editor.sh`
5. `shell-common/env/korean.sh`
6. `shell-common/env/locale.sh`
7. `shell-common/env/security.local.sh`

**Recommendation**: Consider adding `#!/bin/sh` for consistency and tooling support, but not critical.

---

## Bash-Specific Features Detected

The analysis detected the following bash-specific features:

| Feature | Count | Examples |
|---------|-------|----------|
| **Double brackets** `[[ ]]` | 39 | Conditional expressions with pattern matching |
| **BASH_SOURCE** | 27 | Script path detection |
| **Arrays** | 43 | `declare -a`, `read -r -a`, array access |
| **Parameter expansion** | 56 | `${var//}`, `${var:}`, `${var^}`, `${var,}` |
| **Process substitution** | 15 | `<()`, `>()` |
| **BASH_VERSION** | 8 | Shell version detection |
| **shopt** | 7 | Shell options |
| **declare flags** | 12 | `declare -g`, `declare -i`, etc. |
| **Brace expansion** | 5 | `{1..10}` |

---

## Recommended Action Plan

### Phase 1: Critical Fixes (Priority Files)

1. **Add missing shebangs** to priority environment files:
   ```bash
   # shell-common/env/path.sh
   # shell-common/env/proxy.sh
   # shell-common/env/security.sh
   ```
   Add `#!/bin/bash` as first line.

2. **Fix wrong shebangs** in priority files:
   ```bash
   # shell-common/env/fcitx.sh
   # shell-common/functions/fzf.sh
   # shell-common/functions/gpuhelp.sh
   # shell-common/functions/psqlhelp.sh
   ```
   Change to `#!/bin/bash`.

### Phase 2: Core Bash Files

3. **Add shebangs** to core bash files:
   ```bash
   # bash/main.bash
   # bash/profile.bash
   ```
   Add `#!/bin/bash` as first line.

### Phase 3: Optimize POSIX Files

4. **Change to `#!/bin/sh`** for POSIX-compatible files:
   - setup.sh
   - All files in shell-common/tools/external/ that are POSIX-compatible
   - POSIX-compatible alias files

### Phase 4: Other Bash Files

5. **Fix remaining bash-required files**:
   - shell-common/aliases/directory.sh
   - shell-common/projects/dmc.sh
   - shell-common/tools/custom/devx.sh
   - shell-common/tools/external/claude.sh
   - shell-common/tools/external/docker.sh
   - shell-common/tools/ux_lib/ux_lib.sh

### Phase 5: Optional

6. **Add shebangs to source-only files** for consistency (optional).

---

## Note on False Positives

The analysis may have some false positives for the `source` keyword, as it can appear in:
- Comments (e.g., "View source code")
- String literals (e.g., "source files")
- Documentation

Files flagged only for `source` usage should be manually reviewed. The following files likely have false positives:
- shell-common/functions/bat.sh
- shell-common/functions/mytool_help.sh
- shell-common/functions/pyhelp.sh
- shell-common/functions/uxhelp.sh
- shell-common/functions/zsh.sh
- shell-common/functions/claudehelp.sh

**Recommendation**: Manually review these files. If they only use `. script.sh` (dot notation) instead of `source script.sh`, they are POSIX-compatible and can keep `#!/bin/sh`.

---

## Verification Commands

After making changes, verify with:

```bash
# Check for remaining bash features in files with #!/bin/sh
for f in $(grep -l "^#!/bin/sh" **/*.sh); do
    echo "=== $f ==="
    grep -E '(\[\[|\]\]|BASH_SOURCE|declare -[aA]|{[0-9]+\.\.[0-9]+})' "$f" || echo "OK"
done

# Check that bash files have proper shebang
for f in bash/*.bash shell-common/env/*.sh shell-common/functions/*.sh; do
    if grep -qE '(\[\[|\]\]|BASH_SOURCE|declare -[aA])' "$f" 2>/dev/null; then
        shebang=$(head -1 "$f")
        if [[ "$shebang" != *"bash"* ]]; then
            echo "MISSING bash shebang: $f (current: $shebang)"
        fi
    fi
done
```

---

## Conclusion

This analysis identified **32 files** needing shebang changes (26 wrong + 6 missing), with **13 priority files** in the shell-common/env/ and shell-common/functions/ directories requiring immediate attention.

The most critical fixes are:
1. Adding `#!/bin/bash` to bash/main.bash (core initialization file)
2. Adding `#!/bin/bash` to shell-common/env/*.sh files that use BASH_SOURCE
3. Fixing shebangs in functions that use `[[ ]]` or arrays

Following this action plan will ensure consistent and correct shebang usage across all shell scripts.

---

**Generated**: 2026-01-03
**Tool**: analyze_shebangs.py
**Repository**: /home/bwyoon/dotfiles
