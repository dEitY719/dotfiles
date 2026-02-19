/**
 * Input validation and sanitization module
 * Prevents injection attacks and validates topic names
 */

import { ValidationError, SecurityError } from './errors.js';

/**
 * Whitelist pattern for safe topic names
 * Only allows alphanumeric characters, hyphens, and underscores
 */
export const SAFE_TOPIC_PATTERN = /^[A-Za-z0-9_-]+$/;

/**
 * Maximum topic name length (50 characters)
 * Prevents overly long input that could cause performance issues
 */
export const MAX_TOPIC_LENGTH = 50;

/**
 * Minimum topic name length (1 character)
 */
export const MIN_TOPIC_LENGTH = 1;

/**
 * Validates a topic name for safety and compliance
 *
 * Checks:
 * 1. Length constraints (1-50 characters)
 * 2. Character whitelist (alphanumeric, dash, underscore)
 * 3. No shell injection patterns
 * 4. No path traversal attempts
 *
 * @param topic - Topic name to validate
 * @throws ValidationError if length is invalid
 * @throws SecurityError if injection patterns detected
 */
export function validateTopic(topic: string): void {
  if (topic.length < MIN_TOPIC_LENGTH) {
    throw new ValidationError('Topic name cannot be empty');
  }

  if (topic.length > MAX_TOPIC_LENGTH) {
    throw new ValidationError(
      `Topic name exceeds maximum length (${MAX_TOPIC_LENGTH} characters)`
    );
  }

  // Check for shell injection patterns
  const injectionPatterns = [
    /[;&|`$()[\]{}><*?]/,  // Shell metacharacters
    /\$\{/u,                   // Variable expansion ${...}
    /`/u,                       // Backtick command substitution
    /\$\(/u,                    // $(...) command substitution
  ];

  for (const pattern of injectionPatterns) {
    if (pattern.test(topic)) {
      throw new SecurityError(
        `Potentially dangerous characters detected in topic name. ` +
        `Only alphanumeric characters, hyphens (-), and underscores (_) are allowed`
      );
    }
  }

  // Check whitelist pattern
  if (!SAFE_TOPIC_PATTERN.test(topic)) {
    throw new ValidationError(
      `Invalid topic name format. ` +
      `Only alphanumeric characters, hyphens (-), and underscores (_) are allowed`
    );
  }

  // Check for path traversal attempts
  if (topic.includes('..') || topic.includes('/') || topic.includes('\\')) {
    throw new SecurityError(
      'Topic name cannot contain path separators or traversal patterns'
    );
  }
}

/**
 * Sanitizes a topic name by removing/replacing invalid characters
 * More lenient than validate - attempts to make the input safe
 *
 * @param topic - Topic name to sanitize
 * @returns Sanitized topic name
 */
export function sanitizeTopicName(topic: string): string {
  // Trim whitespace
  let sanitized = topic.trim();

  // Replace any character not in whitelist with underscore
  sanitized = sanitized.replace(/[^A-Za-z0-9_-]/g, '_');

  // Limit length
  if (sanitized.length > MAX_TOPIC_LENGTH) {
    sanitized = sanitized.substring(0, MAX_TOPIC_LENGTH);
  }

  // Ensure it's not empty
  if (sanitized.length === 0) {
    sanitized = 'topic';
  }

  return sanitized;
}

/**
 * Checks if a string looks like a category name (broader concept)
 * Categories are typically shorter, single-word identifiers
 *
 * @param name - Name to check
 * @returns true if name appears to be a valid category
 */
export function isSafeTopicName(name: string): boolean {
  if (name.length < MIN_TOPIC_LENGTH || name.length > MAX_TOPIC_LENGTH) {
    return false;
  }
  return SAFE_TOPIC_PATTERN.test(name);
}
