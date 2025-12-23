# Module Context
- **Purpose**: Domain-specific configurations for tools (Git, Docker, Postgres, Python, etc.).
- **Scope**: Aliases, helper functions, and environment settings specific to a tool.
- **Key Files**: `git.bash`, `docker.bash`, `postgresql.bash`, `python.bash`.

# Operational Commands
- **Lint**: `tox -e shellcheck`.
- **Test**: `tox -e shellcheck -- bash/app/postgresql.bash` (Targeted).

# Implementation Patterns

## Check Command Existence
```bash
if ! command -v docker >/dev/null 2>&1; then
    return 0 # Skip if tool not installed
fi
```

## Tool-Specific Help
```bash
dockerhelp() {
    ux_header "Docker Helpers"
    ux_list "dps" "Docker ps formatted"
    # ...
}
```

# Golden Rules
- **Isolation**: `docker.bash` should NOT touch Postgres settings.
- **Check First**: Always check if the binary exists before defining aliases/functions.
- **Help**: Every app module MUST provide a `*help` function (e.g., `githelp`, `psqlhelp`).
- **Lazy Loading**: If initialization is slow (like `nvm` or `rbenv`), use lazy loading patterns.

# Local Standards
- **Postgres**: Use `psql_db` and `psql_user` wrappers (see `postgresql.bash`).
- **Python**: Prefer `uv` or `pip` over system packages.
- **Node**: Use `nvm` management; avoid global npm installs if possible.

# Context Map
- **[Parent Context](../AGENTS.md)** — Back to Bash Core.
