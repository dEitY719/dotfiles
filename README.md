# Dotfiles

Opinionated Bash dotfiles for reproducible terminal environments across WSL, Linux, and macOS.

## Features

- **Modular Configuration**: Organized bash configurations split by purpose (aliases, apps, env, utils)
- **Beautiful Logging**: Custom logging system with colored output and progress indicators
- **Application Integration**: Pre-configured setups for common development tools
- **Code Quality**: Integrated linting and formatting tools (ruff, mypy, shellcheck, shfmt)
- **Easy Installation**: Simple symlink-based setup script

## Project Structure

```
dotfiles/
├── bash/                   # Bash configurations
│   ├── alias/             # Command aliases and shortcuts
│   │   ├── core_aliases.bash
│   │   ├── directory_aliases.bash
│   │   ├── python_alias.bash
│   │   └── system_aliases.bash
│   ├── app/               # Application-specific configurations
│   │   ├── claude.bash    # Claude AI CLI
│   │   ├── gemini.bash    # Google Gemini AI
│   │   ├── git.bash       # Git shortcuts
│   │   ├── npm.bash       # Node.js/npm
│   │   ├── pyenv.bash     # Python version manager
│   │   ├── uv.bash        # Fast Python package installer
│   │   └── ...            # More apps (postgres, mysql, obsidian, etc.)
│   ├── claude/            # Claude-related configurations
│   │   ├── tox-agent.md   # Claude Code tox linting agent
│   │   └── statusline-command.sh  # Claude Code custom status line
│   ├── ux_lib/            # Core functionality (UX library)
│   │   ├── beauty_log.bash       # Logging utilities
│   │   ├── log_util.bash         # Additional log functions
│   │   └── default_wsl_bashrc.bash
│   ├── env/               # Environment variables
│   │   ├── development.bash
│   │   ├── editor.bash
│   │   ├── korean.bash
│   │   ├── locale.bash
│   │   ├── path.bash
│   │   ├── proxy.bash
│   │   └── security.bash
│   ├── util/              # Utility functions
│   │   └── my_man.bash
│   ├── main.bash          # Main entry point
│   ├── profile.bash       # Bash profile configuration
│   └── setup.sh           # Bash setup script
├── git/                   # Git configurations
│   └── setup.sh           # Git setup script
├── tests/                 # Test files
├── pyproject.toml         # Python project configuration
├── tox.ini                # Code quality automation
├── setup.sh               # Main setup script (bash + git)
├── install.sh             # Additional setup script (Claude Code + other tools)
└── README.md              # This file
```

## Installation

### Prerequisites

- Bash 4.0 or later
- Git

### Quick Start

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ```

2. **Run the main setup script:**

   ```bash
   ./setup.sh
   ```

   This will create symlinks:
   - `~/.bashrc` → `~/dotfiles/bash/main.bash`
   - `~/.bash_profile` → `~/dotfiles/bash/profile.bash`
   - `~/.gitconfig` → `~/dotfiles/git/.gitconfig`

3. **Run the installation script (for additional setup):**

   ```bash
   ./install.sh
   ```

   This will set up:
   - `~/.claude/statusline-command.sh` → `~/dotfiles/bash/claude/statusline-command.sh` (symlink)
   - `~/.claude/agents/*.md` → `~/dotfiles/bash/claude/*.md` (symlinks)

4. **Apply the changes:**

   ```bash
   source ~/.bashrc
   ```

### Manual Installation

If you prefer manual setup:

```bash
# Bash configuration
ln -sf ~/dotfiles/bash/main.bash ~/.bashrc
ln -sf ~/dotfiles/bash/profile.bash ~/.bash_profile

# Git configuration
ln -sf ~/dotfiles/git/.gitconfig ~/.gitconfig
```

## Usage

### Environment Variables

Key environment variables are set in `bash/env/`:

- **PATH**: Configured in `path.bash`
- **Editor**: Set in `editor.bash` (defaults to vim)
- **Locale**: Korean and UTF-8 support in `korean.bash` and `locale.bash`
- **Proxy**: Configure proxy settings in `proxy.bash`

### Aliases

Common aliases are available immediately after sourcing. Examples:

```bash
# Directory navigation (from directory_aliases.bash)
ll, la, l      # ls variants

# Python (from python_alias.bash)
py, python3    # Python shortcuts

# System (from system_aliases.bash)
# Add your custom system aliases here
```

For a complete list, check files in `bash/alias/`.

### Application Configurations

Application-specific configurations are in `bash/app/`. Claude-related configurations are in `bash/claude/`. These include:

- **Claude Code**:
  - `app/claude.bash`: CLI shortcuts and environment setup
  - `claude/statusline-command.sh`: Custom status line (managed via `install.sh`)
  - `claude/tox-agent.md`: Tox linting agent (managed via `install.sh`)
- **Git**: Enhanced git commands and aliases
- **Python**: pyenv, uv package manager integration
- **Databases**: PostgreSQL, MySQL configurations
- **Editors**: JetBrains, Cursor, Obsidian

## Development

### Requirements

```bash
# Install Python dependencies (for development tools)
pip install -e .[dev]

# Or using uv (faster)
uv pip install -e .[dev]
```

### Code Quality

This project uses several linting and formatting tools:

```bash
# Format shell scripts
tox -e shfmt

# Check shell scripts
tox -e shellcheck

# Format Python code
tox -e ruff

# Type checking
tox -e mypy

# Markdown linting
tox -e mdlint

# Run all checks
tox
```

### Project Configuration Files

- **pyproject.toml**: Python project metadata, tool configurations (black, ruff, mypy)
- **tox.ini**: Automated testing and linting configuration
- **.markdownlint.json**: Markdown linting rules

## Customization

### Adding Custom Configurations

1. **Create a local configuration file:**

   ```bash
   touch bash/env/local.bash
   ```

2. **Add your custom settings:**

   ```bash
   # bash/env/local.bash
   export MY_CUSTOM_VAR="value"
   alias myalias="command"
   ```

3. **The main.bash will automatically source it**

### Adding Application Configurations

Create a new file in `bash/app/`:

```bash
# bash/app/myapp.bash
export MYAPP_HOME="/path/to/myapp"
alias myapp="command to run myapp"
```

It will be automatically sourced on shell startup.

## Platform Support

- **WSL2** (Windows Subsystem for Linux): Full support with Korean input (fcitx)
- **Linux**: Tested on Ubuntu, Debian
- **macOS**: Basic support (some features may need adjustment)

## Troubleshooting

### Bash configuration not loading

```bash
# Check if symlink is correct
ls -la ~/.bashrc

# Re-run setup
cd ~/dotfiles && ./setup.sh
```

### Permission issues

```bash
# Make setup scripts executable
chmod +x setup.sh bash/setup.sh git/setup.sh
```

### Korean input not working (WSL2)

The dotfiles include fcitx configuration for Korean input on WSL2. If it's not working:

```bash
# Install fcitx
sudo apt install fcitx fcitx-hangul

# The dotfiles will auto-start fcitx
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run code quality checks: `tox`
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Author

**BW-Yoon** - byoungwoo.yoon@samsung.com

## Acknowledgments

- Inspired by various dotfiles repositories in the community
- Built with best practices for shell scripting and Python development