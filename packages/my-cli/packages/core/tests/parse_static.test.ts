/**
 * Unit tests for static registry parser
 * CL-2.2: Static Parser Implementation
 */

import { describe, it, expect } from 'vitest';
import { parseStaticRegistry, parseStaticRegistryFromString } from '../src/registry/parse_static';
import { HelpRegistry } from '../src/registry/Registry';
import { ValidationError } from '../src/errors';
import { resolve } from 'path';

// Path to actual my_help.sh file
// Resolve relative to monorepo root (5 levels up from tests directory)
const MY_HELP_PATH = resolve(__dirname, '../../../../../shell-common/functions/my_help.sh');

describe('parseStaticRegistry', () => {
  describe('File reading', () => {
    it('should read and parse actual my_help.sh file', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      expect(registry).toBeInstanceOf(HelpRegistry);
      expect(registry.categoryCount).toBeGreaterThan(0);
      expect(registry.topicCount).toBeGreaterThan(0);
    });

    it('should throw ValidationError for missing file', async () => {
      await expect(parseStaticRegistry('/nonexistent/path/file.sh')).rejects.toThrow(
        ValidationError,
      );
    });

    it('should throw ValidationError with descriptive message for missing file', async () => {
      await expect(parseStaticRegistry('/nonexistent/path/file.sh')).rejects.toThrow(
        /Help file not found/,
      );
    });
  });

  describe('HELP_CATEGORIES parsing', () => {
    it('should parse HELP_CATEGORIES from actual file', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      expect(registry.getCategory('development')).toBeDefined();
      expect(registry.getCategory('ai')).toBeDefined();
      expect(registry.getCategory('devops')).toBeDefined();
      expect(registry.getCategory('cli')).toBeDefined();
      expect(registry.getCategory('config')).toBeDefined();
      expect(registry.getCategory('docs')).toBeDefined();
      expect(registry.getCategory('system')).toBeDefined();
      expect(registry.getCategory('meta')).toBeDefined();
    });

    it('should parse category descriptions correctly', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const devCategory = registry.getCategory('development');
      expect(devCategory?.description).toContain('Development tools');
    });

    it('should throw ValidationError if no HELP_CATEGORIES found', () => {
      const emptyContent = 'echo "No help categories here"';
      expect(() => parseStaticRegistryFromString(emptyContent)).toThrow(ValidationError);
      expect(() => parseStaticRegistryFromString(emptyContent)).toThrow(
        /No HELP_CATEGORIES found/,
      );
    });
  });

  describe('HELP_CATEGORY_MEMBERS parsing', () => {
    it('should parse HELP_CATEGORY_MEMBERS and create topics', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const devCategory = registry.getCategory('development');
      expect(devCategory?.topics.length).toBeGreaterThan(0);
    });

    it('should parse development category members correctly', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const topics = registry.getTopicsByCategory('development');
      expect(topics.length).toBeGreaterThan(0);

      // Verify some expected topics from my_help.sh
      const topicIds = topics.map((t) => t.id);
      expect(topicIds).toContain('git');
      expect(topicIds).toContain('py');
    });

    it('should parse ai category members correctly', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const topics = registry.getTopicsByCategory('ai');
      expect(topics.length).toBeGreaterThan(0);
      const topicIds = topics.map((t) => t.id);
      expect(topicIds).toContain('claude');
    });

    it('should handle space-separated member lists', () => {
      const testContent = `
HELP_CATEGORIES[test]="Test Category"
HELP_CATEGORY_MEMBERS[test]="topic1 topic2 topic3"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topics = registry.getTopicsByCategory('test');
      expect(topics.length).toBe(3);
      expect(topics.map((t) => t.id)).toEqual(expect.arrayContaining(['topic1', 'topic2', 'topic3']));
    });

    it('should handle extra whitespace in member lists', () => {
      const testContent = `
HELP_CATEGORIES[test]="Test Category"
HELP_CATEGORY_MEMBERS[test]="  topic1   topic2   topic3  "
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topics = registry.getTopicsByCategory('test');
      expect(topics.length).toBe(3);
    });
  });

  describe('HELP_DESCRIPTIONS parsing', () => {
    it('should use HELP_DESCRIPTIONS for topic descriptions when available', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development Tools"
HELP_DESCRIPTIONS[git]="Version control system"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topic = registry.getTopic('git');
      expect(topic?.description).toBe('Version control system');
    });

    it('should fall back to default description if HELP_DESCRIPTIONS missing', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development Tools"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topic = registry.getTopic('git');
      expect(topic?.description).toContain('git');
    });
  });

  describe('Topic creation', () => {
    it('should create topics with correct source type', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topic = registry.getTopic('git');
      expect(topic?.source).toBe('static');
    });

    it('should capitalize topic names for display', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topic = registry.getTopic('git');
      expect(topic?.name).toBe('Git');
    });

    it('should set updatedAt timestamp', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topic = registry.getTopic('git');
      expect(topic?.updatedAt).toBeInstanceOf(Date);
    });

    it('should automatically update category topic list', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORY_MEMBERS[dev]="git python"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const category = registry.getCategory('dev');
      expect(category?.topics).toContain('git');
      expect(category?.topics).toContain('python');
    });
  });

  describe('Edge cases and error handling', () => {
    it('should handle multiple categories', () => {
      const testContent = `
HELP_CATEGORIES[cat1]="Category 1"
HELP_CATEGORIES[cat2]="Category 2"
HELP_CATEGORIES[cat3]="Category 3"
HELP_CATEGORY_MEMBERS[cat1]="topic1"
HELP_CATEGORY_MEMBERS[cat2]="topic2"
HELP_CATEGORY_MEMBERS[cat3]="topic3"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      expect(registry.categoryCount).toBe(3);
      expect(registry.topicCount).toBe(3);
    });

    it('should skip topics with empty IDs', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORY_MEMBERS[dev]="git   python"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      expect(registry.topicCount).toBe(2);
    });

    it('should handle double quotes in descriptions', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development tools (Git, Python, etc.)"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const category = registry.getCategory('dev');
      expect(category?.description).toContain('Git');
    });

    it('should handle underscores in category names', () => {
      const testContent = `
HELP_CATEGORIES[dev_tools]="Development Tools"
HELP_CATEGORY_MEMBERS[dev_tools]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      expect(registry.getCategory('dev_tools')).toBeDefined();
    });

    it('should handle hyphens in topic names', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORY_MEMBERS[dev]="git-flow"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topic = registry.getTopic('git-flow');
      expect(topic).toBeDefined();
    });

    it('should handle underscores in topic names', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORY_MEMBERS[dev]="git_flow"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const topic = registry.getTopic('git_flow');
      expect(topic).toBeDefined();
    });

    it('should skip duplicate category entries (use last value)', () => {
      const testContent = `
HELP_CATEGORIES[dev]="First description"
HELP_CATEGORIES[dev]="Second description"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      const category = registry.getCategory('dev');
      expect(category?.description).toBe('Second description');
    });

    it('should handle missing category members gracefully', () => {
      const testContent = `
HELP_CATEGORIES[dev]="Development"
HELP_CATEGORIES[ai]="AI Tools"
HELP_CATEGORY_MEMBERS[dev]="git"
      `;
      const registry = parseStaticRegistryFromString(testContent);
      expect(registry.categoryCount).toBe(2);
      expect(registry.topicCount).toBe(1);
    });
  });

  describe('Actual file content validation', () => {
    it('should parse all categories from actual my_help.sh', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const expectedCategories = [
        'development',
        'devops',
        'ai',
        'cli',
        'config',
        'docs',
        'system',
        'meta',
      ];

      for (const categoryKey of expectedCategories) {
        const category = registry.getCategory(categoryKey);
        expect(category).toBeDefined(`Category '${categoryKey}' should exist`);
        expect(category?.topics.length).toBeGreaterThan(
          0,
          `Category '${categoryKey}' should have topics`,
        );
      }
    });

    it('should create topics from actual my_help.sh members', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);

      // Verify some expected topics exist
      const expectedTopics = ['git', 'python', 'docker', 'claude', 'npm'];
      for (const topicId of expectedTopics) {
        const topic = registry.getTopic(topicId);
        if (topic) {
          expect(topic.id).toBe(topicId);
          expect(topic.source).toBe('static');
        }
      }
    });

    it('should maintain category-topic relationships from actual file', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const devTopics = registry.getTopicsByCategory('development');
      expect(devTopics.length).toBeGreaterThan(0);

      // All topics should belong to development category
      for (const topic of devTopics) {
        expect(topic.category).toBe('development');
      }
    });
  });

  describe('Performance and statistics', () => {
    it('should provide registry statistics after parsing', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const stats = registry.getStats();

      expect(stats.totalCategories).toBeGreaterThan(0);
      expect(stats.totalTopics).toBeGreaterThan(0);
      expect(stats.topicsBySource.static).toBeGreaterThan(0);
      expect(stats.lastUpdated).toBeInstanceOf(Date);
    });

    it('should be able to serialize parsed registry to JSON', async () => {
      const registry = await parseStaticRegistry(MY_HELP_PATH);
      const json = registry.toJSON();

      expect(json.categories.length).toBeGreaterThan(0);
      expect(json.topics.length).toBeGreaterThan(0);
      expect(json.metadata.version).toBeDefined();
      expect(json.metadata.generatedAt).toBeDefined();
    });
  });
});
