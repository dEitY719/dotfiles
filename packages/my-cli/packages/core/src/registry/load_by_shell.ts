/**
 * Shell-based registry loader
 * Dynamically loads help registry by executing bash/zsh with declare -p
 * Supports shell execution with environment isolation
 *
 * CL-2.3: Shell-based Loader Implementation
 */

import { execFile } from 'child_process';
import { promisify } from 'util';
import { HelpRegistry } from './Registry.js';
import { HelpTopic, HelpCategory } from './types.js';
import { ValidationError, InternalError } from '../errors.js';

const execFileAsync = promisify(execFile);

/**
 * Shell type for execution
 */
export type ShellType = 'bash' | 'zsh';

/**
 * Options for shell-based registry loading
 */
export interface LoadByShellOptions {
  /**
   * Timeout in milliseconds (default: 5000)
   */
  timeout?: number;

  /**
   * Enable debug mode for shell output
   */
  debug?: boolean;
}

/**
 * Loads help registry by executing shell commands
 * Uses bash/zsh with --noprofile --norc for environment isolation
 *
 * @param filePath - Path to shell script file (e.g., my_help.sh)
 * @param shell - Shell type: 'bash' or 'zsh'
 * @param options - Additional options (timeout, debug)
 * @returns Promise<HelpRegistry> - Populated registry from shell execution
 * @throws ValidationError if shell not found or file not found
 * @throws InternalError if execution timeout or parsing fails
 *
 * @example
 * ```typescript
 * const registry = await loadByShell('./my_help.sh', 'bash', { timeout: 5000 });
 * const topics = registry.getTopicsByCategory('development');
 * ```
 */
export async function loadByShell(
  filePath: string,
  shell: ShellType,
  options?: LoadByShellOptions,
): Promise<HelpRegistry> {
  const timeout = options?.timeout ?? 5000;
  const debug = options?.debug ?? false;

  // Validate shell type
  if (shell !== 'bash' && shell !== 'zsh') {
    throw new ValidationError(`Invalid shell type: ${shell}. Must be 'bash' or 'zsh'`);
  }

  // Construct shell command
  // Use --noprofile --norc to isolate from user configuration
  // Source the file, initialize default help data, then dump all HELP_* variables
  const command = `source "${filePath}" 2>/dev/null && _register_default_help_descriptions 2>/dev/null && declare -p HELP_CATEGORIES HELP_DESCRIPTIONS HELP_CATEGORY_MEMBERS HELP_CONTENT 2>/dev/null || echo ""`;

  if (debug) {
    // eslint-disable-next-line no-console
    console.debug(`[load_by_shell] Executing ${shell}: ${command}`);
  }

  try {
    // Different shells have different options for profile/rc isolation
    const args = shell === 'zsh'
      ? ['-f', '-c', command] // zsh: -f skips rc files
      : ['--noprofile', '--norc', '-c', command]; // bash: --noprofile --norc

    const { stdout, stderr } = await execFileAsync(shell, args, {
      timeout,
      maxBuffer: 1024 * 1024, // 1MB buffer
      env: {
        // Only pass minimal environment for isolation
        HOME: process.env.HOME || '/root',
        PATH: process.env.PATH || '/usr/bin:/bin',
      },
    });

    if (debug) {
      // eslint-disable-next-line no-console
      console.debug(`[load_by_shell] stdout length: ${stdout.length}, stderr: ${stderr}`);
    }

    return parseShellOutput(stdout);
  } catch (error) {
    if (error instanceof Error) {
      // Check for timeout
      if (error.message.includes('ETIMEDOUT') || error.message.includes('timed out')) {
        throw new InternalError(`Shell execution timeout after ${timeout}ms`);
      }

      // Check for shell not found
      if (error.message.includes('ENOENT') || error.message.includes('not found')) {
        throw new ValidationError(`Shell '${shell}' not found on system`);
      }

      // Check for file not found
      if (error.message.includes('No such file')) {
        throw new ValidationError(`Help file not found: ${filePath}`);
      }

      throw new InternalError(`Failed to execute shell command: ${error.message}`);
    }

    throw new InternalError('Failed to execute shell command');
  }
}

