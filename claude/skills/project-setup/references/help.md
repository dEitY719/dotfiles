# project-setup — Usage

## Synopsis

```
project-setup [PROJECT_NAME] [--force] [--dry-run]
project-setup -h | --help | help
```

Initialize a Python project with standard configuration files:
`.markdownlint.json`, `tox.ini`, `pyproject.toml`.

## Options

| Option           | Description                                                          | Default                  |
|------------------|----------------------------------------------------------------------|--------------------------|
| `PROJECT_NAME`   | Override project name (used in `pyproject.toml`).                    | Current directory name   |
| `--force`        | Overwrite existing config files without prompting (still backs up).  | off (back up, then write) |
| `--dry-run`      | Show the plan without creating, backing up, or writing files.        | off                      |
| `-h`, `--help`, `help` | Print this usage and exit.                                     | —                        |

## Examples

```bash
# Initialize in current directory using directory name
project-setup

# Override project name
project-setup my-awesome-tool

# Preview only — no files touched
project-setup --dry-run

# Force-overwrite existing configs (backups still created)
project-setup --force
```

## Stop conditions

- `-h` / `--help` / `help` → print this page and exit.
- Step 1 fails (cannot read directory / git config) → halt with `[FAIL]`.
- Step 3 backup write fails → halt with `[FAIL]`, do not proceed to template write.
- Step 4 template write fails → halt with `[FAIL]`, recommend restoring `.bak` files.
- Step 5 validation fails → halt with `[FAIL]`, leave files in place for inspection.

Workflow halts on the FIRST failing step — no silent continuation.
