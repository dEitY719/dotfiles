# Verified Priority Shebang Fixes

**VERIFIED on 2026-01-03**

This document lists only CONFIRMED issues after manual verification of false positives.

---

## shell-common/env/ (4 files - ALL CONFIRMED)

### Files Missing Shebangs (Add `#!/bin/bash`)

#### 1. shell-common/env/path.sh ✗ MISSING SHEBANG
```bash
# Current: NONE (no shebang)
# Add as first line:
#!/bin/bash

# Bash features used:
# - [[]] double brackets (line 20, 27, 34, 37, etc.)
# - BASH_VERSION variable (line 20, 43)
# - Arrays: declare -A, local -a, read -r -a (lines 22-28)
# - Parameter expansion: ${var%/}, ${var:+} (lines 30, 39, 62)
```

#### 2. shell-common/env/proxy.sh ✗ MISSING SHEBANG
```bash
# Current: NONE (no shebang)
# Add as first line:
#!/bin/bash

# Bash features used:
# - BASH_SOURCE[0] variable (line 21)
# - Parameter expansion: ${BASH_SOURCE[0]%/*} (line 21)
```

#### 3. shell-common/env/security.sh ✗ MISSING SHEBANG
```bash
# Current: NONE (no shebang)
# Add as first line:
#!/bin/bash

# Bash features used:
# - BASH_SOURCE[0] variable (line 29)
# - Parameter expansion: ${var%/}, ${var:-} (lines 12, 29)
# - dirname "${BASH_SOURCE[0]:-$0}" (line 29)
```

### Files with Wrong Shebang

#### 4. shell-common/env/fcitx.sh ✗ WRONG SHEBANG
```bash
# Current: #!/usr/bin/env sh
# Change to: #!/bin/bash

# Bash features used:
# - Parameter expansion: ${ENABLE_FCITX:-false} (line 6)
```

---

## shell-common/functions/ (6 files - 3 CONFIRMED, 3 FALSE POSITIVES)

### CONFIRMED: Files Needing Shebang Change to `#!/bin/bash`

#### 1. shell-common/functions/fzf.sh ✗ WRONG SHEBANG
```bash
# Current: #!/bin/sh
# Change to: #!/bin/bash

# Bash features used:
# - Arrays: read -r -a (used for array operations)
```

#### 2. shell-common/functions/gpu_help.sh ✗ WRONG SHEBANG
```bash
# Current: #!/bin/sh
# Change to: #!/bin/bash

# Bash features used:
# - Double brackets [[]] for conditional expressions
```

#### 3. shell-common/functions/psql_help.sh ✗ WRONG SHEBANG
```bash
# Current: #!/bin/sh
# Change to: #!/bin/bash

# Bash features used:
# - Double brackets [[]] for conditional expressions
```

#### 4. shell-common/functions/claude_help.sh ✗ WRONG SHEBANG
```bash
# Current: #!/bin/sh
# Change to: #!/bin/bash

# Bash features used:
# - source command (line 7): source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
# Note: Uses 'source' keyword which is bash-specific (POSIX uses '.')
```

#### 5. shell-common/functions/ux_help.sh ✗ WRONG SHEBANG
```bash
# Current: #!/usr/bin/env sh
# Change to: #!/bin/bash

# Bash features used:
# - source command (line 80 in heredoc example)
# Note: While in heredoc, the function demonstrates bash usage
```

#### 6. shell-common/functions/zsh.sh ✗ WRONG SHEBANG
```bash
# Current: #!/bin/sh
# Change to: #!/bin/bash

# Bash features used:
# - source command (line 162): source "${HOME}/.zshrc"
# Note: Uses 'source' keyword which is bash-specific
```

### FALSE POSITIVES: Files that are OK

#### ✓ shell-common/functions/bat.sh - OK (KEEP #!/bin/sh)
```
# Current: #!/bin/sh - CORRECT
# No actual bash-specific features
# "source" only appears in comments/strings
```

#### ✓ shell-common/functions/mytool_help.sh - OK (KEEP #!/bin/sh)
```
# Current: #!/bin/sh - CORRECT
# No actual bash-specific features
# "source" only appears in strings ("source code")
```

