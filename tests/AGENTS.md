# Module Context

- **Purpose**: Pytest suite that validates bash/zsh compatibility, help system behavior, and custom tool invariants.
- **Scope**: `tests/` only (Python tests + shell test launcher).

# Operational Commands

- **Run All (recommended)**: `./tests/test`
- **Run All (pytest)**: `pytest tests/`
- **Single File**: `pytest tests/test_help_topics.py -v`
- **Full Lint Gate**: `tox` (runs ruff, mypy, shellcheck, shfmt)

# Golden Rules

- **Hermetic Tests**: Tests must not write to user dotfiles; rely on temporary HOME/ZDOTDIR from `conftest.py`.
- **Cross-Shell**: If behavior is intended for both shells, parametrize over `bash` and `zsh`.
- **No Network/Installs**: Tests must not require network access or package installation.
- **Stable Output**: Assert on stable substrings, not full banners, unless the output is part of the contract.

# Testing Strategy

- Use `shell_runner` in `tests/conftest.py` for isolated bash/zsh subprocess execution.
- For new help topics, add to `shell-common/functions/` and extend coverage in `tests/test_help_topics.py`.
- For new custom tools, place scripts in `shell-common/tools/custom/` and extend `tests/test_mytool_help.py` as needed.

# Context Map

- **[Test Suite README](./README.md)** — High-level test architecture and how to run tests
- **[Pytest Fixture](./conftest.py)** — `shell_runner` fixture and environment isolation
- **[Help Topics Tests](./test_help_topics.py)** — Ensures help topics exist and are callable
- **[Compatibility Tests](./test_compatibility.py)** — Bash/Zsh parity checks
- **[MyTool Tests](./test_mytool_help.py)** — Custom tool and help integration checks
