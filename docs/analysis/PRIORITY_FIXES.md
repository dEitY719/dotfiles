# Priority Shebang Fixes

Quick reference for immediate fixes in shell-common/env/ and shell-common/functions/

## shell-common/env/ (4 files)

### Files Missing Shebangs (Add `#!/bin/bash`)

```bash
# 1. shell-common/env/path.sh
# Add as first line:
#!/bin/bash

# Reason: Uses [[]], BASH_VERSION, arrays, parameter expansion
# Features: declare -A, read -r -a, ${var%/}, ${var:+}
```

```bash
# 2. shell-common/env/proxy.sh
# Add as first line:
#!/bin/bash

# Reason: Uses BASH_SOURCE, parameter expansion
# Features: ${BASH_SOURCE[0]%/*}
```

```bash
# 3. shell-common/env/security.sh
# Add as first line:
#!/bin/bash

# Reason: Uses BASH_SOURCE, parameter expansion
# Features: ${BASH_SOURCE[0]:-$0}, ${var%/}, ${var:-}
```

### Files with Wrong Shebang (Change to `#!/bin/bash`)

```bash
# 4. shell-common/env/fcitx.sh
# Change from: #!/usr/bin/env sh
# Change to:   #!/bin/bash

# Reason: Uses parameter expansion ${var%/}, ${var:-}
```

## shell-common/functions/ (9 files)

### Files with Wrong Shebang - CONFIRMED BASH FEATURES

```bash
# 1. shell-common/functions/fzf.sh
# Change from: #!/bin/sh
# Change to:   #!/bin/bash

# Reason: Uses arrays (read -r -a)
```

```bash
# 2. shell-common/functions/gpu_help.sh
# Change from: #!/bin/sh
# Change to:   #!/bin/bash

# Reason: Uses double brackets [[]]
```

```bash
# 3. shell-common/functions/psql_help.sh
# Change from: #!/bin/sh
# Change to:   #!/bin/bash

# Reason: Uses double brackets [[]]
```

### Files with Wrong Shebang - VERIFY (Possible False Positives)

These files were flagged for using "source" keyword, but may be false positives.
Check if they actually use `source` command vs. just mentioning "source" in strings/comments.

If they use `. script.sh` (dot notation), they can KEEP `#!/bin/sh`.
If they use `source script.sh`, they need `#!/bin/bash`.

```bash
# 4. shell-common/functions/bat.sh
# Current: #!/bin/sh
# Action: VERIFY - check for actual 'source' command usage

# 5. shell-common/functions/claude_help.sh
# Current: #!/bin/sh
# Action: VERIFY - check for actual 'source' command usage

# 6. shell-common/functions/mytool_help.sh
# Current: #!/bin/sh
# Action: VERIFY - check for actual 'source' command usage

# 7. shell-common/functions/py_help.sh
# Current: #!/bin/sh
# Action: VERIFY - check for actual 'source' command usage

# 8. shell-common/functions/ux_help.sh
# Current: #!/usr/bin/env sh
# Action: VERIFY - check for actual 'source' command usage

# 9. shell-common/functions/zsh.sh
# Current: #!/bin/sh
# Action: VERIFY - check for actual 'source' command usage
```

## Verification Commands

### Check if file actually uses 'source' command

```bash
# This will show actual source command usage (not in comments/strings)
grep -E '^\s*source\s+' shell-common/functions/bat.sh

# If output is empty, the file doesn't use 'source' and can keep #!/bin/sh
```

### Quick verification for all suspect files

```bash
for f in shell-common/functions/{bat,claude_help,mytool_help,py_help,ux_help,zsh}.sh; do
    echo "=== $f ==="
    grep -E '^\s*(source|\.|eval)\s+' "$f" 2>/dev/null || echo "No source/dot commands found"
    echo
done
```

## Summary

**Immediate Actions Required:**

1. **Add `#!/bin/bash` to 3 env files:**
   - shell-common/env/path.sh
   - shell-common/env/proxy.sh
   - shell-common/env/security.sh

2. **Change shebang in 1 env file:**
   - shell-common/env/fcitx.sh (from `#!/usr/bin/env sh` to `#!/bin/bash`)

3. **Change shebang in 3 functions files (confirmed):**
   - shell-common/functions/fzf.sh
   - shell-common/functions/gpu_help.sh
   - shell-common/functions/psql_help.sh

4. **Verify and possibly fix 6 functions files:**
   - Check if they actually use `source` command
   - If yes: change to `#!/bin/bash`
   - If no: keep current shebang

**Total Priority Files: 13**
- 7 confirmed fixes needed
- 6 need verification

---

Generated: 2026-01-03
