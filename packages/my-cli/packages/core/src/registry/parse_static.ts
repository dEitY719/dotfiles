/**
 * Static parser for help registry
 * Parses HELP_CATEGORIES, HELP_DESCRIPTIONS, and HELP_CATEGORY_MEMBERS
 * from shell script files to populate the HelpRegistry
 *
 * CL-2.2: Static Parser Implementation
 */

import { readFileSync } from 'fs';
import { HelpRegistry } from './Registry.js';
import { HelpTopic, HelpCategory } from './types.js';
import { ValidationError } from '../errors.js';

/**
 * Regex patterns for parsing shell script help definitions
 */
const CATEGORY_PATTERN = /HELP_CATEGORIES\[([a-z0-9_]+)\]="([^"]+)"/g;
const MEMBER_PATTERN = /HELP_CATEGORY_MEMBERS\[([a-z0-9_]+)\]="([^"]+)"/g;
const DESCRIPTION_PATTERN = /HELP_DESCRIPTIONS\[([a-z0-9_]+)\]="([^"]+)"/g;
const CONTENT_PATTERN = /HELP_CONTENT\[([a-z0-9_]+)\]="([^"]*(?:\\.[^"]*)*?)"/gs;

/**
 * Parses a shell script file and creates a populated HelpRegistry
 *
 * @param filePath - Path to the shell script file (e.g., my_help.sh)
 * @returns Promise<HelpRegistry> - Populated registry with categories and topics
 * @throws ValidationError if file cannot be read or parsing fails
 *
 * @example
 * ```typescript
 * const registry = await parseStaticRegistry('./my_help.sh');
 * const devCategory = registry.getCategory('development');
 * const gitTopic = registry.getTopic('git');
 * ```
 */
export async function parseStaticRegistry(filePath: string): Promise<HelpRegistry> {
  try {
    const content = readFileSync(filePath, 'utf-8');
    return parseStaticRegistryFromString(content);
  } catch (error) {
    if (error instanceof Error) {
      if (error.message.includes('ENOENT')) {
        throw new ValidationError(`Help file not found: ${filePath}`);
      }
      if (error.message.includes('EACCES')) {
        throw new ValidationError(`Cannot read help file: ${filePath} (permission denied)`);
      }
      throw new ValidationError(`Failed to read help file: ${error.message}`);
    }
    throw new ValidationError(`Failed to read help file: ${filePath}`);
  }
}

/**
 * Internal function to parse registry from string content
 * Used for both file-based and string-based testing
 *
 * @param content - Shell script content as string
 * @returns HelpRegistry - Populated registry
 * @internal
 */
export function parseStaticRegistryFromString(content: string): HelpRegistry {
  const registry = new HelpRegistry();

  // Parse categories and descriptions
  const categories: Record<string, string> = {};
  const descriptions: Record<string, string> = {};
  const members: Record<string, string> = {};
  const contents: Record<string, string> = {};

  // Extract HELP_CATEGORIES - reset lastIndex before each loop
  let match;
  CATEGORY_PATTERN.lastIndex = 0;
  while ((match = CATEGORY_PATTERN.exec(content)) !== null) {
    const [, key, value] = match;
    categories[key] = value;
  }

  // Extract HELP_DESCRIPTIONS - reset lastIndex before each loop
  DESCRIPTION_PATTERN.lastIndex = 0;
  while ((match = DESCRIPTION_PATTERN.exec(content)) !== null) {
    const [, key, value] = match;
    descriptions[key] = value;
  }

  // Extract HELP_CATEGORY_MEMBERS - reset lastIndex before each loop
  MEMBER_PATTERN.lastIndex = 0;
  while ((match = MEMBER_PATTERN.exec(content)) !== null) {
    const [, key, value] = match;
    members[key] = value;
  }

  // Extract HELP_CONTENT - multiline support
  CONTENT_PATTERN.lastIndex = 0;
  while ((match = CONTENT_PATTERN.exec(content)) !== null) {
    let [, key, value] = match;
    // Unescape content
    value = value
      .replace(/\\n/g, '\n')
      .replace(/\\t/g, '\t')
      .replace(/\\r/g, '\r')
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\');
    contents[key] = value;
  }

  // Validate that we found at least some data
  if (Object.keys(categories).length === 0) {
    throw new ValidationError('No HELP_CATEGORIES found in file');
  }

  // Add categories to registry
  for (const [key, description] of Object.entries(categories)) {
    try {
      const category: HelpCategory = {
        key,
        label: key.charAt(0).toUpperCase() + key.slice(1), // Capitalize key for label
        description,
        topics: [],
      };
      registry.addCategory(category);
    } catch (error) {
      // Skip categories with invalid keys (this shouldn't happen with our regex)
      continue;
    }
  }

  // Add topics from category members
  for (const [categoryKey, memberString] of Object.entries(members)) {
    // Extract actual topic list from parameter expansion syntax
    // Handles: "${HELP_CATEGORY_MEMBERS[key]:-topic1 topic2}" → "topic1 topic2"
    let actualTopicString = memberString;
    const paramExpansionMatch = memberString.match(/\$\{[^}]*:-([^}]*)\}/);
    if (paramExpansionMatch) {
      actualTopicString = paramExpansionMatch[1];
    }

    const topicIds = actualTopicString.trim().split(/\s+/).filter((id) => id.length > 0);

    for (const topicId of topicIds) {
      if (topicId.length === 0) continue;

      const topic: HelpTopic = {
        id: topicId,
        name: topicId.charAt(0).toUpperCase() + topicId.slice(1), // Capitalize for display name
        category: categoryKey,
        description: descriptions[topicId] || `Help for ${topicId}`,
        content: contents[topicId], // Load content if available
        source: 'static',
        updatedAt: new Date(),
      };

      try {
        registry.addTopic(topic);
      } catch (error) {
        // Skip topics that fail validation
        continue;
      }
    }
  }

  return registry;
}
