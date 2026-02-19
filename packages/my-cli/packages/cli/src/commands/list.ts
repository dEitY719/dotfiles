/**
 * List command implementation
 * Lists categories or topics with optional search/filter
 *
 * CL-3.2: List categories and topics with search/filter
 */

import { loadRegistry } from '@my-cli/core';
import { ParsedArguments, CommandHandler } from './index.js';

/**
 * Formats categories as text
 */
function formatCategoriesText(categories: any[]): string {
  if (categories.length === 0) {
    return 'No categories found.';
  }

  const lines: string[] = [];
  lines.push(`Categories (${categories.length}):\n`);

  for (const category of categories) {
    lines.push(`  ${category.key.padEnd(20)} - ${category.description}`);
    lines.push(`    Topics: ${category.topics.length}`);
  }

  return lines.join('\n');
}

/**
 * Formats categories as JSON
 */
function formatCategoriesJson(categories: any[]): string {
  return JSON.stringify(
    {
      count: categories.length,
      categories: categories.map((c) => ({
        key: c.key,
        label: c.label,
        description: c.description,
        topicCount: c.topics.length,
        topics: c.topics,
      })),
    },
    null,
    2,
  );
}

/**
 * Filters topics by search term and category
 */
function filterTopics(
  topics: any[],
  searchTerm?: string,
  filterCategory?: string,
): any[] {
  return topics.filter((topic) => {
    // Filter by category if specified
    if (filterCategory && topic.category !== filterCategory) {
      return false;
    }

    // Filter by search term if specified
    if (searchTerm) {
      const lowerSearch = searchTerm.toLowerCase();
      const matchId = topic.id.toLowerCase().includes(lowerSearch);
      const matchName = topic.name.toLowerCase().includes(lowerSearch);
      const matchDesc = topic.description.toLowerCase().includes(lowerSearch);

      if (!matchId && !matchName && !matchDesc) {
        return false;
      }
    }

    return true;
  });
}

/**
 * Formats topics as text
 */
function formatTopicsText(topics: any[]): string {
  if (topics.length === 0) {
    return 'No topics found.';
  }

  const lines: string[] = [];
  lines.push(`Topics (${topics.length}):\n`);

  // Group by category
  const byCategory = new Map<string, any[]>();
  for (const topic of topics) {
    const cat = topic.category;
    if (!byCategory.has(cat)) {
      byCategory.set(cat, []);
    }
    byCategory.get(cat)!.push(topic);
  }

  // Output grouped
  for (const [category, categoryTopics] of byCategory) {
    lines.push(`  [${category}]`);
    for (const topic of categoryTopics) {
      lines.push(`    ${topic.id.padEnd(15)} - ${topic.description}`);
    }
  }

  return lines.join('\n');
}

/**
 * Formats topics as JSON
 */
function formatTopicsJson(topics: any[]): string {
  return JSON.stringify(
    {
      count: topics.length,
      topics: topics.map((t) => ({
        id: t.id,
        name: t.name,
        category: t.category,
        description: t.description,
        source: t.source,
      })),
    },
    null,
    2,
  );
}

/**
 * List categories handler
 */
export async function listCategories(argv: ParsedArguments): Promise<number> {
  try {
    // Load registry
    const registry = await loadRegistry(
      '/home/bwyoon/dotfiles/shell-common/functions/my_help.sh',
      'auto',
      {
        cacheEnabled: true,
      },
    );

    // Get all categories
    const categories = registry.getCategories();

    // Format output
    const format = argv.format || 'text';
    const output =
      format === 'json'
        ? formatCategoriesJson(categories)
        : formatCategoriesText(categories);

    // eslint-disable-next-line no-console
    console.log(output);

    return 0;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error listing categories:', error instanceof Error ? error.message : error);
    return 1;
  }
}

/**
 * List topics handler
 */
export async function listTopics(argv: ParsedArguments): Promise<number> {
  try {
    // Load registry
    const registry = await loadRegistry(
      '/home/bwyoon/dotfiles/shell-common/functions/my_help.sh',
      'auto',
      {
        cacheEnabled: true,
      },
    );

    // Get all topics
    let topics = registry.getTopics();

    // Apply filters
    const searchTerm = argv.search as string | undefined;
    const filterCategory = argv.filter as string | undefined;

    topics = filterTopics(topics, searchTerm, filterCategory);

    // Format output
    const format = argv.format || 'text';
    const output =
      format === 'json'
        ? formatTopicsJson(topics)
        : formatTopicsText(topics);

    // eslint-disable-next-line no-console
    console.log(output);

    return 0;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error listing topics:', error instanceof Error ? error.message : error);
    return 1;
  }
}

/**
 * Main list command handler
 * Routes to categories or topics subcommand
 */
export const listCommand: CommandHandler = async (argv: ParsedArguments): Promise<number> => {
  // Get subcommand from second positional argument
  const subcommand = argv._[1] as string | undefined;

  if (subcommand === 'categories') {
    return listCategories(argv);
  }

  if (subcommand === 'topics' || !subcommand) {
    // Default to topics if no subcommand
    return listTopics(argv);
  }

  // Unknown subcommand
  throw new Error(`Unknown list subcommand: ${subcommand}`);
};
