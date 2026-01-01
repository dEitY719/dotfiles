# Project Setup Skill

This skill automates the creation of standard configuration files for Python projects.

## Included Files

- `.markdownlint.json`: Configuration for Markdown linting.
- `tox.ini`: Configuration for Tox (test automation).
- `pyproject.toml`: Project metadata and tool configuration (Ruff, Mypy, etc.).

## Usage

When you are in a project directory that needs initialization, you can ask Claude:

> "Create project toml files"
> "Initialize project configuration"
> "Setup standard project files"

Claude will generate the three files, attempting to auto-fill the project name and author details from your environment.
