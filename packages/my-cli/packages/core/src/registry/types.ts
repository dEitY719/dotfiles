/**
 * Type definitions for help system registry
 * Defines data structures for help topics, categories, and metadata
 */

/**
 * Represents a single help topic/command
 * Contains information about what the command does, usage, examples, etc.
 */
export interface HelpTopic {
  /**
   * Unique identifier for the topic (e.g., 'git', 'python3')
   */
  id: string;

  /**
   * Display name for the topic (e.g., 'Git Version Control')
   */
  name: string;

  /**
   * Category key this topic belongs to (e.g., 'devtools', 'languages')
   */
  category: string;

  /**
   * One-line description of what this topic is about
   */
  description: string;

  /**
   * Detailed help text/content (from my_help.sh)
   */
  content?: string;

  /**
   * Usage examples for this topic
   */
  examples?: string[];

  /**
   * Alternative names/aliases for this topic
   */
  aliases?: string[];

  /**
   * Source of this topic ('shell', 'static', 'manpage', etc.)
   */
  source: 'static' | 'shell' | 'manpage' | 'markdown';

  /**
   * Timestamp when topic was last updated
   */
  updatedAt?: Date;

  /**
   * Tags for filtering/searching
   */
  tags?: string[];
}

/**
 * Represents a category of help topics
 * Groups related topics together for navigation
 */
export interface HelpCategory {
  /**
   * Unique key for the category (e.g., 'ai', 'devtools')
   */
  key: string;

  /**
   * Display label for the category
   */
  label: string;

  /**
   * Description of what this category contains
   */
  description: string;

  /**
   * List of topic IDs in this category
   */
  topics: string[];

  /**
   * Display order for the category (lower = higher priority)
   */
  order?: number;

  /**
   * Icon or emoji representation (optional)
   */
  icon?: string;

  /**
   * Parent category key for nested organization
   */
  parent?: string;
}

/**
 * Registry statistics for monitoring
 */
export interface RegistryStats {
  /**
   * Total number of categories
   */
  totalCategories: number;

  /**
   * Total number of topics
   */
  totalTopics: number;

  /**
   * Number of topics by source
   */
  topicsBySource: Record<string, number>;

  /**
   * Last time registry was loaded
   */
  lastUpdated: Date;
}

/**
 * Serialized registry for export/storage
 */
export interface RegistrySnapshot {
  /**
   * All categories in the registry
   */
  categories: HelpCategory[];

  /**
   * All topics in the registry
   */
  topics: HelpTopic[];

  /**
   * Metadata about the registry
   */
  metadata: {
    version: string;
    generatedAt: string;
    source: string[];
  };
}
