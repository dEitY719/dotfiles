# Dotfiles

Opinionated Bash/Zsh dotfiles for reproducible terminal environments across WSL, Linux, and macOS.

## ✨ Features

- **Environment-Specific Setup**: Automatic configuration for Home/Internal/External environments
- **Modular Configuration**: Organized shell configs by purpose (aliases, apps, env, utils)
- **Cross-Shell Support**: Unified config for Bash and Zsh with shared portable code
- **UX Library**: Beautiful logging with colored output and progress indicators
- **Code Quality**: Integrated linting tools (shellcheck, ruff, mypy)
- **Easy Installation**: Interactive setup script with environment detection

## 🚀 Quick Start

### Prerequisites
- Bash 4.0+ or Zsh 5.0+
- Git

### Installation

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh
```

The setup script will:
1. **Ask for your environment** (Public PC / Internal company PC / External company PC)
2. **Configure environment-specific files** (.local.sh files)
3. **Create shell symlinks** (~/.bashrc, ~/.zshrc, ~/.gitconfig)
4. **Set up environment variables**

After setup, reload your shell:
```bash
exec bash  # or exec zsh
```

## 📚 Documentation

### For Initial Setup
→ See **[Setup Guide](docs/SETUP_GUIDE.md)** for detailed installation instructions

### Directory Structure

```
dotfiles/
├── shell-common/          # Shared code (both bash & zsh)
│   ├── env/              # Environment variables & .local configs
│   ├── aliases/          # Command aliases
│   ├── functions/        # Portable functions
│   ├── tools/            # Utilities and tools
│   └── setup.sh          # Environment-specific setup
│
├── bash/                 # Bash-specific configuration
│   ├── env/             # Bash environment settings
│   ├── app/             # Application configurations
│   ├── main.bash        # Main entry point
│   └── setup.sh         # Bash setup
│
├── zsh/                 # Zsh-specific configuration
│   ├── env/             # Zsh environment settings
│   ├── app/             # Application configurations
│   ├── main.zsh         # Main entry point
│   └── setup.sh         # Zsh setup
│
├── git/                 # Git configuration
│   └── setup.sh         # Git setup
│
├── docs/                # Documentation
│   └── SETUP_GUIDE.md   # Detailed setup instructions
│
├── setup.sh             # Main orchestrator
└── README.md            # This file
```

## 🔧 Configuration

### Environment-Specific Configs

The setup script creates `.local.sh` files based on your environment:

- **Public PC**: No company-specific settings
- **Internal Company PC**: Uses system CA bundle (Option 2)
- **External Company PC**: Uses custom certificate (Option 1)

These files are in `.gitignore` and won't be committed to the repository.

### Using Custom Configurations

To add your own settings:

```bash
# Home environment
cp shell-common/env/proxy.local.example shell-common/env/proxy.local.sh
# Edit the file to match your environment
```

## 🛠️ Development

### Code Quality

```bash
# Check shell scripts
tox -e shellcheck

# Format shell scripts
tox -e shfmt

# Check Python code
tox -e ruff

# All checks
tox
```

## 💡 Key Commands

After installation, you'll have access to:

```bash
# Shell management
zsh-help                # Zsh management commands
bash-switch            # Switch to Bash
zsh-switch            # Switch to Zsh

# Help system
my-help               # Show available help topics

# Git shortcuts
gb                    # Git branch
gst                   # Git status
```

## 🐛 Troubleshooting

If shell configuration isn't loading:

```bash
# Re-run setup
cd ~/dotfiles && ./setup.sh

# Reload shell
exec bash  # or exec zsh
```

For more help, see [Setup Guide](docs/SETUP_GUIDE.md).

## 📋 Project Details

| Item | Description |
|------|-------------|
| **Language** | Bash/Zsh/Python |
| **Platform** | WSL2, Linux, macOS |
| **License** | MIT |
| **Author** | BW-Yoon |

## 📖 Additional Resources

- [Setup Guide](docs/SETUP_GUIDE.md) - Detailed setup and configuration
- [Shell-Common Documentation](shell-common/README.md) - Shared code overview
- Configuration files in `pyproject.toml` and `tox.ini`
