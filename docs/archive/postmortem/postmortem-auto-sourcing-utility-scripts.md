# Auto-Sourcing Utility Scripts (2025-12-29)

## Issue
After refactoring `docker.bash` to `shell-common/tools/external/`, shell initialization began auto-sourcing every file from `shell-common/tools/custom/`, which caused:
- zsh to hang with no prompt
- Endless interactive menu loops (`demo_ux.sh`, `check_ux_consistency.sh` running on startup)
- Shell initialization blocking while waiting for user input

## Root Cause
`shell-common/tools/custom/` contains executable utility scripts (not sourced libraries):
- `demo_ux.sh`: Interactive UX library demo
- `check_ux_consistency.sh`: Consistency checker
- All `install-*.sh`: Installation scripts
- All `setup-*.sh`: Configuration scripts

These scripts define `main()` and invoke it at the end of the file, so sourcing them triggers immediate execution and blocks the shell.

## Solution (Commit 9ce6b82)
- Removed auto-sourcing of `shell-common/tools/custom/` from `bash/main.bash` and `~/.zshrc`, replacing with comments to clarify intent.
- Treat scripts in `shell-common/tools/custom/` as executables to be run explicitly or via wrappers, for example:
```bash
./install_docker.sh    # Direct execution
dinstall               # Via function wrapper in docker.sh
```

## Lessons Learned
- Library code (`ux_lib`, functions) can be sourced at shell init; executable scripts must not be.
- Keep directory purpose clear:
  - `shell-common/tools/external/` → Sourced at init (e.g., `apt.sh`, `docker.sh`)
  - `shell-common/tools/custom/` → Executable utilities only
  - `shell-common/functions/` → Sourced at init (functions)

## Prevention
1. Ensure `main()` is not auto-invoked in scripts under `shell-common/tools/custom/`.
2. Define functions without executing them at EOF for any script intended for sourcing.
3. If init-time execution is required, add a dedicated wrapper in `tools/external/`.
4. Never auto-source from `shell-common/tools/custom/` in shell init files.
