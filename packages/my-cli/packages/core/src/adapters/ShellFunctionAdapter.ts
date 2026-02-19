/**
 * ShellFunctionAdapter - Adapter for calling shell functions
 * Calls my_help_impl <topic> to get live help content for a specific topic
 *
 * CL-5.1: Shell integration via safe function invocation
 */

import { execFile } from 'child_process';
import { promisify } from 'util';
import { HelpTopic } from '../registry/types.js';
import { ValidationError, InternalError } from '../errors.js';
import { validateTopic } from '../sanitize.js';

const execFileAsync = promisify(execFile);

/**
 * Adapter for shell function calls
 * Calls my_help_impl to get live help content for topics
 */
export class ShellFunctionAdapter {
  /**
   * Creates a ShellFunctionAdapter
   *
   * @param helpFilePath - Path to my_help.sh file
   * @param shell - Shell type (bash or zsh)
   * @param timeout - Command timeout in milliseconds
   */
  constructor(
    private helpFilePath: string,
    private shell: 'bash' | 'zsh' = 'bash',
    private timeout: number = 5000,
  ) {}

  /**
   * Get a topic by calling my_help_impl
   *
   * @param topicId - Topic identifier (e.g., 'git', 'docker')
   * @returns HelpTopic with live content from shell function
   * @throws ValidationError if topic not found or invalid input
   * @throws InternalError if shell execution fails
   */
  async getTopic(topicId: string): Promise<HelpTopic> {
    // 1. Validate input (prevents injection attacks)
    validateTopic(topicId);

    // 2. Construct shell command safely
    const command = `source "${this.helpFilePath}" 2>/dev/null && my_help_impl "${topicId}" 2>/dev/null`;

    const args =
      this.shell === 'zsh'
        ? ['-f', '-c', command]
        : ['--noprofile', '--norc', '-c', command];

    // 3. Execute shell command
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
      // Handle timeout
      if (error instanceof Error) {
        if (
          error.message.includes('ETIMEDOUT') ||
          error.message.includes('timed out')
        ) {
          throw new InternalError(
            `Shell execution timeout after ${this.timeout}ms`,
          );
        }

        // Handle shell not found
        if (
          error.message.includes('ENOENT') ||
          error.message.includes('not found')
        ) {
          throw new InternalError(`Shell '${this.shell}' not found`);
        }
      }

      throw new InternalError(
        `Failed to get topic '${topicId}': ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /**
   * Parse shell output into HelpTopic
   *
   * @param topicId - Topic identifier
   * @param raw - Raw output from shell
   * @returns Parsed HelpTopic
   * @throws ValidationError if output indicates topic not found
   */
  private parseOutput(topicId: string, raw: string): HelpTopic {
    // Remove ANSI color codes
    const text = raw.replace(/\u001b\[[0-9;]*m/g, '').trim();

    // Check if topic was found
    if (!text || text.toLowerCase().includes('not found')) {
      throw new ValidationError(`Topic not found: ${topicId}`);
    }

    // Extract first line as description
    const lines = text.split('\n');
    const description = lines[0] || '';

    return {
      id: topicId,
      name: topicId.charAt(0).toUpperCase() + topicId.slice(1),
      category: 'shell',
      description,
      content: text,
      source: 'shell',
      updatedAt: new Date(),
    };
  }
}
