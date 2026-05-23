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
git clone https://github.com/dEitY719/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh
```

If you install to a different location, use that path instead of `~/dotfiles`. Most scripts resolve paths via `DOTFILES_ROOT`/`SHELL_COMMON`.

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

→ See **[Setup Guide](docs/guide/setup.md)** for detailed installation instructions

### Detailed Documentation

- **[shell-common/README.md](shell-common/README.md)** - Shared shell configuration, module loading, and best practices
- **[bash/setup.sh](bash/setup.sh)** - Bash-specific setup and configuration
- **[zsh/setup.sh](zsh/setup.sh)** - Zsh-specific setup and configuration

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

### npm config (symlink)

`~/.npmrc` is managed as a symlink to `npm/npmrc.{environment}`. Configured automatically by `./setup.sh`.

## 🔐 Secret Management with git-crypt

This project uses **git-crypt** for transparent encryption of sensitive files (`.env`, API keys, credentials, etc.).

### Overview

- **Automatic encryption/decryption**: Files matching `.gitattributes` patterns are transparently encrypted in git
- **Authentication options**: Symmetric keys or GPG-based authentication
- **Works transparently**: `git clone`, `git pull`, `git push` automatically decrypt/encrypt files
- **Secure storage**: Encrypted files are binary-safe in the repository; only authorized users can decrypt

### Quick Start on a New PC

**Option 1: Restore from backup key (Recommended)**

```bash
# After cloning the repository
cd ~/dotfiles

# Restore your backup key
gcrestore

# Verify decryption worked
source ~/.bashrc  # Should load without errors
echo $GEMINI_API_KEY  # Should show your API key
```

**Option 2: Manual unlock with symmetric key**

```bash
# If you have the backup key file from another PC
git-crypt unlock .secrets/.dotfiles-backup-key.txt
```

### Backup & Recovery

**Backup your key (on the PC with working git-crypt)**:

```bash
gcbackup
# Creates: .secrets/.dotfiles-backup-key.txt (encrypted in git)
```

**Restore on a new PC**:

```bash
gcrestore
# Automatically handles key transfer and restoration
```

### Troubleshooting

- **`.env` shows "GITCRYPT..." header**: Repository is locked (keys don't match)
- **`source ~/.bashrc` fails with syntax errors**: `.env` is still encrypted, run `gcrestore`
- **`git-crypt unlock` fails**: GPG keys or symmetric key not available on this PC
- **Multi-PC Recovery**: See [docs/abc-review-O.md](docs/abc-review-O.md) for detailed step-by-step procedures

### How It Works

1. `.gitattributes` marks files to encrypt:

    ```
    .env filter=git-crypt diff=git-crypt
    .secrets/** filter=git-crypt diff=git-crypt
    ```

2. When you `git push`, git-crypt encrypts these files before storing in the repository

3. When you `git pull` or `git clone`, git-crypt automatically decrypts (if you have the key)

4. On your local machine, files are always plaintext and readable

### Additional Resources

- **[git-crypt documentation](https://github.com/AGWA/git-crypt)** - Official git-crypt docs
- **[Multi-PC Recovery Guide](docs/abc-review-O.md)** - Detailed procedures for recovering git-crypt on another PC
- **Shell commands**: `gc-help` for more git-crypt utilities

## 🛠️ Development

### Code Quality

This repo is migrating from `tox` to **mise** for task orchestration
(issue [#722](https://github.com/dEitY719/dotfiles/issues/722)). Both
runners work during the migration window and produce equivalent results.

#### Preferred — mise (new)

One-time bootstrap:

```bash
curl https://mise.run | sh   # or: brew install mise
mise install                  # installs pinned shellcheck / shfmt / uv
```

Daily use:

```bash
mise run lint     # ruff + mypy + shellcheck + shfmt -d  (read-only)
mise run lint-py  # Python only
mise run lint-sh  # Shell only
mise run test     # bats + pytest + golden rules
mise run fix      # ruff --fix + ruff format + shfmt -w  (mutating)
```

A higher-level wrapper command (`devx <verb>`) lands in PR 2 of #722
and consolidates `./tools/dev.sh`. Until then, call `mise run` directly.

#### Legacy — tox (deprecated, kept until PR 5 of #722)

`tox -e <env>` 와 `mise run <task>` 의 동치 매핑. 단, `tox` (인자 없음)
은 envlist 가 `ruff, mypy, shellcheck, shfmt` 라 ruff/shfmt 단계에서
파일을 **수정**하고 (각 testenv 가 `ruff format` / `shfmt -w` 호출)
나머지는 read-only 인 mixed 동작이다. `mise run lint` 는 순수 read-only
이므로 두 명령은 의미가 다르며, 정확한 mise 대체는 `mise run fix &&
mise run lint` 다.

```bash
tox -e shellcheck   # equivalent to: mise run lint-sh   (둘 다 read-only)
tox -e shfmt        # equivalent to: mise run fix-sh    (둘 다 -w)
tox -e ruff         # equivalent to: mise run fix-py    (둘 다 --fix + format)
tox                 # rough equivalent: mise run fix && mise run lint
                    #   (tox 가 ruff/shfmt 를 -w 모드로 실행하므로
                    #    read-only `mise run lint` 와 동치가 아님)
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

For more help, see [Setup Guide](docs/guide/setup.md).

## 📋 Project Details

| Item         | Description        |
| ------------ | ------------------ |
| **Language** | Bash/Zsh/Python    |
| **Platform** | WSL2, Linux, macOS |
| **License**  | MIT                |
| **Author**   | BW-Yoon            |

## 📖 Additional Resources

- [Setup Guide](docs/guide/setup.md) - Detailed setup and configuration
- [Shell-Common Documentation](shell-common/README.md) - Shared code overview
- Configuration files in `pyproject.toml`, `mise.toml`, and `tox.ini` (legacy — see #722)
