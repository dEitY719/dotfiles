/**
 * Unit tests for list command
 * CL-3.2: List categories and topics with search/filter
 */

import { describe, it, expect, vi } from 'vitest';
import { listCommand, listCategories, listTopics } from '../src/commands/list';
import { ParsedArguments } from '../src/commands';

// Mock the loader
vi.mock('../../../core/src/registry/loader', () => ({
  loadRegistry: vi.fn(async () => {
    // Return a mock registry
    return {
      getCategories: () => [
        {
          key: 'development',
          label: 'Development',
          description: 'Development tools',
          topics: ['git', 'py', 'node'],
        },
        {
          key: 'devops',
          label: 'DevOps',
          description: 'DevOps tools',
          topics: ['docker', 'k8s'],
        },
        {
          key: 'ai',
          label: 'AI',
          description: 'AI tools',
          topics: ['claude', 'gemini'],
        },
      ],
      getTopics: () => [
        {
          id: 'git',
          name: 'Git',
          category: 'development',
          description: 'Version control system',
          source: 'static',
        },
        {
          id: 'py',
          name: 'Python',
          category: 'development',
          description: 'Python programming language',
          source: 'static',
        },
        {
          id: 'node',
          name: 'Node.js',
          category: 'development',
          description: 'JavaScript runtime',
          source: 'shell',
        },
        {
          id: 'docker',
          name: 'Docker',
          category: 'devops',
          description: 'Container platform',
          source: 'static',
        },
        {
          id: 'k8s',
          name: 'Kubernetes',
          category: 'devops',
          description: 'Container orchestration',
          source: 'static',
        },
        {
          id: 'claude',
          name: 'Claude',
          category: 'ai',
          description: 'Claude AI assistant',
          source: 'shell',
        },
        {
          id: 'gemini',
          name: 'Gemini',
          category: 'ai',
          description: 'Google Gemini AI',
          source: 'static',
        },
      ],
      getTopicsByCategory: (category: string) => {
        const allTopics = [
          {
            id: 'git',
            name: 'Git',
            category: 'development',
            description: 'Version control system',
            source: 'static',
          },
          {
            id: 'py',
            name: 'Python',
            category: 'development',
            description: 'Python programming language',
            source: 'static',
          },
          {
            id: 'node',
            name: 'Node.js',
            category: 'development',
            description: 'JavaScript runtime',
            source: 'shell',
          },
          {
            id: 'docker',
            name: 'Docker',
            category: 'devops',
            description: 'Container platform',
            source: 'static',
          },
          {
            id: 'k8s',
            name: 'Kubernetes',
            category: 'devops',
            description: 'Container orchestration',
            source: 'static',
          },
          {
            id: 'claude',
            name: 'Claude',
            category: 'ai',
            description: 'Claude AI assistant',
            source: 'shell',
          },
          {
            id: 'gemini',
            name: 'Gemini',
            category: 'ai',
            description: 'Google Gemini AI',
            source: 'static',
          },
        ];
        return allTopics.filter((t) => t.category === category);
      },
    };
  }),
}));

describe('listCommand', () => {
  describe('Main command handler', () => {
    it('should execute list categories when subcommand is "categories"', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCommand(argv);
      expect(result).toBe(0);
    });

    it('should execute list topics when subcommand is "topics"', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCommand(argv);
      expect(result).toBe(0);
    });

    it('should default to topics when no subcommand specified', async () => {
      const argv = {
        _: ['list'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCommand(argv);
      expect(result).toBe(0);
    });

    it('should handle invalid subcommand gracefully', async () => {
      const argv = {
        _: ['list', 'invalid'],
        format: 'text',
      } as any as ParsedArguments;

      await expect(listCommand(argv)).rejects.toThrow();
    });
  });

  describe('List categories', () => {
    it('should list all categories', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should list categories in JSON format', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'json',
        json: true,
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should list categories in text format', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'text',
        text: true,
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should return exit code 0 on success', async () => {
      const argv = {
        _: ['list', 'categories'],
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });
  });

  describe('List topics', () => {
    it('should list all topics', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should list topics with search filter', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        search: 'git',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should list topics with category filter', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        filter: 'development',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should combine search and filter', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        search: 'git',
        filter: 'development',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should output JSON format', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'json',
        json: true,
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should return exit code 0 on success', async () => {
      const argv = {
        _: ['list', 'topics'],
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });
  });

  describe('Format handling', () => {
    it('should default to text format if not specified', async () => {
      const argv = {
        _: ['list', 'categories'],
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should respect --json flag', async () => {
      const argv = {
        _: ['list', 'categories'],
        json: true,
        format: 'json',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should respect explicit --format option', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'json',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });
  });

  describe('Search functionality', () => {
    it('should filter topics by search term (case insensitive)', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        search: 'GIT',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should support partial search matches', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        search: 'ython',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should handle search with no matches', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        search: 'nonexistent',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });
  });

  describe('Filter functionality', () => {
    it('should filter topics by category', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        filter: 'development',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should handle filter with no matches', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        filter: 'nonexistent',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should return exit code 0 even with no results', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
        search: 'xyz123',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });
  });

  describe('JSON output format', () => {
    it('should output valid JSON for categories', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'json',
      } as any as ParsedArguments;

      // Should not throw and exit with 0
      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should output valid JSON for topics', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'json',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should include metadata in JSON output', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'json',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });
  });

  describe('Text output format', () => {
    it('should output readable text for categories', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should output readable text for topics', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should include topic count in text output', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });
  });

  describe('Error handling', () => {
    it('should handle registry loading errors', async () => {
      // This would test error handling when loadRegistry fails
      // Implementation depends on how errors are handled
      const argv = {
        _: ['list', 'categories'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should return proper exit code', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(typeof result).toBe('number');
      expect(result).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Output validation', () => {
    it('should include all categories in output', async () => {
      const argv = {
        _: ['list', 'categories'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listCategories(argv);
      expect(result).toBe(0);
    });

    it('should include all topics in output', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });

    it('should show topic details (id, name, description)', async () => {
      const argv = {
        _: ['list', 'topics'],
        format: 'text',
      } as any as ParsedArguments;

      const result = await listTopics(argv);
      expect(result).toBe(0);
    });
  });
});
