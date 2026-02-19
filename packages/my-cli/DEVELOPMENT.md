# Development Guide for my-cli

This guide covers setup, architecture, and development workflows for my-cli.

## Table of Contents

- [Setup](#setup)
- [Architecture](#architecture)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Building](#building)
- [Git Workflow](#git-workflow)
- [Troubleshooting](#troubleshooting)

## Setup

### Prerequisites

- Node.js 18+ (`node --version`)
- npm 9+ (`npm --version`)
- Bash or Zsh (for shell integration tests)
- Git 2.30+

### Initial Setup

```bash
# Clone and navigate
cd dotfiles/packages/my-cli

# Install dependencies
npm install

# Build all packages
npm run build

# Verify installation
node packages/cli/dist/index.js --version
# Expected: 0.1.0
```

### Environment

The project is a npm workspace monorepo:

- **Root**: `/dotfiles/packages/my-cli/` (monorepo root)
- **Core**: `packages/core/` (library)
- **CLI**: `packages/cli/` (application)

Both workspaces are linked automatically.

## Architecture

### Package Structure

#### Core (`packages/core`)

Provides help system infrastructure:

- **Registry**: Stores topics and categories
- **Loaders**:
  - `load_by_shell.ts` - Loads help from shell `declare -p` output
  - `parse_static.ts` - Parses static help data
- **Adapters**:
  - `ShellFunctionAdapter.ts` - Calls `my_help_impl` for live content
- **Types**: Interfaces for topics, categories, etc.
- **Sanitization**: Input validation (prevents injection)
- **Error Handling**: Custom error types

Key exports:
```typescript
export { HelpRegistry, HelpTopic, HelpCategory } from './registry/types.js';
export { loadByShell } from './registry/load_by_shell.js';
export { ShellFunctionAdapter } from './adapters/ShellFunctionAdapter.js';
export { ValidationError, SecurityError, InternalError } from './errors.js';
```

#### CLI (`packages/cli`)

Provides user interface:

- **Commands**:
  - `list.ts` - List categories/topics
  - `show.ts` - Show topic details
  - `help.ts` - Launch TUI
  - `completion.ts` - Generate shell completions
- **TUI Screens** (`tui/screens/`):
  - `Topics.tsx` - Browse/search topics
  - `TopicDetail.tsx` - View topic with pagination
- **Command Router**: Routes CLI commands to handlers

## Development Workflow

### Making Changes

1. **Create feature branch**
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make changes** to TypeScript files

3. **Build and test**
   ```bash
   npm run build
   npm test
   ```

4. **Commit**
   ```bash
   git add .
   git commit -m "feat: description"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/my-feature
   ```

### File Organization

When adding features:

- Core logic → `packages/core/src/`
- CLI commands → `packages/cli/src/commands/`
- TUI screens → `packages/cli/src/tui/screens/`
- Tests → Adjacent to source with `.test.ts`

### Adding a New Command

Example: Adding `my-cli config` command

1. Create handler: `packages/cli/src/commands/config.ts`
   ```typescript
   export const configCommand: CommandHandler = async (argv) => {
     // Implementation
     return 0; // success
   };
   ```

2. Export from `packages/cli/src/commands/index.ts`
   ```typescript
   export { configCommand } from './config.js';
   ```

3. Register in `packages/cli/src/index.ts`
   ```typescript
   import { configCommand } from './commands/index.js';
   // ...
   router.registerCommand('config', 'Manage configuration', configCommand);
   ```

4. Add tests: `packages/cli/tests/commands.test.ts`
   ```typescript
   it('should handle config command', async () => {
     const result = await configCommand(argv);
     expect(result).toBe(0);
   });
   ```

### Adding a New TUI Screen

Example: Adding topic filtering screen

1. Create component: `packages/cli/src/tui/screens/TopicFilter.tsx`
   ```typescript
   import React from 'react';
   import { Box, Text } from 'ink';

   export const TopicFilter: React.FC<Props> = ({ topics }) => {
     // Implementation with Ink components
     return <Box>{/* JSX */}</Box>;
   };
   ```

2. Use in main TUI and add key handler
3. Add tests with `ink-testing-library`

## Testing

### Test Structure

- **Unit Tests**: Core library logic
- **Integration Tests**: Command + registry
- **E2E Tests**: Full CLI workflows
- **Performance Tests**: Response time validation

### Running Tests

```bash
# All tests
npm test

# Watch mode
npm run test:watch

# Specific test file
npm test -- packages/core/tests/registry.test.ts

# Specific test case
npm test -- --grep "should load topics"
```

### Writing Tests

Example test pattern:

```typescript
import { describe, it, expect } from 'vitest';

describe('MyFeature', () => {
  it('TC-1: should handle happy path', async () => {
    const result = await myFunction('input');
    expect(result).toEqual('expected');
  });

  it('TC-2: should handle errors', async () => {
    await expect(myFunction('bad')).rejects.toThrow();
  });
});
```

Test naming convention:
- `TC-1`, `TC-2`, etc. for test cases
- Descriptive names: `should [verb] [noun]`
- Test both happy paths and error cases

## Building

### Development Build

```bash
npm run build
# Compiles TypeScript to dist/
# Takes ~1-2 seconds
```

### Production Build with Bundling

```bash
npm run build:production
# Runs: build + bundle
# Creates:
#   - dist/index.js (compiled, ~1.8KB minified)
#   - dist/my-cli.js (esbuild output)
```

### Bundle Analysis

The bundle is optimized for size and performance:

- TypeScript → JavaScript (ES modules)
- Tree-shaking removes unused code
- Minification reduces size
- Target: Node.js 18+

Current metrics:
- **Bundle**: 1.8KB (well under 15MB limit)
- **Response**: < 400ms average
- **Cold start**: < 500ms

## Git Workflow

### Commit Message Format

Follow Conventional Commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`

Example:
```
feat(cli): add completion command

Implemented shell completion script generation
for bash and zsh with dynamic topic support.

Closes #123
```

### Release Process

1. **Update version** in `packages/*/package.json`
2. **Update CHANGELOG.md**
3. **Create git tag**
   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```

## Troubleshooting

### Build Errors

**Error**: `"Cannot find module 'core'"`
- **Solution**: `npm install` in root, then `npm run build`

**Error**: `"Property 'XYZ' does not exist"`
- **Solution**: TypeScript type issue. Check `packages/*/src/**/*.ts` for typing

### Test Failures

**Error**: `"ENOTFOUND my_help.sh"`
- **Solution**: Shell test requires `/dotfiles/shell-common/functions/my_help.sh` to exist
- Verify: `ls /home/bwyoon/dotfiles/shell-common/functions/my_help.sh`

**Error**: `"Cannot resolve @my-cli/core"`
- **Solution**: Ensure workspace is linked
- Fix: `npm install` from root, then rebuild

### Runtime Issues

**Error**: `"Unknown command: 'show'"`
- **Solution**: Command router needs to be updated. Check `src/index.ts` registration

**Error**: `"Shell 'bash' not found"`
- **Solution**: Verify bash/zsh are in PATH
- Check: `which bash` or `which zsh`

## Performance Profiling

### Measure Command Time

```bash
time my-cli list topics
# Real time includes Node.js startup
```

### Profile Hot Paths

Using Node.js inspector:
```bash
node --inspect packages/cli/dist/index.js list topics
# Use Chrome DevTools to analyze
```

## Extending Shell Integration

### Adding New Help Topics

Edit `/dotfiles/shell-common/functions/my_help.sh`:

```bash
HELP_CONTENT[mytopic]="Topic content here"
HELP_DESCRIPTIONS[mytopic]="Short description"
HELP_CATEGORY_MEMBERS[dev]+="mytopic"
```

Reload:
```bash
my-cli list topics
```

## Additional Resources

- [README.md](README.md) - User guide
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [Ink Documentation](https://github.com/vadimdemedes/ink)
- [Vitest Guide](https://vitest.dev/)
- [npm Workspaces](https://docs.npmjs.com/cli/v7/using-npm/workspaces)

## Questions?

Check existing test cases in `tests/` directories for examples of similar functionality.
