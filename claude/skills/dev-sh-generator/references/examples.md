# Before/after example + scope boundaries

## Real-World Example

### Before (Missing dev.sh)

```bash
$ ls -la tools/
total 16
drwxr-xr-x 2 user user 4096 Jan 01 10:00 .
drwxr-xr-x 8 user user 4096 Jan 01 10:00 ..
-rw-r--r-- 1 user user 4873 Jan 01 10:00 AGENTS.md
```

### After (Skill Execution)

```bash
$ ls -la tools/
total 24
drwxr-xr-x 2 user user 4096 Jan 01 10:05 .
drwxr-xr-x 8 user user 4096 Jan 01 10:00 ..
-rw-r--r-- 1 user user 4873 Jan 01 10:00 AGENTS.md
-rwxr-xr-x 1 user user 2077 Jan 01 10:05 dev.sh

$ ./tools/dev.sh help
Usage: ./tools/dev.sh <command>

Commands:
  up           Start dev server (uvicorn on :8000)
  test         Run test suite (pytest)
  format       Format and lint code (tox -e ruff)
  shell        Enter project shell
  cli          Start interactive CLI

$ ./tools/dev.sh up
Starting dev server...
INFO:     Uvicorn running on http://0.0.0.0:8000
```

## Usage Notes

### When to Use This Skill

- New project needs developer workflow automation
- Existing project missing tools/dev.sh
- tools/AGENTS.md updated, need to regenerate dev.sh
- Standardizing workflow across multiple projects

### When NOT to Use This Skill

- Non-Python projects (JavaScript, Rust, Go)
- Projects with complex multi-service orchestration
- Projects requiring custom workflow tools
- When tools/dev.sh has significant custom commands

### Customization After Generation

Users can modify generated file:

- Add custom commands (db, worker, deploy)
- Adjust default values (ports, paths)
- Add project-specific env var exports
- Include additional validation checks