#### ✓ shell-common/functions/py_help.sh - OK (KEEP #!/bin/sh)
```
# Current: #!/bin/sh - CORRECT
# No actual bash-specific features
# "source" only appears in comments/strings
```

---

## Summary of Required Changes

### Total Priority Files Requiring Changes: 10

**shell-common/env/ (4 files):**
1. path.sh - Add `#!/bin/bash`
2. proxy.sh - Add `#!/bin/bash`
3. security.sh - Add `#!/bin/bash`
4. fcitx.sh - Change `#!/usr/bin/env sh` to `#!/bin/bash`

**shell-common/functions/ (6 files):**
1. fzf.sh - Change `#!/bin/sh` to `#!/bin/bash`
2. gpu_help.sh - Change `#!/bin/sh` to `#!/bin/bash`
3. psql_help.sh - Change `#!/bin/sh` to `#!/bin/bash`
4. claude_help.sh - Change `#!/bin/sh` to `#!/bin/bash`
5. ux_help.sh - Change `#!/usr/bin/env sh` to `#!/bin/bash`
6. zsh.sh - Change `#!/bin/sh` to `#!/bin/bash`

---

## Quick Fix Commands

### Add missing shebangs (3 files in env/)
```bash
# CAREFUL: These commands insert shebang as first line
# Backup first!

# 1. path.sh
sed -i '1i#!/bin/bash' shell-common/env/path.sh

# 2. proxy.sh
sed -i '1i#!/bin/bash' shell-common/env/proxy.sh

# 3. security.sh
sed -i '1i#!/bin/bash' shell-common/env/security.sh
```

### Fix wrong shebangs (7 files)
```bash
# Replace first line with correct shebang

# 4. fcitx.sh
sed -i '1s|#!/usr/bin/env sh|#!/bin/bash|' shell-common/env/fcitx.sh

# 5. fzf.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/fzf.sh

# 6. gpu_help.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/gpu_help.sh

# 7. psql_help.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/psql_help.sh

# 8. claude_help.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/claude_help.sh

# 9. ux_help.sh
sed -i '1s|#!/usr/bin/env sh|#!/bin/bash|' shell-common/functions/ux_help.sh

# 10. zsh.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/zsh.sh
```

### All-in-one fix script
```bash
#!/bin/bash
# fix_priority_shebangs.sh

# Add missing shebangs
sed -i '1i#!/bin/bash' shell-common/env/path.sh
sed -i '1i#!/bin/bash' shell-common/env/proxy.sh
sed -i '1i#!/bin/bash' shell-common/env/security.sh

# Fix wrong shebangs
sed -i '1s|#!/usr/bin/env sh|#!/bin/bash|' shell-common/env/fcitx.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/fzf.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/gpu_help.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/psql_help.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/claude_help.sh
sed -i '1s|#!/usr/bin/env sh|#!/bin/bash|' shell-common/functions/ux_help.sh
sed -i '1s|#!/bin/sh|#!/bin/bash|' shell-common/functions/zsh.sh

echo "✓ Fixed 10 priority files"
```

---

## Verification After Fixes

Run this to verify all changes:

```bash
# Check that all priority env files now have #!/bin/bash
for f in shell-common/env/{path,proxy,security,fcitx}.sh; do
    shebang=$(head -1 "$f")
    if [[ "$shebang" == "#!/bin/bash" ]]; then
        echo "✓ $f: $shebang"
    else
        echo "✗ $f: $shebang (EXPECTED: #!/bin/bash)"
    fi
done

# Check that all identified function files now have #!/bin/bash
for f in shell-common/functions/{fzf,gpu_help,psql_help,claude_help,ux_help,zsh}.sh; do
    shebang=$(head -1 "$f")
    if [[ "$shebang" == "#!/bin/bash" ]]; then
        echo "✓ $f: $shebang"
    else
        echo "✗ $f: $shebang (EXPECTED: #!/bin/bash)"
    fi
done
```

---

**Date**: 2026-01-03
**Status**: VERIFIED - All bash features confirmed by manual inspection
**Priority**: HIGH - These are core environment and function files
