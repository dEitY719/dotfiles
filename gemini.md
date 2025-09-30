# Project Summary: Dotfiles Repository

This repository serves as a collection of dotfiles, primarily focusing on bash scripts and configuration files to set up and manage a development environment.

## Key Components:

*   **Bash Scripts (`bash/`)**:
    *   **Aliases (`alias/`)**: Contains aliases for common commands, directory navigation, Python-specific tasks, and general system utilities.
    *   **Application-specific Scripts (`app/`)**: Includes scripts for configuring and interacting with various applications such as Cursor, Custom Project setups, Gemini-related tools, Git, JetBrains IDEs, MySQL, NPM, Obsidian, PostgreSQL, Pyenv, Python, and UV.
    *   **Core Utilities (`core/`)**: Provides foundational utilities like `beauty_log.bash` and `log_util.bash` for enhanced logging, and `default_wsl_bashrc.bash` for Windows Subsystem for Linux (WSL) specific configurations.
    *   **Environment Configurations (`env/`)**: Manages environment variables for development, editor settings, Korean language support, locale, PATH adjustments, proxy settings, and security.
    *   **General Utilities (`util/`)**: Contains miscellaneous utility scripts like `my_man.bash`.
*   **Configuration Files**:
    *   `.gitconfig`: Global Git configuration settings.
    *   `.vscode/settings.json`: Visual Studio Code editor settings.
    *   `.markdownlint.json`: Markdown linting rules.
*   **Python Development Setup**:
    *   `pyproject.toml`: Project configuration for Python tools.
    *   `requirements.txt`: Python package dependencies.
    *   `tox.ini`: Configuration for Tox, a generic virtualenv management and test tool.
*   **Setup Scripts**:
    *   `setup.sh`: A general setup script for the dotfiles.
    *   `git/setup.sh`: Specific setup script for Git configurations.

This repository aims to provide a streamlined and customized development experience through automated configurations and utility scripts.