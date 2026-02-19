/**
 * Unit tests for input validation and sanitization
 * CL-1.3: Input validation module (sanitize.ts)
 */

import { describe, it, expect } from 'vitest';
import {
  validateTopic,
  sanitizeTopicName,
  isSafeTopicName,
  SAFE_TOPIC_PATTERN,
  MAX_TOPIC_LENGTH,
  MIN_TOPIC_LENGTH,
} from '../src/sanitize';
import { ValidationError, SecurityError } from '../src/errors';

describe('validateTopic', () => {
  describe('Valid topic names', () => {
    it('should accept simple lowercase topic', () => {
      expect(() => validateTopic('git')).not.toThrow();
    });

    it('should accept simple uppercase topic', () => {
      expect(() => validateTopic('GIT')).not.toThrow();
    });

    it('should accept topic with numbers', () => {
      expect(() => validateTopic('python3')).not.toThrow();
    });

    it('should accept topic with hyphens', () => {
      expect(() => validateTopic('git-flow')).not.toThrow();
    });

    it('should accept topic with underscores', () => {
      expect(() => validateTopic('py_3_12')).not.toThrow();
    });

    it('should accept mixed format topics', () => {
      expect(() => validateTopic('Git_Flow-2')).not.toThrow();
    });

    it('should accept single character topic', () => {
      expect(() => validateTopic('a')).not.toThrow();
    });

    it('should accept maximum length topic (50 chars)', () => {
      const maxLengthTopic = 'a'.repeat(50);
      expect(() => validateTopic(maxLengthTopic)).not.toThrow();
    });
  });

  describe('Invalid lengths', () => {
    it('should reject empty string', () => {
      expect(() => validateTopic('')).toThrow(ValidationError);
      expect(() => validateTopic('')).toThrow('cannot be empty');
    });

    it('should reject whitespace-only string', () => {
      expect(() => validateTopic('   ')).toThrow(ValidationError);
    });

    it('should reject topic exceeding max length', () => {
      const tooLongTopic = 'a'.repeat(51);
      expect(() => validateTopic(tooLongTopic)).toThrow(ValidationError);
      expect(() => validateTopic(tooLongTopic)).toThrow(
        'exceeds maximum length'
      );
    });
  });

  describe('Shell injection attempts', () => {
    it('should reject semicolon (command separator)', () => {
      expect(() => validateTopic('git; rm -rf /')).toThrow(SecurityError);
    });

    it('should reject pipe operator', () => {
      expect(() => validateTopic('git | cat')).toThrow(SecurityError);
    });

    it('should reject ampersand (background)', () => {
      expect(() => validateTopic('git&')).toThrow(SecurityError);
    });

    it('should reject backtick command substitution', () => {
      expect(() => validateTopic('git`whoami`')).toThrow(SecurityError);
    });

    it('should reject $(...) command substitution', () => {
      expect(() => validateTopic('git$(whoami)')).toThrow(SecurityError);
    });

    it('should reject ${ variable expansion', () => {
      expect(() => validateTopic('topic${VAR}')).toThrow(SecurityError);
    });

    it('should reject parentheses', () => {
      expect(() => validateTopic('git()')).toThrow(SecurityError);
    });

    it('should reject brackets', () => {
      expect(() => validateTopic('git[]')).toThrow(SecurityError);
    });

    it('should reject angle brackets', () => {
      expect(() => validateTopic('git<output')).toThrow(SecurityError);
    });

    it('should reject asterisk (glob)', () => {
      expect(() => validateTopic('git*')).toThrow(SecurityError);
    });

    it('should reject question mark', () => {
      expect(() => validateTopic('git?')).toThrow(SecurityError);
    });

    it('should reject curly braces', () => {
      expect(() => validateTopic('git{a,b}')).toThrow(SecurityError);
    });
  });

  describe('Path traversal attempts', () => {
    it('should reject double dots (..) pattern', () => {
      // Dots fail whitelist pattern first, so ValidationError is thrown
      expect(() => validateTopic('../../etc')).toThrow(ValidationError);
      expect(() => validateTopic('..passwd')).toThrow(ValidationError);
    });

    it('should reject forward slash', () => {
      // Forward slash fails whitelist pattern first
      expect(() => validateTopic('git/help')).toThrow(ValidationError);
    });

    it('should reject backslash', () => {
      // Backslash fails whitelist pattern first
      expect(() => validateTopic('git\\help')).toThrow(ValidationError);
    });
  });

  describe('Invalid characters', () => {
    it('should reject spaces', () => {
      expect(() => validateTopic('git help')).toThrow(ValidationError);
    });

    it('should reject special characters', () => {
      expect(() => validateTopic('git@help')).toThrow(ValidationError);
      expect(() => validateTopic('git#help')).toThrow(ValidationError);
      // $ triggers security check for variable expansion
      expect(() => validateTopic('git$help')).toThrow(SecurityError);
      expect(() => validateTopic('git%help')).toThrow(ValidationError);
    });

    it('should reject dots', () => {
      expect(() => validateTopic('git.help')).toThrow(ValidationError);
    });

    it('should reject accented characters', () => {
      expect(() => validateTopic('café')).toThrow(ValidationError);
    });

    it('should reject unicode characters', () => {
      expect(() => validateTopic('git😀')).toThrow(ValidationError);
    });
  });
});