/**
 * Parses declare -p command output
 * Extracts HELP_CATEGORIES, HELP_DESCRIPTIONS, HELP_CATEGORY_MEMBERS
 *
 * @param output - Output from 'declare -p' command
 * @returns HelpRegistry - Populated with parsed data
 * @internal
 */
function parseShellOutput(output: string): HelpRegistry {
  const registry = new HelpRegistry();

  // Parse associative array format from declare -p output
  // Format: declare -A HELP_CATEGORIES=([key]="value" [key2]="value2" ...)
  const categories: Record<string, string> = {};
  const descriptions: Record<string, string> = {};
  const members: Record<string, string> = {};
  const contents: Record<string, string> = {};

  // Extract each declare statement
  const lines = output.split('\n');
  for (const line of lines) {
    if (line.includes('declare -A')) {
      // Extract variable name and content
      // Format: declare -A VARNAME=([...])
      const match = line.match(/declare -A (\w+)=\((.+)\)$/);
      if (match) {
        const varName = match[1];
        const content = match[2];

        // Parse array elements
        // Support both "value" and $'value\nwith\nescapes' formats
        const elements: Record<string, string> = {};

        // Match both [key]="value" and [key]=$'value' formats
        const elementRegex = /\[([^\]]+)\]=(?:\$'([^']*)'|"([^"]*)"|([^ )]*))/g;
        let elementMatch;

        while ((elementMatch = elementRegex.exec(content)) !== null) {
          const [, key, singleQuotedValue, doubleQuotedValue, unquotedValue] = elementMatch;
          // Use whichever value format was matched
          let value = singleQuotedValue || doubleQuotedValue || unquotedValue || '';

          // Decode bash $'...' escape sequences
          if (singleQuotedValue) {
            value = singleQuotedValue
              .replace(/\\n/g, '\n')
              .replace(/\\t/g, '\t')
              .replace(/\\r/g, '\r')
              .replace(/\\'/g, "'")
              .replace(/\\\\/g, '\\');
          }

          elements[key] = value;
        }

        // Store in appropriate map
        if (varName === 'HELP_CATEGORIES') {
          Object.assign(categories, elements);
        } else if (varName === 'HELP_DESCRIPTIONS') {
          Object.assign(descriptions, elements);
        } else if (varName === 'HELP_CATEGORY_MEMBERS') {
          Object.assign(members, elements);
        } else if (varName === 'HELP_CONTENT') {
          Object.assign(contents, elements);
        }
      }
    }
  }

  // Validate we found at least some data
  if (Object.keys(categories).length === 0) {
    throw new InternalError('No HELP_CATEGORIES found in shell output');
  }

  // Add categories to registry
  for (const [key, description] of Object.entries(categories)) {
    try {
      const category: HelpCategory = {
        key,
        label: key.charAt(0).toUpperCase() + key.slice(1),
        description,
        topics: [],
      };
      registry.addCategory(category);
    } catch (error) {
      // Skip invalid categories
      continue;
    }
  }

  // Add topics from category members
  for (const [categoryKey, memberString] of Object.entries(members)) {
    const topicIds = memberString.trim().split(/\s+/).filter((id) => id.length > 0);

    for (const topicId of topicIds) {
      if (topicId.length === 0) continue;

      const topic: HelpTopic = {
        id: topicId,
        name: topicId.charAt(0).toUpperCase() + topicId.slice(1),
        category: categoryKey,
        description: descriptions[topicId] || `Help for ${topicId}`,
        source: 'shell',
        updatedAt: new Date(),
        ...(contents[topicId] && { content: contents[topicId] }),
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
