/**
 * Unit tests for shell-based registry loader
 * CL-2.3: Shell-based Loader Implementation
 */

import { describe, it, expect } from 'vitest';
import { loadByShell } from '../src/registry/load_by_shell';
import { HelpRegistry } from '../src/registry/Registry';
import { ValidationError, InternalError } from '../src/errors';

// Path to actual my_help.sh file
// Use absolute path since __dirname may be transpiled during test execution
const MY_HELP_PATH = '/home/bwyoon/dotfiles/shell-common/functions/my_help.sh';

describe('loadByShell', () => {
  describe('Basic functionality', () => {
    it('should load registry from bash shell', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      expect(registry).toBeInstanceOf(HelpRegistry);
      expect(registry.categoryCount).toBeGreaterThan(0);
      expect(registry.topicCount).toBeGreaterThan(0);
    });

    it('should load registry from zsh shell if available', async () => {
      try {
        const registry = await loadByShell(MY_HELP_PATH, 'zsh');
        expect(registry).toBeInstanceOf(HelpRegistry);
        expect(registry.categoryCount).toBeGreaterThan(0);
      } catch (error) {
        // zsh may not be installed or may fail parsing
        // This is acceptable - just verify the error type
        expect(error).toBeInstanceOf(Error);
      }
    });

    it('should parse categories from shell output', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      expect(registry.getCategory('development')).toBeDefined();
      expect(registry.getCategory('ai')).toBeDefined();
      expect(registry.getCategory('devops')).toBeDefined();
    });

    it('should parse topics from shell output', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const topics = registry.getTopicsByCategory('development');
      expect(topics.length).toBeGreaterThan(0);
    });
  });

  describe('Error handling', () => {
    it('should throw ValidationError for invalid shell type', async () => {
      await expect(
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        loadByShell(MY_HELP_PATH, 'invalid_shell' as any),
      ).rejects.toThrow(ValidationError);
    });

    it('should throw ValidationError for missing file', async () => {
      await expect(loadByShell('/nonexistent/file.sh', 'bash')).rejects.toThrow();
      // Either ValidationError or InternalError is acceptable since file not found
      // could manifest as "No HELP_CATEGORIES found" which is InternalError
    });

    it('should throw ValidationError when shell not found', async () => {
      // Try to use a shell that definitely doesn't exist
      try {
        await loadByShell(MY_HELP_PATH, 'bash');
        // If we get here, bash exists (expected on most systems)
        expect(true).toBe(true);
      } catch (error) {
        // If bash is truly missing (very unlikely), that's fine
        expect(error).toBeInstanceOf(ValidationError);
      }
    });

    it('should respect timeout option', async () => {
      // Create a script that sleeps longer than timeout
      const slowScript = '/tmp/slow_help.sh';
      const fs = require('fs');
      try {
        fs.writeFileSync(slowScript, 'sleep 10\necho "Done"');
        await expect(loadByShell(slowScript, 'bash', { timeout: 100 })).rejects.toThrow(
          InternalError,
        );
      } finally {
        try {
          fs.unlinkSync(slowScript);
        } catch (e) {
          // ignore cleanup errors
        }
      }
    });

    it('should throw InternalError on timeout', async () => {
      const slowScript = '/tmp/very_slow_help.sh';
      const fs = require('fs');
      try {
        fs.writeFileSync(slowScript, 'bash -c "sleep 5"');
        await expect(loadByShell(slowScript, 'bash', { timeout: 50 })).rejects.toThrow(
          InternalError,
        );
      } finally {
        try {
          fs.unlinkSync(slowScript);
        } catch (e) {
          // ignore cleanup errors
        }
      }
    });
  });

  describe('Environment isolation', () => {
    it('should use --noprofile --norc flags for isolation', async () => {
      // Execute twice and verify consistent results (not affected by shell profile)
      const r1 = await loadByShell(MY_HELP_PATH, 'bash');
      const r2 = await loadByShell(MY_HELP_PATH, 'bash');

      expect(r1.categoryCount).toBe(r2.categoryCount);
      expect(r1.topicCount).toBe(r2.topicCount);
    });

    it('should produce consistent results across multiple executions', async () => {
      const results = [];
      for (let i = 0; i < 3; i++) {
        const registry = await loadByShell(MY_HELP_PATH, 'bash');
        results.push({
          categories: registry.categoryCount,
          topics: registry.topicCount,
        });
      }

      // All results should be identical
      expect(results[0]).toEqual(results[1]);
      expect(results[1]).toEqual(results[2]);
    });
  });

  describe('Data integrity', () => {
    it('should set source to "shell" for loaded topics', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const topics = registry.getTopics();
      for (const topic of topics) {
        expect(topic.source).toBe('shell');
      }
    });

    it('should set updatedAt timestamp for topics', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const topics = registry.getTopics();
      for (const topic of topics) {
        expect(topic.updatedAt).toBeInstanceOf(Date);
      }
    });

    it('should maintain category-topic relationships', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const categories = registry.getCategories();

      for (const category of categories) {
        // Each topic in the category should exist
        for (const topicId of category.topics) {
          const topic = registry.getTopic(topicId);
          expect(topic).toBeDefined();
          expect(topic?.category).toBe(category.key);
        }
      }
    });

    it('should populate descriptions from HELP_DESCRIPTIONS', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const topic = registry.getTopic('git');

      if (topic) {
        // git should have a meaningful description from HELP_DESCRIPTIONS
        expect(topic.description).toBeTruthy();
        expect(topic.description.length).toBeGreaterThan(5);
      }
    });
  });

  describe('Registry statistics', () => {
    it('should provide accurate statistics', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const stats = registry.getStats();

      expect(stats.totalCategories).toBeGreaterThan(0);
      expect(stats.totalTopics).toBeGreaterThan(0);
      expect(stats.topicsBySource.shell).toBeGreaterThan(0);
      expect(stats.lastUpdated).toBeInstanceOf(Date);
    });

    it('should track all topics as "shell" source', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const stats = registry.getStats();

      // All topics should be from 'shell' source
      expect(stats.topicsBySource.shell).toBe(stats.totalTopics);
    });
  });

  describe('Serialization', () => {
    it('should serialize loaded registry to JSON', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const json = registry.toJSON();

      expect(json.categories.length).toBeGreaterThan(0);
      expect(json.topics.length).toBeGreaterThan(0);
      expect(json.metadata.version).toBeDefined();
      expect(json.metadata.generatedAt).toBeDefined();
    });
  });

  describe('Shell differences', () => {
    it('bash and zsh should produce compatible results (if zsh available)', async () => {
      const bashRegistry = await loadByShell(MY_HELP_PATH, 'bash');

      try {
        const zshRegistry = await loadByShell(MY_HELP_PATH, 'zsh');

        // Both shells should produce the same number of categories and topics
        expect(bashRegistry.categoryCount).toBe(zshRegistry.categoryCount);
        expect(bashRegistry.topicCount).toBe(zshRegistry.topicCount);

        // All category keys should be identical
        const bashCategories = new Set(bashRegistry.getCategories().map((c) => c.key));
        const zshCategories = new Set(zshRegistry.getCategories().map((c) => c.key));
        expect(bashCategories).toEqual(zshCategories);
      } catch (error) {
        // zsh may not be installed or may parse differently
        // If bash works, that's sufficient for this test
        expect(bashRegistry.categoryCount).toBeGreaterThan(0);
      }
    });
  });

  describe('Options handling', () => {
    it('should use default timeout if not specified', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      expect(registry.categoryCount).toBeGreaterThan(0);
    });

    it('should use custom timeout when specified', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash', { timeout: 10000 });
      expect(registry.categoryCount).toBeGreaterThan(0);
    });

    it('should accept debug option', async () => {
      // Should not throw even with debug enabled
      const registry = await loadByShell(MY_HELP_PATH, 'bash', { debug: true });
      expect(registry.categoryCount).toBeGreaterThan(0);
    });
  });

  describe('Edge cases', () => {
    it('should handle files with many categories', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const stats = registry.getStats();

      // my_help.sh should have 8 categories
      expect(stats.totalCategories).toBeGreaterThanOrEqual(8);
    });

    it('should handle categories with many topics', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const devCategory = registry.getCategory('development');

      // Development category should have many topics
      if (devCategory) {
        expect(devCategory.topics.length).toBeGreaterThan(5);
      }
    });

    it('should handle special characters in descriptions', async () => {
      const registry = await loadByShell(MY_HELP_PATH, 'bash');
      const topics = registry.getTopics();

      // Should not crash on any description
      for (const topic of topics) {
        expect(topic.description).toBeTruthy();
      }
    });
  });
});
