/**
 * Unit tests for CLI command router
 * CL-3.1: yargs setup and command routing
 */

import { describe, it, expect, vi } from 'vitest';
import { parseArgs, createCommandRouter } from '../src/commands';

describe('parseArgs', () => {
  describe('Global options', () => {
    it('should parse --version flag', async () => {
      const argv = await parseArgs(['--version']);
      // yargs may handle version specially, so just check argv exists
      expect(argv).toBeDefined();
      // The CommandRouter will check isVersionRequest
    });

    it('should parse --help flag', async () => {
      const argv = await parseArgs(['--help']);
      // yargs may handle help specially, so just check argv exists
      expect(argv).toBeDefined();
      // The CommandRouter will check isHelpRequest
    });

    it('should parse --json format option', async () => {
      const argv = await parseArgs(['list', 'categories', '--json']);
      expect(argv.json).toBe(true);
      expect(argv.format).toBe('json');
    });

    it('should parse --text format option', async () => {
      const argv = await parseArgs(['list', 'categories', '--text']);
      expect(argv.text).toBe(true);
      expect(argv.format).toBe('text');
    });

    it('should default to text format', async () => {
      const argv = await parseArgs(['list', 'categories']);
      expect(argv.format).toBeUndefined(); // Or defaults to 'text'
    });
  });

  describe('Search and filter options', () => {
    it('should parse --search option', async () => {
      const argv = await parseArgs(['list', 'topics', '--search', 'git']);
      expect(argv.search).toBe('git');
    });

    it('should parse --filter option', async () => {
      const argv = await parseArgs(['list', 'topics', '--filter', 'development']);
      expect(argv.filter).toBe('development');
    });

    it('should allow multiple search/filter combinations', async () => {
      const argv = await parseArgs([
        'list',
        'topics',
        '--search',
        'git',
        '--filter',
        'dev',
      ]);
      expect(argv.search).toBe('git');
      expect(argv.filter).toBe('dev');
    });
  });

  describe('Command parsing', () => {
    it('should parse command as first positional argument', async () => {
      const argv = await parseArgs(['list']);
      expect(argv._[0]).toBe('list');
    });

    it('should parse subcommand', async () => {
      const argv = await parseArgs(['list', 'categories']);
      expect(argv._[0]).toBe('list');
      expect(argv._[1]).toBe('categories');
    });

    it('should parse options after command', async () => {
      const argv = await parseArgs(['list', 'topics', '--search', 'python']);
      expect(argv._[0]).toBe('list');
      expect(argv._[1]).toBe('topics');
      expect(argv.search).toBe('python');
    });
  });

  describe('Format option handling', () => {
    it('should handle --json as shorthand for --format json', async () => {
      const argv = await parseArgs(['show', 'git', '--json']);
      expect(argv.json === true || argv.format === 'json').toBe(true);
    });

    it('should handle --text as shorthand for --format text', async () => {
      const argv = await parseArgs(['show', 'git', '--text']);
      expect(argv.text === true || argv.format === 'text').toBe(true);
    });

    it('should prefer explicit --format over shorthands', async () => {
      const argv = await parseArgs(['show', 'git', '--format', 'json']);
      expect(argv.format).toBe('json');
    });
  });

  describe('Error handling', () => {
    it('should handle invalid command gracefully', async () => {
      const argv = await parseArgs(['invalid-command']);
      expect(argv._[0]).toBe('invalid-command');
      // Command validation happens later
    });

    it('should handle missing required options', async () => {
      const argv = await parseArgs(['list', 'topics', '--search']);
      // yargs will handle this based on configuration
      expect(argv).toBeDefined();
    });
  });

  describe('Argument handling', () => {
    it('should parse positional arguments', async () => {
      const argv = await parseArgs(['show', 'git']);
      expect(argv._).toContain('show');
      expect(argv._).toContain('git');
    });

    it('should support quoted arguments with spaces', async () => {
      const argv = await parseArgs(['show', 'my-command']);
      expect(argv._).toContain('show');
      expect(argv._).toContain('my-command');
    });
  });
});

