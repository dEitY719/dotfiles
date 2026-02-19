# Changelog

All notable changes to my-cli will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned Features

- [ ] Plugin system for custom commands
- [ ] Configuration file support (~/.my-cli/config.json)
- [ ] Persistent history and bookmarks
- [ ] Custom color schemes and themes
- [ ] API mode for programmatic access
- [ ] Shell function documentation generator
- [ ] Performance benchmarking dashboard

---

## [0.1.0] - 2026-02-19

### Initial Release (MVP)

First stable release of my-cli with core functionality.

#### Added

**Core Features**
- Interactive TUI help browser using Ink/React (CL-1.1)
- Shell registry loader with bash/zsh support (CL-2.3)
- Help topic management and categorization (CL-3.2)
- Command routing system with yargs (CL-3.1)

**Commands**
- `list categories` - Show available help categories (CL-3.3)
- `list topics` - Display all help topics (CL-3.4)
- `show <topic>` - View detailed topic information (CL-4.1)
- `completion bash|zsh` - Generate shell completions (CL-5.2)

**TUI Features**
- Interactive topic browser with keyboard navigation (CL-4.1)
- Fuzzy search with Fuse.js (CL-4.2)
- Content pagination with PgUp/PgDn keys (CL-4.3)
- Topics list with filtering and search (CL-4.2)

**Output Formats**
- JSON output with `--format json` (CL-3.3)
- Text formatting with ANSI color codes (CL-3.3)
- Raw output without formatting (CL-4.1)

**Quality Assurance**
- E2E and performance tests (CL-6.1)
- 357+ comprehensive test cases
- Performance validation (< 400ms response)
- Error handling with custom error types

**Build & Deployment**
- esbuild production bundling (CL-6.2)
- Minified bundle: 1.8KB (< 15MB target)
- TypeScript strict mode compilation
- npm workspace monorepo structure

**Documentation**
- Comprehensive README.md (CL-6.3)
- Development guide (DEVELOPMENT.md)
- Architecture documentation
- Inline code comments and JSDoc

#### Architecture

- **Monorepo**: `packages/core` and `packages/cli`
- **Language**: TypeScript 5.3
- **Runtime**: Node.js 18+
- **TUI Framework**: Ink 6.8.0 with React 19
- **Testing**: Vitest 1.0 with 357+ tests
- **Build**: TypeScript compiler + esbuild

#### Performance

- **Cold Start**: < 500ms
- **Response Time**: < 400ms per command
- **Bundle Size**: 1.8KB minified
- **Test Duration**: ~5.7s for full suite

#### Features by Component

**Core Library (packages/core)**
- `HelpRegistry` - Topic and category management
- `loadByShell` - Load help from shell variables
- `ShellFunctionAdapter` - Real-time content via my_help_impl
- Input validation and error handling
- Security: SQL/shell injection prevention

**CLI Application (packages/cli)**
- Command router for routing to handlers
- TUI with multiple screens
- JSON/text formatters
- Search and pagination features
- Shell completion generator

#### Shell Integration

- Integrates with existing `my_help.sh` functions
- `my_help_impl` - Renders topic content
- `HELP_CATEGORIES`, `HELP_DESCRIPTIONS` arrays
- Safe execution with `--noprofile --norc`

#### Keyboard Shortcuts (TUI)

| Key | Action |
|-----|--------|
| `/` | Start search |
| `Esc` | Exit search/cancel |
| `Enter` | Select/confirm |
| `PgUp` | Scroll up (topic detail) |
| `PgDn` | Scroll down (topic detail) |
| `q` | Quit |

#### Error Handling

- `ValidationError` - Invalid input
- `SecurityError` - Injection attempts
- `InternalError` - Shell execution errors
- User-friendly error messages

#### Testing Coverage

- **Unit Tests**: Core library (250+ tests)
- **Integration Tests**: Command execution
- **E2E Tests**: Full workflows (20+ scenarios)
- **Performance Tests**: Response time validation

#### Git Commits (by feature)

- `7680421` - CL-4.3: TopicDetail pager
- `8e90083` - CL-4.2: Topics search
- `d48b59d` - CL-4.1: Keep TUI running
- `b0b7e8b` - CL-4.1: Path and help handling
- Plus 60+ commits for core, adapters, tests

#### Known Issues

None at release. See issues tracker for future work.

#### Migration Guide

For users upgrading from shell-only `my_help`:

1. Install my-cli: `npm install -g` (or from dotfiles)
2. All existing `my_help` data is automatically loaded
3. Use `my-cli` instead of `my_help` shell function
4. Interactive mode: `my-cli` or `my-cli help`
5. Legacy mode: `my-cli show <topic>` for scripting

#### Contributing

See DEVELOPMENT.md for setup and workflow.

#### Version Info

- **Version**: 0.1.0
- **Release Date**: 2026-02-19
- **Node.js**: 18+ required
- **TypeScript**: 5.3+
- **Status**: MVP (feature complete for v0.1)

---

## Development Milestones

### CL-1: Learning & Setup
- [x] TypeScript/Node.js fundamentals
- [x] Project initialization
- [x] monorepo setup

### CL-2: Core Infrastructure
- [x] Help registry design
- [x] Shell loader implementation
- [x] Configuration system

### CL-3: Command System
- [x] Command routing with yargs
- [x] List categories command
- [x] List topics command
- [x] Help text formatting

### CL-4: TUI & Content
- [x] Ink/React TUI setup
- [x] Topic browser screen
- [x] Fuzzy search implementation
- [x] Content pagination

### CL-5: Advanced Features
- [x] ShellFunctionAdapter
- [x] Shell completion generation

### CL-6: Production Ready
- [x] E2E & performance tests
- [x] esbuild bundling
- [x] Documentation & release

---

[Unreleased]: https://github.com/yourusername/dotfiles/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/dotfiles/releases/tag/v0.1.0
