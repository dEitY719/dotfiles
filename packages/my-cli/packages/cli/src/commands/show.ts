/**
 * Show command implementation
 * Displays detailed information about a help topic
 *
 * CL-3.3: Display topic details with optional raw output and paging
 */

import { loadRegistry, ShellFunctionAdapter } from '@my-cli/core';
import { ParsedArguments, CommandHandler } from './index.js';

/**
 * Retrieves a topic by ID from the registry
 * First attempts to get live content via ShellFunctionAdapter,
 * then falls back to the static registry
 */
export async function getTopicDetail(topicId: string): Promise<any | null> {
  try {
    const helpFilePath = '/home/bwyoon/dotfiles/shell-common/functions/my_help.sh';

    // Try to get live content from shell function first
    try {
      const adapter = new ShellFunctionAdapter(helpFilePath);
      const liveTopic = await adapter.getTopic(topicId);
      return liveTopic;
    } catch (shellError) {
      // If shell adapter fails, fall back to static registry
      const registry = await loadRegistry(helpFilePath, 'static', {
        cacheEnabled: true,
      });

      const topics = registry.getTopics();
      return topics.find((t: any) => t.id === topicId) || null;
    }
  } catch (error) {
    return null;
  }
}

/**
 * Formats a topic as text with all details
 */
function formatTopicText(topic: any): string {
  const lines: string[] = [];

  // Header
  lines.push(`Topic: ${topic.name}`);
  lines.push(`ID: ${topic.id}`);
  lines.push(`Category: ${topic.category}`);
  lines.push(`Source: ${topic.source}`);
  lines.push('');

  // Description
  if (topic.description) {
    lines.push(`Description:`);
    lines.push(`  ${topic.description}`);
    lines.push('');
  }

  // Content
  if (topic.content) {
    lines.push(`Content:`);
    const contentLines = topic.content.split('\n');
    for (const line of contentLines) {
      lines.push(`  ${line}`);
    }
    lines.push('');
  }

  // Examples
  if (topic.examples && topic.examples.length > 0) {
    lines.push(`Examples:`);
    for (const example of topic.examples) {
      lines.push(`  - ${example}`);
    }
    lines.push('');
  }

  // Aliases
  if (topic.aliases && topic.aliases.length > 0) {
    lines.push(`Aliases:`);
    for (const alias of topic.aliases) {
      lines.push(`  - ${alias}`);
    }
    lines.push('');
  }

  // Tags
  if (topic.tags && topic.tags.length > 0) {
    lines.push(`Tags:`);
    lines.push(`  ${topic.tags.join(', ')}`);
  }

  return lines.join('\n');
}

/**
 * Formats a topic as JSON with all metadata
 */
function formatTopicJson(topic: any): string {
  return JSON.stringify(
    {
      id: topic.id,
      name: topic.name,
      category: topic.category,
      description: topic.description,
      content: topic.content || null,
      examples: topic.examples || [],
      aliases: topic.aliases || [],
      source: topic.source,
      tags: topic.tags || [],
      updatedAt: topic.updatedAt || null,
    },
    null,
    2,
  );
}

/**
 * Formats a topic as raw content (just the content field)
 */
function formatTopicRaw(topic: any): string {
  return topic.content || `# ${topic.name}\n\n${topic.description || ''}`;
}

/**
 * Show topic command handler
 * Displays details for a specific topic
 */
export const showCommand: CommandHandler = async (
  argv: ParsedArguments,
): Promise<number> => {
  try {
    // Get topic ID from second positional argument
    const topicId = argv._[1] as string | undefined;

    if (!topicId) {
      // eslint-disable-next-line no-console
      console.error('Error: Topic ID is required. Usage: my-cli show <topic-id>');
      return 1;
    }

    // Retrieve topic from registry
    const topic = await getTopicDetail(topicId);

    if (!topic) {
      // eslint-disable-next-line no-console
      console.error(`Error: Topic '${topicId}' not found.`);
      return 1;
    }

    // Format output
    let output: string;
    if (argv.raw) {
      output = formatTopicRaw(topic);
    } else {
      const format = argv.format || 'text';
      output =
        format === 'json'
          ? formatTopicJson(topic)
          : formatTopicText(topic);
    }

    // eslint-disable-next-line no-console
    console.log(output);

    return 0;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(
      'Error showing topic:',
      error instanceof Error ? error.message : error,
    );
    return 1;
  }
};