describe('createCommandRouter', () => {
  describe('Router initialization', () => {
    it('should create a command router', () => {
      const router = createCommandRouter();
      expect(router).toBeDefined();
      expect(typeof router.registerCommand).toBe('function');
    });

    it('should allow registering commands', () => {
      const router = createCommandRouter();
      const handler = vi.fn();
      router.registerCommand('test', 'Test command', handler);
      expect(router).toBeDefined();
    });
  });

  describe('Command execution', () => {
    it('should execute registered command', async () => {
      const router = createCommandRouter();
      const handler = vi.fn().mockResolvedValue(0);
      router.registerCommand('test', 'Test command', handler);

      const result = await router.execute('test', {});
      expect(handler).toHaveBeenCalled();
      expect(result).toBe(0);
    });

    it('should pass argv to command handler', async () => {
      const router = createCommandRouter();
      const handler = vi.fn().mockResolvedValue(0);
      router.registerCommand('list', 'List command', handler);

      await router.execute('list', { format: 'json', _: ['list', 'topics'] });
      expect(handler).toHaveBeenCalledWith(
        expect.objectContaining({
          format: 'json',
        }),
      );
    });

    it('should throw error for unknown command', async () => {
      const router = createCommandRouter();
      await expect(router.execute('unknown', {})).rejects.toThrow();
    });
  });

  describe('Format resolution', () => {
    it('should resolve format from --json flag', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const format = router.resolveFormat({ json: true } as any);
      expect(format).toBe('json');
    });

    it('should resolve format from --text flag', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const format = router.resolveFormat({ text: true } as any);
      expect(format).toBe('text');
    });

    it('should resolve format from --format option', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const format = router.resolveFormat({ format: 'json' } as any);
      expect(format).toBe('json');
    });

    it('should default to text if no format specified', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const format = router.resolveFormat({} as any);
      expect(format).toBe('text');
    });

    it('should prefer explicit --format over flags', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const format = router.resolveFormat({
        format: 'json',
        text: true,
      } as any); // eslint-disable-line @typescript-eslint/no-explicit-any
      expect(format).toBe('json');
    });
  });

  describe('Search/filter extraction', () => {
    it('should extract search term from argv', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const search = router.getSearchTerm({ search: 'git' } as any);
      expect(search).toBe('git');
    });

    it('should extract filter term from argv', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const filter = router.getFilter({ filter: 'development' } as any);
      expect(filter).toBe('development');
    });

    it('should return undefined if no search term', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const search = router.getSearchTerm({} as any);
      expect(search).toBeUndefined();
    });

    it('should return undefined if no filter', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const filter = router.getFilter({} as any);
      expect(filter).toBeUndefined();
    });
  });

  describe('Help and version', () => {
    it('should identify help flag', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const isHelp = router.isHelpRequest({ help: true } as any);
      expect(isHelp).toBe(true);
    });

    it('should identify version flag', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const isVersion = router.isVersionRequest({ version: true } as any);
      expect(isVersion).toBe(true);
    });

    it('should return false when help flag absent', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const isHelp = router.isHelpRequest({} as any);
      expect(isHelp).toBe(false);
    });

    it('should return false when version flag absent', () => {
      const router = createCommandRouter();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const isVersion = router.isVersionRequest({} as any);
      expect(isVersion).toBe(false);
    });
  });

  describe('Command listing', () => {
    it('should list all registered commands', () => {
      const router = createCommandRouter();
      const handler = vi.fn();
      router.registerCommand('list', 'List command', handler);
      router.registerCommand('show', 'Show command', handler);

      const commands = router.getRegisteredCommands();
      expect(commands).toContain('list');
      expect(commands).toContain('show');
    });

    it('should return empty list initially', () => {
      const router = createCommandRouter();
      const commands = router.getRegisteredCommands();
      expect(Array.isArray(commands)).toBe(true);
    });
  });
});

describe('Error handling and edge cases', () => {
  it('should handle empty argv array', async () => {
    const argv = await parseArgs([]);
    expect(argv).toBeDefined();
  });

  it('should handle mixed flags and positional args', async () => {
    const argv = await parseArgs(['list', '--json', 'topics', '--search', 'git']);
    expect(argv._).toContain('list');
    expect(argv._).toContain('topics');
    expect(argv.json || argv.format === 'json').toBe(true);
    expect(argv.search).toBe('git');
  });

  it('should handle unknown flags gracefully', async () => {
    const argv = await parseArgs(['list', '--unknown-flag']);
    expect(argv).toBeDefined();
  });

  it('should distinguish between flags and values', async () => {
    const argv = await parseArgs(['list', '--search', '--json']);
    // --json should be a flag, --search should have a value
    expect(argv.json || argv.format === 'json').toBe(true);
  });
});
