# project-setup — Error Handling

Graceful degradation branches. None of these continue silently — each either
recovers with a fallback (and notifies the user) or halts with `[FAIL]`.

## Missing Git Configuration

If `git config user.name` / `user.email` is empty, fall back:

```bash
AUTHOR_NAME="Your Name"
AUTHOR_EMAIL="your.email@example.com"
```

Notify the user:

```text
Git config not found. Using default values:
- Author: Your Name
- Email: your.email@example.com

To update, run:
  git config --global user.name "Your Name"
  git config --global user.email "your.email@example.com"
```

This is **recoverable** — proceed with the fallback, do not halt.

## Files Already Exist

Default behavior (no `--force`):

1. Create timestamped backups in Step 3 (`.bak.YYYYmmdd_HHMMSS`).
2. Notify the user of backup locations.
3. Overwrite with the new templates.
4. Provide rollback instructions (`mv .markdownlint.json.backup.<ts> .markdownlint.json`).

With `--force`: same flow — backups are still created, but no prompt is issued.

## Invalid Project Name

If the directory name contains characters outside `[A-Za-z0-9_-]`:

1. Sanitize: replace spaces and special chars with `_`.
2. Notify the user that sanitization occurred.
3. Suggest a manual edit in `pyproject.toml` if the sanitized name is undesirable.

## Write Permission Issues

If a write fails (read-only directory, missing perms):

1. Run `ls -la .` to confirm permissions.
2. Suggest `chmod +w .`.
3. Fall back to displaying the template content for manual creation.
4. Halt with `[FAIL]` — do not partially write.

## Validation Failures (Step 5)

If JSON / INI / TOML syntax is invalid, or `{{...}}` placeholders remain:

1. Do NOT delete the file — leave it for inspection.
2. Halt with `[FAIL] project-setup — Step 5: <file> failed <parser> validation`.
3. Point user at `.bak.<timestamp>` for rollback.
