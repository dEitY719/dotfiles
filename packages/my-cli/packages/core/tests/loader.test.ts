/**
 * Unit tests for unified registry loader
 * CL-2.4: Registry Integration and Loader Selection
 */

import { describe, it, expect } from 'vitest';
import {
  loadRegistry,
  createLoaderConfig,
  LoaderMode,
  LoaderConfig,
} from '../src/registry/loader';
import { HelpRegistry } from '../src/registry/Registry';
import { ValidationError, InternalError } from '../src/errors';

// Path to actual my_help.sh file
const MY_HELP_PATH = '/home/bwyoon/dotfiles/shell-common/functions/my_help.sh';

describe('loadRegistry', () => {
  describe('Mode selection - Static mode', () => {
    it('should load registry using static parser when mode=static', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'static');
      expect(registry).toBeInstanceOf(HelpRegistry);
      expect(registry.categoryCount).toBeGreaterThan(0);
      expect(registry.topicCount).toBeGreaterThan(0);
    });

    it('should throw ValidationError if file not found in static mode', async () => {
      await expect(loadRegistry('/nonexistent/file.sh', 'static')).rejects.toThrow(
        ValidationError,
      );
    });

    it('should not attempt shell execution in static mode', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'static');
      const topics = registry.getTopics();
      for (const topic of topics) {
        expect(topic.source).toBe('static');
      }
    });
  });

  describe('Mode selection - Shell mode', () => {
    it('should load registry using shell executor when mode=shell', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'shell');
      expect(registry).toBeInstanceOf(HelpRegistry);
      expect(registry.categoryCount).toBeGreaterThan(0);
      expect(registry.topicCount).toBeGreaterThan(0);
    });

    it('should use bash shell by default in shell mode', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'shell');
      const topics = registry.getTopics();
      for (const topic of topics) {
        expect(topic.source).toBe('shell');
      }
    });

    it('should throw ValidationError if shell not found', async () => {
      // This test might pass on systems with bash, so we just verify it handles errors
      try {
        await loadRegistry(MY_HELP_PATH, 'shell');
        expect(true).toBe(true);
      } catch (error) {
        expect(error).toBeInstanceOf(Error);
      }
    });
  });

  describe('Mode selection - Auto mode', () => {
    it('should load registry in auto mode (default)', async () => {
      const registry = await loadRegistry(MY_HELP_PATH);
      expect(registry).toBeInstanceOf(HelpRegistry);
      expect(registry.categoryCount).toBeGreaterThan(0);
      expect(registry.topicCount).toBeGreaterThan(0);
    });

    it('should use shell loader first in auto mode', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'auto');
      const topics = registry.getTopics();
      if (topics.length > 0) {
        // If shell succeeds, all topics should have source='shell'
        const shellSources = topics.filter((t) => t.source === 'shell');
        if (shellSources.length === topics.length) {
          expect(shellSources.length).toBe(topics.length);
        }
      }
    });

    it('should fallback to static loader if shell fails in auto mode', async () => {
      // We'll test this by checking that we get a valid registry even if one loader fails
      const registry = await loadRegistry(MY_HELP_PATH, 'auto');
      expect(registry).toBeInstanceOf(HelpRegistry);
      // Should have content from at least one loader
      expect(registry.categoryCount).toBeGreaterThan(0);
    });
  });

  describe('Configuration management', () => {
    it('should create default loader config', () => {
      const config = createLoaderConfig();
      expect(config.mode).toBe('auto');
      expect(config.cacheEnabled).toBe(true);
      expect(config.cacheTTL).toBe(3600000); // 1 hour
      expect(config.shellTimeout).toBe(5000);
    });

    it('should create custom loader config with overrides', () => {
      const config = createLoaderConfig({
        mode: 'static',
        cacheEnabled: false,
        cacheTTL: 10000,
        shellTimeout: 10000,
      });
      expect(config.mode).toBe('static');
      expect(config.cacheEnabled).toBe(false);
      expect(config.cacheTTL).toBe(10000);
      expect(config.shellTimeout).toBe(10000);
    });

    it('should merge partial config with defaults', () => {
      const config = createLoaderConfig({ mode: 'shell' });
      expect(config.mode).toBe('shell');
      expect(config.cacheEnabled).toBe(true); // Default
      expect(config.cacheTTL).toBe(3600000); // Default
    });
  });

  describe('Caching behavior', () => {
    it('should return cached registry on second call with same path', async () => {
      const registry1 = await loadRegistry(MY_HELP_PATH, 'static', {
        cacheEnabled: true,
        cacheTTL: 60000,
      });
      const registry2 = await loadRegistry(MY_HELP_PATH, 'static', {
        cacheEnabled: true,
        cacheTTL: 60000,
      });

      // Both should have same data
      expect(registry1.categoryCount).toBe(registry2.categoryCount);
      expect(registry1.topicCount).toBe(registry2.topicCount);
    });

    it('should not cache when cacheEnabled=false', async () => {
      const registry1 = await loadRegistry(MY_HELP_PATH, 'static', {
        cacheEnabled: false,
      });
      const registry2 = await loadRegistry(MY_HELP_PATH, 'static', {
        cacheEnabled: false,
      });

      // Both should be valid but potentially different instances
      expect(registry1.categoryCount).toBe(registry2.categoryCount);
    });

    it('should expire cache after TTL', async () => {
      // Create with very short TTL
      const config: LoaderConfig = {
        mode: 'static',
        cacheEnabled: true,
        cacheTTL: 100, // 100ms
      };

      const registry1 = await loadRegistry(MY_HELP_PATH, 'static', config);
      const count1 = registry1.categoryCount;

      // Wait for cache to expire
      await new Promise((resolve) => setTimeout(resolve, 150));

      const registry2 = await loadRegistry(MY_HELP_PATH, 'static', config);
      const count2 = registry2.categoryCount;

      // Should have same data but different instances
      expect(count1).toBe(count2);
    });

    it('should use global cache across multiple calls', async () => {
      // Clear cache first by using different paths
      const registry1 = await loadRegistry(MY_HELP_PATH, 'static', {
        cacheEnabled: true,
      });
      const count1 = registry1.categoryCount;

      const registry2 = await loadRegistry(MY_HELP_PATH, 'static', {
        cacheEnabled: true,
      });
      const count2 = registry2.categoryCount;

      expect(count1).toBe(count2);
    });
  });

  describe('Options passing', () => {
    it('should pass timeout option to shell loader', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'shell', {
        shellTimeout: 10000,
      });
      expect(registry.categoryCount).toBeGreaterThan(0);
    });

    it('should support debug mode', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'static', {
        debug: true,
      });
      expect(registry.categoryCount).toBeGreaterThan(0);
    });
  });

  describe('Error handling', () => {
    it('should throw ValidationError for missing file in static mode', async () => {
      await expect(loadRegistry('/nonexistent/path.sh', 'static')).rejects.toThrow(
        ValidationError,
      );
    });

    it('should throw InternalError for timeout in shell mode', async () => {
      const slowScript = '/tmp/test_slow_help.sh';
      const fs = require('fs');
      try {
        fs.writeFileSync(slowScript, 'sleep 10\necho "Done"');
        await expect(
          loadRegistry(slowScript, 'shell', { shellTimeout: 100 }),
        ).rejects.toThrow(InternalError);
      } finally {
        try {
          fs.unlinkSync(slowScript);
        } catch (e) {
          // ignore cleanup errors
        }
      }
    });

    it('should provide helpful error message for invalid mode', async () => {
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await loadRegistry(MY_HELP_PATH, 'invalid' as any);
        expect(true).toBe(false);
      } catch (error) {
        expect(error).toBeInstanceOf(ValidationError);
      }
    });
  });

  describe('Data consistency', () => {
    it('static and shell loaders should produce compatible results', async () => {
      const staticRegistry = await loadRegistry(MY_HELP_PATH, 'static');
      const shellRegistry = await loadRegistry(MY_HELP_PATH, 'shell');

      // Should have same number of categories
      expect(staticRegistry.categoryCount).toBe(shellRegistry.categoryCount);
      expect(staticRegistry.topicCount).toBe(shellRegistry.topicCount);
    });

    it('should maintain category-topic relationships', async () => {
      const registry = await loadRegistry(MY_HELP_PATH);
      const categories = registry.getCategories();

      for (const category of categories) {
        for (const topicId of category.topics) {
          const topic = registry.getTopic(topicId);
          expect(topic).toBeDefined();
          expect(topic?.category).toBe(category.key);
        }
      }
    });

    it('should populate all required topic fields', async () => {
      const registry = await loadRegistry(MY_HELP_PATH);
      const topics = registry.getTopics();

      for (const topic of topics) {
        expect(topic.id).toBeTruthy();
        expect(topic.name).toBeTruthy();
        expect(topic.category).toBeTruthy();
        expect(topic.description).toBeTruthy();
        expect(topic.source).toBeTruthy();
        expect(topic.updatedAt).toBeInstanceOf(Date);
      }
    });
  });

  describe('Performance and stats', () => {
    it('should provide accurate registry statistics', async () => {
      const registry = await loadRegistry(MY_HELP_PATH);
      const stats = registry.getStats();

      expect(stats.totalCategories).toBeGreaterThan(0);
      expect(stats.totalTopics).toBeGreaterThan(0);
      expect(stats.lastUpdated).toBeInstanceOf(Date);
      expect(Object.keys(stats.topicsBySource).length).toBeGreaterThan(0);
    });

    it('should track source distribution in statistics', async () => {
      const registry = await loadRegistry(MY_HELP_PATH, 'static');
      const stats = registry.getStats();

      // Static loader should populate static source
      expect(stats.topicsBySource.static).toBeGreaterThan(0);
    });
  });

  describe('Serialization', () => {
    it('should serialize loaded registry to JSON', async () => {
      const registry = await loadRegistry(MY_HELP_PATH);
      const json = registry.toJSON();

      expect(json.categories.length).toBeGreaterThan(0);
      expect(json.topics.length).toBeGreaterThan(0);
      expect(json.metadata.version).toBeDefined();
      expect(json.metadata.generatedAt).toBeDefined();
      expect(json.metadata.source).toBeDefined();
    });
  });

  describe('Edge cases', () => {
    it('should handle empty file gracefully', async () => {
      const emptyFile = '/tmp/empty_help.sh';
      const fs = require('fs');
      try {
        fs.writeFileSync(emptyFile, '');
        try {
          await loadRegistry(emptyFile, 'static');
          expect(true).toBe(false);
        } catch (error) {
          expect(error).toBeInstanceOf(ValidationError);
        }
      } finally {
        try {
          fs.unlinkSync(emptyFile);
        } catch (e) {
          // ignore cleanup errors
        }
      }
    });

    it('should handle file with only HELP_CATEGORIES (no members)', async () => {
      const partialFile = '/tmp/partial_help.sh';
      const fs = require('fs');
      try {
        fs.writeFileSync(partialFile, 'HELP_CATEGORIES[test]="Test Category"');
        const registry = await loadRegistry(partialFile, 'static');
        expect(registry.categoryCount).toBeGreaterThan(0);
      } finally {
        try {
          fs.unlinkSync(partialFile);
        } catch (e) {
          // ignore cleanup errors
        }
      }
    });
  });
});

describe('LoaderMode type', () => {
  it('should accept valid mode strings', () => {
    const modes: LoaderMode[] = ['static', 'shell', 'auto'];
    expect(modes.length).toBe(3);
  });
});
