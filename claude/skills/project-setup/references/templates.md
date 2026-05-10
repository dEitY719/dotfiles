# project-setup — Templates (SSOT)

Single source of truth for the three configuration files. The main `SKILL.md`
and `phases-detail.md` reference this file — do not duplicate these blocks
elsewhere.

## 1. `.markdownlint.json`

**When to use:** every project. Disables `MD013` (line length) and `MD033`
(inline HTML) while keeping all other rules at defaults.

```json
{
  "default": true,
  "MD013": false,
  "MD033": false
}
```

## 2. `tox.ini`

**When to use:** every project. Provides `ruff`, `mypy`, `mdlint`,
`shellcheck`, `shfmt`, and `py310`–`py313` environments.

```ini
[tox]
envlist = ruff, mypy, mdlint, shellcheck, shfmt
skipsdist = true
skip_missing_interpreters = true

[testenv]
usedevelop = false
deps = .[dev]
setenv =
    target_dir = .
passenv = PATH
allowlist_externals =
    pylint
    mypy
    markdownlint
    pylint-exit
    pytest
    shellcheck
    shfmt

[testenv:lint]
description = Run pylint to check code style and quality
deps =
    .[dev]
commands =
    pylint {env:target_dir}
    ruff check {env:target_dir}

[testenv:ruff]
allowlist_externals = ruff
description = Run ruff to format code and apply auto-fixes
deps = .[dev]
commands =
    ruff format {env:target_dir}
    ruff check {env:target_dir} --fix

[testenv:black]
description = Run black code formatter
deps =
    black
    black[jupyter]
commands = black {env:target_dir}

[testenv:mypy]
description = Run mypy type checker
deps = .[dev]
commands = mypy {env:target_dir}

[testenv:mdlint]
description = Run markdownlint to check markdown files
skip_install = true
allowlist_externals = markdownlint
commands = markdownlint {env:target_dir}/**/*.md

[testenv:shellcheck]
description = Run shellcheck on bash scripts
skip_install = true
allowlist_externals =
    bash
    find
    shellcheck
    xargs
commands = bash -c 'find bash -type f \( -name "*.sh" -o -name "*.bash" \) -print0 | xargs -0 shellcheck -x -e SC1090,SC1091'

[testenv:shfmt]
description = Check shell script formatting with shfmt
skip_install = true
deps =
commands =
    shfmt -w -i 4 bash/

[testenv:shfmt-check]
description = Check shell script formatting with shfmt
skip_install = true
deps =
commands =
    shfmt -d -i 4 bash/

[testenv:py310]
basepython = python3.10
commands = pytest

[testenv:py311]
basepython = python3.11
commands = pytest

[testenv:py312]
basepython = python3.12
commands = pytest

[testenv:py313]
basepython = python3.13
commands = pytest
```

## 3. `pyproject.toml`

**When to use:** every project. Replace `{{PROJECT_NAME}}`, `{{AUTHOR_NAME}}`,
`{{AUTHOR_EMAIL}}` per Step 4 in `phases-detail.md`.

```toml
[build-system]
requires = ["setuptools", "wheel"]
build-backend = "setuptools.build_meta"

[project]
requires-python = ">=3.10"
version = "0.1.0"
name = "{{PROJECT_NAME}}"
description = "Project description here."
authors = [{ name = "{{AUTHOR_NAME}}", email = "{{AUTHOR_EMAIL}}" }]
dependencies = [
    "rich>=14.1.0",
]

[dependency-groups]
dev = ["ruff", "mypy", "pylint-exit", "pytest", "pytest-mock", "tox>=4.26.0"]

[project.optional-dependencies]
dev = [
    "types-toml",
    "types-requests",
    "types-PyYAML",
]

[tool.setuptools]
packages = []

[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]

[tool.black]
line-length = 120
target-version = ['py310', 'py311', "py312", "py313"]
skip-string-normalization = false
exclude = '\.git|\.mypy_cache|\.tox|\.nox|\.venv|build|dist'

[tool.isort]
profile = "black"

[tool.pylint]
max-line-length = 120
ignore = [".venv", ".tox", ".vscode", ".git", "build"]
disable = ["R", "C", "W1203"]

[tool.mypy]
files = ["./"]
strict = true
disallow_untyped_defs = false
disallow_untyped_calls = false
exclude = '(?x)( \.venv/ | \.tox/ | \.vscode/ | \.git/ | build/ | config/tox/ | tests )'

[tool.ruff]
line-length = 120
target-version = "py310"
exclude = [".git", ".mypy_cache", ".tox", ".nox", ".venv", "build", "dist", ".vscode"]

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP"]
ignore = ["G004"]

[tool.ruff.format]
quote-style = "double"
```
