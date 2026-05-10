# project-setup — Options

| Option           | Description                                                          | Default                  |
|------------------|----------------------------------------------------------------------|--------------------------|
| `PROJECT_NAME`   | Override project name. Replaces `{{PROJECT_NAME}}` in `pyproject.toml`. Sanitized: spaces and special chars → `_`. | Current directory name   |
| `--force`        | Overwrite existing config files. Backups are still created in Step 3. | off                      |
| `--dry-run`      | Print the plan (which files would be created / backed up / overwritten) without performing any write. | off                      |
| `-h`, `--help`, `help` | Print `references/help.md` verbatim and exit. Takes precedence over all other args. | —             |

## Placeholder resolution

The author fields in `pyproject.toml` use git config — see Step 1 in `phases-detail.md`.

| Placeholder         | Source                  | Fallback                    |
|---------------------|-------------------------|-----------------------------|
| `{{PROJECT_NAME}}`  | argv or directory name  | sanitized directory name    |
| `{{AUTHOR_NAME}}`   | `git config user.name`  | `Your Name`                 |
| `{{AUTHOR_EMAIL}}`  | `git config user.email` | `your.email@example.com`    |