describe('sanitizeTopicName', () => {
  it('should preserve valid topics unchanged', () => {
    expect(sanitizeTopicName('git')).toBe('git');
    expect(sanitizeTopicName('python3')).toBe('python3');
    expect(sanitizeTopicName('git-flow')).toBe('git-flow');
  });

  it('should trim whitespace', () => {
    expect(sanitizeTopicName('  git  ')).toBe('git');
    expect(sanitizeTopicName('\tpython\n')).toBe('python');
  });

  it('should replace invalid characters with underscores', () => {
    expect(sanitizeTopicName('git help')).toBe('git_help');
    expect(sanitizeTopicName('git@flow')).toBe('git_flow');
    expect(sanitizeTopicName('git#tag')).toBe('git_tag');
  });

  it('should handle mixed invalid characters', () => {
    expect(sanitizeTopicName('git@#$%flow')).toBe('git____flow');
  });

  it('should truncate names exceeding max length', () => {
    const longName = 'a'.repeat(60);
    const result = sanitizeTopicName(longName);
    expect(result.length).toBe(MAX_TOPIC_LENGTH);
  });

  it('should not return empty string', () => {
    const result = sanitizeTopicName('!@#$%');
    expect(result.length).toBeGreaterThan(0);
    // Each special char becomes underscore: _____ (5 underscores)
    expect(result.length).toBe(5);
    // But still has content
    expect(result).toMatch(/^_+$/);
  });

  it('should handle real-world injection attempt', () => {
    const result = sanitizeTopicName('git$(whoami)');
    // git + $ + ( + whoami + ) = git_(__whoami_)
    expect(result).toBe('git__whoami_');
    // Verify it can pass validation after sanitization
    expect(() => validateTopic(result)).not.toThrow();
  });
});

describe('isSafeTopicName', () => {
  it('should return true for valid topics', () => {
    expect(isSafeTopicName('git')).toBe(true);
    expect(isSafeTopicName('python3')).toBe(true);
    expect(isSafeTopicName('git-flow')).toBe(true);
    expect(isSafeTopicName('py_3_12')).toBe(true);
  });

  it('should return false for empty string', () => {
    expect(isSafeTopicName('')).toBe(false);
  });

  it('should return false for topics exceeding max length', () => {
    expect(isSafeTopicName('a'.repeat(51))).toBe(false);
  });

  it('should return false for topics with invalid characters', () => {
    expect(isSafeTopicName('git help')).toBe(false);
    expect(isSafeTopicName('git@flow')).toBe(false);
    expect(isSafeTopicName('git;rm')).toBe(false);
  });

  it('should return false for injection attempts', () => {
    expect(isSafeTopicName('git$(whoami)')).toBe(false);
    expect(isSafeTopicName('git`id`')).toBe(false);
  });
});

describe('SAFE_TOPIC_PATTERN', () => {
  it('should match valid topic names', () => {
    expect(SAFE_TOPIC_PATTERN.test('git')).toBe(true);
    expect(SAFE_TOPIC_PATTERN.test('python3')).toBe(true);
    expect(SAFE_TOPIC_PATTERN.test('git-flow')).toBe(true);
    expect(SAFE_TOPIC_PATTERN.test('_private')).toBe(true);
  });

  it('should not match invalid names', () => {
    expect(SAFE_TOPIC_PATTERN.test('git ')).toBe(false);
    expect(SAFE_TOPIC_PATTERN.test('git@')).toBe(false);
    expect(SAFE_TOPIC_PATTERN.test('git;')).toBe(false);
  });
});

describe('Constants', () => {
  it('should have valid length constraints', () => {
    expect(MIN_TOPIC_LENGTH).toBe(1);
    expect(MAX_TOPIC_LENGTH).toBe(50);
    expect(MAX_TOPIC_LENGTH).toBeGreaterThan(MIN_TOPIC_LENGTH);
  });
});
