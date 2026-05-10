# Graceful degradation rules + actionable error messages

Every failure path must produce a message that tells the user what to do next.
Never silently fall back, never overwrite the user's existing `tools/dev.sh`
without a backup.

## Missing AGENTS.md

If `tools/AGENTS.md` not found:

1. **Graceful Degradation**: Use intelligent defaults based on project detection
2. **Notify User**: Warn that AGENTS.md should be created for consistency
3. **Suggest Creation**: Recommend running agents-md:create skill first

```text
WARNING: tools/AGENTS.md not found. Using detected configuration.

For better consistency, create AGENTS.md first:
  Run: agents-md:create skill or create manually
```

## No Entry Point Detected

If no server entry point found:

1. **Set UVICORN_ENTRY to empty string**
2. **Implement up command with clear error**
3. **Provide guidance in error message**

```bash
if [ -n "$UVICORN_ENTRY" ]; then
  # Start server
else
  echo "ERROR: No dev server configured. Edit tools/dev.sh:"
  echo "  1. Set UVICORN_ENTRY to your FastAPI app (e.g., 'src.main:app')"
  echo "  2. Or set IS_DJANGO=true for Django projects"
  exit 1
fi
```

## Permission Issues

If cannot write or chmod:

1. **Check directory permissions**: `ls -la tools/`
2. **Suggest fix**: `chmod +w tools/`
3. **Fall back**: Display content for manual creation

## Emoji Detection

If existing file has emojis:

1. **Remove ALL emojis** during generation
2. **Notify user** of removal
3. **Explain**: Token efficiency requirement from AGENTS.md

```text
NOTE: Removed emojis from output (AGENTS.md token efficiency rule).
  Before: echo "Starting..."
  After:  echo "Starting..."
```
