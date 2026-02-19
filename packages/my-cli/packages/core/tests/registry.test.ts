/**
 * Unit tests for HelpRegistry and registry types
 * CL-2.1: Type definitions and Registry base class
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { HelpRegistry } from '../src/registry/Registry';
import { HelpTopic, HelpCategory } from '../src/registry/types';
import { ValidationError, NotFoundError } from '../src/errors';

describe('HelpRegistry', () => {
  let registry: HelpRegistry;

  const sampleCategory: HelpCategory = {
    key: 'devtools',
    label: 'Development Tools',
    description: 'Tools and utilities for development',
    topics: [],
    order: 1,
  };

  const sampleTopic: HelpTopic = {
    id: 'git',
    name: 'Git',
    category: 'devtools',
    description: 'Version control system',
    source: 'static',
    aliases: ['gvcs', 'vcs'],
    tags: ['version-control', 'scm'],
  };

  beforeEach(() => {
    registry = new HelpRegistry();
  });

  describe('Category Management', () => {
    it('should add a category', () => {
      registry.addCategory(sampleCategory);
      expect(registry.getCategory('devtools')).toBeDefined();
      expect(registry.categoryCount).toBe(1);
    });

    it('should retrieve category by key', () => {
      registry.addCategory(sampleCategory);
      const category = registry.getCategory('devtools');
      expect(category?.label).toBe('Development Tools');
    });

    it('should return undefined for non-existent category', () => {
      expect(registry.getCategory('nonexistent')).toBeUndefined();
    });

    it('should get all categories', () => {
      registry.addCategory(sampleCategory);
      registry.addCategory({
        key: 'languages',
        label: 'Programming Languages',
        description: 'Languages and runtimes',
        topics: [],
      });

      const categories = registry.getCategories();
      expect(categories).toHaveLength(2);
    });

    it('should reject empty category key', () => {
      const invalidCategory = { ...sampleCategory, key: '' };
      expect(() => registry.addCategory(invalidCategory)).toThrow(ValidationError);
    });

    it('should reject invalid category key format', () => {
      const invalidCategory = { ...sampleCategory, key: '123-invalid' };
      expect(() => registry.addCategory(invalidCategory)).toThrow(ValidationError);
    });

    it('should accept valid category key formats', () => {
      registry.addCategory({ ...sampleCategory, key: 'dev_tools' });
      registry.addCategory({ ...sampleCategory, key: 'a_very_long_category_name' });
      registry.addCategory({ ...sampleCategory, key: '_private' });

      expect(registry.categoryCount).toBe(3);
    });
  });

  describe('Topic Management', () => {
    beforeEach(() => {
      registry.addCategory(sampleCategory);
    });

    it('should add a topic', () => {
      registry.addTopic(sampleTopic);
      expect(registry.getTopic('git')).toBeDefined();
      expect(registry.topicCount).toBe(1);
    });

    it('should retrieve topic by ID', () => {
      registry.addTopic(sampleTopic);
      const topic = registry.getTopic('git');
      expect(topic?.name).toBe('Git');
      expect(topic?.description).toBe('Version control system');
    });

    it('should return undefined for non-existent topic', () => {
      expect(registry.getTopic('nonexistent')).toBeUndefined();
    });

    it('should get all topics', () => {
      registry.addTopic(sampleTopic);
      registry.addTopic({
        id: 'python',
        name: 'Python',
        category: 'devtools',
        description: 'Programming language',
        source: 'static',
      });

      const topics = registry.getTopics();
      expect(topics).toHaveLength(2);
    });

    it('should reject topic with empty ID', () => {
      const invalidTopic = { ...sampleTopic, id: '' };
      expect(() => registry.addTopic(invalidTopic)).toThrow(ValidationError);
    });

    it('should reject topic with non-existent category', () => {
      const invalidTopic = { ...sampleTopic, category: 'nonexistent' };
      expect(() => registry.addTopic(invalidTopic)).toThrow(ValidationError);
    });

    it('should automatically update category topic list', () => {
      registry.addTopic(sampleTopic);
      const category = registry.getCategory('devtools');
      expect(category?.topics).toContain('git');
    });

    it('should get topics by category', () => {
      registry.addTopic(sampleTopic);
      registry.addTopic({
        id: 'python',
        name: 'Python',
        category: 'devtools',
        description: 'Programming language',
        source: 'static',
      });

      const topics = registry.getTopicsByCategory('devtools');
      expect(topics).toHaveLength(2);
    });

    it('should throw NotFoundError for non-existent category in getTopicsByCategory', () => {
      expect(() => registry.getTopicsByCategory('nonexistent')).toThrow(NotFoundError);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      registry.addCategory({ ...sampleCategory });
      registry.addCategory({
        key: 'languages',
        label: 'Programming Languages',
        description: 'Languages and runtimes',
        topics: [],
      });

      registry.addTopic(sampleTopic);
      registry.addTopic({
        id: 'python',
        name: 'Python',
        category: 'languages',
        description: 'Popular programming language',
        source: 'static',
        tags: ['interpreter', 'dynamic'],
      });
      registry.addTopic({
        id: 'github',
        name: 'GitHub',
        category: 'devtools',
        description: 'Git hosting platform',
        source: 'static',
        aliases: ['gh'],
      });
    });

    it('should search topics by ID', () => {
      const results = registry.search('git');
      expect(results).toHaveLength(2);
      expect(results.map((t) => t.id)).toEqual(expect.arrayContaining(['git', 'github']));
    });

    it('should search topics by name', () => {
      const results = registry.search('Python');
      expect(results).toHaveLength(1);
      expect(results[0].id).toBe('python');
    });

    it('should search topics by description', () => {
      const results = registry.search('version control');
      expect(results).toHaveLength(1);
      expect(results[0].id).toBe('git');
    });

    it('should search topics by tags', () => {
      const results = registry.search('interpreter');
      expect(results).toHaveLength(1);
      expect(results[0].id).toBe('python');
    });

    it('should search topics by aliases', () => {
      const results = registry.search('gh');
      expect(results).toHaveLength(1);
      expect(results[0].id).toBe('github');
    });

    it('should be case-insensitive', () => {
      const results1 = registry.search('GIT');
      const results2 = registry.search('git');
      expect(results1).toHaveLength(results2.length);
    });

    it('should return empty array for no matches', () => {
      const results = registry.search('nonexistent');
      expect(results).toHaveLength(0);
    });

    it('should search by category', () => {
      const results = registry.searchByCategory('devtools');
      // devtools has 3 topics: git, python, github (python is in languages, not devtools)
      // Actually, only git and github are in devtools
      expect(results.length).toBeGreaterThanOrEqual(2);
      const ids = results.map((t) => t.id);
      expect(ids).toContain('git');
      expect(ids).toContain('github');
    });
  });

  describe('Registry Statistics', () => {
    beforeEach(() => {
      registry.addCategory(sampleCategory);
      registry.addTopic(sampleTopic);
      registry.addTopic({
        id: 'python',
        name: 'Python',
        category: 'devtools',
        description: 'Programming language',
        source: 'shell',
      });
    });

    it('should provide registry statistics', () => {
      const stats = registry.getStats();
      expect(stats.totalCategories).toBe(1);
      expect(stats.totalTopics).toBe(2);
    });

    it('should track topics by source', () => {
      const stats = registry.getStats();
      expect(stats.topicsBySource.static).toBe(1);
      expect(stats.topicsBySource.shell).toBe(1);
    });

    it('should provide last updated timestamp', () => {
      const stats = registry.getStats();
      expect(stats.lastUpdated).toBeInstanceOf(Date);
    });
  });

  describe('Serialization', () => {
    beforeEach(() => {
      registry.addCategory(sampleCategory);
      registry.addTopic(sampleTopic);
    });

    it('should export to JSON', () => {
      const json = registry.toJSON();
      expect(json.categories).toHaveLength(1);
      expect(json.topics).toHaveLength(1);
      expect(json.metadata.version).toBe('0.1.0');
    });

    it('should include all topic data in JSON export', () => {
      const json = registry.toJSON();
      const topic = json.topics[0];
      expect(topic.id).toBe('git');
      expect(topic.name).toBe('Git');
      expect(topic.aliases).toEqual(['gvcs', 'vcs']);
      expect(topic.tags).toEqual(['version-control', 'scm']);
    });

    it('should include metadata in JSON export', () => {
      const json = registry.toJSON();
      expect(json.metadata.source).toContain('static');
      expect(json.metadata.generatedAt).toBeDefined();
    });
  });

  describe('Registry Lifecycle', () => {
    it('should clear all data', () => {
      registry.addCategory(sampleCategory);
      registry.addTopic(sampleTopic);

      expect(registry.categoryCount).toBe(1);
      expect(registry.topicCount).toBe(1);

      registry.clear();

      expect(registry.categoryCount).toBe(0);
      expect(registry.topicCount).toBe(0);
    });

    it('should update timestamp on operations', () => {
      const before = registry.updated;
      registry.addCategory(sampleCategory);
      const after = registry.updated;

      expect(after.getTime()).toBeGreaterThanOrEqual(before.getTime());
    });

    it('should provide property accessors', () => {
      registry.addCategory(sampleCategory);
      registry.addTopic(sampleTopic);

      expect(registry.categoryCount).toBe(1);
      expect(registry.topicCount).toBe(1);
      expect(registry.updated).toBeInstanceOf(Date);
    });
  });

  describe('Edge Cases', () => {
    it('should handle multiple additions of same category', () => {
      registry.addCategory(sampleCategory);
      registry.addCategory(sampleCategory);

      expect(registry.categoryCount).toBe(1);
    });

    it('should handle special characters in description', () => {
      const specialTopic: HelpTopic = {
        ...sampleTopic,
        description: 'Description with "quotes" and \'apostrophes\' & special chars!',
      };

      registry.addCategory(sampleCategory);
      registry.addTopic(specialTopic);

      const retrieved = registry.getTopic('git');
      expect(retrieved?.description).toContain('quotes');
    });

    it('should handle topics with optional fields undefined', () => {
      const minimalTopic: HelpTopic = {
        id: 'minimal',
        name: 'Minimal',
        category: 'devtools',
        description: 'Minimal topic',
        source: 'static',
      };

      registry.addCategory(sampleCategory);
      registry.addTopic(minimalTopic);

      const retrieved = registry.getTopic('minimal');
      expect(retrieved?.aliases).toBeUndefined();
      expect(retrieved?.tags).toBeUndefined();
    });
  });
});
