# project-setup — Real-World Example

## Before (empty directory)

```bash
$ pwd
/home/user/projects/my-awesome-tool

$ ls -la
total 8
drwxr-xr-x 2 user user 4096 Jan 01 18:00 .
drwxr-xr-x 5 user user 4096 Jan 01 18:00 ..
```

## After skill execution

```bash
$ ls -la
total 20
drwxr-xr-x 2 user user 4096 Jan 01 18:05 .
drwxr-xr-x 5 user user 4096 Jan 01 18:00 ..
-rw-r--r-- 1 user user   67 Jan 01 18:05 .markdownlint.json
-rw-r--r-- 1 user user 2048 Jan 01 18:05 tox.ini
-rw-r--r-- 1 user user 3500 Jan 01 18:05 pyproject.toml
```

## Generated `pyproject.toml` (placeholders resolved)

```toml
[project]
name = "my-awesome-tool"
authors = [{ name = "John Doe", email = "john@example.com" }]
```

## Next steps after setup

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate   # or `.venv\Scripts\activate` on Windows

# Install project with dev dependencies
pip install -e .[dev]

# Run quality checks
tox -e ruff      # Format code
tox -e mypy      # Type check
tox -e mdlint    # Lint markdown

# Run tests (after creating tests/)
tox -e py312
```
