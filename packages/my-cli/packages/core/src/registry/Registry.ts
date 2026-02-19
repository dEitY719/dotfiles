/**
 * Help registry for managing topics and categories
 * Provides methods to query, search, and manage help information
 */

import { HelpTopic, HelpCategory, RegistryStats, RegistrySnapshot } from './types.js';
import { ValidationError, NotFoundError } from '../errors.js';

/**
 * Main registry class for managing help topics and categories
 *
 * @example
 * ```typescript
 * const registry = new HelpRegistry();
 * registry.addCategory({ key: 'devtools', label: 'Development Tools', ... });
 * registry.addTopic({ id: 'git', name: 'Git', category: 'devtools', ... });
 *
 * const topic = registry.getTopic('git');
 * const results = registry.search('version control');
 * ```
 */
export class HelpRegistry {
  /**
   * Map of category keys to category objects
   */
  private categories: Map<string, HelpCategory> = new Map();

  /**
   * Map of topic IDs to topic objects
   */
  private topics: Map<string, HelpTopic> = new Map();

  /**
   * Timestamp of last update
   */
  private lastUpdated: Date = new Date();

  /**
   * Creates a new HelpRegistry instance
   */
  constructor() {
    this.categories = new Map();
    this.topics = new Map();
    this.lastUpdated = new Date();
  }

  /**
   * Adds a category to the registry
   *
   * @param category - Category to add
   * @throws ValidationError if category key is invalid
   */
  addCategory(category: HelpCategory): void {
    if (!category.key || category.key.length === 0) {
      throw new ValidationError('Category key cannot be empty');
    }

    if (!/^[a-z_][a-z0-9_]*$/.test(category.key)) {
      throw new ValidationError(
        'Category key must start with lowercase letter or underscore, ' +
        'followed by lowercase letters, numbers, or underscores'
      );
    }

    this.categories.set(category.key, category);
    this.lastUpdated = new Date();
  }

  /**
   * Adds a topic to the registry
   *
   * @param topic - Topic to add
   * @throws ValidationError if topic is invalid
   */
  addTopic(topic: HelpTopic): void {
    if (!topic.id || topic.id.length === 0) {
      throw new ValidationError('Topic ID cannot be empty');
    }

    if (!this.categories.has(topic.category)) {
      throw new ValidationError(
        `Category '${topic.category}' does not exist. ` +
        `Available categories: ${Array.from(this.categories.keys()).join(', ')}`
      );
    }

    this.topics.set(topic.id, topic);

    // Update category's topic list if not already present
    const category = this.categories.get(topic.category);
    if (category && !category.topics.includes(topic.id)) {
      category.topics.push(topic.id);
    }

    this.lastUpdated = new Date();
  }

  /**
   * Retrieves a category by key
   *
   * @param key - Category key to retrieve
   * @returns Category object or undefined if not found
   */
  getCategory(key: string): HelpCategory | undefined {
    return this.categories.get(key);
  }

  /**
   * Retrieves all categories
   *
   * @returns Array of all categories
   */
  getCategories(): HelpCategory[] {
    return Array.from(this.categories.values());
  }

  /**
   * Retrieves a topic by ID
   *
   * @param id - Topic ID to retrieve
   * @returns Topic object or undefined if not found
   */
  getTopic(id: string): HelpTopic | undefined {
    return this.topics.get(id);
  }

  /**
   * Retrieves all topics
   *
   * @returns Array of all topics
   */
  getTopics(): HelpTopic[] {
    return Array.from(this.topics.values());
  }

  /**
   * Retrieves all topics in a specific category
   *
   * @param categoryKey - Key of the category
   * @returns Array of topics in the category
   * @throws NotFoundError if category doesn't exist
   */
  getTopicsByCategory(categoryKey: string): HelpTopic[] {
    const category = this.getCategory(categoryKey);
    if (!category) {
      throw new NotFoundError(`Category '${categoryKey}' not found`);
    }

    return category.topics
      .map((topicId) => this.topics.get(topicId))
      .filter((topic) => topic !== undefined) as HelpTopic[];
  }

  /**
   * Searches for topics by query string
   * Searches in topic ID, name, description, and tags
   *
   * @param query - Search query (case-insensitive)
   * @returns Array of matching topics
   */
  search(query: string): HelpTopic[] {
    const lowerQuery = query.toLowerCase();

    return Array.from(this.topics.values()).filter((topic) => {
      // Search in ID
      if (topic.id.toLowerCase().includes(lowerQuery)) {
        return true;
      }

      // Search in name
      if (topic.name.toLowerCase().includes(lowerQuery)) {
        return true;
      }

      // Search in description
      if (topic.description.toLowerCase().includes(lowerQuery)) {
        return true;
      }

      // Search in tags
      if (topic.tags?.some((tag) => tag.toLowerCase().includes(lowerQuery))) {
        return true;
      }

      // Search in aliases
      if (topic.aliases?.some((alias) => alias.toLowerCase().includes(lowerQuery))) {
        return true;
      }

      return false;
    });
  }

  /**
   * Searches for topics by category
   *
   * @param categoryKey - Category key to filter by
   * @returns Array of topics in the category
   */
  searchByCategory(categoryKey: string): HelpTopic[] {
    return this.getTopicsByCategory(categoryKey);
  }

  /**
   * Gets registry statistics
   *
   * @returns Statistics about the registry
   */
  getStats(): RegistryStats {
    const topicsBySource: Record<string, number> = {};

    this.topics.forEach((topic) => {
      topicsBySource[topic.source] = (topicsBySource[topic.source] || 0) + 1;
    });

    return {
      totalCategories: this.categories.size,
      totalTopics: this.topics.size,
      topicsBySource,
      lastUpdated: this.lastUpdated,
    };
  }

  /**
   * Exports the registry as a JSON-serializable snapshot
   *
   * @returns Serialized registry snapshot
   */
  toJSON(): RegistrySnapshot {
    const topics = Array.from(this.topics.values());
    return {
      categories: Array.from(this.categories.values()),
      topics: topics.map((topic) => ({
        ...topic,
        updatedAt: topic.updatedAt?.toISOString(),
      } as unknown as HelpTopic)),
      metadata: {
        version: '0.1.0',
        generatedAt: new Date().toISOString(),
        source: Array.from(new Set(topics.map((t) => t.source))),
      },
    };
  }

  /**
   * Clears all data from the registry
   */
  clear(): void {
    this.categories.clear();
    this.topics.clear();
    this.lastUpdated = new Date();
  }

  /**
   * Gets the number of categories
   */
  get categoryCount(): number {
    return this.categories.size;
  }

  /**
   * Gets the number of topics
   */
  get topicCount(): number {
    return this.topics.size;
  }

  /**
   * Gets the last update timestamp
   */
  get updated(): Date {
    return this.lastUpdated;
  }
}
