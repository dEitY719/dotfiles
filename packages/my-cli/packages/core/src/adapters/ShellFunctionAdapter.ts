/**
 * Shell function adapter for live help content
 * Calls my_help_impl shell function to retrieve dynamic topic content
 *
 * CL-5.1: ShellFunctionAdapter for live content retrieval
 */

import { execFile } from 'child_process';
import { promisify } from 'util';
import { HelpTopic } from '../registry/types.js';
import { ValidationError, InternalError } from '../errors.js';

const execFileAsync = promisify(execFile);

/**
 * Validates topic ID to prevent shell injection
 * Only allows alphanumeric, underscore, and hyphen characters
 */
function validateTopicId(topicId: string): void {
  const SAFE_TOPIC_PATTERN = /^[A-Za-z0-9_-]+$/;
  if (!topicId || !SAFE_TOPIC_PATTERN.test(topicId)) {
    throw new ValidationError(`Invalid topic ID: "${topicId}". Must contain only alphanumeric characters, underscores, and hyphens.`);
  }
}

/**
 * Adapter for retrieving help content from shell functions
 * Calls my_help_impl to get live-rendered topic content
 *
 * @example
 * ```typescript
 * const adapter = new ShellFunctionAdapter('/path/to/my_help.sh');
 * const topic = await adapter.getTopic('git');
 * console.log(topic.content); // Rendered help text
 * ```
 */
export class ShellFunctionAdapter {
  /**
   * Creates a new ShellFunctionAdapter
   *
   * @param helpFilePath - Path to the help shell script (e.g., my_help.sh)
   * @param shell - Shell type: 'bash' or 'zsh' (default: 'bash')
   * @param timeout - Execution timeout in milliseconds (default: 5000)
   */
  constructor(
    private helpFilePath: string,
    private shell: 'bash' | 'zsh' = 'bash',
    private timeout: number = 5000,
  ) {}

  /**
   * Retrieves a topic's help content by calling my_help_impl
   *
   * @param topicId - Topic identifier (e.g., 'git', 'proxy')
   * @returns Promise<HelpTopic> - Topic with live-rendered content
   * @throws ValidationError - If topic ID is invalid
   * @throws InternalError - If shell execution fails or times out
   *
   * @example
   * ```typescript
   * try {
   *   const topic = await adapter.getTopic('docker');
   *   console.log(topic.content); // Full rendered content
   * } catch (error) {
   *   if (error instanceof ValidationError) {
   *     console.error('Invalid topic:', error.message);
   *   }
   * }
   * ```
   */
  async getTopic(topicId: string): Promise<HelpTopic> {
    // Validate input to prevent shell injection
    validateTopicId(topicId);

    // Build the command to source the help file and call my_help_impl
    // Note: Using single quotes in the -c argument to prevent expansion
    const command = `source "${this.helpFilePath}" 2>/dev/null && my_help_impl '${topicId}' 2>/dev/null`;

    // Shell-specific argument handling
    // Note: Pass command as a single argument after -c flag
    const args = this.shell === 'zsh'
      ? ['-f', '-c', command]
      : ['--noprofile', '--norc', '-c', command];

    try {
      const { stdout } = await execFileAsync(this.shell, args, {
        timeout: this.timeout,
        maxBuffer: 1024 * 1024, // 1MB buffer
        env: {
          HOME: process.env.HOME || '/root',
          PATH: process.env.PATH || '/usr/bin:/bin',
        },
      });

      return this.parseOutput(topicId, stdout);
    } catch (error) {
      // Some commands (git, docker) return non-zero exit codes but still provide valid output
      // Check if we have stdout content even if the command failed
      if (error instanceof Error && 'stdout' in error) {
        const stdout = (error as any).stdout;
        if (stdout && stdout.trim().length > 0) {
          return this.parseOutput(topicId, stdout);
        }
      }

      if (error instanceof Error) {
        // Handle timeout
        if (error.message.includes('ETIMEDOUT') || error.message.includes('timed out')) {
          throw new InternalError(`Shell execution timeout after ${this.timeout}ms for topic "${topicId}"`);
        }

        // Handle other shell errors
        if (error.message.includes('ENOENT')) {
          throw new InternalError(`Shell '${this.shell}' not found`);
        }
      }

      throw new InternalError(`Failed to execute shell for topic "${topicId}": ${error}`);
    }
  }

  /**
   * Parses shell output into a HelpTopic object
   * Removes ANSI color codes and creates topic metadata
   *
   * @internal
   */
  private parseOutput(topicId: string, raw: string): HelpTopic {
    // Remove ANSI color codes
    const content = raw
      .replace(/\u001b\[[0-9;]*m/g, '') // Remove ANSI escape sequences
      .trim();

    // Check if content is empty or indicates topic not found
    if (!content || content.toLowerCase().includes('not found') || content.toLowerCase().includes('no matching')) {
      throw new ValidationError(`Topic not found: "${topicId}"`);
    }

    return {
      id: topicId,
      name: topicId.charAt(0).toUpperCase() + topicId.slice(1),
      category: 'shell', // Topics from shell are categorized as 'shell'
      description: content.split('\n')[0] || `Help for ${topicId}`,
      content,
      source: 'shell',
      updatedAt: new Date(),
    };
  }
}
