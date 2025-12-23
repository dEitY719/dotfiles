# Module Context
- **Purpose**: Standalone CLI utilities and installation/maintenance scripts.
- **Languages**: Python (complex logic), Bash (glue code, installers).
- **Key Tools**: `srcpack.py` (Code packer), `install-*.sh` (Setup scripts).

# Operational Commands
- **Run Python Tool**: `python3 mytool/srcpack.py --help`.
- **Run Bash Tool**: `./mytool/repo_stats.sh`.
- **Lint Python**: `tox -e ruff`, `tox -e mypy`.
- **Lint Bash**: `tox -e shellcheck`.

# Implementation Patterns

## Python CLI (argparse)
```python
def main():
    parser = argparse.ArgumentParser(description="Tool Description")
    parser.add_argument("--output", help="Output file")
    args = parser.parse_args()
```

## Bash Installer
```bash
#!/bin/bash
source "$(dirname "$0")/../bash/ux_lib/ux_lib.bash"

ux_header "Installing Tool X"
# ... logic ...
```

# Golden Rules
- **Standalone**: Tools should generally run without complex external env setup (or check for it).
- **UX**: Bash scripts MUST source `ux_lib` and use standard output formatting.
- **Help**: All scripts must support `--help` or `-h`.
- **Idempotency**: Install scripts must check if already installed.

# Context Map
- **[Parent Context](../AGENTS.md)** — Back to Project Root.
