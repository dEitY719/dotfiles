# Module Context

- **Purpose**: Test suite validating bash/zsh compatibility, help system behavior, shell function correctness, and custom tool invariants.
- **Scope**: `tests/` directory — bats shell unit tests, pytest integration tests, and golden rules.

# Operational Commands

- **Run All (recommended)**: `./tests/test`
- **Run All (verbose)**: `./tests/test -v`
- **Run Bats Only**: `./tests/bats/lib/bats-core/bin/bats tests/bats/init tests/bats/functions tests/bats/tools`
- **Run Pytest Only**: `pytest tests/integration/`
- **Single Pytest File**: `pytest tests/integration/test_help_topics.py -v`
- **Run Golden Rules**: `bash tests/golden_rules/test_golden_rules.sh`
- **Full Lint Gate**: `tox` (runs ruff, mypy, shellcheck, shfmt)

# Test Structure

```
tests/
├── AGENTS.md              # This file
├── README.md              # Detailed test documentation
├── test                   # Unified test runner (bats + pytest + golden rules)
├── integration/           # Pytest integration tests (cross-shell parity)
│   ├── conftest.py        # shell_runner fixture and environment isolation
│   ├── test_compatibility.py
│   ├── test_help_topics.py
│   ├── test_mytool_help.py
│   └── test_file_cleanup.py
├── bats/                  # Bats shell unit tests
│   ├── test_helper.bash   # Common helper (isolation, subprocess runners)
│   ├── lib/               # Git submodules: bats-core, bats-support, bats-assert
│   ├── init/              # Initialization & loading tests
│   ├── functions/         # Core utility function tests
│   └── tools/             # Custom tool dry-run tests
└── golden_rules/          # Static analysis rule checks
    └── test_golden_rules.sh
```

# Golden Rules

- **Hermetic Tests**: Tests must not write to user dotfiles; rely on temporary HOME/ZDOTDIR.
- **Cross-Shell**: If behavior is intended for both shells, parametrize over `bash` and `zsh`.
- **No Network/Installs**: Tests must not require network access or package installation.
- **Stable Output**: Assert on stable substrings, not full banners.
- **Bats for shell units**: New shell function tests go in `tests/bats/functions/`.
- **Pytest for integration**: Cross-shell parity and help system tests stay in pytest.
- **Dry-run only**: Custom tool tests use `bash -n` syntax check or `--help`/`help` mode. Never run actual installations.
- **Subprocess isolation**: Bats tests run dotfiles in subprocesses (run_in_bash/run_in_zsh), not via direct source.

# Testing Strategy

- Use `run_in_bash`/`run_in_zsh` in `tests/bats/test_helper.bash` for isolated shell subprocess execution.
- Use `shell_runner` in `tests/integration/conftest.py` for pytest-based isolated execution.
- For new help topics, add to `shell-common/functions/` and extend coverage in `tests/integration/test_help_topics.py`.
- For new shell functions, add bats tests in `tests/bats/functions/`.
- For new custom tools, add syntax checks in `tests/bats/tools/custom_tools.bats`.

# Context Map

- **[Test Suite README](./README.md)** — High-level test architecture
- **[Pytest Fixture](./integration/conftest.py)** — `shell_runner` fixture and environment isolation
- **[Bats Helper](./bats/test_helper.bash)** — `run_in_bash`/`run_in_zsh` helpers
- **[Help Topics Tests](./integration/test_help_topics.py)** — Ensures help topics exist and are callable
- **[Compatibility Tests](./integration/test_compatibility.py)** — Bash/Zsh parity checks
- **[MyTool Tests](./integration/test_mytool_help.py)** — mytool-help function behavior
- **[Init Tests](./bats/init/)** — Shell initialization and env var tests
- **[Function Tests](./bats/functions/)** — Core utility function tests
- **[Tool Tests](./bats/tools/)** — Custom tool validation
