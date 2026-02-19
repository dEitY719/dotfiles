/**
 * Unit tests for show command
 * CL-3.3: Display topic details with optional raw output and paging
 */

import { describe, it, expect, vi } from 'vitest';
import { showCommand, getTopicDetail } from '../src/commands/show';
import { ParsedArguments } from '../src/commands';

// Mock the loader
vi.mock('@my-cli/core', () => ({
  loadRegistry: vi.fn(async () => {
    // Return a mock registry
    return {
      getTopics: () => [
        {
          id: 'git',
          name: 'Git',
          category: 'development',
          description: 'Version control system',
          content:
            'Git is a free and open source distributed version control system.\n\nUsage:\ngit [command]',
          examples: [
            'git clone <repo>',
            'git commit -m "message"',
            'git push origin main',
          ],
          aliases: ['gits'],
          source: 'static',
          tags: ['version-control', 'scm'],
        },
        {
          id: 'py',
          name: 'Python',
          category: 'development',
          description: 'Python programming language',
          content:
            'Python is a high-level programming language.\n\nInstall:\nbrew install python3',
          examples: ['python3 --version', 'python3 script.py'],
          source: 'static',
        },
        {
          id: 'docker',
          name: 'Docker',
          category: 'devops',
          description: 'Container platform',
          content: 'Docker is a containerization platform.',
          examples: [],
          source: 'shell',
        },
        {
          id: 'claude',
          name: 'Claude',
          category: 'ai',
          description: 'Claude AI assistant',
          source: 'shell',
          // No content provided
        },
      ],
      getTopic: function (id: string) {
        return this.getTopics().find((t: any) => t.id === id) || null;
      },
    };
  }),
}));

describe('show command', () => {
  // TC-1: Show existing topic with text format
  it('TC-1: Shows topic with text format', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'git'],
      $0: 'my-cli',
      format: 'text',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('Git'),
    );
    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('Version control system'),
    );

    consoleSpy.mockRestore();
  });

  // TC-2: Show existing topic with JSON format
  it('TC-2: Shows topic with JSON format', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'py'],
      $0: 'my-cli',
      format: 'json',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    const output = consoleSpy.mock.calls[0][0];
    expect(output).toContain('"id": "py"');
    expect(output).toContain('"name": "Python"');

    consoleSpy.mockRestore();
  });

  // TC-3: Show topic with content and examples
  it('TC-3: Displays content and examples correctly', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'git'],
      $0: 'my-cli',
      format: 'text',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    const output = consoleSpy.mock.calls[0][0];
    expect(output).toContain('Examples:');
    expect(output).toContain('git clone <repo>');

    consoleSpy.mockRestore();
  });

  // TC-4: Show non-existent topic
  it('TC-4: Returns error for non-existent topic', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'nonexistent'],
      $0: 'my-cli',
      format: 'text',
    } as any;

    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(1);
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining('not found'),
    );

    errorSpy.mockRestore();
  });

  // TC-5: Show topic with --raw flag
  it('TC-5: Shows raw content without formatting', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'git'],
      $0: 'my-cli',
      raw: true,
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    const output = consoleSpy.mock.calls[0][0];
    // Raw should only output content, not formatted metadata
    expect(output).not.toContain('Name:');
    expect(output).toContain('Git is a free and open source');

    consoleSpy.mockRestore();
  });

  // TC-6: Show with missing topic ID
  it('TC-6: Returns error when topic ID is missing', async () => {
    const argv: ParsedArguments = {
      _: ['show'],
      $0: 'my-cli',
      format: 'text',
    } as any;

    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(1);
    expect(errorSpy).toHaveBeenCalled();

    errorSpy.mockRestore();
  });

  // TC-7: Show topic without content field
  it('TC-7: Handles topic without content gracefully', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'claude'],
      $0: 'my-cli',
      format: 'text',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('Claude'),
    );

    consoleSpy.mockRestore();
  });

  // TC-8: Show with --json flag (shorthand)
  it('TC-8: Respects --json flag for format selection', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'docker'],
      $0: 'my-cli',
      json: true,
      format: 'json',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    const output = consoleSpy.mock.calls[0][0];
    expect(output).toContain('"id": "docker"');

    consoleSpy.mockRestore();
  });

  // TC-9: Show with topic that has no examples
  it('TC-9: Handles topic without examples', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'docker'],
      $0: 'my-cli',
      format: 'text',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    // Should still succeed even without examples
    expect(consoleSpy).toHaveBeenCalled();

    consoleSpy.mockRestore();
  });

  // TC-10: Get topic detail helper
  it('TC-10: getTopicDetail retrieves correct topic', async () => {
    const topic = await getTopicDetail('git');
    expect(topic).toBeDefined();
    expect(topic?.id).toBe('git');
    expect(topic?.name).toBe('Git');
  });

  // TC-11: Get topic detail for non-existent ID
  it('TC-11: getTopicDetail returns null for missing topic', async () => {
    const topic = await getTopicDetail('nonexistent');
    expect(topic).toBeNull();
  });

  // TC-12: Show topic with aliases
  it('TC-12: Displays aliases in topic output', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'git'],
      $0: 'my-cli',
      format: 'text',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    const output = consoleSpy.mock.calls[0][0];
    expect(output).toContain('Aliases:');
    expect(output).toContain('gits');

    consoleSpy.mockRestore();
  });

  // TC-13: Show with tags
  it('TC-13: Displays tags in JSON output', async () => {
    const argv: ParsedArguments = {
      _: ['show', 'git'],
      $0: 'my-cli',
      format: 'json',
    } as any;

    const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const result = await showCommand(argv);

    expect(result).toBe(0);
    const output = consoleSpy.mock.calls[0][0];
    expect(output).toContain('"tags"');

    consoleSpy.mockRestore();
  });
});
